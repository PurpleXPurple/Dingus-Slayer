--[[
    Dingus-Slayer · detect.lua v3
    Region-first workspace walk retained from v2 (30k instance cap).
    New: overlay reader for the top-right boss tracker UI. Provides
    a fallback boss list when the workspace walk misses hidden or
    unreplicated bosses (fog, LOD, streaming).

    Overlay cannot provide positions, so it is not used for targeting
    directly. It is exposed as D.overlayBosses() for GUI display and
    as a diagnostic — if the workspace reports 0 bosses but the
    overlay shows 5, something in the scan is broken.
]]--

local D = {}

function D.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local L = Ctx.Lists

    local bossCache = { ts = 0, list = {} }
    local mobCache = { ts = 0, list = {} }
    local humanoidCache = { ts = 0, list = {} }

    local overlayCache = { ts = 0, list = {} }

    local MAX_WALK = 30000
    local CAP_WARNED = false

    --============================================================
    -- HUMANOID COLLECTOR (unchanged from v2)
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

        local roots = {}
        local humanoidsFolder = workspace:FindFirstChild("Humanoids")
        local regionFound = false
        if humanoidsFolder then
            local regions = humanoidsFolder:FindFirstChild("Regions")
            if regions then
                table.insert(roots, regions)
                regionFound = true
            end
            table.insert(roots, humanoidsFolder)
        end
        if not regionFound then
            table.insert(roots, workspace)
        end

        for ri = 1, #roots do
            local root = roots[ri]
            local stack = { { root, 0 } }

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
                                        table.insert(out, {
                                            ch = inst, hm = hum, rp = hrp, d = d,
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
                                "[Dingus][detect] walk cap %d hit — workspace fallback in use",
                                MAX_WALK))
                        end
                        break
                    end
                    if iter % 2000 == 0 then task.wait() end
                end
            end

            if iter >= MAX_WALK then break end
            if #out > 0 and root ~= workspace then break end
        end

        table.sort(out, function(a, b) return a.d < b.d end)
        return out
    end

    --============================================================
    -- BOSS SCANNER
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

        -- Diagnostic: if workspace is empty but overlay shows bosses,
        -- log once so the user knows the scan is missing them.
        if #list == 0 and (St.overlayBosses and #St.overlayBosses > 0) then
            if not St._overlayMissWarned then
                St._overlayMissWarned = true
                print(string.format(
                    "[Dingus][detect] workspace scan empty; overlay shows %d boss(es): %s",
                    #St.overlayBosses, table.concat(St.overlayBosses, ", ")))
            end
        else
            St._overlayMissWarned = false
        end

        return list
    end

    --============================================================
    -- OVERLAY READER (new in v3)
    -- Walks PlayerGui at shallow depth looking for TextLabels whose
    -- text matches a boss name. Screenshot 1 evidence: the top-right
    -- tracker renders boss names as plain TextLabels.
    --============================================================
    function D.readOverlay(force)
        local now = U.clock()
        if not force and now - overlayCache.ts < 1.0 then
            return overlayCache.list
        end
        overlayCache.ts = now

        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then
            overlayCache.list = {}
            return overlayCache.list
        end

        local hits = {}
        local seen = {}
        local stack = { { pg, 0 } }
        local iter = 0

        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 5 then
                if inst:IsA("TextLabel") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string"
                        and #txt >= 3 and #txt <= 30 then
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

    function D.overlayBosses(force)
        return D.readOverlay(force)
    end

    --============================================================
    -- MOB SCANNER
    --============================================================
    function D.scanMobs(force)
        local now = U.clock()
        if not force and now - mobCache.ts < Cfg.ScanTTL then
            return mobCache.list
        end
        mobCache.ts = now
        local list = collectHumanoids(60, function(inst, hum)
            if L.isBoss(inst.Name) then return false end
            if L.isCrow(inst.Name) then return false end
            if L.isQuest(inst.Name) then return false end
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
        if not force and now - humanoidCache.ts < Cfg.ScanTTL then
            return humanoidCache.list
        end
        humanoidCache.ts = now
        local list = collectHumanoids(120, function() return true end)
        humanoidCache.list = list
        return list
    end

    --============================================================
    -- THREAT DETECTION (unchanged from v2)
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

        local threats = {}
        local zoneCount = 0
        local imminent = 0

        for i = 1, #bosses do
            local e = bosses[i]
            if e.d <= 18 then
                zoneCount = zoneCount + 1
                if e.d <= 9 then
                    local attacking = isAttackingAnim(e)
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
    -- BLOCK / STUN DETECTION (unchanged)
    --============================================================
    function D.isEnemyBlocking(enemy)
        if not enemy or not enemy.ch or not enemy.hm then return false end
        local c = enemy.ch
        local h = enemy.hm

        local ok1, v1 = pcall(function() return c:GetAttribute("IsBlocking") end)
        if ok1 and v1 == true then return true end

        local ok2, v2 = pcall(function() return h:GetAttribute("IsBlocking") end)
        if ok2 and v2 == true then return true end

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
        local c = enemy.ch
        local h = enemy.hm

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

        local ok4, ws = pcall(function() return h.WalkSpeed end)
        if ok4 and ws and ws < 1 then
            local ok5, vel = pcall(function() return enemy.rp.AssemblyLinearVelocity end)
            if ok5 and vel and vel.Magnitude < 1 then
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
        bossCache.ts = 0
        mobCache.ts = 0
        humanoidCache.ts = 0
        overlayCache.ts = 0
        bossCache.list = {}
        mobCache.list = {}
        humanoidCache.list = {}
        overlayCache.list = {}
        St._overlayMissWarned = false
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
        }
    end

    print("[Dingus][detect] v3 initialized")
end

return D
