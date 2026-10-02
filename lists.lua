-- Dingus-Slayer · lists.lua v10
-- Merged from Synerox: full boss roster, 80 NPC positions, region anchors,
-- 18 quest entries, trainers, boss timers, shop, clans, BDA.

local L = {}

--============================================================
-- BOSS ROSTER (Synerox fn15 table)
--============================================================
L.bossNames = {
    yetidemon=true, smallyeti=true, handdemon=true, zuko=true,
    saneri=true, obari=true, shinora=true, giyen=true,
    tengai=true, tengen=true, zentaro=true, gyorei=true,
    rengu=true, gyutai=true, datai=true, reaper=true,
    akazo=true, domae=true, nezura=true, yahari=true,
    sumari=true, enru=true, hoyuzo=true, kaiden=true,
    flametrainee=true, watertrainee=true, watertraineesabito=true,
    thundertrainee=true, windtrainee=true, soundtrainee=true,
    stonetrainee=true, serpenttrainee=true, insecttrainee=true,
    taichitrainee=true, taichitraineesuzume=true, soryutrainee=true,
    soryutraineegoki=true, reapertrainee=true, reapertraineekuzan=true,
}

-- Human-readable display names
L.bosses = {
    "yetidemon","smallyeti","handdemon","zuko","saneri","obari",
    "shinora","giyen","tengai","tengen","zentaro","gyorei","rengu",
    "gyutai","datai","reaper","akazo","domae","nezura","yahari",
    "sumari","enru","hoyuzo","kaiden",
    "flametrainee","watertrainee","watertraineesabito",
    "thundertrainee","windtrainee","soundtrainee","stonetrainee",
    "serpenttrainee","insecttrainee","taichitrainee",
    "taichitraineesuzume","soryutrainee","soryutraineegoki",
    "reapertrainee","reapertraineekuzan",
}

L.bossRegions = {
    { name = "Bamboo Grove", bosses = { "sumari","yahari","hoyuzo","kaiden","zuko","obari","giyen" } },
    { name = "Hidden Mist",  bosses = { "reaper","gyutai","domae","tengen","tengai" } },
    { name = "Nightfall",    bosses = { "datai","akazo","rengu","saneri" } },
    { name = "Deep Caves",   bosses = { "nezura","enru","shinora","gyorei","zentaro" } },
    { name = "Training Grounds", bosses = {
        "flametrainee","watertrainee","watertraineesabito",
        "thundertrainee","windtrainee","soundtrainee","stonetrainee",
        "serpenttrainee","insecttrainee","taichitrainee",
        "taichitraineesuzume","soryutrainee","soryutraineegoki",
        "reapertrainee","reapertraineekuzan",
        "yeti","smallyeti","handdemon"
    } },
}

L.selectedBosses = {}
for _, b in ipairs(L.bosses) do L.selectedBosses[b] = true end

function L.setBossEnabled(n, e) if L.selectedBosses[n] ~= nil then L.selectedBosses[n] = not not e end end
function L.isBossEnabled(n) return L.selectedBosses[n] ~= false end
function L.setAllBosses(e) for _, b in ipairs(L.bosses) do L.selectedBosses[b] = not not e end end
function L.enabledCount()
    local n = 0
    for _, b in ipairs(L.bosses) do if L.selectedBosses[b] ~= false then n = n + 1 end end
    return n, #L.bosses
end

--============================================================
-- REGION TELEPORT ANCHORS (Synerox tbl2)
--============================================================
L.regions = {
    ["Hidden Mist Village"]   = Vector3.new(1651, 607.3, -124),
    ["Mistfall Harbor"]       = Vector3.new(140.7, 873.5, 728.2),
    ["Bamboo Grove"]          = Vector3.new(570, 1140, -1150),
    ["Windy Peak"]            = Vector3.new(-456, 1241, -932),
    ["Butterfly Estate"]      = Vector3.new(-1772, 311.3, -110.9),
    ["Iceveil Valley"]        = Vector3.new(283.9, 1305, -2041.2),
    ["Final Selection Plains"]= Vector3.new(-1834, 35, 487.5),
    ["Verdant Cliffs"]        = Vector3.new(1775, 715, -425),
    ["Forgotten Ruins"]       = Vector3.new(-954, 950, 945.5),
    ["Stone Sanctuary"]       = Vector3.new(2564.1, 980, -590),
    ["Misc"]                  = Vector3.new(-315.6, 1292.6, -1488.7),
    ["Temporary"]             = Vector3.new(807, 1122, -1005),
}

