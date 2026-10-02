-- Dingus-Slayer · utils.lua v4
-- Cross-device abstraction: PC · Mobile · Console
-- Every primitive the rest of the codebase needs lives here.

local U = {}

--============================================================
-- SERVICES
--============================================================
local function svc(n) local ok, s = pcall(game.GetService, game, n) return ok and s or nil end
U.Plr   = svc("Players")
U.Lp    = U.Plr and U.Plr.LocalPlayer
U.VIM   = svc("VirtualInputManager")
U.SG    = svc("StarterGui")
U.UIS   = svc("UserInputService")
U.RS    = svc("ReplicatedStorage")
U.CP    = svc("ContentProvider")
U.GuiSvc = svc("GuiService")
U.TS    = svc("TweenService")
U.Run   = svc("RunService")
U.HS    = svc("HttpService")
U.Name  = U.Lp and U.Lp.Name or "?"
U.PlaceId = game.PlaceId

while not U.Lp do task.wait(0.1); U.Lp = U.Plr and U.Plr.LocalPlayer end
U.Name = U.Lp.Name

--============================================================
-- PLATFORM DETECTION
--============================================================
local function detectPlatform()
    if not U.UIS then return "unknown" end
    local ok, touch = pcall(function() return U.UIS.TouchEnabled end)
    local ok2, kb = pcall(function() return U.UIS.KeyboardEnabled end)
    touch = ok and touch
    kb = ok2 and kb
    if kb and not touch then return "pc" end
    if touch and not kb then return "mobile" end
    if touch and kb then return "hybrid" end
    return "unknown"
end

U.Platform = detectPlatform()
U.IsMobile = U.Platform == "mobile" or U.Platform == "hybrid"
U.IsPC     = U.Platform == "pc"

--============================================================
-- EXECUTOR CAPABILITY PROBE
--============================================================
local function probe(name)
    if type(_G[name]) == "function" then return _G[name] end
    local ok, v = pcall(function() return getfenv()[name] end)
    return (ok and type(v) == "function") and v or nil
end

U.Fn = {
    mouse1click = probe("mouse1click"),
    mouse1press = probe("mouse1press"),
    mouse1release = probe("mouse1release"),
    mouse2click = probe("mouse2click"),
    mouse2press = probe("mouse2press"),
    mouse2release = probe("mouse2release"),
    keypress = probe("keypress"),
    keyrelease = probe("keyrelease"),
    mousemoverel = probe("mousemoverel"),
    mousemoveabs = probe("mousemoveabs"),
    setclipboard = probe("setclipboard"),
    writefile = probe("writefile"),
    readfile = probe("readfile"),
    isfile = probe("isfile"),
    delfile = probe("delfile"),
    listfiles = probe("listfiles"),
    makefolder = probe("makefolder"),
    identifyexecutor = probe("identifyexecutor"),
    fireproximityprompt = probe("fireproximityprompt"),
    fireclickdetector = probe("fireclickdetector"),
    firetouchinterest = probe("firetouchinterest"),
    gethui = probe("gethui"),
    request = probe("request"),
    http_request = probe("http_request"),
    hookmetamethod = probe("hookmetamethod"),
    setthreadidentity = probe("setthreadidentity"),
    getthreadidentity = probe("getthreadidentity"),
    firesignal = probe("firesignal"),
}

if type(syn) == "table" and type(syn.request) == "function" and not U.Fn.request then
    U.Fn.request = syn.request
end
if type(http) == "table" and type(http.request) == "function" and not U.Fn.request then
    U.Fn.request = http.request
end

U.Caps = {
    vim = U.VIM ~= nil,
    mouseFn = U.Fn.mouse1click ~= nil,
    keyFn = U.Fn.keypress ~= nil,
    file = U.Fn.writefile ~= nil and U.Fn.readfile ~= nil,
    httpHeaders = U.Fn.request ~= nil or U.Fn.http_request ~= nil,
    proximity = U.Fn.fireproximityprompt ~= nil,
    click = U.Fn.fireclickdetector ~= nil,
    touch = U.Fn.firetouchinterest ~= nil,
    gethui = U.Fn.gethui ~= nil,
    firesignal = U.Fn.firesignal ~= nil or type(firesignal) == "function",
}

U.Executor = "unknown"
if U.Fn.identifyexecutor then
    local ok, name = pcall(U.Fn.identifyexecutor)
    if ok and type(name) == "string" then U.Executor = name end
end

