--[[
    Dingus-Slayer · config.lua v6
    Adds loot system keys. No schema break.
]]--

local Cfg = {}

Cfg.VERSION = 6

-- COMBAT
Cfg.AtkRange       = 8
Cfg.AtkInterval    = 0.38
Cfg.AtkIntMin      = 0.22
Cfg.AtkIntMax      = 0.65
Cfg.StunAtkInt     = 0.20
Cfg.HitWindow      = 15

Cfg.RunSpeed       = 16
Cfg.CloseInSpeed   = 6
Cfg.MaxMoveTick    = 8

Cfg.RetreatHP       = 0.55
Cfg.CriticalHP      = 0.15
Cfg.RetreatDelay    = 2.5
Cfg.RetreatClearHP  = 0.75

Cfg.ScanTTL        = 1.2
Cfg.CrowCheckT     = 2.5
Cfg.QuestCycleT    = 6.0

Cfg.HoverEnabled   = true
Cfg.HoverDistance  = 8
Cfg.HoverHeight    = 2
Cfg.HoverP         = 12000
Cfg.HoverD         = 900
Cfg.HoverTTL       = 0.05
Cfg.HoverRecalcT   = 0.15

Cfg.UGDepth        = 22
Cfg.UGTrigHP       = 0.55
Cfg.UGMaxT         = 6
Cfg.UGClearT       = 1.6

Cfg.SkillKeys      = { "F", "Z", "X", "C", "V", "B" }
Cfg.SkillCooldowns = { 0.5, 1.2, 2.0, 2.8, 3.6, 6.0 }
Cfg.SkillUnlocked  = { true, true, true, true, true, true }
Cfg.RotationOrder  = { 2, 3, 4, 5, 6 }

Cfg.GCDWindow      = 1.10

Cfg.ComboOrderCount = 4
Cfg.ComboReshuffleN = 3

Cfg.DetectHoldSkills    = true
Cfg.HoldProbeDuration   = 1.30
Cfg.HoldCastDuration    = 1.20
Cfg.HoldOverride        = {}

Cfg.AutoBlockOnDamage   = true
Cfg.BlockReactionWindow = 1.50
Cfg.BlockGraceRelease   = 0.35

Cfg.EmergencyHP         = 0.30
Cfg.EmergencyInterval   = 0.15

-- LOOT (new in v6)
Cfg.ChestEnabled        = true
Cfg.LootRadius          = 30
Cfg.LootMaxPasses       = 4
Cfg.LootPassDeadline    = 8
Cfg.LootPromptDepth     = 4
Cfg.LootTargetCooldown  = 45
Cfg.LootVerbose         = false
--============================================================
-- CHEST DETECTION
-- Matched against ProximityPrompt ObjectText + ActionText.
--============================================================
Cfg.ChestKeywords       = {
    -- Standard map chests
    "chest", "common chest", "rare chest", "lost chest",
    -- Biome chests
    "ice chest", "snow chest", "sealed chest",
    -- Boss drops
    "demon chest", "ouwigahara chest", "world events chest",
    -- Generic containers
    "cache", "crate", "chestbox", "lootbox",
}

--============================================================
-- LOOT DETECTION
-- Every item, material, currency, accessory, consumable
-- and event drop that appears as a ground ProximityPrompt
-- after a chest opens or a boss dies.
--============================================================
Cfg.LootKeywords        = {
    -- Currency
    "coin", "wen", "yen", "pouch", "coin pouch", "wen pouch",
    -- Materials
    "ore", "metal scrap", "scrap", "refinement", "refinement ore",
    "silk thread", "silk", "iron ingot", "forged ingot",
    "plating", "weaver", "crystal", "ingot",
    -- Consumables
    "elixir", "potion", "gourd", "regen",
    -- Accessories + equipment (World Events Chest drops)
    "lantern", "demonic lantern",
    "haori", "stylish haori",
    "robe", "necklace", "earring", "ring", "mask", "circlet",
    "accessory", "accessories", "cosmetic",
    -- Event / reroll tokens
    "token", "reroll", "voucher", "ticket",
    -- Legacy / generic
    "relic", "orb", "scroll", "totem", "artifact",
    -- Generic pickup verbs (fallback matching)
    "pickup", "pick up", "drop", "loot", "item", "collect",
    "bag", "satchel", "bundle",
}

