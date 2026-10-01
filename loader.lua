--[[
    Dingus-Slayer · loader.lua v26
    Auto-discovery loader. GitHub contents API + topological sort.
    Single-pass fetch, no polling, no sleep padding.

    Discovers every .lua in the repo root, orders modules by dependency
    (detected by scanning source for `Ctx.<Slot>` references), registers
    under canonical + alias names, boots main.

    Speed wins vs v25:
      - No coroutine timeout wrapper (game:HttpGet is synchronous anyway)
      - No 0.03s inter-file sleeps, no 0.1s inter-phase sleeps
      - Retry = 2 attempts @ 0.35s (was 3 growing up to ~2s)
      - No re-fetch of main in phase 3 (single fetch, kept in memory)
      - No init phase in the loader (main.boot owns init — kills double-init)

    Structural wins:
      - No hardcoded MANIFEST
      - No continue_or_break() stub (was broken; module with missing deps
        still got fetched)
      - Auto-registers under all alias slot names (Fly + FlyMod etc.)
      - Kahn topo sort with deterministic alpha tiebreak + cycle fallback
      - Fallback file list if the GitHub API is unreachable
      - Post-boot safety net for main.lua's missing fly entry
]]--

local REPO_USER   = "PurpleXPurple"
local REPO_NAME   = "Dingus-Slayer"
local REPO_BRANCH = "main"

local RAW_BASE = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/",
    REPO_USER, REPO_NAME, REPO_BRANCH
)
local API_LIST = string.format(
    "https://api.github.com/repos/%s/%s/contents/?ref=%s",
    REPO_USER, REPO_NAME, REPO_BRANCH
)

-- Fallback list — only used if the GitHub API call fails.
local FALLBACK = {
    "lists", "config", "utils", "detect", "scanners", "spoofers",
    "fly", "attack", "optimizers", "gui", "main",
}

-- Canonical slot + aliases per known module.
-- Consumers use `Ctx.<Slot>`. Aliases preserve backward compat when a
-- consumer was written against a different name (e.g. Fly vs FlyMod).
local SLOT_MAP = {
    lists      = { "Lists" },
    config     = { "Cfg", "Config" },
    utils      = { "Util", "Utils", "U" },
    detect     = { "Detect", "D" },
    scanners   = { "Scan", "Scanner", "Scanners" },
    spoofers   = { "Spoof", "Spoofer", "Spoofers" },
    fly        = { "Fly", "FlyMod" },
    attack     = { "Atk", "Attack" },
    optimizers = { "Opt", "Optimizer", "Optimizers" },
    gui        = { "Gui", "GUI" },
    -- main is special: not stored in a slot, booted last.
}

local SELF        = "loader"
local MAX_RETRY   = 2
local RETRY_DELAY = 0.35
local MIN_SOURCE  = 16

local Ctx = {
    St       = {},
    Errors   = {},
    Warnings = {},
    Loaded   = {},
    StartTime = os.clock(),
}

--============================================================
-- LOGGING
--============================================================
local function log(level, msg)
    local prefix = "[Dingus][" .. level .. "]"
    if level == "err" then warn(prefix .. " " .. msg)
    else print(prefix .. " " .. msg) end
end

local function recordErr(stage, msg, detail)
    table.insert(Ctx.Errors, { stage = stage, msg = msg, detail = detail })
    log("err", stage .. ": " .. msg ..
        (detail ~= nil and (" — " .. tostring(detail)) or ""))
end

local function recordWarn(stage, msg)
    table.insert(Ctx.Warnings, { stage = stage, msg = msg })
    log("warn", stage .. ": " .. msg)
end

local function count(t)
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

--============================================================
-- HTTP (no coroutine polling — HttpGet is synchronous)
--============================================================
local function httpGet(url)
    for attempt = 1, MAX_RETRY do
        local ok, res = pcall(function() return game:HttpGet(url, true) end)
        if ok and type(res) == "string" and #res >= MIN_SOURCE then
            return res, nil
        end
        if attempt < MAX_RETRY then task.wait(RETRY_DELAY) end
    end
    return nil, "fetch failed after " .. MAX_RETRY .. " attempts"
