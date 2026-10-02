-- Dingus-Slayer · scanners.lua v6
-- General-purpose scan toolkit + crow helpers.
-- One entry point: S.scan(spec) → matches. Presets wrap it.

local S = {}

function S.init(Ctx)
    local U, F, Sx, L = Ctx.Util, Ctx.Cfg, Ctx.St, Ctx.Lists
    local RS = U.RS
    local CS = nil
    pcall(function() CS = game:GetService("CollectionService") end)

    --============================================================
    -- GENERIC SCAN ENGINE
    --============================================================
    -- spec = {
    --   container  = instance (default: workspace)
    --   maxDepth   = number   (default: 8)
    --   class      = string | {"Model", "Part"}      -- exact ClassName
    --   child      = string | {"Humanoid"}           -- required direct child
    --   notChild   = string | {"Humanoid"}           -- forbidden direct child
    --   tag        = string | {"LootDrop", "Chest"}  -- CollectionService tag
    --   attr       = { name="ChestState" [, value="Opened"] }
    --   name       = string | {"a","b"} | fn(inst) → bool
    --   filter     = fn(inst, depth, parent) → bool (final gate)
    --   radius     = number   (optional; uses nearest position)
    --   center     = Vector3  (default: player HRP)
    --   maxResults = number
    --   timeBudget = seconds  (default: 2.0)
    --   yieldEvery = iterations (default: adaptive)
    --   skip       = instance | {instances}  -- never yield these
    --   blacklist  = {instance, ...}         -- pre-seen (internal)
    -- }
    -- Returns array of { inst, pos, dist, depth, path, parent }

    local function matchName(inst, spec, name)
        if not spec.name then return true end
        local n = string.lower(inst.Name or "")
        if type(spec.name) == "function" then return spec.name(inst) end
        if type(spec.name) == "string" then
            return n:find(string.lower(spec.name), 1, true) ~= nil
        end
        if type(spec.name) == "table" then
            for _, v in ipairs(spec.name) do
                if n:find(string.lower(v), 1, true) then return true end
            end
            return false
        end
        return true
    end

    local function matchClass(inst, spec)
        if not spec.class then return true end
        local cls = inst.ClassName
        if type(spec.class) == "string" then return cls == spec.class end
        for _, c in ipairs(spec.class) do
            if cls == c then return true end
        end
        return false
    end

    local function matchChild(inst, spec)
        if spec.child then
            local list = type(spec.child) == "table" and spec.child or { spec.child }
            for _, c in ipairs(list) do
                if not inst:FindFirstChild(c) then return false end
            end
        end
        if spec.notChild then
            local list = type(spec.notChild) == "table" and spec.notChild or { spec.notChild }
            for _, c in ipairs(list) do
                if inst:FindFirstChild(c) then return false end
            end
        end
        return true
    end

    local function matchTag(inst, spec)
        if not spec.tag then return true end
        if not CS then return false end
        local list = type(spec.tag) == "table" and spec.tag or { spec.tag }
        for _, t in ipairs(list) do
            if CS:HasTag(inst, t) then return true end
        end
        return false
    end

    local function matchAttr(inst, spec)
        if not spec.attr then return true end
        local a = inst:GetAttribute(spec.attr.name)
        if a == nil then return false end
        if spec.attr.value ~= nil then return a == spec.attr.value end
        return true
    end

    local function instPosition(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Attachment") then
            return inst.WorldPosition
        end
        if inst:IsA("Model") then
            if inst.PrimaryPart then return inst.PrimaryPart.Position end
            local h = inst:FindFirstChild("HumanoidRootPart")
            if h then return h.Position end
            local p = inst:FindFirstChildWhichIsA("BasePart", true)
            if p then return p.Position end
            return inst:GetPivot().Position
        end
        if inst:IsA("ProximityPrompt") then
            local p = inst.Parent
            if p then return instPosition(p) end
        end
        if inst:IsA("ClickDetector") then
            local p = inst.Parent
            if p then return instPosition(p) end
        end
        if inst.Parent then
            return instPosition(inst.Parent)
        end
        return nil
    end

    S.instPosition = instPosition

    local function withinRadius(inst, spec, centerPos)
        if not spec.radius then return true end
        if not centerPos then return true end
        local p = instPosition(inst)
        if not p then return false end
        return (p - centerPos).Magnitude <= spec.radius
    end

    local function buildPath(inst, root)
        local parts = {}
        local cur = inst
        local guard = 0
        while cur and cur ~= root and guard < 20 do
            table.insert(parts, 1, cur.Name)
            cur = cur.Parent
            guard = guard + 1
        end
        return table.concat(parts, "/")
    end

    local function skipSet(spec)
        if not spec.skip then return nil end
        local s = {}
        if type(spec.skip) == "table" then
            for i = 1, #spec.skip do s[spec.skip[i]] = true end
        else
            s[spec.skip] = true
        end
        return s
    end

    function S.scan(spec)
        spec = spec or {}
        local container = spec.container or workspace
        local maxDepth = spec.maxDepth or 8
        local yieldEvery = spec.yieldEvery or (U.IsMobile and 400 or 2000)
        local timeBudget = spec.timeBudget or 2.0
        local maxResults = spec.maxResults or 500

        local myHrp = U.hrp()
        local centerPos = spec.center or (myHrp and myHrp.Position) or nil
        local t0 = os.clock()
        local skipped = skipSet(spec)
        local seen = {}
        local matches = {}
        local iter = 0

        -- Fast path: tag-only query
        if spec.tag and not spec.container then
            if CS then
                local list = type(spec.tag) == "table" and spec.tag or { spec.tag }
                for _, tag in ipairs(list) do
                    for _, inst in ipairs(CS:GetTagged(tag)) do
                        if not seen[inst]
                            and matchClass(inst, spec)
                            and matchChild(inst, spec)
                            and matchName(inst, spec, spec.name)
                            and matchAttr(inst, spec)
                            and not (skipped and skipped[inst])
                            and (not spec.filter or spec.filter(inst, 0, inst.Parent))
                            and withinRadius(inst, spec, centerPos) then
                            seen[inst] = true
                            local pos = instPosition(inst)
                            local dist = pos and centerPos and (pos - centerPos).Magnitude or 0
                            table.insert(matches, {
                                inst = inst, pos = pos, dist = dist,
                                depth = 0, path = inst.Name, parent = inst.Parent,
                            })
                        end
                    end
                end
            end
            if maxResults and #matches > maxResults then
                table.sort(matches, function(a, b) return a.dist < b.dist end)
                while #matches > maxResults do table.remove(matches) end
            end
            return matches
        end

        -- BFS walk
        local queue = { { container, 0 } }
        local head = 1
        while head <= #queue do
            if (os.clock() - t0) > timeBudget then break end
            if #matches >= maxResults then break end

            local item = queue[head]; head = head + 1
            local inst, depth = item[1], item[2]
            if inst and depth <= maxDepth and not seen[inst] then
                seen[inst] = true
                if inst ~= container
                   and not (skipped and skipped[inst])
                   and matchClass(inst, spec)
                   and matchChild(inst, spec)
                   and matchTag(inst, spec)
                   and matchAttr(inst, spec)
                   and matchName(inst, spec, spec.name)
                   and (not spec.filter or spec.filter(inst, depth, inst.Parent))
                   and withinRadius(inst, spec, centerPos) then
                    local pos = instPosition(inst)
                    local dist = pos and centerPos and (pos - centerPos).Magnitude or 0
                    table.insert(matches, {
                        inst = inst, pos = pos, dist = dist,
                        depth = depth, path = buildPath(inst, container),
                        parent = inst.Parent,
                    })
                end
                if depth < maxDepth then
                    local ok, kids = pcall(inst.GetChildren, inst)
                    if ok and kids then
                        for i = 1, #kids do
                            queue[#queue + 1] = { kids[i], depth + 1 }
                        end
                    end
                end
                iter = iter + 1
                if iter % yieldEvery == 0 then task.wait() end
            end
        end

        table.sort(matches, function(a, b) return a.dist < b.dist end)
        return matches
    end

    --============================================================
    -- PRESET SCANNERS
    --============================================================

    -- Humanoid-bearing models (any container)
    local function humanoidFilter(inst, hum)
        if not hum or hum.Health <= 0 then return false end
        if U.isPlayer(inst) then return false end
        if inst == U.Lp.Character then return false end
        return true
    end

    function S.humanoids(radius)
        local out = {}
        local matches = S.scan({
            container = workspace,
            maxDepth = 8,
            class = "Model",
            child = "Humanoid",
            radius = radius,
        })
        for _, m in ipairs(matches) do
            local hum = m.inst:FindFirstChildOfClass("Humanoid")
            if humanoidFilter(m.inst, hum) then
                m.humanoid = hum
                m.root = m.inst:FindFirstChild("HumanoidRootPart")
                    or m.inst:FindFirstChild("Torso")
                m.health = hum.Health
                m.maxHealth = hum.MaxHealth
                table.insert(out, m)
            end
        end
        return out
    end

    function S.bosses(radius)
        local out = {}
        for _, m in ipairs(S.humanoids(radius)) do
            if L.isBoss(m.inst.Name) then table.insert(out, m) end
        end
        return out
    end

    function S.mobs(radius)
        local out = {}
        for _, m in ipairs(S.humanoids(radius)) do
            if not L.isBoss(m.inst.Name)
               and not L.isCrow(m.inst.Name)
               and not m.inst:FindFirstAncestor("StationaryNpcs") then
                table.insert(out, m)
            end
        end
        return out
    end

    function S.npcs(radius)
        local out = {}
        for _, m in ipairs(S.humanoids(radius)) do
            if m.inst:FindFirstAncestor("StationaryNpcs")
               or m.inst:FindFirstAncestor("NPCs") then
                table.insert(out, m)
            end
        end
        return out
    end

    function S.players(radius)
        local out = {}
        local plr = U.Plr
        if not plr then return out end
        local myHrp = U.hrp()
        local myPos = myHrp and myHrp.Position or nil
        for _, p in ipairs(plr:GetPlayers()) do
            if p ~= U.Lp and p.Character then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local d = myPos and (hrp.Position - myPos).Magnitude or 0
                    if not radius or d <= radius then
                        table.insert(out, {
                            inst = p.Character, pos = hrp.Position,
                            dist = d, player = p,
                            humanoid = p.Character:FindFirstChildOfClass("Humanoid"),
                            root = hrp, name = p.Name,
                        })
                    end
                end
            end
        end
        table.sort(out, function(a, b) return a.dist < b.dist end)
        return out
    end

    function S.corpses(radius)
        local out = {}
        for _, m in ipairs(S.scan({
            container = workspace,
            maxDepth = 8,
            class = "Model",
            child = "Humanoid",
            radius = radius,
            filter = function(inst, depth)
                local hum = inst:FindFirstChildOfClass("Humanoid")
                return hum and hum.Health <= 0
            end,
        })) do
            table.insert(out, m)
        end
        return out
    end

    -- Prompts (any prompt in radius)
    function S.prompts(radius, textMatch)
        local spec = {
            container = workspace,
            maxDepth = 10,
            class = "ProximityPrompt",
            radius = radius or 50,
        }
        if textMatch then
            spec.filter = function(inst)
                local a = string.lower(inst.ActionText or "")
                local o = string.lower(inst.ObjectText or "")
                return a:find(textMatch, 1, true) or o:find(textMatch, 1, true)
            end
        end
        return S.scan(spec)
    end

    function S.clickDetectors(radius)
        return S.scan({
            container = workspace,
            maxDepth = 10,
            class = "ClickDetector",
            radius = radius or 50,
        })
    end

    -- Chests (folder or tag or attribute)
    local function isChestInst(inst)
        if not inst then return false end
        local state = inst:GetAttribute("ChestState")
        local open  = inst:GetAttribute("IsOpen")
        local cid   = inst:GetAttribute("ChestId") or inst:GetAttribute("ChestGuid")
        if state == "Opened" or state == "Despawned" or open == true then
            return false
        end
        return state ~= nil or open ~= nil or cid ~= nil
    end

    function S.chests(radius)
        local out = {}
        local seen = {}
        -- By folder
        local folder = workspace:FindFirstChild("Chests")
        if folder then
            for _, m in ipairs(S.scan({
                container = folder,
                maxDepth = 10,
                class = "ProximityPrompt",
                radius = radius,
                filter = function(prompt)
                    local model = prompt.Parent
                    local d = 0
                    while model and model ~= folder and d < 10 do
                        if isChestInst(model) then return true end
                        model = model.Parent
                        d = d + 1
                    end
                    return false
                end,
            })) do
                if not seen[m.inst] then
                    seen[m.inst] = true
                    table.insert(out, m)
                end
            end
        end
        -- By attribute
        for _, m in ipairs(S.scan({
            container = workspace,
            maxDepth = 8,
            attr = { name = "ChestState" },
            radius = radius,
            filter = function(inst) return isChestInst(inst) end,
        })) do
            if not seen[m.inst] then
                seen[m.inst] = true
                table.insert(out, m)
            end
        end
        -- By tag
        if CS then
            for _, m in ipairs(S.scan({
                tag = "Chest",
                radius = radius,
                filter = function(inst) return isChestInst(inst) end,
            })) do
                if not seen[m.inst] then
                    seen[m.inst] = true
                    table.insert(out, m)
                end
            end
        end
        table.sort(out, function(a, b) return a.dist < b.dist end)
        return out
    end

    -- Loot drops
    local function isLootInst(inst)
        if inst:GetAttribute("DropClaimedBy") ~= nil then return false end
        local itemId = inst:GetAttribute("DropItemId")
        local uid = U.Lp.UserId
        local owner = inst:GetAttribute("DropOwnerUserId")
        local reserved = inst:GetAttribute("DropReservedFor")
        if owner ~= nil and owner ~= uid and owner ~= 0 then return false end
        if reserved then
            local s = "," .. tostring(uid) .. ","
            if not string.find(tostring(reserved), s, 1, true) then return false end
        end
        return itemId ~= nil or (CS and CS:HasTag(inst, "LootDrop"))
    end

    function S.loot(radius)
        local out = {}
        local seen = {}
        local folder = workspace:FindFirstChild("LootDrops")
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if isLootInst(child) then
                    local pos = instPosition(child)
                    local myHrp = U.hrp()
                    local dist = pos and myHrp
                        and (pos - myHrp.Position).Magnitude or 0
                    if not radius or dist <= radius then
                        seen[child] = true
                        table.insert(out, {
                            inst = child, pos = pos, dist = dist,
                            name = child.Name, parent = folder,
                        })
                    end
                end
            end
        end
        if CS then
            for _, inst in ipairs(CS:GetTagged("LootDrop")) do
                if not seen[inst] and isLootInst(inst) then
                    local pos = instPosition(inst)
                    local myHrp = U.hrp()
                    local dist = pos and myHrp
                        and (pos - myHrp.Position).Magnitude or 0
                    if not radius or dist <= radius then
                        seen[inst] = true
                        table.insert(out, {
                            inst = inst, pos = pos, dist = dist,
                            name = inst.Name, parent = inst.Parent,
                        })
                    end
                end
            end
        end
        table.sort(out, function(a, b) return a.dist < b.dist end)
        return out
    end

    function S.souls(radius)
        local out = {}
        local seen = {}
        local function tryAdd(inst)
            if seen[inst] then return end
            if inst:FindFirstChildOfClass("Humanoid") then return end
            local n = string.lower(inst.Name or "")
            local isSoul = n:find("soul", 1, true) ~= nil
                or inst:GetAttribute("IsSoul") ~= nil
                or inst:GetAttribute("SoulType") ~= nil
            if not isSoul then return end
            local pos = instPosition(inst)
            local myHrp = U.hrp()
            local dist = pos and myHrp and (pos - myHrp.Position).Magnitude or 0
            if radius and dist > radius then return end
            seen[inst] = true
            table.insert(out, {
                inst = inst, pos = pos, dist = dist,
                name = inst.Name, parent = inst.Parent,
            })
        end
        for _, child in ipairs(workspace:GetChildren()) do tryAdd(child) end
        local debree = workspace:FindFirstChild("Debree")
        if debree then
            for _, child in ipairs(debree:GetChildren()) do tryAdd(child) end
        end
        local ld = workspace:FindFirstChild("LootDrops")
        if ld then
            for _, child in ipairs(ld:GetChildren()) do tryAdd(child) end
        end
        if CS then
            for _, tag in ipairs({ "Soul", "Souls", "DemonSoul" }) do
                for _, inst in ipairs(CS:GetTagged(tag)) do tryAdd(inst) end
            end
        end
        table.sort(out, function(a, b) return a.dist < b.dist end)
        return out
    end

    function S.tagged(tag, radius)
        return S.scan({ tag = tag, radius = radius })
    end

    function S.withAttribute(name, value, radius)
        local spec = { container = workspace, maxDepth = 8, radius = radius }
        if value ~= nil then
            spec.attr = { name = name, value = value }
        else
            spec.attr = { name = name }
        end
        return S.scan(spec)
    end

    function S.named(pattern, radius)
        return S.scan({
            container = workspace,
            maxDepth = 8,
            name = pattern,
            radius = radius,
        })
    end

    function S.byPath(path)
        local cur = workspace
        local root = "workspace"
        if type(path) == "string" then
            local parts = {}
            for p in path:gmatch("[^%.]+") do table.insert(parts, p) end
            if parts[1] == "RS" or parts[1] == "ReplicatedStorage" then
                cur = RS; root = "RS"
            end
            local startIdx = (parts[1] == "workspace" or parts[1] == "RS"
                or parts[1] == "ReplicatedStorage") and 2 or 1
            for i = startIdx, #parts do
                cur = cur and cur:FindFirstChild(parts[i])
                if not cur then return nil end
            end
        elseif typeof(path) == "Instance" then
            cur = path
        end
        return cur
    end

    function S.remotes(namePattern)
        local out = {}
        local function scanCont(container)
            if not container then return end
            for _, child in ipairs(container:GetDescendants()) do
                if child:IsA("RemoteEvent") or child:IsA("RemoteFunction")
                   or child:IsA("BindableEvent") or child:IsA("UnreliableRemoteEvent") then
                    if not namePattern
                       or child.Name:lower():find(string.lower(namePattern), 1, true) then
                        table.insert(out, {
                            inst = child, name = child.Name,
                            class = child.ClassName,
                            parent = child.Parent,
                        })
                    end
                end
            end
        end
        scanCont(RS)
        return out
    end

    --============================================================
    -- CONVENIENCE
    --============================================================
    function S.nearest(spec)
        local m = S.scan(spec)
        return m[1]
    end

    function S.count(spec)
        return #S.scan(spec)
    end

    function S.dump(spec, label)
        local m = S.scan(spec)
        print(string.format("[Dingus][Scan] %s · %d matches",
            label or "dump", #m))
        for i = 1, math.min(#m, 20) do
            local e = m[i]
            print(string.format("  [%d] %s · %s @%.1f",
                i, e.inst.ClassName, e.path or e.inst.Name, e.dist or 0))
        end
        if #m > 20 then print(string.format("  ... +%d more", #m - 20)) end
        return m
    end

    function S.stats()
        return {
            platform = U.Platform,
            collectionService = CS ~= nil,
            hasTag = CS ~= nil,
        }
    end

    --============================================================
    -- CROW HELPERS (namespace, kept for callers)
    --============================================================
    S.crow = {}

    local function getComponentsHolder()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        return pg and pg:FindFirstChild("ComponentsHolder") or nil
    end

    local function isCrowish(name)
        if not name then return false end
        local l = string.lower(name)
        return l == "crow" or l:find("crow", 1, true)
            or l:find("kasugai", 1, true)
    end

    function S.crow.tool()
        local c = U.Lp.Character
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") and isCrowish(t.Name) then return t end
            end
        end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and isCrowish(t.Name) then return t end
            end
        end
        return nil
    end

    function S.crow.cancelButton()
        local cc = getComponentsHolder()
        if not cc then return nil end
        local list = S.scan({
            container = cc,
            maxDepth = 6,
            class = "TextButton",
            filter = function(inst)
                local ok, vis = pcall(function() return inst.Visible end)
                if not ok or not vis then return false end
                local ok2, txt = pcall(function() return inst.Text end)
                if not ok2 or type(txt) ~= "string" then return false end
                local l = string.lower(txt):gsub("^%s+", ""):gsub("%s+$", "")
                return l == "cancel" or l == "close"
            end,
        })
        return list[1] and list[1].inst or nil
    end

    function S.crow.quests()
        local cc = getComponentsHolder()
        if not cc then return {} end
        local found, seen = {}, {}
        local list = S.scan({
            container = cc,
            maxDepth = 6,
            class = "TextLabel",
        })
        for _, m in ipairs(list) do
            local ok, txt = pcall(function() return m.inst.Text end)
            if ok and type(txt) == "string" then
                local name = txt:match("^%s*Defeat%s+(.+)$")
                    or txt:match("^%s*Eliminate%s+(.+)$")
                    or txt:match("^%s*Hunt%s+(.+)$")
                if name then
                    name = name:gsub("%s+$", ""):gsub("^%s+", "")
                    if #name > 0 and #name < 40 and not seen[name] then
                        seen[name] = true
                        table.insert(found, name)
                    end
                end
            end
        end
        return found
    end

    --============================================================
    -- BOOT
    --============================================================
    print(string.format("[Dingus][scanners] v6 · %s · CS=%s",
        U.Platform, tostring(CS ~= nil)))
end

return S
