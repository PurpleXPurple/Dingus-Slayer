--[[
    Dingus-Slayer · detect.lua v22
    Region-first boss scanning · animation-driven threat detection
    Uses Ctx.Lists for all name matching · Ctx.Util for helpers · Ctx.Cfg for tuning
]]--

local D = {}

function D.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local L = Ctx.Lists

    --============================================================
    -- CACHES
    --============================================================
    local bossCache = { ts = 0, list = {} }
    local mobCache = { ts = 0, list = {} }
    local humanoidCache = { ts = 0, list = {} }

    --============================================================
    -- GENERIC HUMANOID COLLECTOR
    -- Returns every live Humanoid model nearby with basic info.
    -- Walks region folder first, then workspace as fallback.
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

        -- Region folder first — PS2 stores active NPCs there
        local roots = {}
        local humanoidsFolder = workspace:FindFirstChild("Humanoids")
        if humanoidsFolder then
            local regions = humanoidsFolder:FindFirstChild("Regions")
            if regions then
                table.insert(roots, regions)
            end
            -- Also try direct children of Humanoids (self, other players)
            table.insert(roots, humanoidsFolder)
        end
        table.insert(roots, workspace)

        for ri = 1, #roots do
            local root = roots[ri]
            local stack = { { root, 0 } }
            local iter = 0

            while #stack > 0 do
                local item = table.remove(stack)
                local inst, depth = item[1], item[2]

                if inst and depth <= 8 then
                    -- Check if this instance is a valid candidate
                    if inst ~= U.Lp.Character and not seen[inst] then
                        local hum = inst:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then
                            local nm = inst.Name
                            -- Skip local player
                            local skip = false
                            if nm == myName then skip = true end
                            if U.isPlayer(inst) then skip = true end

                            if not skip and filterFn(inst, hum) then
                                local hrp = inst:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local d = (myPos - hrp.Position).Magnitude
                                    if d <= maxDist then
                                        seen[inst] = true
                                        table.insert(out, {
                                            ch = inst,
                                            hm = hum,
                                            rp = hrp,
                                            d = d,
                                        })
                                    end
                                end
                            end
                        end
                    end

                    -- Descend
                    local ok, kids = pcall(function() return inst:GetChildren() end)
                    if ok and kids then
                        for i = 1, #kids do
                            table.insert(stack, { kids[i], depth + 1 })
                        end
                    end

                    iter = iter + 1
                    if iter % 2000 == 0 then task.wait() end
                end
            end

            -- If we already found results in the region folder, don't walk workspace
            if #out > 0 and root ~= workspace then break end
        end

        table.sort(out, function(a, b) return a.d < b.d end)
        return out
    end

    --============================================================
    -- BOSS SCANNER
    -- Uses Lists.isBoss. Region-first. Cached with TTL.
    --============================================================
    function D.scanBosses(force)
        local now = U.clock()
        if not force and now - bossCache.ts < Cfg.ScanTTL then
            return bossCache.list
        end
        bossCache.ts = now

        local list = collectHumanoids(500, function(inst, hum)
            return L.isBoss(inst.Name)
        end)

        bossCache.list = list
        St.ens = list
        return list
    end

    --============================================================
    -- MOB SCANNER (non-boss live humanoids)
    -- Uses Lists.mobKeywords for fallback targeting.
    --============================================================
    function D.scanMobs(force)
        local now = U.clock()
        if not force and now - mobCache.ts < Cfg.ScanTTL then
            return mobCache.list
        end
        mobCache.ts = now

        local list = collectHumanoids(60, function(inst, hum)
            -- Not a boss, but looks like a mob
            if L.isBoss(inst.Name) then return false end
            if L.isCrow(inst.Name) then return false end
            if L.isQuest(inst.Name) then return false end
            -- Match against mob keywords
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

    --============================================================
    -- NEARBY HUMANOIDS (all non-player)
    --============================================================
    function D.nearbyAll(force)
        local now = U.clock()
        if not force and now - humanoidCache.ts < Cfg.ScanTTL then
            return humanoidCache.list
        end
        humanoidCache.ts = now

        local list = collectHumanoids(120, function(inst, hum)
            return true
        end)

        humanoidCache.list = list
        return list
    end

    --============================================================
    -- THREAT DETECTION
    -- Animation-first: any non-idle animation on nearby boss = attack.
    -- Falls back to velocity + facing check.
    --============================================================
    local function isAttackingAnim(enemy)
        local an = enemy.hm:FindFirstChildOfClass("Animator")
        if not an then return false end

        local ok, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
        if not ok or not tracks then return false end

        for i = 1, #tracks do
            local t = tracks[i]
            local okI, isPlaying = pcall(function() return t.IsPlaying end)
            if okI and isPlaying then
                local okW, w = pcall(function() return t.WeightCurrent end)
                if okW and w > 0.3 then
                    local okN, nm = pcall(function() return t.Name end)
                    if okN and nm then
                        local l = string.lower(nm)
                        -- Exclude idle/walk/run/block — those aren't attacks
                        if not string.find(l, "idle", 1, true)
                            and not string.find(l, "walk", 1, true)
                            and not string.find(l, "run", 1, true)
                            and not string.find(l, "block", 1, true)
                            and not string.find(l, "stun", 1, true) then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    local function isClosingIn(enemy, myPos)
        local ok, vel = pcall(function() return enemy.rp.AssemblyLinearVelocity end)
        if not ok or not vel then return false end

        local speed = vel.Magnitude
        if speed < 4 then return false end

        local toMe = myPos - enemy.rp.Position
        local flat = Vector3.new(toMe.X, 0, toMe.Z)
        if flat.Magnitude < 0.1 then return false end

        local vd = Vector3.new(vel.X, 0, vel.Z)
        if vd.Magnitude < 0.1 then return false end

        local facing = 0
        local ok2, lv = pcall(function() return enemy.rp.CFrame.LookVector end)
        if ok2 and lv then
            facing = lv:Dot(flat.Unit)
        end

        return vd.Unit:Dot(flat.Unit) > 0.5 and facing > 0.3
    end

    function D.updateThreats()
        local now = U.clock()
        if now - St.lTht < 0.1 then return end
        St.lTht = now

        local myHrp = U.hrp()
        if not myHrp then
            St.ths = {}
            St.imm = 0
            St.zn = 0
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

                if e.d <= 9 then
                    local attacking = isAttackingAnim(e)
                    if not attacking then
                        attacking = isClosingIn(e, myPos)
                    end
                    if attacking then
                        imminent = imminent + 1
                    end
                end

                table.insert(threats, {
                    ch = e.ch,
                    rp = e.rp,
                    hm = e.hm,
                    d = e.d,
                    imminent = (e.d <= 9),
                })
            end
        end

        St.ths = threats
        St.zn = zoneCount
        St.imm = imminent
    end

    --============================================================
    -- ENEMY BLOCK DETECTION
    -- Multi-path: attribute, animation, velocity heuristics.
    --============================================================
    function D.isEnemyBlocking(enemy)
        if not enemy or not enemy.ch or not enemy.hm then return false end

        local c = enemy.ch
        local h = enemy.hm

        -- Path 1: attribute on character
        local ok1, v1 = pcall(function() return c:GetAttribute("IsBlocking") end)
        if ok1 and v1 == true then return true end

        -- Path 2: attribute on humanoid
        local ok2, v2 = pcall(function() return h:GetAttribute("IsBlocking") end)
        if ok2 and v2 == true then return true end

        -- Path 3: animator with block name
        local an = h:FindFirstChildOfClass("Animator")
        if an then
            local ok3, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
            if ok3 and tracks then
                for i = 1, #tracks do
                    local t = tracks[i]
                    local okP, isPlaying = pcall(function() return t.IsPlaying end)
                    if okP and isPlaying then
                        local okW, w = pcall(function() return t.WeightCurrent end)
                        if okW and w > 0.3 then
                            local okN, nm = pcall(function() return t.Name end)
                            if okN and nm then
                                local l = string.lower(nm)
                                if string.find(l, "block", 1, true)
                                    or string.find(l, "guard", 1, true)
                                    or string.find(l, "parry", 1, true) then
                                    return true
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Path 4: stationary + low walkspeed for a moment
        local ok4, ws = pcall(function() return h.WalkSpeed end)
        if ok4 and ws and ws < 2 then
            local ok5, md = pcall(function() return h.MoveDirection end)
            if ok5 and md and md.Magnitude < 0.1 then
                local ok6, vel = pcall(function() return enemy.rp.AssemblyLinearVelocity end)
                if ok6 and vel and vel.Magnitude < 2 then
                    -- Only treat as blocking if not stunned
                    if not D.isEnemyStunned(enemy) then
                        return true
                    end
                end
            end
        end

        return false
    end

    --============================================================
    -- ENEMY STUN DETECTION
    -- Multi-path: attribute, humanoid state, animation name.
    --============================================================
    function D.isEnemyStunned(enemy)
        if not enemy or not enemy.ch or not enemy.hm then return false end

        local c = enemy.ch
        local h = enemy.hm

        -- Path 1: attribute on character
        local ok1, v1 = pcall(function() return c:GetAttribute("Stunned") end)
        if ok1 and v1 == true then return true end

        -- Path 2: humanoid state (Ragdoll, FallingDown, Physics)
        local ok2, state = pcall(function() return h:GetState() end)
        if ok2 and state then
            if state == Enum.HumanoidStateType.FallingDown
                or state == Enum.HumanoidStateType.Ragdoll
                or state == Enum.HumanoidStateType.Physics then
                return true
            end
        end

        -- Path 3: animator with stun animation
        local an = h:FindFirstChildOfClass("Animator")
        if an then
            local ok3, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
            if ok3 and tracks then
                for i = 1, #tracks do
                    local t = tracks[i]
                    local okP, isPlaying = pcall(function() return t.IsPlaying end)
                    if okP and isPlaying then
                        local okW, w = pcall(function() return t.WeightCurrent end)
                        if okW and w > 0.3 then
                            local okN, nm = pcall(function() return t.Name end)
                            if okN and nm then
                                local l = string.lower(nm)
                                if string.find(l, "stun", 1, true)
                                    or string.find(l, "blockbreak", 1, true)
                                    or string.find(l, "block_break", 1, true) then
                                    return true
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Path 4: fully frozen (walkspeed 0, velocity 0)
        local ok4, ws = pcall(function() return h.WalkSpeed end)
        if ok4 and ws and ws < 1 then
            local ok5, vel = pcall(function() return enemy.rp.AssemblyLinearVelocity end)
            if ok5 and vel and vel.Magnitude < 1 then
                -- Also check that a stun animation is present
                if an then
                    local ok6, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
                    if ok6 and tracks then
                        for i = 1, #tracks do
                            local t = tracks[i]
                            local okP, isPlaying = pcall(function() return t.IsPlaying end)
                            if okP and isPlaying then
                                local okN, nm = pcall(function() return t.Name end)
                                if okN and nm then
                                    local l = string.lower(nm)
                                    if string.find(l, "stun", 1, true)
                                        or string.find(l, "hurt", 1, true)
                                        or string.find(l, "damage", 1, true) then
                                        return true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        return false
    end

    --============================================================
    -- TARGET PICKER
    -- Returns highest priority target:
    --  1. Nearest stunned boss (best to punish)
    --  2. Nearest boss overall
    --  3. Nearest mob (fallback)
    --============================================================
    function D.pickTarget()
        local bosses = D.scanBosses()
        if #bosses > 0 then
            -- Prefer stunned bosses within close range
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

            -- Otherwise nearest boss
            return bosses[1], "boss"
        end

        -- Fallback to mobs if no bosses
        local mobs = D.scanMobs()
        if #mobs > 0 then
            return mobs[1], "mob"
        end

        return nil, "none"
    end

    --============================================================
    -- INVALIDATE CACHES
    -- Called on respawn or target kill
    --============================================================
    function D.invalidate()
        bossCache.ts = 0
        mobCache.ts = 0
        humanoidCache.ts = 0
        bossCache.list = {}
        mobCache.list = {}
        humanoidCache.list = {}
    end

    --============================================================
    -- STATS (for GUI display)
    --============================================================
    function D.stats()
        return {
            bosses = #bossCache.list,
            mobs = #mobCache.list,
            humans = #humanoidCache.list,
            threats = #St.ths,
            imminent = St.imm,
            zone = St.zn,
        }
    end

    print("[Dingus][detect] initialized")
end

return D
