--[[
    Dingus-Slayer · loader.lua v31
    Multi-CDN fallback · persistent disk cache · concurrency-limited fetch.
    Breadcrumb crash tracing. Sequential compile/execute for memory safety.

    Key improvements over v30:
      - 3 CDN sources per module (github → jsdelivr → statically)
      - Cache-first: warm boots skip HTTP entirely for fresh modules
      - Stale-cache fallback if all CDNs fail
      - Worker-pool fetch: 2 concurrent, yields between ops
      - Per-module timing surfaced in boot summary
      - Breadcrumb trace (mark()) survives crashes
      - Source released after compile (memory spike prevention)
]]--

--============================================================
-- CONFIG
--============================================================
local REPO_USER   = "PurpleXPurple"
local REPO_NAME   = "Dingus-Slayer"
local REPO_BRANCH = "main"

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

local CONCURRENCY    = 2
local MAX_RETRY      = 2
local RETRY_DELAY    = 0.5
local MIN_SOURCE     = 32
local CACHE_DIR      = "Dingus/cache"
local CACHE_TTL      = 3600       -- fresh if < 1 hour old
local TRACE_ENABLED  = true

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
        fetch = {}, compile = {}, execute = {},
        cdnUsed = {}, cacheHits = 0, cacheMiss = 0,
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
if HAS.makefolder then pcall(makefolder, CACHE_DIR) end

local function cachePath(n) return CACHE_DIR .. "/" .. n .. ".lua" end
local function cacheMeta(n) return CACHE_DIR .. "/" .. n .. ".meta" end

local function cacheRead(name)
    if not HAS.readfile then return nil, 0 end
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
    if not HAS.writefile then return end
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
-- HTTP · module fetch (multi-CDN, retries)
--============================================================
local function fetchModule(name)
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
            if attempt < MAX_RETRY then task.wait(RETRY_DELAY) end
        end
    end
    Ctx.Boot.fetch[name] = (now() - t0) * 1000
    return nil, lastErr or "all-cdns-failed"
end

--============================================================
-- WORKER POOL · fetch
-- Cache-first fast path. HTTP only on cache miss or stale.
--============================================================
local function parallelFetch()
    local queue = {}
    for i = 1, #MANIFEST do queue[#queue + 1] = MANIFEST[i] end

    local results = {}
    local outstanding = 0
    local idx = 0

    local function runOne(entry)
        local name = entry.name
        outstanding = outstanding + 1
        task.spawn(function()
            -- Cache first
            local cached, age = cacheRead(name)
            if cached and age > 0 and age < CACHE_TTL then
                Ctx.Boot.cacheHits = Ctx.Boot.cacheHits + 1
                results[name] = { src = cached, source = "cache", ms = 0 }
                outstanding = outstanding - 1
                return
            end

            -- Cold fetch
            Ctx.Boot.cacheMiss = Ctx.Boot.cacheMiss + 1
            local src, err, cdn = fetchModule(name)
            if src then
                results[name] = {
                    src = src, source = cdn or "http",
                    ms = Ctx.Boot.fetch[name] or 0,
                }
                cacheWrite(name, src)
            elseif cached then
                results[name] = { src = cached, source = "stale", ms = 0 }
                recordWarn(name, "http failed, using stale cache: " ..
                    tostring(err))
            else
                results[name] = { src = nil, err = err, source = "none" }
            end
            outstanding = outstanding - 1
        end)
    end

    local function pump()
        while outstanding < CONCURRENCY and idx < #queue do
            idx = idx + 1
            runOne(queue[idx])
        end
    end

    pump()
    while outstanding > 0 do
        task.wait(0.03)
        pump()
    end
    task.wait()

    return results
end

--============================================================
-- COMPILE · sequential, memory-safe
--============================================================
local function compileAll(results)
    local out = {}
    for i = 1, #MANIFEST do
        local name = MANIFEST[i].name
        local r = results[name]
        if not r or not r.src then
            out[name] = { fn = nil, err = r and r.err or "no-source" }
        else
            local t0 = now()
            local fn, cerr = loadstring(r.src, "@" .. name .. ".lua")
            Ctx.Boot.compile[name] = (now() - t0) * 1000
            -- Release source before executing
            results[name].src = nil
            if not fn then
                cacheDelete(name)
                out[name] = { fn = nil, err = cerr, source = r.source }
            else
                out[name] = { fn = fn, err = nil, source = r.source }
            end
        end
        task.wait()
    end
    return out
end