--============================================================
-- NPC / BOSS SPAWN POSITIONS (Synerox tbl3, ~80 entries)
--============================================================
L.npcPositions = {
    ["Kanoe Demon Slayer"]      = Vector3.new(283.9, 1305, -2041.2),
    ["Mizunoe Demon Slayer"]    = Vector3.new(-1834, 35, 487.5),
    ["Mizunoto"]                = Vector3.new(-784.5, 966.5, -133.8),
    ["Civilian"]                = Vector3.new(-567.4, 1246, -1024.5),
    ["*Civilian*"]              = Vector3.new(-703.9, 1246, -946.1),
    ["Bandit"]                  = Vector3.new(570, 1140, -1150),
    ["KaruVillageBandit"]       = Vector3.new(-456, 1241, -932),
    ["Spy"]                     = Vector3.new(-456, 1241, -932),
    ["VillageSpy"]              = Vector3.new(-456, 1241, -932),
    ["Bear Cub"]                = Vector3.new(520, 1122, -1045),
    ["Mother Bear"]             = Vector3.new(507.2, 1124, -970.3),
    ["Kaiden"]                  = Vector3.new(634, 1131.5, -1167),
    ["Kaiden Subordinate"]      = Vector3.new(590, 1148, -1300),
    ["Hoyuzo"]                  = Vector3.new(546.9, 1003.9, -1166.8),
    ["Hoyuzo Subordinate"]      = Vector3.new(546.9, 1003.9, -1166.8),
    ["Grove Raider"]            = Vector3.new(570, 1140, -1150),
    ["Raid Captain"]            = Vector3.new(570, 1140, -1150),
    ["Cache Prowler"]           = Vector3.new(570, 1140, -1150),
    ["Prowler Captain"]         = Vector3.new(570, 1140, -1150),
    ["Cache Lancer"]            = Vector3.new(570, 1140, -1150),
    ["Lancer Captain"]          = Vector3.new(570, 1140, -1150),
    ["IceveilRoadBandit"]       = Vector3.new(142.1, 1385.1, -2783.2),
    ["IceveilRoadMarauder"]     = Vector3.new(142.1, 1385.1, -2783.2),
    ["IceveilRoadPikeman"]      = Vector3.new(142.1, 1385.1, -2783.2),
    ["High Demon"]              = Vector3.new(283.9, 1302, -2041.2),
    ["Fire Profound Demon"]     = Vector3.new(142.1, 1385.1, -2783.2),
    ["Ice Profound Demon"]      = Vector3.new(142.1, 1385.1, -2783.2),
    ["GreaterDemon_ButterflyEstate"] = Vector3.new(-498.9, 284.8, 528.8),
    ["LesserDemon_ButterflyEstate"]  = Vector3.new(-675.7, 230.5, 397.1),
    ["Greater Demon"]           = Vector3.new(-498.9, 284.8, 528.8),
    ["Lesser Demon"]            = Vector3.new(-675.7, 230.5, 397.1),
    ["BloodHoundedDemon_MistfallHarbor"] = Vector3.new(140.7, 873.5, 728.2),
    ["Beast Born Demon"]        = Vector3.new(140.7, 873.5, 728.2),
    ["YetiDemon"]               = Vector3.new(142.1, 1385.1, -2783.2),
    ["SmallYeti"]               = Vector3.new(142.1, 1385.1, -2783.2),
    ["HandDemon"]               = Vector3.new(-1834, 35, 487.5),
    ["Flame Trainee"]           = Vector3.new(-1128.9, 1029, 994.4),
    ["Water Trainee"]           = Vector3.new(815.3, 1018.8, 101.6),
    ["Water Trainee Sabito"]    = Vector3.new(815.3, 1018.8, 101.6),
    ["Thunder Trainee"]         = Vector3.new(2425.5, 1073.6, -556.8),
    ["Wind Trainee"]            = Vector3.new(-941.6, 1381, -2635.6),
    ["Sound Trainee"]           = Vector3.new(192.5, 1349, -2581.3),
    ["Stone Trainee"]           = Vector3.new(2685.2, 1073.6, -568.8),
    ["Serpent Trainee"]         = Vector3.new(-271.4, 1292, -1535.7),
    ["Insect Trainee"]          = Vector3.new(-1395.6, 261.5, 69.2),
    ["Tai Chi Trainee"]         = Vector3.new(2360.5, 602, -642.3),
    ["Tai Chi Trainee Suzume"]  = Vector3.new(2360.5, 602, -642.3),
    ["Soryu Trainee"]           = Vector3.new(-427, 288.8, 543.3),
    ["Soryu Trainee Goki"]      = Vector3.new(-427, 288.8, 543.3),
    ["Reaper Trainee"]          = Vector3.new(-1219.3, 1373.6, -3034.4),
    ["Reaper Trainee Kuzan"]    = Vector3.new(-1219.3, 1373.6, -3034.4),
    ["Tengai"]                  = Vector3.new(-133.5, 1349, -2631.3),
    ["Tengen"]                  = Vector3.new(-133.5, 1349, -2631.3),
    ["Tengai (Tengen)"]         = Vector3.new(-133.5, 1349, -2631.3),
    ["Zentaro"]                 = Vector3.new(1332.1, 821.5, -1017.6),
    ["Reaper"]                  = Vector3.new(98.5, 1043, -573.9),
    ["Akazo"]                   = Vector3.new(-1132, 1380.9, -1746.6),
    ["Shinora"]                 = Vector3.new(-452.6, 964.5, 2.1),
    ["Yahari"]                  = Vector3.new(825.7, 1019.2, -641.3),
    ["Domae"]                   = Vector3.new(-296.5, 1350.5, -3451.3),
    ["Obari"]                   = Vector3.new(770.5, 1121, -1047),
    ["Saneri"]                  = Vector3.new(-379.1, 1093.5, -422.4),
    ["Enru"]                    = Vector3.new(821.8, 800, 543.9),
    ["Sumari"]                  = Vector3.new(396.4, 1018, -620.4),
    ["Rengu"]                   = Vector3.new(-712.9, 965, 883.8),
    ["Gyorei"]                  = Vector3.new(2574.6, 1089, -742.4),
    ["Datai"]                   = Vector3.new(-165.5, 1043, -1137.5),
    ["Nezura"]                  = Vector3.new(-1459.5, 276, 935.5),
    ["Giyen"]                   = Vector3.new(388.9, 1018, -85.1),
    ["Gyutai"]                  = Vector3.new(-266.1, 1043.2, -1139.7),
    ["Zuko"]                    = Vector3.new(-297, 1224, -1023),
    ["Muzan"]                   = Vector3.new(2466.3, 1079.3, 2334.5),
    ["Krue"]                    = Vector3.new(-425.5, 1243.5, -952.5),
    ["Tom"]                     = Vector3.new(540, 1121, -1024),
    ["Chaka"]                   = Vector3.new(585, 1146, -1315),
    ["Wagwan"]                  = Vector3.new(723.8, 1019.2, -802),
    ["Rin"]                     = Vector3.new(170, 888, 603),
    ["Jugg"]                    = Vector3.new(487.7, 874.1, 1007.8),
    ["Shady Individual Rooyi"]  = Vector3.new(-834, 964, -76),
    ["Demon Slayer Goro"]       = Vector3.new(-872, 234.8, 318.5),
    ["Demon Mokuro"]            = Vector3.new(-1835, 31, 487),
    ["Wounded Slayer Tomoi"]    = Vector3.new(485.3, 1222.6, -1813),
    ["Demon Delroy"]            = Vector3.new(283, 1302, -2042),
    ["Demon Slayer Mitsu"]      = Vector3.new(-824.3, 1381.5, -2537.8),
    ["Raze"]                    = Vector3.new(-586.3, 1244.6, -1085.8),
    ["Master Swordsmith"]       = Vector3.new(-1200, 950, 850),
    ["Village Tailor"]          = Vector3.new(-535, 1245, -1325),
    ["Mask Merchant"]           = Vector3.new(-650, 1250, -1180),
    ["Gourd Merchant"]          = Vector3.new(-1798.9, 347.9, -189.3),
    ["Angler Runo"]             = Vector3.new(140.7, 873.5, 728.2),
    ["Butterfly Clinic"]        = Vector3.new(-1798.9, 347.9, -189.3),
    ["Horse Carriage Guy"]      = Vector3.new(-715, 1260, -1120),
    ["Grandpa Somi"]            = Vector3.new(700, 1150, -1050),
    ["Beth"]                    = Vector3.new(-690, 1261, -1200),
    ["Sabito"]                  = Vector3.new(-1046.8, 1133.5, -628.8),
    ["Doctor Ino"]              = Vector3.new(895, 1120, -880),
    ["Final Selection Guides"]  = Vector3.new(-1994.1, 750, 1050.1),
}

