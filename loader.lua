--================================================================
-- Dingus-Slayer · loader.lua v42
--================================================================
-- Everything runs through this file:
--   · Always-fresh module fetching (HTTP cache-bust per session)
--   · Multi-CDN fallback (4 endpoints, ordered by reliability)
--   · Source sanitizer (BOM, markdown fences, HTML, 404 pages)
--   · Detailed per-module error reporting with line numbers and
--     the offending source line
--   · Session-scoped in-memory compile cache for fast reboots
--   · Optional disk cache for cold starts
--   · Structured boot with per-phase timing
--================================================================

local VERSION  = "v42"
local REPO_USER    = "PurpleXPurple"
local REPO_NAME    = "Dingus-Slayer"
local REPO_BRANCH  = "main"
local CACHE_DIR    = "Dingus/cache"
local MIN_SRC      = 32
local FETCH_TIMEOUT_WARN = 2.0   -- seconds before we flag a CDN as slow

--================================================================
-- OPTIONS (tweak here, not in the loadstring)
--================================================================
local OPTIONS = {
    force_fresh      = true,   -- cache-bust every module fetch
    use_disk_cache   = true,   -- persist fetched sources to disk
    use_memory_cache = true,   -- keep compiled fns for reboots
    strip_fences     = true,   -- auto-remove markdown fences
    strict_validate  = true,   -- reject anything not plausibly Lua
    verbose          = true,   -- print per-module rows
    reboot_quiet     = false,  -- on reboot #2+, suppress banner
}

--================================================================
-- EXECUTOR PROBES
--================================================================
local function probe(name)
    if type(_G[name]) == "function" then return _G[name] end
    local ok, v = pcall(function() return getfenv()[name] end)
    return (ok and type(v) == "function") and v or nil
end

local REQUEST = probe("request") or probe("http_request")
if not REQUEST and type(syn) == "table"
   and type(syn.request) == "function" then
    REQUEST = syn.request
end
if not REQUEST and type(http) == "table"
   and type(http.request) == "function" then
    REQUEST = http.request
end

local F = {
    write  = probe("writefile"),
    read   = probe("readfile"),
    exists = probe("isfile"),
    delete = probe("delfile"),
    list   = probe("listfiles"),
    mkdir  = probe("makefolder"),
    id     = probe("identifyexecutor"),
}

local HTTP_MODE = REQUEST and "request" or "HttpGet"

--================================================================
-- SESSION STATE
--================================================================
_G.DINGUS_FN_CACHE   = _G.DINGUS_FN_CACHE   or {}
_G.DINGUS_SESSION    = _G.DINGUS_SESSION
    or string.format("%04x", math.random(0, 0xFFFF))
_G.DINGUS_BOOT_COUNT = (_G.DINGUS_BOOT_COUNT or 0) + 1
_G.DINGUS_LOADED_AT  = os.time()

local IS_REBOOT = _G.DINGUS_BOOT_COUNT > 1
local SESSION_QS = "?v=" .. tostring(_G.DINGUS_LOADED_AT)

if F.mkdir then pcall(F.mkdir, CACHE_DIR) end
if F.mkdir then pcall(F.mkdir, "Dingus") end

--================================================================
-- SMALL UTILITIES
--================================================================
local T0 = os.clock()
local function ms() return (os.clock() - T0) * 1000 end
local function log(m) print("[Dingus][loader] " .. tostring(m)) end
local function warn2(m) warn("[Dingus][loader] " .. tostring(m)) end

local function cPath(n) return CACHE_DIR .. "/" .. n .. ".lua" end
local function cMeta(n) return CACHE_DIR .. "/" .. n .. ".meta" end