--============================================================
-- KEY ENUMS
--============================================================
U.Keys = {
    F = Enum.KeyCode.F, Q = Enum.KeyCode.Q, L = Enum.KeyCode.L,
    Z = Enum.KeyCode.Z, X = Enum.KeyCode.X, C = Enum.KeyCode.C,
    V = Enum.KeyCode.V, B = Enum.KeyCode.B, G = Enum.KeyCode.G,
    W = Enum.KeyCode.W, A = Enum.KeyCode.A, S = Enum.KeyCode.S, D = Enum.KeyCode.D,
    Space = Enum.KeyCode.Space, LeftShift = Enum.KeyCode.LeftShift,
    LeftControl = Enum.KeyCode.LeftControl, One = Enum.KeyCode.One,
    Two = Enum.KeyCode.Two, Three = Enum.KeyCode.Three,
    Four = Enum.KeyCode.Four, Five = Enum.KeyCode.Five,
    T = Enum.KeyCode.T, E = Enum.KeyCode.E,
}
U.VK = {
    F=0x46, Q=0x51, L=0x4C, Z=0x5A, X=0x58, C=0x43, V=0x56, B=0x42, G=0x47,
    W=0x57, A=0x41, S=0x53, D=0x44, Space=0x20, LeftShift=0x10, LeftControl=0x11,
    One=0x31, Two=0x32, Three=0x33, Four=0x34, Five=0x35, T=0x54, E=0x45,
}

--============================================================
-- INPUT — dual backend, PC + Mobile
--============================================================
-- Backend selection
local backend = "none"
if U.VIM then backend = "vim"
elseif U.Fn.keypress then backend = "vk" end
U.InputBackend = backend

local function screenPoint()
    if not U.UIS then return 400, 300 end
    local ok, vp = pcall(function() return U.UIS:GetViewportSize() end)
    if not ok or not vp then return 400, 300 end
    return math.floor(vp.X / 2), math.floor(vp.Y / 2)
end

function U.keyDown(k)
    local code = type(k) == "string" and U.Keys[k] or k
    local vk = type(k) == "string" and U.VK[k] or nil
    if backend == "vim" and code then
        local ok = pcall(function() U.VIM:SendKeyEvent(true, code, false, game) end)
        if ok then return true end
    end
    if backend == "vk" and vk then
        return pcall(U.Fn.keypress, vk)
    end
    return false
end

function U.keyUp(k)
    local code = type(k) == "string" and U.Keys[k] or k
    local vk = type(k) == "string" and U.VK[k] or nil
    if backend == "vim" and code then
        pcall(function() U.VIM:SendKeyEvent(false, code, false, game) end)
    end
    if backend == "vk" and vk then
        pcall(U.Fn.keyrelease, vk)
    end
end

function U.tap(k, hold)
    U.keyDown(k)
    task.wait(hold or 0.03)
    U.keyUp(k)
end

--============================================================
-- MOBILE SKILL BUTTONS
-- Project Slayers 2 exposes skill buttons under
-- PlayerGui.ComponentsHolder.BottomHolder.SkillsHolder.
-- Each child has a KeyLabel (Z/X/C/V/F/B/...) and a GuiButton.
--============================================================
local function findSkillButton(label)
    local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    local ch = pg:FindFirstChild("ComponentsHolder")
    if not ch then return nil end
    local bh = ch:FindFirstChild("BottomHolder")
    if not bh then return nil end
    local sh = bh:FindFirstChild("SkillsHolder")
    if not sh then return nil end
    for _, child in ipairs(sh:GetChildren()) do
        local kl = child:FindFirstChild("KeyLabel", true)
        if kl and kl.Text == label then
            return child:FindFirstChildWhichIsA("GuiButton", true), child
        end
    end
    return nil
end

function U.fireSignal(sig)
    if U.Fn.firesignal then
        local ok = pcall(U.Fn.firesignal, sig)
        if ok then return true end
    end
    if type(firesignal) == "function" then
        local ok = pcall(firesignal, sig)
        if ok then return true end
    end
    -- fallback: Fire the signal directly
    local ok = pcall(function() sig:Fire() end)
    return ok
end

-- Fires a skill. Prefers the on-screen button (mobile + PC both work)
-- then falls back to key simulation.
function U.fireSkill(label)
    if not label then return false end
    local btn = findSkillButton(label)
    if btn then
        U.fireSignal(btn.MouseButton1Down)
        task.wait(0.04)
        U.fireSignal(btn.MouseButton1Up)
        return true
    end
    return U.tap(label, 0.05)
end

function U.hasSkillButton(label)
    return findSkillButton(label) ~= nil
end

--============================================================
-- MOUSE
--============================================================
local mouseBackend = "none"
if U.Fn.mouse1click then mouseBackend = "fn"
elseif U.VIM then mouseBackend = "vim" end
U.MouseBackend = mouseBackend

local function vimMouse(btn, down)
    local x, y = screenPoint()
    -- On mobile, aim slightly right of center where the attack button lives
    if U.IsMobile then x = x + math.floor((U.UIS:GetViewportSize().X or 800) * 0.25) end
    pcall(function()
        U.VIM:SendMouseButtonEvent(x, y, btn, down, game, 0)
    end)
