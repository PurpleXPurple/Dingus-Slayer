--[[
    Dingus-Slayer · attack.lua v19
    Calls Chest.collectAtBoss with the corpse position on kill.
    Blocks target acquisition during loot cycle.
    Aborts loot cycle on retreat.
]]--

local A = {}

function A.init(Ctx)
    local U, F, S, D, L = Ctx.Util, Ctx.Cfg, Ctx.St, Ctx.Detect, Ctx.Lists

    F.AtkRange = F.AtkRange or 8
    F.AtkInterval = F.AtkInterval or 0.38
    F.AtkIntMin = F.AtkIntMin or 0.22
    F.AtkIntMax = F.AtkIntMax or 0.65
    F.StunAtkInt = F.StunAtkInt or 0.20
    F.HitWindow = F.HitWindow or 15
    F.RunSpeed = F.RunSpeed or 16
    F.RetreatHP = F.RetreatHP or 0.55
    F.CriticalHP = F.CriticalHP or 0.15
    F.RetreatDelay = F.RetreatDelay or 2.5
    F.RetreatClearHP = F.RetreatClearHP or 0.75
    F.SkillKeys = F.SkillKeys or { "F","Z","X","C","V","B" }
    F.SkillUnlocked = F.SkillUnlocked or { true,true,true,true,true,true }
    F.GCDWindow = F.GCDWindow or 1.10
    F.ComboOrderCount = F.ComboOrderCount or 4
    F.ComboReshuffleN = F.ComboReshuffleN or 3
    F.DetectHoldSkills = F.DetectHoldSkills ~= false
    F.HoldProbeDuration = F.HoldProbeDuration or 1.30
    F.HoldCastDuration = F.HoldCastDuration or 1.20
    F.HoldOverride = F.HoldOverride or {}
    F.AutoBlockOnDamage = F.AutoBlockOnDamage ~= false
    F.BlockReactionWindow = F.BlockReactionWindow or 1.50
    F.BlockGraceRelease = F.BlockGraceRelease or 0.35
    F.EmergencyHP = F.EmergencyHP or 0.30
    F.EmergencyInterval = F.EmergencyInterval or 0.15
    F.FKeyMode = F.FKeyMode or "auto"
    F.AutoBlock = F.AutoBlock ~= false
    F.BlockHoldTTL = F.BlockHoldTTL or 0.4
    F.BlockProbeWait = F.BlockProbeWait or 0.15
    F.TeleportCd = F.TeleportCd or 0.22
    F.TeleportStrike = F.TeleportStrike or 4.5
    F.TeleportHeight = F.TeleportHeight or 3
    F.TeleportJitter = F.TeleportJitter or 2
    F.ComboBurst = F.ComboBurst or 4
    F.ComboGap = F.ComboGap or 0.11
    F.DodgeCooldown = F.DodgeCooldown or 0.65
    F.InRangeChaseT = F.InRangeChaseT or 0.22
    F.TelegraphWindow = F.TelegraphWindow or 0.45
    F.M1MaxHz = F.M1MaxHz or 10
    F.WeaponHotbarOrder = F.WeaponHotbarOrder or { "3","4","1","5" }

    S.rHt = {}
    S.gcdUntil = 0
    S.aiI = F.AtkInterval
    S.lAtk, S.lSkl, S.lEqp, S.lBrt = 0, 0, 0, 0
    S.lDodge, S.lTele, S.lInRangeChase = 0, 0, 0
    S.lStateRefresh = 0
    S.eq, S.eqKey = "none", nil
    S.cbtS = "IDLE"
    S.comboIndex = 0
    S.comboTargetName = nil
    S.swapPending = false
    S.equipFailCount = 0
    S.fIsBlock, S.fModeResolved = false, false
    S.blocking, S.blockHoldUntil = false, 0
    S.holdSkills, S.holdDetected, S.holdDetecting = {}, false, false
    S.lastHp, S.damageBlockUntil, S.bossIdleSince = 0, 0, 0
    S.emergency, S.critical = false, false
    S.teleCount, S.teleFail, S.dodgeCount = 0, 0, 0
    S.gcdHits, S.gcdMisses = 0, 0
    S.holdFires, S.instantFires = 0, 0
    S.comboFires, S.comboRotations = 0, 0
    S.breathFrac, S.partySize = 1.0, 1
    S.lootCycleActive = false
    S.lootCycleBossName = nil

    local SK = F.SkillKeys
    local SKC = #SK

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

    local function logCombos()
        print("[Dingus][Atk] combo orders:")
        for i, o in ipairs(S.comboOrders) do
            local n = {}
            for _, idx in ipairs(o) do table.insert(n, SK[idx]) end
            print(string.format("  %d: %s", i, table.concat(n, " → ")))
        end
    end
    logCombos()

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
                    logCombos()
                end
            end
        end
    end

    local function scrub()
        local r = U.hrp(); if not r then return end
        for _, c in ipairs(r:GetChildren()) do
            if c:IsA("BodyPosition") or c:IsA("BodyVelocity")
               or c:IsA("BodyGyro") or c:IsA("BodyForce")
               or c:IsA("LinearVelocity") or c:IsA("AlignOrientation")
               or c:IsA("AlignPosition") then
                c:Destroy()
            end
        end
        local h = U.hum()
        if h then h.PlatformStand = false; h.AutoRotate = true end
    end
    scrub()
    U.Lp.CharacterAdded:Connect(function()
        task.wait(1); scrub()
        S.blocking = false; S.blockHoldUntil = 0
        S.fModeResolved = false; S.comboTargetName = nil; S.eqKey = nil
        S.lootCycleActive = false
        if Ctx.Chest then Ctx.Chest.abort() end
        resetCombo()
    end)

    local function readAtkAnim()
        local h = U.hum(); if not h then return false end
        local an = h:FindFirstChildOfClass("Animator"); if not an then return false end
        local ok, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
        if not ok or not tracks then return false end
        for i = 1, #tracks do
            local t = tracks[i]
            local okP, ip = pcall(function() return t.IsPlaying end)
            if okP and ip then
                local okW, w = pcall(function() return t.WeightCurrent end)
                if okW and w > 0.3 then
                    local okN, nm = pcall(function() return t.Name end)
                    if okN and nm then
                        local l = string.lower(nm)
                        if not l:find("idle",1,true) and not l:find("walk",1,true)
                           and not l:find("run",1,true) then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    local function holdProbe(idx)
        if F.HoldOverride[idx] ~= nil then return F.HoldOverride[idx] end
        if S.fIsBlock and SK[idx] == "F" then return false end
        if not F.SkillUnlocked[idx] then return false end
        local h = U.hum(); if not h or h.Health <= 0 then return false end
        local pg = S.gcdUntil
        S.gcdUntil = U.clock() + F.GCDWindow
        local k = SK[idx]
        U.keyDown(k); task.wait(F.HoldProbeDuration)
        local ch = readAtkAnim()
        U.keyUp(k); task.wait(0.15)
        if S.gcdUntil < pg then S.gcdUntil = pg end
        return ch
    end

    local function detectHold()
        if S.holdDetected or S.holdDetecting then return end
        S.holdDetecting = true
        print("[Dingus][Atk] probing hold-cast skills...")
        local hold, inst = {}, {}
        for i = 1, SKC do
            local isHold = holdProbe(i)
            S.holdSkills[i] = isHold
            if isHold then table.insert(hold, i) else table.insert(inst, i) end
            task.wait(0.3)
        end
        print(string.format("[Dingus][Atk] hold:[%s] instant:[%s]",
            table.concat(hold, ","), table.concat(inst, ",")))
        S.comboOrders = buildOrders()
        S.comboOrderIdx, S.comboPos, S.comboRotations = 1, 1, 0
        logCombos()
        S.holdDetected, S.holdDetecting = true, false
    end

    local function blockHold()
        if S.blocking then return end
        S.blocking = true; U.keyDown("F")
    end
    local function blockRel()
        if not S.blocking then return end
        S.blocking = false; U.keyUp("F")
    end

    local function eqTool()
        local c = U.Lp.Character; if not c then return nil end
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and not L.isCrow(t.Name) then return t end
        end
        for _, h in ipairs({"RightHand","LeftHand"}) do
            local hp = c:FindFirstChild(h)
            if hp then
                for _, ch in ipairs(hp:GetChildren()) do
                    if ch:IsA("BasePart") or ch:IsA("MeshPart")
                       or ch:IsA("Model") then
                        if not L.isCrow(ch.Name) then return ch end
                    end
                end
            end
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
        if Ctx.Quest and Ctx.Quest.stats then
            local qs = Ctx.Quest.stats()
            if qs.panelOpen then return end
        end
        local H = Ctx.Hotbar
        if H and H.isLocked() then return end
        local t = U.clock()
        if t - S.lEqp < 1.5 then return end
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
        S.swapPending = true
        task.spawn(function()
            if not H then S.swapPending = false; return end
            if not H.acquire("attack-weapon", 3.0) then S.swapPending = false; return end
            local ok, info = H.equipFirstOf("attack-weapon", "weapon", 0.5)
            if ok then
                S.eq = info or "weapon"
                S.eqKey = H.slotOf(info)
                S.equipFailCount = 0
                print(string.format("[Dingus][Atk] equipped %s (slot %s)",
                    tostring(info), tostring(S.eqKey)))
            else
                S.equipFailCount = (S.equipFailCount or 0) + 1
                if S.equipFailCount >= 3 then
                    if H.scanSlots then H.scanSlots("attack-refresh") end
                    S.equipFailCount = 0
                end
            end
            H.release("attack-weapon"); S.swapPending = false
        end)
    end

    local function gcdReady(t) return t >= S.gcdUntil end

    local function fireSkill(idx, t)
        if not gcdReady(t) then S.gcdMisses = S.gcdMisses + 1; return false end
        if not F.SkillUnlocked[idx] then return false end
        if S.fIsBlock and SK[idx] == "F" then return false end
        if not S.emergency and S.breathFrac and S.breathFrac < 0.12 then return false end
        local k = SK[idx]
        if S.holdSkills[idx] then
            S.holdFires = S.holdFires + 1
            task.spawn(function()
                U.keyDown(k); task.wait(F.HoldCastDuration); U.keyUp(k)
            end)
        else
            S.instantFires = S.instantFires + 1; U.tap(k)
        end
        S.gcdUntil = t + F.GCDWindow
        S.gcdHits = S.gcdHits + 1
        S.skC = (S.skC or 0) + 1
        S.comboFires = S.comboFires + 1
        return true
    end

    local function fireCombo(t, hp, now)
        if not S.skl then return end
        if not gcdReady(now) then return end
        local o = curOrder()
        if not o or #o == 0 then
            S.comboOrders = buildOrders()
            S.comboOrderIdx, S.comboPos = 1, 1; return
        end
        local idx = o[S.comboPos]
        if not idx then resetCombo(); return end
        fireSkill(idx, now)
        advanceCombo()
    end

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
        if t0 - S.lTele < F.TeleportCd then return false end
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
        if not pcall(function() r.CFrame = cf end) then
            S.teleFail = S.teleFail + 1; return false
        end
        pcall(function()
            r.AssemblyLinearVelocity = Vector3.new(
                (math.random()-0.5)*3, -4 - math.random()*3, (math.random()-0.5)*3)
        end)
        S.teleCount = S.teleCount + 1
        return true
    end

    local function inRange(t, tPos, myPos, now)
        if now - S.lInRangeChase < F.InRangeChaseT then return end
        S.lInRangeChase = now
        local r = U.hrp(); if not r then return end
        local dx = tPos.Position.X - myPos.X
        local dz = tPos.Position.Z - myPos.Z
        if dx*dx + dz*dz > 0.04 then
            pcall(function()
                r.CFrame = CFrame.new(myPos,
                    Vector3.new(tPos.Position.X, myPos.Y, tPos.Position.Z))
            end)
        end
    end

    local function dodge(now)
        if now - S.lDodge < F.DodgeCooldown then return false end
        S.lDodge = now; S.dodgeCount = S.dodgeCount + 1; U.tap("Q"); return true
    end

    local function chain(count)
        count = count or F.ComboBurst
        local gap = math.max(F.ComboGap, 1 / F.M1MaxHz)
        if S.blocking then blockRel() end
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
            S.comboTargetName = t.ch.Name; resetCombo()
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
            if #S.rHt > F.HitWindow then table.remove(S.rHt, 1) end
            if hit then S.aHi = (S.aHi or 0) + 1 else S.aMs = (S.aMs or 0) + 1 end
        end)
    end

    local function interval()
        if S.emergency then return F.EmergencyInterval end
        if #S.rHt < 5 then return S.aiI end
        local hits = 0
        for i = 1, #S.rHt do if S.rHt[i] then hits = hits + 1 end end
        local rate = hits / #S.rHt
        if rate > 0.7 then S.aiI = math.max(F.AtkIntMin, S.aiI - 0.03)
        elseif rate < 0.3 then S.aiI = math.min(F.AtkIntMax, S.aiI + 0.03) end
        return S.aiI
    end

    local function readBreath()
        local h = U.hum()
        if h then
            local ok, a = pcall(function() return h:GetAttribute("Breath") end)
            if ok and type(a) == "number" then
                local mOk, mx = pcall(function() return h:GetAttribute("MaxBreath") end)
                if mOk and type(mx) == "number" and mx > 0 then return a/mx end
            end
        end
    end

    local function partySize()
        local p = game:GetService("Players")
        local ok, c = pcall(function() return #p:GetPlayers() end)
        return (ok and c) or 1
    end

    local function acquire()
        local t, k = D.pickTarget()
        S.tgt, S.tgtKind = t, k
        if t then
            if S.comboTargetName ~= t.ch.Name then
                S.comboTargetName = t.ch.Name; resetCombo()
            end
            print(string.format("[Dingus] target %s (%s) @%.0f", t.ch.Name, k, t.d))
        end
        return t
    end

    local function resolveF()
        if S.fModeResolved then return end
        local mode = F.FKeyMode or "auto"
        if mode == "auto" then
            local w = 0
            while (not U.hrp() or S.cbt) and w < 15 do
                task.wait(0.5); w = w + 0.5
            end
            if S.cbt then
                S.fModeResolved = true; S.fIsBlock = false
                print("[Dingus][Atk] F-mode deferred"); return
            end
            local c = U.Lp.Character
            if c then
                U.keyDown("F"); task.wait(0.15)
                local ok1, v1 = pcall(function() return c:GetAttribute("IsBlocking") end)
                U.keyUp("F"); task.wait(0.05)
                S.fIsBlock = (ok1 and v1 == true)
                print("[Dingus][Atk] F-mode = " .. (S.fIsBlock and "BLOCK" or "SKILL"))
                S.comboOrders = buildOrders()
                S.comboOrderIdx, S.comboPos = 1, 1; logCombos()
            end
        else
            S.fIsBlock = (mode == "block")
            print("[Dingus][Atk] F-mode = " .. (S.fIsBlock and "BLOCK" or "SKILL"))
            S.comboOrders = buildOrders(); logCombos()
        end
        S.fModeResolved = true
    end
    task.spawn(resolveF)

    task.spawn(function()
        if not F.DetectHoldSkills then return end
        local w = 0
        while not S.fModeResolved and w < 20 do task.wait(0.25); w = w + 0.25 end
        w = 0
        while (not U.hrp() or S.cbt) and w < 30 do task.wait(0.5); w = w + 0.5 end
        if S.cbt then return end
        detectHold()
    end)

    local retreating = false
    local function retreat(from, reason)
        if retreating then return end
        retreating = true
        S.rtrC = (S.rtrC or 0) + 1
        S.cbtS = "RETREAT"; blockRel()
        -- Abort any in-progress loot cycle
        if Ctx.Chest and Ctx.Chest.abort then pcall(Ctx.Chest.abort) end
        S.lootCycleActive = false
        print(string.format("[Dingus][Atk] retreat (%s)", tostring(reason or "hp")))
        task.spawn(function()
            U.tap("Q"); task.wait(0.25)
            local r, h = U.hrp(), U.hum()
            if not r or not h then retreating = false; S.cbtS = "IDLE"; return end
            local away = r.Position - from
            local flat = Vector3.new(away.X, 0, away.Z)
            if flat.Magnitude < 0.5 then flat = Vector3.new(1,0,0) end
            h.WalkSpeed = F.RunSpeed
            local st = U.clock()
            local cap = st + 3.5
            local lhp = h.Health
            local ldt = st
            while U.clock() < st + F.RetreatDelay do
                local hh = U.hum(); if not hh then break end
                if hh.Health / hh.MaxHealth > F.RetreatClearHP then break end
                if hh.Health < lhp then lhp = hh.Health; ldt = U.clock() end
                if U.clock() - ldt > 1.5 and U.clock() > st + 0.8 then break end
                if U.clock() > cap then break end
                h:Move(flat.Unit); task.wait(0.05)
            end
            retreating = false; S.tgt = nil
            if D.invalidate then D.invalidate() end
        end)
    end

    --============================================================
    -- LOOT CYCLE SPAWNER
    --============================================================
    local function spawnBossLoot(bossPos, bossName)
        if not Ctx.Chest or not Ctx.Chest.collectAtBoss then return end
        if not F.ChestEnabled or not F.ChestOnKill then return end
        S.lootCycleActive = true
        S.lootCycleBossName = bossName
        task.spawn(function()
            local ok, err = pcall(Ctx.Chest.collectAtBoss, bossPos, bossName)
            if not ok then
                print("[Dingus][Atk] loot cycle error: " .. tostring(err))
            end
            S.lootCycleActive = false
            S.lootCycleBossName = nil
            -- Force target re-acquisition on next tick
            S.tgt = nil
            if D.invalidate then D.invalidate() end
        end)
    end

    --============================================================
    -- COMBAT TICK
    --============================================================
    function A.combatTick()
        if not S.cbt then
            S.cbtS = "IDLE"; blockRel()
            return
        end
        local h, r = U.hum(), U.hrp()
        if not h or not r then S.cbtS = "NO_CHAR"; return end
        if h.Health <= 0 then S.cbtS = "DEAD"; blockRel(); return end

        local now = U.clock()
        local hpFrac = h.Health / h.MaxHealth

        -- Critical retreat always runs, even during loot cycle
        S.critical = hpFrac < F.CriticalHP
        if S.critical and not retreating then
            local n = S.ths and S.ths[1]
            local from = n and n.rp.Position
                or (S.tgt and S.tgt.rp and S.tgt.rp.Position)
                or r.Position
            retreat(from, "critical"); return
        end

        S.emergency = (not S.critical) and hpFrac < F.EmergencyHP

        -- Regular retreat also interrupts loot
        if not S.emergency and S.rtr and hpFrac < F.RetreatHP and not retreating then
            local n = S.ths and S.ths[1]
            if n then retreat(n.rp.Position, "hp"); return end
        end
        if retreating then return end

        -- Loot cycle blocks all other behavior
        if S.lootCycleActive then
            S.cbtS = "LOOT"
            blockRel()
            return
        end

        equipWeapon()
        U.groundState()

        if now - S.lStateRefresh > 2.0 then
            S.lStateRefresh = now
            S.breathFrac = readBreath() or 1.0
            S.partySize = partySize()
        end

        if S.lastHp > 0 and h.Health < S.lastHp - 0.5 then
            if S.fIsBlock and F.AutoBlockOnDamage then
                S.damageBlockUntil = now + F.BlockReactionWindow
            end
        end
        S.lastHp = h.Health

        if now - S.lBrt > 2.5 then S.lBrt = now; U.tap("L") end

        -- Target management
        if not S.tgt or not S.tgt.ch.Parent or S.tgt.hm.Health <= 0 then
            if S.tgt then
                local bossPos = S.tgt.rp and S.tgt.rp.Position
                if not bossPos then
                    local rp = S.tgt.ch:FindFirstChild("HumanoidRootPart")
                    bossPos = rp and rp.Position
                end
                local bossName = S.tgt.ch.Name
                S.kll = (S.kll or 0) + 1
                S.bKll = (S.bKll or 0) + 1
                print(string.format("[Dingus] killed %s (%d)",
                    bossName, S.bKll))
                S.tgt = nil; S.comboTargetName = nil
                resetCombo(); blockRel()
                if D.invalidate then D.invalidate() end
                spawnBossLoot(bossPos, bossName)
            end
            -- Do NOT acquire new target during loot cycle
            if S.lootCycleActive then return end
            acquire()
            if not S.tgt then S.cbtS = "IDLE"; blockRel(); return end
        end

        local t = S.tgt
        local tPos = t.ch:FindFirstChild("HumanoidRootPart")
        if not tPos then S.tgt = nil; return end

        local myPos = r.Position
        local dist = U.xzDist(myPos, tPos.Position)
        t.d = dist

        local imm = (S.imm or 0) > 0
        local atk = D.isEnemyAttacking and D.isEnemyAttacking(t) or false

        if not (imm or atk) then
            if S.bossIdleSince == 0 then S.bossIdleSince = now end
        else
            S.bossIdleSince = 0; S.threatPeak = now
        end

        if dist > F.AtkRange then
            S.cbtS = "TELEPORT"; blockRel()
            teleport(t, tPos, myPos)
            fireCombo(t, hpFrac, now); return
        end

        inRange(t, tPos, myPos, now)
        local blocking = D.isEnemyBlocking(t)
        local stunned = D.isEnemyStunned(t)
        local tst = now - (S.threatPeak or 0)

        local forceBlock = false
        if S.fIsBlock and F.AutoBlockOnDamage and now < S.damageBlockUntil then
            if atk or imm then
                forceBlock = true
                S.blockHoldUntil = now + F.BlockHoldTTL
            else
                local idle = S.bossIdleSince > 0 and (now - S.bossIdleSince) or 0
                if idle < F.BlockGraceRelease then forceBlock = true end
            end
        end
        if S.emergency then forceBlock = false end

        if not S.emergency then
            local canDodge = (now - S.lDodge) > F.DodgeCooldown
            local tele = tst < F.TelegraphWindow
            if (imm or atk) and canDodge and tele then
                S.cbtS = "DODGE"; blockRel(); dodge(now); return
            end
        end

        if forceBlock then
            S.cbtS = "BLOCK"; blockHold()
            fireCombo(t, hpFrac, now); return
        end

        if stunned and S.stunPun then
            S.cbtS = "PUNISH"; blockRel()
            if now - S.lAtk >= F.StunAtkInt then S.lAtk = now; strike(t, now) end
            fireCombo(t, hpFrac, now); return
        end

        if blocking then
            S.cbtS = "BREAK"; blockRel()
            fireCombo(t, hpFrac, now)
            if now - S.lAtk > S.aiI * 1.2 then S.lAtk = now; strike(t, now) end
            return
        end

        S.cbtS = S.emergency and "EMERGENCY" or "STRIKE"
        blockRel()
        if now - S.lAtk >= interval() then S.lAtk = now; strike(t, now) end
        fireCombo(t, hpFrac, now)
    end

    --============================================================
    -- PUBLIC
    --============================================================
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
        return { resolved = S.fModeResolved, isBlock = S.fIsBlock, blocking = S.blocking }
    end

    function A.comboInfo()
        local o = curOrder()
        local n = {}
        if o then for _, idx in ipairs(o) do table.insert(n, SK[idx] or tostring(idx)) end end
        return {
            orders = #S.comboOrders, currentOrderIdx = S.comboOrderIdx,
            currentPos = S.comboPos, currentOrder = table.concat(n, " → "),
            rotations = S.comboRotations, totalFires = S.comboFires or 0,
        }
    end

    function A.reshuffleCombos()
        S.comboOrders = buildOrders()
        S.comboOrderIdx, S.comboPos, S.comboRotations = 1, 1, 0
        logCombos()
    end

    function A.telemetry()
        local holder = "no-module"
        if Ctx.Hotbar and Ctx.Hotbar.isLocked then
            holder = Ctx.Hotbar.isLocked() or "free"
        end
        return {
            teleports = S.teleCount or 0, dodges = S.dodgeCount or 0,
            gcdHits = S.gcdHits or 0, gcdMisses = S.gcdMisses or 0,
            comboFires = S.comboFires or 0, comboRotations = S.comboRotations or 0,
            holdFires = S.holdFires or 0, instantFires = S.instantFires or 0,
            holdSkills = S.holdSkills, emergency = S.emergency,
            critical = S.critical, blocking = S.blocking,
            breathFrac = S.breathFrac or 1.0, partySize = S.partySize or 1,
            lootActive = S.lootCycleActive,
            lootBoss = S.lootCycleBossName,
            equipped = S.eq, equipKey = S.eqKey, hotbarHolder = holder,
        }
    end

    function A.reprobeHoldSkills()
        S.holdDetected, S.holdDetecting, S.holdSkills = false, false, {}
        detectHold()
    end

    function A.lootNow()
        if Ctx.Chest and Ctx.Chest.collectAll then
            pcall(function() Ctx.Chest.collectAll() end)
        end
    end

    function A.scanPromptsNow()
        if Ctx.Chest and Ctx.Chest.dump then pcall(Ctx.Chest.dump) end
    end

    function A.refreshWeapon() S.lEqp = 0; S.equipFailCount = 0 end

    function A.abortLoot()
        if Ctx.Chest and Ctx.Chest.abort then pcall(Ctx.Chest.abort) end
        S.lootCycleActive = false
    end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function()
        blockRel()
        if Ctx.Chest and Ctx.Chest.abort then pcall(Ctx.Chest.abort) end
    end)

    print("[Dingus][attack] v19 initialized · boss-anchored loot cycle")
end

return A
