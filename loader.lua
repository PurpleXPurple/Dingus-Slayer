--[[
    Dingus-Slayer · loader.lua v32
    Sequential-safe. Multi-CDN fallback. Cache opt-in. Breadcrumb trace.

    Crash fix from v31:
      - Removed parallel fetch worker pool entirely. Xeno's HTTP layer
        serializes anyway and the pool added coroutine churn + memory
        spikes that hung the executor.
      - Sequential load loop with full-frame yields between modules.
      - Source released after compile to avoid double-buffering memory.

    Retained from v31:
      - Multi-CDN fallback (github → jsdelivr → statically)
      - Cache with 1h TTL, opt-in
      - Stale-cache fallback if all CDNs fail
      - Per-module timing in boot summary
      - Breadcrumb tracing — last line before crash tells us where
      - Full error text in summary
      - chest module added to manifest
]]--

--============================================================
-- CONFIG
--============================================================
local REPO_USER   = "PurpleXPurple"
local REPO_NAME   = "Dingus-Slayer"
local REPO_BRANCH = "main"

-- Dependencies first. Do not reorder.
local MANIFEST = {
    { name = "config",     slots = { "Cfg", "Config" } },
    { name = "lists",      slots = { "Lists" } },
    { name = "utils",      slots = { "Util", "Utils", "U" } },
    { name = "detect",     slots = { "Detect", "D" } },
    { name = "scanners",   slots = { "Scan", "Scanner", "Scanners" } },
    { name = "hotbar",     slots = { "Hotbar", "HB" } },
    { name = "spoofers",   slots = { "Spoof", "Spoofer", "Spoofers" } },
    { name = "chest",      slots = { "Chest" } },
    { name = "quests",     slots = { "Quest", "Quests", "Q" } },
    { name = "attack",     slots = { "Atk", "Attack" } },
    { name = "optimizers", slots = { "Opt", "Optimizer", "Optimizers" } },
    { name = "gui",        slots = { "Gui", "GUI" } },
    { name = "main",       slots = nil },
}

local MAX_RETRY      = 2
local RETRY_DELAY    = 0.5
local MIN_SOURCE     = 32
local CACHE_DIR      = "Dingus/cache"
local CACHE_TTL      = 3600
local USE_CACHE      = true
local TRACE_ENABLED  = true
local YIELD_BETWEEN  = true

--============================================================
-- CDN SOURCES
--============================================================
local CDNS = {
    {
        label = "github",
        url = function(f)
            return string.format(
                "https://raw.githubusercontent.com/%s/%s/%s/%s.lua",
                REPO_USER, REPO_NAME, REPO_BRANCH, f)
        end,
    },
    {
        label = "jsdelivr",
        url = function(f)
            return string.format(
                "https://cdn.jsdelivr.net/gh/%s/%s@%s/%s.lua",
                REPO_USER, REPO_NAME, REPO_BRANCH, f)
        end,
    },
    {
        label = "statically",
        url = function(f)
            return string.format(
                "https://cdn.statically.io/gh/%s/%s/%s/%s.lua",
                REPO_USER, REPO_NAME, REPO_BRANCH, f)
        end,
    },
}

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
    BootId    = bootId,
    StartTime = os.clock(),
    Boot      = {
        fetch = {},
        compile = {},
        execute = {},
        cdnUsed = {},
        cacheHits = 0,
        cacheMiss = 0,
    },
}

--============================================================
-- TRACE + LOG
--============================================================
local trace = "boot:start"
local function mark(s)
    trace = s
    if TRACE_ENABLED then print("[Dingus][trace] " .. s) end
end

local function log(level, msg)
    local pre = "[Dingus][" .. level .. "]"
    if level == "err" then warn(pre .. " " .. msg)
    else print(pre .. " " .. msg) end
end

local function recordErr(stage, msg, detail)
    table.insert(Ctx.Errors, { stage = stage, msg = msg, detail = detail })
end

local function recordWarn(stage, msg)
    table.insert(Ctx.Warnings, { stage = stage, msg = msg })
    log("warn", stage .. ": " .. msg)
end

local function now() return os.clock() end
local function realtime() return os.time() end

