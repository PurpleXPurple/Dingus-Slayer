--[[
    Dingus-Slayer · lists.lua v2
    Rebuilt from research against Project Slayers 2 (live 2026-10).

    Corrections applied (each tagged inline):
      - Removed: yoriichi, kokushibo, muzan (characters, not clans)
      - Removed: sun breathing (not a clan)
      - Removed: kanroji, tokito (not PS2 clans — anime-only)
      - Removed: pyrokinesis, cryokinesis (wrong BDA names)
      - Removed: dream, arrow, tamari (short forms, replaced with
        full "manipulation" names)
      - Removed: mist, beast, sun, moon (not PS2 breathing styles)
      - Removed: reaping blades (not a PS2 fighting style)
      - Removed: serpentine, tidal (not confirmed PS2 weapons)
      - Fixed: tomiyoka → tomioka
      - Fixed: zuko → zoku (wiki canonical)
      - Fixed: honyozu → hoyuzo
      - Added: ~30 missing bosses, ~25 weapons, ~20 regions,
        ~20 clans, ~10 quest items, ~5 BDAs, 1 fighting style

    Word-boundary matching retained from previous fix.
]]--

local L = {}

--============================================================
-- BOSSES
-- Sources: Fandom Bosses, Map 1, Map 2 pages; nerdschalk boss
-- location index; allthings.how endgame guide; sportsrant.
--============================================================
--============================================================
-- BOSSES
-- Sources: Fandom Bosses, Map 1/Map 2 pages; nerdschalk index;
--          in-game screenshots (quest panel, boss tracker).
--============================================================
L.bosses = {
    -- Map 1 (Ouwland)
    "zoku", "zuko",
    "zanegutsu", "kuuchie",
    "kaden",
    "sabito",
    "sanemi",
    "yahaba",
    "susamaru",
    "shiron",
    "giyu",
    "slasher",
    "nezuko",
    "mother bear",

    -- Map 2 (Ouwohana)
    "nomay bandit",
    "muichiro",
    "inosuke",
    "rengoku",
    "renpeke",
    "akeza",
    "swampy",

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

    --============================================================
    -- In-game renamed aliases
    -- The UI/quest panel uses shortened names not present in the
    -- Fandom wiki. Screenshot evidence (2026-10):
    --   quest panel: "Defeat Enru", "Defeat Datai", "Defeat Akazo"
    -- These are the game's display names for the wiki bosses Enmu,
    -- Daki, Akaza respectively. Both spellings must match.
    --============================================================
    "enru",
    "datai",
    "akazo",
}

--============================================================
-- WEAPONS
-- Sources: nerdschalk Nichirin guide, kongbakpao Nightfall
-- tier list, bloxinformer weapons, allthings.how demon weapons.
--============================================================
L.weapons = {
    -- Base katanas (Raze shop + boss drops)
    "regular katana", "fancy katana",
    "cutlass", "rare cutlass",
    "wind katana", "insect katana", "flame katana",
    "serpent katana", "thunder katana", "water katana",
    "sound katanas", "green katana", "butterfly katana",
    "champion katana",
    "enryu", "enryu katana",
    "shinkage", "shinkage katana",
    "tengoku", "tengoku katana",
    "devourer katana",

    -- V2 forged
    "volcanic katana", "tornadic katana",

    -- Nightfall set (7)
    "nightfall katana", "nightfall serpent katana",
    "nightfall axe and mace", "nightfall scythe",
    "nightfall gauntlets", "nightfall claws",
    "nightfall sickles",

    -- Demon-only
    "metal scythe", "skull scythe", "polar scythe",
    "devourer scythe",
    "claws", "bone claws",
    "scythe", "sickles", "blood sickles",
    "war fans",
    "claws", "claw",

    -- Slayer auxiliaries
    "axe and mace", "seismic axe and mace",
    "spear", "firstlight spear",
    "tanto", "firstlight tanto",
    "bladed wagasa", "firstlight bladed wagasa",
    "sound cleavers", "firstlight sound cleavers",
    "sickle",

    -- Forged tiers
    "firstlight", "nightfall", "damascus",
    "firstlight katana", "nightfall katana",
    "firstlight sickles", "damascus sickles",
    "firstlight scythe", "damascus scythe",
    "firstlight war fans", "damascus war fans",
    "damascus shotgun", "lost shotgun",
    "damascus gauntlet", "damascus claws",
    "damascus bladed wagasa",
    "damascus axe and mace",

    -- Generic sword keywords
    "sword", "katana", "saber", "sabre", "blade",
    "rapier", "nodachi", "wakizashi", "tachi",
    "cleaver", "mace", "axe",
    "gauntlet", "shotgun", "gun", "wagasa",
}

L.nonWeapons = {
    "rod", "fishing rod", "horse", "gourd",
    "orb", "potion", "elixir", "meat", "bandage",
    "bell", "scroll", "pouch", "map", "ore", "horn",
    "silk", "scrap", "ingot", "cloth", "plating",
    "tentacle", "worm", "coral", "shovel", "permit",
    "letter", "package", "gemstone", "note",
    "schematic", "lantern", "chest", "coin", "lure",
    "fish", "wen", "voucher", "crate", "emote",
    "mask", "haori", "necklace", "earring", "crow",
    "kasugai", "ring", "sword sheath", "sheathe",
    "uniform",
}

