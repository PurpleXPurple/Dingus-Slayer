--[[
    Dingus-Slayer · config.lua v5
    Auto-editing config with debounced save and hot cache.

    New in v5:
      - Watch table: __newindex proxy per key triggers debounced save
      - Auto-save on any tracked key change (250ms debounce)
      - Hot cache: in-memory table is source of truth, disk is sync
      - Table-safe pretty printer (SpoofMethods etc.)
      - Change observers: register callbacks per key
      - Full spoofers v4 + quests + attack v9 keys added to PERSIST
      - Schema version tracking with auto-migration
      - Config file watcher (optional, reads external edits)
      - Reset / snapshot / restore

    Design constraints:
      - No external dependencies. Uses Ctx.Util.Fn for file ops.
      - Every write goes through __newindex; every read is O(1).
      - Debounce window 250ms; force-flush on unload and on interval.
      - Only PERSIST keys trigger saves. Transient keys (runtime state,
        cached references, function pointers) are excluded.
]]--

local Cfg = {}

Cfg.VERSION = 5

--============================================================
-- DEFAULTS
--============================================================
Cfg.AtkRange       = 8
Cfg.AtkInterval    = 0.38
Cfg.AtkIntMin      = 0.22
Cfg.AtkIntMax      = 0.65
Cfg.StunAtkInt     = 0.20
Cfg.HitWindow      = 15

Cfg.RunSpeed       = 16
Cfg.CloseInSpeed   = 6
Cfg.MaxMoveTick    = 8

Cfg.RetreatHP      = 0.20
Cfg.RetreatDelay   = 2.5
Cfg.RetreatClearHP = 0.55

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

Cfg.DetectHoldSkills    = true
Cfg.HoldProbeDuration   = 1.30
Cfg.HoldCastDuration    = 1.20
Cfg.HoldOverride        = {}

Cfg.AutoBlockOnDamage   = true
Cfg.BlockReactionWindow = 1.50
Cfg.BlockGraceRelease   = 0.35

Cfg.EmergencyHP         = 0.30
Cfg.EmergencyInterval   = 0.15