end

function U.m1()
    if mouseBackend == "fn" then
        if pcall(U.Fn.mouse1click) then return true end
    end
    if mouseBackend == "vim" then
        vimMouse(0, true); task.wait(0.04); vimMouse(0, false)
        return true
    end
    return false
end

function U.m2()
    if U.Fn.mouse2click then
        if pcall(U.Fn.mouse2click) then return true end
    end
    if U.Fn.mouse2press and U.Fn.mouse2release then
        pcall(U.Fn.mouse2press); task.wait(0.03); pcall(U.Fn.mouse2release)
        return true
    end
    if mouseBackend == "vim" then
        vimMouse(1, true); task.wait(0.04); vimMouse(1, false)
        return true
    end
    return false
end

--============================================================
-- PROXIMITY PROMPT — 4-tier fallback
--============================================================
function U.firePrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    -- 1: executor function
    if U.Fn.fireproximityprompt then
        if pcall(U.Fn.fireproximityprompt, prompt) then return true end
    end
    -- 2: InputHoldBegin / End
    if type(prompt.InputHoldBegin) == "function" then
        local ok = pcall(function()
            prompt:InputHoldBegin()
            task.wait(math.min(prompt.HoldDuration or 0.1, 0.4))
            prompt:InputHoldEnd()
        end)
        if ok then return true end
    end
    -- 3: keyboard key code
    if prompt.KeyboardKeyCode and prompt.KeyboardKeyCode ~= Enum.KeyCode.Unknown then
        if U.tap(prompt.KeyboardKeyCode, 0.06) then return true end
    end
    -- 4: fire the trigger signal if exposed
    local ok = pcall(function()
        local trig = prompt:FindFirstChild("Triggered")
        if trig then U.fireSignal(trig) end
    end)
    return ok
end

function U.fireClick(det)
    if not det or not det.Parent then return false end
    if U.Fn.fireclickdetector then
        return pcall(U.Fn.fireclickdetector, det)
    end
    local ok = pcall(function() det.MouseClick:Fire() end)
    return ok
end

function U.touchInterest(a, b)
    if not U.Fn.firetouchinterest then return false end
    pcall(U.Fn.firetouchinterest, a, b, 0)
    task.wait(0.03)
    pcall(U.Fn.firetouchinterest, a, b, 1)
    return true
end

--============================================================
-- HTTP — headers if request() is present, plain HttpGet otherwise
--============================================================
U.HttpMode = U.Fn.request and "request" or (U.Fn.http_request and "http_request" or "HttpGet")

function U.httpGet(url, headers)
    local reqHeaders = headers or {}
    if U.Fn.request then
        local ok, res = pcall(U.Fn.request, { Url = url, Method = "GET", Headers = reqHeaders })
        if ok and type(res) == "table" then
            local s = res.StatusCode or res.Status or res.status
            local b = res.Body or res.body
            local h = res.Headers or res.headers or {}
            if s == 304 then return nil, 304, h end
            if type(s) == "number" and s >= 200 and s < 300 and type(b) == "string" then
                return b, s, h
            end
        end
    end
    if U.Fn.http_request then
        local ok, res = pcall(U.Fn.http_request, { Url = url, Method = "GET", Headers = reqHeaders })
        if ok and type(res) == "table" then
            local b = res.Body or res.body
            if type(b) == "string" then return b, 200, {} end
        end
    end
    local ok, b = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(b) == "string" then return b, 200, {} end
    return nil, 0, {}
end

--============================================================
-- FILE API — full fallback to in-memory VFS
--============================================================
local memfs = {}

