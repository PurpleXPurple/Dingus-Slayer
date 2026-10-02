-- Dingus-Slayer · gui.lua v42
-- Full rebuild with:
--   · Lazy page construction (widgets built on first visit, not boot)
--   · Shared slider InputChanged connection (one, not N)
--   · Per-panel refresh throttle (combat 0.2s, chest 1.0s, faction 0.8s, perf 1.0s)
--   · Reusable dropdown overlay (created once, hidden/shown)
--   · Every widget constructor and callback pcall-wrapped
--   · Guard against gui.Parent == nil (panic hide) inside refresh
--   · Precomputed UDim2 constants for hot rows
--   · Camera viewport fetched from workspace.CurrentCamera, not UIS

local G = {}

function G.init(Ctx)
    local U = Ctx.Util
    local F = Ctx.Cfg
    local S = Ctx.St
    local L = Ctx.Lists

    --========================================================
    -- CACHED SERVICE REFERENCES (fetched once)
    --========================================================
    local TW   = U.TS or game:GetService("TweenService")
    local UIS  = U.UIS or game:GetService("UserInputService")
    local RS   = U.Run or game:GetService("RunService")

    --========================================================
    -- SAFE WRAPPERS
    --========================================================
    local function safe(fn, ...)
        local ok, a, b, c = pcall(fn, ...)
        if ok then return a, b, c end
        warn("[Dingus][gui] " .. tostring(a))
        return nil
    end

    local function safeConnect(sig, fn)
        if not sig or not sig.Connect then return nil end
        local ok, conn = pcall(function() return sig:Connect(fn) end)
        if ok then return conn end
        return nil
    end

    local function safeTween(inst, info, props)
        if not inst or not inst.Parent then return end
        pcall(function() TW:Create(inst, info, props):Play() end)
    end

    local function safeSetText(label, text)
        if not label or not label.Parent then return end
        pcall(function() label.Text = text end)
    end

    local function safeSetColor(inst, prop, color)
        if not inst or not inst.Parent then return end
        pcall(function() inst[prop] = color end)
    end

    --========================================================
    -- CONFIG DEFAULTS
    --========================================================
    F.GuiConcealed  = F.GuiConcealed ~= false
    F.GuiPanicHide  = F.GuiPanicHide ~= false

    --========================================================
    -- PARENT + VIEWPORT
    --========================================================
    local parent, parentKind = U.resolveGuiParent()
    local guiName = "_c" .. string.format("%06x", math.random(0, 0xFFFFFF))
    local old = parent and parent:FindFirstChild("DingusUI")
    if old then pcall(function() old:Destroy() end) end

    local cam = workspace.CurrentCamera
    local vp
    if cam and cam.ViewportSize then
        vp = cam.ViewportSize
    else
        vp = Vector2.new(1280, 720)
    end

    local isM = U.IsMobile
    local WW  = isM and math.min(vp.X - 16, 560) or 1000
    local WH  = isM and math.min(vp.Y - 32, 680) or 720
    local HH  = isM and 46 or 52
    local SW  = isM and 148 or 208
    local PAD = isM and 10 or 14
    local RG  = 8
    local SCW = isM and 5 or 8
    local TGT = 44
    local ROW_H = 62

    --========================================================
    -- PALETTE
    --========================================================
    local C = {
        bg=Color3.fromRGB(11,11,15), bgH=Color3.fromRGB(15,15,21),
        bgS=Color3.fromRGB(9,9,13), bgP=Color3.fromRGB(18,18,24),
        row=Color3.fromRGB(24,24,32), rowH=Color3.fromRGB(34,34,44),
        iconBg=Color3.fromRGB(44,24,24),
        navA=Color3.fromRGB(44,26,26), navH=Color3.fromRGB(22,22,30),
        trackOff=Color3.fromRGB(52,52,66),
        border=Color3.fromRGB(42,34,36),
        accent=Color3.fromRGB(220,90,70), accentD=Color3.fromRGB(150,60,50),
        green=Color3.fromRGB(80,200,120), red=Color3.fromRGB(220,70,80),
        blue=Color3.fromRGB(80,140,220), purple=Color3.fromRGB(160,100,220),
        yellow=Color3.fromRGB(230,190,80),
        text=Color3.fromRGB(232,232,240), textD=Color3.fromRGB(160,165,180),
        textM=Color3.fromRGB(110,115,135),
        dropdown=Color3.fromRGB(38,38,48),
        overlay=Color3.fromRGB(0,0,0),
    }

    local FB = Enum.Font.GothamBold
    local FR = Enum.Font.Gotham
    local FC = Enum.Font.Code

    --========================================================
    -- PRECOMPUTED UDIM2 CONSTANTS
    --========================================================
    local ROW_W_OFFSET = -SCW - 4
    local UD_ROW_SIZE  = UDim2.new(1, ROW_W_OFFSET, 0, ROW_H)
    local UD_ROW_SLIDER = UDim2.new(1, ROW_W_OFFSET, 0, 70)
    local UD_FULL_W    = UDim2.new(1, ROW_W_OFFSET, 0, 0)

    --========================================================
    -- ROOT
    --========================================================
    local gui = Instance.new("ScreenGui")
    gui.Name = guiName
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 2^30
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    local win = Instance.new("Frame")
    win.Size = UDim2.new(0, WW, 0, WH)
    win.Position = UDim2.new(0.5, -WW / 2, 0.5, -WH / 2)
    win.BackgroundColor3 = C.bg
    win.BorderSizePixel = 0
    win.Active = true
    win.Draggable = true
    win.ClipsDescendants = true
    win.Parent = gui
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 14)
    local ws = Instance.new("UIStroke", win)
    ws.Color = C.border
    ws.Thickness = 1
    ws.Transparency = 0.15

    --========================================================
    -- HEADER
    --========================================================
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, HH)
    header.BackgroundColor3 = C.bgH
    header.BorderSizePixel = 0
    header.Parent = win
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)

    local brandBox = Instance.new("Frame")
    brandBox.Size = UDim2.new(0, isM and 120 or 160, 1, 0)
    brandBox.Position = UDim2.new(0, 14, 0, 0)
    brandBox.BackgroundTransparency = 1
    brandBox.Parent = header

    local brand = Instance.new("TextLabel")
    brand.Size = UDim2.new(1, 0, 0, 18)
    brand.Position = UDim2.new(0, 0, 0, isM and 8 or 10)
    brand.BackgroundTransparency = 1
    brand.Text = "DINGUS-SLAYER"
    brand.TextColor3 = C.accent
    brand.TextXAlignment = Enum.TextXAlignment.Left
    brand.Font = FB
    brand.TextSize = isM and 12 or 14
    brand.Parent = brandBox

    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, 0, 0, 14)
    subtitle.Position = UDim2.new(0, 0, 0, isM and 26 or 30)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = U.Platform .. " · " .. (U.Executor or "?")
    subtitle.TextColor3 = C.textM
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Font = FR
    subtitle.TextSize = 10
    subtitle.TextTruncate = Enum.TextTruncate.AtEnd
    subtitle.Parent = brandBox

    local chip = Instance.new("Frame")
    chip.Size = UDim2.new(0, isM and 100 or 130, 0, 24)
    chip.Position = UDim2.new(0, isM and 150 or 190, 0.5, -12)
    chip.BackgroundColor3 = C.row
    chip.BorderSizePixel = 0
    chip.Parent = header
    Instance.new("UICorner", chip).CornerRadius = UDim.new(1, 0)
    local chipDot = Instance.new("Frame")
    chipDot.Size = UDim2.new(0, 8, 0, 8)
    chipDot.Position = UDim2.new(0, 10, 0.5, -4)
    chipDot.BackgroundColor3 = C.textM
    chipDot.BorderSizePixel = 0
    chipDot.Parent = chip
    Instance.new("UICorner", chipDot).CornerRadius = UDim.new(1, 0)
    local chipText = Instance.new("TextLabel")
    chipText.Size = UDim2.new(1, -24, 1, 0)
    chipText.Position = UDim2.new(0, 22, 0, 0)
    chipText.BackgroundTransparency = 1
    chipText.Text = "idle"
    chipText.TextColor3 = C.text
    chipText.TextXAlignment = Enum.TextXAlignment.Left
    chipText.Font = FB
    chipText.TextSize = 11
    chipText.Parent = chip

    local facChip = Instance.new("Frame")
    facChip.Size = UDim2.new(0, isM and 80 or 100, 0, 24)
    facChip.Position = UDim2.new(0, isM and 258 or 326, 0.5, -12)
    facChip.BackgroundColor3 = C.row
    facChip.BorderSizePixel = 0
    facChip.Parent = header
    Instance.new("UICorner", facChip).CornerRadius = UDim.new(1, 0)
    local facText = Instance.new("TextLabel")
    facText.Size = UDim2.new(1, -16, 1, 0)
    facText.Position = UDim2.new(0, 10, 0, 0)
    facText.BackgroundTransparency = 1
    facText.Text = "faction: ?"
    facText.TextColor3 = C.textD
    facText.TextXAlignment = Enum.TextXAlignment.Left
    facText.Font = FB
    facText.TextSize = 11
    facText.Parent = facChip

    local function mkCtrl(glyph, x, col)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, TGT, 0, TGT)
        b.Position = UDim2.new(1, x, 0.5, -TGT / 2)
        b.BackgroundColor3 = col
        b.BackgroundTransparency = 1
        b.BorderSizePixel = 0
        b.Text = glyph
        b.TextColor3 = C.textD
        b.Font = FB
        b.TextSize = 16
        b.AutoButtonColor = false
        b.Parent = header
        Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
        safeConnect(b.MouseEnter, function()
            safeTween(b, TweenInfo.new(0.12), {
                BackgroundTransparency = 0,
                BackgroundColor3 = col,
                TextColor3 = C.text,
            })
        end)
        safeConnect(b.MouseLeave, function()
            safeTween(b, TweenInfo.new(0.12), {
                BackgroundTransparency = 1,
                TextColor3 = C.textD,
            })
        end)
        return b
    end
    local closeB = mkCtrl("X", -TGT - 8, C.red)
    local minB   = mkCtrl("-", -TGT * 2 - 14, Color3.fromRGB(60, 60, 75))

    --========================================================
    -- SIDEBAR
    --========================================================
    local side = Instance.new("Frame")
    side.Size = UDim2.new(0, SW, 1, -HH)
    side.Position = UDim2.new(0, 0, 0, HH)
    side.BackgroundColor3 = C.bgS
    side.BorderSizePixel = 0
    side.Parent = win

    local navScroll = Instance.new("ScrollingFrame")
    navScroll.Size = UDim2.new(1, -12, 1, -80)
    navScroll.Position = UDim2.new(0, 6, 0, 10)
    navScroll.BackgroundTransparency = 1
    navScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    navScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    navScroll.ScrollBarThickness = 4
    navScroll.ScrollBarImageColor3 = C.accentD
    navScroll.Parent = side
    local navLay = Instance.new("UIListLayout", navScroll)
    navLay.Padding = UDim.new(0, 4)
    navLay.SortOrder = Enum.SortOrder.LayoutOrder

    local farmPulse = Instance.new("Frame")
    farmPulse.Size = UDim2.new(1, -16, 0, 34)
    farmPulse.Position = UDim2.new(0, 8, 1, -44)
    farmPulse.BackgroundColor3 = C.bgP
    farmPulse.BorderSizePixel = 0
    farmPulse.Parent = side
    Instance.new("UICorner", farmPulse).CornerRadius = UDim.new(0, 8)
    local pulseDot = Instance.new("Frame")
    pulseDot.Size = UDim2.new(0, 8, 0, 8)
    pulseDot.Position = UDim2.new(0, 12, 0.5, -4)
    pulseDot.BackgroundColor3 = C.textM
    pulseDot.BorderSizePixel = 0
    pulseDot.Parent = farmPulse
    Instance.new("UICorner", pulseDot).CornerRadius = UDim.new(1, 0)
    local pulseText = Instance.new("TextLabel")
    pulseText.Size = UDim2.new(1, -30, 1, 0)
    pulseText.Position = UDim2.new(0, 26, 0, 0)
    pulseText.BackgroundTransparency = 1
    pulseText.Text = "farm: idle"
    pulseText.TextColor3 = C.textD
    pulseText.TextXAlignment = Enum.TextXAlignment.Left
    pulseText.Font = FB
    pulseText.TextSize = 11
    pulseText.Parent = farmPulse

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -SW, 1, -HH)
    content.Position = UDim2.new(0, SW, 0, HH)
    content.BackgroundColor3 = C.bg
    content.BorderSizePixel = 0
    content.ClipsDescendants = true
    content.Parent = win

    --========================================================
    -- WIDGET FACTORY
    --========================================================
    local counters = {}
    local function nextO(p)
        counters[p] = (counters[p] or 0) + 1
        return counters[p]
    end

    local function mkRow(p, h)
        local r = Instance.new("Frame")
        r.Size = h == 70 and UD_ROW_SLIDER or UD_ROW_SIZE
        r.BackgroundColor3 = C.row
        r.BorderSizePixel = 0
        r.LayoutOrder = nextO(p)
        r.Active = true
        r.Parent = p
        Instance.new("UICorner", r).CornerRadius = UDim.new(0, 11)
        return r
    end

    local function mkIcon(par, glyph, tint)
        local b = Instance.new("Frame")
        b.Size = UDim2.new(0, 36, 0, 36)
        b.Position = UDim2.new(0, 12, 0, 12)
        b.BackgroundColor3 = C.iconBg
        b.BorderSizePixel = 0
        b.Parent = par
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 9)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 1, 0)
        l.BackgroundTransparency = 1
        l.Text = glyph
        l.TextColor3 = tint or C.accent
        l.Font = FB
        l.TextSize = 17
        l.Parent = b
    end

    local function mkTitle(r, title, desc)
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -110, 0, 18)
        t.Position = UDim2.new(0, 58, 0, 10)
        t.BackgroundTransparency = 1
        t.Text = title
        t.TextColor3 = C.text
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Font = FB
        t.TextSize = 13
        t.TextTruncate = Enum.TextTruncate.AtEnd
        t.Parent = r
        if desc and desc ~= "" then
            local d = Instance.new("TextLabel")
            d.Size = UDim2.new(1, -110, 0, 14)
            d.Position = UDim2.new(0, 58, 0, 28)
            d.BackgroundTransparency = 1
            d.Text = desc
            d.TextColor3 = C.textM
            d.TextXAlignment = Enum.TextXAlignment.Left
            d.Font = FR
            d.TextSize = 11
            d.TextTruncate = Enum.TextTruncate.AtEnd
            d.Parent = r
        end
    end

    local function mkSwitch(par, init, cb)
        local t = Instance.new("TextButton")
        t.Size = UDim2.new(0, 46, 0, 26)
        t.BackgroundColor3 = init and C.accent or C.trackOff
        t.BorderSizePixel = 0
        t.Text = ""
        t.AutoButtonColor = false
        t.Parent = par
        Instance.new("UICorner", t).CornerRadius = UDim.new(1, 0)
        local k = Instance.new("Frame")
        k.Size = UDim2.new(0, 20, 0, 20)
        k.Position = init
            and UDim2.new(1, -22, 0.5, -10)
            or  UDim2.new(0, 3, 0.5, -10)
        k.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
        k.BorderSizePixel = 0
        k.Parent = t
        Instance.new("UICorner", k).CornerRadius = UDim.new(1, 0)

        local st = init
        local function set(v)
            st = v
            safeTween(t, TweenInfo.new(0.18), {
                BackgroundColor3 = st and C.accent or C.trackOff,
            })
            safeTween(k, TweenInfo.new(0.18), {
                Position = st
                    and UDim2.new(1, -22, 0.5, -10)
                    or  UDim2.new(0, 3, 0.5, -10),
            })
            if cb then
                local ok, err = pcall(cb, st)
                if not ok then
                    warn("[Dingus][gui][switch] " .. tostring(err))
                end
            end
        end
        safeConnect(t.MouseButton1Click, function() set(not st) end)
        return t, set
    end

    local function mkToggle(p, glyph, title, desc, key, cb)
        local r = mkRow(p, ROW_H)
        mkIcon(r, glyph)
        mkTitle(r, title, desc)
        local init = S[key]
        if init == nil then init = F[key] end
        local sw = mkSwitch(r, init, function(v)
            S[key] = v
            F[key] = v
            if cb then pcall(cb, v) end
        end)
        sw.Position = UDim2.new(1, -60, 0.5, -13)
        sw.ZIndex = 3
        return r
    end

    local function mkButton(p, glyph, title, desc, cb, tint)
        local r = mkRow(p, ROW_H)
        mkIcon(r, glyph, tint)
        mkTitle(r, title, desc)
        local chev = Instance.new("TextLabel")
        chev.Size = UDim2.new(0, 20, 0, 24)
        chev.Position = UDim2.new(1, -SCW - 24, 0.5, -12)
        chev.BackgroundTransparency = 1
        chev.Text = ">"
        chev.TextColor3 = tint or C.textM
        chev.Font = FB
        chev.TextSize = 20
        chev.Parent = r
        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, 0, 1, 0)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.Parent = r
        safeConnect(hit.MouseButton1Click, function()
            local ok, err = pcall(cb)
            if not ok then
                print("[Dingus][btn] " .. title .. ": " .. tostring(err))
            end
        end)
        return r
    end

    local function mkInfo(p, h)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, ROW_W_OFFSET, 0, h or 100)
        l.BackgroundColor3 = C.row
        l.BorderSizePixel = 0
        l.Text = "-"
        l.TextColor3 = C.textD
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Top
        l.Font = FC
        l.TextSize = 12
        l.TextWrapped = true
        l.LayoutOrder = nextO(p)
        l.Parent = p
        Instance.new("UICorner", l).CornerRadius = UDim.new(0, 11)
        local pad = Instance.new("UIPadding", l)
        pad.PaddingTop = UDim.new(0, 12)
        pad.PaddingLeft = UDim.new(0, 14)
        pad.PaddingRight = UDim.new(0, 14)
        return l
    end

    local function mkSection(p, text)
        local h = Instance.new("TextLabel")
        h.Size = UDim2.new(1, ROW_W_OFFSET, 0, 22)
        h.BackgroundTransparency = 1
        h.Text = string.upper(text)
        h.TextColor3 = C.textM
        h.TextXAlignment = Enum.TextXAlignment.Left
        h.TextYAlignment = Enum.TextYAlignment.Bottom
        h.Font = FB
        h.TextSize = 10
        h.LayoutOrder = nextO(p)
        h.Parent = p
    end

    --========================================================
    -- SLIDER (shared InputChanged connection)
    --========================================================
    local activeSlider = nil

    local function mkSlider(p, glyph, title, mn, mx, getter, setter, fmt)
        fmt = fmt or "%.1f"
        local r = mkRow(p, 70)
        mkIcon(r, glyph)

        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, -180, 0, 18)
        tl.Position = UDim2.new(0, 58, 0, 10)
        tl.BackgroundTransparency = 1
        tl.Text = title
        tl.TextColor3 = C.text
        tl.TextXAlignment = Enum.TextXAlignment.Left
        tl.Font = FB
        tl.TextSize = 13
        tl.Parent = r

        local vl = Instance.new("TextLabel")
        vl.Size = UDim2.new(0, 80, 0, 18)
        vl.Position = UDim2.new(1, -SCW - 6, 0, 10)
        vl.AnchorPoint = Vector2.new(1, 0)
        vl.BackgroundTransparency = 1
        vl.Text = string.format(fmt, getter())
        vl.TextColor3 = C.accent
        vl.TextXAlignment = Enum.TextXAlignment.Right
        vl.Font = FB
        vl.TextSize = 12
        vl.Parent = r

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(1, -80, 0, 6)
        bar.Position = UDim2.new(0, 58, 0, 46)
        bar.BackgroundColor3 = C.trackOff
        bar.BorderSizePixel = 0
        bar.Parent = r
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

        local pct = math.clamp((getter() - mn) / (mx - mn), 0, 1)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(pct, 0, 1, 0)
        fill.BackgroundColor3 = C.accent
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
        hit.Size = UDim2.new(1, -80, 0, 26)
        hit.Position = UDim2.new(0, 58, 0, 36)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.Parent = r

        local handle = {
            bar = bar, knob = knob, fill = fill, vl = vl,
            mn = mn, mx = mx, fmt = fmt, setter = setter,
        }

        safeConnect(hit.InputBegan, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
               or i.UserInputType == Enum.UserInputType.Touch then
                activeSlider = handle
            end
        end)
        safeConnect(hit.InputEnded, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
               or i.UserInputType == Enum.UserInputType.Touch then
                if activeSlider == handle then activeSlider = nil end
            end
        end)
        return r
    end

    -- Single shared InputChanged connection
    if UIS then
        safeConnect(UIS.InputChanged, function(i)
            local h = activeSlider
            if not h then return end
            if not h.bar or not h.bar.Parent then
                activeSlider = nil
                return
            end
            if i.UserInputType ~= Enum.UserInputType.MouseMovement
               and i.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            local mx2 = UIS:GetMouseLocation().X
            local bx = h.bar.AbsolutePosition.X
            local bw = h.bar.AbsoluteSize.X
            if bw <= 0 then return end
            local pp = math.clamp((mx2 - bx) / bw, 0, 1)
            local val = h.mn + (h.mx - h.mn) * pp
            pcall(h.setter, val)
            pcall(function()
                h.vl.Text = string.format(h.fmt, val)
                h.fill.Size = UDim2.new(pp, 0, 1, 0)
                h.knob.Position = UDim2.new(pp, -7, 0.5, -7)
            end)
        end)
    end

    --========================================================
    -- DROPDOWN (single reusable overlay)
    --========================================================
    local overlay = Instance.new("TextButton")
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = C.overlay
    overlay.BackgroundTransparency = 0.55
    overlay.Text = ""
    overlay.Visible = false
    overlay.ZIndex = 100
    overlay.Parent = gui

    local list = Instance.new("ScrollingFrame")
    local lw = math.min(300, WW - 60)
    local lh = math.min(400, WH - 100)
    list.Size = UDim2.new(0, lw, 0, lh)
    list.Position = UDim2.new(0.5, -lw / 2, 0.5, -lh / 2)
    list.BackgroundColor3 = C.bgH
    list.BorderSizePixel = 0
    list.CanvasSize = UDim2.new(0, 0, 0, 0)
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.ScrollBarThickness = 6
    list.ScrollBarImageColor3 = C.accent
    list.Visible = false
    list.ZIndex = 101
    list.Parent = gui
    Instance.new("UICorner", list).CornerRadius = UDim.new(0, 12)
    local lStroke = Instance.new("UIStroke", list)
    lStroke.Color = C.accent
    lStroke.Thickness = 1
    local lLay = Instance.new("UIListLayout", list)
    lLay.Padding = UDim.new(0, 2)
    lLay.SortOrder = Enum.SortOrder.LayoutOrder
    local lp = Instance.new("UIPadding", list)
    lp.PaddingTop = UDim.new(0, 8)
    lp.PaddingBottom = UDim.new(0, 8)
    lp.PaddingLeft = UDim.new(0, 8)
    lp.PaddingRight = UDim.new(0, 8)

    local dropdownOpen = false

    local function closeDropdown()
        if not dropdownOpen then return end
        dropdownOpen = false
        overlay.Visible = false
        list.Visible = false
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("TextButton") then
                pcall(function() child:Destroy() end)
            end
        end
    end

    safeConnect(overlay.MouseButton1Click, closeDropdown)

    local function mkDropdown(p, glyph, title, desc, optionsFn, getter, setter)
        local r = mkRow(p, ROW_H)
        mkIcon(r, glyph)
        mkTitle(r, title, desc)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 150, 0, 32)
        btn.Position = UDim2.new(1, -162, 0.5, -16)
        btn.BackgroundColor3 = C.dropdown
        btn.BorderSizePixel = 0
        btn.TextColor3 = C.text
        btn.Font = FB
        btn.TextSize = 12
        btn.AutoButtonColor = false
        btn.TextTruncate = Enum.TextTruncate.AtEnd
        btn.Parent = r
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

        local currentText = "  " .. tostring(getter())
        btn.Text = currentText

        safeConnect(btn.MouseButton1Click, function()
            local options = optionsFn()
            if not options or #options == 0 then return end
            closeDropdown()
            local current = tostring(getter())
            for i = 1, #options do
                local opt = options[i]
                local ob = Instance.new("TextButton")
                ob.Size = UDim2.new(1, -8, 0, 36)
                ob.BackgroundColor3 = (opt == current)
                    and C.accent or C.row
                ob.BorderSizePixel = 0
                ob.Text = "  " .. tostring(opt)
                ob.TextColor3 = (opt == current)
                    and C.text or C.textD
                ob.TextXAlignment = Enum.TextXAlignment.Left
                ob.Font = FB
                ob.TextSize = 13
                ob.AutoButtonColor = false
                ob.LayoutOrder = i
                ob.ZIndex = 102
                ob.Parent = list
                Instance.new("UICorner", ob).CornerRadius = UDim.new(0, 8)
                safeConnect(ob.MouseEnter, function()
                    safeSetColor(ob, "BackgroundColor3", C.rowH)
                end)
                safeConnect(ob.MouseLeave, function()
                    safeSetColor(ob, "BackgroundColor3",
                        (opt == current) and C.accent or C.row)
                end)
                safeConnect(ob.MouseButton1Click, function()
                    pcall(setter, opt)
                    btn.Text = "  " .. tostring(opt)
                    closeDropdown()
                end)
            end
            dropdownOpen = true
            overlay.Visible = true
            list.Visible = true
        end)
        return r
    end

    --========================================================
    -- SEGMENT
    --========================================================
    local function mkSegment(p, glyph, title, desc, options, getter, setter)
        local r = mkRow(p, ROW_H)
        mkIcon(r, glyph)
        mkTitle(r, title, desc)
        local holder = Instance.new("Frame")
        holder.Size = UDim2.new(0, 160, 0, 32)
        holder.Position = UDim2.new(1, -172, 0.5, -16)
        holder.BackgroundColor3 = C.dropdown
        holder.BorderSizePixel = 0
        holder.Parent = r
        Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 8)
        local lay = Instance.new("UIListLayout", holder)
        lay.FillDirection = Enum.FillDirection.Horizontal
        lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
        lay.VerticalAlignment = Enum.VerticalAlignment.Center
        lay.SortOrder = Enum.SortOrder.LayoutOrder

        local buttons = {}
        local current = tostring(getter())
        local function set(v)
            current = v
            for opt, b in pairs(buttons) do
                safeSetColor(b, "BackgroundColor3",
                    (opt == current) and C.accent or C.dropdown)
                safeSetColor(b, "TextColor3",
                    (opt == current) and C.text or C.textD)
            end
            pcall(setter, v)
        end
        for i = 1, #options do
            local opt = options[i]
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1 / #options, -2, 1, -4)
            b.BackgroundColor3 = (opt == current)
                and C.accent or C.dropdown
            b.BorderSizePixel = 0
            b.Text = tostring(opt)
            b.TextColor3 = (opt == current)
                and C.text or C.textD
            b.Font = FB
            b.TextSize = 11
            b.AutoButtonColor = false
            b.LayoutOrder = i
            b.Parent = holder
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
            safeConnect(b.MouseButton1Click, function() set(opt) end)
            buttons[opt] = b
        end
        return r
    end

    --========================================================
    -- STAT CARD
    --========================================================
    local function mkStatCard(p, glyph, label, order)
        local c = Instance.new("Frame")
        c.Size = UDim2.new(0.5, -6, 0, 68)
        c.BackgroundColor3 = C.row
        c.BorderSizePixel = 0
        c.LayoutOrder = order or nextO(p)
        c.Parent = p
        Instance.new("UICorner", c).CornerRadius = UDim.new(0, 11)

        local icon = Instance.new("TextLabel")
        icon.Size = UDim2.new(0, 24, 0, 24)
        icon.Position = UDim2.new(0, 12, 0, 12)
        icon.BackgroundTransparency = 1
        icon.Text = glyph
        icon.TextColor3 = C.accent
        icon.Font = FB
        icon.TextSize = 14
        icon.Parent = c

        local lt = Instance.new("TextLabel")
        lt.Size = UDim2.new(1, -46, 0, 14)
        lt.Position = UDim2.new(0, 42, 0, 12)
        lt.BackgroundTransparency = 1
        lt.Text = string.upper(label)
        lt.TextColor3 = C.textM
        lt.TextXAlignment = Enum.TextXAlignment.Left
        lt.Font = FB
        lt.TextSize = 9
        lt.Parent = c

        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(1, -46, 0, 22)
        v.Position = UDim2.new(0, 42, 0, 30)
        v.BackgroundTransparency = 1
        v.Text = "-"
        v.TextColor3 = C.text
        v.TextXAlignment = Enum.TextXAlignment.Left
        v.Font = FB
        v.TextSize = 16
        v.TextTruncate = Enum.TextTruncate.AtEnd
        v.Parent = c
        return v
    end

    --========================================================
    -- PAGES (lazy)
    --========================================================
    local PAGES = {}       -- name -> ScrollingFrame
    local PAGE_BUILDERS = {} -- name -> builder function
    local PAGE_BUILT = {}  -- name -> true after build
    local NAV = {}
    local currentPage = nil

    local function mkPage(name, builderFn)
        local p = Instance.new("ScrollingFrame")
        p.Name = name
        p.Size = UDim2.new(1, 0, 1, 0)
        p.BackgroundTransparency = 1
        p.Visible = false
        p.CanvasSize = UDim2.new(0, 0, 0, 0)
        p.AutomaticCanvasSize = Enum.AutomaticSize.Y
        p.ScrollBarThickness = SCW
        p.ScrollBarImageColor3 = C.accent
        p.Parent = content
        local lay = Instance.new("UIListLayout", p)
        lay.Padding = UDim.new(0, RG)
        lay.SortOrder = Enum.SortOrder.LayoutOrder
        local pad = Instance.new("UIPadding", p)
        pad.PaddingTop = UDim.new(0, PAD)
        pad.PaddingLeft = UDim.new(0, PAD)
        pad.PaddingRight = UDim.new(0, SCW + 4)
        pad.PaddingBottom = UDim.new(0, PAD + 8)
        PAGES[name] = p
        PAGE_BUILDERS[name] = builderFn
        return p
    end

    local function ensurePageBuilt(name)
        if PAGE_BUILT[name] then return end
        local builder = PAGE_BUILDERS[name]
        local p = PAGES[name]
        if not builder or not p then return end
        PAGE_BUILT[name] = true
        local ok, err = pcall(builder, p)
        if not ok then
            warn("[Dingus][gui] page " .. name .. " build failed: "
                .. tostring(err))
        end
    end

    local function selectPage(name)
        if currentPage == name then return end
        currentPage = name
        for n, p in pairs(PAGES) do p.Visible = (n == name) end
        for n, e in pairs(NAV) do e.setActive(n == name) end
        ensurePageBuilt(name)
    end

    local function mkNav(glyph, lbl, name, order)
        local it = Instance.new("TextButton")
        it.Size = UDim2.new(1, -4, 0, isM and 44 or 42)
        it.BackgroundTransparency = 1
        it.Text = ""
        it.LayoutOrder = order
        it.AutoButtonColor = false
        it.Parent = navScroll
        Instance.new("UICorner", it).CornerRadius = UDim.new(0, 9)

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(0, 3, 0, 20)
        bar.Position = UDim2.new(0, 0, 0.5, -10)
        bar.BackgroundColor3 = C.accent
        bar.BackgroundTransparency = 1
        bar.BorderSizePixel = 0
        bar.Parent = it
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

        local ico = Instance.new("TextLabel")
        ico.Size = UDim2.new(0, 24, 0, 24)
        ico.Position = UDim2.new(0, 14, 0.5, -12)
        ico.BackgroundTransparency = 1
        ico.Text = glyph
        ico.TextColor3 = C.textD
        ico.Font = FB
        ico.TextSize = 15
        ico.Parent = it

        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -48, 1, 0)
        l.Position = UDim2.new(0, 44, 0, 0)
        l.BackgroundTransparency = 1
        l.Text = lbl
        l.TextColor3 = C.textD
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Font = FB
        l.TextSize = isM and 12 or 13
        l.TextTruncate = Enum.TextTruncate.AtEnd
        l.Parent = it

        local active = false
        local function setActive(a)
            active = a
            it.BackgroundTransparency = a and 0 or 1
            it.BackgroundColor3 = a and C.navA or C.navH
            ico.TextColor3 = a and C.accent or C.textD
            l.TextColor3 = a and C.text or C.textD
            bar.BackgroundTransparency = a and 0 or 1
        end
        safeConnect(it.MouseEnter, function()
            if not active then
                it.BackgroundTransparency = 0
                it.BackgroundColor3 = C.navH
            end
        end)
        safeConnect(it.MouseLeave, function()
            if not active then it.BackgroundTransparency = 1 end
        end)
        safeConnect(it.MouseButton1Click, function() selectPage(name) end)
        NAV[name] = { item = it, setActive = setActive }
    end

    mkNav("*", "Dashboard", "Dashboard", 1)
    mkNav("#", "Farm",      "Farm",      2)
    mkNav("!", "Faction",   "Faction",   3)
    mkNav("$", "Chests",    "Chests",    4)
    mkNav("+", "Quests",    "Quests",    5)
    mkNav("=", "Logs",      "Logs",      6)
    mkNav("@", "Settings",  "Settings",  7)

    --========================================================
    -- REFRESH HANDLES (populated when pages are built)
    --========================================================
    local R = {
        dashInfo = nil, farmInfo = nil,
        facStatus = nil, facList = nil,
        chestStats = nil, questInfo = nil,
        runtimeInfo = nil, capsInfo = nil, perfInfo = nil,
        svState = nil, svTarget = nil, svHP = nil, svKills = nil,
    }

    --========================================================
    -- PAGE BUILDERS
    --========================================================

    -- DASHBOARD
    mkPage("Dashboard", function(p)
        mkSection(p, "Quick Control")
        local grid = Instance.new("Frame")
        grid.Size = UDim2.new(1, ROW_W_OFFSET, 0, 152)
        grid.BackgroundTransparency = 1
        grid.LayoutOrder = nextO(p)
        grid.Parent = p
        local gl = Instance.new("UIGridLayout", grid)
        gl.CellSize = UDim2.new(0.5, -6, 0, 68)
        gl.CellPadding = UDim2.new(0, 12, 0, 12)
        gl.SortOrder = Enum.SortOrder.LayoutOrder

        R.svState  = mkStatCard(grid, "*", "State",  1)
        R.svTarget = mkStatCard(grid, "#", "Target", 2)
        R.svHP     = mkStatCard(grid, "+", "HP",     3)
        R.svKills  = mkStatCard(grid, "!", "Kills",  4)

        mkSection(p, "Actions")
        mkButton(p, ">", "Start Combat", "Enable farm loop", function()
            S.cbt = true
            print("[Dingus] combat ON")
        end)
        mkButton(p, "X", "Stop Combat", "Halt everything", function()
            S.cbt = false
            print("[Dingus] combat OFF")
        end, C.red)
        mkButton(p, "?", "Force Scan", "Dump mobs to F9", function()
            if Ctx.Atk and Ctx.Atk.forceScan then Ctx.Atk.forceScan() end
        end)
        mkSection(p, "Status")
        R.dashInfo = mkInfo(p, 140)
    end)

    -- FARM
    mkPage("Farm", function(p)
        mkSection(p, "Target Selection")
        mkSegment(p, "#", "Mob Category", "Normal / Boss / All",
            { "Normal", "Boss", "All" },
            function() return S.mobCategory or "All" end,
            function(v)
                S.mobCategory = v
                F.SynMobCategory = v
                if Ctx.Atk and Ctx.Atk.setCategory then
                    Ctx.Atk.setCategory(v)
                end
            end)
        mkDropdown(p, "+", "Region Filter", "Region lock",
            function()
                local opts = { "All" }
                for _, r in ipairs(L.bossRegions or {}) do
                    table.insert(opts, r.name)
                end
                return opts
            end,
            function() return S.regionFilter or "All" end,
            function(v)
                S.regionFilter = v
                F.SynRegionFilter = v
                if Ctx.Atk and Ctx.Atk.setRegion then
                    Ctx.Atk.setRegion(v)
                end
            end)
        mkDropdown(p, "#", "Target Mob", "Name filter",
            function()
                local opts = { "All", "All Bosses", "All Normal Mobs" }
                for _, b in ipairs(L.bosses or {}) do
                    table.insert(opts, b)
                end
                return opts
            end,
            function() return S.targetMob or "All" end,
            function(v)
                S.targetMob = v
                F.SynTargetMob = v
                if Ctx.Atk and Ctx.Atk.setTargetMob then
                    Ctx.Atk.setTargetMob(v)
                end
            end)
        mkSection(p, "Position Mode")
        mkSegment(p, "^", "Farm Mode", "Where to stand",
            { "Overhead", "Underground", "In Front", "Ground" },
            function() return F.SynSafeMode or "Overhead" end,
            function(v)
                F.SynSafeMode = v
                if Ctx.Atk and Ctx.Atk.setFarmMode then
                    Ctx.Atk.setFarmMode(v)
                end
            end)
        mkSlider(p, "#", "Height Offset", -15, 20,
            function() return F.SynHeightOffset or 3.8 end,
            function(v) F.SynHeightOffset = v end, "%.1f")
        mkSlider(p, "+", "Distance Offset", 0, 10,
            function() return F.SynDistance or 2 end,
            function(v) F.SynDistance = v end, "%.1f")
        mkSection(p, "Combat Tuning")
        mkSlider(p, ">", "M1 Interval", 0.10, 0.80,
            function() return F.SynM1Interval or 0.28 end,
            function(v) F.SynM1Interval = v end, "%.2f")
        mkToggle(p, "#", "Multi-Hit", "Chain M1s per tick", "SynMultiHit")
        mkSlider(p, "+", "Multi-Hit Count", 1, 6,
            function() return F.SynMultiHitCount or 3 end,
            function(v) F.SynMultiHitCount = math.floor(v) end, "%.0f")
        mkToggle(p, "!", "Auto Skills", "Fire skill rotation",
            "SynAutoSkills")
        mkToggle(p, "~", "Track Guard", "Stop old anim tracks",
            "SynTrackGuard")
        mkSection(p, "Automation")
        mkToggle(p, "<", "Target Lock", "Lock until death",
            "SynTargetLock")
        mkToggle(p, ">", "Auto Travel", "Teleport to region",
            "SynAutoTravel")
        mkSlider(p, "#", "Boss Rotation (s)", 5, 60,
            function() return F.SynBossRotationT or 15 end,
            function(v) F.SynBossRotationT = math.floor(v) end, "%.0f")
        mkSection(p, "Live State")
        R.farmInfo = mkInfo(p, 130)
    end)

    -- FACTION
    mkPage("Faction", function(p)
        mkSection(p, "Auto-Detect")
        mkToggle(p, "!", "Auto Target Faction",
            "Pick enemies based on your role", "FactionAuto",
            function(v)
                if Ctx.Faction and Ctx.Faction.setAuto then
                    Ctx.Faction.setAuto(v)
                end
            end)
        mkSegment(p, "#", "Role Override", "Manual pick or auto",
            { "auto", "slayer", "demon", "hybrid" },
            function() return F.FactionManual or "auto" end,
            function(v)
                F.FactionManual = v
                if Ctx.Faction and Ctx.Faction.setManual then
                    Ctx.Faction.setManual(v)
                end
            end)
        mkToggle(p, "+", "Include Neutral", "Bandits, civilians, mobs",
            "FactionIncludeNeutral",
            function(v)
                if Ctx.Faction and Ctx.Faction.setIncludeNeutral then
                    Ctx.Faction.setIncludeNeutral(v)
                end
            end)
        mkToggle(p, "*", "Hashira Priority", "Boost Upper Moons",
            "FactionPriorityUpper")
        mkSection(p, "Detection Status")
        R.facStatus = mkInfo(p, 130)
        mkSection(p, "Controls")
        mkButton(p, "#", "Force Re-detect", "Refresh role/rank now",
            function()
                if Ctx.Faction and Ctx.Faction.detect then
                    local fac, rank = Ctx.Faction.detect()
                    print(string.format(
                        "[Dingus][Faction] re-detected: %s / %s",
                        tostring(fac), tostring(rank)))
                end
            end)
        mkButton(p, ">", "List Current Enemies", "Match filter now",
            function()
                if Ctx.Faction and Ctx.Faction.getEnemyList then
                    local enemies = Ctx.Faction.getEnemyList()
                    print(string.format(
                        "[Dingus][Faction] %d enemies match filter",
                        #enemies))
                    for i = 1, math.min(#enemies, 15) do
                        local e = enemies[i]
                        print(string.format("  %-30s [%s] @%.0f",
                            e.name, e.faction, e.dist))
                    end
                end
            end)
        mkSection(p, "Live Enemy List")
        R.facList = mkInfo(p, 220)
    end)

    -- CHESTS
    mkPage("Chests", function(p)
        mkSection(p, "Master")
        mkToggle(p, "$", "Chest Collection", "Master switch",
            "ChestEnabled")
        mkToggle(p, "#", "Collect on Kill", "After kills", "ChestOnKill")
        mkToggle(p, "+", "Passive Sweep", "While idle", "ChestPassive")
        mkToggle(p, "!", "Auto Loot Drops", "Ground items", "ChestLootOn")
        mkToggle(p, "#", "Auto Chests", "Chest boxes", "ChestChestsOn")
        mkToggle(p, "*", "Auto Souls", "Demon souls", "ChestSoulsOn")
        mkSection(p, "Actions")
        mkButton(p, "#", "Scan Now", "Dump to F9", function()
            if Ctx.Chest and Ctx.Chest.dump then Ctx.Chest.dump() end
        end)
        mkButton(p, "X", "Reset Cooldowns", "Clear skip list", function()
            if Ctx.Chest and Ctx.Chest.resetCooldowns then
                Ctx.Chest.resetCooldowns()
            end
        end, C.red)
        mkSection(p, "Live Stats")
        R.chestStats = mkInfo(p, 150)
    end)

    -- QUESTS
    mkPage("Quests", function(p)
        mkSection(p, "Auto Quest")
        mkToggle(p, ">", "Auto Accept Quests", "NPC dialogue loop",
            "autoQuest",
            function(v)
                if Ctx.Quest and Ctx.Quest.setAutoQuest then
                    Ctx.Quest.setAutoQuest(v)
                end
            end)
        mkDropdown(p, "#", "Quest Mode", "Auto or specific",
            function()
                local opts = { "Auto Best Quest (By Level)" }
                for _, q in ipairs(L.quests or {}) do
                    if q.display then table.insert(opts, q.display) end
                end
                return opts
            end,
            function()
                return S.questMode or "Auto Best Quest (By Level)"
            end,
            function(v)
                S.questMode = v
                F.QuestMode = v
                if Ctx.Quest and Ctx.Quest.setQuestMode then
                    Ctx.Quest.setQuestMode(v)
                end
            end)
        mkSection(p, "Actions")
        mkButton(p, "#", "Force Accept", "Current selection", function()
            if Ctx.Quest and Ctx.Quest.forceAcceptQuest then
                local mode = S.questMode
                if mode and mode ~= "Auto Best Quest (By Level)" then
                    local ok, reason = Ctx.Quest.forceAcceptQuest(mode)
                    print("[Dingus][Quest] accept: " .. tostring(ok)
                        .. " (" .. tostring(reason) .. ")")
                end
            end
        end)
        mkButton(p, "X", "Abandon Active", "Drop current", function()
            if Ctx.Quest and Ctx.Quest.forceAbandon then
                Ctx.Quest.forceAbandon()
            end
        end, C.red)
        mkSection(p, "Crow Priority")
        mkToggle(p, "!", "Auto Crow Read", "Refresh priority", "crw")
        mkButton(p, "+", "Force Crow Read", "Read panel now", function()
            if Ctx.Quest and Ctx.Quest.forceCrowRead then
                Ctx.Quest.forceCrowRead()
            end
        end)
        mkSection(p, "Status")
        R.questInfo = mkInfo(p, 170)
    end)

    -- LOGS
    mkPage("Logs", function(p)
        local logFrame = Instance.new("Frame")
        logFrame.Size = UDim2.new(1, -SCW - 8, 1, -PAD * 2)
        logFrame.BackgroundColor3 = C.bgP
        logFrame.BorderSizePixel = 0
        logFrame.LayoutOrder = nextO(p)
        logFrame.Parent = p
        Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0, 11)
        local lScroll = Instance.new("ScrollingFrame")
        lScroll.Size = UDim2.new(1, -12, 1, -12)
        lScroll.Position = UDim2.new(0, 6, 0, 6)
        lScroll.BackgroundTransparency = 1
        lScroll.ScrollBarThickness = 8
        lScroll.ScrollBarImageColor3 = C.accent
        lScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        lScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        lScroll.Parent = logFrame
        local lLay = Instance.new("UIListLayout", lScroll)
        lLay.Padding = UDim.new(0, 3)
        lLay.SortOrder = Enum.SortOrder.LayoutOrder
    end)

    -- SETTINGS
    mkPage("Settings", function(p)
        mkSection(p, "Concealment")
        mkToggle(p, "#", "Concealed Parent", "gethui / CoreGui",
            "GuiConcealed")
        mkButton(p, "v", "Panic Hide", "Hide GUI now", function()
            gui.Parent = nil
        end, C.red)
        mkSection(p, "Config")
        mkButton(p, ">", "Save Config", "Persist to disk", function()
            local ok = F.save and F.save("default")
            print("[Dingus][Config] save: " .. tostring(ok))
        end)
        mkButton(p, "<", "Load Config", "Read from disk", function()
            if F.load then
                local ok, msg = F.load("default")
                print("[Dingus][Config] " .. tostring(msg))
            end
        end)
        mkButton(p, "X", "Reset Config", "Factory defaults", function()
            if F.reset then F.reset() end
        end, C.red)
        mkSection(p, "Diagnostics")
        R.runtimeInfo = mkInfo(p, 160)
        R.capsInfo = mkInfo(p, 200)
        R.perfInfo = mkInfo(p, 160)
    end)

    --========================================================
    -- MINIMIZE PILL
    --========================================================
    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0, 190, 0, 44)
    pill.Position = UDim2.new(0, 20, 0.5, -22)
    pill.BackgroundColor3 = C.bg
    pill.BorderSizePixel = 0
    pill.Active = true
    pill.Draggable = true
    pill.Visible = false
    pill.Parent = gui
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
    local pStroke = Instance.new("UIStroke", pill)
    pStroke.Color = C.accent
    pStroke.Thickness = 1.5
    local pDot = Instance.new("Frame")
    pDot.Size = UDim2.new(0, 8, 0, 8)
    pDot.Position = UDim2.new(0, 14, 0.5, -4)
    pDot.BackgroundColor3 = C.textM
    pDot.BorderSizePixel = 0
    pDot.Parent = pill
    Instance.new("UICorner", pDot).CornerRadius = UDim.new(1, 0)
    local pLbl = Instance.new("TextLabel")
    pLbl.Size = UDim2.new(1, -30, 1, 0)
    pLbl.Position = UDim2.new(0, 28, 0, 0)
    pLbl.BackgroundTransparency = 1
    pLbl.Text = "Dingus-Slayer"
    pLbl.TextColor3 = C.text
    pLbl.TextXAlignment = Enum.TextXAlignment.Left
    pLbl.Font = FB
    pLbl.TextSize = 12
    pLbl.Parent = pill
    local pBtn = Instance.new("TextButton")
    pBtn.Size = UDim2.new(1, 0, 1, 0)
    pBtn.BackgroundTransparency = 1
    pBtn.Text = ""
    pBtn.Parent = pill

    local minimized = false
    local function minimize()
        if minimized then return end
        minimized = true
        win.Visible = false
        pill.Visible = true
    end
    local function restore()
        if not minimized then return end
        minimized = false
        pill.Visible = false
        win.Visible = true
    end
    safeConnect(minB.MouseButton1Click, minimize)
    safeConnect(pBtn.MouseButton1Click, restore)

    --========================================================
    -- INITIAL PAGE
    --========================================================
    selectPage("Dashboard")

    --========================================================
    -- REFRESH — throttled per section
    --========================================================
    local cache = {}
    local nextTick = {
        header = 0,
        dash = 0,
        farm = 0,
        factionStatus = 0,
        factionList = 0,
        chest = 0,
        quest = 0,
        runtime = 0,
        perf = 0,
    }

    local function refreshHeader()
        if not R.svState then return end
        local st = S.cbtS or "-"
        if cache.st ~= st then
            cache.st = st
            safeSetText(R.svState, st)
            local col = C.textM
            if st == "STRIKE" or st == "PUNISH" then
                col = C.green
            elseif st == "RECOVER" or st == "RETREAT" then
                col = C.red
            elseif st == "SCAN" or st == "TELEPORT" then
                col = C.yellow
            elseif st == "LOOT_WAIT" then
                col = C.blue
            end
            safeSetColor(chipDot, "BackgroundColor3", col)
            safeSetText(chipText, st)
            safeSetColor(pulseDot, "BackgroundColor3",
                (st == "STRIKE") and C.green or C.textM)
            safeSetText(pulseText,
                S.cbt and ("farm: " .. st) or "farm: idle")
        end

        local h = U.hum()
        local hp = "?"
        if h then
            hp = string.format("%d/%d",
                math.floor(h.Health), math.floor(h.MaxHealth))
        end
        if cache.hp ~= hp then
            cache.hp = hp
            safeSetText(R.svHP, hp)
        end
        local kc = tostring(S.bKll or 0)
        if cache.kc ~= kc then
            cache.kc = kc
            safeSetText(R.svKills, kc)
        end

        if Ctx.Faction and Ctx.Faction.stats then
            local fs = Ctx.Faction.stats()
            local fstr = tostring(fs.faction)
                .. (fs.isHashira and "*" or "")
            if cache.fstr ~= fstr then
                cache.fstr = fstr
                safeSetText(facText, "faction: " .. fstr)
                local fcol = C.textD
                if fs.faction == "demon" then fcol = C.purple
                elseif fs.faction == "slayer" then fcol = C.blue
                elseif fs.faction == "hybrid" then fcol = C.yellow
                end
                safeSetColor(facText, "TextColor3", fcol)
            end
        end
    end

    local function refreshDashboard()
        if not R.dashInfo then return end
        local tgt = "none"
        if S.tgt and S.tgt.ch then tgt = S.tgt.ch.Name end
        if tgt == "none" and S.lockedTarget then
            tgt = S.lockedTarget.Name or "none"
        end
        if cache.tgt ~= tgt then
            cache.tgt = tgt
            safeSetText(R.svTarget, tgt)
        end
        local h = U.hum()
        local hp = h and string.format("%d/%d",
            math.floor(h.Health), math.floor(h.MaxHealth)) or "?"
        local di = "  target: " .. tostring(tgt)
            .. "\n  hp: " .. hp
            .. "\n  kills: " .. tostring(S.bKll or 0)
            .. "  fps: " .. string.format("%.0f", S.fps or 60)
            .. "\n  mode: " .. tostring(F.SynSafeMode)
            .. "  cat: " .. tostring(S.mobCategory)
        if cache.di ~= di then
            cache.di = di
            safeSetText(R.dashInfo, di)
        end
    end

    local function refreshFarm()
        if not R.farmInfo then return end
        local t = Ctx.Atk and Ctx.Atk.telemetry
            and Ctx.Atk.telemetry() or {}
        local fi = "  state: " .. tostring(t.state)
            .. "\n  hits: " .. tostring(t.hits or 0)
            .. "  kills: " .. tostring(t.kills or 0)
            .. "\n  identity: " .. tostring(t.identityOk)
            .. "  IH: " .. tostring(t.inputHandler)
            .. "\n  SP: " .. tostring(t.skillProvider)
        if cache.fi ~= fi then
            cache.fi = fi
            safeSetText(R.farmInfo, fi)
        end
    end

    local function refreshFactionStatus()
        if not R.facStatus or not Ctx.Faction then return end
        local fs = Ctx.Faction.stats()
        local tgts = fs.targets and table.concat(fs.targets, ", ") or "none"
        local s = "  race: " .. tostring(fs.faction)
            .. "\n  rank: " .. tostring(fs.rank)
            .. "\n  hashira: " .. tostring(fs.isHashira)
            .. "\n  auto: " .. tostring(fs.auto)
            .. "  manual: " .. tostring(fs.manual)
            .. "\n  targeting: " .. tgts
            .. "\n  detections: " .. tostring(fs.detectCount or 0)
            .. "  errors: " .. tostring(fs.detectErrors or 0)
        if cache.fsi ~= s then
            cache.fsi = s
            safeSetText(R.facStatus, s)
        end
    end

    local function refreshFactionList()
        if not R.facList or not Ctx.Faction
           or not Ctx.Faction.getEnemyList then return end
        local enemies = Ctx.Faction.getEnemyList()
        local lines = {}
        if #enemies == 0 then
            lines[1] = "  (no matching enemies in range)"
        else
            lines[1] = "  " .. tostring(#enemies) .. " matching:"
            local n = math.min(#enemies, 8)
            for i = 1, n do
                local e = enemies[i]
                local fac = (e.faction or "?"):sub(1, 3)
                local name = (e.name or "?"):sub(1, 24)
                lines[#lines + 1] = "  [" .. fac .. "] " .. name
                    .. " @" .. string.format("%.0f", e.dist or 0)
            end
        end
        local fl = table.concat(lines, "\n")
        if cache.fl ~= fl then
            cache.fl = fl
            safeSetText(R.facList, fl)
        end
    end

    local function refreshChest()
        if not R.chestStats then return end
        if not (Ctx.Chest and Ctx.Chest.stats) then return end
        local cs = Ctx.Chest.stats()
        local ci = "  enabled: " .. tostring(cs.enabled)
            .. "  loot: " .. tostring(cs.loot)
            .. "\n  chests: " .. tostring(cs.chests)
            .. "  souls: " .. tostring(cs.souls)
            .. "\n  collected: " .. tostring(cs.collected or 0)
            .. "  loot: " .. tostring(cs.lootCollected or 0)
            .. "\n  failed: " .. tostring(cs.failed or 0)
            .. "  running: " .. tostring(cs.running)
        if cache.ci ~= ci then
            cache.ci = ci
            safeSetText(R.chestStats, ci)
        end
    end

    local function refreshQuest()
        if not R.questInfo then return end
        if not (Ctx.Quest and Ctx.Quest.stats) then return end
        local qs = Ctx.Quest.stats()
        local qi = "  level: " .. tostring(qs.level or 0)
            .. "  race: " .. tostring(qs.race)
            .. "\n  mode: " .. tostring(qs.questMode)
            .. "\n  auto: " .. tostring(qs.autoQuest)
            .. "  failures: " .. tostring(qs.failures or 0)
            .. "\n  active: " .. tostring(qs.activeQuestName)
            .. "\n  priority: " .. tostring(qs.priority)
        if cache.qi ~= qi then
            cache.qi = qi
            safeSetText(R.questInfo, qi)
        end
    end

    local function refreshRuntime()
        if R.runtimeInfo then
            local ri = "  platform: " .. tostring(U.Platform)
                .. "\n  executor: " .. tostring(U.Executor)
                .. "\n  input: " .. tostring(U.InputBackend)
                .. "  mouse: " .. tostring(U.MouseBackend)
                .. "\n  http: " .. tostring(U.HttpMode)
                .. "  file: " .. tostring(U.Caps.file)
            if cache.ri ~= ri then
                cache.ri = ri
                safeSetText(R.runtimeInfo, ri)
            end
        end
        if R.capsInfo then
            local cap = "  proximity: " .. tostring(U.Caps.proximity)
                .. "  click: " .. tostring(U.Caps.click)
                .. "\n  touch: " .. tostring(U.Caps.touch)
                .. "  gethui: " .. tostring(U.Caps.gethui)
                .. "\n  firesignal: " .. tostring(U.Caps.firesignal)
                .. "  headers: " .. tostring(U.Caps.httpHeaders)
            if cache.cap ~= cap then
                cache.cap = cap
                safeSetText(R.capsInfo, cap)
            end
        end
    end

    local function refreshPerf()
        if not R.perfInfo or not Ctx.perf then return end
        local p = Ctx.perf()
        local pi = string.format(
            "  fps: %.1f  stress: %.2f\n  backoff: %.2fx  budget: %.1fms",
            p.avg_fps or 60, p.stress or 0,
            p.backoff or 1, (p.budget_used or 0) * 1000)
        if cache.pi ~= pi then
            cache.pi = pi
            safeSetText(R.perfInfo, pi)
        end
    end

    --========================================================
    -- REFRESH LOOP — per-section throttling
    --========================================================
    task.spawn(function()
        while S.run do
            local now = os.clock()
            local visible = gui.Parent ~= nil and not minimized

            if visible and S.boot then
                if now >= nextTick.header then
                    nextTick.header = now + 0.20
                    pcall(refreshHeader)
                end
                if currentPage == "Dashboard"
                   and now >= nextTick.dash then
                    nextTick.dash = now + 0.30
                    pcall(refreshDashboard)
                end
                if currentPage == "Farm" and now >= nextTick.farm then
                    nextTick.farm = now + 0.35
                    pcall(refreshFarm)
                end
                if currentPage == "Faction" then
                    if now >= nextTick.factionStatus then
                        nextTick.factionStatus = now + 0.50
                        pcall(refreshFactionStatus)
                    end
                    if now >= nextTick.factionList then
                        nextTick.factionList = now + 0.80
                        pcall(refreshFactionList)
                    end
                end
                if currentPage == "Chests" and now >= nextTick.chest then
                    nextTick.chest = now + 1.00
                    pcall(refreshChest)
                end
                if currentPage == "Quests" and now >= nextTick.quest then
                    nextTick.quest = now + 0.60
                    pcall(refreshQuest)
                end
                if currentPage == "Settings"
                   and now >= nextTick.runtime then
                    nextTick.runtime = now + 1.50
                    pcall(refreshRuntime)
                    if now >= nextTick.perf then
                        nextTick.perf = now + 1.00
                        pcall(refreshPerf)
                    end
                end
            end

            -- Loop tick — short enough to keep UI responsive, long
            -- enough to not burn frames when idle
            task.wait(visible and 0.15 or 0.5)
        end
    end)

    --========================================================
    -- INPUT
    --========================================================
    if UIS then
        safeConnect(UIS.InputBegan, function(inp, gp)
            if gp then return end
            if inp.KeyCode == Enum.KeyCode.RightShift then
                if minimized then restore() else minimize() end
                return
            end
            if F.GuiPanicHide
               and inp.KeyCode == Enum.KeyCode.Backspace
               and UIS:IsKeyDown(Enum.KeyCode.RightControl) then
                gui.Parent = nil
            end
        end)
    end

    safeConnect(closeB.MouseButton1Click, function()
        closeDropdown()
        pcall(function() gui:Destroy() end)
    end)

    --========================================================
    -- PUBLIC HANDLE
    --========================================================
    G.gui = gui
    G.win = win
    G.minimize = minimize
    G.restore = restore
    G.parent = parent
    G.parentKind = parentKind
    G.PAGES = PAGES
    G.NAV = NAV
    G.closeDropdown = closeDropdown

    print(string.format(
        "[Dingus][gui] v42 - %s - parent=%s - vp=%dx%d - lazy=on",
        U.Platform, parentKind, vp.X, vp.Y))
end

return G
