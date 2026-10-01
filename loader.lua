--[[
    Dingus-Slayer · loader.lua
    Fetches, compiles, and boots all modules in order.
    Errors are logged to console AND to a crash buffer that survives partial failures.
]]--

local REPO_USER = "PurpleXPurple"
local REPO_NAME = "Dingus-Slayer"
local REPO_BRANCH = "main"
local BASE = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/",
    REPO_USER, REPO_NAME, REPO_BRANCH
)

local HTTP_TIMEOUT = 10
local MAX_RETRIES = 3
local RETRY_DELAY = 0.5

local Ctx = {
    Cfg = nil, St = nil,
    Util = nil, Detect = nil, Scan = nil,
    Spoof = nil, Atk = nil, Opt = nil,
    Gui = nil, Log = nil,
    Crow = nil,
    Started = false,
    BootStage = "init",
    Errors = {},
}

Ctx.St = Ctx.St or {}

local function logErr(stage, msg)
    local entry = string.format("[%s] %s: %s", os.date("%H:%M:%S"), stage, tostring(msg))
    table.insert(Ctx.Errors, entry)
    warn("[Dingus] " .. entry)
end

local function notify(title, body, dur)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title, Text = body, Duration = dur or 5,
        })
    end)
end

local function httpGet(url, retries)
    retries = retries or MAX_RETRIES
    for attempt = 1, retries do
        local ok, res = pcall(function()
            return game:HttpGet(url, true)
        end)
        if ok and type(res) == "string" and #res > 0 then
            return res
        end
        if attempt < retries then
            task.wait(RETRY_DELAY * attempt)
        end
    end
    return nil
end

local function fetch(name)
    Ctx.BootStage = "fetch:" .. name
    local url = BASE .. name .. ".lua"
    local code = httpGet(url, MAX_RETRIES)
    if not code then
        logErr(name, "HTTP fetch failed after " .. MAX_RETRIES .. " attempts")
        return nil
    end
    if #code < 50 then
        logErr(name, "suspiciously short response (" .. #code .. " bytes)")
        return nil
    end
    if string.find(code, "404: Not Found", 1, true) then
        logErr(name, "404 Not Found — check path/branch")
        return nil
    end
    Ctx.BootStage = "compile:" .. name
    local fn, err = loadstring(code, "@" .. name .. ".lua")
    if not fn then
        logErr(name, "compile error: " .. tostring(err))
        return nil
    end
    Ctx.BootStage = "execute:" .. name
    local ok, mod = pcall(fn)
    if not ok then
        logErr(name, "runtime error: " .. tostring(mod))
        return nil
    end
    if mod == nil then
        logErr(name, "returned nil — file may not have 'return' at end")
        return nil
    end
    return mod, code
end

-- Dependency order
local ORDER = {
    { name = "config",     slot = "Cfg" },
    { name = "utils",      slot = "Util" },
    { name = "detect",     slot = "Detect" },
    { name = "scanners",   slot = "Scan" },
    { name = "spoofers",   slot = "Spoof" },
    { name = "attack",     slot = "Atk" },
    { name = "optimizers", slot = "Opt" },
    { name = "gui",        slot = "Gui" },
    { name = "main",       slot = nil },
}

-- Preserve source snippets for debugging
Ctx.Sources = {}

local t0 = os.clock()

print("=================================================")
print("  Dingus-Slayer · loading from")
print("  " .. BASE)
print("=================================================")

for i = 1, #ORDER do
    local entry = ORDER[i]
    local name, slot = entry.name, entry.slot
    print(string.format("[%d/%d] loading %s ...", i, #ORDER, name))

    local mod, src = fetch(name)
    if not mod then
        logErr("abort", "cannot continue without '" .. name .. "'")
        notify("Dingus-Slayer", "Load failed at " .. name .. " (see console)", 10)
        print("=================================================")
        print("  LOAD FAILED at " .. name)
        print("  Errors logged:")
        for _, e in ipairs(Ctx.Errors) do print("    " .. e) end
        print("=================================================")
        return
    end

    Ctx.Sources[name] = src
    if slot then Ctx[slot] = mod end

    -- Handle the main module — call boot with context
    if name == "main" then
        if type(mod) ~= "table" or type(mod.boot) ~= "function" then
            logErr("main", "module must return a table with .boot(Ctx)")
            return
        end
        Ctx.BootStage = "main.boot"
        local ok, err = pcall(mod.boot, Ctx)
        if not ok then
            logErr("main.boot", tostring(err))
            notify("Dingus-Slayer", "Boot failed: " .. tostring(err):sub(1, 100), 10)
            return
        end
    end

    task.wait(0.05)
end

Ctx.Started = true
Ctx.BootStage = "done"
local elapsed = os.clock() - t0

print("=================================================")
print(string.format("  Dingus-Slayer loaded in %.2fs", elapsed))
if #Ctx.Errors > 0 then
    print("  Warnings during load:")
    for _, e in ipairs(Ctx.Errors) do print("    " .. e) end
end
print("=================================================")

notify("Dingus-Slayer", string.format("Loaded in %.1fs · %d warnings", elapsed, #Ctx.Errors), 6)
