--[[
    Dingus-Slayer · gui.lua v34
    9 tabs. Chests tab wired to Ctx.Chest.
]]--

local G = {}

function G.init(Ctx)
    local U, F, S, L = Ctx.Util, Ctx.Cfg, Ctx.St, Ctx.Lists
    local TW = game:GetService("TweenService")
    local UIS = game:GetService("UserInputService")
    local LS = game:GetService("LogService")

    F.GuiConcealed = F.GuiConcealed ~= false
    F.GuiPanicHide = F.GuiPanicHide ~= false

    local HAS = {
        writefile = type(writefile) == "function",
        readfile  = type(readfile) == "function",
        delfile   = type(delfile) == "function",
        isfile    = type(isfile) == "function",
        listfiles = type(listfiles) == "function",
        makefolder = type(makefolder) == "function",
        gethui    = type(gethui) == "function",
    }

    local function resolveParent()
        if F.GuiConcealed then
            if HAS.gethui then
                local ok, h = pcall(gethui); if ok and h then return h, "gethui" end
            end
            local ok, cg = pcall(function() return game:GetService("CoreGui") end)
            if ok and cg then return cg, "CoreGui" end
        end
        return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"), "PlayerGui"
    end
    local parent, parentKind = resolveParent()
    if parentKind == "PlayerGui" then
        warn("[Dingus][gui] PlayerGui fallback")
    end

    local guiName = "_c" .. string.format("%06x", math.random(0, 0xFFFFFF))
    local old = parent:FindFirstChild("DingusUI")
    if old then pcall(function() old:Destroy() end) end

    local C = {
        bg=Color3.fromRGB(12,12,16), bgH=Color3.fromRGB(14,14,20),
        bgS=Color3.fromRGB(10,10,14), bgP=Color3.fromRGB(16,16,22),
        row=Color3.fromRGB(24,24,32), rowH=Color3.fromRGB(32,32,42),
        iconBg=Color3.fromRGB(44,24,24), iconBgD=Color3.fromRGB(28,24,28),
        navA=Color3.fromRGB(40,24,24), navH=Color3.fromRGB(22,22,30),
        trackOff=Color3.fromRGB(52,52,66), border=Color3.fromRGB(40,32,34),
        accent=Color3.fromRGB(220,90,70), accentD=Color3.fromRGB(150,60,50),
        green=Color3.fromRGB(80,200,120), red=Color3.fromRGB(220,70,80),
        blue=Color3.fromRGB(70,130,200), orange=Color3.fromRGB(210,140,80),
        text=Color3.fromRGB(232,232,240), textD=Color3.fromRGB(160,165,180),
        textM=Color3.fromRGB(110,115,135),
        logI=Color3.fromRGB(200,200,210), logW=Color3.fromRGB(240,200,100),
        logE=Color3.fromRGB(240,120,120), logD=Color3.fromRGB(140,220,180),
    }
    local FB, FR, FC = Enum.Font.GothamBold, Enum.Font.Gotham, Enum.Font.Code

    --============================================================
    -- LOG
    --============================================================
    local Log = { buffer={}, max=300, filter="all", paused=false, dirty=true }
    function Log.add(text, mt)
        if Log.paused then return end
        if Log.filter == "dingus" and not text:find("Dingus", 1, true) then return end
        if Log.filter == "errors" and mt ~= Enum.MessageType.MessageError then return end
        table.insert(Log.buffer, { text=text, type=mt, time=os.date("%H:%M:%S") })
        if #Log.buffer > Log.max then table.remove(Log.buffer, 1) end
        Log.dirty = true
    end
    function Log.clear() Log.buffer={}; Log.dirty=true end
    function Log.export(fn)
        if not HAS.writefile then return false end
        local l = {}
        for i=1,#Log.buffer do
            local e = Log.buffer[i]
            l[#l+1] = string.format("[%s] %s", e.time, e.text)
        end
        return pcall(writefile, fn, table.concat(l, "\n"))
    end
    pcall(function()
        LS.MessageOut:Connect(function(m,t) pcall(Log.add,m,t) end)
    end)

    local _print = print
    local _warn = warn
    do
        local function coerce(a)
            if type(a)=="string" then return a end
            local ok,s = pcall(tostring,a); return ok and s or "[?]"
        end
        _G.print = function(...)
            local a = {...}; local o = {}
            for i=1,#a do o[i] = coerce(a[i]) end
            pcall(Log.add, table.concat(o," "), Enum.MessageType.MessageOutput)
            return _print(...)
        end
        _G.warn = function(...)
            local a = {...}; local o = {}
            for i=1,#a do o[i] = coerce(a[i]) end
            pcall(Log.add, table.concat(o," "), Enum.MessageType.MessageWarning)
            return _warn(...)
        end
    end
    local function restore() _G.print = _print; _G.warn = _warn end

    --============================================================
    -- ROOT
    --============================================================
    local gui = Instance.new("ScreenGui")
    gui.Name = guiName
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 2^30
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    local WW, WH, HH, SW, PAD, RH, RG, SCW = 940, 680, 48, 200, 14, 60, 8, 10

    local win = Instance.new("Frame")
    win.Size = UDim2.new(0, WW, 0, WH)
    win.Position = UDim2.new(0.5, -WW/2, 0.5, -WH/2)
    win.BackgroundColor3 = C.bg
    win.BorderSizePixel = 0
    win.Active = true
    win.Draggable = true
    win.ClipsDescendants = true
    win.Parent = gui
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 14)
    local ws = Instance.new("UIStroke", win)
    ws.Color = C.border; ws.Thickness = 1; ws.Transparency = 0.2

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, HH)
    header.BackgroundColor3 = C.bgH
    header.BorderSizePixel = 0
    header.Parent = win
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)
    local hFix = Instance.new("Frame")
    hFix.Size = UDim2.new(1, 0, 0, 14)
    hFix.Position = UDim2.new(0, 0, 1, -14)
    hFix.BackgroundColor3 = C.bgH; hFix.BorderSizePixel = 0; hFix.Parent = header

    local chip = Instance.new("Frame")
    chip.Size = UDim2.new(0, 30, 0, 30)
    chip.Position = UDim2.new(0, 16, 0.5, -15)
    chip.BackgroundColor3 = C.accent
    chip.BorderSizePixel = 0
    chip.Parent = header
    Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 8)
    local chipL = Instance.new("TextLabel")
    chipL.Size = UDim2.new(1,0,1,0); chipL.BackgroundTransparency=1
    chipL.Text = "D"; chipL.TextColor3 = Color3.fromRGB(255,245,240)
    chipL.Font = FB; chipL.TextSize = 17; chipL.Parent = chip

    local titleL = Instance.new("TextLabel")
    titleL.Size = UDim2.new(0,280,1,0); titleL.Position = UDim2.new(0,58,0,0)
    titleL.BackgroundTransparency = 1; titleL.Text = "Dingus-Slayer"
    titleL.TextColor3 = C.text; titleL.TextXAlignment = Enum.TextXAlignment.Left
    titleL.Font = FB; titleL.TextSize = 15; titleL.Parent = header

    local liveDot = Instance.new("Frame")
    liveDot.Size = UDim2.new(0,6,0,6); liveDot.Position = UDim2.new(0,200,0.5,-3)
    liveDot.BackgroundColor3 = C.textM; liveDot.BorderSizePixel = 0; liveDot.Parent = header
    Instance.new("UICorner", liveDot).CornerRadius = UDim.new(1,0)

    local liveL = Instance.new("TextLabel")
    liveL.Size = UDim2.new(0,400,1,0); liveL.Position = UDim2.new(0,214,0,0)
    liveL.BackgroundTransparency = 1; liveL.Text = "ready"
    liveL.TextColor3 = C.textM; liveL.TextXAlignment = Enum.TextXAlignment.Left
    liveL.Font = FB; liveL.TextSize = 11; liveL.Parent = header

    local function mkCtrl(g, x, base, hov)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0,30,0,30); b.Position = UDim2.new(1,x,0.5,-15)
        b.BackgroundColor3 = base; b.BackgroundTransparency = 1
        b.BorderSizePixel = 0; b.Text = g; b.TextColor3 = C.textD
        b.Font = FB; b.TextSize = 16; b.AutoButtonColor = false; b.Parent = header
        Instance.new("UICorner", b).CornerRadius = UDim.new(1,0)
        b.MouseEnter:Connect(function()
            TW:Create(b, TweenInfo.new(0.12), {
                BackgroundTransparency=0, BackgroundColor3=hov, TextColor3=C.text
            }):Play()
        end)
        b.MouseLeave:Connect(function()
            TW:Create(b, TweenInfo.new(0.12), {
                BackgroundTransparency=1, TextColor3=C.textD
            }):Play()
        end)
        return b
    end
    local closeB = mkCtrl("✕", -44, C.red, C.red)
    local minB = mkCtrl("–", -78, Color3.fromRGB(60,60,75), Color3.fromRGB(70,70,90))

    --============================================================
    -- SIDEBAR
    --============================================================
    local side = Instance.new("Frame")
    side.Size = UDim2.new(0, SW, 1, -HH)
    side.Position = UDim2.new(0,0,0,HH)
    side.BackgroundColor3 = C.bgS
    side.BorderSizePixel = 0
    side.Parent = win

    local sideLbl = Instance.new("TextLabel")
    sideLbl.Size = UDim2.new(1,-32,0,18); sideLbl.Position = UDim2.new(0,16,0,16)
    sideLbl.BackgroundTransparency = 1; sideLbl.Text = "MENU"
    sideLbl.TextColor3 = C.textM; sideLbl.TextXAlignment = Enum.TextXAlignment.Left
    sideLbl.Font = FB; sideLbl.TextSize = 10; sideLbl.Parent = side

    local navScroll = Instance.new("ScrollingFrame")
    navScroll.Size = UDim2.new(1,-16,1,-110)
    navScroll.Position = UDim2.new(0,8,0,42)
    navScroll.BackgroundTransparency = 1; navScroll.BorderSizePixel = 0
    navScroll.CanvasSize = UDim2.new(0,0,0,0)
    navScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    navScroll.ScrollBarThickness = 4
    navScroll.ScrollBarImageColor3 = C.accentD
    navScroll.ScrollBarImageTransparency = 0.5
    navScroll.ScrollingEnabled = true
    navScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    navScroll.Parent = side
    local navLay = Instance.new("UIListLayout", navScroll)
    navLay.Padding = UDim.new(0,4); navLay.SortOrder = Enum.SortOrder.LayoutOrder

    local footer = Instance.new("Frame")
    footer.Size = UDim2.new(1,-16,0,38); footer.Position = UDim2.new(0,8,1,-50)
    footer.BackgroundColor3 = C.bgP; footer.BorderSizePixel = 0; footer.Parent = side
    Instance.new("UICorner", footer).CornerRadius = UDim.new(0,8)
    local fDot = Instance.new("Frame")
    fDot.Size = UDim2.new(0,6,0,6); fDot.Position = UDim2.new(0,14,0.5,-3)
    fDot.BackgroundColor3 = C.green; fDot.BorderSizePixel = 0; fDot.Parent = footer
    Instance.new("UICorner", fDot).CornerRadius = UDim.new(1,0)
    local fLbl = Instance.new("TextLabel")
    fLbl.Size = UDim2.new(1,-32,1,0); fLbl.Position = UDim2.new(0,28,0,0)
    fLbl.BackgroundTransparency = 1; fLbl.Text = "v34 · idle"
    fLbl.TextColor3 = C.textM; fLbl.TextXAlignment = Enum.TextXAlignment.Left
    fLbl.Font = FB; fLbl.TextSize = 10; fLbl.Parent = footer

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1,-SW,1,-HH); content.Position = UDim2.new(0,SW,0,HH)
    content.BackgroundColor3 = C.bg; content.BorderSizePixel = 0
    content.ClipsDescendants = true; content.Parent = win

    local counters = {}
    local function nextO(p) counters[p] = (counters[p] or 0) + 1; return counters[p] end

    local function mkSwitch(par, init, cb)
        local t = Instance.new("TextButton")
        t.Size = UDim2.new(0,42,0,22)
        t.BackgroundColor3 = init and C.accent or C.trackOff
        t.BorderSizePixel = 0; t.Text = ""; t.AutoButtonColor = false; t.Parent = par
        Instance.new("UICorner", t).CornerRadius = UDim.new(1,0)
        local k = Instance.new("Frame")
        k.Size = UDim2.new(0,18,0,18)
        k.Position = init and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)
        k.BackgroundColor3 = Color3.fromRGB(245,245,250)
        k.BorderSizePixel = 0; k.Parent = t
        Instance.new("UICorner", k).CornerRadius = UDim.new(1,0)
        local st = init
        local function set(v)
            st = v
            TW:Create(t, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
                BackgroundColor3 = st and C.accent or C.trackOff
            }):Play()
            TW:Create(k, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
                Position = st and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)
            }):Play()
            if cb then pcall(cb, st) end
        end
        t.MouseButton1Click:Connect(function() set(not st) end)
        return t, set
    end

    local function mkIcon(par, g, dim)
        local b = Instance.new("Frame")
        b.Size = UDim2.new(0,36,0,36); b.Position = UDim2.new(0,16,0,12)
        b.BackgroundColor3 = dim and C.iconBgD or C.iconBg
        b.BorderSizePixel = 0; b.Parent = par
        Instance.new("UICorner", b).CornerRadius = UDim.new(0,9)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1,0,1,0); l.BackgroundTransparency=1
        l.Text = g; l.TextColor3 = dim and C.textD or C.accent
        l.Font = FB; l.TextSize = 17; l.Parent = b
        return b
    end

    local function mkRow(p, h)
        local r = Instance.new("Frame")
        r.Size = UDim2.new(1, -SCW - 4, 0, h)
        r.BackgroundColor3 = C.row; r.BorderSizePixel = 0
        r.LayoutOrder = nextO(p); r.Active = true; r.Parent = p
        Instance.new("UICorner", r).CornerRadius = UDim.new(0,11)
        r.MouseEnter:Connect(function()
            TW:Create(r, TweenInfo.new(0.12), { BackgroundColor3 = C.rowH }):Play()
        end)
        r.MouseLeave:Connect(function()
            TW:Create(r, TweenInfo.new(0.12), { BackgroundColor3 = C.row }):Play()
        end)
        return r
    end

    local function mkTD(r, title, desc, ty)
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1,-100,0,18); t.Position = UDim2.new(0,64,0,ty or 12)
        t.BackgroundTransparency = 1; t.Text = title; t.TextColor3 = C.text
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Font = FB; t.TextSize = 14; t.Parent = r
        if desc and desc ~= "" then
            local d = Instance.new("TextLabel")
            d.Size = UDim2.new(1,-100,0,15); d.Position = UDim2.new(0,64,0,(ty or 12)+20)
            d.BackgroundTransparency = 1; d.Text = desc; d.TextColor3 = C.textM
            d.TextXAlignment = Enum.TextXAlignment.Left
            d.Font = FR; d.TextSize = 12; d.TextTruncate = Enum.TextTruncate.AtEnd
            d.Parent = r
        end
    end

    local function mkSection(p, text)
        local h = Instance.new("TextLabel")
        h.Size = UDim2.new(1,-SCW-4,0,24); h.BackgroundTransparency = 1
        h.Text = string.upper(text); h.TextColor3 = C.textM
        h.TextXAlignment = Enum.TextXAlignment.Left
        h.TextYAlignment = Enum.TextYAlignment.Bottom
        h.Font = FB; h.TextSize = 10; h.LayoutOrder = nextO(p); h.Parent = p
        local pad = Instance.new("UIPadding", h)
        pad.PaddingLeft = UDim.new(0,6); pad.PaddingBottom = UDim.new(0,4)
        return h
    end

    local function mkToggle(p, g, title, desc, key, cb)
        local r = mkRow(p, RH); mkIcon(r, g); mkTD(r, title, desc)
        local sw = mkSwitch(r, S[key], function(v)
            S[key] = v; if cb then pcall(cb, v) end
        end)
        sw.Position = UDim2.new(1,-58,0.5,-11); sw.ZIndex = 3
        return r
    end

    local function mkCfgToggle(p, g, title, desc, key, cb)
        local r = mkRow(p, RH); mkIcon(r, g); mkTD(r, title, desc)
        local init = F[key] ~= false
        local sw = mkSwitch(r, init, function(v)
            F[key] = v; if cb then pcall(cb, v) end
        end)
        sw.Position = UDim2.new(1,-58,0.5,-11); sw.ZIndex = 3
        return r
    end

    local function mkSlider(p, g, title, mn, mx, getter, setter, fmt)
        fmt = fmt or "%.1f"
        local r = mkRow(p, 70); mkIcon(r, g)
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1,-180,0,18); t.Position = UDim2.new(0,64,0,12)
        t.BackgroundTransparency = 1; t.Text = title; t.TextColor3 = C.text
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Font = FB; t.TextSize = 14; t.Parent = r
        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(0,80,0,18); v.Position = UDim2.new(1,-SCW-6,0,12)
        v.AnchorPoint = Vector2.new(1,0); v.BackgroundTransparency = 1
        v.Text = string.format(fmt, getter()); v.TextColor3 = C.accent
        v.TextXAlignment = Enum.TextXAlignment.Right
        v.Font = FB; v.TextSize = 13; v.Parent = r
        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(1,-80,0,6); bar.Position = UDim2.new(0,64,0,48)
        bar.BackgroundColor3 = C.trackOff; bar.BorderSizePixel = 0; bar.Parent = r
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1,0)
        local pct = math.clamp((getter()-mn)/(mx-mn), 0, 1)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(pct,0,1,0); fill.BackgroundColor3 = C.accent
        fill.BorderSizePixel = 0; fill.Parent = bar
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1,0)
        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0,14,0,14); knob.Position = UDim2.new(pct,-7,0.5,-7)
        knob.BackgroundColor3 = Color3.fromRGB(255,245,240)
        knob.BorderSizePixel = 0; knob.ZIndex = 2; knob.Parent = bar
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1,0)
        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1,-80,0,24); hit.Position = UDim2.new(0,64,0,39)
        hit.BackgroundTransparency = 1; hit.Text = ""; hit.Parent = r
        local drag = false
        hit.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = true end
        end)
        hit.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
        end)
        UIS.InputChanged:Connect(function(i)
            if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
                local mx2 = UIS:GetMouseLocation().X
                local bx, bw = bar.AbsolutePosition.X, bar.AbsoluteSize.X
                if bw > 0 then
                    local pp = math.clamp((mx2-bx)/bw, 0, 1)
                    local val = mn + (mx-mn) * pp
                    setter(val)
                    v.Text = string.format(fmt, val)
                    fill.Size = UDim2.new(pp,0,1,0)
                    knob.Position = UDim2.new(pp,-7,0.5,-7)
                end
            end
        end)
        return r
    end

    local function mkButton(p, g, title, desc, cb, tint)
        local r = mkRow(p, RH); mkIcon(r, g, tint); mkTD(r, title, desc, 14)
        local chev = Instance.new("TextLabel")
        chev.Size = UDim2.new(0,20,0,24); chev.Position = UDim2.new(1,-SCW-24,0.5,-12)
        chev.BackgroundTransparency = 1; chev.Text = "›"; chev.TextColor3 = C.textM
        chev.Font = FB; chev.TextSize = 20; chev.Parent = r
        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1,0,1,0); hit.BackgroundTransparency = 1
        hit.Text = ""; hit.Parent = r
        hit.MouseButton1Click:Connect(function()
            local ok, err = pcall(cb)
            if not ok then print("[Dingus][btn] "..title..": "..tostring(err)) end
        end)
        return r
    end

    local function mkInfo(p, h)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1,-SCW-4,0,h or 100)
        l.BackgroundColor3 = C.row; l.BorderSizePixel = 0
        l.Text = "  —"; l.TextColor3 = C.textD
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Top
        l.Font = FC; l.TextSize = 12; l.TextWrapped = true
        l.LayoutOrder = nextO(p); l.Parent = p
        Instance.new("UICorner", l).CornerRadius = UDim.new(0,11)
        local pad = Instance.new("UIPadding", l)
        pad.PaddingTop = UDim.new(0,12); pad.PaddingLeft = UDim.new(0,14)
        pad.PaddingRight = UDim.new(0,14)
        return l
    end

    --============================================================
    -- PAGES
    --============================================================
    local PAGES, NAV = {}, {}

    local function mkPage(name)
        local p = Instance.new("ScrollingFrame")
        p.Name = name; p.Size = UDim2.new(1,0,1,0)
        p.BackgroundTransparency = 1; p.BorderSizePixel = 0; p.Visible = false
        p.CanvasSize = UDim2.new(0,0,0,0)
        p.AutomaticCanvasSize = Enum.AutomaticSize.Y
        p.ScrollBarThickness = SCW
        p.ScrollBarImageColor3 = C.accent
        p.ScrollBarImageTransparency = 0.2
        p.ScrollingEnabled = true
        p.ScrollingDirection = Enum.ScrollingDirection.Y
        p.ElasticBehavior = Enum.ElasticBehavior.Never
        p.Parent = content
        local lay = Instance.new("UIListLayout", p)
        lay.Padding = UDim.new(0,RG); lay.SortOrder = Enum.SortOrder.LayoutOrder
        local pad = Instance.new("UIPadding", p)
        pad.PaddingTop = UDim.new(0,PAD); pad.PaddingLeft = UDim.new(0,PAD)
        pad.PaddingRight = UDim.new(0,6); pad.PaddingBottom = UDim.new(0,PAD+8)
        PAGES[name] = p; return p
    end

    local function selectPage(name)
        for n, p in pairs(PAGES) do p.Visible = (n == name) end
        for n, e in pairs(NAV) do e.setActive(n == name) end
    end

    local function mkNav(g, lbl, name, order)
        local it = Instance.new("TextButton")
        it.Size = UDim2.new(1,-6,0,40); it.BackgroundColor3 = C.navA
        it.BackgroundTransparency = 1; it.BorderSizePixel = 0; it.Text = ""
        it.LayoutOrder = order; it.AutoButtonColor = false; it.Parent = navScroll
        Instance.new("UICorner", it).CornerRadius = UDim.new(0,9)
        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(0,3,0,20); bar.Position = UDim2.new(0,0,0.5,-10)
        bar.BackgroundColor3 = C.accent; bar.BackgroundTransparency = 1
        bar.BorderSizePixel = 0; bar.Parent = it
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1,0)
        local ico = Instance.new("TextLabel")
        ico.Size = UDim2.new(0,24,0,24); ico.Position = UDim2.new(0,18,0.5,-12)
        ico.BackgroundTransparency = 1; ico.Text = g; ico.TextColor3 = C.textD
        ico.Font = FB; ico.TextSize = 15; ico.Parent = it
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1,-56,1,0); l.Position = UDim2.new(0,50,0,0)
        l.BackgroundTransparency = 1; l.Text = lbl; l.TextColor3 = C.textD
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Font = FB; l.TextSize = 13; l.Parent = it
        local active = false
        local function setActive(a)
            active = a
            TW:Create(it, TweenInfo.new(0.15), {
                BackgroundTransparency = a and 0 or 1,
                BackgroundColor3 = a and C.navA or C.navH,
            }):Play()
            TW:Create(ico, TweenInfo.new(0.15), {
                TextColor3 = a and C.accent or C.textD
            }):Play()
            TW:Create(l, TweenInfo.new(0.15), {
                TextColor3 = a and C.text or C.textD
            }):Play()
            TW:Create(bar, TweenInfo.new(0.15), {
                BackgroundTransparency = a and 0 or 1
            }):Play()
        end
        it.MouseEnter:Connect(function()
            if not active then
                TW:Create(it, TweenInfo.new(0.12), {
                    BackgroundTransparency = 0, BackgroundColor3 = C.navH
                }):Play()
            end
        end)
        it.MouseLeave:Connect(function()
            if not active then
                TW:Create(it, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
            end
        end)
        it.MouseButton1Click:Connect(function() selectPage(name) end)
        NAV[name] = { item = it, setActive = setActive }
        return it
    end

    mkNav("◈","Dashboard","Dashboard",1)
    mkNav("◆","Combat","Combat",2)
    mkNav("◎","Targets","Targets",3)
    mkNav("◰","Chests","Chests",4)
    mkNav("✦","Quests","Quests",5)
    mkNav("▤","Config","Config",6)
    mkNav("▥","Files","Files",7)
    mkNav("≡","Logs","Logs",8)
    mkNav("⚙","Settings","Settings",9)

    --============================================================
    -- DASHBOARD
    --============================================================
    local pDash = mkPage("Dashboard")
    local grid = Instance.new("Frame")
    grid.Size = UDim2.new(1,-SCW-4,0,148); grid.BackgroundTransparency = 1
    grid.LayoutOrder = nextO(pDash); grid.Parent = pDash
    local gl = Instance.new("UIGridLayout", grid)
    gl.CellSize = UDim2.new(0.5,-6,0,68); gl.CellPadding = UDim2.new(0,12,0,12)
    gl.SortOrder = Enum.SortOrder.LayoutOrder

    local function mkStat(par, lbl, order)
        local c = Instance.new("Frame")
        c.Size = UDim2.new(0,100,0,68); c.BackgroundColor3 = C.row
        c.BorderSizePixel = 0; c.LayoutOrder = order; c.Parent = par
        Instance.new("UICorner", c).CornerRadius = UDim.new(0,11)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1,-32,0,14); l.Position = UDim2.new(0,16,0,12)
        l.BackgroundTransparency = 1; l.Text = string.upper(lbl)
        l.TextColor3 = C.textM; l.TextXAlignment = Enum.TextXAlignment.Left
        l.Font = FB; l.TextSize = 10; l.Parent = c
        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(1,-32,0,26); v.Position = UDim2.new(0,16,0,30)
        v.BackgroundTransparency = 1; v.Text = "—"; v.TextColor3 = C.text
        v.TextXAlignment = Enum.TextXAlignment.Left
        v.Font = FB; v.TextSize = 20; v.TextTruncate = Enum.TextTruncate.AtEnd
        v.Parent = c
        return v
    end
    local svState = mkStat(grid, "State", 1)
    local svTgt = mkStat(grid, "Target", 2)
    local svHp = mkStat(grid, "HP", 3)
    local svKill = mkStat(grid, "Kills", 4)

    mkSection(pDash, "Control")
    mkButton(pDash, "▶", "Start Combat", "Enable auto-combat", function()
        S.cbt = true; print("[Dingus] combat on")
    end)
    mkButton(pDash, "■", "Stop Combat", "Halt combat", function()
        S.cbt = false; print("[Dingus] combat off")
    end, true)
    mkButton(pDash, "◎", "Scan Bosses", "Force scan", function()
        S.lScn = 0
        local l = Ctx.Detect.scanBosses(nil, true)
        print("[Dingus] found "..#l.." bosses")
    end)
    mkButton(pDash, "▲", "Force Move", "Teleport to target", function()
        if Ctx.Atk and Ctx.Atk.forceMove then Ctx.Atk.forceMove() end
    end)

    --============================================================
    -- COMBAT
    --============================================================
    local pCombat = mkPage("Combat")
    mkSection(pCombat, "Automation")
    mkToggle(pCombat, "✦", "Auto Skills", "Cycles slot order", "skl")
    mkToggle(pCombat, "◆", "Auto Equip", "Swaps to weapon", "eqp")
    mkToggle(pCombat, "◀", "Auto Retreat", "Dash when HP drops", "rtr")
    mkToggle(pCombat, "◎", "Stun Punish", "Attack during stun", "stunPun")
    mkToggle(pCombat, "◇", "Guard Spoof", "Client-side HP", "gsp")
    mkSection(pCombat, "Tuning")
    mkSlider(pCombat, "◈", "Attack Range", 6, 20,
        function() return F.AtkRange end, function(v) F.AtkRange = v end, "%.1f")
    mkSlider(pCombat, "◆", "Attack Interval", 0.30, 0.90,
        function() return S.aiI or F.AtkInterval end, function(v) S.aiI = v end, "%.2f")
    mkSlider(pCombat, "▶", "Teleport CD", 0.10, 0.80,
        function() return F.TeleportCd or 0.22 end, function(v) F.TeleportCd = v end, "%.2f")
    mkSlider(pCombat, "◀", "Retreat HP %", 10, 90,
        function() return F.RetreatHP*100 end, function(v) F.RetreatHP = v/100 end, "%.0f")
    local combatInfo = mkInfo(pCombat, 130)

    --============================================================
    -- TARGETS
    --============================================================
    local pTgt = mkPage("Targets")
    local tgtH = mkInfo(pTgt, 40)
    local TCBS = {}
    local function refreshTgtH()
        local e, t = 0, 0
        if L and L.enabledCount then e, t = L.enabledCount() end
        tgtH.Text = string.format("  enabled: %d / %d bosses", e, t)
    end
    mkSection(pTgt, "Bulk")
    mkButton(pTgt, "◈", "Select All", "Enable every boss", function()
        if L and L.setAllBosses then
            L.setAllBosses(true)
            for _, s in pairs(TCBS) do if s then pcall(s, true) end end
            refreshTgtH()
        end
    end)
    mkButton(pTgt, "✕", "Clear All", "Disable every boss", function()
        if L and L.setAllBosses then
            L.setAllBosses(false)
            for _, s in pairs(TCBS) do if s then pcall(s, false) end end
            refreshTgtH()
        end
    end, true)
    if L and L.bossRegions then
        for _, reg in ipairs(L.bossRegions) do
            mkSection(pTgt, reg.name)
            for _, bn in ipairs(reg.bosses) do
                local r = mkRow(pTgt, 48); mkIcon(r, "◆")
                local l = Instance.new("TextLabel")
                l.Size = UDim2.new(1,-110,1,0); l.Position = UDim2.new(0,64,0,0)
                l.BackgroundTransparency = 1; l.Text = bn
                l.TextColor3 = C.text; l.TextXAlignment = Enum.TextXAlignment.Left
                l.Font = FB; l.TextSize = 13; l.Parent = r
                local init = true
                if L.isBossEnabled then init = L.isBossEnabled(bn) end
                local sw, setter = mkSwitch(r, init, function(v)
                    if L.setBossEnabled then L.setBossEnabled(bn, v) end
                    refreshTgtH()
                end)
                sw.Position = UDim2.new(1,-SCW-6,0.5,-11)
                sw.AnchorPoint = Vector2.new(1,0)
                sw.ZIndex = 3
                TCBS[bn] = setter
            end
        end
    end
    refreshTgtH()

    --============================================================
    -- CHESTS
    --============================================================
    local pChest = mkPage("Chests")
    mkSection(pChest, "Master")
    mkCfgToggle(pChest, "◰", "Enable Chest Collection",
        "Master switch", "ChestEnabled")
    mkCfgToggle(pChest, "◆", "Collect on Boss Kill",
        "Multi-pass cycle after kills", "ChestOnKill")
    mkCfgToggle(pChest, "◎", "Passive Sweep While Idle",
        "Scan when no boss engaged", "ChestPassive")
    mkSection(pChest, "Collection Methods")
    mkCfgToggle(pChest, "▤", "Use ProximityPrompt",
        "fireproximityprompt + InputHold", "ChestUseProximity")
    mkCfgToggle(pChest, "▥", "Use ClickDetector",
        "fireclickdetector", "ChestUseClick")
    mkCfgToggle(pChest, "⌨", "Use Physical Key",
        "Tap T then E", "ChestUseKey")
    mkCfgToggle(pChest, "◇", "Skip Locked",
        "Cooldown failed chests", "ChestSkipLocked")
    mkSection(pChest, "Range & Timing")
    mkSlider(pChest, "◈", "Scan Radius", 10, 100,
        function() return F.ChestRadius or 50 end,
        function(v) F.ChestRadius = v end, "%.0f")
    mkSlider(pChest, "◆", "Scan Depth", 3, 12,
        function() return F.ChestScanDepth or 8 end,
        function(v) F.ChestScanDepth = v end, "%.0f")
    mkSlider(pChest, "▶", "Max Passes", 1, 10,
        function() return F.ChestMaxPasses or 6 end,
        function(v) F.ChestMaxPasses = v end, "%.0f")
    mkSlider(pChest, "◀", "Pass Deadline (s)", 3, 20,
        function() return F.ChestPassDeadline or 12 end,
        function(v) F.ChestPassDeadline = v end, "%.0f")
    mkSlider(pChest, "◎", "Per-Target CD (s)", 10, 120,
        function() return F.ChestPerTargetCooldown or 45 end,
        function(v) F.ChestPerTargetCooldown = v end, "%.0f")
    mkSlider(pChest, "⌛", "Passive Interval (s)", 5, 60,
        function() return F.ChestPassiveInterval or 12 end,
        function(v) F.ChestPassiveInterval = v end, "%.0f")
    mkSection(pChest, "Actions")
    mkButton(pChest, "▶", "Force Collect Now", "Full multi-pass cycle", function()
        if Ctx.Chest and Ctx.Chest.collectAll then
            local fired, pass = Ctx.Chest.collectAll()
            print(string.format("[Dingus][Chest] forced · fired=%d passes=%d",
                fired, pass))
        end
    end)
    mkButton(pChest, "◈", "Scan Now (Dump to F9)",
        "List every detected target", function()
            if Ctx.Chest and Ctx.Chest.dump then Ctx.Chest.dump() end
        end)
    mkButton(pChest, "✕", "Reset Cooldowns", "Clear skip-lists", function()
        if Ctx.Chest and Ctx.Chest.resetCooldowns then
            Ctx.Chest.resetCooldowns()
            print("[Dingus][Chest] cooldowns cleared")
        end
    end, true)
    mkSection(pChest, "Live Stats")
    local chestStats = mkInfo(pChest, 180)
    mkSection(pChest, "Last Scan")
    local chestTargets = mkInfo(pChest, 140)

    --============================================================
    -- QUESTS
    --============================================================
    local pQ = mkPage("Quests")
    mkSection(pQ, "Crow")
    mkToggle(pQ, "✦", "Auto Crow Quests", "Periodically read quests", "crw")
    mkButton(pQ, "◆", "Equip Crow", "Find and equip crow", function()
        if Ctx.Scan and Ctx.Scan.findCrowTool then
            local t = Ctx.Scan.findCrowTool()
            local h = U.hum()
            if t and h and t:IsA("Tool") then
                pcall(function() h:EquipTool(t) end)
                print("[Dingus] crow equipped")
            end
        end
    end)
    mkButton(pQ, "◈", "Force Quest Read", "Open menu, read, close", function()
        if Ctx.Quest and Ctx.Quest.cycle then
            local c = S.questLastCycle
            S.questLastCycle = 0
            pcall(Ctx.Quest.cycle)
            S.questLastCycle = c
        end
    end)
    mkButton(pQ, "▤", "Dump Structure", "Print BossHunts to F9", function()
        if Ctx.Quest and Ctx.Quest.dumpStructure then
            pcall(Ctx.Quest.dumpStructure)
        end
    end)
    mkSection(pQ, "Priority")
    local questInfo = mkInfo(pQ, 140)

    --============================================================
    -- CONFIG / FILES / LOGS / SETTINGS
    --============================================================
    local pCfg = mkPage("Config")
    mkSection(pCfg, "Actions")
    local cfgInfo = mkInfo(pCfg, 130)
    mkButton(pCfg, "▶", "Save Default", "Persist settings", function()
        local ok, err = F.save and F.save("default")
        print("[Dingus][Config] save: "..tostring(ok))
    end)
    mkButton(pCfg, "◀", "Load Default", "Read settings", function()
        local ok, err = F.load and F.load("default")
        print("[Dingus][Config] load: "..tostring(err))
    end)
    mkButton(pCfg, "≡", "Print to F9", "Dump config", function()
        if F.pretty then print(F.pretty()) end
    end)

    local pFiles = mkPage("Files")
    mkSection(pFiles, "Files")
    local filesInfo = mkInfo(pFiles, 260)
    mkButton(pFiles, "↻", "Refresh Files", "Re-scan folder", function()
        print("[Dingus][Files] refreshed")
    end)

    local pLogs = mkPage("Logs")
    pLogs.ScrollingEnabled = false
    for _, ch in ipairs(pLogs:GetChildren()) do
        if ch:IsA("UIPadding") then ch:Destroy() end
    end
    local lp = Instance.new("UIPadding", pLogs)
    lp.PaddingTop = UDim.new(0,PAD); lp.PaddingLeft = UDim.new(0,PAD)
    lp.PaddingRight = UDim.new(0,PAD+4); lp.PaddingBottom = UDim.new(0,PAD)

    local filterRow = Instance.new("Frame")
    filterRow.Size = UDim2.new(1,-SCW-8,0,34)
    filterRow.BackgroundTransparency = 1; filterRow.Parent = pLogs
    local fBtns = {}
    local function mkFB(lbl, key, x, w)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0,w,1,0); b.Position = UDim2.new(0,x,0,0)
        b.BackgroundColor3 = (Log.filter==key) and C.accent or C.bgP
        b.BorderSizePixel = 0; b.Text = lbl
        b.TextColor3 = (Log.filter==key) and C.text or C.textD
        b.Font = FB; b.TextSize = 12; b.AutoButtonColor = false; b.Parent = filterRow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
        fBtns[key] = b
        b.MouseButton1Click:Connect(function()
            Log.filter = key
            for k, btn in pairs(fBtns) do
                btn.BackgroundColor3 = (k==key) and C.accent or C.bgP
                btn.TextColor3 = (k==key) and C.text or C.textD
            end
            Log.dirty = true
        end)
    end
    mkFB("All", "all", 0, 60)
    mkFB("Dingus", "dingus", 64, 80)
    mkFB("Errors", "errors", 148, 74)

    local logFrame = Instance.new("Frame")
    logFrame.Size = UDim2.new(1,-SCW-8,1,-48)
    logFrame.Position = UDim2.new(0,0,0,46)
    logFrame.BackgroundColor3 = C.bgP; logFrame.BorderSizePixel = 0
    logFrame.Parent = pLogs
    Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0,11)
    local lScroll = Instance.new("ScrollingFrame")
    lScroll.Size = UDim2.new(1,-12,1,-12); lScroll.Position = UDim2.new(0,6,0,6)
    lScroll.BackgroundTransparency = 1; lScroll.BorderSizePixel = 0
    lScroll.ScrollBarThickness = 8; lScroll.ScrollBarImageColor3 = C.accent
    lScroll.ScrollBarImageTransparency = 0.3
    lScroll.CanvasSize = UDim2.new(0,0,0,0)
    lScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    lScroll.Parent = logFrame
    local lLay = Instance.new("UIListLayout", lScroll)
    lLay.Padding = UDim.new(0,3); lLay.SortOrder = Enum.SortOrder.LayoutOrder
    local logRows = {}
    local function colorFor(mt)
        if mt == Enum.MessageType.MessageError then return C.logE end
        if mt == Enum.MessageType.MessageWarning then return C.logW end
        if mt == Enum.MessageType.MessageOutput then return C.logI end
        return C.logD
    end
    local function rebuildLog()
        for _, r in ipairs(logRows) do r:Destroy() end
        logRows = {}
        local e = Log.buffer
        local st = math.max(1, #e - 250 + 1)
        for i = st, #e do
            local en = e[i]
            local r = Instance.new("TextLabel")
            r.Size = UDim2.new(1,-8,0,15); r.BackgroundTransparency = 1
            r.Text = "  ["..en.time.."] "..en.text
            r.TextColor3 = colorFor(en.type)
            r.TextXAlignment = Enum.TextXAlignment.Left
            r.Font = FC; r.TextSize = 11
            r.TextTruncate = Enum.TextTruncate.AtEnd
            r.LayoutOrder = i; r.Parent = lScroll
            table.insert(logRows, r)
        end
        lScroll.CanvasPosition = Vector2.new(0, lScroll.AbsoluteCanvasSize.Y)
    end

    local pSet = mkPage("Settings")
    mkSection(pSet, "Concealment")
    mkCfgToggle(pSet, "◈", "Concealed Parent", "Uses gethui/CoreGui", "GuiConcealed")
    mkCfgToggle(pSet, "◇", "Panic Keybind", "RightCtrl+Backspace", "GuiPanicHide")
    mkButton(pSet, "⇩", "Panic Hide Now", "Hide GUI", function()
        if gui and gui.Parent then
            gui.Parent = nil
            print("[Dingus] GUI hidden")
        end
    end, true)
    mkSection(pSet, "Diagnostics")
    local parentInfo = mkInfo(pSet, 80)
    local runtimeInfo = mkInfo(pSet, 140)

    selectPage("Dashboard")

    --============================================================
    -- MINIMIZE / RESTORE
    --============================================================
    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0,180,0,40)
    pill.Position = UDim2.new(0,20,0.5,-20)
    pill.BackgroundColor3 = C.bg
    pill.BorderSizePixel = 0; pill.Active = true; pill.Draggable = true
    pill.Visible = false; pill.Parent = gui
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1,0)
    local pStroke = Instance.new("UIStroke", pill)
    pStroke.Color = C.accent; pStroke.Thickness = 1.5
    local pDot = Instance.new("Frame")
    pDot.Size = UDim2.new(0,8,0,8); pDot.Position = UDim2.new(0,16,0.5,-4)
    pDot.BackgroundColor3 = C.accent; pDot.BorderSizePixel = 0; pDot.Parent = pill
    Instance.new("UICorner", pDot).CornerRadius = UDim.new(1,0)
    local pLbl = Instance.new("TextLabel")
    pLbl.Size = UDim2.new(1,-36,1,0); pLbl.Position = UDim2.new(0,32,0,0)
    pLbl.BackgroundTransparency = 1; pLbl.Text = "Dingus-Slayer"
    pLbl.TextColor3 = C.text; pLbl.TextXAlignment = Enum.TextXAlignment.Left
    pLbl.Font = FB; pLbl.TextSize = 13; pLbl.Parent = pill
    local pBtn = Instance.new("TextButton")
    pBtn.Size = UDim2.new(1,0,1,0); pBtn.BackgroundTransparency = 1
    pBtn.Text = ""; pBtn.Parent = pill

    local minimized = false
    local TIN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local TOUT = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    local savedPos = win.Position

    local function minimize()
        if minimized then return end
        minimized = true
        savedPos = win.Position
        local t = TW:Create(win, TOUT, {
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
        pill.BackgroundTransparency = 1; pStroke.Transparency = 1
        pDot.BackgroundTransparency = 1; pLbl.TextTransparency = 1
        TW:Create(pill, TweenInfo.new(0.22), { BackgroundTransparency = 0 }):Play()
        TW:Create(pStroke, TweenInfo.new(0.22), { Transparency = 0 }):Play()
        TW:Create(pDot, TweenInfo.new(0.22), { BackgroundTransparency = 0 }):Play()
        TW:Create(pLbl, TweenInfo.new(0.22), { TextTransparency = 0 }):Play()
    end

    local function restore()
        if not minimized then return end
        minimized = false
        TW:Create(pill, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
        TW:Create(pStroke, TweenInfo.new(0.15), { Transparency = 1 }):Play()
        TW:Create(pDot, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
        TW:Create(pLbl, TweenInfo.new(0.15), { TextTransparency = 1 }):Play()
        task.wait(0.12)
        pill.Visible = false
        win.Visible = true
        win.Position = UDim2.new(savedPos.X.Scale, savedPos.X.Offset,
                                 savedPos.Y.Scale, savedPos.Y.Offset + 40)
        win.BackgroundTransparency = 1
        TW:Create(win, TIN, { Position = savedPos, BackgroundTransparency = 0 }):Play()
    end

    minB.MouseButton1Click:Connect(minimize)
    pBtn.MouseButton1Click:Connect(restore)

    --============================================================
    -- REFRESH LOOP
    --============================================================
    local cache = {}
    task.spawn(function()
        while S.run do
            if S.boot and not minimized then
                local h = U.hum()
                local hp = h and string.format("%d/%d",
                    math.floor(h.Health), math.floor(h.MaxHealth)) or "?"
                local st = tostring(S.cbtS or "—")
                if cache.st ~= st then cache.st = st; svState.Text = st end
                local tg = S.tgt and S.tgt.ch.Name or "none"
                if cache.tg ~= tg then cache.tg = tg; svTgt.Text = tg end
                if cache.hp ~= hp then cache.hp = hp; svHp.Text = hp end
                local kl = tostring(S.bKll or 0)
                if cache.kl ~= kl then cache.kl = kl; svKill.Text = kl end

                local hr = S.aAt > 0 and math.floor(S.aHi/S.aAt*100) or 0
                local f = Ctx.Atk and Ctx.Atk.fModeInfo and Ctx.Atk.fModeInfo() or {}
                local ci = string.format(
                    "  state: %s · hits %d/%d (%d%%)\n"..
                    "  kills: %d · retreats: %d\n"..
                    "  threats: %d · imminent: %d\n"..
                    "  F: %s · blocking: %s\n"..
                    "  hp: %s · interval: %.2f",
                    S.cbtS or "—", S.aHi or 0, S.aAt or 0, hr,
                    S.bKll or 0, S.rtrC or 0, S.zn or 0, S.imm or 0,
                    f.isBlock and "BLOCK" or (f.resolved and "SKILL" or "?"),
                    tostring(f.blocking), hp, S.aiI or 0)
                if cache.ci ~= ci then cache.ci = ci; combatInfo.Text = ci end

                if Ctx.Chest and Ctx.Chest.stats then
                    local cs = Ctx.Chest.stats()
                    local csi = string.format(
                        "  enabled: %s · onKill: %s · passive: %s\n"..
                        "  radius: %d · depth: %d · cooldowns: %d\n"..
                        "  sweeps: %d · targets: %d\n"..
                        "  opened: %d · loot: %d\n"..
                        "  failed: %d · skipped: %d · lastFired: %d\n"..
                        "  running: %s",
                        tostring(cs.enabled), tostring(cs.onKill), tostring(cs.passive),
                        cs.radius, cs.depth, cs.cooldowns,
                        cs.totalSweeps, cs.lastTargets,
                        cs.collected, cs.lootCollected,
                        cs.failed, cs.skipped, cs.lastFired,
                        tostring(cs.running))
                    if cache.csi ~= csi then cache.csi = csi; chestStats.Text = csi end

                    local lines = {}
                    local tg2 = Ctx.Chest.lastTargets and Ctx.Chest.lastTargets() or {}
                    if #tg2 == 0 then
                        table.insert(lines, "  (no targets — press Scan Now)")
                    else
                        table.insert(lines, string.format("  %d detected:", #tg2))
                        for i = 1, math.min(#tg2, 6) do
                            local t = tg2[i]
                            table.insert(lines, string.format("    [%s] %s @%.0f",
                                t.kind, (t.name or "?"):gsub("^%s+", ""):sub(1,28), t.d))
                        end
                        if #tg2 > 6 then
                            table.insert(lines, string.format("    ... +%d more", #tg2-6))
                        end
                    end
                    local ct = table.concat(lines, "\n")
                    if cache.ct ~= ct then cache.ct = ct; chestTargets.Text = ct end
                end

                local qi = string.format(
                    "  crow: %s · perched: %s\n"..
                    "  quests: %d · level: %d\n"..
                    "  hunts: %d · cycles: %d",
                    S.crT and S.crT.Name or "not found",
                    tostring(S.cPrch), S.crQuests and #S.crQuests or 0,
                    S.playerLevel or 0, S.huntCount or 0, S.crowCycle or 0)
                if cache.qi ~= qi then cache.qi = qi; questInfo.Text = qi end

                local cfgi = string.format(
                    "  file: %s\n  writefile: %s · readfile: %s",
                    F.slotFile and F.slotFile("default") or "?",
                    tostring(HAS.writefile), tostring(HAS.readfile))
                if cache.cfgi ~= cfgi then cache.cfgi = cfgi; cfgInfo.Text = cfgi end

                local pi = string.format(
                    "  parent: %s\n  name: %s\n  gethui: %s\n  concealed: %s",
                    parentKind, guiName, tostring(HAS.gethui), tostring(F.GuiConcealed))
                if cache.pi ~= pi then cache.pi = pi; parentInfo.Text = pi end

                local ri = string.format(
                    "  fps: %.0f\n  boot: %s · combat: %s\n  spoofers: %s · crow: %s\n  bosses: %d",
                    S.fps or 60, tostring(S.boot), S.cbt and "on" or "off",
                    S.gsp and "on" or "off", S.crw and "on" or "off",
                    L and #L.bosses or 0)
                if cache.ri ~= ri then cache.ri = ri; runtimeInfo.Text = ri end

                local bar = string.format("%s · fps %.0f · log %d",
                    S.cbt and "combat" or "idle", S.fps or 60, #Log.buffer)
                if cache.bar ~= bar then cache.bar = bar; liveL.Text = bar end
                local ck = S.cbt and "g" or "m"
                if cache.ck ~= ck then
                    cache.ck = ck
                    fDot.BackgroundColor3 = S.cbt and C.green or C.textM
                    liveDot.BackgroundColor3 = S.cbt and C.green or C.textM
                end
                if Log.dirty then Log.dirty = false; rebuildLog() end
            end
            task.wait(0.3)
        end
    end)

    UIS.InputBegan:Connect(function(inp, gp)
        if gp then return end
        if inp.KeyCode == Enum.KeyCode.RightShift then
            if minimized then restore() else minimize() end
            return
        end
        if F.GuiPanicHide and inp.KeyCode == Enum.KeyCode.Backspace
           and UIS:IsKeyDown(Enum.KeyCode.RightControl) then
            gui.Parent = nil
            print("[Dingus] GUI panic-hidden")
        end
    end)

    closeB.MouseButton1Click:Connect(function()
        restore()
        gui:Destroy()
    end)

    G.gui = gui
    G.win = win
    G.minimize = minimize
    G.restore = restore
    G.Log = Log
    G.PAGES = PAGES
    G.parent = parent
    G.parentKind = parentKind

    print(string.format("[Dingus][gui] v34 initialized · 9 tabs"))
end

return G
