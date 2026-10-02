--[[
    Dingus-Slayer · quests.lua v7
    Panel + crow tool cached. No PlayerGui walks in hot path.

    Crash fixes:
      C2 · findPanelRoot, findCancelButton no longer walk whole PlayerGui
           on every call; cached by reference + verified cheaply.
      H1 · crow tool cached, no character:GetDescendants walks.
]]--

local Q = {}

function Q.init(Ctx)
    local U     = Ctx.Util
    local Cfg   = Ctx.Cfg
    local St    = Ctx.St
    local Lists = Ctx.Lists

    Cfg.QuestCrowHotbar     = Cfg.QuestCrowHotbar     or "5"
    Cfg.QuestCycleT         = Cfg.QuestCycleT         or 6.0
    Cfg.QuestMenuWait       = Cfg.QuestMenuWait       or 2.5
    Cfg.QuestLogStructure   = Cfg.QuestLogStructure   ~= false
    Cfg.QuestPriorityStale  = Cfg.QuestPriorityStale  or 90
    Cfg.QuestReadOnOpen     = Cfg.QuestReadOnOpen     ~= false
    Cfg.QuestVerbose        = Cfg.QuestVerbose        or false
    Cfg.QuestPanelCacheT    = Cfg.QuestPanelCacheT    or 1.0
    Cfg.QuestCrowCacheT     = Cfg.QuestCrowCacheT     or 2.0

    St.questPriorityBosses  = St.questPriorityBosses or {}
    St.questActiveList      = St.questActiveList or {}
    St.questLastRead        = St.questLastRead or 0
    St.questLastCycle       = St.questLastCycle or 0
    St.questCycleCount      = St.questCycleCount or 0
    St.questAvailableCount  = St.questAvailableCount or 0
    St.questPanelOpened     = false
    St.questStructureLogged = St.questStructureLogged or false
    St.questLevelDumped     = St.questLevelDumped or false

    -- Caches
    St._panelRoot       = nil
    St._panelCacheTs    = 0
    St._cancelBtn       = nil
    St._cancelCacheTs   = 0
    St._crowTool        = nil
    St._crowToolTs      = 0

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
                    return v, "slot.Progression.Level"
                end
            end
        end
        for _, slot in ipairs(slots:GetChildren()) do
            for _, d in ipairs(slot:GetDescendants()) do
                if d.Name == "Level"
                   and (d:IsA("NumberValue") or d:IsA("IntValue"))
                   and d.Value > 0 then
                    return d.Value, "deep"
                end
            end
        end

        if not St.questLevelDumped then
            St.questLevelDumped = true
            print("[Dingus][Quest] LEVEL NOT FOUND")
        end
        return 0, "no match"
    end

    function Q.readLevel() return (readLevelVerbose()) end

    --============================================================
    -- BOSS HUNTS
    --============================================================
    local function findBossHunts()
        local bh = rs:FindFirstChild("BossHunts")
        if bh then return bh end
        local assets = rs:FindFirstChild("Assets")
        if assets then return assets:FindFirstChild("BossHunts") end
        return nil
    end

    function Q.readHunts()
        local folder = findBossHunts()
        if not folder then return {} end
        local out = {}
        local firstConfig = nil
        for _, cfg in ipairs(folder:GetChildren()) do
            if cfg:IsA("Configuration") then
                if not firstConfig then firstConfig = cfg end
                local entry = { id = tonumber(cfg.Name) or cfg.Name, fields = {}, raw = cfg }
                for _, child in ipairs(cfg:GetChildren()) do
                    local ok, v = pcall(function() return child.Value end)
                    entry.fields[child.Name] = ok and v or child.ClassName
                end
                entry.boss = entry.fields.Boss or entry.fields.BossName
                    or entry.fields.Target or entry.fields.NPC or entry.fields.Name
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
                table.insert(fields, string.format("%s=%s", c.Name, ok and tostring(v) or "?"))
            end
            print("[Dingus][Quest] sample config: " .. table.concat(fields, " "))
        end
        St.questAvailableCount = #out
        return out
    end

    --============================================================
    -- CROW TOOL · cached, no GetDescendants
    --============================================================
    local CROW_NAMES = { "crow", "kasugai", "kasugai crow", "karasu", "bird" }

    local function isCrowish(name)
        if not name then return false end
        local l = string.lower(name)
        for _, n in ipairs(CROW_NAMES) do
            if l == n then return true end
        end
        if l:find("crow", 1, true) or l:find("kasugai", 1, true) then
            return true
        end
        return false
    end

    local function findCrowToolVerbose()
        local now = U.clock()
        if St._crowTool and St._crowTool.Parent
           and now - St._crowToolTs < Cfg.QuestCrowCacheT then
            return St._crowTool, "cached"
        end

        local plr = U.Lp
        local char = plr.Character
        if char then
            for _, c in ipairs(char:GetChildren()) do
                if c:IsA("Tool") and isCrowish(c.Name) then
                    St._crowTool = c
                    St._crowToolTs = now
                    return c, "CharacterTool"
                end
            end
            local rh = char:FindFirstChild("RightHand")
            if rh then
                for _, c in ipairs(rh:GetChildren()) do
                    if isCrowish(c.Name) then
                        St._crowTool = c
                        St._crowToolTs = now
                        return c, "HandMesh"
                    end
                end
            end
        end

        local bp = plr:FindFirstChildOfClass("Backpack")
        if bp then
            for _, c in ipairs(bp:GetChildren()) do
                if c:IsA("Tool") and isCrowish(c.Name) then
                    St._crowTool = c
                    St._crowToolTs = now
                    return c, "BackpackTool"
                end
            end
        end

        St._crowTool = nil
        return nil, nil
    end

    --============================================================
    -- PANEL · cached by reference
    --============================================================
    -- Instead of walking the entire PlayerGui, check the two known
    -- locations the game uses: ComponentsHolder and any ScreenGui
    -- that appears/disappears with the crow menu.
    local function getComponentsHolder()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        return pg:FindFirstChild("ComponentsHolder")
    end

    local function findPanelRoot()
        local now = U.clock()
        if St._panelRoot and St._panelRoot.Parent
           and now - St._panelCacheTs < Cfg.QuestPanelCacheT then
            return St._panelRoot
        end

        -- Fast path 1: ComponentsHolder for "current tasks" header
        local cc = getComponentsHolder()
        if not cc then
            St._panelRoot = nil
            return nil
        end

        -- Shallow scan of ComponentsHolder only (depth 6, not 10)
        local stack = { { cc, 0 } }
        local iter = 0
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 6 then
                if inst:IsA("TextLabel") then
                    local okT, txt = pcall(function() return inst.Text end)
                    if okT and type(txt) == "string"
                       and txt:find("current tasks", 1, true) then
                        local root = inst.Parent or inst
                        St._panelRoot = root
                        St._panelCacheTs = now
                        return root
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do
                    table.insert(stack, { k, d + 1 })
                end
                iter = iter + 1
                if iter >= 400 then break end  -- hard cap
            end
        end
        St._panelRoot = nil
        return nil
    end

    local function findCancelButton()
        local now = U.clock()
        if St._cancelBtn and St._cancelBtn.Parent
           and now - St._cancelCacheTs < Cfg.QuestPanelCacheT then
            local okV, vis = pcall(function() return St._cancelBtn.Visible end)
            if okV and vis then return St._cancelBtn end
        end

        -- Only scan ComponentsHolder, not whole PlayerGui
        local cc = getComponentsHolder()
        if not cc then
            St._cancelBtn = nil
            return nil
        end

        local stack = { { cc, 0 } }
        local iter = 0
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 6 then
                if inst:IsA("TextButton") then
                    local okT, txt = pcall(function() return inst.Text end)
                    if okT and type(txt) == "string" then
                        local l = txt:lower():gsub("^%s+", ""):gsub("%s+$", "")
                        if l == "cancel" or l == "close" then
                            local okV, vis = pcall(function() return inst.Visible end)
                            if okV and vis then
                                St._cancelBtn = inst
                                St._cancelCacheTs = now
                                return inst
                            end
                        end
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do
                    table.insert(stack, { k, d + 1 })
                end
                iter = iter + 1
                if iter >= 400 then break end
            end
        end
        St._cancelBtn = nil
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
                if iter >= 500 then break end
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
            table.insert(out, { boss = entry.boss, timeLeft = timeLeft })
        end
        return out
    end

    --============================================================
    -- MENU
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
        -- Invalidate cache so next check re-scans
        St._panelCacheTs = 0
        return findPanelRoot() ~= nil
    end

    local function closeMenu()
        local cancel = findCancelButton()
        if cancel then
            pcall(function() cancel:Activate() end)
            task.wait(0.3)
            St._cancelCacheTs = 0
            return true
        end
        return false
    end

    --============================================================
    -- PUBLIC
    --============================================================
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
            if Ctx.Hotbar and Ctx.Hotbar.isLocked() then return end

            local tool = findCrowToolVerbose()
            if not tool then
                local H = Ctx.Hotbar
                if H and H.acquire("quest-crow", 3.0) then
                    pcall(function() U.tap(Cfg.QuestCrowHotbar or "5") end)
                    task.wait(0.45)
                    tool = findCrowToolVerbose()
                    H.release("quest-crow")
                end
            end

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
                end
            end
        end
    end

    function Q.stats()
        local holder = "no-module"
        if Ctx.Hotbar and Ctx.Hotbar.isLocked then
            holder = Ctx.Hotbar.isLocked() or "free"
        end
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

    task.spawn(function()
        task.wait(3)
        print("[Dingus][Quest] v7 boot (cached panels)")
        Q.readHunts()
        local lvl = readLevelVerbose()
        St.playerLevel = lvl
        print(string.format("[Dingus][Quest] level=%d hunts=%d",
            lvl, St.questAvailableCount))
    end)

    print("[Dingus][quests] v7 initialized")
end

return Q
