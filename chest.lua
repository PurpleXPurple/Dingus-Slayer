--[[
    Dingus-Slayer · chest.lua v5
    Learn-mode default. Whitelist-approval. Cluster honeypot detection.
    Session killswitch.

    Nothing fires until you add a name to F.ChestWhitelist manually.
    Learn mode logs what it sees so you can build the list safely.
]]--

local Chest = {}

function Chest.init(Ctx)
    local U, F, S = Ctx.Util, Ctx.Cfg, Ctx.St

    --============================================================
    -- CONFIG
    --============================================================
    F.ChestEnabled              = F.ChestEnabled              ~= false
    F.ChestLearnMode            = F.ChestLearnMode            ~= false   -- SAFE BY DEFAULT
    F.ChestOnKill               = F.ChestOnKill               ~= false
    F.ChestPassive              = F.ChestPassive              ~= false
    F.ChestPassiveInterval      = F.ChestPassiveInterval      or 25
    F.ChestRadius               = F.ChestRadius               or 10
    F.ChestReachDist            = F.ChestReachDist            or 4
    F.ChestMinInteractGap       = F.ChestMinInteractGap       or 3.0
    F.ChestMaxInteractionsPerMin = F.ChestMaxInteractionsPerMin or 10
    F.ChestSessionInteractionCap = F.ChestSessionInteractionCap or 40
    F.ChestMaxPasses            = F.ChestMaxPasses            or 2
    F.ChestPassDeadline        = F.ChestPassDeadline         or 5
    F.ChestPerTargetCooldown    = F.ChestPerTargetCooldown    or 90
    F.ChestHoneypotThreshold    = F.ChestHoneypotThreshold    or 3   -- cluster size
    F.ChestVerbose              = F.ChestVerbose              or true

    -- EMPTY BY DEFAULT. You populate this yourself after seeing items
    -- in-game. Format: exact case-sensitive name string.
    F.ChestWhitelist = F.ChestWhitelist or {}

    -- Honeypot reject signatures — never fire on these no matter what.
    F.ChestRejectSignatures = F.ChestRejectSignatures or {
        "grimore", "grimoire", "book",
        "/", "\\",
    }

    --============================================================
    -- STATE
    --============================================================
    S.chestCollected       = S.chestCollected       or 0
    S.chestLootCollected   = S.chestLootCollected   or 0
    S.chestFailed          = S.chestFailed          or 0
    S.chestSkipped         = S.chestSkipped         or 0
    S.chestCooldowns       = S.chestCooldowns       or {}
    S.chestLastInteract    = S.chestLastInteract    or 0
    S.chestSessionCount    = S.chestSessionCount    or 0
    S.chestMinuteWindow    = S.chestMinuteWindow    or {}
    S.chestKilled          = false
    S.chestLastTargets     = {}
    S.chestLastScanTs      = 0
    S.chestSeen            = S.chestSeen            or {}    -- learn-mode accumulator
    S.chestRunning         = false

    --============================================================
    -- HELPERS
    --============================================================
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

    local function promptValid(p)
        if not p or not p.Parent then return false end
        if p.Enabled == false then return false end
        local mad = p.MaxActivationDistance or 0
        if type(mad) ~= "number" or mad <= 0 then return false end
        if p.Visible == false then return false end
        -- Reject if any ancestor up to 6 hops has a Humanoid
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
    -- KILLSWITCH
    --============================================================
    local function checkKillswitch()
        if S.chestKilled then return false end
        if S.chestSessionCount >= (F.ChestSessionInteractionCap or 40) then
            S.chestKilled = true
            warn("[Dingus][Chest] SESSION CAP HIT — module disabled. "..
                 "Reset via Chest.resetKillswitch() after verifying safe.")
            return false
        end
        return true
    end

    -- rate limit: N interactions per 60s
    local function rateLimited()
        local now = U.clock()
        local win = S.chestMinuteWindow
        while #win > 0 and now - win[1] > 60 do
            table.remove(win, 1)
        end
        local cap = F.ChestMaxInteractionsPerMin or 10
        if #win >= cap then
            if F.ChestVerbose then
                print(string.format("[Dingus][Chest] rate limit: %d/min reached", cap))
            end
            return true
        end
        return false
    end

    local function recordInteraction()
        local now = U.clock()
        S.chestLastInteract = now
        S.chestSessionCount = S.chestSessionCount + 1
        table.insert(S.chestMinuteWindow, now)
    end

    --============================================================
    -- CLUSTER HONEYPOT DETECTION
    --============================================================
    -- If N+ instances within radius share a base-name pattern, that's a trap.
    -- Real loot doesn't spawn as 12 identical clones named Plane.007,
    -- Plane.008, Plane.011 ...
    local function hasHoneypotCluster(candidates)
        if #candidates < (F.ChestHoneypotThreshold or 3) then return false end
        -- Group by normalized base name (strip .NNN suffix)
        local groups = {}
        for i = 1, #candidates do
            local n = candidates[i].name or ""
            -- strip trailing .NNN or _NNN
            local base = n:gsub("%.[0-9]+$", ""):gsub("_[0-9]+$", "")
            groups[base] = (groups[base] or 0) + 1
        end
        for base, count in pairs(groups) do
            if count >= (F.ChestHoneypotThreshold or 3) then
                print(string.format(
                    "[Dingus][Chest] HONEYPOT DETECTED — %d clones of %q — refusing all",
                    count, base))
                return true
            end
        end
        return false
    end

    --============================================================
    -- SCAN (proximity only, no workspace walk)
    --============================================================
    function Chest.scan(radius)
        radius = radius or F.ChestRadius or 10
        local r = U.hrp()
        if not r then return {} end
        local mp = r.Position
        local out, seen = {}, {}

        -- Tight proximity walk: only parts physically near the player.
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { U.Lp.Character }
        params.MaxParts = 40

        local ok, parts = pcall(function()
            return workspace:GetPartBoundsInRadius(mp, radius, params)
        end)
        if not ok or not parts then return {} end

        for i = 1, #parts do
            local part = parts[i]
            if part and not seen[part] then
                local name = part.Name
                if isWhitelisted(name) then
                    seen[part] = true
                    table.insert(out, {
                        inst = part, pos = part.Position,
                        d = (part.Position - mp).Magnitude,
                        kind = "part", name = name,
                    })
                end
                for _, ch in ipairs(part:GetChildren()) do
                    if not seen[ch] then
                        if ch:IsA("ProximityPrompt") and promptValid(ch) then
                            seen[ch] = true
                            local label = part.Name
                            if ch.ObjectText and #ch.ObjectText > 0 then
                                label = ch.ObjectText
                            end
                            table.insert(out, {
                                inst = ch, pos = part.Position,
                                d = (part.Position - mp).Magnitude,
                                kind = "prompt", name = label,
                                parentName = part.Name,
                            })
                        elseif ch:IsA("ClickDetector") then
                            seen[ch] = true
                            table.insert(out, {
                                inst = ch, pos = part.Position,
                                d = (part.Position - mp).Magnitude,
                                kind = "click", name = part.Name,
                            })
                        end
                    end
                end
            end
        end

        table.sort(out, function(a, b) return a.d < b.d end)
        S.chestLastTargets = out
        S.chestLastScanTs = U.clock()

        -- Learn mode: record everything seen
        if F.ChestLearnMode then
            for i = 1, #out do
                local t = out[i]
                S.chestSeen[t.name] = (S.chestSeen[t.name] or 0) + 1
            end
        end

        return out
    end

    function Chest.lastTargets() return S.chestLastTargets or {} end

    --============================================================
    -- FIRE
    --============================================================
    local function tryFire(target)
        if not checkKillswitch() then return false end
        if rateLimited() then return false end

        local now = U.clock()
        if now - S.chestLastInteract < (F.ChestMinInteractGap or 3.0) then
            return false
        end

        local inst = target.inst
        if not inst or not inst.Parent then return false end

        local r = U.hrp()
        if r and target.pos then
            local d = (r.Position - target.pos).Magnitude
            if d > (F.ChestReachDist or 4) + 1 then
                return false
            end
        end

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
            if ok then recordInteraction(); return true end
        elseif inst:IsA("ClickDetector") then
            local ok = pcall(function()
                if type(fireclickdetector) == "function" then
                    fireclickdetector(inst)
                end
            end)
            if ok then recordInteraction(); return true end
        elseif inst:IsA("BasePart") or inst:IsA("Model") then
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
                    if ok then recordInteraction(); return true end
                end
            end
            if r and target.pos and (r.Position - target.pos).Magnitude <= 3.5 then
                U.tap("T")
                recordInteraction()
                return true
            end
        end
        return false
    end

    --============================================================
    -- SWEEP
    --============================================================
    function Chest.sweep(radius)
        radius = radius or F.ChestRadius or 10
        if not checkKillswitch() then return 0 end

        local targets = Chest.scan(radius)
        if #targets == 0 then return 0 end

        -- honeypot cluster check before any interaction
        if hasHoneypotCluster(targets) then
            S.chestSkipped = S.chestSkipped + #targets
            for i = 1, #targets do
                S.chestCooldowns[targets[i].inst] = U.clock() + 300
            end
            return 0
        end

        -- learn mode: log and return, no firing
        if F.ChestLearnMode then
            print(string.format(
                "[Dingus][Chest][learn] %d target(s) in range — NOT firing:",
                #targets))
            for i = 1, math.min(#targets, 8) do
                local t = targets[i]
                print(string.format("  [%s] %q @%.1f (parent=%q)",
                    t.kind, t.name, t.d, t.parentName or "?"))
            end
            return 0
        end

        local fired = 0
        for i = 1, #targets do
            local t = targets[i]
            if t.inst and t.inst.Parent and not cooling(t.inst) then
                -- Approach within reach
                local r = U.hrp()
                if r and t.pos then
                    local dx = t.pos.X - r.Position.X
                    local dz = t.pos.Z - r.Position.Z
                    local d = math.sqrt(dx*dx + dz*dz)
                    local reach = F.ChestReachDist or 4
                    if d > reach - 0.5 and d <= radius then
                        local flat = Vector3.new(dx, 0, dz)
                        if flat.Magnitude > 0.1 then
                            local dest = r.Position
                                + flat.Unit * math.max(0, flat.Magnitude - reach + 1)
                            dest = Vector3.new(dest.X, r.Position.Y, dest.Z)
                            local ok, cf = pcall(function()
                                return CFrame.new(dest, Vector3.new(t.pos.X, dest.Y, t.pos.Z))
                            end)
                            if ok and cf then r.CFrame = cf end
                            task.wait(0.2)
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
                        print(string.format("[Dingus][Chest] loot %s @%.0f",
                            t.name, t.d))
                    end
                    task.wait(F.ChestMinInteractGap or 3.0)
                else
                    S.chestFailed = S.chestFailed + 1
                    S.chestCooldowns[t.inst] = U.clock() + (F.ChestPerTargetCooldown or 90)
                end
            end
        end
        return fired
    end

    function Chest.collectAll(radius, maxPasses, deadline)
        if F.ChestLearnMode then
            print("[Dingus][Chest] learn mode — collectAll is a no-op")
            return 0, 0
        end
        if not checkKillswitch() then return 0, 0 end
        radius = radius or F.ChestRadius or 10
        maxPasses = maxPasses or F.ChestMaxPasses or 2
        deadline = deadline or F.ChestPassDeadline or 5
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
            task.wait(0.6)
        end
        S.chestRunning = false
        return total, pass
    end

    function Chest.collectBossDrop()
        if F.ChestLearnMode then return end
        if not F.ChestEnabled or not F.ChestOnKill then return end
        task.wait(1.5)
        local fired, pass = Chest.collectAll()
        if fired > 0 or F.ChestVerbose then
            print(string.format("[Dingus][Chest] kill cycle fired=%d pass=%d", fired, pass))
        end
    end

    function Chest.collectPassive()
        if F.ChestLearnMode then return end
        if not F.ChestEnabled or not F.ChestPassive then return end
        local t = U.clock()
        if t - (S.chestLastPassive or 0) < (F.ChestPassiveInterval or 25) then return end
        S.chestLastPassive = t
        Chest.sweep(F.ChestRadius or 10)
    end

    --============================================================
    -- PUBLIC
    --============================================================
    function Chest.setEnabled(v) F.ChestEnabled = not not v end
    function Chest.setLearnMode(v)
        F.ChestLearnMode = not not v
        print("[Dingus][Chest] learn mode = " .. tostring(F.ChestLearnMode))
    end
    function Chest.resetCooldowns() S.chestCooldowns = {} end
    function Chest.resetKillswitch()
        S.chestKilled = false
        S.chestSessionCount = 0
        S.chestMinuteWindow = {}
        print("[Dingus][Chest] killswitch reset")
    end

    function Chest.approve(name)
        -- add to whitelist
        for i = 1, #F.ChestWhitelist do
            if F.ChestWhitelist[i] == name then
                print("[Dingus][Chest] already approved: " .. name)
                return false
            end
        end
        table.insert(F.ChestWhitelist, name)
        print("[Dingus][Chest] approved: " .. name ..
              " (whitelist size " .. #F.ChestWhitelist .. ")")
        return true
    end

    function Chest.unapprove(name)
        for i = #F.ChestWhitelist, 1, -1 do
            if F.ChestWhitelist[i] == name then
                table.remove(F.ChestWhitelist, i)
                print("[Dingus][Chest] unapproved: " .. name)
                return true
            end
        end
        return false
    end

    function Chest.listSeen()
        print("[Dingus][Chest] learn-mode observations:")
        local names = {}
        for n in pairs(S.chestSeen or {}) do table.insert(names, n) end
        table.sort(names)
        for i = 1, #names do
            local n = names[i]
            local wl = false
            for j = 1, #F.ChestWhitelist do
                if F.ChestWhitelist[j] == n then wl = true; break end
            end
            print(string.format("  %-40s seen %dx%s",
                n, S.chestSeen[n], wl and " [APPROVED]" or ""))
        end
        if #names == 0 then print("  (nothing yet)") end
        return names
    end

    function Chest.dump()
        local list = Chest.scan(F.ChestRadius or 10)
        print(string.format("[Dingus][Chest] %d targets in %d studs (learn=%s, killed=%s):",
            #list, F.ChestRadius or 10,
            tostring(F.ChestLearnMode), tostring(S.chestKilled)))
        for i = 1, math.min(#list, 20) do
            local t = list[i]
            local wl = false
            for j = 1, #F.ChestWhitelist do
                if F.ChestWhitelist[j] == t.name then wl = true; break end
            end
            print(string.format("  [%s] %q @%.1f%s",
                t.kind, t.name, t.d, wl and " [WL]" or ""))
        end
        return list
    end

    function Chest.stats()
        local cd = 0
        for _ in pairs(S.chestCooldowns or {}) do cd = cd + 1 end
        return {
            enabled = F.ChestEnabled,
            learnMode = F.ChestLearnMode,
            onKill = F.ChestOnKill,
            passive = F.ChestPassive,
            radius = F.ChestRadius or 10,
            reach = F.ChestReachDist or 4,
            gap = F.ChestMinInteractGap or 3.0,
            whitelistSize = #F.ChestWhitelist,
            rejectCount = #F.ChestRejectSignatures,
            sessionCount = S.chestSessionCount or 0,
            sessionCap = F.ChestSessionInteractionCap or 40,
            minuteCount = #(S.chestMinuteWindow or {}),
            minuteCap = F.ChestMaxInteractionsPerMin or 10,
            killed = S.chestKilled,
            collected = S.chestCollected or 0,
            lootCollected = S.chestLootCollected or 0,
            failed = S.chestFailed or 0,
            skipped = S.chestSkipped or 0,
            cooldowns = cd,
            lastTargets = #(S.chestLastTargets or {}),
        }
    end

    --============================================================
    -- AUTO-LEARN LOG
    --============================================================
    task.spawn(function()
        while S.run do
            if F.ChestLearnMode and S.boot then
                pcall(function() Chest.scan(F.ChestRadius or 10) end)
            end
            task.wait(4)
        end
    end)

    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            Chest.resetCooldowns()
        end)
    end

    print(string.format(
        "[Dingus][chest] v5 · LEARN=%s · whitelist=%d · cap=%d/min, %d/session",
        tostring(F.ChestLearnMode), #F.ChestWhitelist,
        F.ChestMaxInteractionsPerMin or 10,
        F.ChestSessionInteractionCap or 40))
end

return Chest