Cfg.FKeyMode       = "auto"
Cfg.AutoBlock      = true
Cfg.BlockHoldTTL   = 0.4
Cfg.BlockProbeWait = 0.15

Cfg.TeleportCd         = 0.22
Cfg.TeleportStrike     = 4.5
Cfg.TeleportHeight     = 3
Cfg.TeleportJitter     = 2
Cfg.TeleportWalkBlend  = 0.6

Cfg.ComboBurst         = 4
Cfg.ComboGap           = 0.11
Cfg.DodgeCooldown      = 0.65
Cfg.InRangeChaseT      = 0.22
Cfg.TelegraphWindow    = 0.45
Cfg.M1MaxHz            = 10

Cfg.PullRange      = 45
Cfg.MaxPull        = 12

-- Fly (legacy)
Cfg.FlySpeed       = 85
Cfg.FlySpeedBoost  = 40
Cfg.FlyJitter      = 2
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

-- Spoofers
Cfg.SpoofWriteHz          = 10
Cfg.SpoofVerbose          = false
Cfg.SpoofSpeedMult        = 1.25
Cfg.SpoofJumpMult         = 1.15
Cfg.SpoofAntiKnock        = false
Cfg.SpoofKnockThreshold   = 150
Cfg.SpoofFlingThreshold   = 400
Cfg.SpoofVoidYThreshold   = -300
Cfg.SpoofAFKInterval      = 25
Cfg.SpoofBaseWalk         = nil
Cfg.SpoofBaseJump         = nil
Cfg.SpoofBaseGravity      = nil
Cfg.SpoofLoadoutTool      = nil
Cfg.SpoofMethods          = {
    antiSlow = true, antiFreeze = true, antiFall = true,
    spoofWalkSpeed = true, spoofJumpPower = true,
    spoofHipHeight = false, spoofGravity = false,
    spoofBlock = true, spoofMaxHealth = false,
    antiStun = true, antiRagdoll = false,
    antiKnock = false, antiFling = false,
    antiBlind = true, antiFog = true, antiDark = true,
    antiShake = true, antiColor = true,
    antiDeafen = false, antiScream = false,
    antiSit = true, antiTeleportBack = false,
    antiVoid = true, antiState = true,
    antiAFK = true, antiUnequip = false,
    antiToolDrain = false, antiLoadout = false,
    antiNametag = false, antiHighlight = false,
    antiSpectate = true,
}

-- Scanners
Cfg.CrowMenuCooldown = 30
Cfg.CrowScanMinGap   = 0.3
Cfg.CrowModelTTL     = 2.0
Cfg.CrowAcceptLabels = {
    "accept", "accept quest", "take", "take quest",
    "yes", "confirm", "eliminate", "hunt", "begin", "start",
}
Cfg.CrowCancelLabels = { "cancel", "close", "back", "exit", "dismiss" }

-- Quests
Cfg.QuestCrowHotbar     = "5"
Cfg.QuestMenuWait       = 2.5
Cfg.QuestLogStructure   = true
Cfg.QuestPriorityStale  = 90
Cfg.QuestReadOnOpen     = true
Cfg.QuestVerbose        = false
Cfg.QuestPanelCacheT    = 1.0
Cfg.QuestCrowCacheT     = 2.0

-- GUI
Cfg.GuiPanicKey1   = "RightControl"
Cfg.GuiPanicKey2   = "Backspace"
Cfg.GuiConcealed   = true
Cfg.GuiPanicHide   = true

-- Toggles
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

-- Persistence
Cfg.ConfigFile       = "dingus_config.json"
Cfg.AutoSaveT        = 30
Cfg.AutoSaveOnEdit   = true
Cfg.AutoSaveDebounce = 0.25

