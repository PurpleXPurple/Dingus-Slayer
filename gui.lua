--[[
    Dingus-Slayer · gui.lua v32
    Full rebuild. 8 tabs. Working scroll. Bigger window.

    Layout:
      Window 940x660
      Sidebar 200 wide (scrollable nav)
      Header 48 tall
      Content = rest (scrolling pages)

    Scroll fix: ScrollBarThickness=10, explicit ScrollingEnabled,
    explicit ScrollingDirection, UIPadding.right reserves scrollbar
    space so rows don't render underneath.

    Targets tab: region-grouped boss selector with per-boss toggles.
]]--

local G = {}

function G.init(Ctx)
    local U   = Ctx.Util
    local Cfg = Ctx.Cfg
    local St  = Ctx.St
    local Lists = Ctx.Lists
    local Tween = game:GetService("TweenService")
    local UIS   = game:GetService("UserInputService")
    local LogService = game:GetService("LogService")

    --============================================================
    -- GUI CONFIG
    --============================================================
    Cfg.GuiPanicKey1   = Cfg.GuiPanicKey1   or "RightControl"
    Cfg.GuiPanicKey2   = Cfg.GuiPanicKey2   or "Backspace"
    Cfg.GuiConcealed   = Cfg.GuiConcealed   ~= false
    Cfg.GuiPanicHide   = Cfg.GuiPanicHide   ~= false

    --============================================================
    -- CAPABILITIES
    --============================================================
    local HAS = {
        writefile  = type(writefile) == "function",
        readfile   = type(readfile) == "function",
        delfile    = type(delfile) == "function",
        isfile     = type(isfile) == "function",
        listfiles  = type(listfiles) == "function",
        makefolder = type(makefolder) == "function",
        gethui     = type(gethui) == "function",
    }

    --============================================================
    -- CONCEALMENT
    --============================================================
    local function resolveParent()
        if Cfg.GuiConcealed then
            if HAS.gethui then
                local ok, hui = pcall(gethui)
                if ok and hui then return hui, "gethui" end
            end
            local ok, cg = pcall(function()
                return game:GetService("CoreGui")
            end)
            if ok and cg then return cg, "CoreGui" end
        end
        return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"),
            "PlayerGui"
    end

    local parent, parentKind = resolveParent()
    if parentKind == "PlayerGui" then
        warn("[Dingus][gui] PlayerGui fallback — game scripts can see the UI")
    end

    local suffix = string.format("%06x", math.random(0, 0xFFFFFF))
    local guiName = "_c" .. suffix

    local old = parent:FindFirstChild("DingusUI")
    if old then pcall(function() old:Destroy() end) end

    --============================================================
    -- PALETTE
    --============================================================
    local CLR = {
        bg          = Color3.fromRGB(12, 12, 16),
        bgHeader    = Color3.fromRGB(14, 14, 20),
        bgSidebar   = Color3.fromRGB(10, 10, 14),
        bgPanel     = Color3.fromRGB(16, 16, 22),
        row         = Color3.fromRGB(24, 24, 32),
        rowHover    = Color3.fromRGB(32, 32, 42),
        iconBg      = Color3.fromRGB(44, 24, 24),
        iconBgDim   = Color3.fromRGB(28, 24, 28),
        navActive   = Color3.fromRGB(40, 24, 24),
        navHover    = Color3.fromRGB(22, 22, 30),
        trackOff    = Color3.fromRGB(52, 52, 66),
        border      = Color3.fromRGB(40, 32, 34),

        accent      = Color3.fromRGB(220, 90, 70),
        accentSoft  = Color3.fromRGB(240, 130, 110),
        accentDim   = Color3.fromRGB(150, 60, 50),

        green       = Color3.fromRGB(80, 200, 120),
        red         = Color3.fromRGB(220, 70, 80),
        blue        = Color3.fromRGB(70, 130, 200),
        orange      = Color3.fromRGB(210, 140, 80),

        text        = Color3.fromRGB(232, 232, 240),
        textDim     = Color3.fromRGB(160, 165, 180),
        textMuted   = Color3.fromRGB(110, 115, 135),

        logInfo     = Color3.fromRGB(200, 200, 210),
        logWarn     = Color3.fromRGB(240, 200, 100),
        logError    = Color3.fromRGB(240, 120, 120),
        logDingus   = Color3.fromRGB(140, 220, 180),
    }

    local FONT_B = Enum.Font.GothamBold
    local FONT_R = Enum.Font.Gotham
    local FONT_C = Enum.Font.Code

    --============================================================
    -- LOG MANAGER
    --============================================================
    local Log = {
        buffer = {},
        maxLines = 300,
        filter = "all",
        paused = false,
        pendingUpdate = true,
    }

    function Log.add(text, msgType)
        if Log.paused then return end
        if Log.filter == "dingus" and not string.find(text, "Dingus", 1, true) then return end
        if Log.filter == "errors" and msgType ~= Enum.MessageType.MessageError then return end
        table.insert(Log.buffer, {
            text = text, type = msgType, time = os.date("%H:%M:%S"),
        })
        if #Log.buffer > Log.maxLines then table.remove(Log.buffer, 1) end
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
        return pcall(writefile, filename, table.concat(lines, "\n"))
    end

    pcall(function()
        LogService.MessageOut:Connect(function(msg, msgType)
            pcall(Log.add, msg, msgType)
        end)
    end)

    local _origPrint = print
    local _origWarn  = warn
    do
        local function coerce(a)
            if type(a) == "string" then return a end
            local ok, s = pcall(tostring, a)
            return ok and s or "[value]"
        end
        _G.print = function(...)
            local args = { ... }
            local out = {}
            for i = 1, #args do out[i] = coerce(args[i]) end
            pcall(Log.add, table.concat(out, " "), Enum.MessageType.MessageOutput)
            return _origPrint(...)
        end
        _G.warn = function(...)
            local args = { ... }
            local out = {}
            for i = 1, #args do out[i] = coerce(args[i]) end
            pcall(Log.add, table.concat(out, " "), Enum.MessageType.MessageWarning)
            return _origWarn(...)
        end
    end

    local function restoreGlobals()
        _G.print = _origPrint
        _G.warn  = _origWarn
    end

    --============================================================
    -- FILE MANAGER
    --============================================================
    local FileMgr = { files = {}, rootFolder = "Dingus" }
    if HAS.makefolder then pcall(makefolder, FileMgr.rootFolder) end

    function FileMgr.refresh()
        FileMgr.files = {}
        if not HAS.listfiles then
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
        if not ok or not list then ok, list = pcall(listfiles) end
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
    local ConfigMgr = { currentSlot = "default" }

    function ConfigMgr.saveTo(slot)
        slot = slot or ConfigMgr.currentSlot
        if Ctx.Cfg and Ctx.Cfg.save then return Ctx.Cfg.save(slot) end
        return false, "no Cfg.save"
    end

    function ConfigMgr.loadFrom(slot)
        slot = slot or ConfigMgr.currentSlot
        if Ctx.Cfg and Ctx.Cfg.load then return Ctx.Cfg.load(slot) end
        return false, "no Cfg.load"
    end

    function ConfigMgr.listSlots()
        local out = {}
        local all = FileMgr.refresh()
        local prefix = "dingus_config_"
        for _, f in ipairs(all) do
            local name = f.name or ""
            local slot = name:match("^" .. prefix .. "(.-)%.json$")
            if slot then table.insert(out, { name = slot, path = f.path, size = f.size }) end
        end
        return out
    end

    function ConfigMgr.deleteSlot(slot)
        slot = slot or ConfigMgr.currentSlot
        return FileMgr.delete("dingus_config_" .. slot .. ".json")
    end

    --============================================================
    -- ROOT GUI
    --============================================================
    local gui = Instance.new("ScreenGui")
    gui.Name = guiName
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 2 ^ 30
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    -- BIGGER WINDOW
    local WIN_W, WIN_H = 940, 660
    local HEADER_H     = 48
    local SIDEBAR_W    = 200
    local PAD          = 14
    local ROW_H        = 60
    local ROW_GAP      = 8
    local SCROLL_W     = 10

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
    win.ClipsDescendants = true
    win.Parent = gui
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 14)
    local winStroke = Instance.new("UIStroke", win)
    winStroke.Color = CLR.border
    winStroke.Thickness = 1
    winStroke.Transparency = 0.2

    --============================================================
    -- HEADER
    --============================================================
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, HEADER_H)
    header.BackgroundColor3 = CLR.bgHeader
    header.BorderSizePixel = 0
    header.Parent = win
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)
    local hFix = Instance.new("Frame")
    hFix.Size = UDim2.new(1, 0, 0, 14)
    hFix.Position = UDim2.new(0, 0, 1, -14)
    hFix.BackgroundColor3 = CLR.bgHeader
    hFix.BorderSizePixel = 0
    hFix.Parent = header

    local chip = Instance.new("Frame")
    chip.Size = UDim2.new(0, 30, 0, 30)
    chip.Position = UDim2.new(0, 16, 0.5, -15)
    chip.BackgroundColor3 = CLR.accent
    chip.BorderSizePixel = 0
    chip.Parent = header
    Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 8)
    local chipLbl = Instance.new("TextLabel")
    chipLbl.Size = UDim2.new(1, 0, 1, 0)
    chipLbl.BackgroundTransparency = 1
    chipLbl.Text = "D"
    chipLbl.TextColor3 = Color3.fromRGB(255, 245, 240)
    chipLbl.Font = FONT_B
    chipLbl.TextSize = 17
    chipLbl.Parent = chip

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(0, 280, 1, 0)
    titleLbl.Position = UDim2.new(0, 58, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "Dingus-Slayer"
    titleLbl.TextColor3 = CLR.text
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Font = FONT_B
    titleLbl.TextSize = 15
    titleLbl.Parent = header

    local liveDot = Instance.new("Frame")
    liveDot.Size = UDim2.new(0, 6, 0, 6)
    liveDot.Position = UDim2.new(0, 200, 0.5, -3)
    liveDot.BackgroundColor3 = CLR.textMuted
    liveDot.BorderSizePixel = 0
    liveDot.Parent = header
    Instance.new("UICorner", liveDot).CornerRadius = UDim.new(1, 0)

    local liveLbl = Instance.new("TextLabel")
    liveLbl.Size = UDim2.new(0, 400, 1, 0)
    liveLbl.Position = UDim2.new(0, 214, 0, 0)
    liveLbl.BackgroundTransparency = 1
    liveLbl.Text = "ready"
    liveLbl.TextColor3 = CLR.textMuted
    liveLbl.TextXAlignment = Enum.TextXAlignment.Left
    liveLbl.Font = FONT_B
    liveLbl.TextSize = 11
    liveLbl.Parent = header

    local function mkCtrlBtn(glyph, offset, base, hover)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 30, 0, 30)
        b.Position = UDim2.new(1, offset, 0.5, -15)
        b.BackgroundColor3 = base
        b.BackgroundTransparency = 1
        b.BorderSizePixel = 0
        b.Text = glyph
        b.TextColor3 = CLR.textDim
        b.Font = FONT_B
        b.TextSize = 16
        b.AutoButtonColor = false
        b.Parent = header
        Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
        b.MouseEnter:Connect(function()
            Tween:Create(b, TweenInfo.new(0.12), {
                BackgroundTransparency = 0,
                BackgroundColor3 = hover,
                TextColor3 = CLR.text,
            }):Play()
        end)
        b.MouseLeave:Connect(function()
            Tween:Create(b, TweenInfo.new(0.12), {
                BackgroundTransparency = 1,
                TextColor3 = CLR.textDim,
            }):Play()
        end)
        return b
    end

    local closeBtn = mkCtrlBtn("✕", -44, CLR.red, CLR.red)
    local minBtn   = mkCtrlBtn("–", -78, Color3.fromRGB(60,60,75), Color3.fromRGB(70,70,90))

    --============================================================
    -- SIDEBAR (scrollable nav)
    --============================================================
    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, -HEADER_H)
    sidebar.Position = UDim2.new(0, 0, 0, HEADER_H)
    sidebar.BackgroundColor3 = CLR.bgSidebar
    sidebar.BorderSizePixel = 0
    sidebar.Parent = win

    local sideMenuLbl = Instance.new("TextLabel")
    sideMenuLbl.Size = UDim2.new(1, -32, 0, 18)
    sideMenuLbl.Position = UDim2.new(0, 16, 0, 16)
    sideMenuLbl.BackgroundTransparency = 1
    sideMenuLbl.Text = "MENU"
    sideMenuLbl.TextColor3 = CLR.textMuted
    sideMenuLbl.TextXAlignment = Enum.TextXAlignment.Left
    sideMenuLbl.Font = FONT_B
    sideMenuLbl.TextSize = 10
    sideMenuLbl.Parent = sidebar

    local navScroll = Instance.new("ScrollingFrame")
    navScroll.Size = UDim2.new(1, -16, 1, -110)
    navScroll.Position = UDim2.new(0, 8, 0, 42)
    navScroll.BackgroundTransparency = 1
    navScroll.BorderSizePixel = 0
    navScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    navScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    navScroll.ScrollBarThickness = 4
    navScroll.ScrollBarImageColor3 = CLR.accentDim
    navScroll.ScrollBarImageTransparency = 0.5
    navScroll.ScrollingEnabled = true
    navScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    navScroll.Parent = sidebar
    local navLay = Instance.new("UIListLayout", navScroll)
    navLay.Padding = UDim.new(0, 4)
    navLay.SortOrder = Enum.SortOrder.LayoutOrder

    local sideFooter = Instance.new("Frame")
    sideFooter.Size = UDim2.new(1, -16, 0, 38)
    sideFooter.Position = UDim2.new(0, 8, 1, -50)
    sideFooter.BackgroundColor3 = CLR.bgPanel
    sideFooter.BorderSizePixel = 0
    sideFooter.Parent = sidebar
    Instance.new("UICorner", sideFooter).CornerRadius = UDim.new(0, 8)

    local fDot = Instance.new("Frame")
    fDot.Size = UDim2.new(0, 6, 0, 6)
    fDot.Position = UDim2.new(0, 14, 0.5, -3)
    fDot.BackgroundColor3 = CLR.green
    fDot.BorderSizePixel = 0
    fDot.Parent = sideFooter
    Instance.new("UICorner", fDot).CornerRadius = UDim.new(1, 0)

    local fLbl = Instance.new("TextLabel")
    fLbl.Size = UDim2.new(1, -32, 1, 0)
    fLbl.Position = UDim2.new(0, 28, 0, 0)
    fLbl.BackgroundTransparency = 1
    fLbl.Text = "v32 · idle"
    fLbl.TextColor3 = CLR.textMuted
    fLbl.TextXAlignment = Enum.TextXAlignment.Left
    fLbl.Font = FONT_B
    fLbl.TextSize = 10
    fLbl.Parent = sideFooter

    --============================================================
    -- CONTENT CONTAINER
    --============================================================
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -SIDEBAR_W, 1, -HEADER_H)
    content.Position = UDim2.new(0, SIDEBAR_W, 0, HEADER_H)
    content.BackgroundColor3 = CLR.bg
    content.BorderSizePixel = 0
    content.ClipsDescendants = true
    content.Parent = win

    --============================================================
    -- WIDGETS
    --============================================================
    local counters = {}
    local function nextOrder(page)
        counters[page] = (counters[page] or 0) + 1
        return counters[page]
    end

    local function mkSwitch(par, initial, onChange)
        local track = Instance.new("TextButton")
        track.Size = UDim2.new(0, 42, 0, 22)
        track.BackgroundColor3 = initial and CLR.accent or CLR.trackOff
        track.BorderSizePixel = 0
        track.Text = ""
        track.AutoButtonColor = false
        track.Parent = par
        Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 18, 0, 18)
        knob.Position = initial and UDim2.new(1, -20, 0.5, -9)
                             or  UDim2.new(0, 2, 0.5, -9)
        knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
        knob.BorderSizePixel = 0
        knob.Parent = track
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

        local state = initial
        local function set(v)
            state = v
            Tween:Create(track, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
                BackgroundColor3 = state and CLR.accent or CLR.trackOff,
            }):Play()
            Tween:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
                Position = state and UDim2.new(1, -20, 0.5, -9)
                                or  UDim2.new(0, 2, 0.5, -9),
            }):Play()
            if onChange then pcall(onChange, state) end
        end
        track.MouseButton1Click:Connect(function() set(not state) end)
        return track, set
    end

    local function mkIcon(par, glyph, dim)
        local box = Instance.new("Frame")
        box.Size = UDim2.new(0, 36, 0, 36)
        box.Position = UDim2.new(0, 16, 0, 12)
        box.BackgroundColor3 = dim and CLR.iconBgDim or CLR.iconBg
        box.BorderSizePixel = 0
        box.Parent = par
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 9)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = glyph
        lbl.TextColor3 = dim and CLR.textDim or CLR.accent
        lbl.Font = FONT_B
        lbl.TextSize = 17
        lbl.Parent = box
        return box
    end

    local function mkRow(page, height)
        local r = Instance.new("Frame")
        r.Size = UDim2.new(1, -SCROLL_W - 4, 0, height)
        r.BackgroundColor3 = CLR.row
        r.BorderSizePixel = 0
        r.LayoutOrder = nextOrder(page)
        r.Active = true
        r.Parent = page
        Instance.new("UICorner", r).CornerRadius = UDim.new(0, 11)
        r.MouseEnter:Connect(function()
            Tween:Create(r, TweenInfo.new(0.12), { BackgroundColor3 = CLR.rowHover }):Play()
        end)
        r.MouseLeave:Connect(function()
            Tween:Create(r, TweenInfo.new(0.12), { BackgroundColor3 = CLR.row }):Play()
        end)
        return r
    end

    local function mkTitleDesc(row, title, desc, titleY)
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -100, 0, 18)
        t.Position = UDim2.new(0, 64, 0, titleY or 12)
        t.BackgroundTransparency = 1
        t.Text = title
        t.TextColor3 = CLR.text
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Font = FONT_B
        t.TextSize = 14
        t.Parent = row

        local d = nil
        if desc and desc ~= "" then
            d = Instance.new("TextLabel")
            d.Size = UDim2.new(1, -100, 0, 15)
            d.Position = UDim2.new(0, 64, 0, (titleY or 12) + 20)
            d.BackgroundTransparency = 1
            d.Text = desc
            d.TextColor3 = CLR.textMuted
            d.TextXAlignment = Enum.TextXAlignment.Left
            d.Font = FONT_R
            d.TextSize = 12
            d.TextTruncate = Enum.TextTruncate.AtEnd
            d.Parent = row
        end
        return t, d
    end

    local function mkSection(page, text)
        local h = Instance.new("TextLabel")
        h.Size = UDim2.new(1, -SCROLL_W - 4, 0, 24)
        h.BackgroundTransparency = 1
        h.Text = string.upper(text)
        h.TextColor3 = CLR.textMuted
        h.TextXAlignment = Enum.TextXAlignment.Left
        h.TextYAlignment = Enum.TextYAlignment.Bottom
        h.Font = FONT_B
        h.TextSize = 10
        h.LayoutOrder = nextOrder(page)
        h.Parent = page
        local pad = Instance.new("UIPadding", h)
        pad.PaddingLeft = UDim.new(0, 6)
        pad.PaddingBottom = UDim.new(0, 4)
        return h
    end

    local function mkToggleRow(page, glyph, title, desc, key, onChange)
        local row = mkRow(page, ROW_H)
        mkIcon(row, glyph)
        mkTitleDesc(row, title, desc)
        local sw = mkSwitch(row, St[key], function(v)
            St[key] = v
            if onChange then pcall(onChange, v) end
        end)
        sw.Position = UDim2.new(1, -58, 0.5, -11)
        sw.ZIndex = 3
        return row
    end

    local function mkSliderRow(page, glyph, title, minV, maxV, getter, setter, fmt)
        fmt = fmt or "%.1f"
        local row = mkRow(page, 70)
        mkIcon(row, glyph)

        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -180, 0, 18)
        t.Position = UDim2.new(0, 64, 0, 12)
        t.BackgroundTransparency = 1
        t.Text = title
        t.TextColor3 = CLR.text
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Font = FONT_B
        t.TextSize = 14
        t.Parent = row

        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(0, 80, 0, 18)
        v.Position = UDim2.new(1, -SCROLL_W - 6, 0, 12)
        v.AnchorPoint = Vector2.new(1, 0)
        v.BackgroundTransparency = 1
        v.Text = string.format(fmt, getter())
        v.TextColor3 = CLR.accent
        v.TextXAlignment = Enum.TextXAlignment.Right
        v.Font = FONT_B
        v.TextSize = 13
        v.Parent = row

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(1, -80, 0, 6)
        bar.Position = UDim2.new(0, 64, 0, 48)
        bar.BackgroundColor3 = CLR.trackOff
        bar.BorderSizePixel = 0
        bar.Parent = row
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

        local pct = math.clamp((getter() - minV) / (maxV - minV), 0, 1)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(pct, 0, 1, 0)
        fill.BackgroundColor3 = CLR.accent
        fill.BorderSizePixel = 0
        fill.Parent = bar
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 14, 0, 14)
        knob.Position = UDim2.new(pct, -7, 0.5, -7)
        knob.BackgroundColor3 = Color3.fromRGB(255, 245, 240)
        knob.BorderSizePixel = 0
        knob.ZIndex = 2
        knob.Parent = bar
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, -80, 0, 24)
        hit.Position = UDim2.new(0, 64, 0, 39)
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
                    local val = minV + (maxV - minV) * p
                    setter(val)
                    v.Text = string.format(fmt, val)
                    fill.Size = UDim2.new(p, 0, 1, 0)
                    knob.Position = UDim2.new(p, -7, 0.5, -7)
                end
            end
        end)
        return row
    end

    local function mkButtonRow(page, glyph, title, desc, cb, tint)
        local row = mkRow(page, ROW_H)
        mkIcon(row, glyph, tint)
        mkTitleDesc(row, title, desc, 14)

        local chev = Instance.new("TextLabel")
        chev.Size = UDim2.new(0, 20, 0, 24)
        chev.Position = UDim2.new(1, -SCROLL_W - 24, 0.5, -12)
        chev.AnchorPoint = Vector2.new(0, 0)
        chev.BackgroundTransparency = 1
        chev.Text = "›"
        chev.TextColor3 = CLR.textMuted
        chev.Font = FONT_B
        chev.TextSize = 20
        chev.Parent = row

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, 0, 1, 0)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.Parent = row
        hit.MouseButton1Click:Connect(function()
            local ok, err = pcall(cb)
            if not ok then print("[Dingus][btn] " .. title .. ": " .. tostring(err)) end
        end)
        return row
    end

    local function mkInputRow(page, glyph, title, default, onCommit)
        local row = mkRow(page, ROW_H)
        mkIcon(row, glyph)
        mkTitleDesc(row, title, nil, 20)

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0, 160, 0, 28)
        box.Position = UDim2.new(1, -SCROLL_W - 174, 0.5, -14)
        box.BackgroundColor3 = CLR.bgPanel
        box.BorderSizePixel = 0
        box.Text = default or ""
        box.TextColor3 = CLR.text
        box.PlaceholderText = "enter..."
        box.PlaceholderColor3 = CLR.textMuted
        box.Font = FONT_R
        box.TextSize = 13
        box.ClearTextOnFocus = false
        box.Parent = row
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)
        box.FocusLost:Connect(function(enter)
            if enter and onCommit then pcall(onCommit, box.Text) end
        end)
        return row
    end

    local function mkInfo(page, height)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -SCROLL_W - 4, 0, height or 100)
        lbl.BackgroundColor3 = CLR.row
        lbl.BorderSizePixel = 0
        lbl.Text = "  —"
        lbl.TextColor3 = CLR.textDim
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Top
        lbl.Font = FONT_C
        lbl.TextSize = 12
        lbl.TextWrapped = true
        lbl.LayoutOrder = nextOrder(page)
        lbl.Parent = page
        Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 11)
        local pad = Instance.new("UIPadding", lbl)
        pad.PaddingTop = UDim.new(0, 12)
        pad.PaddingLeft = UDim.new(0, 14)
        pad.PaddingRight = UDim.new(0, 14)
        return lbl
    end

    --============================================================
    -- PAGE FACTORY — proper scroll
    --============================================================
    local PAGES = {}
    local NAV   = {}

    local function mkPage(name)
        local p = Instance.new("ScrollingFrame")
        p.Name = name
        p.Size = UDim2.new(1, 0, 1, 0)
        p.Position = UDim2.new(0, 0, 0, 0)
        p.BackgroundTransparency = 1
        p.BorderSizePixel = 0
        p.Visible = false
        p.CanvasSize = UDim2.new(0, 0, 0, 0)
        p.AutomaticCanvasSize = Enum.AutomaticSize.Y
        p.ScrollBarThickness = SCROLL_W
        p.ScrollBarImageColor3 = CLR.accent
        p.ScrollBarImageTransparency = 0.2
        p.ScrollingEnabled = true
        p.ScrollingDirection = Enum.ScrollingDirection.Y
        p.ElasticBehavior = Enum.ElasticBehavior.Never
        p.Parent = content

        local lay = Instance.new("UIListLayout", p)
        lay.Padding = UDim.new(0, ROW_GAP)
        lay.SortOrder = Enum.SortOrder.LayoutOrder

        local pad = Instance.new("UIPadding", p)
        pad.PaddingTop    = UDim.new(0, PAD)
        pad.PaddingLeft   = UDim.new(0, PAD)
        pad.PaddingRight  = UDim.new(0, 6)
        pad.PaddingBottom = UDim.new(0, PAD + 8)

        PAGES[name] = p
        return p
    end

    local function selectPage(name)
        for n, p in pairs(PAGES) do p.Visible = (n == name) end
        for n, e in pairs(NAV) do e.setActive(n == name) end
    end

    local function mkNavItem(glyph, label, name, order)
        local item = Instance.new("TextButton")
        item.Size = UDim2.new(1, -6, 0, 40)
        item.BackgroundColor3 = CLR.navActive
        item.BackgroundTransparency = 1
        item.BorderSizePixel = 0
        item.Text = ""
        item.LayoutOrder = order
        item.AutoButtonColor = false
        item.Parent = navScroll
        Instance.new("UICorner", item).CornerRadius = UDim.new(0, 9)

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(0, 3, 0, 20)
        bar.Position = UDim2.new(0, 0, 0.5, -10)
        bar.BackgroundColor3 = CLR.accent
        bar.BackgroundTransparency = 1
        bar.BorderSizePixel = 0
        bar.Parent = item
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

        local ico = Instance.new("TextLabel")
        ico.Size = UDim2.new(0, 24, 0, 24)
        ico.Position = UDim2.new(0, 18, 0.5, -12)
        ico.BackgroundTransparency = 1
        ico.Text = glyph
        ico.TextColor3 = CLR.textDim
        ico.Font = FONT_B
        ico.TextSize = 15
        ico.Parent = item

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -56, 1, 0)
        lbl.Position = UDim2.new(0, 50, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = CLR.textDim
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = FONT_B
        lbl.TextSize = 13
        lbl.Parent = item

        local isActive = false
        local function setActive(a)
            isActive = a
            Tween:Create(item, TweenInfo.new(0.15), {
                BackgroundTransparency = a and 0 or 1,
                BackgroundColor3 = a and CLR.navActive or CLR.navHover,
            }):Play()
            Tween:Create(ico, TweenInfo.new(0.15), {
                TextColor3 = a and CLR.accent or CLR.textDim,
            }):Play()
            Tween:Create(lbl, TweenInfo.new(0.15), {
                TextColor3 = a and CLR.text or CLR.textDim,
            }):Play()
            Tween:Create(bar, TweenInfo.new(0.15), {
                BackgroundTransparency = a and 0 or 1,
            }):Play()
        end

        item.MouseEnter:Connect(function()
            if not isActive then
                Tween:Create(item, TweenInfo.new(0.12), {
                    BackgroundTransparency = 0,
                    BackgroundColor3 = CLR.navHover,
                }):Play()
            end
        end)
        item.MouseLeave:Connect(function()
            if not isActive then
                Tween:Create(item, TweenInfo.new(0.12), {
                    BackgroundTransparency = 1,
                }):Play()
            end
        end)
        item.MouseButton1Click:Connect(function() selectPage(name) end)

        NAV[name] = { item = item, setActive = setActive }
        return item
    end

    --============================================================
    -- TAB REGISTRATION
    --============================================================
    mkNavItem("◈", "Dashboard", "Dashboard", 1)
    mkNavItem("◆", "Combat",    "Combat",    2)
    mkNavItem("◎", "Targets",   "Targets",   3)
    mkNavItem("✦", "Quests",    "Quests",    4)
    mkNavItem("▤", "Config",    "Config",    5)
    mkNavItem("▥", "Files",     "Files",     6)
    mkNavItem("≡", "Logs",      "Logs",      7)
    mkNavItem("⚙", "Settings",  "Settings",  8)

    --============================================================
    -- DASHBOARD
    --============================================================
    local pDash = mkPage("Dashboard")

    -- Stat grid
    local grid = Instance.new("Frame")
    grid.Size = UDim2.new(1, -SCROLL_W - 4, 0, 148)
    grid.BackgroundTransparency = 1
    grid.LayoutOrder = nextOrder(pDash)
    grid.Parent = pDash
    local gl = Instance.new("UIGridLayout", grid)
    gl.CellSize = UDim2.new(0.5, -6, 0, 68)
    gl.CellPadding = UDim2.new(0, 12, 0, 12)
    gl.SortOrder = Enum.SortOrder.LayoutOrder

    local function mkStat(parent, label, order)
        local card = Instance.new("Frame")
        card.Size = UDim2.new(0, 100, 0, 68)
        card.BackgroundColor3 = CLR.row
        card.BorderSizePixel = 0
        card.LayoutOrder = order
        card.Parent = parent
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 11)

        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -32, 0, 14)
        l.Position = UDim2.new(0, 16, 0, 12)
        l.BackgroundTransparency = 1
        l.Text = string.upper(label)
        l.TextColor3 = CLR.textMuted
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Font = FONT_B
        l.TextSize = 10
        l.Parent = card

        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(1, -32, 0, 26)
        v.Position = UDim2.new(0, 16, 0, 30)
        v.BackgroundTransparency = 1
        v.Text = "—"
        v.TextColor3 = CLR.text
        v.TextXAlignment = Enum.TextXAlignment.Left
        v.Font = FONT_B
        v.TextSize = 20
        v.TextTruncate = Enum.TextTruncate.AtEnd
        v.Parent = card
        return v
    end

    local svState  = mkStat(grid, "State",  1)
    local svTarget = mkStat(grid, "Target", 2)
    local svHp     = mkStat(grid, "HP",     3)
    local svKills  = mkStat(grid, "Kills",  4)

    mkSection(pDash, "Control")
    mkButtonRow(pDash, "▶", "Start Combat",
        "Enable auto-combat and target acquisition",
        function() St.cbt = true; print("[Dingus] combat on") end)
    mkButtonRow(pDash, "■", "Stop Combat",
        "Halt combat loop",
        function()
            St.cbt = false
            if Ctx.Fly and Ctx.Fly.stop then pcall(Ctx.Fly.stop) end
            print("[Dingus] combat off")
        end, true)
    mkButtonRow(pDash, "◎", "Scan for Bosses",
        "Force a boss scan; results in F9",
        function()
            St.lScn = 0
            local l = Ctx.Detect.scanBosses()
            print("[Dingus] found " .. #l .. " bosses")
        end)
    mkButtonRow(pDash, "▲", "Force Move To Target",
        "Teleport above current target",
        function()
            if Ctx.Atk and Ctx.Atk.forceMove then Ctx.Atk.forceMove() end
        end)
    mkButtonRow(pDash, "↻", "Reset Movers",
        "Strip BodyMovers from HRP",
        function()
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
        end, true)

    --============================================================
    -- COMBAT
    --============================================================
    local pCombat = mkPage("Combat")

    mkSection(pCombat, "Automation")
    mkToggleRow(pCombat, "✦", "Auto Skill Rotation",
        "Cycles slot order per F-probe result", "skl")
    mkToggleRow(pCombat, "◆", "Auto Equip Weapon",
        "Swaps to first weapon in inventory", "eqp")
    mkToggleRow(pCombat, "◀", "Auto Retreat",
        "Dash away when HP drops", "rtr")
    mkToggleRow(pCombat, "◎", "Stun Punish",
        "Attack extra fast during stun", "stunPun")
    mkToggleRow(pCombat, "◇", "Guard Spoof",
        "Client-side HP / block reinforcement", "gsp")

    mkSection(pCombat, "Tuning")
    mkSliderRow(pCombat, "◈", "Attack Range", 6, 20,
        function() return Cfg.AtkRange end,
        function(v) Cfg.AtkRange = v end, "%.1f")
    mkSliderRow(pCombat, "◆", "Attack Interval", 0.30, 0.90,
        function() return St.aiI or Cfg.AtkInterval end,
        function(v) St.aiI = v end, "%.2f")
    mkSliderRow(pCombat, "▶", "Teleport Cooldown", 0.10, 0.80,
        function() return Cfg.TeleportCd or 0.22 end,
        function(v) Cfg.TeleportCd = v end, "%.2f")
    mkSliderRow(pCombat, "◀", "Retreat HP %", 10, 90,
        function() return Cfg.RetreatHP * 100 end,
        function(v) Cfg.RetreatHP = v / 100 end, "%.0f")

    local combatInfo = mkInfo(pCombat, 130)

    --============================================================
    -- TARGETS
    --============================================================
    local pTargets = mkPage("Targets")

    local targetHeader = mkInfo(pTargets, 40)
    local TARGET_CHECKBOXES = {}

    local function refreshTargetHeader()
        local enabled, total = 0, 0
        if Lists and Lists.enabledCount then
            enabled, total = Lists.enabledCount()
        end
        targetHeader.Text = string.format("  enabled: %d / %d bosses", enabled, total)
    end

    mkSection(pTargets, "Bulk")
    mkButtonRow(pTargets, "◈", "Select All",
        "Enable every boss in every region",
        function()
            if Lists and Lists.setAllBosses then
                Lists.setAllBosses(true)
                for name, setter in pairs(TARGET_CHECKBOXES) do
                    if setter then pcall(setter, true) end
                end
                refreshTargetHeader()
            end
        end)
    mkButtonRow(pTargets, "✕", "Clear All",
        "Disable every boss",
        function()
            if Lists and Lists.setAllBosses then
                Lists.setAllBosses(false)
                for name, setter in pairs(TARGET_CHECKBOXES) do
                    if setter then pcall(setter, false) end
                end
                refreshTargetHeader()
            end
        end, true)

    if Lists and Lists.bossRegions then
        for _, region in ipairs(Lists.bossRegions) do
            mkSection(pTargets, region.name)
            for _, bossName in ipairs(region.bosses) do
                local row = mkRow(pTargets, 48)
                mkIcon(row, "◆")

                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1, -110, 1, 0)
                lbl.Position = UDim2.new(0, 64, 0, 0)
                lbl.BackgroundTransparency = 1
                lbl.Text = bossName
                lbl.TextColor3 = CLR.text
                lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.Font = FONT_B
                lbl.TextSize = 13
                lbl.Parent = row

                local init = true
                if Lists.isBossEnabled then
                    init = Lists.isBossEnabled(bossName)
                end

                local sw, setter = mkSwitch(row, init, function(v)
                    if Lists.setBossEnabled then
                        Lists.setBossEnabled(bossName, v)
                    end
                    refreshTargetHeader()
                end)
                sw.Position = UDim2.new(1, -SCROLL_W - 6, 0.5, -11)
                sw.AnchorPoint = Vector2.new(1, 0)
                sw.ZIndex = 3
                TARGET_CHECKBOXES[bossName] = setter
            end
        end
    end

    refreshTargetHeader()

    --============================================================
    -- QUESTS
    --============================================================
    local pQuest = mkPage("Quests")

    mkSection(pQuest, "Crow")
    mkToggleRow(pQuest, "✦", "Auto Crow Quests",
        "Periodically read available crow quests", "crw")
    mkButtonRow(pQuest, "◆", "Equip Crow",
        "Find and equip the crow tool",
        function()
            local t = Ctx.Scan and Ctx.Scan.findCrowTool and Ctx.Scan.findCrowTool()
            local h = U.hum()
            if t and h and t:IsA("Tool") then
                pcall(function() h:EquipTool(t) end)
                print("[Dingus] crow equipped")
            end
        end)
    mkButtonRow(pQuest, "◈", "Summon Crow",
        "Call the crow with M1",
        function() U.m1() end)
    mkButtonRow(pQuest, "☰", "Read Quest Panel",
        "Scrape current quests from open panel",
        function()
            if Ctx.Scan and Ctx.Scan.readCrowQuests then
                local qs = Ctx.Scan.readCrowQuests()
                print(string.format("[Dingus][Crow] %d quests: %s",
                    #qs, table.concat(qs, ", ")))
            end
        end)

    mkSection(pQuest, "Quest Cycle")
    mkButtonRow(pQuest, "↻", "Run Quest Cycle",
        "Force a quest discovery pass",
        function()
            if Ctx.Quest and Ctx.Quest.doCycle then Ctx.Quest.doCycle() end
        end)

    local questInfo = mkInfo(pQuest, 130)

    --============================================================
    -- CONFIG
    --============================================================
    local pConfig = mkPage("Config")

    mkSection(pConfig, "Active Slot")
    mkInputRow(pConfig, "▤", "Slot Name", ConfigMgr.currentSlot, function(text)
        ConfigMgr.currentSlot = text
        print("[Dingus][Config] slot = " .. text)
    end)

    mkSection(pConfig, "Actions")
    mkButtonRow(pConfig, "▶", "Save to Slot",
        "Persist current settings",
        function()
            local ok, err = ConfigMgr.saveTo()
            print("[Dingus][Config] save " .. (ok and "ok" or ("fail: " .. tostring(err))))
        end)
    mkButtonRow(pConfig, "◀", "Load from Slot",
        "Read settings from disk",
        function()
            local ok, err = ConfigMgr.loadFrom()
            print("[Dingus][Config] load " .. (ok and tostring(err) or ("fail: " .. tostring(err))))
        end)
    mkButtonRow(pConfig, "✕", "Delete Current Slot",
        "Remove the slot file",
        function()
            local ok = ConfigMgr.deleteSlot(ConfigMgr.currentSlot)
            print("[Dingus][Config] delete " .. tostring(ok))
        end, true)
    mkButtonRow(pConfig, "↻", "Reset to Defaults",
        "Restore factory settings",
        function()
            if Ctx.Cfg and Ctx.Cfg.reset then Ctx.Cfg.reset() end
            print("[Dingus][Config] reset")
        end, true)
    mkButtonRow(pConfig, "≡", "Print Values to F9",
        "Dump full config to console",
        function()
            if Ctx.Cfg and Ctx.Cfg.pretty then print(Ctx.Cfg.pretty()) end
        end)

    local configInfo = mkInfo(pConfig, 110)
    local slotsInfo  = mkInfo(pConfig, 110)

    --============================================================
    -- FILES
    --============================================================
    local pFiles = mkPage("Files")

    mkSection(pFiles, "Actions")
    mkButtonRow(pFiles, "↻", "Refresh File List",
        "Re-scan the Dingus folder",
        function()
            FileMgr.refresh()
            print("[Dingus][Files] refreshed: " .. #FileMgr.files .. " files")
        end)
    mkButtonRow(pFiles, "✕", "Delete boot log",
        "Remove dingus_boot_log.txt",
        function()
            local ok = FileMgr.delete("dingus_boot_log.txt")
            print("[Dingus][Files] delete log: " .. tostring(ok))
        end, true)

    mkSection(pFiles, "Discovered")
    local filesInfo = mkInfo(pFiles, 260)

    --============================================================
    -- LOGS
    --============================================================
    local pLogs = mkPage("Logs")
    -- Override: logs page uses fixed height log frame, not list
    -- Remove the auto layout and add manual positioning
    for _, child in ipairs(pLogs:GetChildren()) do
        if child:IsA("UIPadding") then child:Destroy() end
    end
    local logPad = Instance.new("UIPadding", pLogs)
    logPad.PaddingTop    = UDim.new(0, PAD)
    logPad.PaddingLeft   = UDim.new(0, PAD)
    logPad.PaddingRight  = UDim.new(0, PAD + 4)
    logPad.PaddingBottom = UDim.new(0, PAD)

    local filterRow = Instance.new("Frame")
    filterRow.Size = UDim2.new(1, -SCROLL_W - 8, 0, 34)
    filterRow.Position = UDim2.new(0, 0, 0, 0)
    filterRow.BackgroundTransparency = 1
    filterRow.Parent = pLogs

    local filterBtns = {}
    local function mkFilterBtn(label, key, x, w)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 1, 0)
        b.Position = UDim2.new(0, x, 0, 0)
        b.BackgroundColor3 = (Log.filter == key) and CLR.accent or CLR.bgPanel
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = (Log.filter == key) and CLR.text or CLR.textDim
        b.Font = FONT_B
        b.TextSize = 12
        b.AutoButtonColor = false
        b.Parent = filterRow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        filterBtns[key] = b
        b.MouseButton1Click:Connect(function()
            Log.filter = key
            for k, btn in pairs(filterBtns) do
                btn.BackgroundColor3 = (k == key) and CLR.accent or CLR.bgPanel
                btn.TextColor3 = (k == key) and CLR.text or CLR.textDim
            end
            Log.pendingUpdate = true
        end)
    end
    mkFilterBtn("All",    "all",    0,   60)
    mkFilterBtn("Dingus", "dingus", 64,  80)
    mkFilterBtn("Errors", "errors", 148, 74)

    local function mkLogBtn(label, x, w, cb, tint)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 1, 0)
        b.Position = UDim2.new(0, x, 0, 0)
        b.BackgroundColor3 = tint or CLR.bgPanel
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = CLR.text
        b.Font = FONT_B
        b.TextSize = 12
        b.AutoButtonColor = false
        b.Parent = filterRow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        b.MouseButton1Click:Connect(cb)
    end
    mkLogBtn("Clear", 240, 66, function()
        Log.clear(); print("[Dingus][Log] cleared")
    end, CLR.red)
    mkLogBtn("Pause", 310, 66, function()
        Log.paused = not Log.paused
        print("[Dingus][Log] paused = " .. tostring(Log.paused))
    end, CLR.orange)
    mkLogBtn("Save",  380, 66, function()
        local ok = Log.export("dingus_combat_log.txt")
        print("[Dingus][Log] exported: " .. tostring(ok))
    end)
    mkLogBtn("Copy",  450, 66, function()
        local lines = {}
        for i = 1, #Log.buffer do
            local e = Log.buffer[i]
            lines[#lines+1] = string.format("[%s] %s", e.time, e.text)
        end
        if setclipboard then pcall(setclipboard, table.concat(lines, "\n")) end
        print("[Dingus][Log] copied " .. #lines .. " lines")
    end, CLR.green)

    local logFrame = Instance.new("Frame")
    logFrame.Size = UDim2.new(1, -SCROLL_W - 8, 1, -48)
    logFrame.Position = UDim2.new(0, 0, 0, 46)
    logFrame.BackgroundColor3 = CLR.bgPanel
    logFrame.BorderSizePixel = 0
    logFrame.Parent = pLogs
    Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0, 11)

    local logScroll = Instance.new("ScrollingFrame")
    logScroll.Size = UDim2.new(1, -12, 1, -12)
    logScroll.Position = UDim2.new(0, 6, 0, 6)
    logScroll.BackgroundTransparency = 1
    logScroll.BorderSizePixel = 0
    logScroll.ScrollBarThickness = 8
    logScroll.ScrollBarImageColor3 = CLR.accent
    logScroll.ScrollBarImageTransparency = 0.3
    logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    logScroll.ScrollingEnabled = true
    logScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    logScroll.ElasticBehavior = Enum.ElasticBehavior.Never
    logScroll.Parent = logFrame
    local logLay = Instance.new("UIListLayout", logScroll)
    logLay.Padding = UDim.new(0, 3)
    logLay.SortOrder = Enum.SortOrder.LayoutOrder

    local logRows = {}
    local MAX_VISIBLE = 250

    local function colorFor(mt)
        if mt == Enum.MessageType.MessageError then return CLR.logError end
        if mt == Enum.MessageType.MessageWarning then return CLR.logWarn end
        if mt == Enum.MessageType.MessageOutput then return CLR.logInfo end
        return CLR.logDingus
    end

    local function rebuildLog()
        for _, r in ipairs(logRows) do r:Destroy() end
        logRows = {}
        local entries = Log.buffer
        local start = math.max(1, #entries - MAX_VISIBLE + 1)
        for i = start, #entries do
            local e = entries[i]
            local row = Instance.new("TextLabel")
            row.Size = UDim2.new(1, -8, 0, 15)
            row.BackgroundTransparency = 1
            row.Text = "  [" .. e.time .. "] " .. e.text
            row.TextColor3 = colorFor(e.type)
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.Font = FONT_C
            row.TextSize = 11
            row.TextTruncate = Enum.TextTruncate.AtEnd
            row.LayoutOrder = i
            row.Parent = logScroll
            table.insert(logRows, row)
        end
        logScroll.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y)
    end

    --============================================================
    -- SETTINGS
    --============================================================
    local pSettings = mkPage("Settings")

    mkSection(pSettings, "Concealment")
    mkToggleRow(pSettings, "◈", "Concealed Parent",
        "Uses gethui/CoreGui. Takes effect on reload.",
        "GuiConcealed",
        function(v) Cfg.GuiConcealed = v end)
    mkToggleRow(pSettings, "◇", "Panic Keybind Enabled",
        "RightCtrl + Backspace hides the GUI",
        "GuiPanicHide",
        function(v) Cfg.GuiPanicHide = v end)

    mkButtonRow(pSettings, "⇩", "Panic Hide Now",
        "Tear down the GUI immediately",
        function()
            if gui and gui.Parent then
                gui.Parent = nil
                print("[Dingus] GUI hidden (panic)")
            end
        end, true)

    mkSection(pSettings, "Diagnostics")
    local parentInfo = mkInfo(pSettings, 80)
    local runtimeInfo = mkInfo(pSettings, 140)

    --============================================================
    -- DEFAULT PAGE
    --============================================================
    selectPage("Dashboard")

    --============================================================
    -- MINIMIZE / RESTORE
    --============================================================
    local PILL_W, PILL_H = 180, 40
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
    pillStroke.Color = CLR.accent
    pillStroke.Thickness = 1.5

    local pDot = Instance.new("Frame")
    pDot.Size = UDim2.new(0, 8, 0, 8)
    pDot.Position = UDim2.new(0, 16, 0.5, -4)
    pDot.BackgroundColor3 = CLR.accent
    pDot.BorderSizePixel = 0
    pDot.Parent = pill
    Instance.new("UICorner", pDot).CornerRadius = UDim.new(1, 0)

    local pLbl = Instance.new("TextLabel")
    pLbl.Size = UDim2.new(1, -36, 1, 0)
    pLbl.Position = UDim2.new(0, 32, 0, 0)
    pLbl.BackgroundTransparency = 1
    pLbl.Text = "Dingus-Slayer"
    pLbl.TextColor3 = CLR.text
    pLbl.TextXAlignment = Enum.TextXAlignment.Left
    pLbl.Font = FONT_B
    pLbl.TextSize = 13
    pLbl.Parent = pill

    local pBtn = Instance.new("TextButton")
    pBtn.Size = UDim2.new(1, 0, 1, 0)
    pBtn.BackgroundTransparency = 1
    pBtn.Text = ""
    pBtn.Parent = pill

    local minimized = false
    local TWEEN_IN  = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local TWEEN_OUT = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    local savedPos = win.Position

    local function minimize()
        if minimized then return end
        minimized = true
        savedPos = win.Position
        local t = Tween:Create(win, TWEEN_OUT, {
            Position = UDim2.new(savedPos.X.Scale, savedPos.X.Offset,
                                 savedPos.Y.Scale, savedPos.Y.Offset + 40),
            BackgroundTransparency = 1,
        })
        t:Play()
        t.Completed:Connect(function()
            win.Visible = false
            win.Position = savedPos
            win.BackgroundTransparency = 0
        end)
        task.wait(0.15)
        pill.Visible = true
        pill.BackgroundTransparency = 1
        pillStroke.Transparency = 1
        pDot.BackgroundTransparency = 1
        pLbl.TextTransparency = 1
        Tween:Create(pill,       TweenInfo.new(0.22), { BackgroundTransparency = 0 }):Play()
        Tween:Create(pillStroke, TweenInfo.new(0.22), { Transparency = 0 }):Play()
        Tween:Create(pDot,       TweenInfo.new(0.22), { BackgroundTransparency = 0 }):Play()
        Tween:Create(pLbl,       TweenInfo.new(0.22), { TextTransparency = 0 }):Play()
    end

    local function restore()
        if not minimized then return end
        minimized = false
        Tween:Create(pill,       TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
        Tween:Create(pillStroke, TweenInfo.new(0.15), { Transparency = 1 }):Play()
        Tween:Create(pDot,       TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
        Tween:Create(pLbl,       TweenInfo.new(0.15), { TextTransparency = 1 }):Play()
        task.wait(0.12)
        pill.Visible = false
        win.Visible = true
        win.Position = UDim2.new(savedPos.X.Scale, savedPos.X.Offset,
                                 savedPos.Y.Scale, savedPos.Y.Offset + 40)
        win.BackgroundTransparency = 1
        Tween:Create(win, TWEEN_IN, {
            Position = savedPos,
            BackgroundTransparency = 0,
        }):Play()
    end

    minBtn.MouseButton1Click:Connect(minimize)
    pBtn.MouseButton1Click:Connect(restore)

    --============================================================
    -- REFRESH LOOP
    --============================================================
    local cache = {}
    task.spawn(function()
        while St.run do
            if St.boot and not minimized then
                local h = U.hum()
                local hp = h and string.format("%d/%d",
                    math.floor(h.Health), math.floor(h.MaxHealth)) or "?"

                local s_state = tostring(St.cbtS or "—")
                if cache.s_state ~= s_state then
                    cache.s_state = s_state
                    svState.Text = s_state
                end
                local s_tgt = St.tgt and St.tgt.ch.Name or "none"
                if cache.s_tgt ~= s_tgt then
                    cache.s_tgt = s_tgt
                    svTarget.Text = s_tgt
                end
                if cache.s_hp ~= hp then
                    cache.s_hp = hp
                    svHp.Text = hp
                end
                local s_kill = tostring(St.bKll or 0)
                if cache.s_kill ~= s_kill then
                    cache.s_kill = s_kill
                    svKills.Text = s_kill
                end

                -- Combat info
                local hitRate = St.aAt > 0 and math.floor(St.aHi / St.aAt * 100) or 0
                local fInfo = Ctx.Atk and Ctx.Atk.fModeInfo and Ctx.Atk.fModeInfo() or {}
                local tInfo = Ctx.Atk and Ctx.Atk.telemetry and Ctx.Atk.telemetry() or {}
                local ci = string.format(
                    "  state: %s  ·  hits: %d/%d (%d%%)\n" ..
                    "  kills: %d  ·  retreats: %d  ·  skills: %d\n" ..
                    "  threats: %d  ·  zone: %d  ·  imminent: %d\n" ..
                    "  F-mode: %s  ·  blocking: %s\n" ..
                    "  teleports: %d  ·  last gap: %.2fs\n" ..
                    "  hp: %s  ·  atk interval: %.2f",
                    St.cbtS or "—", St.aHi or 0, St.aAt or 0, hitRate,
                    St.bKll or 0, St.rtrC or 0, St.skC or 0,
                    St.zn or 0, St.zn or 0, St.imm or 0,
                    fInfo.isBlock and "BLOCK" or (fInfo.resolved and "SKILL" or "?"),
                    tostring(fInfo.blocking),
                    tInfo.teleports or 0, tInfo.lastTeleportGap or 0,
                    hp, St.aiI or 0)
                if cache.combatInfo ~= ci then cache.combatInfo = ci; combatInfo.Text = ci end

                -- Quest info
                local qi = string.format(
                    "  crow tool: %s\n" ..
                    "  perched: %s  ·  quests read: %d\n" ..
                    "  player level: %d  ·  hunts: %d\n" ..
                    "  crow cycles: %d  ·  cards taken: %d\n" ..
                    "  quest target: %s",
                    St.crT and St.crT.Name or "not found",
                    tostring(St.cPrch), St.crQuests and #St.crQuests or 0,
                    St.playerLevel or 0, St.huntCount or 0,
                    St.crowCycle or 0, St.crowTake or 0,
                    tostring(St.questTarget or "—"))
                if cache.questInfo ~= qi then cache.questInfo = qi; questInfo.Text = qi end

                -- Config info
                local slotList = ConfigMgr.listSlots()
                local cfgi = string.format(
                    "  active slot: %s\n" ..
                    "  file: %s\n" ..
                    "  saved slots: %d\n" ..
                    "  writefile: %s  ·  readfile: %s",
                    ConfigMgr.currentSlot,
                    Ctx.Cfg.slotFile and Ctx.Cfg.slotFile(ConfigMgr.currentSlot) or "?",
                    #slotList,
                    tostring(HAS.writefile), tostring(HAS.readfile))
                if cache.configInfo ~= cfgi then cache.configInfo = cfgi; configInfo.Text = cfgi end

                local slotLines = { "  available slots:" }
                for i = 1, math.min(#slotList, 10) do
                    local s = slotList[i]
                    slotLines[#slotLines+1] = string.format("    · %s (%d bytes)", s.name, s.size)
                end
                if #slotList == 0 then slotLines[#slotLines+1] = "    (none)" end
                local sl = table.concat(slotLines, "\n")
                if cache.slotsInfo ~= sl then cache.slotsInfo = sl; slotsInfo.Text = sl end

                FileMgr.refresh()
                local fileLines = { string.format("  files: %d", #FileMgr.files) }
                for i = 1, math.min(#FileMgr.files, 20) do
                    local f = FileMgr.files[i]
                    fileLines[#fileLines+1] = string.format("    · %s (%d bytes)", f.name, f.size or 0)
                end
                local fi = table.concat(fileLines, "\n")
                if cache.filesInfo ~= fi then cache.filesInfo = fi; filesInfo.Text = fi end

                local pi = string.format(
                    "  parent: %s\n" ..
                    "  instance name: %s\n" ..
                    "  gethui available: %s\n" ..
                    "  concealed mode: %s",
                    parentKind, guiName,
                    tostring(HAS.gethui),
                    tostring(Cfg.GuiConcealed))
                if cache.parentInfo ~= pi then cache.parentInfo = pi; parentInfo.Text = pi end

                local ri = string.format(
                    "  fps: %.0f\n" ..
                    "  boot: %s  ·  combat: %s\n" ..
                    "  spoofers: %s  ·  crow: %s\n" ..
                    "  bosses loaded: %d",
                    St.fps or 60,
                    tostring(St.boot), St.cbt and "on" or "off",
                    St.gsp and "on" or "off", St.crw and "on" or "off",
                    Lists and #Lists.bosses or 0)
                if cache.runtimeInfo ~= ri then cache.runtimeInfo = ri; runtimeInfo.Text = ri end

                -- Header status
                local bar = string.format("%s · fps %.0f · log %d",
                    St.cbt and "combat" or "idle", St.fps or 60, #Log.buffer)
                if cache.live ~= bar then cache.live = bar; liveLbl.Text = bar end
                local colorKey = St.cbt and "g" or "m"
                if cache.fDot ~= colorKey then
                    cache.fDot = colorKey
                    fDot.BackgroundColor3 = St.cbt and CLR.green or CLR.textMuted
                    liveDot.BackgroundColor3 = St.cbt and CLR.green or CLR.textMuted
                end

                if Log.pendingUpdate then
                    Log.pendingUpdate = false
                    rebuildLog()
                end
            end
            task.wait(0.3)
        end
    end)

    --============================================================
    -- HOTKEYS
    --============================================================
    UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            if minimized then restore() else minimize() end
            return
        end
        if Cfg.GuiPanicHide
           and input.KeyCode == Enum.KeyCode.Backspace
           and UIS:IsKeyDown(Enum.KeyCode.RightControl) then
            gui.Parent = nil
            print("[Dingus] GUI panic-hidden · reload to restore")
        end
    end)

    --============================================================
    -- CLOSE
    --============================================================
    closeBtn.MouseButton1Click:Connect(function()
        restoreGlobals()
        gui:Destroy()
    end)

    --============================================================
    -- EXPOSE
    --============================================================
    G.gui        = gui
    G.win        = win
    G.minimize   = minimize
    G.restore    = restore
    G.Log        = Log
    G.FileMgr    = FileMgr
    G.ConfigMgr  = ConfigMgr
    G.PAGES      = PAGES
    G.parent     = parent
    G.parentKind = parentKind

    print(string.format("[Dingus][gui] v32 initialized · parent=%s · name=%s",
        parentKind, guiName))
end

return G
