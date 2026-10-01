--[[
    Dingus-Slayer · gui.lua v27
    Six tabs. Log manager (live capture). Config slot manager (multi-file).
    File browser. Encapsulated control builders. Clean minimize/restore.
]]--

local G = {}

function G.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St
    local Tween = game:GetService("TweenService")
    local UIS = game:GetService("UserInputService")
    local LogService = game:GetService("LogService")

    --============================================================
    -- CAPABILITY DETECTION
    --============================================================
    local HAS = {
        writefile = type(writefile) == "function",
        readfile  = type(readfile) == "function",
        delfile   = type(delfile) == "function",
        isfile    = type(isfile) == "function",
        listfiles = type(listfiles) == "function",
        makefolder= type(makefolder) == "function",
    }

    --============================================================
    -- COLOR PALETTE
    --============================================================
    local CLR = {
        bg        = Color3.fromRGB(14, 14, 18),
        bgHeader  = Color3.fromRGB(30, 18, 16),
        bgPanel   = Color3.fromRGB(20, 20, 28),
        bgRow     = Color3.fromRGB(24, 24, 32),
        bgSlider  = Color3.fromRGB(38, 38, 48),
        bgInput   = Color3.fromRGB(18, 18, 24),
        border    = Color3.fromRGB(200, 90, 70),
        accent    = Color3.fromRGB(220, 90, 70),
        accentDim = Color3.fromRGB(150, 60, 50),
        green     = Color3.fromRGB(70, 180, 100),
        red       = Color3.fromRGB(200, 60, 70),
        blue      = Color3.fromRGB(60, 130, 200),
        purple    = Color3.fromRGB(130, 80, 180),
        orange    = Color3.fromRGB(180, 120, 60),
        text      = Color3.fromRGB(230, 230, 240),
        textDim   = Color3.fromRGB(160, 170, 190),
        textMuted = Color3.fromRGB(120, 130, 150),
        logInfo   = Color3.fromRGB(200, 200, 210),
        logWarn   = Color3.fromRGB(240, 200, 100),
        logError  = Color3.fromRGB(240, 120, 120),
        logDingus = Color3.fromRGB(140, 220, 180),
    }

    --============================================================
    -- LOG MANAGER
    --============================================================
    local Log = {
        buffer = {},
        maxLines = 300,
        filter = "all",
        paused = false,
        pendingUpdate = false,
        subscribers = {},
    }

    function Log.add(text, msgType)
        if Log.paused then return end
        if Log.filter == "dingus" and not string.find(text, "Dingus", 1, true) then return end
        if Log.filter == "errors" and msgType ~= Enum.MessageType.MessageError then return end

        table.insert(Log.buffer, {
            text = text,
            type = msgType,
            time = os.date("%H:%M:%S"),
        })
        if #Log.buffer > Log.maxLines then
            table.remove(Log.buffer, 1)
        end
        Log.pendingUpdate = true
    end

    function Log.clear()
        Log.buffer = {}
        Log.pendingUpdate = true
    end

    function Log.export(filename)
        if not HAS.writefile then return false, "no writefile" end
        local lines = {}
        for i = 1, #Log.buffer do
            local e = Log.buffer[i]
            lines[#lines+1] = string.format("[%s] %s", e.time, e.text)
        end
        local ok = pcall(writefile, filename, table.concat(lines, "\n"))
        return ok
    end

    function Log.onUpdate(fn)
        table.insert(Log.subscribers, fn)
    end

    -- Hook LogService
    pcall(function()
        LogService.MessageOut:Connect(function(msg, msgType)
            pcall(Log.add, msg, msgType)
        end)
    end)

    -- Also hook print/warn for executors that don't route through LogService
    do
        local oldPrint = print
        local oldWarn = warn
        local function safeHook(msg, level)
            if type(msg) ~= "string" then
                if type(msg) == "table" then
                    local ok, s = pcall(function() return tostring(msg) end)
                    msg = ok and s or "[table]"
                else
                    msg = tostring(msg)
                end
            end
            pcall(Log.add, msg, level)
        end
        _G.print = function(...)
            local args = { ... }
            local out = {}
            for i = 1, #args do out[i] = tostring(args[i]) end
            local joined = table.concat(out, " ")
            safeHook(joined, Enum.MessageType.MessageOutput)
            return oldPrint(...)
        end
        _G.warn = function(...)
            local args = { ... }
            local out = {}
            for i = 1, #args do out[i] = tostring(args[i]) end
            local joined = table.concat(out, " ")
            safeHook(joined, Enum.MessageType.MessageWarning)
            return oldWarn(...)
        end
    end

    --============================================================
    -- FILE MANAGER
    --============================================================
    local FileMgr = {
        files = {},
        rootFolder = "Dingus",
    }

    if HAS.makefolder then
        pcall(makefolder, FileMgr.rootFolder)
    end

    function FileMgr.refresh()
        FileMgr.files = {}
        if not HAS.listfiles then
            -- Fallback: check known files
            local known = {
                Cfg.ConfigFile or "dingus_config.json",
                "dingus_boot_log.txt",
                "dingus_combat_log.txt",
            }
            for _, f in ipairs(known) do
                if HAS.isfile and isfile(f) then
                    local size = 0
                    if HAS.readfile then
                        local ok, content = pcall(readfile, f)
                        if ok and content then size = #content end
                    end
                    table.insert(FileMgr.files, { name = f, size = size })
                end
            end
            return FileMgr.files
        end

        local ok, list = pcall(listfiles, FileMgr.rootFolder)
        if not ok or not list then
            ok, list = pcall(listfiles)
        end
        if ok and list then
            for _, f in ipairs(list) do
                local name = f:match("[^\\/]+$") or f
                local size = 0
                if HAS.readfile then
                    local okR, content = pcall(readfile, f)
                    if okR and content then size = #content end
                end
                table.insert(FileMgr.files, { name = name, path = f, size = size })
            end
        end
        return FileMgr.files
    end

    function FileMgr.delete(path)
        if not HAS.delfile then return false, "no delfile" end
        return pcall(delfile, path)
    end

    function FileMgr.read(path)
        if not HAS.readfile then return nil, "no readfile" end
        local ok, content = pcall(readfile, path)
        if not ok then return nil, tostring(content) end
        return content
    end

    function FileMgr.write(path, content)
        if not HAS.writefile then return false, "no writefile" end
        return pcall(writefile, path, content)
    end

    --============================================================
    -- CONFIG MANAGER
    --============================================================
    local ConfigMgr = {
        currentSlot = "default",
        slots = {},
        basePrefix = "dingus_config_",
    }

    function ConfigMgr.slotFilename(slot)
        return ConfigMgr.basePrefix .. (slot or "default") .. ".json"
    end

    function ConfigMgr.saveTo(slot)
        slot = slot or ConfigMgr.currentSlot
        if not Ctx.Cfg or not Ctx.Cfg.snapshot then return false, "no config" end
        local s = game:GetService("HttpService")
        local ok, encoded = pcall(function() return s:JSONEncode(Ctx.Cfg.snapshot()) end)
        if not ok or not encoded then return false, "encode failed" end
        return FileMgr.write(ConfigMgr.slotFilename(slot), encoded)
    end

    function ConfigMgr.loadFrom(slot)
        slot = slot or ConfigMgr.currentSlot
        local content, err = FileMgr.read(ConfigMgr.slotFilename(slot))
        if not content then return false, err or "no file" end
        local s = game:GetService("HttpService")
        local ok, data = pcall(function() return s:JSONDecode(content) end)
        if not ok or type(data) ~= "table" then return false, "decode failed" end
        if Ctx.Cfg and Ctx.Cfg.apply then
            Ctx.Cfg.apply(data)
            return true, "loaded " .. slot
        end
        return false, "no apply function"
    end

    function ConfigMgr.listSlots()
        local out = {}
        local all = FileMgr.refresh()
        for _, f in ipairs(all) do
            local name = f.name or ""
            local slot = name:match("^" .. ConfigMgr.basePrefix .. "(.-)%.json$")
            if slot then
                table.insert(out, { name = slot, path = f.path, size = f.size })
            end
        end
        return out
    end

    function ConfigMgr.deleteSlot(slot)
        return FileMgr.delete(ConfigMgr.slotFilename(slot))
    end

    --============================================================
    -- ROOT GUI
    --============================================================
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    local old = parent:FindFirstChild("DingusUI")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "DingusUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    local WIN_W, WIN_H = 620, 540
    local PILL_W, PILL_H = 150, 34

    --============================================================
    -- WINDOW
    --============================================================
    local win = Instance.new("Frame")
    win.Name = "Window"
    win.Size = UDim2.new(0, WIN_W, 0, WIN_H)
    win.Position = UDim2.new(0.5, -WIN_W/2, 0.5, -WIN_H/2)
    win.BackgroundColor3 = CLR.bg
    win.BorderSizePixel = 0
    win.Active = true
    win.Draggable = true
    win.Parent = gui
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 10)
    local winStroke = Instance.new("UIStroke", win)
    winStroke.Color = CLR.border
    winStroke.Thickness = 1
    winStroke.Transparency = 0.3

    --============================================================
    -- TITLE BAR
    --============================================================
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 34)
    titleBar.BackgroundColor3 = CLR.bgHeader
    titleBar.BorderSizePixel = 0
    titleBar.Parent = win
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 10)
    titleFix.Position = UDim2.new(0, 0, 1, -10)
    titleFix.BackgroundColor3 = CLR.bgHeader
    titleFix.BorderSizePixel = 0
    titleFix.Parent = titleBar

    local titleDot = Instance.new("Frame")
    titleDot.Size = UDim2.new(0, 8, 0, 8)
    titleDot.Position = UDim2.new(0, 14, 0, 13)
    titleDot.BackgroundColor3 = CLR.accent
    titleDot.BorderSizePixel = 0
    titleDot.Parent = titleBar
    Instance.new("UICorner", titleDot).CornerRadius = UDim.new(1, 0)

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -100, 1, 0)
    titleLbl.Position = UDim2.new(0, 28, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "Dingus-Slayer"
    titleLbl.TextColor3 = CLR.text
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 13
    titleLbl.Parent = titleBar

    local function mkCtrlBtn(txt, xOff, bgColor, hoverColor)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 22, 0, 22)
        b.Position = UDim2.new(1, xOff, 0, 6)
        b.BackgroundColor3 = bgColor
        b.BorderSizePixel = 0
        b.Text = txt
        b.TextColor3 = CLR.text
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.Parent = titleBar
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        b.MouseEnter:Connect(function()
            Tween:Create(b, TweenInfo.new(0.15), { BackgroundColor3 = hoverColor }):Play()
        end)
        b.MouseLeave:Connect(function()
            Tween:Create(b, TweenInfo.new(0.15), { BackgroundColor3 = bgColor }):Play()
        end)
        return b
    end

    local closeBtn = mkCtrlBtn("×", -30, CLR.red, Color3.fromRGB(240, 90, 100))
    local minBtn = mkCtrlBtn("–", -56, Color3.fromRGB(60, 60, 75), Color3.fromRGB(90, 90, 110))

    --============================================================
    -- TAB BAR + CONTENT
    --============================================================
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -16, 0, 30)
    tabBar.Position = UDim2.new(0, 8, 0, 42)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = win
    local tLay = Instance.new("UIListLayout", tabBar)
    tLay.FillDirection = Enum.FillDirection.Horizontal
    tLay.Padding = UDim.new(0, 4)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -16, 1, -140)
    content.Position = UDim2.new(0, 8, 0, 80)
    content.BackgroundColor3 = CLR.bgPanel
    content.BorderSizePixel = 0
    content.Parent = win
    Instance.new("UICorner", content).CornerRadius = UDim.new(0, 8)

    local statusBar = Instance.new("TextLabel")
    statusBar.Size = UDim2.new(1, -16, 0, 44)
    statusBar.Position = UDim2.new(0, 8, 1, -52)
    statusBar.BackgroundColor3 = CLR.bgPanel
    statusBar.BorderSizePixel = 0
    statusBar.Text = "  ready"
    statusBar.TextColor3 = CLR.textDim
    statusBar.TextXAlignment = Enum.TextXAlignment.Left
    statusBar.TextYAlignment = Enum.TextYAlignment.Top
    statusBar.Font = Enum.Font.Code
    statusBar.TextSize = 10
    statusBar.TextWrapped = true
    statusBar.Parent = win
    Instance.new("UICorner", statusBar).CornerRadius = UDim.new(0, 8)

    --============================================================
    -- MINIMIZED PILL
    --============================================================
    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0, PILL_W, 0, PILL_H)
    pill.Position = UDim2.new(0, 20, 0.5, -PILL_H/2)
    pill.BackgroundColor3 = CLR.bg
    pill.BorderSizePixel = 0
    pill.Active = true
    pill.Draggable = true
    pill.Visible = false
    pill.Parent = gui
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local pillStroke = Instance.new("UIStroke", pill)
    pillStroke.Color = CLR.border
    pillStroke.Thickness = 1.5

    local pillDot = Instance.new("Frame")
    pillDot.Size = UDim2.new(0, 8, 0, 8)
    pillDot.Position = UDim2.new(0, 14, 0.5, -4)
    pillDot.BackgroundColor3 = CLR.accent
    pillDot.BorderSizePixel = 0
    pillDot.Parent = pill
    Instance.new("UICorner", pillDot).CornerRadius = UDim.new(1, 0)

    local pillLbl = Instance.new("TextLabel")
    pillLbl.Size = UDim2.new(1, -32, 1, 0)
    pillLbl.Position = UDim2.new(0, 28, 0, 0)
    pillLbl.BackgroundTransparency = 1
    pillLbl.Text = "Dingus"
    pillLbl.TextColor3 = CLR.text
    pillLbl.TextXAlignment = Enum.TextXAlignment.Left
    pillLbl.Font = Enum.Font.GothamBold
    pillLbl.TextSize = 12
    pillLbl.Parent = pill

    local pillBtn = Instance.new("TextButton")
    pillBtn.Size = UDim2.new(1, 0, 1, 0)
    pillBtn.BackgroundTransparency = 1
    pillBtn.Text = ""
    pillBtn.Parent = pill

    --============================================================
    -- MINIMIZE / RESTORE
    --============================================================
    local TWEEN_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local TWEEN_OUT = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    local winPos = win.Position
    local minimized = false

    local function minimize()
        if minimized then return end
        minimized = true
        winPos = win.Position
        local tOut = Tween:Create(win, TWEEN_OUT, {
            Position = UDim2.new(winPos.X.Scale, winPos.X.Offset, winPos.Y.Scale, winPos.Y.Offset + 40),
            BackgroundTransparency = 1,
        })
        tOut:Play()
        tOut.Completed:Connect(function()
            win.Visible = false
            win.Position = winPos
            win.BackgroundTransparency = 0
        end)
        task.wait(0.15)
        pill.Visible = true
        pill.BackgroundTransparency = 1
        pillStroke.Transparency = 1
        pillDot.BackgroundTransparency = 1
        pillLbl.TextTransparency = 1
        Tween:Create(pill, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
        Tween:Create(pillStroke, TweenInfo.new(0.25), { Transparency = 0 }):Play()
        Tween:Create(pillDot, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
        Tween:Create(pillLbl, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
    end

    local function restore()
        if not minimized then return end
        minimized = false
        Tween:Create(pill, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
        Tween:Create(pillStroke, TweenInfo.new(0.15), { Transparency = 1 }):Play()
        Tween:Create(pillDot, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
        Tween:Create(pillLbl, TweenInfo.new(0.15), { TextTransparency = 1 }):Play()
        task.wait(0.12)
        pill.Visible = false
        win.Visible = true
        win.Position = UDim2.new(winPos.X.Scale, winPos.X.Offset, winPos.Y.Scale, winPos.Y.Offset + 40)
        win.BackgroundTransparency = 1
        Tween:Create(win, TWEEN_IN, {
            Position = winPos,
            BackgroundTransparency = 0,
        }):Play()
    end

    minBtn.MouseButton1Click:Connect(minimize)
    pillBtn.MouseButton1Click:Connect(restore)

    --============================================================
    -- CONTROL BUILDERS
    --============================================================
    local counter = {}
    local function nextOrder(pn)
        counter[pn] = (counter[pn] or 0) + 1
        return counter[pn]
    end

    local function mkToggle(page, pn, label, key, onChange)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 32)
        row.BackgroundColor3 = CLR.bgRow
        row.BorderSizePixel = 0
        row.LayoutOrder = nextOrder(pn)
        row.Parent = page
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -80, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = CLR.text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 54, 0, 22)
        btn.Position = UDim2.new(1, -64, 0.5, -11)
        btn.BackgroundColor3 = St[key] and CLR.green or Color3.fromRGB(60, 60, 72)
        btn.BorderSizePixel = 0
        btn.Text = St[key] and "ON" or "OFF"
        btn.TextColor3 = CLR.text
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.Parent = row
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)

        btn.MouseButton1Click:Connect(function()
            St[key] = not St[key]
            btn.Text = St[key] and "ON" or "OFF"
            Tween:Create(btn, TweenInfo.new(0.15), {
                BackgroundColor3 = St[key] and CLR.green or Color3.fromRGB(60, 60, 72),
            }):Play()
            if onChange then pcall(onChange, St[key]) end
        end)
        return btn
    end

    local function mkButton(page, pn, label, cb, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 32)
        b.BackgroundColor3 = color or CLR.blue
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = CLR.text
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.LayoutOrder = nextOrder(pn)
        b.Parent = page
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)

        local base = color or CLR.blue
        b.MouseEnter:Connect(function()
            Tween:Create(b, TweenInfo.new(0.15), {
                BackgroundColor3 = Color3.new(
                    math.min(base.R + 0.1, 1),
                    math.min(base.G + 0.1, 1),
                    math.min(base.B + 0.1, 1)
                ),
            }):Play()
        end)
        b.MouseLeave:Connect(function()
            Tween:Create(b, TweenInfo.new(0.15), { BackgroundColor3 = base }):Play()
        end)

        b.MouseButton1Click:Connect(function()
            local ok, err = pcall(cb)
            if not ok then print("[Dingus][btn] " .. label .. ": " .. tostring(err)) end
        end)
        return b
    end

    local function mkSlider(page, pn, label, minV, maxV, getter, setter, fmt)
        fmt = fmt or "%.1f"
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 46)
        row.BackgroundColor3 = CLR.bgRow
        row.BorderSizePixel = 0
        row.LayoutOrder = nextOrder(pn)
        row.Parent = page
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -20, 0, 16)
        lbl.Position = UDim2.new(0, 12, 0, 6)
        lbl.BackgroundTransparency = 1
        lbl.Text = label .. "  " .. string.format(fmt, getter())
        lbl.TextColor3 = CLR.text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.Parent = row

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(1, -24, 0, 6)
        bar.Position = UDim2.new(0, 12, 0, 28)
        bar.BackgroundColor3 = CLR.bgSlider
        bar.BorderSizePixel = 0
        bar.Parent = row
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame")
        local pct = math.clamp((getter() - minV) / (maxV - minV), 0, 1)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        fill.BackgroundColor3 = CLR.accent
        fill.BorderSizePixel = 0
        fill.Parent = bar
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 14, 0, 14)
        knob.Position = UDim2.new(pct, -7, 0.5, -7)
        knob.BackgroundColor3 = CLR.text
        knob.BorderSizePixel = 0
        knob.ZIndex = 2
        knob.Parent = bar
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, -24, 0, 24)
        hit.Position = UDim2.new(0, 12, 0, 20)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.Parent = row

        local drag = false
        hit.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = true end
        end)
        hit.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
        end)

        UIS.InputChanged:Connect(function(i)
            if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
                local mx = UIS:GetMouseLocation().X
                local bx, bw = bar.AbsolutePosition.X, bar.AbsoluteSize.X
                if bw > 0 then
                    local p = math.clamp((mx - bx) / bw, 0, 1)
                    local v = minV + (maxV - minV) * p
                    setter(v)
                    lbl.Text = label .. "  " .. string.format(fmt, v)
                    fill.Size = UDim2.new(p, 0, 1, 0)
                    knob.Position = UDim2.new(p, -7, 0.5, -7)
                end
            end
        end)
        return lbl
    end

    local function mkInput(page, pn, label, default, onCommit)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 34)
        row.BackgroundColor3 = CLR.bgRow
        row.BorderSizePixel = 0
        row.LayoutOrder = nextOrder(pn)
        row.Parent = page
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, 100, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = CLR.text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.Parent = row

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(1, -128, 0, 22)
        box.Position = UDim2.new(0, 116, 0.5, -11)
        box.BackgroundColor3 = CLR.bgInput
        box.BorderSizePixel = 0
        box.Text = default or ""
        box.TextColor3 = CLR.text
        box.PlaceholderText = "enter..."
        box.PlaceholderColor3 = CLR.textMuted
        box.Font = Enum.Font.Gotham
        box.TextSize = 12
        box.ClearTextOnFocus = false
        box.Parent = row
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)

        box.FocusLost:Connect(function(enter)
            if enter and onCommit then
                pcall(onCommit, box.Text)
            end
        end)
        return box
    end

    local function mkInfo(page, pn, height)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, height or 100)
        lbl.BackgroundColor3 = CLR.bgRow
        lbl.BorderSizePixel = 0
        lbl.Text = "  —"
        lbl.TextColor3 = CLR.textDim
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Top
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 11
        lbl.TextWrapped = true
        lbl.LayoutOrder = nextOrder(pn)
        lbl.Parent = page
        Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 6)
        return lbl
    end

    --============================================================
    -- TAB SYSTEM
    --============================================================
    local pages = {}
    local function mkPage(name)
        local p = Instance.new("ScrollingFrame")
        p.Size = UDim2.new(1, 0, 1, 0)
        p.BackgroundTransparency = 1
        p.BorderSizePixel = 0
        p.ScrollBarThickness = 5
        p.ScrollBarImageColor3 = CLR.accentDim
        p.CanvasSize = UDim2.new(0, 0, 0, 0)
        p.AutomaticCanvasSize = Enum.AutomaticSize.Y
        p.Visible = false
        p.Parent = content
        local lay = Instance.new("UIListLayout", p)
        lay.Padding = UDim.new(0, 5)
        lay.SortOrder = Enum.SortOrder.LayoutOrder
        local pad = Instance.new("UIPadding", p)
        pad.PaddingTop = UDim.new(0, 8)
        pad.PaddingLeft = UDim.new(0, 8)
        pad.PaddingRight = UDim.new(0, 8)
        pad.PaddingBottom = UDim.new(0, 8)
        pages[name] = p
        return p
    end

    local function mkTab(name, order)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 78, 1, 0)
        b.BackgroundColor3 = CLR.bgPanel
        b.BorderSizePixel = 0
        b.Text = name
        b.TextColor3 = CLR.textDim
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.LayoutOrder = order
        b.Parent = tabBar
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        b.MouseButton1Click:Connect(function()
            for n, p in pairs(pages) do p.Visible = (n == name) end
            for _, o in ipairs(tabBar:GetChildren()) do
                if o:IsA("TextButton") then
                    if o == b then
                        Tween:Create(o, TweenInfo.new(0.15), {
                            BackgroundColor3 = CLR.accent,
                            TextColor3 = CLR.text,
                        }):Play()
                    else
                        Tween:Create(o, TweenInfo.new(0.15), {
                            BackgroundColor3 = CLR.bgPanel,
                            TextColor3 = CLR.textDim,
                        }):Play()
                    end
                end
            end
        end)
        return b
    end

    --============================================================
    -- TAB: MAIN
    --============================================================
    local pMain = mkPage("Main")
    local mainInfo = mkInfo(pMain, "Main", 150)

    mkButton(pMain, "Main", "Start Combat", function()
        St.cbt = true
        print("[Dingus] combat on")
    end, CLR.accent)
    mkButton(pMain, "Main", "Stop Combat", function()
        St.cbt = false
        if Ctx.Atk and Ctx.Atk.stopHover then Ctx.Atk.stopHover() end
        print("[Dingus] combat off")
    end, CLR.red)
    mkButton(pMain, "Main", "Scan for Bosses", function()
        St.lScn = 0
        local l = Ctx.Detect.scanBosses()
        print("[Dingus] found " .. #l .. " bosses")
    end, CLR.blue)
    mkButton(pMain, "Main", "Force Move To Target", function()
        if Ctx.Atk and Ctx.Atk.forceMove then Ctx.Atk.forceMove() end
    end, Color3.fromRGB(200, 100, 80))
    mkButton(pMain, "Main", "Run Quest Cycle", function()
        if Ctx.Quest and Ctx.Quest.doCycle then Ctx.Quest.doCycle() end
    end, CLR.orange)
    mkButton(pMain, "Main", "Reset Movers", function()
        local r = U.hrp()
        if r then
            for _, c in ipairs(r:GetChildren()) do
                if c:IsA("BodyPosition") or c:IsA("BodyVelocity")
                    or c:IsA("BodyGyro") or c:IsA("LinearVelocity")
                    or c:IsA("AlignOrientation") then
                    c:Destroy()
                end
            end
            print("[Dingus] movers reset")
        end
    end, Color3.fromRGB(150, 80, 80))

    --============================================================
    -- TAB: COMBAT
    --============================================================
    local pCombat = mkPage("Combat")
    local combatInfo = mkInfo(pCombat, "Combat", 130)
    mkToggle(pCombat, "Combat", "Auto Skill Rotation", "skl")
    mkToggle(pCombat, "Combat", "Auto Equip Weapon", "eqp")
    mkToggle(pCombat, "Combat", "Auto Retreat", "rtr")
    mkToggle(pCombat, "Combat", "Stun Punish", "stunPun")
    mkToggle(pCombat, "Combat", "Guard Spoof", "gsp")
    mkSlider(pCombat, "Combat", "Attack Range", 6, 20,
        function() return Cfg.AtkRange end,
        function(v) Cfg.AtkRange = v end)
    mkSlider(pCombat, "Combat", "Attack Interval", 0.30, 0.90,
        function() return St.aiI or 0.55 end,
        function(v) St.aiI = v end, "%.2f")
    mkSlider(pCombat, "Combat", "Run Speed", 16, 48,
        function() return Cfg.RunSpeed end,
        function(v) Cfg.RunSpeed = v end)
    mkSlider(pCombat, "Combat", "Retreat HP %", 10, 90,
        function() return Cfg.RetreatHP * 100 end,
        function(v) Cfg.RetreatHP = v / 100 end)

    --============================================================
    -- TAB: CROW
    --============================================================
    local pCrow = mkPage("Crow")
    local crowInfo = mkInfo(pCrow, "Crow", 130)
    mkToggle(pCrow, "Crow", "Auto Crow Quests", "crw")
    mkButton(pCrow, "Crow", "Equip Crow", function()
        local t = Ctx.Scan.findCrowTool()
        local h = U.hum()
        if t and h and t:IsA("Tool") then
            pcall(function() h:EquipTool(t) end)
            print("[Dingus] crow equipped")
        end
    end, CLR.green)
    mkButton(pCrow, "Crow", "Summon Crow", function()
        U.m1()
    end, CLR.blue)
    mkButton(pCrow, "Crow", "Accept Quest", function()
        local m = Ctx.Scan.findCrowMenu()
        if m then
            pcall(function() m:Activate() end)
            print("[Dingus] quest accepted")
        end
    end, CLR.orange)

    --============================================================
    -- TAB: CONFIG
    --============================================================
    local pConfig = mkPage("Config")
    local configInfo = mkInfo(pConfig, "Config", 90)

    local slotInput = mkInput(pConfig, "Config", "Slot Name", ConfigMgr.currentSlot, function(text)
        ConfigMgr.currentSlot = text
        print("[Dingus][Config] slot = " .. text)
    end)

    mkButton(pConfig, "Config", "Save to Slot", function()
        local ok, err = ConfigMgr.saveTo()
        print("[Dingus][Config] save " .. (ok and "ok" or ("fail: " .. tostring(err))))
    end, CLR.blue)
    mkButton(pConfig, "Config", "Load from Slot", function()
        local ok, err = ConfigMgr.loadFrom()
        print("[Dingus][Config] load " .. (ok and tostring(err) or ("fail: " .. tostring(err))))
    end, CLR.green)
    mkButton(pConfig, "Config", "Delete Current Slot", function()
        local ok = ConfigMgr.deleteSlot(ConfigMgr.currentSlot)
        print("[Dingus][Config] delete " .. tostring(ok))
    end, CLR.red)
    mkButton(pConfig, "Config", "Reset to Defaults", function()
        if Ctx.Cfg and Ctx.Cfg.reset then Ctx.Cfg.reset() end
        print("[Dingus][Config] reset")
    end, CLR.orange)
    mkButton(pConfig, "Config", "Print Values to F9", function()
        if Ctx.Cfg and Ctx.Cfg.pretty then print(Ctx.Cfg.pretty()) end
    end, Color3.fromRGB(110, 110, 150))

    local slotsInfo = mkInfo(pConfig, "Config", 120)

    --============================================================
    -- TAB: FILES
    --============================================================
    local pFiles = mkPage("Files")
    local filesInfo = mkInfo(pFiles, "Files", 260)

    mkButton(pFiles, "Files", "Refresh File List", function()
        FileMgr.refresh()
        print("[Dingus][Files] refreshed: " .. #FileMgr.files .. " files")
    end, CLR.blue)
    mkButton(pFiles, "Files", "Delete dingus_boot_log.txt", function()
        local ok = FileMgr.delete("dingus_boot_log.txt")
        print("[Dingus][Files] delete log: " .. tostring(ok))
    end, CLR.red)

    --============================================================
    -- TAB: LOG
    --============================================================
    local pLog = mkPage("Log")
    pLog.AutomaticCanvasSize = Enum.AutomaticSize.None
    pLog.CanvasSize = UDim2.new(0, 0, 0, 0)
    pLog.ScrollBarThickness = 6

    -- Filter row
    local filterRow = Instance.new("Frame")
    filterRow.Size = UDim2.new(1, 0, 0, 32)
    filterRow.BackgroundTransparency = 1
    filterRow.LayoutOrder = 0
    filterRow.Parent = pLog

    local filterBtns = {}
    local function mkFilterBtn(label, key, order)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 90, 1, 0)
        b.Position = UDim2.new(0, order * 94, 0, 0)
        b.BackgroundColor3 = Log.filter == key and CLR.accent or CLR.bgPanel
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = Log.filter == key and CLR.text or CLR.textDim
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.Parent = filterRow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        filterBtns[key] = b
        b.MouseButton1Click:Connect(function()
            Log.filter = key
            for k, btn in pairs(filterBtns) do
                btn.BackgroundColor3 = (k == key) and CLR.accent or CLR.bgPanel
                btn.TextColor3 = (k == key) and CLR.text or CLR.textDim
            end
        end)
        return b
    end
    mkFilterBtn("All", "all", 0)
    mkFilterBtn("Dingus", "dingus", 1)
    mkFilterBtn("Errors", "errors", 2)

    -- Buttons row
    local logBtnRow = Instance.new("Frame")
    logBtnRow.Size = UDim2.new(1, 0, 0, 32)
    logBtnRow.BackgroundTransparency = 1
    logBtnRow.LayoutOrder = 1
    logBtnRow.Parent = pLog

    local function mkLogBtn(label, x, cb, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 110, 1, 0)
        b.Position = UDim2.new(0, x, 0, 0)
        b.BackgroundColor3 = color
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = CLR.text
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.Parent = logBtnRow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        b.MouseButton1Click:Connect(cb)
    end
    mkLogBtn("Clear", 0, function()
        Log.clear()
        print("[Dingus][Log] cleared")
    end, CLR.red)
    mkLogBtn("Pause/Resume", 114, function()
        Log.paused = not Log.paused
        print("[Dingus][Log] paused = " .. tostring(Log.paused))
    end, CLR.orange)
    mkLogBtn("Save Log", 228, function()
        local ok = Log.export("dingus_combat_log.txt")
        print("[Dingus][Log] exported: " .. tostring(ok))
    end, CLR.blue)
    mkLogBtn("Copy All", 342, function()
        local lines = {}
        for i = 1, #Log.buffer do
            local e = Log.buffer[i]
            lines[#lines+1] = string.format("[%s] %s", e.time, e.text)
        end
        if setclipboard then pcall(setclipboard, table.concat(lines, "\n")) end
        print("[Dingus][Log] copied " .. #lines .. " lines")
    end, CLR.green)

    -- Log display (fixed height, non-scrolling outer, scroll inside)
    local logFrame = Instance.new("Frame")
    logFrame.Size = UDim2.new(1, 0, 1, -110)
    logFrame.BackgroundColor3 = CLR.bgInput
    logFrame.BorderSizePixel = 0
    logFrame.LayoutOrder = 2
    logFrame.Parent = pLog
    Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0, 6)

    -- Since pLog is a scrolling frame, we need to prevent outer scroll and use inner scrolling
    pLog.AutomaticCanvasSize = Enum.AutomaticSize.None
    pLog.CanvasSize = UDim2.new(0, 0, 0, 0)
    pLog.ScrollingEnabled = false

    local logScroll = Instance.new("ScrollingFrame")
    logScroll.Size = UDim2.new(1, -6, 1, -6)
    logScroll.Position = UDim2.new(0, 3, 0, 3)
    logScroll.BackgroundTransparency = 1
    logScroll.BorderSizePixel = 0
    logScroll.ScrollBarThickness = 5
    logScroll.ScrollBarImageColor3 = CLR.accentDim
    logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    logScroll.Parent = logFrame

    local logLayout = Instance.new("UIListLayout", logScroll)
    logLayout.Padding = UDim.new(0, 2)
    logLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local logRows = {}
    local maxVisibleRows = 250

    local function colorFor(msgType)
        if msgType == Enum.MessageType.MessageError then return CLR.logError end
        if msgType == Enum.MessageType.MessageWarning then return CLR.logWarn end
        if msgType == Enum.MessageType.MessageOutput then return CLR.logInfo end
        return CLR.logDingus
    end

    local function rebuildLog()
        for _, r in ipairs(logRows) do r:Destroy() end
        logRows = {}

        local entries = Log.buffer
        local start = math.max(1, #entries - maxVisibleRows + 1)

        for i = start, #entries do
            local e = entries[i]
            local row = Instance.new("TextLabel")
            row.Size = UDim2.new(1, -6, 0, 14)
            row.BackgroundTransparency = 1
            row.Text = "  [" .. e.time .. "] " .. e.text
            row.TextColor3 = colorFor(e.type)
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.Font = Enum.Font.Code
            row.TextSize = 10
            row.TextTruncate = Enum.TextTruncate.AtEnd
            row.LayoutOrder = i
            row.Parent = logScroll
            table.insert(logRows, row)
        end

        logScroll.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y)
    end

    --============================================================
    -- TABS WIRING
    --============================================================
    local tbMain = mkTab("Main", 1)
    mkTab("Combat", 2)
    mkTab("Crow", 3)
    mkTab("Config", 4)
    mkTab("Files", 5)
    mkTab("Log", 6)

    pMain.Visible = true
    tbMain.BackgroundColor3 = CLR.accent
    tbMain.TextColor3 = CLR.text

    --============================================================
    -- REFRESH LOOP
    --============================================================
    local cache = {}
    task.spawn(function()
        while St.run do
            if St.boot and not minimized then
                -- Main info
                local h = U.hum()
                local hp = h and string.format("%d/%d", math.floor(h.Health), math.floor(h.MaxHealth)) or "?"
                local hitRate = St.aAt > 0 and math.floor(St.aHi / St.aAt * 100) or 0

                local s1 = string.format(
                    "  state: %s · hp: %s\n" ..
                    "  target: %s @%.0f\n" ..
                    "  atk: %d/%d (%d%%)\n" ..
                    "  kills: %d · retreats: %d\n" ..
                    "  quest: %s · lv %d",
                    St.cbtS, hp,
                    St.tgt and St.tgt.ch.Name or "none", St.tgt and St.tgt.d or 0,
                    St.aHi, St.aAt, hitRate,
                    St.bKll, St.rtrC,
                    tostring(St.questTarget or "—"), St.playerLevel or 0)
                if cache.main ~= s1 then cache.main = s1; mainInfo.Text = s1 end

                local s2 = string.format(
                    "  atk range: %.1f · interval: %.2f\n" ..
                    "  runspeed: %.0f · retreat hp: %.0f%%\n" ..
                    "  skill: %s · equip: %s\n" ..
                    "  retreat: %s · stun: %s · spoof: %s",
                    Cfg.AtkRange, St.aiI or 0.55,
                    Cfg.RunSpeed, Cfg.RetreatHP * 100,
                    tostring(St.skl), tostring(St.eqp),
                    tostring(St.rtr), tostring(St.stunPun), tostring(St.gsp))
                if cache.combat ~= s2 then cache.combat = s2; combatInfo.Text = s2 end

                local s3 = string.format(
                    "  crow tool: %s\n" ..
                    "  perched: %s · accepted: %d",
                    St.crT and St.crT.Name or "not found",
                    tostring(St.cPrch), St.cQs)
                if cache.crow ~= s3 then cache.crow = s3; crowInfo.Text = s3 end

                -- Config tab info
                local slotList = ConfigMgr.listSlots()
                local s4 = string.format(
                    "  active slot: %s\n" ..
                    "  saved slots: %d\n" ..
                    "  file: %s\n" ..
                    "  writefile: %s · readfile: %s",
                    ConfigMgr.currentSlot,
                    #slotList,
                    ConfigMgr.slotFilename(ConfigMgr.currentSlot),
                    tostring(HAS.writefile), tostring(HAS.readfile))
                if cache.config ~= s4 then cache.config = s4; configInfo.Text = s4 end

                local slotLines = { "  available slots:" }
                for i = 1, math.min(#slotList, 10) do
                    local s = slotList[i]
                    slotLines[#slotLines+1] = string.format("    · %s (%d bytes)", s.name, s.size)
                end
                if #slotList == 0 then slotLines[#slotLines+1] = "    (none)" end
                local s5 = table.concat(slotLines, "\n")
                if cache.slots ~= s5 then cache.slots = s5; slotsInfo.Text = s5 end

                -- Files tab
                FileMgr.refresh()
                local fileLines = { string.format("  files: %d", #FileMgr.files) }
                for i = 1, math.min(#FileMgr.files, 15) do
                    local f = FileMgr.files[i]
                    fileLines[#fileLines+1] = string.format("    · %s (%d bytes)", f.name, f.size or 0)
                end
                local s6 = table.concat(fileLines, "\n")
                if cache.files ~= s6 then cache.files = s6; filesInfo.Text = s6 end

                -- Status bar
                local bar = string.format(
                    "  fps %.0f  ·  %s  ·  hp %s  ·  log %d",
                    St.fps or 60, St.cbtS, hp, #Log.buffer)
                if cache.bar ~= bar then cache.bar = bar; statusBar.Text = bar end

                -- Log tab rebuild when pending
                if Log.pendingUpdate then
                    Log.pendingUpdate = false
                    rebuildLog()
                end
            end
            task.wait(0.3)
        end
    end)

    --============================================================
    -- HOTKEY
    --============================================================
    UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            if minimized then restore() else minimize() end
        end
    end)

    --============================================================
    -- CLOSE
    --============================================================
    closeBtn.MouseButton1Click:Connect(function()
        gui:Destroy()
    end)

    --============================================================
    -- EXPOSE
    --============================================================
    G.gui = gui
    G.win = win
    G.minimize = minimize
    G.restore = restore
    G.Log = Log
    G.FileMgr = FileMgr
    G.ConfigMgr = ConfigMgr

    print("[Dingus][gui] initialized · 6 tabs")
end

return G
