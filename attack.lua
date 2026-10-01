--[[
    Dingus-Slayer · attack.lua v21
    Movement fix: throttled MoveTo + directional Move every tick.
    Range-based behavior. No hover.
]]--

local A = {}

function A.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local D = Ctx.Detect
    local Lists = Ctx.Lists

    St.rHt = {}
    St.aiI = Cfg.AtkInterval
    St.skCd = { 0, 0, 0, 0, 0 }
    St.lMove = 0

    local function getEquipped()
        local c = U.Lp.Character
        if not c then return nil end
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and not Lists.isCrow(t.Name) then return t end
        end
    end

    local function getAllTools()
        local l = {}
        local c = U.Lp.Character
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") then table.insert(l, t) end
            end
        end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") then table.insert(l, t) end
            end
        end
        return l
    end

    function A.equipWeapon()
        local now = U.clock()
        if now - St.lEqp < 1.0 then return end
        St.lEqp = now
        local h = U.hum()
        if not h then return end
        local tools = getAllTools()
        local eq = getEquipped()
        if eq and Lists.isWeapon(eq.Name) then
            St.eq = eq.Name
            return
        end
        for i = 1, #tools do
            local t = tools[i]
            if t ~= eq and Lists.isWeapon(t.Name) then
                if eq then
                    pcall(function() h:UnequipTools() end)
                    task.wait(0.1)
                end
                pcall(function() h:EquipTool(t) end)
                St.eq = t.Name
                St.swp = St.swp + 1
                return
            end
        end
    end

    local function fireSkill(i)
        local now = U.clock()
        if now < St.skCd[i] then return false end
        local keys = { "Z", "X", "C", "V", "B" }
        local cds = { 1.2, 2.0, 2.8, 3.6, 6.0 }
        U.tap(keys[i])
        St.skCd[i] = now + cds[i]
        St.skC = St.skC + 1
        return true
    end

    function A.fireRotation()
        for _, i in ipairs({ 2, 1, 3, 4, 5 }) do
            if fireSkill(i) then return true end
        end
    end

    local function adaptiveInterval()
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

    function A.attackTarget(t)
        St.aAt = St.aAt + 1
        local before = t.hm.Health
        U.m1()
        local eq = getEquipped()
        if eq then pcall(function() eq:Activate() end) end
        task.spawn(function()
            task.wait(0.2)
            if t and t.hm and t.hm.Parent then
                if t.hm.Health < before then
                    St.aHi = St.aHi + 1
                    table.insert(St.rHt, true)
                else
                    St.aMs = St.aMs + 1
                    table.insert(St.rHt, false)
                end
                if #St.rHt > 12 then table.remove(St.rHt, 1) end
            end
        end)
    end

    local function face(r, x2)
        pcall(function()
            r.CFrame = CFrame.new(r.Position, Vector3.new(x2.Position.X, r.Position.Y, x2.Position.Z))
        end)
    end

    -- Movement: MoveTo throttled + Move every tick
    local function moveTo(h, r, targetPos)
        local now = U.clock()
        local myPos = r.Position
        local dir = targetPos - myPos
        dir = Vector3.new(dir.X, 0, dir.Z)

        if dir.Magnitude < 0.5 then return end

        local dirUnit = dir.Unit

        -- Persistent push every tick
        pcall(function() h:Move(dirUnit) end)
        pcall(function() h.WalkToPoint = targetPos end)

        -- Throttled MoveTo for pathfinding
        if now - (St.lMove or 0) > 0.25 then
            St.lMove = now
            pcall(function() h:MoveTo(targetPos) end)
        end
    end

    function A.combatTick()
        if not St.cbt then St.cbtS = "IDLE"; return end

        local h = U.hum()
        local r = U.hrp()
        if not h or not r then St.cbtS = "NO_CHAR"; return end
        if h.Health <= 0 then St.cbtS = "DEAD"; return end

        local now = U.clock()
        local hpFrac = h.Health / h.MaxHealth

        A.equipWeapon()
        U.groundState()

        if h.Health < (St.lHp or 0) and now - (St.lHpT or 0) > 0.05 then
            St.lDmg = now
        end
        St.lHp = h.Health
        St.lHpT = now

        if now - (St.lBrt or 0) > 2.5 then
            St.lBrt = now
            U.tap("L")
        end

        -- Retreat
        if St.rtr and hpFrac < Cfg.RetreatHP then
            local nearest = St.ths and St.ths[1]
            if nearest then
                local d = r.Position - nearest.rp.Position
                local flat = Vector3.new(d.X, 0, d.Z)
                if flat.Magnitude < 0.5 then flat = Vector3.new(1, 0, 0) end
                St.tgt = nil
                St.cbtS = "RETREAT"
                St.rtrC = St.rtrC + 1
                if Ctx.Spoof and Ctx.Spoof.surfaceUp then Ctx.Spoof.surfaceUp() end
                task.spawn(function()
                    U.tap("Q")
                    task.wait(0.3)
                    local hh = U.hum()
                    if hh then
                        h.WalkSpeed = Cfg.RunSpeed
                        pcall(hh.MoveTo, hh, r.Position + flat.Unit * 60)
                    end
                    local dl = U.clock() + 4
                    while U.clock() < dl do
                        local x = U.hum()
                        if not x or x.Health / x.MaxHealth > 0.65 then break end
                        task.wait(0.3)
                    end
                    St.cbtS = "IDLE"
                end)
                return
            end
        end

        if St.cbtS == "RETREAT" then return end

        -- Target acquisition
        if not St.tgt or not St.tgt.ch.Parent or St.tgt.hm.Health <= 0 then
            if St.tgt then
                St.kll = St.kll + 1
                St.bKll = St.bKll + 1
                print(string.format("[Dingus] killed %s (%d)", St.tgt.ch.Name, St.bKll))
                St.tgt = nil
                St.lScn = 0
            end
            local list = D.scanBosses()
            St.tgt = list[1]
            if not St.tgt then St.cbtS = "IDLE"; return end
            St.cbtS = "ENGAGE"
            print(string.format("[Dingus] target %s @%.0f", St.tgt.ch.Name, St.tgt.d))
        end

        local t = St.tgt
        local x2 = t.ch:FindFirstChild("HumanoidRootPart")
        if not x2 then St.tgt = nil; return end

        local dist = U.xzDist(r.Position, x2.Position)
        t.d = dist

        local eBlk = D.isEnemyBlocking(t)
        local eSt = D.isEnemyStunned(t)

        -- FAR: > 30 studs
        if dist > 30 then
            St.cbtS = "APPROACH_FAR"
            h.WalkSpeed = Cfg.RunSpeed
            moveTo(h, r, x2.Position)
            face(r, x2)
            if St.skl and now - (St.lSkl or 0) > 2.0 then
                St.lSkl = now
                A.fireRotation()
            end
            return
        end

        -- MID: 8-30 studs
        if dist > 8 then
            if eBlk or eSt then
                St.cbtS = "CLOSE_SLOW"
                h.WalkSpeed = Cfg.CloseInSpeed
                moveTo(h, r, x2.Position)
                face(r, x2)
                if St.skl and now - (St.lSkl or 0) > 1.0 then
                    St.lSkl = now
                    A.fireRotation()
                end
                return
            end
            St.cbtS = "APPROACH"
            h.WalkSpeed = Cfg.RunSpeed
            moveTo(h, r, x2.Position)
            face(r, x2)
            if St.skl and now - (St.lSkl or 0) > 1.6 then
                St.lSkl = now
                A.fireRotation()
            end
            return
        end

        -- CLOSE: < 8 studs
        St.cbtS = eBlk and "BREAK_BLOCK" or (eSt and "PUNISH" or "ATTACK")
        h.WalkSpeed = 16
        face(r, x2)

        local interval = eSt and Cfg.StunAtkInt or adaptiveInterval()
        if now - St.lAtk >= interval then
            St.lAtk = now
            A.attackTarget(t)
        end

        if St.skl and now - (St.lSkl or 0) > 1.6 then
            St.lSkl = now
            A.fireRotation()
        end
    end
end

return A
