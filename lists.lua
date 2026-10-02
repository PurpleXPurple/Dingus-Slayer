--[[
    Dingus-Slayer · lists.lua v5
    Endgame bosses only. Map 1 and Map 2 removed per request.
    Kept: Hidden Mist corridor + endgame regions + generic tiers +
    in-game renamed aliases.
]]--

local L = {}

L.bosses = {
    -- Endgame / Hidden Mist corridor
    "obanai",
    "obari",
    "zentaro",
    "tengai",
    "sumari",
    "yahari",
    "reaper",
    "daki",
    "gyutaro",
    "shinobu",
    "nezura",
    "gyomei",
    "fujiko",
    "yeti",
    "tengen",
    "doma",
    "akaza",
    "enmu",
    "hoyuzo",
    "kaiden",

    -- Generic / tiered
    "white terror",
    "high demon",
    "profound demon",
    "trainee",

    -- In-game renamed aliases (screenshot-verified)
    "enru",
    "datai",
    "akazo",

    -- Non-boss NPC names that still trigger hostile responses
    "subordinate",
}

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

-- Emptied: mob scanning returns nothing, pickTarget only returns bosses.
L.mobKeywords = {}

-- Emptied: unused by remaining scanners.
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
    return matchAny(string.lower(nm), L.bosses)
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