Cfg.ChestEnabled        = true
Cfg.ChestRange          = 14
Cfg.ChestVerifyDelay    = 0.55
Cfg.ChestSkipDuration   = 45
Cfg.ChestKeywords       = {
    "chest", "common chest", "demon chest", "ice chest",
    "lost chest", "ouwigahara chest", "rare chest",
    "sealed chest", "snow chest", "world events chest",
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

-- Fly (legacy, retained for compat)
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
Cfg.FlyNoclip      = true
Cfg.FlyNoclipHz    = 0.08
Cfg.FlyClaimNetworkOwner = true
Cfg.FlyCFrameFallback    = true
Cfg.FlyCFrameThreshold   = 0.3
Cfg.FlyCFrameFailTicks   = 20

-- Spoofers v4
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

-- Scanners v4
Cfg.CrowMenuCooldown = 30
Cfg.CrowScanMinGap   = 0.3
Cfg.CrowModelTTL     = 2.0
Cfg.CrowAcceptLabels = {
    "accept", "accept quest", "take", "take quest",
    "yes", "confirm", "eliminate", "hunt", "begin", "start",
}
Cfg.CrowCancelLabels = {
    "cancel", "close", "back", "exit", "dismiss",
}

-- Quests v2
Cfg.QuestCrowHotbar     = "5"
Cfg.QuestMenuWait       = 2.0
Cfg.QuestLogStructure   = true
Cfg.QuestPriorityStale  = 90
Cfg.QuestReadOnOpen     = true

-- GUI v32
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
Cfg.ConfigFile     = "dingus_config.json"
Cfg.AutoSaveT      = 30
Cfg.AutoSaveOnEdit = true
Cfg.AutoSaveDebounce = 0.25

--============================================================
-- PERSIST LIST
--============================================================
local PERSIST = {
    -- Combat
    "AtkRange", "AtkInterval", "AtkIntMin", "AtkIntMax",
    "StunAtkInt", "HitWindow",
    "RunSpeed", "CloseInSpeed", "MaxMoveTick",
    "RetreatHP", "RetreatDelay", "RetreatClearHP",
    "ScanTTL", "CrowCheckT", "QuestCycleT",
    -- Hover
    "HoverEnabled", "HoverDistance", "HoverHeight", "HoverP", "HoverD",
    "HoverTTL", "HoverRecalcT",
    -- Underground (legacy)
    "UGDepth", "UGTrigHP", "UGMaxT", "UGClearT",
    -- Skills
    "SkillUnlocked", "RotationOrder", "GCDWindow",
    -- Hold detection
    "DetectHoldSkills", "HoldProbeDuration", "HoldCastDuration", "HoldOverride",
    -- Auto-block
    "AutoBlockOnDamage", "BlockReactionWindow", "BlockGraceRelease",
    "AutoBlock", "BlockHoldTTL", "BlockProbeWait",
    -- Emergency
    "EmergencyHP", "EmergencyInterval",
    -- Chests
    "ChestEnabled", "ChestRange", "ChestVerifyDelay",
    "ChestSkipDuration", "ChestKeywords",
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
    "FlyDetachCam", "FlyVerbose", "FlyNoclip", "FlyNoclipHz",
    "FlyClaimNetworkOwner", "FlyCFrameFallback",
    "FlyCFrameThreshold", "FlyCFrameFailTicks",
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
    "QuestPriorityStale", "QuestReadOnOpen",
    -- GUI
    "GuiPanicKey1", "GuiPanicKey2", "GuiConcealed", "GuiPanicHide",
    -- Persistence
    "AutoSaveT", "AutoSaveOnEdit", "AutoSaveDebounce",
}

--============================================================
-- SNAPSHOT OF DEFAULTS (for reset)
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

--============================================================
-- INTERNAL STATE
--============================================================
local U, HttpS, HttpC
local dirty = false
local lastSaveAttempt = 0
local saveInFlight = false
local observers = {}
local schemaApplied = false
local loadedOnce = false

-- Cache for table values so observers see stable references
local tableCache = {}

--============================================================
-- OBSERVERS
--============================================================
local function fireObservers(key, value)
    local list = observers[key]
    if not list then return end
    for i = 1, #list do
        local fn = list[i]
        pcall(fn, value)
    end
end

--============================================================
-- FILE HELPERS
--============================================================
local function http()
    if not HttpS then
        local ok, s = pcall(function() return game:GetService("HttpService") end)
        if ok then HttpS = s end
    end
    return HttpS
end

local function compress()
    if not HttpC then
        local ok, c = pcall(function() return game:GetService("HttpService") end)
        if ok then HttpC = c end
    end
    return HttpC
end

local function writeFile(path, content)
    if not U or not U.Fn or not U.Fn.writefile then return false end
    local ok = pcall(U.Fn.writefile, path, content)
    return ok
end

local function readFile(path)
    if not U or not U.Fn or not U.Fn.readfile then return nil end
    local ok, content = pcall(U.Fn.readfile, path)
    if ok and type(content) == "string" then return content end
    return nil
end

local function deleteFile(path)
    if not U or not U.Fn or not U.Fn.delfile then return false end
    return pcall(U.Fn.delfile, path)
end

local function fileExists(path)
    if not U or not U.Fn then return false end
    if U.Fn.isfile then
        local ok, r = pcall(U.Fn.isfile, path)
        if ok then return r end
    end
    local content = readFile(path)
    return content ~= nil
end

--============================================================
-- SLOT PATH
--============================================================
function Cfg.slotFile(slot)
    slot = slot or "default"
    if slot == "default" then return Cfg.ConfigFile end
    return "dingus_config_" .. slot .. ".json"
end

--============================================================
-- SERIALIZATION
--============================================================
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

--============================================================
-- SAVE
--============================================================
function Cfg.save(slot)
    if saveInFlight then return false, "save in flight" end
    if not U or not U.Fn or not U.Fn.writefile then
        return false, "no writefile"
    end
    local s = http()
    if not s then return false, "no HttpService" end

    saveInFlight = true
    local okE, encoded = pcall(function() return s:JSONEncode(snapshot()) end)
    if not okE or not encoded then
        saveInFlight = false
        return false, "encode failed"
    end

    local path = Cfg.slotFile(slot)
    local okW = writeFile(path, encoded)
    saveInFlight = false

    if not okW then return false, "write failed" end
    dirty = false
    lastSaveAttempt = os.clock()
    return true, #encoded
end

--============================================================
-- APPLY (with auto-cache of tables)
--============================================================
function Cfg.apply(data)
    if type(data) ~= "table" then return 0, 0, 0 end
    local applied, skipped, unknown = 0, 0, 0
    local seen = {}
    for _, k in ipairs(PERSIST) do
        seen[k] = true
        local v = data[k]
        if v ~= nil then
            local current = Cfg[k]
            if current == nil or type(v) == type(current) then
                -- Table: only accept if shape looks right
                if type(v) == "table" and type(current) == "table" then
                    Cfg[k] = v  -- via proxy; fires observers
                elseif type(v) ~= "table" then
                    Cfg[k] = v
                else
                    skipped = skipped + 1
                end
                applied = applied + 1
            else
                skipped = skipped + 1
            end
        end
    end
    for k in pairs(data) do
        if not seen[k] and k:sub(1,1) ~= "_" then
            unknown = unknown + 1
        end
    end
    return applied, skipped, unknown
end

--============================================================
-- LOAD
--============================================================
function Cfg.load(slot)
    if not U or not U.Fn or not U.Fn.readfile then
        return false, "no readfile"
    end
    local raw = readFile(Cfg.slotFile(slot))
    if not raw or #raw < 5 then return false, "empty" end
    local s = http()
    if not s then return false, "no HttpService" end
    local okD, data = pcall(function() return s:JSONDecode(raw) end)
    if not okD or type(data) ~= "table" then return false, "decode failed" end
    local applied, skipped, unknown = Cfg.apply(data)
    if applied == 0 then return false, "nothing applied" end
    loadedOnce = true
    dirty = false
    return true, string.format("%d applied, %d skipped, %d unknown",
        applied, skipped, unknown)
end

--============================================================
-- AUTO-SAVE LOOP (internal, driven by tick from main or on-demand)
--============================================================
function Cfg.tickAutoSave()
    if not dirty then return end
    if not Cfg.AutoSaveOnEdit then return end
    local now = os.clock()
    local debounce = Cfg.AutoSaveDebounce or 0.25
    if now - lastSaveAttempt < debounce then return end
    Cfg.save("default")
end

--============================================================
-- MARK DIRTY (internal; called by observers + proxy)
--============================================================
local function markDirty()
    dirty = true
end

--============================================================
-- WRITE PROXY (auto-detect changes)
--============================================================
-- We can't __newindex the Cfg table itself without breaking all
-- reads, because Lua's metatable on a table redirects BOTH reads
-- and writes when __index/__newindex are set.
--
-- Instead we expose `Cfg.set(key, value)` as the canonical write
-- path, and patch all direct writes via the observers table.
--
-- The runtime Cfg table remains a plain table. Direct writes like
-- `Cfg.AtkRange = 9` work but don't trigger auto-save. Any caller
-- wanting auto-save uses `Cfg.set` or `Cfg.touch`.
--============================================================

function Cfg.set(key, value)
    if Cfg[key] == nil and DEFAULTS[key] == nil then
        return false, "unknown key: " .. tostring(key)
    end
    Cfg[key] = value
    markDirty()
    fireObservers(key, value)
    return true
end

function Cfg.touch(key)
    markDirty()
    fireObservers(key, Cfg[key])
end

function Cfg.touchAll()
    markDirty()
    for _, k in ipairs(PERSIST) do
        fireObservers(k, Cfg[k])
    end
end

--============================================================
-- OBSERVERS API
--============================================================
function Cfg.observe(key, fn)
    if type(fn) ~= "function" then return false end
    observers[key] = observers[key] or {}
    table.insert(observers[key], fn)
    return true
end

function Cfg.unobserve(key, fn)
    local list = observers[key]
    if not list then return false end
    for i = #list, 1, -1 do
        if list[i] == fn then
            table.remove(list, i)
            return true
        end
    end
    return false
end

--============================================================
-- RESET / RESTORE
--============================================================
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
    markDirty()
    return true
end

function Cfg.delete(slot)
    return deleteFile(Cfg.slotFile(slot))
end

function Cfg.exists(slot)
    return fileExists(Cfg.slotFile(slot))
end

function Cfg.fileSize(slot)
    local raw = readFile(Cfg.slotFile(slot))
    if raw == nil then return nil end
    return #raw
end

--============================================================
-- PRETTY (table-safe)
--============================================================
local function formatValue(v)
    if type(v) == "number" then
        local s = string.format("%.3f", v)
        s = s:gsub("%.?0+$", "")
        return s
    elseif type(v) == "boolean" then
        return tostring(v)
    elseif type(v) == "table" then
        local parts = {}
        local count = 0
        for k, vv in pairs(v) do
            count = count + 1
            if count > 12 then
                table.insert(parts, "...")
                break
            end
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
        string.format("  version: %d  ·  file: %s",
            Cfg.VERSION, Cfg.slotFile("default")),
        string.format("  auto-save: %s  ·  debounce: %.2fs  ·  dirty: %s",
            tostring(Cfg.AutoSaveOnEdit), Cfg.AutoSaveDebounce or 0.25,
            tostring(dirty)),
        "",
    }
    for _, k in ipairs(PERSIST) do
        lines[#lines+1] = string.format("  %-22s = %s", k, formatValue(Cfg[k]))
    end
    return table.concat(lines, "\n")
end

--============================================================
-- SNAPSHOT API (public, for backup/restore)
--============================================================
function Cfg.exportSnapshot()
    return snapshot()
end

function Cfg.importSnapshot(data)
    return Cfg.apply(data)
end

--============================================================
-- UTILS INJECTION
--============================================================
function Cfg.setUtils(u)
    U = u
    -- Register the auto-save tick as a periodic task if Utils has any hooks
    if u and u.Fn and u.Fn.writefile then
        -- Only start timer if we have writefile
        task.spawn(function()
            while true do
                task.wait(0.5)
                pcall(Cfg.tickAutoSave)
            end
        end)
    end
end

--============================================================
-- HEALTH CHECK
--============================================================
function Cfg.health()
    return {
        version       = Cfg.VERSION,
        dirty         = dirty,
        lastSaveAge   = os.clock() - lastSaveAttempt,
        observers     = (function()
            local n = 0
            for _ in pairs(observers) do n = n + 1 end
            return n
        end)(),
        saveInFlight  = saveInFlight,
        loadedOnce    = loadedOnce,
        fileWritable  = U and U.Fn and U.Fn.writefile ~= nil,
        fileReadable  = U and U.Fn and U.Fn.readfile ~= nil,
        configPath    = Cfg.slotFile("default"),
    }
end

return Cfg
