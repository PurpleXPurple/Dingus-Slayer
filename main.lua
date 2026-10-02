-- Dingus-Slayer · main.lua v37
-- Synerox-style Heartbeat scheduler + adaptive fairness.
-- Tunes itself to whatever frame rate the device can sustain.

local M = {}

--================================================================
-- LOOP TABLE (declared once, mutated per boot)
--================================================================
-- id       unique name
-- interval target seconds between runs (soft)
-- weight   relative CPU cost 0..1 (for budget accounting)
-- priority 1=critical, 2=important, 3=normal, 4=deferrable
-- fn       the function to call

local function buildLoops(C, F)
    return {
        { id = "combat",   interval = 0.05, weight = 0.35, priority = 1,
          fn = function() if C.Atk and C.Atk.combatTick then pcall(C.Atk.combatTick) end end },
        { id = "threats",  interval = 0.10, weight = 0.15, priority = 1,
          fn = function() if C.Detect and C.Detect.updateThreats then pcall(C.Detect.updateThreats) end end },
        { id = "fly",      interval = 0.05, weight = 0.10, priority = 1,
          fn = function() if C.Fly and C.Fly.tick then pcall(C.Fly.tick) end end },
        { id = "spoofers", interval = 0.10, weight = 0.10, priority = 2,
          fn = function() if C.Spoof and C.Spoof.tick then pcall(C.Spoof.tick) end end },
        { id = "quest",    interval = 0.50, weight = 0.15, priority = 3,
          fn = function() if C.Quest and C.Quest.cycle then pcall(C.Quest.cycle) end end },
        { id = "chest",    interval = 1.50, weight = 0.30, priority = 3,
          fn = function() if C.Chest and C.Chest.collectPassive then pcall(C.Chest.collectPassive) end end },
        { id = "config",   interval = F.AutoSaveT or 30, weight = 0.05, priority = 4,
          fn = function() if F.tickAutoSave then pcall(F.tickAutoSave) end end },
        { id = "gc",       interval = 60,   weight = 0.20, priority = 4,
          fn = function() pcall(function() collectgarbage("collect") end) end },
    }
end

--================================================================
-- PERF TRACKER (fair-scheduling core)
--================================================================
local Perf = {
    -- frame-time smoothed
    avg_dt    = 1/60,
    -- stress 0..1 (0 = idle, 1 = max throttle)
    stress    = 0,
    -- backoff multiplier 1..3 (1 = full speed, 3 = 3x slower cadence)
    backoff   = 1,
    -- rolling loop time
    budget_used = 0,
    -- per-loop stats
    stats = {},
    -- recent frame samples for diagnostics
    samples = {},
    maxSamples = 60,
    -- last time we recalculated stress
    lastRecalc = 0,
}

local function recalcStress()
    -- Map smoothed dt to stress:
    --   dt <= 1/50 (>=50fps)   → stress 0
    --   dt >= 1/15 (<=15fps)   → stress 1
    --   linear in between
    local dt = Perf.avg_dt
    local fast = 1/50
    local slow = 1/15
    local s = (dt - fast) / (slow - fast)
    if s < 0 then s = 0 elseif s > 1 then s = 1 end
    Perf.stress = s
    -- backoff: 1x at s=0, up to 3x at s=1
    Perf.backoff = 1 + s * 2
end

