--[[
    Dingus-Slayer · scanners.lua v4
    Crow-focused scanners. Adds helpers for the read-only crow menu:
      findCancelButton()  — menu-open detection
      readCrowQuests()    — read "Defeat X" quest labels
      findQuestCards()    — find clickable quest cards (force-take)
      waitForCaw()        — sound-based crow notification detection

    Kept from v3:
      findCrowTool()      — cached, no ReplicatedStorage fallback
      findCrowModel()     — cached, single return value
      activateCrowMenu()  — dedup activation
      findCrowMenu()      — legacy, returns nil (no accept button in game)
      stats()             — cache introspection

    Removed in v3 (stubbed): findCawSound, deepScan, dumpInventory
]]--

local S = {}

function S.init(Ctx)
    local U   = Ctx.Util
    local Cfg = Ctx.Cfg
    local St  = Ctx.St

    --============================================================
    -- CONFIG DEFAULTS
    --============================================================
    Cfg.CrowAcceptLabels = Cfg.CrowAcceptLabels or {
        "accept", "accept quest", "take", "take quest",
        "yes", "confirm", "eliminate", "hunt", "begin", "start",
    }
    Cfg.CrowCancelLabels = Cfg.CrowCancelLabels or {
        "cancel", "close", "back", "exit", "dismiss",
    }
    Cfg.CrowMenuCooldown = Cfg.CrowMenuCooldown or 30
    Cfg.CrowScanMinGap   = Cfg.CrowScanMinGap or 0.3
    Cfg.CrowModelTTL     = Cfg.CrowModelTTL or 2.0

    --============================================================
    -- STATE
    --============================================================
    local toolCache  = { inst = nil }
    local modelCache = { inst = nil, tag = nil, ts = 0 }
    local menuCache  = { btn = nil, ts = 0 }
    local lastScan   = { tool = 0, model = 0, menu = 0 }

    --============================================================
    -- LOCAL WALKER (early-exit)
    --============================================================
    local function walkUntil(root, maxDepth, predicate)
        if not root then return nil end
        local stack = { { root, 0 } }
        local iter = 0
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= maxDepth then
                local ok, hit, extra = pcall(predicate, inst, d)
                if ok and hit then return inst, extra end
                local okc, kids = pcall(function() return inst:GetChildren() end)
                if okc and kids then
                    for i = 1, #kids do
                        table.insert(stack, { kids[i], d + 1 })
                    end
                end
                iter = iter + 1
                if iter % 1500 == 0 then task.wait() end
            end
        end
        return nil
    end

    --============================================================
    -- NORMALIZERS
    --============================================================
    local function normalize(s)
        if type(s) ~= "string" then return "" end
        s = string.lower(s)
        s = s:gsub("^%s+", "")
        s = s:gsub("%s+$", "")
        return s
    end

    local function getPlayerGui()
        return U.Lp:FindFirstChildOfClass("PlayerGui")
    end

    local function getComponentsHolder()
        local pg = getPlayerGui()
        if not pg then return nil end
        return pg:FindFirstChild("ComponentsHolder")
    end

    --============================================================
    -- CROW TOOL
    --============================================================
    local function toolIsLive(t)
        if not t or not t.Parent then return false end
        local c = U.Lp.Character
        if c and t.Parent == c then return true end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp and t.Parent == bp then return true end
        return false
    end

    function S.findCrowTool()
        if toolCache.inst and toolIsLive(toolCache.inst) then
            return toolCache.inst
        end
        toolCache.inst = nil

        local now = U.clock()
        if now - lastScan.tool < Cfg.CrowScanMinGap then return nil end
        lastScan.tool = now

        local c = U.Lp.Character
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") and U.isCrowName(t.Name) then
                    toolCache.inst = t
                    return t
                end
            end
        end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and U.isCrowName(t.Name) then
                    toolCache.inst = t
                    return t
                end
            end
        end
        return nil
    end

    --============================================================
    -- CROW MODEL
    --============================================================
    local function modelIsLive(m)
        return m and m.Parent ~= nil
    end

    function S.findCrowModel()
        local now = U.clock()
        if modelCache.inst and modelIsLive(modelCache.inst)
           and now - modelCache.ts < Cfg.CrowModelTTL then
            return modelCache.inst
        end
        modelCache.inst = nil

        if now - lastScan.model < Cfg.CrowScanMinGap then return nil end
        lastScan.model = now

        local c = U.Lp.Character
        if c then
            for _, d in ipairs(c:GetChildren()) do
                if (d:IsA("Model") or d:IsA("Accessory")) and U.isCrowName(d.Name) then
                    modelCache.inst = d
                    modelCache.tag = "character"
                    modelCache.ts = now
                    return d
                end
            end
            local ut = c:FindFirstChild("UpperTorso")
            if ut then
                local att = ut:FindFirstChild("Crow-Shoulder-Attachment")
                if att then
                    modelCache.inst = att
                    modelCache.tag = "attachment"
                    modelCache.ts = now
                    return att
                end
            end
        end

        local myHrp = U.hrp()
        if myHrp then
            local myPos = myHrp.Position
            for _, d in ipairs(workspace:GetChildren()) do
                if d:IsA("Model") and U.isCrowName(d.Name) then
                    local p = d:FindFirstChild("HumanoidRootPart") or d.PrimaryPart
                    if p then
                        local dx = p.Position.X - myPos.X
                        local dy = p.Position.Y - myPos.Y
                        local dz = p.Position.Z - myPos.Z
                        if dx*dx + dy*dy + dz*dz < 2500 then
                            modelCache.inst = d
                            modelCache.tag = "nearby"
                            modelCache.ts = now
                            return d
                        end
                    end
                end
            end
        end
        return nil
    end

    --============================================================
    -- MENU OPEN DETECTION · findCancelButton
    --============================================================
    local function isCancelButton(inst)
        if not inst:IsA("TextButton") then return false end
        local okV, vis = pcall(function() return inst.Visible end)
        if not okV or not vis then return false end
        local okT, rawText = pcall(function() return inst.Text end)
        if not okT then return false end
        local t = normalize(rawText)
        if #t == 0 or #t > 20 then return false end
        for i = 1, #Cfg.CrowCancelLabels do
            if t == Cfg.CrowCancelLabels[i] then return true end
        end
        return false
    end

    function S.findCancelButton()
        local cc = getComponentsHolder()
        if not cc then return nil end
        return walkUntil(cc, 6, isCancelButton)
    end

    --============================================================
    -- QUEST READER · readCrowQuests
    --============================================================
    local function readQuestsFromTree(root)
        local found = {}
        local seen = {}
        if not root then return found end

        local stack = { root }
        local iter = 0
        while #stack > 0 do
            local inst = table.remove(stack)
            if inst then
                if inst:IsA("TextLabel") then
                    local okT, txt = pcall(function() return inst.Text end)
                    if okT and type(txt) == "string" then
                        local name = txt:match("^%s*Defeat%s+(.+)$")
                            or txt:match("^%s*Eliminate%s+(.+)$")
                            or txt:match("^%s*Hunt%s+(.+)$")
                        if name then
                            name = name:gsub("%s+$", "")
                            name = name:gsub("^%s+", "")
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

    function S.readCrowQuests()
        local cc = getComponentsHolder()
        if not cc then return {} end
        return readQuestsFromTree(cc)
    end

    --============================================================
    -- QUEST CARDS · findQuestCards
    -- Finds clickable elements inside the crow panel that are not
    -- the Cancel button. These are the quest cards the player clicks
    -- to accept.
    --============================================================
    local function findAncestor(node, target, maxUp)
        local cur = node
        maxUp = maxUp or 12
        for _ = 1, maxUp do
            if not cur then return nil end
            if cur == target then return cur end
            cur = cur.Parent
        end
        return nil
    end

    local function collectClickables(root, exclude)
        local out = {}
        local seen = {}
        if not root then return out end

        local stack = { root }
        local iter = 0
        while #stack > 0 do
            local inst = table.remove(stack)
            if inst then
                if inst ~= exclude then
                    local isClickable = false
                    if inst:IsA("TextButton") or inst:IsA("ImageButton") then
                        isClickable = true
                    end
                    if isClickable then
                        local okV, vis = pcall(function() return inst.Visible end)
                        local okA, act = pcall(function() return inst.Active end)
                        if okV and vis and okA and act then
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

    function S.findQuestCards(cancelBtn)
        local cc = getComponentsHolder()
        if not cc then return {} end

        -- Find the panel root — the ancestor of cancelBtn that is
        -- still a descendant of ComponentsHolder, or cc itself.
        local panelRoot = cc
        if cancelBtn then
            local ok, ancestor = pcall(function()
                -- walk up from cancelBtn looking for a child of cc
                local cur = cancelBtn
                for _ = 1, 12 do
                    if not cur or cur.Parent == cc then return cur end
                    cur = cur.Parent
                end
                return cc
            end)
            if ok and ancestor then panelRoot = ancestor end
        end

        return collectClickables(panelRoot, cancelBtn)
    end

    --============================================================
    -- CAW SOUND · waitForCaw
    --============================================================
    local function isCawName(name)
        local l = string.lower(name or "")
        return string.find(l, "caw", 1, true) ~= nil
            or string.find(l, "crow", 1, true) ~= nil
            or string.find(l, "chaa", 1, true) ~= nil
            or string.find(l, "kasugai", 1, true) ~= nil
    end

    function S.waitForCaw(timeout)
        local deadline = U.clock() + (timeout or 3.0)

        -- Also check notification GUIs — the "Chaaaaaa" popup some games use
        local pg = getPlayerGui()

        while U.clock() < deadline do
            -- Check any currently-playing Sound named like caw
            local ok, found = pcall(function()
                local ss = game:GetService("SoundService")
                local sounds = ss:GetDescendants()
                for i = 1, #sounds do
                    local s = sounds[i]
                    if s:IsA("Sound") and s.IsPlaying and isCawName(s.Name) then
                        return true
                    end
                end
                return false
            end)
            if ok and found then return true end

            -- Check workspace sounds too (some games play from a part)
            local ok2, found2 = pcall(function()
                local ws = workspace:GetDescendants()
                for i = 1, #ws do
                    local s = ws[i]
                    if s:IsA("Sound") and s.IsPlaying and isCawName(s.Name) then
                        return true
                    end
                end
                return false
            end)
            if ok2 and found2 then return true end

            task.wait(0.15)
        end
        return false
    end

    --============================================================
    -- LEGACY · findCrowMenu
    -- The game has no accept button. Returns nil. Kept for
    -- backward compat with old callers.
    --============================================================
    function S.findCrowMenu()
        return nil
    end

    --============================================================
    -- ACTIVATE (dedup)
    --============================================================
    function S.activateCrowMenu(btn)
        if not btn or not btn.Parent then return false end
        local now = U.clock()
        if menuCache.btn == btn
           and now - menuCache.ts < Cfg.CrowMenuCooldown then
            return false
        end
        local ok = pcall(function() btn:Activate() end)
        if ok then
            menuCache.btn = btn
            menuCache.ts = now
        end
        return ok
    end

    --============================================================
    -- STATS
    --============================================================
    function S.stats()
        local now = U.clock()
        return {
            toolCached   = toolCache.inst ~= nil,
            modelCached  = modelCache.inst ~= nil,
            modelTag     = modelCache.tag,
            menuCooldown = menuCache.btn
                           and math.max(0, Cfg.CrowMenuCooldown - (now - menuCache.ts))
                           or 0,
            lastToolScan = now - lastScan.tool,
            lastModelScan = now - lastScan.model,
            lastMenuScan = now - lastScan.menu,
        }
    end

    --============================================================
    -- DEPRECATED STUBS
    --============================================================
    local warned = {}
    local function stubOnce(name)
        if warned[name] then return end
        warned[name] = true
        print("[Dingus][Scanners] " .. name .. " removed — no-op")
    end

    function S.findCawSound()
        stubOnce("findCawSound")
        return nil
    end

    function S.deepScan()
        stubOnce("deepScan")
        return {}
    end

    function S.dumpInventory()
        stubOnce("dumpInventory")
        return {}
    end

    print("[Dingus][scanners] v4 initialized")
end

return S
