--[[
    Dingus-Slayer · main.lua v29
    Strict module/function separation. Cannot fail at chunk load.

    Structure:
      [module scope]  — M table + pure helpers only (no Ctx, no St, no game services)
      [M.boot(Ctx)]   — everything else, every phase pcall-wrapped
      [return M]

    Every subsystem install is safePhase-wrapped.
    Every loop tick is pcall-wrapped inside the scheduler.
    Crow cycle is a closure defined inside M.boot — cannot leak.

    Fixes prior crash: main.lua:13 attempt to index nil with 'Crow'
      — root cause was Ctx/St access at module scope. Impossible here.
]]--

local M = {}

--============================================================
-- MODULE SCOPE · pure helpers only
--============================================================

local PHASES = { "state", "scrub", "config", "subsystems", "systems", "deferred" }

local function phase(idx, name)
    print(string.format("[Dingus][boot %d/%d] %s", idx, #PHASES, name))
end

local function makeLoop(name, tick, interval, maxErrors)
    return {
        name = name,
        tick = tick,
        interval = interval or 0.1,
        maxErrors = maxErrors or 5,
        errors = 0,
        disabled = false,
        lastRun = 0,
        totalRuns = 0,
    }
end

local function safeRun(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        warn(string.format("[Dingus][main] %s: %s", label, tostring(err)))
    end
    return ok, err
end

--============================================================
-- FUNCTION SCOPE · M.boot
--============================================================

function M.boot(Ctx)
    --============================================================
    -- BOOT GUARDS
    --============================================================
    if type(Ctx) ~= "table" then
        warn("[Dingus][main] boot called without Ctx table — aborting")
        return
    end

    local U     = Ctx.Util
    local Cfg   = Ctx.Cfg
    local Lists = Ctx.Lists

    if not U then warn("[Dingus][main] Ctx.Util missing — aborting"); return end
    if not Cfg then warn("[Dingus][main] Ctx.Cfg missing — aborting"); return end
    if not Lists then warn("[Dingus][main] Ctx.Lists missing — aborting"); return end

    -- St may or may not exist; ensure it does
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

        -- Timestamps
        St.lHp = 0; St.lHpT = 0; St.lDmg = 0
        St.lScn = 0; St.lTht = 0; St.lSpf = 0; St.lEqp = 0
        St.lAtk = 0; St.lSkl = 0; St.lBrt = 0; St.lFac = 0; St.lMove = 0
        St.lHover = 0; St.lHoverRecalc = 0; St.lCkC = 0

        -- Hit history + skill cooldowns
        St.rHt = {}
        St.skCd = { 0, 0, 0, 0, 0, 0 }

        St.aiI = Cfg.AtkInterval or 0.55
        St.eq = "none"; St.swp = 0; St.lTl = false

        -- Kill/hit counters
        St.kll = 0; St.bKll = 0
        St.aAt = 0; St.aHi = 0; St.aMs = 0
        St.skC = 0; St.rtrC = 0; St.cQs = 0

        -- Fly
        St.FlyActive = false
        St.flyFailLogged = false

        -- UG
        St.uGs = false; St.uC = 0; St.uGt = 0; St.uST = 0; St.uThC = 0

        -- Detection
        St.ens = {}; St.ths = {}; St.zn = 0; St.imm = 0
        St.tgt = nil; St.tgtKind = nil

        -- Crow
        St.crT = nil; St.crM = nil; St.cPrch = false; St.crQuests = {}

        -- Quest
        St.playerLevel = 0
        St.questTarget = nil
        St.questList = {}
        St.huntCount = 0
        St.qCyc = 0

        -- Spoofer legacy
        St.Spf = { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }

        -- Oversight
        St.fs = {}; St.fps = 60
        St.loadErrors = {}
        St.hoverActive = false

        -- Config defaults for boot-critical keys
        Cfg.QuestCycleT = Cfg.QuestCycleT or 5.0
        Cfg.CrowCheckT  = Cfg.CrowCheckT  or 1.5
        Cfg.AutoSaveT   = Cfg.AutoSaveT   or 30

        print("[Dingus][main] state initialized")
    end)

    --============================================================
    -- PHASE 2 · SCRUB MOVERS
    --============================================================
    phase(2, "scrub")
    safeRun("scrub", function()
        local r = U.hrp()
        if not r then return end
        local n = 0
        for _, c in ipairs(r:GetChildren()) do
            local ok = pcall(function()
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
            { name = "fly",        mod = "Fly"    },
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

    -- Scheduler storage — always created, even if all subs fail
    local loops = {}

    --================================================================
    -- QUEST SUBSYSTEM
    --================================================================
    safeRun("quest-subsystem", function()
        local Quest = { lastCheck = 0, hunts = {}, level = 0 }
        Ctx.Quest = Quest

        function Quest.readLevel()
            local ok, result = pcall(function()
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
                if slots then
                    for _, slot in ipairs(slots:GetChildren()) do
                        local prog = slot:FindFirstChild("Progression")
                        local lvl = prog and prog:FindFirstChild("Level")
                        if lvl and (lvl:IsA("NumberValue") or lvl:IsA("IntValue")) then
                            return lvl.Value
                        end
                    end
                end
                return 0
            end)
            return ok and result or 0
        end

        function Quest.findBossHunts()
            local ok, result = pcall(function()
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
            end)
            return ok and result or {}
        end

        function Quest.doCycle()
            local now = U.clock()
            if now - Quest.lastCheck < (Cfg.QuestCycleT or 5.0) then return end
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
                    local parsed = h.quest:match("Eliminate%s+(.+)")
                        or h.quest:match("Defeat%s+(.+)")
                        or h.quest
                    St.questTarget = parsed
                    return
                end
            end
        end
    end)

    --================================================================
    -- CROW SUBSYSTEM
    -- All Ctx/St access confined to this closure. Cannot leak.
    --================================================================
    safeRun("crow-subsystem", function()
        local Crow = { last = 0, cycles = 0, takeAttempts = 0 }

        -- Helper: find cancel button in PlayerGui.ComponentsHolder
        local function findCancelButton()
            local ok, result = pcall(function()
                local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
                if not pg then return nil end
                local cc = pg:FindFirstChild("ComponentsHolder")
                if not cc then return nil end

                local stack = { cc }
                local iter = 0
                while #stack > 0 do
                    local inst = table.remove(stack)
                    if inst then
                        if inst:IsA("TextButton") then
                            local okT, txt = pcall(function() return inst.Text end)
                            if okT and type(txt) == "string" then
                                local low = txt:lower():gsub("^%s+", ""):gsub("%s+$", "")
                                if low == "cancel" or low == "close" then
                                    local okV, vis = pcall(function() return inst.Visible end)
                                    if okV and vis then return inst end
                                end
                            end
                        end
                        local okC, kids = pcall(function() return inst:GetChildren() end)
                        if okC and kids then
                            for i = 1, #kids do table.insert(stack, kids[i]) end
                        end
                        iter = iter + 1
                        if iter % 2000 == 0 then task.wait() end
                    end
                end
                return nil
            end)
            return ok and result or nil
        end

        -- Helper: read "Defeat X" labels from ComponentsHolder
        local function readCrowQuests()
            local ok, result = pcall(function()
                local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
                if not pg then return {} end
                local cc = pg:FindFirstChild("ComponentsHolder")
                if not cc then return {} end

                local found = {}
                local seen = {}
                local stack = { cc }
                local iter = 0
                while #stack > 0 do
                    local inst = table.remove(stack)
                    if inst then
                        if inst:IsA("TextLabel") then
                            local okT, txt = pcall(function() return inst.Text end)
                            if okT and type(txt) == "string" then
                                local name = txt:match("^%s*Defeat%s+(.+)$")
                                    or txt:match("^%s*Eliminate%s+(.+)$")
                                if name then
                                    name = name:gsub("%s+$", "")
                                    if #name > 0 and #name < 40 and not seen[name] then
                                        seen[name] = true
                                        table.insert(found, name)
                                    end
                                end
                            end
                        end
                        local okC, kids = pcall(function() return inst:GetChildren() end)
                        if okC and kids then
                            for i = 1, #kids do table.insert(stack, kids[i]) end
                        end
                        iter = iter + 1
                        if iter % 2000 == 0 then task.wait() end
                    end
                end
                return found
            end)
            return ok and result or {}
        end

        -- Helper: wait for crow sound
        local function waitForCaw(timeout)
            local deadline = U.clock() + (timeout or 3.0)
            while U.clock() < deadline do
                local ok = pcall(function()
                    local ws = workspace:GetDescendants()
                    for i = 1, #ws do
                        local s = ws[i]
                        if s:IsA("Sound") and s.IsPlaying then
                            local l = string.lower(s.Name)
                            if string.find(l, "caw", 1, true)
                                or string.find(l, "crow", 1, true)
                                or string.find(l, "chaa", 1, true) then
                                return true
                            end
                        end
                    end
                end)
                if ok then return true end
                task.wait(0.1)
            end
            return false
        end

        -- Main crow cycle
        local function crowCycle()
            if not St.crw then return end
            local now = U.clock()
            if now - Crow.last < (Cfg.CrowCheckT or 1.5) then return end
            Crow.last = now
            Crow.cycles = Crow.cycles + 1

            -- Step 1: find crow tool
            local tool = nil
            if Ctx.Scan and Ctx.Scan.findCrowTool then
                tool = Ctx.Scan.findCrowTool()
            end

            -- Step 2: if missing, try hotbar 5
            if not tool then
                pcall(function() U.tap("5") end)
                task.wait(0.4)
                if Ctx.Scan and Ctx.Scan.findCrowTool then
                    tool = Ctx.Scan.findCrowTool()
                end
            end
            if not tool then return end
            St.crT = tool

            -- Step 3: equip
            local c = U.Lp.Character
            if not c then return end
            local equipped = false
            for _, x in ipairs(c:GetChildren()) do
                if x:IsA("Tool") and Lists.isCrow and Lists.isCrow(x.Name) then
                    equipped = true
                    break
                end
            end
            if not equipped and tool:IsA("Tool") then
                local h = U.hum()
                if h then
                    pcall(function() h:EquipTool(tool) end)
                    task.wait(0.4)
                end
            end

            -- Step 4: open menu
            local cancel = findCancelButton()
            if not cancel then
                pcall(function() U.m1() end)
                waitForCaw(3.0)
                task.wait(0.4)
                cancel = findCancelButton()
            end
            if not cancel then
                pcall(function() U.m1() end)
                task.wait(0.8)
                cancel = findCancelButton()
            end
            if not cancel then return end
            St.cPrch = true

            -- Step 5: read quests
            local quests = readCrowQuests()
            if #quests > 0 then
                St.crQuests = quests
                print(string.format("[Dingus][Crow] %d quests: %s",
                    #quests, table.concat(quests, ", ")))
            end

            -- Step 6: close
            local cancelNow = findCancelButton()
            if cancelNow then
                pcall(function() cancelNow:Activate() end)
                task.wait(0.3)
            end
        end

        -- Expose
        Ctx.Crow = { cycle = crowCycle }
        St.Crow = St.Crow or {}
        St.Crow.cycle = crowCycle
    end)

    --================================================================
    -- BUILD SCHEDULER
    --================================================================
    safeRun("scheduler", function()
        local combatTick = function()
            local ok = Ctx.Atk and Ctx.Atk.combatTick
            if ok then pcall(Ctx.Atk.combatTick) end
        end
        local spoofTick = function()
            local ok = Ctx.Spoof and Ctx.Spoof.tick
            if ok then pcall(Ctx.Spoof.tick) end
        end
        local threatTick = function()
            local ok = Ctx.Detect and Ctx.Detect.updateThreats
            if ok then pcall(Ctx.Detect.updateThreats) end
        end
        local crowTick = function()
            if Ctx.Crow and Ctx.Crow.cycle then
                pcall(Ctx.Crow.cycle)
            elseif St.Crow and St.Crow.cycle then
                pcall(St.Crow.cycle)
            end
        end
        local questTick = function()
            if Ctx.Quest and Ctx.Quest.doCycle then
                pcall(Ctx.Quest.doCycle)
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

        loops = {
            makeLoop("combat",   combatTick,  0.05, 5),
            makeLoop("spoofers", spoofTick,   0.10, 5),
            makeLoop("threats",  threatTick,  0.10, 5),
            makeLoop("crow",     crowTick,    2.0,  3),
            makeLoop("quest",    questTick,   5.0,  2),
            makeLoop("config",   configTick,  Cfg.AutoSaveT or 30, 2),
            makeLoop("gc",       gcTick,      60, 1),
        }
        Ctx.Loops = loops
        print(string.format("[Dingus][main] %d scheduler loops", #loops))
    end)

    --================================================================
    -- PHASE 6 · DEFERRED
    --================================================================
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
        if Ctx.Quest and Ctx.Quest.doCycle then
            pcall(Ctx.Quest.doCycle)
        end
        task.wait(0.3)
        local ok, bosses = pcall(function()
            if Ctx.Detect and Ctx.Detect.scanBosses then
                return Ctx.Detect.scanBosses()
            end
            return {}
        end)
        if ok and bosses then
            print(string.format("[Dingus] initial scan: %d bosses", #bosses))
        end
        print("[Dingus] boot complete")
    end)

    --================================================================
    -- MAIN SCHEDULER
    --================================================================
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

    --================================================================
    -- FPS SAMPLER
    --================================================================
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

    --================================================================
    -- RESPAWN
    --================================================================
    pcall(function()
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            if Ctx.Atk and Ctx.Atk.stopHover then pcall(Ctx.Atk.stopHover) end
            if Ctx.Fly and Ctx.Fly.stop then pcall(Ctx.Fly.stop) end
            St.tgt = nil
            St.ens = {}
            St.lScn = 0
            St.mxH = 0
            St.uGs = false
            St.lHp = 0; St.lHpT = 0; St.lDmg = 0
            St.FlyActive = false
            St.flyFailLogged = false
            for i = 1, #loops do
                loops[i].errors = 0
                loops[i].disabled = false
            end
            print("[Dingus] respawned")
        end)
    end)

    --================================================================
    -- RIGHTSHIFT TOGGLE
    --================================================================
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

    --================================================================
    -- UNLOAD
    --================================================================
    Ctx.Unload = function()
        print("[Dingus] unloading...")
        if Ctx.Atk and Ctx.Atk.stopHover then pcall(Ctx.Atk.stopHover) end
        if Ctx.Fly and Ctx.Fly.stop then pcall(Ctx.Fly.stop) end
        St.run = false
        St.boot = false
        pcall(function()
            if Cfg.save then Cfg.save("default") end
        end)
        if Ctx.Cleanup then
            for i = 1, #Ctx.Cleanup do
                pcall(Ctx.Cleanup[i])
            end
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
