-- Dingus-Slayer · lists.lua v8

local L = {}

L.bossRegions = {
    { name = "Bamboo Grove", bosses = { "sumari", "yahari" } },
    { name = "Hidden Mist", bosses = { "reaper", "gyutai", "domae" } },
    { name = "Nightfall", bosses = { "datai", "akazo" } },
    { name = "Deep Caves", bosses = { "nezura", "enru" } },
}

L.bosses = {}
for _, r in ipairs(L.bossRegions) do
    for _, b in ipairs(r.bosses) do table.insert(L.bosses, b) end
end

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

local function matchWord(h, n)
    local s, e = h:find(n, 1, true)
    if not s then return false end
    if #n <= 3 then
        local before = s == 1 or not h:match("^%w", s-1)
        local after = e == #h or not h:match("^%w", e+1)
        return before and after
    end
    return true
end

local function matchAny(h, list)
    for i = 1, #list do if matchWord(h, list[i]) then return true end end
    return false
end

function L.isBoss(nm)
    if not nm then return false end
    local l = string.lower(nm)
    for i = 1, #L.bosses do
        local b = L.bosses[i]
        if matchWord(l, b) then return L.selectedBosses[b] ~= false end
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

return L
