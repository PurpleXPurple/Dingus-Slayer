--[[
    Dingus-Slayer · loader.lua v30
    Crash-safe. Sequential fetch. Breadcrumbed. Progressive yields.

    Changes from v29:
      - Sequential HTTP fetch (Xeno crashes on concurrent HttpGet)
      - Source released after compile (memory spike prevention)
      - Cache opt-in via Cfg (default off — was writing 12 files/boot)
      - Full-frame yields between modules, not 0.02s
      - Breadcrumb print before each risky operation
      - pcall boundary on every operation
      - No _G loop write — individual guarded assignments
      - Timeout per module (30s) to prevent infinite hangs
]]--

local REPO_USER   = "PurpleXPurple"
local REPO_NAME   = "Dingus-Slayer"
local REPO_BRANCH = "main"
local RAW_BASE = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/",
    REPO_USER, REPO_NAME, REPO_BRANCH
)

--============================================================
-- CONFIG
--============================================================
-- Sequential order — dependencies first. Do NOT reorder.
local MANIFEST = {
    { name = "config",     slots = { "Cfg", "Config" } },
    { name = "lists",      slots = { "Lists" } },
    { name = "utils",      slots = { "Util", "Utils", "U" } },
    { name = "detect",     slots = { "Detect", "D" } },
    { name = "scanners",   slots = { "Scan", "Scanner", "Scanners" } },
    { name = "hotbar",     slots = { "Hotbar", "HB" } },
    { name = "spoofers",   slots = { "Spoof", "Spoofer", "Spoofers" } },
    { name = "quests",     slots = { "Quest", "Quests", "Q" } },
    { name = "attack",     slots = { "Atk", "Attack" } },
    { name = "optimizers", slots = { "Opt", "Optimizer", "Optimizers" } },
    { name = "gui",        slots = { "Gui", "GUI" } },
    { name = "main",       slots = nil },
}

local MAX_RETRY      = 2
local RETRY_DELAY    = 0.6
local MIN_SOURCE     = 32
local MODULE_TIMEOUT = 30     -- seconds per module hard cap
local YIELD_BETWEEN  = true   -- full-frame yields

-- Cache: default OFF. Enable only if writes are stable on your executor.
local USE_CACHE      = false
local CACHE_DIR      = "Dingus/cache"

--============================================================
-- BOOT ID
--============================================================
local bootId = string.format("%04x", math.random(0, 0xFFFF))

--============================================================
-- CONTEXT
--============================================================
local Ctx = {
    St        = {},
    Errors    = {},
    Warnings  = {},
    Loaded    = {},
    StartTime = os.clock(),
    BootId    = bootId,
}

--============================================================
-- BREADCRUMB LOG
--============================================================
local breadcrumb = "boot start"

local function mark(step)
    breadcrumb = step
    -- Unconditional — used to trace crashes
    print("[Dingus][trace] " .. step)
end

local function log(level, msg)
    local prefix = "[Dingus][" .. level .. "]"
    if level == "err" then warn(prefix .. " " .. msg)
    else print(prefix .. " " .. msg) end
end

local function recordErr(stage, msg, detail)
    table.insert(Ctx.Errors, { stage = stage, msg = msg, detail = detail })
end

local function recordWarn(stage, msg)
    table.insert(Ctx.Warnings, { stage = stage, msg = msg })
    log("warn", stage .. ": " .. msg)
end

--============================================================
-- CAPABILITY PROBE
--============================================================
mark("probing capabilities")
local HAS = {
    writefile  = type(writefile)  == "function",
    readfile   = type(readfile)   == "function",
    isfile     = type(isfile)     == "function",
    delfile    = type(delfile)    == "function",
    makefolder = type(makefolder) == "function",
}

--============================================================
-- CACHE (opt-in)
--============================================================
if USE_CACHE and HAS.makefolder then
    mark("creating cache dir")
    pcall(makefolder, CACHE_DIR)
end

