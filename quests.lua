local Q = {}

function Q.init(Ctx)
    local U     = Ctx.Util
    local Cfg   = Ctx.Cfg
    local St    = Ctx.St
    local Lists = Ctx.Lists

    -- HARDCODED to slot 5, no auto-probe
    Cfg.QuestCrowHotbar     = "5"

    Cfg.QuestCycleT         = Cfg.QuestCycleT         or 6.0
    Cfg.QuestMenuWait       = Cfg.QuestMenuWait       or 2.5
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
    St.questLevelDumped     = St.questLevelDumped or false

    local rs = game:GetService("ReplicatedStorage")

    local function log(msg)
        if Cfg.QuestVerbose then
            print("[Dingus][Quest] " .. msg)
        end
    end

    --============================================================
    -- LEVEL READER
    --============================================================
    local function getSlots()
        local ps = rs:FindFirstChild("Player_Service")
        local data = ps and ps:FindFirstChild("Data")
        local me = data and data:FindFirstChild(U.Lp.Name)
        if not me then return nil, nil end
        return me:FindFirstChild("slots"), me
    end

    local function readLevelVerbose()
        local slots, me = getSlots()
        if not slots then return 0, "no slots" end

        for _, slot in ipairs(slots:GetChildren()) do
            local prog = slot:FindFirstChild("Progression")
            local lvl = prog and prog:FindFirstChild("Level")
            if lvl then
                local ok, v = pcall(function() return lvl.Value end)
                if ok and type(v) == "number" and v > 0 then
                    return v, "slots." .. slot.Name .. ".Progression.Level"
                end
            end
        end

        for _, slot in ipairs(slots:GetChildren()) do
            local lvl = slot:FindFirstChild("Level")
            if lvl then
                local ok, v = pcall(function() return lvl.Value end)
                if ok and type(v) == "number" and v > 0 then
                    return v, "slots." .. slot.Name .. ".Level"
                end
            end
        end

        for _, slot in ipairs(slots:GetChildren()) do
            for _, d in ipairs(slot:GetDescendants()) do
                if d.Name == "Level" and (d:IsA("NumberValue") or d:IsA("IntValue")) and d.Value > 0 then
                    return d.Value, "deep:" .. d:GetFullName()
                end
            end
        end

        local char = U.Lp.Character
        if char then
            for _, attr in ipairs({"Level", "level", "PlayerLevel", "LVL"}) do
                local ok, v = pcall(function() return char:GetAttribute(attr) end)
                if ok and type(v) == "number" and v > 0 then
                    return v, "charAttr:" .. attr
                end
            end
        end

        if not St.questLevelDumped then
            St.questLevelDumped = true
            print("[Dingus][Quest] LEVEL NOT FOUND — dumping slots tree:")
            for _, slot in ipairs(slots:GetChildren()) do
                print(string.format("  slot: %s (%s)", slot.Name, slot.ClassName))
                for _, d in ipairs(slot:GetDescendants()) do
                    if d:IsA("NumberValue") or d:IsA("IntValue") then
                        print(string.format("    %s = %s", d:GetFullName(), tostring(d.Value)))
                    end
                end
            end
            if me then
                print("  --- me top-level children ---")
                for _, c in ipairs(me:GetChildren()) do
                    print(string.format("    %s (%s)", c.Name, c.ClassName))
                end
            end
        end
        return 0, "no match"
    end

    function Q.readLevel() return (readLevelVerbose()) end

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
                print("[Dingus][Quest] BossHunts not found")
            end
            return {}
        end

        local out = {}
        local firstConfig = nil
        for _, cfg in ipairs(folder:GetChildren()) do
            if cfg:IsA("Configuration") then
                if not firstConfig then firstConfig = cfg end
                local entry = { id = tonumber(cfg.Name) or cfg.Name, name = cfg.Name, fields = {}, raw = cfg }
                for _, child in ipairs(cfg:GetChildren()) do
                    local ok, v = pcall(function() return child.Value end)
                    entry.fields[child.Name] = ok and v or child.ClassName
                end
                entry.boss = entry.fields.Boss or entry.fields.BossName or entry.fields.Target or entry.fields.NPC or entry.fields.Name
                entry.xp = tonumber(entry.fields.XP or entry.fields.Experience or entry.fields.Reward or entry.fields.RewardXP)
                entry.wen = tonumber(entry.fields.Wen or entry.fields.Money or entry.fields.Currency)
                table.insert(out, entry)
            end
        end

        table.sort(out, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)

        if Cfg.QuestLogStructure and not St.questStructureLogged and firstConfig then
            St.questStructureLogged = true
            local fields = {}
            for _, c in ipairs(firstConfig:GetChildren()) do
                local ok, v = pcall(function() return c.Value end)
                table.insert(fields, string.format("%s=%s", c.Name, ok and tostring(v) or "<"..c.ClassName..">"))
            end
            print("[Dingus][Quest] BossHunts at " .. tostring(path))
            print("[Dingus][Quest] sample config: " .. table.concat(fields, " "))
            local ids = {}
            for _, h in ipairs(out) do table.insert(ids, tostring(h.id)) end
            print(string.format("[Dingus][Quest] parsed %d hunts: %s", #out, table.concat(ids, ", ")))
        end
        St.questAvailableCount = #out
        return out
    end

    --============================================================
    -- CROW TOOL FINDER
    --============================================================
    local CROW_NAMES = { "crow", "kasugai", "kasugai crow", "karasu", "crow tool", "crowt", "the crow", "bird" }

    local function isCrowish(name)
        if not name then return false end
        local l = string.lower(name)
        for _, n in ipairs(CROW_NAMES) do if l == n then return true end end
        if l:find("crow", 1, true) or l:find("kasugai", 1, true) then return true end
        return false
    end

    local function findCrowToolVerbose()
        local plr = U.Lp
        local char = plr.Character
        if char then
            for _, c in ipairs(char:GetChildren()) do
                if c:IsA("Tool") and isCrowish(c.Name) then return c, "CharacterTool" end
            end
        end
        local bp = plr:FindFirstChildOfClass("Backpack")
        if bp then
            for _, c in ipairs(bp:GetChildren()) do
                if c:IsA("Tool") and isCrowish(c.Name) then return c, "BackpackTool" end
            end
        end
        if char then
            for _, c in ipairs(char:GetDescendants()) do
                if (c:IsA("Model") or c:IsA("MeshPart") or c:IsA("BasePart")) and isCrowish(c.Name) then return c, "CustomMesh" end
            end
        end
        return nil, nil
    end

    --============================================================
    -- EQUIP CROW (using slot 5)
    --============================================================
    local function equipCrow()
        -- Already equipped?
        local tool, from = findCrowToolVerbose()
        if tool and (from == "CharacterTool" or from == "CustomMesh") then
            return tool
        end

        local H = Ctx.Hotbar
        if not H then return nil end

        -- Use the mutex to prevent conflict with weapon equip
        if not H.acquire("quest-crow", 3.0) then
            if Cfg.QuestVerbose then log("hotbar busy, skipping crow equip") end
            return nil
        end

        local slot = "5" -- HARDCODED slot 5
        if Cfg.QuestVerbose then log("equipping crow via hotbar slot '5'") end

        pcall(function() U.tap(slot) end)
        task.wait(0.45)

        -- Verify
        tool, from = findCrowToolVerbose()
        if not tool then
            if Cfg.QuestVerbose then log("slot 5 did not equip crow") end
        end

        H.release("quest-crow")
        return tool
    end

    --============================================================
    -- PANEL FINDERS
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
                    if okT and type(txt) == "string" and txt:find("current tasks", 1, true) then
                        return inst.Parent or inst
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do table.insert(stack, { k, d + 1 }) end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        return nil
    end

    local function findCancelButton()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        local stack = { pg }
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
                for _, k in ipairs(inst:GetChildren()) do table.insert(stack, k) end
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
                        local boss = txt:match("^%s*Defeat%s+(.+)$") or txt:match("^%s*Eliminate%s+(.+)$") or txt:match("^%s*Hunt%s+(.+)$")
                        if boss then
                            boss = boss:gsub("%s+$", ""):gsub("^%s+", "")
                            table.insert(labels, { boss = boss, inst = inst })
                        end
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do table.insert(stack, k) end
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
            table.insert(out, { boss = entry.boss, timeLeft = timeLeft, label = entry.inst })
        end
        return out
    end

    --============================================================
    -- MENU OPEN / CLOSE
    --============================================================
    local function openMenu()
        if findPanelRoot() then return true end
        pcall(function() U.m1() end)
        local deadline = U.clock() + (Cfg.QuestMenuWait or 2.5)
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
        if #qs > 0 then St.questActiveList = qs; St.questLastRead = U.clock() end
        return qs
    end

    function Q.isPriority(bossName)
        local list = St.questPriorityBosses
        if not list or #list == 0 then return true end
        if (U.clock() - (St.questLastRead or 0)) > (Cfg.QuestPriorityStale * 2) then return true end
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
            if Ctx.Hotbar and Ctx.Hotbar.isLocked() then
                if Cfg.QuestVerbose then log("hotbar locked by " .. tostring(Ctx.Hotbar.isLocked()) .. ", deferring") end
                return
            end

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
                        print(string.format("[Dingus][Quest] %d active · %s", #qs, table.concat(names, ", ")))
                    else
                        if Cfg.QuestVerbose then log("crow panel open but no quest labels found") end
                    end
                    closeMenu()
                    St.questPanelOpened = false
                else
                    if Cfg.QuestVerbose then log("crow menu failed to open after M1") end
                end
            else
                if Cfg.QuestVerbose then log("crow not equipped (slot 5 failed)") end
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
                        print(string.format("    · %s = %s", c.Name, ok and tostring(v) or "?"))
                    end
                end
            end
        else
            print("[Dingus][Quest] BossHunts NOT FOUND")
        end
    end

    function Q.stats()
        local holder = "no-module"
        if Ctx.Hotbar and Ctx.Hotbar.isLocked then holder = Ctx.Hotbar.isLocked() or "free" end
        return {
            level = St.playerLevel or 0,
            availableHunts = St.questAvailableCount or 0,
            priorityCount = #(St.questPriorityBosses or {}),
            priority = table.concat(St.questPriorityBosses or {}, ", "),
            lastReadAge = U.clock() - (St.questLastRead or 0),
            cycles = St.questCycleCount or 0,
            panelOpen = St.questPanelOpened or false,
            crowTool = St.crT and St.crT.Name or "not found",
            crowSlot = Cfg.QuestCrowHotbar,
            hotbarHolder = holder,
        }
    end

    --============================================================
    -- BOOT
    --============================================================
    task.spawn(function()
        task.wait(3)
        print("[Dingus][Quest] v6 boot discovery (slot 5)")
        Q.readHunts()
        local lvl, which = readLevelVerbose()
        St.playerLevel = lvl
        if lvl > 0 then
            print(string.format("[Dingus][Quest] level=%d (%s)", lvl, tostring(which)))
        else
            print("[Dingus][Quest] level: NO PATH WORKED — see dump above")
        end
        print(string.format("[Dingus][Quest] ready · hunts=%d · crowSlot=5", St.questAvailableCount))
    end)

    print("[Dingus][quests] v6 initialized (slot 5)")
end

return Q
