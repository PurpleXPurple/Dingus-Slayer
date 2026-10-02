--[[
    Dingus-Slayer · loader.lua v33
    Sequential only. Multi-CDN. Cache. chest included.
]]--

local USER, NAME, BRANCH = "PurpleXPurple", "Dingus-Slayer", "main"

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

local CDNS = {
    { label = "github",     tmpl = "https://raw.githubusercontent.com/%s/%s/%s/%s.lua" },
    { label = "jsdelivr",   tmpl = "https://cdn.jsdelivr.net/gh/%s/%s@%s/%s.lua" },
    { label = "statically", tmpl = "https://cdn.statically.io/gh/%s/%s/%s/%s.lua" },
}

local MAX_RETRY   = 2
local RETRY_DELAY = 0.5
local MIN_SRC     = 32
local CACHE_DIR   = "Dingus/cache"
local CACHE_TTL   = 3600
local USE_CACHE   = true
local TRACE       = true

local bootId = string.format("%04x", math.random(0, 0xFFFF))

local Ctx = {
    St        = {},
    Errors    = {},
    Warnings  = {},
    Loaded    = {},
    BootId    = bootId,
    StartTime = os.clock(),
    Boot      = { fetch={}, compile={}, execute={}, cdnUsed={}, cacheHits=0, cacheMiss=0 },
}

local trace = "boot:start"
local function mark(s)
    trace = s
    if TRACE then print("[Dingus][trace] "..s) end
end

local function log(level, msg)
    local p = "[Dingus]["..level.."]"
    if level == "err" then warn(p.." "..msg) else print(p.." "..msg) end
end

local function recordErr(stage, msg, detail)
    table.insert(Ctx.Errors, { stage = stage, msg = msg, detail = detail })
end

local function recordWarn(stage, msg)
    table.insert(Ctx.Warnings, { stage = stage, msg = msg })
    log("warn", stage..": "..msg)
end

local function now() return os.clock() end
local function realtime() return os.time() end

mark("probe")
local HAS = {
    writefile  = type(writefile)  == "function",
    readfile   = type(readfile)   == "function",
    delfile    = type(delfile)    == "function",
    makefolder = type(makefolder) == "function",
}

mark("cache:setup")
if USE_CACHE and HAS.makefolder then pcall(makefolder, CACHE_DIR) end

local function cPath(n) return CACHE_DIR.."/"..n..".lua" end
local function cMeta(n) return CACHE_DIR.."/"..n..".meta" end

local function cRead(name)
    if not USE_CACHE or not HAS.readfile then return nil, 0 end
    local ok, src = pcall(readfile, cPath(name))
    if not ok or type(src) ~= "string" or #src < MIN_SRC then return nil, 0 end
    local age = 0
    local okM, meta = pcall(readfile, cMeta(name))
    if okM and type(meta) == "string" then
        local ts = tonumber(meta:match("^(%d+)"))
        if ts then age = realtime() - ts end
    end
    return src, age
end

local function cWrite(name, src)
    if not USE_CACHE or not HAS.writefile then return end
    pcall(writefile, cPath(name), src)
    pcall(writefile, cMeta(name), tostring(realtime()))
end

local function cDelete(name)
    if not HAS.delfile then return end
    pcall(delfile, cPath(name))
    pcall(delfile, cMeta(name))
end

local function tryUrl(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res) == "string" and #res >= MIN_SRC then
        if not string.find(res, "404: Not Found", 1, true) then return res, nil end
        return nil, "404"
    end
    return nil, ok and "invalid" or tostring(res)
end

local function fetchFromCDN(name)
    local t0 = now()
    local lastErr
    for _, cdn in ipairs(CDNS) do
        local url = string.format(cdn.tmpl, USER, NAME, BRANCH, name)
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
    return nil, lastErr or "all-failed"
end

