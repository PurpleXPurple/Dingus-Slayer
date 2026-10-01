--[[
    Dingus-Slayer · loader.lua
    Self-contained console GUI boots first, survives any module failure.
    Logs every stage: fetch / compile / execute / boot / runtime.
]]--

local REPO_USER = "PurpleXPurple"
local REPO_NAME = "Dingus-Slayer"
local REPO_BRANCH = "main"
local BASE = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/",
    REPO_USER, REPO_NAME, REPO_BRANCH
)

local MAX_RETRIES = 3
local RETRY_DELAY = 0.5

--============================================================
-- CONSOLE GUI (self-contained, zero dependencies)
--============================================================
local Console = {}
do
    local CoreGui = game:GetService("CoreGui")
    local parent = (gethui and gethui()) or CoreGui

    local gui = Instance.new("ScreenGui")
    gui.Name = "DingusConsole"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 680, 0, 440)
    frame.Position = UDim2.new(0.5, -340, 0.5, -220)
    frame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    local frameStroke = Instance.new("UIStroke", frame)
    frameStroke.Color = Color3.fromRGB(200, 90, 70)
    frameStroke.Thickness = 1

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(35, 20, 18)
    title.BorderSizePixel = 0
    title.Text = "  Dingus-Slayer · Boot Console"
    title.TextColor3 = Color3.fromRGB(245, 220, 220)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.Parent = frame
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

    local stageLbl = Instance.new("TextLabel")
    stageLbl.Size = UDim2.new(0, 300, 0, 20)
    stageLbl.Position = UDim2.new(0, 8, 0, 34)
    stageLbl.BackgroundTransparency = 1
    stageLbl.Text = "stage: init"
    stageLbl.TextColor3 = Color3.fromRGB(160, 180, 200)
    stageLbl.TextXAlignment = Enum.TextXAlignment.Left
    stageLbl.Font = Enum.Font.Code
    stageLbl.TextSize = 11
    stageLbl.Parent = frame

    local errCountLbl = Instance.new("TextLabel")
    errCountLbl.Size = UDim2.new(0, 200, 0, 20)
    errCountLbl.Position = UDim2.new(1, -208, 0, 34)
    errCountLbl.BackgroundTransparency = 1
    errCountLbl.Text = "errors: 0  ·  warnings: 0"
    errCountLbl.TextColor3 = Color3.fromRGB(240, 200, 100)
    errCountLbl.TextXAlignment = Enum.TextXAlignment.Right
    errCountLbl.Font = Enum.Font.Code
    errCountLbl.TextSize = 11
    errCountLbl.Parent = frame

    -- Close / minimize buttons
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 22, 0, 22)
    closeBtn.Position = UDim2.new(1, -28, 0, 4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 50)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 12
    closeBtn.Parent = frame
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 22, 0, 22)
    minBtn.Position = UDim2.new(1, -54, 0, 4)
    minBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 60)
    minBtn.BorderSizePixel = 0
    minBtn.Text = "_"
    minBtn.TextColor3 = Color3.new(1, 1, 1)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 12
    minBtn.Parent = frame
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 5)

    -- Scrollable log
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -16, 1, -120)
    scroll.Position = UDim2.new(0, 8, 0, 60)
    scroll.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = frame
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)

    local layout = Instance.new("UIListLayout", scroll)
    layout.Padding = UDim.new(0, 1)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    local rows = {}
    local order = 0
    local maxRows = 400
    local autoScroll = true

    scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        local maxY = scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y
        autoScroll = scroll.CanvasPosition.Y >= maxY - 30
    end)

    local COLORS = {
        info = Color3.fromRGB(200, 210, 220),
        ok = Color3.fromRGB(120, 220, 140),
        warn = Color3.fromRGB(240, 200, 100),
        err = Color3.fromRGB(240, 120, 120),
        debug = Color3.fromRGB(140, 160, 200),
        fetch = Color3.fromRGB(100, 180, 240),
        stage = Color3.fromRGB(200, 140, 240),
    }

    function Console.log(level, msg, detail)
        order = order + 1
        local row = Instance.new("TextLabel")
        row.Size = UDim2.new(1, -6, 0, 14)
        row.BackgroundTransparency = 1
        local prefix = "  "
        if level == "err" then prefix = "  ✗ "
        elseif level == "warn" then prefix = "  ! "
        elseif level == "ok" then prefix = "  ✓ "
        elseif level == "fetch" then prefix = "  → "
        elseif level == "stage" then prefix = "  ◆ "
        end
        row.Text = prefix .. tostring(msg)
        row.TextColor3 = COLORS[level] or COLORS.info
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.Font = Enum.Font.Code
        row.TextSize = 11
        row.LayoutOrder = order
        row.Parent = scroll

        if detail then
            order = order + 1
            local drow = Instance.new("TextLabel")
            drow.Size = UDim2.new(1, -20, 0, 12)
            drow.BackgroundTransparency = 1
            drow.Text = "      " .. tostring(detail)
            drow.TextColor3 = Color3.fromRGB(160, 170, 190)
            drow.TextXAlignment = Enum.TextXAlignment.Left
            drow.Font = Enum.Font.Code
            drow.TextSize = 10
            drow.LayoutOrder = order
            drow.Parent = scroll
            table.insert(rows, drow)
        end

        table.insert(rows, row)
        while #rows > maxRows do
            local o = table.remove(rows, 1)
            if o then o:Destroy() end
        end

        if autoScroll then
            task.defer(function()
                scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
            end)
        end

        print(string.format("[Dingus][%s] %s", level, msg))
    end

    -- Error/warning counter
    local errN, warnN = 0, 0
    local function updateCounters()
        errCountLbl.Text = string.format("errors: %d  ·  warnings: %d", errN, warnN)
    end

    function Console.err(msg, detail)
        errN = errN + 1
        updateCounters()
        Console.log("err", msg, detail)
    end

    function Console.warn(msg, detail)
        warnN = warnN + 1
        updateCounters()
        Console.log("warn", msg, detail)
    end

    function Console.stage(name)
        stageLbl.Text = "stage: " .. tostring(name)
        Console.log("stage", name)
    end

    -- Bottom bar
    local btnBar = Instance.new("Frame")
    btnBar.Size = UDim2.new(1, -16, 0, 34)
    btnBar.Position = UDim2.new(0, 8, 1, -42)
    btnBar.BackgroundTransparency = 1
    btnBar.Parent = frame

    local function mkBtn(label, pos, color, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 120, 1, 0)
        b.Position = UDim2.new(0, pos, 0, 0)
        b.BackgroundColor3 = color
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.Parent = btnBar
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        b.MouseButton1Click:Connect(cb)
        return b
    end

    mkBtn("Copy Log", 0, Color3.fromRGB(60, 90, 140), function()
        local out = {}
        for _, r in ipairs(rows) do
            table.insert(out, r.Text)
        end
        local payload = table.concat(out, "\n")
        pcall(function() setclipboard(payload) end)
        Console.log("ok", "copied " .. #out .. " lines to clipboard")
    end)

    mkBtn("Save to File", 126, Color3.fromRGB(60, 90, 60), function()
        local out = {}
        for _, r in ipairs(rows) do
            table.insert(out, r.Text)
        end
        local payload = table.concat(out, "\n")
        pcall(function() writefile("dingus_boot_log.txt", payload) end)
        Console.log("ok", "saved to dingus_boot_log.txt")
    end)

    mkBtn("Clear", 252, Color3.fromRGB(90, 60, 60), function()
        for _, r in ipairs(rows) do r:Destroy() end
        rows = {}
        order = 0
    end)

    mkBtn("Reload Script", 378, Color3.fromRGB(140, 90, 60), function()
        pcall(function()
            loadstring(game:HttpGet(BASE .. "loader.lua"))()
        end)
    end)

    minBtn.MouseButton1Click:Connect(function()
        frame.Visible = not frame.Visible
    end)

    closeBtn.MouseButton1Click:Connect(function()
        gui:Destroy()
    end)

    Console.gui = gui
    Console.frame = frame
end

--============================================================
-- CONTEXT
--============================================================
local Ctx = {
    Cfg = nil, St = {},
    Util = nil, Detect = nil, Scan = nil,
    Spoof = nil, Atk = nil, Opt = nil,
    Gui = nil, Log = nil, Crow = nil,
    Started = false,
    Errors = {},
    Console = Console,
}

local function logErr(stage, msg, detail)
    table.insert(Ctx.Errors, { stage = stage, msg = msg, detail = detail })
    Console.err(stage .. ": " .. tostring(msg), detail)
end

local function notify(title, body, dur)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title, Text = body, Duration = dur or 5,
        })
    end)
