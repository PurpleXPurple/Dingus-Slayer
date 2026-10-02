-- Dingus-Slayer · config.lua v8
-- Added: full Synerox farm + quest keys to PERSIST.

local Cfg = {}
Cfg.VERSION = 8

--=== Combat
Cfg.AtkRange = 8
Cfg.AtkInterval = 0.38
Cfg.AtkIntMin = 0.22
Cfg.AtkIntMax = 0.65
Cfg.StunAtkInt = 0.20
Cfg.HitWindow = 15
Cfg.RunSpeed = 16
Cfg.RetreatHP = 0.30
Cfg.CriticalHP = 0.12
Cfg.RetreatDelay = 2.0
Cfg.RetreatClearHP = 0.55
Cfg.RetreatCooldown = 8.0
Cfg.ScanTTL = 1.2
Cfg.QuestCycleT = 6.0
Cfg.SkillKeys = { "F","Z","X","C","V","B" }
Cfg.SkillUnlocked = { true,true,true,true,true,true }
Cfg.GCDWindow = 1.10
Cfg.ComboBurst = 4
Cfg.ComboGap = 0.11
Cfg.M1MaxHz = 10

--=== Synerox farm (NEW to config — were implicit state in v23)
Cfg.SynSafeMode         = "Overhead"   -- Overhead | Underground | In Front | Ground
Cfg.SynHeightOffset     = 3.8
Cfg.SynDistance         = 2
Cfg.SynMultiHit         = true
Cfg.SynMultiHitCount    = 3
Cfg.SynM1Interval       = 0.28
Cfg.SynAutoSkills       = true
Cfg.SynSkillInterval    = 1
Cfg.SynTrackGuard       = true
Cfg.SynBossLootWait     = 4
Cfg.SynMobLootWait      = 1.8
Cfg.SynAutoTravel       = true
Cfg.SynTargetLock       = true
Cfg.SynBossRotationT    = 15

--=== Synerox farm — category/mob/region selection
Cfg.SynMobCategory      = "All"        -- Normal | Boss | All
Cfg.SynTargetMob        = "All"        -- "All" | name | table (multi-boss)
Cfg.SynRegionFilter     = "All"        -- "All" | region name
Cfg.SynSelectedBosses   = {}

--=== Chest
Cfg.ChestEnabled = true
Cfg.ChestLearnMode = true
Cfg.ChestOnKill = true
Cfg.ChestPassive = true
Cfg.ChestPassiveInterval = 1.5
Cfg.ChestRadius = 350
Cfg.ChestReachDist = 350
Cfg.ChestLootRadius = 350
Cfg.ChestLootOn = true
Cfg.ChestSoulsOn = true
Cfg.ChestChestsOn = true
Cfg.ChestBossLootDelayMin = 3.0
Cfg.ChestBossLootDelayMax = 9.0
Cfg.ChestMaxPerSweep = 20

--=== Quests
Cfg.QuestCrowHotbar = "5"
Cfg.QuestMenuWait = 2.5
Cfg.QuestPriorityStale = 90
Cfg.QuestPanelCacheT = 1.0
Cfg.QuestCrowCacheT = 2.0
Cfg.QuestAutoInterval = 2.0
Cfg.QuestAutoEnabled = false
Cfg.QuestMode = "Auto Best Quest (By Level)"
Cfg.QuestSelectedName = ""

--=== Spoofers
Cfg.SpoofWriteHz = 10
Cfg.SpoofVerbose = false
Cfg.SpoofSpeedMult = 1.25
Cfg.SpoofJumpMult = 1.15
Cfg.SpoofAFKInterval = 25
Cfg.SpoofVoidYThreshold = -300
Cfg.SpoofMethods = {
    antiSlow=true, antiFreeze=true, antiFall=true,
    spoofWalkSpeed=true, spoofJumpPower=true, spoofBlock=true,
    antiStun=true, antiBlind=true, antiFog=true, antiDark=true,
    antiShake=true, antiColor=true, antiSit=true, antiVoid=true,
    antiState=true, antiAFK=true, antiSpectate=true, antiZoom=true,
    antiCinematic=true, antiWarp=true, antiDisarm=true,
    antiInvisible=true, antiForceField=true, antiSeatLock=true,
    antiShakeLock=true,
}

--=== Scanner
Cfg.CrowMenuCooldown = 30
Cfg.CrowScanMinGap = 0.3
Cfg.CrowModelTTL = 2.0
Cfg.CrowCancelLabels = { "cancel","close","back","exit","dismiss" }

