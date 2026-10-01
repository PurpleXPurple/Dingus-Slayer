--[[
    Dingus-Slayer · main.lua v22
    Staged boot · isolated subsystem init · deferred heavy work
    Scheduler with per-loop error budgets · auto-save · clean unload
]]--

local M = {}

--============================================================
-- BOOT PHASES
--============================================================
local PHASES = {
    "state",       -- initialize all St fields
    "scrub",       -- clear orphan body movers
    "config",      -- load saved config
    "subsystems",  -- init all modules (isolated pcall each)
    "systems",     -- quest reader, crow state, spawn loops
    "deferred",    -- heavy work (asset preload, deep scans) — async
}

local function phase(idx, name, detail)
    local total = #PHASES
    print(string.format("[Dingus][boot %d/%d] %s%s",
        idx, total, name, detail and (" — " .. detail) or ""))
end

--============================================================
-- LOOP ERROR BUDGET
--============================================================
local function makeLoop(name, tick, interval, maxErrors)
    maxErrors = maxErrors or 5
    return {
        name = name,
        tick = tick,
        interval = interval or 0.1,
        maxErrors = maxErrors,
        errors = 0,
        disabled = false,
        lastRun = 0,
        totalRuns = 0,
    }
end

--============================================================
-- MAIN BOOT
--============================================================
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

    -- Feature flags
    St.cbt = Cfg.DefaultToggles.combat
    St.skl = Cfg.DefaultToggles.skl
    St.eqp = Cfg.DefaultToggles.eqp
    St.rtr = Cfg.DefaultToggles.rtr
    St.gsp = Cfg.DefaultToggles.gsp
    St.crw = Cfg.DefaultToggles.crw
    St.stunPun = Cfg.DefaultToggles.stunPun

    -- Status
    St.cbtS = "IDLE"
    St.inp = 0

    -- Health observation
    St.mxH = 0
    St.lHp = 0
    St.lHpT = 0
    St.lDmg = 0

    -- Timestamps (all init to 0 so first tick always runs)
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

    -- Attack state
    St.rHt = {}
    St.skCd = { 0, 0, 0, 0, 0 }
    St.aiI = Cfg.AtkInterval
    St.eq = "none"
    St.swp = 0
    St.lTl = false

    -- Counters
    St.kll = 0
    St.bKll = 0
    St.aAt = 0
    St.aHi = 0
    St.aMs = 0
    St.skC = 0
    St.rtrC = 0
    St.cQs = 0

    -- Underground
    St.uGs = false
    St.uC = 0
    St.uGt = 0
    St.uST = 0
    St.uThC = 0

    -- Caches
    St.ens = {}
    St.ths = {}
    St.zn = 0
    St.imm = 0
    St.tgt = nil
    St.hvB = nil

    -- Crow
    St.crT = nil
    St.crM = nil
    St.cPrch = false

    -- Quest
    St.playerLevel = 0
    St.questTarget = nil
    St.huntCount = 0

    -- Spoofer counters
    St.Spf = { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }

    -- FPS tracker
    St.fs = {}
    St.fps = 60

    -- Load state
    St.loadStage = "booting"
    St.loadErrors = {}

    --========================================================
    -- PHASE 2: SCRUB MOVERS
    --========================================================
    phase(2, "scrub")
    St.bootPhase = "scrub"

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
    if scrubbed > 0 then
        print("[Dingus] scrubbed " .. scrubbed .. " orphan movers")
    end

    --========================================================
    -- PHASE 3: CONFIG
    --========================================================
    phase(3, "config")
    St.bootPhase = "config"

    if Cfg.setUtils then Cfg.setUtils(U) end

    if Cfg.exists and Cfg.exists() then
        local okL, msgL = Cfg.load()
        print("[Dingus][Config] " .. tostring(msgL))
    else
        print("[Dingus][Config] no file, using defaults")
    end

    --========================================================
    -- PHASE 4: SUBSYSTEMS
    --========================================================
    phase(4, "subsystems")
    St.bootPhase = "subsystems"

    local subsystems = {
        { name = "detect",     mod = "Detect" },
        { name = "scanners",   mod = "Scan" },
        { name = "spoofers",   mod = "Spoof" },
        { name = "attack",     mod = "Atk" },
        { name = "optimizers", mod = "Opt" },
        { name = "gui",        mod = "Gui" },
    }

    local subsystemsOk = 0
    for i = 1, #subsystems do
        local s = subsystems[i]
        local mod = Ctx[s.mod]
        if not mod then
            print(string.format("[Dingus] %s missing", s.name))
            table.insert(St.loadErrors, s.name .. ": not loaded")
        elseif type(mod.init) ~= "function" then
            print(string.format("[Dingus] %s has no init", s.name))
            table.insert(St.loadErrors, s.name .. ": no init function")
        else
            local ok, err = pcall(mod.init, Ctx)
            if ok then
                subsystemsOk = subsystemsOk + 1
                print(string.format("[Dingus]   ✓ %s", s.name))
            else
                print(string.format("[Dingus]   ✗ %s: %s", s.name, tostring(err)))
                table.insert(St.loadErrors, s.name .. ": " .. tostring(err))
            end
        end
        task.wait(0.02)
    end
    print(string.format("[Dingus] %d/%d subsystems ok", subsystemsOk, #subsystems))

    --========================================================
    -- PHASE 5: SYSTEMS (quest, crow, schedulers)
    --========================================================
    phase(5, "systems")
    St.bootPhase = "systems"

    --=========================================================
    -- QUEST SYSTEM
    --=========================================================
    local Quest = { lastCheck = 0, hunts = {}, level = 0 }
    Ctx.Quest = Quest

    function Quest.readLevel()
        -- Path 1: Humanoids folder
        local hf = workspace:FindFirstChild("Humanoids")
        local me = hf and hf:FindFirstChild(U.Lp.Name)
        if me then
            local prog = me:FindFirstChild("Progression")
            local lvl = prog and prog:FindFirstChild("Level")
            if lvl and (lvl:IsA("NumberValue") or lvl:IsA("IntValue")) then
                return lvl.Value
            end
        end
        -- Path 2: Player_Service
        local rs = game:GetService("ReplicatedStorage")
        local ps = rs:FindFirstChild("Player_Service")
        local data = ps and ps:FindFirstChild("Data")
        local me2 = data and data:FindFirstChild(U.Lp.Name)
        local slots = me2 and me2:FindFirstChild("slots")
        local s1 = slots and slots:FindFirstChild("Slot1")
        if s1 then
            local prog2 = s1:FindFirstChild("Progression")
            local lvl2 = prog2 and prog2:FindFirstChild("Level")
            if lvl2 and (lvl2:IsA("NumberValue") or lvl2:IsA("IntValue")) then
                return lvl2.Value
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

    function Quest.pickQuest(level, hunts)
        -- Higher ID = higher level in this game. Pick highest we qualify for.
        -- Level ranges roughly: #1 lv 1-20, #2 lv 20-40, #3 lv 40-60, #4 lv 60+
        for i = 1, #hunts do
            local h = hunts[i]
            local id = tonumber(h.id) or 0
            local threshold = math.max(1, math.floor(level / 20))
            if id <= threshold then
                return h
            end
        end
        return hunts[1]
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

        if #hunts == 0 then
            return
        end

        local pick = Quest.pickQuest(Quest.level, hunts)
        if pick then
            local target = pick.quest:match("Eliminate%s+(.+)") or pick.quest
            St.questTarget = target
        end
    end

    --=========================================================
    -- CROW SUBSYSTEM
    --=========================================================
    local Crow = { last = 0, accepts = 0, perched = false }
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
            if x:IsA("Tool") and Lists.isCrow(x.Name) then
                equipped = true
                break
            end
        end

        if not equipped and tool:IsA("Tool") then
            local h = U.hum()
            if h then
                pcall(function() h:EquipTool(tool) end)
                task.wait(0.5)
            end
        end

        local model = Ctx.Scan.findCrowModel()
        if not model then
            U.m1()
            task.wait(1.0)
            model = Ctx.Scan.findCrowModel()
        end

        Crow.perched = (model ~= nil)
        St.cPrch = Crow.perched
        if not Crow.perched then return end

        local menu = Ctx.Scan.findCrowMenu()
        if not menu then
            U.m1()
            task.wait(0.5)
            menu = Ctx.Scan.findCrowMenu()
        end

        if menu then
            pcall(function() menu:Activate() end)
            Crow.accepts = Crow.accepts + 1
            St.cQs = Crow.accepts
            print("[Dingus][Crow] accepted #" .. Crow.accepts)
            task.wait(0.8)
        end
    end

    --=========================================================
    -- SCHEDULER
    --=========================================================
    local loops = {
        makeLoop("combat",   function() Ctx.Atk.combatTick()      end, 0.05, 5),
        makeLoop("spoofers", function() Ctx.Spoof.tick()          end, 0.10, 5),
        makeLoop("threats",  function() Ctx.Detect.updateThreats() end, 0.10, 5),
        makeLoop("crow",     crowCycle,                                2.0,  3),
        makeLoop("quest",    function() Quest.doCycle()           end, 5.0,  2),
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
    -- PHASE 6: DEFERRED HEAVY WORK (async)
    --========================================================
    phase(6, "deferred")
    St.bootPhase = "deferred"

    -- Boot sequence done — mark ready BEFORE deferred work starts
    -- so combat tick can run while heavy work continues in background
    St.boot = true
    print("[Dingus] ready · RightShift to toggle UI")

    -- Notify
    pcall(function() U.notify("Dingus-Slayer", "loaded", 4) end)

    -- Now fire off the deferred work in background
    task.spawn(function()
        task.wait(0.5)

        -- Warm workspace walk (caches nothing but primes spatial hash)
        local ok1, err1 = pcall(function() Ctx.Opt.warmWorkspace() end)
        if not ok1 then
            print("[Dingus][deferred] warm failed: " .. tostring(err1))
        end

        task.wait(0.3)

        -- Lighting strip (small impact, non-blocking)
        pcall(function() Ctx.Opt.stripLighting() end)

        task.wait(0.3)

        -- Initial quest scan
        pcall(function() Quest.doCycle() end)

        task.wait(0.3)

        -- Initial boss scan (populates St.ens so UI shows something)
        local ok2, bosses = pcall(function() return Ctx.Detect.scanBosses() end)
        if ok2 and bosses then
            print(string.format("[Dingus] initial scan: %d bosses", #bosses))
            for i = 1, math.min(#bosses, 5) do
                print(string.format("  · %s @%.0f", bosses[i].ch.Name, bosses[i].d))
            end
        end

        print("[Dingus] boot complete")
    end)

    --========================================================
    -- MAIN SCHEDULER LOOP (single dispatcher, per-loop error tracking)
    --========================================================
    task.spawn(function()
        local tick = 0

        while St.run do
            if St.boot then
                local now = U.clock()
                tick = tick + 1

                -- Dispatch each loop based on its own interval
                for i = 1, #loops do
                    local L = loops[i]
                    if not L.disabled and now - L.lastRun >= L.interval then
                        L.lastRun = now
                        L.totalRuns = L.totalRuns + 1
                        local ok, err = pcall(L.tick)
                        if not ok then
                            L.errors = L.errors + 1
                            if L.errors <= 3 then
                                print(string.format("[Dingus][loop %s] error %d: %s",
                                    L.name, L.errors, tostring(err)))
                            end
                            if L.errors >= L.maxErrors then
                                L.disabled = true
                                print(string.format("[Dingus][loop %s] DISABLED after %d errors",
                                    L.name, L.maxErrors))
                            end
                        else
                            -- Success resets the error streak
                            if L.errors > 0 then
                                L.errors = 0
                            end
                        end
                    end
                end

                -- FPS tracker inline (cheap)
                -- Respawn deferred to signal handler below
            end
            task.wait(0.03)
        end
    end)

    --========================================================
    -- FPS TRACKER
    --========================================================
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

    --========================================================
    -- RESPAWN HANDLER
    --========================================================
    pcall(function()
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            -- Reset target lock
            St.tgt = nil
            St.ens = {}
            St.lScn = 0
            St.mxH = 0
            St.uGs = false
            St.lHp = 0
            St.lHpT = 0
            St.lDmg = 0

            -- Scrub movers again (game may have added new ones)
            scrubMovers()

            -- Re-enable any disabled loops
            for i = 1, #loops do
                loops[i].errors = 0
                loops[i].disabled = false
            end

            print("[Dingus] respawned · loops reset")
        end)
    end)

    --========================================================
    -- UI TOGGLE KEY
    --========================================================
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

    --========================================================
    -- UNLOAD HANDLER
    --========================================================
    Ctx.Unload = function()
        print("[Dingus] unloading...")
        St.run = false
        St.boot = false

        -- Save config
        pcall(function() Cfg.save() end)

        -- Destroy hover
        if St.hvB then
            pcall(function() St.hvB:Destroy() end)
            St.hvB = nil
        end

        -- Destroy GUI
        if Ctx.Gui and Ctx.Gui.gui then
            pcall(function() Ctx.Gui.gui:Destroy() end)
        end

        -- Reset character state
        local h = U.hum()
        if h then
            h.WalkSpeed = 16
            h.PlatformStand = false
        end

        print("[Dingus] unloaded")
    end

    print("[Dingus] systems phase complete")
    return true
end

return M
