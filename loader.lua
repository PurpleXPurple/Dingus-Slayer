-- Dingus-Slayer · loader.lua v35
-- Cross-device: request() when available, HttpGet otherwise.
-- File cache works when writefile exists, else every boot fetches.

local VERSION = "v35"
local REPO_USER = "PurpleXPurple"
local REPO_NAME = "Dingus-Slayer"
local REPO_BRANCH = "main"

local CACHE_DIR = "Dingus/cache"
local CACHE_TTL = 3600
local MAX_RETRY = 2
local RETRY_MS = 500
local MIN_SRC = 32

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

local HTTP_HEADERS = {
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    ["Accept"] = "text/plain,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["Accept-Language"] = "en-US,en;q=0.9",
    ["Cache-Control"] = "no-cache",
    ["Pragma"] = "no-cache",
    ["Connection"] = "keep-alive",
}

local CDNS = {
    { label = "github", url = function(n)
        return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s.lua", REPO_USER, REPO_NAME, REPO_BRANCH, n)
    end },
    { label = "jsdelivr", url = function(n)
        return string.format("https://cdn.jsdelivr.net/gh/%s/%s@%s/%s.lua", REPO_USER, REPO_NAME, REPO_BRANCH, n)
    end },
    { label = "statically", url = function(n)
        return string.format("https://cdn.statically.io/gh/%s/%s/%s/%s.lua", REPO_USER, REPO_NAME, REPO_BRANCH, n)
    end },
}

-- Probe executor primitives
local function probe(name)
    if type(_G[name]) == "function" then return _G[name] end
    local ok, v = pcall(function() return getfenv()[name] end)
    return (ok and type(v) == "function") and v or nil
end

local REQUEST = probe("request") or probe("http_request")
if not REQUEST and type(syn) == "table" and type(syn.request) == "function" then REQUEST = syn.request end
if not REQUEST and type(http) == "table" and type(http.request) == "function" then REQUEST = http.request end

local HTTPGET = nil
do
    if type(game.HttpGet) == "function" then
        HTTPGET = function(url) return game:HttpGet(url, true) end
    elseif type(game.GetAsync) == "function" then
        HTTPGET = function(url) return game:GetAsync(url) end
    end
end

local F = {
    write = probe("writefile"),
    read = probe("readfile"),
    exists = probe("isfile"),
    delete = probe("delfile"),
    mkdir = probe("makefolder"),
}

local HTTP_MODE = REQUEST and "request" or (HTTPGET and "HttpGet" or "none")

local BOOT_ID = string.format("%04x", math.random(0, 0xFFFF))
local BOOT_START = os.clock()

local Ctx = {
    St = {}, Errors = {}, Warnings = {}, Loaded = {},
    BootId = BOOT_ID, StartTime = BOOT_START,
    Boot = { fetch={}, compile={}, execute={}, cdnUsed={}, cacheHits=0, cacheMiss=0, cacheStale=0 },
}

local function mark(s) print("[Dingus][trace] " .. s) end
local function log(l, m) print("[Dingus][" .. l .. "] " .. m) end
local function realtime() return os.time() end
local function now() return os.clock() end

-- Cache
if F.mkdir then pcall(F.mkdir, CACHE_DIR) end
local function cPath(n) return CACHE_DIR .. "/" .. n .. ".lua" end
local function cMeta(n) return CACHE_DIR .. "/" .. n .. ".meta" end

local function cRead(name)
    if not F.read then return nil, 0, nil end
    local ok, src = pcall(F.read, cPath(name))
    if not ok or type(src) ~= "string" or #src < MIN_SRC then return nil, 0, nil end
    local age, etag = 0, nil
    local okM, meta = pcall(F.read, cMeta(name))
    if okM and type(meta) == "string" then
        local ts = tonumber(meta:match("^(%d+)"))
        if ts then age = realtime() - ts end
        local e = meta:match("\n(.+)")
        if e and #e > 0 then etag = e end
    end
    return src, age, etag