--================================================================
-- SCHEDULER TICK (runs on Heartbeat)
--================================================================
local function runTick(C, loops, dt, now)
    -- 1. update frame-time smoothing (exponential moving average, alpha=0.1)
    Perf.avg_dt = Perf.avg_dt * 0.9 + dt * 0.1
    if now - Perf.lastRecalc > 1 then
        Perf.lastRecalc = now
        recalcStress()
    end

    -- 2. frame budget = 30% of frame time
    local budget = dt * 0.30
    local used = 0

    -- 3. run due loops in priority order (priority 1 → 4)
    --    loop table is already priority-ordered by construction
    for i = 1, #loops do
        local L = loops[i]

        -- priority-based load shedding
        if L.priority >= 4 and Perf.stress > 0.5 then goto continue end
        if L.priority >= 3 and Perf.stress > 0.8 and L.id ~= "chest" then goto continue end

        -- budget-based shedding (except priority 1, which always runs if due)
        if L.priority > 1 and used > budget then break end

        -- due check
        if now >= (L.nextRun or 0) then
            local t0 = os.clock()
            local ok, err = pcall(L.fn)
            local elapsed = os.clock() - t0

            used = used + elapsed
            L.nextRun = now + L.interval * Perf.backoff
            L.runs = (L.runs or 0) + 1

            -- stats
            local st = Perf.stats[L.id]
            if not st then
                st = { runs = 0, errs = 0, totalMs = 0, maxMs = 0, lastMs = 0 }
                Perf.stats[L.id] = st
            end
            st.runs = st.runs + 1
            st.totalMs = st.totalMs + elapsed
            st.lastMs = elapsed
            if elapsed > st.maxMs then st.maxMs = elapsed end

            if not ok then
                st.errs = st.errs + 1
                if st.errs <= 3 then
                    warn(string.format("[Dingus][loop %s] err %d: %s",
                        L.id, st.errs, tostring(err)))
                end
                if st.errs >= 10 then
                    L.disabled = true
                    warn(string.format("[Dingus][loop %s] disabled after 10 errors", L.id))
                end
            end
        end

        ::continue::
    end

    Perf.budget_used = used
    Perf.last_dt = dt

    -- 4. rolling sample buffer for diagnostics (capped)
    if #Perf.samples < Perf.maxSamples then
        table.insert(Perf.samples, dt)
    else
        Perf.samples[(now * 10 | 0) % Perf.maxSamples + 1] = dt
    end
end

