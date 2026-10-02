-- Dingus-Slayer · loader.lua v41
-- v41 fixes: loadModule now returns (mod, source, err) with err non-nil on
-- failure. Prior version returned (mod, msg) and callers read position 3,
-- hiding every real error behind a nil. Also prints head-of-source.

local VERSION = "v41"
local REPO_USER = "PurpleXPurple"
local REPO_NAME = "Dingus-Slayer"
local REPO_BRANCH = "main"

local function probe(n)
    if type(_G[n]) == "function" then return _G[n] end
    local ok, v = pcall(function() return getfenv()[n] end)
    return (ok and type(v) == "function") and v or nil
end

local REQUEST = probe("request") or probe("http_request")
if not REQUEST and type(syn) == "table"
   and type(syn.request) == "function" then REQUEST = syn.request end
if not REQUEST and type(http) == "table"
   and type(http.request) == "function" then REQUEST = http.request end

local F = {
    write  = probe("writefile"),
    read   = probe("readfile"),
    exists = probe("isfile"),
    delete = probe("delfile"),
    mkdir  = probe("makefolder"),
    id     = probe("identifyexecutor"),
}

local HTTP_MODE = REQUEST and "request" or "HttpGet"

_G.DINGUS_FN_CACHE   = _G.DINGUS_FN_CACHE or {}
_G.DINGUS_SESSION    = _G.DINGUS_SESSION
    or string.format("%04x", math.random(0, 0xFFFF))
_G.DINGUS_BOOT_COUNT = (_G.DINGUS_BOOT_COUNT or 0) + 1
local IS_REBOOT = _G.DINGUS_BOOT_COUNT > 1

