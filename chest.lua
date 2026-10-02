--[[
    Dingus-Slayer · chest.lua v6
    Boss-anchored collection. Jittered delays. Bounded attempt count.

    Flow on boss kill:
      1. Boss dies → attack calls Chest.collectAtBoss(pos, name)
      2. Chest waits 3–9s (random jitter)
      3. Scans a 15-stud radius around the boss corpse only
      4. Counts found items
      5. Attempts exactly that many — no more, no retries
      6. Moves on regardless of success rate
]]--

local Chest = {}

function Chest.init(Ctx)
    local U, F, S = Ctx.Util, Ctx.Cfg, Ctx.St

    --============================================================
    -- CONFIG
    --============================================================
    F.ChestEnabled              = F.ChestEnabled              ~= false
    F.ChestLearnMode            = F.ChestLearnMode            ~= false
    F.ChestOnKill               = F.ChestOnKill               ~= false
    F.ChestPassive              = F.ChestPassive              ~= false
    F.ChestPassiveInterval      = F.ChestPassiveInterval      or 30
    F.ChestRadius               = F.ChestRadius               or 10
    F.ChestBossLootRadius       = F.ChestBossLootRadius       or 15
    F.ChestBossLootDelayMin     = F.ChestBossLootDelayMin     or 3.0
    F.ChestBossLootDelayMax     = F.ChestBossLootDelayMax     or 9.0
    F.ChestBossInterItemMin     = F.ChestBossInterItemMin     or 1.5
    F.ChestBossInterItemMax     = F.ChestBossInterItemMax     or 3.0
    F.ChestReachDist            = F.ChestReachDist            or 4
    F.ChestMinInteractGap       = F.ChestMinInteractGap       or 3.0
    F.ChestMaxInteractionsPerMin = F.ChestMaxInteractionsPerMin or 10
    F.ChestSessionInteractionCap = F.ChestSessionInteractionCap or 40
    F.ChestMaxPasses            = F.ChestMaxPasses            or 2
    F.ChestPassDeadline        = F.ChestPassDeadline         or 5
    F.ChestPerTargetCooldown    = F.ChestPerTargetCooldown    or 90
    F.ChestHoneypotThreshold    = F.ChestHoneypotThreshold    or 3
    F.ChestVerbose              = F.ChestVerbose              or true

    F.ChestWhitelist = F.ChestWhitelist or {}

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
    S.chestSeen            = S.chestSeen            or {}
    S.chestRunning         = false
    S.chestBossCycles      = 0
    S.chestLastBossName    = nil

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

    local function promptValid(p)
        if not p or not p.Parent then return false end
        if p.Enabled == false then return false end
        local mad = p.MaxActivationDistance or 0
        if type(mad) ~= "number" or mad <= 0 then return false end
        if p.Visible == false then return false end
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

    local function checkKillswitch()
        if S.chestKilled then return false end
        if S.chestSessionCount >= (F.ChestSessionInteractionCap or 40) then
            S.chestKilled = true
            warn("[Dingus][Chest] SESSION CAP — module disabled. "..
                 "Chest.resetKillswitch() to re-enable.")
            return false
        end
        return true
    end

    local function rateLimited()
        local now = U.clock()
        local win = S.chestMinuteWindow
        while #win > 0 and now - win[1] > 60 do table.remove(win, 1) end
        if #win >= (F.ChestMaxInteractionsPerMin or 10) then
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
    -- HONEYPOT CLUSTER DETECTION
    --============================================================
    local function hasHoneypotCluster(candidates)
        if #candidates < (F.ChestHoneypotThreshold or 3) then return false end
        local groups = {}
        for i = 1, #candidates do
            local n = candidates[i].name or ""
            local base = n:gsub("%.[0-9]+$", ""):gsub("_[0-9]+$", "")
            groups[base] = (groups[base] or 0) + 1
        end
        for base, count in pairs(groups) do
            if count >= (F.ChestHoneypotThreshold or 3) then
                print(string.format(
                    "[Dingus][Chest] HONEYPOT CLUSTER — %d clones of %q — refusing",
                    count, base))
                return true
            end
        end
        return false
    end

    --============================================================
    -- SCAN AROUND A POSITION (not the player)
    --============================================================
    local function scanAround(centerPos, radius)
        local out, seen = {}, {}
        if not centerPos then return out end
        local maxSq = radius * radius

        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { U.Lp.Character }
        params.MaxParts = 80

        local ok, parts = pcall(function()
            return workspace:GetPartBoundsInRadius(centerPos, radius, params)
        end)
        if not ok or not parts then return out end

        for i = 1, #parts do
            local part = parts[i]
            if part and not seen[part] then
                local name = part.Name
                if isWhitelisted(name) then
                    local dx = part.Position.X - centerPos.X
                    local dy = part.Position.Y - centerPos.Y
                    local dz = part.Position.Z - centerPos.Z
                    local dSq = dx*dx + dy*dy + dz*dz
                    if dSq <= maxSq then
                        seen[part] = true
                        table.insert(out, {
                            inst = part, pos = part.Position,
                            d = math.sqrt(dSq),
                            kind = "part", name = name,
                        })
                    end
                end
                for _, ch in ipairs(part:GetChildren()) do
                    if not seen[ch] then
                        if ch:IsA("ProximityPrompt") and promptValid(ch) then
                            if isWhitelisted(part.Name) then
                                local dx = part.Position.X - centerPos.X
                                local dy = part.Position.Y - centerPos.Y
                                local dz = part.Position.Z - centerPos.Z
                                local dSq = dx*dx + dy*dy + dz*dz
                                if dSq <= maxSq then
                                    seen[ch] = true
                                    table.insert(out, {
                                        inst = ch, pos = part.Position,
                                        d = math.sqrt(dSq),
                                        kind = "prompt", name = part.Name,
                                        parentName = part.Name,
                                    })
                                end
                            end
                        elseif ch:IsA("ClickDetector") then
                            if isWhitelisted(part.Name) then
                                local dx = part.Position.X - centerPos.X
                                local dy = part.Position.Y - centerPos.Y
                                local dz = part.Position.Z - centerPos.Z
                                local dSq = dx*dx + dy*dy + dz*dz
                                if dSq <= maxSq then
                                    seen[ch] = true
                                    table.insert(out, {
                                        inst = ch, pos = part.Position,
                                        d = math.sqrt(dSq),
                                        kind = "click", name = part.Name,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
        table.sort(out, function(a, b) return a.d < b.d end)
        return out
    end

    --============================================================
    -- SCAN AROUND PLAYER (passive / learn mode)
    --============================================================
    function Chest.scan(radius)
        radius = radius or F.ChestRadius or 10
        local r = U.hrp(); if not r then return {} end
        local out = scanAround(r.Position, radius)
        S.chestLastTargets = out
        S.chestLastScanTs = U.clock()
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
            if d > (F.ChestReachDist or 4) + 1 then return false end
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
    -- APPROACH
    --============================================================
    local function approach(pos, reach)
        local r = U.hrp(); if not r or not pos then return end
        local dx = pos.X - r.Position.X
        local dz = pos.Z - r.Position.Z
        local d = math.sqrt(dx*dx + dz*dz)
        if d <= reach - 0.5 then return end
        local flat = Vector3.new(dx, 0, dz)
        if flat.Magnitude < 0.1 then return end
        local dest = r.Position + flat.Unit * math.max(0, flat.Magnitude - reach + 1)
        dest = Vector3.new(dest.X, r.Position.Y, dest.Z)
        local ok, cf = pcall(function()
            return CFrame.new(dest, Vector3.new(pos.X, dest.Y, pos.Z))
        end)
        if ok and cf then r.CFrame = cf end
        task.wait(0.2)
    end

    --============================================================
    -- BOSS-ANCHORED COLLECTION
    --============================================================
    -- Called from attack.lua with the boss corpse position.
    -- Wait jittered 3-9s, scan around corpse, attempt exactly N.
    -- Never retries, never wanders.
    function Chest.collectAtBoss(bossPos, bossName)
        if F.ChestLearnMode then
            print("[Dingus][Chest] learn mode — skipping boss loot cycle")
            return 0, 0
        end
        if not F.ChestEnabled or not F.ChestOnKill then return 0, 0 end
        if not checkKillswitch() then return 0, 0 end

        if S.chestRunning then return 0, 0 end
        S.chestRunning = true
        S.chestBossCycles = S.chestBossCycles + 1
        S.chestLastBossName = bossName

        local r = U.hrp()
        if not bossPos and r then bossPos = r.Position end
        if not bossPos then S.chestRunning = false; return 0, 0 end

        local delay = (F.ChestBossLootDelayMin or 3.0)
            + math.random() * ((F.ChestBossLootDelayMax or 9.0)
                             - (F.ChestBossLootDelayMin or 3.0))

        print(string.format(
            "[Dingus][Chest] %s died — waiting %.1fs then scanning corpse",
            tostring(bossName or "boss"), delay))

        -- Hold up the cycle while jittering. Cancel-aware.
        local waited = 0
        while waited < delay do
            if S.chestAbortRequest then
                print("[Dingus][Chest] abort requested — loot cycle cancelled")
                S.chestRunning = false
                S.chestAbortRequest = false
                return 0, 0
            end
            local step = math.min(0.4, delay - waited)
            task.wait(step)
            waited = waited + step
        end

        -- Scan around boss corpse only
        local radius = F.ChestBossLootRadius or 15
        local targets = scanAround(bossPos, radius)

        if #targets == 0 then
            if F.ChestVerbose then
                print(string.format(
                    "[Dingus][Chest] nothing found in %d-stud radius of %s corpse",
                    radius, tostring(bossName or "boss")))
            end
            S.chestRunning = false
            return 0, 0
        end

        -- Honeypot guard
        if hasHoneypotCluster(targets) then
            print("[Dingus][Chest] honeypot at boss corpse — aborting cycle")
            for i = 1, #targets do
                S.chestCooldowns[targets[i].inst] = U.clock() + 600
            end
            S.chestRunning = false
            return 0, #targets
        end

        -- Cap the number of attempts to what we saw at scan time
        local attemptsAllowed = #targets
        print(string.format(
            "[Dingus][Chest] %d items at corpse — attempting exactly %d",
            attemptsAllowed, attemptsAllowed))

        local collected = 0
        local attempted = 0

        for i = 1, attemptsAllowed do
            if S.chestAbortRequest then
                print("[Dingus][Chest] abort mid-cycle — stopping")
                break
            end
            if not checkKillswitch() then break end

            -- Re-scan for the nearest live target not on cooldown
            local live = scanAround(bossPos, radius)
            local target = nil
            for j = 1, #live do
                local t = live[j]
                if t.inst and t.inst.Parent and not cooling(t.inst) then
                    target = t
                    break
                end
            end

            if not target then
                print("[Dingus][Chest] no more live targets — ending cycle")
                break
            end

            attempted = attempted + 1
            approach(target.pos, F.ChestReachDist or 4)

            if tryFire(target) then
                collected = collected + 1
                S.chestCollected = S.chestCollected + 1
                print(string.format(
                    "[Dingus][Chest] collected %s (attempt %d/%d)",
                    target.name, i, attemptsAllowed))
            else
                S.chestFailed = S.chestFailed + 1
                print(string.format(
                    "[Dingus][Chest] skip %s (attempt %d/%d — %d collected so far)",
                    target.name, i, attemptsAllowed, collected))
                S.chestCooldowns[target.inst] = U.clock()
                    + (F.ChestPerTargetCooldown or 90)
            end

            -- Jittered inter-item delay so the cadence isn't machine-uniform
            if i < attemptsAllowed then
                local gap = (F.ChestBossInterItemMin or 1.5)
                    + math.random() * ((F.ChestBossInterItemMax or 3.0)
                                     - (F.ChestBossInterItemMin or 1.5))
                local gwaited = 0
                while gwaited < gap do
                    if S.chestAbortRequest then break end
                    local step = math.min(0.3, gap - gwaited)
                    task.wait(step)
                    gwaited = gwaited + step
                end
            end
        end

        print(string.format(
            "[Dingus][Chest] corpse cycle done · %d/%d collected · moving to next boss",
            collected, attemptsAllowed))

        S.chestAbortRequest = false
        S.chestRunning = false
        return collected, attemptsAllowed
    end

    --============================================================
    -- LEGACY SWEEP (still used for passive/learn)
    --============================================================
    function Chest.sweep(radius)
        if not checkKillswitch() then return 0 end
        radius = radius or F.ChestRadius or 10
        local targets = Chest.scan(radius)
        if #targets == 0 then return 0 end
        if hasHoneypotCluster(targets) then
            for i = 1, #targets do
                S.chestCooldowns[targets[i].inst] = U.clock() + 300
            end
            return 0
        end
        if F.ChestLearnMode then
            print(string.format("[Dingus][Chest][learn] %d targets — not firing", #targets))
            for i = 1, math.min(#targets, 8) do
                local t = targets[i]
                print(string.format("  [%s] %q @%.1f",
                    t.kind, t.name, t.d))
            end
            return 0
        end
        local fired = 0
        for i = 1, #targets do
            local t = targets[i]
            if t.inst and t.inst.Parent and not cooling(t.inst) then
                approach(t.pos, F.ChestReachDist or 4)
                if tryFire(t) then
                    fired = fired + 1
                    if string.find(t.name, "Chest", 1, true) then
                        S.chestCollected = S.chestCollected + 1
                    else
                        S.chestLootCollected = S.chestLootCollected + 1
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
        if F.ChestLearnMode then return 0, 0 end
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

    --============================================================
    -- PASSIVE — skipped while boss cycle is running
    --============================================================
    function Chest.collectPassive()
        if F.ChestLearnMode then return end
        if not F.ChestEnabled or not F.ChestPassive then return end
        if S.chestRunning then return end
        local t = U.clock()
        if t - (S.chestLastPassive or 0) < (F.ChestPassiveInterval or 30) then return end
        S.chestLastPassive = t
        Chest.sweep(F.ChestRadius or 10)
    end

    --============================================================
    -- CONTROL
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
    function Chest.abort() S.chestAbortRequest = true end

    function Chest.approve(name)
        for i = 1, #F.ChestWhitelist do
            if F.ChestWhitelist[i] == name then return false end
        end
        table.insert(F.ChestWhitelist, name)
        print("[Dingus][Chest] approved: " .. name ..
              " (whitelist=" .. #F.ChestWhitelist .. ")")
        return true
    end

    function Chest.unapprove(name)
        for i = #F.ChestWhitelist, 1, -1 do
            if F.ChestWhitelist[i] == name then
                table.remove(F.ChestWhitelist, i)
                return true
            end
        end
        return false
    end

    function Chest.listSeen()
        print("[Dingus][Chest] learn observations:")
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
        print(string.format("[Dingus][Chest] %d targets (learn=%s killed=%s)",
            #list, tostring(F.ChestLearnMode), tostring(S.chestKilled)))
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
            bossRadius = F.ChestBossLootRadius or 15,
            bossDelayMin = F.ChestBossLootDelayMin or 3.0,
            bossDelayMax = F.ChestBossLootDelayMax or 9.0,
            reach = F.ChestReachDist or 4,
            whitelistSize = #F.ChestWhitelist,
            sessionCount = S.chestSessionCount or 0,
            sessionCap = F.ChestSessionInteractionCap or 40,
            minuteCount = #(S.chestMinuteWindow or {}),
            minuteCap = F.ChestMaxInteractionsPerMin or 10,
            killed = S.chestKilled,
            running = S.chestRunning,
            bossCycles = S.chestBossCycles or 0,
            lastBoss = S.chestLastBossName,
            collected = S.chestCollected or 0,
            lootCollected = S.chestLootCollected or 0,
            failed = S.chestFailed or 0,
            skipped = S.chestSkipped or 0,
            cooldowns = cd,
            lastTargets = #(S.chestLastTargets or {}),
        }
    end

    --============================================================
    -- LEARN SCAN LOOP
    --============================================================
    task.spawn(function()
        while S.run do
            if F.ChestLearnMode and S.boot and not S.chestRunning then
                pcall(function() Chest.scan(F.ChestRadius or 10) end)
            end
            task.wait(4)
        end
    end)

    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            Chest.resetCooldowns()
            S.chestAbortRequest = true
        end)
    end

    print(string.format(
        "[Dingus][chest] v6 · LEARN=%s · WL=%d · boss-delay=%.1f-%.1fs · radius=%d",
        tostring(F.ChestLearnMode), #F.ChestWhitelist,
        F.ChestBossLootDelayMin or 3.0, F.ChestBossLootDelayMax or 9.0,
        F.ChestBossLootRadius or 15))
end

return Chest
