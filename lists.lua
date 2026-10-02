--[[
    Dingus-Slayer · lists.lua v7
    Corrected endgame boss roster using in-game display names.
    Two Reapers. Sumari/Yahari/Datai/Akazo/Domae/Enru are the
    display names, not the wiki canonical names.
]]--

local L = {}

L.bossRegions = {
    {
        name = "Bamboo Grove",
        bosses = { "sumari", "yahari" },
    },
    {
        name = "Hidden Mist",
        bosses = { "reaper", "gyutai", "domae" },
    },
    {
        name = "Nightfall",
        bosses = { "datai", "akazo" },
    },
    {
        name = "Deep Caves",
        bosses = { "nezura", "enru" },
    },
}

L.bosses = {}
for _, region in ipairs(L.bossRegions) do
    for _, b in ipairs(region.bosses) do
        table.insert(L.bosses, b)
    end
end

-- "Reaper" appears twice in-world (Bamboo Grove + Hidden Mist).
-- Same name string, no disambiguation — isBoss returns true for both.
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

L.weapons = {
    "katana", "sword", "blade", "saber", "sabre",
    "cutlass", "rapier", "nodachi", "wakizashi", "tachi",
    "scythe", "sickles", "sickle", "spear", "tanto",
    "gauntlet", "gauntlets", "claws", "claw",
    "wagasa", "cleaver", "cleavers", "axe", "mace",
    "war fans", "shotgun", "gun",
    "nightfall", "firstlight", "damascus",
    "enryu", "shinkage", "tengoku",
    "volcanic", "tornadic", "metal", "skull", "polar", "devourer",
    "bone", "champion", "green", "butterfly",
    "insect", "flame", "serpent", "thunder", "water", "wind", "sound",
    "beast", "regular", "fancy", "ocean wave", "reverb",
    "blood", "seismic", "bladed",
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