--============================================================
-- EXECUTE · sequential
--============================================================
local function executeAll(compiled)
    local mainMod = nil
    local execCount = 0
    for i = 1, #MANIFEST do
        local entry = MANIFEST[i]
        local name = entry.name
        local c = compiled[name]
        if not c or not c.fn then
            log("err", string.format("%s — compile-fail — %s",
                name, tostring(c and c.err or "missing")))
            recordErr(name, "compile-fail", c and c.err or "missing")
            Ctx.Loaded[name] = false
        else
            local t0 = now()
            local ok, mod = pcall(c.fn)
            Ctx.Boot.execute[name] = (now() - t0) * 1000
            if not ok then
                log("err", string.format("%s — runtime-fail — %s",
                    name, tostring(mod)))
                recordErr(name, "runtime-fail", tostring(mod))
                Ctx.Loaded[name] = false
                cacheDelete(name)
            elseif mod == nil then
                recordErr(name, "returns-nil", "missing 'return'")
                log("err", name .. " — returns-nil")
                Ctx.Loaded[name] = false
                cacheDelete(name)
            elseif type(mod) ~= "table" then
                recordErr(name, "wrong-type", type(mod))
                log("err", name .. " — wrong-type " .. type(mod))
                Ctx.Loaded[name] = false
                cacheDelete(name)
            else
                Ctx.Loaded[name] = true
                execCount = execCount + 1
                if name == "main" then
                    mainMod = mod
                else
                    if entry.slots then
                        for _, key in ipairs(entry.slots) do
                            Ctx[key] = mod
                        end
                    end
                    log("info", string.format("  + %-12s · %s",
                        name, c.source or "?"))
                end
            end
        end
        task.wait()
    end
    return mainMod, execCount
end

--============================================================
-- MAIN BOOT
--============================================================
local function bootMain(mainMod)
    if not mainMod or type(mainMod.boot) ~= "function" then
        recordErr("main", "no-boot-fn", nil)
        log("err", "main.boot missing or not a function")
        return false
    end
    local t0 = now()
    local ok, err = pcall(mainMod.boot, Ctx)
    if not ok then
        recordErr("main.boot", "runtime", tostring(err))
        log("err", "main.boot raised — " .. tostring(err))
        return false
    end
    log("info", string.format("  + main.boot · %.0fms", (now() - t0) * 1000))
    return true
end

--============================================================
-- RUN
--============================================================
mark("boot:announce")
print("================================================")
print(string.format("  Dingus-Slayer · boot v31 · id=%s", bootId))
print(string.format("  modules=%d · cdns=%d · conc=%d",
    #MANIFEST, #CDNS, CONCURRENCY))
print("================================================")

local t0 = now()

mark("boot:fetch")
local fetchResults = parallelFetch()
local fetchedCount = 0
for _ in pairs(fetchResults) do fetchedCount = fetchedCount + 1 end
log("info", string.format("fetched %d/%d · cache=%d miss=%d",
    fetchedCount, #MANIFEST, Ctx.Boot.cacheHits, Ctx.Boot.cacheMiss))

mark("boot:compile")
local compiled = compileAll(fetchResults)

mark("boot:execute")
local mainMod, execCount = executeAll(compiled)

mark("boot:main")
local bootOk = bootMain(mainMod)

mark("boot:summary")
local elapsed = now() - t0
print("================================================")
print(string.format("  boot %s in %.2fs · %d/%d modules",
    bootOk and "complete" or "incomplete", elapsed, execCount, #MANIFEST))

-- Per-module CDN + timing line
local slowest, slowestMs = nil, 0
for name, ms in pairs(Ctx.Boot.fetch) do
    if ms > slowestMs then slowest = name; slowestMs = ms end
end
if slowest then
    print(string.format("  slowest fetch: %s · %.0fms · cdn=%s",
        slowest, slowestMs, Ctx.Boot.cdnUsed[slowest] or "cache"))
end

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
-- EXPOSE
--============================================================
mark("boot:expose")
pcall(function() _G.Ctx = Ctx end)
pcall(function() _G.St = Ctx.St end)
for _, key in ipairs({"Cfg", "Lists", "Util", "Detect", "Scan",
                       "Hotbar", "Spoof", "Quest", "Atk", "Opt", "Gui"}) do
    pcall(function()
        if Ctx[key] then _G[key] = Ctx[key] end
    end)
end
_G.DINGUS_BOOT = { id = bootId, elapsed = elapsed, ok = bootOk }

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
