--[[
    Dingus-Slayer · spoofers.lua v5
    40 methods total (31 retained + 9 new).

    New category I · Environmental lock prevention:
      antiZoom        — FOV reset if server debuffs the camera
      antiCinematic   — CameraType reset if forced into Scriptable
      antiWarp        — damps large position deltas from server
      antiDisarm      — re-equips during combat when held tool is stripped
      antiInvisible   — restores self Transparency if server hides us
      antiForceField  — strips unwanted server ForceField instances
      antiSeatLock    — force-unsits when stuck on a bench/vehicle
      antiSoundSpam   — mutes rapid-fire sounds in a 2s window
      antiShakeLock   — snaps camera back after forced shake drift
]]--

local Sp = {}

function Sp.init(Ctx)
    local U   = Ctx.Util
    local Cfg = Ctx.Cfg
    local St  = Ctx.St

    --================================================================
    -- CONFIG DEFAULTS
    --================================================================
    Cfg.SpoofWriteHz          = Cfg.SpoofWriteHz          or 10
    Cfg.SpoofVerbose          = Cfg.SpoofVerbose          or false
    Cfg.SpoofSpeedMult        = Cfg.SpoofSpeedMult        or 1.25
    Cfg.SpoofJumpMult         = Cfg.SpoofJumpMult         or 1.15
    Cfg.SpoofAntiKnock        = Cfg.SpoofAntiKnock        or false
    Cfg.SpoofKnockThreshold   = Cfg.SpoofKnockThreshold   or 150
    Cfg.SpoofFlingThreshold   = Cfg.SpoofFlingThreshold   or 400
    Cfg.SpoofVoidYThreshold   = Cfg.SpoofVoidYThreshold   or -300
    Cfg.SpoofAFKInterval      = Cfg.SpoofAFKInterval      or 25
    Cfg.SpoofBaseWalk         = Cfg.SpoofBaseWalk         or nil
    Cfg.SpoofBaseJump         = Cfg.SpoofBaseJump         or nil
    Cfg.SpoofBaseGravity      = Cfg.SpoofBaseGravity      or nil

    -- NEW
    Cfg.SpoofBaseFOV          = Cfg.SpoofBaseFOV          or nil
    Cfg.SpoofZoomTolerance    = Cfg.SpoofZoomTolerance    or 25
    Cfg.SpoofWarpThreshold    = Cfg.SpoofWarpThreshold    or 80
    Cfg.SpoofWarpDampen       = Cfg.SpoofWarpDampen       or 0.5
    Cfg.SpoofSoundSpamWindow  = Cfg.SpoofSoundSpamWindow  or 2.0
    Cfg.SpoofSoundSpamCount   = Cfg.SpoofSoundSpamCount   or 5
    Cfg.SpoofShakeThreshold   = Cfg.SpoofShakeThreshold   or 15

    -- Per-method enable flags. Safe defaults on. Risky off.
    local D = {
        -- Movement
        antiSlow = true, antiFreeze = true, antiFall = true,
        spoofWalkSpeed = true, spoofJumpPower = true,
        spoofHipHeight = false, spoofGravity = false,
        -- Combat
        spoofBlock = true, spoofMaxHealth = false,
        antiStun = true, antiRagdoll = false,
        antiKnock = false, antiFling = false,
        -- Vision
        antiBlind = true, antiFog = true, antiDark = true,
        antiShake = true, antiColor = true,
        -- Audio
        antiDeafen = false, antiScream = false,
        -- Position / state
        antiSit = true, antiTeleportBack = false,
        antiVoid = true, antiState = true,
        -- Persistence
        antiAFK = true, antiUnequip = false,
        antiToolDrain = false, antiLoadout = false,
        -- Visuals
        antiNametag = false, antiHighlight = false,
        -- Advanced
        antiSpectate = true,
        -- NEW v5
        antiZoom = true,
        antiCinematic = true,
        antiWarp = true,
        antiDisarm = true,
        antiInvisible = true,
        antiForceField = true,
        antiSeatLock = true,
        antiSoundSpam = false,
        antiShakeLock = true,
    }
    Cfg.SpoofMethods = Cfg.SpoofMethods or D
    for k, v in pairs(D) do
        if Cfg.SpoofMethods[k] == nil then Cfg.SpoofMethods[k] = v end
    end

    local enabled = function(name)
        local m = Cfg.SpoofMethods[name]
        if m == nil then return false end
        return m ~= false
    end

    --================================================================
    -- STATE
    --================================================================
    St.Spf = St.Spf or { hpC=0, bkC=0, spdC=0, kbC=0, jmpC=0 }
    St.spoofFires = {}
    St.spoofErrs = {}
    St.spoofLastRun = {}
    St.spoofActiveCount = 0
    St.spoofLastAFK = 0
    St.spoofLastTeleportCheck = nil
    St.spoofLastHp = 0
    St.spoofPrevGsp = St.gsp
    St.spoofLastPos = nil
    St.spoofLastPosT = 0
    St.spoofLastCamCF = nil
    St.spoofSoundHist = {}
    St.spoofCinematicUntil = 0

    local baseWalk, baseJumpPower, baseJumpHeight, baseGravity
    local lastWrittenWalk, lastWrittenJump
    local blockPath

    local function bump(name)
        St.spoofFires[name] = (St.spoofFires[name] or 0) + 1
        St.Spf.spdC = St.Spf.spdC + 1
    end

    local function guard(fn, key)
        local ok, err = pcall(fn)
        if not ok then
            St.spoofErrs[key] = (St.spoofErrs[key] or 0) + 1
            if St.spoofErrs[key] == 1 then
                print(string.format("[Dingus][Spoof] %s raised: %s",
                    key, tostring(err)))
            end
        elseif St.spoofErrs[key] and St.spoofErrs[key] > 0 then
            St.spoofErrs[key] = 0
        end
        return ok
    end

    --================================================================
    -- SNAPSHOT / RESOLVE
    --================================================================
    local function resolveBaseWalk()
        local h = U.hum()
        if not h then return 16 end
        local ws = h.WalkSpeed
        if type(ws) ~= "number" then return 16 end
        if ws < 16 then return 16 end
        if ws > 24 then return 24 end
        return ws
    end

    local function resolveBaseJump(h)
        if not h then return 50, 7.35 end
        if h.UseJumpPower then
            local jp = h.JumpPower
            if type(jp) ~= "number" then return 50, 7.35 end
            if jp < 50 then jp = 50 end
            if jp > 60 then jp = 60 end
            return jp, 7.35
        end
        local jh = h.JumpHeight
        if type(jh) ~= "number" then return 50, 7.35 end
        if jh < 7.35 then jh = 7.35 end
        if jh > 9 then jh = 9 end
        return 50, jh
    end

    local function snapshotBases()
        local h = U.hum()
        if not h then return end
        baseWalk = Cfg.SpoofBaseWalk or resolveBaseWalk()
        baseJumpPower, baseJumpHeight = resolveBaseJump(h)
        baseGravity = Cfg.SpoofBaseGravity or workspace.Gravity
        if not Cfg.SpoofBaseFOV then
            local cam = workspace.CurrentCamera
            if cam then Cfg.SpoofBaseFOV = cam.FieldOfView or 70 end
        end
    end

    local function restoreDefaults()
        local h = U.hum()
        if not h then return end
        if lastWrittenWalk and h.WalkSpeed == lastWrittenWalk then
            pcall(function() h.WalkSpeed = baseWalk or 16 end)
        end
        if h.UseJumpPower and lastWrittenJump and h.JumpPower == lastWrittenJump then
            pcall(function() h.JumpPower = baseJumpPower or 50 end)
        end
        lastWrittenWalk = nil
        lastWrittenJump = nil
    end

    --================================================================
    -- CATEGORY A · MOVEMENT
    --================================================================
    local function antiSlow()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        if h.Sit or h.PlatformStand then return end
        if not baseWalk then snapshotBases() end
        if not baseWalk then return end
        local floor = baseWalk * 0.95
        if h.WalkSpeed < floor and h.WalkSpeed > 0.5 then
            h.WalkSpeed = floor
            bump("antiSlow")
        end
    end

    local function antiFreeze()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        if h.PlatformStand then return end
        if h.WalkSpeed == 0 and not h.Sit then
            local speed = (baseWalk or 16) * (Cfg.SpoofSpeedMult or 1.25)
            h.WalkSpeed = speed
            bump("antiFreeze")
        end
    end

    local function antiFall()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        local r = U.hrp(); if not r then return end
        local ok, st = pcall(function() return h:GetState() end)
        if not ok or not st then return end
        if st == Enum.HumanoidStateType.Freefall then
            local v = r.AssemblyLinearVelocity
            if v and v.Y > -1 and math.abs(v.Y) < 5 then
                pcall(function() h:ChangeState(Enum.HumanoidStateType.Running) end)
                bump("antiFall")
            end
        end
    end

    local function spoofWalkSpeed()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        if not baseWalk then snapshotBases() end
        if not baseWalk then return end
        local target = baseWalk * (Cfg.SpoofSpeedMult or 1.25)
        local current = h.WalkSpeed
        if current < baseWalk * 0.9 then return end
        if current < target - 0.5 then
            h.WalkSpeed = target
            lastWrittenWalk = target
            bump("spoofWalkSpeed")
        end
    end

    local function spoofJumpPower()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        if not baseJumpPower then snapshotBases() end
        if not baseJumpPower then return end
        if h.UseJumpPower then
            local target = baseJumpPower * (Cfg.SpoofJumpMult or 1.15)
            if h.JumpPower < baseJumpPower * 0.9 then return end
            if h.JumpPower < target - 0.5 then
                h.JumpPower = target
                lastWrittenJump = target
                bump("spoofJumpPower")
            end
        else
            local target = (baseJumpHeight or 7.35) * (Cfg.SpoofJumpMult or 1.15)
            if h.JumpHeight < target - 0.3 then
                h.JumpHeight = target
                bump("spoofJumpPower")
            end
        end
    end

    local function spoofHipHeight()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        local hh = h.HipHeight
        if type(hh) ~= "number" or hh ~= hh or hh < 0 or hh > 6 then
            h.HipHeight = 2
            bump("spoofHipHeight")
        end
    end

    local function spoofGravity()
        local g = workspace.Gravity
        if not baseGravity then snapshotBases() end
        if not baseGravity then return end
        if type(g) ~= "number" or g ~= g then
            workspace.Gravity = baseGravity
            bump("spoofGravity")
        elseif g < baseGravity * 0.9 then
            workspace.Gravity = baseGravity * 0.9
            bump("spoofGravity")
        end
    end

    --================================================================
    -- CATEGORY B · COMBAT STATE
    --================================================================
    local function resolveBlockPath()
        local hf = workspace:FindFirstChild("Humanoids")
        if not hf then return nil end
        local me = hf:FindFirstChild(U.Lp.Name)
        if not me then return nil end
        local shcs = me:FindFirstChild("SHCS")
        if not shcs then return nil end
        local bv = shcs:FindFirstChild("Blocking")
        if bv and bv:IsA("NumberValue") then return bv end
        return nil
    end

    local function spoofBlock()
        if not St.cbt then return end
        if (St.zn or 0) == 0 then return end
        if not blockPath or not blockPath.Parent then
            blockPath = resolveBlockPath()
            if not blockPath then return end
        end
        local v = blockPath.Value
        if type(v) == "number" and v < 15 then
            blockPath.Value = 100
            St.Spf.bkC = St.Spf.bkC + 1
            bump("spoofBlock")
        end
    end

    local function spoofMaxHealth()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        if not St.mxH or St.mxH <= 0 then St.mxH = h.MaxHealth end
        if h.MaxHealth < St.mxH then
            h.MaxHealth = St.mxH
            bump("spoofMaxHealth")
        elseif h.MaxHealth > St.mxH then
            St.mxH = h.MaxHealth
        end
    end

    local function antiStun()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        if h.PlatformStand then return end
        local ok, st = pcall(function() return h:GetState() end)
        if not ok or not st then return end
        if st == Enum.HumanoidStateType.FallingDown then
            pcall(function() h:ChangeState(Enum.HumanoidStateType.Running) end)
            bump("antiStun")
        end
    end

    local function antiRagdoll()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        if h.PlatformStand then return end
        local ok, st = pcall(function() return h:GetState() end)
        if not ok or not st then return end
        if st == Enum.HumanoidStateType.Ragdoll
           or st == Enum.HumanoidStateType.Physics then
            pcall(function() h:ChangeState(Enum.HumanoidStateType.Running) end)
            bump("antiRagdoll")
        end
    end

    local function antiKnock()
        if not Cfg.SpoofAntiKnock then return end
        local r = U.hrp(); local h = U.hum()
        if not r or not h or h.Health <= 0 then return end
        local ok, st = pcall(function() return h:GetState() end)
        if ok and st then
            if st == Enum.HumanoidStateType.Jumping
               or st == Enum.HumanoidStateType.Freefall
               or st == Enum.HumanoidStateType.Swimming then
                return
            end
        end
        local v = r.AssemblyLinearVelocity
        if not v then return end
        if v.Magnitude < Cfg.SpoofKnockThreshold then return end
        local hx, hz = v.X, v.Z
        local hm = math.sqrt(hx*hx + hz*hz)
        if hm > 120 then
            local scale = 120 / hm
            r.AssemblyLinearVelocity = Vector3.new(hx * scale, v.Y, hz * scale)
            St.Spf.kbC = St.Spf.kbC + 1
            bump("antiKnock")
        end
    end

    local function antiFling()
        local r = U.hrp(); if not r then return end
        local v = r.AssemblyLinearVelocity
        if not v then return end
        if v.Magnitude > Cfg.SpoofFlingThreshold then
            r.AssemblyLinearVelocity = Vector3.zero
            bump("antiFling")
        end
    end

    --================================================================
    -- CATEGORY C · VISION
    --================================================================
    local function antiBlind()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        for _, c in ipairs(pg:GetChildren()) do
            if c:IsA("ScreenGui") and c.Name ~= "DingusUI"
               and not c.Name:find("^_c") then
                local btr = c:FindFirstChild("Background", true)
                if btr and btr:IsA("Frame") then
                    local sz = btr.Size
                    if sz.X.Scale >= 1 and sz.Y.Scale >= 1
                       and btr.BackgroundTransparency < 0.3 then
                        btr.BackgroundTransparency = 1
                        bump("antiBlind")
                    end
                end
            end
        end
    end

    local function antiFog()
        local L = game:GetService("Lighting")
        if L.FogEnd < 500 and L.FogEnd > 0 then
            L.FogEnd = 5000
            bump("antiFog")
        end
    end

    local function antiDark()
        local L = game:GetService("Lighting")
        if L.Brightness < 1 then
            L.Brightness = 2
            bump("antiDark")
        end
        if L.OutdoorAmbient.R + L.OutdoorAmbient.G + L.OutdoorAmbient.B < 0.5 then
            L.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
            bump("antiDark")
        end
    end

    local function antiShake()
        local cam = workspace.CurrentCamera
        if not cam then return end
        if cam.CFrame ~= cam.CFrame then
            local h = U.hum()
            if h then
                pcall(function() cam.CameraSubject = h end)
                bump("antiShake")
            end
        end
    end

    local function antiColor()
        local L = game:GetService("Lighting")
        for _, c in ipairs(L:GetChildren()) do
            if c:IsA("ColorCorrectionEffect") then
                if math.abs(c.Saturation - 0) > 0.3
                   or math.abs(c.Contrast - 0) > 0.3 then
                    c.Saturation = 0
                    c.Contrast = 0
                    c.TintColor = Color3.fromRGB(255, 255, 255)
                    bump("antiColor")
                end
            end
        end
    end

    --================================================================
    -- CATEGORY D · AUDIO
    --================================================================
    local function antiDeafen()
        local ss = game:GetService("SoundService")
        if ss.AmbientReverb ~= Enum.ReverbType.NoReverb then
            ss.AmbientReverb = Enum.ReverbType.NoReverb
            bump("antiDeafen")
        end
    end

    local function antiScream()
        local r = U.hrp(); if not r then return end
        local myPos = r.Position
        for _, s in ipairs(workspace:GetChildren()) do
            if s:IsA("Sound") and s.IsPlaying and s.Volume > 3 then
                local parent = s.Parent
                if parent and parent:IsA("BasePart") then
                    if (parent.Position - myPos).Magnitude < 30 then
                        s.Volume = 1
                        bump("antiScream")
                    end
                end
            end
        end
    end

    --================================================================
    -- CATEGORY E · POSITION / STATE
    --================================================================
    local function antiSit()
        local h = U.hum()
        if not h then return end
        if h.Sit then
            h.Sit = false
            bump("antiSit")
        end
    end

    local function antiTeleportBack()
        local r = U.hrp(); if not r then return end
        local now = U.clock()
        local last = St.spoofLastTeleportCheck
        if last then
            local dt = now - last.t
            if dt > 0 and dt < 0.2 then
                local dist = (r.Position - last.p).Magnitude
                if dist > 100 then
                    if Cfg.SpoofVerbose then
                        print(string.format(
                            "[Dingus][Spoof] teleport-back: %.0f studs", dist))
                    end
                    bump("antiTeleportBack")
                end
            end
        end
        St.spoofLastTeleportCheck = { t = now, p = r.Position }
    end

    local function antiVoid()
        local r = U.hrp(); if not r then return end
        if r.Position.Y < Cfg.SpoofVoidYThreshold then
            local ok, cf = pcall(function() return CFrame.new(0, 50, 0) end)
            if ok and cf then
                r.CFrame = cf
                bump("antiVoid")
                print("[Dingus][Spoof] void rescue")
            end
        end
    end

    local function antiState()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        if h.PlatformStand then return end
        local ok, st = pcall(function() return h:GetState() end)
        if not ok or not st then return end
        local bad = {
            [Enum.HumanoidStateType.FallingDown] = true,
            [Enum.HumanoidStateType.Ragdoll]     = true,
            [Enum.HumanoidStateType.Physics]     = true,
        }
        if bad[st] then
            pcall(function() h:ChangeState(Enum.HumanoidStateType.Running) end)
            bump("antiState")
        end
    end

    --================================================================
    -- CATEGORY F · PERSISTENCE
    --================================================================
    local function antiAFK()
        local now = U.clock()
        if now - (St.spoofLastAFK or 0) < (Cfg.SpoofAFKInterval or 25) then return end
        St.spoofLastAFK = now
        local h = U.hum(); if not h then return end
        if h.MoveDirection.Magnitude > 0.1 then return end
        if St.cbt then return end
        pcall(function()
            h:Move(Vector3.new(
                (math.random() - 0.5) * 2, 0,
                (math.random() - 0.5) * 2))
        end)
        task.spawn(function()
            task.wait(0.2)
            local hh = U.hum()
            if hh then pcall(function() hh:Move(Vector3.zero) end) end
        end)
        bump("antiAFK")
    end

    local function antiUnequip()
        local h = U.hum(); if not h then return end
        local c = U.Lp.Character; if not c then return end
        local eq = nil
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") then eq = t; break end
        end
        if eq then return end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if not bp then return end
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then
                pcall(function() h:EquipTool(t) end)
                bump("antiUnequip")
                return
            end
        end
    end

    local function antiToolDrain()
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if not bp then return end
        local count = 0
        for _ in ipairs(bp:GetChildren()) do count = count + 1 end
        if not St.spoofLastToolCount then
            St.spoofLastToolCount = count
        elseif count < St.spoofLastToolCount - 3 then
            print(string.format("[Dingus][Spoof] tool count: %d -> %d",
                St.spoofLastToolCount, count))
            St.spoofLastToolCount = count
            bump("antiToolDrain")
        else
            St.spoofLastToolCount = count
        end
    end

    local function antiLoadout()
        if not Cfg.SpoofLoadoutTool then return end
        local h = U.hum(); if not h then return end
        local c = U.Lp.Character; if not c then return end
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and t.Name == Cfg.SpoofLoadoutTool then return end
        end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if not bp then return end
        local want = bp:FindFirstChild(Cfg.SpoofLoadoutTool)
        if want and want:IsA("Tool") then
            pcall(function() h:EquipTool(want) end)
            bump("antiLoadout")
        end
    end

    --================================================================
    -- CATEGORY G · VISUALS
    --================================================================
    local function antiNametag()
        local h = U.hum(); if not h then return end
        if h.NameDisplayDistance > 0 then
            h.NameDisplayDistance = 0
            h.HealthDisplayDistance = 0
            bump("antiNametag")
        end
    end

    local function antiHighlight()
        local c = U.Lp.Character; if not c then return end
        for _, ch in ipairs(c:GetChildren()) do
            if ch:IsA("Highlight") then
                ch:Destroy()
                bump("antiHighlight")
            end
        end
    end

    --================================================================
    -- CATEGORY H · ADVANCED
    --================================================================
    local function antiSpectate()
        local cam = workspace.CurrentCamera
        if not cam then return end
        local h = U.hum(); if not h then return end
        if cam.CameraSubject ~= h then
            if not St.FlyActive then
                pcall(function() cam.CameraSubject = h end)
                bump("antiSpectate")
            end
        end
    end

    --================================================================
    -- CATEGORY I · LOCK PREVENTION (NEW v5)
    --================================================================

    -- Restore FOV if the server debuffs the camera zoom
    local function antiZoom()
        local cam = workspace.CurrentCamera
        if not cam then return end
        if not Cfg.SpoofBaseFOV then snapshotBases() end
        local base = Cfg.SpoofBaseFOV or 70
        local fov = cam.FieldOfView
        if type(fov) ~= "number" or fov ~= fov then
            cam.FieldOfView = base
            bump("antiZoom")
            return
        end
        local tol = Cfg.SpoofZoomTolerance or 25
        if math.abs(fov - base) > tol then
            cam.FieldOfView = base
            bump("antiZoom")
        end
    end

    -- Reset CameraType if forced into Scriptable for non-cutscene reasons
    local function antiCinematic()
        local cam = workspace.CurrentCamera
        if not cam then return end
        if St.FlyActive then return end
        -- Let user-triggered cinematics through: allow Scriptable for
        -- up to 15s after they happen, then revert.
        if cam.CameraType == Enum.CameraType.Scriptable then
            if St.spoofCinematicUntil == 0 then
                St.spoofCinematicUntil = U.clock() + 15
                return
            end
            if U.clock() > St.spoofCinematicUntil then
                cam.CameraType = Enum.CameraType.Custom
                St.spoofCinematicUntil = 0
                bump("antiCinematic")
            end
        else
            St.spoofCinematicUntil = 0
        end
    end

    -- Damp large position jumps between ticks that aren't from our teleport
    local function antiWarp()
        local r = U.hrp(); if not r then return end
        local now = U.clock()
        if not St.spoofLastPos then
            St.spoofLastPos = r.Position
            St.spoofLastPosT = now
            return
        end
        local dt = now - St.spoofLastPosT
        if dt <= 0 or dt > 1.0 then
            St.spoofLastPos = r.Position
            St.spoofLastPosT = now
            return
        end
        local jump = (r.Position - St.spoofLastPos).Magnitude
        local threshold = Cfg.SpoofWarpThreshold or 80
        -- Our teleport-chase is intentional, so ignore jumps under 30
        -- after a known teleport flag.
        if jump > threshold and not St.lTele or (St.lTele and now - St.lTele > 0.3) then
            -- Attempt to damp velocity if the server is warping us
            local v = r.AssemblyLinearVelocity
            if v and v.Magnitude > 50 then
                local scale = Cfg.SpoofWarpDampen or 0.5
                r.AssemblyLinearVelocity = v * scale
                bump("antiWarp")
            end
        end
        St.spoofLastPos = r.Position
        St.spoofLastPosT = now
    end

    -- Re-equip during combat when held tool is stripped
    local function antiDisarm()
        if not St.cbt then return end
        local h = U.hum(); if not h or h.Health <= 0 then return end
        local c = U.Lp.Character; if not c then return end
        local hasTool = false
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") then hasTool = true; break end
        end
        if hasTool then return end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if not bp then return end
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then
                pcall(function() h:EquipTool(t) end)
                bump("antiDisarm")
                return
            end
        end
    end

    -- Restore self Transparency if the server hides the character
    local function antiInvisible()
        local c = U.Lp.Character; if not c then return end
        for _, p in ipairs(c:GetChildren()) do
            if p:IsA("BasePart") then
                local t = p.LocalTransparencyModifier
                if type(t) == "number" and t > 0.9 and t <= 1 then
                    -- Only repair if not intentionally hidden (stealth VFX)
                    local hasStealthVFX = false
                    for _, ch in ipairs(c:GetChildren()) do
                        if ch.Name:find("Invis", 1, true)
                           or ch.Name:find("Stealth", 1, true) then
                            hasStealthVFX = true
                            break
                        end
                    end
                    if not hasStealthVFX then
                        p.LocalTransparencyModifier = 0
                        p.Transparency = 0
                        bump("antiInvisible")
                    end
                end
            end
        end
    end

    -- Remove server ForceField instances that weren't player-requested
    local function antiForceField()
        local c = U.Lp.Character; if not c then return end
        for _, ch in ipairs(c:GetChildren()) do
            if ch:IsA("ForceField") then
                -- Only strip if we're in combat and past spawn grace
                local inSpawnGrace = (U.clock() - (St.spawnTime or 0)) < 5
                if St.cbt and not inSpawnGrace then
                    pcall(function() ch:Destroy() end)
                    bump("antiForceField")
                end
            end
        end
    end

    -- Force unsit when stuck on a bench/vehicle
    local function antiSeatLock()
        local h = U.hum(); if not h then return end
        if not h.Sit then return end
        -- Only force-unsit if we've been sitting for >2s and aren't moving
        if not St.spoofSitStart then
            St.spoofSitStart = U.clock()
            return
        end
        if U.clock() - St.spoofSitStart < 2.0 then return end
        -- If user is not actively pressing movement keys, unsit
        local uis = U.UIS
        local pressing = false
        if uis then
            local keys = { Enum.KeyCode.W, Enum.KeyCode.A,
                           Enum.KeyCode.S, Enum.KeyCode.D,
                           Enum.KeyCode.Space }
            for _, k in ipairs(keys) do
                if uis:IsKeyDown(k) then pressing = true; break end
            end
        end
        if not pressing then
            h.Sit = false
            bump("antiSeatLock")
        end
        St.spoofSitStart = 0
    end

    -- Mute repeated sounds clustered within a short window
    local function antiSoundSpam()
        local r = U.hrp(); if not r then return end
        local now = U.clock()
        local window = Cfg.SpoofSoundSpamWindow or 2.0
        local limit = Cfg.SpoofSoundSpamCount or 5
        -- Prune history
        for i = #St.spoofSoundHist, 1, -1 do
            if now - St.spoofSoundHist[i].t > window then
                table.remove(St.spoofSoundHist, i)
            end
        end
        -- Count sounds playing near us
        local soundsNear = {}
        for _, s in ipairs(workspace:GetChildren()) do
            if s:IsA("Sound") and s.IsPlaying and s.Volume > 1 then
                local parent = s.Parent
                if parent and parent:IsA("BasePart") then
                    if (parent.Position - r.Position).Magnitude < 25 then
                        soundsNear[s.Name] = (soundsNear[s.Name] or 0) + 1
                    end
                end
            end
        end
        for name, count in pairs(soundsNear) do
            if count >= limit then
                -- Track it and mute for a bit
                table.insert(St.spoofSoundHist, { t = now, name = name })
                for _, s in ipairs(workspace:GetChildren()) do
                    if s:IsA("Sound") and s.Name == name and s.IsPlaying then
                        local parent = s.Parent
                        if parent and parent:IsA("BasePart")
                           and (parent.Position - r.Position).Magnitude < 25 then
                            s.Volume = 0
                        end
                    end
                end
                bump("antiSoundSpam")
            end
        end
    end

    -- Snap camera back after a forced shake offset
    local function antiShakeLock()
        local cam = workspace.CurrentCamera
        if not cam then return end
        if St.FlyActive then return end
        local cf = cam.CFrame
        if not St.spoofLastCamCF then
            St.spoofLastCamCF = cf
            return
        end
        -- Get the rotational delta between frames
        local prev = St.spoofLastCamCF
        local dot = prev.LookVector:Dot(cf.LookVector)
        local angleDelta = math.deg(math.acos(math.clamp(dot, -1, 1)))
        local threshold = Cfg.SpoofShakeThreshold or 15
        -- If camera rotated > threshold degrees in one tick without input,
        -- snap it back
        if angleDelta > threshold then
            local uis = U.UIS
            local mouseDelta = false
            if uis then
                local md = uis:GetMouseDelta()
                if md and (math.abs(md.X) > 3 or math.abs(md.Y) > 3) then
                    mouseDelta = true
                end
            end
            if not mouseDelta then
                pcall(function() cam.CFrame = prev end)
                bump("antiShakeLock")
            end
        end
        St.spoofLastCamCF = cam.CFrame
    end

    --================================================================
    -- REGISTRY
    --================================================================
    local ACTIONS = {
        -- A · Movement
        { key = "antiSlow",         fn = antiSlow,         hz = 8 },
        { key = "antiFreeze",       fn = antiFreeze,       hz = 8 },
        { key = "antiFall",         fn = antiFall,         hz = 10 },
        { key = "spoofWalkSpeed",   fn = spoofWalkSpeed,   hz = 5 },
        { key = "spoofJumpPower",   fn = spoofJumpPower,   hz = 5 },
        { key = "spoofHipHeight",   fn = spoofHipHeight,   hz = 4 },
        { key = "spoofGravity",     fn = spoofGravity,     hz = 2 },
        -- B · Combat state
        { key = "spoofBlock",       fn = spoofBlock,       hz = 8 },
        { key = "spoofMaxHealth",   fn = spoofMaxHealth,   hz = 5 },
        { key = "antiStun",         fn = antiStun,         hz = 10 },
        { key = "antiRagdoll",      fn = antiRagdoll,      hz = 10 },
        { key = "antiKnock",        fn = antiKnock,        hz = 10 },
        { key = "antiFling",        fn = antiFling,        hz = 10 },
        -- C · Vision
        { key = "antiBlind",        fn = antiBlind,        hz = 2 },
        { key = "antiFog",          fn = antiFog,          hz = 1 },
        { key = "antiDark",         fn = antiDark,         hz = 1 },
        { key = "antiShake",        fn = antiShake,        hz = 4 },
        { key = "antiColor",        fn = antiColor,        hz = 1 },
        -- D · Audio
        { key = "antiDeafen",       fn = antiDeafen,       hz = 1 },
        { key = "antiScream",       fn = antiScream,       hz = 4 },
        -- E · Position
        { key = "antiSit",          fn = antiSit,          hz = 6 },
        { key = "antiTeleportBack", fn = antiTeleportBack, hz = 8 },
        { key = "antiVoid",         fn = antiVoid,         hz = 6 },
        { key = "antiState",        fn = antiState,        hz = 10 },
        -- F · Persistence
        { key = "antiAFK",          fn = antiAFK,          hz = 0.2 },
        { key = "antiUnequip",      fn = antiUnequip,      hz = 2 },
        { key = "antiToolDrain",    fn = antiToolDrain,    hz = 0.5 },
        { key = "antiLoadout",      fn = antiLoadout,      hz = 1 },
        -- G · Visuals
        { key = "antiNametag",      fn = antiNametag,      hz = 2 },
        { key = "antiHighlight",    fn = antiHighlight,    hz = 2 },
        -- H · Advanced
        { key = "antiSpectate",     fn = antiSpectate,     hz = 2 },
        -- I · Lock prevention (v5)
        { key = "antiZoom",         fn = antiZoom,         hz = 4 },
        { key = "antiCinematic",    fn = antiCinematic,    hz = 2 },
        { key = "antiWarp",         fn = antiWarp,         hz = 10 },
        { key = "antiDisarm",       fn = antiDisarm,       hz = 2 },
        { key = "antiInvisible",    fn = antiInvisible,    hz = 4 },
        { key = "antiForceField",   fn = antiForceField,   hz = 2 },
        { key = "antiSeatLock",     fn = antiSeatLock,     hz = 2 },
        { key = "antiSoundSpam",    fn = antiSoundSpam,    hz = 4 },
        { key = "antiShakeLock",    fn = antiShakeLock,    hz = 20 },
    }

    for _, a in ipairs(ACTIONS) do
        a.interval = 1 / math.max(0.1, a.hz)
        St.spoofLastRun[a.key] = 0
    end

    --================================================================
    -- RESPAWN
    --================================================================
    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(1.5)
            baseWalk, baseJumpPower, baseJumpHeight = nil, nil, nil
            lastWrittenWalk, lastWrittenJump = nil, nil
            blockPath = nil
            St.spoofLastToolCount = nil
            St.spoofLastTeleportCheck = nil
            St.spoofLastPos = nil
            St.spoofLastCamCF = nil
            St.spoofSoundHist = {}
            St.spoofSitStart = 0
            St.spoofCinematicUntil = 0
            St.spawnTime = U.clock()
            St.mxH = 0
        end)
    end
    St.spawnTime = U.clock()

    --================================================================
    -- TICK
    --================================================================
    function Sp.tick()
        if not St.gsp then
            if St.spoofPrevGsp then
                St.spoofPrevGsp = false
                pcall(restoreDefaults)
            end
            return
        end
        if not St.spoofPrevGsp then
            St.spoofPrevGsp = true
        end

        local now = U.clock()
        local active = 0
        for i = 1, #ACTIONS do
            local a = ACTIONS[i]
            if enabled(a.key) then
                active = active + 1
                if now - St.spoofLastRun[a.key] >= a.interval then
                    St.spoofLastRun[a.key] = now
                    guard(a.fn, a.key)
                end
            end
        end
        St.spoofActiveCount = active
    end

    --================================================================
    -- DEPRECATED STUBS
    --================================================================
    local ugWarned = false
    function Sp.goUnderground()
        if ugWarned then return end
        ugWarned = true
        print("[Dingus][Spoof] goUnderground removed — no-op")
    end
    function Sp.surfaceUp() end
    function Sp.checkUG() end

    --================================================================
    -- PUBLIC
    --================================================================
    function Sp.stats()
        local out = {
            enabled = St.gsp,
            activeMethods = St.spoofActiveCount or 0,
            totalMethods = #ACTIONS,
        }
        for _, a in ipairs(ACTIONS) do
            out[a.key] = {
                on     = enabled(a.key),
                fires  = St.spoofFires[a.key] or 0,
                errors = St.spoofErrs[a.key] or 0,
            }
        end
        return out
    end

    function Sp.setMethod(name, on)
        if Cfg.SpoofMethods[name] == nil then
            -- Allow adding new keys dynamically
            Cfg.SpoofMethods[name] = not not on
            return true
        end
        Cfg.SpoofMethods[name] = not not on
        return true
    end

    function Sp.listMethods()
        local out = {}
        for i = 1, #ACTIONS do
            local a = ACTIONS[i]
            out[i] = { key = a.key, hz = a.hz, on = enabled(a.key) }
        end
        return out
    end

    if St.gsp then
        print(string.format(
            "[Dingus][Spoof] v5 loaded · %d methods registered", #ACTIONS))
    else
        print(string.format(
            "[Dingus][Spoof] v5 loaded · %d methods registered · master OFF",
            #ACTIONS))
    end
end

return Sp
