--[[
    Dingus-Slayer · spoofers.lua v3
    Minimal, guarded client-side state reinforcement.

    Cut from v2 (all dead, broken, or net-negative):
      spoofHP        — cosmetic; server owns HP in FilteredEnabled games
      goUnderground  — dead code; if called, self-traps (checkUG never scheduled)
      surfaceUp      — dead code; left BodyPosition on character
      checkUG        — dead code; timer drift against wall clock
      hpC/bkC/spdC/kbC/jmpC — never read by any consumer

    Kept and fixed:
      spoofSpeed     — calibrated 1.25x base, dedup writes, concede-to-server
      spoofJump      — same
      spoofBlock     — cached path, in-combat only, low threshold
      antiKnock      — preserves Y, 150 threshold, opt-in (default off)
      antiStun       — only intervenes on FallingDown, never Ragdoll/Physics

    Added:
      base-value snapshot at boot, reset on respawn
      write-fight detection; auto-concede after 5 consecutive corrections
      toggle-off unwinding (only restores if our last write is still present)
      guarded pcall: first-error print, recovery print
      deprecated stubs for removed public methods (one-time warning)
      one-time boot warning when gsp is enabled
      Sp.stats() for live runtime inspection

    Architectural note: in a FilteredEnabled game the server owns movement,
    HP, ragdoll, and knockback. Client writes are inputs to client-side
    physics, not authoritative. spoofSpeed and spoofJump have real effect
    (they change movement that the server then validates). Everything else
    is a local-visibility tweak. This file does not pretend otherwise.
]]--

local Sp = {}