U.File = {
    write = function(path, data)
        if U.Fn.writefile then
            local ok = pcall(U.Fn.writefile, path, data)
            if ok then return true end
        end
        memfs[path] = data
        return true
    end,
    read = function(path)
        if U.Fn.readfile then
            local ok, d = pcall(U.Fn.readfile, path)
            if ok and type(d) == "string" then return d end
        end
        return memfs[path]
    end,
    exists = function(path)
        if U.Fn.isfile then
            local ok, r = pcall(U.Fn.isfile, path)
            if ok then return r end
        end
        return memfs[path] ~= nil
    end,
    delete = function(path)
        if U.Fn.delfile then pcall(U.Fn.delfile, path) end
        memfs[path] = nil
        return true
    end,
    mkdir = function(path)
        if U.Fn.makefolder then
            pcall(U.Fn.makefolder, path)
        end
        return true
    end,
    list = function(dir)
        if U.Fn.listfiles then
            local ok, r = pcall(U.Fn.listfiles, dir)
            if ok and type(r) == "table" then return r end
        end
        local out = {}
        local prefix = dir .. "/"
        for k in pairs(memfs) do
            if k:sub(1, #prefix) == prefix then table.insert(out, k) end
        end
        return out
    end,
    persistent = U.Caps.file,
}

--============================================================
-- NOTIFICATIONS — SG with print fallback
--============================================================
U.NotifyRateLimited = false
local lastNotify = 0

function U.notify(title, text, dur)
    local now = os.clock()
    if now - lastNotify < 0.3 then return false end
    lastNotify = now
    if U.SG then
        local ok = pcall(function()
            U.SG:SetCore("SendNotification", {
                Title = tostring(title or "Dingus"),
                Text = tostring(text or ""),
                Duration = tonumber(dur) or 4,
            })
        end)
        if ok then return true end
    end
    print(string.format("[%s] %s", tostring(title), tostring(text)))
    return false
end

--============================================================
-- GUI PARENT — concealed if possible, else PlayerGui
--============================================================
function U.resolveGuiParent()
    if U.Fn.gethui then
        local ok, h = pcall(U.Fn.gethui)
        if ok and h then return h, "gethui" end
    end
    if U.IsMobile then
        -- Some mobile executors don't populate CoreGui for scripts; PlayerGui is safest
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if pg then return pg, "PlayerGui" end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg, "CoreGui" end
    return U.Lp:WaitForChild("PlayerGui"), "PlayerGui"
end

--============================================================
-- CHARACTER / MATH / MISC
--============================================================
function U.hum()
    local c = U.Lp and U.Lp.Character
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end

function U.hrp()
    local c = U.Lp and U.Lp.Character
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end

function U.isPlayer(c)
    if not U.Plr or not c then return false end
    local ok, r = pcall(function() return U.Plr:GetPlayerFromCharacter(c) ~= nil end)
    return ok and r or false
end

function U.xzDist(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

function U.round(n, d)
    d = d or 0
    local m = 10 ^ d
    return math.floor(n * m + 0.5) / m
end

function U.clock() return os.clock() end
function U.date() return os.date("%H:%M:%S") end

function U.groundState()
    local h = U.hum(); if not h then return end
    pcall(function()
        local s = h:GetState()
        if s == Enum.HumanoidStateType.Freefall
            or s == Enum.HumanoidStateType.Ragdoll
            or s == Enum.HumanoidStateType.FallingDown
            or s == Enum.HumanoidStateType.Physics then
            h:ChangeState(Enum.HumanoidStateType.Running)
        end
        h.PlatformStand = false
    end)
end

function U.isCrowName(nm)
    if not nm then return false end
    local l = string.lower(nm)
    return l:find("crow", 1, true) ~= nil or l:find("kasugai", 1, true) ~= nil
end

function U.isBossName(nm, list)
    if not nm or not list then return false end
    local l = string.lower(nm)
    for i = 1, #list do
        if l:find(list[i], 1, true) then return true end
    end
    return false
end

function U.walkTree(root, maxDepth, perNode, yieldEvery)
    if not root then return end
    yieldEvery = yieldEvery or 2500
    perNode = perNode or function() end
    local stack = { { root, 0 } }
    local iter = 0
    while #stack > 0 do
        local item = table.remove(stack)
        local inst, d = item[1], item[2]
        if inst and d <= maxDepth then
            pcall(perNode, inst, d)
            local ok, kids = pcall(function() return inst:GetChildren() end)
            if ok and kids then
                for i = 1, #kids do table.insert(stack, { kids[i], d + 1 }) end
            end
            iter = iter + 1
            if iter % yieldEvery == 0 then task.wait() end
        end
    end
end

function U.copy(text)
    if U.Fn.setclipboard then return pcall(U.Fn.setclipboard, text) end
    return false
end

function U.retry(fn, tries, delay)
    tries = tries or 3
    delay = delay or 0.1
    for i = 1, tries do
        local ok, res = pcall(fn)
        if ok and res then return res end
        if i < tries then task.wait(delay) end
    end
    return nil
end

function U.safe(fn, ...)
    local ok, res = pcall(fn, ...)
    return ok and res or nil
end

function U.report()
    local r = {}
    local function add(k, v) r[#r+1] = string.format("%-16s %s", k, tostring(v)) end
    add("executor", U.Executor)
    add("platform", U.Platform)
    add("placeId", U.PlaceId)
    add("input", U.InputBackend)
    add("mouse", U.MouseBackend)
    add("httpMode", U.HttpMode)
    add("fileAPI", U.Caps.file)
    add("headers", U.Caps.httpHeaders)
    add("proximity", U.Caps.proximity)
    add("click", U.Caps.click)
    add("gethui", U.Caps.gethui)
    add("firesignal", U.Caps.firesignal)
    return table.concat(r, "\n")
end

return U