--============================================================
-- CAPABILITY PROBE
--============================================================
mark("probe:capabilities")
local HAS = {
    writefile  = type(writefile)  == "function",
    readfile   = type(readfile)   == "function",
    isfile     = type(isfile)     == "function",
    delfile    = type(delfile)    == "function",
    makefolder = type(makefolder) == "function",
}

--============================================================
-- CACHE
--============================================================
mark("cache:setup")
if USE_CACHE and HAS.makefolder then
    pcall(makefolder, CACHE_DIR)
end

local function cachePath(n) return CACHE_DIR .. "/" .. n .. ".lua" end
local function cacheMeta(n) return CACHE_DIR .. "/" .. n .. ".meta" end

local function cacheRead(name)
    if not USE_CACHE or not HAS.readfile then return nil, 0 end
    local ok, src = pcall(readfile, cachePath(name))
    if not ok or type(src) ~= "string" or #src < MIN_SOURCE then
        return nil, 0
    end
    local age = 0
    local okM, meta = pcall(readfile, cacheMeta(name))
    if okM and type(meta) == "string" then
        local ts = tonumber(meta:match("^(%d+)"))
        if ts then age = realtime() - ts end
    end
    return src, age
end

local function cacheWrite(name, src)
    if not USE_CACHE or not HAS.writefile then return end
    pcall(writefile, cachePath(name), src)
    pcall(writefile, cacheMeta(name), tostring(realtime()))
end

local function cacheDelete(name)
    if not HAS.delfile then return end
    pcall(delfile, cachePath(name))
    pcall(delfile, cacheMeta(name))
end

--============================================================
-- HTTP · single attempt
--============================================================
local function tryUrl(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res) == "string" and #res >= MIN_SOURCE then
        if not string.find(res, "404: Not Found", 1, true) then
            return res, nil
        end
        return nil, "404"
    end
    return nil, ok and "invalid-response" or tostring(res)
end

--============================================================
-- HTTP · multi-CDN with retries
--============================================================
local function fetchFromCDNs(name)
    local t0 = now()
    local lastErr = nil

    for _, cdn in ipairs(CDNS) do
        local url = cdn.url(name)
        for attempt = 1, MAX_RETRY do
            local src, err = tryUrl(url)
            if src then
                Ctx.Boot.cdnUsed[name] = cdn.label
                Ctx.Boot.fetch[name] = (now() - t0) * 1000
                return src, nil, cdn.label
            end
            lastErr = err
            if attempt < MAX_RETRY then
                task.wait(RETRY_DELAY)
            end
        end
    end

    Ctx.Boot.fetch[name] = (now() - t0) * 1000
    return nil, lastErr or "all-cdns-failed"
end

