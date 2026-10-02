-- Dingus-Slayer · main.lua v39
-- GUI removed from init order. Loader owns GUI lifecycle.
-- Heartbeat guard hardened. Fast init loop.

local M = {}

local function buildLoops(C, F)
    return {
        { id = "combat",   interval = 0.05, weight = 0.35, priority = 1,
          fn = function()
              if C.Atk and C.Atk.combatTick then pcall(C.Atk.combatTick) end
          end },
        { id = "threats",  interval = 0.10, weight = 0.15, priority = 1,
          fn = function()
              if C.Detect and C.Detect.updateThreats then
                  pcall(C.Detect.updateThreats)
              end
          end },
        { id = "fly",      interval = 0.05, weight = 0.10, priority = 1,
          fn = function()
              if C.Fly and C.Fly.tick then pcall(C.Fly.tick) end
          end },
        { id = "spoofers", interval = 0.10, weight = 0.10, priority = 2,
          fn = function()
              if C.Spoof and C.Spoof.tick then pcall(C.Spoof.tick) end
          end },
        { id = "quest",    interval = 0.50, weight = 0.15, priority = 3,
          fn = function()
              if C.Quest and C.Quest.cycle then pcall(C.Quest.cycle) end
          end },
        { id = "chest",    interval = 1.50, weight = 0.30, priority = 3,
          fn = function()
              if C.Chest and C.Chest.collectPassive then
                  pcall(C.Chest.collectPassive)
              end
          end },
        { id = "config",   interval = F.AutoSaveT or 30,
          weight = 0.05, priority = 4,
          fn = function()
              if F.tickAutoSave then pcall(F.tickAutoSave) end
          end },
        { id = "gc",       interval = 60, weight = 0.20, priority = 4,
          fn = function()
              pcall(function() collectgarbage("collect") end)
          end },
    }
end

local Perf = {
    avg_dt = 1/60, stress = 0, backoff = 1,
    budget_used = 0, stats = {},
    lastRecalc = 0, lastFrame = 0,
}

local function recalcStress()
    local dt = Perf.avg_dt
    local fast = 1/50
    local slow = 1/15
    local s = (dt - fast) / (slow - fast)
    if s < 0 then s = 0 elseif s > 1 then s = 1 end
    Perf.stress = s
    Perf.backoff = 1 + s * 2
end

local function runTick(C, loops, dt, now)
    Perf.avg_dt = Perf.avg_dt * 0.9 + dt * 0.1
    if now - Perf.lastRecalc > 1 then
        Perf.lastRecalc = now
        recalcStress()
    end

    local budget = dt * 0.30
    local used = 0

    for i = 1, #loops do
        local L = loops[i]

        if L.priority >= 4 and Perf.stress > 0.5 then goto continue end
        if L.priority >= 3 and Perf.stress > 0.8 and L.id ~= "chest" then
            goto continue
        end
        if L.priority > 1 and used > budget then break end

        if now >= (L.nextRun or 0) then
            local t0 = os.clock()
            local ok, err = pcall(L.fn)
            local elapsed = os.clock() - t0

            used = used + elapsed
            L.nextRun = now + L.interval * Perf.backoff
            L.runs = (L.runs or 0) + 1

            local st = Perf.stats[L.id]
            if not st then
                st = { runs = 0, errs = 0, totalMs = 0,
                       maxMs = 0, lastMs = 0 }
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
                    warn("[Dingus][loop " .. L.id
                        .. "] disabled after 10 errors")
                end
            end
        end

        ::continue::
    end

    Perf.budget_used = used
    Perf.lastFrame = now
end