end

--============================================================
-- DISCOVERY
--============================================================
local function discoverFiles()
    local ok, body = pcall(function() return game:HttpGet(API_LIST, true) end)
    if not ok or type(body) ~= "string" or #body < 2 then
        recordWarn("discover", "GitHub API unreachable, using fallback list")
        return FALLBACK
    end

    local http = game:GetService("HttpService")
    local okD, data = pcall(function() return http:JSONDecode(body) end)
    if not okD or type(data) ~= "table" then
        recordWarn("discover", "API returned non-JSON, using fallback")
        return FALLBACK
    end

    local names = {}
    for _, item in ipairs(data) do
        if type(item) == "table" and item.type == "file" then
            local nm = item.name
            if type(nm) == "string" and nm:sub(-4) == ".lua" then
                local stem = nm:sub(1, -5)
                if stem ~= SELF then
                    table.insert(names, stem)
                end
            end
        end
    end

    if #names == 0 then
        recordWarn("discover", "API returned no .lua files, using fallback")
        return FALLBACK
    end

    table.sort(names)
    return names
end

--============================================================
-- SLOT RESOLUTION
--============================================================
local function slotsFor(name)
    local known = SLOT_MAP[name]
    if known then return known end
    -- Heuristic: snake_case → PascalCase
    local pascal = name:gsub("_(%a)", function(c) return c:upper() end)
    pascal = pascal:sub(1, 1):upper() .. pascal:sub(2)
    return { pascal }
end

--============================================================
-- DEPENDENCY GRAPH
--============================================================
local function extractCtxRefs(src)
    local set = {}
    for id in src:gmatch("Ctx%.([%a_][%w_]*)") do set[id] = true end
    return set
end

local function buildOrder(sources)
    -- Map every alias → module name
    local aliasToName = {}
    for name in pairs(sources) do
        for _, alias in ipairs(slotsFor(name)) do
            aliasToName[alias] = name
        end
    end

    -- Deps: name → set of module names it depends on
    local deps = {}
    for name, src in pairs(sources) do
        deps[name] = {}
        for ref in pairs(extractCtxRefs(src)) do
            local target = aliasToName[ref]
            if target and target ~= name then
                deps[name][target] = true
            end
        end
    end

    -- Kahn's algorithm; ties broken alphabetically for determinism
    local inDegree = {}
    local reverse  = {}
    for name in pairs(sources) do
        inDegree[name] = inDegree[name] or 0
        reverse[name]  = reverse[name]  or {}
    end
    for name, ds in pairs(deps) do
        for target in pairs(ds) do
            inDegree[name] = inDegree[name] + 1
            reverse[target][name] = true
        end
    end

    local ready = {}
    for name, d in pairs(inDegree) do
        if d == 0 then table.insert(ready, name) end
    end
    table.sort(ready)

    local order = {}
    while #ready > 0 do
        local n = table.remove(ready, 1)
        table.insert(order, n)
        local newlyReady = {}
        for dep in pairs(reverse[n] or {}) do
            inDegree[dep] = inDegree[dep] - 1
            if inDegree[dep] == 0 then table.insert(newlyReady, dep) end
        end
        table.sort(newlyReady)
        for _, d in ipairs(newlyReady) do table.insert(ready, d) end
    end

    if #order < count(sources) then
        -- Cycle — append remaining alphabetically
        local seen = {}
        for _, n in ipairs(order) do seen[n] = true end
        local rest = {}
        for name in pairs(sources) do
            if not seen[name] then table.insert(rest, name) end
        end
        table.sort(rest)
        for _, n in ipairs(rest) do table.insert(order, n) end
        recordWarn("graph", "dependency cycle detected — partial order used")
    end

    return order, deps
end

