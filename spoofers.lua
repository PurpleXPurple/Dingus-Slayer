--[[
    Dingus-Slayer · spoofers.lua v4
    Client-state repair kit. 31 methods, grouped.

    All methods assume a FilteredEnabled game. Anything that writes a
    server-owned property is either a local echo (cosmetic) or a floor
    (server can correct, we re-correct). Nothing here defeats a
    server-side ban.

    Xeno compatibility: no hookmetamethod dependencies except the two
    guarded "advanced" methods. Every other method works with plain
    property writes and pcall.

    Categories:
      A · Movement      (7)  walk, jump, hip, slow, freeze, fall, gravity
      B · Combat state  (6)  block, maxHP, stun, ragdoll, knock, fling
      C · Vision        (5)  blind, fog, dark, shake, color
      D · Audio         (2)  deafen, scream
      E · Position      (4)  sit, teleport-back, void, state
      F · Persistence   (4)  afk, unequip, tool-drain, loadout
      G · Visuals       (2)  nametag, highlight
      H · Advanced      (1)  spectate (guarded)

    = 31 total.
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

    -- Per-method enable flags. Safe defaults on. Risky off.
    local D = {
        -- Movement
        antiSlow          = true,
        antiFreeze        = true,
        antiFall          = true,
        spoofWalkSpeed    = true,
        spoofJumpPower    = true,
        spoofHipHeight    = false,
        spoofGravity      = false,
        -- Combat
        spoofBlock        = true,
        spoofMaxHealth    = false,
        antiStun          = true,
        antiRagdoll       = false,
        antiKnock         = false,
        antiFling         = false,
        -- Vision
        antiBlind         = true,
        antiFog           = true,
        antiDark          = true,
        antiShake         = true,
        antiColor         = true,
        -- Audio
        antiDeafen        = false,
        antiScream        = false,
        -- Position / state
        antiSit           = true,
        antiTeleportBack  = false,
        antiVoid          = true,
        antiState         = true,
        -- Persistence
        antiAFK           = true,
        antiUnequip       = false,
        antiToolDrain     = false,
        antiLoadout       = false,
        -- Visuals
        antiNametag       = false,
        antiHighlight     = false,
        -- Advanced
        antiSpectate      = true,
    }
    Cfg.SpoofMethods = Cfg.SpoofMethods or D

    local enabled = function(name)
        local m = Cfg.SpoofMethods[name]
        if m == nil then return false end
        return m ~= false
    end

    --================================================================
    -- STATE
    --================================================================
    St.Spf = St.Spf or { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }
    St.spoofFires = {}
    St.spoofErrs = {}
    St.spoofConceded = {}
    St.spoofLastRun = {}
    St.spoofRuntime = {}
    St.spoofActiveCount = 0
    St.spoofLastAFK = 0
    St.spoofLastTeleportCheck = nil
    St.spoofLastHp = 0
    St.spoofPrevGsp = St.gsp

    local baseWalk, baseJumpPower, baseJumpHeight, baseGravity
    local lastWrittenWalk, lastWrittenJump
    local blockPath

    local function bump(name)
        St.spoofFires[name] = (St.spoofFires[name] or 0) + 1
        St.Spf.spdC = St.Spf.spdC + 1
    end

    --================================================================
    -- GUARDED PCALL
    --================================================================
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
        baseWalk      = Cfg.SpoofBaseWalk or resolveBaseWalk()
        baseJumpPower, baseJumpHeight = resolveBaseJump(h)
        baseGravity   = Cfg.SpoofBaseGravity or workspace.Gravity
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

    -- A1 · antiSlow — floor WalkSpeed at base × 0.95
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

    -- A2 · antiFreeze — total freeze recovery (WalkSpeed == 0)
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

    -- A3 · antiFall — cancel Freefall when no upward intent
    local function antiFall()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        local r = U.hrp()
        if not r then return end
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

    -- A4 · spoofWalkSpeed — reinforced slow drift up
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

    -- A5 · spoofJumpPower — reinforced jump
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

    -- A6 · spoofHipHeight — repair if server sets it to NaN/0
    local function spoofHipHeight()
        local h = U.hum()
        if not h or h.Health <= 0 then return end
        local hh = h.HipHeight
        if type(hh) ~= "number" or hh ~= hh or hh < 0 or hh > 6 then
            h.HipHeight = 2
            bump("spoofHipHeight")
        end
    end

    -- A7 · spoofGravity — floor Workspace.Gravity at base × 0.9
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

    -- B1 · spoofBlock — reinforce block bar (PS2 SHCS.Blocking)
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

    -- B2 · spoofMaxHealth — reinforce MaxHealth snapshot
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

    -- B3 · antiStun — FallingDown → Running
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

    -- B4 · antiRagdoll — Ragdoll / Physics forced back to Running
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

    -- B5 · antiKnock — horizontal velocity clamp on high impulse
    local function antiKnock()
        if not Cfg.SpoofAntiKnock then return end
        local r = U.hrp()
        local h = U.hum()
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

    -- B6 · antiFling — catastrophic velocity clamp
    local function antiFling()
        local r = U.hrp()
        if not r then return end
        local v = r.AssemblyLinearVelocity
        if not v then return end
        if v.Magnitude > Cfg.SpoofFlingThreshold then
            r.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            if Cfg.SpoofVerbose then
                print(string.format("[Dingus][Spoof] fling cancelled: %.0f",
                    v.Magnitude))
            end
            bump("antiFling")
        end
    end

    --================================================================
    -- CATEGORY C · VISION
    --================================================================

    -- C1 · antiBlind — clear full-screen overlays on PlayerGui
    local function antiBlind()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        for _, c in ipairs(pg:GetChildren()) do
            if c:IsA("ScreenGui") and c.Name ~= "DingusUI"
               and not c.Name:find("^_c") then
                local btr = c:FindFirstChild("Background", true)
                if btr and btr:IsA("Frame") then
                    local sz = btr.Size
                    if sz.X.Scale >= 1 and sz.Y.Scale >= 1 and btr.BackgroundTransparency < 0.3 then
                        btr.BackgroundTransparency = 1
                        bump("antiBlind")
                    end
                end
            end
        end
    end

    -- C2 · antiFog — clamp FogEnd when server drops it as a debuff
    local function antiFog()
        local L = game:GetService("Lighting")
        if L.FogEnd < 500 and L.FogEnd > 0 then
            L.FogEnd = 5000
            bump("antiFog")
        end
    end

    -- C3 · antiDark — brightness / ambient floor
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

    -- C4 · antiShake — reset camera offset from random shake
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

    -- C5 · antiColor — reset ColorCorrection saturation/contrast to neutral
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

    -- D1 · antiDeafen — restore SoundService ambient volume
    local function antiDeafen()
        local ss = game:GetService("SoundService")
        if ss.AmbientReverb ~= Enum.ReverbType.NoReverb then
            ss.AmbientReverb = Enum.ReverbType.NoReverb
            bump("antiDeafen")
        end
        if ss.RespectFilteringEnabled == false then
            ss.RespectFilteringEnabled = true
        end
    end

    -- D2 · antiScream — mute very loud short sounds near character
    local function antiScream()
        local r = U.hrp()
        if not r then return end
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

    -- E1 · antiSit — force-unsit if server sitted the character
    local function antiSit()
        local h = U.hum()
        if not h then return end
        if h.Sit then
            h.Sit = false
            bump("antiSit")
        end
    end

    -- E2 · antiTeleportBack — log server position snaps (no repair)
    local function antiTeleportBack()
        local r = U.hrp()
        if not r then return end
        local now = U.clock()
        local last = St.spoofLastTeleportCheck
        if last then
            local dt = now - last.t
            if dt > 0 and dt < 0.2 then
                local dist = (r.Position - last.p).Magnitude
                if dist > 100 then
                    if Cfg.SpoofVerbose then
                        print(string.format(
                            "[Dingus][Spoof] teleport-back detected: %.0f studs in %.2fs",
                            dist, dt))
                    end
                    bump("antiTeleportBack")
                end
            end
        end
        St.spoofLastTeleportCheck = { t = now, p = r.Position }
    end

    -- E3 · antiVoid — rescue from below-world
    local function antiVoid()
        local r = U.hrp()
        if not r then return end
        if r.Position.Y < Cfg.SpoofVoidYThreshold then
            local ok, cf = pcall(function()
                return CFrame.new(0, 50, 0)
            end)
            if ok and cf then
                r.CFrame = cf
                bump("antiVoid")
                print("[Dingus][Spoof] void rescue triggered")
            end
        end
    end

    -- E4 · antiState — force Running when enabled and not intentionally airborne
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

    -- F1 · antiAFK — micro-motion every N seconds to defeat idle kick
    local function antiAFK()
        local now = U.clock()
        if now - (St.spoofLastAFK or 0) < (Cfg.SpoofAFKInterval or 25) then return end
        St.spoofLastAFK = now
        local h = U.hum()
        if not h then return end
        if h.MoveDirection.Magnitude > 0.1 then return end
        if St.cbt then return end  -- combat already generating input
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

    -- F2 · antiUnequip — re-equip the last weapon if server strips it
    local function antiUnequip()
        local h = U.hum()
        if not h then return end
        local c = U.Lp.Character
        if not c then return end
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

    -- F3 · antiToolDrain — detect Backpack tools dropped to 0 unexpectedly
    local function antiToolDrain()
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if not bp then return end
        local count = 0
        for _, _ in ipairs(bp:GetChildren()) do
            count = count + 1
        end
        if not St.spoofLastToolCount then
            St.spoofLastToolCount = count
        elseif count < St.spoofLastToolCount - 3 then
            print(string.format("[Dingus][Spoof] tool count dropped: %d -> %d",
                St.spoofLastToolCount, count))
            St.spoofLastToolCount = count
            bump("antiToolDrain")
        else
            St.spoofLastToolCount = count
        end
    end

    -- F4 · antiLoadout — enforce a saved loadout (equipped tool name)
    local function antiLoadout()
        if not Cfg.SpoofLoadoutTool then return end
        local h = U.hum()
        if not h then return end
        local c = U.Lp.Character
        if not c then return end
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

    -- G1 · antiNametag — clamp DisplayDistance on the local character
    local function antiNametag()
        local h = U.hum()
        if not h then return end
        if h.NameDisplayDistance > 0 then
            h.NameDisplayDistance = 0
            h.HealthDisplayDistance = 0
            bump("antiNametag")
        end
    end

    -- G2 · antiHighlight — remove Highlight instances attached to self
    local function antiHighlight()
        local c = U.Lp.Character
        if not c then return end
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

    -- H1 · antiSpectate — force CameraSubject back to own humanoid
    local function antiSpectate()
        local cam = workspace.CurrentCamera
        if not cam then return end
        local h = U.hum()
        if not h then return end
        if cam.CameraSubject ~= h then
            -- Only repair if we're not already flying (which changes subject)
            if not St.FlyActive then
                pcall(function() cam.CameraSubject = h end)
                bump("antiSpectate")
            end
        end
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
    }

    -- Precompute intervals
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
            lastWrittenWalk = nil
            lastWrittenJump = nil
            blockPath = nil
            St.spoofLastToolCount = nil
            St.spoofLastTeleportCheck = nil
            St.mxH = 0
        end)
    end

    --================================================================
    -- TICK
    --================================================================
    function Sp.tick()
        -- Master toggle
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
            enabled        = St.gsp,
            activeMethods  = St.spoofActiveCount or 0,
            totalMethods   = #ACTIONS,
            conceded       = false,
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
        if Cfg.SpoofMethods[name] == nil then return false end
        Cfg.SpoofMethods[name] = not not on
        return true
    end

    function Sp.listMethods()
        local out = {}
        for i = 1, #ACTIONS do
            local a = ACTIONS[i]
            out[i] = {
                key = a.key,
                hz  = a.hz,
                on  = enabled(a.key),
            }
        end
        return out
    end

    --================================================================
    -- BOOT
    --================================================================
    if St.gsp then
        print(string.format(
            "[Dingus][Spoof] v4 loaded · %d methods registered",
            #ACTIONS))
        print("[Dingus][Spoof] NOTE: gsp is ON. Client writes are " ..
              "local echoes; server retains authority. Disable via " ..
              "St.gsp = false if you see rubber-banding.")
    else
        print(string.format(
            "[Dingus][Spoof] v4 loaded · %d methods registered · master OFF",
            #ACTIONS))
    end
end

return Sp
