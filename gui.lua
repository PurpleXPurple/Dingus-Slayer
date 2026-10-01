--[[
    Dingus-Slayer · gui.lua v21
    4 tabs, per-tab scrolling, all controls visible.
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

    local win = Instance.new("Frame")
    win.Size = UDim2.new(0, 520, 0, 500)
    win.Position = UDim2.new(0.5, -260, 0.5, -250)
    win.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
    win.BorderSizePixel = 0
    win.Active = true
    win.Draggable = true
    win.Parent = gui
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 8)
    local ws = Instance.new("UIStroke", win)
    ws.Color = Color3.fromRGB(200, 90, 70)
    ws.Thickness = 1

    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
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
    closeBtn.Size = UDim2.new(0, 24, 0, 24)
    closeBtn.Position = UDim2.new(1, -30, 0, 3)
    closeBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 50)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 13
    closeBtn.Parent = win
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

    -- Tab bar
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -16, 0, 28)
    tabBar.Position = UDim2.new(0, 8, 0, 36)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = win
    local tLay = Instance.new("UIListLayout", tabBar)
    tLay.FillDirection = Enum.FillDirection.Horizontal
    tLay.Padding = UDim.new(0, 4)

    -- Content
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -16, 1, -124)
    content.Position = UDim2.new(0, 8, 0, 70)
    content.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
    content.BorderSizePixel = 0
    content.Parent = win
    Instance.new("UICorner", content).CornerRadius = UDim.new(0, 6)

    -- Bottom status bar (shared across tabs)
    local bottomBar = Instance.new("TextLabel")
    bottomBar.Size = UDim2.new(1, -16, 0, 42)
    bottomBar.Position = UDim2.new(0, 8, 1, -50)
    bottomBar.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
    bottomBar.BorderSizePixel = 0
    bottomBar.Text = "  ready"
    bottomBar.TextColor3 = Color3.fromRGB(180, 200, 180)
    bottomBar.TextXAlignment = Enum.TextXAlignment.Left
    bottomBar.TextYAlignment = Enum.TextYAlignment.Top
    bottomBar.Font = Enum.Font.Code
    bottomBar.TextSize = 10
    bottomBar.TextWrapped = true
    bottomBar.Parent = win
    Instance.new("UICorner", bottomBar).CornerRadius = UDim.new(0, 6)

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
                    o.BackgroundColor3 = (o == b) and Color3.fromRGB(200, 90, 70) or Color3.fromRGB(30, 30, 40)
                end
            end
        end)
        return b
    end

    -- Control builders
    local orderCounter = {}
    local function nextOrder(pageName)
        orderCounter[pageName] = (orderCounter[pageName] or 0) + 1
        return orderCounter[pageName]
    end

    local function mkToggle(page, pageName, label, key)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 28)
        row.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        row.BorderSizePixel = 0
        row.LayoutOrder = nextOrder(pageName)
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

    local function mkButton(page, pageName, label, cb, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 32)
        b.BackgroundColor3 = color or Color3.fromRGB(60, 90, 140)
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.LayoutOrder = nextOrder(pageName)
        b.Parent = page
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        b.MouseButton1Click:Connect(function()
            local ok, err = pcall(cb)
            if not ok then print("[Dingus][btn] " .. label .. ": " .. tostring(err)) end
        end)
        return b
    end

    local function mkSlider(page, pageName, label, minV, maxV, getter, setter)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 44)
        row.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        row.BorderSizePixel = 0
        row.LayoutOrder = nextOrder(pageName)
        row.Parent = page
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -20, 0, 16)
        lbl.Position = UDim2.new(0, 10, 0, 4)
        lbl.BackgroundTransparency = 1
        lbl.Text = label .. ": " .. string.format("%.2f", getter())
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
        hit.Size = UDim2.new(1, -20, 0, 22)
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
        game:GetService("UserInputService").InputChanged:Connect(function(i)
            if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
                local mx = game:GetService("UserInputService"):GetMouseLocation().X
                local bx, bw = bar.AbsolutePosition.X, bar.AbsoluteSize.X
                if bw > 0 then
                    local p = math.clamp((mx - bx) / bw, 0, 1)
                    local v = minV + (maxV - minV) * p
                    setter(v)
                    lbl.Text = label .. ": " .. string.format("%.2f", v)
                    fill.Size = UDim2.new(p, 0, 1, 0)
                end
            end
        end)
    end

    local function mkInfo(page, pageName, height)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, height or 80)
        lbl.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
        lbl.BorderSizePixel = 0
        lbl.Text = "  —"
        lbl.TextColor3 = Color3.fromRGB(180, 200, 180)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Top
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 11
        lbl.TextWrapped = true
        lbl.LayoutOrder = nextOrder(pageName)
        lbl.Parent = page
        Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 5)
        return lbl
    end

    --============================================================
    -- TAB: MAIN
    --============================================================
    local pMain = mkPage("Main")
    local mainInfo = mkInfo(pMain, "Main", 140)
    mkButton(pMain, "Main", "Toggle Combat", function()
        St.cbt = not St.cbt
        print("[Dingus] combat " .. (St.cbt and "ON" or "OFF"))
    end, Color3.fromRGB(200, 90, 70))
    mkButton(pMain, "Main", "Force Boss Scan", function()
        St.lScn = 0
        local l = Ctx.Detect.scanBosses()
        print("[Dingus] scan: " .. #l .. " bosses")
        for i = 1, math.min(#l, 5) do
            print(string.format("  %s @%.0f", l[i].ch.Name, l[i].d))
        end
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

    --============================================================
    -- TAB: COMBAT
    --============================================================
    local pCombat = mkPage("Combat")
    local combatInfo = mkInfo(pCombat, "Combat", 120)
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
    mkSlider(pCombat, "Combat", "Run Speed", 16, 64,
        function() return Cfg.RunSpeed end,
        function(v) Cfg.RunSpeed = v end)
    mkSlider(pCombat, "Combat", "Close-In Speed", 4, 16,
        function() return Cfg.CloseInSpeed end,
        function(v) Cfg.CloseInSpeed = v end)
    mkSlider(pCombat, "Combat", "Retreat HP %", 10, 90,
        function() return Cfg.RetreatHP * 100 end,
        function(v) Cfg.RetreatHP = v / 100 end)

    --============================================================
    -- TAB: CROW
    --============================================================
    local pCrow = mkPage("Crow")
    local crowInfo = mkInfo(pCrow, "Crow", 140)
    mkToggle(pCrow, "Crow", "Auto Crow Quests", "crw")
    mkButton(pCrow, "Crow", "Equip Crow", function()
        local t = Ctx.Scan.findCrowTool()
        local h = U.hum()
        if t and h and t:IsA("Tool") then
            pcall(function() h:EquipTool(t) end)
            print("[Dingus] crow equipped: " .. t.Name)
        else
            print("[Dingus] no crow tool")
        end
    end, Color3.fromRGB(60, 130, 60))
    mkButton(pCrow, "Crow", "Summon Click", function()
        U.m1()
        print("[Dingus] clicked")
    end, Color3.fromRGB(60, 90, 140))
    mkButton(pCrow, "Crow", "Try Accept Menu", function()
        local m = Ctx.Scan.findCrowMenu()
        if m then
            pcall(function() m:Activate() end)
            print("[Dingus] menu: " .. m:GetFullName())
        else
            print("[Dingus] no menu found")
        end
    end, Color3.fromRGB(140, 90, 60))
    mkButton(pCrow, "Crow", "Dump Crow Paths", function()
        local hits = Ctx.Scan.deepScan({ "crow", "kasugai" })
        print("[Dingus] " .. #hits .. " crow hits")
        for i = 1, math.min(#hits, 30) do
            print("  " .. hits[i].cls .. " :: " .. hits[i].path)
        end
    end, Color3.fromRGB(100, 100, 60))
    mkButton(pCrow, "Crow", "Dump Quest Paths", function()
        local hits = Ctx.Scan.deepScan({ "quest", "boss hunt", "boss_hunt" })
        print("[Dingus] " .. #hits .. " quest hits")
        for i = 1, math.min(#hits, 30) do
            print("  " .. hits[i].cls .. " :: " .. hits[i].path)
        end
    end, Color3.fromRGB(100, 100, 60))

    --============================================================
    -- TAB: CONFIG
    --============================================================
    local pConfig = mkPage("Config")
    local configInfo = mkInfo(pConfig, "Config", 180)
    mkButton(pConfig, "Config", "Save Config", function()
        local lines = {
            "AtkRange=" .. Cfg.AtkRange,
            "AtkInterval=" .. St.aiI,
            "RunSpeed=" .. Cfg.RunSpeed,
            "CloseInSpeed=" .. Cfg.CloseInSpeed,
            "RetreatHP=" .. Cfg.RetreatHP,
            "AutoSkill=" .. tostring(St.skl),
            "AutoEquip=" .. tostring(St.eqp),
            "AutoRetreat=" .. tostring(St.rtr),
            "AutoCrow=" .. tostring(St.crw),
        }
        if U.save then U.save("dingus_config.txt", table.concat(lines, "\n")) end
        print("[Dingus] config saved")
    end, Color3.fromRGB(60, 130, 200))
    mkButton(pConfig, "Config", "Run Diagnostic", function()
        local r = U.report and U.report() or "no report"
        print("[Dingus]\n" .. r)
        local s = Ctx.Detect.scanBosses and #Ctx.Detect.scanBosses() or 0
        print("[Dingus] bosses: " .. s)
        if Ctx.Quest and Ctx.Quest.findBossHunts then
            local hunts = Ctx.Quest.findBossHunts()
            print("[Dingus] quest configs: " .. #hunts)
            for i = 1, math.min(#hunts, 10) do
                print("  #" .. hunts[i].id .. " " .. hunts[i].quest)
            end
        end
    end, Color3.fromRGB(100, 100, 140))
    mkButton(pConfig, "Config", "Unload Script", function()
        if Ctx.Unload then Ctx.Unload() end
    end, Color3.fromRGB(140, 60, 60))

    --============================================================
    -- TAB BUTTONS
    --============================================================
    local tabMain = mkTab("Main", 1)
    mkTab("Combat", 2)
    mkTab("Crow", 3)
    mkTab("Config", 4)

    pMain.Visible = true
    tabMain.BackgroundColor3 = Color3.fromRGB(200, 90, 70)

    --============================================================
    -- REFRESH LOOP
    --============================================================
    local cache = {}
    task.spawn(function()
        while St.run do
            if St.boot then
                local h = U.hum()
                local hp = h and string.format("%d/%d", math.floor(h.Health), math.floor(h.MaxHealth)) or "?"
                local hitRate = St.aAt > 0 and math.floor(St.aHi / St.aAt * 100) or 0
                local ws = h and h.WalkSpeed or 0

                local s1 = string.format(
                    "  state: %s · hp: %s\n  target: %s\n  target distance: %.0f\n  atk: %d/%d (%d%%)\n  kills: %d · retreats: %d · quest: %s\n  walkspeed: %.0f · input: %d",
                    St.cbtS, hp,
                    St.tgt and St.tgt.ch.Name or "none",
                    St.tgt and St.tgt.d or 0,
                    St.aHi, St.aAt, hitRate,
                    St.bKll, St.rtrC, tostring(St.questTarget or "—"),
                    ws, St.inp)
                if cache.main ~= s1 then cache.main = s1; mainInfo.Text = s1 end

                local s2 = string.format(
                    "  attack range: %.1f · interval: %.2f\n  runspeed: %.0f · close-in: %.0f\n  hp threshold: %.0f%%\n  skill rotation: %s · equip: %s\n  retreat: %s · stun: %s · guard: %s",
                    Cfg.AtkRange, St.aiI,
                    Cfg.RunSpeed, Cfg.CloseInSpeed,
                    Cfg.RetreatHP * 100,
                    tostring(St.skl), tostring(St.eqp),
                    tostring(St.rtr), tostring(St.stunPun), tostring(St.gsp))
                if cache.combat ~= s2 then cache.combat = s2; combatInfo.Text = s2 end

                local s3 = string.format(
                    "  crow tool: %s\n  perched: %s · quests accepted: %d\n  auto: %s\n  quest target: %s\n  level: %d",
                    St.crT and St.crT.Name or "not found",
                    tostring(St.cPrch), St.cQs,
                    tostring(St.crw),
                    tostring(St.questTarget or "—"),
                    St.playerLevel or 0)
                if cache.crow ~= s3 then cache.crow = s3; crowInfo.Text = s3 end

                local s4 = string.format(
                    "  executor: %s\n  place: %s\n  player: %s\n  VIM: %s · mouse1click: %s\n  bosses: %d · quest configs: %d\n  fps: %.0f",
                    tostring(identifyexecutor and identifyexecutor() or "?"),
                    tostring(game.PlaceId),
                    tostring(U.Name),
                    tostring(U.VIM ~= nil),
                    tostring(U.Fn and U.Fn.mouse1click ~= nil),
                    #(St.ens or {}),
                    St.huntCount or 0,
                    St.fps or 60)
                if cache.config ~= s4 then cache.config = s4; configInfo.Text = s4 end

                -- Bottom bar refresh
                local bar = string.format(
                    "  fps: %.0f · state: %s · target: %s · hp: %s",
                    St.fps or 60, St.cbtS,
                    St.tgt and St.tgt.ch.Name or "none",
                    hp)
                if cache.bar ~= bar then cache.bar = bar; bottomBar.Text = bar end
            end
            task.wait(0.4)
        end
    end)

    closeBtn.MouseButton1Click:Connect(function()
        gui:Destroy()
    end)

    G.gui = gui
    G.win = win
    G.bottomBar = bottomBar
end

return G
