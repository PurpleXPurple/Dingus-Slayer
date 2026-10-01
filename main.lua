--[[
    Dingus-Slayer · main.lua
    One loop for everything. Auto-quest reads BossHunts, picks available, walks to boss.
]]--

local M = {}

function M.boot(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St

    --============================================================
    -- STATE
    --============================================================
    St.run = true
    St.cbt = false
    St.skl = true
    St.eqp = true
    St.rtr = true
    St.gsp = true
    St.crw = true
    St.stunPun = true
    St.hvr = false  -- NO HOVER by default now

    St.cbtS = "IDLE"
    St.inp = 0
    St.mxH = 0
    St.lScn = 0
    St.lTht = 0
    St.lSpf = 0
    St.lEqp = 0
    St.lAtk = 0
    St.lSkl = 0
    St.lBrt = 0
    St.lDmg = 0
    St.lHp = 0
    St.lHpT = 0
    St.lCkC = 0

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
    St.uGt = 0
    St.uST = 0
    St.uThC = 0

    St.ens = {}
    St.ths = {}
    St.zn = 0
    St.imm = 0
    St.tgt = nil
    St.hvB = nil
    St.fs = {}
    St.fps = 60
    St.aiI = Cfg.AtkInterval
    St.rHt = {}
    St.skCd = { 0, 0, 0, 0, 0 }
    St.Spf = { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }
    St.boot = false
    St.cPrch = false
    St.questTarget = nil
    St.playerLevel = 0

    --============================================================
    -- SUBSYSTEM INIT
    --============================================================
    local subsys = {
        { name = "detect",     fn = function() Ctx.Detect.init(Ctx) end },
        { name = "scanners",   fn = function() Ctx.Scan.init(Ctx) end },
        { name = "spoofers",   fn = function() Ctx.Spoof.init(Ctx) end },
        { name = "attack",     fn = function() Ctx.Atk.init(Ctx) end },
        { name = "optimizers", fn = function() Ctx.Opt.init(Ctx) end },
        { name = "gui",        fn = function() Ctx.Gui.init(Ctx) end },
    }
    for i = 1, #subsys do
        local ok, err = pcall(subsys[i].fn)
        if not ok then
            print("[Dingus] " .. subsys[i].name .. " init failed: " .. tostring(err))
        end
    end

    --============================================================
    -- AUTO-QUEST
    --============================================================
    local Quest = {
        lastCheck = 0,
        currentTarget = nil,
    }
    Ctx.Quest = Quest

    function Quest.readLevel()
        -- Try multiple sources for player level
        local hf = workspace:FindFirstChild("Humanoids")
        local me = hf and hf:FindFirstChild(U.Lp.Name)
        if me then
            local prog = me:FindFirstChild("Progression")
            local lvl = prog and prog:FindFirstChild("Level")
            if lvl and lvl:IsA("NumberValue") then return lvl.Value end
        end
        -- Fallback: try Player_Service
        local rs = game:GetService("ReplicatedStorage")
        local ps = rs:FindFirstChild("Player_Service")
        local data = ps and ps:FindFirstChild("Data")
        local me2 = data and data:FindFirstChild(U.Lp.Name)
        local slots = me2 and me2:FindFirstChild("slots")
        local s1 = slots and slots:FindFirstChild("Slot1")
        local prog2 = s1 and s1:FindFirstChild("Progression")
        local lvl2 = prog2 and prog2:FindFirstChild("Level")
        if lvl2 and (lvl2:IsA("NumberValue") or lvl2:IsA("IntValue")) then
            return lvl2.Value
        end
        return 0
    end

    function Quest.findBossHunts()
        local rs = game:GetService("ReplicatedStorage")
        local hunts = rs:FindFirstChild("BossHunts")
        if not hunts then return {} end
        local list = {}
        for _, cfg in ipairs(hunts:GetChildren()) do
            if cfg:IsA("Configuration") then
                local name = cfg.Name
                local side = cfg:FindFirstChild("Side")
                local quest = cfg:FindFirstChild("Quest")
                table.insert(list, {
                    id = name,
                    side = side and tostring(side.Value) or "?",
                    quest = quest and tostring(quest.Value) or "?",
                })
            end
        end
        return list
    end

    function Quest.pickQuest(level, hunts)
        -- Prefer higher ID hunts (later = higher level in this game)
        table.sort(hunts, function(a, b)
            local ia = tonumber(a.id) or 0
            local ib = tonumber(b.id) or 0
            return ia > ib
        end)
        for i = 1, #hunts do
            local h = hunts[i]
            local id = tonumber(h.id) or 0
            -- Only pick quests we're roughly qualified for
            if id <= math.max(1, math.floor(level / 20)) then
                return h
            end
        end
        return hunts[1]
    end

    function Quest.doCycle()
        local now = U.clock()
        if now - Quest.lastCheck < 5 then return end
        Quest.lastCheck = now

        St.playerLevel = Quest.readLevel()
        local hunts = Quest.findBossHunts()
        if #hunts == 0 then
            print("[Dingus][Quest] no BossHunts configs found")
            return
        end
        local pick = Quest.pickQuest(St.playerLevel, hunts)
        if pick then
            print(string.format("[Dingus][Quest] available: #%s %s (side=%s)",
                pick.id, pick.quest, pick.side))
            -- Extract target name from "Eliminate X"
            local target = pick.quest:match("Eliminate%s+(.+)") or pick.quest
            St.questTarget = target
        end
    end

    --============================================================
    -- CROW (simplified)
    --============================================================
    local Crow = { last = 0, accepts = 0 }
    Ctx.Crow = Crow

    local function crowCycle()
        if not St.crw then return end
        local now = U.clock()
        if now - Crow.last < 2.0 then return end
        Crow.last = now

        local tool = Ctx.Scan.findCrowTool()
        if not tool then return end
        St.crT = tool

        local c = U.Lp.Character
        if not c then return end
        local equipped = false
        for _, x in ipairs(c:GetChildren()) do
            if x:IsA("Tool") and Ctx.Lists.isCrow(x.Name) then equipped = true; break end
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
        St.cPrch = (model ~= nil)

        if not St.cPrch then return end

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
            print("[Dingus][Crow] quest accepted #" .. Crow.accepts)
            task.wait(0.8)
        end
    end

    --============================================================
    -- BOOT
    --============================================================
    task.spawn(function()
        task.wait(0.3)
        St.inp = U.detectInput()
        print("[Dingus] input method " .. St.inp)

        task.wait(0.2)
        local b = Ctx.Detect.scanBosses()
        print("[Dingus] " .. #b .. " bosses in workspace")

        task.wait(0.1)
        St.playerLevel = Quest.readLevel()
        print("[Dingus] player level " .. St.playerLevel)

        -- Quest scan
        local hunts = Quest.findBossHunts()
        print("[Dingus] " .. #hunts .. " quest configs")

        task.wait(0.1)
        pcall(function() Ctx.Opt.stripLighting() end)

        St.boot = true
        print("[Dingus] ready · press RightShift for UI")

        pcall(function()
            U.notify("Dingus-Slayer", "loaded", 5)
        end)
    end)

    --============================================================
    -- MAIN LOOP (single)
    --============================================================
    task.spawn(function()
        local tickCount = 0
        local lastFpsUpdate = 0

        while St.run do
            if St.boot then
                tickCount = tickCount + 1

                -- Every tick (20Hz): combat
                pcall(Ctx.Atk.combatTick)

                -- Every 10 ticks (2Hz): threats
                if tickCount % 10 == 0 then
                    pcall(Ctx.Detect.updateThreats)
                end

                -- Every 5 ticks (4Hz): spoofers
                if tickCount % 5 == 0 then
                    pcall(Ctx.Spoof.tick)
                end

                -- Every 40 ticks (0.5Hz): crow + quest
                if tickCount % 40 == 0 then
                    pcall(crowCycle)
                end

                if tickCount % 60 == 0 then
                    pcall(Quest.doCycle)
                end

                -- Every 200 ticks: GC
                if tickCount % 200 == 0 then
                    pcall(Ctx.Opt.gc)
                end

                tickCount = tickCount % 10000
            end
            task.wait(0.05)
        end
    end)

    -- FPS tracker (independent, cheap)
    game:GetService("RunService").RenderStepped:Connect(function(dt)
        if dt > 0 and dt < 1 then
            table.insert(St.fs, dt)
            if #St.fs > 30 then table.remove(St.fs, 1) end
            local sum = 0
            for i = 1, #St.fs do sum = sum + St.fs[i] end
            if sum > 0 then St.fps = #St.fs / sum end
        end
    end)

    -- Respawn
    U.Lp.CharacterAdded:Connect(function()
        task.wait(2)
        St.tgt = nil
        St.ens = {}
        St.lScn = 0
        St.mxH = 0
        St.uGs = false
        if St.hvB then pcall(function() St.hvB:Destroy() end); St.hvB = nil end
        print("[Dingus] respawned")
    end)

    -- UI toggle key
    game:GetService("UserInputService").InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            if Ctx.Gui and Ctx.Gui.win then
                Ctx.Gui.win.Visible = not Ctx.Gui.win.Visible
            end
        end
    end)

    -- Unload
    Ctx.Unload = function()
        St.run = false
        if St.hvB then pcall(function() St.hvB:Destroy() end) end
        if Ctx.Gui and Ctx.Gui.gui then
            pcall(function() Ctx.Gui.gui:Destroy() end)
        end
    end
end

return M
