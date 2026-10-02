-- Dingus-Slayer · spoofers.lua v6
-- Mobile-safe: no GetMouseDelta dependency, no antiShakeLock drift.

local Sp = {}

function Sp.init(Ctx)
    local U, Cfg, St = Ctx.Util, Ctx.Cfg, Ctx.St

    Cfg.SpoofMethods = Cfg.SpoofMethods or {}

    St.Spf = St.Spf or {}
    St.spoofFires = St.spoofFires or {}
    St.spoofErrs = St.spoofErrs or {}
    St.spoofLastRun = St.spoofLastRun or {}
    St.spoofActiveCount = 0
    St.spoofLastAFK = 0
    St.spawnTime = os.clock()

    local baseWalk, baseJump
    local lastWrittenWalk

    local function bump(name)
        St.spoofFires[name] = (St.spoofFires[name] or 0) + 1
    end

    local function guard(fn, key)
        local ok, err = pcall(fn)
        if not ok then
            St.spoofErrs[key] = (St.spoofErrs[key] or 0) + 1
            if St.spoofErrs[key] == 1 then
                print("[Dingus][Spoof] "..key.." raised: "..tostring(err))
            end
        elseif St.spoofErrs[key] and St.spoofErrs[key] > 0 then
            St.spoofErrs[key] = 0
        end
    end

    local function enabled(name) return Cfg.SpoofMethods[name] ~= false end

    local function snapshotBases()
        local h = U.hum()
        if not h then return end
        baseWalk = baseWalk or (h.WalkSpeed > 0 and h.WalkSpeed or 16)
        baseJump = baseJump or (h.UseJumpPower and h.JumpPower or 50)
    end

    -- A · Movement
    local function antiSlow()
        local h = U.hum()
        if not h or h.Health <= 0 or h.PlatformStand then return end
        if not baseWalk then snapshotBases() end
        if not baseWalk then return end
        local floor = baseWalk * 0.95
        if h.WalkSpeed < floor and h.WalkSpeed > 0.5 then
            h.WalkSpeed = floor; bump("antiSlow")
        end
    end

    local function antiFreeze()
        local h = U.hum()
        if not h or h.Health <= 0 or h.PlatformStand then return end
        if h.WalkSpeed == 0 and not h.Sit then
            h.WalkSpeed = (baseWalk or 16) * (Cfg.SpoofSpeedMult or 1.25)
            bump("antiFreeze")
        end
    end

    local function spoofWalkSpeed()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        if not baseWalk then snapshotBases() end
        if not baseWalk then return end
        local target = baseWalk * (Cfg.SpoofSpeedMult or 1.25)
        if h.WalkSpeed < baseWalk * 0.9 then return end
        if h.WalkSpeed < target - 0.5 then
            h.WalkSpeed = target
            lastWrittenWalk = target
            bump("spoofWalkSpeed")
        end
    end

    local function spoofJumpPower()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        if not baseJump then snapshotBases() end
        if not baseJump then return end
        if h.UseJumpPower then
            local target = baseJump * (Cfg.SpoofJumpMult or 1.15)
            if h.JumpPower < baseJump * 0.9 then return end
            if h.JumpPower < target - 0.5 then
                h.JumpPower = target; bump("spoofJumpPower")
            end
        end
    end

    -- B · Combat
    local function spoofBlock()
        if not St.cbt then return end
        if (St.zn or 0) == 0 then return end
        local hf = workspace:FindFirstChild("Humanoids")
        local me = hf and hf:FindFirstChild(U.Lp.Name)
        local shcs = me and me:FindFirstChild("SHCS")
        local bv = shcs and shcs:FindFirstChild("Blocking")
        if bv and type(bv.Value) == "number" and bv.Value < 15 then
            bv.Value = 100
            St.Spf.bkC = (St.Spf.bkC or 0) + 1
            bump("spoofBlock")
        end
    end

    local function antiStun()
        local h = U.hum()
        if not h or h.Health <= 0 or h.PlatformStand then return end
        local ok, st = pcall(function() return h:GetState() end)
        if ok and st == Enum.HumanoidStateType.FallingDown then
            pcall(function() h:ChangeState(Enum.HumanoidStateType.Running) end)
            bump("antiStun")
        end
    end

    -- C · Vision
    local function antiFog()
        local L = game:GetService("Lighting")
        if L.FogEnd < 500 and L.FogEnd > 0 then L.FogEnd = 5000; bump("antiFog") end
    end

    local function antiDark()
        local L = game:GetService("Lighting")
        if L.Brightness < 1 then L.Brightness = 2; bump("antiDark") end
    end

    local function antiColor()
        local L = game:GetService("Lighting")
        for _, c in ipairs(L:GetChildren()) do
            if c:IsA("ColorCorrectionEffect") then
                if math.abs(c.Saturation) > 0.3 or math.abs(c.Contrast) > 0.3 then
                    c.Saturation = 0; c.Contrast = 0
                    c.TintColor = Color3.fromRGB(255,255,255)
                    bump("antiColor")
                end
            end
        end
    end

    local function antiBlind()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        for _, c in ipairs(pg:GetChildren()) do
            if c:IsA("ScreenGui") and not c.Name:find("^_c") then
                local bg = c:FindFirstChild("Background", true)
                if bg and bg:IsA("Frame") then
                    if bg.Size.X.Scale >= 1 and bg.Size.Y.Scale >= 1
                       and bg.BackgroundTransparency < 0.3 then
                        bg.BackgroundTransparency = 1; bump("antiBlind")
                    end
                end
            end
        end
    end

    -- E · Position
    local function antiSit()
        local h = U.hum()
        if h and h.Sit then h.Sit = false; bump("antiSit") end
    end

    local function antiVoid()
        local r = U.hrp(); if not r then return end
        if r.Position.Y < (Cfg.SpoofVoidYThreshold or -300) then
            r.CFrame = CFrame.new(0, 50, 0); bump("antiVoid")
        end
    end

    local function antiState()
        local h = U.hum()
        if not h or h.Health <= 0 or h.PlatformStand then return end
        local ok, st = pcall(function() return h:GetState() end)
        if not ok or not st then return end
        if st == Enum.HumanoidStateType.FallingDown
           or st == Enum.HumanoidStateType.Ragdoll
           or st == Enum.HumanoidStateType.Physics then
            pcall(function() h:ChangeState(Enum.HumanoidStateType.Running) end)
            bump("antiState")
        end
    end

    -- F · Persistence
    local function antiAFK()
        local now = U.clock()
        if now - (St.spoofLastAFK or 0) < (Cfg.SpoofAFKInterval or 25) then return end
        St.spoofLastAFK = now
        local h = U.hum(); if not h then return end
        if h.MoveDirection.Magnitude > 0.1 or St.cbt then return end
        pcall(function() h:Move(Vector3.new((math.random()-0.5)*2, 0, (math.random()-0.5)*2)) end)
        task.spawn(function()
            task.wait(0.2)
            local hh = U.hum()
            if hh then pcall(function() hh:Move(Vector3.zero) end) end
        end)
        bump("antiAFK")
    end

    -- I · Locks
    local function antiZoom()
        local cam = workspace.CurrentCamera
        if not cam then return end
        if not Cfg.SpoofBaseFOV then Cfg.SpoofBaseFOV = cam.FieldOfView or 70 end
        if math.abs(cam.FieldOfView - Cfg.SpoofBaseFOV) > 25 then
            cam.FieldOfView = Cfg.SpoofBaseFOV; bump("antiZoom")
        end
    end

    local function antiCinematic()
        local cam = workspace.CurrentCamera
        if not cam then return end
        if cam.CameraType == Enum.CameraType.Scriptable then
            St.spoofCinematicUntil = St.spoofCinematicUntil or (U.clock() + 15)
            if U.clock() > St.spoofCinematicUntil then
                cam.CameraType = Enum.CameraType.Custom
                St.spoofCinematicUntil = 0
                bump("antiCinematic")
            end
        else
            St.spoofCinematicUntil = 0
        end
    end

    local function antiWarp()
        local r = U.hrp(); if not r then return end
        local now = U.clock()
        if not St.spoofLastPos then
            St.spoofLastPos = r.Position; St.spoofLastPosT = now; return
        end
        local dt = now - St.spoofLastPosT
        if dt <= 0 or dt > 1 then St.spoofLastPos = r.Position; St.spoofLastPosT = now; return end
        local jump = (r.Position - St.spoofLastPos).Magnitude
        if jump > 80 and not St.lTele then
            local v = r.AssemblyLinearVelocity
            if v and v.Magnitude > 50 then
                r.AssemblyLinearVelocity = v * 0.5; bump("antiWarp")
            end
        end
        St.spoofLastPos = r.Position; St.spoofLastPosT = now
    end

    local function antiForceField()
        local c = U.Lp.Character; if not c then return end
        for _, ch in ipairs(c:GetChildren()) do
            if ch:IsA("ForceField") then
                local inGrace = (U.clock() - (St.spawnTime or 0)) < 5
                if St.cbt and not inGrace then
                    ch:Destroy(); bump("antiForceField")
                end
            end
        end
    end

    local function antiSeatLock()
        local h = U.hum(); if not h or not h.Sit then return end
        if not St.spoofSitStart then St.spoofSitStart = U.clock(); return end
        if U.clock() - St.spoofSitStart < 2 then return end
        local uis = U.UIS
        local pressing = false
        if uis then
            for _, k in ipairs({Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D}) do
                if uis:IsKeyDown(k) then pressing = true; break end
            end
        end
        if not pressing then h.Sit = false; bump("antiSeatLock") end
        St.spoofSitStart = 0
    end

    -- Mobile: skip GetMouseDelta entirely (returns garbage or errors)
    local function antiShakeLock()
        if U.IsMobile then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        if not St.spoofLastCamCF then St.spoofLastCamCF = cam.CFrame; return end
        local prev = St.spoofLastCamCF
        local dot = prev.LookVector:Dot(cam.CFrame.LookVector)
        local ang = math.deg(math.acos(math.clamp(dot, -1, 1)))
        if ang > 15 then
            local uis = U.UIS
            local md = uis and uis:GetMouseDelta()
            if not md or (math.abs(md.X) <= 3 and math.abs(md.Y) <= 3) then
                cam.CFrame = prev; bump("antiShakeLock")
            end
        end
        St.spoofLastCamCF = cam.CFrame
    end

    local ACTIONS = {
        { key="antiSlow", fn=antiSlow, hz=8 },
        { key="antiFreeze", fn=antiFreeze, hz=8 },
        { key="spoofWalkSpeed", fn=spoofWalkSpeed, hz=5 },
        { key="spoofJumpPower", fn=spoofJumpPower, hz=5 },
        { key="spoofBlock", fn=spoofBlock, hz=8 },
        { key="antiStun", fn=antiStun, hz=10 },
        { key="antiFog", fn=antiFog, hz=1 },
        { key="antiDark", fn=antiDark, hz=1 },
        { key="antiColor", fn=antiColor, hz=1 },
        { key="antiBlind", fn=antiBlind, hz=2 },
        { key="antiSit", fn=antiSit, hz=6 },
        { key="antiVoid", fn=antiVoid, hz=6 },
        { key="antiState", fn=antiState, hz=10 },
        { key="antiAFK", fn=antiAFK, hz=0.2 },
        { key="antiZoom", fn=antiZoom, hz=4 },
        { key="antiCinematic", fn=antiCinematic, hz=2 },
        { key="antiWarp", fn=antiWarp, hz=10 },
        { key="antiForceField", fn=antiForceField, hz=2 },
        { key="antiSeatLock", fn=antiSeatLock, hz=2 },
        { key="antiShakeLock", fn=antiShakeLock, hz=20 },
    }

    for _, a in ipairs(ACTIONS) do a.interval = 1 / math.max(0.1, a.hz) end

    function Sp.tick()
        if not St.gsp then return end
        local now = U.clock()
        local active = 0
        for i = 1, #ACTIONS do
            local a = ACTIONS[i]
            if enabled(a.key) then
                active = active + 1
                if now - (St.spoofLastRun[a.key] or 0) >= a.interval then
                    St.spoofLastRun[a.key] = now
                    guard(a.fn, a.key)
                end
            end
        end
        St.spoofActiveCount = active
    end

    function Sp.stats()
        local out = { enabled = St.gsp, active = St.spoofActiveCount, total = #ACTIONS }
        for _, a in ipairs(ACTIONS) do
            out[a.key] = { on = enabled(a.key), fires = St.spoofFires[a.key] or 0, errors = St.spoofErrs[a.key] or 0 }
        end
        return out
    end

    function Sp.setMethod(name, on)
        Cfg.SpoofMethods[name] = not not on
        return true
    end

    function Sp.listMethods()
        local out = {}
        for i = 1, #ACTIONS do
            out[i] = { key = ACTIONS[i].key, hz = ACTIONS[i].hz, on = enabled(ACTIONS[i].key) }
        end
        return out
    end

    print(string.format("[Dingus][Spoof] v6 · %d methods · %s", #ACTIONS, U.Platform))
end

return Sp
