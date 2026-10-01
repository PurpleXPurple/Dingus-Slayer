--[[
    Dingus-Slayer · utils.lua
    Defensive service loading. Every external lookup is pcall-wrapped so one
    missing service doesn't kill the whole module.
]]--

local U = {}

-- Safe service loader — never throws
local function svc(name)
    local ok, s = pcall(function() return game:GetService(name) end)
    if ok then return s end
    return nil
end

local Plr = svc("Players")
local VIM = svc("VirtualInputManager")   -- ← this was the crash point on Xeno
local StarterGui = svc("StarterGui")
local UIS = svc("UserInputService")

local Lp = Plr and Plr.LocalPlayer

U.Plr = Plr
U.Lp = Lp
U.VIM = VIM

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
-- CHARACTER HELPERS
--============================================================
function U.hum()
    if not Lp then return nil end
    local c = Lp.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

function U.hrp()
    if not Lp then return nil end
    local c = Lp.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

function U.isPlayer(c)
    if not Plr then return false end
    return Plr:GetPlayerFromCharacter(c) ~= nil
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
-- MATH
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
-- INPUT (all pcall-wrapped, VIM optional)
--============================================================
function U.keyDown(vk, key)
    if VIM then
        local ok = pcall(function() VIM:SendKeyEvent(true, key, false, game) end)
        if ok then return true end
    end
    if keypress then
        local ok = pcall(keypress, vk)
        if ok then return true end
    end
    return false
end

function U.keyUp(vk, key)
    if VIM then pcall(function() VIM:SendKeyEvent(false, key, false, game) end) end
    if keyrelease then pcall(keyrelease, vk) end
end

function U.tap(vk, key)
    U.keyDown(vk, key)
    task.wait(0.03)
    U.keyUp(vk, key)
end

function U.m1()
    if mouse1click then
        if pcall(mouse1click) then return true end
    end
    if mouse1press and mouse1release then
        pcall(mouse1press)
        task.wait(0.03)
        pcall(mouse1release)
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
    local candidates = {
        function() if mouse1click then return pcall(mouse1click) end end,
        function()
            if mouse1press and mouse1release then
                local ok = pcall(mouse1press)
                task.wait(0.03)
                pcall(mouse1release)
                return ok
            end
        end,
        function()
            if VIM then
                local ok = pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0) end)
                task.wait(0.03)
                pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0) end)
                return ok
            end
        end,
    }
    for i = 1, #candidates do
        local ok = pcall(candidates[i])
        if ok then return i end
    end
    return 0
end

--============================================================
-- HUMAN STATE
--============================================================
function U.groundState()
    local h = U.hum()
    if not h then return end
    local st = h:GetState()
    if st == Enum.HumanoidStateType.Freefall
        or st == Enum.HumanoidStateType.Ragdoll
        or st == Enum.HumanoidStateType.FallingDown
        or st == Enum.HumanoidStateType.Physics then
        pcall(function() h:ChangeState(Enum.HumanoidStateType.Running) end)
    end
    pcall(function() h.PlatformStand = false end)
end

--============================================================
-- TREE WALKER (yields periodically)
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
            local ok = pcall(perNode, inst, d)
            if ok then
                local ok2, kids = pcall(function() return inst:GetChildren() end)
                if ok2 and kids then
                    for i = 1, #kids do
                        table.insert(stack, { kids[i], d + 1 })
                    end
                end
            end
            iter = iter + 1
            if iter % yieldEvery == 0 then task.wait() end
        end
    end
end

--============================================================
-- NOTIFICATIONS
--============================================================
function U.notify(title, text, dur)
    if not StarterGui then return end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title, Text = text, Duration = dur or 5,
        })
    end)
end

--============================================================
-- DIAGNOSTIC — dumps environment info for debugging
--============================================================
function U.diagnose()
    local info = {}
    info["executor"] = tostring(identifyexecutor and identifyexecutor() or "?")
    info["place_id"] = tostring(game.PlaceId)
    info["job_id"] = tostring(game.JobId):sub(1, 8)
    info["has_players"] = Plr ~= nil
    info["has_localplayer"] = Lp ~= nil
    info["has_vim"] = VIM ~= nil
    info["has_startergui"] = StarterGui ~= nil
    info["has_uinput"] = UIS ~= nil
    info["has_mouse1click"] = type(mouse1click) == "function"
    info["has_mouse1press"] = type(mouse1press) == "function"
    info["has_keypress"] = type(keypress) == "function"
    info["has_setclipboard"] = type(setclipboard) == "function"
    info["has_writefile"] = type(writefile) == "function"
    info["has_httpget"] = type(game.HttpGet) == "function"
    return info
end

return U
