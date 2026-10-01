--[[
    Dingus-Slayer · loader.lua v25
    Three-phase loader. Per-file retry. Dependency-aware order.
    Crash-safe: partial failures leave a working core.
]]--

local REPO_USER = "PurpleXPurple"
local REPO_NAME = "Dingus-Slayer"
local REPO_BRANCH = "main"
local BASE = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/",
    REPO_USER, REPO_NAME, REPO_BRANCH
)

local MAX_RETRIES = 3
local RETRY_DELAY = 0.6
local HTTP_TIMEOUT = 12

local Ctx = {
    St = {},
    Errors = {},
    Warnings = {},
    Loaded = {},
    StartTime = os.clock(),
}

--============================================================
-- LOGGING
--============================================================
local function log(level, msg)
    local prefix = "[Dingus][" .. level .. "]"
    if level == "err" then warn(prefix .. " " .. msg)
    else print(prefix .. " " .. msg) end
end

local function logErr(stage, msg, detail)
    table.insert(Ctx.Errors, { stage = stage, msg = msg, detail = detail })
    log("err", stage .. ": " .. msg .. (detail and (" — " .. tostring(detail)) or ""))
end

local function logWarn(stage, msg)
    table.insert(Ctx.Warnings, { stage = stage, msg = msg })
    log("warn", stage .. ": " .. msg)
end

