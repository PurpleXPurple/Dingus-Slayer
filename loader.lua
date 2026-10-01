local REPO_USER = "PurpleXPurple"
local REPO_NAME = "Dingus-Slayer"
local REPO_BRANCH = "main"
local BASE = string.format("https://raw.githubusercontent.com/%s/%s/%s/", REPO_USER, REPO_NAME, REPO_BRANCH)

local MAX_RETRIES = 3
local RETRY_DELAY = 0.5

-- Safe console creator — if this fails, we still print to F9
local Console = { rows = {} }
local function initConsole()
    local ok, err = pcall(function()
        local parent = (gethui and gethui()) or game:GetService("CoreGui")
        local gui = Instance.new("ScreenGui")
        gui.Name = "DingusConsole"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.Parent = parent

        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 640, 0, 400)
        frame.Position = UDim2.new(0.5, -320, 0.5, -200)
        frame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
        frame.BorderSizePixel = 0
        frame.Active = true
        frame.Draggable = true
        frame.Parent = gui
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 30)
        title.BackgroundColor3 = Color3.fromRGB(35, 20, 18)
        title.BorderSizePixel = 0
        title.Text = "  Dingus Boot Console"
        title.TextColor3 = Color3.fromRGB(245, 220, 220)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Font = Enum.Font.GothamBold
        title.TextSize = 13
        title.Parent = frame

        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.new(1, -16, 1, -50)
        scroll.Position = UDim2.new(0, 8, 0, 38)
        scroll.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 6
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.Parent = frame

        local layout = Instance.new("UIListLayout", scroll)
        layout.Padding = UDim.new(0, 1)
        layout.SortOrder = Enum.SortOrder.LayoutOrder

        Console.scroll = scroll
        Console.frame = frame
        Console.rows = {}
        Console.order = 0
    end)
    if not ok then
        warn("[Dingus] console GUI failed: " .. tostring(err))
    end
end

initConsole()

function Console.log(level, msg)
    local line = string.format("[%s] %s", level, tostring(msg))
    print(line)
    if Console.scroll then
        pcall(function()
            Console.order = Console.order + 1
            local row = Instance.new("TextLabel")
            row.Size = UDim2.new(1, -6, 0, 14)
            row.BackgroundTransparency = 1
            row.Text = "  " .. line
            row.TextColor3 = (level == "err" and Color3.fromRGB(240,120,120))
                or (level == "warn" and Color3.fromRGB(240,200,100))
                or (level == "ok" and Color3.fromRGB(120,220,140))
                or Color3.fromRGB(200,210,220)
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.Font = Enum.Font.Code
            row.TextSize = 10
            row.LayoutOrder = Console.order
            row.Parent = Console.scroll
            table.insert(Console.rows, row)
            while #Console.rows > 300 do
                local o = table.remove(Console.rows, 1)
                if o then o:Destroy() end
            end
            Console.scroll.CanvasPosition = Vector2.new(0, Console.scroll.AbsoluteCanvasSize.Y)
        end)
    end
end

function Console.err(stage, msg)
    Console.log("err", stage .. ": " .. tostring(msg))
end

function Console.warn(stage, msg)
    Console.log("warn", stage .. ": " .. tostring(msg))
end

-- Context
local Ctx = { St = {}, Errors = {}, Console = Console }

local function logErr(stage, msg)
    table.insert(Ctx.Errors, { stage = stage, msg = msg })
    Console.err(stage, msg)
end

-- HTTP
local function httpGet(url, retries)
    retries = retries or MAX_RETRIES
    for attempt = 1, retries do
        Console.log("info", string.format("GET %s (try %d/%d)", url:sub(-50), attempt, retries))
        local ok, res = pcall(function() return game:HttpGet(url, true) end)
        if ok and type(res) == "string" and #res > 0 then return res end
        if not ok then Console.warn("http", tostring(res)) end
        if attempt < retries then task.wait(RETRY_DELAY * attempt) end
    end
    return nil
end

-- Fetch + compile + execute
local function fetch(name)
    local url = BASE .. name .. ".lua"
    local code = httpGet(url)
    if not code then logErr(name, "HTTP fetch failed"); return nil end
    if #code < 50 then logErr(name, "response too short"); return nil end
    if string.find(code, "404: Not Found", 1, true) then logErr(name, "404 Not Found"); return nil end

    local fn, err = loadstring(code, "@" .. name .. ".lua")
    if not fn then
        logErr(name, "compile error: " .. tostring(err))
        return nil
    end

    local ok, mod = pcall(fn)
    if not ok then
        logErr(name, "runtime error: " .. tostring(mod))
        return nil
    end
    if mod == nil then
        logErr(name, "returned nil — check for missing 'return' at end of file")
        return nil
    end

    Console.log("ok", "loaded " .. name)
    return mod
end

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

local t0 = os.clock()
Console.log("info", "Dingus-Slayer boot @ " .. BASE)

for i = 1, #ORDER do
    local entry = ORDER[i]
    Console.log("info", string.format("[%d/%d] loading %s", i, #ORDER, entry.name))
    local mod = fetch(entry.name)
    if not mod then
        logErr("abort", "cannot continue without '" .. entry.name .. "'")
        Console.log("err", "BOOT ABORTED")
        return
    end
    if entry.slot then Ctx[entry.slot] = mod end
    if entry.name == "main" then
        if type(mod) ~= "table" or type(mod.boot) ~= "function" then
            logErr("main", "must return { boot = function(Ctx) }")
            return
        end
        local ok, err = pcall(mod.boot, Ctx)
        if not ok then logErr("main.boot", tostring(err)); return end
    end
    task.wait(0.05)
end

local el = os.clock() - t0
Console.log("ok", string.format("boot complete in %.2fs", el))