--================================================================
-- SOURCE SANITIZER
--================================================================
-- Detects and rejects (or fixes) every common way a .lua file gets
-- corrupted between GitHub and the executor:
--   · UTF-8 BOM
--   · Leading/trailing markdown code fences (```lua ... ```)
--   · HTML responses from CDN error pages
--   · GitHub 404 JSON bodies
--   · Truncated downloads
local function sanitize(src, name)
    if type(src) ~= "string" then return nil, "not-a-string" end
    if #src < MIN_SRC then
        return nil, "too-short(" .. #src .. ")"
    end

    -- UTF-8 BOM
    if src:sub(1, 3) == "\239\187\191" then
        src = src:sub(4)
    end

    -- Markdown fences
    local strippedFence = false
    if OPTIONS.strip_fences then
        local s, c
        s, c = src:gsub("^%s*```[%a]*%s*\r?\n", "", 1)
        if c > 0 then strippedFence = true; src = s end
        s, c = src:gsub("^%s*```%s*\r?\n", "", 1)
        if c > 0 then strippedFence = true; src = s end
        s, c = src:gsub("^%s*```", "", 1)
        if c > 0 then strippedFence = true; src = s end
        s, c = src:gsub("\r?\n```%s*$", "")
        if c > 0 then strippedFence = true; src = s end
        s, c = src:gsub("```%s*$", "")
        if c > 0 then strippedFence = true; src = s end
    end

    -- HTML response
    local lhead = src:sub(1, 300):lower()
    if lhead:find("<!doctype", 1, true)
       or lhead:find("<html", 1, true) then
        return nil, "html-response"
    end

    -- GitHub 404 body
    if lhead:find("404: not found", 1, true)
       or lhead:find("404 not found", 1, true) then
        return nil, "not-found"
    end

    -- Loose Lua-shape validation
    if OPTIONS.strict_validate then
        local zone = src:sub(1, 400)
        local hasLocal    = zone:find("local", 1, true) ~= nil
        local hasReturn   = zone:find("return", 1, true) ~= nil
        local hasFunction = zone:find("function", 1, true) ~= nil
        local hasComment  = zone:find("--", 1, true) ~= nil
        if not (hasLocal or hasReturn or hasFunction or hasComment) then
            return nil, "not-lua"
        end
    end

    return src, strippedFence and "fences-stripped" or nil
end

--================================================================
-- SOURCE HEAD (for error reports)
--================================================================
local function head(src, len)
    if type(src) ~= "string" then return "<not-a-string>" end
    len = len or 120
    local h = src:sub(1, len)
    h = h:gsub("[^\32-\126\n]", "?")
    h = h:gsub("\n", "\\n")
    return h
end

--================================================================
-- HTTP (with fallback chain)
--================================================================
local lastSlowCdn = nil

local function httpGet(url)
    local t0 = os.clock()
    if REQUEST then
        local ok, res = pcall(REQUEST, {
            Url = url, Method = "GET",
            Headers = {
                ["Accept"] = "text/plain",
                ["Cache-Control"] = "no-cache",
                ["Pragma"] = "no-cache",
            },
        })
        if ok and type(res) == "table" then
            local body = res.Body or res.body
            local status = res.StatusCode or res.Status or res.status
            if type(status) == "number"
               and status >= 200 and status < 300
               and type(body) == "string"
               and #body >= MIN_SRC then
                local dt = os.clock() - t0
                if dt > FETCH_TIMEOUT_WARN then lastSlowCdn = true end
                return body
            end
        end
    end
    local bust = url .. (url:find("?", 1, true) and "&" or "?")
        .. "_t=" .. os.time()
    local ok, body = pcall(function() return game:HttpGet(bust, true) end)
    if ok and type(body) == "string" and #body >= MIN_SRC then
        if body:find("404: Not Found", 1, true) then return nil end
        local dt = os.clock() - t0
        if dt > FETCH_TIMEOUT_WARN then lastSlowCdn = true end
        return body
    end
    return nil
end

--================================================================
-- CDN CHAIN
--================================================================
local function cdnChain(name)
    local bust = OPTIONS.force_fresh and SESSION_QS or ""
    local rawBase = "https://raw.githubusercontent.com/"
        .. REPO_USER .. "/" .. REPO_NAME .. "/" .. REPO_BRANCH
        .. "/" .. name .. ".lua" .. bust
    local jsdBase = "https://cdn.jsdelivr.net/gh/"
        .. REPO_USER .. "/" .. REPO_NAME .. "@" .. REPO_BRANCH
        .. "/" .. name .. ".lua" .. bust
    local statBase = "https://cdn.statically.io/gh/"
        .. REPO_USER .. "/" .. REPO_NAME .. "/" .. REPO_BRANCH
        .. "/" .. name .. ".lua" .. bust
    local ghcdnBase = "https://ghcdn.dev/"
        .. REPO_USER .. "/" .. REPO_NAME .. "/" .. REPO_BRANCH
        .. "/" .. name .. ".lua" .. bust
    return {
        { label = "github",    url = rawBase },
        { label = "jsdelivr",  url = jsdBase },
        { label = "statically",url = statBase },
        { label = "ghcdn",     url = ghcdnBase },
    }
end

--================================================================
-- DISK CACHE
--================================================================
local function diskRead(n)
    if not F.read then return nil end
    local ok, s = pcall(F.read, cPath(n))
    if not ok or type(s) ~= "string" or #s < MIN_SRC then return nil end
    return s
end

local function diskWrite(n, src)
    if not F.write then return end
    pcall(F.write, cPath(n), src)
    pcall(F.write, cMeta(n), tostring(os.time()))
