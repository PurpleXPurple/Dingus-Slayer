-- Dingus-Slayer · quests.lua v8

local Q = {}

function Q.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St

    St.questPriorityBosses = St.questPriorityBosses or {}
    St.questLastRead = St.questLastRead or 0
    St.questLastCycle = St.questLastCycle or 0
    St.questCycleCount = St.questCycleCount or 0
    St.questAvailableCount = St.questAvailableCount or 0
    St._panelRoot = nil
    St._crowTool = nil

    local rs = U.RS

    local function getSlots()
        local ps = rs:FindFirstChild("Player_Service")
        local data = ps and ps:FindFirstChild("Data")
        local me = data and data:FindFirstChild(U.Lp.Name)
        if not me then return nil end
        return me:FindFirstChild("slots")
    end

    function Q.readLevel()
        local slots = getSlots()
        if not slots then return 0 end
        for _, slot in ipairs(slots:GetChildren()) do
            local prog = slot:FindFirstChild("Progression")
            local lvl = prog and prog:FindFirstChild("Level")
            if lvl then
                local ok, v = pcall(function() return lvl.Value end)
                if ok and type(v) == "number" and v > 0 then return v end
            end
        end
        return 0
    end

    local function findBossHunts()
        local bh = rs:FindFirstChild("BossHunts")
        if bh then return bh end
        local assets = rs:FindFirstChild("Assets")
        return assets and assets:FindFirstChild("BossHunts")
    end

    function Q.readHunts()
        local folder = findBossHunts()
        if not folder then return {} end
        local out = {}
        for _, cfg in ipairs(folder:GetChildren()) do
            if cfg:IsA("Configuration") then
                table.insert(out, { id = tonumber(cfg.Name) or cfg.Name })
            end
        end
        St.questAvailableCount = #out
        return out
    end

    local function isCrowish(name)
        if not name then return false end
        local l = string.lower(name)
        return l == "crow" or l:find("crow", 1, true) or l:find("kasugai", 1, true)
    end

    local function findCrowTool()
        if St._crowTool and St._crowTool.Parent then return St._crowTool end
        local char = U.Lp.Character
        if char then
            for _, c in ipairs(char:GetChildren()) do
                if c:IsA("Tool") and isCrowish(c.Name) then
                    St._crowTool = c
                    return c
                end
            end
        end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then
            for _, c in ipairs(bp:GetChildren()) do
                if c:IsA("Tool") and isCrowish(c.Name) then
                    St._crowTool = c
                    return c
                end
            end
        end
        return nil
    end

    local function getComponentsHolder()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        return pg and pg:FindFirstChild("ComponentsHolder") or nil
    end

    local function findPanelRoot()
        local cc = getComponentsHolder()
        if not cc then return nil end
        local stack = { { cc, 0 } }
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 6 then
                if inst:IsA("TextLabel") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string" and txt:find("current tasks", 1, true) then
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

    local function findCancelButton()
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

    local function readQuestsFromPanel()
        local root = findPanelRoot()
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
                        if boss then
                            boss = boss:gsub("%s+$", ""):gsub("^%s+", "")
                            table.insert(out, { boss = boss })
                        end
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do table.insert(stack, k) end
            end
        end
        return out
    end

    local function openMenu()
        if findPanelRoot() then return true end
        U.m1()
        local deadline = U.clock() + (Cfg.QuestMenuWait or 2.5)
        while U.clock() < deadline do
            if findPanelRoot() then return true end
            task.wait(0.15)
        end
        return findPanelRoot() ~= nil
    end

    local function closeMenu()
        local c = findCancelButton()
        if c then
            pcall(function() c:Activate() end)
            task.wait(0.3)
            return true
        end
        return false
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
        if now - St.questLastCycle < (Cfg.QuestCycleT or 6.0) then return end
        St.questLastCycle = now
        Q.readHunts()
        St.playerLevel = Q.readLevel()
        local stale = (now - St.questLastRead) > (Cfg.QuestPriorityStale or 90)
        local empty = #St.questPriorityBosses == 0
        if stale or empty then
            if Ctx.Hotbar and Ctx.Hotbar.isLocked() then return end
            local tool = findCrowTool()
            if not tool then
                U.fireSkill(Cfg.QuestCrowHotbar or "5") or U.tap(Cfg.QuestCrowHotbar or "5")
                task.wait(0.45)
                tool = findCrowTool()
            end
            if tool then
                if openMenu() then
                    local qs = readQuestsFromPanel()
                    if #qs > 0 then
                        local names = {}
                        for _, q in ipairs(qs) do table.insert(names, q.boss) end
                        St.questPriorityBosses = names
                        St.questLastRead = now
                        print(string.format("[Dingus][Quest] %d active: %s",
                            #qs, table.concat(names, ", ")))
                    end
                    closeMenu()
                end
            end
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
            crowTool = St._crowTool and St._crowTool.Name or "not found",
        }
    end

    print(string.format("[Dingus][quests] v8 · %s", U.Platform))
end

return Q
