--[[
    Dingus-Slayer · loader.lua
    Minimal loader. All output goes to F9.
]]--

local REPO = "https://raw.githubusercontent.com/PurpleXPurple/Dingus-Slayer/main/"

local Ctx = { St = {}, Errors = {} }
local function log(lvl, msg)
    print(string.format("[Dingus][%s] %s", lvl, msg))
end

local function httpGet(url)
    for i = 1, 3 do
        local ok, res = pcall(function() return game:HttpGet(url, true) end)
        if ok and type(res) == "string" and #res > 50 then return res end
        task.wait(0.5)
    end
    return nil
end

local ORDER = {
    { name = "lists",      slot = "Lists" },
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

for i = 1, #ORDER do
    local e = ORDER[i]
    log("info", string.format("[%d/%d] %s", i, #ORDER, e.name))
    local code = httpGet(REPO .. e.name .. ".lua")
    if not code then
        log("err", e.name .. ": fetch failed")
        return
    end
    if string.find(code, "404: Not Found", 1, true) then
        log("err", e.name .. ": 404")
        return
    end
    local fn, err = loadstring(code, "@" .. e.name .. ".lua")
    if not fn then
        log("err", e.name .. ": compile — " .. tostring(err))
        return
    end
    local ok, mod = pcall(fn)
    if not ok then
        log("err", e.name .. ": runtime — " .. tostring(mod))
        return
    end
    if mod == nil then
        log("err", e.name .. ": nil return")
        return
    end
    if e.slot then Ctx[e.slot] = mod end
    if e.name == "main" then
        if type(mod) ~= "table" or type(mod.boot) ~= "function" then
            log("err", "main: missing boot")
            return
        end
        local ok2, err2 = pcall(mod.boot, Ctx)
        if not ok2 then
            log("err", "main.boot: " .. tostring(err2))
            return
        end
    end
    task.wait(0.03)
end

log("ok", "boot complete")