--============================================================
-- QUEST DATABASE (Synerox tbl4 — 18 entries)
--============================================================
L.quests = {
    { name="Ill take 3 bandits",            display="Bandits (Lv 0+)",              inst="Defeat 3 bandits",               minLvl=0,   cat="Normal", region="Windy Peak",           race="Any",            npc="Krue", mob="Bandit",               wp=Vector3.new(-297,1224,-1023),  tasks={["Bandits remaining"]="Bandit"} },
    { name="Ill take the bandit boss(Lv 7)", display="Zuko (Boss Lv 7+)",            inst="Defeat The Bandit Boss",         minLvl=7,   cat="Boss",   region="Windy Peak",           race="Any",            npc="Krue", mob="Zuko",                 wp=Vector3.new(-297,1224,-1023),  tasks={["Defeat Zuko"]="Zuko"} },
    { name="Ill drive the bears back(Lv 10)",display="Bear Cubs (Lv 10+)",           inst="Hunt the Bears",                 minLvl=10,  cat="Normal", region="Bamboo Grove",         race="Any",            npc="Tom",  mob="Bear Cub",             wp=Vector3.new(540,1121,-1024),   tasks={["Bear Cubs hunted"]="Bear Cub"} },
    { name="Ill fell the Mother Bear(Lv 18)",display="Mother Bear (Lv 18+)",          inst="Fell the Mother Bear",           minLvl=18,  cat="Normal", region="Bamboo Grove",         race="Any",            npc="Tom",  mob="Mother Bear",          wp=Vector3.new(540,1121,-1024),   tasks={["Fell the Mother Bear"]="Mother Bear"} },
    { name="Ill clear out his subordinates(Lv 26)",display="Kaiden Subordinates (Lv 26+)",inst="Clear Kaiden's Subordinates", minLvl=26,  cat="Normal", region="Bamboo Grove",         race="Any",            npc="Chaka",mob="Kaiden Subordinate",   wp=Vector3.new(585,1146,-1315),   tasks={["Subordinates defeated"]="Kaiden Subordinate"} },
    { name="Ill deal with Kaiden(Lv 34)",   display="Kaiden (Boss Lv 34+)",          inst="Defeat Kaiden",                  minLvl=34,  cat="Boss",   region="Bamboo Grove",         race="Any",            npc="Chaka",mob="Kaiden",               wp=Vector3.new(585,1146,-1315),   tasks={["Defeat Kaiden"]="Kaiden"} },
    { name="I will clear out his guards(Lv 40)",display="Hoyuzo Guards (Lv 40+)",     inst="Clear Hoyuzo's Guard",           minLvl=40,  cat="Normal", region="Bamboo Grove",         race="Any",            npc="Wagwan",mob="Hoyuzo Subordinate",  wp=Vector3.new(533,1001,-1357),   tasks={["Guards defeated"]="Hoyuzo Subordinate"} },
    { name="Ill drive them off(Lv 47)",     display="Beast Born Demons (Lv 47+)",    inst="Hold the Night",                 minLvl=47,  cat="Normal", region="Mistfall Harbor",      race="Any",            npc="Rin",  mob="Beast Born Demon",     wp=Vector3.new(170,888,603),      tasks={["Beast Born Demons defeated"]="Beast Born Demon"} },
    { name="I will take care of Hoyuzo(Lv 50)",display="Hoyuzo (Boss Lv 50+)",        inst="Defeat Hoyuzo",                  minLvl=50,  cat="Boss",   region="Bamboo Grove",         race="Any",            npc="Wagwan",mob="Hoyuzo",              wp=Vector3.new(746,1001,-1413),   tasks={["Defeat Hoyuzo"]="Hoyuzo"} },
    { name="Ill clear the cave(Lv 62)",     display="Blood Hounded Demons (Lv 62+)", inst="Purge Dreamfall Hollow",         minLvl=62,  cat="Normal", region="Mistfall Harbor",      race={"Slayer","Hybrid"}, npc="Jugg", mob="Blood Hounded Demon", wp=Vector3.new(789,829,927),      tasks={["Blood Hounded Demons defeated"]="Blood Hounded Demon"} },
    { name="Ill eliminate the Mizunoto(Lv 62)",display="Mizunoto Slayers (Lv 62+)",   inst="Eliminate the Mizunoto",         minLvl=62,  cat="Normal", region="Mistfall Harbor",      race={"Demon","Hybrid"}, npc="Shady Individual Rooyi", mob="Mizunoto", wp=Vector3.new(-834,964,-76),     tasks={["Broken Nichirin Katanas"]="Mizunoto"} },
    { name="Ill thin them out(Lv 75)",      display="Lesser Demons (Lv 75+)",        inst="Thin the Cavern Floor",          minLvl=75,  cat="Normal", region="Butterfly Estate",     race={"Slayer","Hybrid"}, npc="Demon Slayer Goro", mob="Lesser Demon", wp=Vector3.new(-675,230,397),    tasks={["Lesser Demons defeated"]="Lesser Demon"} },
    { name="Ill break their watch(Lv 75)",  display="Mizunoe Slayers (Lv 75+)",      inst="Break Their Watch",              minLvl=75,  cat="Normal", region="Final Selection Plains",race={"Demon","Hybrid"}, npc="Demon Mokuro",   mob="Mizunoe Demon Slayer", wp=Vector3.new(-1835,31,487),     tasks={["Mizunoe Demon Slayers defeated"]="Mizunoe Demon Slayer"} },
    { name="Ill go up after the greater ones(Lv 83)",display="Greater Demons (Lv 83+)",inst="Hunt the Greater Demons",       minLvl=83,  cat="Normal", region="Butterfly Estate",     race={"Slayer","Hybrid"}, npc="Demon Slayer Goro", mob="Greater Demon", wp=Vector3.new(-498,284,528),    tasks={["Greater Demons defeated"]="Greater Demon"} },
    { name="Ill help you defeat them(Lv 90)",display="High Demons (Lv 90+)",         inst="Drive Off the High Demons",      minLvl=90,  cat="Normal", region="Iceveil Valley",       race={"Slayer","Hybrid"}, npc="Wounded Slayer Tomoi", mob="High Demon", wp=Vector3.new(388,1253,-1928),   tasks={["High Demons defeated"]="High Demon"} },
    { name="Theyre not welcome here(Lv 90)",display="Kanoe Slayers (Lv 90+)",        inst="They're Not Welcome Here",       minLvl=90,  cat="Normal", region="Iceveil Valley",       race={"Demon","Hybrid"}, npc="Demon Delroy",    mob="Kanoe Demon Slayer", wp=Vector3.new(283,1302,-2042),   tasks={["Kanoe Demon Slayers defeated"]="Kanoe Demon Slayer"} },
    { name="Ill drive back the frost(Lv 105)",display="Ice Profound Demons (Lv 105+)",inst="Drive Back the Frost",           minLvl=105, cat="Normal", region="Iceveil Valley",       race="Any",            npc="Demon Slayer Mitsu", mob="Ice Profound Demon", wp=Vector3.new(-920,1381,-2448),  tasks={["Ice Profound Demons defeated"]="Ice Profound Demon"} },
    { name="Ill put out the blaze(Lv 115)", display="Fire Profound Demons (Lv 115+)",inst="Put Out the Blaze",              minLvl=115, cat="Normal", region="Iceveil Valley",       race="Any",            npc="Demon Slayer Mitsu", mob="Fire Profound Demon", wp=Vector3.new(-916,1374,-2431),  tasks={["Fire Profound Demons defeated"]="Fire Profound Demon"} },
}