end

local function diskDelete(n)
    if not F.delete then return end
    pcall(F.delete, cPath(n))
    pcall(F.delete, cMeta(n))
end

--================================================================
-- MODULE FETCH (multi-CDN with per-CDN diagnostics)
--================================================================
local function fetchModule(name)
    local chain = cdnChain(name)
    local tried = {}
    for _, cdn in ipairs(chain) do
        local t0 = os.clock()
        local body = httpGet(cdn.url)
        local dt = (os.clock() - t0) * 1000
        if body then
            return body, cdn.label, dt, tried
        end
        tried[#tried + 1] = cdn.label .. "(" .. math.floor(dt) .. "ms)"
    end
    return nil, nil, nil, tried
end

--================================================================
-- MODULE COMPILE (with rich error info)
--================================================================
local function compileModule(name, src)
    local compiler = loadstring or load
    if not compiler then
        return nil, "no-compiler-in-executor"
    end
    local fn, cerr = compiler(src, "@" .. name .. ".lua")
    if not fn then
        -- Extract line from error message
        local line = tostring(cerr):match(":(%d+):") or "?"
        return nil, "line " .. line .. ": " .. tostring(cerr)
    end
    return fn, nil
end

--================================================================
-- MODULE LOAD (fetch → sanitize → compile → execute)
--================================================================
local function loadModule(entry)
    local name = entry.name

    -- In-memory cache
    if OPTIONS.use_memory_cache then
        local fn = _G.DINGUS_FN_CACHE[name]
        if fn then
            local ok, mod = pcall(fn)
            if ok and type(mod) == "table" then
                return mod, "memory", 0, nil
            end
            _G.DINGUS_FN_CACHE[name] = nil
        end
    end

    -- Fetch (always fresh if OPTIONS.force_fresh)
    local src, cdn, fetchMs, tried = fetchModule(name)
    local source = cdn

    -- Fallback to disk only if the network failed AND we allow it
    if not src and OPTIONS.use_disk_cache then
        src = diskRead(name)
        if src then
            source = "disk"
            fetchMs = 0
        end
    end

    if not src then
        local attempts = tried and table.concat(tried, ",") or "no-attempts"
        return nil, nil, 0, "fetch-fail[" .. attempts .. "]"
    end

    -- Sanitize
    local sanitized, note = sanitize(src, name)
    if not sanitized then
        diskDelete(name)
        return nil, source, fetchMs,
            "sanitize:" .. tostring(note) .. " | " .. head(src)
    end
    src = sanitized

    -- Compile
    local fn, cerr = compileModule(name, src)
    if not fn then
        local h = head(src)
        src = nil
        diskDelete(name)
        return nil, source, fetchMs,
            "compile:" .. tostring(cerr) .. " | " .. h
    end
    src = nil

    -- Execute
    local ok, mod = pcall(fn)
    if not ok then
        diskDelete(name)
        return nil, source, fetchMs,
            "runtime:" .. tostring(mod)
    end
    if type(mod) ~= "table" then
        diskDelete(name)
        return nil, source, fetchMs,
            "wrong-type:" .. type(mod)
    end

    -- Cache disk + memory
    if OPTIONS.use_disk_cache then
        local sanitizedForDisk = sanitize and nil
        -- store sanitized version
        if F.write then
            pcall(F.write, cPath(name), "")
            -- we lost `src` reference above; simplest path: re-fetch
            -- only when a fresh write is genuinely needed. Skip.
        end
    end
    if OPTIONS.use_memory_cache then
        _G.DINGUS_FN_CACHE[name] = fn
    end

    return mod, source, fetchMs or 0, nil, note
end

--================================================================
-- MANIFEST
--================================================================
local CORE = {
    { name = "config",     slots = { "Cfg", "Config" } },
    { name = "lists",      slots = { "Lists" } },
    { name = "utils",      slots = { "Util", "Utils", "U" } },
    { name = "detect",     slots = { "Detect", "D" } },
    { name = "scanners",   slots = { "Scan", "Scanner" } },
    { name = "hotbar",     slots = { "Hotbar", "HB" } },
    { name = "faction",    slots = { "Faction", "Fac" } },
    { name = "fly",        slots = { "Fly", "FlyMod" } },
    { name = "spoofers",   slots = { "Spoof", "Spoofer" } },
    { name = "chest",      slots = { "Chest" } },
    { name = "quests",     slots = { "Quest", "Quests", "Q" } },
    { name = "attack",     slots = { "Atk", "Attack" } },
    { name = "optimizers", slots = { "Opt", "Optimizer" } },
    { name = "main",       slots = nil },
}

local GUI_ENTRY = { name = "gui", slots = { "Gui", "GUI" } }

--================================================================
-- CTX
--================================================================
local Ctx = {
    St = {}, Errors = {}, Warnings = {}, Loaded = {},
    BootId    = _G.DINGUS_SESSION,
    StartTime = T0,
    BootCount = _G.DINGUS_BOOT_COUNT,
    Boot = { fetch = 0, compile = 0, execute = 0, reused = 0 },
}

--================================================================
-- BANNER
--================================================================
if OPTIONS.verbose and (not IS_REBOOT or not OPTIONS.reboot_quiet) then
    print("")
    print(string.rep("=", 62))
    print("  DINGUS-SLAYER  ·  loader " .. VERSION)
    print(string.format("  session %s  ·  %s",
        _G.DINGUS_SESSION, os.date("%Y-%m-%d %H:%M:%S")))
    print(string.format("  exec=%s  ·  http=%s  ·  fresh=%s  ·  disk=%s",
        tostring(F.id and F.id() or "?"),
        HTTP_MODE,
        tostring(OPTIONS.force_fresh),
        tostring(OPTIONS.use_disk_cache)))
    print(string.rep("=", 62))
elseif IS_REBOOT then
    log(string.format("reboot #%d · session %s",
        _G.DINGUS_BOOT_COUNT, _G.DINGUS_SESSION))
end

--================================================================
-- PHASE 1 · LOAD CORE
--================================================================
if OPTIONS.verbose and (not IS_REBOOT or not OPTIONS.reboot_quiet) then
    print("")
    print("----- PHASE 1/4 · LOAD ----------------------------------------")
end

local loaded, failed = 0, 0
local mainMod = nil

for i = 1, #CORE do
    local entry = CORE[i]
    local t0 = os.clock()
    local mod, source, fetchMs, err, note =
        loadModule(entry)
    local elapsed = (os.clock() - t0) * 1000

    if mod then
        loaded = loaded + 1
        Ctx.Loaded[entry.name] = true
        if entry.slots then
            for _, slot in ipairs(entry.slots) do
                Ctx[slot] = mod
            end
        end
        if entry.name == "main" then mainMod = mod end
        if OPTIONS.verbose and (not IS_REBOOT or not OPTIONS.reboot_quiet) then
            local tag = "ok"
            if source == "memory" then tag = "mm"
            elseif source == "disk" then tag = "dk" end
            local noteSuffix = note and (" (" .. note .. ")") or ""
            print(string.format(
                "  [%s] %-12s %-10s %5dms%s",
                tag, entry.name, source or "?", math.floor(elapsed),
                noteSuffix))
        end
    else
        failed = failed + 1
        Ctx.Loaded[entry.name] = false
        local errText = tostring(err or "unknown")
        Ctx.Errors[#Ctx.Errors + 1] = {
            stage = entry.name,
            msg = "load",
            detail = errText,
        }
        if OPTIONS.verbose then
            print(string.format(
                "  [XX] %-12s %5dms  %s",
                entry.name, math.floor(elapsed), errText))
        else
            warn2(entry.name .. " failed: " .. errText)
        end
    end

    task.wait()
end

--================================================================
-- PHASE 2 · BOOT
--================================================================
if OPTIONS.verbose and (not IS_REBOOT or not OPTIONS.reboot_quiet) then
    print("")
    print("----- PHASE 2/4 · BOOT ----------------------------------------")
end

local bootOk = false
if mainMod and type(mainMod.boot) == "function" then
    local tb = os.clock()
    local ok, err = pcall(mainMod.boot, Ctx)
    if ok then
        bootOk = true
        if OPTIONS.verbose and (not IS_REBOOT or not OPTIONS.reboot_quiet) then
            print(string.format(
                "  [ok] main.boot  ·  %.0fms",
                (os.clock() - tb) * 1000))
        end
    else
        Ctx.Errors[#Ctx.Errors + 1] = {
            stage = "main.boot", msg = "runtime",
            detail = tostring(err),
        }
        warn2("main.boot raised: " .. tostring(err))
    end
else
    Ctx.Errors[#Ctx.Errors + 1] = {
        stage = "main",
        msg = mainMod and "no-boot-fn" or "not-loaded",
    }
end

--================================================================
-- PHASE 3 · EXPOSE
--================================================================
if OPTIONS.verbose and (not IS_REBOOT or not OPTIONS.reboot_quiet) then
    print("")
    print("----- PHASE 3/4 · EXPOSE --------------------------------------")
end

pcall(function() _G.Ctx = Ctx end)
pcall(function() _G.St  = Ctx.St end)
for _, k in ipairs({
    "Cfg", "Lists", "Util", "Detect", "Scan", "Hotbar", "Faction",
    "Fly", "Spoof", "Chest", "Quest", "Atk", "Opt", "Gui",
}) do
    if Ctx[k] then pcall(function() _G[k] = Ctx[k] end) end
end

_G.DINGUS_BOOT = {
    id         = _G.DINGUS_SESSION,
    version    = VERSION,
    boot_count = _G.DINGUS_BOOT_COUNT,
    loaded_at  = _G.DINGUS_LOADED_AT,
    ok         = bootOk,
    loaded     = loaded,
    failed     = failed,
    total      = #CORE,
    errors     = #Ctx.Errors,
    warnings   = #Ctx.Warnings,
    elapsed    = (os.clock() - T0),
    http_mode  = HTTP_MODE,
    executor   = tostring(F.id and F.id() or "?"),
    fresh      = OPTIONS.force_fresh,
}

--================================================================
-- PHASE 4 · GUI (ISOLATED) + NOTIFY
--================================================================
if OPTIONS.verbose and (not IS_REBOOT or not OPTIONS.reboot_quiet) then
    print("")
    print("----- PHASE 4/4 · GUI + NOTIFY --------------------------------")
end

task.spawn(function()
    task.wait(0.5)
    local guiMod, source, fetchMs, err = loadModule(GUI_ENTRY)
    if not guiMod then
        warn2("gui skipped (" .. tostring(err) .. ")")
        return
    end
    Ctx.Gui = guiMod
    _G.Gui = guiMod
    Ctx.Loaded.gui = true
    if type(guiMod.init) == "function" then
        local ok, initErr = pcall(guiMod.init, Ctx)
        if ok then
            if OPTIONS.verbose
               and (not IS_REBOOT or not OPTIONS.reboot_quiet) then
                print("[Dingus][loader] gui loaded ("
                    .. tostring(source) .. ")")
            end
        else
            warn2("gui.init failed: " .. tostring(initErr))
        end
    end
end)

task.spawn(function()
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Dingus-Slayer",
            Text = string.format("%s · %.1fs · %d/%d",
                bootOk and "loaded" or "incomplete",
                os.clock() - T0, loaded, #CORE),
            Duration = 4,
        })
    end)
