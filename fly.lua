-- Dingus-Slayer · fly.lua v6
-- Replaced with Synerox farm movement (Overhead/Underground/In Front).
-- Manages the anchored farm platform + HRP teleport per target.
-- Not a "fly" in the old sense — this is Synerox's ground-anchor model.

local F = {}

function F.init(Ctx)
    local U, Cfg, St = Ctx.Util, Ctx.Cfg, Ctx.St

    F.active = false
    F.platform = nil
    F.lastPos = nil
    F.lastTarget = nil
    St.SynFarmMode = St.SynFarmMode or "Overhead"

    --============================================================
    -- FARM PLATFORM (Synerox fn22)
    --============================================================
    local function ensurePlatform()
        if F.platform and F.platform.Parent then return F.platform end
        local p = Instance.new("Part")
        p.Name = "SyneroxFarmPlatform"
        p.Size = Vector3.new(16, 1.2, 16)
        p.Transparency = 1
        p.Anchored = true
        p.CanCollide = true
        p.Parent = workspace
        F.platform = p
        return p
    end

    local function movePlatform(cf)
        local p = ensurePlatform()
        p.Size = Vector3.new(16, 1.2, 16)
        p.CanCollide = true
        p.CFrame = CFrame.new(cf.Position.X, cf.Position.Y - 3.2, cf.Position.Z)
    end

    local function destroyPlatform()
        if F.platform then
            pcall(function() F.platform:Destroy() end)
            F.platform = nil
        end
    end

    F.ensurePlatform = ensurePlatform
    F.movePlatform = movePlatform
    F.destroyPlatform = destroyPlatform

    --============================================================
    -- POSITION CALCULATOR (Synerox attack-position)
    --============================================================
    function F.computeCF(targetRoot, mode, heightOffset, distance)
        mode = mode or St.SynFarmMode or "Overhead"
        heightOffset = heightOffset or (Cfg.SynHeightOffset or 3.8)
        distance = distance or (Cfg.SynDistance or 2)
        local pos = targetRoot.Position
        if mode == "Overhead" then
            return CFrame.new(pos + Vector3.new(0, heightOffset, 0), pos)
        elseif mode == "Underground" then
            return CFrame.new(pos + Vector3.new(0, -heightOffset, 0), pos)
        elseif mode == "In Front" then
            local look = targetRoot.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, 1) end
            flat = flat.Unit
            local n = pos + flat * distance
            return CFrame.new(n, Vector3.new(pos.X, n.Y, pos.Z))
        elseif mode == "Ground" then
            return CFrame.new(pos + targetRoot.CFrame.LookVector * distance, pos)
        end
        return CFrame.new(pos + Vector3.new(0, heightOffset, 0), pos)
    end

    --============================================================
    -- APPLY (teleport HRP + move platform)
    --============================================================
    function F.apply(targetRoot, mode, heightOffset, distance)
        local hrp = U.hrp()
        if not hrp or not targetRoot then return end
        local cf = F.computeCF(targetRoot, mode, heightOffset, distance)
        hrp.CFrame = cf
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        movePlatform(cf)
        F.lastPos = cf.Position
        return cf
    end

    --============================================================
    -- PUBLIC
    --============================================================
    function F.start()
        if F.active then return true end
        F.active = true
        St.FlyActive = true
        print("[Dingus][Farm] movement enabled · mode="..tostring(St.SynFarmMode))
        return true
    end

    function F.stop()
        if not F.active then return end
        F.active = false
        destroyPlatform()
        St.FlyActive = false
        print("[Dingus][Farm] movement disabled")
    end

    function F.toggle()
        if F.active then F.stop() else F.start() end
    end

    function F.setMode(mode)
        St.SynFarmMode = mode
        print("[Dingus][Farm] mode = "..tostring(mode))
    end

    --============================================================
    -- TICK — heartbeat driven, keeps platform positioned while
    -- target is locked and player is attacking.
    --============================================================
    function F.tick()
        if not F.active then return end
        if not St.cbt then return end
        if not St.lockedTarget then destroyPlatform(); return end
        local t = St.lockedTarget
        if not t.Root or not t.Root.Parent or not t.Humanoid or t.Humanoid.Health <= 0 then
            destroyPlatform(); return end
        F.apply(t.Root)
    end

    if U.Run then
        U.Run.Heartbeat:Connect(function() pcall(F.tick) end)
    end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function() F.stop() end)

    print(string.format("[Dingus][fly] v6 · Synerox-farm-movement · %s", U.Platform))
end

return F
