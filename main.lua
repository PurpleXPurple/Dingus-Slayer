--[[
    Dingus-Slayer · main.lua
    State bootstrap, subsystem wiring, main loops, respawn handling.
    All loops are pcall-wrapped with per-loop error tracking and auto-disable on repeated failure.
]]--

local M = {}

local MAX_LOOP_ERRORS = 5

function M.boot(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St

    --=========================================================
    -- STATE INITIALIZATION (every field referenced anywhere)
    --=========================================================
    St.run = true

    -- Feature flags
    St.cbt = false
    St.hvr = true
    St.eqp = true
    St.rtr = true
    St.skl = true
    St.gsp = true
    St.crw = true
    St.stunPun = true

    -- Status
    St.cbtS = "IDLE"
    St.boot = false
    St.inp = 0

    -- Health observation
    St.mxH = 0
    St.lHp = 0
    St.lHpT = 0
    St.lDmg = 0

    -- Scanning timestamps
    St.lScn = 0
    St.lTht = 0

    -- Spoofer timestamps
    St.lSpf = 0

    -- Attack timestamps and counters
    St.lEqp = 0
    St.lAtk = 0
    St.lSkl = 0
    St.lHvr = 0
    St.lFac = 0
    St.lBrt = 0
    St.lTl = false
    St.aiI = Cfg.AtkIntBase
    St.rHt = {}
    St.skCd = { 0, 0, 0, 0, 0 }

    -- Counters
    St.kll = 0
    St.bKll = 0
    St.aAt = 0
    St.aHi = 0
    St.aMs = 0
    St.skC = 0
    St.rtrC = 0
    St.cQs = 0
    St.swp = 0

    -- Underground state
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

    -- FPS tracking
    St.fs = {}
    St.fps = 60

    -- Crow state
    St.crT = nil
    St.crM = nil
    St.cPrch = false

    -- Spoofer counters (referenced by gui.lua)
    St.Spf = { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }

    --=========================================================
    -- LOG FUNCTION
    --=========================================================
    local logBuf = {}
    local function Log(cat, msg)
        local e = { t = U.date(), c = cat, m = tostring(msg) }
        table.insert(logBuf, e)
        if #logBuf > 500 then table.remove(logBuf, 1) end
        print(string.format("[%s][%s] %s", e.t, cat, e.m))
        if Ctx.Gui and Ctx.Gui.addLogRow then
            pcall(Ctx.Gui.addLogRow, e)
        end
    end
    Ctx.Log = Log

    --=========================================================
    -- SUBSYSTEM INIT — each in its own pcall
    --=========================================================
    local subsys = {
        { name = "detect",   fn = function() Ctx.Detect.init(Ctx) end },
        { name = "scanners", fn = function() Ctx.Scan.init(Ctx)   end },
        { name = "spoofers", fn = function() Ctx.Spoof.init(Ctx)  end },
        { name = "attack",   fn = function() Ctx.Atk.init(Ctx)    end },
        { name = "optimizers", fn = function() Ctx.Opt.init(Ctx)  end },
        { name = "gui",      fn = function() Ctx.Gui.init(Ctx)    end },
    }

    for i = 1, #subsys do
        local s = subsys[i]
        local ok, err = pcall(s.fn)
        if not ok then
            Log("INIT", s.name .. " failed: " .. tostring(err))
        else
            Log("INIT", s.name .. " ok")
        end
        task.wait(0.05)
    end

    --=========================================================
    -- CROW SUBSYSTEM
    --=========================================================
    local Crow = {
        lastCheck = 0,
        perched = false,
        menuOpen = false,
        accepts = 0,
        errors = 0,
    }
    Ctx.Crow = Crow

    local function crowCycle()
        if not St.crw then return end
        local now = U.clock()
        if now - Crow.lastCheck < Cfg.CrowCheckT then return end
        Crow.lastCheck = now

        local tool = Ctx.Scan.findCrowTool()
        if not tool then
            if Ctx.Gui and Ctx.Gui.CrowLabel then
                pcall(function()
                    Ctx.Gui.CrowLabel.Text = "  status: no crow in inventory"
                end)
            end
            return
        end

        local c = U.Lp.Character
        if not c then return end
        local equipped = false
        for _, x in ipairs(c:GetChildren()) do
            if x:IsA("Tool") and U.isCrowName(x.Name) then
                equipped = true
                break
            end
        end

        if not equipped and tool:IsA("Tool") then
            local h = U.hum()
            if h then
                pcall(function() h:EquipTool(tool) end)
                Log("CROW", "equipped " .. tool.Name)
                task.wait(0.5)
            end
        end

        local model, how = Ctx.Scan.findCrowModel()
        if not model then
            U.m1()
            Log("CROW", "summon click")
            task.wait(1.0)
            model, how = Ctx.Scan.findCrowModel()
        end

        Crow.perched = (how == "attachment")
        if not Crow.perched then
            if Ctx.Gui and Ctx.Gui.CrowLabel then
                pcall(function()
                    Ctx.Gui.CrowLabel.Text = "  status: summoned, waiting perch"
                end)
            end
            return
        end

        local caw = Ctx.Scan.findCawSound()
        if caw then
            Log("CROW", "caw detected — menu opening")
            Crow.menuOpen = true
        end

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
            Log("CROW", "accepted #" .. Crow.accepts)
            task.wait(0.8)
        else
            if Ctx.Gui and Ctx.Gui.CrowLabel then
                pcall(function()
                    Ctx.Gui.CrowLabel.Text = "  status: perched, no menu yet"
                end)
            end
        end
    end
    Crow.doCycle = crowCycle

    --=========================================================
    -- BOOT SEQUENCE (runs async)
    --=========================================================
    task.spawn(function()
        task.wait(0.5)

        Log("BOOT", "detecting input method")
        local ok1, method = pcall(U.detectInput)
        if not ok1 or not method then
            Log("BOOT", "input detection threw: " .. tostring(method))
            St.inp = 0
        else
            St.inp = method
            Log("BOOT", "input method " .. method .. (method == 0 and " (none worked)" or ""))
        end

        task.wait(0.3)
        local ok2, bosses = pcall(Ctx.Detect.scanBosses)
        if ok2 and bosses then
            Log("BOOT", "found " .. #bosses .. " bosses")
        else
            Log("BOOT", "boss scan failed")
        end

        task.wait(0.2)
        local ok3, crow = pcall(Ctx.Scan.findCrowTool)
        if ok3 and crow then
            Log("BOOT", "crow tool: " .. crow.Name .. " (" .. crow.ClassName .. ")")
        else
            Log("BOOT", "crow tool not found")
        end

        task.wait(0.1)
        pcall(function() Ctx.Opt.warmWorkspace() end)
        pcall(function() Ctx.Opt.stripLighting() end)

        St.boot = true
        Log("BOOT", "ready")
        pcall(U.notify, "Dingus-Slayer",
            "loaded · " .. tostring(identifyexecutor and identifyexecutor() or "?"), 5)
    end)

    --=========================================================
    -- SAFE LOOP RUNNER — disables loop after N consecutive errors
    --=========================================================
    local function spawnLoop(name, tickFn, interval)
        task.spawn(function()
            local errCount = 0
            local disabled = false
            while St.run do
                if disabled then
                    task.wait(2)
                else
                    if St.boot then
                        local ok, err = pcall(tickFn)
                        if not ok then
                            errCount = errCount + 1
                            if errCount <= 3 then
                                Log("LOOP", name .. " err (" .. errCount .. "): " .. tostring(err))
                            end
                            if errCount >= MAX_LOOP_ERRORS then
                                Log("LOOP", name .. " disabled after " .. MAX_LOOP_ERRORS .. " errors")
                                disabled = true
                            end
                        else
                            errCount = 0
                        end
                    end
                    task.wait(interval)
                end
            end
        end)
    end

    spawnLoop("combat",   function() Ctx.Atk.combatTick()      end, 0.05)
    spawnLoop("spoofers", function() Ctx.Spoof.tick()          end, 0.1)
    spawnLoop("threats",  function() Ctx.Detect.updateThreats() end, 0.1)
    spawnLoop("crow",     crowCycle,                                1.0)
    spawnLoop("gc",       function() Ctx.Opt.gc()              end, 5)

    --=========================================================
    -- UI REFRESH LOOP
    --=========================================================
    task.spawn(function()
        while St.run do
            if St.boot and Ctx.Gui and Ctx.Gui.StatusLabel then
                local h = U.hum()
                local hp = h and string.format("%d/%d", math.floor(h.Health), math.floor(h.MaxHealth)) or "?"
                local hitRate = St.aAt > 0 and (St.aHi / St.aAt * 100) or 0
                pcall(function()
                    Ctx.Gui.StatusLabel.Text = string.format(
                        "  state: %s · hp: %s\n" ..
                        "  target: %s\n" ..
                        "  atk: %d/%d (%.0f%%) int %.2f\n" ..
                        "  kills: %d · retreats: %d · crow: %d\n" ..
                        "  input: %d · ug: %s · fps: %.0f",
                        St.cbtS, hp,
                        St.tgt and St.tgt.ch.Name or "none",
                        St.aHi, St.aAt, hitRate, St.aiI,
                        St.bKll, St.rtrC, St.cQs,
                        St.inp, St.uGs and "yes" or "no", St.fps or 60)
                end)
                if Ctx.Gui.SpoofLabel then
                    pcall(function()
                        Ctx.Gui.SpoofLabel.Text = string.format(
                            "  hpC: %d | bkC: %d | spdC: %d | kbC: %d | jmpC: %d",
                            St.Spf.hpC, St.Spf.bkC, St.Spf.spdC, St.Spf.kbC, St.Spf.jmpC)
                    end)
                end
                if Ctx.Gui.CrowLabel and not St.crT then
                    pcall(function()
                        Ctx.Gui.CrowLabel.Text = "  status: idle · no crow"
                    end)
                end
            end
            task.wait(0.4)
        end
    end)

    --=========================================================
    -- FPS TRACKER
    --=========================================================
    pcall(function()
        game:GetService("RunService").RenderStepped:Connect(function(dt)
            if dt > 0 and dt < 1 then
                if not St.fs then St.fs = {} end
                table.insert(St.fs, dt)
                if #St.fs > 60 then table.remove(St.fs, 1) end
                local sum = 0
                for i = 1, #St.fs do sum = sum + St.fs[i] end
                if sum > 0 then St.fps = #St.fs / sum end
            end
        end)
    end)

    --=========================================================
    -- RESPAWN HANDLER
    --=========================================================
    pcall(function()
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            St.tgt = nil
            St.ens = {}
            St.lScn = 0
            St.lHp = 0
            St.lHpT = 0
            St.mxH = 0
            St.uGs = false
            St.cPrch = false
            if St.hvB then
                pcall(function() St.hvB:Destroy() end)
                St.hvB = nil
            end
            Log("INFO", "respawned")
        end)
    end)

    --=========================================================
    -- UNLOAD HANDLER (for safe exit)
    --=========================================================
    Ctx.Unload = function()
        St.run = false
        if St.hvB then pcall(function() St.hvB:Destroy() end) end
        if Ctx.Gui and Ctx.Gui.gui then pcall(function() Ctx.Gui.gui:Destroy() end) end
        if Ctx.Gui and Ctx.Gui.miniGui then pcall(function() Ctx.Gui.miniGui:Destroy() end) end
        Log("INFO", "unloaded")
    end

    Log("BOOT", "main.lua initialized")
end

return M
