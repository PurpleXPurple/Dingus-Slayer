--[[
    Dingus-Slayer · lists.lua v6
    Endgame bosses only. Region-grouped. Per-boss selection state.

    Removed: mother bear, nomay bandit, muichiro, inosuke, rengoku,
             renpeke, akeza, swampy, zoku, zuko, zanegutsu, kuuchie,
             kaden, sabito, sanemi, yahaba, susamaru, shiron, giyu,
             slasher, nezuko, trainee, subordinate, white terror,
             high demon, profound demon.
]]--

local L = {}

--============================================================
-- BOSS REGIONS
-- Grouped for the GUI selector. Flat list is derived below.
--============================================================
L.bossRegions = {
    {
        name = "Hidden Mist",
        bosses = { "obanai", "obari", "gyomei", "shinobu", "tengen", "fujiko" },
    },
    {
        name = "Bamboo Grove",
        bosses = { "sumari", "yahari", "hoyuzo", "nezura" },
    },
    {
        name = "Demon Domain",
        bosses = { "daki", "gyutaro", "doma", "akaza" },
    },
    {
        name = "Nightfall",
        bosses = { "zentaro", "tengai", "reaper", "enmu" },
    },
    {
        name = "Frozen Wilds",
        bosses = { "yeti", "kaiden" },
    },
    {
        name = "Renamed",
        bosses = { "enru", "datai", "akazo" },
    },
}

-- Flat list derived from regions
L.bosses = {}
for _, region in ipairs(L.bossRegions) do
    for _, b in ipairs(region.bosses) do
        table.insert(L.bosses, b)
    end
end

--============================================================
-- SELECTION STATE
--============================================================
L.selectedBosses = {}
for _, b in ipairs(L.bosses) do
    L.selectedBosses[b] = true
end

function L.setBossEnabled(name, enabled)
    if L.selectedBosses[name] == nil then return end
    L.selectedBosses[name] = not not enabled
end

function L.isBossEnabled(name)
    return L.selectedBosses[name] ~= false
end

function L.setAllBosses(enabled)
    for _, b in ipairs(L.bosses) do
        L.selectedBosses[b] = not not enabled
    end
end

function L.enabledCount()
    local n = 0
    for _, b in ipairs(L.bosses) do
        if L.selectedBosses[b] ~= false then n = n + 1 end
    end
    return n, #L.bosses
end

--============================================================
-- WEAPONS
--============================================================
L.weapons = {
    "katana", "sword", "blade", "saber", "sabre",
    "cutlass", "rapier", "nodachi", "wakizashi", "tachi",
    "scythe", "sickles", "sickle", "spear", "tanto",
    "gauntlet", "gauntlets", "claws", "claw",
    "wagasa", "cleaver", "cleavers", "axe", "mace",
    "war fans",
    "shotgun", "gun",
    "nightfall", "firstlight", "damascus",
    "enryu", "shinkage", "tengoku",
    "volcanic", "tornadic",
    "metal", "skull", "polar", "devourer",
    "bone",
    "champion",
    "green",
    "butterfly",
    "insect", "flame", "serpent", "thunder", "water", "wind", "sound",
    "beast",
    "regular", "fancy",
    "ocean wave", "reverb",
    "blood",
    "seismic",
    "bladed",
}

L.nonWeapons = {
    "rod", "fishing", "horse", "gourd",
    "orb", "potion", "elixir", "meat", "bandage",
    "bell", "scroll", "pouch", "map", "ore", "horn",
    "silk", "scrap", "ingot", "cloth", "plating",
    "tentacle", "worm", "coral", "shovel", "permit",
    "letter", "package", "gemstone", "note",
    "schematic", "lantern", "chest", "coin", "lure",
    "fish", "wen", "voucher", "crate", "emote",
    "mask", "haori", "necklace", "earring",
    "kasugai", "ring", "sheath", "sheathe",
    "uniform", "crow",
}

L.mobKeywords = {}
L.questKeywords = {}
L.crowKeywords = { "crow", "kasugai" }

--============================================================
-- MATCHING
--============================================================
local function matchWord(haystack, needle)
    local s, e = string.find(haystack, needle, 1, true)
    if not s then return false end
    if #needle <= 3 then
        local before = s == 1 or not string.match(haystack:sub(s-1, s-1), "%w")
        local after  = e == #haystack or not string.match(haystack:sub(e+1, e+1), "%w")
        return before and after
    end
    return true
end

local function matchAny(haystack, list)
    for i = 1, #list do
        if matchWord(haystack, list[i]) then return true end
    end
    return false
end

function L.isBoss(nm)
    if not nm then return false end
    local l = string.lower(nm)
    for i = 1, #L.bosses do
        local b = L.bosses[i]
        if matchWord(l, b) then
            return L.selectedBosses[b] ~= false
        end
    end
    return false
end

function L.isWeapon(nm)
    if not nm then return false end
    local l = string.lower(nm)
    if matchAny(l, L.nonWeapons) then return false end
    return matchAny(l, L.weapons)
end

function L.isCrow(nm)
    if not nm then return false end
    return matchAny(string.lower(nm), L.crowKeywords)
end

function L.isQuest(nm)
    return false
end

return L
