--[[
    Dingus-Slayer · main.lua v25
    Hover-behind system. No flight. Natural labels.
]]--

local M = {}

local PHASES = { "state", "scrub", "config", "subsystems", "systems", "deferred" }

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
    -- STATE
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

    St.cbtS = "IDLE"
    St.inp = 0
    St.mxH = 0
    St.lHp = 0; St.lHpT = 0; St.lDmg = 0
    St.lScn = 0; St.lTht = 0; St.lSpf = 0; St.lEqp = 0
    St.lAtk = 0; St.lSkl = 0; St.lBrt = 0; St.lFac = 0; St.lMove = 0
    St.lHover = 0; St.lHoverRecalc = 0; St.lCkC = 0
    St.rHt = {}
    St.skCd = { 0, 0, 0, 0, 0 }
    St.aiI = Cfg.AtkInterval
    St.eq = "none"; St.swp = 0; St.lTl = false
    St.kll = 0; St.bKll = 0; St.aAt = 0; St.aHi = 0; St.aMs = 0
    St.skC = 0; St.rtrC = 0; St.cQs = 0
    St.uGs = false; St.uC = 0; St.uGt = 0; St.uST = 0; St.uThC = 0
    St.ens = {}; St.ths = {}; St.zn = 0; St.imm = 0
    St.tgt = nil
    St.crT = nil; St.crM = nil; St.cPrch = false
    St.playerLevel = 0; St.questTarget = nil; St.huntCount = 0
    St.Spf = { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }
    St.fs = {}; St.fps = 60
    St.loadErrors = {}
    St.hoverActive = false
    St.hoverBp = nil

    --========================================================
    -- SCRUB
    --========================================================
    phase(2, "scrub")

    local function scrubMovers()
        local r = U.hrp(); if not r then return 0 end
        local n = 0
        for _, c in ipairs(r:GetChildren()) do
            if c:IsA("BodyPosition") or c:IsA("BodyVelocity")
                or c:IsA("BodyGyro") or c:IsA("BodyForce")
                or c:IsA("LinearVelocity") or c:IsA("AlignOrientation") then
                c:Destroy(); n = n + 1
            end
        end
        local h = U.hum()
        if h then h.PlatformStand = false; h.WalkSpeed = 16 end
        return n
    end
    local sc = scrubMovers()
    if sc > 0 then print("[Dingus] scrubbed " .. sc .. " movers") end

    --========================================================
    -- CONFIG
    --========================================================
    phase(3, "config")
    if Cfg.setUtils then Cfg.setUtils(U) end
    if Cfg.exists and Cfg.exists() then
        local okL, msgL = Cfg.load()
        print("[Dingus][Config] " .. tostring(msgL))
    end

    --========================================================
    -- SUBSYSTEMS
    --========================================================
    phase(4, "subsystems")
    local subsys = {
        { name = "detect",     mod = "Detect" },
        { name = "scanners",   mod = "Scan" },
        { name = "spoofers",   mod = "Spoof" },
        { name = "attack",     mod = "Atk" },
        { name = "optimizers", mod = "Opt" },
        { name = "gui",        mod = "Gui" },
    }
    local okCount = 0
    for i = 1, #subsys do
        local s = subsys[i]
        local mod = Ctx[s.mod]
        if mod and type(mod.init) == "function" then
            local ok, err = pcall(mod.init, Ctx)
            if ok then okCount = okCount + 1; print("[Dingus]   ✓ " .. s.name)
            else print("[Dingus]   ✗ " .. s.name .. ": " .. tostring(err)); table.insert(St.loadErrors, s.name .. ": " .. tostring(err)) end
        else
            print("[Dingus]   ✗ " .. s.name .. " missing")
            table.insert(St.loadErrors, s.name .. ": missing")
        end
        task.wait(0.02)
    end
    print(string.format("[Dingus] %d/%d subsystems ok", okCount, #subsys))

    --========================================================
    -- SYSTEMS
    --========================================================
    phase(5, "systems")

    -- Quest
    local Quest = { lastCheck = 0, hunts = {}, level = 0 }
    Ctx.Quest = Quest

    function Quest.readLevel()
        local hf = workspace:FindFirstChild("Humanoids")
        local me = hf and hf:FindFirstChild(U.Lp.Name)
        if me then
            local prog = me:FindFirstChild("Progression")
            local lvl = prog and prog:FindFirstChild("Level")
            if lvl and (lvl:IsA("NumberValue") or lvl:IsA("IntValue")) then return lvl.Value end
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
            if l2 and (l2:IsA("NumberValue") or l2:IsA("IntValue")) then return l2.Value end
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
        table.sort(out, function(a, b) return (tonumber(a.id) or 0) > (tonumber(b.id) or 0) end)
        return out
    end

    function Quest.doCycle()
        local now = U.clock()
        if now - Quest.lastCheck < Cfg.QuestCycleT then return end
        Quest.lastCheck = now
        Quest.level = Quest.readLevel()
        St.playerLevel = Quest.level
        Quest.hunts = Quest.findBossHunts()
        St.huntCount = #Quest.hunts
        if #Quest.hunts == 0 then return end
        for i = 1, #Quest.hunts do
            local h = Quest.hunts[i]
            local id = tonumber(h.id) or 0
            if id <= math.max(1, math.floor(Quest.level / 20)) then
                St.questTarget = h.quest:match("Eliminate%s+(.+)") or h.quest
                return
            end
        end
    end

    -- Crow
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
        local c = U.Lp.Character; if not c then return end
        local equipped = false
        for _, x in ipairs(c:GetChildren()) do
            if x:IsA("Tool") and Lists.isCrow(x.Name) then equipped = true; break end
        end
        if not equipped and tool:IsA("Tool") then
            local h = U.hum()
            if h then pcall(function() h:EquipTool(tool) end); task.wait(0.5) end
        end
        local model = Ctx.Scan.findCrowModel()
        if not model then U.m1(); task.wait(1.0); model = Ctx.Scan.findCrowModel() end
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

    --========================================================
    -- DEFERRED
    --========================================================
    phase(6, "deferred")
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
    -- MAIN SCHEDULER
    --========================================================
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
                                print(string.format("[Dingus][loop %s] disabled", L.name))
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
            if Ctx.Atk and Ctx.Atk.stopHover then Ctx.Atk.stopHover() end
            St.tgt = nil; St.ens = {}; St.lScn = 0
            St.mxH = 0; St.uGs = false
            St.lHp = 0; St.lHpT = 0; St.lDmg = 0
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
                    if Ctx.Gui.win.Visible then
                        if Ctx.Gui.minimize then Ctx.Gui.minimize() end
                    else
                        if Ctx.Gui.restore then Ctx.Gui.restore() end
                    end
                end
            end
        end)
    end)

    -- Unload
    Ctx.Unload = function()
        print("[Dingus] unloading...")
        if Ctx.Atk and Ctx.Atk.stopHover then Ctx.Atk.stopHover() end
        St.run = false
        St.boot = false
        pcall(function() Cfg.save() end)
        if Ctx.Gui and Ctx.Gui.gui then pcall(function() Ctx.Gui.gui:Destroy() end) end
        local h = U.hum()
        if h then h.WalkSpeed = 16; h.PlatformStand = false end
        print("[Dingus] unloaded")
    end
end

return M
