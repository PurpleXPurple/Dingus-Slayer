local Cfg = {}

Cfg.VERSION = 1

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
Cfg.HoverDistance  = 8      -- studs behind the boss
Cfg.HoverHeight    = 2      -- studs above ground
Cfg.HoverP         = 12000  -- high P, holds position firmly
Cfg.HoverD         = 900    -- higher D, less oscillation
Cfg.HoverTTL       = 0.05   -- recompute position this often
Cfg.HoverRecalcT   = 0.15   -- full re-read of boss CFrame this often

-- UNDERGROUND EVASION
Cfg.UGDepth        = 22
Cfg.UGTrigHP       = 0.55
Cfg.UGMaxT         = 6
Cfg.UGClearT       = 1.6

-- SKILLS
Cfg.SkillKeys      = { "Z", "X", "C", "V", "B" }
Cfg.SkillCooldowns = { 1.2, 2.0, 2.8, 3.6, 6.0 }
Cfg.RotationOrder  = { 2, 1, 3, 4, 5 }

-- PULL
Cfg.PullRange      = 45
Cfg.MaxPull        = 12

-- PERSISTENCE
Cfg.ConfigFile     = "dingus_config.json"
Cfg.AutoSaveT      = 30

Cfg.DefaultToggles = {
    combat  = false,
    skl     = true,
    eqp     = true,
    rtr     = true,
    gsp     = true,
    crw     = true,
    stunPun = true,
    hover   = true,
}

local PERSIST = {
    "AtkRange", "AtkInterval", "AtkIntMin", "AtkIntMax",
    "StunAtkInt", "HitWindow",
    "RunSpeed", "CloseInSpeed", "MaxMoveTick",
    "RetreatHP", "RetreatDelay", "RetreatClearHP",
    "ScanTTL", "CrowCheckT", "QuestCycleT",
    "HoverEnabled", "HoverDistance", "HoverHeight", "HoverP", "HoverD",
    "UGDepth", "UGTrigHP", "UGMaxT", "UGClearT",
    "PullRange", "MaxPull", "AutoSaveT",
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

function Cfg.save()
    if not U or not U.Fn or not U.Fn.writefile then return false, "no writefile" end
    local s = http()
    if not s then return false, "no HttpService" end
    local okE, encoded = pcall(function() return s:JSONEncode(Cfg.snapshot()) end)
    if not okE or not encoded then return false, "encode failed" end
    local okW = pcall(U.Fn.writefile, Cfg.ConfigFile, encoded)
    if not okW then return false, "write failed" end
    return true, #encoded
end

function Cfg.load()
    if not readfile then return false, "no readfile" end
    local okR, raw = pcall(readfile, Cfg.ConfigFile)
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

function Cfg.delete()
    if delfile then return pcall(delfile, Cfg.ConfigFile) end
    return false
end

function Cfg.exists()
    if isfile then
        local ok, r = pcall(isfile, Cfg.ConfigFile)
        if ok then return r end
    end
    if readfile then
        local ok, raw = pcall(readfile, Cfg.ConfigFile)
        return ok and raw ~= nil
    end
    return false
end

function Cfg.fileSize()
    if readfile then
        local ok, raw = pcall(readfile, Cfg.ConfigFile)
        return ok and raw and #raw or 0
    end
    return 0
end

function Cfg.pretty()
    local lines = { "=== Current Config ===" }
    for _, k in ipairs(PERSIST) do
        local v = Cfg[k]
        local vs = type(v) == "number" and string.format("%.3f", v) or tostring(v)
        vs = vs:gsub("%.?0+$", "")
        lines[#lines+1] = string.format("  %-16s = %s", k, vs)
    end
    return table.concat(lines, "\n")
end

return Cfg
