--[[
    Dingus-Slayer · fly.lua v3
    Noclip · network-owner claim · CFrame fallback · progress watchdog.

    Diagnosis from runtime logs:
      bv.Velocity = 85, hrp.AssemblyLinearVelocity ≈ 2-31
      → server reconciliation rejects BodyVelocity motion.

    Fixes:
      - Noclip: character parts CanCollide = false, session-persistent
      - SetNetworkOwner(player) attempted at start; logged on failure
      - CFrame fallback: switches mode when BV fails for 20 ticks
      - Progress trend in telemetry so stalls are visible in F9
      - Reduced jitter (was causing micro-oscillation)
]]--

local F = {}

function F.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local RunService = game:GetService("RunService")

    Cfg.FlySpeed             = Cfg.FlySpeed or 85
    Cfg.FlySpeedBoost        = Cfg.FlySpeedBoost or 40
    Cfg.FlyJitter            = Cfg.FlyJitter or 2
    Cfg.FlyJitterHz          = Cfg.FlyJitterHz or 1.7
    Cfg.FlyHeight            = Cfg.FlyHeight or 6
    Cfg.FlyMaxForce          = Cfg.FlyMaxForce or 1e5
    Cfg.FlyP                 = Cfg.FlyP or 4000
    Cfg.FlyD                 = Cfg.FlyD or 1200
    Cfg.FlyArriveDist        = Cfg.FlyArriveDist or 10
    Cfg.FlyMinSpeed          = Cfg.FlyMinSpeed or 40
    Cfg.FlyNoclip            = Cfg.FlyNoclip ~= false
    Cfg.FlyClaimNetworkOwner = Cfg.FlyClaimNetworkOwner ~= false
    Cfg.FlyCFrameFallback    = Cfg.FlyCFrameFallback ~= false
    Cfg.FlyCFrameThreshold   = Cfg.FlyCFrameThreshold or 0.3
    Cfg.FlyCFrameFailTicks   = Cfg.FlyCFrameFailTicks or 20

    F.active = false
    F.bv = nil
    F.bg = nil
    F.hrp = nil
    F.mode = "bv"          -- "bv" | "cframe"
    F.velFailCount = 0
    F.lastPos = nil
    F.lastProgressTime = 0
    F.lastDistance = math.huge
    F.stuckCount = 0
    F.jitterPhase = 0
    F.lastLog = 0
    F.peakSpeed = 0
    F.avgSpeed = 0
    F.speedSamples = 0
    F.speedSum = 0
    F._origPlatformStand = false
    F._origWalkSpeed = 16
    F._lastLoggedDist = nil

    --============================================================
    -- NOCLIP · session-persistent
    --============================================================
    if Cfg.FlyNoclip then
        local function disableCollision(part)
            if part and part:IsA("BasePart") then
                pcall(function() part.CanCollide = false end)
            end
        end
        local noclipConn = nil
        local function bindNoclip(char)
            if not char then return end
            if noclipConn then
                pcall(function() noclipConn:Disconnect() end)
            end
            for _, p in ipairs(char:GetDescendants()) do
                disableCollision(p)
            end
            noclipConn = char.DescendantAdded:Connect(disableCollision)
        end
        bindNoclip(U.Lp.Character)
        U.Lp.CharacterAdded:Connect(function(c)
            task.wait(0.5)
            bindNoclip(c)
        end)
        print("[Dingus][Fly] noclip enabled")
    end

    --============================================================
    -- MOVERS
    --============================================================
    local function scrub()
        local hrp = U.hrp()
        if not hrp then return end
        for _, c in ipairs(hrp:GetChildren()) do
            if c.Name == "_dgbv" or c.Name == "_dbg" then
                c:Destroy()
            end
        end
    end

    local function claimNetworkOwner()
        if not Cfg.FlyClaimNetworkOwner then return end
        local hrp = U.hrp()
        if not hrp then return end
        local ok, err = pcall(function()
            hrp:SetNetworkOwner(U.Lp)
        end)
        if not ok then
            print("[Dingus][Fly] SetNetworkOwner failed: " .. tostring(err))
        end
    end

    local function makeMovers()
        local hrp = U.hrp()
        if not hrp then return false end
        scrub()

        local bv = Instance.new("BodyVelocity")
        bv.Name = "_dgbv"
        bv.MaxForce = Vector3.new(Cfg.FlyMaxForce, Cfg.FlyMaxForce, Cfg.FlyMaxForce)
        bv.P = Cfg.FlyP
        bv.Velocity = Vector3.zero
        bv.Parent = hrp

        local bg = Instance.new("BodyGyro")
        bg.Name = "_dbg"
        bg.MaxTorque = Vector3.new(4e5, 4e5, 4e5)
        bg.P = 8000
        bg.D = 900
        bg.CFrame = hrp.CFrame
        bg.Parent = hrp

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

    --============================================================
    -- PUBLIC
    --============================================================
    function F.start()
        if F.active then return true end
        local h = U.hum()
        if not h then return false end
        if not makeMovers() then return false end

        F._origPlatformStand = h.PlatformStand
        F._origWalkSpeed = h.WalkSpeed
        h.PlatformStand = true
        h.WalkSpeed = 0

        F.active = true
        F.mode = "bv"
        F.velFailCount = 0
        F.lastPos = nil
        F.lastProgressTime = U.clock()
        F.lastDistance = math.huge
        F.stuckCount = 0
        F.jitterPhase = 0
        F.peakSpeed = 0
        F.avgSpeed = 0
        F.speedSamples = 0
        F.speedSum = 0
        F._lastLoggedDist = nil
        St.FlyActive = true

        claimNetworkOwner()
        print("[Dingus][Fly] started")
        return true
    end

    function F.stop()
        if not F.active then return end
        F.active = false
        F.mode = "bv"
        destroyMovers()

        local h = U.hum()
        if h then
            h.PlatformStand = F._origPlatformStand or false
            h.WalkSpeed = F._origWalkSpeed or 16
        end
        St.FlyActive = false

        if F.speedSamples > 0 then
            print(string.format(
                "[Dingus][Fly] stopped — avg %.0f peak %.0f over %d samples",
                F.avgSpeed, F.peakSpeed, F.speedSamples))
        else
            print("[Dingus][Fly] stopped")
        end
    end

    function F.toggle()
        if F.active then F.stop() else F.start() end
    end

    --============================================================
    -- TICK
    --============================================================
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

        local bossLook = targetHRP.CFrame.LookVector
        local goalPos = targetPos
            - bossLook * Cfg.HoverDistance
            + Vector3.new(0, Cfg.FlyHeight, 0)

        local toGoal = goalPos - myPos
        local goalDist = toGoal.Magnitude
        local distance = (targetPos - myPos).Magnitude

        -- Arrived
        if goalDist < Cfg.FlyArriveDist then
            if F.mode == "bv" and F.bv then
                F.bv.Velocity = F.bv.Velocity * 0.75
            end
            local hLook = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
            if (hLook - myPos).Magnitude > 0.5 then
                if F.mode == "bv" and F.bg then
                    F.bg.CFrame = CFrame.new(myPos, hLook)
                else
                    pcall(function()
                        hrp.CFrame = CFrame.new(myPos, hLook)
                    end)
                end
            end
            return
        end

        local dir = toGoal.Unit

        -- Stall
        if not F.lastPos then
            F.lastPos = myPos
            F.lastProgressTime = now
        else
            if distance < F.lastDistance - 0.5 then
                F.lastProgressTime = now
                F.lastDistance = distance
                F.stuckCount = 0
            elseif now - F.lastProgressTime > 1.5 then
                F.stuckCount = F.stuckCount + 1
                F.lastProgressTime = now
            end
            F.lastPos = myPos
        end

        local speed = Cfg.FlySpeed
        if F.stuckCount > 0 then speed = speed + Cfg.FlySpeedBoost end
        if goalDist < 40 then
            speed = math.max(Cfg.FlyMinSpeed, speed * (goalDist / 40))
        end

        -- Jitter (small)
        F.jitterPhase = F.jitterPhase + dt * Cfg.FlyJitterHz * 6.28318
        local jx = math.sin(F.jitterPhase) * Cfg.FlyJitter
        local jy = math.cos(F.jitterPhase * 0.7) * Cfg.FlyJitter * 0.6
        local jz = math.sin(F.jitterPhase * 1.3) * Cfg.FlyJitter * 0.4

        local right = dir:Cross(Vector3.new(0, 1, 0))
        if right.Magnitude < 0.1 then right = Vector3.new(1, 0, 0) end
        right = right.Unit
        local up = right:Cross(dir).Unit
        local jitter = right * jx + up * jy + dir * jz

        local velocity = dir * speed + jitter

        -- Apply
        if F.mode == "bv" then
            if not F.bv or not F.bv.Parent then
                F.mode = "cframe"
            else
                F.bv.Velocity = velocity
                if F.bg and F.bg.Parent then
                    local hLook = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
                    if (hLook - myPos).Magnitude > 0.5 then
                        F.bg.CFrame = CFrame.new(myPos, hLook)
                    end
                end
            end
        end

        if F.mode == "cframe" then
            local step = velocity * dt
            pcall(function()
                hrp.CFrame = hrp.CFrame + step
            end)
        end

        -- Measure
        local measured = 0
        local okV, v = pcall(function() return hrp.AssemblyLinearVelocity.Magnitude end)
        if okV and v and v == v and v < math.huge then measured = v end

        -- Fallback decision
        if F.mode == "bv" and Cfg.FlyCFrameFallback then
            if measured < speed * Cfg.FlyCFrameThreshold then
                F.velFailCount = F.velFailCount + 1
            else
                F.velFailCount = 0
            end
            if F.velFailCount >= Cfg.FlyCFrameFailTicks then
                F.mode = "cframe"
                print("[Dingus][Fly] velocity rejected — switching to CFrame mode")
                if F.bv then pcall(function() F.bv:Destroy() end); F.bv = nil end
                if F.bg then pcall(function() F.bg:Destroy() end); F.bg = nil end
            end
        end

        F.speedSamples = F.speedSamples + 1
        F.speedSum = F.speedSum + measured
        F.avgSpeed = F.speedSum / F.speedSamples
        if measured > F.peakSpeed then F.peakSpeed = measured end

        -- Telemetry with trend
        if now - F.lastLog > 0.5 then
            local trend = ""
            if F._lastLoggedDist then
                local delta = distance - F._lastLoggedDist
                trend = string.format(" | %+.0f", delta)
            end
            F._lastLoggedDist = distance
            F.lastLog = now
            print(string.format(
                "[Dingus][Fly] %s | dist %.0f | goal %.0f | spd %.0f (avg %.0f) | mode %s | fail %d%s",
                St.tgt.ch.Name, distance, goalDist, measured, F.avgSpeed,
                F.mode, F.velFailCount, trend))
        end
    end

    RunService.Heartbeat:Connect(function(dt)
        pcall(F.tick, dt)
    end)

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function() F.stop() end)

    print("[Dingus][fly] v3 initialized")
end

return F
