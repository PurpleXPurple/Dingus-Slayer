--[[
    Dingus-Slayer · main.lua v23
    Staged boot · horse-flight · auto-noclip while flying
]]--

local M = {}

local PHASES = { "state", "scrub", "config", "subsystems", "systems", "flight", "deferred" }

local function phase(idx, name)
    print(string.format("[Dingus][boot %d/%d] %s", idx, #PHASES, name))
end

local function makeLoop(name, tick, interval, maxErrors)
    maxErrors = maxErrors or 5
    return {
        name = name, tick = tick, interval = interval or 0.1,
        maxErrors = maxErrors, errors = 0, disabled = false,
        lastRun = 0, totalRuns = 0,
    }
end

function M.boot(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local Lists = Ctx.Lists

    --========================================================
    -- PHASE 1: STATE
    --========================================================
    phase(1, "state")
    St.run = true
    St.boot = false
    St.bootPhase = "state"

    St.cbt = Cfg.DefaultToggles.combat
    St.skl = Cfg.DefaultToggles.skl
    St.eqp = Cfg.DefaultToggles.eqp
    St.rtr = Cfg.DefaultToggles.rtr
    St.gsp = Cfg.DefaultToggles.gsp
    St.crw = Cfg.DefaultToggles.crw
    St.stunPun = Cfg.DefaultToggles.stunPun
    St.fly = false

    St.cbtS = "IDLE"
    St.inp = 0
    St.mxH = 0
    St.lHp = 0
    St.lHpT = 0
    St.lDmg = 0
    St.lScn = 0
    St.lTht = 0
    St.lSpf = 0
    St.lEqp = 0
    St.lAtk = 0
    St.lSkl = 0
    St.lBrt = 0
    St.lHvr = 0
    St.lFac = 0
    St.lMove = 0
    St.lCkC = 0

    St.rHt = {}
    St.skCd = { 0, 0, 0, 0, 0 }
    St.aiI = Cfg.AtkInterval
    St.eq = "none"
    St.swp = 0
    St.lTl = false
    St.kll = 0
    St.bKll = 0
    St.aAt = 0
    St.aHi = 0
    St.aMs = 0
    St.skC = 0
    St.rtrC = 0
    St.cQs = 0
    St.uGs = false
    St.uC = 0
    St.uGt = 0
    St.uST = 0
    St.uThC = 0
    St.ens = {}
    St.ths = {}
    St.zn = 0
    St.imm = 0
    St.tgt = nil
    St.hvB = nil
    St.crT = nil
    St.crM = nil
    St.cPrch = false
    St.playerLevel = 0
    St.questTarget = nil
    St.huntCount = 0
    St.Spf = { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }
    St.fs = {}
    St.fps = 60
    St.loadErrors = {}

    --========================================================
    -- PHASE 2: SCRUB
    --========================================================
    phase(2, "scrub")

    local function scrubMovers()
        local r = U.hrp()
        if not r then return 0 end
        local n = 0
        for _, c in ipairs(r:GetChildren()) do
            if c:IsA("BodyPosition") or c:IsA("BodyVelocity")
                or c:IsA("BodyGyro") or c:IsA("BodyForce")
                or c:IsA("LinearVelocity") or c:IsA("AlignOrientation") then
                c:Destroy()
                n = n + 1
            end
        end
        local h = U.hum()
        if h then
            h.PlatformStand = false
            h.WalkSpeed = 16
        end
        return n
    end

    local scrubbed = scrubMovers()
    if scrubbed > 0 then print("[Dingus] scrubbed " .. scrubbed .. " movers") end

    --========================================================
    -- PHASE 3: CONFIG
    --========================================================
    phase(3, "config")
    if Cfg.setUtils then Cfg.setUtils(U) end
    if Cfg.exists and Cfg.exists() then
        local okL, msgL = Cfg.load()
        print("[Dingus][Config] " .. tostring(msgL))
    end

    --========================================================
    -- PHASE 4: SUBSYSTEMS
    --========================================================
    phase(4, "subsystems")

    local subsystems = {
        { name = "detect",     mod = "Detect" },
        { name = "scanners",   mod = "Scan" },
        { name = "spoofers",   mod = "Spoof" },
        { name = "attack",     mod = "Atk" },
        { name = "optimizers", mod = "Opt" },
        { name = "gui",        mod = "Gui" },
    }
    local okCount = 0
    for i = 1, #subsystems do
        local s = subsystems[i]
        local mod = Ctx[s.mod]
        if mod and type(mod.init) == "function" then
            local ok, err = pcall(mod.init, Ctx)
            if ok then
                okCount = okCount + 1
                print("[Dingus]   ✓ " .. s.name)
            else
                print("[Dingus]   ✗ " .. s.name .. ": " .. tostring(err))
                table.insert(St.loadErrors, s.name .. ": " .. tostring(err))
            end
        else
            print("[Dingus]   ✗ " .. s.name .. " missing")
            table.insert(St.loadErrors, s.name .. ": missing")
        end
        task.wait(0.02)
    end
    print(string.format("[Dingus] %d/%d subsystems ok", okCount, #subsystems))

    --========================================================
    -- PHASE 5: SYSTEMS
    --========================================================
    phase(5, "systems")

    -- QUEST
    local Quest = { lastCheck = 0, hunts = {}, level = 0 }
    Ctx.Quest = Quest

    function Quest.readLevel()
        local hf = workspace:FindFirstChild("Humanoids")
        local me = hf and hf:FindFirstChild(U.Lp.Name)
        if me then
            local prog = me:FindFirstChild("Progression")
            local lvl = prog and prog:FindFirstChild("Level")
            if lvl and (lvl:IsA("NumberValue") or lvl:IsA("IntValue")) then
                return lvl.Value
            end
        end
        local rs = game:GetService("ReplicatedStorage")
        local ps = rs:FindFirstChild("Player_Service")
        local data = ps and ps:FindFirstChild("Data")
        local me2 = data and data:FindFirstChild(U.Lp.Name)
        local slots = me2 and me2:FindFirstChild("slots")
        local s1 = slots and slots:FindFirstChild("Slot1")
        if s1 then
            local p2 = s1:FindFirstChild("Progression")
            local l2 = p2 and p2:FindFirstChild("Level")
            if l2 and (l2:IsA("NumberValue") or l2:IsA("IntValue")) then
                return l2.Value
            end
        end
        return 0
    end

    function Quest.findBossHunts()
        local rs = game:GetService("ReplicatedStorage")
        local hunts = rs:FindFirstChild("BossHunts")
        if not hunts then return {} end
        local out = {}
        for _, cfg in ipairs(hunts:GetChildren()) do
            if cfg:IsA("Configuration") then
                local side = cfg:FindFirstChild("Side")
                local quest = cfg:FindFirstChild("Quest")
                table.insert(out, {
                    id = cfg.Name,
                    side = side and tostring(side.Value) or "?",
                    quest = quest and tostring(quest.Value) or "?",
                })
            end
        end
        table.sort(out, function(a, b)
            return (tonumber(a.id) or 0) > (tonumber(b.id) or 0)
        end)
        return out
    end

    function Quest.doCycle()
        local now = U.clock()
        if now - Quest.lastCheck < Cfg.QuestCycleT then return end
        Quest.lastCheck = now
        Quest.level = Quest.readLevel()
        St.playerLevel = Quest.level
        local hunts = Quest.findBossHunts()
        Quest.hunts = hunts
        St.huntCount = #hunts
        if #hunts == 0 then return end
        for i = 1, #hunts do
            local h = hunts[i]
            local id = tonumber(h.id) or 0
            if id <= math.max(1, math.floor(Quest.level / 20)) then
                local target = h.quest:match("Eliminate%s+(.+)") or h.quest
                St.questTarget = target
                return
            end
        end
    end

    -- CROW
    local Crow = { last = 0, accepts = 0 }
    Ctx.Crow = Crow

    local function crowCycle()
        if not St.crw then return end
        local now = U.clock()
        if now - Crow.last < Cfg.CrowCheckT then return end
        Crow.last = now
        local tool = Ctx.Scan.findCrowTool()
        if not tool then return end
        St.crT = tool
        local c = U.Lp.Character
        if not c then return end
        local equipped = false
        for _, x in ipairs(c:GetChildren()) do
            if x:IsA("Tool") and Lists.isCrow(x.Name) then equipped = true; break end
        end
        if not equipped and tool:IsA("Tool") then
            local h = U.hum()
            if h then pcall(function() h:EquipTool(tool) end); task.wait(0.5) end
        end
        local model = Ctx.Scan.findCrowModel()
        if not model then
            U.m1(); task.wait(1.0); model = Ctx.Scan.findCrowModel()
        end
        St.cPrch = (model ~= nil)
        if not St.cPrch then return end
        local menu = Ctx.Scan.findCrowMenu()
        if not menu then U.m1(); task.wait(0.5); menu = Ctx.Scan.findCrowMenu() end
        if menu then
            pcall(function() menu:Activate() end)
            Crow.accepts = Crow.accepts + 1
            St.cQs = Crow.accepts
            print("[Dingus][Crow] accepted #" .. Crow.accepts)
            task.wait(0.8)
        end
    end

    --========================================================
    -- PHASE 6: FLIGHT
    --========================================================
    phase(6, "flight")

    local Fly = {
        active = false,
        mounted = false,
        horseTool = nil,
        savedCollide = {},
        att = nil,
        lv = nil,
        ao = nil,
        flyConn = nil,
        noclipConn = nil,
        lastPulse = 0,
        pulseUntil = 0,
        camLerp = 0,
    }
    Ctx.Fly = Fly
    St.FlyActive = false
    St.FlyMounted = false
    St.FlySpeed = 22

    local function findHorse()
        local c = U.Lp.Character
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") and string.find(string.lower(t.Name), "horse", 1, true) then
                    return t
                end
            end
        end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and string.find(string.lower(t.Name), "horse", 1, true) then
                    return t
                end
            end
        end
        return nil
    end

    local function saveCollide(inst, dict)
        if not inst then return end
        for _, p in ipairs(inst:GetDescendants()) do
            if p:IsA("BasePart") then
                if dict[p] == nil then
                    dict[p] = p.CanCollide
                end
            end
        end
    end

    local function restoreCollide(dict)
        for part, val in pairs(dict) do
            if part and part.Parent then
                pcall(function() part.CanCollide = val end)
            end
        end
        for k in pairs(dict) do
            dict[k] = nil
        end
    end

    function Fly.start()
        if Fly.active then return true end
        local horse = findHorse()
        if not horse then
            print("[Dingus][Fly] no horse in inventory")
            return false
        end
        Fly.horseTool = horse
        local h = U.hum()
        if not h then return false end

        -- Unequip weapon first to make room
        local c = U.Lp.Character
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") and t ~= horse then
                    pcall(function() h:UnequipTools() end)
                    break
                end
            end
        end

        pcall(function() h:EquipTool(horse) end)
        task.wait(0.9)

        local r = U.hrp()
        if not r then return false end

        -- Wait for mount state
        local deadline = U.clock() + 3
        while U.clock() < deadline do
            local hh = U.hum()
            if not hh then break end
            local st = hh:GetState()
            if hh.Sit or hh.PlatformStand or st == Enum.HumanoidStateType.Physics then
                Fly.mounted = true
                break
            end
            task.wait(0.1)
        end

        St.FlyMounted = Fly.mounted

        -- Attachment + soft velocity
        local att = Instance.new("Attachment")
        att.Name = "DingusFlyAtt"
        att.Parent = r

        local lv = Instance.new("LinearVelocity")
        lv.Name = "DingusFlyLV"
        lv.MaxForce = 6e4
        lv.MaxAxes = Enum.Axis.X + Enum.Axis.Y + Enum.Axis.Z
        lv.Attachment0 = att
        lv.Velocity = Vector3.zero
        lv.Parent = r

        local ao = Instance.new("AlignOrientation")
        ao.Name = "DingusFlyAO"
        ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
        ao.Attachment0 = att
        ao.MaxTorque = 5e4
        ao.Responsiveness = 20
        ao.Parent = r

        Fly.att = att
        Fly.lv = lv
        Fly.ao = ao
        Fly.active = true
        Fly.lastPulse = 0
        Fly.pulseUntil = 0
        Fly.camLerp = 0
        St.FlyActive = true

        -- Save collision states before disabling
        saveCollide(U.Lp.Character, Fly.savedCollide)
        -- Also try to catch any nearby horse model in workspace
        local myName = U.Lp.Name
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") and string.find(string.lower(obj.Name), "horse", 1, true) then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                if not hum then
                    saveCollide(obj, Fly.savedCollide)
                end
            end
        end

        -- Noclip: only active while flying
        Fly.noclipConn = game:GetService("RunService").Stepped:Connect(function()
            if not Fly.active then return end
            local ch = U.Lp.Character
            if ch then
                for _, p in ipairs(ch:GetDescendants()) do
                    if p:IsA("BasePart") and p.CanCollide then
                        p.CanCollide = false
                    end
                end
            end
        end)

        -- Stutter flight: brief pulses with damping between
        Fly.flyConn = game:GetService("RunService").Heartbeat:Connect(function(dt)
            if not Fly.active or not Fly.lv then return end
            local cam = workspace.CurrentCamera
            if not cam then return end
            local uis = game:GetService("UserInputService")

            local move = Vector3.zero
            if uis:IsKeyDown(Enum.KeyCode.W) then move = move + cam.CFrame.LookVector end
            if uis:IsKeyDown(Enum.KeyCode.S) then move = move - cam.CFrame.LookVector end
            if uis:IsKeyDown(Enum.KeyCode.A) then move = move - cam.CFrame.RightVector end
            if uis:IsKeyDown(Enum.KeyCode.D) then move = move + cam.CFrame.RightVector end
            if uis:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0, 1, 0) end
            if uis:IsKeyDown(Enum.KeyCode.LeftControl) then move = move - Vector3.new(0, 1, 0) end

            local now = U.clock()
            -- Stutter pulse: fire a thrust burst every 0.55-0.9s for 0.12-0.2s
            local pulseGap = 0.55 + math.random() * 0.35
            if now - Fly.lastPulse > pulseGap then
                Fly.lastPulse = now
                local pulseDur = 0.12 + math.random() * 0.08
                Fly.pulseUntil = now + pulseDur
            end

            local thrusting = now < Fly.pulseUntil
            -- Thrust only during pulse windows, low damping between
            local target
            if thrusting and move.Magnitude > 0.1 then
                target = move.Unit * St.FlySpeed
            elseif thrusting then
                target = Vector3.new(0, 0, 0)
            else
                -- Coast with slight damping so motion feels alive
                target = Fly.lv.Velocity * 0.82
            end

            -- Gentle lerp, real slow feel
            Fly.lv.Velocity = Fly.lv.Velocity:Lerp(target, 5 * dt)
            -- Soft orientation
            Fly.ao.CFrame = Fly.ao.CFrame:Lerp(cam.CFrame, 8 * dt)
        end)

        print("[Dingus][Fly] started · mounted=" .. tostring(Fly.mounted))
        return true
    end

    function Fly.stop()
        if not Fly.active then return end
        Fly.active = false
        St.FlyActive = false

        if Fly.flyConn then Fly.flyConn:Disconnect(); Fly.flyConn = nil end
        if Fly.noclipConn then Fly.noclipConn:Disconnect(); Fly.noclipConn = nil end
        if Fly.lv then pcall(function() Fly.lv:Destroy() end); Fly.lv = nil end
        if Fly.ao then pcall(function() Fly.ao:Destroy() end); Fly.ao = nil end
        if Fly.att then pcall(function() Fly.att:Destroy() end); Fly.att = nil end

        -- Restore original collision
        restoreCollide(Fly.savedCollide)

        -- Dismount horse: unequip then re-equip weapon
        local h = U.hum()
        if h then
            pcall(function() h:UnequipTools() end)
            task.wait(0.15)
        end

        print("[Dingus][Fly] stopped")
    end

    function Fly.toggle()
        if Fly.active then Fly.stop() else Fly.start() end
    end

    --========================================================
    -- PHASE 7: DEFERRED
    --========================================================
    phase(7, "deferred")
    St.boot = true
    print("[Dingus] ready · RightShift to toggle UI")
    pcall(function() U.notify("Dingus-Slayer", "loaded", 4) end)

    task.spawn(function()
        task.wait(0.5)
        pcall(function() Ctx.Opt.warmWorkspace() end)
        task.wait(0.3)
        pcall(function() Ctx.Opt.stripLighting() end)
        task.wait(0.3)
        pcall(function() Quest.doCycle() end)
        task.wait(0.3)
        local ok, bosses = pcall(function() return Ctx.Detect.scanBosses() end)
        if ok and bosses then
            print(string.format("[Dingus] initial scan: %d bosses", #bosses))
        end
        print("[Dingus] boot complete")
    end)

    --========================================================
    -- SCHEDULER
    --========================================================
    local loops = {
        makeLoop("combat",   function() Ctx.Atk.combatTick()       end, 0.05, 5),
        makeLoop("spoofers", function() Ctx.Spoof.tick()           end, 0.10, 5),
        makeLoop("threats",  function() Ctx.Detect.updateThreats() end, 0.10, 5),
        makeLoop("crow",     crowCycle,                                  2.0,  3),
        makeLoop("quest",    function() Quest.doCycle()            end, 5.0,  2),
        makeLoop("config",   function()
            local ok = Cfg.save()
            if not ok then error("autosave failed") end
        end, Cfg.AutoSaveT or 30, 2),
        makeLoop("gc",       function()
            pcall(function() collectgarbage("collect") end)
        end, 60, 1),
    }
    Ctx.Loops = loops

    task.spawn(function()
        while St.run do
            if St.boot then
                local now = U.clock()
                for i = 1, #loops do
                    local L = loops[i]
                    if not L.disabled and now - L.lastRun >= L.interval then
                        L.lastRun = now
                        L.totalRuns = L.totalRuns + 1
                        local ok, err = pcall(L.tick)
                        if ok then
                            if L.errors > 0 then L.errors = 0 end
                        else
                            L.errors = L.errors + 1
                            if L.errors <= 3 then
                                print(string.format("[Dingus][loop %s] err %d: %s", L.name, L.errors, tostring(err)))
                            end
                            if L.errors >= L.maxErrors then
                                L.disabled = true
                                print(string.format("[Dingus][loop %s] DISABLED", L.name))
                            end
                        end
                    end
                end
            end
            task.wait(0.03)
        end
    end)

    -- FPS
    pcall(function()
        game:GetService("RunService").RenderStepped:Connect(function(dt)
            if dt > 0 and dt < 1 then
                table.insert(St.fs, dt)
                if #St.fs > 30 then table.remove(St.fs, 1) end
                local sum = 0
                for i = 1, #St.fs do sum = sum + St.fs[i] end
                if sum > 0 then St.fps = #St.fs / sum end
            end
        end)
    end)

    -- Respawn
    pcall(function()
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            if Fly.active then Fly.stop() end
            St.tgt = nil
            St.ens = {}
            St.lScn = 0
            St.mxH = 0
            St.uGs = false
            St.lHp = 0
            St.lHpT = 0
            St.lDmg = 0
            scrubMovers()
            for i = 1, #loops do
                loops[i].errors = 0
                loops[i].disabled = false
            end
            print("[Dingus] respawned")
        end)
    end)

    -- UI toggle
    pcall(function()
        game:GetService("UserInputService").InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.KeyCode == Enum.KeyCode.RightShift then
                if Ctx.Gui and Ctx.Gui.win then
                    Ctx.Gui.win.Visible = not Ctx.Gui.win.Visible
                end
            end
        end)
    end)

    -- Unload
    Ctx.Unload = function()
        print("[Dingus] unloading...")
        if Fly.active then Fly.stop() end
        St.run = false
        St.boot = false
        pcall(function() Cfg.save() end)
        if St.hvB then pcall(function() St.hvB:Destroy() end); St.hvB = nil end
        if Ctx.Gui and Ctx.Gui.gui then
            pcall(function() Ctx.Gui.gui:Destroy() end)
        end
        local h = U.hum()
        if h then
            h.WalkSpeed = 16
            h.PlatformStand = false
        end
        print("[Dingus] unloaded")
    end
end

return M
