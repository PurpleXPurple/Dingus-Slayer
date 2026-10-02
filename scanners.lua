--[[
    Dingus-Slayer · scanners.lua v3
    Cached, rate-limited, early-exit crow scanners.

    Changes vs v2:
      - deleted: findCawSound, deepScan, dumpInventory (zero callers)
        kept as no-op stubs so any hidden caller doesn't nil-crash
      - findCrowTool: no ReplicatedStorage fallback; caches live Tool;
        iterates only Character children + Backpack
      - findCrowModel: single return value; caches live model;
        squared-distance check (no sqrt); R6 note
      - findCrowMenu: early-exit walk (depth 5, not 10); exact-label
        match instead of substring; TextButton-only (no ImageButton.Text
        dereference); dedup activation via activateCrowMenu
      - new: S.activateCrowMenu(btn) — dedup-aware activation
      - new: S.stats() — cache + cooldown introspection
      - config: CrowAcceptLabels, CrowMenuCooldown, CrowScanMinGap

    What this file is NOT: a "bypass". Tree walks are still tree walks.
    If a game has client-side anti-cheat counting GetChildren call rate,
    these scanners are still visible. Caching just lowers the count.
]]--

local S = {}

function S.init(Ctx)
    local U   = Ctx.Util
    local Cfg = Ctx.Cfg
    local St  = Ctx.St

    --================================================================
    -- CONFIG DEFAULTS
    --================================================================
    -- Exact-match labels (lowercased, trimmed) that count as an
    -- "accept" button. Anything not in this list is ignored.
    Cfg.CrowAcceptLabels = Cfg.CrowAcceptLabels or {
        "accept", "accept quest", "take", "take quest",
        "yes", "confirm", "eliminate", "hunt", "begin", "start",
    }
    -- Minimum seconds between two activations of the same button.
    Cfg.CrowMenuCooldown = Cfg.CrowMenuCooldown or 30
    -- Minimum seconds between two scans of the same type.
    -- Callers with tight loops (say 0.05s) hit this; the crow
    -- scheduler at 1.5s cadence does not.
    Cfg.CrowScanMinGap = Cfg.CrowScanMinGap or 0.3
    -- Cache validity window for the crow model. Tool has no TTL
    -- because instance liveness is the correct validity signal.
    Cfg.CrowModelTTL = Cfg.CrowModelTTL or 2.0

    --================================================================
    -- STATE
    --================================================================
    local toolCache  = { inst = nil }
    local modelCache = { inst = nil, tag = nil, ts = 0 }
    local menuCache  = { btn = nil, ts = 0 }
    local lastScan   = { tool = 0, model = 0, menu = 0 }

    --================================================================
    -- LOCAL WALKER (early-exit)
    -- U.walkTree in utils.lua does not support early exit; a walker
    -- that keeps popping after the target is found wastes CPU.
    -- predicate(inst, depth) -> (hit:boolean, extra:any?)
    --================================================================
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

    --================================================================
    -- CROW TOOL
    -- Character children + Backpack only. No ReplicatedStorage
    -- fallback: if it isn't in the character or Backpack, the game
    -- doesn't intend you to equip it directly.
    --================================================================
    local function toolIsLive(t)
        if not t or not t.Parent then return false end
        local c = U.Lp.Character
        if c and t.Parent == c then return true end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp and t.Parent == bp then return true end
        return false
    end

    function S.findCrowTool()
        -- Cache hit path. Live tool wins over any time gate.
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

    --================================================================
    -- CROW MODEL
    -- Single return value. Callers (main.lua crowCycle) treat the
    -- result as truthy/nil, so the second "tag" return was unused
    -- and confusing. Attachment vs Model is recorded in stats.
    --
    -- R6 characters have no UpperTorso; the attachment branch is
    -- R15-only. Nearby-model branch covers both rigs.
    --================================================================
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
                        -- 50^2 = 2500. Squared-distance avoids sqrt.
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

    --================================================================
    -- CROW MENU
    -- Exact-label match. No "ok" / "yes" substring matching (those
    -- matched "book", "eyes", "took", etc.). No ImageButton.Text
    -- dereference (raises on some engine versions).
    -- Depth 5, not 10. Early exit on first match.
    --================================================================
    local function normalize(s)
        if type(s) ~= "string" then return "" end
        s = string.lower(s)
        s = s:gsub("^%s+", "")
        s = s:gsub("%s+$", "")
        return s
    end

    local function isAcceptButton(inst)
        if not inst:IsA("TextButton") then return false end
        local okV, vis = pcall(function() return inst.Visible end)
        if not okV or not vis then return false end
        local okT, rawText = pcall(function() return inst.Text end)
        if not okT then return false end
        local t = normalize(rawText)
        if #t == 0 or #t > 24 then return false end
        for i = 1, #Cfg.CrowAcceptLabels do
            if t == Cfg.CrowAcceptLabels[i] then return true end
        end
        return false
    end

    function S.findCrowMenu()
        local now = U.clock()
        if now - lastScan.menu < Cfg.CrowScanMinGap then return nil end
        lastScan.menu = now

        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        local cc = pg:FindFirstChild("ComponentsHolder")
        if not cc then return nil end

        return walkUntil(cc, 5, isAcceptButton)
    end

    --================================================================
    -- ACTIVATE (dedup)
    -- Replaces direct menu:Activate() in callers. Same button cannot
    -- be activated twice within Cfg.CrowMenuCooldown seconds.
    -- Different buttons (new menu instance) fire immediately.
    --================================================================
    function S.activateCrowMenu(btn)
        if not btn then return false end
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

    --================================================================
    -- STATS (for GUI display or debugging)
    --================================================================
    function S.stats()
        local now = U.clock()
        return {
            toolCached      = toolCache.inst ~= nil,
            modelCached     = modelCache.inst ~= nil,
            modelTag        = modelCache.tag,
            menuCooldown    = menuCache.btn
                              and math.max(0, Cfg.CrowMenuCooldown - (now - menuCache.ts))
                              or 0,
            lastToolScan    = now - lastScan.tool,
            lastModelScan   = now - lastScan.model,
            lastMenuScan    = now - lastScan.menu,
        }
    end

    --================================================================
    -- DEPRECATED STUBS
    -- Removed in v3. Kept so any hidden caller gets a warning instead
    -- of a nil-call. Return types match the originals: findCawSound
    -- returned a Sound or nil; deepScan/dumpInventory returned tables.
    --================================================================
    local warned = {}
    local function stubOnce(name)
        if warned[name] then return end
        warned[name] = true
        print("[Dingus][Scanners] " .. name .. " removed in v3 — no-op")
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

    print("[Dingus][scanners] v3 initialized")
end

return S
