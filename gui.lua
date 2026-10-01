--[[
    Dingus-Slayer · gui.lua v24
    Resize-safe. Type-guarded visibility. Persistent size memory.
]]--

local G = {}

function G.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg
    local St = Ctx.St

    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    local old = parent:FindFirstChild("DingusUI")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "DingusUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = parent

    --============================================================
    -- WINDOW
    --============================================================
    local FULL_W, FULL_H = 520, 500
    local MINI_W, MINI_H = 140, 30

    local win = Instance.new("Frame")
    win.Name = "Window"
    win.Size = UDim2.new(0, FULL_W, 0, FULL_H)
    win.Position = UDim2.new(0.5, -FULL_W / 2, 0.5, -FULL_H / 2)
    win.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
    win.BorderSizePixel = 0
    win.Active = true
    win.Draggable = true
    win.ClipsDescendants = true
    win.Parent = gui
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 8)
    local winStroke = Instance.new("UIStroke", win)
    winStroke.Color = Color3.fromRGB(200, 90, 70)
    winStroke.Thickness = 1

    --============================================================
    -- TITLE BAR (always visible)
    --============================================================
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 30)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundColor3 = Color3.fromRGB(35, 20, 18)
    title.BorderSizePixel = 0
    title.Text = "  Dingus-Slayer"
    title.TextColor3 = Color3.fromRGB(245, 220, 220)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.ZIndex = 2
    title.Parent = win
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

    --============================================================
    -- WINDOW CONTROL BUTTONS
    --============================================================
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "Close"
    closeBtn.Size = UDim2.new(0, 22, 0, 22)
    closeBtn.Position = UDim2.new(1, -26, 0, 4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 50)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 12
    closeBtn.ZIndex = 3
    closeBtn.Parent = win
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

    local resizeBtn = Instance.new("TextButton")
    resizeBtn.Name = "Resize"
    resizeBtn.Size = UDim2.new(0, 22, 0, 22)
    resizeBtn.Position = UDim2.new(1, -52, 0, 4)
    resizeBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 60)
    resizeBtn.BorderSizePixel = 0
    resizeBtn.Text = "–"
    resizeBtn.TextColor3 = Color3.new(1, 1, 1)
    resizeBtn.Font = Enum.Font.GothamBold
    resizeBtn.TextSize = 14
    resizeBtn.ZIndex = 3
    resizeBtn.Parent = win
    Instance.new("UICorner", resizeBtn).CornerRadius = UDim.new(0, 5)

    --============================================================
    -- CONTENT CONTAINER (hidden when minimized)
    --============================================================
    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(1, 0, 1, -30)
    container.Position = UDim2.new(0, 0, 0, 30)
    container.BackgroundTransparency = 1
    container.Parent = win

    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.Size = UDim2.new(1, -16, 0, 28)
    tabBar.Position = UDim2.new(0, 8, 0, 4)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = container
    local tLay = Instance.new("UIListLayout", tabBar)
    tLay.FillDirection = Enum.FillDirection.Horizontal
    tLay.Padding = UDim.new(0, 4)

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -16, 1, -80)
    content.Position = UDim2.new(0, 8, 0, 38)
    content.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
    content.BorderSizePixel = 0
    content.Parent = container
    Instance.new("UICorner", content).CornerRadius = UDim.new(0, 6)

    local bottomBar = Instance.new("TextLabel")
    bottomBar.Name = "Status"
    bottomBar.Size = UDim2.new(1, -16, 0, 34)
    bottomBar.Position = UDim2.new(0, 8, 1, -40)
    bottomBar.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
    bottomBar.BorderSizePixel = 0
    bottomBar.Text = "  ready"
    bottomBar.TextColor3 = Color3.fromRGB(180, 200, 180)
    bottomBar.TextXAlignment = Enum.TextXAlignment.Left
    bottomBar.TextYAlignment = Enum.TextYAlignment.Top
    bottomBar.Font = Enum.Font.Code
    bottomBar.TextSize = 10
    bottomBar.TextWrapped = true
    bottomBar.Parent = container
    Instance.new("UICorner", bottomBar).CornerRadius = UDim.new(0, 6)

    --============================================================
    -- RESIZE HANDLER (safe)
    --============================================================
    local minimized = false

    local function minimize()
        if minimized then return end
        minimized = true
        -- Shrink window and hide container. No iteration over children.
        win.Size = UDim2.new(0, MINI_W, 0, MINI_H)
        container.Visible = false
        resizeBtn.Text = "+"
        resizeBtn.Position = UDim2.new(1, -52, 0, 4)
        closeBtn.Position = UDim2.new(1, -26, 0, 4)
    end

    local function restore()
        if not minimized then return end
        minimized = false
        win.Size = UDim2.new(0, FULL_W, 0, FULL_H)
        container.Visible = true
        resizeBtn.Text = "–"
    end

    resizeBtn.MouseButton1Click:Connect(function()
        local ok, err = pcall(function()
            if minimized then restore() else minimize() end
        end)
        if not ok then
            print("[Dingus][gui] resize error: " .. tostring(err))
        end
    end)

    --============================================================
    -- TAB SYSTEM
    --============================================================
    local pages = {}
    local function mkPage(name)
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
        pages[name] = p
        return p
    end

    local function mkTab(name, order)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 88, 1, 0)
        b.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        b.BorderSizePixel = 0
        b.Text = name
        b.TextColor3 = Color3.fromRGB(220, 220, 230)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.LayoutOrder = order
        b.Parent = tabBar
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        b.MouseButton1Click:Connect(function()
            for n, p in pairs(pages) do p.Visible = (n == name) end
            for _, o in ipairs(tabBar:GetChildren()) do
                if o:IsA("TextButton") then
                    o.BackgroundColor3 = (o == b)
                        and Color3.fromRGB(200, 90, 70)
                        or Color3.fromRGB(30, 30, 40)
                end
            end
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

    local function mkToggle(page, pn, label, key)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 28)
        row.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        row.BorderSizePixel = 0
        row.LayoutOrder = nextOrder(pn)
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

    local function mkButton(page, pn, label, cb, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 32)
        b.BackgroundColor3 = color or Color3.fromRGB(60, 90, 140)
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.LayoutOrder = nextOrder(pn)
        b.Parent = page
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        b.MouseButton1Click:Connect(function()
            local ok, err = pcall(cb)
            if not ok then
                print("[Dingus][btn] " .. label .. ": " .. tostring(err))
            end
        end)
        return b
    end

    local function mkSlider(page, pn, label, minV, maxV, getter, setter)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 44)
        row.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        row.BorderSizePixel = 0
        row.LayoutOrder = nextOrder(pn)
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
        local pct = math.clamp((getter() - minV) / (maxV - minV), 0, 1)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(200, 90, 70)
        fill.BorderSizePixel = 0
        fill.Parent = bar
        Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, -20, 0, 22)
        hit.Position = UDim2.new(0, 10, 0, 20)
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

        game:GetService("UserInputService").InputChanged:Connect(function(i)
            if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
                local mx = game:GetService("UserInputService"):GetMouseLocation().X
                local bx, bw = bar.AbsolutePosition.X, bar.AbsoluteSize.X
                if bw > 0 then
                    local p = math.clamp((mx - bx) / bw, 0, 1)
                    local v = minV + (maxV - minV) * p
                    setter(v)
                    lbl.Text = label .. ": " .. string.format("%.1f", v)
                    fill.Size = UDim2.new(p, 0, 1, 0)
                end
            end
        end)
    end

    local function mkInfo(page, pn, height)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, height or 100)
        lbl.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
        lbl.BorderSizePixel = 0
        lbl.Text = "  —"
        lbl.TextColor3 = Color3.fromRGB(180, 200, 180)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Top
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 11
        lbl.TextWrapped = true
        lbl.LayoutOrder = nextOrder(pn)
        lbl.Parent = page
        Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 5)
        return lbl
    end

    --============================================================
    -- TAB CONTENT
    --============================================================
    local pMain = mkPage("Main")
    local mainInfo = mkInfo(pMain, "Main", 150)
    mkButton(pMain, "Main", "Toggle Combat", function()
        St.cbt = not St.cbt
        print("[Dingus] combat " .. (St.cbt and "ON" or "OFF"))
    end, Color3.fromRGB(200, 90, 70))
    mkButton(pMain, "Main", "Toggle Horse Flight", function()
        if Ctx.Fly and Ctx.Fly.toggle then Ctx.Fly.toggle() end
    end, Color3.fromRGB(90, 60, 140))
    mkButton(pMain, "Main", "Force Boss Scan", function()
        St.lScn = 0
        local l = Ctx.Detect.scanBosses()
        print("[Dingus] scan: " .. #l .. " bosses")
    end, Color3.fromRGB(60, 130, 200))
    mkButton(pMain, "Main", "Run Quest Cycle", function()
        if Ctx.Quest and Ctx.Quest.doCycle then Ctx.Quest.doCycle() end
    end, Color3.fromRGB(140, 90, 60))
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
    end, Color3.fromRGB(120, 60, 60))

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
        function(v) St.aiI = v end)
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
    end, Color3.fromRGB(90, 60, 140))
    mkButton(pFly, "Fly", "Stop Flight", function()
        if Ctx.Fly then Ctx.Fly.stop() end
    end, Color3.fromRGB(120, 60, 60))
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
    end, Color3.fromRGB(60, 130, 60))
    mkButton(pCrow, "Crow", "Summon Click", function()
        U.m1()
    end, Color3.fromRGB(60, 90, 140))
    mkButton(pCrow, "Crow", "Try Accept Menu", function()
        local m = Ctx.Scan.findCrowMenu()
        if m then
            pcall(function() m:Activate() end)
            print("[Dingus] menu activated")
        end
    end, Color3.fromRGB(140, 90, 60))

    local pConfig = mkPage("Config")
    local configInfo = mkInfo(pConfig, "Config", 150)
    mkButton(pConfig, "Config", "Save Config", function()
        local ok, result = Cfg.save()
        print("[Dingus][Config] save " .. (ok and "ok" or ("fail: " .. tostring(result))))
    end, Color3.fromRGB(60, 130, 200))
    mkButton(pConfig, "Config", "Load Config", function()
        if not Cfg.exists() then print("[Dingus][Config] no file"); return end
        local ok, result = Cfg.load()
        print("[Dingus][Config] " .. tostring(result))
    end, Color3.fromRGB(60, 130, 100))
    mkButton(pConfig, "Config", "Reset Defaults", function()
        Cfg.reset()
        print("[Dingus][Config] reset")
    end, Color3.fromRGB(140, 100, 60))
    mkButton(pConfig, "Config", "Delete File", function()
        print("[Dingus][Config] delete: " .. tostring(Cfg.delete()))
    end, Color3.fromRGB(140, 60, 60))
    mkButton(pConfig, "Config", "Print Values", function()
        print(Cfg.pretty())
    end, Color3.fromRGB(100, 100, 140))

    --============================================================
    -- TAB WIRING
    --============================================================
    local tbMain = mkTab("Main", 1)
    mkTab("Combat", 2)
    mkTab("Fly", 3)
    mkTab("Crow", 4)
    mkTab("Config", 5)

    pMain.Visible = true
    tbMain.BackgroundColor3 = Color3.fromRGB(200, 90, 70)

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
                    "  kills: %d · retreats: %d\n" ..
                    "  fly: %s · mounted: %s\n" ..
                    "  quest: %s · level: %d",
                    St.cbtS, hp,
                    St.tgt and St.tgt.ch.Name or "none", St.tgt and St.tgt.d or 0,
                    St.aHi, St.aAt, hitRate,
                    St.bKll, St.rtrC,
                    tostring(St.FlyActive), tostring(St.FlyMounted),
                    tostring(St.questTarget or "—"), St.playerLevel or 0)
                if cache.main ~= s1 then cache.main = s1; mainInfo.Text = s1 end

                local s2 = string.format(
                    "  atk range: %.1f · interval: %.2f\n" ..
                    "  runspeed: %.0f · retreat hp: %.0f%%\n" ..
                    "  auto skill: %s · equip: %s\n" ..
                    "  retreat: %s · stun: %s · guard: %s",
                    Cfg.AtkRange, St.aiI,
                    Cfg.RunSpeed, Cfg.RetreatHP * 100,
                    tostring(St.skl), tostring(St.eqp),
                    tostring(St.rtr), tostring(St.stunPun), tostring(St.gsp))
                if cache.combat ~= s2 then cache.combat = s2; combatInfo.Text = s2 end

                local s3 = string.format(
                    "  active: %s\n  mounted: %s\n  speed: %.0f studs/s\n  noclip: %s",
                    tostring(St.FlyActive),
                    tostring(St.FlyMounted),
                    St.FlySpeed or 22,
                    Ctx.Fly and Ctx.Fly.active and "ON" or "OFF")
                if cache.fly ~= s3 then cache.fly = s3; flyInfo.Text = s3 end

                local s4 = string.format(
                    "  crow tool: %s\n  perched: %s · accepted: %d\n  auto: %s",
                    St.crT and St.crT.Name or "not found",
                    tostring(St.cPrch), St.cQs, tostring(St.crw))
                if cache.crow ~= s4 then cache.crow = s4; crowInfo.Text = s4 end

                local s5 = string.format(
                    "  file: %s\n  exists: %s (%d bytes)\n  exec: %s · fps: %.0f",
                    Cfg.ConfigFile,
                    tostring(Cfg.exists()), Cfg.fileSize(),
                    tostring(identifyexecutor and identifyexecutor() or "?"),
                    St.fps or 60)
                if cache.config ~= s5 then cache.config = s5; configInfo.Text = s5 end

                local bar = string.format(
                    "  fps: %.0f · state: %s · fly: %s · hp: %s",
                    St.fps or 60, St.cbtS,
                    St.FlyActive and "ON" or "OFF", hp)
                if cache.bar ~= bar then cache.bar = bar; bottomBar.Text = bar end
            end
            task.wait(0.4)
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
end

return G
