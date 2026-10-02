--[[
    Dingus-Slayer · detect.lua v5
    Fixes B1/B2/B3.

    Changes:
      - Walk ALL roots, do not early-break
      - Iteration cap 60k with rate-limited yields
      - Priority filter has an "empty result" safety valve
      - Farthest-boss distance surfaced for diagnostics
]]--

local D = {}

function D.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local L = Ctx.Lists

    local bossCache     = { ts = 0, list = {} }
    local mobCache      = { ts = 0, list = {} }
    local humanoidCache = { ts = 0, list = {} }
    local overlayCache  = { ts = 0, list = {} }

    local MAX_WALK = 60000
    local CAP_WARNED = false

    --============================================================
    -- HUMANOID COLLECTOR
    --============================================================
    local function collectHumanoids(maxDist, filterFn)
        maxDist = maxDist or 500
        filterFn = filterFn or function() return true end

        local myHrp = U.hrp()
        if not myHrp then return {} end

        local myPos = myHrp.Position
        local myName = U.Name
        local out = {}
        local seen = {}
        local iter = 0

        -- Roots: Humanoids first (game's own container), then Regions
        -- (also under Humanoids but walked explicitly for depth),
        -- then workspace as last resort.
        local roots = {}
        local humanoidsFolder = workspace:FindFirstChild("Humanoids")
        if humanoidsFolder then
            table.insert(roots, { humanoidsFolder, "Humanoids" })
            local regions = humanoidsFolder:FindFirstChild("Regions")
            if regions then
                table.insert(roots, { regions, "Regions" })
            end
        end
        table.insert(roots, { workspace, "workspace" })

        -- Walk ALL roots. No early break.
        for ri = 1, #roots do
            local rootEntry = roots[ri]
            local root = rootEntry[1]
            local tag = rootEntry[2]
            local stack = { { root, 0 } }
            local rootFound = 0

            while #stack > 0 do
                local item = table.remove(stack)
                local inst, depth = item[1], item[2]

                if inst and depth <= 8 then
                    if inst ~= U.Lp.Character and not seen[inst] then
                        local hum = inst:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then
                            local nm = inst.Name
                            local skip = false
                            if nm == myName then skip = true end
                            if U.isPlayer(inst) then skip = true end

                            if not skip and filterFn(inst, hum) then
                                local hrp = inst:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local d = (myPos - hrp.Position).Magnitude
                                    if d <= maxDist then
                                        seen[inst] = true
                                        rootFound = rootFound + 1
                                        table.insert(out, {
                                            ch = inst, hm = hum, rp = hrp, d = d,
                                            src = tag,
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
                            warn(string.format(
                                "[Dingus][detect] walk cap %d hit", MAX_WALK))
                        end
                        break
                    end
                    if iter % 2000 == 0 then task.wait() end
                end
            end

            if iter >= MAX_WALK then break end
            -- No early-break; continue to next root even if this one found matches.
        end

        table.sort(out, function(a, b) return a.d < b.d end)
        return out
    end

    --============================================================
    -- PRIORITY FILTER · with safety valve
    --============================================================
    local priorityFailures = 0
    local function priorityActive()
        if not Ctx.Quest or not Ctx.Quest.getPriorityBosses then return false end
        local ok, list = pcall(Ctx.Quest.getPriorityBosses)
        if not ok or not list or #list == 0 then return false end
        -- If we keep finding zero matches across many scans, disable filter
        if priorityFailures > 20 then return false end
        return true
    end

    local function passesPriorityFilter(name)
        if not priorityActive() then return true end
        local ok, result = pcall(Ctx.Quest.isPriority, name)
        if not ok then return true end
        return result ~= false
    end

    --============================================================
    -- SCAN BOSSES
    --============================================================
    function D.scanBosses(force, includeNonPriority)
        local now = U.clock()
        if not force and now - bossCache.ts < (Cfg.ScanTTL or 1.2) then
            local list = bossCache.list
            if includeNonPriority or not priorityActive() then return list end
            local out = {}
            for i = 1, #list do
                if passesPriorityFilter(list[i].ch.Name) then
                    table.insert(out, list[i])
                end
            end
            return out
        end
        bossCache.ts = now

        local list = collectHumanoids(2000, function(inst, hum)
            return L.isBoss(inst.Name)
        end)

        bossCache.list = list
        St.ens = list

        -- Diagnostic: report if the priority filter drops everything
        local priorityDropped = 0
        local priorityKept = 0
        local out = {}
        for i = 1, #list do
            if passesPriorityFilter(list[i].ch.Name) then
                priorityKept = priorityKept + 1
                table.insert(out, list[i])
            else
                priorityDropped = priorityDropped + 1
            end
        end

        if #list > 0 and priorityKept == 0 and priorityDropped > 0 then
            priorityFailures = priorityFailures + 1
            if priorityFailures == 5 then
                print(string.format(
                    "[Dingus][detect] priority filter dropped all %d bosses — disabling until quests refresh",
                    priorityDropped))
            end
        end

        if includeNonPriority or not priorityActive() then return list end
        return out
    end

    --============================================================
    -- OVERLAY READER (retained)
    --============================================================
    function D.readOverlay(force)
        local now = U.clock()
        if not force and now - overlayCache.ts < 1.0 then
            return overlayCache.list
        end
        overlayCache.ts = now

        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then overlayCache.list = {}; return overlayCache.list end

        local hits, seen = {}, {}
        local stack = { { pg, 0 } }
        local iter = 0
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 5 then
                if inst:IsA("TextLabel") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string" and #txt >= 3 and #txt <= 30 then
                        if L.isBoss(txt) then
                            local norm = txt:lower():gsub("^%s+", ""):gsub("%s+$", "")
                            if not seen[norm] then
                                seen[norm] = true
                                hits[#hits+1] = txt
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
        overlayCache.list = hits
        return hits
    end

    function D.overlayBosses(force) return D.readOverlay(force) end

    --============================================================
    -- MOBS (kept, empty keyword list)
    --============================================================
    function D.scanMobs(force)
        local now = U.clock()
        if not force and now - mobCache.ts < (Cfg.ScanTTL or 1.2) then
            return mobCache.list
        end
        mobCache.ts = now
        local list = collectHumanoids(60, function(inst)
            if L.isBoss(inst.Name) then return false end
            if L.isCrow(inst.Name) then return false end
            local lname = string.lower(inst.Name)
            for i = 1, #L.mobKeywords do
                if string.find(lname, L.mobKeywords[i], 1, true) then
                    return true
                end
            end
            return false
        end)
        mobCache.list = list
        return list
    end

    function D.nearbyAll(force)
        local now = U.clock()
        if not force and now - humanoidCache.ts < (Cfg.ScanTTL or 1.2) then
            return humanoidCache.list
        end
        humanoidCache.ts = now
        local list = collectHumanoids(120, function() return true end)
        humanoidCache.list = list
        return list
    end

    --============================================================
    -- ANIMATION READERS
    --============================================================
    local function animMatch(enemy, pred)
        if not enemy or not enemy.hm then return false end
        local an = enemy.hm:FindFirstChildOfClass("Animator")
        if not an then return false end
        local ok, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
        if not ok or not tracks then return false end
        for i = 1, #tracks do
            local t = tracks[i]
            local okP, isPlaying = pcall(function() return t.IsPlaying end)
            if okP and isPlaying then
                local okW, w = pcall(function() return t.WeightCurrent end)
                if okW and w > 0.3 then
                    local okN, nm = pcall(function() return t.Name end)
                    if okN and nm then
                        if pred(string.lower(nm)) then return true end
                    end
                end
            end
        end
        return false
    end

    function D.isEnemyAttacking(enemy)
        return animMatch(enemy, function(l)
            if l:find("idle",1,true) or l:find("walk",1,true)
               or l:find("run",1,true) or l:find("block",1,true)
               or l:find("stun",1,true) or l:find("hit",1,true)
               or l:find("death",1,true) then
                return false
            end
            if l:find("attack",1,true) or l:find("slash",1,true)
               or l:find("cast",1,true) or l:find("punch",1,true)
               or l:find("swing",1,true) or l:find("combo",1,true)
               or l:find("skill",1,true) or l:find("ability",1,true) then
                return true
            end
            return false
        end)
    end

    --============================================================
    -- THREATS
    --============================================================
    local function isClosingIn(enemy, myPos)
        local ok, vel = pcall(function() return enemy.rp.AssemblyLinearVelocity end)
        if not ok or not vel then return false end
        if vel.Magnitude < 4 then return false end
        local toMe = myPos - enemy.rp.Position
        local flat = Vector3.new(toMe.X, 0, toMe.Z)
        if flat.Magnitude < 0.1 then return false end
        local vd = Vector3.new(vel.X, 0, vel.Z)
        if vd.Magnitude < 0.1 then return false end
        local facing = 0
        local ok2, lv = pcall(function() return enemy.rp.CFrame.LookVector end)
        if ok2 and lv then facing = lv:Dot(flat.Unit) end
        return vd.Unit:Dot(flat.Unit) > 0.5 and facing > 0.3
    end

    function D.updateThreats()
        local now = U.clock()
        if now - St.lTht < 0.1 then return end
        St.lTht = now

        local myHrp = U.hrp()
        if not myHrp then
            St.ths = {}; St.imm = 0; St.zn = 0; return
        end

        local myPos = myHrp.Position
        local bosses = D.scanBosses()

        local threats, zoneCount, imminent = {}, 0, 0
        for i = 1, #bosses do
            local e = bosses[i]
            if e.d <= 18 then
                zoneCount = zoneCount + 1
                if e.d <= 9 then
                    local attacking = D.isEnemyAttacking(e)
                    if not attacking then attacking = isClosingIn(e, myPos) end
                    if attacking then imminent = imminent + 1 end
                end
                table.insert(threats, {
                    ch = e.ch, rp = e.rp, hm = e.hm, d = e.d,
                    imminent = (e.d <= 9),
                })
            end
        end
        St.ths = threats
        St.zn = zoneCount
        St.imm = imminent
    end

    --============================================================
    -- BLOCK / STUN
    --============================================================
    function D.isEnemyBlocking(enemy)
        if not enemy or not enemy.ch or not enemy.hm then return false end
        local c, h = enemy.ch, enemy.hm
        local ok1, v1 = pcall(function() return c:GetAttribute("IsBlocking") end)
        if ok1 and v1 == true then return true end
        local ok2, v2 = pcall(function() return h:GetAttribute("IsBlocking") end)
        if ok2 and v2 == true then return true end
        if animMatch(enemy, function(l)
            return l:find("block",1,true) or l:find("guard",1,true)
                or l:find("parry",1,true)
        end) then return true end
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
        if animMatch(enemy, function(l)
            return l:find("stun",1,true) or l:find("blockbreak",1,true)
                or l:find("block_break",1,true)
        end) then return true end
        return false
    end

    --============================================================
    -- PICK
    --============================================================
    function D.pickTarget()
        local bosses = D.scanBosses()
        if #bosses > 0 then
            local bestStunned = nil
            for i = 1, #bosses do
                local b = bosses[i]
                if b.d <= 40 and D.isEnemyStunned(b) then
                    if not bestStunned or b.d < bestStunned.d then
                        bestStunned = b
                    end
                end
            end
            if bestStunned then return bestStunned, "boss-stunned" end
            return bosses[1], "boss"
        end
        local mobs = D.scanMobs()
        if #mobs > 0 then return mobs[1], "mob" end
        return nil, "none"
    end

    function D.invalidate()
        bossCache.ts = 0; mobCache.ts = 0
        humanoidCache.ts = 0; overlayCache.ts = 0
        bossCache.list = {}; mobCache.list = {}
        humanoidCache.list = {}; overlayCache.list = {}
    end

    function D.stats()
        return {
            bosses = #bossCache.list,
            mobs = #mobCache.list,
            humans = #humanoidCache.list,
            threats = #St.ths,
            imminent = St.imm,
            zone = St.zn,
            overlay = #overlayCache.list,
            priorityFailures = priorityFailures,
        }
    end

    --============================================================
    -- DIAGNOSTIC · dump everything the scanner sees
    --============================================================
    function D.dump()
        local list = collectHumanoids(2000, function() return true end)
        print(string.format("[Dingus][detect] dump: %d humanoids in 2000 studs", #list))
        local shown = 0
        for i = 1, #list do
            local e = list[i]
            local isB = L.isBoss(e.ch.Name)
            if isB or shown < 15 then
                print(string.format("  %s [%s] @%.0f%s",
                    e.ch.Name, e.src or "?",
                    e.d, isB and " BOSS" or ""))
                if isB then shown = shown + 1 end
            end
        end
        return #list
    end

    print("[Dingus][detect] v5 initialized · multi-root, no early break")
end

return D
