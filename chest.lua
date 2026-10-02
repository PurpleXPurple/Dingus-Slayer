-- Dingus-Slayer · chest.lua v8
-- Full Synerox loot / chest / soul collection.
-- Uses LootDrops folder + LootDrop/ Chest/ Soul/ Souls/ DemonSoul tags.

local Chest = {}

function Chest.init(Ctx)
    local U, F, S, L = Ctx.Util, Ctx.Cfg, Ctx.St, Ctx.Lists

    F.ChestEnabled = F.ChestEnabled ~= false
    F.ChestOnKill  = F.ChestOnKill ~= false
    F.ChestPassive = F.ChestPassive ~= false
    F.ChestLootOn  = F.ChestLootOn  ~= false
    F.ChestSoulsOn = F.ChestSoulsOn ~= false
    F.ChestChestsOn = F.ChestChestsOn ~= false
    F.ChestReachDist = F.ChestReachDist or 350
    F.ChestLootRadius = F.ChestLootRadius or 350
    F.ChestPassiveInterval = F.ChestPassiveInterval or 1.5
    F.ChestBossLootDelayMin = F.ChestBossLootDelayMin or 3.0
    F.ChestBossLootDelayMax = F.ChestBossLootDelayMax or 9.0
    F.ChestMaxPerSweep = F.ChestMaxPerSweep or 20

    S.chestCollected = S.chestCollected or 0
    S.chestLootCollected = S.chestLootCollected or 0
    S.chestFailed = S.chestFailed or 0
    S.chestCooldowns = S.chestCooldowns or {}
    S.chestRunning = false
    S.chestLastPassive = 0
    S.chestLastTargets = {}
    S.chestKilled = false
    S.chestSessionCount = 0

    local ok = false
    local CS = pcall(function() return game:GetService("CollectionService") end)
    local CollectionService
    if CS then
        local _, v = pcall(function() return game:GetService("CollectionService") end)
        CollectionService = v
    end

    --============================================================
    -- HELPERS
    --============================================================
    local function getLootDropsFolder()
        return workspace:FindFirstChild("LootDrops")
    end

    local function getChestsFolder()
        return workspace:FindFirstChild("Chests")
    end

    local function myUserId()
        return U.Lp.UserId
    end

    local function partOf(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst end
        return inst:FindFirstChild("Handle")
            or inst:FindFirstChild("Root")
            or inst:FindFirstChildWhichIsA("BasePart", true)
    end

    local function positionOf(inst)
        if not inst then return nil end
        local attr = inst:GetAttribute("DropTarget")
        if typeof(attr) == "Vector3" then return attr end
        local p = partOf(inst)
        if p then return p.Position end
        if inst:IsA("Model") then return inst:GetPivot().Position end
        return nil
    end

    local function isUnder(inst, name)
        return inst:FindFirstAncestor(name) ~= nil
    end

    --============================================================
    -- LOOT DROP CANDIDATE (Synerox fn38 inner)
    --============================================================
    local function isLootCandidate(inst, centerPos, radius)
        if not inst or not inst.Parent then return false end
        if isUnder(inst, "Regions") or isUnder(inst, "StationaryNpcs") then return false end
        if inst.Name == "Regions" or inst.Name == "Debree" then return false end
        if inst:GetAttribute("DropClaimedBy") ~= nil then return false end
        local lootDrops = getLootDropsFolder()
        local hasTag = CollectionService and CollectionService:HasTag(inst, "LootDrop")
        if not (inst:GetAttribute("DropItemId") ~= nil
                or (lootDrops and inst.Parent == lootDrops)
                or hasTag) then
            return false
        end
        -- Ownership check
        local owner = inst:GetAttribute("DropOwnerUserId")
        local reserved = inst:GetAttribute("DropReservedFor")
        local uid = myUserId()
        local ownerOk = (owner == nil or owner == uid or owner == 0)
        if reserved then
            local str = "," .. tostring(uid) .. ","
            if not string.find(tostring(reserved), str, 1, true) then
                ownerOk = false
            end
        end
        if not ownerOk then return false end
        local p = positionOf(inst)
        if not p then return false end
        if centerPos and (p - centerPos).Magnitude > (radius or 350) then return false end
        return true, p
    end

    --============================================================
    -- CHEST CANDIDATE (Synerox chest scan)
    --============================================================
    local function isChestPrompt(prompt, promptPos)
        if not prompt or not prompt:IsA("ProximityPrompt") then return false, nil end
        if not prompt.Parent then return false, nil end
        local actionText = string.lower(prompt.ActionText or "")
        local objectText = string.lower(prompt.ObjectText or "")
        local nameLower = string.lower(prompt.Name or "")
        -- Reject dialogue/trainers/shops
        for _, word in ipairs({"chat","talk","speak","train","buy","shop","quest","dialogue"}) do
            if actionText:find(word, 1, true) then return false, nil end
        end
        for _, word in ipairs({"trainer","urokodaki","muzan","npc","station","corps","slayer","shop"}) do
            if objectText:find(word, 1, true) then return false, nil end
        end
        -- Find chest state ancestor
        local parent = prompt.Parent
        local chestModel = nil
        local depth = 0
        local chestsFolder = getChestsFolder()
        while parent and parent ~= workspace and depth < 12 do
            if (chestsFolder and parent.Parent == chestsFolder)
               or parent:GetAttribute("ChestState") ~= nil
               or parent:GetAttribute("IsOpen") ~= nil
               or parent:GetAttribute("ChestId") ~= nil
               or parent:GetAttribute("ChestGuid") ~= nil then
                chestModel = parent
                break
            end
            parent = parent.Parent
            depth = depth + 1
        end
        -- Fallback: name matches
        if not chestModel
           and not nameLower:find("chest", 1, true)
           and not objectText:find("chest", 1, true)
           and not objectText:find("cache", 1, true)
           and not actionText:find("open", 1, true) then
            return false, nil
        end
        -- Skip open/despawned
        if chestModel then
            local state = chestModel:GetAttribute("ChestState")
            if chestModel:GetAttribute("IsOpen") == true
               or state == "Opened" or state == "Despawned" then
                return false, nil
            end
            if state == "Locked" and not prompt.Enabled then
                return false, nil
            end
            if string.lower(chestModel.Name or ""):find("mound", 1, true) then
                return false, nil
            end
        end
        return true, chestModel
    end

    --============================================================
    -- SOUL CANDIDATE (Synerox soul scan)
    --============================================================
    local function isSoulCandidate(inst, centerPos, radius)
        if not inst or not inst.Parent then return false, nil end
        if isUnder(inst, "StationaryNpcs") or isUnder(inst, "ActiveNpcs") then return false, nil end
        if inst:FindFirstChildOfClass("Humanoid") then return false, nil end
        local n = string.lower(inst.Name or "")
        local isSoul = n:find("soul", 1, true) ~= nil
            or n == "weak soul" or n == "strong soul" or n == "brave soul"
            or inst:GetAttribute("IsSoul") ~= nil
            or inst:GetAttribute("SoulType") ~= nil
        if not isSoul then return false, nil end
        local p = partOf(inst)
        local pos = p and p.Position or (inst:IsA("Model") and inst:GetPivot().Position)
        if not pos then return false, nil end
        if centerPos and (pos - centerPos).Magnitude > (radius or 250) then return false, nil end
        return true, pos, p
    end

    --============================================================
    -- FIRING
    --============================================================
    local function firePrompt(prompt, expectedKey)
        if not prompt or not prompt.Parent then return false end
        prompt.Enabled = true
        local holdDuration = prompt.HoldDuration
        local mad = prompt.MaxActivationDistance
        pcall(function()
            prompt.HoldDuration = 0
            prompt.MaxActivationDistance = 60
        end)
        if U.Fn.fireproximityprompt then
            pcall(U.Fn.fireproximityprompt, prompt, 0)
            pcall(U.Fn.fireproximityprompt, prompt)
        end
        -- Keyboard key
        local kc = prompt.KeyboardKeyCode
        if not kc or kc == Enum.KeyCode.Unknown then kc = expectedKey or Enum.KeyCode.T end
        U.keyDown(kc); task.wait(0.05); U.keyUp(kc)
        -- Restore
        pcall(function()
            prompt.HoldDuration = holdDuration
            prompt.MaxActivationDistance = mad
        end)
        return true
    end

    --============================================================
    -- APPROACH + COLLECT LOOT DROP (Synerox loot pickup)
    --============================================================
    local function collectLootDrop(drop, pos, part)
        local hrp = U.hrp()
        if not hrp then return false end
        local cf = CFrame.new(pos + Vector3.new(0, 1.2, 0))
        hrp.CFrame = cf
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        if Ctx.Fly and Ctx.Fly.movePlatform then pcall(Ctx.Fly.movePlatform, cf) end
        local prompt = drop:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then firePrompt(prompt) end
        if part and U.Fn.firetouchinterest then
            pcall(U.Fn.firetouchinterest, hrp, part, 0)
            task.wait(0.02)
            pcall(U.Fn.firetouchinterest, hrp, part, 1)
        end
        task.wait(0.14)
        -- Retry once if still not claimed
        if drop.Parent and drop:GetAttribute("DropClaimedBy") == nil then
            if prompt and prompt.Parent then
                prompt.Enabled = true
                pcall(U.Fn.fireproximityprompt, prompt, 0)
                pcall(U.Fn.fireproximityprompt, prompt)
            end
            if part and U.Fn.firetouchinterest then
                pcall(U.Fn.firetouchinterest, hrp, part, 0)
                task.wait(0.02)
                pcall(U.Fn.firetouchinterest, hrp, part, 1)
            end
            task.wait(0.08)
        end
        return drop:GetAttribute("DropClaimedBy") ~= nil
    end

    --============================================================
    -- SWEEP LOOT (Synerox main loot loop, simplified)
    --============================================================
    function Chest.sweepLoot(radius)
        if not F.ChestEnabled or not F.ChestLootOn then return 0 end
        local hrp = U.hrp(); if not hrp then return 0 end
        local lootDrops = getLootDropsFolder()
        local found = {}
        -- Enumerate LootDrops children
        if lootDrops then
            for _, child in ipairs(lootDrops:GetChildren()) do
                local ok, p = isLootCandidate(child, hrp.Position, radius)
                if ok then table.insert(found, { inst=child, pos=p, part=partOf(child) }) end
            end
        end
        -- Enumerate LootDrop tags
        if CollectionService then
            local tagged = CollectionService:GetTagged("LootDrop")
            for _, inst in ipairs(tagged) do
                if not lootDrops or inst.Parent ~= lootDrops then
                    local ok, p = isLootCandidate(inst, hrp.Position, radius)
                    if ok then table.insert(found, { inst=inst, pos=p, part=partOf(inst) }) end
                end
            end
        end
        if #found == 0 then return 0 end
        table.sort(found, function(a, b)
            return (hrp.Position - a.pos).Magnitude < (hrp.Position - b.pos).Magnitude
        end)
        local collected = 0
        for i = 1, math.min(#found, F.ChestMaxPerSweep or 20) do
            local d = found[i]
            if d.inst and d.inst.Parent and d.inst:GetAttribute("DropClaimedBy") == nil then
                if collectLootDrop(d.inst, d.pos, d.part) then
                    collected = collected + 1
                    S.chestLootCollected = S.chestLootCollected + 1
                end
            end
        end
        return collected
    end

    --============================================================
    -- SWEEP CHESTS (Synerox chest scan)
    --============================================================
    function Chest.sweepChests(radius)
        if not F.ChestEnabled or not F.ChestChestsOn then return 0 end
        local hrp = U.hrp(); if not hrp then return 0 end
        local out = {}
        local chestsFolder = getChestsFolder()
        if chestsFolder then
            for _, prompt in ipairs(chestsFolder:GetDescendants()) do
                if prompt:IsA("ProximityPrompt") then
                    local ok, model = isChestPrompt(prompt)
                    if ok then
                        local pos
                        local parent = prompt.Parent
                        if parent and parent:IsA("Attachment") then pos = parent.WorldPosition
                        elseif parent and parent:IsA("BasePart") then pos = parent.Position
                        elseif parent and parent:IsA("Model") then pos = parent:GetPivot().Position
                        elseif model then pos = model:GetPivot().Position end
                        if pos and (pos - hrp.Position).Magnitude <= (radius or 350) then
                            table.insert(out, { prompt=prompt, pos=pos, model=model })
                        end
                    end
                end
            end
        end
        if CollectionService then
            for _, model in ipairs(CollectionService:GetTagged("Chest")) do
                for _, prompt in ipairs(model:GetDescendants()) do
                    if prompt:IsA("ProximityPrompt") then
                        local ok, m = isChestPrompt(prompt)
                        if ok then
                            local pos = (m and m:GetPivot().Position) or prompt.Parent.Position
                            if pos and (pos - hrp.Position).Magnitude <= (radius or 350) then
                                table.insert(out, { prompt=prompt, pos=pos, model=m })
                            end
                        end
                    end
                end
            end
        end
        if #out == 0 then return 0 end
        table.sort(out, function(a, b)
            return (hrp.Position - a.pos).Magnitude < (hrp.Position - b.pos).Magnitude
        end)
        local fired = 0
        for i = 1, math.min(#out, 5) do
            local c = out[i]
            local hrp2 = U.hrp()
            if hrp2 then
                local cf = CFrame.new(c.pos + Vector3.new(0, 1.5, 2.5), c.pos)
                hrp2.CFrame = cf
                hrp2.AssemblyLinearVelocity = Vector3.zero
                hrp2.AssemblyAngularVelocity = Vector3.zero
                if Ctx.Fly and Ctx.Fly.movePlatform then pcall(Ctx.Fly.movePlatform, cf) end
            end
            task.wait(0.18)
            firePrompt(c.prompt)
            -- Wait up to 2.5s for chest to open
            local deadline = U.clock() + 2.5
            while U.clock() < deadline do
                local m = c.model
                if m then
                    local state = m:GetAttribute("ChestState")
                    if m:GetAttribute("IsOpen") == true or state == "Opened" then break end
                end
                task.wait(0.12)
            end
            fired = fired + 1
            S.chestCollected = S.chestCollected + 1
        end
        return fired
    end

    --============================================================
    -- SWEEP SOULS (Synerox soul scan)
    --============================================================
    function Chest.sweepSouls(radius)
        if not F.ChestEnabled or not F.ChestSoulsOn then return 0 end
        local hrp = U.hrp(); if not hrp then return 0 end
        local out = {}
        local function add(inst)
            local ok, pos, part = isSoulCandidate(inst, hrp.Position, radius or 250)
            if ok then table.insert(out, { inst=inst, pos=pos, part=part }) end
        end
        for _, child in ipairs(workspace:GetChildren()) do add(child) end
        local deb = workspace:FindFirstChild("Debree")
        if deb then
            for _, child in ipairs(deb:GetChildren()) do add(child) end
        end
        local ld = getLootDropsFolder()
        if ld then
            for _, child in ipairs(ld:GetChildren()) do add(child) end
        end
        if CollectionService then
            for _, tag in ipairs({"Soul","Souls","DemonSoul"}) do
                for _, inst in ipairs(CollectionService:GetTagged(tag)) do add(inst) end
            end
        end
        if #out == 0 then return 0 end
        table.sort(out, function(a, b)
            return (hrp.Position - a.pos).Magnitude < (hrp.Position - b.pos).Magnitude
        end)
        local collected = 0
        for i = 1, math.min(#out, 10) do
            local s = out[i]
            local hrp2 = U.hrp()
            if hrp2 then
                local cf = CFrame.new(s.pos + Vector3.new(0, 0.6, 0))
                hrp2.CFrame = cf
                hrp2.AssemblyLinearVelocity = Vector3.zero
                hrp2.AssemblyAngularVelocity = Vector3.zero
                if Ctx.Fly and Ctx.Fly.movePlatform then pcall(Ctx.Fly.movePlatform, cf) end
            end
            task.wait(0.08)
            local prompt = s.inst:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt then
                firePrompt(prompt)
            elseif s.part and U.Fn.firetouchinterest then
                pcall(U.Fn.firetouchinterest, U.hrp(), s.part, 0)
                task.wait(0.02)
                pcall(U.Fn.firetouchinterest, U.hrp(), s.part, 1)
            end
            task.wait(0.1)
            collected = collected + 1
            S.chestLootCollected = S.chestLootCollected + 1
        end
        return collected
    end

    --============================================================
    -- MASTER SWEEP — try chests → souls → loot
    --============================================================
    function Chest.sweep()
        local n = 0
        n = n + Chest.sweepChests()
        if n == 0 then n = n + Chest.sweepSouls() end
        if n == 0 then n = n + Chest.sweepLoot() end
        return n
    end

    --============================================================
    -- PASSIVE (main scheduler calls this)
    --============================================================
    function Chest.collectPassive()
        if not F.ChestEnabled or not F.ChestPassive then return end
        if S.chestRunning then return end
        local t = U.clock()
        if t - (S.chestLastPassive or 0) < (F.ChestPassiveInterval or 1.5) then return end
        S.chestLastPassive = t
        S.chestRunning = true
        pcall(function() Chest.sweep() end)
        S.chestRunning = false
    end

    --============================================================
    -- BOSS-CORPSE CYCLE (kept for attack.lua compat)
    --============================================================
    function Chest.collectAtBoss(bossPos, bossName)
        if not F.ChestEnabled or not F.ChestOnKill then return 0, 0 end
        if S.chestRunning then return 0, 0 end
        S.chestRunning = true
        local delay = (F.ChestBossLootDelayMin or 3.0)
            + math.random() * ((F.ChestBossLootDelayMax or 9.0) - (F.ChestBossLootDelayMin or 3.0))
        local waited = 0
        while waited < delay do
            if S.chestAbortRequest then
                S.chestAbortRequest = false
                S.chestRunning = false
                return 0, 0
            end
            local step = math.min(0.4, delay - waited)
            task.wait(step); waited = waited + step
        end
        -- Sweep chests / souls / loot around corpse
        local collected = 0
        collected = collected + (Chest.sweepChests() or 0)
        collected = collected + (Chest.sweepSouls() or 0)
        collected = collected + (Chest.sweepLoot() or 0)
        S.chestRunning = false
        return collected, collected
    end

    --============================================================
    -- PUBLIC
    --============================================================
    function Chest.scan(radius)
        local hrp = U.hrp(); if not hrp then return {} end
        local out = {}
        -- Loot
        local lootDrops = getLootDropsFolder()
        if lootDrops then
            for _, child in ipairs(lootDrops:GetChildren()) do
                local ok, p = isLootCandidate(child, hrp.Position, radius or 350)
                if ok then table.insert(out, { kind="loot", name=child.Name, pos=p, d=(hrp.Position-p).Magnitude }) end
            end
        end
        -- Chests
        local chestsFolder = getChestsFolder()
        if chestsFolder then
            for _, prompt in ipairs(chestsFolder:GetDescendants()) do
                if prompt:IsA("ProximityPrompt") then
                    local ok, model = isChestPrompt(prompt)
                    if ok then
                        local pos = model and model:GetPivot().Position or prompt.Parent.Position
                        table.insert(out, { kind="chest", name=model and model.Name or prompt.Name, pos=pos, d=(hrp.Position-pos).Magnitude })
                    end
                end
            end
        end
        -- Souls
        for _, child in ipairs(workspace:GetChildren()) do
            local ok, pos = isSoulCandidate(child, hrp.Position, 250)
            if ok then table.insert(out, { kind="soul", name=child.Name, pos=pos, d=(hrp.Position-pos).Magnitude }) end
        end
        table.sort(out, function(a,b) return a.d < b.d end)
        S.chestLastTargets = out
        return out
    end

    function Chest.lastTargets() return S.chestLastTargets end

    function Chest.dump()
        local list = Chest.scan()
        print(string.format("[Dingus][Chest] %d targets", #list))
        for i = 1, math.min(#list, 20) do
            local t = list[i]
            print(string.format("  [%s] %s @%.1f", t.kind, t.name, t.d))
        end
        return list
    end

    function Chest.stats()
        local cd = 0
        for _ in pairs(S.chestCooldowns or {}) do cd = cd + 1 end
        return {
            enabled = F.ChestEnabled,
            onKill = F.ChestOnKill, passive = F.ChestPassive,
            loot = F.ChestLootOn, souls = F.ChestSoulsOn, chests = F.ChestChestsOn,
            sessionCount = S.chestSessionCount or 0,
            collected = S.chestCollected or 0,
            lootCollected = S.chestLootCollected or 0,
            failed = S.chestFailed or 0,
            running = S.chestRunning,
            cooldowns = cd,
            lastTargets = #(S.chestLastTargets or {}),
        }
    end

    function Chest.setEnabled(v) F.ChestEnabled = not not v end
    function Chest.setLearnMode(_) end
    function Chest.resetCooldowns() S.chestCooldowns = {} end
    function Chest.resetKillswitch() S.chestKilled = false; S.chestSessionCount = 0 end
    function Chest.abort() S.chestAbortRequest = true end
    function Chest.approve(_) end
    function Chest.unapprove(_) end
    function Chest.listSeen() end
    function Chest.collectAll() return Chest.sweep(), 1 end

    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            Chest.resetCooldowns()
            S.chestAbortRequest = true
        end)
    end

    print(string.format(
        "[Dingus][chest] v8 · Synerox-loot · %s · prox=%s touch=%s cs=%s",
        U.Platform, tostring(U.Caps.proximity), tostring(U.Caps.touch),
        tostring(CollectionService ~= nil)))
end

return Chest