end

local function cWrite(name, src, etag)
    if not F.write then return end
    pcall(F.write, cPath(name), src)
    local meta = tostring(realtime())
    if etag then meta = meta .. "\n" .. etag end
    pcall(F.write, cMeta(name), meta)
end

local function cDelete(name)
    if not F.delete then return end
    pcall(F.delete, cPath(name))
    pcall(F.delete, cMeta(name))
end

-- HTTP
local function httpGet(url, etag)
    if REQUEST then
        local headers = {}
        for k, v in pairs(HTTP_HEADERS) do headers[k] = v end
        if etag then headers["If-None-Match"] = etag end
        local ok, res = pcall(REQUEST, { Url = url, Method = "GET", Headers = headers })
        if ok and type(res) == "table" then
            local status = res.StatusCode or res.Status or res.status
            local body = res.Body or res.body
            local rh = res.Headers or res.headers or {}
            local newEtag = rh["etag"] or rh["ETag"] or rh["Etag"]
            if status == 304 then return nil, nil, "not-modified" end
            if status and status >= 200 and status < 300 and type(body) == "string" and #body >= MIN_SRC then
                if body:find("404: Not Found", 1, true) then return nil, nil, "404" end
                return body, newEtag, nil
            end
            return nil, nil, "status-" .. tostring(status)
        end
    end
    if HTTPGET then
        local bust = url .. (url:find("?", 1, true) and "&" or "?") .. "t=" .. realtime()
        local ok, body = pcall(HTTPGET, bust)
        if ok and type(body) == "string" and #body >= MIN_SRC then
            if body:find("404: Not Found", 1, true) then return nil, nil, "404" end
            return body, nil, nil
        end
        return nil, nil, "http-fail"
    end
    return nil, nil, "no-http"
end

local function fetchFromCDNs(name, cachedEtag)
    local t0 = now()
    local lastErr
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
    return nil, nil, lastErr or "all-fail"
end

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
            source = cdn
            Ctx.Boot.cacheHits = Ctx.Boot.cacheHits + 1
        elseif src then
            source = "stale"
            Ctx.Boot.cacheStale = Ctx.Boot.cacheStale + 1
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
    if not fn then cDelete(name); return nil, "compile-fail", tostring(cerr), fetchMs end

    mark("execute:" .. name)
    local te = now()
    local ok, mod = pcall(fn)
    Ctx.Boot.execute[name] = (now() - te) * 1000
    fn = nil
    if not ok then cDelete(name); return nil, "runtime-fail", tostring(mod), fetchMs end
    if mod == nil then cDelete(name); return nil, "returns-nil", "missing return", fetchMs end
    if type(mod) ~= "table" then cDelete(name); return nil, "wrong-type", type(mod), fetchMs end
    return mod, nil, nil, fetchMs, source
end