--============================================================
-- TRAINERS (Synerox tbl10)
--============================================================
L.trainers = {
    { name="Urokodaki", display="Water Breathing",  style="Water",   pos=Vector3.new(667.2,1022.7,-228.2) },
    { name="Zentaro",   display="Thunder Breathing",style="Thunder", pos=Vector3.new(1970.2,1660,-609.8) },
    { name="Rengu",     display="Flame Breathing",  style="Flame",   pos=Vector3.new(-967.6,1028.7,1188.2) },
    { name="Saneri",    display="Wind Breathing",   style="Wind",    pos=Vector3.new(-275.6,1187.5,-3436.7) },
    { name="Gyorei",    display="Stone Breathing",  style="Stone",   pos=Vector3.new(2578.6,1095.8,-828.4) },
    { name="Shinora",   display="Insect Breathing", style="Insect",  pos=Vector3.new(-1798.9,347.9,-189.3) },
    { name="Obari",     display="Serpent Breathing",style="Serpent", pos=Vector3.new(37,1311.2,-1179.5) },
    { name="Tengai",    display="Sound Breathing",  style="Sound",   pos=Vector3.new(464.9,1491.1,-3272.8) },
}

--============================================================
-- BOSS TIMERS (Synerox tbl7)
--============================================================
L.bossTimers = {
    Nezuko      = { respawn=600,  pos=Vector3.new(-1040,1120,-680) },
    Yahaba      = { respawn=900,  pos=Vector3.new(-150,280,-1650) },
    Sasumaru    = { respawn=900,  pos=Vector3.new(-180,280,-1700) },
    HandDemon   = { respawn=600,  pos=Vector3.new(2250,1600,-750) },
    Sabito      = { respawn=600,  pos=Vector3.new(-1046.8,1133.5,-628.8) },
    Shiron      = { respawn=480,  pos=Vector3.new(800,1030,-180) },
    Sanemi      = { respawn=1200, pos=Vector3.new(-280,1190,-3450) },
    Giyu        = { respawn=1200, pos=Vector3.new(670,1030,-250) },
    Rengoku     = { respawn=1200, pos=Vector3.new(-970,1035,1200) },
    Tengen      = { respawn=1200, pos=Vector3.new(1980,1670,-620) },
    Akaza       = { respawn=1500, pos=Vector3.new(3100,1800,-1500) },
    Douma       = { respawn=1800, pos=Vector3.new(-2500,2100,800) },
}

