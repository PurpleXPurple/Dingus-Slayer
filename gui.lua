local G = {}

function G.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St

    local V = Cfg.UI
    local root = (gethui and gethui()) or game:GetService("CoreGui")

    local gui = Instance.new("ScreenGui")
    gui.Name = "DingusSlayer"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = root

    local miniGui = Instance.new("ScreenGui")
    miniGui.Name = "DingusMini"
    miniGui.ResetOnSpawn = false
    miniGui.IgnoreGuiInset = true
    miniGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    miniGui.Enabled = false
    miniGui.Parent = root

    -- MAIN WINDOW
    local win = Instance.new("Frame")
    win.Name = "Window"
    win.Size = UDim2.new(0, 560, 0, 460)
    win.Position = UDim2.new(0.5, -280, 0.5, -230)
    win.BackgroundColor3 = V.Bg
    win.BorderSizePixel = 0
    win.Active = true
    win.Draggable = true
    win.Parent = gui
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 8)
    local ws = Instance.new("UIStroke", win)
    ws.Color = V.Accent
    ws.Thickness = 1

    -- Title bar
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(35, 20, 18)
    title.BorderSizePixel = 0
    title.Text = "  Dingus-Slayer · " .. tostring(identifyexecutor and identifyexecutor() or "?")
    title.TextColor3 = V.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = V.FontBold
    title.TextSize = V.TextSizeTitle
    title.Parent = win
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

    -- Minimize button (goes to crow icon)
    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 22, 0, 22)
    minBtn.Position = UDim2.new(1, -56, 0, 4)
    minBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 60)
    minBtn.BorderSizePixel = 0
    minBtn.Text = "_"
    minBtn.TextColor3 = Color3.new(1, 1, 1)
    minBtn.Font = V.FontBold
    minBtn.TextSize = 14
    minBtn.Parent = win
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 5)

    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 22, 0, 22)
    closeBtn.Position = UDim2.new(1, -28, 0, 4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 50)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = V.FontBold
    closeBtn.TextSize = 12
    closeBtn.Parent = win
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

    -- Tab bar
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -16, 0, 26)
    tabBar.Position = UDim2.new(0, 8, 0, 36)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = win
    local tLay = Instance.new("UIListLayout", tabBar)
    tLay.FillDirection = Enum.FillDirection.Horizontal
    tLay.Padding = UDim.new(0, 4)
    tLay.SortOrder = Enum.SortOrder.LayoutOrder

    -- Content area
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -16, 1, -110)
    content.Position = UDim2.new(0, 8, 0, 68)
    content.BackgroundColor3 = V.Bg3
    content.BorderSizePixel = 0
    content.Parent = win
    Instance.new("UICorner", content).CornerRadius = UDim.new(0, 6)

    -- Status bar
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -16, 0, 36)
    status.Position = UDim2.new(0, 8, 1, -44)
    status.BackgroundColor3 = V.Bg2
    status.BorderSizePixel = 0
    status.Text = "  Ready."
    status.TextColor3 = V.TextDim
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.Font = V.FontCode
    status.TextSize = 10
    status.TextWrapped = true
    status.Parent = win
    Instance.new("UICorner", status).CornerRadius = UDim.new(0, 6)

    -- Tab pages
    local tabs = {}
    local function makePage(name)
        local p = Instance.new("ScrollingFrame")
        p.Size = UDim2.new(1, 0, 1, 0)
        p.BackgroundTransparency = 1
        p.BorderSizePixel = 0
        p.ScrollBarThickness = 6
        p.CanvasSize = UDim2.new(0, 0, 0, 0)
        p.AutomaticCanvasSize = Enum.AutomaticSize.Y
        p.Visible = false
        p.Parent = content
        local lay = Instance.new("UIListLayout", p)
        lay.Padding = UDim.new(0, 4)
        lay.SortOrder = Enum.SortOrder.LayoutOrder
        local pad = Instance.new("UIPadding", p)
        pad.PaddingTop = UDim.new(0, 6)
        pad.PaddingLeft = UDim.new(0, 6)
        pad.PaddingRight = UDim.new(0, 6)
        pad.PaddingBottom = UDim.new(0, 6)
        tabs[name] = p
        return p
    end

    local currentTab = nil
    local function makeTab(name, order)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 80, 1, 0)
        b.BackgroundColor3 = V.Bg2
        b.BorderSizePixel = 0
        b.Text = name
        b.TextColor3 = V.Text
        b.Font = V.FontBold
        b.TextSize = 11
        b.LayoutOrder = order
        b.Parent = tabBar
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        b.MouseButton1Click:Connect(function()
            for n, p in pairs(tabs) do p.Visible = (n == name) end
            currentTab = name
            for _, o in ipairs(tabBar:GetChildren()) do
                if o:IsA("TextButton") then
                    o.BackgroundColor3 = (o == b) and V.Accent or V.Bg2
                end
            end
        end)
        return b
    end

    -- Row builders
    local function buildToggle(parent, label, key, order, getVal, setVal)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 26)
        row.BackgroundColor3 = V.Bg2
        row.BorderSizePixel = 0
        row.LayoutOrder = order
        row.Parent = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -70, 1, 0)
        lbl.Position = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = V.Text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = V.Font
        lbl.TextSize = V.TextSize
        lbl.Parent = row
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 50, 0, 20)
        btn.Position = UDim2.new(1, -58, 0.5, -10)
        btn.BackgroundColor3 = getVal() and V.Green or Color3.fromRGB(60, 60, 70)
        btn.BorderSizePixel = 0
        btn.Text = getVal() and "ON" or "OFF"
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = V.FontBold
        btn.TextSize = 11
        btn.Parent = row
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
        btn.MouseButton1Click:Connect(function()
            setVal(not getVal())
            btn.Text = getVal() and "ON" or "OFF"
            btn.BackgroundColor3 = getVal() and V.Green or Color3.fromRGB(60, 60, 70)
        end)
    end

    local function buildSlider(parent, label, key, min, max, order, getVal, setVal)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 42)
        row.BackgroundColor3 = V.Bg2
        row.BorderSizePixel = 0
        row.LayoutOrder = order
        row.Parent = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -20, 0, 16)
        lbl.Position = UDim2.new(0, 10, 0, 4)
        lbl.BackgroundTransparency = 1
        lbl.Text = label .. ": " .. tostring(getVal())
        lbl.TextColor3 = V.Text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = V.Font
        lbl.TextSize = V.TextSize
        lbl.Parent = row
        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(1, -20, 0, 6)
        bar.Position = UDim2.new(0, 10, 0, 26)
        bar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        bar.BorderSizePixel = 0
        bar.Parent = row
        Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 3)
        local fill = Instance.new("Frame")
        local pct = (getVal() - min) / (max - min)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        fill.BackgroundColor3 = V.Accent
        fill.BorderSizePixel = 0
        fill.Parent = bar
        Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)
        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, -20, 0, 20)
        hit.Position = UDim2.new(0, 10, 0, 20)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.Parent = row
        local drag = false
        hit.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then drag = true end
        end)
        hit.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
        end)
        local uis = game:GetService("UserInputService")
        uis.InputChanged:Connect(function(inp)
            if drag and inp.UserInputType == Enum.UserInputType.MouseMovement then
                local mx = uis:GetMouseLocation().X
                local bx, bw = bar.AbsolutePosition.X, bar.AbsoluteSize.X
                local p = math.clamp((mx - bx) / bw, 0, 1)
                local v = min + (max - min) * p
                v = math.floor(v / 0.01 + 0.5) * 0.01
                setVal(v)
                lbl.Text = label .. ": " .. string.format("%.2f", v)
                fill.Size = UDim2.new(p, 0, 1, 0)
            end
        end)
    end

    local function buildButton(parent, label, order, cb, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 28)
        b.BackgroundColor3 = color or Color3.fromRGB(60, 90, 140)
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = V.FontBold
        b.TextSize = 12
        b.LayoutOrder = order
        b.Parent = parent
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        b.MouseButton1Click:Connect(cb)
        return b
    end

    -- MAIN tab
    local pMain = makePage("Main")
    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, 0, 0, 90)
    info.BackgroundColor3 = V.Bg2
    info.BorderSizePixel = 0
    info.Text = "  booting..."
    info.TextColor3 = V.TextDim
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.Font = V.FontCode
    info.TextSize = 10
    info.LayoutOrder = 1
    info.Parent = pMain
    Instance.new("UICorner", info).CornerRadius = UDim.new(0, 5)
    G.StatusLabel = info

    buildButton(pMain, "Toggle Combat", 2, function()
        St.cbt = not St.cbt
        if Ctx.Log then Ctx.Log("INFO", "combat " .. (St.cbt and "ON" or "OFF")) end
    end, Color3.fromRGB(200, 90, 70))
    buildButton(pMain, "Force Boss Scan", 3, function()
        St.lScn = 0
        local l = Ctx.Detect.scanBosses()
        if Ctx.Log then Ctx.Log("SCAN", "found " .. #l .. " bosses") end
    end, Color3.fromRGB(60, 130, 200))
    buildButton(pMain, "Force Crow Cycle", 4, function()
        Ctx.Crow = Ctx.Crow or {}
        if Ctx.Crow.doCycle then Ctx.Crow.doCycle() end
    end, Color3.fromRGB(60, 130, 60))

    -- COMBAT tab
    local pCmb = makePage("Combat")
    buildToggle(pCmb, "Hover Above Enemy", "hvr", 1, function() return St.hvr end, function(v) St.hvr = v end)
    buildToggle(pCmb, "Auto Skill Rotation", "skl", 2, function() return St.skl end, function(v) St.skl = v end)
    buildToggle(pCmb, "Auto Equip Weapon", "eqp", 3, function() return St.eqp end, function(v) St.eqp = v end)
    buildToggle(pCmb, "Auto Retreat", "rtr", 4, function() return St.rtr end, function(v) St.rtr = v end)
    buildToggle(pCmb, "Stun Punish", "stunPun", 5, function() return St.stunPun end, function(v) St.stunPun = v end)
    buildSlider(pCmb, "Hover Height", "hH", 5, 40, 6, function() return Cfg.HoverHeight end, function(v) Cfg.HoverHeight = v end)
    buildSlider(pCmb, "Attack Range", "aR", 6, 20, 7, function() return Cfg.AtkRange end, function(v) Cfg.AtkRange = v end)
    buildSlider(pCmb, "Attack Interval", "aI", Cfg.AtkIntMin, Cfg.AtkIntMax, 8, function() return St.aiI end, function(v) St.aiI = v end)
    buildSlider(pCmb, "Retreat HP %", "rHp", 10, 90, 9, function() return Cfg.RetreatHP * 100 end, function(v) Cfg.RetreatHP = v / 100 end)

    -- SPOOF tab
    local pSpf = makePage("Spoof")
    buildToggle(pSpf, "Enable Spoofers", "gsp", 1, function() return St.gsp end, function(v) St.gsp = v end)
    local spoofInfo = Instance.new("TextLabel")
    spoofInfo.Size = UDim2.new(1, 0, 0, 100)
    spoofInfo.BackgroundColor3 = V.Bg2
    spoofInfo.BorderSizePixel = 0
    spoofInfo.Text = "  hpC: 0 | bkC: 0 | spdC: 0 | kbC: 0 | jmpC: 0"
    spoofInfo.TextColor3 = V.Green
    spoofInfo.TextXAlignment = Enum.TextXAlignment.Left
    spoofInfo.TextYAlignment = Enum.TextYAlignment.Top
    spoofInfo.Font = V.FontCode
    spoofInfo.TextSize = 10
    spoofInfo.LayoutOrder = 2
    spoofInfo.Parent = pSpf
    Instance.new("UICorner", spoofInfo).CornerRadius = UDim.new(0, 5)
    G.SpoofLabel = spoofInfo

    -- CROW tab
    local pCrw = makePage("Crow")
    buildToggle(pCrw, "Auto Crow Quests", "crw", 1, function() return St.crw end, function(v) St.crw = v end)
    local crowInfo = Instance.new("TextLabel")
    crowInfo.Size = UDim2.new(1, 0, 0, 100)
    crowInfo.BackgroundColor3 = V.Bg2
    crowInfo.BorderSizePixel = 0
    crowInfo.Text = "  status: idle"
    crowInfo.TextColor3 = V.Green
    crowInfo.TextXAlignment = Enum.TextXAlignment.Left
    crowInfo.TextYAlignment = Enum.TextYAlignment.Top
    crowInfo.Font = V.FontCode
    crowInfo.TextSize = 10
    crowInfo.LayoutOrder = 2
    crowInfo.Parent = pCrw
    Instance.new("UICorner", crowInfo).CornerRadius = UDim.new(0, 5)
    G.CrowLabel = crowInfo

    buildButton(pCrw, "Equip Crow", 3, function()
        local t = Ctx.Scan.findCrowTool()
        local h = U.hum()
        if t and h and t:IsA("Tool") then
            pcall(function() h:EquipTool(t) end)
            if Ctx.Log then Ctx.Log("CROW", "equipped manually") end
        else
            if Ctx.Log then Ctx.Log("CROW", "no crow tool found") end
        end
    end, Color3.fromRGB(60, 130, 60))
    buildButton(pCrw, "Force Click Crow", 4, function()
        U.m1()
    end, Color3.fromRGB(60, 90, 140))
    buildButton(pCrw, "Force Menu Accept", 5, function()
        local m = Ctx.Scan.findCrowMenu()
        if m then
            pcall(function() m:Activate() end)
            if Ctx.Log then Ctx.Log("CROW", "forced accept") end
        else
            if Ctx.Log then Ctx.Log("CROW", "no menu found") end
        end
    end, Color3.fromRGB(140, 90, 60))
    buildButton(pCrw, "Deep Scan Tree", 6, function()
        local hits = Ctx.Scan.deepScan({ "crow", "quest", "boss" })
        if Ctx.Log then Ctx.Log("SCAN", #hits .. " hits — see console") end
        for i = 1, math.min(#hits, 50) do
            print(hits[i].cls .. " :: " .. hits[i].path)
        end
    end, Color3.fromRGB(100, 100, 60))

    -- EVADE tab
    local pEva = makePage("Evade")
    buildSlider(pEva, "Trigger HP %", "uHP", 10, 90, 1, function() return Cfg.UGTrigHP * 100 end, function(v) Cfg.UGTrigHP = v / 100 end)
    buildSlider(pEva, "Depth", "uD", 8, 50, 2, function() return Cfg.UGDepth end, function(v) Cfg.UGDepth = v end)
    buildSlider(pEva, "Max Hide (s)", "uT", 1, 15, 3, function() return Cfg.UGMaxT end, function(v) Cfg.UGMaxT = v end)

    -- LOG tab
    local pLog = makePage("Log")
    local logScroll = pLog
    logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local logOrder = 0
    local logRows = {}
    local function addLogRow(e)
        logOrder = logOrder + 1
        local row = Instance.new("TextLabel")
        row.Size = UDim2.new(1, 0, 0, 14)
        row.BackgroundTransparency = 1
        row.Text = "  [" .. e.c .. "] " .. e.m
        local col = V.Text
        if e.c == "KILL" then col = V.Red
        elseif e.c == "CROW" then col = V.Green
        elseif e.c == "TARGET" then col = V.Yellow
        elseif e.c == "RETREAT" then col = V.Yellow
        elseif e.c == "EQUIP" then col = V.Green
        elseif e.c == "UG" then col = V.Cyan
        elseif e.c == "SCAN" then col = V.Purple
        elseif e.c == "OPT" then col = V.Blue
        end
        row.TextColor3 = col
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.Font = V.FontCode
        row.TextSize = 10
        row.LayoutOrder = logOrder
        row.Parent = logScroll
        table.insert(logRows, row)
        while #logRows > 100 do
            local o = table.remove(logRows, 1)
            if o then o:Destroy() end
        end
        logScroll.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y)
    end
    G.addLogRow = addLogRow

    -- Assemble pages visibility
    tabs["Main"].Visible = true
    for _, o in ipairs(tabBar:GetChildren()) do
        if o:IsA("TextButton") and o.Text == "Main" then
            o.BackgroundColor3 = V.Accent
        end
    end

    -- Tab creation
    makeTab("Main", 1)
    makeTab("Combat", 2)
    makeTab("Spoof", 3)
    makeTab("Crow", 4)
    makeTab("Evade", 5)
    makeTab("Log", 6)

    -- MINIMIZE BUTTON (crow icon)
    local mini = Instance.new("TextButton")
    mini.Name = "Mini"
    mini.Size = UDim2.new(0, 54, 0, 54)
    mini.Position = UDim2.new(0, 20, 0.5, -27)
    mini.BackgroundColor3 = V.Bg
    mini.BackgroundTransparency = 0.05
    mini.BorderSizePixel = 0
    mini.Text = ""
    mini.AutoButtonColor = false
    mini.Active = true
    mini.Draggable = true
    mini.Parent = miniGui
    Instance.new("UICorner", mini).CornerRadius = UDim.new(0.5, 0)
    local ms = Instance.new("UIStroke", mini)
    ms.Color = V.Accent
    ms.Thickness = 2
    ms.Transparency = 0.15

    local miniIcon = Instance.new("ImageLabel")
    miniIcon.Size = UDim2.new(0.72, 0, 0.72, 0)
    miniIcon.Position = UDim2.new(0.14, 0, 0.14, 0)
    miniIcon.BackgroundTransparency = 1
    miniIcon.Image = Cfg.CrowAsset
    miniIcon.ImageColor3 = V.Text
    miniIcon.ZIndex = 2
    miniIcon.Parent = mini

    if Cfg.CrowAsset == "rbxassetid://0" then
        local fallback = Instance.new("TextLabel")
        fallback.Size = UDim2.new(1, 0, 1, 0)
        fallback.BackgroundTransparency = 1
        fallback.Text = "🦅"
        fallback.TextColor3 = V.Text
        fallback.TextScaled = true
        fallback.Font = V.FontBold
        fallback.ZIndex = 1
        fallback.Parent = mini
    end

    -- Hover effects
    mini.MouseEnter:Connect(function()
        miniIcon.ImageColor3 = Color3.new(1, 1, 1)
        ms.Transparency = 0
    end)
    mini.MouseLeave:Connect(function()
        miniIcon.ImageColor3 = V.Text
        ms.Transparency = 0.15
    end)

    -- Pulse animation
    task.spawn(function()
        while St.run do
            if miniGui.Enabled then
                ms.Transparency = 0.6
                local tw = game:GetService("TweenService"):Create(ms, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.15 })
                tw:Play()
                task.wait(3)
            else
                task.wait(1)
            end
        end
    end)

    -- Minimize logic
    minBtn.MouseButton1Click:Connect(function()
        gui.Enabled = false
        miniGui.Enabled = true
        if Ctx.Log then Ctx.Log("UI", "minimized") end
    end)

    mini.MouseButton1Click:Connect(function()
        gui.Enabled = true
        miniGui.Enabled = false
        if Ctx.Log then Ctx.Log("UI", "restored") end
    end)

    -- Ctrl+M hotkey
    game:GetService("UserInputService").InputBegan:Connect(function(inp, gp)
        if gp then return end
        if inp.KeyCode == Enum.KeyCode.M and game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.LeftControl) then
            if gui.Enabled then
                gui.Enabled = false
                miniGui.Enabled = true
            else
                gui.Enabled = true
                miniGui.Enabled = false
            end
        end
    end)

    -- Close
    closeBtn.MouseButton1Click:Connect(function()
        gui:Destroy()
        miniGui:Destroy()
    end)

    G.Window = win
    G.gui = gui
    G.miniGui = miniGui
    G.status = status
end

return G
