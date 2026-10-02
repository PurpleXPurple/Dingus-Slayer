--[[
    Dingus-Slayer · loader.lua v27
    Fetches, compiles, executes, and slots every module.
    Prints full error text — no more masked "runtime error" lines.

    Structure:
      1. Fetch each module over HTTP
      2. Compile with loadstring
      3. Execute to get the returned table
      4. Slot the table into Ctx under canonical + alias names
      5. Boot main with the populated Ctx
      6. Print summary including full error detail
]]--

local REPO_USER   = "PurpleXPurple"
local REPO_NAME   = "Dingus-Slayer"
local REPO_BRANCH = "main"
local RAW_BASE = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/",
    REPO_USER, REPO_NAME, REPO_BRANCH
)

--============================================================
-- MANIFEST
-- name = filename stem · slots = Ctx keys to register under
--============================================================
local MANIFEST = {
    { name = "config",     slots = { "Cfg", "Config" } },
    { name = "lists",      slots = { "Lists" } },
    { name = "utils",      slots = { "Util", "Utils", "U" } },
    { name = "detect",     slots = { "Detect", "D" } },
    { name = "scanners",   slots = { "Scan", "Scanner", "Scanners" } },
    { name = "spoofers",   slots = { "Spoof", "Spoofer", "Spoofers" } },
    { name = "fly",        slots = { "Fly", "FlyMod" } },
    { name = "attack",     slots = { "Atk", "Attack" } },
    { name = "optimizers", slots = { "Opt", "Optimizer", "Optimizers" } },
    { name = "gui",        slots = { "Gui", "GUI" } },
    { name = "main",       slots = nil },  -- special: booted, not slotted
}

local MAX_RETRY   = 2
local RETRY_DELAY = 0.4
local MIN_SOURCE  = 16

--============================================================
-- BOOT ID (random hex so multi-session logs are distinguishable)
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
    StartTime = os.clock(),
    BootId    = bootId,
}

--============================================================
-- LOGGING
--============================================================
local function log(level, msg)
    local prefix = "[Dingus][" .. level .. "]"
    if level == "err" then
        warn(prefix .. " " .. msg)
    else
        print(prefix .. " " .. msg)
    end
end

local function recordErr(stage, msg, detail)
    table.insert(Ctx.Errors, { stage = stage, msg = msg, detail = detail })
end

local function recordWarn(stage, msg)
    table.insert(Ctx.Warnings, { stage = stage, msg = msg })
    log("warn", stage .. ": " .. msg)
end

--============================================================
-- HTTP
--============================================================
local function httpGet(url)
    local lastErr
    for attempt = 1, MAX_RETRY do
        local ok, res = pcall(function() return game:HttpGet(url, true) end)
        if ok and type(res) == "string" and #res >= MIN_SOURCE then
            return res, nil
        end
        lastErr = ok and ("short response: " .. tostring(res and #res or "nil"))
                 or ("raised: " .. tostring(res))
        if attempt < MAX_RETRY then task.wait(RETRY_DELAY) end
    end
    return nil, lastErr
end

--============================================================
-- FETCH + COMPILE + EXECUTE
-- Returns: table module, or nil + error triple
--============================================================
local function loadModule(entry)
    local name = entry.name
    local url = RAW_BASE .. name .. ".lua"

    -- Fetch
    local src, fetchErr = httpGet(url)
    if not src then
        return nil, "fetch-fail", fetchErr
    end
    if string.find(src, "404: Not Found", 1, true) then
        return nil, "404", url
    end

    -- Compile
    local fn, compileErr = loadstring(src, "@" .. name .. ".lua")
    if not fn then
        return nil, "compile-fail", tostring(compileErr)
    end

    -- Execute
    local ok, mod = pcall(fn)
    if not ok then
        return nil, "runtime-fail", tostring(mod)
    end
    if mod == nil then
        return nil, "returns-nil", "file missing 'return' at end"
    end
    if type(mod) ~= "table" then
        return nil, "wrong-type", "returned " .. type(mod) .. ", expected table"
    end

    return mod, nil, nil
end

--============================================================
-- REGISTER SLOTS
--============================================================
local function registerSlots(mod, slots)
    if not slots then return end
    for _, key in ipairs(slots) do
        Ctx[key] = mod
    end
end

--============================================================
-- BOOT
--============================================================
print("=================================================")
print("  Dingus-Slayer · boot v27 · id=" .. bootId)
print("  " .. RAW_BASE)
print("=================================================")

local t0 = os.clock()
local loadedCount = 0
local mainMod = nil

for i = 1, #MANIFEST do
    local entry = MANIFEST[i]
    local name = entry.name

    -- Load
    local mod, errKind, errDetail = loadModule(entry)

    if not mod then
        log("err", string.format("%s — %s%s",
            name, errKind,
            errDetail and (" — " .. tostring(errDetail)) or ""))
        recordErr(name, errKind, errDetail)
        Ctx.Loaded[name] = false
    else
        loadedCount = loadedCount + 1
        Ctx.Loaded[name] = true

        if name == "main" then
            mainMod = mod
            if type(mod.boot) ~= "function" then
                log("warn", "main has no .boot function")
                recordWarn("main", "missing .boot")
            else
                log("info", "  + " .. name .. " (boot fn present)")
            end
        else
            registerSlots(mod, entry.slots)
            log("info", "  + " .. name)
        end
    end

    task.wait(0.02)
end

--============================================================
-- BOOT MAIN
--============================================================
local bootOk = false
if mainMod and type(mainMod.boot) == "function" then
    log("info", "calling main.boot")
    local ok, err = pcall(mainMod.boot, Ctx)
    if ok then
        bootOk = true
        log("info", "  + main.boot returned cleanly")
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
-- POST-BOOT SAFETY (fly)
-- If fly was loaded but not initialized, init it now.
--============================================================
if not bootOk then
    if Ctx.Fly and type(Ctx.Fly.init) == "function"
       and type(Ctx.Fly.tick) ~= "function" then
        local ok, err = pcall(Ctx.Fly.init, Ctx)
        if ok then
            log("info", "  + fly.init (post-boot fallback)")
        else
            log("warn", "fly.init fallback failed: " .. tostring(err))
        end
    end
end

--============================================================
-- SUMMARY
--============================================================
local elapsed = os.clock() - t0
print("=================================================")
print(string.format("  boot %s in %.2fs  ·  %d/%d modules loaded",
    bootOk and "complete" or "incomplete",
    elapsed, loadedCount, #MANIFEST))
print("=================================================")

if #Ctx.Errors > 0 then
    print(string.format("  errors (%d):", #Ctx.Errors))
    for _, e in ipairs(Ctx.Errors) do
        print(string.format("    [%s] %s%s",
            e.stage,
            e.msg,
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

--============================================================
-- NOTIFICATION
--============================================================
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Dingus-Slayer",
        Text = string.format("%s · %.1fs · %d errors",
            bootOk and "loaded" or "incomplete",
            elapsed, #Ctx.Errors),
        Duration = 5,
    })
end)
