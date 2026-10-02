--[[
    Dingus-Slayer · attack.lua v14
    ProximityPrompt-driven loot. Boss kill → 8s loot window → next boss.
    Combo engine, hotbar mutex, telegraph reaction all retained.
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
    Cfg.AtkIntMin      = Cfg.AtkIntMin      or 0.22
    Cfg.AtkIntMax      = Cfg.AtkIntMax      or 0.65
    Cfg.StunAtkInt     = Cfg.StunAtkInt     or 0.20
    Cfg.HitWindow      = Cfg.HitWindow      or 15
    Cfg.RunSpeed       = Cfg.RunSpeed       or 16

    Cfg.RetreatHP       = Cfg.RetreatHP       or 0.55
    Cfg.CriticalHP      = Cfg.CriticalHP      or 0.15
    Cfg.RetreatDelay    = Cfg.RetreatDelay    or 2.5
    Cfg.RetreatClearHP  = Cfg.RetreatClearHP  or 0.75

    Cfg.SkillKeys      = Cfg.SkillKeys      or { "F", "Z", "X", "C", "V", "B" }
    Cfg.SkillUnlocked  = Cfg.SkillUnlocked  or { true, true, true, true, true, true }
    Cfg.GCDWindow      = Cfg.GCDWindow      or 1.10

    Cfg.ComboOrderCount = Cfg.ComboOrderCount or 4
    Cfg.ComboReshuffleN = Cfg.ComboReshuffleN or 3

    Cfg.DetectHoldSkills    = Cfg.DetectHoldSkills    ~= false
    Cfg.HoldProbeDuration   = Cfg.HoldProbeDuration   or 1.30
    Cfg.HoldCastDuration    = Cfg.HoldCastDuration    or 1.20
    Cfg.HoldOverride        = Cfg.HoldOverride        or {}

    Cfg.AutoBlockOnDamage   = Cfg.AutoBlockOnDamage   ~= false
    Cfg.BlockReactionWindow = Cfg.BlockReactionWindow or 1.50
    Cfg.BlockGraceRelease   = Cfg.BlockGraceRelease   or 0.35

    Cfg.EmergencyHP         = Cfg.EmergencyHP         or 0.30
    Cfg.EmergencyInterval   = Cfg.EmergencyInterval   or 0.15

    Cfg.ChestEnabled        = Cfg.ChestEnabled        ~= false
    Cfg.LootRadius          = Cfg.LootRadius          or 30
    Cfg.LootMaxPasses       = Cfg.LootMaxPasses       or 4
    Cfg.LootPassDeadline    = Cfg.LootPassDeadline    or 8
    Cfg.LootPromptDepth     = Cfg.LootPromptDepth     or 4
    Cfg.LootTargetCooldown  = Cfg.LootTargetCooldown  or 45
    Cfg.LootVerbose         = Cfg.LootVerbose         or false
    Cfg.ChestKeywords       = Cfg.ChestKeywords       or {
        "chest", "cache", "crate",
    }
    Cfg.LootKeywords        = Cfg.LootKeywords        or {
        "coin", "pouch", "metal scrap", "refinement", "silk thread",
        "ore", "relic", "orb", "scroll", "totem",
        "drop", "loot", "pick up", "pickup",
    }

    Cfg.FKeyMode       = Cfg.FKeyMode       or "auto"
    Cfg.AutoBlock      = Cfg.AutoBlock      ~= false
    Cfg.BlockHoldTTL   = Cfg.BlockHoldTTL   or 0.4
    Cfg.BlockProbeWait = Cfg.BlockProbeWait or 0.15

    Cfg.TeleportCd         = Cfg.TeleportCd         or 0.22
    Cfg.TeleportStrike     = Cfg.TeleportStrike     or 4.5
    Cfg.TeleportHeight     = Cfg.TeleportHeight     or 3
    Cfg.TeleportJitter     = Cfg.TeleportJitter     or 2
    Cfg.TeleportWalkBlend  = Cfg.TeleportWalkBlend  or 0.6

    Cfg.ComboBurst         = Cfg.ComboBurst         or 4
    Cfg.ComboGap           = Cfg.ComboGap           or 0.11
    Cfg.DodgeCooldown      = Cfg.DodgeCooldown      or 0.65
    Cfg.InRangeChaseT      = Cfg.InRangeChaseT      or 0.22
    Cfg.TelegraphWindow    = Cfg.TelegraphWindow    or 0.45
    Cfg.M1MaxHz            = Cfg.M1MaxHz            or 10

    Cfg.WeaponHotbarOrder  = Cfg.WeaponHotbarOrder  or { "3", "4", "1", "5" }

    --============================================================
    -- STATE
    --============================================================
    St.rHt = {}
    St.gcdUntil = 0
    St.aiI = Cfg.AtkInterval

    St.lAtk = 0; St.lSkl = 0; St.lEqp = 0; St.lBrt = 0
    St.lDodge = 0; St.lTele = 0; St.lInRangeChase = 0
    St.lStateRefresh = 0; St.lChestScan = 0; St.lChestPassive = 0
    St.lLootSweep = 0

    St.eq = "none"
    St.cbtS = "IDLE"
    St.comboIndex = 0
    St.comboTargetName = nil
    St.swapPending = false

    St.fIsBlock = false
    St.fModeResolved = false
    St.blocking = false
    St.blockHoldUntil = 0

    St.holdSkills = {}
    St.holdDetected = false
    St.holdDetecting = false

    St.lastHp = 0
    St.damageBlockUntil = 0
    St.bossIdleSince = 0
    St.emergency = false
    St.critical = false

    -- Loot state
    St.chestCollected = 0
    St.lootCollected = 0
    St.lootSkipped = 0
    St.lootPasses = 0
    St.lootTargetCooldowns = {}   -- [instance] = expiry

    St.teleCount = 0; St.teleFail = 0; St.dodgeCount = 0
    St.gcdHits = 0; St.gcdMisses = 0
    St.holdFires = 0; St.instantFires = 0
    St.comboFires = 0; St.comboRotations = 0

    St.breathFrac = 1.0
    St.partySize = 1

    local SK_KEYS = Cfg.SkillKeys
    local SKILL_COUNT = #SK_KEYS

    --============================================================
    -- COMBO ENGINE
    --============================================================
    local function buildPermutation()
        local pool = {}
        for i = 1, SKILL_COUNT do
            if not (St.fIsBlock and SK_KEYS[i] == "F")
               and Cfg.SkillUnlocked[i] then
                table.insert(pool, i)
            end
        end
        for i = #pool, 2, -1 do
            local j = math.random(1, i)
            pool[i], pool[j] = pool[j], pool[i]
        end
        return pool
    end

    local function buildComboOrders()
        local orders, seen, attempts = {}, {}, 0
        while #orders < Cfg.ComboOrderCount and attempts < 50 do
            attempts = attempts + 1
            local perm = buildPermutation()
            local key = table.concat(perm, ",")
            if not seen[key] and #perm > 0 then
                seen[key] = true
                table.insert(orders, perm)
            end
        end
        return orders
    end

    St.comboOrders = buildComboOrders()
    St.comboOrderIdx = 1
    St.comboPos = 1
    St.comboRotations = 0

    local function logCombos()
        print("[Dingus][Atk] combo orders:")
        for i, order in ipairs(St.comboOrders) do
            local names = {}
            for _, idx in ipairs(order) do
                table.insert(names, SK_KEYS[idx])
            end
            print(string.format("  %d: %s", i, table.concat(names, " → ")))
        end
    end
    logCombos()

    local function currentOrder() return St.comboOrders[St.comboOrderIdx] end

    local function advanceCombo()
        local order = currentOrder()
        if not order or #order == 0 then
            St.comboOrderIdx = 1
            St.comboPos = 1
            return
        end
        St.comboPos = St.comboPos + 1
        if St.comboPos > #order then
            St.comboRotations = St.comboRotations + 1
            St.comboOrderIdx = St.comboOrderIdx + 1
            St.comboPos = 1
            if St.comboOrderIdx > #St.comboOrders then
                St.comboOrderIdx = 1
                if St.comboRotations >= Cfg.ComboReshuffleN then
                    St.comboOrders = buildComboOrders()
                    St.comboRotations = 0
                    print("[Dingus][Atk] combos reshuffled")
                    logCombos()
                end
            end
        end
    end

    local function resetCombo() St.comboPos = 1 end

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
        if h then h.PlatformStand = false; h.AutoRotate = true end
    end
    scrubMovers()
    U.Lp.CharacterAdded:Connect(function()
        task.wait(1)
        scrubMovers()
        St.blocking = false
        St.blockHoldUntil = 0
        St.fModeResolved = false
        St.comboTargetName = nil
        resetCombo()
    end)

    --============================================================
    -- ANIMATION READER
    --============================================================
    local function readAttackAnim()
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
                        if not string.find(l, "idle", 1, true)
                            and not string.find(l, "walk", 1, true)
                            and not string.find(l, "run", 1, true) then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    local function holdProbeOne(idx)
        local override = Cfg.HoldOverride[idx]
        if override ~= nil then return override end
        if St.fIsBlock and SK_KEYS[idx] == "F" then return false end
        if not Cfg.SkillUnlocked[idx] then return false end
        local h = U.hum()
        if not h or h.Health <= 0 then return false end
        local prevGcd = St.gcdUntil
        St.gcdUntil = U.clock() + Cfg.GCDWindow
        local k = SK_KEYS[idx]
        U.keyDown(k)
        task.wait(Cfg.HoldProbeDuration)
        local ch = readAttackAnim()
        U.keyUp(k)
        task.wait(0.15)
        if St.gcdUntil < prevGcd then St.gcdUntil = prevGcd end
        return ch
    end

    local function detectHoldSkills()
        if St.holdDetected or St.holdDetecting then return end
        St.holdDetecting = true
        print("[Dingus][Atk] probing hold-cast skills...")
        local hold, instant = {}, {}
        for i = 1, SKILL_COUNT do
            local isHold = holdProbeOne(i)
            St.holdSkills[i] = isHold
            if isHold then table.insert(hold, i)
            else table.insert(instant, i) end
            task.wait(0.3)
        end
        print(string.format("[Dingus][Atk] hold: [%s] instant: [%s]",
            table.concat(hold, ","), table.concat(instant, ",")))
        St.comboOrders = buildComboOrders()
        St.comboOrderIdx = 1; St.comboPos = 1; St.comboRotations = 0
        logCombos()
        St.holdDetected = true
        St.holdDetecting = false
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
        local rh = c:FindFirstChild("RightHand")
        if rh then
            for _, child in ipairs(rh:GetChildren()) do
                if not L.isCrow(child.Name) then return child end
            end
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

    local function equipWeapon()
        if St.swapPending then return end
        if Ctx.Quest and Ctx.Quest.stats then
            local qs = Ctx.Quest.stats()
            if qs.panelOpen then return end
        end
        local H = Ctx.Hotbar
        if H and H.isLocked() then return end
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
                St.swapPending = true
                task.spawn(function()
                    pcall(function() h:EquipTool(t) end)
                    St.eq = t.Name
                    St.swapPending = false
                end)
                return
            end
        end
        St.swapPending = true
        task.spawn(function()
            if not H or not H.acquire("attack-weapon", 3.0) then
                St.swapPending = false
                return
            end
            for _, k in ipairs(Cfg.WeaponHotbarOrder or {"3"}) do
                pcall(function() U.tap(k) end)
                task.wait(0.4)
                local eq = equippedTool()
                if eq and not L.isCrow(eq.Name) then
                    St.eq = eq.Name
                    H.release("attack-weapon")
                    St.swapPending = false
                    return
                end
            end
            H.release("attack-weapon")
            St.swapPending = false
        end)
    end

    --============================================================
    -- SKILL FIRING
    --============================================================
    local function gcdReady(now) return now >= St.gcdUntil end

    local function fireSkill(idx, now)
        if not gcdReady(now) then
            St.gcdMisses = St.gcdMisses + 1
            return false
        end
        if not Cfg.SkillUnlocked[idx] then return false end
        if St.fIsBlock and SK_KEYS[idx] == "F" then return false end
        if not St.emergency and St.breathFrac and St.breathFrac < 0.12 then
            return false
        end
        local k = SK_KEYS[idx]
        local isHold = St.holdSkills[idx]
        if isHold then
            St.holdFires = St.holdFires + 1
            task.spawn(function()
                U.keyDown(k)
                task.wait(Cfg.HoldCastDuration)
                U.keyUp(k)
            end)
        else
            St.instantFires = St.instantFires + 1
            U.tap(k)
        end
        St.gcdUntil = now + Cfg.GCDWindow
        St.gcdHits = St.gcdHits + 1
        St.skC = (St.skC or 0) + 1
        St.comboFires = St.comboFires + 1
        return true
    end

    local function fireCombo(t, hpFrac, now)
        if not St.skl then return end
        if not gcdReady(now) then return end
        local order = currentOrder()
        if not order or #order == 0 then
            St.comboOrders = buildComboOrders()
            St.comboOrderIdx = 1; St.comboPos = 1
            return
        end
        local idx = order[St.comboPos]
        if not idx then resetCombo(); return end
        if fireSkill(idx, now) then
            advanceCombo()
        else
            advanceCombo()
        end
    end

    --============================================================
    -- SAFE CFrame / TELEPORT
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

    local function teleportChase(t, tPos, myPos)
        local r = U.hrp()
        if not r then return false end
        local now = U.clock()
        if now - St.lTele < Cfg.TeleportCd then return false end
        St.lTele = now
        local targetPos = tPos.Position
        local approach = targetPos - myPos
        local flatApproach = Vector3.new(approach.X, 0, approach.Z)
        if flatApproach.Magnitude < 0.1 then flatApproach = Vector3.new(1, 0, 0) end
        flatApproach = flatApproach.Unit
        local side = Vector3.new(-flatApproach.Z, 0, flatApproach.X)
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
        if not ok then St.teleFail = St.teleFail + 1; return false end
        pcall(function()
            r.AssemblyLinearVelocity = Vector3.new(
                (math.random() - 0.5) * 3, -4 - math.random() * 3,
                (math.random() - 0.5) * 3)
        end)
        St.teleCount = St.teleCount + 1
        return true
    end

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
    end

    local function tryDodge(now)
        if now - St.lDodge < Cfg.DodgeCooldown then return false end
        St.lDodge = now
        St.dodgeCount = St.dodgeCount + 1
        U.tap("Q")
        return true
    end

    --============================================================
    -- CHAINED STRIKE
    --============================================================
    local function doChainedStrike(count)
        count = count or Cfg.ComboBurst
        local gap = math.max(Cfg.ComboGap, 1 / Cfg.M1MaxHz)
        if St.blocking then releaseBlock() end
        task.spawn(function()
            for i = 1, count do
                if i % 2 == 0 then U.m2() else U.m1() end
                if i < count then task.wait(gap) end
            end
        end)
    end

    local function strike(t, now)
        St.aAt = (St.aAt or 0) + 1
        local hpBefore = t.hm.Health
        if St.comboTargetName ~= t.ch.Name then
            St.comboTargetName = t.ch.Name
            resetCombo()
        end
        St.comboIndex = St.comboIndex + 1
        local chain = Cfg.ComboBurst
        if St.emergency then chain = chain + 2 end
        if St.comboIndex % 4 == 0 then chain = chain + 1 end
        doChainedStrike(chain)
        local tool = equippedTool()
        if tool then pcall(function() tool:Activate() end) end
        task.spawn(function()
            task.wait(0.35)
            if not (t and t.hm and t.hm.Parent) then return end
            local hit = t.hm.History < hpBefore
            table.insert(St.rHt, hit)
            if #St.rHt > Cfg.HitWindow then table.remove(St.rHt, 1) end
            if hit then St.aHi = (St.aHi or 0) + 1
            else St.aMs = (St.aMs or 0) + 1 end
        end)
    end

    local function currentInterval()
        if St.emergency then return Cfg.EmergencyInterval end
        if #St.rHt < 5 then return St.aiI end
        local hits = 0
        for i = 1, #St.rHt do if St.rHt[i] then hits = hits + 1 end end
        local rate = hits / #St.rHt
        if rate > 0.7 then St.aiI = math.max(Cfg.AtkIntMin, St.aiI - 0.03)
        elseif rate < 0.3 then St.aiI = math.min(Cfg.AtkIntMax, St.aiI + 0.03) end
        return St.aiI
    end

    local function readBreath()
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
        return nil
    end

    local function readPartySize()
        local plr = game:GetService("Players")
        local ok, count = pcall(function() return #plr:GetPlayers() end)
        return (ok and count) or 1
    end

    --============================================================
    -- LOOT · ProximityPrompt-driven
    --============================================================
    local function hasKeyword(str, list)
        if not str then return false end
        local l = string.lower(str)
        for i = 1, #list do
            if string.find(l, list[i], 1, true) then return true end
        end
        return false
    end

    local function promptPos(prompt)
        local parent = prompt.Parent
        if not parent then return nil end
        if parent:IsA("BasePart") then return parent.Position end
        if parent:IsA("Attachment") and parent.Parent
           and parent.Parent:IsA("BasePart") then
            return parent.Parent.Position
        end
        if parent:IsA("Model") then
            if parent.PrimaryPart then return parent.PrimaryPart.Position end
            local any = parent:FindFirstChildWhichIsA("BasePart")
            if any then return any.Position end
        end
        return nil
    end

    local function promptIsCooling(prompt, now)
        local exp = St.lootTargetCooldowns[prompt]
        if exp and now < exp then return true end
        if exp and now >= exp then St.lootTargetCooldowns[prompt] = nil end
        return false
    end

    local function scanPrompts(maxDist)
        local r = U.hrp()
        if not r then return {} end
        local myPos = r.Position
        local out = {}
        local stack = { { workspace, 0 } }
        local iter = 0
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, depth = item[1], item[2]
            if inst and depth <= (Cfg.LootPromptDepth or 4) then
                if inst:IsA("ProximityPrompt") then
                    local pos = promptPos(inst)
                    if pos then
                        local d = (pos - myPos).Magnitude
                        if d <= maxDist then
                            local name = (inst.ObjectText or "")
                                .. " " .. (inst.ActionText or "")
                            local kind = nil
                            if hasKeyword(name, Cfg.ChestKeywords) then
                                kind = "chest"
                            elseif hasKeyword(name, Cfg.LootKeywords) then
                                kind = "loot"
                            end
                            if kind then
                                table.insert(out, {
                                    prompt = inst,
                                    parent = inst.Parent,
                                    dist = d,
                                    kind = kind,
                                    name = name,
                                    pos = pos,
                                })
                            end
                        end
                    end
                end
                for _, c in ipairs(inst:GetChildren()) do
                    table.insert(stack, { c, depth + 1 })
                end
                iter = iter + 1
                if iter % 3000 == 0 then task.wait() end
            end
        end
        table.sort(out, function(a, b) return a.dist < b.dist end)
        return out
    end

    local function firePrompt(prompt)
        if type(fireproximityprompt) == "function" then
            local ok = pcall(fireproximityprompt, prompt)
            if ok then return true end
        end
        -- Hold duration fallback
        local ok = pcall(function()
            if prompt.InputHoldBegin then prompt:InputHoldBegin() end
            task.wait(prompt.HoldDuration or 0.1)
            if prompt.InputHoldEnd then prompt:InputHoldEnd() end
        end)
        if ok then return true end
        -- Move + tap T
        local r = U.hrp()
        local pos = promptPos(prompt)
        if r and pos then
            pcall(function()
                local flat = Vector3.new(pos.X - r.Position.X, 0, pos.Z - r.Position.Z)
                if flat.Magnitude > 0.5 then
                    local dest = r.Position + flat.Unit * math.max(0, flat.Magnitude - 3)
                    r.CFrame = CFrame.new(Vector3.new(dest.X, r.Position.Y, dest.Z),
                                          Vector3.new(pos.X, r.Position.Y, pos.Z))
                end
            end)
            task.wait(0.1)
            U.tap("T")
            return true
        end
        return false
    end

    local function moveToPos(pos)
        local r = U.hrp()
        if not r or not pos then return end
        local approach = pos - r.Position
        local flat = Vector3.new(approach.X, 0, approach.Z)
        if flat.Magnitude < 0.5 then return end
        local dest = r.Position + flat.Unit * math.max(0, flat.Magnitude - 4)
        dest = Vector3.new(dest.X, r.Position.Y, dest.Z)
        local cf = safeCFrame(dest, pos)
        pcall(function() r.CFrame = cf end)
        task.wait(0.12)
    end

    -- Single sweep: find all chest+loot prompts within radius, fire them
    local function lootSweep(radius)
        local now = U.clock()
        local prompts = scanPrompts(radius)
        if #prompts == 0 then return 0 end

        local fired = 0
        for i = 1, #prompts do
            local p = prompts[i]
            if p.prompt and p.prompt.Parent
               and not promptIsCooling(p.prompt, now) then
                moveToPos(p.pos)
                local ok = firePrompt(p.prompt)
                if ok then
                    fired = fired + 1
                    if p.kind == "chest" then
                        St.chestCollected = (St.chestCollected or 0) + 1
                        print(string.format("[Dingus][Loot] chest opened: %s",
                            (p.name or ""):gsub("^%s+", "")))
                    else
                        St.lootCollected = (St.lootCollected or 0) + 1
                    end
                else
                    St.lootSkipped = (St.lootSkipped or 0) + 1
                    St.lootTargetCooldowns[p.prompt] = now + (Cfg.LootTargetCooldown or 45)
                end
                task.wait(0.06)
            end
        end
        return fired
    end

    -- Full loot cycle after a kill. Deadline-capped.
    local function lootBossDrop()
        if not Cfg.ChestEnabled then return end
        local startT = U.clock()
        local deadline = startT + (Cfg.LootPassDeadline or 8)
        local totalFired = 0
        local emptyPasses = 0
        local pass = 0
        local maxPasses = Cfg.LootMaxPasses or 4

        while U.clock() < deadline and pass < maxPasses and emptyPasses < 2 do
            pass = pass + 1
            St.lootPasses = (St.lootPasses or 0) + 1
            local fired = lootSweep(Cfg.LootRadius or 30)
            totalFired = totalFired + fired
            if fired == 0 then
                emptyPasses = emptyPasses + 1
            else
                emptyPasses = 0
            end
            task.wait(0.3)
        end

        if totalFired > 0 then
            print(string.format("[Dingus][Loot] cycle done · fired=%d passes=%d",
                totalFired, pass))
        else
            if Cfg.LootVerbose then
                print("[Dingus][Loot] no loot found within radius")
            end
        end
    end

    local function lootPassive()
        if not Cfg.ChestEnabled then return end
        if St.tgt then return end
        local fired = lootSweep(Cfg.LootRadius or 30)
        if fired > 0 and Cfg.LootVerbose then
            print(string.format("[Dingus][Loot] passive · %d", fired))
        end
    end

    --============================================================
    -- TARGET ACQUISITION
    --============================================================
    local function acquireTarget()
        local tgt, kind = D.pickTarget()
        St.tgt = tgt
        St.tgtKind = kind
        if tgt then
            if St.comboTargetName ~= tgt.ch.Name then
                St.comboTargetName = tgt.ch.Name
                resetCombo()
            end
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
            local c = U.Lp.Character
            if c then
                U.keyDown("F")
                task.wait(0.15)
                local ok1, v1 = pcall(function() return c:GetAttribute("IsBlocking") end)
                U.keyUp("F")
                task.wait(0.05)
                if ok1 and v1 == true then
                    St.fIsBlock = true
                    print("[Dingus][Atk] F-mode = BLOCK")
                else
                    St.fIsBlock = false
                    print("[Dingus][Atk] F-mode = SKILL")
                end
                St.comboOrders = buildComboOrders()
                St.comboOrderIdx = 1; St.comboPos = 1
                logCombos()
            end
        elseif mode == "block" then
            St.fIsBlock = true
            print("[Dingus][Atk] F-mode = BLOCK (config)")
            St.comboOrders = buildComboOrders(); logCombos()
        else
            St.fIsBlock = false
            print("[Dingus][Atk] F-mode = SKILL (config)")
            St.comboOrders = buildComboOrders(); logCombos()
        end
        St.fModeResolved = true
    end
    task.spawn(resolveFMode)

    task.spawn(function()
        if not Cfg.DetectHoldSkills then return end
        local waited = 0
        while not St.fModeResolved and waited < 20 do
            task.wait(0.25); waited = waited + 0.25
        end
        waited = 0
        while (not U.hrp() or St.cbt) and waited < 30 do
            task.wait(0.5); waited = waited + 0.5
        end
        if St.cbt then return end
        detectHoldSkills()
    end)

    --============================================================
    -- RETREAT
    --============================================================
    local retreatRunning = false

    local function startRetreat(from, reason)
        if retreatRunning then return end
        retreatRunning = true
        St.rtrC = (St.rtrC or 0) + 1
        St.cbtS = "RETREAT"
        releaseBlock()
        print(string.format("[Dingus][Atk] retreat (%s)", tostring(reason or "hp")))
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
            local hardCap = startT + 3.5
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
                if U.clock() - lastDamageT > 1.5 and U.clock() > startT + 0.8 then break end
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
    -- COMBAT TICK
    --============================================================
    function A.combatTick()
        if not St.cbt then
            St.cbtS = "IDLE"
            releaseBlock()
            if Cfg.ChestEnabled and (U.clock() - St.lChestPassive > 15) then
                St.lChestPassive = U.clock()
                pcall(lootPassive)
            end
            return
        end

        local h = U.hum()
        local r = U.hrp()
        if not h or not r then St.cbtS = "NO_CHAR"; return end
        if h.Health <= 0 then St.cbtS = "DEAD"; releaseBlock(); return end

        local now = U.clock()
        local hpFrac = h.Health / h.MaxHealth

        St.critical = hpFrac < Cfg.CriticalHP
        if St.critical and not retreatRunning then
            local nearest = St.ths and St.ths[1]
            local from = nearest and nearest.rp.Position
                or (St.tgt and St.tgt.rp and St.tgt.rp.Position)
                or r.Position
            startRetreat(from, "critical")
            return
        end

        St.emergency = (not St.critical) and hpFrac < Cfg.EmergencyHP

        equipWeapon()
        U.groundState()

        if now - St.lStateRefresh > 2.0 then
            St.lStateRefresh = now
            St.breathFrac = readBreath() or 1.0
            St.partySize = readPartySize()
        end

        if St.lastHp > 0 and h.Health < St.lastHp - 0.5 then
            if St.fIsBlock and Cfg.AutoBlockOnDamage then
                St.damageBlockUntil = now + Cfg.BlockReactionWindow
            end
        end
        St.lastHp = h.Health

        if now - St.lBrt > 2.5 then St.lBrt = now; U.tap("L") end

        if not St.emergency and St.rtr and hpFrac < Cfg.RetreatHP
           and not retreatRunning then
            local nearest = St.ths and St.ths[1]
            if nearest then startRetreat(nearest.rp.Position, "hp"); return end
        end
        if retreatRunning then return end

        -- Passive loot — only when no target engaged
        if Cfg.ChestEnabled and not St.tgt
           and (now - St.lChestPassive) > 15 then
            St.lChestPassive = now
            pcall(lootPassive)
        end

        -- Target management
        if not St.tgt or not St.tgt.ch.Parent or St.tgt.hm.Health <= 0 then
            if St.tgt then
                St.kll = (St.kll or 0) + 1
                St.bKll = (St.bKll or 0) + 1
                print(string.format("[Dingus] killed %s (%d)",
                    St.tgt.ch.Name, St.bKll))
                St.tgt = nil
                St.comboTargetName = nil
                resetCombo()
                releaseBlock()
                if D.invalidate then D.invalidate() end

                -- Full loot cycle before next target
                if Cfg.ChestEnabled then
                    pcall(lootBossDrop)
                end
            end

            acquireTarget()
            if not St.tgt then St.cbtS = "IDLE"; releaseBlock(); return end
        end

        local t = St.tgt
        local tPos = t.ch:FindFirstChild("HumanoidRootPart")
        if not tPos then St.tgt = nil; return end

        local myPos = r.Position
        local dist = U.xzDist(myPos, tPos.Position)
        t.d = dist

        local imminent = (St.imm or 0) > 0
        local bossAttacking = false
        if D.isEnemyAttacking then bossAttacking = D.isEnemyAttacking(t) end

        if not (imminent or bossAttacking) then
            if St.bossIdleSince == 0 then St.bossIdleSince = now end
        else
            St.bossIdleSince = 0
            St.threatPeak = now
        end

        if dist > Cfg.AtkRange then
            St.cbtS = "TELEPORT"
            releaseBlock()
            teleportChase(t, tPos, myPos)
            fireCombo(t, hpFrac, now)
            return
        end

        inRangeChase(t, tPos, myPos, now)

        local blocking = D.isEnemyBlocking(t)
        local stunned = D.isEnemyStunned(t)
        local timeSinceThreat = now - (St.threatPeak or 0)

        local forceBlock = false
        if St.fIsBlock and Cfg.AutoBlockOnDamage then
            if now < St.damageBlockUntil then
                if bossAttacking or imminent then
                    forceBlock = true
                    St.blockHoldUntil = now + Cfg.BlockHoldTTL
                else
                    local idleDur = St.bossIdleSince > 0 and (now - St.bossIdleSince) or 0
                    if idleDur < Cfg.BlockGraceRelease then forceBlock = true end
                end
            end
        end
        if St.emergency then forceBlock = false end

        if not St.emergency then
            local canDodge = (now - St.lDodge) > Cfg.DodgeCooldown
            local telegraph = timeSinceThreat < Cfg.TelegraphWindow
            if (imminent or bossAttacking) and canDodge and telegraph then
                St.cbtS = "DODGE"
                releaseBlock()
                tryDodge(now)
                return
            end
        end

        if forceBlock then
            St.cbtS = "BLOCK"
            holdBlock()
            fireCombo(t, hpFrac, now)
            return
        end

        if stunned and St.stunPun then
            St.cbtS = "PUNISH"
            releaseBlock()
            if now - St.lAtk >= Cfg.StunAtkInt then
                St.lAtk = now
                strike(t, now)
            end
            fireCombo(t, hpFrac, now)
            return
        end

        if blocking then
            St.cbtS = "BREAK"
            releaseBlock()
            fireCombo(t, hpFrac, now)
            if now - St.lAtk > St.aiI * 1.2 then
                St.lAtk = now
                strike(t, now)
            end
            return
        end

        St.cbtS = St.emergency and "EMERGENCY" or "STRIKE"
        releaseBlock()
        if now - St.lAtk >= currentInterval() then
            St.lAtk = now
            strike(t, now)
        end
        fireCombo(t, hpFrac, now)
    end

    --============================================================
    -- PUBLIC
    --============================================================
    function A.forceScan()
        if D.invalidate then D.invalidate() end
        local list = D.scanBosses(nil, true)
        print(string.format("[Dingus] force scan: %d bosses", #list))
    end

    function A.forceMove()
        if not St.tgt then return end
        local r = U.hrp()
        local tPos = St.tgt.ch:FindFirstChild("HumanoidRootPart")
        if r and tPos then
            local dest = tPos.Position + Vector3.new(0, 3, 0)
            pcall(function() r.CFrame = safeCFrame(dest, tPos.Position) end)
        end
    end

    function A.fModeInfo()
        return {
            resolved = St.fModeResolved,
            isBlock = St.fIsBlock,
            blocking = St.blocking,
        }
    end

    function A.comboInfo()
        local order = currentOrder()
        local names = {}
        if order then
            for _, idx in ipairs(order) do
                table.insert(names, SK_KEYS[idx] or tostring(idx))
            end
        end
        return {
            orders = #St.comboOrders,
            currentOrderIdx = St.comboOrderIdx,
            currentPos = St.comboPos,
            currentOrder = table.concat(names, " → "),
            rotations = St.comboRotations,
            totalFires = St.comboFires or 0,
        }
    end

    function A.reshuffleCombos()
        St.comboOrders = buildComboOrders()
        St.comboOrderIdx = 1; St.comboPos = 1; St.comboRotations = 0
        logCombos()
    end

    function A.telemetry()
        local holder = "no-module"
        if Ctx.Hotbar and Ctx.Hotbar.isLocked then
            holder = Ctx.Hotbar.isLocked() or "free"
        end
        return {
            teleports = St.teleCount or 0,
            dodges = St.dodgeCount or 0,
            gcdHits = St.gcdHits or 0,
            gcdMisses = St.gcdMisses or 0,
            comboFires = St.comboFires or 0,
            comboRotations = St.comboRotations or 0,
            holdFires = St.holdFires or 0,
            instantFires = St.instantFires or 0,
            holdSkills = St.holdSkills,
            emergency = St.emergency,
            critical = St.critical,
            blocking = St.blocking,
            breathFrac = St.breathFrac or 1.0,
            partySize = St.partySize or 1,
            chestsCollected = St.chestCollected or 0,
            lootCollected = St.lootCollected or 0,
            lootSkipped = St.lootSkipped or 0,
            lootPasses = St.lootPasses or 0,
            equipped = St.eq,
            hotbarHolder = holder,
        }
    end

    function A.reprobeHoldSkills()
        St.holdDetected = false
        St.holdDetecting = false
        St.holdSkills = {}
        detectHoldSkills()
    end

    function A.lootNow()
        pcall(lootBossDrop)
    end

    function A.scanPromptsNow()
        local list = scanPrompts(Cfg.LootRadius or 30)
        print(string.format("[Dingus][Loot] %d prompts within radius:", #list))
        for i = 1, math.min(#list, 10) do
            local p = list[i]
            print(string.format("  [%s] %s @ %.0f",
                p.kind, (p.name or ""):gsub("^%s+", ""), p.dist))
        end
        return list
    end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function() releaseBlock() end)

    print("[Dingus][attack] v14 initialized · ProximityPrompt loot")
end

return A
