-- ═══════════════════════════════════════════════════════════════════════
--   DINGUS-SLAYER · loader.lua v34
--   Smarter HTTP headers · ETag conditional requests · structured boot log
-- ═══════════════════════════════════════════════════════════════════════

local VERSION   = "v34"
local REPO_USER = "PurpleXPurple"
local REPO_NAME = "Dingus-Slayer"
local REPO_BRANCH = "main"

local CACHE_DIR = "Dingus/cache"
local CACHE_TTL = 3600
local MAX_RETRY = 2
local RETRY_MS  = 500
local MIN_SRC   = 32

-- ═══════════════════════════════════════════════════════════════════════
-- MANIFEST · dependencies in order. Do not reorder.
-- ═══════════════════════════════════════════════════════════════════════
local MANIFEST = {
    -- core (no deps)
    { name = "config",     slots = { "Cfg", "Config" } },
    { name = "lists",      slots = { "Lists" } },
    { name = "utils",      slots = { "Util", "Utils", "U" } },
    -- subsystems
    { name = "detect",     slots = { "Detect", "D" } },
    { name = "scanners",   slots = { "Scan", "Scanner", "Scanners" } },
    { name = "hotbar",     slots = { "Hotbar", "HB" } },
    { name = "spoofers",   slots = { "Spoof", "Spoofer", "Spoofers" } },
    { name = "chest",      slots = { "Chest" } },
    { name = "quests",     slots = { "Quest", "Quests", "Q" } },
    { name = "attack",     slots = { "Atk", "Attack" } },
    { name = "optimizers", slots = { "Opt", "Optimizer", "Optimizers" } },
    { name = "gui",        slots = { "Gui", "GUI" } },
    -- entrypoint
    { name = "main",       slots = nil },
}

-- ═══════════════════════════════════════════════════════════════════════
-- HTTP HEADERS · sent when request() is available
-- ═══════════════════════════════════════════════════════════════════════
-- Mimics a browser fetching a text file. Reduces executor fingerprint
-- at the CDN edge and unlocks conditional requests (ETag / 304).
local HTTP_HEADERS = {
    ["User-Agent"]      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " ..
                          "AppleWebKit/537.36 (KHTML, like Gecko) " ..
                          "Chrome/120.0.0.0 Safari/537.36",
    ["Accept"]          = "text/plain,text/html,application/xhtml+xml," ..
                          "application/xml;q=0.9,*/*;q=0.8",
    ["Accept-Language"] = "en-US,en;q=0.9",
    ["Accept-Encoding"] = "identity",
    ["Cache-Control"]   = "no-cache",
    ["Pragma"]          = "no-cache",
    ["Connection"]      = "keep-alive",
}

-- ═══════════════════════════════════════════════════════════════════════
-- CDN CHAIN
-- ═══════════════════════════════════════════════════════════════════════
local CDNS = {
    {
        label = "github",
        url = function(n)
            return string.format(
                "https://raw.githubusercontent.com/%s/%s/%s/%s.lua",
                REPO_USER, REPO_NAME, REPO_BRANCH, n)
        end,
    },
    {
        label = "jsdelivr",
        url = function(n)
            return string.format(
                "https://cdn.jsdelivr.net/gh/%s/%s@%s/%s.lua",
                REPO_USER, REPO_NAME, REPO_BRANCH, n)
        end,
    },
    {
        label = "statically",
        url = function(n)
            return string.format(
                "https://cdn.statically.io/gh/%s/%s/%s/%s.lua",
                REPO_USER, REPO_NAME, REPO_BRANCH, n)
        end,
    },
}

-- ═══════════════════════════════════════════════════════════════════════
-- CAPABILITY PROBE
-- ═══════════════════════════════════════════════════════════════════════
local HAS = {
    writefile  = type(writefile)  == "function",
    readfile   = type(readfile)   == "function",
    delfile    = type(delfile)    == "function",
    makefolder = type(makefolder) == "function",
}

