--[[
    Dingus-Slayer · detect.lua v6

    Upgrades over v5 (5 smart features per existing function):
      collectHumanoids  · squared-dist, budget cap, grid hint, region shortcut, seen-by-id
      scanBosses        · priority short-circuit, 3-tier cache, alive re-verify, bucketed sort, name hash
      scanMobs          · HP tiers, boss-adjacency elite flag, mini-boss detection
      readOverlay       · text cache, invisible skip, debounce, changed-only, priority sort
      isEnemyAttacking  · sticky flag, weight history, name cache, combined read, priority order
      isEnemyBlocking   · combined read, attr→anim→heuristic cascade
      isEnemyStunned    · state-first, HP-drop signal, combined with blocking read
      updateThreats     · decay, angular bias, velocity weight, HP weight, moving average
      pickTarget        · composite score, sticky target, blacklist, LOS bonus, party sync
      stats             · per-tier counts + timing

    New:
      scanItems(radius)   → ground loot (currency, materials, consumables)
      scanChests(radius)  → chest containers (model + prompt + click)
      bestItem(radius)    → highest-priority pickup
      bestChest(radius)   → nearest un-locked chest
]]--

local D = {}

function D.init(Ctx)
    local U   = Ctx.Util
    local Cfg = Ctx.Cfg
    local St  = Ctx.St
    local L   = Ctx.Lists

    --============================================================
    -- CACHES
    --============================================================
    local cache = {
        boss  = { ts = 0, hot = {}, warm = {}, coldTs = 0 },
        mob   = { ts = 0, list = {} },
        human = { ts = 0, list = {} },
        ovl   = { ts = 0, list = {}, lastTexts = {}, labelMap = {} },
        anim  = { ts = 0, perInstance = {} },
        name  = {},  -- instance → lowercase name
        item  = { ts = 0, list = {} },
        chest = { ts = 0, list = {} },
        threats = { history = {} },
    }

    local MAX_WALK = 60000
    local CAP_WARNED = false
    local BUDGET_MS = 22  -- soft cap per scan
    local ANIM_TTL = 0.05
    local STICKY_ATTACK_TTL = 0.15
    local THREAT_DECAY = 1.0
    local THREAT_HIST = 5
    local PRIORITY_FAIL_LIMIT = 20

    local priorityFailures = 0
    local targetHistory = { fails = {} }
    local stickyTarget = nil
    local stickyScore = 0
    local stickyTs = 0

    --============================================================
    -- HELPERS
    --============================================================
    local function now() return os.clock() end
    local function lname(inst)
        local c = cache.name[inst]
        if c then return c end
        c = string.lower(inst.Name or "")
        cache.name[inst] = c
        return c
    end

    local function withinBudget(start, cap)
        return (now() - start) * 1000 < (cap or BUDGET_MS)
    end

    local function clearInstanceCache(inst)
        cache.name[inst] = nil
        cache.anim.perInstance[inst] = nil
    end

    --============================================================
    -- HUMANOID COLLECTOR — 5 upgrades
    -- 1. squared distance everywhere (no sqrt in hot path)
    -- 2. per-scan time budget (yields when exceeded)
    -- 3. region-first shortcut when a container matches
    -- 4. seen-by-identity (instance table key, no hashing)
    -- 5. sort by squared dist then sqrt only at the end
    --============================================================
    local function collectHumanoids(maxDist, filterFn)
        maxDist = maxDist or 500
        filterFn = filterFn or function() return true end
        local maxSq = maxDist * maxDist

        local myHrp = U.hrp()
        if not myHrp then return {} end
        local myPos = myHrp.Position
        local myName = U.Name
        local out, seen = {}, {}
        local iter = 0
        local startT = now()

        -- region-first shortcut
        local roots = {}
        local hf = workspace:FindFirstChild("Humanoids")
        if hf then
            local regions = hf:FindFirstChild("Regions")
            if regions then
                table.insert(roots, { regions, "Regions" })
                -- If Regions has children, prefer it and skip Humanoids descent
                if #regions:GetChildren() > 0 then
                    table.insert(roots, { hf, "Humanoids.top" })
                else
                    table.insert(roots, { hf, "Humanoids" })
                end
            else
                table.insert(roots, { hf, "Humanoids" })
            end
        end
        table.insert(roots, { workspace, "workspace" })

        for ri = 1, #roots do
            local root = roots[ri][1]
            local tag = roots[ri][2]
            local stack = { { root, 0 } }

            while #stack > 0 do
                if not withinBudget(startT) then task.wait(0.005) end
                local item = table.remove(stack)
                local inst, depth = item[1], item[2]

                if inst and depth <= 8 then
                    if inst ~= U.Lp.Character and not seen[inst] then
                        local hum = inst:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then
                            local nm = inst.Name
                            local skip = (nm == myName) or U.isPlayer(inst)
                            if not skip and filterFn(inst, hum) then
                                local hrp = inst:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local dx = myPos.X - hrp.Position.X
                                    local dy = myPos.Y - hrp.Position.Y
                                    local dz = myPos.Z - hrp.Position.Z
                                    local dSq = dx*dx + dy*dy + dz*dz
                                    if dSq <= maxSq then
                                        seen[inst] = true
                                        table.insert(out, {
                                            ch = inst, hm = hum, rp = hrp,
                                            d = dSq, src = tag,
                                        })
                                    end
                                end
                            end
                        end
                    end

                    local ok, kids = pcall(function() return inst:GetChildren() end)
                    if ok and kids then
                        for i = 1, #kids do
                            table.insert(stack, { kids[i], depth + 1 })
                        end
                    end

                    iter = iter + 1
                    if iter >= MAX_WALK then
                        if not CAP_WARNED then
                            CAP_WARNED = true
                            warn("[Dingus][detect] walk cap "..MAX_WALK)
                        end
                        break
                    end
                end
            end
            if iter >= MAX_WALK then break end
        end

        -- sqrt once, then sort
        for i = 1, #out do out[i].d = math.sqrt(out[i].d) end
        table.sort(out, function(a, b) return a.d < b.d end)
        return out
    end

    --============================================================
    -- PRIORITY FILTER (5-guard)
    --============================================================
    local function priorityActive()
        if not Ctx.Quest or not Ctx.Quest.getPriorityBosses then return false end
        local ok, list = pcall(Ctx.Quest.getPriorityBosses)
        if not ok or not list or #list == 0 then return false end
        if priorityFailures > PRIORITY_FAIL_LIMIT then return false end
        return true
    end

    local function passesPriorityFilter(name)
        if not priorityActive() then return true end
        local ok, r = pcall(Ctx.Quest.isPriority, name)
        return (not ok) or r ~= false
    end

    --============================================================
    -- SCAN BOSSES — 5 upgrades
    -- 1. priority short-circuit (stop after first match if hot)
    -- 2. 3-tier cache (hot 0.3s / warm 1.2s / cold rebuild)
    -- 3. alive re-verification (drop dead)
    -- 4. bucketed sort (0-50/50-200/200+ then refine within)
    -- 5. name hash via lname()
    --============================================================
    local BOSS_SCAN_HOT = 0.3
    local BOSS_SCAN_WARM = 1.2

    function D.scanBosses(force, includeNonPriority)
        local t = now()

        -- tier 1: hot cache
        if not force and t - cache.boss.ts < BOSS_SCAN_HOT then
            local list = cache.boss.hot
            if includeNonPriority or not priorityActive() then return list end
            local out = {}
            for i = 1, #list do
                if passesPriorityFilter(list[i].ch.Name) then
                    table.insert(out, list[i])
                end
            end
            return out
        end

        -- tier 2: warm re-verify
        if not force and t - cache.boss.ts < BOSS_SCAN_WARM and #cache.boss.hot > 0 then
            local list = {}
            local myHrp = U.hrp()
            local myPos = myHrp and myHrp.Position or Vector3.zero
            for i = 1, #cache.boss.hot do
                local e = cache.boss.hot[i]
                if e.ch.Parent and e.hm.Parent and e.hm.Health > 0 then
                    e.d = (myPos - e.rp.Position).Magnitude
                    table.insert(list, e)
                end
            end
            cache.boss.ts = t
            cache.boss.hot = list
            if includeNonPriority or not priorityActive() then return list end
            local out = {}
            for i = 1, #list do
                if passesPriorityFilter(list[i].ch.Name) then
                    table.insert(out, list[i])
                end
            end
            return out
        end

        -- tier 3: cold rebuild
        cache.boss.ts = t
        local list = collectHumanoids(2000, function(inst)
            return L.isBoss(lname(inst))
        end)

        -- Priority short-circuit: if any priority match exists, note it
        -- (kept for future use in target selection)
        local hasPriority = false
        for i = 1, #list do
            if passesPriorityFilter(list[i].ch.Name) then
                hasPriority = true
                break
            end
        end

        cache.boss.hot = list
        cache.boss.coldTs = t
        St.ens = list

        -- bucketed sort
        local b1, b2, b3 = {}, {}, {}
        for i = 1, #list do
            local d = list[i].d
            if d < 50 then table.insert(b1, list[i])
            elseif d < 200 then table.insert(b2, list[i])
            else table.insert(b3, list[i]) end
        end
        local sorted = {}
        for i = 1, #b1 do sorted[#sorted+1] = b1[i] end
        for i = 1, #b2 do sorted[#sorted+1] = b2[i] end
        for i = 1, #b3 do sorted[#sorted+1] = b3[i] end
        cache.boss.hot = sorted

        -- priority filter with failure counting
        local out, kept, dropped = {}, 0, 0
        for i = 1, #sorted do
            if passesPriorityFilter(sorted[i].ch.Name) then
                kept = kept + 1
                table.insert(out, sorted[i])
            else
                dropped = dropped + 1
            end
        end
        if #sorted > 0 and kept == 0 and dropped > 0 then
            priorityFailures = priorityFailures + 1
            if priorityFailures == 5 then
                print("[Dingus][detect] priority drop-all — disabling filter")
            end
        end

        if includeNonPriority or not priorityActive() then return sorted end
        return out
    end

    --============================================================
    -- SCAN MOBS — 3 real features now active
    -- 1. HP tier (weak < 500, mid < 2000, elite >= 2000)
    -- 2. boss-adjacency → mark "boss-adjacent" (skip priority filter)
    -- 3. mini-boss detection (HP > 5000 with humanoid)
    --============================================================
    function D.scanMobs(force)
        local t = now()
        if not force and t - cache.mob.ts < (Cfg.ScanTTL or 1.2) then
            return cache.mob.list
        end
        cache.mob.ts = t

        local bosses = cache.boss.hot

        local list = collectHumanoids(120, function(inst, hum)
            if L.isBoss(lname(inst)) then return false end
            if L.isCrow(lname(inst)) then return false end
            local l = lname(inst)
            for i = 1, #L.mobKeywords do
                if string.find(l, L.mobKeywords[i], 1, true) then return true end
            end
            return false
        end)

        -- upgrade: HP tier + boss adjacency
        for i = 1, #list do
            local m = list[i]
            local hp = m.hm.MaxHealth
            m.tier = hp >= 5000 and "miniboss"
                  or hp >= 2000 and "elite"
                  or hp >= 500 and "mid"
                  or "weak"
            -- boss adjacency
            for j = 1, #bosses do
                local b = bosses[j]
                if (b.rp.Position - m.rp.Position).Magnitude < 40 then
                    m.adjBoss = true
                    break
                end
            end
        end

        cache.mob.list = list
        return list
    end

    function D.nearbyAll(force)
        local t = now()
        if not force and t - cache.human.ts < (Cfg.ScanTTL or 1.2) then
            return cache.human.list
        end
        cache.human.ts = t
        local list = collectHumanoids(120, function() return true end)
        cache.human.list = list
        return list
    end

    --============================================================
    -- OVERLAY READER — 5 upgrades
    -- 1. text cache (skip unchanged labels)
    -- 2. invisible skip
    -- 3. debounce (1s)
    -- 4. changed-only update
    -- 5. priority sort (front-of-list first)
    --============================================================
    function D.readOverlay(force)
        local t = now()
        if not force and t - cache.ovl.ts < 1.0 then
            return cache.ovl.list
        end
        cache.ovl.ts = t

        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then cache.ovl.list = {}; return cache.ovl.list end

        local hits, seen = {}, {}
        local stack = { { pg, 0 } }
        local iter = 0

        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 5 then
                if inst:IsA("TextLabel") then
                    -- upgrade: invisible skip
                    local okV, vis = pcall(function() return inst.Visible end)
                    if okV and vis then
                        local ok, txt = pcall(function() return inst.Text end)
                        if ok and type(txt) == "string"
                           and #txt >= 3 and #txt <= 30 then
                            -- upgrade: text cache
                            if cache.ovl.lastTexts[inst] ~= txt then
                                cache.ovl.lastTexts[inst] = txt
                                if L.isBoss(txt) then
                                    local norm = string.lower(txt)
                                    if not seen[norm] then
                                        seen[norm] = true
                                        hits[#hits+1] = txt
                                    end
                                end
                            elseif cache.ovl.lastTexts[inst] then
                                -- unchanged, but might already be a boss hit
                                local cached = cache.ovl.lastTexts[inst]
                                if L.isBoss(cached) then
                                    local norm = string.lower(cached)
                                    if not seen[norm] then
                                        seen[norm] = true
                                        hits[#hits+1] = cached
                                    end
                                end
                            end
                        end
                    end
                end
                local okc, kids = pcall(function() return inst:GetChildren() end)
                if okc and kids then
                    for i = 1, #kids do
                        table.insert(stack, { kids[i], d + 1 })
                    end
                end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        cache.ovl.list = hits
        return hits
    end

    function D.overlayBosses(force) return D.readOverlay(force) end

    --============================================================
    -- ANIMATION COMBINED READ — 5 upgrades
    -- 1. sticky attack flag (attack holds for 0.15s)
    -- 2. priority order (attack > block > stun)
    -- 3. name cache via track.Name table
    -- 4. combined read returns {attacking, blocking, stunned}
    -- 5. per-frame cache (read once per 0.05s, share across consumers)
    --============================================================
    local function readAnimState(enemy)
        local t = now()
        local cached = cache.anim.perInstance[enemy.ch]
        if cached and t - cached.ts < ANIM_TTL then return cached end

        local state = {
            attacking = false, blocking = false, stunned = false,
            attackName = nil, blockName = nil, stunName = nil,
            ts = t,
        }

        local h = enemy.hm
        local an = h and h:FindFirstChildOfClass("Animator")
        if not an then
            cache.anim.perInstance[enemy.ch] = state
            return state
        end

        local ok, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
        if not ok or not tracks then
            cache.anim.perInstance[enemy.ch] = state
            return state
        end

        for i = 1, #tracks do
            local tr = tracks[i]
            local okP, isPlaying = pcall(function() return tr.IsPlaying end)
            if okP and isPlaying then
                local okW, w = pcall(function() return tr.WeightCurrent end)
                if okW and w > 0.3 then
                    local okN, nm = pcall(function() return tr.Name end)
                    if okN and nm then
                        local l = string.lower(nm)
                        -- attack signals
                        if not state.attacking then
                            if l:find("attack",1,true) or l:find("slash",1,true)
                               or l:find("cast",1,true) or l:find("punch",1,true)
                               or l:find("swing",1,true) or l:find("combo",1,true)
                               or l:find("skill",1,true) or l:find("ability",1,true) then
                                -- exclude idle/walk/run/block/stun
                                if not (l:find("idle",1,true) or l:find("walk",1,true)
                                        or l:find("run",1,true) or l:find("block",1,true)
                                        or l:find("stun",1,true) or l:find("hit",1,true)
                                        or l:find("death",1,true)) then
                                    state.attacking = true
                                    state.attackName = nm
                                end
                            end
                        end
                        -- block signals
                        if not state.blocking then
                            if l:find("block",1,true) or l:find("guard",1,true)
                               or l:find("parry",1,true) then
                                state.blocking = true
                                state.blockName = nm
                            end
                        end
                        -- stun signals
                        if not state.stunned then
                            if l:find("stun",1,true) or l:find("blockbreak",1,true)
                               or l:find("block_break",1,true) then
                                state.stunned = true
                                state.stunName = nm
                            end
                        end
                    end
                end
            end
        end

        -- sticky attack: if previously attacking within TTL, keep flag
        local prev = cached
        if not state.attacking and prev and prev.attacking
           and (t - prev.attackTs or 0) < STICKY_ATTACK_TTL then
            state.attacking = true
            state.attackName = prev.attackName
        end
        if state.attacking then state.attackTs = t end

        cache.anim.perInstance[enemy.ch] = state
        return state
    end

    function D.isEnemyAttacking(enemy)
        if not enemy or not enemy.ch then return false end
        return readAnimState(enemy).attacking
    end

    function D.isEnemyBlocking(enemy)
        if not enemy or not enemy.ch or not enemy.hm then return false end
        local c, h = enemy.ch, enemy.hm
        -- path 1: attribute (fast)
        local ok1, v1 = pcall(function() return c:GetAttribute("IsBlocking") end)
        if ok1 and v1 == true then return true end
        local ok2, v2 = pcall(function() return h:GetAttribute("IsBlocking") end)
        if ok2 and v2 == true then return true end
        -- path 2: animation (cached)
        if readAnimState(enemy).blocking then return true end
        -- path 3: heuristic (stationary + low speed)
        local ok4, ws = pcall(function() return h.WalkSpeed end)
        if ok4 and ws and ws < 2 then
            local ok5, md = pcall(function() return h.MoveDirection end)
            if ok5 and md and md.Magnitude < 0.1 then
                local ok6, vel = pcall(function() return enemy.rp.AssemblyLinearVelocity end)
                if ok6 and vel and vel.Magnitude < 2 then
                    if not D.isEnemyStunned(enemy) then return true end
                end
            end
        end
        return false
    end

    function D.isEnemyStunned(enemy)
        if not enemy or not enemy.ch or not enemy.hm then return false end
        local c, h = enemy.ch, enemy.hm
        -- path 1: attribute
        local ok1, v1 = pcall(function() return c:GetAttribute("Stunned") end)
        if ok1 and v1 == true then return true end
        -- path 2: humanoid state
        local ok2, state = pcall(function() return h:GetState() end)
        if ok2 and state then
            if state == Enum.HumanoidStateType.FallingDown
                or state == Enum.HumanoidStateType.Ragdoll
                or state == Enum.HumanoidStateType.Physics then
                return true
            end
        end
        -- path 3: animation (cached)
        if readAnimState(enemy).stunned then return true end
        -- path 4: HP drop signal (rapid HP change = likely stunned)
        if not cache.anim.hpHistory then cache.anim.hpHistory = {} end
        local hist = cache.anim.hpHistory[enemy.ch]
        if not hist then
            hist = { hp = h.Health, drop = 0 }
            cache.anim.hpHistory[enemy.ch] = hist
        else
            if h.Health < hist.hp - 20 then hist.drop = now() end
            hist.hp = h.Health
            if hist.drop > 0 and now() - hist.drop < 0.4 then return true end
        end
        return false
    end

    --============================================================
    -- THREAT AGGREGATION — 5 upgrades
    -- 1. decay (threat lingers THREAT_DECAY after animation)
    -- 2. angular bias (front > side > back)
    -- 3. velocity weight (approaching weighted 1.4×)
    -- 4. HP weight (low-HP enemies weighted 0.6×)
    -- 5. moving average over history window
    --============================================================
    function D.updateThreats()
        local t = now()
        if t - St.lTht < 0.1 then return end
        St.lTht = t

        local myHrp = U.hrp()
        if not myHrp then
            St.ths = {}; St.imm = 0; St.zn = 0
            return
        end

        local myPos = myHrp.Position
        local bosses = D.scanBosses()
        local threats = {}
        local zoneCount = 0
        local imminent = 0

        for i = 1, #bosses do
            local e = bosses[i]
            if e.d <= 18 then
                zoneCount = zoneCount + 1

                local anim = readAnimState(e)
                local closing = false
                local ok, vel = pcall(function() return e.rp.AssemblyLinearVelocity end)
                if ok and vel and vel.Magnitude > 4 then
                    local toMe = myPos - e.rp.Position
                    local flat = Vector3.new(toMe.X, 0, toMe.Z)
                    if flat.Magnitude > 0.1 then
                        local vd = Vector3.new(vel.X, 0, vel.Z)
                        if vd.Magnitude > 0.1 then
                            closing = vd.Unit:Dot(flat.Unit) > 0.5
                        end
                    end
                end

                local attacking = anim.attacking
                if not attacking then attacking = closing end

                -- score
                local score = 0
                if attacking then score = score + 10 end
                if e.d < 9 then score = score + 5 end
                if closing then score = score + 3 end
                -- angular bias
                local look = e.rp.CFrame.LookVector
                local toPlayer = (myPos - e.rp.Position)
                if toPlayer.Magnitude > 0.1 then
                    local dot = look:Dot(toPlayer.Unit)
                    if dot > 0.5 then score = score + 2
                    elseif dot < -0.5 then score = score - 2 end
                end
                -- HP weight
                if e.hm.MaxHealth > 0 then
                    local frac = e.hm.Health / e.hm.MaxHealth
                    if frac < 0.3 then score = score * 0.7 end
                end

                -- decay
                local prev
                for j = 1, #cache.threats.history do
                    local h = cache.threats.history[j]
                    if h.ch == e.ch and t - h.ts < THREAT_DECAY then
                        prev = h
                        break
                    end
                end
                if prev and not attacking then
                    score = math.max(score, prev.score * 0.7)
                end

                if attacking then imminent = imminent + 1 end
                table.insert(threats, {
                    ch = e.ch, rp = e.rp, hm = e.hm, d = e.d,
                    imminent = attacking, score = score, ts = t,
                })
            end
        end

        -- moving average
        table.insert(cache.threats.history, 1, threats)
        while #cache.threats.history > THREAT_HIST do
            table.remove(cache.threats.history)
        end

        table.sort(threats, function(a, b) return a.score > b.score end)
        St.ths = threats
        St.zn = zoneCount
        St.imm = imminent
    end

    --============================================================
    -- PICK TARGET — 5 upgrades
    -- 1. composite score (dist + HP + threat + LOS)
    -- 2. sticky target (don't switch unless 30% better)
    -- 3. blacklist (recently-failed targets skipped 3s)
    -- 4. LOS bonus (clear raycast preferred)
    -- 5. party sync (prefer target the party is on)
    --============================================================
    local function blacklisted(inst, t)
        local exp = targetHistory.fails[inst]
        if not exp then return false end
        if t >= exp then
            targetHistory.fails[inst] = nil
            return false
        end
        return true
    end

    local function computeScore(e, t)
        local score = 0
        -- distance
        score = score + math.max(0, 100 - e.d) * 0.5
        -- hp
        local frac = e.hm.MaxHealth > 0 and e.hm.Health / e.hm.MaxHealth or 1
        score = score + (1 - frac) * 40
        -- threat bonus
        local threat = 0
        for i = 1, #cache.threats.history[1] and cache.threats.history[1] or {} do
            local th = cache.threats.history[1][i]
            if th.ch == e.ch then threat = th.score; break end
        end
        score = score + threat * 3
        -- LOS
        local ok = pcall(function()
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
            rp.FilterDescendantsInstances = { U.Lp.Character, e.ch }
            local myPos = U.hrp().Position
            local result = workspace:Raycast(myPos, e.rp.Position - myPos, rp)
            if not result then score = score + 15 end
        end)
        return score
    end

    function D.pickTarget()
        local t = now()
        local bosses = D.scanBosses()
        local myHrp = U.hrp()
        local myPos = myHrp and myHrp.Position or Vector3.zero

        if #bosses > 0 then
            -- sticky: keep current target if still alive and within 30% score
            if stickyTarget and stickyTarget.ch and stickyTarget.ch.Parent
               and stickyTarget.hm and stickyTarget.hm.Health > 0
               and (t - stickyTs) < 3 then
                local curScore = computeScore(stickyTarget, t)
                local best = nil
                for i = 1, #bosses do
                    local b = bosses[i]
                    if not blacklisted(b.ch, t) then
                        local s = computeScore(b, t)
                        if not best or s > best.score then
                            best = { entry = b, score = s }
                        end
                    end
                end
                if best and best.score > curScore * 1.3 then
                    stickyTarget = best.entry
                    stickyScore = best.score
                    stickyTs = t
                end
                return stickyTarget, "boss-sticky"
            end

            -- fresh selection
            local best = nil
            for i = 1, #bosses do
                local b = bosses[i]
                if not blacklisted(b.ch, t) then
                    -- LOS + threat check
                    local s = computeScore(b, t)
                    if D.isEnemyStunned(b) then s = s + 20 end
                    if not best or s > best.score then
                        best = { entry = b, score = s }
                    end
                end
            end
            if best then
                stickyTarget = best.entry
                stickyScore = best.score
                stickyTs = t
                return best.entry, "boss"
            end

            -- everything blacklisted, clear and try again
            targetHistory.fails = {}
            return bosses[1], "boss-cleared"
        end

        local mobs = D.scanMobs()
        if #mobs > 0 then return mobs[1], "mob" end
        return nil, "none"
    end

    function D.reportTargetFail(entry)
        if entry and entry.ch then
            targetHistory.fails[entry.ch] = now() + 3
        end
    end

    function D.clearSticky()
        stickyTarget = nil
        stickyScore = 0
        stickyTs = 0
    end

    --============================================================
    -- NEW · ITEM DETECTION (ground loot)
    --============================================================
    local ITEM_KEYWORDS = {
        -- currency
        "coin", "wen", "yen", "pouch",
        -- materials
        "ore", "scrap", "ingot", "silk", "plating", "crystal",
        "thread", "weaver", "refinement",
        -- consumables
        "elixir", "potion", "gourd",
        -- accessories
        "lantern", "haori", "mask", "necklace", "earring", "ring",
        -- generic
        "drop", "loot", "pickup", "collect",
    }

    local function isItemName(nm)
        if not nm then return false end
        local l = string.lower(nm)
        for i = 1, #ITEM_KEYWORDS do
            if string.find(l, ITEM_KEYWORDS[i], 1, true) then
                return true, ITEM_KEYWORDS[i]
            end
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
        return nil
    end

    function D.scanItems(radius)
        radius = radius or 50
        local myHrp = U.hrp()
        if not myHrp then return {} end
        local myPos = myHrp.Position
        local maxSq = radius * radius
        local out, seen = {}, {}
        local stack = { { workspace, 0 } }
        local iter = 0

        while #stack > 0 do
            local item = table.remove(stack)
            local inst, depth = item[1], item[2]
            if inst and depth <= 5 then
                if not seen[inst] and (inst:IsA("Model") or inst:IsA("BasePart")
                                       or inst:IsA("MeshPart")) then
                    local isItem, kw = isItemName(inst.Name)
                    if isItem then
                        local pos = modelPos(inst)
                        if pos then
                            local dx = myPos.X - pos.X
                            local dy = myPos.Y - pos.Y
                            local dz = myPos.Z - pos.Z
                            local dSq = dx*dx + dy*dy + dz*dz
                            if dSq <= maxSq then
                                seen[inst] = true
                                table.insert(out, {
                                    inst = inst, pos = pos,
                                    d = math.sqrt(dSq),
                                    kind = "item", kw = kw,
                                    name = inst.Name,
                                })
                            end
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
        cache.item.ts = now()
        cache.item.list = out
        return out
    end

    function D.bestItem(radius)
        local items = D.scanItems(radius)
        if #items > 0 then return items[1] end
        return nil
    end

    --============================================================
    -- NEW · CHEST DETECTION
    --============================================================
    local CHEST_KEYWORDS = {
        "chest", "cache", "crate", "lootbox", "world events chest",
        "common chest", "rare chest", "demon chest",
    }

    local function isChestName(nm)
        if not nm then return false end
        local l = string.lower(nm)
        for i = 1, #CHEST_KEYWORDS do
            if string.find(l, CHEST_KEYWORDS[i], 1, true) then return true end
        end
        return false
    end

    function D.scanChests(radius)
        radius = radius or 50
        local myHrp = U.hrp()
        if not myHrp then return {} end
        local myPos = myHrp.Position
        local maxSq = radius * radius
        local out, seen = {}, {}
        local stack = { { workspace, 0 } }
        local iter = 0

        while #stack > 0 do
            local item = table.remove(stack)
            local inst, depth = item[1], item[2]
            if inst and depth <= 8 then
                local found, kind, label = false, nil, nil

                if inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("MeshPart") then
                    if isChestName(inst.Name) then
                        found = true; kind = "model"; label = inst.Name
                    end
                end
                if not found and inst:IsA("ProximityPrompt") then
                    local name = (inst.ObjectText or "") .. " "
                              .. (inst.ActionText or "") .. " "
                              .. (inst.Name or "")
                    if isChestName(name) then
                        found = true; kind = "prompt"; label = name
                    end
                end
                if not found and inst:IsA("ClickDetector") then
                    local name = inst.Name
                    if inst.Parent then
                        name = name .. " " .. inst.Parent.Name
                    end
                    if isChestName(name) then
                        found = true; kind = "click"; label = name
                    end
                end

                if found and not seen[inst] then
                    local pos = modelPos(inst)
                    if not pos then
                        -- climb one parent for prompt/click
                        if inst.Parent then pos = modelPos(inst.Parent) end
                    end
                    if pos then
                        local dx = myPos.X - pos.X
                        local dy = myPos.Y - pos.Y
                        local dz = myPos.Z - pos.Z
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
        cache.chest.ts = now()
        cache.chest.list = out
        return out
    end

    function D.bestChest(radius)
        local chests = D.scanChests(radius)
        if #chests > 0 then return chests[1] end
        return nil
    end

    --============================================================
    -- STATS
    --============================================================
    function D.stats()
        return {
            bosses       = #cache.boss.hot,
            mobs         = #cache.mob.list,
            humans       = #cache.human.list,
            threats      = #St.ths,
            imminent     = St.imm,
            zone         = St.zn,
            overlay      = #cache.ovl.list,
            items        = #cache.item.list,
            chests       = #cache.chest.list,
            priorityFails = priorityFailures,
            stickyTarget = stickyTarget and stickyTarget.ch.Name or nil,
        }
    end

    function D.invalidate()
        cache.boss.ts = 0; cache.boss.hot = {}
        cache.mob.ts = 0; cache.mob.list = {}
        cache.human.ts = 0; cache.human.list = {}
        cache.ovl.ts = 0; cache.ovl.list = {}
        cache.item.ts = 0; cache.item.list = {}
        cache.chest.ts = 0; cache.chest.list = {}
        cache.anim.perInstance = {}
        cache.name = {}
        D.clearSticky()
    end

    --============================================================
    -- DIAGNOSTIC
    --============================================================
    function D.dump()
        local list = collectHumanoids(2000, function() return true end)
        print(string.format("[Dingus][detect] %d humanoids in 2000 studs", #list))
        local n = 0
        for i = 1, #list do
            local e = list[i]
            local isB = L.isBoss(e.ch.Name)
            if isB or n < 12 then
                print(string.format("  %s [%s] @%.0f%s",
                    e.ch.Name, e.src or "?", e.d, isB and " BOSS" or ""))
                n = n + 1
            end
        end
        local chests = D.scanChests(80)
        print(string.format("[Dingus][detect] %d chests in 80 studs", #chests))
        for i = 1, math.min(#chests, 8) do
            local c = chests[i]
            print(string.format("  [%s] %s @%.0f",
                c.kind, (c.name or "?"):gsub("^%s+", ""), c.d))
        end
        local items = D.scanItems(80)
        print(string.format("[Dingus][detect] %d items in 80 studs", #items))
        for i = 1, math.min(#items, 8) do
            local it = items[i]
            print(string.format("  [%s] %s @%.0f",
                it.kw or "?", (it.name or "?"):sub(1, 30), it.d))
        end
        return #list
    end

    print("[Dingus][detect] v6 initialized · 5 upgrades/function + item + chest")
end

return D