function M.boot(C)
    if type(C) ~= "table" then
        warn("[Dingus][main] no Ctx")
        return
    end
    _G.Ctx = C

    local U = C.Util
    local F = C.Cfg
    if not U or not F then
        warn("[Dingus][main] Util or Cfg missing")
        return
    end

    local S = C.St or {}
    C.St = S
    _G.St = S

    -- Kill any prior connections from a previous boot
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

    -- State
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
    S.kll, S.bKll = 0, 0
    S.aAt, S.aHi, S.aMs = 0, 0, 0
    S.ens, S.ths, S.zn, S.imm = {}, {}, 0, 0
    S.tgt, S.tgtKind = nil, nil
    S.Spf = { hpC = 0, bkC = 0, spdC = 0, kbC = 0, jmpC = 0 }
    S.fs, S.fps = {}, 60
    S.perf = Perf

    -- Scrub movers (deferred)
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

    -- Config load
    pcall(function()
        if F.setUtils then F.setUtils(U) end
        if F.exists and F.exists("default") then
            local ok, msg = F.load("default")
            if ok and _G.DINGUS_BOOT_COUNT == 1 then
                print("[Dingus][main] config: " .. tostring(msg))
            end
        end
    end)

    -- Subsystem init (GUI intentionally absent — loader owns it)
    local ORDER = {
        { "detect",     "Detect" },
        { "scanners",   "Scan"   },
        { "hotbar",     "Hotbar" },
        { "faction",    "Faction" },
        { "fly",        "Fly"    },
        { "spoofers",   "Spoof"  },
        { "chest",      "Chest"  },
        { "quests",     "Quest"  },
        { "attack",     "Atk"    },
        { "optimizers", "Opt"    },
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
                warn("[Dingus][main] " .. pair[1] .. " init: "
                    .. tostring(err))
            end
        else
            warn("[Dingus][main] " .. pair[1] .. " missing")
        end
        -- Yield only on slow devices
        if U.IsMobile then task.wait() end
    end

    -- Loops
    local loops = buildLoops(C, F)
    C.Loops = loops

    local t0 = os.clock()
    for i = 1, #loops do
        loops[i].nextRun = t0 + (i - 1) * 0.005
    end

    local RS = U.Run or game:GetService("RunService")
    local clockAccum = 0

    _G.DINGUS_HEARTBEAT_CONN = RS.Heartbeat:Connect(function(dt)
        if not S.run then return end
        clockAccum = clockAccum + dt
        if S.boot then
            runTick(C, loops, dt, clockAccum)
        end
    end)

    -- FPS sampler at 0.5s cadence
    local fpsAccum = 0
    local fpsFrames = 0
    _G.DINGUS_RENDER_CONN = RS.RenderStepped:Connect(function(dt)
        if not S.run then return end
        fpsAccum = fpsAccum + dt
        fpsFrames = fpsFrames + 1
        if fpsAccum >= 0.5 then
            S.fps = fpsFrames / fpsAccum
            fpsAccum = 0
            fpsFrames = 0
        end
    end)

    -- RightShift toggle (works even if GUI loads later)
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

    -- Respawn handler
    pcall(function()
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            if not S.run then return end
            if C.Atk and C.Atk.forceStopRetreat then
                pcall(C.Atk.forceStopRetreat)
            end
            if C.Chest and C.Chest.resetCooldowns then
                pcall(C.Chest.resetCooldowns)
            end
            if C.Fly and C.Fly.stop then pcall(C.Fly.stop) end
            S.tgt = nil
            S.ens = {}
            for i = 1, #loops do
                loops[i].disabled = false
                loops[i].runs = 0
                local st = Perf.stats[loops[i].id]
                if st then st.errs = 0 end
            end
            print("[Dingus] respawned")
        end)
    end)

    -- Unload
    C.Unload = function()
        print("[Dingus] unloading...")
        S.run = false
        S.boot = false
        pcall(function() if F.save then F.save("default") end end)
        if C.Cleanup then
            for i = 1, #C.Cleanup do pcall(C.Cleanup[i]) end
        end
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

    S.boot = true
    if _G.DINGUS_BOOT_COUNT == 1 then
        print(string.format(
            "[Dingus] ready · %d loops · %d/%d subsystems (gui separate)",
            #loops, okCount, #ORDER))
    end

    C.perf = function()
        local out = {
            avg_fps = 1 / Perf.avg_dt,
            stress = Perf.stress,
            backoff = Perf.backoff,
            budget_used = Perf.budget_used,
            loops = {},
        }
        for _, L in ipairs(loops) do
            local st = Perf.stats[L.id]
                or { runs = 0, errs = 0, totalMs = 0, maxMs = 0, lastMs = 0 }
            out.loops[L.id] = {
                runs = st.runs, errs = st.errs,
                avg_ms = st.runs > 0
                    and (st.totalMs / st.runs * 1000) or 0,
                max_ms = st.maxMs * 1000,
                last_ms = st.lastMs * 1000,
                disabled = L.disabled or false,
            }
        end
        return out
    end

    C.perfPrint = function()
        local p = C.perf()
        print(string.format(
            "[Dingus][perf] fps=%.1f stress=%.2f backoff=%.2fx budget=%.1fms",
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