-- request() detection — Synapse/Krnl/Fluxus/Xeno and friends
local REQUEST_FN = nil
do
    if type(request) == "function" then
        REQUEST_FN = request
    elseif type(syn) == "table" and type(syn.request) == "function" then
        REQUEST_FN = syn.request
    elseif type(http) == "table" and type(http.request) == "function" then
        REQUEST_FN = http.request
    elseif type(http_request) == "function" then
        REQUEST_FN = http_request
    end
end

-- HttpGet fallback chain
local HTTPGET_FN = nil
do
    if type(game.HttpGet) == "function" then
        HTTPGET_FN = function(url) return game:HttpGet(url, true) end
    elseif type(game.HttpGetAsync) == "function" then
        HTTPGET_FN = function(url) return game:HttpGetAsync(url, true) end
    elseif type(game.GetAsync) == "function" then
        HTTPGET_FN = function(url) return game:GetAsync(url) end
    end
end

local HTTP_MODE = REQUEST_FN and "request()" or (HTTPGET_FN and "HttpGet" or "none")

-- ═══════════════════════════════════════════════════════════════════════
-- BOOT ID
-- ═══════════════════════════════════════════════════════════════════════
local BOOT_ID = string.format("%04x", math.random(0, 0xFFFF))
local BOOT_START = os.clock()

-- ═══════════════════════════════════════════════════════════════════════
-- CONTEXT
-- ═══════════════════════════════════════════════════════════════════════
local Ctx = {
    St        = {},
    Errors    = {},
    Warnings  = {},
    Loaded    = {},
    BootId    = BOOT_ID,
    StartTime = BOOT_START,
    Boot      = {
        fetch = {}, compile = {}, execute = {},
        cdnUsed = {}, cacheHits = 0, cacheMiss = 0, cacheStale = 0,
    },
}

-- ═══════════════════════════════════════════════════════════════════════
-- LOGGING
-- ═══════════════════════════════════════════════════════════════════════
local trace = "boot:start"
local function mark(s)
    trace = s
    print("[Dingus][trace] " .. s)
end

local function log(level, msg)
    local p = "[Dingus][" .. level .. "]"
    if level == "err" then warn(p .. " " .. msg)
    else print(p .. " " .. msg) end
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

-- ═══════════════════════════════════════════════════════════════════════
-- CACHE · stores { timestamp, etag, source }
-- ═══════════════════════════════════════════════════════════════════════
if HAS.makefolder then pcall(makefolder, CACHE_DIR) end

local function cPath(n)  return CACHE_DIR .. "/" .. n .. ".lua" end
local function cMeta(n)  return CACHE_DIR .. "/" .. n .. ".meta" end

local function cRead(name)
    if not HAS.readfile then return nil, 0, nil end
    local ok, src = pcall(readfile, cPath(name))
    if not ok or type(src) ~= "string" or #src < MIN_SRC then return nil, 0, nil end
    local age, etag = 0, nil
    local okM, meta = pcall(readfile, cMeta(name))
    if okM and type(meta) == "string" then
        local ts = tonumber(meta:match("^(%d+)"))
        if ts then age = realtime() - ts end
        local e = meta:match("\n(.+)")
        if e and #e > 0 then etag = e end
    end
    return src, age, etag
end

local function cWrite(name, src, etag)
    if not HAS.writefile then return end
    pcall(writefile, cPath(name), src)
    local meta = tostring(realtime())
    if etag then meta = meta .. "\n" .. etag end
    pcall(writefile, cMeta(name), meta)
end

local function cDelete(name)
    if not HAS.delfile then return end
    pcall(delfile, cPath(name))
    pcall(delfile, cMeta(name))
end

