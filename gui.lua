--[[
    Dingus-Slayer · gui.lua
    Lightweight. 4 tabs. Single status label per tab. No log widget.
]]--

local G = {}
local lastUpdate = {}

function G.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St

    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "DingusUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = parent

    -- Main window
    local win = Instance.new("Frame")
    win.Size = UDim2.new(0, 420, 0, 340)
    win.Position = UDim2.new(0.5, -210, 0.5, -170)
    win.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
    win.BorderSizePixel = 0
    win.Active = true
    win.Draggable = true
    win.Parent = gui
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 8)
    local ws = Instance.new("UIStroke", win)
    ws.Color = Color3.fromRGB(200, 90, 70)
    ws.Thickness = 1

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 28)
    title.BackgroundColor3 = Color3.fromRGB(35, 20, 18)
    title.BorderSizePixel = 0
    title.Text = "  Dingus-Slayer"
    title.TextColor3 = Color3.fromRGB(245, 220, 220)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.Parent = win
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 22, 0, 22)
    closeBtn.Position = UDim2.new(1, -28, 0, 3)
    closeBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 50)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 12
    closeBtn.Parent = win
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

    -- Tab bar
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -16, 0, 26)
    tabBar.Position = UDim2.new(0, 8, 0, 34)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = win
    local tLay = Instance.new("UIListLayout", tabBar)
    tLay.FillDirection = Enum.FillDirection.Horizontal
    tLay.Padding = UDim.new(0, 4)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -16, 1, -110)
    content.Position = UDim2.new(0, 8, 0, 66)
    content.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
    content.BorderSizePixel = 0
    content.Parent = win
    Instance.new("UICorner", content).CornerRadius = UDim.new(0, 6)

    local pages = {}
    local function mkPage(name)
        local p = Instance.new("Frame")
        p.Size = UDim2.new(1, 0, 1, 0)
        p.BackgroundTransparency = 1
        p.Visible = false
        p.Parent = content
        pages[name] = p
        return p
    end

    local function mkTab(name)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 76, 1, 0)
        b.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        b.BorderSizePixel = 0
        b.Text = name
        b.TextColor3 = Color3.fromRGB(220, 220, 230)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.Parent = tabBar
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        b.MouseButton1Click:Connect(function()
            for n, p in pairs(pages) do p.Visible = (n == name) end
            for _, o in ipairs(tabBar:GetChildren()) do
                if o:IsA("TextButton") then
                    o.BackgroundColor3 = (o == b) and Color3.fromRGB(200, 90, 70) or Color3.fromRGB(30, 30, 40)
                end
            end
        end)
        return b
    end

    -- Status label builder (reused)
    local function mkStatus(page)
        local s = Instance.new("TextLabel")
        s.Size = UDim2.new(1, -16, 0, 100)
        s.Position = UDim2.new(0, 8, 0, 8)
        s.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        s.BorderSizePixel = 0
        s.Text = "  ready"
        s.TextColor3 = Color3.fromRGB(200, 220, 200)
        s.TextXAlignment = Enum.TextXAlignment.Left
        s.TextYAlignment = Enum.TextYAlignment.Top
        s.Font = Enum.Font.Code
        s.TextSize = 11
        s.Parent = page
        Instance.new("UICorner", s).CornerRadius = UDim.new(0, 5)
        return s
    end

    -- Toggle builder
    local function mkToggle(page, label, key, order)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -16, 0, 26)
        row.Position = UDim2.new(0, 8, 0, 116 + (order or 0) * 30)
        row.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        row.BorderSizePixel = 0
        row.Parent = page
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -70, 1, 0)
        lbl.Position = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = Color3.fromRGB(225, 225, 235)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 50, 0, 20)
        btn.Position = UDim2.new(1, -58, 0.5, -10)
        btn.BackgroundColor3 = St[key] and Color3.fromRGB(70, 180, 100) or Color3.fromRGB(60, 60, 70)
        btn.BorderSizePixel = 0
        btn.Text = St[key] and "ON" or "OFF"
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.Parent = row
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)

        btn.MouseButton1Click:Connect(function()
            St[key] = not St[key]
            btn.Text = St[key] and "ON" or "OFF"
            btn.BackgroundColor3 = St[key] and Color3.fromRGB(70, 180, 100) or Color3.fromRGB(60, 60, 70)
        end)
    end

    -- Button builder
    local function mkButton(page, label, order, cb, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -16, 0, 30)
        b.Position = UDim2.new(0, 8, 0, 116 + (order or 0) * 34)
        b.BackgroundColor3 = color or Color3.fromRGB(60, 90, 140)
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.Parent = page
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        b.MouseButton1Click:Connect(cb)
        return b
    end

    -- Slider builder
    local function mkSlider(page, label, minV, maxV, default, order, getter, setter)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -16, 0, 42)
        row.Position = UDim2.new(0, 8, 0, 116 + (order or 0) * 46)
        row.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        row.BorderSizePixel = 0
        row.Parent = page
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -20, 0, 16)
        lbl.Position = UDim2.new(0, 10, 0, 4)
        lbl.BackgroundTransparency = 1
        lbl.Text = label .. ": " .. string.format("%.1f", getter())
        lbl.TextColor3 = Color3.fromRGB(225, 225, 235)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.Parent = row

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(1, -20, 0, 6)
        bar.Position = UDim2.new(0, 10, 0, 26)
        bar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        bar.BorderSizePixel = 0
        bar.Parent = row
        Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 3)

        local fill = Instance.new("Frame")
        local pct = (getter() - minV) / (maxV - minV)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(200, 90, 70)
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
        hit.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = true end
        end)
        hit.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
        end)
        local uis = game:GetService("UserInputService")
        uis.InputChanged:Connect(function(i)
            if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
                local mx = uis:GetMouseLocation().X
                local bx, bw = bar.AbsolutePosition.X, bar.AbsoluteSize.X
                local p = math.clamp((mx - bx) / bw, 0, 1)
                local v = minV + (maxV - minV) * p
                setter(v)
                lbl.Text = label .. ": " .. string.format("%.1f", v)
                fill.Size = UDim2.new(p, 0, 1, 0)
            end
        end)
    end

    -- BUILD TABS
    local pMain = mkPage("Main")
    local pCombat = mkPage("Combat")
    local pCrow = mkPage("Crow")
    local pConfig = mkPage("Config")

    pMain.Visible = true
    mkTab("Main"); mkTab("Combat"); mkTab("Crow"); mkTab("Config")

    -- Set first tab color
    for _, o in ipairs(tabBar:GetChildren()) do
        if o:IsA("TextButton") and o.Text == "Main" then
            o.BackgroundColor3 = Color3.fromRGB(200, 90, 70)
        end
    end

    -- Main tab
    local mainStatus = mkStatus(pMain)
    mkButton(pMain, "Toggle Combat", 0, function()
        St.cbt = not St.cbt
        print("[Dingus] combat " .. (St.cbt and "ON" or "OFF"))
    end, Color3.fromRGB(200, 90, 70))
    mkButton(pMain, "Force Boss Scan", 1, function()
        St.lScn = 0
        local l = Ctx.Detect.scanBosses()
        print("[Dingus] " .. #l .. " bosses found")
    end, Color3.fromRGB(60, 130, 200))
    mkButton(pMain, "Auto-Quest Cycle", 2, function()
        if Ctx.Quest and Ctx.Quest.doCycle then Ctx.Quest.doCycle() end
    end, Color3.fromRGB(140, 90, 60))

    -- Combat tab
    local combatStatus = mkStatus(pCombat)
    mkToggle(pCombat, "Auto Skill Rotation", "skl", 0)
    mkToggle(pCombat, "Auto Equip Weapon", "eqp", 1)
    mkToggle(pCombat, "Auto Retreat", "rtr", 2)
    mkToggle(pCombat, "Stun Punish", "stunPun", 3)
    mkSlider(pCombat, "Attack Range", 6, 20, Cfg.AtkRange, 4,
        function() return Cfg.AtkRange end,
        function(v) Cfg.AtkRange = v end)
    mkSlider(pCombat, "Attack Interval", 0.3, 0.9, St.aiI, 5,
        function() return St.aiI end,
        function(v) St.aiI = v end)

    -- Crow tab
    local crowStatus = mkStatus(pCrow)
    mkToggle(pCrow, "Auto Crow Quests", "crw", 0)
    mkButton(pCrow, "Equip Crow", 1, function()
        local t = Ctx.Scan.findCrowTool()
        local h = U.hum()
        if t and h and t:IsA("Tool") then
            pcall(function() h:EquipTool(t) end)
            print("[Dingus] crow equipped")
        end
    end, Color3.fromRGB(60, 130, 60))
    mkButton(pCrow, "Force Click", 2, function()
        U.m1()
    end, Color3.fromRGB(60, 90, 140))
    mkButton(pCrow, "Accept Menu", 3, function()
        local m = Ctx.Scan.findCrowMenu()
        if m then
            pcall(function() m:Activate() end)
            print("[Dingus] menu activated")
        else
            print("[Dingus] no menu")
        end
    end, Color3.fromRGB(140, 90, 60))

    -- Config tab
    local configStatus = mkStatus(pConfig)
    mkButton(pConfig, "Save Config", 0, function()
        local s = string.format(
            "AtkRange=%s\nAtkInterval=%s\nAutoSkill=%s\nAutoEquip=%s\nAutoRetreat=%s\nStunPunish=%s\nAutoCrow=%s",
            Cfg.AtkRange, St.aiI, tostring(St.skl), tostring(St.eqp),
            tostring(St.rtr), tostring(St.stunPun), tostring(St.crw))
        if U.save then U.save("dingus_config.txt", s) end
        print("[Dingus] config saved")
    end, Color3.fromRGB(60, 130, 200))

    -- UI updater (single loop, only updates on text change)
    task.spawn(function()
        while St.run do
            if St.boot then
                local h = U.hum()
                local hp = h and string.format("%d/%d", math.floor(h.Health), math.floor(h.MaxHealth)) or "?"
                local hitRate = St.aAt > 0 and math.floor(St.aHi / St.aAt * 100) or 0

                local s1 = string.format(
                    "  state: %s · hp: %s\n  target: %s\n  atk: %d/%d (%d%%) int %.2f\n  kills: %d · retreats: %d\n  input: %d · fps: %.0f",
                    St.cbtS, hp,
                    St.tgt and St.tgt.ch.Name or "none",
                    St.aHi, St.aAt, hitRate, St.aiI,
                    St.bKll, St.rtrC,
                    St.inp, St.fps or 60)
                if lastUpdate.main ~= s1 then
                    lastUpdate.main = s1
                    mainStatus.Text = s1
                end

                local s2 = string.format(
                    "  attack range: %.1f\n  attack interval: %.2f\n  hits: %d/%d\n  auto skill: %s · auto equip: %s\n  auto retreat: %s · stun punish: %s",
                    Cfg.AtkRange, St.aiI, St.aHi, St.aAt,
                    tostring(St.skl), tostring(St.eqp),
                    tostring(St.rtr), tostring(St.stunPun))
                if lastUpdate.combat ~= s2 then
                    lastUpdate.combat = s2
                    combatStatus.Text = s2
                end

                local s3 = string.format(
                    "  crow tool: %s\n  perched: %s\n  accepted: %d\n  quest: %s",
                    St.crT and St.crT.Name or "none",
                    St.cPrch and "yes" or "no",
                    St.cQs,
                    St.questTarget or "none")
                if lastUpdate.crow ~= s3 then
                    lastUpdate.crow = s3
                    crowStatus.Text = s3
                end

                local s4 = string.format(
                    "  executor: %s\n  place: %s\n  VIM: %s\n  mouse1click: %s",
                    tostring(identifyexecutor and identifyexecutor() or "?"),
                    tostring(game.PlaceId),
                    tostring(U.VIM ~= nil),
                    tostring(U.Fn and U.Fn.mouse1click ~= nil))
                if lastUpdate.config ~= s4 then
                    lastUpdate.config = s4
                    configStatus.Text = s4
                end
            end
            task.wait(0.5)
        end
    end)

    closeBtn.MouseButton1Click:Connect(function()
        gui:Destroy()
        St.run = false
    end)

    G.gui = gui
    G.win = win
end

return G
