-- Dingus-Slayer · chest.lua v7
-- Cross-device: uses U.firePrompt / U.fireClick / U.touchInterest.

local Chest = {}

function Chest.init(Ctx)
    local U, F, S = Ctx.Util, Ctx.Cfg, Ctx.St

    F.ChestEnabled = F.ChestEnabled ~= false
    F.ChestLearnMode = F.ChestLearnMode ~= false
    F.ChestOnKill = F.ChestOnKill ~= false
    F.ChestPassive = F.ChestPassive ~= false
    F.ChestWhitelist = F.ChestWhitelist or {}
    F.ChestRejectSignatures = F.ChestRejectSignatures or { "grimore","grimoire","book","/","\\" }

    S.chestCollected = S.chestCollected or 0
    S.chestLootCollected = S.chestLootCollected or 0
    S.chestFailed = S.chestFailed or 0
    S.chestCooldowns = S.chestCooldowns or {}
    S.chestLastInteract = S.chestLastInteract or 0
    S.chestSessionCount = S.chestSessionCount or 0
    S.chestMinuteWindow = S.chestMinuteWindow or {}
    S.chestKilled = S.chestKilled or false
    S.chestRunning = S.chestRunning or false
    S.chestSeen = S.chestSeen or {}
    S.chestLastTargets = S.chestLastTargets or {}
    S.chestBossCycles = S.chestBossCycles or 0

    local function rejectedName(name)
        if not name then return true end
        local l = string.lower(name)
        for _, sig in ipairs(F.ChestRejectSignatures) do
            if l:find(sig, 1, true) then return true end
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
            warn("[Dingus][Chest] SESSION CAP — disabled")
            return false
        end
        return true
    end

    local function rateLimited()
        local now = U.clock()
        local win = S.chestMinuteWindow
        while #win > 0 and now - win[1] > 60 do table.remove(win, 1) end
        return #win >= (F.ChestMaxInteractionsPerMin or 10)
    end

    local function recordInteraction()
        local now = U.clock()
        S.chestLastInteract = now
        S.chestSessionCount = S.chestSessionCount + 1
        table.insert(S.chestMinuteWindow, now)
    end

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
                print(string.format("[Dingus][Chest] HONEYPOT — %d clones of %q", count, base))
                return true
            end
        end
        return false
    end

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
                        table.insert(out, { inst=part, pos=part.Position, d=math.sqrt(dSq), kind="part", name=name })
                    end
                end
                for _, ch in ipairs(part:GetChildren()) do
                    if not seen[ch] then
                        if ch:IsA("ProximityPrompt") and promptValid(ch) and isWhitelisted(part.Name) then
                            local dx = part.Position.X - centerPos.X
                            local dy = part.Position.Y - centerPos.Y
                            local dz = part.Position.Z - centerPos.Z
                            local dSq = dx*dx + dy*dy + dz*dz
                            if dSq <= maxSq then
                                seen[ch] = true
                                table.insert(out, { inst=ch, pos=part.Position, d=math.sqrt(dSq), kind="prompt", name=part.Name })
                            end
                        elseif ch:IsA("ClickDetector") and isWhitelisted(part.Name) then
                            local dx = part.Position.X - centerPos.X
                            local dy = part.Position.Y - centerPos.Y
                            local dz = part.Position.Z - centerPos.Z
                            local dSq = dx*dx + dy*dy + dz*dz
                            if dSq <= maxSq then
                                seen[ch] = true
                                table.insert(out, { inst=ch, pos=part.Position, d=math.sqrt(dSq), kind="click", name=part.Name })
                            end
                        end
                    end
                end
            end
        end
        table.sort(out, function(a, b) return a.d < b.d end)
        return out
    end

    function Chest.scan(radius)
        radius = radius or F.ChestRadius or 10
        local r = U.hrp(); if not r then return {} end
        local out = scanAround(r.Position, radius)
        S.chestLastTargets = out
        if F.ChestLearnMode then
            for i = 1, #out do
                S.chestSeen[out[i].name] = (S.chestSeen[out[i].name] or 0) + 1
            end
        end
        return out
    end

    function Chest.lastTargets() return S.chestLastTargets or {} end

    local function tryFire(target)
        if not checkKillswitch() then return false end
        if rateLimited() then return false end
        local now = U.clock()
        if now - S.chestLastInteract < (F.ChestMinInteractGap or 3.0) then return false end
        local inst = target.inst
        if not inst or not inst.Parent then return false end
        local r = U.hrp()
        if r and target.pos then
            local d = (r.Position - target.pos).Magnitude
            if d > (F.ChestReachDist or 4) + 1 then return false end
        end
        if inst:IsA("ProximityPrompt") then
            if U.firePrompt(inst) then recordInteraction(); return true end
        elseif inst:IsA("ClickDetector") then
            if U.fireClick(inst) then recordInteraction(); return true end
        end
        return false
    end

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

    function Chest.collectAtBoss(bossPos, bossName)
        if F.ChestLearnMode then return 0, 0 end
        if not F.ChestEnabled or not F.ChestOnKill then return 0, 0 end
        if not checkKillswitch() then return 0, 0 end
        if S.chestRunning then return 0, 0 end
        S.chestRunning = true
        S.chestBossCycles = S.chestBossCycles + 1
        local r = U.hrp()
        if not bossPos and r then bossPos = r.Position end
        if not bossPos then S.chestRunning = false; return 0, 0 end
        local delay = (F.ChestBossLootDelayMin or 3.0)
            + math.random() * ((F.ChestBossLootDelayMax or 9.0) - (F.ChestBossLootDelayMin or 3.0))
        local waited = 0
        while waited < delay do
            if S.chestAbortRequest then
                S.chestRunning = false
                S.chestAbortRequest = false
                return 0, 0
            end
            local step = math.min(0.4, delay - waited)
            task.wait(step)
            waited = waited + step
        end
        local radius = F.ChestBossLootRadius or 15
        local targets = scanAround(bossPos, radius)
        if #targets == 0 then S.chestRunning = false; return 0, 0 end
        if hasHoneypotCluster(targets) then
            for i = 1, #targets do S.chestCooldowns[targets[i].inst] = U.clock() + 600 end
            S.chestRunning = false
            return 0, #targets
        end
        local attemptsAllowed = #targets
        local collected = 0
        for i = 1, attemptsAllowed do
            if S.chestAbortRequest then break end
            if not checkKillswitch() then break end
            local live = scanAround(bossPos, radius)
            local target = nil
            for j = 1, #live do
                local t = live[j]
                if t.inst and t.inst.Parent and not cooling(t.inst) then
                    target = t; break
                end
            end
            if not target then break end
            approach(target.pos, F.ChestReachDist or 4)
            if tryFire(target) then
                collected = collected + 1
                S.chestCollected = S.chestCollected + 1
            else
                S.chestFailed = S.chestFailed + 1
                S.chestCooldowns[target.inst] = U.clock() + (F.ChestPerTargetCooldown or 90)
            end
            if i < attemptsAllowed then
                local gap = (F.ChestBossInterItemMin or 1.5)
                    + math.random() * ((F.ChestBossInterItemMax or 3.0) - (F.ChestBossInterItemMin or 1.5))
                local gwaited = 0
                while gwaited < gap do
                    if S.chestAbortRequest then break end
                    local step = math.min(0.3, gap - gwaited)
                    task.wait(step)
                    gwaited = gwaited + step
                end
            end
        end
        S.chestAbortRequest = false
        S.chestRunning = false
        return collected, attemptsAllowed
    end

    function Chest.collectPassive()
        if F.ChestLearnMode then return end
        if not F.ChestEnabled or not F.ChestPassive then return end
        if S.chestRunning then return end
        local t = U.clock()
        if t - (S.chestLastPassive or 0) < (F.ChestPassiveInterval or 30) then return end
        S.chestLastPassive = t
        local targets = Chest.scan(F.ChestRadius or 10)
        for i = 1, math.min(#targets, 5) do
            approach(targets[i].pos, F.ChestReachDist or 4)
            tryFire(targets[i])
        end
    end

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
    end
    function Chest.abort() S.chestAbortRequest = true end

    function Chest.approve(name)
        for i = 1, #F.ChestWhitelist do
            if F.ChestWhitelist[i] == name then return false end
        end
        table.insert(F.ChestWhitelist, name)
        print("[Dingus][Chest] approved: "..name.." (wl="..#F.ChestWhitelist..")")
        return true
    end

    function Chest.unapprove(name)
        for i = #F.ChestWhitelist, 1, -1 do
            if F.ChestWhitelist[i] == name then
                table.remove(F.ChestWhitelist, i); return true
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
            print(string.format("  %-40s %dx%s", n, S.chestSeen[n], wl and " [APPROVED]" or ""))
        end
        return names
    end

    function Chest.dump()
        local list = Chest.scan(F.ChestRadius or 10)
        print(string.format("[Dingus][Chest] %d targets (learn=%s)",
            #list, tostring(F.ChestLearnMode)))
        for i = 1, math.min(#list, 20) do
            local t = list[i]
            print(string.format("  [%s] %q @%.1f", t.kind, t.name, t.d))
        end
        return list
    end

    function Chest.stats()
        local cd = 0
        for _ in pairs(S.chestCooldowns or {}) do cd = cd + 1 end
        return {
            enabled = F.ChestEnabled, learnMode = F.ChestLearnMode,
            whitelistSize = #F.ChestWhitelist,
            sessionCount = S.chestSessionCount or 0,
            sessionCap = F.ChestSessionInteractionCap or 40,
            killed = S.chestKilled, running = S.chestRunning,
            collected = S.chestCollected or 0,
            failed = S.chestFailed or 0,
            cooldowns = cd,
            lastTargets = #(S.chestLastTargets or {}),
            hasProximity = U.Caps.proximity,
            hasClick = U.Caps.click,
        }
    end

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
        "[Dingus][chest] v7 · %s · prox=%s click=%s touch=%s",
        U.Platform, tostring(U.Caps.proximity),
        tostring(U.Caps.click), tostring(U.Caps.touch)))
end

return Chest