local CORE_MANIFEST = {
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

local CDNS = {
    { label = "github", url = function(n)
        return string.format(
            "https://raw.githubusercontent.com/%s/%s/%s/%s.lua",
            REPO_USER, REPO_NAME, REPO_BRANCH, n) end },
    { label = "jsdelivr", url = function(n)
        return string.format(
            "https://cdn.jsdelivr.net/gh/%s/%s@%s/%s.lua",
            REPO_USER, REPO_NAME, REPO_BRANCH, n) end },
    { label = "statically", url = function(n)
        return string.format(
            "https://cdn.statically.io/gh/%s/%s/%s/%s.lua",
            REPO_USER, REPO_NAME, REPO_BRANCH, n) end },
    { label = "ghcdn", url = function(n)
        return string.format(
            "https://ghcdn.dev/%s/%s/%s/%s.lua",
            REPO_USER, REPO_NAME, REPO_BRANCH, n) end },
}

local CACHE_DIR = "Dingus/cache"
local MIN_SRC   = 32

if F.mkdir then pcall(F.mkdir, CACHE_DIR) end
if F.mkdir then pcall(F.mkdir, "Dingus") end

local T0 = os.clock()
local function warn2(m) warn("[Dingus][loader] " .. m) end

local function cPath(n) return CACHE_DIR .. "/" .. n .. ".lua" end
local function cMeta(n) return CACHE_DIR .. "/" .. n .. ".meta" end

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

--============================================================
-- SANITIZE
--============================================================
local function head(src)
    if type(src) ~= "string" then return "<not-string>" end
    local h = src:sub(1, 80)
    h = h:gsub("[^\32-\126]", "?")
    h = h:gsub("\n", "\\n")
    return h
end

local function sanitize(src, name)
    if type(src) ~= "string" then return nil, "not-a-string" end
    if #src < MIN_SRC then return nil, "too-short(" .. #src .. ")" end

    if src:sub(1, 3) == "\239\187\191" then src = src:sub(4) end

    local fenceStripped = false
    local stripped, count

    stripped, count = src:gsub("^%s*```[%a]*%s*\r?\n", "", 1)
    if count > 0 then fenceStripped = true; src = stripped end
    stripped, count = src:gsub("^%s*```%s*\r?\n", "", 1)
    if count > 0 then fenceStripped = true; src = stripped end
    stripped, count = src:gsub("^%s*```", "", 1)
    if count > 0 then fenceStripped = true; src = stripped end
    stripped, count = src:gsub("\r?\n```%s*$", "")
    if count > 0 then fenceStripped = true; src = stripped end
    stripped, count = src:gsub("```%s*$", "")
    if count > 0 then fenceStripped = true; src = stripped end

    local lhead = src:sub(1, 240):lower()
    if lhead:find("<!doctype", 1, true)
       or lhead:find("<html", 1, true) then
        return nil, "html-response"
    end
    if lhead:find("404: not found", 1, true)
       or lhead:find("404 not found", 1, true) then
        return nil, "not-found"
    end

    local zone = src:sub(1, 400)
    if not zone:find("local", 1, true)
       and not zone:find("return", 1, true)
       and not zone:find("function", 1, true)
       and not zone:find("--", 1, true) then
        return nil, "not-lua"
    end

    return src, fenceStripped
end

--============================================================
-- HTTP
--============================================================
local FETCH_SLOW = false

local function httpGet(url)
    local t0 = os.clock()
    if REQUEST then
        local ok, res = pcall(REQUEST, { Url = url, Method = "GET",
            Headers = { ["Accept"] = "text/plain",
                        ["Cache-Control"] = "no-cache" } })
        if ok and type(res) == "table" then
            local body = res.Body or res.body
            local status = res.StatusCode or res.Status or res.status
            if type(status) == "number"
               and status >= 200 and status < 300
               and type(body) == "string"
               and #body >= MIN_SRC then
                if os.clock() - t0 > 2 then FETCH_SLOW = true end
                return body
            end
        end
    end
    local bust = url .. (url:find("?", 1, true) and "&" or "?")
        .. "t=" .. os.time()
    local ok, body = pcall(function() return game:HttpGet(bust, true) end)
    if ok and type(body) == "string" and #body >= MIN_SRC then
        if body:find("404: Not Found", 1, true) then return nil end
        if os.clock() - t0 > 2 then FETCH_SLOW = true end
        return body
    end
    return nil
end

local function fetchModule(name)
    for _, cdn in ipairs(CDNS) do
        local body = httpGet(cdn.url(name))
        if body then return body, cdn.label end
        if FETCH_SLOW and cdn ~= CDNS[1] then break end
    end
    return nil, nil
end

--============================================================
-- CTX
--============================================================
local Ctx = {
    St = {}, Errors = {}, Warnings = {}, Loaded = {},
    BootId    = _G.DINGUS_SESSION,
    StartTime = T0,
    BootCount = _G.DINGUS_BOOT_COUNT,
    Boot = { fetch = 0, compile = 0, execute = 0, reused = 0 },
}

--============================================================
-- MODULE LOADER (returns mod, source, err — err non-nil on failure)
--============================================================
local function loadModule(entry)
    local name = entry.name

    local cachedFn = _G.DINGUS_FN_CACHE[name]
    if cachedFn then
        Ctx.Boot.reused = Ctx.Boot.reused + 1
        local ok, mod = pcall(cachedFn)
        if ok and type(mod) == "table" then
            return mod, "memory", nil
        end
        _G.DINGUS_FN_CACHE[name] = nil
    end

    local src = diskRead(name)
    local source = "disk"
    if not src then
        local t0 = os.clock()
        src, source = fetchModule(name)
        Ctx.Boot.fetch = Ctx.Boot.fetch + (os.clock() - t0)
        if not src then
            return nil, nil, "fetch-fail"
        end
    end

    local sanitized, note = sanitize(src, name)
    if not sanitized then
        local h = head(src)
        diskDelete(name)
        return nil, nil, "sanitize:" .. tostring(note) .. " | " .. h
    end
    src = sanitized

    local tc = os.clock()
    local compiler = loadstring or load
    local fn, cerr = compiler(src, "@" .. name .. ".lua")
    Ctx.Boot.compile = Ctx.Boot.compile + (os.clock() - tc)
    if not fn then
        local h = head(src)
        src = nil
        diskDelete(name)
        return nil, nil, "compile:" .. tostring(cerr) .. " | " .. h
    end
    src = nil

    local te = os.clock()
    local ok, mod = pcall(fn)
    Ctx.Boot.execute = Ctx.Boot.execute + (os.clock() - te)
    if not ok then
        diskDelete(name)
        return nil, nil, "runtime:" .. tostring(mod)
    end
    if type(mod) ~= "table" then
        diskDelete(name)
        return nil, nil, "wrong-type:" .. type(mod)
    end

    _G.DINGUS_FN_CACHE[name] = fn
    if note and not IS_REBOOT then
        print(string.format("  ~ %-12s markdown fences stripped", name))
    end
    return mod, source, nil
end

--============================================================
-- BANNER
--============================================================
if not IS_REBOOT then
    print("")
    print(string.rep("=", 62))
    print("  DINGUS-SLAYER · loader " .. VERSION)
    print(string.format("  session %s · %s",
        _G.DINGUS_SESSION, os.date("%Y-%m-%d %H:%M:%S")))
    print(string.format("  core=%d + gui · http=%s · cache=%s · exec=%s",
        #CORE_MANIFEST, HTTP_MODE,
        F.write and "disk+mem" or "mem",
        tostring(F.id and F.id() or "?")))
    print(string.rep("=", 62))
else
    print("[Dingus][loader] reboot #" .. _G.DINGUS_BOOT_COUNT
        .. " · session " .. _G.DINGUS_SESSION)
end

--============================================================
-- PHASE 1 · LOAD CORE
--============================================================
if not IS_REBOOT then
    print("")
    print("----- PHASE 1/4 · LOAD ----------------------------------------")
end

local loaded, failed = 0, 0
local mainMod

for i = 1, #CORE_MANIFEST do
    local entry = CORE_MANIFEST[i]
    local t0 = os.clock()
    local mod, source, err = loadModule(entry)
    local elapsed = (os.clock() - t0) * 1000

    if mod then
        loaded = loaded + 1
        Ctx.Loaded[entry.name] = true
        if entry.slots then
            for _, slot in ipairs(entry.slots) do Ctx[slot] = mod end
        end
        if entry.name == "main" then mainMod = mod end
        if not IS_REBOOT then
            local tag = "ok"
            if source == "memory" then tag = "mm"
            elseif source == "disk" then tag = "dk" end
            print(string.format("  [%s] %-12s %-10s %5dms",
                tag, entry.name, source or "?", math.floor(elapsed)))
        end
    else
        failed = failed + 1
        Ctx.Loaded[entry.name] = false
        local errText = tostring(err or "unknown")
        table.insert(Ctx.Errors, {
            stage = entry.name, msg = "load", detail = errText })
        if not IS_REBOOT then
            print(string.format("  [XX] %-12s %5dms  %s",
                entry.name, math.floor(elapsed), errText))
        else
            warn2(entry.name .. " failed: " .. errText)
        end
    end

    task.wait()
end

--============================================================
-- PHASE 2 · BOOT
--============================================================
if not IS_REBOOT then
    print("")
    print("----- PHASE 2/4 · BOOT ----------------------------------------")
end

local bootOk = false
if mainMod and type(mainMod.boot) == "function" then
    local tb = os.clock()
    local ok, err = pcall(mainMod.boot, Ctx)
    if ok then
        bootOk = true
        if not IS_REBOOT then
            print(string.format("  [ok] main.boot · %.0fms",
                (os.clock() - tb) * 1000))
        end
    else
        table.insert(Ctx.Errors, {
            stage = "main.boot", msg = "runtime",
            detail = tostring(err) })
        warn2("main.boot raised: " .. tostring(err))
    end
else
    table.insert(Ctx.Errors, {
        stage = "main",
        msg = mainMod and "no-boot-fn" or "not-loaded" })
end

--============================================================
-- PHASE 3 · EXPOSE
--============================================================
if not IS_REBOOT then
    print("")
    print("----- PHASE 3/4 · EXPOSE --------------------------------------")
end

pcall(function() _G.Ctx = Ctx end)
pcall(function() _G.St  = Ctx.St end)
for _, k in ipairs({
    "Cfg","Lists","Util","Detect","Scan","Hotbar","Faction","Fly",
    "Spoof","Chest","Quest","Atk","Opt","Gui",
}) do
    if Ctx[k] then pcall(function() _G[k] = Ctx[k] end) end
end

_G.DINGUS_BOOT = {
    id = _G.DINGUS_SESSION, version = VERSION,
    boot_count = _G.DINGUS_BOOT_COUNT,
    ok = bootOk, loaded = loaded, failed = failed,
    total = #CORE_MANIFEST, errors = #Ctx.Errors,
    warnings = #Ctx.Warnings, elapsed = (os.clock() - T0),
    fetch = Ctx.Boot.fetch, compile = Ctx.Boot.compile,
    execute = Ctx.Boot.execute, reused = Ctx.Boot.reused,
}

--============================================================
-- PHASE 4 · GUI (ISOLATED) + NOTIFY
--============================================================
if not IS_REBOOT then
    print("")
    print("----- PHASE 4/4 · GUI + NOTIFY --------------------------------")
end

task.spawn(function()
    task.wait(0.5)
    local guiMod, source, err = loadModule(GUI_ENTRY)
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
            print("[Dingus][loader] gui loaded (" .. tostring(source) .. ")")
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
                bootOk and "core loaded" or "incomplete",
                os.clock() - T0, loaded, #CORE_MANIFEST),
            Duration = 4,
        })
    end)
end)

--============================================================
-- SUMMARY
--============================================================
if not IS_REBOOT then
    print("")
    print(string.rep("-", 62))
    print(string.format("  CORE · %s in %.2fs",
        bootOk and "complete" or "incomplete", os.clock() - T0))
    print(string.format("  %d loaded · %d failed · %d errors",
        loaded, failed, #Ctx.Errors))
    print(string.format(
        "  fetch=%.0fms  compile=%.0fms  execute=%.0fms  reused=%d",
        Ctx.Boot.fetch   * 1000,
        Ctx.Boot.compile * 1000,
        Ctx.Boot.execute * 1000,
        Ctx.Boot.reused))
    if #Ctx.Errors > 0 then
        print("")
        print("  errors:")
        for _, e in ipairs(Ctx.Errors) do
            print(string.format("    [%s] %s", e.stage, tostring(e.detail)))
        end
    end
    print(string.rep("-", 62))
    print("  gui loads isolated — if it fails, core still runs")
end

Ctx.BootDone = true
