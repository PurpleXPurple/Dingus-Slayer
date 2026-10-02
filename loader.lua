--[[
    Dingus-Slayer · loader.lua v29
    Adds hotbar to manifest. Everything else unchanged from v28.
]]--

local REPO_USER   = "PurpleXPurple"
local REPO_NAME   = "Dingus-Slayer"
local REPO_BRANCH = "main"
local RAW_BASE = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/",
    REPO_USER, REPO_NAME, REPO_BRANCH
)

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

local MAX_RETRY     = 3
local RETRY_BACKOFF = { 0.20, 0.40, 0.80 }
local MIN_SOURCE    = 32
local PARALLEL_TIMEOUT = 20

local HAS = {
    writefile  = type(writefile)  == "function",
    readfile   = type(readfile)   == "function",
    isfile     = type(isfile)     == "function",
    delfile    = type(delfile)    == "function",
    makefolder = type(makefolder) == "function",
}
local CACHE_DIR = "Dingus/cache"

local bootId = string.format("%04x", math.random(0, 0xFFFF))

local Ctx = {
    St        = {},
    Errors    = {},
    Warnings  = {},
    Loaded    = {},
    Boot      = {
        id          = bootId,
        startTime   = os.clock(),
        fetchMs     = {},
        compileMs   = {},
        executeMs   = {},
        cacheHits   = 0,
        cacheMisses = 0,
        httpHits    = 0,
        httpFails   = 0,
    },
}

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

if HAS.makefolder then pcall(makefolder, CACHE_DIR) end

local function cachePath(name) return CACHE_DIR .. "/" .. name .. ".lua" end
local function cacheRead(name)
    if not HAS.readfile then return nil end
    local ok, content = pcall(readfile, cachePath(name))
    if ok and type(content) == "string" and #content >= MIN_SOURCE then return content end
    return nil
end
local function cacheWrite(name, content)
    if not HAS.writefile then return end
    pcall(writefile, cachePath(name), content)
end
local function cacheDelete(name)
    if not HAS.delfile then return end
    pcall(delfile, cachePath(name))
end