--================================================================
-- BOOT
--================================================================
function M.boot(C)
    if type(C) ~= "table" then
        warn("[Dingus][main] no Ctx — abort")
        return
    end
    _G.Ctx = C

    local U = C.Util
    local F = C.Cfg
    if not U or not F then
        warn("[Dingus][main] Util or Cfg missing — abort")
        return
    end

    local S = C.St or {}
    C.St = S
    _G.St = S

    --================================================================
    -- SESSION-LEVEL GUARD: if a previous boot's heartbeat still runs,
    -- kill it before starting a new one.
    --================================================================
    if _G.DINGUS_HEARTBEAT_CONN then
        pcall(function() _G.DINGUS_HEARTBEAT_CONN:Disconnect() end)
        _G.DINGUS_HEARTBEAT_CONN = nil
    end
    if _G.DINGUS_RENDER_CONN then
        pcall(function() _G.DINGUS_RENDER_CONN:Disconnect() end)
        _G.DINGUS_RENDER_CONN = nil
    end
    if _G.DINGUS_INPUT_CONN then
        pcall(function() _G.DINGUS_INPUT_CONN:Disconnect() end)
        _G.DINGUS_INPUT_CONN = nil
    end
    if _G.DINGUS_CLEANUP_LIST then
        for i = 1, #_G.DINGUS_CLEANUP_LIST do
            pcall(_G.DINGUS_CLEANUP_LIST[i])
        end
        _G.DINGUS_CLEANUP_LIST = nil
    end

    --================================================================
    -- P1 · STATE INIT (single-pass, no branches)
    --================================================================
    S.run = true
    S.boot = false
    local D = F.DefaultToggles or {}
    S.cbt     = D.combat or false
    S.skl     = D.skl ~= false
    S.eqp     = D.eqp ~= false
    S.rtr     = D.rtr ~= false
    S.gsp     = D.gsp or false
    S.crw     = D.crw ~= false
    S.stunPun = D.stunPun ~= false
    S.cbtS    = "IDLE"
    S.rHt     = {}
    S.aiI     = F.AtkInterval or 0.38
    S.eq      = "none"
    S.kll, S.bKll, S.aAt, S.aHi, S.aMs = 0, 0, 0, 0, 0
    S.ens, S.ths, S.zn, S.imm = {}, {}, 0, 0
    S.tgt, S.tgtKind = nil, nil
    S.Spf = { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }
    S.fs, S.fps = {}, 60
    S.perf = Perf

    --================================================================
    -- P2 · SCRUB MOVERS (deferred to a task so boot doesn't block)
    --================================================================
    task.spawn(function()
        local R = U.hrp()
        if not R then return end
        for _, c in ipairs(R:GetChildren()) do
            if c:IsA("BodyPosition") or c:IsA("BodyVelocity")
               or c:IsA("BodyGyro") or c:IsA("BodyForce")
               or c:IsA("LinearVelocity") or c:IsA("AlignOrientation")
               or c:IsA("AlignPosition") then
                pcall(c.Destroy, c)
            end
        end
        local H = U.hum()
        if H then
            H.PlatformStand = false
            H.WalkSpeed = 16
            H.AutoRotate = true
        end
    end)

    --================================================================
    -- P3 · CONFIG LOAD
    --================================================================
    pcall(function()
        if F.setUtils then F.setUtils(U) end
        if F.exists and F.exists("default") then
            local ok, msg = F.load("default")
            if ok and not IS_REBOOT then
                print("[Dingus][main] config: " .. tostring(msg))
            end
        end
    end)

    --================================================================
    -- P4 · SUBSYSTEM INIT (isolated — a failure doesn't kill the boot)
    --================================================================
    local ORDER = {
        { "detect",     "Detect" },
        { "scanners",   "Scan"   },
        { "hotbar",     "Hotbar" },
        { "fly",        "Fly"    },
        { "spoofers",   "Spoof"  },
        { "chest",      "Chest"  },
        { "quests",     "Quest"  },
        { "attack",     "Atk"    },
        { "optimizers", "Opt"    },
        { "gui",        "Gui"    },
    }
    local okCount = 0
    for i = 1, #ORDER do
        local pair = ORDER[i]
        local mod = C[pair[2]]
        if mod and type(mod.init) == "function" then
            local good, err = pcall(mod.init, C)
            if good then
                okCount = okCount + 1
            else
                warn("[Dingus][main] " .. pair[1] .. " init: " .. tostring(err))
            end
        else
            warn("[Dingus][main] " .. pair[1] .. " missing")
        end
        task.wait()  -- yield between inits so we don't freeze on mobile
    end

    for _, k in ipairs({ "Cfg","Detect","Scan","Hotbar","Fly","Spoof",
                        "Chest","Quest","Atk","Opt","Gui" }) do
        if C[k] then pcall(function() _G[k] = C[k] end) end
    end

    --================================================================
    -- P5 · SCHEDULER (single Heartbeat, adaptive)
    --================================================================
    local loops = buildLoops(C, F)
    C.Loops = loops

    -- initial nextRun stagger so they don't all fire on frame 1
    local t0 = os.clock()
    for i = 1, #loops do
        loops[i].nextRun = t0 + (i - 1) * 0.005
    end

    local RS = U.Run or game:GetService("RunService")

    -- shared clock we advance in Heartbeat (matches frame timing)
    local clockAccum = 0

    _G.DINGUS_HEARTBEAT_CONN = RS.Heartbeat:Connect(function(dt)
        if not S.run then return end
        clockAccum = clockAccum + dt
        if S.boot then
            runTick(C, loops, dt, clockAccum)
        end
    end)

    --================================================================
    -- P6 · FPS SAMPLER (RenderStepped, but adaptive cadence)
    --================================================================
    local fpsAccum = 0
    local fpsFrames = 0
    _G.DINGUS_RENDER_CONN = RS.RenderStepped:Connect(function(dt)
        if not S.run then return end
        fpsAccum = fpsAccum + dt
        fpsFrames = fpsFrames + 1
        -- Sample every ~0.5s, not every frame
        if fpsAccum >= 0.5 then
            S.fps = fpsFrames / fpsAccum
            fpsAccum = 0
            fpsFrames = 0
        end
    end)

    --================================================================
    -- P7 · INPUT TOGGLE (RightShift)
    --================================================================
    local UIS = U.UIS
    if UIS then
        _G.DINGUS_INPUT_CONN = UIS.InputBegan:Connect(function(inp, gp)
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
    end

    --================================================================
    -- P8 · RESPAWN HANDLER (reset loops, not the whole boot)
    --================================================================
    pcall(function()
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            if not S.run then return end
            if C.Atk and C.Atk.forceStopRetreat then pcall(C.Atk.forceStopRetreat) end
            if C.Chest and C.Chest.resetCooldowns then pcall(C.Chest.resetCooldowns) end
            if C.Fly and C.Fly.stop then pcall(C.Fly.stop) end
            S.tgt = nil
            S.ens = {}
            -- restore any disabled loops
            for i = 1, #loops do
                loops[i].disabled = false
                loops[i].runs = 0
                local st = Perf.stats[loops[i].id]
                if st then st.errs = 0 end
            end
            print("[Dingus] respawned")
        end)
    end)

    --================================================================
    -- P9 · UNLOAD CONTRACT
    --================================================================
    C.Unload = function()
        print("[Dingus] unloading...")
        S.run = false
        S.boot = false
        pcall(function() if F.save then F.save("default") end end)

        -- run module cleanups
        if C.Cleanup then
            for i = 1, #C.Cleanup do pcall(C.Cleanup[i]) end
        end

        -- disconnect scheduler
        if _G.DINGUS_HEARTBEAT_CONN then
            pcall(function() _G.DINGUS_HEARTBEAT_CONN:Disconnect() end)
            _G.DINGUS_HEARTBEAT_CONN = nil
        end
        if _G.DINGUS_RENDER_CONN then
            pcall(function() _G.DINGUS_RENDER_CONN:Disconnect() end)
            _G.DINGUS_RENDER_CONN = nil
        end
        if _G.DINGUS_INPUT_CONN then
            pcall(function() _G.DINGUS_INPUT_CONN:Disconnect() end)
            _G.DINGUS_INPUT_CONN = nil
        end

        if C.Gui and C.Gui.gui then
            pcall(function() C.Gui.gui:Destroy() end)
        end

        local H = U.hum()
        if H then
            H.WalkSpeed = 16
            H.PlatformStand = false
        end

        _G.Ctx, _G.St = nil, nil
        print("[Dingus] unloaded")
    end

    --================================================================
    -- READY
    --================================================================
    S.boot = true
    if not IS_REBOOT then
        print(string.format("[Dingus] ready · %d loops · %d/%d subsystems",
            #loops, okCount, #ORDER))
        print("[Dingus] RightShift toggles UI · _G.Ctx.Unload() to stop")
    end

    --================================================================
    -- PUBLIC DIAGNOSTICS
    --================================================================
    C.perf = function()
        local out = {
            avg_fps = 1 / Perf.avg_dt,
            stress = Perf.stress,
            backoff = Perf.backoff,
            budget_used = Perf.budget_used,
            frames_sampled = #Perf.samples,
            loops = {},
        }
        for _, L in ipairs(loops) do
            local st = Perf.stats[L.id] or { runs = 0, errs = 0, totalMs = 0, maxMs = 0, lastMs = 0 }
            out.loops[L.id] = {
                runs = st.runs,
                errs = st.errs,
                avg_ms = st.runs > 0 and (st.totalMs / st.runs * 1000) or 0,
                max_ms = st.maxMs * 1000,
                last_ms = st.lastMs * 1000,
                disabled = L.disabled or false,
            }
        end
        return out
    end

    C.perfPrint = function()
        local p = C.perf()
        print(string.format("[Dingus][perf] fps=%.1f stress=%.2f backoff=%.2fx budget=%.1fms",
            p.avg_fps, p.stress, p.backoff, p.budget_used * 1000))
        print(string.format("  %-10s %-8s %-8s %-10s %-10s %-6s",
            "loop", "runs", "errs", "avg_ms", "max_ms", "state"))
        for id, s in pairs(p.loops) do
            print(string.format("  %-10s %-8d %-8d %-10.2f %-10.2f %-6s",
                id, s.runs, s.errs, s.avg_ms, s.max_ms,
                s.disabled and "DIS" or "on"))
        end
    end
end

return M
