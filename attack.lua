--[[
    Dingus-Slayer · attack.lua v25
    Hover-behind positioning. BodyPosition locks character 8 studs behind boss.
    Block in PS2 is directional — behind = boss can't block.
]]--

local A = {}

function A.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local D = Ctx.Detect
    local L = Ctx.Lists

    -- State
    St.rHt = St.rHt or {}
    St.skCd = St.skCd or { 0, 0, 0, 0, 0 }
    St.aiI = St.aiI or Cfg.AtkInterval
    St.lAtk = 0
    St.lSkl = 0
    St.lEqp = 0
    St.lMove = 0
    St.lBrt = 0
    St.lFac = 0
    St.lHover = 0
    St.lHoverRecalc = 0
    St.userMoveUntil = 0
    St.eq = St.eq or "none"
    St.lTl = false
    St.cbtS = St.cbtS or "IDLE"
    St.hoverBp = nil
    St.hoverAtt = nil
    St.hoverActive = false

    local SK_KEYS = { "Z", "X", "C", "V", "B" }
    local SK_CDS  = { 1.2, 2.0, 2.8, 3.6, 6.0 }
    local ROTATION = { 2, 1, 3, 4, 5 }

    local UIS = game:GetService("UserInputService")

    --============================================================
    -- USER INPUT AWARENESS
    --============================================================
    local moveKeys = {
        [Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true,
        [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
        [Enum.KeyCode.Space] = true,
    }
    UIS.InputBegan:Connect(function(i, gp)
        if gp then return end
        if moveKeys[i.KeyCode] then St.userMoveUntil = U.clock() + 1.5 end
    end)
    local function canAutoMove() return U.clock() > St.userMoveUntil end

    --============================================================
    -- HOVER SYSTEM
    --============================================================
    local function scrubHover()
        local r = U.hrp()
        if not r then return end
        for _, c in ipairs(r:GetChildren()) do
            if c.Name == "DingusHoverBP" or c.Name == "DingusHoverAtt" then
                c:Destroy()
            end
        end
        St.hoverBp = nil
        St.hoverAtt = nil
        St.hoverActive = false
    end

    function A.startHover()
        if St.hoverActive then return end
        scrubHover()
        local r = U.hrp()
        if not r then return end

        local att = Instance.new("Attachment")
        att.Name = "DingusHoverAtt"
        att.Parent = r

        local bp = Instance.new("BodyPosition")
        bp.Name = "DingusHoverBP"
        bp.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        bp.P = Cfg.HoverP
        bp.D = Cfg.HoverD
        bp.Position = r.Position
        bp.Parent = r

        St.hoverBp = bp
        St.hoverAtt = att
        St.hoverActive = true
    end

    function A.stopHover()
        if St.hoverBp then pcall(function() St.hoverBp:Destroy() end); St.hoverBp = nil end
        if St.hoverAtt then pcall(function() St.hoverAtt:Destroy() end); St.hoverAtt = nil end
        St.hoverActive = false
    end

    -- Compute position behind a target
    local function behindPos(targetRP)
        local look = targetRP.CFrame.LookVector
        local behind = targetRP.Position - look * Cfg.HoverDistance
        return Vector3.new(behind.X, behind.Y + Cfg.HoverHeight, behind.Z)
    end

    local function updateHover(targetRP)
        if not Cfg.HoverEnabled then
            if St.hoverActive then A.stopHover() end
            return
        end
        if not St.hoverActive then A.startHover() end
        if not St.hoverBp then return end

        local now = U.clock()
        if now - St.lHover < Cfg.HoverTTL then return end
        St.lHover = now

        -- Compute target hover position
        local goal = behindPos(targetRP)

        -- Smooth chase, but fast enough to stay behind
        local current = St.hoverBp.Position
        local dist = (goal - current).Magnitude

        -- If boss turned and we're more than 4 studs from goal, snap fast
        if dist > 4 then
            St.hoverBp.Position = current:Lerp(goal, 0.35)
        else
            St.hoverBp.Position = current:Lerp(goal, 0.15)
        end
    end

    --============================================================
    -- TOOL ACCESS
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
        if c then for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") then table.insert(out, t) end
        end end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then table.insert(out, t) end
        end end
        return out
    end

    local function equipWeapon()
        local now = U.clock()
        if now - St.lEqp < 1.2 then return end
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
                St.swp = (St.swp or 0) + 1
                return
            end
        end
        St.eq = "unarmed"
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
            if fireSkill(i) then return true end
        end
    end

    --============================================================
    -- ATTACK
    --============================================================
    local function strike(t)
        St.aAt = (St.aAt or 0) + 1
        local hpBefore = t.hm.Health
        U.m1()
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

    --============================================================
    -- FACING / WALK
    --============================================================
    local function face(r, pos)
        pcall(function()
            r.CFrame = CFrame.new(r.Position, Vector3.new(pos.X, r.Position.Y, pos.Z))
        end)
    end

    local function walkTo(h, target)
        if not canAutoMove() then return end
        local now = U.clock()
        if now - St.lMove < 0.3 then return end
        St.lMove = now
        pcall(function() h:MoveTo(target) end)
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
        A.stopHover()
        if Ctx.Spoof and Ctx.Spoof.surfaceUp then pcall(Ctx.Spoof.surfaceUp) end

        task.spawn(function()
            U.tap("Q"); task.wait(0.25)
            local r = U.hrp(); local h = U.hum()
            if not r or not h then retreatRunning = false; St.cbtS = "IDLE"; return end

            local away = r.Position - from
            local flat = Vector3.new(away.X, 0, away.Z)
            if flat.Magnitude < 0.5 then flat = Vector3.new(1, 0, 0) end
            h.WalkSpeed = Cfg.RunSpeed
            pcall(function() h:MoveTo(r.Position + flat.Unit * 60) end)

            local deadline = U.clock() + Cfg.RetreatDelay
            while U.clock() < deadline do
                local hh = U.hum(); if not hh then break end
                if hh.Health / hh.MaxHealth > Cfg.RetreatClearHP then break end
                task.wait(0.25)
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
            print(string.format("[Dingus] target %s (%s) @%.0f", tgt.ch.Name, kind, tgt.d))
        end
        return tgt
    end

    --============================================================
    -- COMBAT TICK
    --============================================================
    function A.combatTick()
        if not St.cbt then
            St.cbtS = "IDLE"
            if St.hoverActive then A.stopHover() end
            return
        end

        local h = U.hum(); local r = U.hrp()
        if not h or not r then St.cbtS = "NO_CHAR"; return end
        if h.Health <= 0 then St.cbtS = "DEAD"; if St.hoverActive then A.stopHover() end; return end

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
                print(string.format("[Dingus] killed %s (%d)", St.tgt.ch.Name, St.bKll))
                St.tgt = nil
                if D.invalidate then D.invalidate() end
            end
            acquireTarget()
            if not St.tgt then
                St.cbtS = "IDLE"
                if St.hoverActive then A.stopHover() end
                return
            end
        end

        local t = St.tgt
        local tPos = t.ch:FindFirstChild("HumanoidRootPart")
        if not tPos then St.tgt = nil; return end

        local dist = U.xzDist(r.Position, tPos.Position)
        t.d = dist

        local blocking = D.isEnemyBlocking(t)
        local stunned = D.isEnemyStunned(t)

        --========================================================
        -- STATE: PUNISH
        --========================================================
        if stunned and dist <= 12 then
            St.cbtS = "PUNISH"
            h.WalkSpeed = 16
            updateHover(tPos)

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
        -- STATE: ATTACK (in range, hover behind)
        --========================================================
        if dist <= Cfg.AtkRange + 4 then
            St.cbtS = "ATTACK"
            h.WalkSpeed = 16
            updateHover(tPos)
            face(r, tPos.Position)

            if now - St.lAtk >= currentInterval() then
                St.lAtk = now
                strike(t)
            end
            if St.skl and now - St.lSkl > 1.6 then
                St.lSkl = now
                fireRotation()
            end
            return
        end

        --========================================================
        -- STATE: APPROACH (out of range, walk in)
        --========================================================
        if dist <= 30 then
            St.cbtS = "APPROACH"
            if St.hoverActive then A.stopHover() end
            h.WalkSpeed = blocking and Cfg.CloseInSpeed or Cfg.RunSpeed
            walkTo(h, tPos.Position)
            face(r, tPos.Position)

            if St.skl and now - St.lSkl > 1.5 then
                St.lSkl = now
                fireRotation()
            end
            return
        end

        --========================================================
        -- STATE: FAR
        --========================================================
        St.cbtS = "FAR"
        if St.hoverActive then A.stopHover() end
        h.WalkSpeed = Cfg.RunSpeed
        walkTo(h, tPos.Position)
        face(r, tPos.Position)
        if St.skl and now - St.lSkl > 2.0 then
            St.lSkl = now
            fireRotation()
        end
    end

    -- Cleanup on unload
    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function() A.stopHover() end)

    print("[Dingus][attack] initialized · hover-behind")
end

return A
