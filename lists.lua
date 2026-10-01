local L = {}

L.bosses = {
    "zuko","mother bear","honyozu","hoyuzo","yahaba","susamaru","reaper","slasher",
    "daki","gyutaro","douma","akaza","nezuko","obanai","zentaro","sanemi","giyu",
    "shiron","sabito","muichiro","inosuke","rengoku","renpeke","swampy","yeti",
    "tengen","tengai","fujiko","enmu","shinobu","gyomei","kaiden","kaden",
    "zanegutsu","sumari","gyutai","gyorei","giyen","saneri","obari","nezura",
    "ren","rangu","trainee","white terror","high demon","profound demon",
}

L.weapons = {
    "sword","katana","cutlass","sickles","sickle","scythe","spear","tanto",
    "war fans","shotgun","gun","gauntlet","claw","claws","wagasa","axe","mace",
    "cleaver","saber","sabre","blade","rapier","nodachi","wakizashi","tachi",
    "nightfall","firstlight","damascus","enryu","shinkage","tengoku",
    "serpentine","tidal","tornadic","volcanic","butterfly","thundercloud",
    "regular katana","fancy katana","ocean wave","reverb","sound katanas",
    "firstlight katana","nightfall katana","insect katana","flame katana",
    "thunder katana","water katana","wind katana","stone katana","beast katanas",
    "nightfall sickles","damascus sickles","blood sickles","nightfall scythe",
    "damascus scythe","firstlight spear","damascus spear","firstlight tanto",
    "damascus tanto","firstlight war fans","damascus war fans","damascus shotgun",
    "lost shotgun","nightfall gauntlet","damascus gauntlet","nightfall claws",
    "damascus claws","firstlight bladed wagasa","damascus bladed wagasa",
    "nightfall axe and mace","seismic axe and mace","damascus axe and mace",
    "nightfall serpent katana","firstlight sound cleavers","firstlight insect katana",
}

L.nonWeapons = {
    "rod","fishing","horse","gourd","orb","potion","elixir","meat","bandage",
    "bell","scroll","pouch","map","ore","horn","silk","scrap","ingot","cloth",
    "plating","tentacle","worm","coral","shovel","permit","letter","package",
    "gemstone","note","schematic","lantern","chest","coin","lure","fish","wen",
    "voucher","crate","emote","mask","haori","necklace","earring","crow",
    "kasugai","ring","horns","sword sheath","sheathe",
}

L.questItems = {
    "serpent key","shovel","frozen heart","supply box","fishing permit",
    "permit stamp","beast core","jewelry box","biwa bell","bandage",
    "broken nichirin katana","wagwan's ring","suspicious note","package",
    "letter","gemstone","cooked bear meat","book of guidance","bear meat",
    "bear claws","ore","lucky penny",
}

L.materials = {
    "coin stack","coin pouch","coin pile","coin","demon horns","crude iron ingot",
    "firstlight star ore","nightfall reinforced plating","firstlight weaver's silk",
    "nightfall weaver's cloth","firstlight forged ingot","nightfall forged ingot",
    "refinement guard","mythic refinement ore","refinement ore","silk thread",
    "metal scraps",
}

L.consumables = {
    "underwater breathing potion","stamina regen elixir","health regen elixir",
    "health elixir","muzan's blood","stamina regen potion","health regen potion",
    "health potion","large gourd","medium gourd","small gourd",
}

L.clans = {
    "uzui","agatsuma","kamado","rengoku","shinazugawa","tomiyoka","kocho",
    "kanroji","iguro","himejima","tokito","uzui supreme","sun breathing",
    "yoriichi","kokushibo","muzan",
}

L.regions = {
    "windy peak","bamboo grove","mistfall harbor","butterfly estate",
    "iceveil valley","iceveil settlement","hidden mist village",
    "final selection plains","final selection","dreamfall hollow",
    "stone sanctuary","verdant cliffs","forgotten ruins","veilfall cavern",
    "the white terror lair","seasons crossing","frost veil shrine",
}

L.breathings = {
    "water","flame","thunder","wind","stone","mist","serpent","insect",
    "sound","beast","sun","moon",
}

L.demonArts = {
    "blood manipulation","pyrokinesis","shockwave","cryokinesis",
    "obi manipulation","reaper","tamari","dream","arrow",
}

L.fightingStyles = {
    "reaping blades","tai chi","soryu",
}

L.questKeywords = {
    "quest","mission","task","objective","bounty","contract","hunt",
    "eliminate","target","assassin","slay","kill","reward",
}

L.crowKeywords = { "crow","kasugai" }

L.mobKeywords = {
    "bear","cub","bandit","civilian","demon","wolf","boar","trapper",
    "oni","slasher","thug","brigand","trainee",
}

-- Word-boundary aware substring match.
-- Short needles (<=3 chars) require an actual boundary on both sides.
-- Longer needles match as plain substring.
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
    if not nm then return false end
    return matchAny(string.lower(nm), L.questKeywords)
end

return L--[[
    Dingus-Slayer · lists.lua
    Central data tables. Every classification in one place.
]]--

local L = {}

L.bosses = {
    "zuko","mother bear","honyozu","hoyuzo","yahaba","susamaru","reaper","slasher",
    "daki","gyutaro","douma","akaza","nezuko","obanai","zentaro","sanemi","giyu",
    "shiron","sabito","muichiro","inosuke","rengoku","renpeke","swampy","yeti",
    "tengen","tengai","fujiko","enmu","shinobu","gyomei","kaiden","kaden",
    "zanegutsu","sumari","gyutai","gyorei","giyen","saneri","obari","nezura",
    "ren","rangu","trainee","white terror","high demon","profound demon",
}

