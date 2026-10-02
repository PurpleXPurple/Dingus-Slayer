--[[
    Dingus-Slayer · chest.lua v3
    Chest + loot collection. Proven working 2026-10-03.
]]--

local Chest = {}

function Chest.init(Ctx)
    local U, F, S = Ctx.Util, Ctx.Cfg, Ctx.St

    F.ChestEnabled           = F.ChestEnabled           ~= false
    F.ChestOnKill            = F.ChestOnKill            ~= false
    F.ChestPassive           = F.ChestPassive           ~= false
    F.ChestPassiveInterval   = F.ChestPassiveInterval   or 12
    F.ChestRadius            = F.ChestRadius            or 50
    F.ChestMaxPasses         = F.ChestMaxPasses         or 6
    F.ChestPassDeadline      = F.ChestPassDeadline      or 12
    F.ChestScanDepth         = F.ChestScanDepth         or 8
    F.ChestPerTargetCooldown = F.ChestPerTargetCooldown or 45
    F.ChestApproachDist      = F.ChestApproachDist      or 3
    F.ChestKeyChar           = F.ChestKeyChar           or "T"
    F.ChestFallbackKeyChar   = F.ChestFallbackKeyChar   or "E"
    F.ChestVerbose           = F.ChestVerbose           or false

    F.ChestKeywords = F.ChestKeywords or {
        "chest", "cache", "crate", "lootbox",
        "common chest", "rare chest", "lost chest", "ice chest",
        "snow chest", "sealed chest", "demon chest",
        "ouwigahara chest", "world events chest",
    }
    F.ChestLootKeywords = F.ChestLootKeywords or {
        "coin", "wen", "yen", "pouch",
        "ore", "scrap", "ingot", "silk", "plating", "crystal",
        "thread", "weaver", "refinement",
        "elixir", "potion", "gourd",
        "lantern", "demonic lantern", "haori", "mask", "necklace",
        "earring", "ring", "relic", "orb", "scroll", "totem",
        "token", "reroll", "voucher",
        "drop", "loot", "pickup", "pick up", "item",
    }

    S.chestCollected     = S.chestCollected     or 0
    S.chestLootCollected = S.chestLootCollected or 0
    S.chestFailed        = S.chestFailed        or 0
    S.chestSkipped       = S.chestSkipped       or 0
    S.chestPasses        = S.chestPasses        or 0
    S.chestCooldowns     = S.chestCooldowns     or {}
    S.chestLastSweep     = 0
    S.chestLastPassive   = 0
    S.chestLastTargets   = {}
    S.chestLastScanTs    = 0
    S.chestRunning       = false
    S.chestLastFired     = 0
    S.chestTotalSweeps   = 0

    local function hasKw(str, list)
        if not str or not list then return false end
        local l = string.lower(str)
        for i = 1, #list do
            if string.find(l, list[i], 1, true) then return true end
        end
        return false
    end

    local function modelPos(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Attachment") and inst.Parent
           and inst.Parent:IsA("BasePart") then
            return inst.Parent.Position
        end
        if inst:IsA("Model") then
            if inst.PrimaryPart then return inst.PrimaryPart.Position end
            local any = inst:FindFirstChildWhichIsA("BasePart")
            if any then return any.Position end
        end
        if inst:IsA("ClickDetector") or inst:IsA("ProximityPrompt") then
            return modelPos(inst.Parent)
        end
        return nil
    end

    local function classify(name)
        if hasKw(name, F.ChestKeywords) then return "chest" end
        if hasKw(name, F.ChestLootKeywords) then return "loot" end
        return nil
    end

    local function cooling(inst)
        local exp = S.chestCooldowns[inst]
        if not exp then return false end
        if U.clock() >= exp then S.chestCooldowns[inst] = nil; return false end
        return true
    end

    function Chest.scan(radius)
        radius = radius or F.ChestRadius or 50
        local r = U.hrp()
        if not r then return {} end
        local mp = r.Position
        local maxSq = radius * radius
        local out, seen = {}, {}
        local stack = { { workspace, 0 } }
        local iter = 0
        local depthCap = F.ChestScanDepth or 8

        while #stack > 0 do
            local item = table.remove(stack)
            local inst, depth = item[1], item[2]
            if inst and depth <= depthCap then
                local kind, label = nil, nil
                if inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("MeshPart") then
                    kind = classify(inst.Name); label = inst.Name
                end
                if not kind and inst:IsA("ProximityPrompt") then
                    local nm = (inst.ObjectText or "") .. " "
                            .. (inst.ActionText or "") .. " "
                            .. (inst.Name or "")
                    kind = classify(nm); label = nm
                end
                if not kind and inst:IsA("ClickDetector") then
                    local nm = inst.Name
                    if inst.Parent then nm = nm .. " " .. inst.Parent.Name end
                    kind = classify(nm); label = nm
                end
                if kind and not seen[inst] then
                    local pos = modelPos(inst)
                    if pos then
                        local dx = mp.X - pos.X
                        local dy = mp.Y - pos.Y
                        local dz = mp.Z - pos.Z
                        local dSq = dx*dx + dy*dy + dz*dz
                        if dSq <= maxSq then
                            seen[inst] = true
                            table.insert(out, {
                                inst = inst, pos = pos,
                                d = math.sqrt(dSq),
                                kind = kind, name = label or inst.Name,
                            })
                        end
                    end
                end
                for _, c in ipairs(inst:GetChildren()) do
                    table.insert(stack, { c, depth + 1 })
                end
                iter = iter + 1
                if iter % 3000 == 0 then task.wait() end
            end
        end
        table.sort(out, function(a, b) return a.d < b.d end)
        S.chestLastTargets = out
        S.chestLastScanTs = U.clock()
        return out
    end

    function Chest.lastTargets() return S.chestLastTargets or {} end

    local function fireProx(p)
        if type(fireproximityprompt) == "function" then
            local ok = pcall(fireproximityprompt, p)
            if ok then return true end
        end
        return pcall(function()
            if p.InputHoldBegin then p:InputHoldBegin() end
            task.wait(p.HoldDuration or 0.1)
            if p.InputHoldEnd then p:InputHoldEnd() end
        end)
    end

    local function fireClick(d)
        if type(fireclickdetector) == "function" then
            return pcall(fireclickdetector, d)
        end
        return false
    end

    local function physicalKey()
        U.tap(F.ChestKeyChar or "T")
        task.wait(0.08)
        if F.ChestFallbackKeyChar and F.ChestFallbackKeyChar ~= F.ChestKeyChar then
            U.tap(F.ChestFallbackKeyChar)
            task.wait(0.08)
        end
        return true
    end

    local function moveTo(pos)
        local r = U.hrp()
        if not r or not pos then return end
        local dx = pos.X - r.Position.X
        local dz = pos.Z - r.Position.Z
        local flat = Vector3.new(dx, 0, dz)
        if flat.Magnitude < 0.5 then return end
        local margin = F.ChestApproachDist or 3
        local dest = r.Position + flat.Unit * math.max(0, flat.Magnitude - margin)
        dest = Vector3.new(dest.X, r.Position.Y, dest.Z)
        local ok, cf = pcall(function()
            return CFrame.new(dest, Vector3.new(pos.X, dest.Y, pos.Z))
        end)
        if ok and cf then pcall(function() r.CFrame = cf end) end
        task.wait(0.12)
    end

    local function interact(target)
        local inst = target.inst
        if not inst or not inst.Parent then return false end
        if inst:IsA("ProximityPrompt") then
            if fireProx(inst) then return true end
        elseif inst:IsA("ClickDetector") then
            if fireClick(inst) then return true end
        end
        local got = false
        for _, ch in ipairs(inst:GetDescendants()) do
            if not got then
                if ch:IsA("ProximityPrompt") then
                    if fireProx(ch) then got = true end
                elseif ch:IsA("ClickDetector") then
                    if fireClick(ch) then got = true end
                end
            end
        end
        if got then return true end
        return physicalKey()
    end

    function Chest.sweep(radius)
        radius = radius or F.ChestRadius or 50
        local targets = Chest.scan(radius)
        if #targets == 0 then S.chestLastFired = 0; return 0 end
        local fired = 0
        for i = 1, #targets do
            local t = targets[i]
            if t.inst and t.inst.Parent and not cooling(t.inst) then
                moveTo(t.pos)
                if interact(t) then
                    fired = fired + 1
                    if t.kind == "chest" then
                        S.chestCollected = S.chestCollected + 1
                        print(string.format("[Dingus][Chest] opened %s @%.0f",
                            (t.name or "?"):gsub("^%s+", ""), t.d))
                    else
                        S.chestLootCollected = S.chestLootCollected + 1
                    end
                else
                    S.chestFailed = S.chestFailed + 1
                    S.chestCooldowns[t.inst] = U.clock() + (F.ChestPerTargetCooldown or 45)
                end
                task.wait(0.08)
            elseif t.inst and cooling(t.inst) then
                S.chestSkipped = S.chestSkipped + 1
            end
        end
        S.chestLastFired = fired
        S.chestLastSweep = U.clock()
        S.chestTotalSweeps = S.chestTotalSweeps + 1
        return fired
    end

    function Chest.collectAll(radius, maxPasses, deadline)
        radius = radius or F.ChestRadius or 50
        maxPasses = maxPasses or F.ChestMaxPasses or 6
        deadline = deadline or F.ChestPassDeadline or 12
        if not F.ChestEnabled then return 0, 0 end
        if S.chestRunning then return 0, 0 end
        S.chestRunning = true
        local startT = U.clock()
        local total, empty, pass = 0, 0, 0
        while U.clock() < startT + deadline and pass < maxPasses and empty < 3 do
            pass = pass + 1
            local fired = Chest.sweep(radius)
            total = total + fired
            if fired == 0 then empty = empty + 1 else empty = 0 end
            task.wait(0.4)
        end
        S.chestPasses = (S.chestPasses or 0) + pass
        S.chestRunning = false
        return total, pass
    end

    function Chest.collectBossDrop()
        if not F.ChestEnabled or not F.ChestOnKill then return end
        print("[Dingus][Chest] boss drop — running cycle")
        local fired, pass = Chest.collectAll()
        print(string.format("[Dingus][Chest] done · fired=%d passes=%d", fired, pass))
    end

    function Chest.collectPassive()
        if not F.ChestEnabled or not F.ChestPassive then return end
        local t = U.clock()
        if t - S.chestLastPassive < (F.ChestPassiveInterval or 12) then return end
        S.chestLastPassive = t
        local fired = Chest.sweep(F.ChestRadius or 50)
        if fired > 0 then
            print(string.format("[Dingus][Chest] passive · %d", fired))
        end
    end

    function Chest.setEnabled(v) F.ChestEnabled = not not v end
    function Chest.resetCooldowns() S.chestCooldowns = {} end

    function Chest.dump()
        local list = Chest.scan(F.ChestRadius or 50)
        print(string.format("[Dingus][Chest] %d targets within %d studs:",
            #list, F.ChestRadius or 50))
        for i = 1, math.min(#list, 20) do
            local t = list[i]
            print(string.format("  [%s] %s @%.0f",
                t.kind, (t.name or ""):gsub("^%s+", ""), t.d))
        end
        return list
    end

    function Chest.stats()
        local cd = 0
        for _ in pairs(S.chestCooldowns or {}) do cd = cd + 1 end
        return {
            enabled = F.ChestEnabled,
            onKill = F.ChestOnKill,
            passive = F.ChestPassive,
            radius = F.ChestRadius or 50,
            depth = F.ChestScanDepth or 8,
            passes = S.chestPasses or 0,
            totalSweeps = S.chestTotalSweeps or 0,
            collected = S.chestCollected or 0,
            lootCollected = S.chestLootCollected or 0,
            failed = S.chestFailed or 0,
            skipped = S.chestSkipped or 0,
            lastFired = S.chestLastFired or 0,
            lastScanAge = U.clock() - (S.chestLastScanTs or 0),
            lastTargets = #(S.chestLastTargets or {}),
            cooldowns = cd,
            running = S.chestRunning or false,
        }
    end

    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(1.5)
            Chest.resetCooldowns()
        end)
    end

    print("[Dingus][chest] v3 initialized")
end

return Chest