--============================================================
-- SHOP (Synerox tbl5)
--============================================================
L.shop = {
    weapons = {
        ["Common Katana"]     = { price=500,   pos=Vector3.new(-586.3,1244.6,-1085.8) },
        ["Water Nichirin"]    = { price=2500,  pos=Vector3.new(667.2,1022.7,-228.2) },
        ["Thunder Nichirin"]  = { price=2500,  pos=Vector3.new(1970.2,1660,-609.8) },
        ["Wind Nichirin"]     = { price=2500,  pos=Vector3.new(-275.6,1187.5,-3436.7) },
        ["Flame Nichirin"]    = { price=2500,  pos=Vector3.new(-967.6,1028.7,1188.2) },
        ["Insect Nichirin"]   = { price=3000,  pos=Vector3.new(-1805,350,-180) },
        ["Sound Nichirin"]    = { price=3000,  pos=Vector3.new(1980,1670,-620) },
        ["Beast Nichirin"]    = { price=3000,  pos=Vector3.new(450,1050,-320) },
        ["Mist Nichirin"]     = { price=3500,  pos=Vector3.new(980,280,-2820) },
        ["Sun Nichirin"]      = { price=5000,  pos=Vector3.new(-1050,1135,-630) },
        ["Moon Nichirin"]     = { price=5000,  pos=Vector3.new(3100,1800,-1500) },
        ["Devourer Katana"]   = { price=10000, pos=Vector3.new(-2500,2100,800) },
    },
    gourds = {
        ["Small Gourd"]  = { price=700,  pos=Vector3.new(-1798.9,347.9,-189.3) },
        ["Medium Gourd"] = { price=1500, pos=Vector3.new(-1798.9,347.9,-189.3) },
        ["Big Gourd"]    = { price=3500, pos=Vector3.new(-1798.9,347.9,-189.3) },
    },
    items = {
        ["Bandage"]        = { price=50,  pos=Vector3.new(-586.3,1244.6,-1085.8) },
        ["Health Potion"]  = { price=200, pos=Vector3.new(-1798.9,347.9,-189.3) },
        ["Stamina Elixir"] = { price=200, pos=Vector3.new(-1798.9,347.9,-189.3) },
        ["Lantern"]        = { price=250, pos=Vector3.new(540,1121,-1024) },
        ["Fishing Bait"]   = { price=100, pos=Vector3.new(140.7,873.5,728.2) },
    },
}

