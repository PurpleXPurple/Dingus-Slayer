    --============================================================
    -- CROW SUBSYSTEM v2
    -- Flow:
    --   1. Try findCrowTool (Character + Backpack)
    --   2. If missing, press "5" (hotbar slot) then re-check
    --   3. If not equipped, equip via Humanoid:EquipTool
    --   4. Trigger menu: M1 to call, wait for caw sound/notification
    --   5. Wait for the menu GUI to appear (Cancel button as proxy)
    --   6. Scan quest entries (TextLabels matching "Defeat X")
    --   7. Force-take: click each quest card, then Cancel
    --============================================================
    local Crow = { last = 0, cycles = 0, takeAttempts = 0 }
    Ctx.Crow = Crow

    -- Detect menu-open by finding a "Cancel" or "Close" TextButton.
    local function findCancelButton()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        local cc = pg:FindFirstChild("ComponentsHolder")
        if not cc then return nil end
        local stack = { cc }
        local iter = 0
        while #stack > 0 do
            local inst = table.remove(stack)
            if inst then
                if inst:IsA("TextButton") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string" then
                        local low = txt:lower():gsub("^%s+", ""):gsub("%s+$", "")
                        if low == "cancel" or low == "close" then
                            local okV, vis = pcall(function() return inst.Visible end)
                            if okV and vis then return inst end
                        end
                    end
                end
                local okc, kids = pcall(function() return inst:GetChildren() end)
                if okc and kids then
                    for i = 1, #kids do table.insert(stack, kids[i]) end
                end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        return nil
    end

    -- Find quest cards: clickable elements inside the crow panel that
    -- aren't the Cancel button. Returns a list of TextButtons.
    local function findQuestCards(cancelBtn)
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return {} end
        local cc = pg:FindFirstChild("ComponentsHolder")
        if not cc then return {} end

        -- Find the menu root — the deepest container that also
        -- contains cancelBtn.
        local menuRoot = nil
        local function findAncestor(node, target)
            local cur = node
            for _ = 1, 12 do
                if not cur then return nil end
                if cur == target then return cur end
                cur = cur.Parent
            end
            return nil
        end
        if cancelBtn then
            menuRoot = findAncestor(cancelBtn, cc) or cc
        else
            menuRoot = cc
        end

        local out = {}
        local seen = {}
        local stack = { menuRoot }
        local iter = 0
        while #stack > 0 do
            local inst = table.remove(stack)
            if inst then
                if inst:IsA("TextButton") and inst ~= cancelBtn then
                    local okV, vis = pcall(function() return inst.Visible end)
                    if okV and vis then
                        local okA, act = pcall(function() return inst.Active end)
                        if okA and act then
                            if not seen[inst] then
                                seen[inst] = true
                                table.insert(out, inst)
                            end
                        end
                    end
                end
                local okc, kids = pcall(function() return inst:GetChildren() end)
                if okc and kids then
                    for i = 1, #kids do table.insert(stack, kids[i]) end
                end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        return out
    end

    -- Read quest text from menu TextLabels
    local function readCrowQuests()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return {} end
        local cc = pg:FindFirstChild("ComponentsHolder")
        if not cc then return {} end
        local found = {}
        local seen = {}
        local stack = { cc }
        local iter = 0
        while #stack > 0 do
            local inst = table.remove(stack)
            if inst then
                if inst:IsA("TextLabel") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string" then
                        local name = txt:match("^%s*Defeat%s+(.+)$")
                            or txt:match("^%s*Eliminate%s+(.+)$")
                        if name then
                            name = name:gsub("%s+$", "")
                            if #name > 0 and #name < 40 and not seen[name] then
                                seen[name] = true
                                table.insert(found, name)
                            end
                        end
                    end
                end
                local okc, kids = pcall(function() return inst:GetChildren() end)
                if okc and kids then
                    for i = 1, #kids do table.insert(stack, kids[i]) end
                end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        return found
    end

    -- Wait for caw sound (crow notification) after M1 call
    local function waitForCaw(timeout)
        local deadline = U.clock() + (timeout or 3.0)
        while U.clock() < deadline do
            local ws = workspace:GetDescendants()
            for i = 1, #ws do
                local s = ws[i]
                if s:IsA("Sound") and s.IsPlaying then
                    local l = string.lower(s.Name)
                    if string.find(l, "caw", 1, true)
                        or string.find(l, "crow", 1, true)
                        or string.find(l, "chaa", 1, true) then
                        return true
                    end
                end
            end
            task.wait(0.1)
        end
        return false
    end

    local function crowCycle()
        if not St.crw then return end
        local now = U.clock()
        if now - Crow.last < Cfg.CrowCheckT then return end
        Crow.last = now
        Crow.cycles = Crow.cycles + 1

        -- Step 1: find tool in Character or Backpack
        local tool = Ctx.Scan.findCrowTool()
        if not tool then
            -- Step 2: press hotbar 5 to equip from inventory hotbar
            U.tap("5")
            task.wait(0.4)
            tool = Ctx.Scan.findCrowTool()
        end
        if not tool then return end
        St.crT = tool

        -- Step 3: ensure equipped
        local c = U.Lp.Character
        if not c then return end
        local equipped = false
        for _, x in ipairs(c:GetChildren()) do
            if x:IsA("Tool") and Lists.isCrow(x.Name) then
                equipped = true
                break
            end
        end
        if not equipped and tool:IsA("Tool") then
            local h = U.hum()
            if h then
                pcall(function() h:EquipTool(tool) end)
                task.wait(0.4)
            end
        end

        -- Step 4: check if menu already open
        local cancel = findCancelButton()
        if not cancel then
            -- Trigger the call. If not holding the tool, one M1.
            -- If holding, M1 usually clicks. Try once, then wait.
            U.m1()
            waitForCaw(3.0)
            task.wait(0.4)
            cancel = findCancelButton()
        end

        if not cancel then
            -- Menu never opened. Try a second M1 sometimes works.
            U.m1()
            task.wait(0.8)
            cancel = findCancelButton()
        end

        if not cancel then return end
        St.cPrch = true

        -- Step 5: read quests
        local quests = readCrowQuests()
        if #quests > 0 then
            St.crQuests = quests
            print(string.format("[Dingus][Crow] %d quests: %s",
                #quests, table.concat(quests, ", ")))
        end

        -- Step 6: force-take — click every quest card
        local cards = findQuestCards(cancel)
        if #cards > 0 then
            for i, card in ipairs(cards) do
                if card and card.Parent then
                    pcall(function() card:Activate() end)
                    Crow.takeAttempts = Crow.takeAttempts + 1
                    task.wait(0.15)
                end
            end
            print(string.format("[Dingus][Crow] force-took %d quest card(s) · total %d",
                #cards, Crow.takeAttempts))
        else
            print("[Dingus][Crow] no quest cards found in panel")
        end

        -- Step 7: close menu
        cancel = findCancelButton()
        if cancel then
            pcall(function() cancel:Activate() end)
            task.wait(0.3)
        end
    end
