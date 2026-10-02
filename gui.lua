-- Dingus-Slayer · gui.lua v40
-- Full rebuild. Widget factory pattern. Real dropdowns. Faction tab.
-- Compact status header. Auto-farm sidebar. 7 tabs.

local G = {}

function G.init(Ctx)
    local U, F, S, L = Ctx.Util, Ctx.Cfg, Ctx.St, Ctx.Lists
    local TW = U.TS or game:GetService("TweenService")
    local UIS = U.UIS

    F.GuiConcealed = F.GuiConcealed ~= false
    F.GuiPanicHide = F.GuiPanicHide ~= false

    local parent, parentKind = U.resolveGuiParent()
    local guiName = "_c" .. string.format("%06x", math.random(0, 0xFFFFFF))
    local old = parent:FindFirstChild("DingusUI")
    if old then pcall(function() old:Destroy() end) end

    --========================================================
    -- DEVICE GEOMETRY
    --========================================================
    local isM = U.IsMobile
    local vp  = UIS and UIS:GetViewportSize() or Vector2.new(1280, 720)
    local WW  = isM and math.min(vp.X - 16, 560) or 1000
    local WH  = isM and math.min(vp.Y - 32, 680) or 720
    local HH  = isM and 46 or 52
    local SW  = isM and 148 or 208
    local PAD = isM and 10 or 14
    local RG  = 8
    local SCW = isM and 5 or 8
    local TGT = 44

    --========================================================
    -- PALETTE
    --========================================================
    local C = {
        bg=Color3.fromRGB(11,11,15), bgH=Color3.fromRGB(15,15,21),
        bgS=Color3.fromRGB(9,9,13), bgP=Color3.fromRGB(18,18,24),
        row=Color3.fromRGB(24,24,32), rowH=Color3.fromRGB(34,34,44),
        iconBg=Color3.fromRGB(44,24,24),
        navA=Color3.fromRGB(44,26,26), navH=Color3.fromRGB(22,22,30),
        trackOff=Color3.fromRGB(52,52,66), border=Color3.fromRGB(42,34,36),
        accent=Color3.fromRGB(220,90,70), accentD=Color3.fromRGB(150,60,50),
        green=Color3.fromRGB(80,200,120), red=Color3.fromRGB(220,70,80),
        blue=Color3.fromRGB(80,140,220), purple=Color3.fromRGB(160,100,220),
        yellow=Color3.fromRGB(230,190,80),
        text=Color3.fromRGB(232,232,240), textD=Color3.fromRGB(160,165,180),
        textM=Color3.fromRGB(110,115,135),
        dropdown=Color3.fromRGB(38,38,48),
        overlay=Color3.fromRGB(0,0,0),
    }
    local FB, FR, FC = Enum.Font.GothamBold, Enum.Font.Gotham, Enum.Font.Code

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
    win.Position = UDim2.new(0.5, -WW/2, 0.5, -WH/2)
    win.BackgroundColor3 = C.bg
    win.BorderSizePixel = 0
    win.Active = true
    win.Draggable = true
    win.ClipsDescendants = true
    win.Parent = gui
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 14)
    local ws = Instance.new("UIStroke", win)
    ws.Color = C.border; ws.Thickness = 1; ws.Transparency = 0.15

    --========================================================
    -- HEADER
    --========================================================
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, HH)
    header.BackgroundColor3 = C.bgH
    header.BorderSizePixel = 0
    header.Parent = win
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)

    -- brand
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

    -- live status chip
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

    -- faction chip
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

    -- window controls
    local function mkCtrl(g, x, col)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, TGT, 0, TGT)
        b.Position = UDim2.new(1, x, 0.5, -TGT/2)
        b.BackgroundColor3 = col
        b.BackgroundTransparency = 1
        b.BorderSizePixel = 0
        b.Text = g
        b.TextColor3 = C.textD
        b.Font = FB
        b.TextSize = 16
        b.AutoButtonColor = false
        b.Parent = header
        Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
        b.MouseEnter:Connect(function()
            TW:Create(b, TweenInfo.new(0.12), {
                BackgroundTransparency=0, BackgroundColor3=col, TextColor3=C.text
            }):Play()
        end)
        b.MouseLeave:Connect(function()
            TW:Create(b, TweenInfo.new(0.12), {
                BackgroundTransparency=1, TextColor3=C.textD
            }):Play()
        end)
        return b
    end
    local closeB = mkCtrl("✕", -TGT-8, C.red)
    local minB   = mkCtrl("–", -TGT*2-14, Color3.fromRGB(60,60,75))

    --========================================================
    -- SIDEBAR NAV
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

    -- auto-farm indicator at bottom of sidebar
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

    --========================================================
    -- CONTENT AREA
    --========================================================
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -SW, 1, -HH)
    content.Position = UDim2.new(0, SW, 0, HH)
    content.BackgroundColor3 = C.bg
    content.BorderSizePixel = 0
    content.ClipsDescendants = true
    content.Parent = win

    local counters = {}
    local function nextO(p) counters[p] = (counters[p] or 0) + 1; return counters[p] end

    --========================================================
    -- WIDGET LIBRARY
    --========================================================

    -- Switch (iOS-style toggle)
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
        k.Position = init and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 3, 0.5, -10)
        k.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
        k.BorderSizePixel = 0
        k.Parent = t
        Instance.new("UICorner", k).CornerRadius = UDim.new(1, 0)
        local st = init
        local function set(v)
            st = v
            TW:Create(t, TweenInfo.new(0.18), {
                BackgroundColor3 = st and C.accent or C.trackOff
            }):Play()
            TW:Create(k, TweenInfo.new(0.18), {
                Position = st and UDim2.new(1, -22, 0.5, -10)
                    or UDim2.new(0, 3, 0.5, -10)
            }):Play()
            if cb then pcall(cb, st) end
        end
        t.MouseButton1Click:Connect(function() set(not st) end)
        return t, set
    end

    -- Row base
    local function mkRow(p, h)
        local r = Instance.new("Frame")
        r.Size = UDim2.new(1, -SCW - 4, 0, h or 62)
        r.BackgroundColor3 = C.row
        r.BorderSizePixel = 0
        r.LayoutOrder = nextO(p)
        r.Active = true
        r.Parent = p
        Instance.new("UICorner", r).CornerRadius = UDim.new(0, 11)
        return r
    end

    local function mkIcon(par, g, tint)
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
        l.Text = g
        l.TextColor3 = tint or C.accent
        l.Font = FB
        l.TextSize = 17
        l.Parent = b
    end

    local function mkTitle(r, t, d)
        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -110, 0, 18)
        title.Position = UDim2.new(0, 58, 0, 10)
        title.BackgroundTransparency = 1
        title.Text = t
        title.TextColor3 = C.text
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Font = FB
        title.TextSize = 13
        title.TextTruncate = Enum.TextTruncate.AtEnd
        title.Parent = r
        if d and d ~= "" then
            local desc = Instance.new("TextLabel")
            desc.Size = UDim2.new(1, -110, 0, 14)
            desc.Position = UDim2.new(0, 58, 0, 28)
            desc.BackgroundTransparency = 1
            desc.Text = d
            desc.TextColor3 = C.textM
            desc.TextXAlignment = Enum.TextXAlignment.Left
            desc.Font = FR
            desc.TextSize = 11
            desc.TextTruncate = Enum.TextTruncate.AtEnd
            desc.Parent = r
        end
    end

    -- Toggle
    local function mkToggle(p, g, t, d, key, cb)
        local r = mkRow(p, 62)
        mkIcon(r, g)
        mkTitle(r, t, d)
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

    -- Button
    local function mkButton(p, g, t, d, cb, tint)
        local r = mkRow(p, 62)
        mkIcon(r, g, tint)
        mkTitle(r, t, d)
        local chev = Instance.new("TextLabel")
        chev.Size = UDim2.new(0, 20, 0, 24)
        chev.Position = UDim2.new(1, -SCW-24, 0.5, -12)
        chev.BackgroundTransparency = 1
        chev.Text = "›"
        chev.TextColor3 = tint or C.textM
        chev.Font = FB
        chev.TextSize = 20
        chev.Parent = r
        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, 0, 1, 0)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.Parent = r
        hit.MouseButton1Click:Connect(function()
            local ok, err = pcall(cb)
            if not ok then print("[Dingus][btn] " .. t .. ": " .. tostring(err)) end
        end)
        return r
    end

    -- Info block
    local function mkInfo(p, h)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -SCW-4, 0, h or 100)
        l.BackgroundColor3 = C.row
        l.BorderSizePixel = 0
        l.Text = "—"
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

    -- Section header
    local function mkSection(p, text)
        local h = Instance.new("TextLabel")
        h.Size = UDim2.new(1, -SCW-4, 0, 22)
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

    -- Slider
    local function mkSlider(p, g, t, mn, mx, getter, setter, fmt)
        fmt = fmt or "%.1f"
        local r = mkRow(p, 70)
        mkIcon(r, g)
        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, -180, 0, 18)
        tl.Position = UDim2.new(0, 58, 0, 10)
        tl.BackgroundTransparency = 1
        tl.Text = t
        tl.TextColor3 = C.text
        tl.TextXAlignment = Enum.TextXAlignment.Left
        tl.Font = FB
        tl.TextSize = 13
        tl.Parent = r
        local vl = Instance.new("TextLabel")
        vl.Size = UDim2.new(0, 80, 0, 18)
        vl.Position = UDim2.new(1, -SCW-6, 0, 10)
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
        local drag = false
        hit.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
               or i.UserInputType == Enum.UserInputType.Touch then
                drag = true
            end
        end)
        hit.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
               or i.UserInputType == Enum.UserInputType.Touch then
                drag = false
            end
        end)
        UIS.InputChanged:Connect(function(i)
            if not drag then return end
            if i.UserInputType == Enum.UserInputType.MouseMovement
               or i.UserInputType == Enum.UserInputType.Touch then
                local mx2 = UIS:GetMouseLocation().X
                local bx = bar.AbsolutePosition.X
                local bw = bar.AbsoluteSize.X
                if bw > 0 then
                    local pp = math.clamp((mx2 - bx) / bw, 0, 1)
                    local val = mn + (mx - mn) * pp
                    setter(val)
                    vl.Text = string.format(fmt, val)
                    fill.Size = UDim2.new(pp, 0, 1, 0)
                    knob.Position = UDim2.new(pp, -7, 0.5, -7)
                end
            end
        end)
    end

    -- Real dropdown (popup list)
    local function mkDropdown(p, g, t, d, optionsFn, getter, setter)
        local r = mkRow(p, 62)
        mkIcon(r, g)
        mkTitle(r, t, d)
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
        local arrow = Instance.new("TextLabel")
        arrow.Size = UDim2.new(0, 20, 1, 0)
        arrow.Position = UDim2.new(1, -22, 0, 0)
        arrow.BackgroundTransparency = 1
        arrow.Text = "▾"
        arrow.TextColor3 = C.textM
        arrow.Font = FB
        arrow.TextSize = 12
        arrow.Parent = btn

        local function refresh()
            btn.Text = "  " .. tostring(getter())
        end
        refresh()

        btn.MouseButton1Click:Connect(function()
            local options = optionsFn()
            -- Build overlay
            local overlay = Instance.new("TextButton")
            overlay.Size = UDim2.new(1, 0, 1, 0)
            overlay.BackgroundColor3 = C.overlay
            overlay.BackgroundTransparency = 0.55
            overlay.Text = ""
            overlay.ZIndex = 100
            overlay.Parent = gui
            local list = Instance.new("ScrollingFrame")
            list.Size = UDim2.new(0, math.min(300, WW - 60), 0, math.min(400, WH - 100))
            list.Position = UDim2.new(0.5, -math.min(300, WW - 60)/2, 0.5,
                -math.min(400, WH - 100)/2)
            list.BackgroundColor3 = C.bgH
            list.BorderSizePixel = 0
            list.CanvasSize = UDim2.new(0, 0, 0, 0)
            list.AutomaticCanvasSize = Enum.AutomaticSize.Y
            list.ScrollBarThickness = 6
            list.ScrollBarImageColor3 = C.accent
            list.ZIndex = 101
            list.Parent = gui
            Instance.new("UICorner", list).CornerRadius = UDim.new(0, 12)
            local ls = Instance.new("UIStroke", list)
            ls.Color = C.accent; ls.Thickness = 1
            local lLay = Instance.new("UIListLayout", list)
            lLay.Padding = UDim.new(0, 2)
            lLay.SortOrder = Enum.SortOrder.LayoutOrder
            local lp = Instance.new("UIPadding", list)
            lp.PaddingTop = UDim.new(0, 8)
            lp.PaddingBottom = UDim.new(0, 8)
            lp.PaddingLeft = UDim.new(0, 8)
            lp.PaddingRight = UDim.new(0, 8)

            local closed = false
            local function close()
                if closed then return end
                closed = true
                overlay:Destroy()
                list:Destroy()
            end

            overlay.MouseButton1Click:Connect(close)

            local current = tostring(getter())
            for _, opt in ipairs(options) do
                local ob = Instance.new("TextButton")
                ob.Size = UDim2.new(1, -8, 0, 36)
                ob.BackgroundColor3 = (opt == current) and C.accent or C.row
                ob.BorderSizePixel = 0
                ob.Text = "  " .. tostring(opt)
                ob.TextColor3 = (opt == current) and C.text or C.textD
                ob.TextXAlignment = Enum.TextXAlignment.Left
                ob.Font = FB
                ob.TextSize = 13
                ob.AutoButtonColor = false
                ob.LayoutOrder = nextO(list)
                ob.ZIndex = 102
                ob.Parent = list
                Instance.new("UICorner", ob).CornerRadius = UDim.new(0, 8)
                ob.MouseEnter:Connect(function()
                    ob.BackgroundColor3 = C.rowH
                end)
                ob.MouseLeave:Connect(function()
                    ob.BackgroundColor3 = (opt == current) and C.accent or C.row
                end)
                ob.MouseButton1Click:Connect(function()
                    pcall(setter, opt)
                    refresh()
                    close()
                end)
            end
        end)
        return r
    end

    -- Segmented control (2-5 options)
    local function mkSegment(p, g, t, d, options, getter, setter)
        local r = mkRow(p, 62)
        mkIcon(r, g)
        mkTitle(r, t, d)
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
            for opt, btn in pairs(buttons) do
                btn.BackgroundColor3 = (opt == current) and C.accent or C.dropdown
                btn.TextColor3 = (opt == current) and C.text or C.textD
            end
            pcall(setter, v)
        end
        for i, opt in ipairs(options) do
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1 / #options, -2, 1, -4)
            b.BackgroundColor3 = (opt == current) and C.accent or C.dropdown
            b.BorderSizePixel = 0
            b.Text = tostring(opt)
            b.TextColor3 = (opt == current) and C.text or C.textD
            b.Font = FB
            b.TextSize = 11
            b.AutoButtonColor = false
            b.LayoutOrder = i
            b.Parent = holder
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
            b.MouseButton1Click:Connect(function() set(opt) end)
            buttons[opt] = b
        end
        return r
    end

    -- Stat card (for dashboard grid)
    local function mkStatCard(p, g, label, getter, order)
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
        icon.Text = g
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
        v.Text = "—"
        v.TextColor3 = C.text
        v.TextXAlignment = Enum.TextXAlignment.Left
        v.Font = FB
        v.TextSize = 16
        v.TextTruncate = Enum.TextTruncate.AtEnd
        v.Parent = c
        return v
    end

    --========================================================
    -- PAGES
    --========================================================
    local PAGES, NAV = {}, {}

    local function mkPage(name)
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
        return p
    end

    local function selectPage(name)
        for n, p in pairs(PAGES) do p.Visible = (n == name) end
        for n, e in pairs(NAV) do e.setActive(n == name) end
    end

    local function mkNav(g, lbl, name, order)
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
        ico.Text = g
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
        it.MouseEnter:Connect(function()
            if not active then
                it.BackgroundTransparency = 0
                it.BackgroundColor3 = C.navH
            end
        end)
        it.MouseLeave:Connect(function()
            if not active then it.BackgroundTransparency = 1 end
        end)
        it.MouseButton1Click:Connect(function() selectPage(name) end)
        NAV[name] = { item = it, setActive = setActive }
    end

    mkNav("◈", "Dashboard", "Dashboard", 1)
    mkNav("◆", "Farm",      "Farm",      2)
    mkNav("⚔", "Faction",   "Faction",   3)
    mkNav("◰", "Chests",    "Chests",    4)
    mkNav("✦", "Quests",    "Quests",    5)
    mkNav("≡", "Logs",      "Logs",      6)
    mkNav("⚙", "Settings",  "Settings",  7)

    --========================================================
    -- DASHBOARD
    --========================================================
    local pDash = mkPage("Dashboard")
    mkSection(pDash, "Quick Control")

    local grid = Instance.new("Frame")
    grid.Size = UDim2.new(1, -SCW - 4, 0, 152)
    grid.BackgroundTransparency = 1
    grid.LayoutOrder = nextO(pDash)
    grid.Parent = pDash
    local gl = Instance.new("UIGridLayout", grid)
    gl.CellSize = UDim2.new(0.5, -6, 0, 68)
    gl.CellPadding = UDim2.new(0, 12, 0, 12)
    gl.SortOrder = Enum.SortOrder.LayoutOrder

    local svState = mkStatCard(grid, "◈", "State", nil, 1)
    local svTarget = mkStatCard(grid, "◆", "Target", nil, 2)
    local svHP = mkStatCard(grid, "◉", "HP", nil, 3)
    local svKills = mkStatCard(grid, "✦", "Kills", nil, 4)

    mkSection(pDash, "Actions")
    mkButton(pDash, "▶", "Start Combat", "Enable farm loop", function()
        S.cbt = true
        print("[Dingus] combat ON")
    end)
    mkButton(pDash, "■", "Stop Combat", "Halt everything", function()
        S.cbt = false
        print("[Dingus] combat OFF")
    end, C.red)
    mkButton(pDash, "◎", "Force Scan", "Dump mobs to F9", function()
        if Ctx.Atk and Ctx.Atk.forceScan then Ctx.Atk.forceScan() end
    end)
    mkSection(pDash, "Status")
    local dashInfo = mkInfo(pDash, 140)

    --========================================================
    -- FARM
    --========================================================
    local pFarm = mkPage("Farm")
    mkSection(pFarm, "Target Selection")
    mkSegment(pFarm, "◈", "Mob Category", "Normal / Boss / All",
        { "Normal", "Boss", "All" },
        function() return S.mobCategory or "All" end,
        function(v)
            S.mobCategory = v
            F.SynMobCategory = v
            if Ctx.Atk and Ctx.Atk.setCategory then Ctx.Atk.setCategory(v) end
        end)
    mkDropdown(pFarm, "◉", "Region Filter", "Region lock",
        function()
            local opts = { "All" }
            for _, r in ipairs(L.bossRegions) do table.insert(opts, r.name) end
            return opts
        end,
        function() return S.regionFilter or "All" end,
        function(v)
            S.regionFilter = v
            F.SynRegionFilter = v
            if Ctx.Atk and Ctx.Atk.setRegion then Ctx.Atk.setRegion(v) end
        end)
    mkDropdown(pFarm, "◆", "Target Mob", "Name filter",
        function()
            local opts = { "All", "All Bosses", "All Normal Mobs" }
            for _, b in ipairs(L.bosses) do table.insert(opts, b) end
            return opts
        end,
        function() return S.targetMob or "All" end,
        function(v)
            S.targetMob = v
            F.SynTargetMob = v
            if Ctx.Atk and Ctx.Atk.setTargetMob then Ctx.Atk.setTargetMob(v) end
        end)
    mkSection(pFarm, "Position Mode")
    mkSegment(pFarm, "▲", "Farm Mode", "Where to stand",
        { "Overhead", "Underground", "In Front", "Ground" },
        function() return F.SynSafeMode or "Overhead" end,
        function(v)
            F.SynSafeMode = v
            if Ctx.Atk and Ctx.Atk.setFarmMode then Ctx.Atk.setFarmMode(v) end
        end)
    mkSlider(pFarm, "◈", "Height Offset", -15, 20,
        function() return F.SynHeightOffset or 3.8 end,
        function(v) F.SynHeightOffset = v end, "%.1f")
    mkSlider(pFarm, "◆", "Distance Offset", 0, 10,
        function() return F.SynDistance or 2 end,
        function(v) F.SynDistance = v end, "%.1f")
    mkSection(pFarm, "Combat Tuning")
    mkSlider(pFarm, "▶", "M1 Interval", 0.10, 0.80,
        function() return F.SynM1Interval or 0.28 end,
        function(v) F.SynM1Interval = v end, "%.2f")
    mkToggle(pFarm, "◆", "Multi-Hit", "Chain M1s per tick", "SynMultiHit")
    mkSlider(pFarm, "◉", "Multi-Hit Count", 1, 6,
        function() return F.SynMultiHitCount or 3 end,
        function(v) F.SynMultiHitCount = math.floor(v) end, "%.0f")
    mkToggle(pFarm, "✦", "Auto Skills", "Fire skill rotation", "SynAutoSkills")
    mkToggle(pFarm, "◇", "Track Guard", "Stop old anim tracks", "SynTrackGuard")
    mkSection(pFarm, "Automation")
    mkToggle(pFarm, "◀", "Target Lock", "Lock until death", "SynTargetLock")
    mkToggle(pFarm, "▶", "Auto Travel", "Teleport to region", "SynAutoTravel")
    mkSlider(pFarm, "◆", "Boss Rotation (s)", 5, 60,
        function() return F.SynBossRotationT or 15 end,
        function(v) F.SynBossRotationT = math.floor(v) end, "%.0f")
    mkSection(pFarm, "Live State")
    local farmInfo = mkInfo(pFarm, 130)

    --========================================================
    -- FACTION (NEW)
    --========================================================
    local pFac = mkPage("Faction")
    mkSection(pFac, "Auto-Detect")
    mkToggle(pFac, "⚔", "Auto Target Faction", "Pick enemies based on your role", "FactionAuto", function(v)
        if Ctx.Faction and Ctx.Faction.setAuto then Ctx.Faction.setAuto(v) end
    end)
    mkSegment(pFac, "◈", "Role Override", "Manual pick or auto",
        { "auto", "slayer", "demon", "hybrid" },
        function() return F.FactionManual or "auto" end,
        function(v)
            F.FactionManual = v
            if Ctx.Faction and Ctx.Faction.setManual then Ctx.Faction.setManual(v) end
        end)
    mkToggle(pFac, "◉", "Include Neutral", "Bandits, civilians, mobs", "FactionIncludeNeutral", function(v)
        if Ctx.Faction and Ctx.Faction.setIncludeNeutral then
            Ctx.Faction.setIncludeNeutral(v)
        end
    end)
    mkToggle(pFac, "★", "Hashira Priority", "Boost Upper Moons", "FactionPriorityUpper")
    mkSection(pFac, "Detection Status")
    local facStatus = mkInfo(pFac, 130)
    mkSection(pFac, "Controls")
    mkButton(pFac, "◈", "Force Re-detect", "Refresh role/rank now", function()
        if Ctx.Faction and Ctx.Faction.detect then
            local fac, rank = Ctx.Faction.detect()
            print(string.format("[Dingus][Faction] re-detected: %s / %s",
                tostring(fac), tostring(rank)))
        end
    end)
    mkButton(pFac, "▶", "List Current Enemies", "Match filter now", function()
        if Ctx.Faction and Ctx.Faction.getEnemyList then
            local enemies = Ctx.Faction.getEnemyList()
            print(string.format("[Dingus][Faction] %d enemies match filter", #enemies))
            for i = 1, math.min(#enemies, 15) do
                local e = enemies[i]
                print(string.format("  %-30s [%s] @%.0f",
                    e.name, e.faction, e.dist))
            end
        end
    end)
    mkSection(pFac, "Live Enemy List")
    local facList = mkInfo(pFac, 220)

    --========================================================
    -- CHESTS
    --========================================================
    local pChest = mkPage("Chests")
    mkSection(pChest, "Master")
    mkToggle(pChest, "◰", "Chest Collection", "Master switch", "ChestEnabled")
    mkToggle(pChest, "◆", "Collect on Kill", "After kills", "ChestOnKill")
    mkToggle(pChest, "◎", "Passive Sweep", "While idle", "ChestPassive")
    mkToggle(pChest, "✦", "Auto Loot Drops", "Ground items", "ChestLootOn")
    mkToggle(pChest, "◆", "Auto Chests", "Chest boxes", "ChestChestsOn")
    mkToggle(pChest, "◉", "Auto Souls", "Demon souls", "ChestSoulsOn")
    mkSection(pChest, "Actions")
    mkButton(pChest, "◈", "Scan Now", "Dump to F9", function()
        if Ctx.Chest and Ctx.Chest.dump then Ctx.Chest.dump() end
    end)
    mkButton(pChest, "✕", "Reset Cooldowns", "Clear skip list", function()
        if Ctx.Chest and Ctx.Chest.resetCooldowns then
            Ctx.Chest.resetCooldowns()
        end
    end, C.red)
    mkSection(pChest, "Live Stats")
    local chestStats = mkInfo(pChest, 150)

    --========================================================
    -- QUESTS
    --========================================================
    local pQuest = mkPage("Quests")
    mkSection(pQuest, "Auto Quest")
    mkToggle(pQuest, "▶", "Auto Accept Quests", "NPC dialogue loop", "autoQuest", function(v)
        if Ctx.Quest and Ctx.Quest.setAutoQuest then Ctx.Quest.setAutoQuest(v) end
    end)
    mkDropdown(pQuest, "◆", "Quest Mode", "Auto or specific",
        function()
            local opts = { "Auto Best Quest (By Level)" }
            for _, q in ipairs(L.quests) do
                if q.display then table.insert(opts, q.display) end
            end
            return opts
        end,
        function() return S.questMode or "Auto Best Quest (By Level)" end,
        function(v)
            S.questMode = v
            F.QuestMode = v
            if Ctx.Quest and Ctx.Quest.setQuestMode then Ctx.Quest.setQuestMode(v) end
        end)
    mkSection(pQuest, "Actions")
    mkButton(pQuest, "◈", "Force Accept", "Current selection", function()
        if Ctx.Quest and Ctx.Quest.forceAcceptQuest then
            local mode = S.questMode
            if mode and mode ~= "Auto Best Quest (By Level)" then
                local ok, reason = Ctx.Quest.forceAcceptQuest(mode)
                print("[Dingus][Quest] accept: " .. tostring(ok)
                    .. " (" .. tostring(reason) .. ")")
            end
        end
    end)
    mkButton(pQuest, "✕", "Abandon Active", "Drop current", function()
        if Ctx.Quest and Ctx.Quest.forceAbandon then
            Ctx.Quest.forceAbandon()
        end
    end, C.red)
    mkSection(pQuest, "Crow Priority")
    mkToggle(pQuest, "✦", "Auto Crow Read", "Refresh priority", "crw")
    mkButton(pQuest, "◉", "Force Crow Read", "Read panel now", function()
        if Ctx.Quest and Ctx.Quest.forceCrowRead then
            Ctx.Quest.forceCrowRead()
        end
    end)
    mkSection(pQuest, "Status")
    local questInfo = mkInfo(pQuest, 170)

    --========================================================
    -- LOGS
    --========================================================
    local pLogs = mkPage("Logs")
    local logFrame = Instance.new("Frame")
    logFrame.Size = UDim2.new(1, -SCW-8, 1, -PAD*2)
    logFrame.BackgroundColor3 = C.bgP
    logFrame.BorderSizePixel = 0
    logFrame.LayoutOrder = nextO(pLogs)
    logFrame.Parent = pLogs
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

    --========================================================
    -- SETTINGS
    --========================================================
    local pSet = mkPage("Settings")
    mkSection(pSet, "Concealment")
    mkToggle(pSet, "◈", "Concealed Parent", "gethui / CoreGui", "GuiConcealed")
    mkButton(pSet, "⇩", "Panic Hide", "Hide GUI now", function()
        gui.Parent = nil
    end, C.red)
    mkSection(pSet, "Config")
    mkButton(pSet, "▶", "Save Config", "Persist to disk", function()
        local ok = F.save and F.save("default")
        print("[Dingus][Config] save: " .. tostring(ok))
    end)
    mkButton(pSet, "◀", "Load Config", "Read from disk", function()
        if F.load then
            local ok, msg = F.load("default")
            print("[Dingus][Config] " .. tostring(msg))
        end
    end)
    mkButton(pSet, "✕", "Reset Config", "Factory defaults", function()
        if F.reset then F.reset() end
    end, C.red)
    mkSection(pSet, "Diagnostics")
    local runtimeInfo = mkInfo(pSet, 160)
    local capsInfo = mkInfo(pSet, 200)
    local perfInfo = mkInfo(pSet, 160)

    selectPage("Dashboard")

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
    minB.MouseButton1Click:Connect(minimize)
    pBtn.MouseButton1Click:Connect(restore)

    --========================================================
    -- REFRESH LOOP
    --========================================================
    local cache = {}
    task.spawn(function()
        while S.run do
            if S.boot and not minimized then
                local h = U.hum()
                local hp = h and string.format("%d/%d",
                    math.floor(h.Health), math.floor(h.MaxHealth)) or "?"

                -- State chip
                local st = S.cbtS or "—"
                if cache.st ~= st then
                    cache.st = st
                    svState.Text = st
                    local col = C.textM
                    if st == "STRIKE" or st == "PUNISH" then col = C.green
                    elseif st == "RECOVER" or st == "RETREAT" then col = C.red
                    elseif st == "SCAN" or st == "TELEPORT" then col = C.yellow
                    elseif st == "LOOT_WAIT" then col = C.blue end
                    chipDot.BackgroundColor3 = col
                    chipText.Text = st
                    pulseDot.BackgroundColor3 = (st == "STRIKE" and C.green) or C.textM
                    pulseText.Text = S.cbt and ("farm: " .. st) or "farm: idle"
                end

                local tgt = S.tgt and S.tgt.ch and S.tgt.ch.Name
                    or (S.lockedTarget and S.lockedTarget.Name) or "none"
                if cache.tgt ~= tgt then cache.tgt = tgt; svTarget.Text = tgt end
                if cache.hp ~= hp then cache.hp = hp; svHP.Text = hp end
                local kc = tostring(S.bKll or 0)
                if cache.kc ~= kc then cache.kc = kc; svKills.Text = kc end

                -- Faction chip
                if Ctx.Faction and Ctx.Faction.stats then
                    local fs = Ctx.Faction.stats()
                    local fstr = string.format("%s%s",
                        tostring(fs.faction),
                        fs.isHashira and "★" or "")
                    if cache.fstr ~= fstr then
                        cache.fstr = fstr
                        facText.Text = "faction: " .. fstr
                        local fcol = C.textD
                        if fs.faction == "demon" then fcol = C.purple
                        elseif fs.faction == "slayer" then fcol = C.blue
                        elseif fs.faction == "hybrid" then fcol = C.yellow end
                        facText.TextColor3 = fcol
                    end
                end

                -- Dashboard info
                local di = string.format(
                    "  target: %s\n  hp: %s\n  kills: %d  fps: %.0f\n  mode: %s  cat: %s",
                    tostring(tgt), hp, S.bKll or 0, S.fps or 60,
                    tostring(F.SynSafeMode), tostring(S.mobCategory))
                if cache.di ~= di then cache.di = di; dashInfo.Text = di end

                -- Farm info
                local t = Ctx.Atk and Ctx.Atk.telemetry and Ctx.Atk.telemetry() or {}
                local fi = string.format(
                    "  state: %s\n  hits: %d  kills: %d\n  identity: %s  IH: %s\n  SP: %s",
                    tostring(t.state), t.hits or 0, t.kills or 0,
                    tostring(t.identityOk), tostring(t.inputHandler),
                    tostring(t.skillProvider))
                if cache.fi ~= fi then cache.fi = fi; farmInfo.Text = fi end

                -- Faction page
                if Ctx.Faction then
                    local fs = Ctx.Faction.stats()
                    local tgts = fs.targets and table.concat(fs.targets, ", ") or "none"
                    local fsi = string.format(
                        "  race: %s\n  rank: %s\n  hashira: %s\n  auto: %s  manual: %s\n  targeting: %s\n  detections: %d  errors: %d",
                        tostring(fs.faction), tostring(fs.rank),
                        tostring(fs.isHashira),
                        tostring(fs.auto), tostring(fs.manual),
                        tgts, fs.detectCount or 0, fs.detectErrors or 0)
                    if cache.fsi ~= fsi then cache.fsi = fsi; facStatus.Text = fsi end

                    local enemies = Ctx.Faction.getEnemyList and Ctx.Faction.getEnemyList() or {}
                    local lines = {}
                    if #enemies == 0 then
                        table.insert(lines, "  (no matching enemies in range)")
                    else
                        table.insert(lines, string.format("  %d matching:", #enemies))
                        for i = 1, math.min(#enemies, 8) do
                            local e = enemies[i]
                            table.insert(lines, string.format(
                                "  [%s] %s @%.0f",
                                (e.faction or "?"):sub(1, 3),
                                (e.name or "?"):sub(1, 24),
                                e.dist or 0))
                        end
                    end
                    local fl = table.concat(lines, "\n")
                    if cache.fl ~= fl then cache.fl = fl; facList.Text = fl end
                end

                -- Chest info
                if Ctx.Chest and Ctx.Chest.stats then
                    local cs = Ctx.Chest.stats()
                    local ci = string.format(
                        "  enabled: %s  loot: %s\n  chests: %s  souls: %s\n  collected: %d  loot: %d\n  failed: %d  running: %s",
                        tostring(cs.enabled), tostring(cs.loot),
                        tostring(cs.chests), tostring(cs.souls),
                        cs.collected or 0, cs.lootCollected or 0,
                        cs.failed or 0, tostring(cs.running))
                    if cache.ci ~= ci then cache.ci = ci; chestStats.Text = ci end
                end

                -- Quest info
                if Ctx.Quest and Ctx.Quest.stats then
                    local qs = Ctx.Quest.stats()
                    local qi = string.format(
                        "  level: %d  race: %s\n  mode: %s\n  auto: %s  failures: %d\n  active: %s\n  priority: %s",
                        qs.level or 0, tostring(qs.race),
                        tostring(qs.questMode),
                        tostring(qs.autoQuest), qs.failures or 0,
                        tostring(qs.activeQuestName),
                        tostring(qs.priority))
                    if cache.qi ~= qi then cache.qi = qi; questInfo.Text = qi end
                end

                -- Settings info
                local ri = string.format(
                    "  platform: %s\n  executor: %s\n  input: %s  mouse: %s\n  http: %s  file: %s",
                    U.Platform, U.Executor, U.InputBackend, U.MouseBackend,
                    U.HttpMode, tostring(U.Caps.file))
                if cache.ri ~= ri then cache.ri = ri; runtimeInfo.Text = ri end

                local cap = string.format(
                    "  proximity: %s  click: %s\n  touch: %s  gethui: %s\n  firesignal: %s  headers: %s",
                    tostring(U.Caps.proximity), tostring(U.Caps.click),
                    tostring(U.Caps.touch), tostring(U.Caps.gethui),
                    tostring(U.Caps.firesignal), tostring(U.Caps.httpHeaders))
                if cache.cap ~= cap then cache.cap = cap; capsInfo.Text = cap end

                if Ctx.perf then
                    local p = Ctx.perf()
                    local pi = string.format(
                        "  fps: %.1f  stress: %.2f\n  backoff: %.2fx  budget: %.1fms",
                        p.avg_fps or 60, p.stress or 0,
                        p.backoff or 1, (p.budget_used or 0) * 1000)
                    if cache.pi ~= pi then cache.pi = pi; perfInfo.Text = pi end
                end
            end
            task.wait(0.35)
        end
    end)

    --========================================================
    -- INPUT
    --========================================================
    UIS.InputBegan:Connect(function(inp, gp)
        if gp then return end
        if inp.KeyCode == Enum.KeyCode.RightShift then
            if minimized then restore() else minimize() end
            return
        end
        if F.GuiPanicHide and inp.KeyCode == Enum.KeyCode.Backspace
           and UIS:IsKeyDown(Enum.KeyCode.RightControl) then
            gui.Parent = nil
        end
    end)

    closeB.MouseButton1Click:Connect(function()
        gui:Destroy()
    end)

    G.gui = gui
    G.win = win
    G.minimize = minimize
    G.restore = restore
    G.parent = parent
    G.parentKind = parentKind
    G.PAGES = PAGES
    G.NAV = NAV

    print(string.format("[Dingus][gui] v40 · %s · parent=%s · 7 tabs",
        U.Platform, parentKind))
end

return G