--============================================================
-- FETCH + COMPILE
--============================================================
local function fetchSources(names)
    local sources = {}
    for _, name in ipairs(names) do
        local url = RAW_BASE .. name .. ".lua"
        local src, e = httpGet(url)
        if not src then
            recordErr(name, "fetch failed", e)
        else
            sources[name] = src
        end
    end
    return sources
end

local function compileAll(sources)
    local compiled = {}
    for name, src in pairs(sources) do
        local fn, ce = loadstring(src, "@" .. name .. ".lua")
        if not fn then
            recordErr(name, "compile error", ce)
        else
            compiled[name] = fn
        end
    end
    return compiled
end

--============================================================
-- REGISTER
--============================================================
local function registerAll(order, compiled)
    local mainMod = nil
    for _, name in ipairs(order) do
        local fn = compiled[name]
        if fn then
            local ok, mod = pcall(fn)
            if not ok then
                recordErr(name, "runtime error", mod)
            elseif mod == nil then
                recordErr(name, "returned nil — missing 'return' at end")
            else
                Ctx.Loaded[name] = true
                if name == "main" then
                    mainMod = mod
                else
                    for _, alias in ipairs(slotsFor(name)) do
                        Ctx[alias] = mod
                    end
                end
                log("info", "  + " .. name)
            end
        end
    end
    return mainMod
end

--============================================================
-- BOOT
--============================================================
local function bootMain(mainMod)
    if type(mainMod) ~= "table" or type(mainMod.boot) ~= "function" then
        recordErr("main", "main must return { boot = function(Ctx) }")
        return false
    end
    local ok, e = pcall(mainMod.boot, Ctx)
    if not ok then
        recordErr("main.boot", tostring(e))
        return false
    end
    log("info", "  + main.boot")
    return true
end

--============================================================
-- POST-BOOT SAFETY
-- main.boot's subsys list omits fly, but attack.lua calls
-- Ctx.Fly.start(). If fly was loaded but never initialized (no .tick
-- function exists yet), init it here so combat doesn't nil-call.
--============================================================
local function postBootSafety()
    if Ctx.Fly
        and type(Ctx.Fly.init) == "function"
        and type(Ctx.Fly.tick) ~= "function" then
        local ok, e = pcall(Ctx.Fly.init, Ctx)
        if ok then
            log("info", "  + fly.init (post-boot safety)")
        else
            recordWarn("fly.init", "post-boot init failed: " .. tostring(e))
        end
    end
end

--============================================================
-- ENTRY
--============================================================
print("=================================================")
print("  Dingus-Slayer · boot v26")
print("  " .. RAW_BASE)
print("=================================================")

local t0 = os.clock()

local names = discoverFiles()
log("info", string.format("discovered %d modules", #names))

local sources  = fetchSources(names)
log("info", string.format("fetched %d/%d", count(sources), #names))

local compiled = compileAll(sources)
log("info", string.format("compiled %d", count(compiled)))

local order, _deps = buildOrder(sources)
log("info", "load order: " .. table.concat(order, " → "))

local mainMod = registerAll(order, compiled)
local bootOk  = bootMain(mainMod)

postBootSafety()

local elapsed = os.clock() - t0
print("=================================================")
print(string.format("  boot %s in %.2fs",
    bootOk and "complete" or "incomplete", elapsed))
if #Ctx.Errors > 0 then
    print(string.format("  errors (%d):", #Ctx.Errors))
    for _, e in ipairs(Ctx.Errors) do
        print(string.format("    [%s] %s", e.stage, e.msg))
    end
end
if #Ctx.Warnings > 0 then
    print(string.format("  warnings (%d):", #Ctx.Warnings))
    for _, w in ipairs(Ctx.Warnings) do
        print(string.format("    [%s] %s", w.stage, w.msg))
    end
end
print("=================================================")

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Dingus-Slayer",
        Text = string.format("%s · %.1fs · %d errors",
            bootOk and "loaded" or "partial", elapsed, #Ctx.Errors),
        Duration = 5,
    })
end)
