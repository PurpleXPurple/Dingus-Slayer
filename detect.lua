--[[
    Dingus-Slayer · detect.lua v7
    Fixes v6 per-iteration throttle. Walk covers all roots unconditionally.
    Every other v6 feature retained (squared dist, name cache, sticky, etc).
]]--

local D = {}

function D.init(Ctx)
    local U, F, S, L = Ctx.Util, Ctx.Cfg, Ctx.St, Ctx.Lists

    local cache = {
        boss  = { ts = 0, hot = {} },
        mob   = { ts = 0, list = {} },
        human = { ts = 0, list = {} },
        ovl   = { ts = 0, list = {}, lastTexts = {} },
        anim  = { ts = 0, perInstance = {} },
        name  = {},
        item  = { ts = 0, list = {} },
        chest = { ts = 0, list = {} },
        threats = { history = {} },
    }

    local MAX_WALK = 60000
    local YIELD_EVERY = 500
    local CAP_WARNED = false
    local ANIM_TTL = 0.05
    local STICKY_ATTACK_TTL = 0.15
    local PRIORITY_FAIL_LIMIT = 20
    local BOSS_SCAN_HOT = 0.3
    local BOSS_SCAN_WARM = 1.2

    local priorityFailures = 0
    local targetHistory = { fails = {} }
    local stickyTarget = nil
    local stickyScore = 0
    local stickyTs = 0

    local function now() return os.clock() end

    local function lname(inst)
        local c = cache.name[inst]
        if c then return c end
        c = string.lower(inst.Name or "")
        cache.name[inst] = c
        return c
    end

    --============================================================
    -- HUMANOID COLLECTOR · v7 batching
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

        -- Always walk all roots. No region shortcut, no early break.
        local roots = {}
        local hf = workspace:FindFirstChild("Humanoids")
        if hf then
            table.insert(roots, { hf, "Humanoids" })
            local regions = hf:FindFirstChild("Regions")
            if regions then
                table.insert(roots, { regions, "Regions" })
            end
        end
        table.insert(roots, { workspace, "workspace" })

        for ri = 1, #roots do
            local root = roots[ri][1]
            local tag = roots[ri][2]
            local stack = { { root, 0 } }

            while #stack > 0 do
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
                    -- batch yield
                    if iter % YIELD_EVERY == 0 then
                        task.wait()
                    end
                end
            end
            if iter >= MAX_WALK then break end
        end

        for i = 1, #out do out[i].d = math.sqrt(out[i].d) end
        table.sort(out, function(a, b) return a.d < b.d end)
        return out
    end

    --============================================================
    -- PRIORITY FILTER
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
    -- SCAN BOSSES
    --============================================================
    function D.scanBosses(force, includeNonPriority)
        local t = now()

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

        cache.boss.ts = t
        local list = collectHumanoids(2000, function(inst)
            return L.isBoss(lname(inst))
        end)
        cache.boss.hot = list
        S.ens = list

        local kept, dropped = 0, 0
        local out = {}
        for i = 1, #list do
            if passesPriorityFilter(list[i].ch.Name) then
                kept = kept + 1
                table.insert(out, list[i])
            else
                dropped = dropped + 1
            end
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

    --============================================================
    -- MOBS · annotated with tier and adjacency
    --============================================================
    function D.scanMobs(force)
        local t = now()
        if not force and t - cache.mob.ts < (F.ScanTTL or 1.2) then
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
        for i = 1, #list do
            local m = list[i]
            local hp = m.hm.MaxHealth
            m.tier = hp >= 5000 and "miniboss"
                  or hp >= 2000 and "elite"
                  or hp >= 500 and "mid" or "weak"
            for j = 1, #bosses do
                if (bosses[j].rp.Position - m.rp.Position).Magnitude < 40 then
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
        if not force and t - cache.human.ts < (F.ScanTTL or 1.2) then
            return cache.human.list
        end
        cache.human.ts = t
        local list = collectHumanoids(120, function() return true end)
        cache.human.list = list
        return list
    end

    --============================================================
    -- OVERLAY
    --============================================================
    function D.readOverlay(force)
        local t = now()
        if not force and t - cache.ovl.ts < 1.0 then return cache.ovl.list end
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
                    local okV, vis = pcall(function() return inst.Visible end)
                    if okV and vis then
                        local ok, txt = pcall(function() return inst.Text end)
                        if ok and type(txt) == "string"
                           and #txt >= 3 and #txt <= 30 then
                            if L.isBoss(txt) then
                                local norm = string.lower(txt)
                                if not seen[norm] then
                                    seen[norm] = true
                                    hits[#hits+1] = txt
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
                if iter % YIELD_EVERY == 0 then task.wait() end
            end
        end
        cache.ovl.list = hits
        return hits
    end

    function D.overlayBosses(force) return D.readOverlay(force) end

    --============================================================
    -- ANIMATION COMBINED READ
    --============================================================
    local function readAnimState(enemy)
        local t = now()
        local cached = cache.anim.perInstance[enemy.ch]
        if cached and t - cached.ts < ANIM_TTL then return cached end
        local state = {
            attacking=false, blocking=false, stunned=false,
            attackName=nil, blockName=nil, stunName=nil, ts=t,
        }
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
                                if not state.attacking then
                                    if l:find("attack",1,true) or l:find("slash",1,true)
                                       or l:find("cast",1,true) or l:find("punch",1,true)
                                       or l:find("swing",1,true) or l:find("combo",1,true)
                                       or l:find("skill",1,true) or l:find("ability",1,true) then
                                        if not (l:find("idle",1,true) or l:find("walk",1,true)
                                                or l:find("run",1,true) or l:find("block",1,true)
                                                or l:find("stun",1,true) or l:find("hit",1,true)
                                                or l:find("death",1,true)) then
                                            state.attacking = true
                                            state.attackName = nm
                                        end
                                    end
                                end
                                if not state.blocking then
                                    if l:find("block",1,true) or l:find("guard",1,true)
                                       or l:find("parry",1,true) then
                                        state.blocking = true; state.blockName = nm
                                    end
                                end
                                if not state.stunned then
                                    if l:find("stun",1,true) or l:find("blockbreak",1,true)
                                       or l:find("block_break",1,true) then
                                        state.stunned = true; state.stunName = nm
                                    end
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
            state.attackName = cached.attackName
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
        local ok1, v1 = pcall(function() return c:GetAttribute("IsBlocking") end)
        if ok1 and v1 == true then return true end
        local ok2, v2 = pcall(function() return h:GetAttribute("IsBlocking") end)
        if ok2 and v2 == true then return true end
        if readAnimState(enemy).blocking then return true end
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
        local ok1, v1 = pcall(function() return c:GetAttribute("Stunned") end)
        if ok1 and v1 == true then return true end
        local ok2, state = pcall(function() return h:GetState() end)
        if ok2 and state then
            if state == Enum.HumanoidStateType.FallingDown
                or state == Enum.HumanoidStateType.Ragdoll
                or state == Enum.HumanoidStateType.Physics then
                return true
            end
        end
        if readAnimState(enemy).stunned then return true end
        return false
    end

    --============================================================
    -- THREATS
    --============================================================
    function D.updateThreats()
        local t = now()
        if t - S.lTht < 0.1 then return end
        S.lTht = t
        local myHrp = U.hrp()
        if not myHrp then S.ths = {}; S.imm = 0; S.zn = 0; return end
        local myPos = myHrp.Position
        local bosses = D.scanBosses()
        local threats, zoneCount, imminent = {}, 0, 0
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
                local attacking = anim.attacking or closing
                local score = 0
                if attacking then score = score + 10 end
                if e.d < 9 then score = score + 5 end
                if closing then score = score + 3 end
                local look = e.rp.CFrame.LookVector
                local toPlayer = myPos - e.rp.Position
                if toPlayer.Magnitude > 0.1 then
                    local dot = look:Dot(toPlayer.Unit)
                    if dot > 0.5 then score = score + 2
                    elseif dot < -0.5 then score = score - 2 end
                end
                if attacking then imminent = imminent + 1 end
                table.insert(threats, {
                    ch=e.ch, rp=e.rp, hm=e.hm, d=e.d,
                    imminent=attacking, score=score, ts=t,
                })
            end
        end
        table.sort(threats, function(a, b) return a.score > b.score end)
        S.ths = threats
        S.zn = zoneCount
        S.imm = imminent
    end

    --============================================================
    -- PICK TARGET
    --============================================================
    local function blacklisted(inst, t)
        local exp = targetHistory.fails[inst]
        if not exp then return false end
        if t >= exp then targetHistory.fails[inst] = nil; return false end
        return true
    end

    local function computeScore(e, t)
        local score = math.max(0, 100 - e.d) * 0.5
        local frac = e.hm.MaxHealth > 0 and e.hm.Health / e.hm.MaxHealth or 1
        score = score + (1 - frac) * 40
        for i = 1, #(cache.threats.history[1] or {}) do
            local th = cache.threats.history[1][i]
            if th.ch == e.ch then score = score + th.score * 3; break end
        end
        return score
    end

    function D.pickTarget()
        local t = now()
        local bosses = D.scanBosses()
        if #bosses > 0 then
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
                    stickyTarget = best.entry; stickyScore = best.score; stickyTs = t
                end
                return stickyTarget, "boss-sticky"
            end
            local best = nil
            for i = 1, #bosses do
                local b = bosses[i]
                if not blacklisted(b.ch, t) then
                    local s = computeScore(b, t)
                    if D.isEnemyStunned(b) then s = s + 20 end
                    if not best or s > best.score then
                        best = { entry = b, score = s }
                    end
                end
            end
            if best then
                stickyTarget = best.entry; stickyScore = best.score; stickyTs = t
                return best.entry, "boss"
            end
            targetHistory.fails = {}
            return bosses[1], "boss-cleared"
        end
        local mobs = D.scanMobs()
        if #mobs > 0 then return mobs[1], "mob" end
        return nil, "none"
    end

    function D.reportTargetFail(entry)
        if entry and entry.ch then targetHistory.fails[entry.ch] = now() + 3 end
    end
    function D.clearSticky() stickyTarget = nil; stickyScore = 0; stickyTs = 0 end

    --============================================================
    -- ITEMS + CHESTS (unchanged)
    --============================================================
    local ITEM_KEYWORDS = {
        "coin","wen","yen","pouch","ore","scrap","ingot","silk","plating",
        "crystal","thread","weaver","refinement","elixir","potion","gourd",
        "lantern","haori","mask","necklace","earring","ring",
        "drop","loot","pickup","collect",
    }
    local function isItemName(nm)
        if not nm then return false end
        local l = string.lower(nm)
        for i = 1, #ITEM_KEYWORDS do
            if string.find(l, ITEM_KEYWORDS[i], 1, true) then return true, ITEM_KEYWORDS[i] end
        end
        return false
    end
    local function modelPos(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Attachment") and inst.Parent and inst.Parent:IsA("BasePart") then
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
        local myHrp = U.hrp(); if not myHrp then return {} end
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
                    local isIt, kw = isItemName(inst.Name)
                    if isIt then
                        local pos = modelPos(inst)
                        if pos then
                            local dx = myPos.X - pos.X
                            local dy = myPos.Y - pos.Y
                            local dz = myPos.Z - pos.Z
                            local dSq = dx*dx + dy*dy + dz*dz
                            if dSq <= maxSq then
                                seen[inst] = true
                                table.insert(out, {
                                    inst=inst, pos=pos, d=math.sqrt(dSq),
                                    kind="item", kw=kw, name=inst.Name,
                                })
                            end
                        end
                    end
                end
                for _, c in ipairs(inst:GetChildren()) do
                    table.insert(stack, { c, depth + 1 })
                end
                iter = iter + 1
                if iter % YIELD_EVERY == 0 then task.wait() end
            end
        end
        table.sort(out, function(a, b) return a.d < b.d end)
        cache.item.ts = now(); cache.item.list = out
        return out
    end
    function D.bestItem(radius)
        local items = D.scanItems(radius)
        if #items > 0 then return items[1] end
    end

    local CHEST_KEYWORDS = {
        "chest","cache","crate","lootbox","world events chest",
        "common chest","rare chest","demon chest",
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
        local myHrp = U.hrp(); if not myHrp then return {} end
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
                    if isChestName(inst.Name) then found=true; kind="model"; label=inst.Name end
                end
                if not found and inst:IsA("ProximityPrompt") then
                    local n = (inst.ObjectText or "").." "..(inst.ActionText or "").." "..(inst.Name or "")
                    if isChestName(n) then found=true; kind="prompt"; label=n end
                end
                if not found and inst:IsA("ClickDetector") then
                    local n = inst.Name
                    if inst.Parent then n = n.." "..inst.Parent.Name end
                    if isChestName(n) then found=true; kind="click"; label=n end
                end
                if found and not seen[inst] then
                    local pos = modelPos(inst)
                    if not pos and inst.Parent then pos = modelPos(inst.Parent) end
                    if pos then
                        local dx = myPos.X - pos.X
                        local dy = myPos.Y - pos.Y
                        local dz = myPos.Z - pos.Z
                        local dSq = dx*dx + dy*dy + dz*dz
                        if dSq <= maxSq then
                            seen[inst] = true
                            table.insert(out, {
                                inst=inst, pos=pos, d=math.sqrt(dSq),
                                kind=kind, name=label or inst.Name,
                            })
                        end
                    end
                end
                for _, c in ipairs(inst:GetChildren()) do
                    table.insert(stack, { c, depth + 1 })
                end
                iter = iter + 1
                if iter % YIELD_EVERY == 0 then task.wait() end
            end
        end
        table.sort(out, function(a, b) return a.d < b.d end)
        cache.chest.ts = now(); cache.chest.list = out
        return out
    end
    function D.bestChest(radius)
        local chests = D.scanChests(radius)
        if #chests > 0 then return chests[1] end
    end

    --============================================================
    -- STATS + INVALIDATE + DUMP
    --============================================================
    function D.stats()
        return {
            bosses=#cache.boss.hot, mobs=#cache.mob.list,
            humans=#cache.human.list, threats=#S.ths,
            imminent=S.imm, zone=S.zn, overlay=#cache.ovl.list,
            items=#cache.item.list, chests=#cache.chest.list,
            priorityFails=priorityFailures,
            stickyTarget=stickyTarget and stickyTarget.ch.Name or nil,
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

    function D.dump()
        local t0 = now()
        local list = collectHumanoids(2000, function() return true end)
        local ms = math.floor((now() - t0) * 1000)
        print(string.format("[Dingus][detect] dump: %d humanoids in %dms", #list, ms))
        local n = 0
        for i = 1, #list do
            local e = list[i]
            local isB = L.isBoss(e.ch.Name)
            if isB or n < 15 then
                print(string.format("  %s [%s] @%.0f%s",
                    e.ch.Name, e.src or "?", e.d, isB and " BOSS" or ""))
                n = n + 1
            end
        end
        return #list
    end

    print("[Dingus][detect] v7 initialized · batched walk · all-roots")
end

return D
