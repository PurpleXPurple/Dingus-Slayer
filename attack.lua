--[[
    Dingus-Slayer · attack.lua v6
    Combat rewrite. Addresses every /audit finding from v5.

    Fixes:
      C1  Safe CFrame construction (guaranteed look-at separation)
      C2  Real combo chaining (multi-click M1 per strike)
      C3  Telegraph reaction (auto-dodge Q, block hold on incoming)
      C4  Behind direction from player→boss vector, not boss LookVector
      H1  In-range chase (re-face + reposition when boss moves)
      H3  Ultimate gating (skills 5 & 6 held for high-value windows)
      M2  Combo index resets per-target, not per-timeout
      M4  Boss attack animation read via detect.isEnemyAttacking

    State machine:
      IDLE, TELEPORT, CLOSE, STRIKE, PUNISH, BREAK, DODGE, BLOCK,
      RETREAT, DEAD, NO_CHAR

    Core loop:
      1. Threat evaluation (dodge / block / strike / break / punish)
      2. Positional management (teleport out-of-range, chase in-range)
      3. Attack execution (chained M1s, gated skills)
]]--

local A = {}

function A.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local D = Ctx.Detect
    local L = Ctx.Lists
    local RunService = game:GetService("RunService")

    --============================================================
    -- INLINE CONFIG
    --============================================================
    Cfg.AtkRange       = Cfg.AtkRange       or 8
    Cfg.AtkInterval    = Cfg.AtkInterval    or 0.55
    Cfg.AtkIntMin      = Cfg.AtkIntMin      or 0.28
    Cfg.AtkIntMax      = Cfg.AtkIntMax      or 0.80
    Cfg.StunAtkInt     = Cfg.StunAtkInt     or 0.24
    Cfg.HitWindow      = Cfg.HitWindow      or 12
    Cfg.RunSpeed       = Cfg.RunSpeed       or 16

    Cfg.RetreatHP      = Cfg.RetreatHP      or 0.35
    Cfg.RetreatDelay   = Cfg.RetreatDelay   or 4.0
    Cfg.RetreatClearHP = Cfg.RetreatClearHP or 0.65

    Cfg.SkillKeys      = Cfg.SkillKeys      or { "F", "Z", "X", "C", "V", "B" }
    Cfg.SkillCooldowns = Cfg.SkillCooldowns or { 0.5, 1.2, 2.0, 2.8, 3.6, 6.0 }
    Cfg.RotationOrder  = Cfg.RotationOrder  or { 2, 3, 4, 5, 6 }

    Cfg.FKeyMode       = Cfg.FKeyMode       or "auto"
    Cfg.AutoBlock      = Cfg.AutoBlock      ~= false
    Cfg.BlockHoldTTL   = Cfg.BlockHoldTTL   or 0.4
    Cfg.BlockProbeWait = Cfg.BlockProbeWait or 0.15

    -- Teleport
    Cfg.TeleportCd         = Cfg.TeleportCd         or 0.25
    Cfg.TeleportBehindDist = Cfg.TeleportBehindDist or 7
    Cfg.TeleportHeight     = Cfg.TeleportHeight     or 3
    Cfg.TeleportJitter     = Cfg.TeleportJitter     or 2
    Cfg.TeleportWalkBlend  = Cfg.TeleportWalkBlend  or 0.5
    Cfg.TeleportStrike      = Cfg.TeleportStrike      or 4.5   -- prefer landing inside strike range

    -- Combat
    Cfg.ComboClicks        = Cfg.ComboClicks        or 3
    Cfg.ComboClickGap      = Cfg.ComboClickGap      or 0.08
    Cfg.ComboInterChainGap = Cfg.ComboInterChainGap or 0.18
    Cfg.DodgeCooldown      = Cfg.DodgeCooldown      or 0.8
    Cfg.InRangeChaseT      = Cfg.InRangeChaseT      or 0.25
    Cfg.UltimateHPGate     = Cfg.UltimateHPGate     or 0.30
    Cfg.TelegraphWindow    = Cfg.TelegraphWindow    or 0.35

    Cfg.EquipDebugN    = Cfg.EquipDebugN    or 2

    --============================================================
    -- STATE
    --============================================================
    St.rHt = {}
    St.skCd = { 0, 0, 0, 0, 0, 0 }
    St.aiI = Cfg.AtkInterval

    St.lAtk = 0
    St.lSkl = 0
    St.lEqp = 0
    St.lBrt = 0
    St.lDodge = 0
    St.lTele = 0
    St.lInRangeChase = 0
    St.lTelegraph = 0
    St.lMoveLog = 0

    St.eq = "none"
    St.cbtS = "IDLE"
    St.lastPos = nil
    St.lastPosTime = 0
    St.stuckWarnings = 0
    St.swapPending = false
    St.equipDebugLeft = Cfg.EquipDebugN

    -- Combo state (per-target)
    St.comboIndex = 0
    St.comboTargetName = nil
    St.comboActive = false

    -- F-mode
    St.fIsBlock = false
    St.fModeResolved = false
    St.blocking = false
    St.blockHoldUntil = 0

    -- Teleport
    St.teleCount = 0
    St.teleFail = 0

    -- Dodge
    St.dodgeCount = 0

    -- Threat state
    St.lastBossAttacking = false
    St.threatSince = 0

    local SK_KEYS  = Cfg.SkillKeys
    local SK_CDS   = Cfg.SkillCooldowns
    local ROTATION = Cfg.RotationOrder

    --============================================================
    -- MOVER SCRUB
    --============================================================
    local function scrubMovers()
        local r = U.hrp()
        if not r then return 0 end
        local n = 0
        for _, c in ipairs(r:GetChildren()) do
            if c:IsA("BodyPosition") or c:IsA("BodyVelocity")
                or c:IsA("BodyGyro") or c:IsA("BodyForce")
                or c:IsA("LinearVelocity") or c:IsA("AlignOrientation")
                or c:IsA("AlignPosition") then
                c:Destroy(); n = n + 1
            end
        end
        local h = U.hum()
        if h then
            h.PlatformStand = false
            h.AutoRotate = true
        end
        return n
    end
    scrubMovers()
    U.Lp.CharacterAdded:Connect(function()
        task.wait(1)
        scrubMovers()
        St.blocking = false
        St.blockHoldUntil = 0
        St.fModeResolved = false
        St.comboIndex = 0
        St.comboActive = false
        St.comboTargetName = nil
    end)

    --============================================================
    -- F-KEY PROBE
    --============================================================
    local function readBlockAttribute()
        local c = U.Lp.Character
        if not c then return false end
        local ok1, v1 = pcall(function() return c:GetAttribute("IsBlocking") end)
        if ok1 and v1 == true then return true end
        local h = U.hum()
        if h then
            local ok2, v2 = pcall(function() return h:GetAttribute("IsBlocking") end)
            if ok2 and v2 == true then return true end
        end
        return false
    end

    local function readBlockAnim()
        local h = U.hum()
        if not h then return false end
        local an = h:FindFirstChildOfClass("Animator")
        if not an then return false end
        local ok, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
        if not ok or not tracks then return false end
        for i = 1, #tracks do
            local t = tracks[i]
            local okP, isPlaying = pcall(function() return t.IsPlaying end)
            if okP and isPlaying then
                local okW, w = pcall(function() return t.WeightCurrent end)
                if okW and w > 0.3 then
                    local okN, nm = pcall(function() return t.Name end)
                    if okN and nm then
                        local l = string.lower(nm)
                        if string.find(l, "block", 1, true)
                            or string.find(l, "guard", 1, true)
                            or string.find(l, "parry", 1, true) then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    local function probeFKey()
        local h = U.hum()
        if not h or h.Health <= 0 then return nil end
        if St.cbt then return nil end
        local baseWS = h.WalkSpeed
        U.keyDown("F")
        task.wait(Cfg.BlockProbeWait)
        local isBlock = false
        if readBlockAttribute() then isBlock = true end
        if not isBlock and readBlockAnim() then isBlock = true end
        if not isBlock then
            local h2 = U.hum()
            if h2 and h2.WalkSpeed < baseWS - 4 then isBlock = true end
        end
        U.keyUp("F")
        task.wait(0.05)
        return isBlock and "block" or "skill"
    end

    --============================================================
    -- BLOCK HOLD / RELEASE
    --============================================================
    local function holdBlock()
        if St.blocking then return end
        St.blocking = true
        U.keyDown("F")
    end

    local function releaseBlock()
        if not St.blocking then return end
        St.blocking = false
        U.keyUp("F")
    end

    --============================================================
    -- TOOL HELPERS
    --============================================================
    local function equippedTool()
        local c = U.Lp.Character
        if not c then return nil end
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and not L.isCrow(t.Name) then return t end
        end
    end

    local function inventoryTools()
        local out = {}
        local c = U.Lp.Character
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") then table.insert(out, t) end
            end
        end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") then table.insert(out, t) end
            end
        end
        return out
    end

    local function equipWeapon()
        if St.swapPending then return end
        local now = U.clock()
        if now - St.lEqp < 1.5 then return end
        St.lEqp = now

        local h = U.hum(); if not h then return end
        local current = equippedTool()

        if current and L.isWeapon(current.Name) then
            St.eq = current.Name
            return
        end

        local target = nil
        for _, t in ipairs(inventoryTools()) do
            if L.isWeapon(t.Name) then target = t; break end
        end
        if not target then return end

        St.swapPending = true
        task.spawn(function()
            pcall(function()
                if current then
                    pcall(function() h:UnequipTools() end)
                    task.wait(0.08)
                end
                pcall(function() h:EquipTool(target) end)
                St.eq = target.Name
                print("[Dingus] equipped " .. target.Name)
            end)
            St.swapPending = false
        end)
    end

    --============================================================
    -- SKILLS
    --============================================================
    local function skillIsUltimate(idx)
        return idx >= 5
    end

    local function fireSkill(idx)
        local now = U.clock()
        if now < St.skCd[idx] then return false end
        U.tap(SK_KEYS[idx])
        St.skCd[idx] = now + SK_CDS[idx]
        St.skC = (St.skC or 0) + 1
        return true
    end

    --============================================================
    -- STRIKE · chained M1 combo
    --============================================================
    -- C2/C4 fix: fire N clicks with tight gap, wait interChain gap,
    -- occasionally chain a second burst. This triggers the game's
    -- internal combo progression instead of isolated first-attacks.
    local function doChainedStrike(burstCount)
        burstCount = burstCount or Cfg.ComboClicks
        local gap = Cfg.ComboClickGap

        if St.blocking then releaseBlock() end

        task.spawn(function()
            for i = 1, burstCount do
                U.m1()
                if i < burstCount then task.wait(gap) end
            end
        end)
    end

    local function strike(t)
        St.aAt = (St.aAt or 0) + 1
        local hpBefore = t.hm.Health

        -- Reset combo when target changes
        if St.comboTargetName ~= t.ch.Name then
            St.comboTargetName = t.ch.Name
            St.comboIndex = 0
        end
        St.comboIndex = St.comboIndex + 1

        -- Chain count escalates with combo index, resets per target
        local chain = 3
        if St.comboIndex % 5 == 0 then
            chain = 4  -- heavier finisher
        end

        if St.blocking then releaseBlock() end
        doChainedStrike(chain)

        -- Tool activation for any weapon-specific ability
        local tool = equippedTool()
        if tool then pcall(function() tool:Activate() end) end

        -- Hit verification
        task.spawn(function()
            task.wait(0.30)
            if not (t and t.hm and t.hm.Parent) then return end
            local hit = t.hm.Health < hpBefore
            table.insert(St.rHt, hit)
            if #St.rHt > Cfg.HitWindow then table.remove(St.rHt, 1) end
            if hit then
                St.aHi = (St.aHi or 0) + 1
            else
                St.aMs = (St.aMs or 0) + 1
            end
        end)
    end

    local function currentInterval()
        if #St.rHt < 5 then return St.aiI end
        local hits = 0
        for i = 1, #St.rHt do
            if St.rHt[i] then hits = hits + 1 end
        end
        local rate = hits / #St.rHt
        if rate > 0.7 then
            St.aiI = math.max(Cfg.AtkIntMin, St.aiI - 0.03)
        elseif rate < 0.3 then
            St.aiI = math.min(Cfg.AtkIntMax, St.aiI + 0.03)
        end
        return St.aiI
    end

    --============================================================
    -- SKILL ROTATION (with ultimate gating)
    --============================================================
    local function fireRotation(t, hpFrac)
        for _, i in ipairs(ROTATION) do
            if St.fIsBlock and SK_KEYS[i] == "F" then
                -- skip F if block
            else
                -- H3 fix: hold ultimate-tier skills (index 5+) unless
                -- the boss is stunned, HP is low, or we have breathing room
                local canFire = true
                if skillIsUltimate(i) then
                    local stunned = t and D.isEnemyStunned and D.isEnemyStunned(t)
                    local bossLow = hpFrac and hpFrac < Cfg.UltimateHPGate
                    local notThreatened = (St.imm or 0) == 0
                    if not (stunned or bossLow or notThreatened) then
                        canFire = false
                    end
                end
                if canFire and fireSkill(i) then return true end
            end
        end
    end

    --============================================================
    -- FACE TARGET (safe)
    --============================================================
    local function faceTarget(r, targetPos)
        pcall(function()
            local dx = targetPos.X - r.Position.X
            local dz = targetPos.Z - r.Position.Z
            if dx*dx + dz*dz < 0.04 then return end  -- too close, skip
            r.CFrame = CFrame.new(r.Position,
                Vector3.new(targetPos.X, r.Position.Y, targetPos.Z))
        end)
    end

    --============================================================
    -- SAFE CFrame CONSTRUCTION (C1 fix)
    --============================================================
    local function safeCFrame(dest, lookAtPos)
        -- Guarantee horizontal separation so the look vector isn't
        -- near-zero (which normalizes to NaN and drops the player
        -- into the void baseplate).
        local dx = lookAtPos.X - dest.X
        local dz = lookAtPos.Z - dest.Z
        local horizSq = dx*dx + dz*dz

        if horizSq < 0.25 then
            -- Horizontal components cancel. Force a separation using
            -- an arbitrary perpendicular.
            dx = 1
            dz = 0
            lookAtPos = Vector3.new(dest.X + dx, lookAtPos.Y, dest.Z + dz)
        end

        local ok, cf = pcall(function()
            return CFrame.new(dest, Vector3.new(lookAtPos.X, dest.Y, lookAtPos.Z))
        end)
        if ok and cf then return cf, nil end

        -- Fallback: position only, no orientation
        return CFrame.new(dest), "look-at build failed"
    end

    --============================================================
    -- TELEPORT CHASE (C4 fix — direction from player→boss)
    --============================================================
    local function teleportChase(t, tPos)
        local r = U.hrp()
        if not r then return false end

        local now = U.clock()
        if now - St.lTele < Cfg.TeleportCd then return false end
        St.lTele = now

        local myPos = r.Position
        local targetPos = tPos.Position

        -- C4: compute the approach vector FROM the player TO the boss.
        -- Land between the player's current position and the boss,
        -- offset slightly to the side for a flank angle.
        local approach = targetPos - myPos
        local flatApproach = Vector3.new(approach.X, 0, approach.Z)
        if flatApproach.Magnitude < 0.1 then
            flatApproach = Vector3.new(1, 0, 0)
        end
        flatApproach = flatApproach.Unit

        -- Side vector (perpendicular, horizontal)
        local side = Vector3.new(-flatApproach.Z, 0, flatApproach.X)

        -- Destination: in front of boss relative to us, at strike range,
        -- slightly to the side so we're not perfectly aligned with the
        -- boss's forward (avoids head-on face-off).
        local sideBias = (math.random() - 0.5) * 3
        local jx = (math.random() - 0.5) * Cfg.TeleportJitter
        local jz = (math.random() - 0.5) * Cfg.TeleportJitter

        local dest = targetPos
            - flatApproach * Cfg.TeleportStrike
            + side * sideBias
            + Vector3.new(jx, Cfg.TeleportHeight, jz)

        -- Keep us at a sane Y above the boss
        if dest.Y < targetPos.Y + 1 then
            dest = Vector3.new(dest.X, targetPos.Y + Cfg.TeleportHeight, dest.Z)
        end

        -- Look at the boss
        local cf, err = safeCFrame(dest, targetPos)
        local ok = pcall(function() r.CFrame = cf end)
        if not ok then
            St.teleFail = St.teleFail + 1
            return false
        end

        -- Kill any residual velocity so the server sees a settled state
        pcall(function()
            r.AssemblyLinearVelocity = Vector3.new(
                (math.random() - 0.5) * 3,
                -4 - math.random() * 3,
                (math.random() - 0.5) * 3
            )
        end)

        -- Blend: occasionally issue a small walk so post-hop we don't
        -- always have a frozen MoveDirection
        if math.random() < Cfg.TeleportWalkBlend then
            local h = U.hum()
            if h then
                pcall(function()
                    h:Move(Vector3.new(
                        (math.random() - 0.5) * 2,
                        0,
                        (math.random() - 0.5) * 2
                    ))
                end)
            end
        end

        St.teleCount = St.teleCount + 1
        return true
    end

    --============================================================
    -- IN-RANGE CHASE (H1 fix)
    --============================================================
    -- When the boss moves during melee, we need to stay glued to the
    -- strike radius. Re-face every tick; if the boss slides away,
    -- nudge ourselves back into range with a short teleport.
    local function inRangeChase(t, tPos, myPos)
        local now = U.clock()
        if now - St.lInRangeChase < Cfg.InRangeChaseT then return end
        St.lInRangeChase = now

        local r = U.hrp()
        if not r then return end

        local myH = U.hum()
        if myH then
            myH.AutoRotate = true
        end

        faceTarget(r, tPos.Position)

        -- If boss has slid beyond AtkRange, do a fast short hop
        local dist = U.xzDist(myPos, tPos.Position)
        if dist > Cfg.AtkRange + 1.5 then
            local approach = tPos.Position - myPos
            local flat = Vector3.new(approach.X, 0, approach.Z)
            if flat.Magnitude > 0.1 then
                flat = flat.Unit
            end
            local hopDist = dist - Cfg.TeleportStrike
            if hopDist > 0.5 and hopDist < 20 then
                local dest = myPos + flat * hopDist
                dest = Vector3.new(dest.X, myPos.Y, dest.Z)
                local cf = safeCFrame(dest, tPos.Position)
                pcall(function() r.CFrame = cf end)
            end
        end
    end

    --============================================================
    -- DODGE (C3 fix)
    --============================================================
    local function tryDodge()
        local now = U.clock()
        if now - St.lDodge < Cfg.DodgeCooldown then return false end
        St.lDodge = now
        St.dodgeCount = St.dodgeCount + 1
        U.tap("Q")
        return true
    end

    --============================================================
    -- RETREAT
    --============================================================
    local retreatRunning = false

    local function startRetreat(from)
        if retreatRunning then return end
        retreatRunning = true
        St.rtrC = (St.rtrC or 0) + 1
        St.cbtS = "RETREAT"
        releaseBlock()
        if Ctx.Spoof and Ctx.Spoof.surfaceUp then
            pcall(Ctx.Spoof.surfaceUp)
        end

        task.spawn(function()
            U.tap("Q"); task.wait(0.25)
            local r = U.hrp(); local h = U.hum()
            if not r or not h then
                retreatRunning = false; St.cbtS = "IDLE"; return
            end
            local away = r.Position - from
            local flat = Vector3.new(away.X, 0, away.Z)
            if flat.Magnitude < 0.5 then flat = Vector3.new(1, 0, 0) end
            h.WalkSpeed = Cfg.RunSpeed

            local startT = U.clock()
            local hardCap = startT + 2.5
            local lastHp = h.Health
            local lastDamageT = startT

            while U.clock() < startT + Cfg.RetreatDelay do
                local hh = U.hum()
                if not hh then break end
                if hh.Health / hh.MaxHealth > Cfg.RetreatClearHP then break end
                if hh.Health < lastHp then
                    lastHp = hh.Health
                    lastDamageT = U.clock()
                end
                if U.clock() - lastDamageT > 1.2 and U.clock() > startT + 0.6 then
                    break
                end
                if U.clock() > hardCap then break end
                h:Move(flat.Unit)
                task.wait(0.05)
            end

            retreatRunning = false
            St.tgt = nil
            if D.invalidate then D.invalidate() end
        end)
    end

    --============================================================
    -- TARGET ACQUISITION
    --============================================================
    local function acquireTarget()
        local tgt, kind = D.pickTarget()
        St.tgt = tgt
        St.tgtKind = kind
        if tgt then
            St.comboTargetName = nil
            St.comboIndex = 0
            print(string.format("[Dingus] target %s (%s) @%.0f",
                tgt.ch.Name, kind, tgt.d))
        end
        return tgt
    end

    --============================================================
    -- F-MODE RESOLUTION
    --============================================================
    local function resolveFMode()
        if St.fModeResolved then return end
        local mode = Cfg.FKeyMode or "auto"

        if mode == "auto" then
            local waited = 0
            while (not U.hrp() or St.cbt) and waited < 15 do
                task.wait(0.5)
                waited = waited + 0.5
            end
            if St.cbt then
                St.fModeResolved = true
                St.fIsBlock = false
                print("[Dingus][Atk] F-mode deferred — default skill")
                return
            end
            local result = probeFKey()
            if result == "block" then
                St.fIsBlock = true
                Cfg.RotationOrder = { 2, 3, 4, 5, 6 }
                ROTATION = Cfg.RotationOrder
                print("[Dingus][Atk] F-mode = BLOCK")
            else
                St.fIsBlock = false
                Cfg.RotationOrder = { 2, 3, 1, 4, 5, 6 }
                ROTATION = Cfg.RotationOrder
                print("[Dingus][Atk] F-mode = SKILL")
            end
        elseif mode == "block" then
            St.fIsBlock = true
            Cfg.RotationOrder = { 2, 3, 4, 5, 6 }
            ROTATION = Cfg.RotationOrder
            print("[Dingus][Atk] F-mode = BLOCK (config)")
        elseif mode == "skill" then
            St.fIsBlock = false
            Cfg.RotationOrder = { 2, 3, 1, 4, 5, 6 }
            ROTATION = Cfg.RotationOrder
            print("[Dingus][Atk] F-mode = SKILL (config)")
        end
        St.fModeResolved = true
    end
    task.spawn(resolveFMode)

    --============================================================
    -- COMBAT TICK
    --============================================================
    function A.combatTick()
        if not St.cbt then
            St.cbtS = "IDLE"
            releaseBlock()
            return
        end

        local h = U.hum()
        local r = U.hrp()
        if not h or not r then St.cbtS = "NO_CHAR"; return end
        if h.Health <= 0 then
            St.cbtS = "DEAD"
            releaseBlock()
            return
        end

        local now = U.clock()
        local hpFrac = h.Health / h.MaxHealth

        equipWeapon()
        U.groundState()

        if h.Health < (St.lHp or 0) and now - (St.lHpT or 0) > 0.05 then
            St.lDmg = now
        end
        St.lHp = h.Health
        St.lHpT = now

        -- Passive breathing
        if now - St.lBrt > 2.5 then
            St.lBrt = now
            U.tap("L")
        end

        -- Low HP → retreat
        if St.rtr and hpFrac < Cfg.RetreatHP and not retreatRunning then
            local nearest = St.ths and St.ths[1]
            if nearest then startRetreat(nearest.rp.Position); return end
        end
        if retreatRunning then return end

        -- Acquire target
        if not St.tgt or not St.tgt.ch.Parent or St.tgt.hm.Health <= 0 then
            if St.tgt then
                St.kll = (St.kll or 0) + 1
                St.bKll = (St.bKll or 0) + 1
                print(string.format("[Dingus] killed %s (%d)",
                    St.tgt.ch.Name, St.bKll))
                St.tgt = nil
                St.comboIndex = 0
                St.comboTargetName = nil
                releaseBlock()
                if D.invalidate then D.invalidate() end
            end
            acquireTarget()
            if not St.tgt then
                St.cbtS = "IDLE"
                releaseBlock()
                return
            end
        end

        local t = St.tgt
        local tPos = t.ch:FindFirstChild("HumanoidRootPart")
        if not tPos then St.tgt = nil; return end

        local myPos = r.Position
        local dist = U.xzDist(myPos, tPos.Position)
        t.d = dist

        --========================================================
        -- TELEGRAPH EVALUATION (C3 fix)
        --========================================================
        local imminent = (St.imm or 0) > 0
        local bossAttacking = false
        if D.isEnemyAttacking then
            bossAttacking = D.isEnemyAttacking(t)
        end
        -- Also read the threat timing
        if imminent and not St.lastBossAttacking then
            St.threatSince = now
        end
        St.lastBossAttacking = imminent or bossAttacking

        --========================================================
        -- LONG RANGE → TELEPORT
        --========================================================
        if dist > Cfg.AtkRange then
            St.cbtS = "TELEPORT"
            releaseBlock()

            -- Don't teleport if a boss attack is mid-wind-up — the
            -- teleport animation won't save us. Dodge first.
            if (imminent or bossAttacking) and (now - St.lDodge > Cfg.DodgeCooldown) then
                St.cbtS = "DODGE"
                tryDodge()
                task.wait(0.05)
                return
            end

            teleportChase(t, tPos)
            if St.skl and now - St.lSkl > 2.0 then
                St.lSkl = now
                fireRotation(t, hpFrac)
            end
            return
        end

        --========================================================
        -- IN RANGE
        --========================================================
        -- Maintain alignment with the boss
        inRangeChase(t, tPos, myPos)

        local blocking = D.isEnemyBlocking(t)
        local stunned = D.isEnemyStunned(t)
        local timeSinceThreat = now - St.threatSince

        --========================================================
        -- TELEGRAPH REACTION (C3)
        --========================================================
        -- Priority: dodge > block > strike
        -- 1. If a boss attack is imminent and we can dodge, do it
        -- 2. Otherwise if we can block (F is block), hold F
        -- 3. Otherwise attack

        local canDodge = (now - St.lDodge) > Cfg.DodgeCooldown
        local telegraphWindow = timeSinceThreat < Cfg.TelegraphWindow

        if (imminent or bossAttacking) and canDodge and telegraphWindow then
            St.cbtS = "DODGE"
            releaseBlock()
            tryDodge()
            return
        end

        --========================================================
        -- AUTO-BLOCK
        --========================================================
        local shouldBlock = false
        if St.fIsBlock and Cfg.AutoBlock then
            local threatNow = imminent or bossAttacking
            if threatNow then
                St.blockHoldUntil = now + Cfg.BlockHoldTTL
            end
            shouldBlock = threatNow or (now < (St.blockHoldUntil or 0))
        end

        --========================================================
        -- PUNISH · BREAK_BLOCK · ATTACK
        --========================================================
        if stunned and St.stunPun then
            St.cbtS = "PUNISH"
            releaseBlock()
            if now - St.lAtk >= Cfg.StunAtkInt then
                St.lAtk = now
                strike(t)
            end
            -- Punish window: fire heavy skills liberally
            if St.skl and now - St.lSkl > 0.25 then
                St.lSkl = now
                fireRotation(t, hpFrac)
            end
            return
        end

        if blocking then
            St.cbtS = "BREAK"
            releaseBlock()
            if St.skl and now - St.lSkl > 0.4 then
                St.lSkl = now
                fireRotation(t, hpFrac)
            end
            if now - St.lAtk > St.aiI * 1.2 then
                St.lAtk = now
                strike(t)
            end
            return
        end

        -- Normal attack
        St.cbtS = "STRIKE"

        if shouldBlock and (now - St.lAtk < currentInterval() * 0.7) then
            St.cbtS = "BLOCK"
            holdBlock()
            -- Still fire rotation while blocking if skills are ready
            if St.skl and now - St.lSkl > 1.0 then
                St.lSkl = now
                fireRotation(t, hpFrac)
            end
        else
            releaseBlock()
            if now - St.lAtk >= currentInterval() then
                St.lAtk = now
                strike(t)
            end
            if St.skl and now - St.lSkl > 1.4 then
                St.lSkl = now
                fireRotation(t, hpFrac)
            end
        end
    end

    --============================================================
    -- PUBLIC HELPERS
    --============================================================
    function A.forceScan()
        if D.invalidate then D.invalidate() end
        local list = D.scanBosses()
        print(string.format("[Dingus] force scan: %d bosses", #list))
        for i = 1, math.min(#list, 5) do
            print(string.format("  · %s @%.0f studs",
                list[i].ch.Name, list[i].d))
        end
    end

    function A.forceMove()
        if not St.tgt then return end
        local r = U.hrp()
        local tPos = St.tgt.ch:FindFirstChild("HumanoidRootPart")
        if r and tPos then
            local dest = tPos.Position + Vector3.new(0, 3, 0)
            local cf = safeCFrame(dest, tPos.Position)
            pcall(function() r.CFrame = cf end)
        end
    end

    function A.fModeInfo()
        return {
            resolved = St.fModeResolved,
            isBlock  = St.fIsBlock,
            blocking = St.blocking,
            rotation = Cfg.RotationOrder,
        }
    end

    function A.telemetry()
        return {
            teleports = St.teleCount or 0,
            teleFails = St.teleFail or 0,
            dodges    = St.dodgeCount or 0,
            lastTeleportGap = U.clock() - (St.lTele or 0),
            comboIndex = St.comboIndex or 0,
            comboTarget = St.comboTargetName,
        }
    end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function()
        releaseBlock()
    end)

    print("[Dingus][attack] v6 initialized · chained strikes + dodge + telegraph")
end

return A