local function httpGetOnce(url)
    local ok, res = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(res) == "string" and #res >= MIN_SOURCE then return res, nil end
    if not ok then return nil, "raised: " .. tostring(res) end
    return nil, "short response: " .. tostring(res and #res or "nil")
end

local function httpGet(url)
    local lastErr
    for attempt = 1, MAX_RETRY do
        local src, err = httpGetOnce(url)
        if src then return src, nil end
        lastErr = err
        if attempt < MAX_RETRY then task.wait(RETRY_BACKOFF[attempt] or 0.5) end
    end
    return nil, lastErr
end

local function parallelFetch()
    local results = {}
    local outstanding = 0

    for i = 1, #MANIFEST do
        local entry = MANIFEST[i]
        outstanding = outstanding + 1
        task.spawn(function()
            local name = entry.name
            local tStart = os.clock()
            local cached = cacheRead(name)
            local src, err = httpGet(RAW_BASE .. name .. ".lua")

            if src then
                Ctx.Boot.httpHits = Ctx.Boot.httpHits + 1
                results[name] = {
                    src = src, err = nil,
                    ms = (os.clock() - tStart) * 1000,
                    source = "http", cached = cached,
                }
            elseif cached then
                Ctx.Boot.cacheHits = Ctx.Boot.cacheHits + 1
                results[name] = {
                    src = cached, err = nil,
                    ms = (os.clock() - tStart) * 1000,
                    source = "cache",
                    note = "http failed: " .. tostring(err),
                }
            else
                Ctx.Boot.httpFails = Ctx.Boot.httpFails + 1
                results[name] = {
                    src = nil, err = err or "no source",
                    ms = (os.clock() - tStart) * 1000,
                    source = "none",
                }
            end
            outstanding = outstanding - 1
        end)
    end

    local deadline = os.clock() + PARALLEL_TIMEOUT
    while outstanding > 0 and os.clock() < deadline do
        task.wait(0.02)
    end
    return results
end

local function compileAll(fetchResults)
    local compiled = {}
    for name, fr in pairs(fetchResults) do
        if not fr.src then
            compiled[name] = { fn = nil, err = "no source", fr = fr }
        else
            local tStart = os.clock()
            local fn, cerr = loadstring(fr.src, "@" .. name .. ".lua")
            Ctx.Boot.compileMs[name] = (os.clock() - tStart) * 1000
            if not fn then
                compiled[name] = { fn = nil, err = cerr, fr = fr }
                cacheDelete(name)
            else
                compiled[name] = { fn = fn, err = nil, fr = fr }
            end
        end
    end
    return compiled
end

local function executeAll(compiled)
    local mainMod = nil
    local execCount = 0

    for i = 1, #MANIFEST do
        local entry = MANIFEST[i]
        local name = entry.name
        local c = compiled[name]

        if not c or not c.fn then
            local errText = c and c.err or "missing"
            log("err", string.format("%s — compile-fail — %s", name, tostring(errText)))
            recordErr(name, "compile-fail", errText)
            Ctx.Loaded[name] = false
        else
            local tStart = os.clock()
            local ok, mod = pcall(c.fn)
            Ctx.Boot.executeMs[name] = (os.clock() - tStart) * 1000

            if not ok then
                log("err", string.format("%s — runtime-fail — %s", name, tostring(mod)))
                recordErr(name, "runtime-fail", tostring(mod))
                Ctx.Loaded[name] = false
                cacheDelete(name)
            elseif mod == nil then
                log("err", string.format("%s — returns-nil", name))
                recordErr(name, "returns-nil", "file missing 'return' at end")
                Ctx.Loaded[name] = false
                cacheDelete(name)
            elseif type(mod) ~= "table" then
                log("err", string.format("%s — wrong-type — got %s", name, type(mod)))
                recordErr(name, "wrong-type", "returned " .. type(mod))
                Ctx.Loaded[name] = false
                cacheDelete(name)
            else
                Ctx.Loaded[name] = true
                execCount = execCount + 1
                if c.fr and c.fr.src and c.fr.source == "http" then
                    cacheWrite(name, c.fr.src)
                end
                if name == "main" then
                    mainMod = mod
                    if type(mod.boot) ~= "function" then
                        recordWarn("main", "missing .boot function")
                    else
                        log("info", "  + " .. name .. " (boot fn)")
                    end
                else
                    if entry.slots then
                        for _, key in ipairs(entry.slots) do
                            Ctx[key] = mod
                        end
                    end
                    local sourceTag = c.fr and c.fr.source or "?"
                    log("info", string.format("  + %-12s · %s · %.0fms",
                        name, sourceTag, c.fr and c.fr.ms or 0))
                end
            end
        end
    end
    return mainMod, execCount
end

local function bootMain(mainMod)
    if not mainMod then
        log("err", "main module never loaded — cannot boot")
        recordErr("main", "not-loaded", nil)
        return false
    end
    if type(mainMod.boot) ~= "function" then
        log("err", "main.boot is not a function")
        recordErr("main", "no-boot-fn", nil)
        return false
    end
    local tStart = os.clock()
    local ok, err = pcall(mainMod.boot, Ctx)
    Ctx.Boot.mainBootMs = (os.clock() - tStart) * 1000
    if not ok then
        log("err", "main.boot raised — " .. tostring(err))
        recordErr("main.boot", "runtime", tostring(err))
        return false
    end
    log("info", string.format("  + main.boot · %.0fms", Ctx.Boot.mainBootMs))
    return true
end

print("=================================================")
print("  Dingus-Slayer · boot v29 · id=" .. bootId)
print("  " .. RAW_BASE)
print("=================================================")

local t0 = os.clock()

log("info", string.format("phase 1/4 · parallel fetch (%d modules)", #MANIFEST))
local fetchResults = parallelFetch()
log("info", string.format("  fetched · http=%d cache=%d fail=%d",
    Ctx.Boot.httpHits, Ctx.Boot.cacheHits, Ctx.Boot.httpFails))

log("info", "phase 2/4 · compile")
local compiled = compileAll(fetchResults)

log("info", "phase 3/4 · execute + slot")
local mainMod, execCount = executeAll(compiled)

log("info", "phase 4/4 · main.boot")
local bootOk = bootMain(mainMod)

local elapsed = os.clock() - t0
print("=================================================")
print(string.format("  boot %s in %.2fs · %d/%d modules",
    bootOk and "complete" or "incomplete",
    elapsed, execCount, #MANIFEST))

local fetchTotal = 0
local execTotal = 0
for _, fr in pairs(fetchResults) do fetchTotal = fetchTotal + (fr.ms or 0) end
for _, ms in pairs(Ctx.Boot.executeMs) do execTotal = execTotal + ms end
local maxFetch = 0
for _, fr in pairs(fetchResults) do
    if (fr.ms or 0) > maxFetch then maxFetch = fr.ms end
end
print(string.format("  fetch wall: %.0fms · exec total: %.0fms · main: %.0fms",
    maxFetch, execTotal, Ctx.Boot.mainBootMs or 0))
print("=================================================")

if #Ctx.Errors > 0 then
    print(string.format("  errors (%d):", #Ctx.Errors))
    for _, e in ipairs(Ctx.Errors) do
        print(string.format("    [%s] %s%s",
            e.stage, e.msg,
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

-- Expose to _G for diagnostics
_G.Ctx    = Ctx
_G.St     = Ctx.St
_G.Cfg    = Ctx.Cfg
_G.Lists  = Ctx.Lists
_G.Util   = Ctx.Util
_G.Detect = Ctx.Detect
_G.Scan   = Ctx.Scan
_G.Hotbar = Ctx.Hotbar
_G.Spoof  = Ctx.Spoof
_G.Quest  = Ctx.Quest
_G.Atk    = Ctx.Atk
_G.Opt    = Ctx.Opt
_G.Gui    = Ctx.Gui

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Dingus-Slayer",
        Text = string.format("%s · %.1fs · %d errors",
            bootOk and "loaded" or "incomplete",
            elapsed, #Ctx.Errors),
        Duration = 5,
    })
end)
