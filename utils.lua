--[[
    Dingus-Slayer · utils.lua
    Safe service loading, capability probing, nil-guarded helpers.
    Never throws during module load — everything wrapped.
]]--

local U = {}

--============================================================
-- SAFE SERVICE LOADER
--============================================================
local function svc(name)
    local ok, s = pcall(function() return game:GetService(name) end)
    return ok and s or nil
end

local Plr = svc("Players")
local VIM = svc("VirtualInputManager")
local SG  = svc("StarterGui")
local UIS = svc("UserInputService")
local RS  = svc("ReplicatedStorage")
local CP  = svc("ContentProvider")

local Lp = Plr and Plr.LocalPlayer

U.Plr = Plr
U.Lp = Lp
U.VIM = VIM
U.SG = SG
U.UIS = UIS
U.RS = RS
U.CP = CP
U.Name = Lp and Lp.Name or "?"

--============================================================
-- CAPABILITY PROBE
--============================================================
local function has(name)
    local f = _G[name]
    if type(f) == "function" then return true end
    local ok, v = pcall(function() return getfenv()[name] end)
    return ok and type(v) == "function"
end

local function grab(name)
    if type(_G[name]) == "function" then return _G[name] end
    local ok, v = pcall(function() return getfenv()[name] end)
    return ok and v or nil
end

U.Fn = {
    mouse1click   = grab("mouse1click"),
    mouse1press   = grab("mouse1press"),
    mouse1release = grab("mouse1release"),
    keypress      = grab("keypress"),
    keyrelease    = grab("keyrelease"),
    mousemoverel  = grab("mousemoverel"),
    setclipboard  = grab("setclipboard"),
    writefile     = grab("writefile"),
    identifyexecutor = grab("identifyexecutor"),
}

U.Caps = {
    mouse1click   = has("mouse1click"),
    mouse1press   = has("mouse1press"),
    keypress      = has("keypress"),
    VIM           = VIM ~= nil,
    setclipboard  = has("setclipboard"),
    writefile     = has("writefile"),
}

--============================================================
-- KEY ENUMS
--============================================================
U.Keys = {
    F = Enum.KeyCode.F, Q = Enum.KeyCode.Q, L = Enum.KeyCode.L,
    Z = Enum.KeyCode.Z, X = Enum.KeyCode.X, C = Enum.KeyCode.C,
    V = Enum.KeyCode.V, B = Enum.KeyCode.B,
    W = Enum.KeyCode.W, A = Enum.KeyCode.A, S = Enum.KeyCode.S, D = Enum.KeyCode.D,
    Space = Enum.KeyCode.Space, LeftShift = Enum.KeyCode.LeftShift,
    LeftControl = Enum.KeyCode.LeftControl,
}

U.VK = {
    F = 0x46, Q = 0x51, L = 0x4C,
    Z = 0x5A, X = 0x58, C = 0x43, V = 0x56, B = 0x42,
    W = 0x57, A = 0x41, S = 0x53, D = 0x44,
    Space = 0x20, LeftShift = 0x10, LeftControl = 0x11,
}

--============================================================
-- CHARACTER
--============================================================
function U.hum()
    if not Lp then return nil end
    local c = Lp.Character
    if not c then return nil end
    return c:FindFirstChildOfClass("Humanoid")
end

function U.hrp()
    if not Lp then return nil end
    local c = Lp.Character
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart")
end

function U.isPlayer(c)
    if not Plr or not c then return false end
    local ok, r = pcall(function() return Plr:GetPlayerFromCharacter(c) ~= nil end)
    return ok and r or false
end

--============================================================
-- NAME MATCHERS
--============================================================
function U.isBossName(nm, list)
    if not nm or not list then return false end
    local l = string.lower(nm)
    for i = 1, #list do
        if string.find(l, list[i], 1, true) then return true end
    end
    return false
end

function U.isWeaponName(nm, wl, nwl)
    if not nm or not wl or not nwl then return false end
    local l = string.lower(nm)
    for i = 1, #nwl do
        if string.find(l, nwl[i], 1, true) then return false end
    end
    for i = 1, #wl do
        if string.find(l, wl[i], 1, true) then return true end
    end
    return false
end

function U.isCrowName(nm)
    if not nm then return false end
    local l = string.lower(nm)
    return string.find(l, "crow", 1, true) ~= nil
        or string.find(l, "kasugai", 1, true) ~= nil
end

