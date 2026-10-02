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
        local ns = string
