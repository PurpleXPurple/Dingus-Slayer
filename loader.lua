-- Dingus-Slayer · loader.lua v39
-- No environment checks. If this is executing, we are in Roblox.
-- If loadstring or HttpGet are missing the fetch will simply fail and
-- you will see a clean module-level error instead of a false abort.

local VERSION = "v39"
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
    mkdir  = probe("makefolder"),
    id     = probe("identifyexecutor"),
}

local HTTP_MODE = REQUEST and "request" or "HttpGet"

_G.DINGUS_FN_CACHE   = _G.DINGUS_FN_CACHE or {}
_G.DINGUS_SESSION    = _G.DINGUS_SESSION
    or string.format("%04x", math.random(0, 0xFFFF))
_G.DINGUS_BOOT_COUNT = (_G.DINGUS_BOOT_COUNT or 0) + 1
local IS_REBOOT = _G.DINGUS_BOOT_COUNT > 1

local MANIFEST = {
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
    { name = "gui",        slots = { "Gui", "GUI" } },
    { name = "main",       slots = nil },
}

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
local function log(msg) print("[Dingus][loader] " .. msg) end
local function warn2(msg) warn("[Dingus][loader] " .. msg) end

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

local Ctx = {
    St = {}, Errors = {}, Warnings = {}, Loaded = {},
    BootId    = _G.DINGUS_SESSION,
    StartTime = T0,
    BootCount = _G.DINGUS_BOOT_COUNT,
    Boot = { fetch = 0, compile = 0, execute = 0, reused = 0 },
}

local function loadModule(entry)
    local name = entry.name

    local cachedFn = _G.DINGUS_FN_CACHE[name]
    if cachedFn then
        Ctx.Boot.reused = Ctx.Boot.reused + 1
        local ok, mod = pcall(cachedFn)
        if ok and type(mod) == "table" then
            return mod, "memory"
        else
            _G.DINGUS_FN_CACHE[name] = nil
        end
    end

    local src = diskRead(name)
    local source = "disk"
    if not src then
        local t0 = os.clock()
        src, source = fetchModule(name)
        Ctx.Boot.fetch = Ctx.Boot.fetch + (os.clock() - t0)
        if not src then return nil, "fetch-fail", source end
        diskWrite(name, src)
    end

    local tc = os.clock()
    local compiler = loadstring or load
    local fn, cerr = compiler(src, "@" .. name .. ".lua")
    Ctx.Boot.compile = Ctx.Boot.compile + (os.clock() - tc)
    src = nil
    if not fn then
        diskDelete(name)
        return nil, "compile-fail", tostring(cerr)
    end

    local te = os.clock()
    local ok, mod = pcall(fn)
    Ctx.Boot.execute = Ctx.Boot.execute + (os.clock() - te)
    if not ok then
        diskDelete(name)
        return nil, "runtime-fail", tostring(mod)
    end
    if type(mod) ~= "table" then
        diskDelete(name)
        return nil, "wrong-type", type(mod)
    end

    _G.DINGUS_FN_CACHE[name] = fn
    return mod, source
end

if not IS_REBOOT then
    print("")
    print(string.rep("=", 62))
    print("  DINGUS-SLAYER · loader " .. VERSION)
    print(string.format("  session %s · %s",
        _G.DINGUS_SESSION, os.date("%Y-%m-%d %H:%M:%S")))
    print(string.format("  modules=%d · http=%s · cache=%s · executor=%s",
        #MANIFEST, HTTP_MODE,
        F.write and "disk+mem" or "mem",
        tostring(F.id and F.id() or "?")))
    print(string.rep("=", 62))
else
    log(string.format("reboot #%d · session %s",
        _G.DINGUS_BOOT_COUNT, _G.DINGUS_SESSION))
end

if not IS_REBOOT then
    print("")
    print("----- PHASE 1/4 · LOAD ----------------------------------------")
end

local loaded, failed = 0, 0
local mainMod

for i = 1, #MANIFEST do
    local entry = MANIFEST[i]
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
            local icon = "ok"
            if source == "memory" then icon = "mm"
            elseif source == "disk" then icon = "dk" end
            print(string.format("  [%s] %-12s %-10s %5dms",
                icon, entry.name, source or "?", math.floor(elapsed)))
        end
    else
        failed = failed + 1
        Ctx.Loaded[entry.name] = false
        table.insert(Ctx.Errors, {
            stage = entry.name, msg = source or "?", detail = err })
        if not IS_REBOOT then
            print(string.format("  [XX] %-12s %-10s %5dms  %s",
                entry.name, source or "?",
                math.floor(elapsed), tostring(err)))
        else
            warn2(entry.name .. " failed: " .. tostring(err))
        end
    end

    task.wait()
end

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
    total = #MANIFEST, errors = #Ctx.Errors,
    warnings = #Ctx.Warnings, elapsed = (os.clock() - T0),
    fetch = Ctx.Boot.fetch, compile = Ctx.Boot.compile,
    execute = Ctx.Boot.execute, reused = Ctx.Boot.reused,
}

if not IS_REBOOT then
    print("")
    print("----- PHASE 4/4 · NOTIFY --------------------------------------")
    task.spawn(function()
        pcall(function()
            game:GetService("StarterGui"):SetCore(
                "SendNotification", {
                Title = "Dingus-Slayer",
                Text = string.format("%s · %.1fs · %d/%d",
                    bootOk and "loaded" or "incomplete",
                    os.clock() - T0, loaded, #MANIFEST),
                Duration = 4,
            })
        end)
    end)
end

if not IS_REBOOT then
    print("")
    print(string.rep("-", 62))
    print(string.format("  RESULT · %s in %.2fs",
        bootOk and "complete" or "incomplete", os.clock() - T0))
    print(string.format("  %d loaded · %d failed · %d errors · %d warnings",
        loaded, failed, #Ctx.Errors, #Ctx.Warnings))
    print(string.format(
        "  fetch=%.0fms  compile=%.0fms  execute=%.0fms  reused=%d",
        Ctx.Boot.fetch   * 1000,
        Ctx.Boot.compile * 1000,
        Ctx.Boot.execute * 1000,
        Ctx.Boot.reused))
    if #Ctx.Errors > 0 then
        print("")
        for _, e in ipairs(Ctx.Errors) do
            print(string.format("  [%s] %s -- %s",
                e.stage, e.msg, tostring(e.detail)))
        end
    end
    print(string.rep("-", 62))
else
    log(string.format("reboot complete · %d/%d modules · %.0fms",
        loaded, #MANIFEST, (os.clock() - T0) * 1000))
end

Ctx.BootDone = true
