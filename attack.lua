local A = {}

function A.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local D = Ctx.Detect
    local L = Ctx.Lists
    local RunService = game:GetService("RunService")

    St.rHt = {}
    St.skCd = { 0, 0, 0, 0, 0, 0 }        -- v3: 6 entries
    St.aiI = Cfg.AtkInterval
    St.lAtk = 0
    St.lSkl = 0
    St.lEqp = 0
    St.lBrt = 0
    St.lFac = 0
    St.lMoveLog = 0
    St.eq = "none"
    St.lTl = false
    St.cbtS = "IDLE"
    St.lastPos = nil
    St.lastPosTime = 0
    St.stuckWarnings = 0
    St.lastComboTime = 0
    St.comboIndex = 0
    St.swapPending = false
    St.flyFailLogged = false

    -- v3 F-key state
    St.fIsBlock       = false
    St.fModeResolved  = false
    St.blocking       = false
    St.blockHoldUntil = 0

    local SK_KEYS  = Cfg.SkillKeys or { "F", "Z", "X", "C", "V", "B" }
    local SK_CDS   = Cfg.SkillCooldowns or { 0.5, 1.2, 2.0, 2.8, 3.6, 6.0 }
    local ROTATION = Cfg.RotationOrder or { 2, 3, 4, 5, 6 }

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
                c:Destroy()
                n = n + 1
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
    -- Runs once at boot (deferred). Decides whether F is block or
    -- skill. Detection signals, in priority order:
    --   1. Character/Humanoid attribute "IsBlocking" set during tap
    --   2. Animation track named block/guard/parry during tap
    --   3. Block bar value drop (SHCS.Blocking or similar)
    --   4. WalkSpeed clamped during tap
    -- If none fire, defaults to "skill".
    --============================================================
    local function readBlockAttribute()
        local c = U.Lp.Character
        if not c then return false end
        local h = U.hum()
        local ok1, v1 = pcall(function() return c:GetAttribute("IsBlocking") end)
        if ok1 and v1 == true then return true end
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
        if St.cbt then return nil end  -- defer if combat active

        -- Baseline WalkSpeed for signal 4
        local baseWS = h.WalkSpeed

        U.keyDown("F")
        local waitT = Cfg.BlockProbeWait or 0.15
        task.wait(waitT)

        local isBlock = false
        if readBlockAttribute() then isBlock = true end
        if not isBlock and readBlockAnim() then isBlock = true end
        if not isBlock then
            local h2 = U.hum()
            if h2 and h2.WalkSpeed < baseWS - 4 then
                isBlock = true
            end
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
    -- WEAPON EQUIP
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
            -- Skip F if we've determined it's block.
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

        -- Release block before striking. Holding F while clicking M1
        -- usually cancels the attack in most action games.
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
        for i = 1, #St.rHt do if St.rHt[i] then hits = hits + 1 end end
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
    -- FLY TRANSITION
    --============================================================
    local function tryEngageFly()
        if not Ctx.Fly then return false end
        if Ctx.Fly.active then return true end
        if type(Ctx.Fly.start) ~= "function" then return false end

        local ok, err = pcall(Ctx.Fly.start)
        if not ok then
            if not St.flyFailLogged then
                St.flyFailLogged = true
                print("[Dingus][Atk] fly start raised: " .. tostring(err))
            end
            return false
        end
        if not Ctx.Fly.active then
            if not St.flyFailLogged then
                St.flyFailLogged = true
                print("[Dingus][Atk] fly start returned without activating")
            end
            return false
        end
        St.flyFailLogged = false
        return true
    end

    local function tryDisengageFly()
        if not Ctx.Fly or not Ctx.Fly.active then return end
        if type(Ctx.Fly.stop) ~= "function" then return end
        pcall(Ctx.Fly.stop)
    end

    local function groundChase(r, tPos)
        local h = U.hum()
        if not h then return end
        local flat = Vector3.new(tPos.Position.X - r.Position.X, 0,
                                tPos.Position.Z - r.Position.Z)
        if flat.Magnitude < 0.1 then return end
        h.WalkSpeed = Cfg.RunSpeed
        h:Move(flat.Unit)
    end

    --============================================================
    -- MOVEMENT TICK
    --============================================================
    local function movementTick(dt)
        if not St.cbt then return end
        if St.cbtS == "RETREAT" then return end
        if St.FlyActive then return end
        if not St.tgt or not St.tgt.ch.Parent or St.tgt.hm.Health <= 0 then return end

        local h = U.hum()
        local r = U.hrp()
        if not h or not r then return end

        local targetHRP = St.tgt.ch:FindFirstChild("HumanoidRootPart")
        if not targetHRP then return end

        local myPos = r.Position
        local targetPos = targetHRP.Position
        local dist = U.xzDist(myPos, targetPos)

        if dist <= Cfg.AtkRange then
            h:Move(Vector3.zero)
            return
        end

        local dir = targetPos - myPos
        local flatDir = Vector3.new(dir.X, 0, dir.Z)
        if flatDir.Magnitude < 0.1 then return end
        flatDir = flatDir.Unit

        h.WalkSpeed = Cfg.RunSpeed
        h:Move(flatDir)

        local now = U.clock()
        if not St.lastPos then
            St.lastPos = myPos
            St.lastPosTime = now
        else
            local moved = (myPos - St.lastPos).Magnitude
            if moved > 0.4 then
                St.lastPos = myPos
                St.lastPosTime = now
            elseif now - St.lastPosTime > 1.2 then
                local nudge = flatDir * 2.5
                local newPos = myPos + nudge
                pcall(function()
                    r.CFrame = CFrame.new(newPos,
                        Vector3.new(targetPos.X, newPos.Y, targetPos.Z))
                end)
                St.lastPos = newPos
                St.lastPosTime = now
                St.stuckWarnings = St.stuckWarnings + 1
            end
        end

        if now - St.lMoveLog > 2.0 then
            St.lMoveLog = now
            print(string.format("[Dingus][Move] chasing %s @%.0f",
                St.tgt.ch.Name, dist))
        end
    end

    RunService.Heartbeat:Connect(function(dt)
        pcall(movementTick, dt)
    end)

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
        tryDisengageFly()
        if Ctx.Spoof and Ctx.Spoof.surfaceUp then pcall(Ctx.Spoof.surfaceUp) end

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
            local deadline = startT + Cfg.RetreatDelay
            local hardCap = startT + 2.5
            local lastHp = h.Health
            local lastDamageT = startT
            local clearSince = nil

            while U.clock() < deadline do
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

                if St.zn == 0 then
                    if not clearSince then clearSince = U.clock() end
                    if U.clock() - clearSince > 0.4 then break end
                else
                    clearSince = nil
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
    -- F-KEY RESOLUTION (once, deferred)
    --============================================================
    local function resolveFMode()
        if St.fModeResolved then return end
        local mode = Cfg.FKeyMode or "auto"

        if mode == "auto" then
            -- Wait for stable character + no combat
            local waited = 0
            while (not U.hrp() or St.cbt) and waited < 15 do
                task.wait(0.5)
                waited = waited + 0.5
            end
            if St.cbt then
                St.fModeResolved = true
                St.fIsBlock = false
                print("[Dingus][Atk] F-mode deferred (combat active) — default skill")
                return
            end

            local result = probeFKey()
            if result == "block" then
                St.fIsBlock = true
                Cfg.RotationOrder = { 2, 3, 4, 5, 6 }
                ROTATION = Cfg.RotationOrder
                print("[Dingus][Atk] F-mode = BLOCK (probe: attribute/anim/ws)")
            else
                St.fIsBlock = false
                Cfg.RotationOrder = { 2, 3, 1, 4, 5, 6 }
                ROTATION = Cfg.RotationOrder
                print("[Dingus][Atk] F-mode = SKILL (probe: no block signal)")
            end
        elseif mode == "block" then
            St.fIsBlock = true
            Cfg.RotationOrder = { 2, 3, 4, 5, 6 }
            ROTATION = Cfg.RotationOrder
            print("[Dingus][Atk] F-mode = BLOCK (config override)")
        elseif mode == "skill" then
            St.fIsBlock = false
            Cfg.RotationOrder = { 2, 3, 1, 4, 5, 6 }
            ROTATION = Cfg.RotationOrder
            print("[Dingus][Atk] F-mode = SKILL (config override)")
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
            tryDisengageFly()
            return
        end

        local h = U.hum()
        local r = U.hrp()
        if not h or not r then St.cbtS = "NO_CHAR"; return end
        if h.Health <= 0 then
            St.cbtS = "DEAD"
            releaseBlock()
            tryDisengageFly()
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
                tryDisengageFly()
                if D.invalidate then D.invalidate() end
            end
            acquireTarget()
            if not St.tgt then
                St.cbtS = "IDLE"
                releaseBlock()
                tryDisengageFly()
                return
            end
        end

        local t = St.tgt
        local tPos = t.ch:FindFirstChild("HumanoidRootPart")
        if not tPos then St.tgt = nil; return end

        local dist = U.xzDist(r.Position, tPos.Position)
        t.d = dist

        --========================================================
        -- LONG RANGE
        --========================================================
        if dist > Cfg.AtkRange + 4 then
            if tryEngageFly() then
                St.cbtS = "FLY"
                releaseBlock()  -- no block while flying
                if St.skl and now - St.lSkl > 2.0 then
                    St.lSkl = now
                    fireRotation()
                end
                return
            end
            St.cbtS = "APPROACH"
            releaseBlock()
            faceTarget(r, tPos.Position)
            groundChase(r, tPos)
            if St.skl and now - St.lSkl > 2.0 then
                St.lSkl = now
                fireRotation()
            end
            return
        end

        --========================================================
        -- IN RANGE
        --========================================================
        if Ctx.Fly and Ctx.Fly.active then
            tryDisengageFly()
        end

        local blocking = D.isEnemyBlocking(t)
        local stunned = D.isEnemyStunned(t)

        faceTarget(r, tPos.Position)

        --========================================================
        -- AUTO-BLOCK (v3)
        -- Only active when F is block and AutoBlock is on.
        -- Hold F when threat is imminent and we aren't attacking.
        --========================================================
        local shouldBlock = false
        if St.fIsBlock and Cfg.AutoBlock then
            local threatNow = (St.imm or 0) > 0
            if threatNow then
                St.blockHoldUntil = now + (Cfg.BlockHoldTTL or 0.6)
            end
            shouldBlock = threatNow or (now < (St.blockHoldUntil or 0))
        end

        --========================================================
        -- STUN PUNISH
        --========================================================
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

        --========================================================
        -- ENEMY BLOCKING · BREAK
        --========================================================
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

        --========================================================
        -- NORMAL ATTACK · BLOCK HELD WHEN NOT ATTACKING
        --========================================================
        St.cbtS = "ATTACK"

        -- If we should block and aren't ready to attack, hold F.
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
            print(string.format("  · %s @%.0f studs", list[i].ch.Name, list[i].d))
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

    -- Expose F-mode for GUI/debug
    function A.fModeInfo()
        return {
            resolved = St.fModeResolved,
            isBlock = St.fIsBlock,
            blocking = St.blocking,
            rotation = Cfg.RotationOrder,
        }
    end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function()
        releaseBlock()
        tryDisengageFly()
    end)

    print("[Dingus][attack] v3 initialized")
end

return A