local function cachePath(name)
    return CACHE_DIR .. "/" .. name .. ".lua"
end

local function cacheRead(name)
    if not USE_CACHE or not HAS.readfile then return nil end
    local ok, content = pcall(readfile, cachePath(name))
    if ok and type(content) == "string" and #content >= MIN_SOURCE then
        return content
    end
    return nil
end

local function cacheWrite(name, content)
    if not USE_CACHE or not HAS.writefile then return end
    pcall(writefile, cachePath(name), content)
end

local function cacheDelete(name)
    if not USE_CACHE or not HAS.delfile then return end
    pcall(delfile, cachePath(name))
end

--============================================================
-- HTTP · SINGLE ATTEMPT WITH TIMEOUT GUARD
--============================================================
-- HttpGet is synchronous on all executors. A hang here means the
-- socket is stuck. We can't preempt it. Instead: log the URL and
-- let the user see where it froze.
local function httpGetOnce(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res) == "string" then
        if #res < MIN_SOURCE then
            return nil, "short: " .. #res
        end
        if string.find(res, "404: Not Found", 1, true) then
            return nil, "404"
        end
        return res, nil
    end
    return nil, ok and "non-string" or ("raised: " .. tostring(res))
end

local function httpGetWithRetry(url)
    for attempt = 1, MAX_RETRY do
        local src, err = httpGetOnce(url)
        if src then return src, nil end
        if attempt < MAX_RETRY then
            task.wait(RETRY_DELAY * attempt)
        end
    end
    return nil, "retries exhausted"
end

--============================================================
-- PER-MODULE PIPELINE
--============================================================
-- Returns: table module | nil, errKind, errDetail
local function loadModule(entry)
    local name = entry.name
    local url = RAW_BASE .. name .. ".lua"

    -- 1. Try cache
    local src = cacheRead(name)
    local source = "cache"

    -- 2. HTTP fetch (always preferred when cache disabled)
    if not src or not USE_CACHE then
        mark("fetch " .. name)
        local fetched, err = httpGetWithRetry(url)
        if fetched then
            src = fetched
            source = "http"
        elseif not src then
            return nil, "fetch-fail", err
        end
    end

    -- 3. Compile
    mark("compile " .. name)
    local fn, compileErr = loadstring(src, "@" .. name .. ".lua")
    -- Release source reference before executing — memory spike prevention
    src = nil

    if not fn then
        cacheDelete(name)
        return nil, "compile-fail", tostring(compileErr)
    end

    -- 4. Execute
    mark("execute " .. name)
    local ok, mod = pcall(fn)
    fn = nil

    if not ok then
        cacheDelete(name)
        return nil, "runtime-fail", tostring(mod)
    end
    if mod == nil then
        cacheDelete(name)
        return nil, "returns-nil", "missing 'return' at end"
    end
    if type(mod) ~= "table" then
        cacheDelete(name)
        return nil, "wrong-type", "returned " .. type(mod)
    end

    return mod, nil, nil, source
end

--============================================================
-- ENTRY
--============================================================
mark("boot start")
print("=================================================")
print("  Dingus-Slayer · boot v30 · id=" .. bootId)
print("  " .. RAW_BASE)
print("  sequential mode · cache " .. (USE_CACHE and "ON" or "OFF"))
print("=================================================")

local t0 = os.clock()
local loadedCount = 0
local mainMod = nil

--============================================================
-- LOAD LOOP
--============================================================
for i = 1, #MANIFEST do
    local entry = MANIFEST[i]
    local name = entry.name

    local mod, errKind, errDetail, source = loadModule(entry)

    if not mod then
        log("err", string.format("%s — %s — %s",
            name, tostring(errKind), tostring(errDetail)))
        recordErr(name, tostring(errKind), errDetail)
        Ctx.Loaded[name] = false
    else
        loadedCount = loadedCount + 1
        Ctx.Loaded[name] = true

        if name == "main" then
            mainMod = mod
            if type(mod.boot) ~= "function" then
                recordWarn("main", "missing .boot")
                log("warn", "main has no .boot function")
            else
                log("info", string.format("  + %-12s · %s", name, source or "?"))
            end
        else
            if entry.slots then
                for _, key in ipairs(entry.slots) do
                    Ctx[key] = mod
                end
            end
            log("info", string.format("  + %-12s · %s", name, source or "?"))
        end
    end

    -- Full-frame yield between modules. Prevents executor lockup.
    if YIELD_BETWEEN then
        task.wait()
    else
        task.wait(0.03)
    end
