-- Dingus-Slayer · fly.lua v7
-- Fixes: F-01 (mode key sync), F-02 (double Heartbeat), F-03 (fingerprint name).
-- Reads F.SynSafeMode as source of truth. No self-hook — main scheduler drives.

local F = {}

function F.init(Ctx)
    local U, F_, S = Ctx.Util, Ctx.Cfg, Ctx.St

    F.active = false
    F.platform = nil
    F.lastPos = nil

    --========================================================
    -- HIDDEN ANCHOR FOLDER (obfuscates platform from workspace)
    --========================================================
    local function anchorFolder()
        local folder = workspace:FindFirstChild("_dgAnchors")
        if not folder then
            folder = Instance.new("Folder")
            folder.Name = "_dgAnchors"
            folder.Parent = workspace
        end
        return folder
    end

    --========================================================
    -- PLATFORM (renamed, parented to folder, non-descriptive)
    --========================================================
    local function ensurePlatform()
        if F.platform and F.platform.Parent then return F.platform end
        local hex = string.format("%06x", math.random(0, 0xFFFFFF))
        local p = Instance.new("Part")
        p.Name = "_a" .. hex
        p.Size = Vector3.new(16, 1.2, 16)
        p.Transparency = 1
        p.CanCollide = true
        p.Anchored = true
        p.Locked = true
        p.Massless = true
        p.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)
        p.Parent = anchorFolder()
        F.platform = p
        return p
    end

    local function movePlatform(cf)
        local p = ensurePlatform()
        p.CFrame = CFrame.new(cf.Position.X, cf.Position.Y - 3.2, cf.Position.Z)
    end

    local function destroyPlatform()
        if F.platform then
            pcall(function() F.platform:Destroy() end)
            F.platform = nil
        end
        -- Clean empty folder
        local folder = workspace:FindFirstChild("_dgAnchors")
        if folder and #folder:GetChildren() == 0 then
            pcall(function() folder:Destroy() end)
        end
    end

    F.ensurePlatform = ensurePlatform
    F.movePlatform   = movePlatform
    F.destroyPlatform = destroyPlatform

    --========================================================
    -- POSITION CALCULATOR — reads F.SynSafeMode (source of truth)
    --========================================================
    function F.computeCF(targetRoot, mode, heightOffset, distance)
        mode = mode or F_.SynSafeMode or "Overhead"
        heightOffset = heightOffset or (F_.SynHeightOffset or 3.8)
        distance = distance or (F_.SynDistance or 2)
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

    --========================================================
    -- PUBLIC
    --========================================================
    function F.start()
        if F.active then return true end
        F.active = true
        S.FlyActive = true
        print("[Dingus][Farm] movement enabled · mode="..tostring(F_.SynSafeMode))
        return true
    end

    function F.stop()
        if not F.active then return end
        F.active = false
        destroyPlatform()
        S.FlyActive = false
    end

    function F.toggle()
        if F.active then F.stop() else F.start() end
    end

    function F.setMode(mode)
        F_.SynSafeMode = mode
        print("[Dingus][Farm] mode = "..tostring(mode))
    end

    --========================================================
    -- TICK — driven by main.lua scheduler, NO self-Heartbeat
    --========================================================
    function F.tick()
        if not F.active then return end
        if not S.cbt then return end
        local t = S.lockedTarget
        if not t or not t.Root or not t.Root.Parent
            or not t.Humanoid or t.Humanoid.Health <= 0 then
            destroyPlatform()
            return
        end
        F.apply(t.Root)
    end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function() F.stop() end)

    print(string.format("[Dingus][fly] v7 · Synerox-farm · %s", U.Platform))
end

return F
