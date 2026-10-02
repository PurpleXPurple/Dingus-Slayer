-- Dingus-Slayer · attack.lua v22
-- Cross-device: uses U.fireSkill for skills (GUI buttons on mobile).

local A = {}

function A.init(Ctx)
    local U, F, S, D, L = Ctx.Util, Ctx.Cfg, Ctx.St, Ctx.Detect, Ctx.Lists

    -- defaults
    F.AtkRange = F.AtkRange or 8
    F.AtkInterval = F.AtkInterval or 0.38
    F.RetreatHP = F.RetreatHP or 0.30
    F.CriticalHP = F.CriticalHP or 0.12
    F.RetreatCooldown = F.RetreatCooldown or 8.0
    F.SkillKeys = F.SkillKeys or {"F","Z","X","C","V","B"}
    F.GCDWindow = F.GCDWindow or 1.10
    F.ComboOrderCount = F.ComboOrderCount or 4
    F.ComboBurst = F.ComboBurst or 4
    F.M1MaxHz = F.M1MaxHz or 10
    F.TeleportCd = F.TeleportCd or 0.22
    F.TeleportStrike = F.TeleportStrike or 4.5
    F.TeleportHeight = F.TeleportHeight or 3
    F.TeleportJitter = F.TeleportJitter or 2
    F.DodgeCooldown = F.DodgeCooldown or 0.65
    F.AtkVerbose = F.AtkVerbose ~= false

    S.rHt = {}
    S.gcdUntil = 0
    S.cbtS = "IDLE"
    S.comboIndex = 0
    S.retreating = false
    S.retreatStart = 0
    S.retreatCooldownUntil = 0
    S.lStateRefresh = 0
    S.lootCycleActive = false
    S.lootCycleStart = 0

    local SK = F.SkillKeys
    local SKC = #SK

    local function slog(msg) if F.AtkVerbose then print("[Dingus][Atk] "..msg) end end

    S._lastLoggedState = nil
    local function logState(s)
        if S._lastLoggedState == s then return end
        S._lastLoggedState = s
        print("[Dingus][Atk] state → "..tostring(s))
    end

    -- combo
    local function buildPerm()
        local pool = {}
        for i = 1, SKC do
            if not (S.fIsBlock and SK[i] == "F") and F.SkillUnlocked[i] then
                table.insert(pool, i)
            end
        end
        for i = #pool, 2, -1 do
            local j = math.random(1, i)
            pool[i], pool[j] = pool[j], pool[i]
        end
        return pool
    end

    local function buildOrders()
        local orders, seen, tries = {}, {}, 0
        while #orders < F.ComboOrderCount and tries < 50 do
            tries = tries + 1
            local p = buildPerm()
            local k = table.concat(p, ",")
            if not seen[k] and #p > 0 then
                seen[k] = true
                table.insert(orders, p)
            end
        end
        return orders
    end

    S.comboOrders = buildOrders()
    S.comboOrderIdx, S.comboPos, S.comboRotations = 1, 1, 0

    local function curOrder() return S.comboOrders[S.comboOrderIdx] end
    local function resetCombo() S.comboPos = 1 end

    local function advanceCombo()
        local o = curOrder()
        if not o or #o == 0 then S.comboOrderIdx, S.comboPos = 1, 1; return end
        S.comboPos = S.comboPos + 1
        if S.comboPos > #o then
            S.comboRotations = S.comboRotations + 1
            S.comboOrderIdx = S.comboOrderIdx + 1
            S.comboPos = 1
            if S.comboOrderIdx > #S.comboOrders then
                S.comboOrderIdx = 1
                if S.comboRotations >= F.ComboReshuffleN then
                    S.comboOrders = buildOrders()
                    S.comboRotations = 0
                end
            end
        end
    end

    local function fireSkill(idx, t)
        if t < S.gcdUntil then return false end
        if not F.SkillUnlocked[idx] then return false end
        if S.fIsBlock and SK[idx] == "F" then return false end
        local k = SK[idx]
        -- Cross-device: GUI button first, then key sim
        if not U.fireSkill(k) then
            U.tap(k, 0.05)
        end
        S.gcdUntil = t + F.GCDWindow
        S.comboFires = (S.comboFires or 0) + 1
        return true
    end

    local function fireCombo(t, hp, now)
        if not S.skl then return end
        if now < S.gcdUntil then return end
        local o = curOrder()
        if not o or #o == 0 then
            S.comboOrders = buildOrders()
            S.comboOrderIdx, S.comboPos = 1, 1
            return
        end
        local idx = o[S.comboPos]
        if not idx then resetCombo(); return end
        fireSkill(idx, now)
        advanceCombo()
    end

    -- tool
    local function eqTool()
        local c = U.Lp.Character; if not c then return nil end
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and not L.isCrow(t.Name) then return t end
        end
        return nil
    end

    local function invTools()
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
        if S.swapPending then return end
        local t = U.clock()
        if t - (S.lEqp or 0) < 1.5 then return end
        S.lEqp = t
        local h = U.hum(); if not h then return end
        local cur = eqTool()
        if cur and L.isWeapon(cur.Name) then S.eq = cur.Name; return end
        for _, tool in ipairs(invTools()) do
            if L.isWeapon(tool.Name) then
                S.swapPending = true
                task.spawn(function()
                    pcall(function() h:EquipTool(tool) end)
                    S.eq = tool.Name; S.swapPending = false
                end)
                return
            end
        end
    end

    -- movement
    local function safeCF(dest, look)
        local dx = look.X - dest.X
        local dz = look.Z - dest.Z
        if dx*dx + dz*dz < 0.25 then
            look = Vector3.new(dest.X + 1, look.Y, dest.Z)
        end
        local ok, cf = pcall(function()
            return CFrame.new(dest, Vector3.new(look.X, dest.Y, look.Z))
        end)
        return (ok and cf) or CFrame.new(dest)
    end

    local function teleport(t, tPos, myPos)
        local r = U.hrp(); if not r then return false end
        local t0 = U.clock()
        if t0 - (S.lTele or 0) < F.TeleportCd then return false end
        S.lTele = t0
        local tp = tPos.Position
        local ap = tp - myPos
        local flat = Vector3.new(ap.X, 0, ap.Z)
        if flat.Magnitude < 0.1 then flat = Vector3.new(1,0,0) end
        flat = flat.Unit
        local side = Vector3.new(-flat.Z, 0, flat.X)
        local jx = (math.random() - 0.5) * F.TeleportJitter
        local jz = (math.random() - 0.5) * F.TeleportJitter
        local bias = math.sin(t0 * 0.3) * 2
        local dest = tp - flat * F.TeleportStrike + side * (bias + jx * 0.5)
            + Vector3.new(jx, F.TeleportHeight, jz)
        if dest.Y < tp.Y + 1 then
            dest = Vector3.new(dest.X, tp.Y + F.TeleportHeight, dest.Z)
        end
        local cf = safeCF(dest, tp)
        if not pcall(function() r.CFrame = cf end) then return false end
        pcall(function()
            r.AssemblyLinearVelocity = Vector3.new(
                (math.random()-0.5)*3, -4 - math.random()*3, (math.random()-0.5)*3)
        end)
        S.teleCount = (S.teleCount or 0) + 1
        return true
    end

    local function inRange(t, tPos, myPos, now)
        if now - (S.lInRangeChase or 0) < 0.22 then return end
        S.lInRangeChase = now
        local r = U.hrp(); if not r then return end
        local dx = tPos.Position.X - myPos.X
        local dz = tPos.Position.Z - myPos.Z
        if dx*dx + dz*dz > 0.04 then
            pcall(function()
                r.CFrame = CFrame.new(myPos, Vector3.new(tPos.Position.X, myPos.Y, tPos.Position.Z))
            end)
        end
    end

    local function dodge(now)
        if now - (S.lDodge or 0) < F.DodgeCooldown then return false end
        S.lDodge = now
        S.dodgeCount = (S.dodgeCount or 0) + 1
        U.fireSkill("Q") or U.tap("Q")
        return true
    end

    local function chain(count)
        count = count or F.ComboBurst
        local gap = math.max(0.11, 1 / F.M1MaxHz)
        task.spawn(function()
            for i = 1, count do
                if i % 2 == 0 then U.m2() else U.m1() end
                if i < count then task.wait(gap) end
            end
        end)
    end

    local function strike(t, now)
        S.aAt = (S.aAt or 0) + 1
        local hpB = t.hm.Health
        if S.comboTargetName ~= t.ch.Name then
            S.comboTargetName = t.ch.Name
            resetCombo()
        end
        S.comboIndex = S.comboIndex + 1
        local c = F.ComboBurst
        if S.emergency then c = c + 2 end
        if S.comboIndex % 4 == 0 then c = c + 1 end
        chain(c)
        local tool = eqTool()
        if tool then pcall(function() tool:Activate() end) end
        task.spawn(function()
            task.wait(0.35)
            if not (t and t.hm and t.hm.Parent) then return end
            local hit = t.hm.Health < hpB
            table.insert(S.rHt, hit)
            if #S.rHt > 15 then table.remove(S.rHt, 1) end
            if hit then S.aHi = (S.aHi or 0) + 1 else S.aMs = (S.aMs or 0) + 1 end
        end)
    end

    local function interval()
        if S.emergency then return F.EmergencyInterval end
        return S.aiI or F.AtkInterval
    end

    local function resolveF()
        if S.fModeResolved then return end
        local mode = F.FKeyMode or "auto"
        if mode == "auto" then
            local c = U.Lp.Character
            if c then
                U.keyDown("F"); task.wait(0.15)
                local ok1, v1 = pcall(function() return c:GetAttribute("IsBlocking") end)
                U.keyUp("F"); task.wait(0.05)
                S.fIsBlock = (ok1 and v1 == true)
            end
        else
            S.fIsBlock = (mode == "block")
        end
        S.fModeResolved = true
    end
    task.spawn(resolveF)

    -- retreat
    local function retreat(from, reason)
        if S.retreating then return end
        if U.clock() < S.retreatCooldownUntil then return end
        S.retreating = true
        S.retreatStart = U.clock()
        S.retreatCount = (S.retreatCount or 0) + 1
        S.cbtS = "RETREAT"
        logState("RETREAT")
        if Ctx.Chest and Ctx.Chest.abort then pcall(Ctx.Chest.abort) end
        S.lootCycleActive = false
        task.spawn(function()
            U.fireSkill("Q") or U.tap("Q")
            task.wait(0.25)
            local r, h = U.hrp(), U.hum()
            if not r or not h then
                S.retreating = false; S.retreatStart = 0; return
            end
            local away = r.Position - from
            local flat = Vector3.new(away.X, 0, away.Z)
            if flat.Magnitude < 0.5 then flat = Vector3.new(1,0,0) end
            h.WalkSpeed = F.RunSpeed or 16
            local st = U.clock()
            while U.clock() < st + (F.RetreatDelay or 2.0) do
                local hh = U.hum(); if not hh then break end
                if hh.Health / hh.MaxHealth > (F.RetreatClearHP or 0.55) then break end
                pcall(function() h:Move(flat.Unit) end)
                task.wait(0.05)
            end
            S.retreating = false
            S.retreatStart = 0
            S.retreatCooldownUntil = U.clock() + (F.RetreatCooldown or 8.0)
            S.tgt = nil
        end)
    end

    local function spawnBossLoot(bossPos, bossName)
        if not Ctx.Chest or not Ctx.Chest.collectAtBoss then return end
        if not F.ChestEnabled or not F.ChestOnKill then return end
        S.lootCycleActive = true
        S.lootCycleStart = U.clock()
        task.spawn(function()
            local ok, err = pcall(Ctx.Chest.collectAtBoss, bossPos, bossName)
            if not ok then
                print("[Dingus][Atk] loot cycle error: "..tostring(err))
            end
            S.lootCycleActive = false
            S.lootCycleStart = 0
            S.tgt = nil
            if D.invalidate then D.invalidate() end
        end)
    end

    local function combatTickInner()
        if not S.cbt then
            S.cbtS = "IDLE"
            logState("IDLE")
            return
        end
        local h, r = U.hum(), U.hrp()
        if not h or not r then S.cbtS = "NO_CHAR"; logState("NO_CHAR"); return end
        if h.Health <= 0 then S.cbtS = "DEAD"; logState("DEAD"); return end

        local now = U.clock()
        local hpFrac = h.Health / h.MaxHealth

        if S.retreating then
            if S.retreatStart > 0 and now - S.retreatStart > 6 then
                S.retreating = false
                S.retreatStart = 0
                S.retreatCooldownUntil = now + (F.RetreatCooldown or 8.0)
            else return end
        end

        if S.lootCycleActive then
            if S.lootCycleStart > 0 and now - S.lootCycleStart > 20 then
                if Ctx.Chest and Ctx.Chest.abort then pcall(Ctx.Chest.abort) end
                S.lootCycleActive = false
                S.lootCycleStart = 0
            else
                S.cbtS = "LOOT"; logState("LOOT"); return
            end
        end

        S.critical = hpFrac < F.CriticalHP
        S.emergency = hpFrac < (F.EmergencyHP or 0.30)

        if not S.emergency and hpFrac < F.RetreatHP then
            if now >= S.retreatCooldownUntil then
                local n = S.ths and S.ths[1]
                if n then retreat(n.rp.Position, "hp"); return end
            end
        end

        equipWeapon()
        U.groundState()

        if not S.tgt or not S.tgt.ch.Parent or S.tgt.hm.Health <= 0 then
            if S.tgt then
                local bossPos = S.tgt.rp and S.tgt.rp.Position
                local bossName = S.tgt.ch.Name
                S.bKll = (S.bKll or 0) + 1
                print(string.format("[Dingus] killed %s (%d)", bossName, S.bKll))
                S.tgt = nil
                resetCombo()
                spawnBossLoot(bossPos, bossName)
            end
            if S.lootCycleActive then return end
            local t, k = D.pickTarget()
            S.tgt = t
            S.tgtKind = k
            if not t then S.cbtS = "IDLE"; logState("IDLE"); return end
        end

        local t = S.tgt
        local tPos = t.ch:FindFirstChild("HumanoidRootPart")
        if not tPos then S.tgt = nil; return end

        local myPos = r.Position
        local dist = U.xzDist(myPos, tPos.Position)
        t.d = dist
        local atk = D.isEnemyAttacking and D.isEnemyAttacking(t) or false

        if dist > F.AtkRange then
            S.cbtS = "TELEPORT"; logState("TELEPORT")
            teleport(t, tPos, myPos)
            fireCombo(t, hpFrac, now)
            return
        end

        inRange(t, tPos, myPos, now)
        local blocking = D.isEnemyBlocking(t)
        local stunned = D.isEnemyStunned(t)

        if not S.emergency and atk then
            if now - (S.lDodge or 0) > F.DodgeCooldown then
                S.cbtS = "DODGE"; logState("DODGE"); dodge(now); return
            end
        end

        if stunned and S.stunPun then
            S.cbtS = "PUNISH"; logState("PUNISH")
            if now - (S.lAtk or 0) >= (F.StunAtkInt or 0.20) then
                S.lAtk = now; strike(t, now)
            end
            fireCombo(t, hpFrac, now)
            return
        end

        if blocking then
            S.cbtS = "BREAK"; logState("BREAK")
            fireCombo(t, hpFrac, now)
            if now - (S.lAtk or 0) > (S.aiI or 0.38) * 1.2 then
                S.lAtk = now; strike(t, now)
            end
            return
        end

        S.cbtS = S.emergency and "EMERGENCY" or "STRIKE"
        logState(S.cbtS)
        if now - (S.lAtk or 0) >= interval() then S.lAtk = now; strike(t, now) end
        fireCombo(t, hpFrac, now)
    end

    function A.combatTick()
        local ok, err = pcall(combatTickInner)
        if not ok and not S._tickErrLogged then
            S._tickErrLogged = true
            warn("[Dingus][Atk] tick error: "..tostring(err))
        elseif ok then
            S._tickErrLogged = false
        end
    end

    function A.forceScan()
        if D.invalidate then D.invalidate() end
        local l = D.scanBosses(nil, true)
        print(string.format("[Dingus] force scan: %d bosses", #l))
    end

    function A.forceMove()
        if not S.tgt then return end
        local r = U.hrp()
        local tPos = S.tgt.ch:FindFirstChild("HumanoidRootPart")
        if r and tPos then
            local dest = tPos.Position + Vector3.new(0, 3, 0)
            pcall(function() r.CFrame = safeCF(dest, tPos.Position) end)
        end
    end

    function A.fModeInfo()
        return { resolved=S.fModeResolved, isBlock=S.fIsBlock, blocking=S.blocking }
    end

    function A.telemetry()
        return {
            state = S.cbtS,
            teleports = S.teleCount or 0,
            dodges = S.dodgeCount or 0,
            comboFires = S.comboFires or 0,
            emergency = S.emergency,
            blocking = S.blocking,
            retreating = S.retreating,
            lootActive = S.lootCycleActive,
            equipped = S.eq,
        }
    end

    function A.forceStopRetreat()
        S.retreating = false
        S.retreatStart = 0
        S.retreatCooldownUntil = U.clock() + 1
        S.tgt = nil
    end

    function A.abortLoot()
        if Ctx.Chest and Ctx.Chest.abort then pcall(Ctx.Chest.abort) end
        S.lootCycleActive = false
        S.lootCycleStart = 0
    end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function()
        if Ctx.Chest and Ctx.Chest.abort then pcall(Ctx.Chest.abort) end
    end)

    print(string.format(
        "[Dingus][attack] v22 · %s · skill-buttons=%s",
        U.Platform, tostring(U.hasSkillButton("Z"))))
end

return A
