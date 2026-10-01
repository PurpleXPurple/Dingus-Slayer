local D = {}

function D.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St

    function D.scanBosses()
        local now = U.clock()
        if now - St.lScn < Cfg.ScanTTL then return St.ens end
        St.lScn = now

        local myHrp = U.hrp()
        if not myHrp then St.ens = {}; return St.ens end

        local myPos = myHrp.Position
        local out, n = {}, 0
        local seen = {}
        local regions = workspace:FindFirstChild("Humanoids")
        regions = regions and regions:FindFirstChild("Regions")

        local roots = {}
        if regions then table.insert(roots, regions) end
        table.insert(roots, workspace)

        for r = 1, #roots do
            U.walkTree(roots[r], 8, function(inst, d)
                if inst == U.Lp.Character then return end
                local h = inst:FindFirstChildOfClass("Humanoid")
                if not h or h.Health <= 0 then return end
                if U.isPlayer(inst) then return end
                if not U.isBossName(inst.Name, Cfg.BossList) then return end
                if seen[inst] then return end
                seen[inst] = true
                local rp = inst:FindFirstChild("HumanoidRootPart")
                if not rp then return end
                n = n + 1
                out[n] = { ch=inst, hm=h, rp=rp, d=(myPos - rp.Position).Magnitude }
            end, 2000)
            if n > 0 then break end
        end

        table.sort(out, function(a, b) return a.d < b.d end)
        St.ens = out
        return out
    end

    function D.updateThreats()
        local now = U.clock()
        if now - St.lTht < 0.1 then return end
        St.lTht = now

        local myHrp = U.hrp()
        if not myHrp then St.ths = {}; St.imm = 0; St.zn = 0; return end

        local myPos = myHrp.Position
        local list = D.scanBosses()
        local near, imm = 0, 0
        local ths = {}

        for i = 1, #list do
            local e = list[i]
            if e.d <= 18 then
                near = near + 1
                if e.d <= 9 then
                    local moving = false
                    local an = e.hm:FindFirstChildOfClass("Animator")
                    if an then
                        for _, t in ipairs(an:GetPlayingAnimationTracks()) do
                            if t.IsPlaying and t.WeightCurrent > 0.3 then
                                local id = string.lower(tostring(t.Animation.AnimationId))
                                local nm = string.lower(t.Name or "")
                                if not string.find(id, "idle", 1, true)
                                    and not string.find(id, "walk", 1, true)
                                    and not string.find(id, "run", 1, true)
                                    and not string.find(nm, "block", 1, true) then
                                    moving = true
                                    break
                                end
                            end
                        end
                    end
                    if not moving then
                        local vel = e.rp.AssemblyLinearVelocity
                        local toMe = myPos - e.rp.Position
                        local flat = Vector3.new(toMe.X, 0, toMe.Z)
                        if flat.Magnitude > 0.1 and vel.Magnitude > 4 then
                            local facing = e.rp.CFrame.LookVector:Dot(flat.Unit)
                            local vd = Vector3.new(vel.X, 0, vel.Z)
                            if facing > 0.3 and vd.Unit:Dot(flat.Unit) > 0.5 then
                                moving = true
                            end
                        end
                    end
                    if moving then imm = imm + 1 end
                end
                ths[#ths+1] = { ch=e.ch, rp=e.rp, hm=e.hm, d=e.d }
            end
        end

        St.ths = ths
        St.zn = near
        St.imm = imm
    end

    function D.isEnemyBlocking(e)
        local c, h = e.ch, e.hm
        local ok, v = pcall(function() return c:GetAttribute("IsBlocking") end)
        if ok and v then return true end
        ok, v = pcall(function() return h:GetAttribute("IsBlocking") end)
        if ok and v then return true end
        local an = h:FindFirstChildOfClass("Animator")
        if an then
            for _, t in ipairs(an:GetPlayingAnimationTracks()) do
                if t.IsPlaying and t.WeightCurrent > 0.3 then
                    local nm = string.lower(t.Name or "")
                    if string.find(nm, "block", 1, true) or string.find(nm, "guard", 1, true) then
                        return true
                    end
                end
            end
        end
        if h.WalkSpeed < 2 and h.MoveDirection.Magnitude < 0.1 then
            if e.rp.AssemblyLinearVelocity.Magnitude < 2 then return true end
        end
        return false
    end

    function D.isEnemyStunned(e)
        local c, h = e.ch, e.hm
        local ok, v = pcall(function() return c:GetAttribute("Stunned") end)
        if ok and v then return true end
        local s = h:GetState()
        if s == Enum.HumanoidStateType.FallingDown
            or s == Enum.HumanoidStateType.Ragdoll
            or s == Enum.HumanoidStateType.Physics then
            return true
        end
        local an = h:FindFirstChildOfClass("Animator")
        if an then
            for _, t in ipairs(an:GetPlayingAnimationTracks()) do
                if t.IsPlaying and t.WeightCurrent > 0.3 then
                    local nm = string.lower(t.Name or "")
                    if string.find(nm, "stun", 1, true) or string.find(nm, "blockbreak", 1, true) then
                        return true
                    end
                end
            end
        end
        if h.WalkSpeed < 1 and e.rp.AssemblyLinearVelocity.Magnitude < 1 then
            return true
        end
        return false
    end
end

return D
