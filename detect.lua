-- Dingus-Slayer · detect.lua v9
-- Same walker. Mobile-friendly yields.

local D = {}

function D.init(Ctx)
    local U, F, S, L = Ctx.Util, Ctx.Cfg, Ctx.St, Ctx.Lists

    local cache = {
        boss={ts=0,hot={}}, mob={ts=0,list={}}, human={ts=0,list={}},
        ovl={ts=0,list={}}, anim={ts=0,perInstance={}}, name={},
        item={ts=0,list={}}, chest={ts=0,list={}}, threats={history={}},
    }

    D.walkStats = {}

    local MAX_DEPTH = 8
    local PER_ROOT_MS = 800
    local TOTAL_SCAN_MS = 2500
    local MAX_ITER_ROOT = 40000
    local YIELD_EVERY = U.IsMobile and 500 or 2000 -- smaller yields on mobile
    local BOSS_SCAN_HOT = 0.3
    local BOSS_SCAN_WARM = 1.2
    local ANIM_TTL = 0.05
    local STICKY_ATTACK_TTL = 0.15
    local PRIORITY_FAIL_LIMIT = 20

    local priorityFailures = 0
    local targetHistory = { fails = {} }
    local stickyTarget, stickyScore, stickyTs = nil, 0, 0

    local function now() return os.clock() end

    local function lname(inst)
        local c = cache.name[inst]
        if c then return c end
        c = string.lower(inst.Name or "")
        cache.name[inst] = c
        return c
    end

    local CONTAINER_NAMES = {
        "Humanoids","NPCs","Enemies","Mobs","Entities","Units",
        "Characters","Monsters",
    }

    local function buildRoots()
        local roots = {}
        local seenRoot = {}
        local hf = workspace:FindFirstChild("Humanoids")
        if hf then
            local regions = hf:FindFirstChild("Regions")
            if regions then
                table.insert(roots, { regions, "Humanoids.Regions" }); seenRoot[regions]=true
            end
            table.insert(roots, { hf, "Humanoids" }); seenRoot[hf]=true
        end
        for _, name in ipairs(CONTAINER_NAMES) do
            if name ~= "Humanoids" then
                local c = workspace:FindFirstChild(name)
                if c and not seenRoot[c] then
                    table.insert(roots, { c, name }); seenRoot[c]=true
                end
            end
        end
        table.insert(roots, { workspace, "workspace" })
        return roots
    end

    local function bfsWalk(root, tag, maxIter, out, seen, myPos, myName, maxSq, filterFn, totalDeadline)
        local startT = now()
        local queue = { { root, 0 } }
        local head = 1
        local iter = 0
        local hits = 0

        while head <= #queue do
            if (now() - startT) * 1000 > PER_ROOT_MS then break end
            if now() > totalDeadline then break end
            if iter >= maxIter then break end

            local item = queue[head]; head = head + 1
            local inst, depth = item[1], item[2]
            if inst and depth <= MAX_DEPTH then
                if inst ~= U.Lp.Character and not seen[inst] then
                    local hum = inst:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        local nm = inst.Name
                        if nm ~= myName then
                            local isP = false
                            if inst:FindFirstChild("Head") then isP = U.isPlayer(inst) end
                            if not isP and filterFn(inst, hum) then
                                local hrp = inst:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local dx = myPos.X - hrp.Position.X
                                    local dy = myPos.Y - hrp.Position.Y
                                    local dz = myPos.Z - hrp.Position.Z
                                    local dSq = dx*dx + dy*dy + dz*dz
                                    if dSq <= maxSq then
                                        seen[inst] = true
                                        hits = hits + 1
                                        table.insert(out, { ch=inst, hm=hum, rp=hrp, d=dSq, src=tag })
                                    end
                                end
                            end
                        end
                    end
                    if depth < MAX_DEPTH then
                        local ok, kids = pcall(inst.GetChildren, inst)
                        if ok and kids then
                            for i = 1, #kids do queue[#queue+1] = { kids[i], depth+1 } end
                        end
                    end
                    iter = iter + 1
                    if iter % YIELD_EVERY == 0 then task.wait() end
                end
            end
        end
        return hits, iter, math.floor((now() - startT) * 1000)
    end

    local function collectHumanoids(maxDist, filterFn)
        maxDist = maxDist or 2000
        filterFn = filterFn or function() return true end
        local maxSq = maxDist * maxDist
        local myHrp = U.hrp(); if not myHrp then return {} end
        local myPos = myHrp.Position
        local myName = U.Name
        local out, seen = {}, {}
        local totalStart = now()
        local totalDeadline = totalStart + TOTAL_SCAN_MS / 1000
        local roots = buildRoots()
        local perRootIter = math.floor(MAX_ITER_ROOT / math.max(1, #roots))
        local stats = {}
        for ri = 1, #roots do
            local root, tag = roots[ri][1], roots[ri][2]
            local hits, iter, ms = bfsWalk(root, tag, perRootIter, out, seen, myPos, myName, maxSq, filterFn, totalDeadline)
            stats[tag] = { iter=iter, hits=hits, ms=ms }
            if now() > totalDeadline then stats[tag].cut = true; break end
        end
        D.walkStats = stats
        for i = 1, #out do out[i].d = math.sqrt(out[i].d) end
        table.sort(out, function(a, b) return a.d < b.d end)
        return out
    end

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

    function D.scanBosses(force, includeNonPriority)
        local t = now()
        if not force and t - cache.boss.ts < BOSS_SCAN_HOT then
            local list = cache.boss.hot
            if includeNonPriority or not priorityActive() then return list end
            local out = {}
            for i = 1, #list do
                if passesPriorityFilter(list[i].ch.Name) then table.insert(out, list[i]) end
            end
            return out
        end
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
                if passesPriorityFilter(list[i].ch.Name) then table.insert(out, list[i]) end
            end
            return out
        end
        cache.boss.ts = t
        local list = collectHumanoids(2000, function(inst) return L.isBoss(lname(inst)) end)
        cache.boss.hot = list
        S.ens = list
        local kept, dropped = 0, 0
        local out = {}
        for i = 1, #list do
            if passesPriorityFilter(list[i].ch.Name) then
                kept = kept + 1; table.insert(out, list[i])
            else dropped = dropped + 1 end
        end
        if #list > 0 and kept == 0 and dropped > 0 then
            priorityFailures = priorityFailures + 1
            if priorityFailures == 5 then
                print("[Dingus][detect] priority drop-all — disabling filter")
            end
        end
        if includeNonPriority or not priorityActive() then return list end
        return out
    end

    function D.scanMobs(force)
        local t = now()
        if not force and t - cache.mob.ts < (F.ScanTTL or 1.2) then return cache.mob.list end
        cache.mob.ts = t
        local bosses = cache.boss.hot
        local list = collectHumanoids(120, function(inst, hum)
            if L.isBoss(lname(inst)) then return false end
            if L.isCrow(lname(inst)) then return false end
            local l = lname(inst)
            for i = 1, #L.mobKeywords do
                if l:find(L.mobKeywords[i], 1, true) then return true end
            end
            return false
        end)
        cache.mob.list = list
        return list
    end

    function D.nearbyAll(force)
        local t = now()
        if not force and t - cache.human.ts < (F.ScanTTL or 1.2) then return cache.human.list end
        cache.human.ts = t
        local list = collectHumanoids(120, function() return true end)
        cache.human.list = list
        return list
    end

    local function readAnimState(enemy)
        local t = now()
        local cached = cache.anim.perInstance[enemy.ch]
        if cached and t - cached.ts < ANIM_TTL then return cached end
        local state = { attacking=false, blocking=false, stunned=false, ts=t }
        local h = enemy.hm
        local an = h and h:FindFirstChildOfClass("Animator")
        if an then
            local ok, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
            if ok and tracks then
                for i = 1, #tracks do
                    local tr = tracks[i]
                    local okP, ip = pcall(function() return tr.IsPlaying end)
                    if okP and ip then
                        local okW, w = pcall(function() return tr.WeightCurrent end)
                        if okW and w > 0.3 then
                            local okN, nm = pcall(function() return tr.Name end)
                            if okN and nm then
                                local l = string.lower(nm)
                                if not state.attacking and (l:find("attack",1,true) or l:find("slash",1,true)
                                   or l:find("cast",1,true) or l:find("punch",1,true)
                                   or l:find("swing",1,true) or l:find("combo",1,true)) then
                                    if not (l:find("idle") or l:find("walk") or l:find("run")) then
                                        state.attacking = true
                                    end
                                end
                                if not state.blocking and (l:find("block",1,true) or l:find("guard",1,true)) then
                                    state.blocking = true
                                end
                                if not state.stunned and (l:find("stun",1,true) or l:find("blockbreak",1,true)) then
                                    state.stunned = true
                                end
                            end
                        end
                    end
                end
            end
        end
        if not state.attacking and cached and cached.attacking
           and (t - (cached.attackTs or 0)) < STICKY_ATTACK_TTL then
            state.attacking = true
        end
        if state.attacking then state.attackTs = t end
        cache.anim.perInstance[enemy.ch] = state
        return state
    end

    function D.isEnemyAttacking(e) return e and e.ch and readAnimState(e).attacking or false end

    function D.isEnemyBlocking(enemy)
        if not enemy or not enemy.ch or not enemy.hm then return false end
        local c, h = enemy.ch, enemy.hm
        local ok1, v1 = pcall(function() return c:GetAttribute("IsBlocking") end)
        if ok1 and v1 == true then return true end
        local ok2, v2 = pcall(function() return h:GetAttribute("IsBlocking") end)
        if ok2 and v2 == true then return true end
        if readAnimState(enemy).blocking then return true end
        return false
    end

    function D.isEnemyStunned(enemy)
        if not enemy or not enemy.hm then return false end
        local ok1, v1 = pcall(function() return enemy.ch:GetAttribute("Stunned") end)
        if ok1 and v1 == true then return true end
        local ok2, st = pcall(function() return enemy.hm:GetState() end)
        if ok2 and st then
            if st == Enum.HumanoidStateType.FallingDown
               or st == Enum.HumanoidStateType.Ragdoll
               or st == Enum.HumanoidStateType.Physics then return true end
        end
        if readAnimState(enemy).stunned then return true end
        return false
    end

    function D.updateThreats()
        local t = now()
        if t - (S.lTht or 0) < 0.1 then return end
        S.lTht = t
        local myHrp = U.hrp()
        if not myHrp then S.ths={}; S.imm=0; S.zn=0; return end
        local myPos = myHrp.Position
        local bosses = D.scanBosses()
        local threats, zoneCount, imminent = {}, 0, 0
        for i = 1, #bosses do
            local e = bosses[i]
            if e.d <= 18 then
                zoneCount = zoneCount + 1
                local anim = readAnimState(e)
                local attacking = anim.attacking
                if attacking then imminent = imminent + 1 end
                table.insert(threats, { ch=e.ch, rp=e.rp, hm=e.hm, d=e.d, imminent=attacking })
            end
        end
        S.ths = threats
        S.zn = zoneCount
        S.imm = imminent
    end

    function D.pickTarget()
        local t = now()
        local bosses = D.scanBosses()
        if #bosses > 0 then
            local best
            for i = 1, #bosses do
                local b = bosses[i]
                local score = math.max(0, 100 - b.d) * 0.5
                if D.isEnemyStunned(b) then score = score + 20 end
                if not best or score > best.score then best = { entry=b, score=score } end
            end
            if best then
                stickyTarget = best.entry; stickyScore = best.score; stickyTs = t
                return best.entry, "boss"
            end
        end
        local mobs = D.scanMobs()
        if #mobs > 0 then return mobs[1], "mob" end
        return nil, "none"
    end

    function D.reportTargetFail(e) if e and e.ch then targetHistory.fails[e.ch] = now() + 3 end end
    function D.clearSticky() stickyTarget = nil end

    function D.stats()
        return {
            bosses = #cache.boss.hot, mobs = #cache.mob.list,
            humans = #cache.human.list, threats = #S.ths,
            imminent = S.imm, zone = S.zn,
        }
    end

    function D.invalidate()
        cache.boss.ts = 0; cache.boss.hot = {}
        cache.mob.ts = 0; cache.mob.list = {}
        cache.human.ts = 0; cache.human.list = {}
        cache.anim.perInstance = {}
        cache.name = {}
        D.clearSticky()
    end

    function D.dump()
        local t0 = now()
        local list = collectHumanoids(2000, function() return true end)
        local ms = math.floor((now() - t0) * 1000)
        print(string.format("[Dingus][detect] dump: %d humanoids in %dms", #list, ms))
        for tag, st in pairs(D.walkStats) do
            print(string.format("  %-22s iter=%-6d hits=%-3d ms=%-4d%s",
                tag, st.iter or 0, st.hits or 0, st.ms or 0,
                st.cut and "  [CUT]" or ""))
        end
        return #list
    end

    print(string.format(
        "[Dingus][detect] v9 · %s · yield=%d",
        U.Platform, YIELD_EVERY))
end

return D
