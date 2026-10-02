-- Dingus-Slayer · fly.lua v5 (deprecated, retained)
-- Cross-device: works on PC + Mobile via CFrame writes, no BodyMovers.

local F = {}

function F.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St

    F.active = false
    F.lastPos = nil

    function F.start()
        if F.active then return true end
        local h = U.hum()
        if not h then return false end
        F.active = true
        h.PlatformStand = true
        St.FlyActive = true
        print("[Dingus][Fly] started (deprecated, CFrame mode)")
        return true
    end

    function F.stop()
        if not F.active then return end
        F.active = false
        local h = U.hum()
        if h then
            h.PlatformStand = false
            h.WalkSpeed = 16
        end
        St.FlyActive = false
        print("[Dingus][Fly] stopped")
    end

    function F.toggle() if F.active then F.stop() else F.start() end end

    function F.tick(dt)
        if not F.active then return end
        if not St.tgt or not St.tgt.ch.Parent then F.stop(); return end
        local r = U.hrp(); local h = U.hum()
        if not r or not h or h.Health <= 0 then F.stop(); return end
        local tPos = St.tgt.ch:FindFirstChild("HumanoidRootPart")
        if not tPos then return end
        local myPos = r.Position
        local goal = tPos.Position + Vector3.new(0, 6, 0)
        local toGoal = goal - myPos
        if toGoal.Magnitude < 8 then return end
        local step = toGoal.Unit * math.min(toGoal.Magnitude, 85 * dt)
        pcall(function() r.CFrame = r.CFrame + step end)
    end

    if U.Run then
        U.Run.Heartbeat:Connect(function(dt) pcall(F.tick, dt) end)
    end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function() F.stop() end)

    print(string.format("[Dingus][fly] v5 (deprecated) · %s", U.Platform))
end

return F