--============================================================
-- PERSIST LIST
--============================================================
local PERSIST = {
    -- Combat
    "AtkRange", "AtkInterval", "AtkIntMin", "AtkIntMax",
    "StunAtkInt", "HitWindow",
    "RunSpeed", "CloseInSpeed", "MaxMoveTick",
    "RetreatHP", "CriticalHP", "RetreatDelay", "RetreatClearHP",
    "ScanTTL", "CrowCheckT", "QuestCycleT",
    -- Hover
    "HoverEnabled", "HoverDistance", "HoverHeight", "HoverP", "HoverD",
    "HoverTTL", "HoverRecalcT",
    -- Underground
    "UGDepth", "UGTrigHP", "UGMaxT", "UGClearT",
    -- Skills
    "SkillUnlocked", "RotationOrder", "GCDWindow",
    "ComboOrderCount", "ComboReshuffleN",
    -- Hold detection
    "DetectHoldSkills", "HoldProbeDuration", "HoldCastDuration", "HoldOverride",
    -- Auto-block
    "AutoBlockOnDamage", "BlockReactionWindow", "BlockGraceRelease",
    "AutoBlock", "BlockHoldTTL", "BlockProbeWait",
    -- Emergency
    "EmergencyHP", "EmergencyInterval",
    -- Loot (new)
    "ChestEnabled", "LootRadius", "LootMaxPasses", "LootPassDeadline",
    "LootPromptDepth", "LootTargetCooldown", "LootVerbose",
    "ChestKeywords", "LootKeywords",
    -- F-mode
    "FKeyMode",
    -- Teleport
    "TeleportCd", "TeleportStrike", "TeleportHeight",
    "TeleportJitter", "TeleportWalkBlend",
    -- Combo
    "ComboBurst", "ComboGap", "DodgeCooldown",
    "InRangeChaseT", "TelegraphWindow", "M1MaxHz",
    -- Pull
    "PullRange", "MaxPull",
    -- Fly
    "FlySpeed", "FlySpeedBoost", "FlyJitter", "FlyJitterHz",
    "FlyHeight", "FlyMaxForce", "FlyP", "FlyD",
    "FlyArriveDist", "FlyMinSpeed", "FlyParentHead",
    "FlyDetachCam", "FlyVerbose",
    -- Spoofers
    "SpoofWriteHz", "SpoofVerbose", "SpoofSpeedMult",
    "SpoofJumpMult", "SpoofAntiKnock", "SpoofKnockThreshold",
    "SpoofFlingThreshold", "SpoofVoidYThreshold",
    "SpoofAFKInterval", "SpoofMethods", "SpoofLoadoutTool",
    -- Scanners
    "CrowMenuCooldown", "CrowScanMinGap", "CrowModelTTL",
    "CrowAcceptLabels", "CrowCancelLabels",
    -- Quests
    "QuestCrowHotbar", "QuestMenuWait", "QuestLogStructure",
    "QuestPriorityStale", "QuestReadOnOpen", "QuestVerbose",
    "QuestPanelCacheT", "QuestCrowCacheT",
    -- GUI
    "GuiPanicKey1", "GuiPanicKey2", "GuiConcealed", "GuiPanicHide",
    -- Persistence
    "AutoSaveT", "AutoSaveOnEdit", "AutoSaveDebounce",
}

--============================================================
-- DEFAULTS SNAPSHOT
--============================================================
local DEFAULTS = {}
for _, k in ipairs(PERSIST) do
    local v = Cfg[k]
    if type(v) == "table" then
        local copy = {}
        for kk, vv in pairs(v) do copy[kk] = vv end
        DEFAULTS[k] = copy
    else
        DEFAULTS[k] = v
    end
end

local U, HttpS
local dirty = false
local lastSaveAttempt = 0
local saveInFlight = false
local observers = {}

local function fireObservers(key, value)
    local list = observers[key]
    if not list then return end
    for i = 1, #list do
        pcall(list[i], value)
    end
end

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