--============================================================
-- CLANS + BDA (Synerox)
--============================================================
L.clans = {
    "Kamado","Rengoku","Soyama","Uzui",
    "Agatsuma","Douma","Himejima","Iguro","Shinazugawa","Tamayo",
    "Kocho","Shabana","Tomioka","Ubuyashiki",
    "Makomo","Sabito","Susumaru","Urokodaki","Yahaba",
    "Aori","Aoshima","Kaneki","Kurotsume","Yamagiri",
    "Ando","Aokawa","Fujiwara","Fukukoshi","Hagiwara","Hozumi",
    "Kanzaki","Kazetani","Kuroaki","Kurosaki","Mori","Saito",
    "Sakurai","Suzuki","Toka","Tsukino","Yukimori",
}

L.bda = {
    "Arrow","Blood Manipulation","Cryokinesis","Dream",
    "Obi Manipulation","Pyrokenesis","Reaper","Shockwave","Tamari",
}

--============================================================
-- WEAPON CLASSIFICATION (retained)
--============================================================
L.weapons = {
    "katana","sword","blade","saber","sabre","cutlass","rapier",
    "nodachi","wakizashi","tachi","scythe","sickles","sickle",
    "spear","tanto","gauntlet","gauntlets","claws","claw",
    "wagasa","cleaver","cleavers","axe","mace","war fans",
    "shotgun","gun","nightfall","firstlight","damascus",
    "enryu","shinkage","tengoku","volcanic","tornadic","metal",
    "skull","polar","devourer","bone","champion","green",
    "butterfly","insect","flame","serpent","thunder","water",
    "wind","sound","beast","regular","fancy","ocean wave",
    "reverb","blood","seismic","bladed",
}

