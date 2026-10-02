--[[
    Dingus-Slayer · chest.lua v4
    Whitelist-only. Honeypot-safe. 3-stud reach. Rate-limited.
]]--

local Chest = {}

function Chest.init(Ctx)
    local U, F, S = Ctx.Util, Ctx.Cfg, Ctx.St

    F.ChestEnabled           = F.ChestEnabled           ~= false
    F.ChestOnKill            = F.ChestOnKill            ~= false
    F.ChestPassive           = F.ChestPassive           ~= false
    F.ChestPassiveInterval   = F.ChestPassiveInterval   or 20
    F.ChestRadius            = 12
    F.ChestMaxPasses         = F.ChestMaxPasses         or 3
    F.ChestPassDeadline      = F.ChestPassDeadline      or 6
    F.ChestPerTargetCooldown = F.ChestPerTargetCooldown or 60
    F.ChestReachDist         = 4
    F.ChestMinInteractGap    = 2.0
    F.ChestVerbose           = F.ChestVerbose           or false
    F.ChestRequireVisible    = true

    -- EXACT names only. No substrings. No keyword matching.
    -- Add new names as you personally verify them in-game.
    F.ChestWhitelist = {
        "World Events Chest",
        "Common Chest",
        "Rare Chest",
        "Lost Chest",
        "Ice Chest",
        "Snow Chest",
        "Sealed Chest",
        "Demon Chest",
        "Ouwigahara Chest",
        "Gold Coin",
        "Silver Coin",
        "Coin",
        "Coin Pouch",
        "Large Wen Pouch",
        "Metal Scraps",
        "Refinement Ore",
        "Mythic Refinement Ore",
        "Silk Thread",
        "Crude Iron Ingot",
        "Demon Horn",
        "Health Elixir",
        "Health Regen Elixir",
        "Stamina Regen Elixir",
        "Underwater Breathing Potion",
        "Demonic Lantern",
        "Stylish Haori",
        "Lost Mask",
    }

    -- Honeypot signatures. Any name containing these is rejected
    -- regardless of whitelist. These are decoy words the game uses.
    F.ChestRejectSignatures = {
        "bookgrimore", "bookgrimoire", "grimore", "grimoire",
        "/", "\\",   -- asset paths, not world items
    }

    S.chestCollected     = S.chestCollected     or 0
    S.chestLootCollected = S.chestLootCollected or 0
    S.chestFailed        = S.chestFailed        or 0
    S.chestSkipped       = S.chestSkipped       or 0
    S.chestCooldowns     = S.chestCooldowns     or {}
    S.chestLastInteract  = S.chestLastInteract  or 0
    S.chestLastTargets   = {}
    S.chestLastScanTs    = 0
    S.chestRunning       = false

    local function rejectedName(name)
        if not name then return true end
        local l = string.lower(name)
        for _, sig in ipairs(F.ChestRejectSignatures) do
            if string.find(l, sig, 1, true) then return true end
        end
        return false
    end

    local function isWhitelisted(name)
        if not name or rejectedName(name) then return false end
        for i = 1, #F.ChestWhitelist do
            if name == F.ChestWhitelist[i] then return true end
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

    -- A real chest's prompt checks: enabled, has range, visible, parent
    -- isn't a player-owned thing.
    local function promptValid(p)
        if not p or not p.Parent then return false end
        if p.Enabled == false then return false end
        local mad = p.MaxActivationDistance or 0
        if type(mad) ~= "number" or mad <= 0 then return false end
        if F.ChestRequireVisible then
            if p.Visible == false then return false end
        end
        -- Reject if any ancestor is a Player character (a decoy near a
        -- player is always a trap).
        local par = p.Parent
        for _ = 1, 6 do
            if not par then break end
            if par:IsA("Model") and par:FindFirstChildOfClass("Humanoid") then
                return false
            end
            par = par.Parent
        end
        return true
    end

    local function cooling(inst)
        local exp = S.chestCooldowns[inst]
        if not exp then return false end
        if U.clock() >= exp then S.chestCooldowns[inst] = nil; return false end
        return true
    end

    --============================================================
    -- SCAN · whitelist only
    --============================================================
    function Chest.scan(radius)
        radius = radius or F.ChestRadius or 12
        local r = U.hrp(); if not r then return {} end
        local mp = r.Position
        local maxSq = radius * radius
        local out, seen = {}, {}
        local iter = 0

        -- Only walk the immediate vicinity. GetPartBoundsInRadius is
        -- cheap and never descends into asset trees.
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { U.Lp.Character }
        params.MaxParts = 60

        local ok, parts = pcall(function()
            return workspace:GetPartBoundsInRadius(mp, radius, params)
        end)

        if ok and parts then
            for i = 1, #parts do
                local part = parts[i]
                if part and not seen[part] then
                    -- check part itself
                    if isWhitelisted(part.Name) then
                        seen[part] = true
                        table.insert(out, {
                            inst = part, pos = part.Position,
                            d = (part.Position - mp).Magnitude,
                            kind = "part",
                            name = part.Name,
                        })
                    end
                    -- check for prompt/click on or in the part
                    for _, ch in ipairs(part:GetChildren()) do
                        if not seen[ch] then
                            if ch:IsA("ProximityPrompt")
                               and isWhitelisted(part.Name)
                               and promptValid(ch) then
                                seen[ch] = true
                                table.insert(out, {
                                    inst = ch, pos = part.Position,
                                    d = (part.Position - mp).Magnitude,
                                    kind = "prompt",
                                    name = part.Name,
                                    prompt = ch,
                                })
                            elseif ch:IsA("ClickDetector")
                               and isWhitelisted(part.Name) then
                                seen[ch] = true
                                table.insert(out, {
                                    inst = ch, pos = part.Position,
                                    d = (part.Position - mp).Magnitude,
                                    kind = "click",
                                    name = part.Name,
                                    click = ch,
                                })
                            end
                        end
                    end
                end
                iter = iter + 1
                if iter % 40 == 0 then task.wait() end
            end
        end

        -- Also check the player's own immediate children for prompts
        -- (chest sometimes parents prompt directly to character)
        for _, ch in ipairs(workspace:GetChildren()) do
            if ch:IsA("Model") and not seen[ch] then
                local name = ch.Name
                if isWhitelisted(name) then
                    local pos = modelPos(ch)
                    if pos then
                        local d = (pos - mp).Magnitude
                        if d <= radius then
                            seen[ch] = true
                            table.insert(out, {
                                inst = ch, pos = pos, d = d,
                                kind = "model", name = name,
                            })
                        end
                    end
                end
            end
        end

        table.sort(out, function(a, b) return a.d < b.d end)
        S.chestLastTargets = out
        S.chestLastScanTs = U.clock()
        return out
    end

    function Chest.lastTargets() return S.chestLastTargets or {} end

    --============================================================
    -- INTERACT · 1 per ChestMinInteractGap seconds
    --============================================================
    local function tryFire(target)
        local now = U.clock()
        if now - S.chestLastInteract < (F.ChestMinInteractGap or 2.0) then
            return false
        end

        local inst = target.inst
        if not inst or not inst.Parent then return false end

        -- Reach check — never fire beyond physical range
        local reach = F.ChestReachDist or 4
        local r = U.hrp()
        if r and target.pos then
            if (r.Position - target.pos).Magnitude > reach + 2 then
                return false
            end
        end

        S.chestLastInteract = now

        if inst:IsA("ProximityPrompt") and promptValid(inst) then
            local ok = pcall(function()
                if type(fireproximityprompt) == "function" then
                    fireproximityprompt(inst)
                else
                    inst:InputHoldBegin()
                    task.wait(math.min(inst.HoldDuration or 0.1, 0.4))
                    inst:InputHoldEnd()
                end
            end)
            if ok then return true end
        elseif inst:IsA("ClickDetector") then
            return pcall(function()
                if type(fireclickdetector) == "function" then
                    fireclickdetector(inst)
                end
            end)
        elseif inst:IsA("BasePart") or inst:IsA("Model") then
            -- Find a valid prompt child and fire it
            for _, ch in ipairs(inst:GetDescendants()) do
                if ch:IsA("ProximityPrompt") and promptValid(ch) then
                    local ok = pcall(function()
                        if type(fireproximityprompt) == "function" then
                            fireproximityprompt(ch)
                        else
                            ch:InputHoldBegin()
                            task.wait(math.min(ch.HoldDuration or 0.1, 0.4))
                            ch:InputHoldEnd()
                        end
                    end)
                    if ok then return true end
                end
            end
            -- Fallback: physical T. Only if within 3 studs.
            if r and target.pos and (r.Position - target.pos).Magnitude <= 3.5 then
                U.tap("T")
                return true
            end
        end
        return false
    end

    --============================================================
    -- SWEEP · one pass, one interaction per gap
    --============================================================
    function Chest.sweep(radius)
        radius = radius or F.ChestRadius or 12
        local targets = Chest.scan(radius)
        if #targets == 0 then return 0 end
        local fired = 0
        for i = 1, #targets do
            local t = targets[i]
            if t.inst and t.inst.Parent and not cooling(t.inst) then
                -- Move to it if close enough to approach
                local r = U.hrp()
                if r and t.pos then
                    local dx = t.pos.X - r.Position.X
                    local dz = t.pos.Z - r.Position.Z
                    local d = math.sqrt(dx*dx + dz*dz)
                    if d > (F.ChestReachDist or 4) - 0.5 and d <= radius then
                        local flat = Vector3.new(dx, 0, dz)
                        if flat.Magnitude > 0.1 then
                            local dest = r.Position
                                + flat.Unit * math.max(0, flat.Magnitude - (F.ChestReachDist or 4) + 1)
                            dest = Vector3.new(dest.X, r.Position.Y, dest.Z)
                            local ok, cf = pcall(function()
                                return CFrame.new(dest, Vector3.new(t.pos.X, dest.Y, t.pos.Z))
                            end)
                            if ok and cf then r.CFrame = cf end
                            task.wait(0.15)
                        end
                    end
                end

                if tryFire(t) then
                    fired = fired + 1
                    if string.find(t.name, "Chest", 1, true) then
                        S.chestCollected = S.chestCollected + 1
                        print(string.format("[Dingus][Chest] opened %s @%.0f",
                            t.name, t.d))
                    else
                        S.chestLootCollected = S.chestLootCollected + 1
                    end
                    task.wait(F.ChestMinInteractGap or 2.0)
                else
                    S.chestFailed = S.chestFailed + 1
                    S.chestCooldowns[t.inst] = U.clock() + (F.ChestPerTargetCooldown or 60)
                end
            end
        end
        return fired
    end

    function Chest.collectAll(radius, maxPasses, deadline)
        radius = radius or F.ChestRadius or 12
        maxPasses = maxPasses or F.ChestMaxPasses or 3
        deadline = deadline or F.ChestPassDeadline or 6
        if not F.ChestEnabled then return 0, 0 end
        if S.chestRunning then return 0, 0 end
        S.chestRunning = true
        local startT = U.clock()
        local total, empty, pass = 0, 0, 0
        while U.clock() < startT + deadline and pass < maxPasses and empty < 2 do
            pass = pass + 1
            local fired = Chest.sweep(radius)
            total = total + fired
            if fired == 0 then empty = empty + 1 else empty = 0 end
            task.wait(0.5)
        end
        S.chestRunning = false
        return total, pass
    end

    function Chest.collectBossDrop()
        if not F.ChestEnabled or not F.ChestOnKill then return end
        -- Wait for the drop to land. Game spawns the chest ~1s after kill.
        task.wait(1.2)
        local fired, pass = Chest.collectAll()
        if fired > 0 or F.ChestVerbose then
            print(string.format("[Dingus][Chest] kill cycle · fired=%d passes=%d", fired, pass))
        end
    end

    function Chest.collectPassive()
        if not F.ChestEnabled or not F.ChestPassive then return end
        local t = U.clock()
        if t - (S.chestLastPassive or 0) < (F.ChestPassiveInterval or 20) then return end
        S.chestLastPassive = t
        Chest.sweep(F.ChestRadius or 12)
    end

    function Chest.setEnabled(v) F.ChestEnabled = not not v end
    function Chest.resetCooldowns() S.chestCooldowns = {} end

    function Chest.dump()
        local list = Chest.scan(F.ChestRadius or 12)
        print(string.format("[Dingus][Chest] %d whitelisted targets within %d studs:",
            #list, F.ChestRadius or 12))
        for i = 1, math.min(#list, 20) do
            local t = list[i]
            print(string.format("  [%s] %s @%.0f", t.kind, t.name, t.d))
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
            radius = F.ChestRadius or 12,
            reach = F.ChestReachDist or 4,
            gap = F.ChestMinInteractGap or 2.0,
            whitelistSize = #F.ChestWhitelist,
            collected = S.chestCollected or 0,
            lootCollected = S.chestLootCollected or 0,
            failed = S.chestFailed or 0,
            skipped = S.chestSkipped or 0,
            cooldowns = cd,
            lastTargets = #(S.chestLastTargets or {}),
            running = S.chestRunning or false,
        }
    end

    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            Chest.resetCooldowns()
        end)
    end

    print("[Dingus][chest] v4 · whitelist-only · honeypot-safe")
end

return Chest
