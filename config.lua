--[[
    Dingus-Slayer · config.lua v4
    Adds: FKeyMode, AutoBlock, BlockHoldTTL, BlockProbeWait.
    No schema break — v3 files load, new keys default in.
    SkillKeys now has 6 entries (F is slot 1).
]]--

local Cfg = {}

Cfg.VERSION = 4

-- COMBAT
Cfg.AtkRange       = 8
Cfg.AtkInterval    = 0.55
Cfg.AtkIntMin      = 0.35
Cfg.AtkIntMax      = 0.75
Cfg.StunAtkInt     = 0.28
Cfg.HitWindow      = 12

-- MOVEMENT
Cfg.RunSpeed       = 32
Cfg.CloseInSpeed   = 6
Cfg.MaxMoveTick    = 8

-- RETREAT
Cfg.RetreatHP      = 0.35
Cfg.RetreatDelay   = 4.0
Cfg.RetreatClearHP = 0.65

-- SCANNING
Cfg.ScanTTL        = 1.2
Cfg.CrowCheckT     = 1.5
Cfg.QuestCycleT    = 5.0

-- HOVER-BEHIND
Cfg.HoverEnabled   = true
Cfg.HoverDistance  = 8
Cfg.HoverHeight    = 2
Cfg.HoverP         = 12000
Cfg.HoverD         = 900
Cfg.HoverTTL       = 0.05
Cfg.HoverRecalcT   = 0.15

-- UNDERGROUND (legacy)
Cfg.UGDepth        = 22
Cfg.UGTrigHP       = 0.55
Cfg.UGMaxT         = 6
Cfg.UGClearT       = 1.6

-- SKILLS · 6 slots (F at index 1)
Cfg.SkillKeys      = { "F", "Z", "X", "C", "V", "B" }
Cfg.SkillCooldowns = { 0.5, 1.2, 2.0, 2.8, 3.6, 6.0 }
-- Order excludes index 1 by default; auto-tuned at boot.
Cfg.RotationOrder  = { 2, 3, 4, 5, 6 }

-- F-KEY BEHAVIOR
-- "auto"  — probe once, cache result
-- "block" — force block mode (hold-to-block)
-- "skill" — force skill mode (F joins rotation)
Cfg.FKeyMode       = "auto"
Cfg.AutoBlock      = true
Cfg.BlockHoldTTL   = 0.6    -- seconds to keep holding after threat clears
Cfg.BlockProbeWait = 0.15   -- seconds to observe after probe tap

-- PULL
Cfg.PullRange      = 45
Cfg.MaxPull        = 12

-- FLY
Cfg.FlySpeed       = 85
Cfg.FlySpeedBoost  = 40
Cfg.FlyJitter      = 3
Cfg.FlyJitterHz    = 1.7
Cfg.FlyHeight      = 6
Cfg.FlyMaxForce    = 1e5
Cfg.FlyP           = 4000
Cfg.FlyD           = 1200
Cfg.FlyArriveDist  = 10
Cfg.FlyMinSpeed    = 40
Cfg.FlyParentHead  = false
Cfg.FlyDetachCam   = false
Cfg.FlyVerbose     = false

-- SPOOFERS
Cfg.SpoofSpeedMult = 1.25
Cfg.SpoofJumpMult  = 1.15
Cfg.SpoofWriteHz   = 5
Cfg.SpoofAntiKnock = false
Cfg.SpoofVerbose   = false

-- SCANNERS
Cfg.CrowMenuCooldown = 30
Cfg.CrowScanMinGap   = 0.3
Cfg.CrowModelTTL     = 2.0

-- PERSISTENCE
Cfg.ConfigFile     = "dingus_config.json"
Cfg.AutoSaveT      = 30

Cfg.DefaultToggles = {
    combat  = false,
    skl     = true,
    eqp     = true,
    rtr     = true,
    gsp     = false,
    crw     = true,
    stunPun = true,
    hover   = true,
}

-- PERSIST — every key that round-trips to disk.
-- Tables excluded (SkillKeys/Cooldowns/RotationOrder are structural).
local PERSIST = {
    "AtkRange", "AtkInterval", "AtkIntMin", "AtkIntMax",
    "StunAtkInt", "HitWindow",
    "RunSpeed", "CloseInSpeed", "MaxMoveTick",
    "RetreatHP", "RetreatDelay", "RetreatClearHP",
    "ScanTTL", "CrowCheckT", "QuestCycleT",
    "HoverEnabled", "HoverDistance", "HoverHeight", "HoverP", "HoverD",
    "UGDepth", "UGTrigHP", "UGMaxT", "UGClearT",
    "PullRange", "MaxPull", "AutoSaveT",
    "FlySpeed", "FlySpeedBoost", "FlyJitter", "FlyJitterHz",
    "FlyHeight", "FlyMaxForce", "FlyP", "FlyD",
    "FlyArriveDist", "FlyMinSpeed",
    "FlyParentHead", "FlyDetachCam", "FlyVerbose",
    "SpoofSpeedMult", "SpoofJumpMult", "SpoofWriteHz",
    "SpoofAntiKnock", "SpoofVerbose",
    "CrowMenuCooldown", "CrowScanMinGap", "CrowModelTTL",
    "FKeyMode", "AutoBlock", "BlockHoldTTL", "BlockProbeWait",
}