--============================================================
-- MATH / TIME
--============================================================
function U.xzDist(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

function U.round(n, dec)
    dec = dec or 0
    local m = 10 ^ dec
    return math.floor(n * m + 0.5) / m
end

function U.clock() return os.clock() end
function U.date() return os.date("%H:%M:%S") end

--============================================================
-- INPUT
--============================================================
function U.keyDown(k)
    local kk = type(k) == "string" and U.Keys[k] or k
    local vk = type(k) == "string" and U.VK[k] or nil
    if VIM and kk then
        local ok = pcall(function() VIM:SendKeyEvent(true, kk, false, game) end)
        if ok then return true end
    end
    if U.Fn.keypress and vk then
        local ok = pcall(U.Fn.keypress, vk)
        if ok then return true end
    end
    return false
end

function U.keyUp(k)
    local kk = type(k) == "string" and U.Keys[k] or k
    local vk = type(k) == "string" and U.VK[k] or nil
    if VIM and kk then
        pcall(function() VIM:SendKeyEvent(false, kk, false, game) end)
    end
    if U.Fn.keyrelease and vk then
        pcall(U.Fn.keyrelease, vk)
    end
end

function U.tap(k)
    U.keyDown(k)
    task.wait(0.03)
    U.keyUp(k)
end

function U.m1()
    if U.Fn.mouse1click then
        if pcall(U.Fn.mouse1click) then return true end
    end
    if U.Fn.mouse1press and U.Fn.mouse1release then
        pcall(U.Fn.mouse1press)
        task.wait(0.03)
        pcall(U.Fn.mouse1release)
        return true
    end
    if VIM then
        pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0) end)
        task.wait(0.03)
        pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0) end)
        return true
    end
    return false
end

function U.detectInput()
    if U.Fn.mouse1click then
        if pcall(U.Fn.mouse1click) then return 1 end
    end
    if U.Fn.mouse1press and U.Fn.mouse1release then
        local ok = pcall(U.Fn.mouse1press)
        task.wait(0.03)
        pcall(U.Fn.mouse1release)
        if ok then return 2 end
    end
    if VIM then
        local ok = pcall(function()
            VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.03)
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
        if ok then return 3 end
    end
    return 0
end

--============================================================
-- HUMANOID STATE
--============================================================
function U.groundState()
    local h = U.hum()
    if not h then return end
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

--============================================================
-- TREE WALKER
--============================================================
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
                for i = 1, #kids do
                    table.insert(stack, { kids[i], d + 1 })
                end
            end
            iter = iter + 1
            if iter % yieldEvery == 0 then task.wait() end
        end
    end
end

--============================================================
-- CLIPBOARD / FILE
--============================================================
function U.copy(text)
    if not U.Fn.setclipboard then return false end
    return pcall(U.Fn.setclipboard, text)
end

function U.save(name, text)
    if not U.Fn.writefile then return false end
    return pcall(U.Fn.writefile, name, text)
end

--============================================================
-- NOTIFICATIONS
--============================================================
function U.notify(title, text, dur)
    if not SG then return end
    pcall(function()
        SG:SetCore("SendNotification", {
            Title = title, Text = text, Duration = dur or 5,
        })
    end)
end

--============================================================
-- RETRY HELPER
--============================================================
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

--============================================================
-- SAFE CALL (never throws, returns nil on failure)
--============================================================
function U.safe(fn, ...)
    local ok, res = pcall(fn, ...)
    return ok and res or nil
end

--============================================================
-- DIAGNOSTIC
--============================================================
function U.report()
    local r = {}
    r[#r+1] = "executor: " .. tostring(U.Fn.identifyexecutor and U.Fn.identifyexecutor() or "?")
    r[#r+1] = "place: " .. tostring(game.PlaceId)
    r[#r+1] = "player: " .. tostring(U.Name)
    r[#r+1] = "VIM: " .. tostring(VIM ~= nil)
    r[#r+1] = "UIS: " .. tostring(UIS ~= nil)
    r[#r+1] = "mouse1click: " .. tostring(U.Caps.mouse1click)
    r[#r+1] = "mouse1press: " .. tostring(U.Caps.mouse1press)
    r[#r+1] = "keypress: " .. tostring(U.Caps.keypress)
    r[#r+1] = "setclipboard: " .. tostring(U.Caps.setclipboard)
    r[#r+1] = "writefile: " .. tostring(U.Caps.writefile)
    return table.concat(r, "\n")
end

return U