L.weapons = {
    "sword","katana","cutlass","sickles","sickle","scythe","spear","tanto",
    "war fans","shotgun","gun","gauntlet","claw","claws","wagasa","axe","mace",
    "cleaver","saber","sabre","blade","rapier","nodachi","wakizashi","tachi",
    "nightfall","firstlight","damascus","enryu","shinkage","tengoku",
    "serpentine","tidal","tornadic","volcanic","butterfly","thundercloud",
    "regular katana","fancy katana","ocean wave","reverb","sound katanas",
    "firstlight katana","nightfall katana","insect katana","flame katana",
    "thunder katana","water katana","wind katana","stone katana","beast katanas",
    "nightfall sickles","damascus sickles","blood sickles","nightfall scythe",
    "damascus scythe","firstlight spear","damascus spear","firstlight tanto",
    "damascus tanto","firstlight war fans","damascus war fans","damascus shotgun",
    "lost shotgun","nightfall gauntlet","damascus gauntlet","nightfall claws",
    "damascus claws","firstlight bladed wagasa","damascus bladed wagasa",
    "nightfall axe and mace","seismic axe and mace","damascus axe and mace",
    "nightfall serpent katana","firstlight sound cleavers","firstlight insect katana",
}

L.nonWeapons = {
    "rod","fishing","horse","gourd","orb","potion","elixir","meat","bandage",
    "bell","scroll","pouch","map","ore","horn","silk","scrap","ingot","cloth",
    "plating","tentacle","worm","coral","shovel","permit","letter","package",
    "gemstone","note","schematic","lantern","chest","coin","lure","fish","wen",
    "voucher","crate","emote","mask","haori","necklace","earring","crow",
    "kasugai","gourd","ring","horns","sword sheath","sheathe",
}

L.questItems = {
    "serpent key","shovel","frozen heart","supply box","fishing permit",
    "permit stamp","beast core","jewelry box","biwa bell","bandage",
    "broken nichirin katana","wagwan's ring","suspicious note","package",
    "letter","gemstone","cooked bear meat","book of guidance","bear meat",
    "bear claws","ore","lucky penny",
}

L.materials = {
    "coin stack","coin pouch","coin pile","coin","demon horns","crude iron ingot",
    "firstlight star ore","nightfall reinforced plating","firstlight weaver's silk",
    "nightfall weaver's cloth","firstlight forged ingot","nightfall forged ingot",
    "refinement guard","mythic refinement ore","refinement ore","silk thread",
    "metal scraps",
}

L.consumables = {
    "underwater breathing potion","stamina regen elixir","health regen elixir",
    "health elixir","muzan's blood","stamina regen potion","health regen potion",
    "health potion","large gourd","medium gourd","small gourd",
}

L.clans = {
    "uzui","agatsuma","kamado","rengoku","shinazugawa","tomiyoka","kocho",
    "kanroji","iguro","himejima","tokito","uzui supreme","sun breathing",
    "yoriichi","kokushibo","muzan",
}

L.regions = {
    "windy peak","bamboo grove","mistfall harbor","butterfly estate",
    "iceveil valley","iceveil settlement","hidden mist village",
    "final selection plains","final selection","dreamfall hollow",
    "stone sanctuary","verdant cliffs","forgotten ruins","veilfall cavern",
    "the white terror lair","seasons crossing","frost veil shrine",
}

L.breathings = {
    "water","flame","thunder","wind","stone","mist","serpent","insect",
    "sound","beast","sun","moon",
}

L.demonArts = {
    "blood manipulation","pyrokinesis","shockwave","cryokinesis",
    "obi manipulation","reaper","tamari","dream","arrow",
}

L.fightingStyles = {
    "reaping blades","tai chi","soryu",
}

L.questKeywords = {
    "quest","mission","task","objective","bounty","contract","hunt",
    "eliminate","target","assassin","slay","kill","reward",
}

L.crowKeywords = { "crow","kasugai" }

L.mobKeywords = {
    "bear","cub","bandit","civilian","demon","wolf","boar","trapper",
    "oni","slasher","thug","brigand","trainee",
}

function L.isBoss(nm)
    if not nm then return false end
    local l = string.lower(nm)
    for i = 1, #L.bosses do
        if string.find(l, L.bosses[i], 1, true) then return true end
    end
    return false
end

function L.isWeapon(nm)
    if not nm then return false end
    local l = string.lower(nm)
    for i = 1, #L.nonWeapons do
        if string.find(l, L.nonWeapons[i], 1, true) then return false end
    end
    for i = 1, #L.weapons do
        if string.find(l, L.weapons[i], 1, true) then return true end
    end
    return false
end

function L.isCrow(nm)
    if not nm then return false end
    local l = string.lower(nm)
    for i = 1, #L.crowKeywords do
        if string.find(l, L.crowKeywords[i], 1, true) then return true end
    end
    return false
end

function L.isQuest(nm)
    if not nm then return false end
    local l = string.lower(nm)
    for i = 1, #L.questKeywords do
        if string.find(l, L.questKeywords[i], 1, true) then return true end
    end
    return false
end

return L
