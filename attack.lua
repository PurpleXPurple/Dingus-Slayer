--[[
    Dingus-Slayer · attack.lua v22
    Combat handler. Distance-tiered behavior. Uses detect for targeting,
    Lists for classification. No hover. Throttled movement. Clean retreat.
]]--

local A = {}

function A.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local D = Ctx.Detect
    local L = Ctx.Lists

    --============================================================
    -- LOCAL STATE
    --============================================================
    St.rHt = St.rHt or {}
    St.skCd = St.skCd or { 0, 0, 0, 0, 0 }
    St.aiI = St.aiI or Cfg.AtkInterval
    St.lAtk = St.lAtk or 0
    St.lSkl = St.lSkl or 0
    St.lEqp = St.lEqp or 0
    St.lMove = St.lMove or 0
    St.lBrt = St.lBrt or 0
    St.lFac = St.lFac or 0
    St.eq = St.eq or "none"
    St.lTl = St.lTl or false

    local SK_KEYS = { "Z", "X", "C", "V", "B" }
    local SK_CDS  = { 1.2, 2.0, 2.8, 3.6, 6.0 }
    local ROTATION = { 2, 1, 3, 4, 5 }

    --============================================================
    -- TOOL ACCESS
    --============================================================
    local function equippedTool()
        local c = U.Lp.Character
        if not c then return nil end
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and not L.isCrow(t.Name) then return t end
        end
        return nil
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

    --============================================================
    -- WEAPON EQUIP
    --============================================================
    local function equipWeapon()
        local now = U.clock()
        if now - St.lEqp < 1.0 then return end
        St.lEqp = now

        local h = U.hum()
        if not h then return end

        local current = equippedTool()
        if current and L.isWeapon(current.Name) then
            St.eq = current.Name
            return
        end

        local tools = inventoryTools()
        local best = nil
        for i = 1, #tools do
            local t = tools[i]
            if L.isWeapon(t.Name) then
                best = t
                break
            end
        end
        if not best then
            St.eq = "unarmed"
            return
        end

        if current then
            pcall(function() h:UnequipTools() end)
            task.wait(0.08)
        end
        pcall(function() h:EquipTool(best) end)
        St.eq = best.Name
        St.swp = (St.swp or 0) + 1
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
        for i = 1, #ROTATION do
            if fireSkill(ROTATION[i]) then return true end
        end
        return false
    end

    --============================================================
    -- ADAPTIVE ATTACK INTERVAL
    --============================================================
    local function currentInterval()
        local h = St.rHt
        if #h < 5 then return St.aiI end
        local hits = 0
        for i = 1, #h do
            if h[i] then hits = hits + 1 end
        end
        local rate = hits / #h
        if rate > 0.7 then
            St.aiI = math.max(Cfg.AtkIntMin, St.aiI - 0.02)
        elseif rate < 0.3 then
            St.aiI = math.min(Cfg.AtkIntMax, St.aiI + 0.02)
        end
        return St.aiI
    end

    --============================================================
    -- SINGLE ATTACK
    --============================================================
    local function strike(t)
        St.aAt = (St.aAt or 0) + 1
        local hpBefore = t.hm.Health

        U.m1()
        local tool = equippedTool()
        if tool then pcall(function() tool:Activate() end) end

        task.spawn(function()
            task.wait(0.2)
            if not (t and t.hm and t.hm.Parent) then return end
            local hpAfter = t.hm.Health
            local hit = hpAfter < hpBefore
            table.insert(St.rHt, hit)
            if #St.rHt > Cfg.HitWindow then table.remove(St.rHt, 1) end
            if hit then
                St.aHi = (St.aHi or 0) + 1
            else
                St.aMs = (St.aMs or 0) + 1
            end
        end)
    end

    --============================================================
    -- FACING / MOVEMENT
    --============================================================
    local function face(r, targetPos)
        pcall(function()
            r.CFrame = CFrame.new(r.Position, Vector3.new(targetPos.X, r.Position.Y, targetPos.Z))
        end)
    end

    local function walk(h, r, targetPos)
        local dir = targetPos - r.Position
        dir = Vector3.new(dir.X, 0, dir.Z)
        if dir.Magnitude < 0.5 then return end

        -- Persistent directional push
        pcall(function() h:Move(dir.Unit) end)
        pcall(function() h.WalkToPoint = targetPos end)

        -- Throttled MoveTo for pathfinding
        local now = U.clock()
        if now - St.lMove > 0.25 then
            St.lMove = now
            pcall(function() h:MoveTo(targetPos) end)
        end
    end

    --============================================================
    -- RETREAT
    --============================================================
    local function startRetreat(from)
        if St.cbtS == "RETREAT" then return end
        St.cbtS = "RETREAT"
        St.rtrC = (St.rtrC or 0) + 1
        St.tgt = nil

        if Ctx.Spoof and Ctx.Spoof.surfaceUp then
            pcall(Ctx.Spoof.surfaceUp)
        end

        task.spawn(function()
            U.tap("Q")
            task.wait(0.25)

            local r = U.hrp()
            local h = U.hum()
            if not r or not h then St.cbtS = "IDLE"; return end

            local away = r.Position - from
            local flat = Vector3.new(away.X, 0, away.Z)
            if flat.Magnitude < 0.5 then flat = Vector3.new(1, 0, 0) end

            h.WalkSpeed = Cfg.RunSpeed
            pcall(function() h:MoveTo(r.Position + flat.Unit * 60) end)

            local deadline = U.clock() + Cfg.RetreatDelay
            while U.clock() < deadline do
                local hh = U.hum()
                if not hh then break end
                if hh.Health / hh.MaxHealth > Cfg.RetreatClearHP then break end
                task.wait(0.25)
            end

            St.cbtS = "IDLE"
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
            St.cbtS = "ENGAGE"
            print(string.format("[Dingus] target %s (%s) @%.0f", tgt.ch.Name, kind, tgt.d))
        end
        return tgt
    end

    --============================================================
    -- MAIN TICK
    --============================================================
    function A.combatTick()
        if not St.cbt then
            St.cbtS = "IDLE"
            return
        end

        local h = U.hum()
        local r = U.hrp()
        if not h or not r then
            St.cbtS = "NO_CHAR"
            return
        end
        if h.Health <= 0 then
            St.cbtS = "DEAD"
            return
        end

        local now = U.clock()
        local hpFrac = h.Health / h.MaxHealth

        -- Maintenance
        equipWeapon()
        U.groundState()

        -- Track damage timing
        if h.Health < (St.lHp or 0) and now - (St.lHpT or 0) > 0.05 then
            St.lDmg = now
        end
        St.lHp = h.Health
        St.lHpT = now

        -- Breath maintenance
        if now - St.lBrt > 2.5 then
            St.lBrt = now
            U.tap("L")
        end

        -- Retreat check
        if St.rtr and hpFrac < Cfg.RetreatHP then
            local nearest = St.ths and St.ths[1]
            if nearest then
                startRetreat(nearest.rp.Position)
                return
            end
        end
        if St.cbtS == "RETREAT" then return end

        -- Target acquisition / validation
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
                return
            end
        end

        local t = St.tgt
        local tPos = t.ch:FindFirstChild("HumanoidRootPart")
        if not tPos then
            St.tgt = nil
            return
        end

        local dist = U.xzDist(r.Position, tPos.Position)
        t.d = dist

        -- Enemy state checks
        local blocking = D.isEnemyBlocking(t)
        local stunned = D.isEnemyStunned(t)

        --========================================================
        -- DISTANCE 1: FAR (> 30) — chase + ranged skills
        --========================================================
        if dist > 30 then
            St.cbtS = "APPROACH_FAR"
            h.WalkSpeed = Cfg.RunSpeed
            walk(h, r, tPos.Position)
            face(r, tPos.Position)

            if St.skl and now - St.lSkl > 2.0 then
                St.lSkl = now
                fireRotation()
            end
            return
        end

        --========================================================
        -- DISTANCE 2: MID (8-30) — approach + skills
        --========================================================
        if dist > 8 then
            if blocking or stunned then
                -- Slow, careful approach when boss is defensive
                St.cbtS = "CLOSE_SLOW"
                h.WalkSpeed = Cfg.CloseInSpeed
                walk(h, r, tPos.Position)
                face(r, tPos.Position)

                if St.skl and now - St.lSkl > 1.0 then
                    St.lSkl = now
                    fireRotation()
                end
                return
            end

            St.cbtS = "APPROACH"
            h.WalkSpeed = Cfg.RunSpeed
            walk(h, r, tPos.Position)
            face(r, tPos.Position)

            if St.skl and now - St.lSkl > 1.6 then
                St.lSkl = now
                fireRotation()
            end
            return
        end

        --========================================================
        -- DISTANCE 3: CLOSE (< 8) — melee
        --========================================================
        h.WalkSpeed = 16
        face(r, tPos.Position)

        if blocked(stunned, blocking) then
            return
        end

        -- Normal attack cycle
        local interval = currentInterval()
        if now - St.lAtk >= interval then
            St.lAtk = now
            strike(t)
        end

        if St.skl and now - St.lSkl > 1.6 then
            St.lSkl = now
            fireRotation()
        end
    end

    --============================================================
    -- CLOSE-RANGE STATE DISPATCH
    --============================================================
    function blocked(stunned, blocking)
        local now = U.clock()

        if stunned then
            St.cbtS = "PUNISH"
            if now - St.lAtk >= Cfg.StunAtkInt then
                St.lAtk = now
                strike(St.tgt)
            end
            if St.skl and now - St.lSkl > 0.3 then
                St.lSkl = now
                fireRotation()
            end
            return true
        end

        if blocking then
            St.cbtS = "BREAK_BLOCK"
            -- Skills break blocks faster than melee
            if St.skl and now - St.lSkl > 0.5 then
                St.lSkl = now
                fireRotation()
            end
            -- Occasional melee to keep pressure
            if now - St.lAtk > St.aiI * 1.5 then
                St.lAtk = now
                strike(St.tgt)
            end
            return true
        end

        St.cbtS = "ATTACK"
        return false
    end

    print("[Dingus][attack] initialized")
end

return A