L.nonWeapons = {
    "rod","fishing","horse","gourd","orb","potion","elixir",
    "meat","bandage","bell","scroll","pouch","map","ore","horn",
    "silk","scrap","ingot","cloth","plating","tentacle","worm",
    "coral","shovel","permit","letter","package","gemstone","note",
    "schematic","lantern","chest","coin","lure","fish","wen",
    "voucher","crate","emote","mask","haori","necklace","earring",
    "kasugai","ring","sheath","sheathe","uniform","crow",
}

L.mobKeywords = {}
L.questKeywords = {}
L.crowKeywords = { "crow", "kasugai" }

--============================================================
-- MATCHERS
--============================================================
local function normalize(n)
    return string.lower(n or ""):gsub("%s+", "")
end

local function matchAny(h, list)
    for i = 1, #list do
        if h:find(list[i], 1, true) then return true end
    end
    return false
end

function L.isBoss(nm)
    if not nm then return false end
    local n = normalize(nm)
    if L.bossNames[n] then return L.selectedBosses[n] ~= false end
    for _, b in ipairs(L.bosses) do
        if n:find(b, 1, true) then return L.selectedBosses[b] ~= false end
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

function L.isQuest(_) return false end

function L.getBossRegion(nm)
    local n = normalize(nm)
    for _, r in ipairs(L.bossRegions) do
        for _, b in ipairs(r.bosses) do
            if n:find(b, 1, true) then return r.name end
        end
    end
    return "Unknown"
end

function L.getRegionPos(regionName)
    return L.regions[regionName]
end

function L.getNpcPos(npcName)
    return L.npcPositions[npcName]
end

function L.findNpcPosition(arg)
    if not arg then return nil end
    local target = normalize(arg)
    for k, v in pairs(L.npcPositions) do
        if normalize(k):find(target, 1, true) or target:find(normalize(k), 1, true) then
            return v, k
        end
    end
    return nil
end

return L