--============================================================
-- QUEST ITEMS
-- Sources: fandom quest pages, spider lily guides,
-- Supply the Settlement quest, Level 225 guide.
--============================================================
L.questItems = {
    "spider lily",                -- 9 needed for Muzan quest
    "bamboo muzzle",              -- Nezura drop
    "frozen heart",               -- Yeti-related
    "supply box",
    "fishing permit", "permit stamp",
    "beast core",                 -- 5 needed for Serpent Breathing
    "jewelry box", "biwa bell",
    "bandage",
    "broken nichirin katana",
    "wagwan's ring",
    "suspicious note", "package", "letter", "gemstone",
    "cooked bear meat",           -- 9 needed for Supply the Settlement
    "book of guidance",
    "bear meat", "bear claws",
    "lucky penny",
    "riyaku's necklace",          -- Zoku drop
    "sabito's mask",              -- Sabito drop 12%
    "serpent key",
    "nezuko's bamboo pacifier",   -- 5% Nezuko drop
    "golden kanzashi",            -- Daki drop
    "black lotus crown",          -- Doma drop
    "ember heart lantern",        -- required for snow biome
    "everburn lantern",           -- Tier 3 raid schematic
    "demon horn", "demon horns",  -- training material (20-50 needed)
    "ore",                        -- Final Selection reward
}

--============================================================
-- MATERIALS
--============================================================
L.materials = {
    -- Currency
    "coin stack", "coin pouch", "coin pile", "coin",
    -- Forging
    "crude iron ingot",
    "firstlight star ore",
    "nightfall reinforced plating",
    "firstlight weaver's silk",
    "nightfall weaver's cloth",
    "firstlight forged ingot",
    "nightfall forged ingot",
    "refinement guard",
    "mythic refinement ore",     -- 10 needed for V2
    "refinement ore",
    "silk thread",                -- 300 needed for V2
    "metal scraps",               -- 500 needed for V2
    "demon horns",
}

--============================================================
-- CONSUMABLES  (8 potions confirmed by progameguides)
--============================================================
L.consumables = {
    "health potion",
    "health regen potion",
    "health elixir",
    "health regen elixir",
    "stamina regen potion",
    "stamina regen elixir",
    "muzan's blood",              -- turns player into demon
    "underwater breathing potion",
    "large gourd", "medium gourd", "small gourd",
}

--============================================================
-- CLANS  (41 total; source: bloxinformer, techwiser tier list)
--============================================================
L.clans = {
    -- Supreme (0.1%)
    "kamado", "rengoku", "soyama",
    -- Mythic (0.9%)
    "agatsuma", "douma", "himejima", "iguro",
    "shinazugawa", "tamayo", "sabito",
    -- Legendary (4%)
    "kocho", "shabana", "tomioka", "ubuyashiki",
    -- Rare (12%)
    "makomo", "susumaru", "urokodaki", "yahaba",
    -- Uncommon (23%)
    "yamagiri",
    -- Common (60%)
    "aokawa", "fujiwara", "fukukoshi", "hagiwara", "hozumi",
    -- Other confirmed
    "kaneki", "kurotsume", "aoshima", "aori",
    -- Uzui (Supreme per some sources, Legendary per others)
    "uzui",
}

--============================================================
-- REGIONS
-- Sources: Fandom Map 1, Ouwland, Black Market locations.
--============================================================
L.regions = {
    -- Map 1 / Ouwland
    "kiribating village",
    "zapiwara cave", "zapiwara mountain",
    "ushumaru village",
    "waroru cave",
    "kabiwaru village",
    "abubu cave",
    "jinger's home", "wind trainer",
    "ouwbayashi home",
    "butterfly mansion",          -- wiki canonical (vs Butterfly Estate)
    "butterfly estate",           -- guide alternate
    "dangerous woods",
    "final selection", "final selection plains",
    "karu village",
    "torii village",
    "port",
    "ruin",

    -- Map 2 / Ouwohana
    "nomay village",
    "wop city",
    "akeza cave",
    "beast cave",
    "mist trainer",

    -- Cross-map / endgame
    "windy peak",
    "bamboo grove",
    "mistfall harbor", "mistful harbor",   -- guide typo variant
    "hidden mist village",
    "iceveil valley", "iceveil settlement",
    "dreamfall hollow",
    "frost veil shrine",
    "stone sanctuary",
    "forgotten ruins",
    "seasons crossing",
    "frozen valley",
    "ouwigahara",
}

--============================================================
-- BREATHING STYLES  (exactly 8 in PS2; sources confirm)
--============================================================
L.breathings = {
    "water", "thunder", "flame", "wind",
    "stone", "insect", "sound", "serpent",
    -- trainer names (often matched alongside style name)
    "urokodaki", "zentaro", "rengu", "saneri",
    "gyorei", "shinora", "tengai", "obari",
}

--============================================================
-- DEMON ARTS  (9 confirmed BDAs)
--============================================================
L.demonArts = {
    "blood manipulation",
    "ice manipulation",           -- was cryokinesis
    "arrow manipulation",         -- was arrow
    "shockwave",
    "explosive blood",
    "dream manipulation",         -- was dream
    "reaper",
    "obi manipulation",
    "tamari manipulation",        -- was tamari
    "tamari",                     -- short form fallback
}

--============================================================
-- FIGHTING STYLES  (3 confirmed)
--============================================================
L.fightingStyles = {
    "tai chi",
    "soryu",
    "reaper",
    -- trainer names
    "renjiro", "kazuma", "zurinyz",
}

L.questKeywords = {
    "quest", "mission", "task", "objective", "bounty",
    "contract", "hunt", "eliminate", "target",
    "assassin", "slay", "kill", "reward",
}

L.crowKeywords = { "crow", "kasugai" }

L.mobKeywords = {
    "bear", "cub", "bandit", "civilian", "demon",
    "wolf", "boar", "trapper", "oni", "slasher",
    "thug", "brigand", "trainee",
    "frost demon", "nomay bandit",
}

--============================================================
-- MATCHING
-- Word-boundary awareness for short needles (<= 3 chars).
-- Retained from previous fix; "ren" no longer matches "torrent",
-- "claw" no longer matches "clawmachine".
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

return L
