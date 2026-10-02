-- Dingus-Slayer · config.lua v7
-- Cross-device persistence via U.File.

local Cfg = {}
Cfg.VERSION = 7

-- Combat
Cfg.AtkRange = 8
Cfg.AtkInterval = 0.38
Cfg.AtkIntMin = 0.22
Cfg.AtkIntMax = 0.65
Cfg.StunAtkInt = 0.20
Cfg.HitWindow = 15
Cfg.RunSpeed = 16
Cfg.CloseInSpeed = 6
Cfg.MaxMoveTick = 8
Cfg.RetreatHP = 0.30
Cfg.CriticalHP = 0.12
Cfg.RetreatDelay = 2.0
Cfg.RetreatClearHP = 0.55
Cfg.RetreatCooldown = 8.0
Cfg.ScanTTL = 1.2
Cfg.CrowCheckT = 2.5
Cfg.QuestCycleT = 6.0

Cfg.SkillKeys = { "F","Z","X","C","V","B" }
Cfg.SkillCooldowns = { 0.5, 1.2, 2.0, 2.8, 3.6, 6.0 }
Cfg.SkillUnlocked = { true,true,true,true,true,true }
Cfg.RotationOrder = { 2,3,4,5,6 }
Cfg.GCDWindow = 1.10
Cfg.ComboOrderCount = 4
Cfg.ComboReshuffleN = 3
Cfg.DetectHoldSkills = true
Cfg.HoldProbeDuration = 1.30
Cfg.HoldCastDuration = 1.20
Cfg.HoldOverride = {}
Cfg.AutoBlockOnDamage = true
Cfg.BlockReactionWindow = 1.50
Cfg.BlockGraceRelease = 0.35
Cfg.EmergencyHP = 0.30
Cfg.EmergencyInterval = 0.15

Cfg.ChestEnabled = true
Cfg.ChestLearnMode = true
Cfg.ChestOnKill = true
Cfg.ChestPassive = true
Cfg.ChestPassiveInterval = 30
Cfg.ChestRadius = 10
Cfg.ChestBossLootRadius = 15
Cfg.ChestBossLootDelayMin = 3.0
Cfg.ChestBossLootDelayMax = 9.0
Cfg.ChestBossInterItemMin = 1.5
Cfg.ChestBossInterItemMax = 3.0
Cfg.ChestReachDist = 4
Cfg.ChestMinInteractGap = 3.0
Cfg.ChestMaxInteractionsPerMin = 10
Cfg.ChestSessionInteractionCap = 40
Cfg.ChestMaxPasses = 2
Cfg.ChestPassDeadline = 5
Cfg.ChestPerTargetCooldown = 90
Cfg.ChestHoneypotThreshold = 3
Cfg.ChestVerbose = true
Cfg.ChestWhitelist = {}
Cfg.ChestRejectSignatures = { "grimore","grimoire","book","/","\\" }

Cfg.FKeyMode = "auto"
Cfg.AutoBlock = true
Cfg.BlockHoldTTL = 0.4
Cfg.BlockProbeWait = 0.15
Cfg.TeleportCd = 0.22
Cfg.TeleportStrike = 4.5
Cfg.TeleportHeight = 3
Cfg.TeleportJitter = 2
Cfg.TeleportWalkBlend = 0.6
Cfg.ComboBurst = 4
Cfg.ComboGap = 0.11
Cfg.DodgeCooldown = 0.65
Cfg.InRangeChaseT = 0.22
Cfg.TelegraphWindow = 0.45
Cfg.M1MaxHz = 10

-- Spoofers
Cfg.SpoofWriteHz = 10
Cfg.SpoofVerbose = false
Cfg.SpoofSpeedMult = 1.25
Cfg.SpoofJumpMult = 1.15
Cfg.SpoofAntiKnock = false
Cfg.SpoofKnockThreshold = 150
Cfg.SpoofFlingThreshold = 400
Cfg.SpoofVoidYThreshold = -300
Cfg.SpoofAFKInterval = 25
Cfg.SpoofMethods = {
    antiSlow=true, antiFreeze=true, antiFall=true,
    spoofWalkSpeed=true, spoofJumpPower=true,
    spoofBlock=true, antiStun=true, antiBlind=true,
    antiFog=true, antiDark=true, antiShake=true, antiColor=true,
    antiSit=true, antiVoid=true, antiState=true, antiAFK=true,
    antiSpectate=true, antiZoom=true, antiCinematic=true,
    antiWarp=true, antiDisarm=true, antiInvisible=true,
    antiForceField=true, antiSeatLock=true, antiShakeLock=true,
}

Cfg.CrowMenuCooldown = 30
Cfg.CrowScanMinGap = 0.3
Cfg.CrowModelTTL = 2.0
Cfg.CrowCancelLabels = { "cancel","close","back","exit","dismiss" }

Cfg.QuestCrowHotbar = "5"
Cfg.QuestMenuWait = 2.5
Cfg.QuestPriorityStale = 90
Cfg.QuestPanelCacheT = 1.0
Cfg.QuestCrowCacheT = 2.0

Cfg.GuiPanicKey1 = "RightControl"
Cfg.GuiPanicKey2 = "Backspace"
Cfg.GuiConcealed = true
Cfg.GuiPanicHide = true

Cfg.DefaultToggles = {
    combat = false, skl = true, eqp = true, rtr = true,
    gsp = false, crw = true, stunPun = true, hover = true,
}

Cfg.ConfigFile = "dingus_config.json"
Cfg.AutoSaveT = 30
Cfg.AutoSaveOnEdit = true
Cfg.AutoSaveDebounce = 0.25

