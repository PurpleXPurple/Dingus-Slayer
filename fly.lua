local F = {}

function F.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local RunService = game:GetService("RunService")

    Cfg.FlySpeed       = Cfg.FlySpeed       or 85
    Cfg.FlySpeedBoost  = Cfg.FlySpeedBoost  or 40
    Cfg.FlyJitter      = Cfg.FlyJitter      or 3
    Cfg.FlyJitterHz    = Cfg.FlyJitterHz    or 1.7
    Cfg.FlyHeight      = Cfg.FlyHeight      or 6
    Cfg.FlyMaxForce    = Cfg.FlyMaxForce    or 1e5
    Cfg.FlyP           = Cfg.FlyP           or 4000
    Cfg.FlyD           = Cfg.FlyD           or 1200
    Cfg.FlyArriveDist  = Cfg.FlyArriveDist  or 10
    Cfg.FlyMinSpeed    = Cfg.FlyMinSpeed    or 40
    Cfg.FlyDetachCam   = Cfg.FlyDetachCam   or false

    F.active = false
    F.bv = nil
    F.bg = nil
    F.hrp = nil
    F.lastPos = nil
    F.lastPosTime = 0
    F.lastProgressTime = 0
    F.lastDistance = math.huge
    F.stuckCount = 0
    F.jitterPhase = 0
    F.lastLog = 0
    F.peakSpeed = 0
    F.avgSpeed = 0
    F.speedSamples = 0
    F.speedSum = 0
    F._origCamSubject = nil
    F._origPlatformStand = false

    local function scrub()
        local hrp = U.hrp()
        if not hrp then return end
        for _, c in ipairs(hrp:GetChildren()) do
            if c:IsA("BodyVelocity") or c:IsA("BodyGyro")
               or c:IsA("BodyPosition") or c:IsA("BodyForce")
               or c:IsA("LinearVelocity") or c:IsA("AlignOrientation")
               or c:IsA("AlignPosition") then
                c:Destroy()
            end
        end
    end

    -- BodyVelocity + BodyGyro on HRP. Parent is Head only if Cfg says so.
    -- Research shows anti-cheats scan HRP for BodyMovers; Head evades some.
    local function makeMovers()
        local hrp = U.hrp()
        if not hrp then return false end
        scrub()

        local target = hrp
        if Cfg.FlyParentHead then
            local head = hrp.Parent and hrp.Parent:FindFirstChild("Head")
            if head then target = head end
        end

        local bv = Instance.new("BodyVelocity")
        bv.Name = "_dgbv"
        bv.MaxForce = Vector3.new(Cfg.FlyMaxForce, Cfg.FlyMaxForce, Cfg.FlyMaxForce)
        bv.P = Cfg.FlyP
        bv.Velocity = Vector3.zero
        bv.Parent = target

        local bg = Instance.new("BodyGyro")
        bg.Name = "_dbg"
        bg.MaxTorque = Vector3.new(4e5, 4e5, 4e5)
        bg.P = 8000
        bg.D = 900
        bg.CFrame = hrp.CFrame
        bg.Parent = target

        F.bv = bv
        F.bg = bg
        F.hrp = hrp
        return true
    end

    local function destroyMovers()
        if F.bv then pcall(function() F.bv:Destroy() end); F.bv = nil end
        if F.bg then pcall(function() F.bg:Destroy() end); F.bg = nil end
        F.hrp = nil
    end

    local function saveCamera()
        if not Cfg.FlyDetachCam then return end
        local cam = workspace.CurrentCamera
        if cam then
            F._origCamSubject = cam.CameraSubject
            local h = U.hum()
            if h then cam.CameraSubject = h end
        end
    end

    local function restoreCamera()
        if not F._origCamSubject then return end
        local cam = workspace.CurrentCamera
        if cam then cam.CameraSubject = F._origCamSubject end
        F._origCamSubject = nil
    end

    function F.start()
        if F.active then return true end
        local h = U.hum()
        if not h then return false end
        if not makeMovers() then return false end

        F._origPlatformStand = h.PlatformStand
        h.PlatformStand = true
        h.WalkSpeed = 0

        F.active = true
        F.lastPos = nil
        F.lastPosTime = U.clock()
        F.lastProgressTime = U.clock()
        F.lastDistance = math.huge
        F.stuckCount = 0
        F.jitterPhase = 0
        F.peakSpeed = 0
        F.avgSpeed = 0
        F.speedSamples = 0
        F.speedSum = 0
        St.FlyActive = true

        saveCamera()
        print("[Dingus][Fly] started")
        return true
    end

    function F.stop()
        if not F.active then return end
        F.active = false
        destroyMovers()

        local h = U.hum()
        if h then
            h.PlatformStand = F._origPlatformStand or false
            h.WalkSpeed = 16
        end

        St.FlyActive = false
        restoreCamera()

        if F.speedSamples > 0 then
            print(string.format("[Dingus][Fly] stopped — avg %.0f peak %.0f studs/s over %d samples",
                F.avgSpeed, F.peakSpeed, F.speedSamples))
        else
            print("[Dingus][Fly] stopped")
        end
    end

    function F.toggle()
        if F.active then F.stop() else F.start() end
    end

    function F.tick(dt)
        if not F.active then return end
        if not St.cbt then F.stop(); return end
        if not St.tgt or not St.tgt.ch.Parent then return end

        local hrp = U.hrp()
        local hum = U.hum()
        if not hrp or not hum then F.stop(); return end
        if hum.Health <= 0 then F.stop(); return end

        local targetHRP = St.tgt.ch:FindFirstChild("HumanoidRootPart")
        if not targetHRP then return end

        local now = U.clock()
        local myPos = hrp.Position
        local targetPos = targetHRP.Position

        local toTarget = targetPos - myPos
        local distance = toTarget.Magnitude

        local bossLook = targetHRP.CFrame.LookVector
        local behindOffset = -bossLook * Cfg.HoverDistance
        local aboveOffset = Vector3.new(0, Cfg.FlyHeight, 0)
        local goalPos = targetPos + behindOffset + aboveOffset

        local toGoal = goalPos - myPos
        local goalDist = toGoal.Magnitude

        if goalDist < Cfg.FlyArriveDist then
            F.bv.Velocity = F.bv.Velocity * 0.75
            local horizontalLook = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
            if (horizontalLook - myPos).Magnitude > 0.5 then
                F.bg.CFrame = CFrame.new(myPos, horizontalLook)
            end
            return
        end

        local dir = toGoal.Unit

        if not F.lastPos then
            F.lastPos = myPos
            F.lastPosTime = now
            F.lastProgressTime = now
        else
            local moved = (myPos - F.lastPos).Magnitude
            if moved > 1 then
                F.lastPos = myPos
                F.lastPosTime = now
            end
            if distance < F.lastDistance - 0.5 then
                F.lastProgressTime = now
                F.lastDistance = distance
                F.stuckCount = 0
            elseif now - F.lastProgressTime > 1.5 then
                F.stuckCount = F.stuckCount + 1
                F.lastProgressTime = now
                if F.stuckCount == 1 or F.stuckCount % 3 == 0 then
                    print(string.format("[Dingus][Fly] stall #%d — boosting", F.stuckCount))
                end
            end
        end

        local speed = Cfg.FlySpeed
        if F.stuckCount > 0 then speed = speed + Cfg.FlySpeedBoost end
        if goalDist < 40 then speed = math.max(Cfg.FlyMinSpeed, speed * (goalDist / 40)) end

        -- Jitter stays. It's the main anti-detection mechanic in this module.
        F.jitterPhase = F.jitterPhase + dt * Cfg.FlyJitterHz * 6.28318
        local jitterX = math.sin(F.jitterPhase) * Cfg.FlyJitter
        local jitterY = math.cos(F.jitterPhase * 0.7) * Cfg.FlyJitter * 0.6
        local jitterZ = math.sin(F.jitterPhase * 1.3) * Cfg.FlyJitter * 0.4

        local right = dir:Cross(Vector3.new(0, 1, 0))
        if right.Magnitude < 0.1 then right = Vector3.new(1, 0, 0) end
        right = right.Unit
        local up = right:Cross(dir).Unit
        local forward = dir

        local jitter = right * jitterX + up * jitterY + forward * jitterZ
        local velocity = dir * speed + jitter

        F.bv.Velocity = velocity

        local horizontalLook = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
        if (horizontalLook - myPos).Magnitude > 0.5 then
            F.bg.CFrame = CFrame.new(myPos, horizontalLook)
        end

        -- Speed telemetry. Clamped report — no raw Infinity in logs.
        local measuredSpeed = 0
        local okV, v = pcall(function() return hrp.AssemblyLinearVelocity.Magnitude end)
        if okV and v and v == v and v < math.huge then measuredSpeed = v end
        F.speedSamples = F.speedSamples + 1
        F.speedSum = F.speedSum + measuredSpeed
        F.avgSpeed = F.speedSum / F.speedSamples
        if measuredSpeed > F.peakSpeed then F.peakSpeed = measuredSpeed end

        if now - F.lastLog > 0.5 then
            F.lastLog = now
            print(string.format(
                "[Dingus][Fly] %s | dist %.0f | goal %.0f | spd %.0f (avg %.0f) | stall %d",
                St.tgt.ch.Name, distance, goalDist, measuredSpeed, F.avgSpeed, F.stuckCount))
        end
    end

    RunService.Heartbeat:Connect(function(dt)
        pcall(F.tick, dt)
    end)

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function() F.stop() end)

    print("[Dingus][fly] v2 initialized")
end

return F
