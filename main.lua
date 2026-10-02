-- Dingus-Slayer · main.lua v36

local M = {}

function M.boot(C)
    if type(C) ~= "table" then warn("[Dingus][main] no Ctx"); return end
    _G.Ctx = C

    local U, F = C.Util, C.Cfg
    if not U or not F then warn("[Dingus][main] Util/Cfg missing"); return end

    local S = C.St or {}
    C.St = S
    _G.St = S

    -- P1 · state
    S.run = true
    S.boot = false
    local D = F.DefaultToggles or {}
    S.cbt = D.combat or false
    S.skl = D.skl ~= false
    S.eqp = D.eqp ~= false
    S.rtr = D.rtr ~= false
    S.gsp = D.gsp or false
    S.crw = D.crw ~= false
    S.stunPun = D.stunPun ~= false
    S.cbtS = "IDLE"
    S.rHt = {}
    S.aiI = F.AtkInterval or 0.38
    S.eq = "none"
    S.kll, S.bKll, S.aAt, S.aHi, S.aMs = 0, 0, 0, 0, 0
    S.ens, S.ths, S.zn, S.imm = {}, {}, 0, 0
    S.tgt, S.tgtKind = nil, nil
    S.Spf = { hpC=0, bkC=0, spdC=0, kbC=0, jmpC=0 }
    S.fs, S.fps = {}, 60

    print(string.format("[Dingus][main] state init · %s · %s", U.Platform, U.Executor))

    -- P2 · scrub movers
    pcall(function()
        local R = U.hrp(); if not R then return end
        for _, c in ipairs(R:GetChildren()) do
            if c:IsA("BodyPosition") or c:IsA("BodyVelocity") or c:IsA("BodyGyro")
                or c:IsA("BodyForce") or c:IsA("LinearVelocity")
                or c:IsA("AlignOrientation") or c:IsA("AlignPosition") then
                pcall(c.Destroy, c)
            end
        end
        local H = U.hum()
        if H then H.PlatformStand = false; H.WalkSpeed = 16; H.AutoRotate = true end
    end)

    -- P3 · config
    pcall(function()
        if F.setUtils then F.setUtils(U) end
        if F.exists and F.exists("default") then
            local ok, msg = F.load("default")
            if ok then print("[Dingus][Config] " .. tostring(msg)) end
        else
            if not U.Caps.file then
                print("[Dingus][Config] in-memory only (no file API)")
            end
        end
    end)

    -- P4 · subsystems
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
        local p = order[i]
        local mod = C[p[2]]
        if mod and type(mod.init) == "function" then
            local good, err = pcall(mod.init, C)
            if good then
                ok = ok + 1
                print("[Dingus]   + " .. p[1])
            else
                print("[Dingus]   x " .. p[1] .. ": " .. tostring(err))
            end
        else
            print("[Dingus]   x " .. p[1] .. " missing")
        end
        task.wait(0.02)
    end
    print(string.format("[Dingus] %d/%d subsystems ok", ok, #order))

    for _, k in ipairs({"Cfg","Detect","Scan","Hotbar","Spoof","Chest","Quest","Atk","Opt","Gui"}) do
        if C[k] then pcall(function() _G[k] = C[k] end) end
    end

    -- P5 · scheduler
    local loops = {
        { name="combat",   fn=function() if C.Atk and C.Atk.combatTick then pcall(C.Atk.combatTick) end end,   interval=0.05, lastRun=0 },
        { name="spoofers", fn=function() if C.Spoof and C.Spoof.tick then pcall(C.Spoof.tick) end end,          interval=0.10, lastRun=0 },
        { name="threats",  fn=function() if C.Detect and C.Detect.updateThreats then pcall(C.Detect.updateThreats) end end, interval=0.10, lastRun=0 },
        { name="quest",    fn=function() if C.Quest and C.Quest.cycle then pcall(C.Quest.cycle) end end,        interval=0.50, lastRun=0 },
        { name="chest",    fn=function() if C.Chest and C.Chest.collectPassive then pcall(C.Chest.collectPassive) end end, interval=3.0, lastRun=0 },
        { name="config",   fn=function() if F.tickAutoSave then pcall(F.tickAutoSave) end end,                 interval=F.AutoSaveT or 30, lastRun=0 },
        { name="gc",       fn=function() pcall(function() collectgarbage("collect") end) end,                  interval=60, lastRun=0 },
    }
    C.Loops = loops

    S.boot = true
    print("[Dingus] ready · RightShift to toggle UI")

    task.spawn(function()
        while S.run do
            if S.boot then
                local t = U.clock()
                for i = 1, #loops do
                    local L = loops[i]
                    if t - L.lastRun >= L.interval then
                        L.lastRun = t
                        pcall(L.fn)
                    end
                end
            end
            task.wait(0.05)
        end
    end)

    -- FPS sampler
    pcall(function()
        U.Run.RenderStepped:Connect(function(dt)
            if dt > 0 and dt < 1 then
                local fs = S.fs
                fs[#fs+1] = dt
                if #fs > 30 then table.remove(fs, 1) end
                local sum = 0
                for i = 1, #fs do sum = sum + fs[i] end
                if sum > 0 then S.fps = #fs / sum end
            end
        end)
    end)

    -- Respawn
    pcall(function()
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            if C.Chest and C.Chest.resetCooldowns then pcall(C.Chest.resetCooldowns) end
            S.tgt = nil
            S.ens = {}
            S.lScn = 0
            S.Spf = { hpC=0, bkC=0, spdC=0, kbC=0, jmpC=0 }
            print("[Dingus] respawned")
        end)
    end)

    -- Toggle key
    pcall(function()
        U.UIS.InputBegan:Connect(function(inp, gp)
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

    C.Unload = function()
        print("[Dingus] unloading...")
        S.run, S.boot = false, false
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