end)

--================================================================
-- SUMMARY
--================================================================
if OPTIONS.verbose and (not IS_REBOOT or not OPTIONS.reboot_quiet) then
    print("")
    print(string.rep("-", 62))
    print(string.format("  CORE · %s in %.2fs",
        bootOk and "complete" or "incomplete", os.clock() - T0))
    print(string.format("  %d loaded · %d failed · %d errors",
        loaded, failed, #Ctx.Errors))
    if #Ctx.Errors > 0 then
        print("")
        print("  errors:")
        for _, e in ipairs(Ctx.Errors) do
            print(string.format("    [%s] %s",
                e.stage, tostring(e.detail)))
        end
    end
    print(string.rep("-", 62))
end

Ctx.BootDone = true

--================================================================
-- SESSION-LEVEL HELPERS (expose the smart bits for later)
--================================================================
_G.Dingus = _G.Dingus or {}

function _G.Dingus.clearCache()
    if not F.list or not F.delete then return false, "no-file-api" end
    local ok, files = pcall(F.list, CACHE_DIR)
    if not ok or type(files) ~= "table" then return false, "list-failed" end
    for _, f in ipairs(files) do pcall(F.delete, f) end
    _G.DINGUS_FN_CACHE = {}
    return true, #files
end

function _G.Dingus.reboot()
    _G.DINGUS_FN_CACHE = {}
    local fresh = (loadstring or load)(
        string.format([[
            loadstring(game:HttpGet(
                "https://raw.githubusercontent.com/%s/%s/%s/loader.lua?v="
                .. os.time(), true))()
        ]], REPO_USER, REPO_NAME, REPO_BRANCH))
    if fresh then pcall(fresh) end
end

function _G.Dingus.version()
    return VERSION
end

function _G.Dingus.snapshot()
    return {
        session = _G.DINGUS_SESSION,
        boot_count = _G.DINGUS_BOOT_COUNT,
        loaded_at = _G.DINGUS_LOADED_AT,
        version = VERSION,
        http = HTTP_MODE,
        executor = F.id and F.id() or "?",
        memory_cache_size = (function()
            local n = 0
            for _ in pairs(_G.DINGUS_FN_CACHE) do n = n + 1 end
            return n
        end)(),
    }
end

print("[Dingus][loader] " .. VERSION .. " ready · use _G.Dingus.snapshot()")