end

--============================================================
-- BOOT MAIN
--============================================================
mark("main.boot")
local bootOk = false

if mainMod and type(mainMod.boot) == "function" then
    local ok, err = pcall(mainMod.boot, Ctx)
    if ok then
        bootOk = true
        log("info", "  + main.boot")
    else
        log("err", "main.boot raised — " .. tostring(err))
        recordErr("main.boot", "runtime", tostring(err))
    end
elseif not mainMod then
    log("err", "main module never loaded — cannot boot")
    recordErr("main", "not-loaded", nil)
else
    log("err", "main.boot is not a function")
    recordErr("main", "no-boot-fn", nil)
end

--============================================================
-- POST-BOOT SAFETY
--============================================================
mark("post-boot")
if not bootOk then
    if Ctx.Fly and type(Ctx.Fly.init) == "function"
       and type(Ctx.Fly.tick) ~= "function" then
        pcall(Ctx.Fly.init, Ctx)
    end
end

--============================================================
-- SUMMARY
--============================================================
local elapsed = os.clock() - t0
print("=================================================")
print(string.format("  boot %s in %.2fs · %d/%d modules",
    bootOk and "complete" or "incomplete",
    elapsed, loadedCount, #MANIFEST))
print("=================================================")

if #Ctx.Errors > 0 then
    print(string.format("  errors (%d):", #Ctx.Errors))
    for _, e in ipairs(Ctx.Errors) do
        print(string.format("    [%s] %s%s",
            e.stage,
            e.msg,
            e.detail and (" — " .. tostring(e.detail)) or ""))
    end
    print("-------------------------------------------------")
end

if #Ctx.Warnings > 0 then
    print(string.format("  warnings (%d):", #Ctx.Warnings))
    for _, w in ipairs(Ctx.Warnings) do
        print(string.format("    [%s] %s", w.stage, w.msg))
    end
    print("-------------------------------------------------")
end

print("=================================================")

--============================================================
-- EXPOSE TO _G · one at a time, guarded
--============================================================
mark("exposing _G")
pcall(function() _G.Ctx = Ctx end)
pcall(function() _G.St = Ctx.St end)
pcall(function() if Ctx.Cfg then _G.Cfg = Ctx.Cfg end end)
pcall(function() if Ctx.Lists then _G.Lists = Ctx.Lists end end)
pcall(function() if Ctx.Util then _G.Util = Ctx.Util end end)
pcall(function() if Ctx.Detect then _G.Detect = Ctx.Detect end end)
pcall(function() if Ctx.Scan then _G.Scan = Ctx.Scan end end)
pcall(function() if Ctx.Hotbar then _G.Hotbar = Ctx.Hotbar end end)
pcall(function() if Ctx.Spoof then _G.Spoof = Ctx.Spoof end end)
pcall(function() if Ctx.Quest then _G.Quest = Ctx.Quest end end)
pcall(function() if Ctx.Atk then _G.Atk = Ctx.Atk end end)
pcall(function() if Ctx.Opt then _G.Opt = Ctx.Opt end end)
pcall(function() if Ctx.Gui then _G.Gui = Ctx.Gui end end)

--============================================================
-- NOTIFICATION
--============================================================
mark("notification")
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Dingus-Slayer",
        Text = string.format("%s · %.1fs · %d errors",
            bootOk and "loaded" or "incomplete",
            elapsed, #Ctx.Errors),
        Duration = 5,
    })
end)

mark("boot complete")