--=== GUI
Cfg.GuiPanicKey1 = "RightControl"
Cfg.GuiPanicKey2 = "Backspace"
Cfg.GuiConcealed = true
Cfg.GuiPanicHide = true

Cfg.DefaultToggles = {
    combat=false, skl=true, eqp=true, rtr=true,
    gsp=false, crw=true, stunPun=true,
}

Cfg.ConfigFile = "dingus_config.json"
Cfg.AutoSaveT = 30
Cfg.AutoSaveOnEdit = true
Cfg.AutoSaveDebounce = 0.25

local PERSIST = {
    -- Combat core
    "AtkRange","AtkInterval","AtkIntMin","AtkIntMax","StunAtkInt","HitWindow",
    "RunSpeed","RetreatHP","CriticalHP","RetreatDelay","RetreatClearHP",
    "RetreatCooldown","ScanTTL","QuestCycleT","GCDWindow","ComboBurst","ComboGap",
    "M1MaxHz","SkillUnlocked",
    -- Synerox farm
    "SynSafeMode","SynHeightOffset","SynDistance","SynMultiHit","SynMultiHitCount",
    "SynM1Interval","SynAutoSkills","SynSkillInterval","SynTrackGuard",
    "SynBossLootWait","SynMobLootWait","SynAutoTravel","SynTargetLock",
    "SynBossRotationT","SynMobCategory","SynTargetMob","SynRegionFilter",
    "SynSelectedBosses",
    -- Chest
    "ChestEnabled","ChestLearnMode","ChestOnKill","ChestPassive",
    "ChestPassiveInterval","ChestRadius","ChestReachDist","ChestLootRadius",
    "ChestLootOn","ChestSoulsOn","ChestChestsOn",
    "ChestBossLootDelayMin","ChestBossLootDelayMax","ChestMaxPerSweep",
    -- Quests
    "QuestCrowHotbar","QuestMenuWait","QuestPriorityStale",
    "QuestPanelCacheT","QuestCrowCacheT","QuestAutoInterval",
    "QuestAutoEnabled","QuestMode","QuestSelectedName",
    -- Spoofers
    "SpoofWriteHz","SpoofVerbose","SpoofSpeedMult","SpoofJumpMult",
    "SpoofAFKInterval","SpoofVoidYThreshold","SpoofMethods",
    -- Scanner
    "CrowMenuCooldown","CrowScanMinGap","CrowModelTTL","CrowCancelLabels",
    -- GUI
    "GuiPanicKey1","GuiPanicKey2","GuiConcealed","GuiPanicHide",
    -- Save
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
    if saveInFlight then return false, "busy" end
    if not U or not U.File then return false, "no-file" end
    saveInFlight = true
    local s = U.HS
    if not s then saveInFlight = false; return false, "no-hs" end
    local ok, enc = pcall(function() return s:JSONEncode(snapshot()) end)
    if not ok or not enc then saveInFlight = false; return false, "enc" end
    U.File.mkdir("Dingus")
    U.File.write(Cfg.slotFile(slot), enc)
    saveInFlight = false
    dirty = false
    lastSaveAttempt = os.clock()
    return true, #enc
end

function Cfg.load(slot)
    if not U or not U.File then return false, "no-file" end
    local raw = U.File.read(Cfg.slotFile(slot))
    if not raw or #raw < 5 then return false, "empty" end
    local s = U.HS
    if not s then return false, "no-hs" end
    local ok, data = pcall(function() return s:JSONDecode(raw) end)
    if not ok or type(data) ~= "table" then return false, "dec" end
    local applied = 0
    for _, k in ipairs(PERSIST) do
        local v = data[k]
        if v ~= nil and (Cfg[k] == nil or type(v) == type(Cfg[k])) then
            Cfg[k] = v
            applied = applied + 1
        end
    end
    if applied == 0 then return false, "nothing" end
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
    if Cfg[key] == nil and DEFAULTS[key] == nil then
        return false, "unknown "..tostring(key)
    end
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
    if os.clock() - lastSaveAttempt < (Cfg.AutoSaveDebounce or 0.25) then return end
    Cfg.save("default")
end

function Cfg.pretty()
    local out = { "=== Config ===" }
    for _, k in ipairs(PERSIST) do
        local v = Cfg[k]
        out[#out+1] = string.format("  %-24s = %s", k,
            type(v) == "table" and "table" or tostring(v))
    end
    return table.concat(out, "\n")
end

return Cfg