local DEFAULTS = {}
for _, k in ipairs(PERSIST) do DEFAULTS[k] = Cfg[k] end

local U, HttpS

local function http()
    if not HttpS then
        local ok, s = pcall(function() return game:GetService("HttpService") end)
        if ok then HttpS = s end
    end
    return HttpS
end

function Cfg.setUtils(u) U = u end

function Cfg.slotFile(slot)
    slot = slot or "default"
    if slot == "default" then return Cfg.ConfigFile end
    return "dingus_config_" .. slot .. ".json"
end

function Cfg.snapshot()
    local t = { _version = Cfg.VERSION, _saved_at = os.time() }
    for _, k in ipairs(PERSIST) do t[k] = Cfg[k] end
    return t
end

function Cfg.apply(data)
    if type(data) ~= "table" then return 0, 0 end
    local applied, skipped = 0, 0
    for _, k in ipairs(PERSIST) do
        local v = data[k]
        if v ~= nil then
            if type(v) == type(DEFAULTS[k]) then
                Cfg[k] = v
                applied = applied + 1
            else
                skipped = skipped + 1
            end
        end
    end
    return applied, skipped
end

function Cfg.save(slot)
    if not U or not U.Fn or not U.Fn.writefile then return false, "no writefile" end
    local s = http()
    if not s then return false, "no HttpService" end
    local okE, encoded = pcall(function() return s:JSONEncode(Cfg.snapshot()) end)
    if not okE or not encoded then return false, "encode failed" end
    local okW = pcall(U.Fn.writefile, Cfg.slotFile(slot), encoded)
    if not okW then return false, "write failed" end
    return true, #encoded
end

function Cfg.load(slot)
    if not U or not U.Fn or not U.Fn.readfile then return false, "no readfile" end
    local okR, raw = pcall(U.Fn.readfile, Cfg.slotFile(slot))
    if not okR or not raw or #raw < 5 then return false, "empty" end
    local s = http()
    if not s then return false, "no HttpService" end
    local okD, data = pcall(function() return s:JSONDecode(raw) end)
    if not okD or type(data) ~= "table" then return false, "decode failed" end
    local applied, skipped = Cfg.apply(data)
    if applied == 0 then return false, "nothing applied" end
    return true, string.format("%d applied", applied)
end

function Cfg.reset()
    for _, k in ipairs(PERSIST) do Cfg[k] = DEFAULTS[k] end
    return true
end

function Cfg.delete(slot)
    if not U or not U.Fn or not U.Fn.delfile then return false, "no delfile" end
    return pcall(U.Fn.delfile, Cfg.slotFile(slot))
end

function Cfg.exists(slot)
    if not U or not U.Fn then return false end
    if U.Fn.isfile then
        local ok, r = pcall(U.Fn.isfile, Cfg.slotFile(slot))
        if ok then return r end
    end
    if U.Fn.readfile then
        local ok, raw = pcall(U.Fn.readfile, Cfg.slotFile(slot))
        return ok and raw ~= nil
    end
    return false
end

function Cfg.fileSize(slot)
    if not U or not U.Fn or not U.Fn.readfile then return nil end
    local ok, raw = pcall(U.Fn.readfile, Cfg.slotFile(slot))
    if not ok or raw == nil then return nil end
    return #raw
end

function Cfg.pretty()
    local lines = { "=== Current Config ===" }
    for _, k in ipairs(PERSIST) do
        local v = Cfg[k]
        local vs
        if type(v) == "number" then
            vs = string.format("%.3f", v):gsub("%.?0+$", "")
        elseif type(v) == "boolean" then
            vs = tostring(v)
        elseif type(v) == "table" then
            local parts = {}
            for i, item in ipairs(v) do parts[i] = tostring(item) end
            vs = "{" .. table.concat(parts, ", ") .. "}"
        else
            vs = tostring(v)
        end
        lines[#lines+1] = string.format("  %-18s = %s", k, vs)
    end
    return table.concat(lines, "\n")
end

return Cfg
