local Sp = {}

function Sp.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St

    St.Spf = { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }

    local function log(msg)
        print("[Dingus][UG] " .. msg)
    end

    local function spoofHP()
        local h = U.hum()
        if not h then return end
        if h.MaxHealth > St.mxH then St.mxH = h.MaxHealth end
        if h.Health < St.mxH * 0.9 and h.Health > 0 then
            pcall(function() h.Health = St.mxH end)
            St.Spf.hpC = St.Spf.hpC + 1
        end
        if h.MaxHealth < St.mxH then
            pcall(function() h.MaxHealth = St.mxH end)
        end
    end

    local function spoofBlock()
        local hf = workspace:FindFirstChild("Humanoids")
        if not hf then return end
        local me = hf:FindFirstChild(U.Lp.Name)
        if not me then return end
        local shcs = me:FindFirstChild("SHCS")
        if not shcs then return end
        local bv = shcs:FindFirstChild("Blocking")
        if bv and bv:IsA("NumberValue") and bv.Value < 40 then
            pcall(function() bv.Value = 100 end)
            St.Spf.bkC = St.Spf.bkC + 1
        end
    end

    local function spoofSpeed()
        local h = U.hum()
        if not h then return end
        if h.WalkSpeed < 32 then
            pcall(function() h.WalkSpeed = 32 end)
            St.Spf.spdC = St.Spf.spdC + 1
        end
    end

    local function spoofJump()
        local h = U.hum()
        if not h then return end
        if h.UseJumpPower then
            if h.JumpPower < 100 then
                pcall(function() h.JumpPower = 100 end)
                St.Spf.jmpC = St.Spf.jmpC + 1
            end
        else
            if h.JumpHeight < 13 then
                pcall(function() h.JumpHeight = 13 end)
                St.Spf.jmpC = St.Spf.jmpC + 1
            end
        end
    end

    local function antiKnock()
        local r = U.hrp()
        if not r then return end
        local v = r.AssemblyLinearVelocity
        if v.Magnitude > 35 then
            r.AssemblyLinearVelocity = Vector3.new(v.X * 0.2, v.Y * 0.5, v.Z * 0.2)
            St.Spf.kbC = St.Spf.kbC + 1
        end
    end

    local function antiStun()
        local h = U.hum()
        if not h then return end
        local s = h:GetState()
        if s == Enum.HumanoidStateType.Ragdoll
            or s == Enum.HumanoidStateType.FallingDown
            or s == Enum.HumanoidStateType.Physics then
            pcall(function() h:ChangeState(Enum.HumanoidStateType.Running) end)
        end
    end

    function Sp.tick()
        if not St.gsp then return end
        local now = U.clock()
        if now - St.lSpf < 0.1 then return end
        St.lSpf = now
        pcall(spoofHP)
        pcall(spoofBlock)
        pcall(spoofSpeed)
        pcall(spoofJump)
        pcall(antiKnock)
        pcall(antiStun)
    end

    function Sp.goUnderground()
        if St.uGs then return end
        local r = U.hrp()
        if not r then return end
        local o = r.Position
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { U.Lp.Character }
        local res = workspace:Raycast(o, Vector3.new(0, -200, 0), rp)
        local gy = res and res.Position.Y or (o.Y - 15)
        local ty = gy - Cfg.UGDepth
        local bp = r:FindFirstChild("PS2_HoverBP")
        if not bp then
            bp = Instance.new("BodyPosition")
            bp.Name = "PS2_HoverBP"
            bp.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            bp.P = Cfg.HoverP
            bp.D = Cfg.HoverD
            bp.Parent = r
        end
        bp.Position = Vector3.new(o.X, ty, o.Z)
        pcall(function() r.CFrame = CFrame.new(o.X, ty, o.Z) end)
        St.uGs = true
        St.uGt = U.clock() + Cfg.UGMaxT
        St.uST = 0
        St.uThC = 0
        St.uC = (St.uC or 0) + 1
        log("dive #" .. St.uC)
    end

    function Sp.surfaceUp()
        if not St.uGs then return end
        St.uGs = false
        local r = U.hrp()
        if not r then return end
        local bp = r:FindFirstChild("PS2_HoverBP")
        if not bp then return end
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { U.Lp.Character }
        local res = workspace:Raycast(r.Position, Vector3.new(0, 200, 0), rp)
        local uy = res and (res.Position.Y + 3) or (r.Position.Y + Cfg.UGDepth + 3)
        bp.Position = Vector3.new(r.Position.X, uy, r.Position.Z)
        log(string.format("up after %.1fs", St.uST or 0))
    end

    function Sp.checkUG()
        if not St.uGs then return end
        local n = U.clock()
        St.uST = (St.uST or 0) + 0.05
        if n > St.uGt then Sp.surfaceUp(); return end
        if St.imm == 0 then
            if St.uThC == 0 then St.uThC = n end
            if n - St.uThC > Cfg.UGClearT then Sp.surfaceUp(); St.uThC = 0 end
        else
            St.uThC = 0
        end
    end
end

return Sp
