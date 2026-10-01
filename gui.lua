--[[
    Dingus-Slayer · gui.lua v25
    Dual-frame architecture: full window + minimized pill.
    TweenService transitions. Draggable pill persists position.
]]--

local G = {}

function G.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St

    local Tween = game:GetService("TweenService")
    local UIS = game:GetService("UserInputService")

    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    local old = parent:FindFirstChild("DingusUI")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "DingusUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    --============================================================
    -- WINDOW CONSTANTS
    --============================================================
    local WIN_W, WIN_H = 520, 500
    local PILL_W, PILL_H = 150, 34

    --============================================================
    -- COLOR PALETTE
    --============================================================
    local CLR = {
        bg        = Color3.fromRGB(14, 14, 18),
        bgHeader  = Color3.fromRGB(30, 18, 16),
        bgPanel   = Color3.fromRGB(20, 20, 28),
        bgRow     = Color3.fromRGB(24, 24, 32),
        bgSlider  = Color3.fromRGB(38, 38, 48),
        border    = Color3.fromRGB(200, 90, 70),
        accent    = Color3.fromRGB(220, 90, 70),
        accentDim = Color3.fromRGB(150, 60, 50),
        green     = Color3.fromRGB(70, 180, 100),
        red       = Color3.fromRGB(200, 60, 70),
        blue      = Color3.fromRGB(60, 130, 200),
        text      = Color3.fromRGB(230, 230, 240),
        textDim   = Color3.fromRGB(160, 170, 190),
        textMuted = Color3.fromRGB(120, 130, 150),
    }

    --============================================================
    -- FULL WINDOW FRAME
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
    titleBar.Name = "TitleBar"
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

    --============================================================
    -- WINDOW CONTROLS (minimize, close)
    --============================================================
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
    -- TAB BAR
    --============================================================
    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.Size = UDim2.new(1, -16, 0, 30)
    tabBar.Position = UDim2.new(0, 8, 0, 42)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = win
    local tLay = Instance.new("UIListLayout", tabBar)
    tLay.FillDirection = Enum.FillDirection.Horizontal
    tLay.Padding = UDim.new(0, 4)

    --============================================================
    -- CONTENT AREA
    --============================================================
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -16, 1, -140)
    content.Position = UDim2.new(0, 8, 0, 80)
    content.BackgroundColor3 = CLR.bgPanel
    content.BorderSizePixel = 0
    content.Parent = win
    Instance.new("UICorner", content).CornerRadius = UDim.new(0, 8)

    --============================================================
    -- STATUS BAR
    --============================================================
    local statusBar = Instance.new("TextLabel")
    statusBar.Name = "Status"
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
    -- MINIMIZED PILL (separate frame)
    --============================================================
    local pill = Instance.new("Frame")
    pill.Name = "MinimizedPill"
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

    -- Pill hover glow
    local pillBtn = Instance.new("TextButton")
    pillBtn.Size = UDim2.new(1, 0, 1, 0)
    pillBtn.BackgroundTransparency = 1
    pillBtn.Text = ""
    pillBtn.Parent = pill
    pillBtn.MouseEnter:Connect(function()
        Tween:Create(pillStroke, TweenInfo.new(0.15), { Color = Color3.fromRGB(240, 120, 100) }):Play()
        Tween:Create(pillDot, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(255, 120, 100) }):Play()
    end)
    pillBtn.MouseLeave:Connect(function()
        Tween:Create(pillStroke, TweenInfo.new(0.15), { Color = CLR.border }):Play()
        Tween:Create(pillDot, TweenInfo.new(0.15), { BackgroundColor3 = CLR.accent }):Play()
    end)

    --============================================================
    -- MINIMIZE / RESTORE LOGIC
    --============================================================
    local TWEEN_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local TWEEN_OUT = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.In)

    local winPos = win.Position
    local minimized = false

    local function minimize()
        if minimized then return end
        minimized = true

        -- Save current window position
        winPos = win.Position

        -- Animate window out
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

        -- Fade in pill after window starts moving
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

        -- Fade out pill
        Tween:Create(pill, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
        Tween:Create(pillStroke, TweenInfo.new(0.15), { Transparency = 1 }):Play()
        Tween:Create(pillDot, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
        Tween:Create(pillLbl, TweenInfo.new(0.15), { TextTransparency = 1 }):Play()

        task.wait(0.12)
        pill.Visible = false

        -- Show window with slide-in
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

    local activeTabButton = nil

    local function mkTab(name, order)
        local b = Instance.new("TextButton")
        b.Name = "Tab_" .. name
        b.Size = UDim2.new(0, 86, 1, 0)
        b.BackgroundColor3 = CLR.bgPanel
        b.BorderSizePixel = 0
        b.Text = name
        b.TextColor3 = CLR.textDim
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
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
            activeTabButton = b
        end)
        return b
    end

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
    end

    local function mkButton(page, pn, label, cb, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 34)
        b.BackgroundColor3 = color or CLR.blue
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = CLR.text
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.LayoutOrder = nextOrder(pn)
        b.Parent = page
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)

        local baseColor = color or CLR.blue
        b.MouseEnter:Connect(function()
            Tween:Create(b, TweenInfo.new(0.15), {
                BackgroundColor3 = Color3.new(
                    math.min(baseColor.R + 0.1, 1),
                    math.min(baseColor.G + 0.1, 1),
                    math.min(baseColor.B + 0.1, 1)
                ),
            }):Play()
        end)
        b.MouseLeave:Connect(function()
            Tween:Create(b, TweenInfo.new(0.15), { BackgroundColor3 = baseColor }):Play()
        end)

        b.MouseButton1Click:Connect(function()
            local ok, err = pcall(cb)
            if not ok then
                print("[Dingus][btn] " .. label .. ": " .. tostring(err))
            end
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
            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                drag = true
            end
        end)
        hit.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                drag = false
            end
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
    -- TAB PAGES
    --============================================================
    local pMain = mkPage("Main")
    local mainInfo = mkInfo(pMain, "Main", 150)
    mkButton(pMain, "Main", "Toggle Combat", function()
        St.cbt = not St.cbt
        print("[Dingus] combat " .. (St.cbt and "ON" or "OFF"))
    end, CLR.accent)
    mkButton(pMain, "Main", "Toggle Horse Flight", function()
        if Ctx.Fly and Ctx.Fly.toggle then Ctx.Fly.toggle() end
    end, Color3.fromRGB(130, 80, 180))
    mkButton(pMain, "Main", "Force Boss Scan", function()
        St.lScn = 0
        local l = Ctx.Detect.scanBosses()
        print("[Dingus] scan: " .. #l .. " bosses")
    end, CLR.blue)
    mkButton(pMain, "Main", "Run Quest Cycle", function()
        if Ctx.Quest and Ctx.Quest.doCycle then Ctx.Quest.doCycle() end
    end, Color3.fromRGB(180, 120, 60))
    mkButton(pMain, "Main", "Clear Body Movers", function()
        local r = U.hrp()
        if r then
            for _, c in ipairs(r:GetChildren()) do
                if c:IsA("BodyPosition") or c:IsA("BodyVelocity")
                    or c:IsA("BodyGyro") or c:IsA("LinearVelocity")
                    or c:IsA("AlignOrientation") then
                    c:Destroy()
                end
            end
            print("[Dingus] cleared movers")
        end
    end, Color3.fromRGB(150, 80, 80))

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
        function() return St.aiI end,
        function(v) St.aiI = v end, "%.2f")
    mkSlider(pCombat, "Combat", "Run Speed", 16, 48,
        function() return Cfg.RunSpeed end,
        function(v) Cfg.RunSpeed = v end)
    mkSlider(pCombat, "Combat", "Retreat HP %", 10, 90,
        function() return Cfg.RetreatHP * 100 end,
        function(v) Cfg.RetreatHP = v / 100 end)

    local pFly = mkPage("Fly")
    local flyInfo = mkInfo(pFly, "Fly", 120)
    mkButton(pFly, "Fly", "Start Horse Flight", function()
        if Ctx.Fly then Ctx.Fly.start() end
    end, Color3.fromRGB(130, 80, 180))
    mkButton(pFly, "Fly", "Stop Flight", function()
        if Ctx.Fly then Ctx.Fly.stop() end
    end, CLR.red)
    mkSlider(pFly, "Fly", "Flight Speed", 8, 40,
        function() return St.FlySpeed or 22 end,
        function(v) St.FlySpeed = v end)

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
    mkButton(pCrow, "Crow", "Summon Click", function()
        U.m1()
    end, CLR.blue)
    mkButton(pCrow, "Crow", "Try Accept Menu", function()
        local m = Ctx.Scan.findCrowMenu()
        if m then
            pcall(function() m:Activate() end)
            print("[Dingus] menu activated")
        end
    end, Color3.fromRGB(180, 120, 60))

    local pConfig = mkPage("Config")
    local configInfo = mkInfo(pConfig, "Config", 150)
    mkButton(pConfig, "Config", "Save Config", function()
        local ok, result = Cfg.save()
        print("[Dingus][Config] save " .. (ok and "ok" or ("fail: " .. tostring(result))))
    end, CLR.blue)
    mkButton(pConfig, "Config", "Load Config", function()
        if not Cfg.exists() then print("[Dingus][Config] no file"); return end
        local ok, result = Cfg.load()
        print("[Dingus][Config] " .. tostring(result))
    end, CLR.green)
    mkButton(pConfig, "Config", "Reset Defaults", function()
        Cfg.reset()
        print("[Dingus][Config] reset")
    end, Color3.fromRGB(180, 130, 80))
    mkButton(pConfig, "Config", "Delete File", function()
        print("[Dingus][Config] delete: " .. tostring(Cfg.delete()))
    end, CLR.red)
    mkButton(pConfig, "Config", "Print Values", function()
        print(Cfg.pretty())
    end, Color3.fromRGB(110, 110, 150))

    --============================================================
    -- TAB BUTTONS
    --============================================================
    local tbMain = mkTab("Main", 1)
    mkTab("Combat", 2)
    mkTab("Fly", 3)
    mkTab("Crow", 4)
    mkTab("Config", 5)

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
                local h = U.hum()
                local hp = h
                    and string.format("%d/%d", math.floor(h.Health), math.floor(h.MaxHealth))
                    or "?"
                local hitRate = St.aAt > 0
                    and math.floor(St.aHi / St.aAt * 100)
                    or 0

                local s1 = string.format(
                    "  state: %s · hp: %s\n" ..
                    "  target: %s @%.0f\n" ..
                    "  atk: %d/%d (%d%%)\n" ..
                    "  kills: %d · retreats: %d · fly: %s\n" ..
                    "  quest: %s · lv %d",
                    St.cbtS, hp,
                    St.tgt and St.tgt.ch.Name or "none", St.tgt and St.tgt.d or 0,
                    St.aHi, St.aAt, hitRate,
                    St.bKll, St.rtrC, St.FlyActive and "ON" or "OFF",
                    tostring(St.questTarget or "—"), St.playerLevel or 0)
                if cache.main ~= s1 then cache.main = s1; mainInfo.Text = s1 end

                local s2 = string.format(
                    "  atk range: %.1f · interval: %.2f\n" ..
                    "  runspeed: %.0f · retreat hp: %.0f%%\n" ..
                    "  skill: %s · equip: %s\n" ..
                    "  retreat: %s · stun: %s · spoof: %s",
                    Cfg.AtkRange, St.aiI,
                    Cfg.RunSpeed, Cfg.RetreatHP * 100,
                    tostring(St.skl), tostring(St.eqp),
                    tostring(St.rtr), tostring(St.stunPun), tostring(St.gsp))
                if cache.combat ~= s2 then cache.combat = s2; combatInfo.Text = s2 end

                local s3 = string.format(
                    "  active: %s · mounted: %s\n" ..
                    "  speed: %.0f studs/s\n" ..
                    "  noclip: %s",
                    tostring(St.FlyActive),
                    tostring(St.FlyMounted),
                    St.FlySpeed or 22,
                    Ctx.Fly and Ctx.Fly.active and "ON" or "OFF")
                if cache.fly ~= s3 then cache.fly = s3; flyInfo.Text = s3 end

                local s4 = string.format(
                    "  crow tool: %s\n" ..
                    "  perched: %s · accepted: %d\n" ..
                    "  auto: %s",
                    St.crT and St.crT.Name or "not found",
                    tostring(St.cPrch), St.cQs, tostring(St.crw))
                if cache.crow ~= s4 then cache.crow = s4; crowInfo.Text = s4 end

                local s5 = string.format(
                    "  file: %s\n" ..
                    "  exists: %s (%d bytes)\n" ..
                    "  exec: %s · fps: %.0f",
                    Cfg.ConfigFile,
                    tostring(Cfg.exists()), Cfg.fileSize(),
                    tostring(identifyexecutor and identifyexecutor() or "?"),
                    St.fps or 60)
                if cache.config ~= s5 then cache.config = s5; configInfo.Text = s5 end

                local bar = string.format(
                    "  fps %.0f  ·  %s  ·  fly %s  ·  hp %s",
                    St.fps or 60, St.cbtS,
                    St.FlyActive and "ON" or "OFF", hp)
                if cache.bar ~= bar then cache.bar = bar; statusBar.Text = bar end
            end
            task.wait(0.4)
        end
    end)

    --============================================================
    -- HOTKEY (RightShift toggles minimize)
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

    G.gui = gui
    G.win = win
    G.minimize = minimize
    G.restore = restore
end

return G