-- ═══════════════════════════════════════════════════════════════════════
-- HTTP · with headers when request() is available
-- ═══════════════════════════════════════════════════════════════════════
local function httpGet(url, etag)
    if REQUEST_FN then
        local headers = {}
        for k, v in pairs(HTTP_HEADERS) do headers[k] = v end
        if etag then headers["If-None-Match"] = etag end

        local ok, res = pcall(REQUEST_FN, {
            Url = url,
            Method = "GET",
            Headers = headers,
        })
        if ok and type(res) == "table" then
            local status = res.StatusCode or res.Status or res.status
            local body = res.Body or res.body
            local rHeaders = res.Headers or res.headers or {}
            local newEtag = rHeaders["etag"] or rHeaders["ETag"] or
                            rHeaders["Etag"]
            -- 304 = not modified, use cached
            if status == 304 then
                return nil, nil, "not-modified"
            end
            if status and status >= 200 and status < 300
               and type(body) == "string" and #body >= MIN_SRC then
                if body:find("404: Not Found", 1, true) then
                    return nil, nil, "404"
                end
                return body, newEtag, nil
            end
            return nil, nil, "status-" .. tostring(status)
        end
        -- request() failed → fall through to HttpGet
    end

    if HTTPGET_FN then
        -- Cache-bust since HttpGet can't send headers
        local bust = url .. (url:find("?", 1, true) and "&" or "?") ..
                     "t=" .. realtime()
        local ok, body = pcall(HTTPGET_FN, bust)
        if ok and type(body) == "string" and #body >= MIN_SRC then
            if body:find("404: Not Found", 1, true) then
                return nil, nil, "404"
            end
            return body, nil, nil
        end
        return nil, nil, "http-fail"
    end

    return nil, nil, "no-http-method"
end

-- ═══════════════════════════════════════════════════════════════════════
-- FETCH · tries each CDN in order with retries
-- ═══════════════════════════════════════════════════════════════════════
local function fetchFromCDNs(name, cachedEtag)
    local t0 = now()
    local lastErr = nil

    for _, cdn in ipairs(CDNS) do
        local url = cdn.url(name)
        for attempt = 1, MAX_RETRY do
            local body, newEtag, err = httpGet(url, cachedEtag)
            if body then
                Ctx.Boot.cdnUsed[name] = cdn.label
                Ctx.Boot.fetch[name] = (now() - t0) * 1000
                return body, cdn.label, newEtag
            elseif err == "not-modified" then
                Ctx.Boot.cdnUsed[name] = cdn.label .. "/304"
                Ctx.Boot.fetch[name] = (now() - t0) * 1000
                return nil, cdn.label .. "/304", cachedEtag
            end
            lastErr = err
            if attempt < MAX_RETRY then task.wait(RETRY_MS / 1000) end
        end
    end

    Ctx.Boot.fetch[name] = (now() - t0) * 1000
    return nil, nil, lastErr or "all-cdns-failed"
end

-- ═══════════════════════════════════════════════════════════════════════
-- LOAD ONE MODULE
-- ═══════════════════════════════════════════════════════════════════════
local function loadModule(entry)
    local name = entry.name
    local src, age, cachedEtag = cRead(name)
    local source = "cache"
    local fetchMs = 0

    if not src or age >= CACHE_TTL then
        mark("fetch:" .. name)
        local body, cdn, newEtag = fetchFromCDNs(name, cachedEtag)
        fetchMs = Ctx.Boot.fetch[name] or 0

        if body then
            src = body
            source = cdn or "http"
            Ctx.Boot.cacheMiss = Ctx.Boot.cacheMiss + 1
            cWrite(name, src, newEtag)
        elseif cdn and cdn:find("/304", 1, true) then
            -- conditional request said not-modified, use cache
            source = cdn
            Ctx.Boot.cacheHits = Ctx.Boot.cacheHits + 1
        elseif src then
            source = "stale"
            Ctx.Boot.cacheStale = Ctx.Boot.cacheStale + 1
            recordWarn(name, "http failed, using stale cache")
        else
            return nil, "fetch-fail", tostring(cdn or "no-source"), fetchMs
        end
    else
        Ctx.Boot.cacheHits = Ctx.Boot.cacheHits + 1
    end

    mark("compile:" .. name)
    local tc = now()
    local fn, cerr = loadstring(src, "@" .. name .. ".lua")
    Ctx.Boot.compile[name] = (now() - tc) * 1000
    src = nil

    if not fn then
        cDelete(name)
        return nil, "compile-fail", tostring(cerr), fetchMs
    end

    mark("execute:" .. name)
    local te = now()
    local ok, mod = pcall(fn)
    Ctx.Boot.execute[name] = (now() - te) * 1000
    fn = nil

    if not ok then
        cDelete(name); return nil, "runtime-fail", tostring(mod), fetchMs
    end
    if mod == nil then
        cDelete(name); return nil, "returns-nil", "missing 'return'", fetchMs
    end
    if type(mod) ~= "table" then
        cDelete(name); return nil, "wrong-type", type(mod), fetchMs
    end

    return mod, nil, nil, fetchMs, source
