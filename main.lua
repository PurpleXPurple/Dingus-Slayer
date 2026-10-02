--[[
    Dingus-Slayer · main.lua v32
    Boot orchestration. No inline crow or quest subsystems.

    Changes from v31:
      - Removed crow subsystem (now in quests.lua)
      - Removed inline Quest (now in quests.lua)
      - Added quests to subsystems list
      - Single quest loop calls Ctx.Quest.cycle
      - Removed crow loop from scheduler
]]--

local M = {}

local PHASES = { "state", "scrub", "config", "subsystems", "systems", "deferred" }

local function phase(idx, name)
    print(string.format("[Dingus][boot %d/%d] %s", idx, #PHASES, name))
end

local function makeLoop(name, tick, interval, maxErrors)
    return {
        name = name, tick = tick, interval = interval or 0.1,
        maxErrors = maxErrors or 5, errors = 0, disabled = false,
        lastRun = 0, totalRuns = 0,
    }
end

local function safeRun(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        warn(string.format("[Dingus][main] %s: %s", label, tostring(err)))
    end
    return ok, err
end

function M.boot(Ctx)
    if type(Ctx) ~= "table" then
        warn("[Dingus][main] boot called without Ctx — aborting")
        return
    end

    local U     = Ctx.Util
    local Cfg   = Ctx.Cfg
    local Lists = Ctx.Lists

    if not U then warn("[Dingus][main] Util missing"); return end
    if not Cfg then warn("[Dingus][main] Cfg missing"); return end

    local St = Ctx.St
    if type(St) ~= "table" then
        St = {}
        Ctx.St = St
    end

    --============================================================
    -- PHASE 1 · STATE
    --============================================================
    phase(1, "state")
    safeRun("state", function()
        St.run = true
        St.boot = false
        St.bootPhase = "state"

        local DT = Cfg.DefaultToggles or {}
        St.cbt     = DT.combat  or false
        St.skl     = DT.skl     ~= false
        St.eqp     = DT.eqp     ~= false
        St.rtr     = DT.rtr     ~= false
        St.gsp     = DT.gsp     or false
        St.crw     = DT.crw     ~= false
        St.stunPun = DT.stunPun ~= false

        St.cbtS = "IDLE"
        St.inp = 0
        St.mxH = 0

        St.lHp = 0; St.lHpT = 0; St.lDmg = 0
        St.lScn = 0; St.lTht = 0; St.lSpf = 0; St.lEqp = 0
        St.lAtk = 0; St.lSkl = 0; St.lBrt = 0; St.lFac = 0; St.lMove = 0
        St.lTele = 0

        St.rHt = {}
        St.skCd = { 0, 0, 0, 0, 0, 0 }

        St.aiI = Cfg.AtkInterval or 0.38
        St.eq = "none"; St.swp = 0; St.lTl = false

        St.kll = 0; St.bKll = 0
        St.aAt = 0; St.aHi = 0; St.aMs = 0
        St.skC = 0; St.rtrC = 0; St.cQs = 0
        St.teleCount = 0

        St.FlyActive = false

        St.uGs = false; St.uC = 0; St.uGt = 0; St.uST = 0; St.uThC = 0

        St.ens = {}; St.ths = {}; St.zn = 0; St.imm = 0
        St.tgt = nil; St.tgtKind = nil

        -- Quest state
        St.questPriorityBosses = {}
        St.questActiveList = {}
        St.questAvailableCount = 0
        St.questCycleCount = 0
        St.questLastRead = 0
        St.questLastCycle = 0
        St.questPanelOpened = false

        -- Crow state (retained for GUI reads)
        St.crT = nil; St.cPrch = false; St.crQuests = {}
        St.crowCycle = 0
        St.crowTake = 0

        St.playerLevel = 0
        St.questTarget = nil
        St.huntCount = 0
        St.qCyc = 0

        St.Spf = { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }

        St.fs = {}; St.fps = 60
        St.loadErrors = {}
        St.hoverActive = false

        Cfg.QuestCycleT = Cfg.QuestCycleT or 6.0
        Cfg.AutoSaveT   = Cfg.AutoSaveT   or 30

        print("[Dingus][main] state initialized")
    end)

    --============================================================
    -- PHASE 2 · SCRUB
    --============================================================
    phase(2, "scrub")
    safeRun("scrub", function()
        local r = U.hrp()
        if not r then return end
        local n = 0
        for _, c in ipairs(r:GetChildren()) do
            pcall(function()
                if c:IsA("BodyPosition") or c:IsA("BodyVelocity")
                    or c:IsA("BodyGyro") or c:IsA("BodyForce")
                    or c:IsA("LinearVelocity") or c:IsA("AlignOrientation")
                    or c:IsA("AlignPosition") then
                    c:Destroy()
                    n = n + 1
                end
            end)
        end
        local h = U.hum()
        if h then
            h.PlatformStand = false
            h.WalkSpeed = 16
            h.AutoRotate = true
        end
        if n > 0 then print("[Dingus][main] scrubbed " .. n .. " movers") end
    end)

    --============================================================
    -- PHASE 3 · CONFIG
    --============================================================
    phase(3, "config")
    safeRun("config", function()
        if Cfg.setUtils then Cfg.setUtils(U) end
        if Cfg.exists and Cfg.exists("default") then
            local ok, msg = Cfg.load("default")
            print("[Dingus][Config] " .. tostring(msg))
        end
    end)

    --============================================================
    -- PHASE 4 · SUBSYSTEMS
    --============================================================
    phase(4, "subsystems")
    safeRun("subsystems", function()
        local subsys = {
            { name = "detect",     mod = "Detect" },
            { name = "scanners",   mod = "Scan"   },
            { name = "spoofers",   mod = "Spoof"  },
            { name = "quests",     mod = "Quest"  },
            { name = "attack",     mod = "Atk"    },
            { name = "optimizers", mod = "Opt"    },
            { name = "gui",        mod = "Gui"    },
        }
        local okCount = 0
        for i = 1, #subsys do
            local s = subsys[i]
            local mod = Ctx[s.mod]
            if mod and type(mod.init) == "function" then
                local ok, err = pcall(mod.init, Ctx)
                if ok then
                    okCount = okCount + 1
                    print("[Dingus]   + " .. s.name)
                else
                    print("[Dingus]   x " .. s.name .. ": " .. tostring(err))
                    table.insert(St.loadErrors, s.name .. ": " .. tostring(err))
                end
            else
                print("[Dingus]   x " .. s.name .. " missing")
                table.insert(St.loadErrors, s.name .. ": missing")
            end
            task.wait(0.02)
        end
        print(string.format("[Dingus] %d/%d subsystems ok", okCount, #subsys))
    end)

    --============================================================
    -- PHASE 5 · SYSTEMS
    --============================================================
    phase(5, "systems")

    local loops = {}

    safeRun("scheduler", function()
        local combatTick = function()
            if Ctx.Atk and Ctx.Atk.combatTick then
                pcall(Ctx.Atk.combatTick)
            end
        end
        local spoofTick = function()
            if Ctx.Spoof and Ctx.Spoof.tick then
                pcall(Ctx.Spoof.tick)
            end
        end
        local threatTick = function()
            if Ctx.Detect and Ctx.Detect.updateThreats then
                pcall(Ctx.Detect.updateThreats)
            end
        end
        local questTick = function()
            if Ctx.Quest and Ctx.Quest.cycle then
                pcall(Ctx.Quest.cycle)
            end
        end
        local configTick = function()
            if Cfg.save then
                local ok = Cfg.save("default")
                if not ok then error("autosave failed") end
            end
        end
        local gcTick = function()
            pcall(function() collectgarbage("collect") end)
        end

        local built = {
            makeLoop("combat",   combatTick,  0.05, 5),
            makeLoop("spoofers", spoofTick,   0.10, 5),
            makeLoop("threats",  threatTick,  0.10, 5),
            makeLoop("quest",    questTick,   Cfg.QuestCycleT or 6.0, 3),
            makeLoop("config",   configTick,  Cfg.AutoSaveT or 30, 2),
            makeLoop("gc",       gcTick,      60, 1),
        }
        loops = built
        Ctx.Loops = loops
        print(string.format("[Dingus][main] %d scheduler loops", #loops))
    end)

    --============================================================
    -- PHASE 6 · DEFERRED
    --============================================================
    phase(6, "deferred")
    St.boot = true
    print("[Dingus] ready · RightShift to toggle UI")
    pcall(function() U.notify("Dingus-Slayer", "loaded", 4) end)

    task.spawn(function()
        task.wait(0.5)
        if Ctx.Opt and Ctx.Opt.warmWorkspace then
            pcall(Ctx.Opt.warmWorkspace)
        end
        task.wait(0.3)
        if Ctx.Opt and Ctx.Opt.stripLighting then
            pcall(Ctx.Opt.stripLighting)
        end
        task.wait(0.3)
        if Ctx.Quest and Ctx.Quest.cycle then
            pcall(Ctx.Quest.cycle)
        end
        task.wait(0.3)
        local ok, bosses = pcall(function()
            if Ctx.Detect and Ctx.Detect.scanBosses then
                return Ctx.Detect.scanBosses(nil, true)
            end
            return {}
        end)
        if ok and bosses then
            print(string.format("[Dingus] initial scan: %d bosses", #bosses))
        end
        print("[Dingus] boot complete")
    end)

    --============================================================
    -- MAIN SCHEDULER
    --============================================================
    local ST = St
    task.spawn(function()
        while ST.run do
            if ST.boot then
                local now = U.clock()
                local n = #loops
                for i = 1, n do
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
                                print(string.format(
                                    "[Dingus][loop %s] err %d: %s",
                                    L.name, L.errors, tostring(err)))
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

    --============================================================
    -- FPS
    --============================================================
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

    --============================================================
    -- RESPAWN
    --============================================================
    pcall(function()
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            if Ctx.Atk and Ctx.Atk.stopHover then pcall(Ctx.Atk.stopHover) end
            St.tgt = nil
            St.ens = {}
            St.lScn = 0
            St.mxH = 0
            St.uGs = false
            St.lHp = 0; St.lHpT = 0; St.lDmg = 0
            St.cPrch = false
            St.FlyActive = false
            for i = 1, #loops do
                loops[i].errors = 0
                loops[i].disabled = false
            end
            print("[Dingus] respawned")
        end)
    end)

    --============================================================
    -- RIGHTSHIFT
    --============================================================
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

    --============================================================
    -- UNLOAD
    --============================================================
    Ctx.Unload = function()
        print("[Dingus] unloading...")
        if Ctx.Atk and Ctx.Atk.stopHover then pcall(Ctx.Atk.stopHover) end
        St.run = false
        St.boot = false
        pcall(function() if Cfg.save then Cfg.save("default") end end)
        if Ctx.Cleanup then
            for i = 1, #Ctx.Cleanup do pcall(Ctx.Cleanup[i]) end
        end
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
