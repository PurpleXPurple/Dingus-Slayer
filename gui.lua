--[[
    Dingus-Slayer · gui.lua v28
    Sidebar layout · section-grouped card rows · custom switch widget.
    Matches Ctx.Gui contract: win, minimize, restore, gui, Log, FileMgr, ConfigMgr.
    Restores _G.print / _G.warn on close (audit M3).
    ConfigMgr delegates to Ctx.Cfg.save/load for single-file-source.
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
    -- CAPABILITIES
    --============================================================
    local HAS = {
        writefile  = type(writefile) == "function",
        readfile   = type(readfile) == "function",
        delfile    = type(delfile) == "function",
        isfile     = type(isfile) == "function",
        listfiles  = type(listfiles) == "function",
        makefolder = type(makefolder) == "function",
    }

    --============================================================
    -- PALETTE
    --============================================================
    local CLR = {
        bg          = Color3.fromRGB(12, 12, 16),
        bgHeader    = Color3.fromRGB(14, 14, 20),
        bgSidebar   = Color3.fromRGB(10, 10, 14),
        bgPanel     = Color3.fromRGB(16, 16, 22),
        row         = Color3.fromRGB(22, 22, 30),
        rowHover    = Color3.fromRGB(28, 28, 38),
        iconBg      = Color3.fromRGB(38, 22, 22),
        iconBgDim   = Color3.fromRGB(26, 22, 26),
        navActive   = Color3.fromRGB(34, 22, 22),
        navHover    = Color3.fromRGB(20, 20, 28),
        trackOff    = Color3.fromRGB(48, 48, 62),
        border      = Color3.fromRGB(36, 30, 32),

        accent      = Color3.fromRGB(220, 90, 70),
        accentSoft  = Color3.fromRGB(240, 130, 110),
        accentDim   = Color3.fromRGB(150, 60, 50),

        green       = Color3.fromRGB(80, 200, 120),
        red         = Color3.fromRGB(220, 70, 80),
        blue        = Color3.fromRGB(70, 130, 200),
        orange      = Color3.fromRGB(210, 140, 80),

        text        = Color3.fromRGB(232, 232, 240),
        textDim     = Color3.fromRGB(160, 165, 180),
        textMuted   = Color3.fromRGB(105, 110, 130),

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
        local ok = pcall(writefile, filename, table.concat(lines, "\n"))
        return ok
    end

    -- LogService hook (safe, non-destructive)
    pcall(function()
        LogService.MessageOut:Connect(function(msg, msgType)
            pcall(Log.add, msg, msgType)
        end)
    end)

    -- print/warn hook (restored on close)
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
    -- CONFIG MANAGER (delegates to Cfg.save / Cfg.load)
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
    -- ROOT
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

    local WIN_W, WIN_H = 720, 560
    local HEADER_H  = 44
    local SIDEBAR_W = 180
    local PAD       = 12

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
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 12)
    local winStroke = Instance.new("UIStroke", win)
    winStroke.Color = CLR.border
    winStroke.Thickness = 1
    winStroke.Transparency = 0.35

    --============================================================
    -- HEADER
    --============================================================
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, HEADER_H)
    header.BackgroundColor3 = CLR.bgHeader
    header.BorderSizePixel = 0
    header.Parent = win
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)
    local hFix = Instance.new("Frame")
    hFix.Size = UDim2.new(1, 0, 0, 12)
    hFix.Position = UDim2.new(0, 0, 1, -12)
    hFix.BackgroundColor3 = CLR.bgHeader
    hFix.BorderSizePixel = 0
    hFix.Parent = header

    -- logo chip
    local chip = Instance.new("Frame")
    chip.Size = UDim2.new(0, 26, 0, 26)
    chip.Position = UDim2.new(0, 14, 0.5, -13)
    chip.BackgroundColor3 = CLR.accent
    chip.BorderSizePixel = 0
    chip.Parent = header
    Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 7)
    local chipLbl = Instance.new("TextLabel")
    chipLbl.Size = UDim2.new(1, 0, 1, 0)
    chipLbl.BackgroundTransparency = 1
    chipLbl.Text = "D"
    chipLbl.TextColor3 = Color3.fromRGB(255, 245, 240)
    chipLbl.Font = FONT_B
    chipLbl.TextSize = 15
    chipLbl.Parent = chip

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(0, 240, 1, 0)
    titleLbl.Position = UDim2.new(0, 50, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "Dingus-Slayer"
    titleLbl.TextColor3 = CLR.text
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Font = FONT_B
    titleLbl.TextSize = 14
    titleLbl.Parent = header

    -- live dot
    local liveDot = Instance.new("Frame")
    liveDot.Size = UDim2.new(0, 6, 0, 6)
    liveDot.Position = UDim2.new(0, 176, 0.5, -3)
    liveDot.BackgroundColor3 = CLR.green
    liveDot.BorderSizePixel = 0
    liveDot.Parent = header
    Instance.new("UICorner", liveDot).CornerRadius = UDim.new(1, 0)

    local liveLbl = Instance.new("TextLabel")
    liveLbl.Size = UDim2.new(0, 60, 1, 0)
    liveLbl.Position = UDim2.new(0, 188, 0, 0)
    liveLbl.BackgroundTransparency = 1
    liveLbl.Text = "ready"
    liveLbl.TextColor3 = CLR.textMuted
    liveLbl.TextXAlignment = Enum.TextXAlignment.Left
    liveLbl.Font = FONT_B
    liveLbl.TextSize = 10
    liveLbl.Parent = header

    local function mkCtrlBtn(glyph, offset, base, hover)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 26, 0, 26)
        b.Position = UDim2.new(1, offset, 0.5, -13)
        b.BackgroundColor3 = base
        b.BackgroundTransparency = 1
        b.BorderSizePixel = 0
        b.Text = glyph
        b.TextColor3 = CLR.textDim
        b.Font = FONT_B
        b.TextSize = 14
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

    local closeBtn = mkCtrlBtn("✕", -38, CLR.red, CLR.red)
    local minBtn   = mkCtrlBtn("–", -70, Color3.fromRGB(60,60,75), Color3.fromRGB(70,70,90))

    --============================================================
    -- SIDEBAR
    --============================================================
    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, -HEADER_H)
    sidebar.Position = UDim2.new(0, 0, 0, HEADER_H)
    sidebar.BackgroundColor3 = CLR.bgSidebar
    sidebar.BorderSizePixel = 0
    sidebar.Parent = win

    local sideMenuLbl = Instance.new("TextLabel")
    sideMenuLbl.Size = UDim2.new(1, -24, 0, 18)
    sideMenuLbl.Position = UDim2.new(0, 16, 0, 14)
    sideMenuLbl.BackgroundTransparency = 1
    sideMenuLbl.Text = "MENU"
    sideMenuLbl.TextColor3 = CLR.textMuted
    sideMenuLbl.TextXAlignment = Enum.TextXAlignment.Left
    sideMenuLbl.Font = FONT_B
    sideMenuLbl.TextSize = 9
    sideMenuLbl.Parent = sidebar

    local navHolder = Instance.new("Frame")
    navHolder.Size = UDim2.new(1, -16, 1, -80)
    navHolder.Position = UDim2.new(0, 8, 0, 38)
    navHolder.BackgroundTransparency = 1
    navHolder.Parent = sidebar
    local navLay = Instance.new("UIListLayout", navHolder)
    navLay.Padding = UDim.new(0, 4)
    navLay.SortOrder = Enum.SortOrder.LayoutOrder

    local sideFooter = Instance.new("Frame")
    sideFooter.Size = UDim2.new(1, -16, 0, 34)
    sideFooter.Position = UDim2.new(0, 8, 1, -42)
    sideFooter.BackgroundColor3 = CLR.bgPanel
    sideFooter.BorderSizePixel = 0
    sideFooter.Parent = sidebar
    Instance.new("UICorner", sideFooter).CornerRadius = UDim.new(0, 8)

    local fDot = Instance.new("Frame")
    fDot.Size = UDim2.new(0, 6, 0, 6)
    fDot.Position = UDim2.new(0, 12, 0.5, -3)
    fDot.BackgroundColor3 = CLR.green
    fDot.BorderSizePixel = 0
    fDot.Parent = sideFooter
    Instance.new("UICorner", fDot).CornerRadius = UDim.new(1, 0)

    local fLbl = Instance.new("TextLabel")
    fLbl.Size = UDim2.new(1, -32, 1, 0)
    fLbl.Position = UDim2.new(0, 24, 0, 0)
    fLbl.BackgroundTransparency = 1
    fLbl.Text = "v26 · idle"
    fLbl.TextColor3 = CLR.textMuted
    fLbl.TextXAlignment = Enum.TextXAlignment.Left
    fLbl.Font = FONT_B
    fLbl.TextSize = 10
    fLbl.Parent = sideFooter

    --============================================================
    -- CONTENT AREA
    --============================================================
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -SIDEBAR_W, 1, -HEADER_H)
    content.Position = UDim2.new(0, SIDEBAR_W, 0, HEADER_H)
    content.BackgroundColor3 = CLR.bg
    content.BorderSizePixel = 0
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
        track.Size = UDim2.new(0, 38, 0, 20)
        track.BackgroundColor3 = initial and CLR.accent or CLR.trackOff
        track.BorderSizePixel = 0
        track.Text = ""
        track.AutoButtonColor = false
        track.Parent = par
        Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 16, 0, 16)
        knob.Position = initial and UDim2.new(1, -18, 0.5, -8)
                             or  UDim2.new(0, 2, 0.5, -8)
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
                Position = state and UDim2.new(1, -18, 0.5, -8)
                                or  UDim2.new(0, 2, 0.5, -8),
            }):Play()
            if onChange then pcall(onChange, state) end
        end
        track.MouseButton1Click:Connect(function() set(not state) end)
        return track, set
    end

    local function mkIcon(par, glyph, dim)
        local box = Instance.new("Frame")
        box.Size = UDim2.new(0, 32, 0, 32)
        box.Position = UDim2.new(0, 14, 0, 11)
        box.BackgroundColor3 = dim and CLR.iconBgDim or CLR.iconBg
        box.BorderSizePixel = 0
        box.Parent = par
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = glyph
        lbl.TextColor3 = dim and CLR.textDim or CLR.accent
        lbl.Font = FONT_B
        lbl.TextSize = 15
        lbl.Parent = box
        return box
    end

    local function mkRow(page, height)
        local r = Instance.new("Frame")
        r.Size = UDim2.new(1, 0, 0, height)
        r.BackgroundColor3 = CLR.row
        r.BorderSizePixel = 0
        r.LayoutOrder = nextOrder(page)
        r.Active = true
        r.Parent = page
        Instance.new("UICorner", r).CornerRadius = UDim.new(0, 10)
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
        t.Size = UDim2.new(1, -80, 0, 16)
        t.Position = UDim2.new(0, 56, 0, titleY or 11)
        t.BackgroundTransparency = 1
        t.Text = title
        t.TextColor3 = CLR.text
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Font = FONT_B
        t.TextSize = 13
        t.Parent = row

        local d = nil
        if desc and desc ~= "" then
            d = Instance.new("TextLabel")
            d.Size = UDim2.new(1, -80, 0, 14)
            d.Position = UDim2.new(0, 56, 0, (titleY or 11) + 18)
            d.BackgroundTransparency = 1
            d.Text = desc
            d.TextColor3 = CLR.textMuted
            d.TextXAlignment = Enum.TextXAlignment.Left
            d.Font = FONT_R
            d.TextSize = 11
            d.TextTruncate = Enum.TextTruncate.AtEnd
            d.Parent = row
        end
        return t, d
    end

    local function mkSection(page, text)
        local h = Instance.new("TextLabel")
        h.Size = UDim2.new(1, 0, 0, 22)
        h.BackgroundTransparency = 1
        h.Text = string.upper(text)
        h.TextColor3 = CLR.textMuted
        h.TextXAlignment = Enum.TextXAlignment.Left
        h.TextYAlignment = Enum.TextYAlignment.Bottom
        h.Font = FONT_B
        h.TextSize = 9
        h.LayoutOrder = nextOrder(page)
        h.Parent = page
        local pad = Instance.new("UIPadding", h)
        pad.PaddingLeft = UDim.new(0, 4)
        pad.PaddingBottom = UDim.new(0, 2)
        return h
    end

    local function mkToggleRow(page, glyph, title, desc, key, onChange)
        local row = mkRow(page, 56)
        mkIcon(row, glyph)
        mkTitleDesc(row, title, desc)
        local sw = mkSwitch(row, St[key], function(v)
            St[key] = v
            if onChange then pcall(onChange, v) end
        end)
        sw.Position = UDim2.new(1, -52, 0.5, -10)
        sw.ZIndex = 3
        return row
    end

    local function mkSliderRow(page, glyph, title, minV, maxV, getter, setter, fmt)
        fmt = fmt or "%.1f"
        local row = mkRow(page, 62)
        mkIcon(row, glyph)

        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -140, 0, 16)
        t.Position = UDim2.new(0, 56, 0, 12)
        t.BackgroundTransparency = 1
        t.Text = title
        t.TextColor3 = CLR.text
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Font = FONT_B
        t.TextSize = 13
        t.Parent = row

        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(0, 70, 0, 16)
        v.Position = UDim2.new(1, -84, 0, 12)
        v.BackgroundTransparency = 1
        v.Text = string.format(fmt, getter())
        v.TextColor3 = CLR.accent
        v.TextXAlignment = Enum.TextXAlignment.Right
        v.Font = FONT_B
        v.TextSize = 12
        v.Parent = row

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(1, -72, 0, 5)
        bar.Position = UDim2.new(0, 56, 0, 42)
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
        knob.Size = UDim2.new(0, 12, 0, 12)
        knob.Position = UDim2.new(pct, -6, 0.5, -6)
        knob.BackgroundColor3 = Color3.fromRGB(255, 245, 240)
        knob.BorderSizePixel = 0
        knob.ZIndex = 2
        knob.Parent = bar
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, -72, 0, 22)
        hit.Position = UDim2.new(0, 56, 0, 33)
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
                    knob.Position = UDim2.new(p, -6, 0.5, -6)
                end
            end
        end)
        return row
    end

    local function mkButtonRow(page, glyph, title, desc, cb, tint)
        local row = mkRow(page, 50)
        mkIcon(row, glyph, tint)
        mkTitleDesc(row, title, desc, 16)

        -- chevron
        local chev = Instance.new("TextLabel")
        chev.Size = UDim2.new(0, 20, 0, 20)
        chev.Position = UDim2.new(1, -34, 0.5, -10)
        chev.BackgroundTransparency = 1
        chev.Text = "›"
        chev.TextColor3 = CLR.textMuted
        chev.Font = FONT_B
        chev.TextSize = 18
        chev.Parent = row

        -- click overlay (excludes chevron visually but captures whole row)
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
        local row = mkRow(page, 50)
        mkIcon(row, glyph)
        mkTitleDesc(row, title, nil, 16)

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0, 140, 0, 26)
        box.Position = UDim2.new(1, -154, 0.5, -13)
        box.BackgroundColor3 = CLR.bgPanel
        box.BorderSizePixel = 0
        box.Text = default or ""
        box.TextColor3 = CLR.text
        box.PlaceholderText = "enter..."
        box.PlaceholderColor3 = CLR.textMuted
        box.Font = FONT_R
        box.TextSize = 12
        box.ClearTextOnFocus = false
        box.Parent = row
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)
        box.FocusLost:Connect(function(enter)
            if enter and onCommit then pcall(onCommit, box.Text) end
        end)
        return row
    end

    local function mkInfo(page, height)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, height or 100)
        lbl.BackgroundColor3 = CLR.row
        lbl.BorderSizePixel = 0
        lbl.Text = "  —"
        lbl.TextColor3 = CLR.textDim
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Top
        lbl.Font = FONT_C
        lbl.TextSize = 11
        lbl.TextWrapped = true
        lbl.LayoutOrder = nextOrder(page)
        lbl.Parent = page
        Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 10)
        local pad = Instance.new("UIPadding", lbl)
        pad.PaddingTop = UDim.new(0, 10)
        pad.PaddingLeft = UDim.new(0, 12)
        pad.PaddingRight = UDim.new(0, 12)
        return lbl
    end

    --============================================================
    -- PAGES
    --============================================================
    local PAGES = {}
    local NAV = {}

    local function mkPage(name, scrolling)
        scrolling = scrolling ~= false
        local p
        if scrolling then
            p = Instance.new("ScrollingFrame")
            p.ScrollBarThickness = 4
            p.ScrollBarImageColor3 = CLR.accentDim
            p.ScrollBarImageTransparency = 0.3
            p.CanvasSize = UDim2.new(0, 0, 0, 0)
            p.AutomaticCanvasSize = Enum.AutomaticSize.Y
        else
            p = Instance.new("Frame")
        end
        p.Name = name
        p.Size = UDim2.new(1, 0, 1, 0)
        p.Position = UDim2.new(0, 0, 0, 0)
        p.BackgroundTransparency = 1
        p.BorderSizePixel = 0
        p.Visible = false
        p.Parent = content

        if scrolling then
            local lay = Instance.new("UIListLayout", p)
            lay.Padding = UDim.new(0, 6)
            lay.SortOrder = Enum.SortOrder.LayoutOrder
            local pad = Instance.new("UIPadding", p)
            pad.PaddingTop    = UDim.new(0, PAD)
            pad.PaddingLeft   = UDim.new(0, PAD)
            pad.PaddingRight  = UDim.new(0, PAD)
            pad.PaddingBottom = UDim.new(0, PAD)
        end
        PAGES[name] = p
        return p
    end

    --============================================================
    -- NAV ITEMS
    --============================================================
    local function selectPage(name)
        for n, p in pairs(PAGES) do p.Visible = (n == name) end
        for n, e in pairs(NAV) do e.setActive(n == name) end
    end

    local function mkNavItem(glyph, label, name, order)
        local item = Instance.new("TextButton")
        item.Size = UDim2.new(1, 0, 0, 38)
        item.BackgroundColor3 = CLR.navActive
        item.BackgroundTransparency = 1
        item.BorderSizePixel = 0
        item.Text = ""
        item.LayoutOrder = order
        item.AutoButtonColor = false
        item.Parent = navHolder
        Instance.new("UICorner", item).CornerRadius = UDim.new(0, 8)

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(0, 3, 0, 18)
        bar.Position = UDim2.new(0, 0, 0.5, -9)
        bar.BackgroundColor3 = CLR.accent
        bar.BackgroundTransparency = 1
        bar.BorderSizePixel = 0
        bar.Parent = item
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

        local ico = Instance.new("TextLabel")
        ico.Size = UDim2.new(0, 24, 0, 24)
        ico.Position = UDim2.new(0, 14, 0.5, -12)
        ico.BackgroundTransparency = 1
        ico.Text = glyph
        ico.TextColor3 = CLR.textDim
        ico.Font = FONT_B
        ico.TextSize = 14
        ico.Parent = item

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -48, 1, 0)
        lbl.Position = UDim2.new(0, 44, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = CLR.textDim
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = FONT_B
        lbl.TextSize = 12
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

    mkNavItem("◈", "Dashboard", "Dashboard", 1)
    mkNavItem("◆", "Combat",    "Combat",    2)
    mkNavItem("✦", "Quests",    "Quests",    3)
    mkNavItem("◎", "Config",    "Config",    4)
    mkNavItem("▤", "Files",     "Files",     5)
    mkNavItem("≡", "Logs",      "Logs",      6)

    --============================================================
    -- PAGE: DASHBOARD
    --============================================================
    local pDash = mkPage("Dashboard")

    -- stat grid
    local grid = Instance.new("Frame")
    grid.Size = UDim2.new(1, 0, 0, 136)
    grid.BackgroundTransparency = 1
    grid.LayoutOrder = nextOrder(pDash)
    grid.Parent = pDash
    local gl = Instance.new("UIGridLayout", grid)
    gl.CellSize = UDim2.new(0.5, -4, 0, 60)
    gl.CellPadding = UDim2.new(0, 8, 0, 8)
    gl.SortOrder = Enum.SortOrder.LayoutOrder

    local function mkStat(parent, label, order)
        local card = Instance.new("Frame")
        card.Size = UDim2.new(0, 100, 0, 60)
        card.BackgroundColor3 = CLR.row
        card.BorderSizePixel = 0
        card.LayoutOrder = order
        card.Parent = parent
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -24, 0, 12)
        l.Position = UDim2.new(0, 14, 0, 10)
        l.BackgroundTransparency = 1
        l.Text = string.upper(label)
        l.TextColor3 = CLR.textMuted
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Font = FONT_B
        l.TextSize = 9
        l.Parent = card

        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(1, -24, 0, 24)
        v.Position = UDim2.new(0, 14, 0, 26)
        v.BackgroundTransparency = 1
        v.Text = "—"
        v.TextColor3 = CLR.text
        v.TextXAlignment = Enum.TextXAlignment.Left
        v.Font = FONT_B
        v.TextSize = 18
        v.TextTruncate = Enum.TextTruncate.AtEnd
        v.Parent = card
        return v
    end

    local svState   = mkStat(grid, "State",   1)
    local svTarget  = mkStat(grid, "Target",  2)
    local svHp      = mkStat(grid, "HP",      3)
    local svKills   = mkStat(grid, "Kills",   4)

    mkSection(pDash, "Control")
    mkButtonRow(pDash, "▶", "Start Combat",  "Enable auto-combat and target acquisition", function()
        St.cbt = true; print("[Dingus] combat on")
    end)
    mkButtonRow(pDash, "■", "Stop Combat",   "Halt combat loop and release fly", function()
        St.cbt = false
        if Ctx.Fly and Ctx.Fly.stop then Ctx.Fly.stop() end
        print("[Dingus] combat off")
    end, true)
    mkButtonRow(pDash, "◎", "Scan for Bosses", "Force a boss scan; results in F9", function()
        St.lScn = 0
        local l = Ctx.Detect.scanBosses()
        print("[Dingus] found " .. #l .. " bosses")
    end)
    mkButtonRow(pDash, "▲", "Force Move To Target", "Teleport above current target", function()
        if Ctx.Atk and Ctx.Atk.forceMove then Ctx.Atk.forceMove() end
    end)
    mkButtonRow(pDash, "↻", "Reset Movers",  "Strip BodyMovers from HRP", function()
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
    -- PAGE: COMBAT
    --============================================================
    local pCombat = mkPage("Combat")

    mkSection(pCombat, "Automation")
    mkToggleRow(pCombat, "✦", "Auto Skill Rotation", "Cycles Z X C V B in rotation order", "skl")
    mkToggleRow(pCombat, "◆", "Auto Equip Weapon",   "Swaps to the first weapon in inventory", "eqp")
    mkToggleRow(pCombat, "◀", "Auto Retreat",        "Dash away when HP drops below threshold", "rtr")
    mkToggleRow(pCombat, "◎", "Stun Punish",         "Attack extra fast during stun windows", "stunPun")
    mkToggleRow(pCombat, "◇", "Guard Spoof",         "Client-side HP / block reinforcement", "gsp")

    mkSection(pCombat, "Tuning")
    mkSliderRow(pCombat, "◈", "Attack Range", 6, 20,
        function() return Cfg.AtkRange end,
        function(v) Cfg.AtkRange = v end, "%.1f")
    mkSliderRow(pCombat, "◆", "Attack Interval", 0.30, 0.90,
        function() return St.aiI or Cfg.AtkInterval end,
        function(v) St.aiI = v end, "%.2f")
    mkSliderRow(pCombat, "▶", "Run Speed", 16, 48,
        function() return Cfg.RunSpeed end,
        function(v) Cfg.RunSpeed = v end, "%.0f")
    mkSliderRow(pCombat, "◀", "Retreat HP %", 10, 90,
        function() return Cfg.RetreatHP * 100 end,
        function(v) Cfg.RetreatHP = v / 100 end, "%.0f")

    local combatInfo = mkInfo(pCombat, 108)

    --============================================================
    -- PAGE: QUESTS
    --============================================================
    local pQuest = mkPage("Quests")

    mkSection(pQuest, "Crow")
    mkToggleRow(pQuest, "✦", "Auto Crow Quests", "Periodically accept available crow quests", "crw")
    mkButtonRow(pQuest, "◆", "Equip Crow",   "Find and equip the crow tool", function()
        local t = Ctx.Scan.findCrowTool()
        local h = U.hum()
        if t and h and t:IsA("Tool") then
            pcall(function() h:EquipTool(t) end)
            print("[Dingus] crow equipped")
        end
    end)
    mkButtonRow(pQuest, "◈", "Summon Crow",  "Call the crow with M1", function() U.m1() end)
    mkButtonRow(pQuest, "◎", "Accept Quest", "Activate the quest menu button", function()
        local m = Ctx.Scan.findCrowMenu()
        if m then
            pcall(function() m:Activate() end)
            print("[Dingus] quest accepted")
        end
    end)

    mkSection(pQuest, "Quest Cycle")
    mkButtonRow(pQuest, "↻", "Run Quest Cycle", "Force a quest discovery pass", function()
        if Ctx.Quest and Ctx.Quest.doCycle then Ctx.Quest.doCycle() end
    end)

    local questInfo = mkInfo(pQuest, 96)

    --============================================================
    -- PAGE: CONFIG
    --============================================================
    local pConfig = mkPage("Config")

    mkSection(pConfig, "Active Slot")
    mkInputRow(pConfig, "▤", "Slot Name", ConfigMgr.currentSlot, function(text)
        ConfigMgr.currentSlot = text
        print("[Dingus][Config] slot = " .. text)
    end)

    mkSection(pConfig, "Actions")
    mkButtonRow(pConfig, "▶", "Save to Slot",   "Persist current settings", function()
        local ok, err = ConfigMgr.saveTo()
        print("[Dingus][Config] save " .. (ok and "ok" or ("fail: " .. tostring(err))))
    end)
    mkButtonRow(pConfig, "◀", "Load from Slot", "Read settings from disk", function()
        local ok, err = ConfigMgr.loadFrom()
        print("[Dingus][Config] load " .. (ok and tostring(err) or ("fail: " .. tostring(err))))
    end)
    mkButtonRow(pConfig, "✕", "Delete Current Slot", "Remove the slot file", function()
        local ok = ConfigMgr.deleteSlot(ConfigMgr.currentSlot)
        print("[Dingus][Config] delete " .. tostring(ok))
    end, true)
    mkButtonRow(pConfig, "↻", "Reset to Defaults", "Restore factory settings", function()
        if Ctx.Cfg and Ctx.Cfg.reset then Ctx.Cfg.reset() end
        print("[Dingus][Config] reset")
    end, true)
    mkButtonRow(pConfig, "≡", "Print Values to F9", "Dump full config to console", function()
        if Ctx.Cfg and Ctx.Cfg.pretty then print(Ctx.Cfg.pretty()) end
    end)

    local configInfo = mkInfo(pConfig, 96)
    local slotsInfo  = mkInfo(pConfig, 96)

    --============================================================
    -- PAGE: FILES
    --============================================================
    local pFiles = mkPage("Files")

    mkSection(pFiles, "Actions")
    mkButtonRow(pFiles, "↻", "Refresh File List", "Re-scan the Dingus folder", function()
        FileMgr.refresh()
        print("[Dingus][Files] refreshed: " .. #FileMgr.files .. " files")
    end)
    mkButtonRow(pFiles, "✕", "Delete boot log", "Remove dingus_boot_log.txt", function()
        local ok = FileMgr.delete("dingus_boot_log.txt")
        print("[Dingus][Files] delete log: " .. tostring(ok))
    end, true)

    mkSection(pFiles, "Discovered")
    local filesInfo = mkInfo(pFiles, 240)

    --============================================================
    -- PAGE: LOGS  (non-scrolling outer)
    --============================================================
    local pLogs = mkPage("Logs", false)

    local logPad = Instance.new("UIPadding", pLogs)
    logPad.PaddingTop    = UDim.new(0, PAD)
    logPad.PaddingLeft   = UDim.new(0, PAD)
    logPad.PaddingRight  = UDim.new(0, PAD)
    logPad.PaddingBottom = UDim.new(0, PAD)

    local filterRow = Instance.new("Frame")
    filterRow.Size = UDim2.new(1, 0, 0, 30)
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
        b.TextSize = 11
        b.AutoButtonColor = false
        b.Parent = filterRow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
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
    mkFilterBtn("All",    "all",    0,   50)
    mkFilterBtn("Dingus", "dingus", 54,  68)
    mkFilterBtn("Errors", "errors", 126, 62)

    local function mkLogBtn(label, x, w, cb, tint)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 1, 0)
        b.Position = UDim2.new(0, x, 0, 0)
        b.BackgroundColor3 = tint or CLR.bgPanel
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = CLR.text
        b.Font = FONT_B
        b.TextSize = 11
        b.AutoButtonColor = false
        b.Parent = filterRow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        b.MouseButton1Click:Connect(cb)
    end
    mkLogBtn("Clear", 204, 56, function()
        Log.clear(); print("[Dingus][Log] cleared")
    end, CLR.red)
    mkLogBtn("Pause", 264, 56, function()
        Log.paused = not Log.paused
        print("[Dingus][Log] paused = " .. tostring(Log.paused))
    end, CLR.orange)
    mkLogBtn("Save",  324, 56, function()
        local ok = Log.export("dingus_combat_log.txt")
        print("[Dingus][Log] exported: " .. tostring(ok))
    end)
    mkLogBtn("Copy",  384, 56, function()
        local lines = {}
        for i = 1, #Log.buffer do
            local e = Log.buffer[i]
            lines[#lines+1] = string.format("[%s] %s", e.time, e.text)
        end
        if setclipboard then pcall(setclipboard, table.concat(lines, "\n")) end
        print("[Dingus][Log] copied " .. #lines .. " lines")
    end, CLR.green)

    local logFrame = Instance.new("Frame")
    logFrame.Size = UDim2.new(1, 0, 1, -42)
    logFrame.Position = UDim2.new(0, 0, 0, 42)
    logFrame.BackgroundColor3 = CLR.bgPanel
    logFrame.BorderSizePixel = 0
    logFrame.Parent = pLogs
    Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0, 10)

    local logScroll = Instance.new("ScrollingFrame")
    logScroll.Size = UDim2.new(1, -12, 1, -12)
    logScroll.Position = UDim2.new(0, 6, 0, 6)
    logScroll.BackgroundTransparency = 1
    logScroll.BorderSizePixel = 0
    logScroll.ScrollBarThickness = 5
    logScroll.ScrollBarImageColor3 = CLR.accentDim
    logScroll.ScrollBarImageTransparency = 0.3
    logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    logScroll.Parent = logFrame
    local logLay = Instance.new("UIListLayout", logScroll)
    logLay.Padding = UDim.new(0, 2)
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
            row.Size = UDim2.new(1, -8, 0, 14)
            row.BackgroundTransparency = 1
            row.Text = "  [" .. e.time .. "] " .. e.text
            row.TextColor3 = colorFor(e.type)
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.Font = FONT_C
            row.TextSize = 10
            row.TextTruncate = Enum.TextTruncate.AtEnd
            row.LayoutOrder = i
            row.Parent = logScroll
            table.insert(logRows, row)
        end
        logScroll.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y)
    end

    --============================================================
    -- DEFAULT PAGE
    --============================================================
    selectPage("Dashboard")

    --============================================================
    -- MINIMIZE / RESTORE
    --============================================================
    local PILL_W, PILL_H = 160, 36
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
    pDot.Position = UDim2.new(0, 14, 0.5, -4)
    pDot.BackgroundColor3 = CLR.accent
    pDot.BorderSizePixel = 0
    pDot.Parent = pill
    Instance.new("UICorner", pDot).CornerRadius = UDim.new(1, 0)

    local pLbl = Instance.new("TextLabel")
    pLbl.Size = UDim2.new(1, -32, 1, 0)
    pLbl.Position = UDim2.new(0, 28, 0, 0)
    pLbl.BackgroundTransparency = 1
    pLbl.Text = "Dingus-Slayer"
    pLbl.TextColor3 = CLR.text
    pLbl.TextXAlignment = Enum.TextXAlignment.Left
    pLbl.Font = FONT_B
    pLbl.TextSize = 12
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

                -- Dashboard stats
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
                local ci = string.format(
                    "  state: %s  ·  hits: %d/%d (%d%%)\n" ..
                    "  kills: %d  ·  retreats: %d  ·  skills fired: %d\n" ..
                    "  fly: %s  ·  threats: %d  ·  zone: %d\n" ..
                    "  hp: %s  ·  atk interval: %.2f",
                    St.cbtS or "—", St.aHi or 0, St.aAt or 0, hitRate,
                    St.bKll or 0, St.rtrC or 0, St.skC or 0,
                    tostring(St.FlyActive), St.zn or 0, St.imm or 0,
                    hp, St.aiI or 0)
                if cache.combatInfo ~= ci then cache.combatInfo = ci; combatInfo.Text = ci end

                -- Quest info
                local qi = string.format(
                    "  crow tool: %s\n" ..
                    "  perched: %s  ·  accepted: %d\n" ..
                    "  player level: %d  ·  hunts: %d\n" ..
                    "  quest target: %s",
                    St.crT and St.crT.Name or "not found",
                    tostring(St.cPrch), St.cQs or 0,
                    St.playerLevel or 0, St.huntCount or 0,
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
                    Ctx.Cfg.slotFile(ConfigMgr.currentSlot),
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

                -- Files info
                FileMgr.refresh()
                local fileLines = { string.format("  files: %d", #FileMgr.files) }
                for i = 1, math.min(#FileMgr.files, 15) do
                    local f = FileMgr.files[i]
                    fileLines[#fileLines+1] = string.format("    · %s (%d bytes)", f.name, f.size or 0)
                end
                local fi = table.concat(fileLines, "\n")
                if cache.filesInfo ~= fi then cache.filesInfo = fi; filesInfo.Text = fi end

                -- Header status
                local bar = string.format("%s · fps %.0f · log %d",
                    St.cbt and "combat" or "idle", St.fps or 60, #Log.buffer)
                if cache.live ~= bar then cache.live = bar; liveLbl.Text = bar end
                if cache.fDot ~= (St.cbt and "g" or "m") then
                    cache.fDot = St.cbt and "g" or "m"
                    fDot.BackgroundColor3 = St.cbt and CLR.green or CLR.textMuted
                    liveDot.BackgroundColor3 = St.cbt and CLR.green or CLR.textMuted
                end

                -- Log rebuild
                if Log.pendingUpdate then
                    Log.pendingUpdate = false
                    rebuildLog()
                end
            end
            task.wait(0.3)
        end
    end)

    --============================================================
    -- HOTKEY (in-window; main.lua has its own global hook)
    --============================================================
    UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            if minimized then restore() else minimize() end
        end
    end)

    --============================================================
    -- CLOSE (restore print/warn)
    --============================================================
    closeBtn.MouseButton1Click:Connect(function()
        _G.print = _origPrint
        _G.warn  = _origWarn
        gui:Destroy()
    end)

    --============================================================
    -- EXPOSE
    --============================================================
    G.gui       = gui
    G.win       = win
    G.minimize  = minimize
    G.restore   = restore
    G.Log       = Log
    G.FileMgr   = FileMgr
    G.ConfigMgr = ConfigMgr
    G.PAGES     = PAGES

    print("[Dingus][gui] initialized · v28 sidebar layout")
end

return G
