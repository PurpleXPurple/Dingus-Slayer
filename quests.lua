-- Dingus-Slayer · quests.lua v9
-- Full Synerox quest pipeline + crow panel reader.
-- Handles: auto-accept (NPC dialogue), auto-abandon, level tracking,
-- race filtering, best-quest pick, crow priority routing, force accept.

local Q = {}

function Q.init(Ctx)
    local U, F, S, L = Ctx.Util, Ctx.Cfg, Ctx.St, Ctx.Lists

    --========================================================
    -- CONFIG DEFAULTS
    --========================================================
    F.QuestCrowHotbar    = F.QuestCrowHotbar or "5"
    F.QuestMenuWait      = F.QuestMenuWait or 2.5
    F.QuestPriorityStale = F.QuestPriorityStale or 90
    F.QuestPanelCacheT   = F.QuestPanelCacheT or 1.0
    F.QuestCrowCacheT    = F.QuestCrowCacheT or 2.0
    F.QuestAutoInterval  = F.QuestAutoInterval or 2.0

    --========================================================
    -- STATE
    --========================================================
    S.questPriorityBosses = S.questPriorityBosses or {}
    S.questActiveList     = S.questActiveList or {}
    S.questLastRead       = S.questLastRead or 0
    S.questLastCycle      = S.questLastCycle or 0
    S.questCycleCount     = S.questCycleCount or 0
    S.questAvailableCount = 0
    S.playerLevel         = S.playerLevel or 0
    S.playerRace          = S.playerRace or "Slayer"
    S.activeQuestName     = S.activeQuestName or nil
    S.activeQuestSummary  = S.activeQuestSummary or ""
    S.questIsInteracting  = false
    S.autoQuest           = S.autoQuest or false
    S.questMode           = S.questMode or "Auto Best Quest (By Level)"
    S.selectedQuestName   = S.selectedQuestName or nil
    S.autoAcceptFailures  = 0
    S.lastFailedQuest     = nil
    S.lastAutoCycle       = 0
    S.lastLevelRead       = 0
    S.crowCycle           = 0
    S.huntCount           = 0
    S._panelRoot          = nil
    S._crowTool           = nil
    S.cPrch               = false

    --========================================================
    -- GAME MODULE PROBES
    --========================================================
    local RS = U.RS
    local PlayerService = RS:FindFirstChild("Player_Service")

    local function safeRequire(path)
        if not path then return nil end
        local ok, mod = pcall(require, path)
        return ok and mod or nil
    end

    -- Communication signals
    local SignalFunction, SignalEvent
    pcall(function()
        local c = RS:FindFirstChild("Communication")
        local sc = c and c:FindFirstChild("ServerAndClient")
        local sig = sc and sc:FindFirstChild("Signals")
        if sig then
            SignalFunction = safeRequire(sig:FindFirstChild("SignalFunction"))
            SignalEvent = safeRequire(sig:FindFirstChild("SignalEvent"))
        end
    end)

    -- Utility (GetData)
    local Utility
    pcall(function()
        local cam = RS:FindFirstChild("CAM")
        local glob = cam and cam:FindFirstChild("Global")
        if glob then
            Utility = safeRequire(glob:FindFirstChild("Utility"))
        end
    end)

    -- Gameplay Quests module
    local GameplayQuests
    pcall(function()
        local cam = RS:FindFirstChild("CAM")
        local glob = cam and cam:FindFirstChild("Global")
        local subs = glob and glob:FindFirstChild("Subsets")
        local gp = subs and subs:FindFirstChild("Gameplay")
        if gp then
            GameplayQuests = safeRequire(gp:FindFirstChild("Quests"))
        end
    end)

    -- Dialogue module
    local Dialogue
    pcall(function()
        local cam = RS:FindFirstChild("CAM")
        local cl = cam and cam:FindFirstChild("Client")
        local modules = cl and cl:FindFirstChild("Modules")
        local gp = modules and modules:FindFirstChild("GamePlay")
        if gp then
            Dialogue = safeRequire(gp:FindFirstChild("Dialogue"))
        end
    end)

    -- AreaLocator module
    local AreaLocator
    pcall(function()
        local cam = RS:FindFirstChild("CAM")
        local glob = cam and cam:FindFirstChild("Global")
        local subs = glob and glob:FindFirstChild("Subsets")
        local areas = subs and subs:FindFirstChild("Areas")
        if areas then
            AreaLocator = safeRequire(areas:FindFirstChild("AreaLocator"))
        end
    end)

    --========================================================
    -- PLAYER DATA
    --========================================================
    local function getPlayerData()
        if not PlayerService then return nil end
        local data = PlayerService:FindFirstChild("Data")
        if not data then return nil end
        return data:FindFirstChild(U.Lp.Name)
    end

    local function getEquippedSlot()
        local data = getPlayerData()
        if not data then return nil end
        local slotEquipped = data:FindFirstChild("slotEquipped")
        local idx = slotEquipped and tostring(slotEquipped.Value) or "1"
        local slots = data:FindFirstChild("slots")
        if slots then
            return slots:FindFirstChild("Slot"..idx)
                or slots:FindFirstChild(idx)
                or slots:GetChildren()[1]
        end
        return data
    end

    --========================================================
    -- LEVEL (Synerox fn26)
    --========================================================
    local function readLevel()
        if Utility and Utility.GetData then
            local ok, level = pcall(function()
                local exp1, exp2 = Utility.GetData(U.Lp, true)
                local expVal = exp1 and exp1:FindFirstChild("Exp")
                    or exp2 and exp2:FindFirstChild("Exp")
                if expVal and expVal:FindFirstChild("Goal") then
                    local gs
                    pcall(function()
                        local cam = RS:FindFirstChild("CAM")
                        local glob = cam and cam:FindFirstChild("Global")
                        gs = safeRequire(glob:FindFirstChild("gameSettings"))
                    end)
                    local perLevel = (gs and gs.expPerLevel) or 60
                    return math.floor(expVal.Goal.Value / perLevel)
                end
                return 0
            end)
            if ok and type(level) == "number" and level > 0 then return level end
        end
        -- Fallback: slots path
        local slot = getEquippedSlot()
        if slot then
            local prog = slot:FindFirstChild("Progression")
            local lvl = prog and prog:FindFirstChild("Level")
            if lvl then
                local ok, v = pcall(function() return lvl.Value end)
                if ok and type(v) == "number" and v > 0 then return v end
            end
        end
        return 0
    end

    --========================================================
    -- RACE (Synerox fn25)
    --========================================================
    local function readRace()
        local race = "Slayer"
        if Utility and Utility.GetData then
            pcall(function()
                local d1, d2 = Utility.GetData(U.Lp, true)
                local r1 = d1 and d1:FindFirstChild("Race")
                local r2 = d2 and d2:FindFirstChild("Race")
                if r1 and r1.Value ~= "" then race = r1.Value
                elseif r2 and r2.Value ~= "" then race = r2.Value end
            end)
        end
        return race
    end

    --========================================================
    -- NPC POSITION (4-tier fallback — Synerox fn31 + L.npcPositions)
    --========================================================
    local function findNpcPosition(npcName)
        if not npcName then return nil end

        -- 1. Debree.Regions.*.StationaryNpcs / ActiveNpcs
        local debree = workspace:FindFirstChild("Debree")
        local regions = debree and debree:FindFirstChild("Regions")
        if regions then
            for _, region in ipairs(regions:GetChildren()) do
                local stat = region:FindFirstChild("StationaryNpcs")
                local act  = region:FindFirstChild("ActiveNpcs")
                local found = stat and stat:FindFirstChild(npcName)
                    or act and act:FindFirstChild(npcName)
                if found then
                    local root = found:FindFirstChild("HumanoidRootPart")
                        or found:FindFirstChild("Torso")
                        or found.PrimaryPart
                    if root then return root.Position, found end
                end
            end
        end

        -- 2. Humanoids.Regions.*
        local humanoids = workspace:FindFirstChild("Humanoids")
        local hreg = humanoids and humanoids:FindFirstChild("Regions")
        if hreg then
            for _, region in ipairs(hreg:GetChildren()) do
                local stat = region:FindFirstChild("StationaryNpcs")
                local act  = region:FindFirstChild("ActiveNpcs")
                local found = stat and stat:FindFirstChild(npcName)
                    or act and act:FindFirstChild(npcName)
                if found then
                    local root = found:FindFirstChild("HumanoidRootPart")
                        or found:FindFirstChild("Torso")
                        or found.PrimaryPart
                    if root then return root.Position, found end
                end
            end
        end

        -- 3. Regions.GetNpcSpawn
        local regionsMod
        pcall(function()
            regionsMod = safeRequire(RS:FindFirstChild("Regions"))
        end)
        if regionsMod and regionsMod.GetNpcSpawn then
            local ok, pos = pcall(regionsMod.GetNpcSpawn, npcName)
            if ok and typeof(pos) == "Vector3" then return pos, nil end
        end

        -- 4. Static fallback from lists
        local pos = L.getNpcPos(npcName)
        if pos then return pos, nil end

        return nil, nil
    end

    --========================================================
    -- READ ACTIVE QUEST (Synerox fn27)
    --========================================================
    local function readActiveQuest()
        if not Utility or not Utility.GetData then return nil end
        local ok, result = pcall(function()
            local d1, d2 = Utility.GetData(U.Lp, true)
            local holder = (d1 and d1:FindFirstChild("Quests") and d1.Quests:FindFirstChild("Holder"))
                or (d2 and d2:FindFirstChild("Quests") and d2.Quests:FindFirstChild("Holder"))
            if not holder then return nil end
            local firstFinished, inProgress
            for _, child in ipairs(holder:GetChildren()) do
                local name = child:FindFirstChild("QuestString")
                    and child.QuestString.Value or child.Name
                local tasks = {}
                local hasTasks, allDone = false, true
                if child:FindFirstChild("Tasks") then
                    for _, task in ipairs(child.Tasks:GetChildren()) do
                        local cur = task:FindFirstChild("Value") and task.Value.Value or 0
                        local max = task:FindFirstChild("Max") and task.Max.Value or 1
                        tasks[task.Name] = { Current = cur, Max = max }
                        hasTasks = true
                        if cur < max then allDone = false end
                    end
                end
                local entry = {
                    Name        = child.Name,
                    QuestString = name,
                    Tasks       = tasks,
                    Finished    = hasTasks and allDone,
                    IsFinished  = hasTasks and allDone,
                    HasTasks    = hasTasks,
                    Instance    = child,
                }
                if hasTasks and not allDone then return entry end
                if hasTasks then firstFinished = entry
                elseif not inProgress then inProgress = entry end
            end
            return firstFinished or inProgress
        end)
        return ok and result or nil
    end

    --========================================================
    -- ABANDON QUEST (Synerox fn28)
    --========================================================
    local function abandonQuest(entry)
        local target = entry or readActiveQuest()
        local abandoned = false
        if target then
            pcall(function()
                if SignalEvent and SignalEvent.ToServer then
                    SignalEvent.ToServer("RemoveQuest", target.Name)
                    if target.QuestString and target.QuestString ~= target.Name then
                        SignalEvent.ToServer("RemoveQuest", target.QuestString)
                    end
                end
            end)
            pcall(function()
                if GameplayQuests and GameplayQuests.DeleteQuest then
                    GameplayQuests.DeleteQuest(U.Lp, target.Instance or target.Name)
                end
            end)
            abandoned = true
        end
        -- Clean empty holders
        pcall(function()
            if not Utility or not Utility.GetData then return end
            local d = Utility.GetData(U.Lp, true)
            local holder = d and d:FindFirstChild("Quests")
                and d.Quests:FindFirstChild("Holder")
            if holder then
                for _, child in ipairs(holder:GetChildren()) do
                    if not child:FindFirstChild("Tasks")
                       or #child.Tasks:GetChildren() == 0 then
                        child:Destroy()
                    end
                end
            end
        end)
        return abandoned
    end

    --========================================================
    -- QUEST ENTRY LOOKUP + PICK (Synerox fn30 + fn32)
    --========================================================
    local function raceOk(quest)
        if not quest or not quest.race or quest.race == "Any" then return true end
        local race = S.playerRace or "Slayer"
        if type(quest.race) == "table" then
            for _, r in ipairs(quest.race) do
                if r == race then return true end
            end
            return false
        end
        return quest.race == race
    end

    local function findQuestEntry(byName)
        if not byName then return nil end
        for _, q in ipairs(L.quests) do
            if q.name == byName or q.display == byName
               or q.inst == byName or q.npc == byName then
                return q
            end
        end
        return nil
    end

    local function pickBestQuest(level)
        local best, bestLvl = nil, -1
        for _, q in ipairs(L.quests) do
            if level >= q.minLvl and q.minLvl >= bestLvl and raceOk(q) then
                bestLvl = q.minLvl
                best = q
            end
        end
        return best
    end

    --========================================================
    -- DIALOGUE HELPERS
    --========================================================
    local function findDialogueButtons()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil, nil end
        local cc = pg:FindFirstChild("ComponentsHolder")
        if not cc then return nil, nil end
        local df = cc:FindFirstChild("DialogueFrame")
        if not df then return nil, nil end
        local actual = df:FindFirstChild("Actual")
        if not actual then return nil, nil end
        return actual:FindFirstChild("ButtonHolder"), actual
    end

    local function closeDialogue()
        pcall(function()
            local cam = RS:FindFirstChild("CAM")
            local cl = cam and cam:FindFirstChild("Client")
            local comp = cl and cl:FindFirstChild("Components")
            local cli = comp and comp:FindFirstChild("Client")
            local dc = cli and cli:FindFirstChild("DialogueComponent")
            if dc then
                local du = safeRequire(dc:FindFirstChild("DialogueUtility"))
                if du and du.Close then du.Close() end
            end
        end)
        pcall(function()
            if Dialogue and Dialogue.CurrentDialogue then
                Dialogue.CurrentDialogue.Current = nil
                if Dialogue.CurrentDialogue.Cancel then
                    Dialogue.CurrentDialogue.Cancel:Fire()
                end
            end
        end)
    end

    --========================================================
    -- NPC PROMPT FINDER
    --========================================================
    local function findNpcPrompt(npcName, npcModel)
        -- Direct prompt on model
        if npcModel then
            local prompt = npcModel:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt then return prompt end
        end
        -- Scan nearby
        local myRoot = U.hrp()
        if not myRoot then return nil end
        local target = string.lower(npcName or "")
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local parent = d.Parent
                local part
                if parent:IsA("Attachment") then part = parent.Parent
                elseif parent:IsA("BasePart") then part = parent
                elseif parent:IsA("Model") then part = parent:FindFirstChildWhichIsA("BasePart", true) end
                if part and (part.Position - myRoot.Position).Magnitude < 20 then
                    local pName = string.lower(parent.Name or "")
                    local gpName = parent.Parent and string.lower(parent.Parent.Name or "") or ""
                    if pName:find(target, 1, true) or gpName:find(target, 1, true) then
                        return d
                    end
                end
            end
        end
        return nil
    end

    --========================================================
    -- ACCEPT QUEST (Synerox fn29 full pipeline)
    --========================================================
    local function acceptQuest(entry)
        if not entry then return false, "no-entry" end
        if S.questIsInteracting then return false, "busy" end

        -- Already active check
        local active = readActiveQuest()
        if active and not active.IsFinished then
            if active.QuestString == entry.name
               or active.Name == entry.inst
               or active.Name == entry.name then
                return true, "already-active"
            end
        end

        local pos, npcModel = findNpcPosition(entry.npc)
        if not pos then return false, "npc-not-found" end

        S.questIsInteracting = true
        local myRoot = U.hrp()
        if not myRoot then
            S.questIsInteracting = false
            return false, "no-char"
        end

        -- Teleport
        myRoot.CFrame = CFrame.new(pos + Vector3.new(0, 2, 3), pos)
        myRoot.AssemblyLinearVelocity = Vector3.zero
        myRoot.AssemblyAngularVelocity = Vector3.zero

        task.wait(0.35)

        -- Area locator
        if AreaLocator and AreaLocator.Update then
            pcall(AreaLocator.Update, myRoot)
        end

        -- Fire prompt
        local prompt = findNpcPrompt(entry.npc, npcModel)
        if prompt then
            U.firePrompt(prompt)
            task.wait(0.3)
        end

        -- Dialogue wait + click
        local deadline = os.clock() + 9
        local clicked = false
        local sawDialogue = false

        while os.clock() < deadline do
            local bh, actual = findDialogueButtons()
            if bh then
                sawDialogue = true
                local targetBtn
                for _, child in ipairs(bh:GetChildren()) do
                    local n = string.lower(child.Name or "")
                    if n:find(string.lower(entry.name), 1, true)
                       or (entry.display and n:find(string.lower(entry.display), 1, true))
                       or n == string.lower(entry.name) then
                        targetBtn = child
                        break
                    end
                end
                if targetBtn then
                    local btn = targetBtn:FindFirstChildWhichIsA("TextButton", true)
                    if btn then
                        U.fireSignal(btn.MouseButton1Click)
                        pcall(function() btn:Activate() end)
                        clicked = true
                    end
                    break
                end
                -- ClickDetector fallback
                if actual then
                    local cd = actual:FindFirstChild("ClickDetector")
                    if cd and cd.Visible then
                        pcall(function() cd.MouseButton1Click:Fire() end)
                        if U.VIM then
                            local ap = cd.AbsolutePosition + cd.AbsoluteSize / 2
                            pcall(function()
                                U.VIM:SendMouseButtonEvent(ap.X, ap.Y, 0, true, game, 0)
                                task.wait(0.03)
                                U.VIM:SendMouseButtonEvent(ap.X, ap.Y, 0, false, game, 0)
                            end)
                        end
                    end
                end
                task.wait(0.2)
            else
                task.wait(0.2)
            end
        end

        -- Remote fallback if no dialogue button
        if not clicked then
            pcall(function()
                if Dialogue and Dialogue.Functions and Dialogue.Functions.AddQuest then
                    Dialogue.Functions.AddQuest(entry.name)
                end
            end)
            pcall(function()
                if SignalEvent and SignalEvent.ToServer then
                    SignalEvent.ToServer("AddQuest", entry.name)
                end
            end)
        end

        -- Verify
        local verifyDeadline = os.clock() + 3
        local verified = false
        while os.clock() < verifyDeadline do
            task.wait(0.1)
            local q = readActiveQuest()
            if q and (q.QuestString == entry.name
                      or q.Name == entry.inst
                      or q.Name == entry.name) then
                verified = true
                break
            end
        end

        closeDialogue()
        task.wait(0.1)
        S.questIsInteracting = false
        return verified, clicked and "dialogue" or (sawDialogue and "no-btn" or "remote")
    end

    --========================================================
    -- CROW PANEL (read-only, separate from NPC quests)
    --========================================================
    local function getComponentsHolder()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        return pg and pg:FindFirstChild("ComponentsHolder") or nil
    end

    local function findCrowPanel()
        local cc = getComponentsHolder()
        if not cc then return nil end
        local stack = { { cc, 0 } }
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 6 then
                if inst:IsA("TextLabel") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string"
                       and txt:find("current tasks", 1, true) then
                        return inst.Parent or inst
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do
                    table.insert(stack, { k, d + 1 })
                end
            end
        end
        return nil
    end

    local function findCrowCancel()
        local cc = getComponentsHolder()
        if not cc then return nil end
        local stack = { { cc, 0 } }
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 6 then
                if inst:IsA("TextButton") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string" then
                        local l = txt:lower():gsub("^%s+", ""):gsub("%s+$", "")
                        if l == "cancel" or l == "close" then
                            local okV, vis = pcall(function() return inst.Visible end)
                            if okV and vis then return inst end
                        end
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do
                    table.insert(stack, { k, d + 1 })
                end
            end
        end
        return nil
    end

    local function readCrowPanelQuests()
        local root = findCrowPanel()
        if not root then return {} end
        local out = {}
        local stack = { root }
        while #stack > 0 do
            local inst = table.remove(stack)
            if inst then
                if inst:IsA("TextLabel") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string" then
                        local boss = txt:match("^%s*Defeat%s+(.+)$")
                            or txt:match("^%s*Eliminate%s+(.+)$")
                            or txt:match("^%s*Hunt%s+(.+)$")
                        if boss then
                            boss = boss:gsub("%s+$", ""):gsub("^%s+", "")
                            if #boss > 0 and #boss < 40 then
                                table.insert(out, { boss = boss })
                            end
                        end
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do
                    table.insert(stack, k)
                end
            end
        end
        return out
    end

    local function isCrowish(name)
        if not name then return false end
        local l = string.lower(name)
        return l == "crow" or l:find("crow", 1, true)
            or l:find("kasugai", 1, true)
    end

    local function findCrowTool()
        if S._crowTool and S._crowTool.Parent then return S._crowTool end
        local char = U.Lp.Character
        if char then
            for _, c in ipairs(char:GetChildren()) do
                if c:IsA("Tool") and isCrowish(c.Name) then
                    S._crowTool = c; return c
                end
            end
        end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then
            for _, c in ipairs(bp:GetChildren()) do
                if c:IsA("Tool") and isCrowish(c.Name) then
                    S._crowTool = c; return c
                end
            end
        end
        return nil
    end

    local function openCrowMenu()
        if findCrowPanel() then return true end
        U.m1()
        local deadline = os.clock() + (F.QuestMenuWait or 2.5)
        while os.clock() < deadline do
            if findCrowPanel() then return true end
            task.wait(0.15)
        end
        return findCrowPanel() ~= nil
    end

    local function closeCrowMenu()
        local c = findCrowCancel()
        if c then
            pcall(function() c:Activate() end)
            task.wait(0.3)
        end
    end

    --========================================================
    -- PRIORITY API (consumed by detect.lua)
    --========================================================
    function Q.isPriority(bossName)
        local list = S.questPriorityBosses
        if not list or #list == 0 then return true end
        if (U.clock() - (S.questLastRead or 0)) > (F.QuestPriorityStale * 2) then
            return true
        end
        local l = string.lower(bossName or "")
        for i = 1, #list do
            local t = string.lower(list[i])
            if l:find(t, 1, true) or t:find(l, 1, true) then return true end
        end
        return false
    end

    function Q.getPriorityBosses() return S.questPriorityBosses end
    function Q.getActiveQuests()    return S.questActiveList end
    function Q.getPlayerLevel()     return S.playerLevel end
    function Q.getPlayerRace()      return S.playerRace end
    function Q.getBestQuest()       return pickBestQuest(S.playerLevel) end

    --========================================================
    -- CROW CYCLE
    --========================================================
    local function crowCycle()
        S.crowCycle = S.crowCycle + 1
        if not S.crw then return end
        local now = U.clock()
        local stale = (now - S.questLastRead) > (F.QuestPriorityStale or 90)
        local empty = #S.questPriorityBosses == 0
        if not (stale or empty) then return end
        if Ctx.Hotbar and Ctx.Hotbar.isLocked() then return end

        local tool = findCrowTool()
        if not tool then
            U.fireSkill(F.QuestCrowHotbar or "5") or U.tap(F.QuestCrowHotbar or "5")
            task.wait(0.45)
            tool = findCrowTool()
        end
        if tool then
            S.crT = tool
            if openCrowMenu() then
                S.cPrch = true
                local qs = readCrowPanelQuests()
                if #qs > 0 then
                    local names = {}
                    for _, q in ipairs(qs) do table.insert(names, q.boss) end
                    S.questPriorityBosses = names
                    S.questActiveList = qs
                    S.questLastRead = now
                    print(string.format("[Dingus][Quest] crow: %d active · %s",
                        #qs, table.concat(names, ", ")))
                end
                closeCrowMenu()
                S.cPrch = false
            end
        end
    end

    --========================================================
    -- AUTO-QUEST CYCLE (Synerox fn30 → fn29 pipeline)
    --========================================================
    local function autoQuestCycle()
        if not S.autoQuest then return end
        if S.questIsInteracting then return end
        local now = U.clock()
        if now - S.lastAutoCycle < (F.QuestAutoInterval or 2.0) then return end
        S.lastAutoCycle = now

        local level = S.playerLevel
        local active = readActiveQuest()

        -- Finished → abandon
        if active and active.IsFinished then
            abandonQuest(active)
            S.lastFailedQuest = nil
            S.autoAcceptFailures = 0
            task.wait(0.3)
            return
        end

        -- Determine target
        local target
        if S.questMode == "Auto Best Quest (By Level)" then
            target = pickBestQuest(level)
        else
            target = findQuestEntry(S.questMode) or findQuestEntry(S.selectedQuestName)
        end
        if not target then return end

        -- Level gate
        if level < target.minLvl then
            if S.lastFailedQuest ~= target.name then
                S.lastFailedQuest = target.name
                print(string.format("[Dingus][Quest] %s needs Lv %d (you are %d)",
                    target.display or target.name, target.minLvl, level))
            end
            return
        end

        -- Wrong active → abandon
        if active then
            local matches = active.QuestString == target.name
                or active.Name == target.inst
                or active.Name == target.name
            if not matches then
                abandonQuest(active)
                task.wait(0.3)
            else
                return
            end
        end

        -- Accept
        local ok, reason = acceptQuest(target)
        if ok then
            S.autoAcceptFailures = 0
            S.lastFailedQuest = nil
            print(string.format("[Dingus][Quest] accepted: %s (%s)",
                target.display or target.name, tostring(reason)))
            -- Push target to attack module
            if Ctx.Atk then
                pcall(function()
                    if Ctx.Atk.setCategory then Ctx.Atk.setCategory(target.cat) end
                    if Ctx.Atk.setTargetMob then Ctx.Atk.setTargetMob(target.mob) end
                    if Ctx.Atk.setRegion then Ctx.Atk.setRegion(target.region) end
                end)
            end
        else
            if S.lastFailedQuest == target.name then
                S.autoAcceptFailures = S.autoAcceptFailures + 1
            else
                S.lastFailedQuest = target.name
                S.autoAcceptFailures = 1
            end
            if S.autoAcceptFailures >= 3 then
                S.autoQuest = false
                print(string.format("[Dingus][Quest] auto-quest disabled after 3 failures (%s)",
                    tostring(reason)))
            end
        end
    end

    --========================================================
    -- MAIN CYCLE (called from scheduler)
    --========================================================
    function Q.cycle()
        S.questCycleCount = S.questCycleCount + 1
        local now = U.clock()
        if now - S.questLastCycle < (F.QuestCycleT or 6.0) then return end
        S.questLastCycle = now

        -- Refresh level/race every 10s
        if now - S.lastLevelRead > 10 then
            S.lastLevelRead = now
            S.playerLevel = readLevel()
            S.playerRace  = readRace()
            local a = readActiveQuest()
            if a then
                S.activeQuestName = a.QuestString or a.Name
                local parts = {}
                for k, v in pairs(a.Tasks or {}) do
                    table.insert(parts, string.format("%s:%d/%d", k, v.Current, v.Max))
                end
                S.activeQuestSummary = table.concat(parts, " ")
            else
                S.activeQuestName = nil
                S.activeQuestSummary = ""
            end
        end

        crowCycle()
        autoQuestCycle()
    end

    --========================================================
    -- STATS
    --========================================================
    function Q.stats()
        local holder = "free"
        if Ctx.Hotbar and Ctx.Hotbar.isLocked then
            holder = Ctx.Hotbar.isLocked() or "free"
        end
        local tool = findCrowTool()
        return {
            level = S.playerLevel or 0,
            race = S.playerRace or "?",
            autoQuest = S.autoQuest,
            questMode = S.questMode,
            activeQuestName = S.activeQuestName,
            activeQuestSummary = S.activeQuestSummary,
            priorityCount = #(S.questPriorityBosses or {}),
            priority = table.concat(S.questPriorityBosses or {}, ", "),
            lastReadAge = U.clock() - (S.questLastRead or 0),
            crowTool = tool and tool.Name or "not-found",
            hotbarHolder = holder,
            crowCycles = S.crowCycle,
            interacting = S.questIsInteracting,
            failures = S.autoAcceptFailures,
            availableQuests = #(L.quests or {}),
        }
    end

    --========================================================
    -- PUBLIC CONTROLS
    --========================================================
    function Q.setAutoQuest(v)
        S.autoQuest = not not v
        if S.autoQuest then
            S.autoAcceptFailures = 0
            S.lastFailedQuest = nil
            print("[Dingus][Quest] auto-quest ENABLED")
        else
            print("[Dingus][Quest] auto-quest DISABLED")
        end
    end

    function Q.setQuestMode(mode)
        S.questMode = mode
        print("[Dingus][Quest] mode = " .. tostring(mode))
    end

    function Q.forceAcceptQuest(name)
        local target = findQuestEntry(name)
        if not target then return false, "not-found" end
        if S.playerLevel < target.minLvl then return false, "level-too-low" end
        local active = readActiveQuest()
        if active then
            abandonQuest(active)
            task.wait(0.3)
        end
        return acceptQuest(target)
    end

    function Q.forceAbandon()
        local active = readActiveQuest()
        if active then return abandonQuest(active) end
        return false
    end

    function Q.forceCrowRead()
        S.questLastRead = 0
        S.questPriorityBosses = {}
        crowCycle()
        return S.questPriorityBosses
    end

    function Q.listAvailableQuests()
        local out = {}
        for _, q in ipairs(L.quests) do
            table.insert(out, {
                name = q.name, display = q.display,
                minLvl = q.minLvl, category = q.cat,
                region = q.region, race = q.race,
                eligible = S.playerLevel >= q.minLvl and raceOk(q),
            })
        end
        return out
    end

    function Q.teleportToNpc(npcName)
        local pos = findNpcPosition(npcName)
        if not pos then return false end
        local hrp = U.hrp()
        if hrp then
            hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
        return true
    end

    --========================================================
    -- CLEANUP
    --========================================================
    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function()
        S.questIsInteracting = false
        S.autoQuest = false
        closeDialogue()
    end)

    --========================================================
    -- BOOT TASK
    --========================================================
    task.spawn(function()
        task.wait(3)
        S.playerLevel = readLevel()
        S.playerRace  = readRace()
        print(string.format(
            "[Dingus][Quest] boot · lvl=%d race=%s quests=%d util=%s SE=%s",
            S.playerLevel, S.playerRace, #L.quests,
            tostring(Utility ~= nil), tostring(SignalEvent ~= nil)))
    end)

    print(string.format(
        "[Dingus][quests] v9 · %s · %d quests · Utility=%s · SE=%s · SQ=%s",
        U.Platform, #L.quests,
        tostring(Utility ~= nil),
        tostring(SignalEvent ~= nil),
        tostring(GameplayQuests ~= nil)))
end

return Q
