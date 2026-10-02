--[[
    Dingus-Slayer · quests.lua v3
    Multi-path level reader with self-diagnostics.
    BossHunts parsing with structure logging.
    Crow tool detection tolerant of name variants.
]]--

local Q = {}

function Q.init(Ctx)
    local U     = Ctx.Util
    local Cfg   = Ctx.Cfg
    local St    = Ctx.St
    local Lists = Ctx.Lists

    Cfg.QuestCycleT         = Cfg.QuestCycleT         or 6.0
    Cfg.QuestCrowHotbar     = Cfg.QuestCrowHotbar     or "5"
    Cfg.QuestMenuWait       = Cfg.QuestMenuWait       or 2.0
    Cfg.QuestLogStructure   = Cfg.QuestLogStructure   ~= false
    Cfg.QuestPriorityStale  = Cfg.QuestPriorityStale  or 90
    Cfg.QuestReadOnOpen     = Cfg.QuestReadOnOpen     ~= false
    Cfg.QuestVerbose        = Cfg.QuestVerbose        ~= false

    St.questPriorityBosses  = St.questPriorityBosses or {}
    St.questActiveList      = St.questActiveList or {}
    St.questLastRead        = St.questLastRead or 0
    St.questLastCycle       = St.questLastCycle or 0
    St.questCycleCount      = St.questCycleCount or 0
    St.questAvailableCount  = St.questAvailableCount or 0
    St.questPanelOpened     = false
    St.questStructureLogged = St.questStructureLogged or false
    St.questLevelPathsTried = {}

    local rs = game:GetService("ReplicatedStorage")

    local function log(msg)
        if Cfg.QuestVerbose then
            print("[Dingus][Quest] " .. msg)
        end
    end

    --============================================================
    -- LEVEL READER · multi-path with diagnostics
    --============================================================
    local function tryReadValue(inst, name)
        if not inst then return nil end
        local v = inst:FindFirstChild(name)
        if not v then return nil end
        local ok, val = pcall(function() return v.Value end)
        if ok and type(val) == "number" then return val end
        return nil
    end

    local LEVEL_PATHS = {
        function(plr, rs)
            -- Path 1: workspace.Humanoids.<name>.Progression.Level
            local hf = workspace:FindFirstChild("Humanoids")
            local me = hf and hf:FindFirstChild(plr.Name)
            if not me then return nil, "Humanoids.<name> missing" end
            return tryReadValue(me:FindFirstChild("Progression"), "Level"),
                   "Humanoids.Progression.Level"
        end,
        function(plr, rs)
            -- Path 2: workspace.Humanoids.Regions.<name>.Progression.Level
            local hf = workspace:FindFirstChild("Humanoids")
            local regions = hf and hf:FindFirstChild("Regions")
            if not regions then return nil, "Humanoids.Regions missing" end
            for _, r in ipairs(regions:GetChildren()) do
                local me = r:FindFirstChild(plr.Name) or r:FindFirstChild("Players") and r.Players:FindFirstChild(plr.Name)
                if me then
                    return tryReadValue(me:FindFirstChild("Progression"), "Level"),
                           "Regions.*.<name>.Progression.Level"
                end
            end
            return nil, "no match in Regions"
        end,
        function(plr, rs)
            -- Path 3: RS.Player_Service.Data.<name>.slots.SlotN.Progression.Level
            local ps = rs:FindFirstChild("Player_Service")
            local data = ps and ps:FindFirstChild("Data")
            local me = data and data:FindFirstChild(plr.Name)
            if not me then return nil, "Player_Service.Data.<name> missing" end
            local slots = me:FindFirstChild("slots")
            if not slots then return nil, "slots missing" end
            for _, slot in ipairs(slots:GetChildren()) do
                local v = tryReadValue(slot:FindFirstChild("Progression"), "Level")
                if v then return v, "slots." .. slot.Name .. ".Progression.Level" end
            end
            return nil, "no Level in any slot"
        end,
        function(plr, rs)
            -- Path 4: RS.Player_Service.Data.<name>.Profile.Level (alt structure)
            local ps = rs:FindFirstChild("Player_Service")
            local data = ps and ps:FindFirstChild("Data")
            local me = data and data:FindFirstChild(plr.Name)
            if not me then return nil, "no Data" end
            return tryReadValue(me, "Level"), "Data.<name>.Level"
        end,
        function(plr, rs)
            -- Path 5: character attribute
            local char = plr.Character
            if not char then return nil, "no char" end
            local ok, lvl = pcall(function() return char:GetAttribute("Level") end)
            if ok and type(lvl) == "number" then return lvl, "char attribute" end
            return nil, "no char attribute"
        end,
        function(plr, rs)
            -- Path 6: any NumberValue named Level anywhere in workspace.Humanoids
            local hf = workspace:FindFirstChild("Humanoids")
            if not hf then return nil, "no Humanoids" end
            local me = hf:FindFirstChild(plr.Name)
            if not me then return nil, "no me" end
            for _, d in ipairs(me:GetDescendants()) do
                if d.Name == "Level" and (d:IsA("NumberValue") or d:IsA("IntValue")) then
                    return d.Value, "descendant Level"
                end
            end
            return nil, "no descendant Level"
        end,
    }

    local function readLevelVerbose()
        local plr = U.Lp
        for i, pathFn in ipairs(LEVEL_PATHS) do
            local ok, v, tag = pcall(pathFn, plr, rs)
            if ok and v and type(v) == "number" and v > 0 then
                if Cfg.QuestVerbose then
                    log(string.format("level from path %d (%s): %d", i, tag, v))
                end
                return v, i
            end
        end
        return 0, 0
    end

    function Q.readLevel()
        local v = readLevelVerbose()
        return v
    end

    --============================================================
    -- BOSS HUNTS
    --============================================================
    local function findBossHunts()
        local bh = rs:FindFirstChild("BossHunts")
        if bh then return bh, "RS.BossHunts" end
        local assets = rs:FindFirstChild("Assets")
        if assets then
            local bh2 = assets:FindFirstChild("BossHunts")
            if bh2 then return bh2, "RS.Assets.BossHunts" end
        end
        return nil, nil
    end

    function Q.readHunts()
        local folder, path = findBossHunts()
        if not folder then
            if Cfg.QuestLogStructure and not St.questStructureLogged then
                St.questStructureLogged = true
                print("[Dingus][Quest] BossHunts not found in RS or RS.Assets")
            end
            return {}
        end

        local out = {}
        local firstConfig = nil
        for _, cfg in ipairs(folder:GetChildren()) do
            if cfg:IsA("Configuration") then
                if not firstConfig then firstConfig = cfg end
                local entry = {
                    id = tonumber(cfg.Name) or cfg.Name,
                    name = cfg.Name,
                    fields = {},
                    raw = cfg,
                }
                for _, child in ipairs(cfg:GetChildren()) do
                    local ok, v = pcall(function() return child.Value end)
                    entry.fields[child.Name] = ok and v or child.ClassName
                end
                entry.boss = entry.fields.Boss
                    or entry.fields.BossName
                    or entry.fields.Target
                    or entry.fields.NPC
                    or entry.fields.Name
                entry.xp = tonumber(entry.fields.XP
                    or entry.fields.Experience
                    or entry.fields.Reward
                    or entry.fields.RewardXP)
                entry.wen = tonumber(entry.fields.Wen
                    or entry.fields.Money
                    or entry.fields.Currency)
                table.insert(out, entry)
            end
        end

        table.sort(out, function(a, b)
            return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
        end)

        if Cfg.QuestLogStructure and not St.questStructureLogged and firstConfig then
            St.questStructureLogged = true
            local fields = {}
            for _, c in ipairs(firstConfig:GetChildren()) do
                local ok, v = pcall(function() return c.Value end)
                table.insert(fields, string.format("%s=%s",
                    c.Name, ok and tostring(v) or "<"..c.ClassName..">"))
            end
            print("[Dingus][Quest] BossHunts at " .. tostring(path))
            print("[Dingus][Quest] sample config: " .. table.concat(fields, " "))
            local ids = {}
            for _, h in ipairs(out) do table.insert(ids, tostring(h.id)) end
            print(string.format("[Dingus][Quest] parsed %d hunts: %s",
                #out, table.concat(ids, ", ")))
        end

        St.questAvailableCount = #out
        return out
    end

    --============================================================
    -- CROW TOOL FINDER · variant-tolerant
    --============================================================
    local CROW_NAMES = {
        "crow", "kasugai", "kasugai crow", "karasu",
        "crow tool", "crowt", "the crow",
    }

    local function isCrowish(name)
        if not name then return false end
        local l = string.lower(name)
        for _, n in ipairs(CROW_NAMES) do
            if l == n then return true end
        end
        -- substring
        if l:find("crow", 1, true) or l:find("kasugai", 1, true) then
            return true
        end
        return false
    end

    local function findCrowToolVerbose()
        local plr = U.Lp
        local found, from = nil, nil

        -- Character
        local char = plr.Character
        if char then
            for _, c in ipairs(char:GetChildren()) do
                if c:IsA("Tool") and isCrowish(c.Name) then
                    found, from = c, "Character"
                    break
                end
            end
        end

        -- Backpack
        if not found then
            local bp = plr:FindFirstChildOfClass("Backpack")
            if bp then
                for _, c in ipairs(bp:GetChildren()) do
                    if c:IsA("Tool") and isCrowish(c.Name) then
                        found, from = c, "Backpack"
                        break
                    end
                end
            end
        end

        if Cfg.QuestVerbose and not found then
            -- Log what IS in the backpack so we know what names exist
            local bp = plr:FindFirstChildOfClass("Backpack")
            if bp then
                local names = {}
                for _, c in ipairs(bp:GetChildren()) do
                    if c:IsA("Tool") then table.insert(names, c.Name) end
                end
                log("no crow tool. Backpack tools: " .. table.concat(names, ", "))
            end
        end

        return found, from
    end

    --============================================================
    -- PANEL FINDERS (unchanged shape, now read whole PlayerGui)
    --============================================================
    local function findPanelRoot()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        local stack = { { pg, 0 } }
        local iter = 0
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 10 then
                if inst:IsA("TextLabel") then
                    local okT, txt = pcall(function() return inst.Text end)
                    if okT and type(txt) == "string"
                       and txt:find("current tasks", 1, true) then
                        return inst.Parent or inst
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do
                    table.insert(stack, { k, d + 1 })
                end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        return nil
    end

    local function findCancelButton()
        local root = findPanelRoot()
        if not root then return nil end
        local stack = { root }
        local iter = 0
        while #stack > 0 do
            local inst = table.remove(stack)
            if inst then
                if inst:IsA("TextButton") then
                    local okT, txt = pcall(function() return inst.Text end)
                    if okT and type(txt) == "string" then
                        local l = txt:lower():gsub("^%s+", ""):gsub("%s+$", "")
                        if l == "cancel" or l == "close" then
                            local okV, vis = pcall(function() return inst.Visible end)
                            if okV and vis then return inst end
                        end
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do
                    table.insert(stack, k)
                end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        return nil
    end

    local function parseTimeLeft(s)
        if type(s) ~= "string" then return nil end
        local parts = {}
        for p in s:gmatch("%d+") do table.insert(parts, tonumber(p)) end
        if #parts == 2 then return parts[1] * 60 + parts[2] end
        if #parts == 3 then return parts[1] * 3600 + parts[2] * 60 + parts[3] end
        return nil
    end

    local function readQuestsFromPanel()
        local root = findPanelRoot()
        if not root then return {} end
        local labels = {}
        local stack = { root }
        local iter = 0
        while #stack > 0 do
            local inst = table.remove(stack)
            if inst then
                if inst:IsA("TextLabel") then
                    local okT, txt = pcall(function() return inst.Text end)
                    if okT and type(txt) == "string" then
                        local boss = txt:match("^%s*Defeat%s+(.+)$")
                            or txt:match("^%s*Eliminate%s+(.+)$")
                            or txt:match("^%s*Hunt%s+(.+)$")
                        if boss then
                            boss = boss:gsub("%s+$", ""):gsub("^%s+", "")
                            table.insert(labels, { boss = boss, inst = inst })
                        end
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do
                    table.insert(stack, k)
                end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        local out = {}
        for _, entry in ipairs(labels) do
            local timeLeft
            local anchor = entry.inst
            for _ = 1, 4 do
                anchor = anchor and anchor.Parent
                if not anchor then break end
                for _, sib in ipairs(anchor:GetChildren()) do
                    if sib ~= entry.inst and sib:IsA("TextLabel") then
                        local t = parseTimeLeft(sib.Text)
                        if t then timeLeft = t end
                    end
                end
            end
            table.insert(out, {
                boss = entry.boss,
                timeLeft = timeLeft,
                label = entry.inst,
            })
        end
        return out
    end

    --============================================================
    -- MENU OPEN / CLOSE
    --============================================================
    local function equipCrow()
        local tool = findCrowToolVerbose()
        if tool then
            local h = U.hum()
            if h then
                if tool.Parent ~= U.Lp.Character then
                    pcall(function() h:EquipTool(tool) end)
                    task.wait(0.5)
                end
            end
            return tool
        end
        -- hotbar fallback
        if Cfg.QuestCrowHotbar then
            pcall(function() U.tap(Cfg.QuestCrowHotbar) end)
            task.wait(0.5)
            return findCrowToolVerbose()
        end
        return nil
    end

    local function openMenu()
        if findPanelRoot() then return true end
        pcall(function() U.m1() end)
        local deadline = U.clock() + (Cfg.QuestMenuWait or 2.0)
        while U.clock() < deadline do
            if findPanelRoot() then return true end
            task.wait(0.15)
        end
        pcall(function() U.m1() end)
        task.wait(0.6)
        return findPanelRoot() ~= nil
    end

    local function closeMenu()
        local cancel = findCancelButton()
        if cancel then
            pcall(function() cancel:Activate() end)
            task.wait(0.3)
            return true
        end
        return false
    end

    --============================================================
    -- PUBLIC
    --============================================================
    function Q.readActiveQuests()
        if not Cfg.QuestReadOnOpen then return St.questActiveList end
        local qs = readQuestsFromPanel()
        if #qs > 0 then
            St.questActiveList = qs
            St.questLastRead = U.clock()
        end
        return qs
    end

    function Q.isPriority(bossName)
        local list = St.questPriorityBosses
        if not list or #list == 0 then return true end
        if (U.clock() - (St.questLastRead or 0)) > (Cfg.QuestPriorityStale * 2) then
            return true
        end
        local l = string.lower(bossName or "")
        for i = 1, #list do
            local t = string.lower(list[i])
            if l:find(t, 1, true) or t:find(l, 1, true) then return true end
        end
        return false
    end

    function Q.getPriorityBosses() return St.questPriorityBosses end

    function Q.cycle()
        local now = U.clock()
        St.questCycleCount = St.questCycleCount + 1

        if now - St.questLastCycle < Cfg.QuestCycleT then return end
        St.questLastCycle = now

        Q.readHunts()
        St.playerLevel = Q.readLevel()

        local stale = (now - St.questLastRead) > Cfg.QuestPriorityStale
        local empty = #St.questPriorityBosses == 0

        if stale or empty then
            local tool = equipCrow()
            if tool then
                St.crT = tool
                local opened = openMenu()
                if opened then
                    St.questPanelOpened = true
                    St.cPrch = true
                    local qs = readQuestsFromPanel()
                    if #qs > 0 then
                        local names = {}
                        for _, q in ipairs(qs) do table.insert(names, q.boss) end
                        St.questPriorityBosses = names
                        St.questActiveList = qs
                        St.questLastRead = now
                        print(string.format("[Dingus][Quest] %d active · %s",
                            #qs, table.concat(names, ", ")))
                    end
                    closeMenu()
                    St.questPanelOpened = false
                else
                    if Cfg.QuestVerbose then
                        log("crow menu failed to open")
                    end
                end
            else
                if Cfg.QuestVerbose then
                    log("no crow tool found, skipping menu open")
                end
            end
        end
    end

    function Q.dumpStructure()
        local folder, path = findBossHunts()
        if folder then
            print("[Dingus][Quest] BossHunts at " .. tostring(path))
            for _, cfg in ipairs(folder:GetChildren()) do
                print(string.format("  %s (%s)", cfg.Name, cfg.ClassName))
                if cfg:IsA("Configuration") then
                    for _, c in ipairs(cfg:GetChildren()) do
                        local ok, v = pcall(function() return c.Value end)
                        print(string.format("    · %s = %s",
                            c.Name, ok and tostring(v) or "?"))
                    end
                end
            end
        else
            print("[Dingus][Quest] BossHunts NOT FOUND")
        end
    end

    function Q.stats()
        return {
            level = St.playerLevel or 0,
            availableHunts = St.questAvailableCount or 0,
            priorityCount = #(St.questPriorityBosses or {}),
            priority = table.concat(St.questPriorityBosses or {}, ", "),
            lastReadAge = U.clock() - (St.questLastRead or 0),
            cycles = St.questCycleCount or 0,
            panelOpen = St.questPanelOpened or false,
            crowTool = St.crT and St.crT.Name or "not found",
        }
    end

    --============================================================
    -- BOOT
    --============================================================
    task.spawn(function()
        task.wait(3)
        print("[Dingus][Quest] v3 boot discovery")
        Q.readHunts()
        local lvl, which = readLevelVerbose()
        St.playerLevel = lvl
        if which > 0 then
            print(string.format("[Dingus][Quest] level=%d (path %d)", lvl, which))
        else
            print("[Dingus][Quest] level: NO PATH WORKED")
        end
        print(string.format("[Dingus][Quest] ready · hunts=%d",
            St.questAvailableCount))
    end)

    print("[Dingus][quests] v3 initialized")
end

return Q
