--[[
    Dingus-Slayer · attack.lua v5
    Teleport-based chase. Fly path removed entirely.

    Chase strategy:
      - Target within AtkRange: strike
      - Target beyond AtkRange: teleport behind, facing forward
      - Teleport is rate-limited (TeleportCd), jittered, and blended
        with a random walk command so position history looks normal

    Config keys added (defaulted inline):
      TeleportCd          seconds between teleport hops
      TeleportBehindDist  studs behind boss to land
      TeleportHeight      studs above target Y
      TeleportJitter      random XY jitter per hop
      TeleportWalkBlend   chance to send a small walk command post-hop
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
    Cfg.AtkIntMin      = Cfg.AtkIntMin      or 0.35
    Cfg.AtkIntMax      = Cfg.AtkIntMax      or 0.75
    Cfg.StunAtkInt     = Cfg.StunAtkInt     or 0.28
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
    Cfg.BlockHoldTTL   = Cfg.BlockHoldTTL   or 0.6
    Cfg.BlockProbeWait = Cfg.BlockProbeWait or 0.15

    -- Teleport
    Cfg.TeleportCd         = Cfg.TeleportCd         or 0.22
    Cfg.TeleportBehindDist = Cfg.TeleportBehindDist or 6
    Cfg.TeleportHeight     = Cfg.TeleportHeight     or 3
    Cfg.TeleportJitter     = Cfg.TeleportJitter     or 2
    Cfg.TeleportWalkBlend  = Cfg.TeleportWalkBlend  or 0.4

    Cfg.EquipDebugN    = Cfg.EquipDebugN    or 3

    --============================================================
    -- STATE
    --============================================================
    St.rHt = {}
    St.skCd = { 0, 0, 0, 0, 0, 0 }
    St.aiI = Cfg.AtkInterval
    St.lAtk = 0; St.lSkl = 0; St.lEqp = 0; St.lBrt = 0
    St.lFac = 0; St.lMoveLog = 0; St.lTele = 0
    St.eq = "none"; St.lTl = false
    St.cbtS = "IDLE"
    St.lastPos = nil; St.lastPosTime = 0
    St.stuckWarnings = 0
    St.lastComboTime = 0; St.comboIndex = 0
    St.swapPending = false
    St.equipDebugLeft = Cfg.EquipDebugN

    St.fIsBlock = false
    St.fModeResolved = false
    St.blocking = false
    St.blockHoldUntil = 0

    -- Teleport counters
    St.teleCount = 0

    local SK_KEYS = Cfg.SkillKeys
    local SK_CDS  = Cfg.SkillCooldowns
    local ROTATION = Cfg.RotationOrder

    local COMBO_AIR       = { "m1", "m2", "m1", "m2", "m1" }
    local COMBO_SPECIAL_A = { "m2", "m2", "m1", "m2", "m1" }
    local COMBO_SPECIAL_B = { "m1", "m1", "m2", "m1", "m2" }
    local COMBO_RESET_TIME = 1.2

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
        local debugThis = St.equipDebugLeft > 0
        if debugThis then
            St.equipDebugLeft = St.equipDebugLeft - 1
            print(string.format("[Dingus][Equip] current=%s",
                current and current.Name or "nil"))
        end

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
    local function fireSkill(idx)
        local now = U.clock()
        if now < St.skCd[idx] then return false end
        U.tap(SK_KEYS[idx])
        St.skCd[idx] = now + SK_CDS[idx]
        St.skC = (St.skC or 0) + 1
        return true
    end

    local function fireRotation()
        for _, i in ipairs(ROTATION) do
            if not (St.fIsBlock and SK_KEYS[i] == "F") then
                if fireSkill(i) then return true end
            end
        end
    end

    --============================================================
    -- STRIKE
    --============================================================
    local function m1() U.m1() end
    local function m2() U.m2() end

    local function strike(t)
        St.aAt = (St.aAt or 0) + 1
        local hpBefore = t.hm.Health

        if St.blocking then releaseBlock() end

        local now = U.clock()
        if now - St.lastComboTime > COMBO_RESET_TIME then
            St.comboIndex = 0
        end
        St.lastComboTime = now
        St.comboIndex = St.comboIndex + 1

        local combo
        if t.d and t.d > 15 then
            combo = COMBO_AIR
        elseif math.random() < 0.5 then
            combo = COMBO_SPECIAL_A
        else
            combo = COMBO_SPECIAL_B
        end

        local step = combo[((St.comboIndex - 1) % #combo) + 1]
        if step == "m2" then m2() else m1() end

        local tool = equippedTool()
        if tool then pcall(function() tool:Activate() end) end

        task.spawn(function()
            task.wait(0.25)
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
            St.aiI = math.max(Cfg.AtkIntMin, St.aiI - 0.02)
        elseif rate < 0.3 then
            St.aiI = math.min(Cfg.AtkIntMax, St.aiI + 0.02)
        end
        return St.aiI
    end

    local function faceTarget(r, targetPos)
        pcall(function()
            r.CFrame = CFrame.new(r.Position,
                Vector3.new(targetPos.X, r.Position.Y, targetPos.Z))
        end)
    end

    --============================================================
    -- TELEPORT CHASE
    --============================================================
    local function teleportChase(t, tPos)
        local r = U.hrp()
        if not r then return false end

        local now = U.clock()
        if now - St.lTele < Cfg.TeleportCd then return false end
        St.lTele = now

        local targetPos = tPos.Position
        local bossLook = tPos.CFrame.LookVector

        -- Land behind the boss at configured height
        local behindOffset = -bossLook * Cfg.TeleportBehindDist
        local aboveOffset = Vector3.new(0, Cfg.TeleportHeight, 0)

        -- Jitter — small enough to look like movement, big enough to
        -- break exact-repeat position vectors
        local jx = (math.random() - 0.5) * Cfg.TeleportJitter
        local jy = (math.random() - 0.5) * (Cfg.TeleportJitter * 0.3)
        local jz = (math.random() - 0.5) * Cfg.TeleportJitter

        local dest = targetPos + behindOffset + aboveOffset
            + Vector3.new(jx, jy, jz)

        local face = Vector3.new(targetPos.X, dest.Y, targetPos.Z)

        local ok = pcall(function()
            r.CFrame = CFrame.new(dest, face)
        end)

        if not ok then return false end

        -- Blend: post-hop velocity that doesn't look like landing
        -- from a teleport. Random small XY, slightly negative Y so
        -- it reads as "landed and settled".
        pcall(function()
            r.AssemblyLinearVelocity = Vector3.new(
                (math.random() - 0.5) * 4,
                -5 - math.random() * 3,
                (math.random() - 0.5) * 4
            )
        end)

        -- Blend: occasional tiny walk command so MoveDirection in
        -- the next tick isn't zero for every hop
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

        if now - St.lBrt > 2.5 then St.lBrt = now; U.tap("L") end

        if St.rtr and hpFrac < Cfg.RetreatHP and not retreatRunning then
            local nearest = St.ths and St.ths[1]
            if nearest then startRetreat(nearest.rp.Position); return end
        end
        if retreatRunning then return end

        if not St.tgt or not St.tgt.ch.Parent or St.tgt.hm.Health <= 0 then
            if St.tgt then
                St.kll = (St.kll or 0) + 1
                St.bKll = (St.bKll or 0) + 1
                print(string.format("[Dingus] killed %s (%d)",
                    St.tgt.ch.Name, St.bKll))
                St.tgt = nil
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

        local dist = U.xzDist(r.Position, tPos.Position)
        t.d = dist

        --========================================================
        -- LONG RANGE · TELEPORT
        --========================================================
        if dist > Cfg.AtkRange then
            St.cbtS = "TELEPORT"
            releaseBlock()
            teleportChase(t, tPos)
            if St.skl and now - St.lSkl > 2.0 then
                St.lSkl = now
                fireRotation()
            end
            return
        end

        --========================================================
        -- IN RANGE
        --========================================================
        local blocking = D.isEnemyBlocking(t)
        local stunned = D.isEnemyStunned(t)

        faceTarget(r, tPos.Position)

        local shouldBlock = false
        if St.fIsBlock and Cfg.AutoBlock then
            local threatNow = (St.imm or 0) > 0
            if threatNow then
                St.blockHoldUntil = now + Cfg.BlockHoldTTL
            end
            shouldBlock = threatNow or (now < (St.blockHoldUntil or 0))
        end

        if stunned and St.stunPun then
            St.cbtS = "PUNISH"
            releaseBlock()
            if now - St.lAtk >= Cfg.StunAtkInt then
                St.lAtk = now
                strike(t)
            end
            if St.skl and now - St.lSkl > 0.3 then
                St.lSkl = now
                fireRotation()
            end
            return
        end

        if blocking then
            St.cbtS = "BREAK_BLOCK"
            releaseBlock()
            if St.skl and now - St.lSkl > 0.5 then
                St.lSkl = now
                fireRotation()
            end
            if now - St.lAtk > St.aiI * 1.5 then
                St.lAtk = now
                strike(t)
            end
            return
        end

        St.cbtS = "ATTACK"
        if shouldBlock and (now - St.lAtk < currentInterval() * 0.8) then
            holdBlock()
        else
            releaseBlock()
            if now - St.lAtk >= currentInterval() then
                St.lAtk = now
                strike(t)
            end
        end

        if St.skl and now - St.lSkl > 1.6 then
            St.lSkl = now
            fireRotation()
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
            r.CFrame = CFrame.new(tPos.Position + Vector3.new(0, 3, 0))
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
            lastTeleportGap = U.clock() - (St.lTele or 0),
        }
    end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function()
        releaseBlock()
    end)

    print("[Dingus][attack] v5 initialized · teleport-based")
end

return A
