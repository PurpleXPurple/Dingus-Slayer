-- Dingus-Slayer · attack.lua v23
-- Full Synerox farming loop:
--  · FarmPlatform + Overhead/Underground/InFront positioning
--  · M1 via InputHandler.VirtualPress("Combat") + mouse/VIM fallback
--  · Auto-skill via Skill_Provider + Skill_Controller.Attempt_Hold
--  · Track guard (stops Swing/Punch/Slash/React tracks)
--  · Freeze recovery (destroys Stun/CombatStun/RagDoll values)
--  · Target lock + boss rotation
--  · Category/region/name filter with fuzzy matching
--  · Auto-travel to target region

local A = {}

function A.init(Ctx)
    local U, F, S, D, L = Ctx.Util, Ctx.Cfg, Ctx.St, Ctx.Detect, Ctx.Lists

    -- defaults
    F.AtkRange = F.AtkRange or 60
    F.AtkVerbose = F.AtkVerbose ~= false
    F.SynSafeMode = F.SynSafeMode or "Overhead"
    F.SynHeightOffset = F.SynHeightOffset or 3.8
    F.SynDistance = F.SynDistance or 2
    F.SynMultiHit = F.SynMultiHit ~= false
    F.SynMultiHitCount = F.SynMultiHitCount or 3
    F.SynM1Interval = F.SynM1Interval or 0.28
    F.SynAutoSkills = F.SynAutoSkills ~= false
    F.SynSkillInterval = F.SynSkillInterval or 1
    F.SynTrackGuard = F.SynTrackGuard ~= false
    F.SynBossLootWait = F.SynBossLootWait or 4
    F.SynMobLootWait = F.SynMobLootWait or 1.8
    F.SynAutoTravel = F.SynAutoTravel ~= false
    F.SynTargetLock = F.SynTargetLock ~= false
    F.SynBossRotationT = F.SynBossRotationT or 15

    -- state
    S.lockedTarget = nil
    S.targetMob = S.targetMob or "All"
    S.mobCategory = S.mobCategory or "All"
    S.regionFilter = S.regionFilter or "All"
    S.selectedBosses = S.selectedBosses or {}
    S.bossIndex = S.bossIndex or 1
    S.bossRotateTime = 0
    S.lastM1 = 0
    S.lastSkillTime = 0
    S.skillIndex = 1
    S.bossLootPos = nil
    S.bossLootTime = 0
    S.mobCorpsePos = nil
    S.mobCorpseTime = 0
    S.cbtS = "IDLE"
    S.aAt, S.aHi, S.aMs = S.aAt or 0, S.aHi or 0, S.aMs or 0
    S.bKll = S.bKll or 0
    S.retreats = S.retreats or 0
    S.lastStateLog = nil

    --============================================================
    -- REQUIRE GAME MODULES (Synerox paths)
    --============================================================
    local function safeRequire(path)
        local ok, mod = pcall(require, path)
        return ok and mod or nil
    end

    local RS = U.RS
    local Syn = {
        SignalFunction = nil, SignalEvent = nil,
        InputHandler = nil, Skill_Provider = nil, Skill_Controller = nil,
    }
    pcall(function()
        local c = RS:FindFirstChild("Communication")
        local sc = c and c:FindFirstChild("ServerAndClient")
        local sig = sc and sc:FindFirstChild("Signals")
        if sig then
            Syn.SignalFunction = safeRequire(sig:FindFirstChild("SignalFunction"))
            Syn.SignalEvent = safeRequire(sig:FindFirstChild("SignalEvent"))
        end
    end)
    pcall(function()
        local cam = RS:FindFirstChild("CAM")
        local cl = cam and cam:FindFirstChild("Client")
        local comp = cl and cl:FindFirstChild("Components")
        local c2 = comp and comp:FindFirstChild("Client")
        if c2 then
            Syn.InputHandler = safeRequire(c2:FindFirstChild("InputHandler"))
        end
        local ctrl = cl and cl:FindFirstChild("Controllers")
        if ctrl then
            Syn.Skill_Provider = safeRequire(ctrl:FindFirstChild("Skills_Provider"))
            Syn.Skill_Controller = safeRequire(ctrl:FindFirstChild("Skill_Controller"))
        end
    end)
    Ctx.Syn = Syn

    local function slog(msg) if F.AtkVerbose then print("[Dingus][Atk] "..msg) end end
    local function logState(s)
        if S.lastStateLog == s then return end
        S.lastStateLog = s
        slog("state → "..tostring(s))
    end

    --============================================================
    -- FREEZE RECOVERY (Synerox fn11)
    --============================================================
    local function recoverFreeze()
        local char = U.Lp.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")

        pcall(function()
            local ps = RS:FindFirstChild("Player_Service")
            local vals = ps and ps:FindFirstChild("Values")
            local me = vals and vals:FindFirstChild(U.Lp.Name)
            if me then
                for _, name in ipairs({
                    "Stun","Strict_Stun","CombatStun","RagDoll","Ragdoll",
                    "ragdoll","ragDoll","Blocking","JumpingDisabled",
                    "skill_stand_still","skill_slow",
                }) do
                    local v = me:FindFirstChild(name)
                    if v then v:Destroy() end
                end
            end
        end)

        pcall(function()
            if hrp then
                for _, name in ipairs({"skill_stand_still","skill_slow","air_combo_bp"}) do
                    local c = hrp:FindFirstChild(name)
                    if c then c:Destroy() end
                end
            end
        end)

        pcall(function()
            if Syn.InputHandler and Syn.InputHandler.VirtualRelease then
                Syn.InputHandler.VirtualRelease("Block")
                Syn.InputHandler.VirtualRelease("Combat")
            end
        end)

        pcall(function()
            local rc = char:FindFirstChild("RagdollConstraints")
            if rc then
                for _, c in ipairs(rc:GetChildren()) do
                    if c:IsA("Constraint") then
                        c.Enabled = false
                        local rig = c:FindFirstChild("RigidJoint")
                        if rig and rig.Value then
                            local rv = rig.Value
                            local a1 = c.Attachment1
                            if a1 and a1.Parent and rv.Part1 ~= a1.Parent then
                                rv.Part1 = a1.Parent
                            end
                        end
                    end
                end
            end
        end)

        pcall(function()
            if hum then
                local animator = hum:FindFirstChildOfClass("Animator")
                if animator then
                    for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
                        if t.Name ~= "idle" then
                            pcall(function() t:Stop(0); t:Destroy() end)
                        end
                    end
                end
            end
        end)

        pcall(function()
            if hum and hum.Health > 0 then
                hum:ChangeState(Enum.HumanoidStateType.Running)
                if hum.WalkSpeed < 10 then hum.WalkSpeed = 16 end
                if hum.JumpPower == 0 then hum.JumpPower = 50 end
                hum.PlatformStand = false
                hum.Sit = false
                hum.AutoRotate = true
            end
        end)
    end

    --============================================================
    -- STUN CHECK (Synerox fn10)
    --============================================================
    local function isStunned()
        local char = U.Lp.Character
        if not char then return true end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return false end
        local ok, st = pcall(function() return hum:GetState() end)
        if ok and st then
            if st == Enum.HumanoidStateType.Physics
                or st == Enum.HumanoidStateType.Ragdoll
                or st == Enum.HumanoidStateType.FallingDown
                or st == Enum.HumanoidStateType.GettingUp then
                return true
            end
        end
        local vOk, vals = pcall(function()
            return RS.Player_Service.Values:FindFirstChild(U.Lp.Name)
        end)
        if vOk and vals then
            if vals:FindFirstChild("Stun")
                or vals:FindFirstChild("Strict_Stun")
                or vals:FindFirstChild("CombatStun")
                or vals:FindFirstChild("RagDoll") then
                return true
            end
        end
        return false
    end

    --============================================================
    -- FARM PLATFORM (delegates to Ctx.Fly)
    --============================================================
    local function ensurePlatform()
        if Ctx.Fly and Ctx.Fly.ensurePlatform then return Ctx.Fly.ensurePlatform() end
    end
    local function movePlatform(cf)
        if Ctx.Fly and Ctx.Fly.movePlatform then Ctx.Fly.movePlatform(cf) end
    end
    local function destroyPlatform()
        if Ctx.Fly and Ctx.Fly.destroyPlatform then Ctx.Fly.destroyPlatform() end
    end

    --============================================================
    -- M1 (Synerox fn13)
    --============================================================
    local function fireM1(count, trackGuard)
        count = count or 1
        local char = U.Lp.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        if isStunned() then return end

        if trackGuard then
            local animator = hum:FindFirstChildOfClass("Animator")
            if animator then
                for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
                    local nm = t.Name
                    if nm:find("Swing") or nm:find("Punch")
                        or nm:find("Slash") or nm:find("React") then
                        pcall(function() t:Stop(0); t:Destroy() end)
                    end
                end
            end
        end

        for i = 1, count do
            if Syn.InputHandler and Syn.InputHandler.VirtualPress and Syn.InputHandler.VirtualRelease then
                pcall(function()
                    Syn.InputHandler.VirtualPress("Combat")
                    task.wait(0.015)
                    Syn.InputHandler.VirtualRelease("Combat")
                end)
            elseif U.Fn.mouse1click then
                U.m1()
            else
                U.m1()
            end
            if count > 1 and i < count then task.wait(0.04) end
        end
    end

    --============================================================
    -- AUTO SKILL (Synerox fn12)
    --============================================================
    local function fireAutoSkill()
        if not F.SynAutoSkills then return false end
        if isStunned() then return false end
        local now = U.clock()
        if now - (S.lastSkillTime or 0) < (F.SynSkillInterval or 1) then return false end

        local SP = Syn.Skill_Provider
        local SC = Syn.Skill_Controller
        if not SP or not SC then return false end
        local ok, keys = pcall(function() return SP.get_current_keys() end)
        if not ok or not keys or #keys == 0 then return false end

        local valid = {}
        for _, s in ipairs(keys) do
            if s.Name and s.Name ~= "Blocking" and s.Key and not s.RequiresModeBar then
                table.insert(valid, s)
            end
        end
        if #valid == 0 then return false end
        if S.skillIndex > #valid then S.skillIndex = 1 end
        local skill = valid[S.skillIndex]
        S.skillIndex = S.skillIndex + 1
        if not skill then return false end

        -- Attempt 1: Skill_Controller.Attempt_Hold
        local oldId = nil
        if U.Fn.getthreadidentity and U.Fn.setthreadidentity then
            local ok2, v = pcall(U.Fn.getthreadidentity)
            if ok2 then oldId = v end
            pcall(U.Fn.setthreadidentity, 2)
        end
        local ok3, flag = pcall(function() return SC.Attempt_Hold(skill.Name) end)
        if U.Fn.setthreadidentity and oldId then
            pcall(U.Fn.setthreadidentity, oldId)
        end
        if ok3 and flag then
            task.delay(0.08, function()
                local oldId2 = nil
                if U.Fn.getthreadidentity and U.Fn.setthreadidentity then
                    local ok4, v2 = pcall(U.Fn.getthreadidentity)
                    if ok4 then oldId2 = v2 end
                    pcall(U.Fn.setthreadidentity, 2)
                end
                pcall(function() SC.StopHold(skill.Name) end)
                if U.Fn.setthreadidentity and oldId2 then
                    pcall(U.Fn.setthreadidentity, oldId2)
                end
            end)
            S.lastSkillTime = now
            return true
        end

        -- Attempt 2: GUI button
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        local cc = pg and pg:FindFirstChild("ComponentsHolder")
        local bh = cc and cc:FindFirstChild("BottomHolder")
        local sh = bh and bh:FindFirstChild("SkillsHolder")
        if sh then
            for _, child in ipairs(sh:GetChildren()) do
                local kl = child:FindFirstChild("KeyLabel", true)
                if kl and kl.Text == skill.Key then
                    local btn = child:FindFirstChildWhichIsA("GuiButton", true)
                    if btn then
                        U.fireSignal(btn.MouseButton1Down)
                        task.wait(0.04)
                        U.fireSignal(btn.MouseButton1Up)
                        S.lastSkillTime = now
                        return true
                    end
                end
            end
        end

        -- Attempt 3: key event
        if skill.Key and Enum.KeyCode[skill.Key] then
            U.keyDown(skill.Key); task.wait(0.04); U.keyUp(skill.Key)
            S.lastSkillTime = now
            return true
        end
        return false
    end

    --============================================================
    -- MOB FINDER (Synerox fn14)
    --============================================================
    local function findMobs()
        local out = {}
        local humanoids = workspace:FindFirstChild("Humanoids")
        if not humanoids then return out end
        local regions = humanoids:FindFirstChild("Regions")
        if regions then
            for _, region in ipairs(regions:GetChildren()) do
                local active = region:FindFirstChild("ActiveNpcs")
                if active then
                    for _, typeFolder in ipairs(active:GetChildren()) do
                        for _, model in ipairs(typeFolder:GetChildren()) do
                            if model:IsA("Model") and model ~= U.Lp.Character then
                                local hum = model:FindFirstChildOfClass("Humanoid")
                                local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                                if hum and root and hum.Health > 0 and root.Position.Y > -400 then
                                    table.insert(out, {
                                        Model = model, Root = root, Humanoid = hum,
                                        Name = model.Name, Type = typeFolder.Name,
                                        Region = region.Name,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
        -- Fallback: direct children of Humanoids
        if #out == 0 then
            for _, model in ipairs(humanoids:GetChildren()) do
                if model:IsA("Model") and model ~= U.Lp.Character and not U.isPlayer(model) then
                    local hum = model:FindFirstChildOfClass("Humanoid")
                    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                    if hum and root and hum.Health > 0 and root.Position.Y > -400 then
                        table.insert(out, {
                            Model = model, Root = root, Humanoid = hum,
                            Name = model.Name, Type = model.Name, Region = "Direct",
                        })
                    end
                end
            end
        end
        return out
    end

    --============================================================
    -- BOSS CHECK (Synerox fn15)
    --============================================================
    local function isBossName(mob)
        local n = string.lower(mob.Name or "")
        local t = string.gsub(n, "%s+", "")
        local ty = string.lower(mob.Type or "")
        local ty2 = string.gsub(ty, "%s+", "")
        return L.bossNames[n] or L.bossNames[t] or L.bossNames[ty] or L.bossNames[ty2]
            or n:find("trainee") or ty:find("trainee")
    end

    --============================================================
    -- FILTER (Synerox fn16, inner fn17)
    --============================================================
    local function nameMatches(selName, mob)
        if not selName or selName == "All"
           or selName == "All Bosses" or selName == "All Normal Mobs" then
            return true
        end
        local s = string.lower(selName)
        local ss = string.gsub(s, "%s+", "")
        local t = string.lower(mob.Type or "")
        local n = string.lower(mob.Name or "")
        local ts = string.gsub(t, "%s+", "")
        local ns = string.gsub(n, "%s+", "")
        if ts == ss or ns == ss or t == s or n == s then return true end
        local strip = ss:gsub("_%a+", "")
        local tstrip = ts:gsub("_%a+", "")
        local nstrip = ns:gsub("_%a+", "")
        if tstrip == strip or nstrip == strip or ts == strip or ns == strip then return true end
        -- Greater/Lesser distinction
        local wantGreater = s:find("greater") ~= nil
        local wantLesser  = s:find("lesser") ~= nil
        local hasGreater  = (ts:find("greater") or ns:find("greater")) ~= nil
        local hasLesser   = (ts:find("lesser") or ns:find("lesser")) ~= nil
        if wantGreater and hasLesser then return false end
        if wantLesser and hasGreater then return false end
        if s:find("trainee") and (t:find("trainee") or n:find("trainee")) then
            local str = s:gsub("trainee", "")
            if str == "" or ts:find(str) or ns:find(str) then return true end
        else
            if (s:find("tengen") or s:find("tengai")) and (t:find("tengai") or n:find("tengai")) then
                return true
            end
            if not ts:find("subordinate") and not ns:find("subordinate") then
                if t:find(s) or n:find(s) or ts:find(ss) or ns:find(ss)
                   or ts:find(strip) or ns:find(strip) then
                    return true
                end
            end
        end
        return false
    end

    local function passesFilter(mob, selName, region, category)
        if not mob or not mob.Model or not mob.Model.Parent then return false end
        if not mob.Humanoid or not mob.Humanoid.Parent then return false end
        if (mob.Humanoid.Health or 0) <= 0 then return false end
        if not mob.Root or not mob.Root.Parent or mob.Root.Position.Y <= -400 then return false end
        -- Civilian bypass
        local isCiv = string.find(string.lower(mob.Type or ""), "civilian")
            or string.find(string.lower(mob.Name or ""), "civilian")
        local wantCiv = type(selName) == "string" and (selName:lower():find("civilian") or selName:lower():find("civil"))
        if isCiv and not wantCiv then return false end
        -- Category
        local isBoss = isBossName(mob)
        if category == "Boss" and not isBoss then return false end
        if category == "Normal" and isBoss then return false end
        -- Name match (table or string)
        if type(selName) == "table" then
            if #selName == 0 then return true end
            for _, v in ipairs(selName) do
                if nameMatches(v, mob) then return true end
            end
            return false
        end
        if not nameMatches(selName, mob) then return false end
        -- Region
        if region and region ~= "All" and mob.Region ~= region then return false end
        return true
    end

    --============================================================
    -- TARGET PICK (Synerox fn17)
    --============================================================
    local function pickTarget()
        local hrp = U.hrp()
        if not hrp then return nil end
        local mobs = findMobs()
        local best, bestD = nil, math.huge
        for _, m in ipairs(mobs) do
            if passesFilter(m, S.targetMob, S.regionFilter, S.mobCategory) then
                local d = (hrp.Position - m.Root.Position).Magnitude
                if d < bestD then best, bestD = m, d end
            end
        end
        return best
    end

    --============================================================
    -- APPLY POSITION + PLATFORM
    --============================================================
    local function positionAt(mob)
        local hrp = U.hrp()
        if not hrp or not mob or not mob.Root then return end
        local mode = F.SynSafeMode or "Overhead"
        local off = F.SynHeightOffset or 3.8
        local dist = F.SynDistance or 2
        local pos = mob.Root.Position
        local cf
        if mode == "Overhead" then
            cf = CFrame.new(pos + Vector3.new(0, off, 0), pos)
        elseif mode == "Underground" then
            cf = CFrame.new(pos + Vector3.new(0, -off, 0), pos)
        elseif mode == "In Front" then
            local look = mob.Root.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, 1) end
            flat = flat.Unit
            local n = pos + flat * dist
            cf = CFrame.new(n, Vector3.new(pos.X, n.Y, pos.Z))
        elseif mode == "Ground" then
            cf = CFrame.new(pos + mob.Root.CFrame.LookVector * dist, pos)
        else
            cf = CFrame.new(pos + Vector3.new(0, off, 0), pos)
        end
        hrp.CFrame = cf
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        movePlatform(cf)
    end

    --============================================================
    -- BOSS ROTATION (Synerox multi-select)
    --============================================================
    local function rotateBossIfNeeded()
        local selected = S.selectedBosses
        if type(selected) ~= "table" or #selected <= 1 then return end
        local now = U.clock()
        if now - (S.bossRotateTime or 0) < (F.SynBossRotationT or 15) then return end
        S.bossRotateTime = now
        S.bossIndex = (S.bossIndex % #selected) + 1
        S.targetMob = selected[S.bossIndex]
    end

    --============================================================
    -- COMBAT TICK (Synerox farming loop)
    --============================================================
    local function tickInner()
        if not S.cbt then
            S.cbtS = "IDLE"
            logState("IDLE")
            destroyPlatform()
            return
        end

        local char = U.Lp.Character
        if not char then
            S.cbtS = "NO_CHAR"; logState("NO_CHAR"); destroyPlatform(); return
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or hum.Health <= 0 or not hrp then
            S.cbtS = "DEAD"; logState("DEAD"); destroyPlatform(); return
        end

        -- Stun recovery
        if isStunned() then
            S.cbtS = "RECOVER"; logState("RECOVER")
            destroyPlatform()
            recoverFreeze()
            return
        end

        local now = U.clock()

        -- Boss rotation
        rotateBossIfNeeded()

        -- Validate locked target
        local locked = S.lockedTarget
        if locked then
            if not passesFilter(locked, S.targetMob, S.regionFilter, S.mobCategory) then
                if locked.Root and locked.Root.Position then
                    if isBossName(locked) then
                        S.bossLootPos = locked.Root.Position
                        S.bossLootTime = now
                    else
                        S.mobCorpsePos = locked.Root.Position
                        S.mobCorpseTime = now
                    end
                end
                S.lockedTarget = nil
                locked = nil
                if F.SynTargetLock then
                    S.cbtS = "KILL_WAIT"
                end
            end
        end

        -- Loot-wait: teleport to corpse + hold position while Chest sweeps
        local bossWaiting = S.bossLootPos and (now - S.bossLootTime < (F.SynBossLootWait or 4))
        local mobWaiting  = S.mobCorpsePos and (now - S.mobCorpseTime < (F.SynMobLootWait or 1.8))
        if not locked and (bossWaiting or mobWaiting) then
            local pos = bossWaiting and S.bossLootPos or S.mobCorpsePos
            local cf = CFrame.new(pos + Vector3.new(0, (F.SynHeightOffset or 3.8) + 0.5, 0), pos)
            hrp.CFrame = cf
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            movePlatform(cf)
            S.cbtS = "LOOT_WAIT"; logState("LOOT_WAIT")
            return
        elseif not bossWaiting then S.bossLootPos = nil
        elseif not mobWaiting then S.mobCorpsePos = nil end

        -- Acquire new target
        if not locked then
            S.cbtS = "SCAN"; logState("SCAN")
            local best = pickTarget()
            if best then
                S.lockedTarget = best
                locked = best
            end
        end

        if not locked then
            destroyPlatform()
            -- Auto-travel to target region
            if F.SynAutoTravel and S.regionFilter and S.regionFilter ~= "All" then
                local rp = L.getRegionPos(S.regionFilter)
                if rp and (hrp.Position - rp).Magnitude > 80 then
                    hrp.CFrame = CFrame.new(rp + Vector3.new(0, 3, 0))
                    hrp.AssemblyLinearVelocity = Vector3.zero
                end
            end
            S.cbtS = "NO_TARGET"; logState("NO_TARGET")
            return
        end

        -- Position at target
        positionAt(locked)
        S.cbtS = "STRIKE"; logState("STRIKE")

        -- M1
        if now - (S.lastM1 or 0) >= (F.SynM1Interval or 0.28) then
            S.lastM1 = now
            local count = F.SynMultiHit and (F.SynMultiHitCount or 3) or 1
            fireM1(count, F.SynTrackGuard)
            S.aAt = S.aAt + count
        end

        -- Auto-skill
        fireAutoSkill()
    end

    function A.combatTick()
        local ok, err = pcall(tickInner)
        if not ok then
            if not S._tickErrLogged then
                S._tickErrLogged = true
                warn("[Dingus][Atk] tick error: "..tostring(err))
            end
        else
            S._tickErrLogged = false
        end
    end

    --============================================================
    -- PUBLIC
    --============================================================
    function A.setCategory(cat) S.mobCategory = cat end
    function A.setTargetMob(name) S.targetMob = name end
    function A.setRegion(region) S.regionFilter = region end
    function A.setSelectedBosses(list) S.selectedBosses = list; S.bossIndex = 1 end
    function A.setFarmMode(mode)
        F.SynSafeMode = mode
        if Ctx.Fly and Ctx.Fly.setMode then Ctx.Fly.setMode(mode) end
    end

    function A.teleportTo(name)
        local pos, key = L.findNpcPosition(name)
        if pos then
            local hrp = U.hrp()
            if hrp then
                hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
            return true, key
        end
        return false
    end

    function A.teleportToRegion(region)
        local pos = L.getRegionPos(region)
        if not pos then return false end
        local hrp = U.hrp()
        if hrp then hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
        return true
    end

    function A.forceScan()
        if D.invalidate then D.invalidate() end
        local mobs = findMobs()
        print(string.format("[Dingus] farm scan: %d mobs visible", #mobs))
    end

    function A.telemetry()
        return {
            state = S.cbtS,
            locked = S.lockedTarget and S.lockedTarget.Name or nil,
            targetMob = S.targetMob,
            category = S.mobCategory,
            region = S.regionFilter,
            mode = F.SynSafeMode,
            hits = S.aAt, killCount = S.bKll,
            lootWait = S.bossLootPos ~= nil or S.mobCorpsePos ~= nil,
        }
    end

    function A.forceStopRetreat()
        recoverFreeze()
        S.lockedTarget = nil
        destroyPlatform()
    end

    function A.abortLoot()
        if Ctx.Chest and Ctx.Chest.abort then pcall(Ctx.Chest.abort) end
        S.bossLootPos = nil; S.mobCorpsePos = nil
    end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function()
        destroyPlatform()
        if Ctx.Chest and Ctx.Chest.abort then pcall(Ctx.Chest.abort) end
    end)

    print(string.format(
        "[Dingus][attack] v23 · Synerox-farm · %s · IH=%s SP=%s SC=%s",
        U.Platform,
        tostring(Syn.InputHandler ~= nil),
        tostring(Syn.Skill_Provider ~= nil),
        tostring(Syn.Skill_Controller ~= nil)))
end

return A