end

--============================================================
-- HTTP WITH RETRIES
--============================================================
local function httpGet(url, retries)
    retries = retries or MAX_RETRIES
    for attempt = 1, retries do
        Console.log("fetch", string.format("GET %s (try %d/%d)", url:sub(-40), attempt, retries))
        local ok, res = pcall(function() return game:HttpGet(url, true) end)
        if ok and type(res) == "string" and #res > 0 then
            return res
        end
        if not ok then
            Console.warn("http error", tostring(res))
        end
        if attempt < retries then task.wait(RETRY_DELAY * attempt) end
    end
    return nil
end

--============================================================
-- ERROR CONTEXT EXTRACTOR
--============================================================
local function extractLineContext(source, errMsg)
    local lineNum = tonumber(errMsg:match("%[(%d+)%]"))
        or tonumber(errMsg:match(":(%d+):"))
    if not lineNum then return nil end

    local lines = {}
    for l in source:gmatch("[^\r\n]*") do
        table.insert(lines, l)
    end

    local from = math.max(1, lineNum - 2)
    local to = math.min(#lines, lineNum + 2)
    local out = {}
    for i = from, to do
        local marker = (i == lineNum) and " >> " or "    "
        table.insert(out, string.format("%s%d | %s", marker, i, lines[i] or ""))
    end
    return table.concat(out, "\n"), lineNum
end

--============================================================
-- FETCH + COMPILE + EXECUTE
--============================================================
local function fetch(name)
    Console.stage("fetch:" .. name)
    local url = BASE .. name .. ".lua"
    local code = httpGet(url, MAX_RETRIES)

    if not code then
        logErr(name, "HTTP fetch failed after " .. MAX_RETRIES .. " attempts", url)
        return nil
    end

    if #code < 50 then
        logErr(name, "response too short (" .. #code .. " bytes)",
            "first 200 chars: " .. code:sub(1, 200))
        return nil
    end

    if string.find(code, "404: Not Found", 1, true) then
        logErr(name, "404 Not Found", url)
        return nil
    end

    Console.stage("compile:" .. name)
    local fn, err = loadstring(code, "@" .. name .. ".lua")
    if not fn then
        local ctx = extractLineContext(code, tostring(err))
        logErr(name, "compile error", tostring(err) .. (ctx and ("\n" .. ctx) or ""))
        return nil
    end

    Console.stage("execute:" .. name)
    local ok, mod = pcall(fn)
    if not ok then
        local ctx = extractLineContext(code, tostring(mod))
        logErr(name, "runtime error", tostring(mod) .. (ctx and ("\n" .. ctx) or ""))
        return nil
    end

    if mod == nil then
        logErr(name, "returned nil — file has no 'return X' at end")
        return nil
    end

    Console.log("ok", "loaded " .. name)
    return mod, code
end

--============================================================
-- ORDER
--============================================================
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

Ctx.Sources = {}

--============================================================
-- BOOT
--============================================================
local t0 = os.clock()

Console.log("stage", "Dingus-Slayer boot @ " .. BASE)
Console.log("info", "executor: " .. tostring(identifyexecutor and identifyexecutor() or "?"))

for i = 1, #ORDER do
    local entry = ORDER[i]
    local name, slot = entry.name, entry.slot
    Console.stage(string.format("%d/%d · %s", i, #ORDER, name))

    local mod, src = fetch(name)
    if not mod then
        logErr("abort", "cannot continue without '" .. name .. "'")
        Console.log("err", "=== BOOT ABORTED at " .. name .. " ===")
        notify("Dingus-Slayer", "Load failed at " .. name .. " — check console", 10)
        return
    end

    Ctx.Sources[name] = src
    if slot then Ctx[slot] = mod end

    if name == "main" then
        if type(mod) ~= "table" or type(mod.boot) ~= "function" then
            logErr("main", "module must return { boot = function(Ctx) ... }")
            return
        end
        Console.stage("main.boot")
        local ok, err = pcall(mod.boot, Ctx)
        if not ok then
            logErr("main.boot", tostring(err), extractLineContext(src, tostring(err)) or "")
            notify("Dingus-Slayer", "Boot failed: " .. tostring(err):sub(1, 80), 10)
            return
        end
    end

    task.wait(0.05)
end

Ctx.Started = true
Ctx.BootStage = "done"
local elapsed = os.clock() - t0

Console.log("ok", string.format("boot complete in %.2fs", elapsed))
if #Ctx.Errors > 0 then
    Console.warn("boot finished with " .. #Ctx.Errors .. " error(s)")
else
    Console.log("ok", "no errors")
end

notify("Dingus-Slayer", string.format("Loaded in %.1fs · %d errors", elapsed, #Ctx.Errors), 6)
