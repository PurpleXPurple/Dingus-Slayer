local A = {}

function A.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local D = Ctx.Detect

    St.rHt = {}
    St.aiI = Cfg.AtkIntBase
    St.skCd = { 0, 0, 0, 0, 0 }
    St.lAtk = 0
    St.lSkl = 0

    local function getEquipped()
        local c = U.Lp.Character
        if not c then return nil end
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and not U.isCrowName(t.Name) then return t end
        end
    end

    local function getAllTools()
        local l = {}
        local c = U.Lp.Character
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") then l[#l+1] = t end
            end
        end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") then l[#l+1] = t end
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
        if not St.lTl and #tools > 0 then
            St.lTl = true
            local names = {}
            for i = 1, #tools do names[i] = tools[i].Name end
            if Ctx.Log then Ctx.Log("EQUIP", "inv: " .. table.concat(names, ", ")) end
        end
        local eq = getEquipped()
        if eq and U.isWeaponName(eq.Name, Cfg.WeaponList, Cfg.NoWeaponList) then
            St.eq = eq.Name
            return
        end
        for i = 1, #tools do
            local t = tools[i]
            if t ~= eq and U.isWeaponName(t.Name, Cfg.WeaponList, Cfg.NoWeaponList) then
                if eq then
                    pcall(function() h:UnequipTools() end)
                    task.wait(0.1)
                end
                pcall(function() h:EquipTool(t) end)
                St.eq = t.Name
                St.swp = (St.swp or 0) + 1
                if Ctx.Log then Ctx.Log("EQUIP", "eq " .. t.Name) end
                return
            end
        end
        St.eq = "unarmed"
    end

    local function fireSkill(i)
        local now = U.clock()
        if now < St.skCd[i] then return false end
        local keyName = Cfg.SkillKeys[i]
        U.tap(U.VK[keyName], U.Keys[keyName])
        St.skCd[i] = now + Cfg.SkillCooldowns[i]
        St.skC = (St.skC or 0) + 1
        return true
    end

    function A.fireRotation()
        for _, i in ipairs(Cfg.RotationOrder) do
            if fireSkill(i) then return true end
        end
        return false
    end

    function A.adaptiveInterval()
        local h = St.rHt
        if #h < 5 then return St.aiI end
        local hits = 0
        for i = 1, #h do if h[i] then hits = hits + 1 end end
        local rate = hits / #h
        if rate > 0.7 then
            St.aiI = math.max(Cfg.AtkIntMin, St.aiI - 0.02)
        elseif rate < 0.3 then
            St.aiI = math.min(Cfg.AtkIntMax, St.aiI + 0.02)
        end
        return St.aiI
    end

    function A.attackTarget(t)
        St.aAt = (St.aAt or 0) + 1
        local before = t.hm.Health
        U.m1()
        local eq = getEquipped()
        if eq then pcall(function() eq:Activate() end) end
        task.spawn(function()
            task.wait(0.2)
            if t and t.hm and t.hm.Parent then
                if t.hm.Health < before then
                    St.aHi = (St.aHi or 0) + 1
                    table.insert(St.rHt, true)
                else
                    St.aMs = (St.aMs or 0) + 1
                    table.insert(St.rHt, false)
                end
                if #St.rHt > Cfg.HitWindow then table.remove(St.rHt, 1) end
            end
        end)
    end

    function A.combatTick()
        if not St.cbt then
            if St.hvB then St.hvB:Destroy(); St.hvB = nil end
            St.cbtS = "IDLE"
            return
        end
        local h = U.hum()
        local r = U.hrp()
        if not h or not r then
            St.cbtS = "NO_CHAR"
            return
        end

        local now = U.clock()
        local hf = h.Health / h.MaxHealth

        A.equipWeapon()
        if not St.uGs then U.groundState() end

        if h.Health < (St.lHp or 0) and now - (St.lHpT or 0) > 0.05 then
            St.lDmg = now
        end
        St.lHp = h.Health
        St.lHpT = now

        if not St.uGs and now - (St.lBrt or 0) > 2.5 then
            St.lBrt = now
            U.tap(U.VK.L, U.Keys.L)
        end

        if St.uGs then
            Ctx.Spoof.checkUG()
            St.cbtS = "UG"
            return
        end

        if St.cbtS == "RETREAT" then return end

        if now - (St.lDmg or 0) < 0.5 and hf < Cfg.UGTrigHP then
            Ctx.Spoof.goUnderground()
            return
        end

        if St.rtr and hf < Cfg.RetreatHP then
            local ths = St.ths or {}
            local nearest = ths[1]
            if nearest then
                local d = r.Position - nearest.rp.Position
                local flat = Vector3.new(d.X, 0, d.Z)
                if flat.Magnitude < 0.5 then flat = Vector3.new(1, 0, 0) end
                St.tgt = nil
                St.cbtS = "RETREAT"
                St.rtrC = (St.rtrC or 0) + 1
                if St.hvB then St.hvB:Destroy(); St.hvB = nil end
                if Ctx.Log then Ctx.Log("RETREAT", "start") end
                task.spawn(function()
                    U.tap(U.VK.Q, U.Keys.Q)
                    task.wait(0.3)
                    local hh = U.hum()
                    if hh then pcall(hh.MoveTo, hh, r.Position + flat.Unit * 60) end
                    local dl = U.clock() + 4
                    while U.clock() < dl do
                        local x = U.hum()
                        if not x or x.Health / x.MaxHealth > 0.65 then break end
                        task.wait(0.3)
                    end
                    if Ctx.Log then Ctx.Log("RETREAT", "end") end
                    St.cbtS = "IDLE"
                end)
                return
            end
        end

        if not St.tgt or not St.tgt.ch.Parent or St.tgt.hm.Health <= 0 then
            if St.tgt then
                St.kll = (St.kll or 0) + 1
                St.bKll = (St.bKll or 0) + 1
                if Ctx.Log then Ctx.Log("KILL", "boss " .. St.tgt.ch.Name .. " (" .. St.bKll .. ")") end
                St.tgt = nil
                St.lScn = 0
            end
            local list = D.scanBosses()
            St.tgt = list[1]
            if not St.tgt then St.cbtS = "IDLE"; return end
            St.cbtS = "ENGAGE"
            if Ctx.Log then Ctx.Log("TARGET", "boss: " .. St.tgt.ch.Name .. " @" .. U.round(St.tgt.d)) end
        end

        local t = St.tgt
        local r2 = U.hrp()
        if not r2 then return end
        local x2 = t.ch:FindFirstChild("HumanoidRootPart")
        if not x2 then St.tgt = nil; return end

        local xd = U.xzDist(r2.Position, x2.Position)

        if xd > Cfg.AtkRange then
            St.cbtS = "ENGAGE"
            local d = Vector3.new(x2.Position.X, x2.Position.Y + Cfg.HoverHeight, x2.Position.Z)
            local dl = d - r2.Position
            if dl.Magnitude > 0.1 then
                local s = dl.Unit * math.min(dl.Magnitude, Cfg.MaxMoveTick)
                r2.CFrame = CFrame.new(r2.Position + s, Vector3.new(d.X, r2.Position.Y, d.Z))
                if not St.hvB then
                    St.hvB = Instance.new("BodyPosition")
                    St.hvB.Name = "PS2_HoverBP"
                    St.hvB.MaxForce = Vector3.new(4e4, 4e4, 4e4)
                    St.hvB.P = Cfg.HoverP
                    St.hvB.D = Cfg.HoverD
                    St.hvB.Parent = r2
                end
                St.hvB.Position = r2.Position
            end
            if now - (St.lFac or 0) > Cfg.FaceTTL then
                St.lFac = now
                pcall(function()
                    r2.CFrame = CFrame.new(r2.Position, Vector3.new(x2.Position.X, r2.Position.Y, x2.Position.Z))
                end)
            end
            return
        end

        St.cbtS = "ATTACK"

        if St.hvr then
            if not St.hvB then
                St.hvB = Instance.new("BodyPosition")
                St.hvB.Name = "PS2_HoverBP"
                St.hvB.MaxForce = Vector3.new(4e4, 4e4, 4e4)
                St.hvB.P = Cfg.HoverP
                St.hvB.D = Cfg.HoverD
                St.hvB.Parent = r2
            end
            if now - (St.lHvr or 0) > Cfg.HoverTTL then
                St.lHvr = now
                St.hvB.Position = Vector3.new(x2.Position.X, x2.Position.Y + Cfg.HoverHeight, x2.Position.Z)
            end
        end

        if now - (St.lFac or 0) > Cfg.FaceTTL then
            St.lFac = now
            pcall(function()
                r2.CFrame = CFrame.new(r2.Position, Vector3.new(x2.Position.X, r2.Position.Y, x2.Position.Z))
                local cp = workspace.CurrentCamera.CFrame.Position
                local l = x2.Position - cp
                if l.Magnitude > 0.1 then
                    workspace.CurrentCamera.CFrame = CFrame.new(cp, cp + l.Unit)
                end
            end)
        end

        local eBlk = D.isEnemyBlocking(t)
        local eSt = D.isEnemyStunned(t)

        if eBlk then
            St.cbtS = "BREAK_BLOCK"
            if now - St.lSkl > 0.5 then
                St.lSkl = now
                A.fireRotation()
            end
            if now - St.lAtk > St.aiI * 1.5 then
                St.lAtk = now
                A.attackTarget(t)
            end
            return
        end

        if eSt and St.stunPun then
            St.cbtS = "PUNISH"
            if now - St.lAtk > Cfg.StunAtkInt then
                St.lAtk = now
                A.attackTarget(t)
            end
            if St.skl and now - St.lSkl > 0.3 then
                St.lSkl = now
                A.fireRotation()
            end
            return
        end

        St.cbtS = "ATTACK"
        if now - St.lAtk >= A.adaptiveInterval() then
            St.lAtk = now
            A.attackTarget(t)
        end
        if St.skl and now - St.lSkl > 1.6 then
            St.lSkl = now
            A.fireRotation()
        end
    end
end

return A
