--[[
    Dingus-Slayer · main.lua v26
    Adapted to refactored module set (loader v26, config v2, gui v28,
    scanners v3, spoofers v3, fly v2, attack v2, lists v2, detect v2,
    utils v2, optimizers v2).

    Changes vs v25:
      - fly added to subsys (was omitted — C1 audit)
      - crow subsystem rewritten: menu is read-only (Cancel button only)
      - boss overlay reader added (top-right tracker)
      - boss HP bar reader added (top-center, in-combat only)
      - quest parser updated for "Defeat <name>" format
      - Cfg.save / Cfg.load use slot API
      - all state defaults widened to cover new module contracts
      - deprecation warnings for modules removed in prior refactors
      - unload runs through new cleanup contract
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

function M.boot(Ctx)
    local U     = Ctx.Util
    local Cfg   = Ctx.Cfg
    local St    = Ctx.St
    local Lists = Ctx.Lists

    --================================================================
    -- PHASE 1 · STATE
    --================================================================
    phase(1, "state")
    St.run = true
    St.boot = false
    St.bootPhase = "state"

    -- Toggle defaults
    local DT = Cfg.DefaultToggles or {}
    St.cbt     = DT.combat  or false
    St.skl     = DT.skl     ~= false
    St.eqp     = DT.eqp     ~= false
    St.rtr     = DT.rtr     ~= false
    St.gsp     = DT.gsp     or false      -- audit recommendation: off
    St.crw     = DT.crw     ~= false
    St.stunPun = DT.stunPun ~= false

    -- Combat FSM
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

    -- Fly
    St.FlyActive = false
    St.flyFailLogged = false

    -- Retreat
    St.uGs = false; St.uC = 0; St.uGt = 0; St.uST = 0; St.uThC = 0

    -- Detection caches (written by detect.lua)
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

    -- Spoofers (v3 uses these; legacy counters kept at 0)
    St.Spf = { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }

    -- Oversight
    St.fs = {}; St.fps = 60
    St.loadErrors = {}
    St.hoverActive = false       -- dead state, kept for GUI reads

    -- Boot-config defaults
    Cfg.QuestCycleT = Cfg.QuestCycleT or 5.0
    Cfg.CrowCheckT  = Cfg.CrowCheckT  or 1.5
    Cfg.AutoSaveT   = Cfg.AutoSaveT   or 30

    --================================================================
    -- PHASE 2 · SCRUB MOVERS
    --================================================================
    phase(2, "scrub")

    local function scrubMovers()
        local r = U.hrp(); if not r then return 0 end
        local n = 0
        for _, c in ipairs(r:GetChildren()) do
            if c:IsA("BodyPosition") or c:IsA("BodyVelocity")
                or c:IsA("BodyGyro") or c:IsA("BodyForce")
                or c:IsA("LinearVelocity") or c:IsA("AlignOrientation")
                or c:IsA("AlignPosition") then
                c:Destroy(); n = n + 1
            end
        end
        local h = U.hum()
        if h then
            h.PlatformStand = false
            h.WalkSpeed = 16
            h.AutoRotate = true
        end
        return n
    end
    local sc = scrubMovers()
    if sc > 0 then print("[Dingus] scrubbed " .. sc .. " movers") end

    --================================================================
    -- PHASE 3 · CONFIG
    --================================================================
    phase(3, "config")
    if Cfg.setUtils then Cfg.setUtils(U) end
    if Cfg.exists and Cfg.exists("default") then
        local okL, msgL = Cfg.load("default")
        print("[Dingus][Config] " .. tostring(msgL))
        if okL then
            -- Reapply toggles from loaded config
            St.skl     = DT.skl     ~= false
            St.eqp     = DT.eqp     ~= false
            St.rtr     = DT.rtr     ~= false
            St.gsp     = DT.gsp     or false
            St.crw     = DT.crw     ~= false
            St.stunPun = DT.stunPun ~= false
        end
    end

    --================================================================
    -- PHASE 4 · SUBSYSTEMS
    --================================================================
    phase(4, "subsystems")
    local subsys = {
        { name = "detect",     mod = "Detect" },
        { name = "scanners",   mod = "Scan"   },
        { name = "spoofers",   mod = "Spoof"  },
        { name = "fly",        mod = "Fly"    },  -- C1 fix
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

    --================================================================
    -- PHASE 5 · SYSTEMS
    --================================================================
    phase(5, "systems")

    --============================================================
    -- QUEST SUBSYSTEM
    --============================================================
    local Quest = { lastCheck = 0, hunts = {}, level = 0 }
    Ctx.Quest = Quest

    function Quest.readLevel()
        -- Path 1: workspace.Humanoids.<me>.Progression.Level
        local hf = workspace:FindFirstChild("Humanoids")
        local me = hf and hf:FindFirstChild(U.Lp.Name)
        if me then
            local prog = me:FindFirstChild("Progression")
            local lvl = prog and prog:FindFirstChild("Level")
            if lvl and (lvl:IsA("NumberValue") or lvl:IsA("IntValue")) then
                return lvl.Value
            end
        end
        -- Path 2: ReplicatedStorage.Player_Service.Data.<me>.slots.Slot1...
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

    --============================================================
    -- CROW SUBSYSTEM
    --============================================================
    -- Menu is read-only (screenshot evidence). Flow:
    --   1. find crow tool → equip
    --   2. trigger menu with M1
    --   3. read quest entries from Kasugai Crow panel
    --   4. click Cancel to close
    --   5. record quest names into St.crQuests
    --
    -- No "Accept" button exists. Do not look for one.
    --============================================================
    local Crow = { last = 0, cycles = 0 }
    Ctx.Crow = Crow

    -- Scrape quest entries from the open menu.
    -- Panel shows rows like: "Defeat Enru | 3,432 | 1,485 | 5:40"
    -- We walk the ComponentsHolder looking for TextLabels whose
    -- Text matches "Defeat <name>" or "Eliminate <name>".
    local function readCrowQuests()
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
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string" then
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
                local okc, kids = pcall(function() return inst:GetChildren() end)
                if okc and kids then
                    for i = 1, #kids do table.insert(stack, kids[i]) end
                end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        return found
    end

    -- Find the Cancel button. Only interactive element in the panel.
    local function findCancelButton()
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
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string" then
                        local low = txt:lower():gsub("^%s+", ""):gsub("%s+$", "")
                        if low == "cancel" or low == "close" then
                            local okV, vis = pcall(function() return inst.Visible end)
                            if okV and vis then return inst end
                        end
                    end
                end
                local okc, kids = pcall(function() return inst:GetChildren() end)
                if okc and kids then
                    for i = 1, #kids do table.insert(stack, kids[i]) end
                end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        return nil
    end

    local function crowCycle()
        if not St.crw then return end
        local now = U.clock()
        if now - Crow.last < Cfg.CrowCheckT then return end
        Crow.last = now
        Crow.cycles = Crow.cycles + 1

        -- Step 1: crow tool present and equipped?
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
            if h then
                pcall(function() h:EquipTool(tool) end)
                task.wait(0.4)
            end
        end

        -- Step 2: trigger menu
        local alreadyOpen = findCancelButton() ~= nil
        if not alreadyOpen then
            U.m1()
            task.wait(0.8)
        end

        -- Step 3: read quests
        local quests = readCrowQuests()
        if #quests > 0 then
            St.crQuests = quests
            St.cPrch = true
            -- If a quest matches our current target interest, keep it
            if not St.questTarget and #quests > 0 then
                St.questTarget = quests[1]
            end
            print(string.format("[Dingus][Crow] %d quests: %s",
                #quests, table.concat(quests, ", ")))
        end

        -- Step 4: close menu (Cancel)
        local cancel = findCancelButton()
        if cancel then
            pcall(function() cancel:Activate() end)
            task.wait(0.3)
        end
    end

    --============================================================
    -- BOSS OVERLAY READER (screenshot evidence)
    -- Top-right overlay lists boss names on map. Read-only.
    -- Populates St.ens as a fallback if detect.scanBosses returns
    -- nothing from the workspace walk.
    --============================================================
    local function readBossOverlay()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return {} end
        -- The overlay lives somewhere in PlayerGui. Walk shallow (depth 4)
        -- looking for a frame with many TextLabels whose text matches
        -- a boss name.
        local hits = {}
        local stack = { { pg, 0 } }
        local iter = 0
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 4 then
                if inst:IsA("TextLabel") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string" and #txt >= 3 and #txt <= 30 then
                        if Lists.isBoss(txt) then
                            hits[#hits+1] = txt
                        end
                    end
                end
                local okc, kids = pcall(function() return inst:GetChildren() end)
                if okc and kids then
                    for i = 1, #kids do
                        table.insert(stack, { kids[i], d + 1 })
                    end
                end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        return hits
    end

    --============================================================
    -- SCHEDULER LOOPS
    --============================================================
    local loops = {
        makeLoop("combat",   function() Ctx.Atk.combatTick()       end, 0.05, 5),
        makeLoop("spoofers", function() Ctx.Spoof.tick()           end, 0.10, 5),
        makeLoop("threats",  function() Ctx.Detect.updateThreats() end, 0.10, 5),
        makeLoop("crow",     crowCycle,                                  2.0,  3),
        makeLoop("quest",    function() Quest.doCycle()            end, 5.0,  2),
        makeLoop("overlay",  function()
            local names = readBossOverlay()
            if #names > 0 then
                -- Feed to detect state as a secondary cache
                St.overlayBosses = names
            end
        end, 3.0, 2),
        makeLoop("config",   function()
            local ok = Cfg.save("default")
            if not ok then error("autosave failed") end
        end, Cfg.AutoSaveT or 30, 2),
        makeLoop("gc",       function()
            pcall(function() collectgarbage("collect") end)
        end, 60, 1),
    }
    Ctx.Loops = loops

    --============================================================
    -- DEFERRED
    --============================================================
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

    --============================================================
    -- MAIN SCHEDULER
    --============================================================
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
            if Ctx.Fly and Ctx.Fly.stop then pcall(Ctx.Fly.stop) end
            St.tgt = nil
            St.ens = {}
            St.lScn = 0
            St.mxH = 0
            St.uGs = false
            St.lHp = 0; St.lHpT = 0; St.lDmg = 0
            St.FlyActive = false
            St.flyFailLogged = false
            scrubMovers()
            for i = 1, #loops do
                loops[i].errors = 0
                loops[i].disabled = false
            end
            print("[Dingus] respawned")
        end)
    end)

    -- RightShift toggle
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
        pcall(function() Cfg.save("default") end)
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
