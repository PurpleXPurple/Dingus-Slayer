local A = {}

function A.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local D = Ctx.Detect
    local L = Ctx.Lists
    local RunService = game:GetService("RunService")

    St.rHt = {}
    St.skCd = { 0, 0, 0, 0, 0 }
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

    local SK_KEYS = { "Z", "X", "C", "V", "B" }
    local SK_CDS  = { 1.2, 2.0, 2.8, 3.6, 6.0 }
    local ROTATION = { 2, 1, 3, 4, 5 }

    local COMBO_AIR       = { "m1", "m2", "m1", "m2", "m1" }
    local COMBO_SPECIAL_A = { "m2", "m2", "m1", "m2", "m1" }
    local COMBO_SPECIAL_B = { "m1", "m1", "m2", "m1", "m2" }
    local COMBO_RESET_TIME = 1.2

    local function scrubMovers()
        local r = U.hrp()
        if not r then return 0 end
        local n = 0
        for _, c in ipairs(r:GetChildren()) do
            if c:IsA("BodyPosition") or c:IsA("BodyVelocity")
                or c:IsA("BodyGyro") or c:IsA("BodyForce")
                or c:IsA("LinearVelocity") or c:IsA("AlignOrientation") then
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
    end)

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
        local now = U.clock()
        if now - St.lEqp < 1.5 then return end
        St.lEqp = now
        local h = U.hum(); if not h then return end
        local current = equippedTool()
        if current and L.isWeapon(current.Name) then
            St.eq = current.Name
            return
        end
        for _, t in ipairs(inventoryTools()) do
            if L.isWeapon(t.Name) then
                if current then
                    pcall(function() h:UnequipTools() end)
                    task.wait(0.08)
                end
                pcall(function() h:EquipTool(t) end)
                St.eq = t.Name
                print("[Dingus] equipped " .. t.Name)
                return
            end
        end
    end

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
            if fireSkill(i) then return true end
        end
    end

    local function m1() U.m1() end

    local function m2()
        if mouse2click then
            pcall(mouse2click)
        elseif VIM then
            pcall(function() VIM:SendMouseButtonEvent(0, 0, 1, true, game, 0) end)
            task.wait(0.03)
            pcall(function() VIM:SendMouseButtonEvent(0, 0, 1, false, game, 0) end)
        end
    end

    local function strike(t)
        St.aAt = (St.aAt or 0) + 1
        local hpBefore = t.hm.Health

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
            r.CFrame = CFrame.new(r.Position, Vector3.new(targetPos.X, r.Position.Y, targetPos.Z))
        end)
    end

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
                    r.CFrame = CFrame.new(newPos, Vector3.new(targetPos.X, newPos.Y, targetPos.Z))
                end)
                St.lastPos = newPos
                St.lastPosTime = now
                St.stuckWarnings = St.stuckWarnings + 1
            end
        end

        if now - St.lMoveLog > 2.0 then
            St.lMoveLog = now
            print(string.format("[Dingus][Move] chasing %s @%.0f", St.tgt.ch.Name, dist))
        end
    end

    RunService.Heartbeat:Connect(function(dt)
        pcall(movementTick, dt)
    end)

    local retreatRunning = false
    local function startRetreat(from)
        if retreatRunning then return end
        retreatRunning = true
        St.rtrC = (St.rtrC or 0) + 1
        St.cbtS = "RETREAT"
        if Ctx.Fly and Ctx.Fly.stop then Ctx.Fly.stop() end
        if Ctx.Spoof and Ctx.Spoof.surfaceUp then pcall(Ctx.Spoof.surfaceUp) end
        task.spawn(function()
            U.tap("Q"); task.wait(0.25)
            local r = U.hrp(); local h = U.hum()
            if not r or not h then retreatRunning = false; St.cbtS = "IDLE"; return end
            local away = r.Position - from
            local flat = Vector3.new(away.X, 0, away.Z)
            if flat.Magnitude < 0.5 then flat = Vector3.new(1, 0, 0) end
            h.WalkSpeed = Cfg.RunSpeed
            local deadline = U.clock() + Cfg.RetreatDelay
            while U.clock() < deadline do
                local hh = U.hum()
                if not hh then break end
                if hh.Health / hh.MaxHealth > Cfg.RetreatClearHP then break end
                h:Move(flat.Unit)
                task.wait(0.05)
            end
            retreatRunning = false
            St.tgt = nil
            if D.invalidate then D.invalidate() end
        end)
    end

    local function acquireTarget()
        local tgt, kind = D.pickTarget()
        St.tgt = tgt
        St.tgtKind = kind
        if tgt then
            print(string.format("[Dingus] target %s (%s) @%.0f", tgt.ch.Name, kind, tgt.d))
        end
        return tgt
    end

    function A.combatTick()
        if not St.cbt then
            St.cbtS = "IDLE"
            if Ctx.Fly and Ctx.Fly.active then Ctx.Fly.stop() end
            return
        end

        local h = U.hum()
        local r = U.hrp()
        if not h or not r then St.cbtS = "NO_CHAR"; return end
        if h.Health <= 0 then
            St.cbtS = "DEAD"
            if Ctx.Fly and Ctx.Fly.active then Ctx.Fly.stop() end
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
                print(string.format("[Dingus] killed %s (%d)", St.tgt.ch.Name, St.bKll))
                St.tgt = nil
                if Ctx.Fly and Ctx.Fly.active then Ctx.Fly.stop() end
                if D.invalidate then D.invalidate() end
            end
            acquireTarget()
            if not St.tgt then
                St.cbtS = "IDLE"
                if Ctx.Fly and Ctx.Fly.active then Ctx.Fly.stop() end
                return
            end
        end

        local t = St.tgt
        local tPos = t.ch:FindFirstChild("HumanoidRootPart")
        if not tPos then St.tgt = nil; return end

        local dist = U.xzDist(r.Position, tPos.Position)
        t.d = dist

        if dist > Cfg.AtkRange + 4 then
            St.cbtS = "FLY"
            if Ctx.Fly and not Ctx.Fly.active then
                Ctx.Fly.start()
            end
            if Ctx.Fly and Ctx.Fly.active then
                return
            end
            faceTarget(r, tPos.Position)
            if St.skl and now - St.lSkl > 2.0 then
                St.lSkl = now
                fireRotation()
            end
            return
        end

        if Ctx.Fly and Ctx.Fly.active then
            Ctx.Fly.stop()
            task.wait(0.15)
        end

        local blocking = D.isEnemyBlocking(t)
        local stunned = D.isEnemyStunned(t)

        faceTarget(r, tPos.Position)

        if stunned and St.stunPun then
            St.cbtS = "PUNISH"
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
        if now - St.lAtk >= currentInterval() then
            St.lAtk = now
            strike(t)
        end
        if St.skl and now - St.lSkl > 1.6 then
            St.lSkl = now
            fireRotation()
        end
    end

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

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function()
        if Ctx.Fly and Ctx.Fly.stop then Ctx.Fly.stop() end
    end)

    print("[Dingus][attack] initialized")
end

return A
