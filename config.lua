--[[
    Dingus-Slayer · config.lua
    Central settings store + JSON persistence.
    Every field used by attack/main/gui is declared here with a default.
]]--

local Cfg = {}

--============================================================
-- VERSION (bump when schema changes)
--============================================================
Cfg.VERSION = 1

--============================================================
-- COMBAT
--============================================================
Cfg.AtkRange       = 8       -- studs; melee hitbox begins here
Cfg.AtkInterval    = 0.55    -- base seconds between M1 clicks
Cfg.AtkIntMin      = 0.35    -- adaptive interval floor
Cfg.AtkIntMax      = 0.75    -- adaptive interval ceiling
Cfg.StunAtkInt     = 0.28    -- faster attack when enemy stunned
Cfg.HitWindow      = 12      -- samples used by adaptive tracker

--============================================================
-- MOVEMENT
--============================================================
Cfg.RunSpeed       = 32      -- WalkSpeed when chasing (default 16)
Cfg.CloseInSpeed   = 6       -- slow approach when enemy blocking/stunned
Cfg.MaxMoveTick    = 8       -- studs per tick when using CFrame nudge

--============================================================
-- RETREAT
--============================================================
Cfg.RetreatHP      = 0.35    -- retreat when HP drops below this fraction
Cfg.RetreatDelay   = 4.0     -- seconds spent running away
Cfg.RetreatClearHP = 0.65    -- stop retreating once HP exceeds this

--============================================================
-- SCANNING
--============================================================
Cfg.ScanTTL        = 1.2     -- boss scan cache TTL
Cfg.CrowCheckT     = 1.5     -- crow cycle interval
Cfg.QuestCycleT    = 5.0     -- BossHunts rescan interval

--============================================================
-- HOVER (used for underground positioning + optional combat hover)
--============================================================
Cfg.HoverHeight    = 20      -- studs above target if hover enabled
Cfg.HoverP         = 4000    -- BodyPosition proportional constant
Cfg.HoverD         = 700     -- BodyPosition derivative constant

--============================================================
-- UNDERGROUND EVASION
--============================================================
Cfg.UGDepth        = 22      -- studs below ground level
Cfg.UGTrigHP       = 0.55    -- dive trigger HP fraction
Cfg.UGMaxT         = 6       -- seconds maximum underground
Cfg.UGClearT       = 1.6     -- surfacing delay after threats clear

--============================================================
-- SKILLS
--============================================================
Cfg.SkillKeys      = { "Z", "X", "C", "V", "B" }
Cfg.SkillCooldowns = { 1.2, 2.0, 2.8, 3.6, 6.0 }
Cfg.RotationOrder  = { 2, 1, 3, 4, 5 }

--============================================================
-- PULL
--============================================================
Cfg.PullRange      = 45
Cfg.MaxPull        = 12

--============================================================
-- PERSISTENCE
--============================================================
Cfg.ConfigFile     = "dingus_config.json"
Cfg.AutoSaveT      = 30      -- seconds between auto-saves

--============================================================
-- DEFAULT TOGGLES (session state, not persisted)
--============================================================
Cfg.DefaultToggles = {
    combat  = false,
    skl     = true,
    eqp     = true,
    rtr     = true,
    gsp     = true,
    crw     = true,
    stunPun = true,
}

--============================================================
-- FIELDS THAT GET SAVED / LOADED
--============================================================
local PERSIST = {
    "AtkRange", "AtkInterval", "AtkIntMin", "AtkIntMax",
    "StunAtkInt", "HitWindow",
    "RunSpeed", "CloseInSpeed", "MaxMoveTick",
    "RetreatHP", "RetreatDelay", "RetreatClearHP",
    "ScanTTL", "CrowCheckT", "QuestCycleT",
    "HoverHeight", "HoverP", "HoverD",
    "UGDepth", "UGTrigHP", "UGMaxT", "UGClearT",
    "PullRange", "MaxPull", "AutoSaveT",
}