--============================================================
-- LOAD ONE MODULE · fetch + compile + execute
-- Returns: mod table | nil, errKind, errDetail, source
--============================================================
local function loadModule(entry)
    local name = entry.name

    -- 1. Try cache
    local src, age = cacheRead(name)
    local source = "cache"

    if not src or age >= CACHE_TTL then
        -- 2. Fetch from CDN
        mark("fetch:" .. name)
        local fetched, err, cdn = fetchFromCDNs(name)
        if fetched then
            src = fetched
            source = cdn or "http"
            Ctx.Boot.cacheMiss = Ctx.Boot.cacheMiss + 1
            cacheWrite(name, src)
        elseif src then
            -- Stale cache fallback
            source = "stale"
            recordWarn(name, "http failed, using stale cache")
            Ctx.Boot.cacheHits = Ctx.Boot.cacheHits + 1
        else
            Ctx.Boot.fetch[name] = Ctx.Boot.fetch[name] or 0
            return nil, "fetch-fail", err or "no-source"
        end
    else
        Ctx.Boot.cacheHits = Ctx.Boot.cacheHits + 1
    end

    -- 3. Compile
    mark("compile:" .. name)
    local tCompile = now()
    local fn, compileErr = loadstring(src, "@" .. name .. ".lua")
    Ctx.Boot.compile[name] = (now() - tCompile) * 1000
    src = nil  -- release source

    if not fn then
        cacheDelete(name)
        return nil, "compile-fail", tostring(compileErr)
    end

    -- 4. Execute
    mark("execute:" .. name)
    local tExec = now()
    local ok, mod = pcall(fn)
    Ctx.Boot.execute[name] = (now() - tExec) * 1000
    fn = nil  -- release closure

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
mark("boot:announce")
print("================================================")
print(string.format("  Dingus-Slayer · boot v32 · id=%s", bootId))
print(string.format("  modules=%d · cdns=%d · cache=%s",
    #MANIFEST, #CDNS, USE_CACHE and "on" or "off"))
print("================================================")

local t0 = now()
local loadedCount = 0
local mainMod = nil

--============================================================
-- LOAD LOOP · strictly sequential
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

    -- Full-frame yield between modules. Critical for Xeno stability.
    if YIELD_BETWEEN then
        task.wait()
    else
        task.wait(0.03)
    end
end

--============================================================
-- BOOT MAIN
--============================================================
mark("boot:main")
local bootOk = false

if mainMod and type(mainMod.boot) == "function" then
    local tBoot = now()
    local ok, err = pcall(mainMod.boot, Ctx)
    if ok then
        bootOk = true
        log("info", string.format("  + main.boot · %.0fms",
            (now() - tBoot) * 1000))
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
mark("boot:post")
if not bootOk then
    if Ctx.Fly and type(Ctx.Fly.init) == "function"
       and type(Ctx.Fly.tick) ~= "function" then
        pcall(Ctx.Fly.init, Ctx)
    end
end

--============================================================
-- SUMMARY
--============================================================
mark("boot:summary")
local elapsed = now() - t0

print("================================================")
print(string.format("  boot %s in %.2fs · %d/%d modules",
    bootOk and "complete" or "incomplete", elapsed, loadedCount, #MANIFEST))

-- Slowest fetch
local slowest, slowestMs = nil, 0
for name, ms in pairs(Ctx.Boot.fetch) do
    if ms > slowestMs then slowest = name; slowestMs = ms end
end
if slowest then
    print(string.format("  slowest fetch: %s · %.0fms · source=%s",
        slowest, slowestMs, Ctx.Boot.cdnUsed[slowest] or "cache"))
end

-- Aggregate timing
local compileTotal, executeTotal = 0, 0
for _, ms in pairs(Ctx.Boot.compile) do compileTotal = compileTotal + ms end
for _, ms in pairs(Ctx.Boot.execute) do executeTotal = executeTotal + ms end
print(string.format("  compile total: %.0fms · execute total: %.0fms",
    compileTotal, executeTotal))
print(string.format("  cache: %d hits · %d misses",
    Ctx.Boot.cacheHits, Ctx.Boot.cacheMiss))

if #Ctx.Errors > 0 then
    print(string.format("  errors (%d):", #Ctx.Errors))
    for _, e in ipairs(Ctx.Errors) do
        print(string.format("    [%s] %s%s",
            e.stage, e.msg,
            e.detail and (" — " .. tostring(e.detail)) or ""))
    end
end

if #Ctx.Warnings > 0 then
    print(string.format("  warnings (%d):", #Ctx.Warnings))
    for _, w in ipairs(Ctx.Warnings) do
        print(string.format("    [%s] %s", w.stage, w.msg))
    end
end

print("================================================")

--============================================================
-- EXPOSE _G · individual guarded writes
--============================================================
mark("boot:expose")
pcall(function() _G.Ctx = Ctx end)
pcall(function() _G.St = Ctx.St end)

local EXPOSE = {
    "Cfg", "Lists", "Util", "Detect", "Scan", "Hotbar",
    "Spoof", "Chest", "Quest", "Atk", "Opt", "Gui",
}
for i = 1, #EXPOSE do
    local key = EXPOSE[i]
    local val = Ctx[key]
    if val ~= nil then
        pcall(function() _G[key] = val end)
    end
end

pcall(function()
    _G.DINGUS_BOOT = {
        id = bootId, elapsed = elapsed, ok = bootOk,
        loaded = loadedCount, total = #MANIFEST,
        errors = #Ctx.Errors, warnings = #Ctx.Warnings,
    }
end)

--============================================================
-- NOTIFICATION
--============================================================
mark("boot:notify")
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Dingus-Slayer",
        Text = string.format("%s · %.1fs · %d errors",
            bootOk and "loaded" or "incomplete",
            elapsed, #Ctx.Errors),
        Duration = 5,
    })
end)

mark("boot:complete")