function Sp.init(Ctx)
    local U   = Ctx.Util
    local Cfg = Ctx.Cfg
    local St  = Ctx.St

    --================================================================
    -- CONFIG DEFAULTS
    --================================================================
    Cfg.SpoofSpeedMult = Cfg.SpoofSpeedMult or 1.25
    Cfg.SpoofJumpMult  = Cfg.SpoofJumpMult  or 1.15
    Cfg.SpoofWriteHz   = Cfg.SpoofWriteHz   or 5
    Cfg.SpoofAntiKnock = Cfg.SpoofAntiKnock or false
    Cfg.SpoofVerbose   = Cfg.SpoofVerbose   or false

    local SPOOF_INTERVAL    = 1 / math.max(1, Cfg.SpoofWriteHz)
    local WRITE_FIGHT_LIMIT = 5
    local WRITE_FIGHT_WINDOW = 0.4

    --================================================================
    -- STATE
    --================================================================
    -- Preserved for backward compat with any consumer reading St.Spf.
    -- Values stay at 0 in v3; live stats come from Sp.stats().
    St.Spf = St.Spf or { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }

    local baseWalkSpeed   = nil
    local baseJumpPower   = nil
    local baseJumpHeight  = nil

    local lastWrittenWalk = nil
    local lastWrittenJump = nil

    local blockPath       = nil
    local prevGsp         = St.gsp

    local writeCount      = 0
    local conceded        = false
    local writeFightSpeed = 0
    local writeFightJump  = 0
    local lastSpeedWriteT = 0
    local lastJumpWriteT  = 0

    local Errs = {}

    --================================================================
    -- GUARDED PCALL
    -- First error prints once. If the function then succeeds, a
    -- recovery line prints and the counter resets. Subsequent errors
    -- after a recovery also print. This means: a bug you can see,
    -- not a bug you can't.
    --================================================================
    local function guard(fn, key)
        local ok, err = pcall(fn)
        if not ok then
            Errs[key] = (Errs[key] or 0) + 1
            if Errs[key] == 1 then
                print(string.format("[Dingus][Spoof] %s raised: %s", key, tostring(err)))
            end
        else
            if Errs[key] and Errs[key] > 0 then
                print(string.format("[Dingus][Spoof] %s recovered after %d failures",
                    key, Errs[key]))
                Errs[key] = 0
            end
        end
        return ok
    end

    --================================================================
    -- BASE VALUE RESOLUTION
    -- Snapshot at boot. Clamp to sane range so a garbage value at
    -- boot doesn't become our permanent base.
    --================================================================
    local function resolveBaseWalkSpeed()
        local h = U.hum()
        if not h then return 16 end
        local ws = h.WalkSpeed
        if type(ws) ~= "number" then return 16 end
        if ws < 16 then return 16 end
        if ws > 24 then return 24 end
        return ws
    end

    local function resolveBaseJump(h)
        if not h then return 50, 7.35 end
        if h.UseJumpPower then
            local jp = h.JumpPower
            if type(jp) ~= "number" then return 50, 7.35 end
            if jp < 50 then jp = 50 end
            if jp > 60 then jp = 60 end
            return jp, 7.35
        end
        local jh = h.JumpHeight
        if type(jh) ~= "number" then return 50, 7.35 end
        if jh < 7.35 then jh = 7.35 end
        if jh > 9 then jh = 9 end
        return 50, jh
    end

    local function snapshotBases()
        local h = U.hum()
        if not h then return end
        baseWalkSpeed = resolveBaseWalkSpeed()
        baseJumpPower, baseJumpHeight = resolveBaseJump(h)
    end

    --================================================================
    -- RESTORE
    -- Only restores if the current value equals what we last wrote.
    -- Never steps on a value another script has changed since.
    --================================================================
    local function restoreDefaults()
        local h = U.hum()
        if not h then return end
        if lastWrittenWalk and h.WalkSpeed == lastWrittenWalk then
            pcall(function() h.WalkSpeed = baseWalkSpeed or 16 end)
        end
        if h.UseJumpPower and lastWrittenJump and h.JumpPower == lastWrittenJump then
            pcall(function() h.JumpPower = baseJumpPower or 50 end)
        end
        lastWrittenWalk = nil
        lastWrittenJump = nil
    end

    --================================================================
    -- SKIP CONDITIONS
    --================================================================
    local function canSpoof(h)
        if not h then return false end
        if h.Health <= 0 then return false end
        if h.Sit then return false end
        if h.PlatformStand then return false end
        return true
    end

    --================================================================
    -- SPOOF SPEED
    --================================================================
    local function spoofSpeed()
        local h = U.hum()
        if not canSpoof(h) then return end
        if not baseWalkSpeed then snapshotBases() end
        if not baseWalkSpeed then return end

        local target  = baseWalkSpeed * Cfg.SpoofSpeedMult
        local current = h.WalkSpeed

        -- Respect server debuffs. Don't fight downward corrections.
        if current < baseWalkSpeed * 0.9 then
            writeFightSpeed = 0
            return
        end

        if current < target - 0.5 then
            local now = U.clock()
            -- If we wrote recently and the value is already back down,
            -- the server (or a game script) is correcting us. Count it.
            if lastSpeedWriteT > 0
               and now - lastSpeedWriteT < WRITE_FIGHT_WINDOW then
                writeFightSpeed = writeFightSpeed + 1
                if writeFightSpeed >= WRITE_FIGHT_LIMIT then
                    conceded = true
                    St.gsp = false
                    print("[Dingus][Spoof] speed: conceding to server authority")
                    return
                end
            end
            h.WalkSpeed = target
            lastWrittenWalk = target
            lastSpeedWriteT = now
            writeCount = writeCount + 1
            if Cfg.SpoofVerbose then
                print(string.format("[Dingus][Spoof] speed -> %.1f", target))
            end
        else
            writeFightSpeed = 0
        end
    end

    --================================================================
    -- SPOOF JUMP
    --================================================================
    local function spoofJump()
        local h = U.hum()
        if not canSpoof(h) then return end
        if not baseJumpPower then snapshotBases() end
        if not baseJumpPower then return end

        if h.UseJumpPower then
            local target  = baseJumpPower * Cfg.SpoofJumpMult
            local current = h.JumpPower

            if current < baseJumpPower * 0.9 then
                writeFightJump = 0
                return
            end

            if current < target - 0.5 then
                local now = U.clock()
                if lastJumpWriteT > 0
                   and now - lastJumpWriteT < WRITE_FIGHT_WINDOW then
                    writeFightJump = writeFightJump + 1
                    if writeFightJump >= WRITE_FIGHT_LIMIT then
                        print("[Dingus][Spoof] jump: conceding to server authority")
                        return
                    end
                end
                h.JumpPower = target
                lastWrittenJump = target
                lastJumpWriteT = now
                writeCount = writeCount + 1
                if Cfg.SpoofVerbose then
                    print(string.format("[Dingus][Spoof] jump -> %.1f", target))
                end
            else
                writeFightJump = 0
            end
        else
            local target  = (baseJumpHeight or 7.35) * Cfg.SpoofJumpMult
            local current = h.JumpHeight
            if current < target - 0.3 then
                h.JumpHeight = target
                writeCount = writeCount + 1
            end
        end
    end

    --================================================================
    -- SPOOF BLOCK (PS2-specific, cached path)
    --================================================================
    local function resolveBlockPath()
        local hf = workspace:FindFirstChild("Humanoids")
        if not hf then return nil end
        local me = hf:FindFirstChild(U.Lp.Name)
        if not me then return nil end
        local shcs = me:FindFirstChild("SHCS")
        if not shcs then return nil end
        local bv = shcs:FindFirstChild("Blocking")
        if bv and bv:IsA("NumberValue") then return bv end
        return nil
    end

    local function spoofBlock()
        -- Combat-only. Reduces write rate and detection surface.
        if not St.cbt then return end
        if (St.zn or 0) == 0 then return end

        if not blockPath or not blockPath.Parent then
            blockPath = resolveBlockPath()
            if not blockPath then return end
        end

        local v = blockPath.Value
        if type(v) == "number" and v < 15 then
            blockPath.Value = 100
            writeCount = writeCount + 1
        end
    end

    --================================================================
    -- ANTI-KNOCK (opt-in, default off)
    -- Preserves Y velocity. Higher threshold than v2. Only clamps
    -- horizontal. Skips while airborne under our own power.
    --
    -- Note: server computes knockback independently. Client-side
    -- clamping produces divergence and server correction (rubber-band).
    -- Leave off unless a specific game makes it worth the cost.
    --================================================================
    local function antiKnock()
        if not Cfg.SpoofAntiKnock then return end
        local r = U.hrp()
        local h = U.hum()
        if not r or not h then return end
        if h.Health <= 0 then return end

        local ok, st = pcall(function() return h:GetState() end)
        if ok and st then
            if st == Enum.HumanoidStateType.Jumping
               or st == Enum.HumanoidStateType.Freefall
               or st == Enum.HumanoidStateType.Swimming
               or st == Enum.HumanoidStateType.Flying then
                return
            end
        end

        local v = r.AssemblyLinearVelocity
        if not v then return end
        if v.Magnitude < 150 then return end

        local hx, hz = v.X, v.Z
        local hm = math.sqrt(hx * hx + hz * hz)
        if hm > 120 then
            local scale = 120 / hm
            r.AssemblyLinearVelocity = Vector3.new(hx * scale, v.Y, hz * scale)
            writeCount = writeCount + 1
        end
    end

    --================================================================
    -- ANTI-STUN
    -- Only FallingDown is safe to interrupt. Ragdoll and Physics have
    -- active ragdoll constraints; forcing them out launches or locks
    -- the character. Skip both. Skip if PlatformStand (under script
    -- control).
    --================================================================
    local function antiStun()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        if h.PlatformStand then return end

        local ok, st = pcall(function() return h:GetState() end)
        if not ok or not st then return end

        if st == Enum.HumanoidStateType.FallingDown then
            pcall(function() h:ChangeState(Enum.HumanoidStateType.Running) end)
        end
    end

    --================================================================
    -- RESPAWN
    --================================================================
    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(1.5)
            baseWalkSpeed   = nil
            baseJumpPower   = nil
            baseJumpHeight  = nil
            lastWrittenWalk = nil
            lastWrittenJump = nil
            blockPath       = nil
            writeFightSpeed = 0
            writeFightJump  = 0
            lastSpeedWriteT = 0
            lastJumpWriteT  = 0
        end)
    end

    --================================================================
    -- TICK
    --================================================================
    function Sp.tick()
        -- Toggle-off unwind
        if not St.gsp then
            if prevGsp then
                prevGsp = false
                pcall(restoreDefaults)
            end
            return
        end
        if not prevGsp then
            prevGsp = true
        end

        local now = U.clock()
        if now - (St.lSpf or 0) < SPOOF_INTERVAL then return end
        St.lSpf = now

        guard(spoofSpeed, "speed")
        guard(spoofJump,  "jump")
        guard(spoofBlock, "block")
        guard(antiKnock,  "knock")
        guard(antiStun,   "stun")
    end

    --================================================================
    -- DEPRECATED PUBLIC METHODS
    -- Kept as no-ops so any hidden caller doesn't nil-crash.
    --================================================================
    local ugWarned = false
    function Sp.goUnderground()
        if ugWarned then return end
        ugWarned = true
        print("[Dingus][Spoof] goUnderground removed in v3 — no-op")
    end
    function Sp.surfaceUp() end
    function Sp.checkUG() end

    --================================================================
    -- STATS (for GUI display or debugging)
    --================================================================
    function Sp.stats()
        return {
            enabled  = St.gsp,
            writes   = writeCount,
            conceded = conceded,
            baseWalk = baseWalkSpeed,
            baseJump = baseJumpPower,
        }
    end

    --================================================================
    -- BOOT WARNING
    --================================================================
    if St.gsp then
        print("[Dingus][Spoof] NOTE: guard spoof is enabled. In a " ..
              "FilteredEnabled game the server owns movement, HP, and " ..
              "ragdoll state. Client writes here have limited effect and " ..
              "may register as tampering. Set St.gsp = false if you see " ..
              "rubber-banding.")
    end

    print("[Dingus][spoofers] v3 initialized")
end

return Sp
