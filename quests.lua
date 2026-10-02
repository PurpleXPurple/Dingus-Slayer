--[[
    Dingus-Slayer · quests.lua v2
    Read-only quest router. No remotes — the game auto-assigns quests.

    Recon facts (2026-10-02):
      ReplicatedStorage.BossHunts        — Configuration instances numbered 3-10+
      ReplicatedStorage.Assets.Quests    — item templates (JewelryBox etc.)
      ReplicatedStorage.Assets.Chests    — chest templates including World Events Chest
      Crow panel: passive display, no accept button, timer auto-cycles at 5 slots

    Flow:
      1. Periodically equip crow + M1 to open the menu
      2. Read assigned quests ("Defeat X" rows)
      3. Close menu
      4. Expose priority boss list to attack.lua
      5. Combat filters targets to priority bosses only
      6. Menu reopens every QuestCycleT to pick up new assignments

    No remote is required. Rewards are auto-collected by the game on kill.
]]--

local Q = {}

function Q.init(Ctx)
    local U     = Ctx.Util
    local Cfg   = Ctx.Cfg
    local St    = Ctx.St
    local Lists = Ctx.Lists

    --============================================================
    -- CONFIG
    --============================================================
    Cfg.QuestCycleT         = Cfg.QuestCycleT         or 6.0
    Cfg.QuestCrowHotbar     = Cfg.QuestCrowHotbar     or "5"
    Cfg.QuestMenuWait       = Cfg.QuestMenuWait       or 2.0
    Cfg.QuestLogStructure   = Cfg.QuestLogStructure   ~= false
    Cfg.QuestPriorityStale  = Cfg.QuestPriorityStale  or 90
    Cfg.QuestReadOnOpen     = Cfg.QuestReadOnOpen     ~= false

    --============================================================
    -- STATE
    --============================================================
    St.questPriorityBosses  = {}
    St.questActiveList      = {}
    St.questLastRead        = 0
    St.questLastCycle       = 0
    St.questCycleCount      = 0
    St.questStructureLogged = false
    St.questAvailableCount  = 0
    St.questMaxSlots        = 5
    St.questNextMissionAt   = 0
    St.questPanelOpened     = false

    local rs = game:GetService("ReplicatedStorage")

    --============================================================
    -- FOLDER RESOLUTION
    --============================================================
    local function bossHuntsFolder()
        return rs:FindFirstChild("BossHunts")
    end

    local function assetsFolder()
        return rs:FindFirstChild("Assets")
    end

    --============================================================
    -- BOSS HUNTS READER
    --============================================================
    local function describeConfig(cfg)
        local fields = {}
        for _, child in ipairs(cfg:GetChildren()) do
            local ok, v = pcall(function() return child.Value end)
            if ok then
                table.insert(fields, string.format("%s=%s", child.Name, tostring(v)))
            else
                table.insert(fields, string.format("%s<%s>", child.Name, child.ClassName))
            end
        end
        return table.concat(fields, " ")
    end

    function Q.readHunts()
        local folder = bossHuntsFolder()
        if not folder then return {} end

        local out = {}
        local firstStructure = nil
        for _, cfg in ipairs(folder:GetChildren()) do
            if cfg:IsA("Configuration") then
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
                    or entry.fields.Name
                entry.xp = tonumber(entry.fields.XP
                    or entry.fields.Experience
                    or entry.fields.Reward)
                entry.wen = tonumber(entry.fields.Wen
                    or entry.fields.Money
                    or entry.fields.Currency)

                if not firstStructure then
                    firstStructure = describeConfig(cfg)
                end
                table.insert(out, entry)
            end
        end

        table.sort(out, function(a, b)
            return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
        end)

        if Cfg.QuestLogStructure and not St.questStructureLogged
           and firstStructure then
            St.questStructureLogged = true
            print("[Dingus][Quest] BossHunts structure: " .. firstStructure)
            local ids = {}
            for _, h in ipairs(out) do
                table.insert(ids, tostring(h.id))
            end
            print(string.format("[Dingus][Quest] parsed %d hunts: %s",
                #out, table.concat(ids, ", ")))
        end

        St.questAvailableCount = #out
        return out
    end

    --============================================================
    -- PLAYER LEVEL
    --============================================================
    function Q.readLevel()
        local ok, result = pcall(function()
            local hf = workspace:FindFirstChild("Humanoids")
            local me = hf and hf:FindFirstChild(U.Lp.Name)
            if me then
                local prog = me:FindFirstChild("Progression")
                local lvl = prog and prog:FindFirstChild("Level")
                if lvl and (lvl:IsA("NumberValue") or lvl:IsA("IntValue")) then
                    return lvl.Value
                end
            end
            local ps = rs:FindFirstChild("Player_Service")
            local data = ps and ps:FindFirstChild("Data")
            local me2 = data and data:FindFirstChild(U.Lp.Name)
            local slots = me2 and me2:FindFirstChild("slots")
            if slots then
                for _, slot in ipairs(slots:GetChildren()) do
                    local prog = slot:FindFirstChild("Progression")
                    local lvl = prog and prog:FindFirstChild("Level")
                    if lvl and (lvl:IsA("NumberValue") or lvl:IsA("IntValue")) then
                        return lvl.Value
                    end
                end
            end
            return 0
        end)
        return ok and result or 0
    end

    --============================================================
    -- CROW PANEL FINDERS
    --============================================================
    -- Panel root detection: look for the "Here are your current tasks"
    -- header text which is unique to the crow menu.
    local function findPanelRoot()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end

        local stack = { { pg, 0 } }
        local iter = 0
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 8 then
                if inst:IsA("TextLabel") then
                    local okT, txt = pcall(function() return inst.Text end)
                    if okT and type(txt) == "string"
                       and txt:find("current tasks", 1, true) then
                        -- Walk up to a reasonable root
                        local cur = inst
                        for _ = 1, 5 do
                            if cur and cur.Parent and cur.Parent:IsA("ScreenGui") then
                                return cur.Parent
                            end
                            cur = cur.Parent
                        end
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

    --============================================================
    -- QUEST ROW READER
    -- Returns list of { boss, xp, wen, timeLeft, rawLabel }
    --============================================================
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

        -- Collect all "Defeat X" labels
        local labels = {}
        local stack = { root }
        local iter = 0
        while #stack > 0 do
            local inst = table.remove(stack)
            if inst then
                if inst:IsA("TextLabel") then
                    local okT, txt = pcall(function() return inst.Text end)
                    if okT and type(txt) == "string" then
                        local bossName = txt:match("^%s*Defeat%s+(.+)$")
                            or txt:match("^%s*Eliminate%s+(.+)$")
                            or txt:match("^%s*Hunt%s+(.+)$")
                        if bossName then
                            bossName = bossName:gsub("%s+$", ""):gsub("^%s+", "")
                            table.insert(labels, {
                                boss = bossName,
                                inst = inst,
                            })
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

        -- For each quest label, walk up the ancestry tree looking for
        -- sibling time + reward labels within a few levels.
        local out = {}
        for _, entry in ipairs(labels) do
            local boss = entry.boss
            local timeLeft, xp, wen = nil, nil, nil

            local anchor = entry.inst
            for up = 1, 4 do
                anchor = anchor and anchor.Parent
                if not anchor then break end
                for _, sib in ipairs(anchor:GetChildren()) do
                    if sib ~= entry.inst then
                        if sib:IsA("TextLabel") then
                            local txt = sib.Text
                            local t = parseTimeLeft(txt)
                            if t then timeLeft = t end
                            local num = txt:match("([%d,]+)")
                            if num then
                                local clean = tonumber(num:gsub(",", ""))
                                if clean and clean > 100 and not xp then
                                    xp = clean
                                elseif clean and clean > 10 and not wen then
                                    wen = clean
                                end
                            end
                        end
                    end
                end
            end

            table.insert(out, {
                boss = boss,
                timeLeft = timeLeft,
                xp = xp,
                wen = wen,
                label = entry.inst,
            })
        end
        return out
    end

    --============================================================
    -- MENU OPEN / CLOSE
    --============================================================
    local function crowToolEquipped()
        local c = U.Lp.Character
        if not c then return nil end
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and Lists.isCrow and Lists.isCrow(t.Name) then
                return t
            end
        end
        return nil
    end

    local function equipCrow()
        local tool = crowToolEquipped()
        if tool then return tool end

        -- Try scanner cache
        if Ctx.Scan and Ctx.Scan.findCrowTool then
            local t = Ctx.Scan.findCrowTool()
            if t and t:IsA("Tool") then
                local h = U.hum()
                if h then
                    pcall(function() h:EquipTool(t) end)
                    task.wait(0.5)
                    return crowToolEquipped()
                end
            end
        end

        -- Try hotbar key
        pcall(function() U.tap(Cfg.QuestCrowHotbar) end)
        task.wait(0.5)
        return crowToolEquipped()
    end

    local function openMenu()
        if findPanelRoot() then return true end
        pcall(function() U.m1() end)
        local deadline = U.clock() + Cfg.QuestMenuWait
        while U.clock() < deadline do
            if findPanelRoot() then return true end
            task.wait(0.15)
        end
        -- Second attempt
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
        -- Some panels close on M1 anywhere
        pcall(function() U.m1() end)
        task.wait(0.3)
        return false
    end

    --============================================================
    -- PUBLIC · READ CYCLE
    --============================================================
    function Q.readActiveQuests()
        if not Cfg.QuestReadOnOpen then return St.questActiveList end
        local quests = readQuestsFromPanel()
        if #quests > 0 then
            St.questActiveList = quests
            St.questLastRead = U.clock()
        end
        return quests
    end

    --============================================================
    -- PUBLIC · PRIORITY EXPOSURE
    -- attack.lua reads Q.isPriority(bossName).
    --============================================================
    function Q.isPriority(bossName)
        if not bossName then return true end
        local list = St.questPriorityBosses
        if not list or #list == 0 then return true end  -- no filter = kill anything

        local lower = string.lower(bossName)
        for i = 1, #list do
            local target = string.lower(list[i])
            if lower:find(target, 1, true) or target:find(lower, 1, true) then
                return true
            end
        end
        return false
    end

    function Q.getPriorityBosses()
        return St.questPriorityBosses
    end

    --============================================================
    -- PUBLIC · CYCLE (called by main scheduler)
    --============================================================
    function Q.cycle()
        local now = U.clock()
        if now - St.questLastCycle < Cfg.QuestCycleT then return end
        St.questLastCycle = now
        St.questCycleCount = St.questCycleCount + 1

        -- Refresh available hunts + player level
        Q.readHunts()
        St.playerLevel = Q.readLevel()

        -- Refresh priorities if stale
        local stale = (now - St.questLastRead) > Cfg.QuestPriorityStale
        local slotsFull = #St.questPriorityBosses >= St.questMaxSlots

        if stale or slotsFull or #St.questPriorityBosses == 0 then
            local tool = equipCrow()
            if tool then
                local opened = openMenu()
                if opened then
                    St.questPanelOpened = true
                    local quests = readQuestsFromPanel()
                    if #quests > 0 then
                        local names = {}
                        for i = 1, #quests do
                            table.insert(names, quests[i].boss)
                        end
                        St.questPriorityBosses = names
                        St.questActiveList = quests
                        St.questLastRead = now
                        print(string.format("[Dingus][Quest] %d active · %s",
                            #quests, table.concat(names, ", ")))
                    end
                    closeMenu()
                    St.questPanelOpened = false
                end
            end
        end
    end

    --============================================================
    -- PUBLIC · STRUCTURE DUMP (for debugging)
    --============================================================
    function Q.dumpStructure()
        local folder = bossHuntsFolder()
        if folder then
            print("[Dingus][Quest] BossHunts children:")
            for _, cfg in ipairs(folder:GetChildren()) do
                print(string.format("  %s (%s) — %s",
                    cfg.Name, cfg.ClassName,
                    cfg:IsA("Configuration") and describeConfig(cfg) or ""))
            end
        end
        local assets = assetsFolder()
        if assets then
            local q = assets:FindFirstChild("Quests")
            if q then
                print("[Dingus][Quest] Assets.Quests:")
                for _, c in ipairs(q:GetChildren()) do
                    print(string.format("  %s (%s)", c.Name, c.ClassName))
                end
            end
            local ch = assets:FindFirstChild("Chests")
            if ch then
                print("[Dingus][Quest] Assets.Chests:")
                for _, c in ipairs(ch:GetChildren()) do
                    print(string.format("  %s (%s)", c.Name, c.ClassName))
                end
            end
        end
    end

    --============================================================
    -- PUBLIC · STATS
    --============================================================
    function Q.stats()
        return {
            level = St.playerLevel or 0,
            availableHunts = St.questAvailableCount or 0,
            priorityCount = #(St.questPriorityBosses or {}),
            priority = table.concat(St.questPriorityBosses or {}, ", "),
            lastReadAge = U.clock() - (St.questLastRead or 0),
            cycles = St.questCycleCount or 0,
            panelOpen = St.questPanelOpened or false,
        }
    end

    --============================================================
    -- BOOT · one-shot discovery
    --============================================================
    task.spawn(function()
        task.wait(3)
        print("[Dingus][Quest] boot discovery...")
        Q.readHunts()
        St.playerLevel = Q.readLevel()
        print(string.format("[Dingus][Quest] ready · level=%d hunts=%d",
            St.playerLevel, St.questAvailableCount))
    end)

    print("[Dingus][quests] v2 initialized · read-only router")
end

return Q