local function snapshot()
    local t = { _version = Cfg.VERSION, _saved_at = os.time() }
    for _, k in ipairs(PERSIST) do
        local v = Cfg[k]
        if type(v) == "table" then
            local copy = {}
            for kk, vv in pairs(v) do copy[kk] = vv end
            t[k] = copy
        else
            t[k] = v
        end
    end
    return t
end

function Cfg.save(slot)
    if saveInFlight then return false, "save in flight" end
    if not U or not U.Fn or not U.Fn.writefile then return false, "no writefile" end
    local s = http()
    if not s then return false, "no HttpService" end

    saveInFlight = true
    local okE, encoded = pcall(function() return s:JSONEncode(snapshot()) end)
    if not okE or not encoded then
        saveInFlight = false
        return false, "encode failed"
    end
    local okW = pcall(U.Fn.writefile, Cfg.slotFile(slot), encoded)
    saveInFlight = false
    if not okW then return false, "write failed" end
    dirty = false
    lastSaveAttempt = os.clock()
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
    local applied = 0
    for _, k in ipairs(PERSIST) do
        local v = data[k]
        if v ~= nil and (Cfg[k] == nil or type(v) == type(Cfg[k])) then
            Cfg[k] = v
            applied = applied + 1
        end
    end
    if applied == 0 then return false, "nothing applied" end
    dirty = false
    return true, string.format("%d applied", applied)
end

function Cfg.apply(data)
    if type(data) ~= "table" then return 0 end
    local applied = 0
    for _, k in ipairs(PERSIST) do
        local v = data[k]
        if v ~= nil and (Cfg[k] == nil or type(v) == type(Cfg[k])) then
            Cfg[k] = v
            applied = applied + 1
        end
    end
    return applied
end

function Cfg.reset()
    for _, k in ipairs(PERSIST) do
        local v = DEFAULTS[k]
        if type(v) == "table" then
            local copy = {}
            for kk, vv in pairs(v) do copy[kk] = vv end
            Cfg[k] = copy
        else
            Cfg[k] = v
        end
        fireObservers(k, Cfg[k])
    end
    dirty = true
    return true
end

function Cfg.delete(slot)
    if not U or not U.Fn or not U.Fn.delfile then return false end
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

function Cfg.set(key, value)
    if Cfg[key] == nil and DEFAULTS[key] == nil then
        return false, "unknown key: " .. tostring(key)
    end
    Cfg[key] = value
    dirty = true
    fireObservers(key, value)
    return true
end

function Cfg.touch(key)
    dirty = true
    fireObservers(key, Cfg[key])
end

function Cfg.observe(key, fn)
    if type(fn) ~= "function" then return false end
    observers[key] = observers[key] or {}
    table.insert(observers[key], fn)
    return true
end

function Cfg.tickAutoSave()
    if not dirty then return end
    if not Cfg.AutoSaveOnEdit then return end
    local now = os.clock()
    local debounce = Cfg.AutoSaveDebounce or 0.25
    if now - lastSaveAttempt < debounce then return end
    Cfg.save("default")
end

local function formatValue(v)
    if type(v) == "number" then
        return (string.format("%.3f", v):gsub("%.?0+$", ""))
    elseif type(v) == "boolean" then
        return tostring(v)
    elseif type(v) == "table" then
        local parts, count = {}, 0
        for k, vv in pairs(v) do
            count = count + 1
            if count > 8 then table.insert(parts, "..."); break end
            if type(k) == "number" then
                table.insert(parts, tostring(vv))
            else
                table.insert(parts, k .. "=" .. tostring(vv))
            end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif type(v) == "nil" then
        return "nil"
    else
        return tostring(v)
    end
end

function Cfg.pretty()
    local lines = {
        "=== Current Config ===",
        string.format("  version: %d  ·  file: %s", Cfg.VERSION, Cfg.slotFile("default")),
        "",
    }
    for _, k in ipairs(PERSIST) do
        lines[#lines+1] = string.format("  %-22s = %s", k, formatValue(Cfg[k]))
    end
    return table.concat(lines, "\n")
end

return Cfg
