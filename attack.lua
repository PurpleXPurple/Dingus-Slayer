--[[
    Dingus-Slayer · attack.lua v26
    Movement overhaul: Line-of-sight + Pathfinding + Direct Velocity
]]--

local A = {}

function A.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local D = Ctx.Detect
    local L = Ctx.Lists
    local RunService = game:GetService("RunService")
    local PathfindingService = game:GetService("PathfindingService")

    -- ... (Your existing state variables: St.rHt, St.skCd, etc.) ...

    -- NEW: Movement state
    St.moveConn = nil
    St.moveTarget = nil
    St.moveMode = "IDLE" -- "IDLE" | "PATH" | "DIRECT"
    St.currentWaypoint = 1
    St.currentPath = nil
    St.lastPathRecalc = 0
    St.lastRaycast = 0

    --============================================================
    -- LINE OF SIGHT CHECK
    --============================================================
    local function hasLineOfSight(myHRP, targetHRP)
        local origin = myHRP.Position
        local direction = (targetHRP.Position - origin).Unit * (targetHRP.Position - origin).Magnitude

        local raycastParams = RaycastParams.new()
        raycastParams.FilterDescendantsInstances = { U.Lp.Character, targetHRP.Parent }
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude

        local result = workspace:Raycast(origin, direction, raycastParams)
        -- If no obstruction, we have line of sight
        return result == nil
    end

    --============================================================
    -- MOVEMENT LOOP (Runs every frame)
    --============================================================
    local function movementTick()
        if not St.cbt or St.cbtS == "RETREAT" or St.cbtS == "IDLE" then
            -- Stop moving if we're not in combat or retreating (retreat handled separately)
            if St.moveConn and St.moveMode ~= "IDLE" then
                St.moveMode = "IDLE"
                St.moveTarget = nil
            end
            return
        end

        local h = U.hum()
        local r = U.hrp()
        if not h or not r then return end

        -- If no target, stop moving
        if not St.tgt or not St.tgt.ch.Parent then
            St.moveMode = "IDLE"
            return
        end

        local targetHRP = St.tgt.ch:FindFirstChild("HumanoidRootPart")
        if not targetHRP then return end

        local now = U.clock()
        local dist = U.xzDist(r.Position, targetHRP.Position)

        -- If we're in melee range, stop moving (combat handler will handle positioning)
        if dist <= Cfg.AtkRange + 2 then
            if St.moveMode ~= "IDLE" then
                St.moveMode = "IDLE"
                h:Move(Vector3.new(0, 0, 0)) -- Stop
            end
            return
        end

        -- Raycast check (throttled to 0.15s for performance)
        if now - St.lastRaycast > 0.15 then
            St.lastRaycast = now
            local canSee = hasLineOfSight(r, targetHRP)

            if canSee and St.moveMode ~= "DIRECT" then
                -- Switch to DIRECT mode
                St.moveMode = "DIRECT"
                St.currentPath = nil
                print("[Dingus][Move] -> DIRECT (line of sight)")
            elseif not canSee and St.moveMode ~= "PATH" then
                -- Switch to PATH mode
                St.moveMode = "PATH"
                St.lastPathRecalc = 0 -- Force immediate recalc
                print("[Dingus][Move] -> PATH (obstructed)")
            end
        end

        -- Execute movement based on mode
        if St.moveMode == "DIRECT" then
            -- Direct velocity: Simple, fast, responsive
            local direction = (targetHRP.Position - r.Position).Unit
            -- Apply velocity directly to the HRP
            r.Velocity = Vector3.new(direction.X * Cfg.RunSpeed, r.Velocity.Y, direction.Z * Cfg.RunSpeed)

        elseif St.moveMode == "PATH" then
            -- Pathfinding: Smart navigation around obstacles
            if now - St.lastPathRecalc > 0.5 or not St.currentPath then
                St.lastPathRecalc = now
                local path = PathfindingService:CreatePath({
                    AgentRadius = 2,
                    AgentHeight = 5,
                    AgentCanJump = true,
                    WaypointSpacing = 4
                })
                path:ComputeAsync(r.Position, targetHRP.Position)
                St.currentPath = path
                St.currentWaypoint = 1
            end

            if St.currentPath and St.currentPath.Status == Enum.PathStatus.Success then
                local waypoints = St.currentPath:GetWaypoints()
                if St.currentWaypoint <= #waypoints then
                    local wp = waypoints[St.currentWaypoint]
                    if wp.Action == Enum.PathWaypointAction.Jump then
                        h:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                    h:MoveTo(wp.Position)

                    -- Check if reached waypoint
                    if (r.Position - wp.Position).Magnitude < 3 then
                        St.currentWaypoint = St.currentWaypoint + 1
                    end
                else
                    -- Reached end of path, recalc next tick
                    St.currentPath = nil
                end
            end
        end
    end

    --============================================================
    -- COMBAT TICK (Simplified movement handling)
    --============================================================
    function A.combatTick()
        -- ... (Your existing state, HP tracking, retreat check logic) ...

        -- Movement is now handled by the separate loop.
        -- The combat tick only handles state transitions based on distance.

        local t = St.tgt
        local tPos = t.ch:FindFirstChild("HumanoidRootPart")
        if not tPos then St.tgt = nil; return end

        local dist = U.xzDist(r.Position, tPos.Position)
        t.d = dist

        -- STATE: PUNISH (stun)
        if D.isEnemyStunned(t) and dist <= 12 then
            St.cbtS = "PUNISH"
            -- Movement handled by loop (will stop if in range)
            -- ... (attack code) ...
            return
        end

        -- STATE: ATTACK (close)
        if dist <= Cfg.AtkRange then
            St.cbtS = "ATTACK"
            -- Movement handled by loop (will stop if in range)
            -- ... (attack code) ...
            return
        end

        -- STATE: APPROACH (The movement loop handles this)
        St.cbtS = "APPROACH"
        -- The movement loop is already walking/pathing towards the target.
        -- We can optionally fire skills from a distance.
        if St.skl and now - St.lSkl > 1.5 then
            St.lSkl = now
            fireRotation()
        end
    end

    --============================================================
    -- START / STOP MOVEMENT
    --============================================================
    function A.startMovement()
        if St.moveConn then return end
        St.moveConn = RunService.Heartbeat:Connect(movementTick)
        print("[Dingus][Move] movement loop started")
    end

    function A.stopMovement()
        if St.moveConn then
            St.moveConn:Disconnect()
            St.moveConn = nil
        end
        St.moveMode = "IDLE"
        local r = U.hrp()
        if r then r.Velocity = Vector3.new(0, r.Velocity.Y, 0) end
        print("[Dingus][Move] movement loop stopped")
    end

    -- Start the movement loop when combat starts
    local oldCombatTick = A.combatTick
    A.combatTick = function()
        if St.cbt and not St.moveConn then
            A.startMovement()
        elseif not St.cbt and St.moveConn then
            A.stopMovement()
        end
        oldCombatTick()
    end

    print("[Dingus][attack] initialized · movement overhaul")
end

return A
