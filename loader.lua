local B = "https://raw.githubusercontent.com/PurpleX/Dingus-Slayer/main/"

local Ctx = {
    Cfg = nil, St = nil,
    Util = nil, Detect = nil, Scan = nil,
    Spoof = nil, Atk = nil, Opt = nil,
    Gui = nil, Log = nil,
    Started = false,
}

local function fetch(name)
    local ok, code = pcall(function()
        return game:HttpGet(B .. name .. ".lua")
    end)
    if not ok or not code then
        warn("[PS2] fetch failed: " .. name)
        return nil
    end
    local fn, err = loadstring(code)
    if not fn then
        warn("[PS2] compile failed: " .. name .. " — " .. tostring(err))
        return nil
    end
    local ok2, mod = pcall(fn)
    if not ok2 then
        warn("[PS2] run failed: " .. name .. " — " .. tostring(mod))
        return nil
    end
    return mod
end

local order = {
    { "config", "Cfg" },
    { "utils", "Util" },
    { "detect", "Detect" },
    { "scanners", "Scan" },
    { "spoofers", "Spoof" },
    { "attack", "Atk" },
    { "optimizers", "Opt" },
    { "gui", "Gui" },
    { "main", nil },
}

for i = 1, #order do
    local entry = order[i]
    local name, slot = entry[1], entry[2]
    print("[PS2] loading " .. name)
    local mod = fetch(name)
    if not mod then
        warn("[PS2] abort at " .. name)
        return
    end
    if slot then Ctx[slot] = mod end
    if name == "main" and type(mod) == "table" and mod.boot then
        mod.boot(Ctx)
    end
    task.wait(0.05)
end

Ctx.Started = true
