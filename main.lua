local M = {}

function M.boot(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St

    St.run = true
    St.cbt = false
    St.hvr = true
    St.eqp = true
    St.rtr = true
    St.skl = true
    St.gsp = true
    St.crw = true
    St.stunPun = true
    St.cbtS = "IDLE"
    St.mxH = 0
    St.lScn = 0
    St.lScn = 0
    St.kll = 0
    St.bKll = 0
    St.aAt = 0
    St.aHi = 0
    St.aMs = 0
    St.skC = 0
    St.rtrC = 0
    St.cQs = 0
    St.swp = 0
    St.uGs = false
    St.uC = 0

    local Plr = U.Plr
    local Lp = U.Lp

    -- Init subsystems
    Ctx.Detect.init(Ctx)
    Ctx.Scan.init(Ctx)
    Ctx.Spoof.init(Ctx)
    Ctx.Atk.init(Ctx)
    Ctx.Opt.init(Ctx)

    -- Log function
    local logBuf = {}
    local function Log(cat, msg)
        local e = { t = U.date(), c = cat, m = msg }
        table.insert(logBuf, e)
        print(string.format("[%s][%s] %s", e.t, cat, msg))
        if Ctx.Gui and Ctx.Gui.addLogRow then
            pcall(Ctx.Gui.addLogRow, e)
        end
    end
    Ctx.Log = Log

    -- GUI init
    Ctx.Gui.init(Ctx)

    -- Crow subsystem
    local Crow = {
        lastCheck = 0,
        perched = false,
        menuOpen = false,
        accepts = 0,
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
                pcall(function() Ctx.Gui.CrowLabel.Text = "  status: no crow in inventory" end)
            end
            return
        end

        -- 1. Equip if not already
        local c = Lp.Character
        if not c then return end
        local equipped = false
        for _, x in ipairs(c:GetChildren()) do
            if x:IsA("Tool") and U.isCrowName(x.Name) then equipped = true; break end
        end

        if not equipped and tool:IsA("Tool") then
            local h = U.hum()
            if h then
                pcall(function() h:EquipTool(tool) end)
                Log("CROW", "equipped " .. tool.Name)
                task.wait(0.5)
            end
        end

        -- 2. Summon crow (click to fly)
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
                pcall(function() Ctx.Gui.CrowLabel.Text = "  status: crow summoned, waiting perch" end)
            end
            return
        end

        -- 3. Crow perched — check if caw sound playing (menu just opened)
        local caw = Ctx.Scan.findCawSound()
        if caw then
            Log("CROW", "caw detected — menu open")
            Crow.menuOpen = true
        end

        -- 4. Find and click menu accept
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
            Log("CROW", "quest accepted #" .. Crow.accepts)
            task.wait(0.8)
        else
            if Ctx.Gui and Ctx.Gui.CrowLabel then
                pcall(function() Ctx.Gui.CrowLabel.Text = "  status: perched, no menu" end)
            end
        end
    end

    Crow.doCycle = crowCycle

    -- BOOT
    task.spawn(function()
        task.wait(0.5)
        Log("BOOT", "detecting input method")
        local method = U.detectInput()
        St.inp = method
        Log("BOOT", "input method " .. method)

        task.wait(0.3)
        local bosses = Ctx.Detect.scanBosses()
        Log("BOOT", "found " .. #bosses .. " bosses")

        task.wait(0.2)
        local crow = Ctx.Scan.findCrowTool()
        if crow then
            Log("BOOT", "crow tool: " .. crow.Name .. " (" .. crow.ClassName .. ")")
        else
            Log("BOOT", "crow tool not found in inventory")
        end

        St.boot = true
        Log("BOOT", "ready")

        Ctx.Opt.warmWorkspace()
        Ctx.Opt.stripLighting()

        U.notify("Dingus-Slayer", "loaded · " .. tostring(identifyexecutor and identifyexecutor() or "?"), 5)
    end)

    -- LOOPS
    task.spawn(function()
        while St.run do
            if St.boot then pcall(Ctx.Atk.combatTick) end
            task.wait(0.05)
        end
    end)

    task.spawn(function()
        while St.run do
            if St.boot then pcall(Ctx.Spoof.tick) end
            task.wait(0.1)
        end
    end)

    task.spawn(function()
        while St.run do
            if St.boot then pcall(Ctx.Detect.updateThreats) end
            task.wait(0.1)
        end
    end)

    task.spawn(function()
        while St.run do
            if St.boot then pcall(crowCycle) end
            task.wait(1.0)
        end
    end)

    task.spawn(function()
        while St.run do
            if St.boot then pcall(Ctx.Opt.gc) end
            task.wait(5)
        end
    end)

    -- UI refresh
    task.spawn(function()
        while St.run do
            if St.boot and Ctx.Gui and Ctx.Gui.StatusLabel then
                local h = U.hum()
                local hp = h and string.format("%d/%d", math.floor(h.Health), math.floor(h.MaxHealth)) or "?"
                local hitRate = St.aAt > 0 and (St.aHi / St.aAt * 100) or 0
                pcall(function()
                    Ctx.Gui.StatusLabel.Text = string.format(
                        "  state: %s · hp: %s\n  target: %s\n  atk: %d/%d (%.0f%%) int %.2f\n  kills: %d · retreats: %d · crow: %d\n  input: %d · ug: %s · fps: %.0f",
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
            end
            task.wait(0.4)
        end
    end)

    -- FPS tracker
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

    -- Respawn handler
    Lp.CharacterAdded:Connect(function()
        task.wait(2)
        St.tgt = nil
        St.ens = {}
        St.lScn = 0
        St.lHp = 0
        St.mxH = 0
        St.uGs = false
        if St.hvB then pcall(function() St.hvB:Destroy() end); St.hvB = nil end
        Log("INFO", "respawned")
    end)
end

return M