local function loadModule(entry)
    local name = entry.name
    local src, age = cRead(name)
    local source = "cache"

    if not src or age >= CACHE_TTL then
        mark("fetch:"..name)
        local fetched, err, cdn = fetchFromCDN(name)
        if fetched then
            src = fetched
            source = cdn or "http"
            Ctx.Boot.cacheMiss = Ctx.Boot.cacheMiss + 1
            cWrite(name, src)
        elseif src then
            source = "stale"
            recordWarn(name, "http failed, using stale cache")
            Ctx.Boot.cacheHits = Ctx.Boot.cacheHits + 1
        else
            return nil, "fetch-fail", err or "no-source"
        end
    else
        Ctx.Boot.cacheHits = Ctx.Boot.cacheHits + 1
    end

    mark("compile:"..name)
    local tc = now()
    local fn, cerr = loadstring(src, "@"..name..".lua")
    Ctx.Boot.compile[name] = (now() - tc) * 1000
    src = nil

    if not fn then
        cDelete(name)
        return nil, "compile-fail", tostring(cerr)
    end

    mark("execute:"..name)
    local te = now()
    local ok, mod = pcall(fn)
    Ctx.Boot.execute[name] = (now() - te) * 1000
    fn = nil

    if not ok then cDelete(name); return nil, "runtime-fail", tostring(mod) end
    if mod == nil then cDelete(name); return nil, "returns-nil", "no 'return'" end
    if type(mod) ~= "table" then cDelete(name); return nil, "wrong-type", type(mod) end
    return mod, nil, nil, source
end

mark("boot")
print("================================================")
print(string.format("  Dingus-Slayer · v33 · id=%s · %d modules",
    bootId, #MANIFEST))
print("================================================")

local t0 = now()
local loaded = 0
local mainMod = nil

for i = 1, #MANIFEST do
    local entry = MANIFEST[i]
    local name = entry.name
    local mod, errK, errD, src = loadModule(entry)

    if not mod then
        log("err", string.format("%s — %s — %s", name, tostring(errK), tostring(errD)))
        recordErr(name, tostring(errK), errD)
        Ctx.Loaded[name] = false
    else
        loaded = loaded + 1
        Ctx.Loaded[name] = true
        if name == "main" then
            mainMod = mod
            if type(mod.boot) ~= "function" then
                recordWarn("main", "missing .boot")
            else
                log("info", string.format("  + %-12s · %s", name, src or "?"))
            end
        else
            if entry.slots then
                for _, key in ipairs(entry.slots) do Ctx[key] = mod end
            end
            log("info", string.format("  + %-12s · %s", name, src or "?"))
        end
    end
    task.wait()
end

mark("main.boot")
local bootOk = false
if mainMod and type(mainMod.boot) == "function" then
    local tb = now()
    local ok, err = pcall(mainMod.boot, Ctx)
    if ok then
        bootOk = true
        log("info", string.format("  + main.boot · %.0fms", (now() - tb) * 1000))
    else
        log("err", "main.boot raised — "..tostring(err))
        recordErr("main.boot", "runtime", tostring(err))
    end
end

mark("summary")
local el = now() - t0
print("================================================")
print(string.format("  boot %s in %.2fs · %d/%d modules",
    bootOk and "complete" or "incomplete", el, loaded, #MANIFEST))
print(string.format("  cache: %d hits · %d misses",
    Ctx.Boot.cacheHits, Ctx.Boot.cacheMiss))
if #Ctx.Errors > 0 then
    print(string.format("  errors (%d):", #Ctx.Errors))
    for _, e in ipairs(Ctx.Errors) do
        print(string.format("    [%s] %s%s", e.stage, e.msg,
            e.detail and (" — "..tostring(e.detail)) or ""))
    end
end
if #Ctx.Warnings > 0 then
    print(string.format("  warnings (%d):", #Ctx.Warnings))
    for _, w in ipairs(Ctx.Warnings) do
        print(string.format("    [%s] %s", w.stage, w.msg))
    end
end
print("================================================")

mark("expose")
pcall(function() _G.Ctx = Ctx end)
pcall(function() _G.St = Ctx.St end)
for _, k in ipairs({ "Cfg","Lists","Util","Detect","Scan","Hotbar",
                     "Spoof","Chest","Quest","Atk","Opt","Gui" }) do
    if Ctx[k] then pcall(function() _G[k] = Ctx[k] end) end
end
pcall(function()
    _G.DINGUS_BOOT = { id = bootId, elapsed = el, ok = bootOk,
                       loaded = loaded, total = #MANIFEST,
                       errors = #Ctx.Errors }
end)

mark("notify")
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Dingus-Slayer",
        Text = string.format("%s · %.1fs · %d errors",
            bootOk and "loaded" or "incomplete", el, #Ctx.Errors),
        Duration = 5,
    })
end)

mark("complete")
