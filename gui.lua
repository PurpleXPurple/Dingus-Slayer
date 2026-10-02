-- Dingus-Slayer · gui.lua v35
-- Cross-device: mobile layout auto-scales, touch targets ≥ 44px, concealed parent chain.

local G = {}

function G.init(Ctx)
    local U, F, S = Ctx.Util, Ctx.Cfg, Ctx.St
    local TW = U.TS or game:GetService("TweenService")
    local UIS = U.UIS
    local LS = game:GetService("LogService")

    F.GuiConcealed = F.GuiConcealed ~= false
    F.GuiPanicHide = F.GuiPanicHide ~= false

    local parent, parentKind = U.resolveGuiParent()
    if parentKind == "PlayerGui" then warn("[Dingus][gui] PlayerGui fallback") end

    local guiName = "_c" .. string.format("%06x", math.random(0, 0xFFFFFF))
    local old = parent:FindFirstChild("DingusUI")
    if old then pcall(function() old:Destroy() end) end

    -- Device-aware sizing
    local isM = U.IsMobile
    local vpSize = UIS and UIS:GetViewportSize() or Vector2.new(1280, 720)
    local WW = isM and math.min(vpSize.X - 20, 500) or 940
    local WH = isM and math.min(vpSize.Y - 40, 640) or 680
    local HH = isM and 44 or 48
    local SW = isM and 150 or 200
    local PAD = isM and 10 or 14
    local RH = isM and 60 or 60
    local RG = isM and 8 or 8
    local SCW = isM and 6 or 10
    local TGT = 44

    local C = {
        bg=Color3.fromRGB(12,12,16), bgH=Color3.fromRGB(14,14,20),
        bgS=Color3.fromRGB(10,10,14), bgP=Color3.fromRGB(16,16,22),
        row=Color3.fromRGB(24,24,32), rowH=Color3.fromRGB(32,32,42),
        iconBg=Color3.fromRGB(44,24,24), iconBgD=Color3.fromRGB(28,24,28),
        navA=Color3.fromRGB(40,24,24), navH=Color3.fromRGB(22,22,30),
        trackOff=Color3.fromRGB(52,52,66), border=Color3.fromRGB(40,32,34),
        accent=Color3.fromRGB(220,90,70), accentD=Color3.fromRGB(150,60,50),
        green=Color3.fromRGB(80,200,120), red=Color3.fromRGB(220,70,80),
        text=Color3.fromRGB(232,232,240), textD=Color3.fromRGB(160,165,180),
        textM=Color3.fromRGB(110,115,135),
    }
    local FB, FR, FC = Enum.Font.GothamBold, Enum.Font.Gotham, Enum.Font.Code

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
    ws.Color = C.border; ws.Thickness = 1; ws.Transparency = 0.2

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, HH)
    header.BackgroundColor3 = C.bgH
    header.BorderSizePixel = 0
    header.Parent = win
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)

    local titleL = Instance.new("TextLabel")
    titleL.Size = UDim2.new(1, -140, 1, 0); titleL.Position = UDim2.new(0, 16, 0, 0)
    titleL.BackgroundTransparency = 1; titleL.Text = "Dingus-Slayer · "..U.Platform
    titleL.TextColor3 = C.text; titleL.TextXAlignment = Enum.TextXAlignment.Left
    titleL.Font = FB; titleL.TextSize = isM and 12 or 15
    titleL.TextTruncate = Enum.TextTruncate.AtEnd
    titleL.Parent = header

    local function mkCtrl(g, x, col)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, TGT, 0, TGT)
        b.Position = UDim2.new(1, x, 0.5, -TGT/2)
        b.BackgroundColor3 = col; b.BackgroundTransparency = 1
        b.BorderSizePixel = 0; b.Text = g; b.TextColor3 = C.textD
        b.Font = FB; b.TextSize = 16; b.AutoButtonColor = false; b.Parent = header
        Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
        b.MouseEnter:Connect(function()
            TW:Create(b, TweenInfo.new(0.12), { BackgroundTransparency=0, BackgroundColor3=col, TextColor3=C.text }):Play()
        end)
        b.MouseLeave:Connect(function()
            TW:Create(b, TweenInfo.new(0.12), { BackgroundTransparency=1, TextColor3=C.textD }):Play()
        end)
        return b
    end
    local closeB = mkCtrl("✕", -TGT-8, C.red)
    local minB = mkCtrl("–", -TGT*2-14, Color3.fromRGB(60,60,75))

    local side = Instance.new("Frame")
    side.Size = UDim2.new(0, SW, 1, -HH)
    side.Position = UDim2.new(0,0,0,HH)
    side.BackgroundColor3 = C.bgS
    side.BorderSizePixel = 0
    side.Parent = win

    local navScroll = Instance.new("ScrollingFrame")
    navScroll.Size = UDim2.new(1,-12,1,-70)
    navScroll.Position = UDim2.new(0,6,0,10)
    navScroll.BackgroundTransparency = 1
    navScroll.CanvasSize = UDim2.new(0,0,0,0)
    navScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    navScroll.ScrollBarThickness = 4
    navScroll.ScrollBarImageColor3 = C.accentD
    navScroll.Parent = side
    local navLay = Instance.new("UIListLayout", navScroll)
    navLay.Padding = UDim.new(0,4); navLay.SortOrder = Enum.SortOrder.LayoutOrder

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1,-SW,1,-HH)
    content.Position = UDim2.new(0,SW,0,HH)
    content.BackgroundColor3 = C.bg
    content.BorderSizePixel = 0
    content.ClipsDescendants = true
    content.Parent = win

    local counters = {}
    local function nextO(p) counters[p] = (counters[p] or 0) + 1; return counters[p] end

    local function mkSwitch(par, init, cb)
        local t = Instance.new("TextButton")
        t.Size = UDim2.new(0, 46, 0, 26)
        t.BackgroundColor3 = init and C.accent or C.trackOff
        t.BorderSizePixel = 0; t.Text = ""; t.AutoButtonColor = false; t.Parent = par
        Instance.new("UICorner", t).CornerRadius = UDim.new(1,0)
        local k = Instance.new("Frame")
        k.Size = UDim2.new(0, 20, 0, 20)
        k.Position = init and UDim2.new(1,-22,0.5,-10) or UDim2.new(0,3,0.5,-10)
        k.BackgroundColor3 = Color3.fromRGB(245,245,250)
        k.BorderSizePixel = 0; k.Parent = t
        Instance.new("UICorner", k).CornerRadius = UDim.new(1,0)
        local st = init
        local function set(v)
            st = v
            TW:Create(t, TweenInfo.new(0.18), { BackgroundColor3 = st and C.accent or C.trackOff }):Play()
            TW:Create(k, TweenInfo.new(0.18), { Position = st and UDim2.new(1,-22,0.5,-10) or UDim2.new(0,3,0.5,-10) }):Play()
            if cb then pcall(cb, st) end
        end
        t.MouseButton1Click:Connect(function() set(not st) end)
        return t, set
    end

    local function mkIcon(par, g)
        local b = Instance.new("Frame")
        b.Size = UDim2.new(0, 36, 0, 36); b.Position = UDim2.new(0, 12, 0, 12)
        b.BackgroundColor3 = C.iconBg; b.BorderSizePixel = 0; b.Parent = par
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 9)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1,0,1,0); l.BackgroundTransparency=1
        l.Text = g; l.TextColor3 = C.accent
        l.Font = FB; l.TextSize = 17; l.Parent = b
    end

    local function mkRow(p, h)
        local r = Instance.new("Frame")
        r.Size = UDim2.new(1, -SCW - 4, 0, h or RH)
        r.BackgroundColor3 = C.row; r.BorderSizePixel = 0
        r.LayoutOrder = nextO(p); r.Active = true; r.Parent = p
        Instance.new("UICorner", r).CornerRadius = UDim.new(0, 11)
        return r
    end

    local function mkTitle(r, t, d)
        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1,-110,0,18); title.Position = UDim2.new(0,58,0,10)
        title.BackgroundTransparency = 1; title.Text = t; title.TextColor3 = C.text
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Font = FB; title.TextSize = 13; title.Parent = r
        if d and d ~= "" then
            local desc = Instance.new("TextLabel")
            desc.Size = UDim2.new(1,-110,0,14); desc.Position = UDim2.new(0,58,0,28)
            desc.BackgroundTransparency = 1; desc.Text = d; desc.TextColor3 = C.textM
            desc.TextXAlignment = Enum.TextXAlignment.Left
            desc.Font = FR; desc.TextSize = 11
            desc.TextTruncate = Enum.TextTruncate.AtEnd
            desc.Parent = r
        end
    end

    local function mkToggle(p, g, t, d, key, cb)
        local r = mkRow(p, RH); mkIcon(r, g); mkTitle(r, t, d)
        local sw = mkSwitch(r, S[key], function(v)
            S[key] = v; if cb then pcall(cb, v) end
        end)
        sw.Position = UDim2.new(1, -(isM and 60 or 60), 0.5, -13); sw.ZIndex = 3
    end

    local function mkCfgToggle(p, g, t, d, key)
        local r = mkRow(p, RH); mkIcon(r, g); mkTitle(r, t, d)
        local sw = mkSwitch(r, F[key] ~= false, function(v) F[key] = v end)
        sw.Position = UDim2.new(1, -(isM and 60 or 60), 0.5, -13); sw.ZIndex = 3
    end

    local function mkButton(p, g, t, d, cb, red)
        local r = mkRow(p, RH); mkIcon(r, g); mkTitle(r, t, d)
        local chev = Instance.new("TextLabel")
        chev.Size = UDim2.new(0,20,0,24); chev.Position = UDim2.new(1,-SCW-24,0.5,-12)
        chev.BackgroundTransparency = 1; chev.Text = "›"
        chev.TextColor3 = red and C.red or C.textM
        chev.Font = FB; chev.TextSize = 20; chev.Parent = r
        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1,0,1,0); hit.BackgroundTransparency = 1
        hit.Text = ""; hit.Parent = r
        hit.MouseButton1Click:Connect(function()
            local ok, err = pcall(cb)
            if not ok then print("[Dingus][btn] "..t..": "..tostring(err)) end
        end)
    end

    local function mkInfo(p, h)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1,-SCW-4,0,h or 100)
        l.BackgroundColor3 = C.row; l.BorderSizePixel = 0
        l.Text = "—"; l.TextColor3 = C.textD
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Top
        l.Font = FC; l.TextSize = 12; l.TextWrapped = true
        l.LayoutOrder = nextO(p); l.Parent = p
        Instance.new("UICorner", l).CornerRadius = UDim.new(0, 11)
        local pad = Instance.new("UIPadding", l)
        pad.PaddingTop = UDim.new(0,12); pad.PaddingLeft = UDim.new(0,14)
        pad.PaddingRight = UDim.new(0,14)
        return l
    end

    local function mkSection(p, text)
        local h = Instance.new("TextLabel")
        h.Size = UDim2.new(1,-SCW-4,0,24); h.BackgroundTransparency = 1
        h.Text = string.upper(text); h.TextColor3 = C.textM
        h.TextXAlignment = Enum.TextXAlignment.Left
        h.TextYAlignment = Enum.TextYAlignment.Bottom
        h.Font = FB; h.TextSize = 10; h.LayoutOrder = nextO(p); h.Parent = p
        return h
    end

    local PAGES, NAV = {}, {}

    local function mkPage(name)
        local p = Instance.new("ScrollingFrame")
        p.Name = name; p.Size = UDim2.new(1,0,1,0)
        p.BackgroundTransparency = 1; p.Visible = false
        p.CanvasSize = UDim2.new(0,0,0,0)
        p.AutomaticCanvasSize = Enum.AutomaticSize.Y
        p.ScrollBarThickness = SCW
        p.ScrollBarImageColor3 = C.accent
        p.Parent = content
        local lay = Instance.new("UIListLayout", p)
        lay.Padding = UDim.new(0,RG); lay.SortOrder = Enum.SortOrder.LayoutOrder
        local pad = Instance.new("UIPadding", p)
        pad.PaddingTop = UDim.new(0,PAD); pad.PaddingLeft = UDim.new(0,PAD)
        pad.PaddingRight = UDim.new(0,SCW+4); pad.PaddingBottom = UDim.new(0,PAD+8)
        PAGES[name] = p; return p
    end

    local function selectPage(name)
        for n, p in pairs(PAGES) do p.Visible = (n == name) end
        for n, e in pairs(NAV) do e.setActive(n == name) end
    end

    local function mkNav(g, lbl, name, order)
        local it = Instance.new("TextButton")
        it.Size = UDim2.new(1,-4,0,isM and 44 or 40)
        it.BackgroundTransparency = 1; it.Text = ""
        it.LayoutOrder = order; it.AutoButtonColor = false; it.Parent = navScroll
        Instance.new("UICorner", it).CornerRadius = UDim.new(0,9)
        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(0,3,0,20); bar.Position = UDim2.new(0,0,0.5,-10)
        bar.BackgroundColor3 = C.accent; bar.BackgroundTransparency = 1
        bar.BorderSizePixel = 0; bar.Parent = it
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1,0)
        local ico = Instance.new("TextLabel")
        ico.Size = UDim2.new(0,24,0,24); ico.Position = UDim2.new(0,14,0.5,-12)
        ico.BackgroundTransparency = 1; ico.Text = g; ico.TextColor3 = C.textD
        ico.Font = FB; ico.TextSize = 15; ico.Parent = it
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1,-48,1,0); l.Position = UDim2.new(0,44,0,0)
        l.BackgroundTransparency = 1; l.Text = lbl; l.TextColor3 = C.textD
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Font = FB; l.TextSize = isM and 12 or 13
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
                it.BackgroundTransparency = 0; it.BackgroundColor3 = C.navH
            end
        end)
        it.MouseLeave:Connect(function()
            if not active then it.BackgroundTransparency = 1 end
        end)
        it.MouseButton1Click:Connect(function() selectPage(name) end)
        NAV[name] = { item = it, setActive = setActive }
    end

    mkNav("◈","Dashboard","Dashboard",1)
    mkNav("◆","Combat","Combat",2)
    mkNav("◰","Chests","Chests",3)
    mkNav("✦","Quests","Quests",4)
    mkNav("≡","Logs","Logs",5)
    mkNav("⚙","Settings","Settings",6)

    -- Dashboard
    local pDash = mkPage("Dashboard")
    mkSection(pDash, "Control")
    mkButton(pDash, "▶", "Start Combat", "Enable auto-combat", function()
        S.cbt = true; print("[Dingus] combat on")
    end)
    mkButton(pDash, "■", "Stop Combat", "Halt", function()
        S.cbt = false; print("[Dingus] combat off")
    end, true)
    mkButton(pDash, "◎", "Scan Bosses", "Force scan", function()
        local l = Ctx.Detect.scanBosses(nil, true)
        print("[Dingus] found "..#l.." bosses")
    end)
    local dashInfo = mkInfo(pDash, 160)

    -- Combat
    local pCombat = mkPage("Combat")
    mkSection(pCombat, "Automation")
    mkToggle(pCombat, "✦", "Auto Skills", "Cycles slot order", "skl")
    mkToggle(pCombat, "◆", "Auto Equip", "Swaps weapon", "eqp")
    mkToggle(pCombat, "◀", "Auto Retreat", "Dash when HP drops", "rtr")
    mkToggle(pCombat, "◎", "Stun Punish", "Attack during stun", "stunPun")
    mkSection(pCombat, "Info")
    local combatInfo = mkInfo(pCombat, 140)

    -- Chests
    local pChest = mkPage("Chests")
    mkSection(pChest, "Master")
    mkCfgToggle(pChest, "◰", "Enable Chest Collection", "Master switch", "ChestEnabled")
    mkCfgToggle(pChest, "◆", "Collect on Boss Kill", "After kills", "ChestOnKill")
    mkCfgToggle(pChest, "◎", "Passive Sweep", "Scan while idle", "ChestPassive")
    mkCfgToggle(pChest, "🔒", "Learn Mode", "Observe only", "ChestLearnMode")
    mkSection(pChest, "Actions")
    mkButton(pChest, "◈", "Scan Now", "Dump to F9", function()
        if Ctx.Chest and Ctx.Chest.dump then Ctx.Chest.dump() end
    end)
    mkButton(pChest, "✕", "Reset Cooldowns", "Clear skip-list", function()
        if Ctx.Chest and Ctx.Chest.resetCooldowns then
            Ctx.Chest.resetCooldowns()
            print("[Dingus][Chest] cooldowns cleared")
        end
    end, true)
    mkSection(pChest, "Live Stats")
    local chestStats = mkInfo(pChest, 160)

    -- Quests
    local pQuest = mkPage("Quests")
    mkSection(pQuest, "Crow")
    mkToggle(pQuest, "✦", "Auto Crow Quests", "Periodically read", "crw")
    mkButton(pQuest, "◈", "Force Quest Read", "Open menu, read, close", function()
        if Ctx.Quest and Ctx.Quest.cycle then
            local c = S.questLastCycle
            S.questLastCycle = 0
            pcall(Ctx.Quest.cycle)
            S.questLastCycle = c
        end
    end)
    local questInfo = mkInfo(pQuest, 140)

    -- Logs
    local pLogs = mkPage("Logs")
    local logFrame = Instance.new("Frame")
    logFrame.Size = UDim2.new(1,-SCW-8,1,-PAD*2)
    logFrame.BackgroundColor3 = C.bgP; logFrame.BorderSizePixel = 0
    logFrame.LayoutOrder = nextO(pLogs); logFrame.Parent = pLogs
    Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0, 11)
    local lScroll = Instance.new("ScrollingFrame")
    lScroll.Size = UDim2.new(1,-12,1,-12); lScroll.Position = UDim2.new(0,6,0,6)
    lScroll.BackgroundTransparency = 1
    lScroll.ScrollBarThickness = 8
    lScroll.ScrollBarImageColor3 = C.accent
    lScroll.CanvasSize = UDim2.new(0,0,0,0)
    lScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    lScroll.Parent = logFrame
    local lLay = Instance.new("UIListLayout", lScroll)
    lLay.Padding = UDim.new(0,3); lLay.SortOrder = Enum.SortOrder.LayoutOrder

    -- Settings
    local pSet = mkPage("Settings")
    mkSection(pSet, "Concealment")
    mkCfgToggle(pSet, "◈", "Concealed Parent", "gethui/CoreGui", "GuiConcealed")
    mkButton(pSet, "⇩", "Panic Hide Now", "Hide GUI", function()
        gui.Parent = nil
    end, true)
    mkSection(pSet, "Diagnostics")
    local runtimeInfo = mkInfo(pSet, 160)
    local capsInfo = mkInfo(pSet, 180)

    selectPage("Dashboard")

    -- Minimize
    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0,180,0,44)
    pill.Position = UDim2.new(0,20,0.5,-22)
    pill.BackgroundColor3 = C.bg
    pill.BorderSizePixel = 0; pill.Active = true; pill.Draggable = true
    pill.Visible = false; pill.Parent = gui
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1,0)
    local pStroke = Instance.new("UIStroke", pill)
    pStroke.Color = C.accent; pStroke.Thickness = 1.5
    local pLbl = Instance.new("TextLabel")
    pLbl.Size = UDim2.new(1,-20,1,0); pLbl.Position = UDim2.new(0,14,0,0)
    pLbl.BackgroundTransparency = 1; pLbl.Text = "Dingus-Slayer"
    pLbl.TextColor3 = C.text; pLbl.TextXAlignment = Enum.TextXAlignment.Left
    pLbl.Font = FB; pLbl.TextSize = 13; pLbl.Parent = pill
    local pBtn = Instance.new("TextButton")
    pBtn.Size = UDim2.new(1,0,1,0); pBtn.BackgroundTransparency = 1
    pBtn.Text = ""; pBtn.Parent = pill

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

    -- Refresh loop
    local cache = {}
    task.spawn(function()
        while S.run do
            if S.boot and not minimized then
                local h = U.hum()
                local hp = h and string.format("%d/%d", math.floor(h.Health), math.floor(h.MaxHealth)) or "?"
                local st = tostring(S.cbtS or "—")
                local di = string.format(
                    "  state: %s\n  target: %s\n  hp: %s\n  kills: %d\n  fps: %.0f",
                    st, S.tgt and S.tgt.ch.Name or "none", hp, S.bKll or 0, S.fps or 60)
                if cache.di ~= di then cache.di = di; dashInfo.Text = di end

                local ci = string.format(
                    "  state: %s\n  hits: %d/%d\n  kills: %d\n  retreats: %d\n  threats: %d/%d\n  interval: %.2f",
                    st, S.aHi or 0, S.aAt or 0, S.bKll or 0, S.rtrC or 0,
                    S.imm or 0, S.zn or 0, S.aiI or 0)
                if cache.ci ~= ci then cache.ci = ci; combatInfo.Text = ci end

                if Ctx.Chest and Ctx.Chest.stats then
                    local cs = Ctx.Chest.stats()
                    local csi = string.format(
                        "  enabled: %s  learn: %s\n  whitelist: %d\n  session: %d/%d\n  collected: %d  failed: %d\n  killed: %s",
                        tostring(cs.enabled), tostring(cs.learnMode),
                        cs.whitelistSize, cs.sessionCount, cs.sessionCap,
                        cs.collected, cs.failed, tostring(cs.killed))
                    if cache.csi ~= csi then cache.csi = csi; chestStats.Text = csi end
                end

                if Ctx.Quest and Ctx.Quest.stats then
                    local qs = Ctx.Quest.stats()
                    local qi = string.format(
                        "  level: %d\n  priority: %d\n  %s\n  crow: %s",
                        qs.level, qs.priorityCount,
                        qs.priority ~= "" and qs.priority or "(none)",
                        qs.crowTool)
                    if cache.qi ~= qi then cache.qi = qi; questInfo.Text = qi end
                end

                local ri = string.format(
                    "  platform: %s\n  executor: %s\n  input: %s\n  mouse: %s\n  http: %s",
                    U.Platform, U.Executor, U.InputBackend, U.MouseBackend, U.HttpMode)
                if cache.ri ~= ri then cache.ri = ri; runtimeInfo.Text = ri end

                local cap = string.format(
                    "  file: %s  headers: %s\n  proximity: %s  click: %s  touch: %s\n  gethui: %s  firesignal: %s",
                    tostring(U.Caps.file), tostring(U.Caps.httpHeaders),
                    tostring(U.Caps.proximity), tostring(U.Caps.click), tostring(U.Caps.touch),
                    tostring(U.Caps.gethui), tostring(U.Caps.firesignal))
                if cache.cap ~= cap then cache.cap = cap; capsInfo.Text = cap end
            end
            task.wait(0.35)
        end
    end)

    -- Input
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

    print(string.format("[Dingus][gui] v35 · %s · parent=%s · %dx%d",
        U.Platform, parentKind, WW, WH))
end

return G
