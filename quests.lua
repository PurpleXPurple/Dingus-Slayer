-- Dingus-Slayer · quests.lua v10
-- Clean rebuild. No compound or-chains that can break the parser.

local Q = {}

function Q.init(Ctx)
    local U = Ctx.Util
    local F = Ctx.Cfg
    local S = Ctx.St
    local L = Ctx.Lists

    F.QuestCrowHotbar = F.QuestCrowHotbar or "5"
    F.QuestMenuWait = F.QuestMenuWait or 2.5
    F.QuestPriorityStale = F.QuestPriorityStale or 90
    F.QuestAutoInterval = F.QuestAutoInterval or 2.0

    S.questPriorityBosses = S.questPriorityBosses or {}
    S.questActiveList = S.questActiveList or {}
    S.questLastRead = S.questLastRead or 0
    S.questLastCycle = S.questLastCycle or 0
    S.questCycleCount = S.questCycleCount or 0
    S.playerLevel = S.playerLevel or 0
    S.playerRace = S.playerRace or "Slayer"
    S.activeQuestName = nil
    S.activeQuestSummary = ""
    S.questIsInteracting = false
    S.autoQuest = S.autoQuest or false
    S.questMode = S.questMode or "Auto Best Quest (By Level)"
    S.autoAcceptFailures = 0
    S.lastFailedQuest = nil
    S.lastAutoCycle = 0
    S.lastLevelRead = 0
    S.crowCycleCount = 0
    S._crowTool = nil
    S._crowPanel = nil

    local RS = U.RS

    local Utility = nil
    pcall(function()
        local cam = RS:FindFirstChild("CAM")
        local glob = cam and cam:FindFirstChild("Global")
        local util = glob and glob:FindFirstChild("Utility")
        if util then
            local ok, mod = pcall(require, util)
            if ok then Utility = mod end
        end
    end)

    local SignalEvent = nil
    pcall(function()
        local c = RS:FindFirstChild("Communication")
        local sc = c and c:FindFirstChild("ServerAndClient")
        local sig = sc and sc:FindFirstChild("Signals")
        local se = sig and sig:FindFirstChild("SignalEvent")
        if se then
            local ok, mod = pcall(require, se)
            if ok then SignalEvent = mod end
        end
    end)

    local function getData()
        if not Utility or not Utility.GetData then
            return nil, nil
        end
        local ok, d1, d2 = pcall(Utility.GetData, U.Lp, true)
        if not ok then return nil, nil end
        return d1, d2
    end

    local function readLevel()
        local d1, d2 = getData()
        local list = { d1, d2 }
        for i = 1, 2 do
            local d = list[i]
            if d then
                local exp = d:FindFirstChild("Exp")
                if exp then
                    local goal = exp:FindFirstChild("Goal")
                    if goal and type(goal.Value) == "number"
                       and goal.Value > 0 then
                        return math.floor(goal.Value / 60)
                    end
                end
                local prog = d:FindFirstChild("Progression")
                if prog then
                    local lvl = prog:FindFirstChild("Level")
                    if lvl and type(lvl.Value) == "number" then
                        return lvl.Value
                    end
                end
            end
        end
        return 0
    end

    local function readRace()
        local d1, d2 = getData()
        local list = { d1, d2 }
        for i = 1, 2 do
            local d = list[i]
            if d then
                local r = d:FindFirstChild("Race")
                if r and type(r.Value) == "string"
                   and r.Value ~= "" then
                    return r.Value
                end
            end
        end
        return "Slayer"
    end

    local function findNpcPosition(npcName)
        if not npcName then return nil, nil end

        local debree = workspace:FindFirstChild("Debree")
        local regions = debree and debree:FindFirstChild("Regions")
        if regions then
            for _, region in ipairs(regions:GetChildren()) do
                for _, fname in ipairs({ "StationaryNpcs", "ActiveNpcs" }) do
                    local folder = region:FindFirstChild(fname)
                    if folder then
                        local npc = folder:FindFirstChild(npcName)
                        if npc then
                            local root = npc:FindFirstChild("HumanoidRootPart")
                            if not root then
                                root = npc:FindFirstChild("Torso")
                            end
                            if not root then root = npc.PrimaryPart end
                            if root then return root.Position, npc end
                        end
                    end
                end
            end
        end

        local humanoids = workspace:FindFirstChild("Humanoids")
        local hreg = humanoids and humanoids:FindFirstChild("Regions")
        if hreg then
            for _, region in ipairs(hreg:GetChildren()) do
                for _, fname in ipairs({ "StationaryNpcs", "ActiveNpcs" }) do
                    local folder = region:FindFirstChild(fname)
                    if folder then
                        local npc = folder:FindFirstChild(npcName)
                        if npc then
                            local root = npc:FindFirstChild("HumanoidRootPart")
                            if not root then
                                root = npc:FindFirstChild("Torso")
                            end
                            if not root then root = npc.PrimaryPart end
                            if root then return root.Position, npc end
                        end
                    end
                end
            end
        end

        local pos = L.getNpcPos(npcName)
        if pos then return pos, nil end
        return nil, nil
    end

    local function readActiveQuest()
        local d1, d2 = getData()
        local list = { d1, d2 }
        for i = 1, 2 do
            local d = list[i]
            if d then
                local quests = d:FindFirstChild("Quests")
                local holder = quests and quests:FindFirstChild("Holder")
                if holder then
                    for _, child in ipairs(holder:GetChildren()) do
                        local tasks = child:FindFirstChild("Tasks")
                        if tasks and #tasks:GetChildren() > 0 then
                            local allDone = true
                            local taskMap = {}
                            for _, task in ipairs(tasks:GetChildren()) do
                                local cur = 0
                                local max = 1
                                local v = task:FindFirstChild("Value")
                                local m = task:FindFirstChild("Max")
                                if v and type(v.Value) == "number" then
                                    cur = v.Value
                                end
                                if m and type(m.Value) == "number" then
                                    max = m.Value
                                end
                                taskMap[task.Name] = {
                                    Current = cur, Max = max,
                                }
                                if cur < max then allDone = false end
                            end
                            local qs = child:FindFirstChild("QuestString")
                            local qname = child.Name
                            if qs and type(qs.Value) == "string" then
                                qname = qs.Value
                            end
                            return {
                                Name = child.Name,
                                QuestString = qname,
                                Tasks = taskMap,
                                Finished = allDone,
                                IsFinished = allDone,
                                Instance = child,
                            }
                        end
                    end
                end
            end
        end
        return nil
    end

    local function abandonQuest(entry)
        local target = entry or readActiveQuest()
        if not target then return false end
        pcall(function()
            if SignalEvent and SignalEvent.ToServer then
                SignalEvent.ToServer("RemoveQuest", target.Name)
                if target.QuestString
                   and target.QuestString ~= target.Name then
                    SignalEvent.ToServer("RemoveQuest", target.QuestString)
                end
            end
        end)
        return true
    end

    local function raceOk(quest)
        if not quest then return true end
        if not quest.race then return true end
        if quest.race == "Any" then return true end
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
        for _, q in ipairs(L.quests or {}) do
            if q.name == byName then return q end
            if q.display == byName then return q end
            if q.inst == byName then return q end
        end
        return nil
    end

    local function pickBestQuest(level)
        local best = nil
        local bestLvl = -1
        for _, q in ipairs(L.quests or {}) do
            if level >= q.minLvl and q.minLvl >= bestLvl
               and raceOk(q) then
                bestLvl = q.minLvl
                best = q
            end
        end
        return best
    end

    local function isCrowish(name)
        if not name then return false end
        local l = string.lower(name)
        if l == "crow" then return true end
        if l:find("crow", 1, true) then return true end
        if l:find("kasugai", 1, true) then return true end
        return false
    end

    local function findCrowTool()
        if S._crowTool and S._crowTool.Parent then
            return S._crowTool
        end
        local char = U.Lp.Character
        if char then
            for _, c in ipairs(char:GetChildren()) do
                if c:IsA("Tool") and isCrowish(c.Name) then
                    S._crowTool = c
                    return c
                end
            end
        end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then
            for _, c in ipairs(bp:GetChildren()) do
                if c:IsA("Tool") and isCrowish(c.Name) then
                    S._crowTool = c
                    return c
                end
            end
        end
        return nil
    end

    local function findCrowPanel()
        if S._crowPanel and S._crowPanel.Parent then
            return S._crowPanel
        end
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        local cc = pg:FindFirstChild("ComponentsHolder")
        if not cc then return nil end
        local stack = { { cc, 0 } }
        while #stack > 0 do
            local item = table.remove(stack)
            local inst = item[1]
            local d = item[2]
            if inst and d <= 6 then
                if inst:IsA("TextLabel") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string" then
                        if txt:find("current tasks", 1, true) then
                            S._crowPanel = inst.Parent or inst
                            return S._crowPanel
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

    local function findCrowCancel()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        local cc = pg:FindFirstChild("ComponentsHolder")
        if not cc then return nil end
        local stack = { { cc, 0 } }
        while #stack > 0 do
            local item = table.remove(stack)
            local inst = item[1]
            local d = item[2]
            if inst and d <= 6 then
                if inst:IsA("TextButton") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string" then
                        local l = string.lower(txt)
                        l = l:gsub("^%s+", "")
                        l = l:gsub("%s+$", "")
                        if l == "cancel" or l == "close" then
                            local okv, vis = pcall(
                                function() return inst.Visible end)
                            if okv and vis then return inst end
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
                        if not boss then
                            boss = txt:match("^%s*Eliminate%s+(.+)$")
                        end
                        if not boss then
                            boss = txt:match("^%s*Hunt%s+(.+)$")
                        end
                        if boss then
                            boss = boss:gsub("%s+$", "")
                            boss = boss:gsub("^%s+", "")
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

    local function openCrowMenu()
        if findCrowPanel() then return true end
        U.m1()
        local deadline = U.clock() + (F.QuestMenuWait or 2.5)
        while U.clock() < deadline do
            if findCrowPanel() then return true end
            task.wait(0.15)
        end
        S._crowPanel = nil
        return findCrowPanel() ~= nil
    end

    local function closeCrowMenu()
        local c = findCrowCancel()
        if c then
            pcall(function() c:Activate() end)
            task.wait(0.3)
        end
    end

    local function acceptQuest(entry)
        if not entry then return false, "no-entry" end
        if S.questIsInteracting then return false, "busy" end

        local pos, npcModel = findNpcPosition(entry.npc)
        if not pos then return false, "npc-missing" end

        S.questIsInteracting = true
        local hrp = U.hrp()
        if not hrp then
            S.questIsInteracting = false
            return false, "no-char"
        end

        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 2, 3), pos)
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.35)

        local prompt = nil
        if npcModel then
            prompt = npcModel:FindFirstChildWhichIsA(
                "ProximityPrompt", true)
        end
        if not prompt then
            local myHrp = U.hrp()
            if myHrp then
                for _, d in ipairs(workspace:GetDescendants()) do
                    if d:IsA("ProximityPrompt") then
                        local parent = d.Parent
                        if parent and parent:IsA("BasePart") then
                            local dist = (parent.Position
                                - myHrp.Position).Magnitude
                            if dist < 20 then
                                prompt = d
                                break
                            end
                        end
                    end
                end
            end
        end
        if prompt then
            U.firePrompt(prompt)
            task.wait(0.3)
        end

        local deadline = U.clock() + 8
        local clicked = false
        while U.clock() < deadline do
            local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
            local cc = pg and pg:FindFirstChild("ComponentsHolder")
            local df = cc and cc:FindFirstChild("DialogueFrame")
            local actual = df and df:FindFirstChild("Actual")
            local bh = actual and actual:FindFirstChild("ButtonHolder")
            if bh then
                for _, child in ipairs(bh:GetChildren()) do
                    local cn = string.lower(child.Name or "")
                    local en = string.lower(entry.name or "")
                    local matchA = cn:find(en, 1, true) ~= nil
                    local matchB = en:find(cn, 1, true) ~= nil
                    if matchA or matchB then
                        local btn = child:FindFirstChildWhichIsA(
                            "TextButton", true)
                        if btn then
                            U.fireSignal(btn.MouseButton1Click)
                            pcall(function() btn:Activate() end)
                            clicked = true
                            break
                        end
                    end
                end
                if clicked then break end
            end
            task.wait(0.2)
        end

        if not clicked then
            pcall(function()
                if SignalEvent and SignalEvent.ToServer then
                    SignalEvent.ToServer("AddQuest", entry.name)
                end
            end)
        end

        task.wait(0.5)
        S.questIsInteracting = false
        if clicked then
            return true, "dialogue"
        end
        return false, "remote"
    end

    local function crowCycle()
        S.crowCycleCount = S.crowCycleCount + 1
        if not S.crw then return end
        local now = U.clock()
        local stale = (now - S.questLastRead)
            > (F.QuestPriorityStale or 90)
        local empty = #S.questPriorityBosses == 0
        if not stale and not empty then return end

        local tool = findCrowTool()
        if not tool then
            U.fireSkill(F.QuestCrowHotbar or "5")
            task.wait(0.45)
            tool = findCrowTool()
        end
        if not tool then return end

        S.crT = tool
        if openCrowMenu() then
            local qs = readCrowPanelQuests()
            if #qs > 0 then
                local names = {}
                for _, q in ipairs(qs) do
                    table.insert(names, q.boss)
                end
                S.questPriorityBosses = names
                S.questActiveList = qs
                S.questLastRead = now
                print(string.format(
                    "[Dingus][Quest] crow: %d active - %s",
                    #qs, table.concat(names, ", ")))
            end
            closeCrowMenu()
        end
    end

    local function autoQuestCycle()
        if not S.autoQuest then return end
        if S.questIsInteracting then return end
        local now = U.clock()
        if now - S.lastAutoCycle
           < (F.QuestAutoInterval or 2.0) then
            return
        end
        S.lastAutoCycle = now

        local level = S.playerLevel
        local active = readActiveQuest()

        if active and active.IsFinished then
            abandonQuest(active)
            S.lastFailedQuest = nil
            S.autoAcceptFailures = 0
            task.wait(0.3)
            return
        end

        local target = nil
        if S.questMode == "Auto Best Quest (By Level)" then
            target = pickBestQuest(level)
        else
            target = findQuestEntry(S.questMode)
        end
        if not target then return end

        if level < target.minLvl then
            if S.lastFailedQuest ~= target.name then
                S.lastFailedQuest = target.name
                print(string.format(
                    "[Dingus][Quest] %s needs Lv %d (you are %d)",
                    target.display or target.name,
                    target.minLvl, level))
            end
            return
        end

        if active then
            local match = false
            if active.QuestString == target.name then match = true end
            if active.Name == target.inst then match = true end
            if active.Name == target.name then match = true end
            if not match then
                abandonQuest(active)
                task.wait(0.3)
            else
                return
            end
        end

        local ok, reason = acceptQuest(target)
        if ok then
            S.autoAcceptFailures = 0
            S.lastFailedQuest = nil
            print(string.format(
                "[Dingus][Quest] accepted: %s (%s)",
                target.display or target.name, tostring(reason)))
            if Ctx.Atk then
                if Ctx.Atk.setCategory then
                    Ctx.Atk.setCategory(target.cat)
                end
                if Ctx.Atk.setTargetMob then
                    Ctx.Atk.setTargetMob(target.mob)
                end
                if Ctx.Atk.setRegion then
                    Ctx.Atk.setRegion(target.region)
                end
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
                print("[Dingus][Quest] auto disabled after 3 failures")
            end
        end
    end

    function Q.cycle()
        S.questCycleCount = S.questCycleCount + 1
        local now = U.clock()
        if now - S.questLastCycle < (F.QuestCycleT or 6.0) then
            return
        end
        S.questLastCycle = now

        if now - S.lastLevelRead > 10 then
            S.lastLevelRead = now
            S.playerLevel = readLevel()
            S.playerRace = readRace()
            local a = readActiveQuest()
            if a then
                S.activeQuestName = a.QuestString or a.Name
                local parts = {}
                for k, v in pairs(a.Tasks or {}) do
                    table.insert(parts, string.format(
                        "%s:%d/%d", k, v.Current, v.Max))
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

    function Q.isPriority(bossName)
        local list = S.questPriorityBosses
        if not list or #list == 0 then return true end
        local age = U.clock() - (S.questLastRead or 0)
        if age > (F.QuestPriorityStale * 2) then return true end
        local l = string.lower(bossName or "")
        for i = 1, #list do
            local t = string.lower(list[i])
            if l:find(t, 1, true) then return true end
            if t:find(l, 1, true) then return true end
        end
        return false
    end

    function Q.getPriorityBosses() return S.questPriorityBosses end
    function Q.getActiveQuests() return S.questActiveList end
    function Q.getPlayerLevel() return S.playerLevel end
    function Q.getPlayerRace() return S.playerRace end
    function Q.getBestQuest() return pickBestQuest(S.playerLevel) end

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
        if S.playerLevel < target.minLvl then
            return false, "level-too-low"
        end
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
        for _, q in ipairs(L.quests or {}) do
            table.insert(out, {
                name = q.name,
                display = q.display,
                minLvl = q.minLvl,
                category = q.cat,
                region = q.region,
                race = q.race,
                eligible = S.playerLevel >= q.minLvl and raceOk(q),
            })
        end
        return out
    end

    function Q.stats()
        local holder = "free"
        if Ctx.Hotbar and Ctx.Hotbar.isLocked then
            holder = Ctx.Hotbar.isLocked() or "free"
        end
        return {
            level = S.playerLevel or 0,
            race = S.playerRace or "?",
            autoQuest = S.autoQuest,
            questMode = S.questMode,
            activeQuestName = S.activeQuestName,
            activeQuestSummary = S.activeQuestSummary,
            priorityCount = #(S.questPriorityBosses or {}),
            priority = table.concat(
                S.questPriorityBosses or {}, ", "),
            lastReadAge = U.clock() - (S.questLastRead or 0),
            crowTool = S._crowTool and S._crowTool.Name or "not-found",
            hotbarHolder = holder,
            crowCycles = S.crowCycleCount,
            interacting = S.questIsInteracting,
            failures = S.autoAcceptFailures,
            availableQuests = #(L.quests or {}),
        }
    end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function()
        S.questIsInteracting = false
        S.autoQuest = false
    end)

    task.spawn(function()
        task.wait(3)
        S.playerLevel = readLevel()
        S.playerRace = readRace()
        print(string.format(
            "[Dingus][Quest] boot - lvl=%d race=%s quests=%d util=%s se=%s",
            S.playerLevel, S.playerRace, #(L.quests or {}),
            tostring(Utility ~= nil),
            tostring(SignalEvent ~= nil)))
    end)

    print(string.format(
        "[Dingus][quests] v10 - %s - %d quests - util=%s - se=%s",
        U.Platform, #(L.quests or {}),
        tostring(Utility ~= nil),
        tostring(SignalEvent ~= nil)))
end

return Q
