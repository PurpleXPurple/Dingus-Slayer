--[[
    Dingus-Slayer · attack.lua v7
    Post-v0.140 combat. Global cooldown. Chained M1/M2. Punish windows.

    Addresses /audit:
      C1  Global cooldown tracking (St.gcdUntil) replaces per-skill array
      C2  St.skCd array removed
      C3  Alternating M1/M2 in chain (matches game's combo FSM)
      H1  Skill unlock mask (Cfg.SkillUnlocked)
      H2  AtkInterval lowered to 0.38
      H3  Party-size aware aggression
      H4  Teleport priority over dodge out-of-range
      M1  Breath meter read (if available)
      M2  Single CFrame write per tick
      M3  Punish window detection
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
    -- CONFIG
    --============================================================
    Cfg.AtkRange       = Cfg.AtkRange       or 8
    Cfg.AtkInterval    = Cfg.AtkInterval    or 0.38
    Cfg.AtkIntMin      = Cfg.AtkIntMin      or 0.25
    Cfg.AtkIntMax      = Cfg.AtkIntMax      or 0.65
    Cfg.StunAtkInt     = Cfg.StunAtkInt     or 0.22
    Cfg.HitWindow      = Cfg.HitWindow      or 15
    Cfg.RunSpeed       = Cfg.RunSpeed       or 16

    Cfg.RetreatHP      = Cfg.RetreatHP      or 0.35
    Cfg.RetreatDelay   = Cfg.RetreatDelay   or 3.0
    Cfg.RetreatClearHP = Cfg.RetreatClearHP or 0.65

    Cfg.SkillKeys      = Cfg.SkillKeys      or { "F", "Z", "X", "C", "V", "B" }
    Cfg.SkillUnlocked  = Cfg.SkillUnlocked  or { true, true, true, true, true, true }
    Cfg.RotationOrder  = Cfg.RotationOrder  or { 2, 3, 4, 5, 6 }

    -- Global cooldown: single shared timer for all skills (v0.140)
    Cfg.GCDWindow      = Cfg.GCDWindow      or 1.30

    Cfg.FKeyMode       = Cfg.FKeyMode       or "auto"
    Cfg.AutoBlock      = Cfg.AutoBlock      ~= false
    Cfg.BlockHoldTTL   = Cfg.BlockHoldTTL   or 0.4
    Cfg.BlockProbeWait = Cfg.BlockProbeWait or 0.15

    Cfg.TeleportCd         = Cfg.TeleportCd         or 0.22
    Cfg.TeleportStrike      = Cfg.TeleportStrike      or 4.5
    Cfg.TeleportHeight     = Cfg.TeleportHeight     or 3
    Cfg.TeleportJitter     = Cfg.TeleportJitter     or 2
    Cfg.TeleportWalkBlend  = Cfg.TeleportWalkBlend  or 0.6

    Cfg.ComboBurst         = Cfg.ComboBurst         or 4
    Cfg.ComboGap           = Cfg.ComboGap           or 0.11

    Cfg.DodgeCooldown      = Cfg.DodgeCooldown      or 0.7
    Cfg.InRangeChaseT      = Cfg.InRangeChaseT      or 0.22
    Cfg.UltimateHPGate     = Cfg.UltimateHPGate     or 0.40
    Cfg.TelegraphWindow    = Cfg.TelegraphWindow    or 0.45
    Cfg.WalkBlendInterval  = Cfg.WalkBlendInterval  or 8.0
    Cfg.BlockBlendInterval = Cfg.BlockBlendInterval or 15.0
    Cfg.M1MaxHz            = Cfg.M1MaxHz            or 10

    --============================================================
    -- STATE
    --============================================================
    St.rHt = {}
    St.gcdUntil = 0
    St.aiI = Cfg.AtkInterval

    St.lAtk = 0
    St.lSkl = 0
    St.lEqp = 0
    St.lBrt = 0
    St.lDodge = 0
    St.lTele = 0
    St.lInRangeChase = 0
    St.lThreat = 0
    St.lWalkBlend = 0
    St.lBlockBlend = 0
    St.lTelemetryPrint = 0

    St.eq = "none"
    St.cbtS = "IDLE"
    St.comboIndex = 0
    St.comboTargetName = nil
    St.swapPending = false

    St.fIsBlock = false
    St.fModeResolved = false
    St.blocking = false
    St.blockHoldUntil = 0

    St.teleCount = 0
    St.teleFail = 0
    St.dodgeCount = 0
    St.gcdHits = 0
    St.gcdMisses = 0

    St.breathFrac = 1.0
    St.partySize = 1

    local SK_KEYS = Cfg.SkillKeys

    --============================================================
    -- MOVER SCRUB
    --============================================================
    local function scrubMovers()
        local r = U.hrp()
        if not r then return end
        for _, c in ipairs(r:GetChildren()) do
            if c:IsA("BodyPosition") or c:IsA("BodyVelocity")
                or c:IsA("BodyGyro") or c:IsA("BodyForce")
                or c:IsA("LinearVelocity") or c:IsA("AlignOrientation")
                or c:IsA("AlignPosition") then
                c:Destroy()
            end
        end
        local h = U.hum()
        if h then
            h.PlatformStand = false
            h.AutoRotate = true
        end
    end
    scrubMovers()
    U.Lp.CharacterAdded:Connect(function()
        task.wait(1)
        scrubMovers()
        St.blocking = false
        St.blockHoldUntil = 0
        St.fModeResolved = false
        St.comboIndex = 0
        St.comboTargetName = nil
    end)

    --============================================================
    -- BREATH METER READER
    --============================================================
    -- Attempts to read the breath resource from common paths.
    -- Returns a 0-1 fraction. Returns nil on failure.
    local function readBreath()
        local c = U.Lp.Character
        if not c then return nil end
        local h = U.hum()
        if h then
            local ok, att = pcall(function() return h:GetAttribute("Breath") end)
            if ok and type(att) == "number" then
                local maxOk, mx = pcall(function() return h:GetAttribute("MaxBreath") end)
                if maxOk and type(mx) == "number" and mx > 0 then
                    return att / mx
                end
            end
        end
        -- Fallback: search ReplicatedStorage Player_Service for a Breath value
        local rs = game:GetService("ReplicatedStorage")
        local ps = rs:FindFirstChild("Player_Service")
        local data = ps and ps:FindFirstChild("Data")
        local me = data and data:FindFirstChild(U.Lp.Name)
        local slots = me and me:FindFirstChild("slots")
        if slots then
            for _, slot in ipairs(slots:GetChildren()) do
                local stats = slot:FindFirstChild("Stats")
                local br = stats and stats:FindFirstChild("Breath")
                local mx = stats and stats:FindFirstChild("MaxBreath")
                if br and mx and br.Value and mx.Value and mx.Value > 0 then
                    return br.Value / mx.Value
                end
            end
        end
        return nil
    end

    --============================================================
    -- PARTY SIZE
    --============================================================
    local function readPartySize()
        local plr = game:GetService("Players")
        local ok, count = pcall(function() return #plr:GetPlayers() end)
        return (ok and count) or 1
    end

    --============================================================
    -- BLOCK
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
    -- TOOL
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
    -- GCD GATED SKILL
    --============================================================
    local function gcdReady(now)
        return now >= St.gcdUntil
    end

    local function fireSkill(idx, now)
        if not gcdReady(now) then
            St.gcdMisses = St.gcdMisses + 1
            return false
        end
        if not Cfg.SkillUnlocked[idx] then return false end
        if St.fIsBlock and SK_KEYS[idx] == "F" then return false end

        -- Breath gate
        if St.breathFrac and St.breathFrac < 0.15 then
            return false
        end

        U.tap(SK_KEYS[idx])
        St.gcdUntil = now + Cfg.GCDWindow
        St.gcdHits = St.gcdHits + 1
        St.skC = (St.skC or 0) + 1
        return true
    end

    --============================================================
    -- PUNISH-WINDOW DETECTION
    --============================================================
    -- A punish window opens when:
    --   1. Boss just finished a heavy attack animation (recovery)
    --   2. Boss is in a stagger state
    --   3. Boss just whiffed its own skill
    -- We approximate from the threat counter and stun flag.
    local function inPunishWindow(t)
        if not t then return false end
        if D.isEnemyStunned and D.isEnemyStunned(t) then return true end
        -- After a threat spike subsides, there's usually a 1.5s recovery
        local now = U.clock()
        if St.threatPeak and now - St.threatPeak < 1.5 then return true end
        return false
    end

    --============================================================
    -- SKILL ROTATION (GCD-aware, ultimate gated)
    --============================================================
    local function fireRotation(t, hpFrac, now)
        if not St.skl then return end
        if not gcdReady(now) then return end

        local stunned = t and D.isEnemyStunned and D.isEnemyStunned(t)
        local punish = inPunishWindow(t)
        local bossLow = hpFrac and hpFrac < Cfg.UltimateHPGate
        local notThreatened = (St.imm or 0) == 0

        for _, idx in ipairs(Cfg.RotationOrder) do
            local isUlt = idx >= 5
            if not isUlt then
                -- Non-ultimate: fire if unlocked and gcd free
                if fireSkill(idx, now) then return true end
            else
                -- Ultimate gated
                if stunned or punish or bossLow or notThreatened then
                    if fireSkill(idx, now) then return true end
                end
            end
        end
        return false
    end

    --============================================================
    -- SAFE CFrame
    --============================================================
    local function safeCFrame(dest, lookAtPos)
        local dx = lookAtPos.X - dest.X
        local dz = lookAtPos.Z - dest.Z
        if dx*dx + dz*dz < 0.25 then
            lookAtPos = Vector3.new(dest.X + 1, lookAtPos.Y, dest.Z)
        end
        local ok, cf = pcall(function()
            return CFrame.new(dest, Vector3.new(lookAtPos.X, dest.Y, lookAtPos.Z))
        end)
        if ok and cf then return cf end
        return CFrame.new(dest)
    end

    --============================================================
    -- TELEPORT CHASE
    --============================================================
    local function teleportChase(t, tPos, myPos)
        local r = U.hrp()
        if not r then return false end

        local now = U.clock()
        if now - St.lTele < Cfg.TeleportCd then return false end
        St.lTele = now

        local targetPos = tPos.Position
        local approach = targetPos - myPos
        local flatApproach = Vector3.new(approach.X, 0, approach.Z)
        if flatApproach.Magnitude < 0.1 then
            flatApproach = Vector3.new(1, 0, 0)
        end
        flatApproach = flatApproach.Unit
        local side = Vector3.new(-flatApproach.Z, 0, flatApproach.X)

        -- Slow-drifting bias so teleport landings aren't statistically identical
        local bias = math.sin(now * 0.3) * 2
        local jx = (math.random() - 0.5) * Cfg.TeleportJitter
        local jz = (math.random() - 0.5) * Cfg.TeleportJitter

        local dest = targetPos
            - flatApproach * Cfg.TeleportStrike
            + side * (bias + jx * 0.5)
            + Vector3.new(jx, Cfg.TeleportHeight, jz)

        if dest.Y < targetPos.Y + 1 then
            dest = Vector3.new(dest.X, targetPos.Y + Cfg.TeleportHeight, dest.Z)
        end

        local cf = safeCFrame(dest, targetPos)
        local ok = pcall(function() r.CFrame = cf end)
        if not ok then
            St.teleFail = St.teleFail + 1
            return false
        end

        pcall(function()
            r.AssemblyLinearVelocity = Vector3.new(
                (math.random() - 0.5) * 3,
                -4 - math.random() * 3,
                (math.random() - 0.5) * 3
            )
        end)

        -- Walk blend
        if math.random() < Cfg.TeleportWalkBlend then
            local h = U.hum()
            if h then
                pcall(function()
                    h:Move(Vector3.new(
                        (math.random() - 0.5) * 2, 0,
                        (math.random() - 0.5) * 2
                    ))
                end)
            end
        end

        St.teleCount = St.teleCount + 1
        return true
    end

    --============================================================
    -- IN-RANGE CHASE
    --============================================================
    local function inRangeChase(t, tPos, myPos, now)
        if now - St.lInRangeChase < Cfg.InRangeChaseT then return end
        St.lInRangeChase = now

        local r = U.hrp()
        if not r then return end

        local dx = tPos.Position.X - myPos.X
        local dz = tPos.Position.Z - myPos.Z
        if dx*dx + dz*dz > 0.04 then
            pcall(function()
                r.CFrame = CFrame.new(myPos,
                    Vector3.new(tPos.Position.X, myPos.Y, tPos.Position.Z))
            end)
        end

        local dist = U.xzDist(myPos, tPos.Position)
        if dist > Cfg.AtkRange + 1.5 and dist < 25 then
            local approach = tPos.Position - myPos
            local flat = Vector3.new(approach.X, 0, approach.Z)
            if flat.Magnitude > 0.1 then
                flat = flat.Unit
                local hopDist = dist - Cfg.TeleportStrike
                if hopDist > 0.5 then
                    local dest = myPos + flat * hopDist
                    dest = Vector3.new(dest.X, myPos.Y, dest.Z)
                    local cf = safeCFrame(dest, tPos.Position)
                    pcall(function() r.CFrame = cf end)
                end
            end
        end
    end

    --============================================================
    -- DODGE
    --============================================================
    local function tryDodge(now)
        if now - St.lDodge < Cfg.DodgeCooldown then return false end
        St.lDodge = now
        St.dodgeCount = St.dodgeCount + 1
        U.tap("Q")
        return true
    end

    --============================================================
    -- CHAINED STRIKE (alternating M1/M2)
    --============================================================
    local function doChainedStrike(count)
        count = count or Cfg.ComboBurst
        local gap = Cfg.ComboGap

        if St.blocking then releaseBlock() end

        task.spawn(function()
            -- Enforce max M1 Hz by spacing accordingly
            local minGap = 1 / Cfg.M1MaxHz
            local effectiveGap = math.max(gap, minGap)
            for i = 1, count do
                -- Alternate: odd = M1, even = M2
                if i % 2 == 0 then
                    U.m2()
                else
                    U.m1()
                end
                if i < count then task.wait(effectiveGap) end
            end
        end)
    end

    local function strike(t, now)
        St.aAt = (St.aAt or 0) + 1
        local hpBefore = t.hm.Health

        if St.comboTargetName ~= t.ch.Name then
            St.comboTargetName = t.ch.Name
            St.comboIndex = 0
        end
        St.comboIndex = St.comboIndex + 1

        local chain = Cfg.ComboBurst
        if St.comboIndex % 4 == 0 then chain = chain + 1 end

        doChainedStrike(chain)

        local tool = equippedTool()
        if tool then pcall(function() tool:Activate() end) end

        task.spawn(function()
            task.wait(0.35)
            if not (t and t.hm and t.hm.Parent) then return end
            local hit = t.hm.Health < hpBefore
            table.insert(St.rHt, hit)
            if #St.rHt > Cfg.HitWindow then table.remove(St.rHt, 1) end
            if hit then St.aHi = (St.aHi or 0) + 1
            else St.aMs = (St.aMs or 0) + 1 end
        end)
    end

    local function currentInterval()
        if #St.rHt < 5 then return St.aiI end
        local hits = 0
        for i = 1, #St.rHt do if St.rHt[i] then hits = hits + 1 end end
        local rate = hits / #St.rHt
        -- Party scaling: more players = tighter interval to compensate
        local partyAdj = 1.0
        if St.partySize >= 3 then partyAdj = 0.85
        elseif St.partySize == 2 then partyAdj = 0.92 end

        if rate > 0.7 then
            St.aiI = math.max(Cfg.AtkIntMin, St.aiI - 0.03)
        elseif rate < 0.3 then
            St.aiI = math.min(Cfg.AtkIntMax, St.aiI + 0.03)
        end
        return St.aiI * partyAdj
    end

    --============================================================
    -- TARGET
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
    -- F-MODE
    --============================================================
    local function resolveFMode()
        if St.fModeResolved then return end
        local mode = Cfg.FKeyMode or "auto"

        if mode == "auto" then
            local waited = 0
            while (not U.hrp() or St.cbt) and waited < 15 do
                task.wait(0.5); waited = waited + 0.5
            end
            if St.cbt then
                St.fModeResolved = true
                St.fIsBlock = false
                print("[Dingus][Atk] F-mode deferred — skill")
                return
            end
            -- Probe
            local h = U.hum()
            if h then
                local baseWS = h.WalkSpeed
                U.keyDown("F")
                task.wait(Cfg.BlockProbeWait)
                local isBlock = false
                local c = U.Lp.Character
                if c then
                    local ok1, v1 = pcall(function() return c:GetAttribute("IsBlocking") end)
                    if ok1 and v1 == true then isBlock = true end
                end
                U.keyUp("F")
                task.wait(0.05)
                if isBlock then
                    St.fIsBlock = true
                    print("[Dingus][Atk] F-mode = BLOCK")
                else
                    St.fIsBlock = false
                    print("[Dingus][Atk] F-mode = SKILL")
                end
            end
        elseif mode == "block" then
            St.fIsBlock = true
            print("[Dingus][Atk] F-mode = BLOCK (config)")
        elseif mode == "skill" then
            St.fIsBlock = false
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

        -- Refresh periodic state
        if now - (St.lStateRefresh or 0) > 2.0 then
            St.lStateRefresh = now
            St.breathFrac = readBreath() or 1.0
            St.partySize = readPartySize()
        end

        if h.Health < (St.lHp or 0) and now - (St.lHpT or 0) > 0.05 then
            St.lDmg = now
        end
        St.lHp = h.Health
        St.lHpT = now

        if now - St.lBrt > 2.5 then
            St.lBrt = now
            U.tap("L")
        end

        -- Retreat
        if St.rtr and hpFrac < Cfg.RetreatHP and not retreatRunning then
            local nearest = St.ths and St.ths[1]
            if nearest then startRetreat(nearest.rp.Position); return end
        end
        if retreatRunning then return end

        -- Target
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

        -- Threat tracking
        local imminent = (St.imm or 0) > 0
        local bossAttacking = false
        if D.isEnemyAttacking then
            bossAttacking = D.isEnemyAttacking(t)
        end
        if (imminent or bossAttacking) then
            St.threatPeak = now
        end

        --========================================================
        -- LONG RANGE · teleport first, dodge only if in-range
        --========================================================
        if dist > Cfg.AtkRange then
            St.cbtS = "TELEPORT"
            releaseBlock()
            teleportChase(t, tPos, myPos)
            fireRotation(t, hpFrac, now)
            return
        end

        --========================================================
        -- IN RANGE
        --========================================================
        inRangeChase(t, tPos, myPos, now)

        local blocking = D.isEnemyBlocking(t)
        local stunned = D.isEnemyStunned(t)
        local timeSinceThreat = now - (St.threatPeak or 0)

        --========================================================
        -- TELEGRAPH REACTION
        --========================================================
        local canDodge = (now - St.lDodge) > Cfg.DodgeCooldown
        local telegraphWindow = timeSinceThreat < Cfg.TelegraphWindow

        if (imminent or bossAttacking) and canDodge and telegraphWindow then
            St.cbtS = "DODGE"
            releaseBlock()
            tryDodge(now)
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
        -- PUNISH / BREAK / ATTACK
        --========================================================
        if stunned and St.stunPun then
            St.cbtS = "PUNISH"
            releaseBlock()
            if now - St.lAtk >= Cfg.StunAtkInt then
                St.lAtk = now
                strike(t, now)
            end
            fireRotation(t, hpFrac, now)
            return
        end

        if blocking then
            St.cbtS = "BREAK"
            releaseBlock()
            fireRotation(t, hpFrac, now)
            if now - St.lAtk > St.aiI * 1.2 then
                St.lAtk = now
                strike(t, now)
            end
            return
        end

        St.cbtS = "STRIKE"

        if shouldBlock and (now - St.lAtk < currentInterval() * 0.7) then
            St.cbtS = "BLOCK"
            holdBlock()
            fireRotation(t, hpFrac, now)
        else
            releaseBlock()
            if now - St.lAtk >= currentInterval() then
                St.lAtk = now
                strike(t, now)
            end
            fireRotation(t, hpFrac, now)
        end

        --========================================================
        -- ANTI-DETECTION BLEND
        --========================================================
        if now - St.lWalkBlend > Cfg.WalkBlendInterval then
            St.lWalkBlend = now
            local hh = U.hum()
            if hh then
                pcall(function()
                    hh:Move(Vector3.new(
                        (math.random() - 0.5) * 4, 0,
                        (math.random() - 0.5) * 4
                    ))
                end)
                task.spawn(function()
                    task.wait(0.3)
                    local hh2 = U.hum()
                    if hh2 then pcall(function() hh2:Move(Vector3.zero) end) end
                end)
            end
        end

        if now - St.lBlockBlend > Cfg.BlockBlendInterval and not shouldBlock then
            St.lBlockBlend = now
            if not St.blocking then
                holdBlock()
                task.spawn(function()
                    task.wait(0.2)
                    releaseBlock()
                end)
            end
        end
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
    -- PUBLIC
    --============================================================
    function A.forceScan()
        if D.invalidate then D.invalidate() end
        local list = D.scanBosses()
        print(string.format("[Dingus] force scan: %d bosses", #list))
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
        }
    end

    function A.telemetry()
        return {
            teleports   = St.teleCount or 0,
            teleFails   = St.teleFail or 0,
            dodges      = St.dodgeCount or 0,
            gcdHits     = St.gcdHits or 0,
            gcdMisses   = St.gcdMisses or 0,
            gcdReady    = U.clock() >= St.gcdUntil,
            gcdRemaining = math.max(0, St.gcdUntil - U.clock()),
            comboIndex  = St.comboIndex or 0,
            comboTarget = St.comboTargetName,
            breathFrac  = St.breathFrac or 1.0,
            partySize   = St.partySize or 1,
        }
    end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function() releaseBlock() end)

    print("[Dingus][attack] v7 initialized · GCD-aware · chained M1/M2")
end

return A