-- Snapshot of defaults for reset
local DEFAULTS = {}
for _, k in ipairs(PERSIST) do
    DEFAULTS[k] = Cfg[k]
end

--============================================================
-- HANDLERS
--============================================================
local U     -- utils module (injected)
local HttpS -- cached HttpService

local function http()
    if not HttpS then
        local ok, s = pcall(function() return game:GetService("HttpService") end)
        if ok then HttpS = s end
    end
    return HttpS
end

local function canWrite()
    return U and U.Fn and U.Fn.writefile ~= nil
end

local function canRead()
    if readfile then return true end
    return false
end

local function doRead(name)
    if not readfile then return nil end
    local ok, data = pcall(readfile, name)
    if ok then return data end
    return nil
end

function Cfg.setUtils(u)
    U = u
end

function Cfg.snapshot()
    local t = { _version = Cfg.VERSION, _saved_at = os.time() }
    for _, k in ipairs(PERSIST) do
        t[k] = Cfg[k]
    end
    return t
end

function Cfg.apply(data)
    if type(data) ~= "table" then
        return 0, "input not table"
    end
    local applied, skipped = 0, 0
    for _, k in ipairs(PERSIST) do
        local v = data[k]
        if v ~= nil then
            local expected = type(DEFAULTS[k])
            if type(v) == expected then
                Cfg[k] = v
                applied = applied + 1
            else
                skipped = skipped + 1
            end
        end
    end
    return applied, skipped
end

function Cfg.save()
    if not canWrite() then
        return false, "no writefile"
    end
    local s = http()
    if not s then
        return false, "no HttpService"
    end
    local data = Cfg.snapshot()
    local okE, encoded = pcall(function() return s:JSONEncode(data) end)
    if not okE or not encoded then
        return false, "encode failed: " .. tostring(encoded)
    end
    local okW, errW = pcall(U.Fn.writefile, Cfg.ConfigFile, encoded)
    if not okW then
        return false, "write failed: " .. tostring(errW)
    end
    return true, #encoded
end

function Cfg.load()
    if not canRead() then
        return false, "no readfile"
    end
    local raw = doRead(Cfg.ConfigFile)
    if not raw or #raw < 5 then
        return false, "empty or missing"
    end
    local s = http()
    if not s then
        return false, "no HttpService"
    end
    local okD, data = pcall(function() return s:JSONDecode(raw) end)
    if not okD or type(data) ~= "table" then
        return false, "decode failed: " .. tostring(data)
    end
    local applied, skipped = Cfg.apply(data)
    if applied == 0 then
        return false, "no fields applied"
    end
    return true, string.format("%d applied, %d skipped", applied, skipped)
end

function Cfg.reset()
    for _, k in ipairs(PERSIST) do
        Cfg[k] = DEFAULTS[k]
    end
    return true, "reset to defaults"
end

function Cfg.delete()
    if delfile then
        local ok = pcall(delfile, Cfg.ConfigFile)
        return ok
    end
    return false
end

function Cfg.exists()
    if isfile then
        local ok, r = pcall(isfile, Cfg.ConfigFile)
        if ok then return r end
    end
    return doRead(Cfg.ConfigFile) ~= nil
end

function Cfg.fileSize()
    local raw = doRead(Cfg.ConfigFile)
    return raw and #raw or 0
end

function Cfg.pretty()
    local lines = {}
    lines[#lines+1] = "=== Current Config ==="
    for _, k in ipairs(PERSIST) do
        local v = Cfg[k]
        local vs
        if type(v) == "number" then
            vs = string.format("%.3f", v)
            vs = vs:gsub("%.?0+$", "")
        else
            vs = tostring(v)
        end
        lines[#lines+1] = string.format("  %-16s = %s", k, vs)
    end
    return table.concat(lines, "\n")
end

function Cfg.list()
    return PERSIST
end

return Cfg