-- Banner
print("")
print(string.rep("─", 62))
print("  DINGUS-SLAYER · loader " .. VERSION)
print(string.format("  session %s · %s · branch=%s", BOOT_ID, os.date("%Y-%m-%d %H:%M:%S"), REPO_BRANCH))
print(string.format("  modules=%d · cdn-chain=%d · cache=%s · http=%s", #MANIFEST, #CDNS, F.write and "on" or "off", HTTP_MODE))
print(string.rep("─", 62))

-- Phase 1 · load
print("")
print("----- PHASE 1/4 · LOAD ----------------------------------------")
local t0 = now()
local loaded = 0
local mainMod = nil

for i = 1, #MANIFEST do
    local entry = MANIFEST[i]
    local name = entry.name
    local mod, errK, errD, fetchMs, source = loadModule(entry)
    if not mod then
        print(string.format("  ✗ %-12s %-12s %5dms  fail  %s · %s",
            name, "—", fetchMs or 0, tostring(errK), tostring(errD)))
        table.insert(Ctx.Errors, { stage = name, msg = tostring(errK), detail = errD })
    else
        loaded = loaded + 1
        Ctx.Loaded[name] = true
        local cacheStatus = "miss"
        if source == "cache" then cacheStatus = "hit"
        elseif source == "stale" then cacheStatus = "stale"
        elseif source and source:find("/304", 1, true) then cacheStatus = "304" end
        print(string.format("  ✓ %-12s %-12s %5dms  %s",
            name, source or "?", math.floor(fetchMs or 0), cacheStatus))
        if name == "main" then mainMod = mod
        else
            if entry.slots then
                for _, key in ipairs(entry.slots) do Ctx[key] = mod end
            end
        end
    end
    task.wait()
end

-- Phase 2 · boot
print("")
print("----- PHASE 2/4 · BOOT ----------------------------------------")
local bootOk = false
if mainMod and type(mainMod.boot) == "function" then
    local tb = now()
    local ok, err = pcall(mainMod.boot, Ctx)
    if ok then bootOk = true; print(string.format("  ✓ main.boot · %.0fms", (now() - tb) * 1000))
    else print(string.format("  ✗ main.boot raised: %s", tostring(err)))
        table.insert(Ctx.Errors, { stage = "main.boot", msg = "runtime", detail = tostring(err) }) end
elseif not mainMod then
    print("  ✗ main never loaded")
else
    print("  ✗ main.boot is not a function")
end

-- Phase 3 · expose
print("")
print("----- PHASE 3/4 · EXPOSE --------------------------------------")
pcall(function() _G.Ctx = Ctx end)
pcall(function() _G.St = Ctx.St end)
for _, k in ipairs({"Cfg","Lists","Util","Detect","Scan","Hotbar","Spoof","Chest","Quest","Atk","Opt","Gui"}) do
    if Ctx[k] then pcall(function() _G[k] = Ctx[k] end) end
end
pcall(function()
    _G.DINGUS_BOOT = {
        id = BOOT_ID, version = VERSION, elapsed = now() - t0,
        ok = bootOk, loaded = loaded, total = #MANIFEST,
        errors = #Ctx.Errors, warnings = #Ctx.Warnings,
        platform = Ctx.Util and Ctx.Util.Platform or "?",
        executor = Ctx.Util and Ctx.Util.Executor or "?",
    }
end)

-- Phase 4 · notify
print("")
print("----- PHASE 4/4 · NOTIFY --------------------------------------")
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Dingus-Slayer",
        Text = string.format("%s · %.1fs · %d errors",
            bootOk and "loaded" or "incomplete", now() - t0, #Ctx.Errors),
        Duration = 5,
    })
end)

-- Summary
print("")
print(string.rep("─", 62))
print(string.format("  RESULT · %s in %.2fs", bootOk and "complete" or "incomplete", now() - t0))
print(string.format("  %d/%d modules · %d errors · %d warnings", loaded, #MANIFEST, #Ctx.Errors, #Ctx.Warnings))

local fSum = 0
for _, ms in pairs(Ctx.Boot.fetch) do fSum = fSum + ms end
local cSum, eSum = 0, 0
for _, ms in pairs(Ctx.Boot.compile) do cSum = cSum + ms end
for _, ms in pairs(Ctx.Boot.execute) do eSum = eSum + ms end
print(string.format("  fetch: %.0fms · compile: %.0fms · execute: %.0fms", fSum, cSum, eSum))
print(string.format("  cache: %d hits · %d misses · %d stale",
    Ctx.Boot.cacheHits, Ctx.Boot.cacheMiss, Ctx.Boot.cacheStale))

if #Ctx.Errors > 0 then
    print("")
    print(string.format("  errors (%d):", #Ctx.Errors))
    for _, e in ipairs(Ctx.Errors) do
        print(string.format("    [%s] %s%s", e.stage, e.msg, e.detail and (" — " .. tostring(e.detail)) or ""))
    end
end

print(string.rep("─", 62))
mark("complete")
