--[[
    Dingus-Slayer · main.lua v35 · compressed
    Same feature set as v34. Just denser.
]]--

local M = {}
local PH = { "state", "scrub", "config", "subsys", "sys", "defer" }

local function mk(n, t, i, e)
    return { name = n, tick = t, interval = i or 0.1,
             maxErrors = e or 5, errors = 0, disabled = false,
             lastRun = 0, totalRuns = 0 }
end

local function sr(label, fn)
    local ok, err = pcall(fn)
    if not ok then warn("[Dingus][main] "..label..": "..tostring(err)) end
    return ok
end

function M.boot(C)
    if type(C) ~= "table" then
        warn("[Dingus][main] no Ctx — abort")
        return
    end

    _G.Ctx = C
    local U, F, L = C.Util, C.Cfg, C.Lists
    if not U or not F then
        warn("[Dingus][main] Util/Cfg missing — abort")
        return
    end

    local S = C.St or {}
    C.St = S
    _G.St = S

    --========================================================
    -- P1 · state
    --========================================================
    print(string.format("[Dingus][boot 1/%d] %s", #PH, PH[1]))
    sr("state", function()
        S.run, S.boot, S.bootPhase = true, false, "state"
        local D = F.DefaultToggles or {}
        S.cbt     = D.combat  or false
        S.skl     = D.skl     ~= false
        S.eqp     = D.eqp     ~= false
        S.rtr     = D.rtr     ~= false
        S.gsp     = D.gsp     or false
        S.crw     = D.crw     ~= false
        S.stunPun = D.stunPun ~= false

        -- timers table (single source)
        S.t = {}
        for _, k in ipairs({
            "lHp","lHpT","lDmg","lScn","lTht","lSpf","lEqp","lAtk",
            "lSkl","lBrt","lFac","lMove","lTele",
        }) do S.t[k] = 0 end

        S.cbtS = "IDLE"
        S.rHt  = {}
        S.skCd = {0,0,0,0,0,0}
        S.aiI  = F.AtkInterval or 0.38
        S.eq   = "none"
        S.kll, S.bKll, S.aAt, S.aHi, S.aMs = 0, 0, 0, 0, 0
        S.skC, S.rtrC, S.cQs, S.teleCount = 0, 0, 0, 0

        S.FlyActive, S.flyFailLogged = false, false
        S.uGs, S.uC, S.uGt, S.uST, S.uThC = false, 0, 0, 0, 0

        S.ens, S.ths, S.zn, S.imm = {}, {}, 0, 0
        S.tgt, S.tgtKind = nil, nil

        S.crT, S.crM, S.cPrch, S.crQuests = nil, nil, false, {}
        S.crowCycle, S.crowTake = 0, 0

        S.playerLevel, S.questTarget, S.questList = 0, nil, {}
        S.huntCount, S.qCyc = 0, 0

        S.questPriorityBosses = {}
        S.questActiveList = {}
        S.questAvailableCount = 0
        S.questCycleCount = 0
        S.questLastRead = 0
        S.questLastCycle = 0
        S.questPanelOpened = false

        S.chestCollected, S.chestLootCollected = 0, 0
        S.chestFailed, S.chestSkipped = 0, 0
        S.chestPasses, S.chestCooldowns = 0, {}

        S.Spf = { hpC=0, bkC=0, spdC=0, kbC=0, jmpC=0 }
        S.fs, S.fps = {}, 60
        S.loadErrors = {}
        S.hoverActive = false

        F.QuestCycleT = F.QuestCycleT or 6.0
        F.AutoSaveT   = F.AutoSaveT   or 30

        print("[Dingus][main] state init")
    end)

    --========================================================
    -- P2 · scrub movers
    --========================================================
    print(string.format("[Dingus][boot 2/%d] %s", #PH, PH[2]))
    sr("scrub", function()
        local R = U.hrp(); if not R then return end
        local n = 0
        for _, c in ipairs(R:GetChildren()) do
            if c:IsA("BodyPosition") or c:IsA("BodyVelocity")
                or c:IsA("BodyGyro") or c:IsA("BodyForce")
                or c:IsA("LinearVelocity") or c:IsA("AlignOrientation")
                or c:IsA("AlignPosition") then
                pcall(c.Destroy, c); n = n + 1
            end
        end
        local H = U.hum()
        if H then H.PlatformStand = false; H.WalkSpeed = 16; H.AutoRotate = true end
        if n > 0 then print("[Dingus][main] scrubbed "..n) end
    end)

    --========================================================
    -- P3 · config
    --========================================================
    print(string.format("[Dingus][boot 3/%d] %s", #PH, PH[3]))
    sr("config", function()
        if F.setUtils then F.setUtils(U) end
        if F.exists and F.exists("default") then
            local ok, msg = F.load("default")
            print("[Dingus][Config] "..tostring(msg))
        end
    end)

    --========================================================
    -- P4 · subsystems
    --========================================================
    print(string.format("[Dingus][boot 4/%d] %s", #PH, PH[4]))
    sr("subsys", function()
        local order = {
            { "detect",     "Detect" },
            { "scanners",   "Scan"   },
            { "hotbar",     "Hotbar" },
            { "spoofers",   "Spoof"  },
            { "chest",      "Chest"  },
            { "quests",     "Quest"  },
            { "attack",     "Atk"    },
            { "optimizers", "Opt"    },
            { "gui",        "Gui"    },
        }
        local ok = 0
        for i = 1, #order do
            local pair = order[i]
            local mod = C[pair[2]]
            if mod and type(mod.init) == "function" then
                local good, err = pcall(mod.init, C)
                if good then ok = ok + 1
                    print("[Dingus]   + "..pair[1])
                else
                    print("[Dingus]   x "..pair[1]..": "..tostring(err))
                    table.insert(S.loadErrors, pair[1]..": "..tostring(err))
                end
            else
                print("[Dingus]   x "..pair[1].." missing")
                table.insert(S.loadErrors, pair[1]..": missing")
            end
            task.wait(0.02)
        end
        print(string.format("[Dingus] %d/%d subsystems ok", ok, #order))

        for _, k in ipairs({
            "Cfg","Detect","Scan","Hotbar","Spoof","Chest","Quest",
            "Atk","Opt","Gui",
        }) do
            if C[k] then pcall(function() _G[k] = C[k] end) end
        end
    end)

    --========================================================
    -- P5 · scheduler
    --========================================================
    print(string.format("[Dingus][boot 5/%d] %s", #PH, PH[5]))

    local loops = {}

    sr("scheduler", function()
        -- tick builders — every closure is pcall-wrapped at call site
        local function T(name, fn)
            return function()
                local f = C[name]
                if f then pcall(fn, f) end
            end
        end

        loops = {
            mk("combat",   function() if C.Atk and C.Atk.combatTick then pcall(C.Atk.combatTick) end end, 0.05, 5),
            mk("spoofers", function() if C.Spoof and C.Spoof.tick then pcall(C.Spoof.tick) end end, 0.10, 5),
            mk("threats",  function() if C.Detect and C.Detect.updateThreats then pcall(C.Detect.updateThreats) end end, 0.10, 5),
            mk("quest",    function() if C.Quest and C.Quest.cycle then pcall(C.Quest.cycle) end end, 0.5, 3),
            mk("chest",    function() if C.Chest and C.Chest.collectPassive then pcall(C.Chest.collectPassive) end end, 3.0, 3),
            mk("config",   function()
                if F.tickAutoSave then pcall(F.tickAutoSave) end
                if F.save then pcall(function() F.save("default") end) end
            end, F.AutoSaveT or 30, 2),
            mk("gc", function() pcall(function() collectgarbage("collect") end) end, 60, 1),
        }
        C.Loops = loops
        print(string.format("[Dingus][main] %d loops", #loops))
    end)

    --========================================================
    -- P6 · deferred
    --========================================================
    print(string.format("[Dingus][boot 6/%d] %s", #PH, PH[6]))
    S.boot = true
    print("[Dingus] ready · RightShift to toggle UI")
    pcall(function() U.notify("Dingus-Slayer", "loaded", 4) end)

    -- one-shot warmup
    task.spawn(function()
        local steps = {
            function() if C.Opt and C.Opt.warmWorkspace then C.Opt.warmWorkspace() end end,
            function() if C.Opt and C.Opt.stripLighting then C.Opt.stripLighting() end end,
            function() if C.Quest and C.Quest.cycle then C.Quest.cycle() end end,
            function()
                if C.Detect and C.Detect.scanBosses then
                    local ok, b = pcall(C.Detect.scanBosses, nil, true)
                    if ok and b then
                        print(string.format("[Dingus] initial scan: %d bosses", #b))
                    end
                end
            end,
        }
        for i = 1, #steps do
            task.wait(0.3)
            pcall(steps[i])
        end
        print("[Dingus] boot complete")
    end)

    --========================================================
    -- main scheduler — single task, all loops
    --========================================================
    local ST = S
    task.spawn(function()
        while ST.run do
            if ST.boot then
                local t = U.clock()
                local n = #loops
                for i = 1, n do
                    local L = loops[i]
                    if not L.disabled and t - L.lastRun >= L.interval then
                        L.lastRun = t
                        L.totalRuns = L.totalRuns + 1
                        local ok, err = pcall(L.tick)
                        if ok then
                            if L.errors > 0 then L.errors = 0 end
                        else
                            L.errors = L.errors + 1
                            if L.errors <= 3 then
                                print(string.format("[Dingus][loop %s] err %d: %s",
                                    L.name, L.errors, tostring(err)))
                            end
                            if L.errors >= L.maxErrors then
                                L.disabled = true
                                print("[Dingus][loop "..L.name.."] disabled")
                            end
                        end
                    end
                end
            end
            task.wait(0.05)
        end
    end)

    --========================================================
    -- FPS sampler
    --========================================================
    pcall(function()
        game:GetService("RunService").RenderStepped:Connect(function(dt)
            if dt > 0 and dt < 1 then
                local fs = ST.fs
                fs[#fs + 1] = dt
                if #fs > 30 then table.remove(fs, 1) end
                local s = 0
                for i = 1, #fs do s = s + fs[i] end
                if s > 0 then ST.fps = #fs / s end
            end
        end)
    end)

    --========================================================
    -- Respawn
    --========================================================
    pcall(function()
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            if C.Atk and C.Atk.stopHover then pcall(C.Atk.stopHover) end
            if C.Hotbar and C.Hotbar.forceRelease then pcall(C.Hotbar.forceRelease) end
            if C.Chest and C.Chest.resetCooldowns then pcall(C.Chest.resetCooldowns) end
            ST.tgt = nil
            ST.ens = {}
            ST.lScn = 0
            ST.mxH = 0
            ST.uGs = false
            ST.cPrch = false
            ST.FlyActive = false
            ST.lHp, ST.lHpT, ST.lDmg = 0, 0, 0
            for i = 1, #loops do
                loops[i].errors = 0
                loops[i].disabled = false
            end
            print("[Dingus] respawned")
        end)
    end)

    --========================================================
    -- RightShift toggle
    --========================================================
    pcall(function()
        game:GetService("UserInputService").InputBegan:Connect(function(inp, gp)
            if gp then return end
            if inp.KeyCode == Enum.KeyCode.RightShift then
                local G = C.Gui
                if G and G.win then
                    if G.win.Visible then
                        if G.minimize then G.minimize() end
                    else
                        if G.restore then G.restore() end
                    end
                end
            end
        end)
    end)

    --========================================================
    -- Unload
    --========================================================
    C.Unload = function()
        print("[Dingus] unloading...")
        if C.Atk and C.Atk.stopHover then pcall(C.Atk.stopHover) end
        if C.Hotbar and C.Hotbar.forceRelease then pcall(C.Hotbar.forceRelease) end
        ST.run, ST.boot = false, false
        pcall(function() if F.save then F.save("default") end end)
        if C.Cleanup then
            for i = 1, #C.Cleanup do pcall(C.Cleanup[i]) end
        end
        if C.Gui and C.Gui.gui then pcall(function() C.Gui.gui:Destroy() end) end
        local H = U.hum()
        if H then H.WalkSpeed = 16; H.PlatformStand = false end
        _G.Ctx, _G.St = nil, nil
        print("[Dingus] unloaded")
    end
end

return M
