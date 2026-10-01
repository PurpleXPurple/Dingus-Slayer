--[[
    Dingus-Slayer · attack.lua v23
    State machine. Hitbox dual-path. User-input-aware movement.
    Uses Ctx.Detect for enemy state, Ctx.Lists for classification.
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
    St.lAtk = 0
    St.lSkl = 0
    St.lEqp = 0
    St.lMove = 0
    St.lBrt = 0
    St.lFac = 0
    St.lHitbox = 0
    St.userMoveUntil = 0
    St.hitsTotal = 0
    St.attemptsTotal = 0
    St.lastStateChange = 0
    St.skillQueue = {}
    St.eq = St.eq or "none"
    St.lTl = false
    St.cbtS = "IDLE"

    local SK_KEYS = { "Z", "X", "C", "V", "B" }
    local SK_CDS  = { 1.2, 2.0, 2.8, 3.6, 6.0 }
    local ROTATION = { 2, 1, 3, 4, 5 }

    local UIS = game:GetService("UserInputService")

    --============================================================
    -- STATE MACHINE
    --============================================================
    local STATE_PRIORITY = {
        IDLE = 1,
        APPROACH_FAR = 2,
        APPROACH = 2,
        CLOSE_SLOW = 2,
        ATTACK = 3,
        BREAK_BLOCK = 4,
        PUNISH = 5,
        RETREAT = 6,
        DEAD = 7,
        FLYING = 8,
    }

    local TRANSITIONS = {
        IDLE         = { APPROACH_FAR=true, APPROACH=true, CLOSE_SLOW=true, ATTACK=true, BREAK_BLOCK=true, PUNISH=true, RETREAT=true, DEAD=true, FLYING=true },
        APPROACH_FAR = { IDLE=true, APPROACH=true, CLOSE_SLOW=true, ATTACK=true, BREAK_BLOCK=true, PUNISH=true, RETREAT=true, DEAD=true, FLYING=true },
        APPROACH     = { IDLE=true, APPROACH_FAR=true, CLOSE_SLOW=true, ATTACK=true, BREAK_BLOCK=true, PUNISH=true, RETREAT=true, DEAD=true, FLYING=true },
        CLOSE_SLOW   = { IDLE=true, APPROACH=true, ATTACK=true, BREAK_BLOCK=true, PUNISH=true, RETREAT=true, DEAD=true, FLYING=true },
        ATTACK       = { IDLE=true, APPROACH=true, CLOSE_SLOW=true, BREAK_BLOCK=true, PUNISH=true, RETREAT=true, DEAD=true, FLYING=true },
        BREAK_BLOCK  = { IDLE=true, ATTACK=true, PUNISH=true, RETREAT=true, DEAD=true, FLYING=true },
        PUNISH       = { IDLE=true, ATTACK=true, RETREAT=true, DEAD=true, FLYING=true },
        RETREAT      = { IDLE=true, APPROACH=true, DEAD=true, FLYING=true },
        DEAD         = { IDLE=true, FLYING=true },
        FLYING       = { IDLE=true, APPROACH=true, DEAD=true },
    }

    local function setState(new)
        if new == St.cbtS then return true end
        local cur = St.cbtS
        if not TRANSITIONS[cur] or not TRANSITIONS[cur][new] then
            return false
        end
        local curP = STATE_PRIORITY[cur] or 0
        local newP = STATE_PRIORITY[new] or 0
        if newP < curP and not (TRANSITIONS[cur] and TRANSITIONS[cur][new]) then
            return false
        end
        St.cbtS = new
        St.lastStateChange = U.clock()
        return true
    end

    --============================================================
    -- USER INPUT AWARENESS
    --============================================================
    local movementKeys = {
        [Enum.KeyCode.W] = true,
        [Enum.KeyCode.A] = true,
        [Enum.KeyCode.S] = true,
        [Enum.KeyCode.D] = true,
        [Enum.KeyCode.Space] = true,
    }

    UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if movementKeys[input.KeyCode] then
            St.userMoveUntil = U.clock() + 1.5
        end
    end)

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
        if now - St.lEqp < 1.2 then return end
        St.lEqp = now

        local h = U.hum()
        if not h then return end

        local current = equippedTool()
        if current and L.isWeapon(current.Name) then
            St.eq = current.Name
            return
        end

        local tools = inventoryTools()
        for i = 1, #tools do
            local t = tools[i]
            if L.isWeapon(t.Name) then
                if current then
                    pcall(function() h:UnequipTools() end)
                    task.wait(0.08)
                end
                pcall(function() h:EquipTool(t) end)
                St.eq = t.Name
                St.swp = (St.swp or 0) + 1
                print("[Dingus] equipped " .. t.Name)
                return
            end
        end
        St.eq = "unarmed"
    end

    --============================================================
    -- SKILL QUEUE
    --============================================================
    local function enqueueSkill(idx)
        local now = U.clock()
        if now < St.skCd[idx] then return false end
        table.insert(St.skillQueue, { idx = idx, at = now })
        return true
    end

    local function processSkillQueue()
        if #St.skillQueue == 0 then return end
        local item = table.remove(St.skillQueue, 1)
        local now = U.clock()
        local idx = item.idx
        if now < St.skCd[idx] then return end
        U.tap(SK_KEYS[idx])
        St.skCd[idx] = now + SK_CDS[idx]
        St.skC = (St.skC or 0) + 1
    end

    local function fireRotation()
        for i = 1, #ROTATION do
            enqueueSkill(ROTATION[i])
        end
    end

    --============================================================
    -- HITBOX ATTACK (dual-path)
    --============================================================
    local function buildHitboxCF(targetPart)
        return targetPart.CFrame * CFrame.new(0, 0, -3)
    end

    local function hitboxScan(targetPart)
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { U.Lp.Character }
        local ok, parts = pcall(function()
            return workspace:GetPartBoundsInBox(
                buildHitboxCF(targetPart),
                Vector3.new(7, 9, 7),
                params
            )
        end)
        if not ok or not parts then return nil end
        for i = 1, #parts do
            local parent = parts[i].Parent
            if parent and parent:FindFirstChildOfClass("Humanoid") then
                return parent, parts[i]
            end
        end
        return nil
    end

    local function fireAttack(t)
        -- Path 1: mouse click
        U.m1()

        -- Path 2: touch interest on target HRP (if supported)
        if firetouchinterest and t and t.rp then
            pcall(function()
                firetouchinterest(t.rp, U.hrp(), 0)
                task.wait()
                firetouchinterest(t.rp, U.hrp(), 1)
            end)
        end

        -- Path 3: activate tool
        local tool = equippedTool()
        if tool then pcall(function() tool:Activate() end) end

        -- Path 4: hitbox scan — validate proximity to target
        if t and t.rp then
            local nearbyChar = hitboxScan(t.rp)
            if nearbyChar and nearbyChar == t.ch then
                -- Correct target is in range
            end
        end
    end

    --============================================================
    -- ADAPTIVE INTERVAL
    --============================================================
    local function currentInterval()
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

    --============================================================
    -- STRIKE
    --============================================================
    local function strike(t)
        St.aAt = (St.aAt or 0) + 1
        local hpBefore = t.hm.Health

        fireAttack(t)

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

    --============================================================
    -- FACING
    --============================================================
    local function face(r, targetPos)
        pcall(function()
            r.CFrame = CFrame.new(r.Position, Vector3.new(targetPos.X, r.Position.Y, targetPos.Z))
        end)
    end

    --============================================================
    -- MOVEMENT (user-aware)
    --============================================================
    local function canAutoMove()
        return U.clock() > St.userMoveUntil
    end

    local function walkTo(h, r, targetPos)
        if not canAutoMove() then return end

        local now = U.clock()
        if now - St.lMove < 0.3 then return end
        St.lMove = now

        -- Use MoveTo only, never mix with Move
        pcall(function() h:MoveTo(targetPos) end)
    end

    --============================================================
    -- RETREAT (isolated)
    --============================================================
    local retreatRunning = false

    local function startRetreat(from)
        if retreatRunning then return end
        retreatRunning = true
        St.rtrC = (St.rtrC or 0) + 1
        setState("RETREAT")

        if Ctx.Spoof and Ctx.Spoof.surfaceUp then
            pcall(Ctx.Spoof.surfaceUp)
        end

        task.spawn(function()
            U.tap("Q")
            task.wait(0.25)

            local r = U.hrp()
            local h = U.hum()
            if not r or not h then
                retreatRunning = false
                setState("IDLE")
                return
            end

            local away = r.Position - from
            local flat = Vector3.new(away.X, 0, away.Z)
            if flat.Magnitude < 0.5 then flat = Vector3.new(1, 0, 0) end

            h.WalkSpeed = Cfg.RunSpeed
            local dest = r.Position + flat.Unit * 60
            pcall(function() h:MoveTo(dest) end)

            local deadline = U.clock() + (Cfg.RetreatDelay or 4)
            while U.clock() < deadline do
                local hh = U.hum()
                if not hh then break end
                if hh.Health / hh.MaxHealth > (Cfg.RetreatClearHP or 0.65) then break end
                task.wait(0.25)
            end

            retreatRunning = false
            St.tgt = nil
            if Ctx.Detect and Ctx.Detect.invalidate then
                Ctx.Detect.invalidate()
            end
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
                tgt.ch.Name, tostring(kind), tgt.d))
        end
        return tgt
    end

    --============================================================
    -- COMBAT TICK
    --============================================================
    function A.combatTick()
        if St.FlyActive then
            setState("FLYING")
            return
        end

        if not St.cbt then
            setState("IDLE")
            return
        end

        local h = U.hum()
        local r = U.hrp()
        if not h or not r then
            setState("IDLE")
            return
        end

        if h.Health <= 0 then
            setState("DEAD")
            return
        end

        local now = U.clock()
        local hpFrac = h.Health / h.MaxHealth

        -- Maintenance
        equipWeapon()
        U.groundState()
        processSkillQueue()

        -- Damage tracking
        if h.Health < (St.lHp or 0) and now - (St.lHpT or 0) > 0.05 then
            St.lDmg = now
        end
        St.lHp = h.Health
        St.lHpT = now

        -- Breath
        if now - St.lBrt > 2.5 then
            St.lBrt = now
            U.tap("L")
        end

        -- Retreat
        if St.rtr and hpFrac < Cfg.RetreatHP and not retreatRunning then
            local nearest = St.ths and St.ths[1]
            if nearest then
                startRetreat(nearest.rp.Position)
                return
            end
        end
        if retreatRunning then return end

        -- Target validation
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
                setState("IDLE")
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

        -- Evaluate enemy state once per tick
        local blocking = D.isEnemyBlocking(t)
        local stunned = D.isEnemyStunned(t)

        --========================================================
        -- STATE: PUNISH (stun)
        --========================================================
        if stunned and dist <= 12 then
            setState("PUNISH")
            h.WalkSpeed = 16
            face(r, tPos.Position)

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
        -- STATE: BREAK_BLOCK
        --========================================================
        if blocking and dist <= 12 then
            setState("BREAK_BLOCK")
            h.WalkSpeed = 16
            face(r, tPos.Position)

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
        -- STATE: ATTACK (close)
        --========================================================
        if dist <= Cfg.AtkRange then
            setState("ATTACK")
            h.WalkSpeed = 16
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
        -- STATE: CLOSE_SLOW (mid-range defensive)
        --========================================================
        if dist <= 30 and (blocking or stunned) then
            setState("CLOSE_SLOW")
            h.WalkSpeed = Cfg.CloseInSpeed
            walkTo(h, r, tPos.Position)
            face(r, tPos.Position)
            if St.skl and now - St.lSkl > 1.0 then
                St.lSkl = now
                fireRotation()
            end
            return
        end

        --========================================================
        -- STATE: APPROACH (mid-range)
        --========================================================
        if dist <= 30 then
            setState("APPROACH")
            h.WalkSpeed = Cfg.RunSpeed
            walkTo(h, r, tPos.Position)
            face(r, tPos.Position)
            if St.skl and now - St.lSkl > 1.6 then
                St.lSkl = now
                fireRotation()
            end
            return
        end

        --========================================================
        -- STATE: APPROACH_FAR
        --========================================================
        setState("APPROACH_FAR")
        h.WalkSpeed = Cfg.RunSpeed
        walkTo(h, r, tPos.Position)
        face(r, tPos.Position)
        if St.skl and now - St.lSkl > 2.0 then
            St.lSkl = now
            fireRotation()
        end
    end

    print("[Dingus][attack] initialized · state machine + hitbox")
end

return A