end

-- ═══════════════════════════════════════════════════════════════════════
-- DISPLAY
-- ═══════════════════════════════════════════════════════════════════════
local LINE = string.rep("─", 62)

local function banner()
    print("")
    print(LINE)
    print("  DINGUS-SLAYER · boot-loader " .. VERSION)
    print(string.format("  session %s · %s · branch=%s",
        BOOT_ID, os.date("%Y-%m-%d %H:%M:%S"), REPO_BRANCH))
    print(string.format("  modules=%d · cdn-chain=%d · cache=%s · http=%s",
        #MANIFEST, #CDNS,
        HAS.writefile and "on" or "off", HTTP_MODE))
    print(LINE)
end

local function phaseHeader(n, label)
    print("")
    print(string.format("----- PHASE %d/4 · %s %s",
        n, label:upper(), string.rep("-", 40 - #label)))
end

local function moduleRow(icon, name, source, ms, cacheStatus, note)
    print(string.format("  %s %-12s %-12s %5dms  %-6s %s",
        icon,
        name,
        source or "—",
        math.floor(ms or 0),
        cacheStatus or "",
        note or ""))
end

local function summaryHeader()
    print("")
    print(LINE)
end

-- ═══════════════════════════════════════════════════════════════════════
-- RUN
-- ═══════════════════════════════════════════════════════════════════════
banner()

-- ─── PHASE 1 · FETCH + COMPILE + EXECUTE ───────────────────────────────
phaseHeader(1, "load")

local t0 = now()
local loaded = 0
local mainMod = nil
local rows = {}

for i = 1, #MANIFEST do
    local entry = MANIFEST[i]
    local name = entry.name

    local mod, errK, errD, fetchMs, source = loadModule(entry)

    if not mod then
        moduleRow("✗", name, "—", fetchMs or 0, "fail",
            (errK or "?") .. " · " .. (errD or "?"))
        recordErr(name, tostring(errK), errD)
        Ctx.Loaded[name] = false
        rows[#rows + 1] = { name = name, ok = false, source = "—",
            ms = fetchMs or 0, cache = "fail", note = errK }
    else
        loaded = loaded + 1
        Ctx.Loaded[name] = true

        local cacheStatus = "miss"
        if source == "cache" then cacheStatus = "hit"
        elseif source == "stale" then cacheStatus = "stale"
        elseif source and source:find("/304", 1, true) then cacheStatus = "304"
        end

        local icon = "✓"
        if source == "cache" then icon = "·"
        elseif source == "stale" then icon = "★"
        elseif source and source:find("/304", 1, true) then icon = "◆"
        end

        if name == "main" then
            mainMod = mod
            if type(mod.boot) ~= "function" then
                recordWarn("main", "missing .boot")
                moduleRow("⚠", name, source or "?", fetchMs or 0,
                    cacheStatus, "no .boot fn")
            else
                moduleRow(icon, name, source or "?", fetchMs or 0,
                    cacheStatus, "boot fn present")
            end
        else
            if entry.slots then
                for _, key in ipairs(entry.slots) do
                    Ctx[key] = mod
                end
            end
            moduleRow(icon, name, source or "?", fetchMs or 0, cacheStatus)
        end
    end

    task.wait()
end

-- ─── PHASE 2 · BOOT ────────────────────────────────────────────────────
phaseHeader(2, "boot")

local bootOk = false
if mainMod and type(mainMod.boot) == "function" then
    local tb = now()
    local ok, err = pcall(mainMod.boot, Ctx)
    if ok then
        bootOk = true
        print(string.format("  ✓ main.boot · %.0fms", (now() - tb) * 1000))
    else
        print(string.format("  ✗ main.boot raised: %s", tostring(err)))
        recordErr("main.boot", "runtime", tostring(err))
    end
elseif not mainMod then
    print("  ✗ main module never loaded")
    recordErr("main", "not-loaded", nil)
else
    print("  ✗ main.boot is not a function")
    recordErr("main", "no-boot-fn", nil)
end

-- ─── PHASE 3 · EXPOSE ──────────────────────────────────────────────────
phaseHeader(3, "expose")

pcall(function() _G.Ctx = Ctx end)
pcall(function() _G.St  = Ctx.St end)

local EXPOSE = {
    "Cfg", "Lists", "Util", "Detect", "Scan", "Hotbar",
    "Spoof", "Chest", "Quest", "Atk", "Opt", "Gui",
}
for i = 1, #EXPOSE do
    local key = EXPOSE[i]
    if Ctx[key] then pcall(function() _G[key] = Ctx[key] end) end
end

pcall(function()
    _G.DINGUS_BOOT = {
        id = BOOT_ID, version = VERSION, elapsed = now() - t0,
        ok = bootOk, loaded = loaded, total = #MANIFEST,
        errors = #Ctx.Errors, warnings = #Ctx.Warnings,
    }
end)

-- ─── PHASE 4 · NOTIFY ──────────────────────────────────────────────────
phaseHeader(4, "notify")
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Dingus-Slayer",
        Text = string.format("%s · %.1fs · %d errors",
            bootOk and "loaded" or "incomplete",
            now() - t0, #Ctx.Errors),
        Duration = 5,
    })
end)

-- ─── SUMMARY ───────────────────────────────────────────────────────────
summaryHeader()
print(string.format("  RESULT · %s in %.2fs",
    bootOk and "complete" or "incomplete", now() - t0))
print(string.format("  %d/%d modules · %d errors · %d warnings",
    loaded, #MANIFEST, #Ctx.Errors, #Ctx.Warnings))

-- aggregate timing
local fMax = 0
for _, ms in pairs(Ctx.Boot.fetch) do if ms > fMax then fMax = ms end end
local fSum = 0
for _, ms in pairs(Ctx.Boot.fetch) do fSum = fSum + ms end
local cSum, eSum = 0, 0
for _, ms in pairs(Ctx.Boot.compile) do cSum = cSum + ms end
for _, ms in pairs(Ctx.Boot.execute) do eSum = eSum + ms end

print(string.format(
    "  fetch: %.0fms wall (max %.0f) · compile: %.0fms · execute: %.0fms",
    fSum, fMax, cSum, eSum))

-- slowest fetch name
local slowName, slowMs = nil, 0
for name, ms in pairs(Ctx.Boot.fetch) do
    if ms > slowMs then slowName, slowMs = name, ms end
end
if slowName and slowMs > 100 then
    print(string.format("  slowest: %s · %.0fms · %s",
        slowName, slowMs, Ctx.Boot.cdnUsed[slowName] or "cache"))
end

print(string.format("  cache: %d hits · %d misses · %d stale",
    Ctx.Boot.cacheHits, Ctx.Boot.cacheMiss, Ctx.Boot.cacheStale))

if #Ctx.Errors > 0 then
    print("")
    print(string.format("  errors (%d):", #Ctx.Errors))
    for _, e in ipairs(Ctx.Errors) do
        print(string.format("    [%s] %s%s",
            e.stage, e.msg,
            e.detail and (" — " .. tostring(e.detail)) or ""))
    end
end

if #Ctx.Warnings > 0 then
    print("")
    print(string.format("  warnings (%d):", #Ctx.Warnings))
    for _, w in ipairs(Ctx.Warnings) do
        print(string.format("    [%s] %s", w.stage, w.msg))
    end
end

print(LINE)
mark("complete")