--============================================================
-- HTTP WITH TIMEOUT + RETRY
--============================================================
local function httpGet(url, retries)
    retries = retries or MAX_RETRIES
    local lastErr = nil

    for attempt = 1, retries do
        local done = false
        local result = nil

        -- Fire the request in a coroutine so we can enforce a timeout
        local co = coroutine.create(function()
            local ok, res = pcall(function()
                return game:HttpGet(url, true)
            end)
            if ok then result = res end
            done = true
        end)
        coroutine.resume(co)

        local waited = 0
        while not done and waited < HTTP_TIMEOUT do
            task.wait(0.1)
            waited = waited + 0.1
        end

        if done and result and type(result) == "string" and #result > 40 then
            return result, nil
        end

        lastErr = not done and "timeout" or ("short: " .. tostring(result and #result))
        if attempt < retries then
            task.wait(RETRY_DELAY * attempt)
        end
    end

    return nil, lastErr
end

--============================================================
-- MODULE FETCH + COMPILE + EXECUTE
--============================================================
local function fetchModule(name)
    local url = BASE .. name .. ".lua"
    local code, err = httpGet(url, MAX_RETRIES)
    if not code then
        logErr(name, "HTTP failed", err)
        return nil
    end

    if string.find(code, "404: Not Found", 1, true) then
        logErr(name, "404 Not Found", url)
        return nil
    end

    local fn, compileErr = loadstring(code, "@" .. name .. ".lua")
    if not fn then
        logErr(name, "compile error", compileErr)
        return nil
    end

    local ok, mod = pcall(fn)
    if not ok then
        logErr(name, "runtime error", mod)
        return nil
    end

    if mod == nil then
        logErr(name, "returned nil — missing 'return' at end")
        return nil
    end

    return mod, code
end

--============================================================
-- DEPENDENCY MANIFEST
--============================================================
-- Each entry: { name, slot, requires = {...} }
-- requires is the list of module names that must be loaded before this one
local MANIFEST = {
    { name = "lists",      slot = "Lists" },
    { name = "config",     slot = "Cfg",      requires = {} },
    { name = "utils",      slot = "Util",     requires = { "config" } },
    { name = "detect",     slot = "Detect",   requires = { "utils", "lists", "config" } },
    { name = "scanners",   slot = "Scan",     requires = { "utils", "lists" } },
    { name = "spoofers",   slot = "Spoof",    requires = { "utils", "config" } },
    { name = "attack",     slot = "Atk",      requires = { "utils", "detect", "lists", "spoofers", "config" } },
    { name = "optimizers", slot = "Opt",      requires = { "utils", "config" } },
    { name = "gui",        slot = "Gui",      requires = { "utils", "config" } },
    { name = "main",       slot = nil,        requires = { "utils", "detect", "attack", "gui", "optimizers", "scanners", "spoofers", "lists", "config" } },
}

--============================================================
-- PHASE 1: REQUIRE (fetch + compile + execute)
--============================================================
local function phaseRequire()
    log("info", "phase 1/3 — requiring modules")

    local loadedNames = {}
    for i = 1, #MANIFEST do
        local entry = MANIFEST[i]
        local name = entry.name

        -- Check dependencies first
        local depsOk = true
        if entry.requires then
            for j = 1, #entry.requires do
                if not loadedNames[entry.requires[j]] then
                    logErr(name, "missing dependency: " .. entry.requires[j])
                    depsOk = false
                    break
                end
            end
        end
        if not depsOk then
            Ctx.Loaded[name] = false
            task.wait(0.03)
            continue_or_break()
        else
            local mod, src = fetchModule(name)
            if mod then
                Ctx.Loaded[name] = true
                if entry.slot then Ctx[entry.slot] = mod end
                if src then Ctx["_" .. name .. "Src"] = src end
                loadedNames[name] = true
                log("info", "  ✓ " .. name)
            else
                Ctx.Loaded[name] = false
                log("warn", "  ✗ " .. name)
            end
            task.wait(0.03)
        end
    end
end

-- Lua doesn't have `continue` — emulate with a helper flag
function continue_or_break() end

--============================================================
-- PHASE 2: INIT (call .init on each subsystem)
--============================================================
local function phaseInit()
    log("info", "phase 2/3 — initializing subsystems")

    local initOrder = { "Detect", "Scan", "Spoof", "Atk", "Opt", "Gui" }
    local okCount = 0

    for i = 1, #initOrder do
        local slot = initOrder[i]
        local mod = Ctx[slot]
        if mod and type(mod.init) == "function" then
            local ok, err = pcall(mod.init, Ctx)
            if ok then
                okCount = okCount + 1
                log("info", "  ✓ " .. slot)
            else
                logErr(slot .. ".init", tostring(err))
            end
        elseif mod then
            logWarn(slot, "no init function")
        else
            logWarn(slot, "module not loaded")
        end
        task.wait(0.02)
    end

    log("info", "  " .. okCount .. "/" .. #initOrder .. " subsystems initialized")
end

--============================================================
-- PHASE 3: BOOT (call main.boot with full context)
--============================================================
local function phaseBoot()
    log("info", "phase 3/3 — booting main")
    local main = Ctx._mainMod
    if not main then
        -- main wasn't stored in a slot — look for it by re-reading from Loaded
        -- We stored it during phase 1; re-fetch it here
        local mod = fetchModule("main")
        if not mod then
            logErr("main", "could not load main module")
            return false
        end
        main = mod
    end

    if type(main) ~= "table" or type(main.boot) ~= "function" then
        logErr("main", "main must return { boot = function(Ctx) }")
        return false
    end

    local ok, err = pcall(main.boot, Ctx)
    if not ok then
        logErr("main.boot", tostring(err))
        return false
    end

    log("info", "  ✓ main.boot")
    return true
end

--============================================================
-- ENTRY
--============================================================
print("=================================================")
print("  Dingus-Slayer · boot")
print("  " .. BASE)
print("=================================================")

-- Special-case: main module must be captured for phase 3
-- We handle this by setting slot = "_mainMod" during phase 1
for i = 1, #MANIFEST do
    if MANIFEST[i].name == "main" then
        MANIFEST[i].slot = "_mainMod"
    end
end

phaseRequire()
task.wait(0.1)
phaseInit()
task.wait(0.1)

local bootOk = phaseBoot()

local elapsed = os.clock() - Ctx.StartTime
print("=================================================")
print(string.format("  boot %s in %.2fs", bootOk and "complete" or "incomplete", elapsed))
if #Ctx.Errors > 0 then
    print("  errors (" .. #Ctx.Errors .. "):")
    for i = 1, #Ctx.Errors do
        local e = Ctx.Errors[i]
        print(string.format("    [%s] %s", e.stage, e.msg))
    end
end
if #Ctx.Warnings > 0 then
    print("  warnings (" .. #Ctx.Warnings .. "):")
    for i = 1, #Ctx.Warnings do
        local w = Ctx.Warnings[i]
        print(string.format("    [%s] %s", w.stage, w.msg))
    end
end
print("=================================================")

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Dingus-Slayer",
        Text = string.format("%s · %.1fs · %d errors",
            bootOk and "loaded" or "partial", elapsed, #Ctx.Errors),
        Duration = 5,
    })
end)