local PERSIST = {
    "AtkRange","AtkInterval","AtkIntMin","AtkIntMax",
    "StunAtkInt","HitWindow","RunSpeed","CloseInSpeed","MaxMoveTick",
    "RetreatHP","CriticalHP","RetreatDelay","RetreatClearHP","RetreatCooldown",
    "ScanTTL","CrowCheckT","QuestCycleT",
    "SkillUnlocked","RotationOrder","GCDWindow","ComboOrderCount","ComboReshuffleN",
    "DetectHoldSkills","HoldProbeDuration","HoldCastDuration","HoldOverride",
    "AutoBlockOnDamage","BlockReactionWindow","BlockGraceRelease","AutoBlock",
    "BlockHoldTTL","BlockProbeWait","EmergencyHP","EmergencyInterval",
    "ChestEnabled","ChestLearnMode","ChestOnKill","ChestPassive",
    "ChestPassiveInterval","ChestRadius","ChestBossLootRadius",
    "ChestBossLootDelayMin","ChestBossLootDelayMax",
    "ChestBossInterItemMin","ChestBossInterItemMax","ChestReachDist",
    "ChestMinInteractGap","ChestMaxInteractionsPerMin",
    "ChestSessionInteractionCap","ChestMaxPasses","ChestPassDeadline",
    "ChestPerTargetCooldown","ChestHoneypotThreshold","ChestVerbose",
    "ChestWhitelist","ChestRejectSignatures",
    "FKeyMode","TeleportCd","TeleportStrike","TeleportHeight",
    "TeleportJitter","TeleportWalkBlend","ComboBurst","ComboGap",
    "DodgeCooldown","InRangeChaseT","TelegraphWindow","M1MaxHz",
    "SpoofWriteHz","SpoofVerbose","SpoofSpeedMult","SpoofJumpMult",
    "SpoofAntiKnock","SpoofKnockThreshold","SpoofFlingThreshold",
    "SpoofVoidYThreshold","SpoofAFKInterval","SpoofMethods",
    "CrowMenuCooldown","CrowScanMinGap","CrowModelTTL","CrowCancelLabels",
    "QuestCrowHotbar","QuestMenuWait","QuestPriorityStale",
    "QuestPanelCacheT","QuestCrowCacheT",
    "GuiPanicKey1","GuiPanicKey2","GuiConcealed","GuiPanicHide",
    "AutoSaveT","AutoSaveOnEdit","AutoSaveDebounce",
}

local DEFAULTS = {}
for _, k in ipairs(PERSIST) do
    local v = Cfg[k]
    if type(v) == "table" then
        local copy = {}
        for kk, vv in pairs(v) do copy[kk] = vv end
        DEFAULTS[k] = copy
    else DEFAULTS[k] = v end
end

local U
local dirty = false
local lastSaveAttempt = 0
local saveInFlight = false
local observers = {}

local function fire(key, value)
    local list = observers[key]
    if not list then return end
    for i = 1, #list do pcall(list[i], value) end
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
        else t[k] = v end
    end
    return t
end

function Cfg.save(slot)
    if saveInFlight then return false, "save in flight" end
    if not U or not U.File then return false, "no file api" end
    saveInFlight = true
    local s = U.HS
    if not s then saveInFlight = false; return false, "no HttpService" end
    local okE, encoded = pcall(function() return s:JSONEncode(snapshot()) end)
    if not okE or not encoded then saveInFlight = false; return false, "encode" end
    U.File.mkdir("Dingus")
    local ok = U.File.write(Cfg.slotFile(slot), encoded)
    saveInFlight = false
    if not ok then return false, "write" end
    dirty = false
    lastSaveAttempt = os.clock()
    return true, #encoded
end

function Cfg.load(slot)
    if not U or not U.File then return false, "no file api" end
    local raw = U.File.read(Cfg.slotFile(slot))
    if not raw or #raw < 5 then return false, "empty" end
    local s = U.HS
    if not s then return false, "no HttpService" end
    local ok, data = pcall(function() return s:JSONDecode(raw) end)
    if not ok or type(data) ~= "table" then return false, "decode" end
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

function Cfg.reset()
    for _, k in ipairs(PERSIST) do
        local v = DEFAULTS[k]
        if type(v) == "table" then
            local copy = {}
            for kk, vv in pairs(v) do copy[kk] = vv end
            Cfg[k] = copy
        else Cfg[k] = v end
        fire(k, Cfg[k])
    end
    dirty = true
    return true
end

function Cfg.exists(slot)
    if not U or not U.File then return false end
    return U.File.exists(Cfg.slotFile(slot))
end

function Cfg.set(key, value)
    if Cfg[key] == nil and DEFAULTS[key] == nil then return false, "unknown "..tostring(key) end
    Cfg[key] = value
    dirty = true
    fire(key, value)
    return true
end

function Cfg.touch(key) dirty = true; fire(key, Cfg[key]) end

function Cfg.observe(key, fn)
    if type(fn) ~= "function" then return false end
    observers[key] = observers[key] or {}
    table.insert(observers[key], fn)
    return true
end

function Cfg.tickAutoSave()
    if not dirty or not Cfg.AutoSaveOnEdit then return end
    local now = os.clock()
    if now - lastSaveAttempt < (Cfg.AutoSaveDebounce or 0.25) then return end
    Cfg.save("default")
end

function Cfg.pretty()
    local out = { "=== Current Config ===" }
    for _, k in ipairs(PERSIST) do
        local v = Cfg[k]
        out[#out+1] = string.format("  %-24s = %s", k, type(v) == "table" and "table" or tostring(v))
    end
    return table.concat(out, "\n")
end

return Cfg
