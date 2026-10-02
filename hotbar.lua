-- Dingus-Slayer · hotbar.lua v4
-- Full item DB + mutex + slot scanner + auto-equip + cross-device.
-- Fires hotbar keys via U.fireSkill (same KeyLabel path as skills).

local H = {}

function H.init(Ctx)
    local U, F, S = Ctx.Util, Ctx.Cfg, Ctx.St

    --============================================================
    -- STATE
    --============================================================
    S.hotbarHolder  = nil
    S.hotbarExpiry  = 0
    S.hotbarSlots   = F.HotbarSlots or S.hotbarSlots or {}   -- [key] = itemName
    S.hotbarLastKey = nil
    S.hotbarTaps    = 0
    S.hotbarDenied  = 0
    S.hotbarSlotTs  = 0

    --============================================================
    -- ITEM DATABASE
    -- Categories: weapon, crow, potion, gourd, utility, accessory
    --============================================================
    local DB = {
        -- WEAPONS — Katanas
        ["regular katana"]="weapon", ["fancy katana"]="weapon",
        ["green katana"]="weapon", ["cutlass"]="weapon",
        ["water katana"]="weapon", ["flame katana"]="weapon",
        ["wind katana"]="weapon", ["thunder katana"]="weapon",
        ["stone katana"]="weapon", ["mist katana"]="weapon",
        ["insect katana"]="weapon", ["serpent katana"]="weapon",
        ["sound katana"]="weapon", ["sound katanas"]="weapon",
        ["beast katanas"]="weapon", ["ocean wave katana"]="weapon",
        ["waterfall katana"]="weapon", ["cloud katana"]="weapon",
        ["butterfly katana"]="weapon", ["champion katana"]="weapon",
        ["thundercloud katana"]="weapon", ["devourer katana"]="weapon",
        -- V2 forged
        ["volcanic katana"]="weapon", ["tornadic katana"]="weapon",
        ["serpentine katana"]="weapon",
        -- Hidden Mist forge
        ["enryu katana"]="weapon", ["shinkage katana"]="weapon",
        ["tengoku katana"]="weapon",
        -- Nightfall set
        ["nightfall katana"]="weapon", ["nightfall serpent katana"]="weapon",
        ["nightfall scythe"]="weapon", ["nightfall sickles"]="weapon",
        ["nightfall claws"]="weapon", ["nightfall gauntlets"]="weapon",
        ["nightfall axe and mace"]="weapon",
        -- Firstlight set
        ["firstlight katana"]="weapon", ["firstlight tanto"]="weapon",
        ["firstlight spear"]="weapon", ["firstlight war fans"]="weapon",
        ["firstlight bladed wagasa"]="weapon",
        ["firstlight sound cleavers"]="weapon",
        ["firstlight insect katana"]="weapon",
        -- Polar set
        ["polar katana"]="weapon", ["polar scythe"]="weapon",
        ["polar fans"]="weapon",
        -- Devourer set
        ["devourer scythe"]="weapon", ["devourer fans"]="weapon",
        ["devourer claws"]="weapon",
        -- Demon-only
        ["metal scythe"]="weapon", ["skull scythe"]="weapon",
        ["bone claws"]="weapon", ["blood sickles"]="weapon",
        ["war fans"]="weapon",
        -- Standalones
        ["spear"]="weapon", ["tanto"]="weapon",
        ["gauntlet"]="weapon", ["gauntlets"]="weapon",
        ["axe and mace"]="weapon", ["shotgun"]="weapon",
        ["lost shotgun"]="weapon", ["bladed wagasa"]="weapon",
        ["scythe"]="weapon", ["sickles"]="weapon", ["claws"]="weapon",
        ["cleaver"]="weapon", ["katana"]="weapon", ["sword"]="weapon",

        -- CROW
        ["kasugai crow"]="crow", ["kasugai"]="crow",
        ["crow"]="crow", ["the crow"]="crow",

        -- POTIONS
        ["health potion"]="potion",
        ["health regen potion"]="potion",
        ["health elixir"]="potion",
        ["health regen elixir"]="potion",
        ["stamina potion"]="potion",
        ["stamina regen potion"]="potion",
        ["stamina regen elixir"]="potion",
        ["underwater breathing potion"]="potion",
        ["muzan's blood"]="potion",

        -- GOURDS
        ["small gourd"]="gourd", ["medium gourd"]="gourd",
        ["large gourd"]="gourd", ["big gourd"]="gourd",
        ["clay gourd"]="gourd", ["focus gourd"]="gourd",
        ["rage gourd"]="gourd",

        -- UTILITY
        ["lantern"]="utility", ["demonic lantern"]="utility",
        ["nichirin lantern"]="utility",
        ["frozen heart lantern"]="utility",
        ["ember heart lantern"]="utility",
        ["everburn lantern"]="utility",
        ["horse"]="utility", ["fishing rod"]="utility",
        ["shovel"]="utility", ["permit"]="utility",
        ["key"]="utility", ["serpent key"]="utility",

        -- ACCESSORIES
        ["red oni mask"]="accessory", ["bamboo muzzle"]="accessory",
        ["stone haori"]="accessory", ["reaper's outfit"]="accessory",
        ["kintsugi haori"]="accessory",
        ["black dragon armour"]="accessory",
        ["black lotus crown"]="accessory",
        ["golden kanzashi"]="accessory",
        ["stylish haori"]="accessory",
        ["stylish mask"]="accessory",
        ["fox mask"]="accessory",
        ["straw hat"]="accessory",
        ["demonic horns"]="accessory",
        ["demonic horns ii"]="accessory",
        ["sabito's mask"]="accessory",
        ["nezuko's bamboo pacifier"]="accessory",
        ["riyaku's necklace"]="accessory",
        ["polar mask"]="accessory",
        ["scare dwarding mask"]="accessory",
    }

    -- Weapon tier (higher = better for auto-equip)
    local TIER = {
        devourer = 100, firstlight = 95, nightfall = 90,
        enryu = 88, shinkage = 88, tengoku = 88,
        sun = 85, moon = 80, volcanic = 78, tornadic = 78,
        serpentine = 78, mist = 75, sound = 70, insect = 65,
        flame = 60, thunder = 55, water = 50, wind = 45,
        stone = 44, beast = 40, polar = 35, champion = 30,
        butterfly = 28, cloud = 26, thundercloud = 24,
        ocean = 22, waterfall = 20, common = 20, regular = 18,
        fancy = 16, green = 14, wooden = 10, metal = 8,
    }

    --============================================================
    -- HELPERS
    --============================================================
    local function normalize(n)
        if not n then return "" end
        return string.lower(n):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function tick()
        if S.hotbarHolder and U.clock() >= S.hotbarExpiry then
            S.hotbarHolder = nil
            S.hotbarExpiry = 0
        end
    end

    local function readEquippedName()
        local c = U.Lp.Character
        if not c then return nil end
        for _, x in ipairs(c:GetChildren()) do
            if x:IsA("Tool") then return x.Name end
        end
        for _, hand in ipairs({ "RightHand", "LeftHand" }) do
            local h = c:FindFirstChild(hand)
            if h then
                for _, ch in ipairs(h:GetChildren()) do
                    if ch:IsA("BasePart") or ch:IsA("MeshPart")
                       or ch:IsA("Model") then
                        return ch.Name
                    end
                end
            end
        end
        for _, attr in ipairs({ "EquippedItem", "CurrentItem", "HeldItem" }) do
            local ok, v = pcall(function() return c:GetAttribute(attr) end)
            if ok and type(v) == "string" then return v end
        end
        return nil
    end

    --============================================================
    -- CLASSIFY
    --============================================================
    function H.classifyItem(name)
        local n = normalize(name)
        if #n == 0 then return nil end
        if DB[n] then return DB[n] end
        for key, cat in pairs(DB) do
            if n:find(key, 1, true) or key:find(n, 1, true) then
                return cat
            end
        end
        if n:find("katana") or n:find("sword") or n:find("scythe")
           or n:find("claw") or n:find("sickle") or n:find("spear")
           or n:find("tanto") or n:find("fans") or n:find("gauntlet")
           or n:find("axe") or n:find("mace") then
            return "weapon"
        end
        if n:find("potion") or n:find("elixir") then return "potion" end
        if n:find("gourd") then return "gourd" end
        if n:find("crow") or n:find("kasugai") then return "crow" end
        if n:find("haori") or n:find("mask") or n:find("necklace")
           or n:find("earring") or n:find("ring") then
            return "accessory"
        end
        return nil
    end

    local function weaponTier(name)
        local n = normalize(name)
        local best = 0
        for k, v in pairs(TIER) do
            if n:find(k, 1, true) and v > best then best = v end
        end
        return best
    end

    --============================================================
    -- MUTEX
    --============================================================
    function H.acquire(holder, duration)
        tick()
        if S.hotbarHolder and S.hotbarHolder ~= holder then
            S.hotbarDenied = S.hotbarDenied + 1
            return false
        end
        S.hotbarHolder = holder
        S.hotbarExpiry = U.clock() + (duration or 1.0)
        return true
    end

    function H.release(holder)
        tick()
        if not S.hotbarHolder then return true end
        if S.hotbarHolder == holder then
            S.hotbarHolder = nil
            S.hotbarExpiry = 0
        end
        return true
    end

    function H.isLocked() tick(); return S.hotbarHolder end
    function H.lockedBy() tick(); return S.hotbarHolder end
    function H.forceRelease() S.hotbarHolder = nil; S.hotbarExpiry = 0 end

    -- Waits up to `timeout` for mutex to be free, then acquires
    function H.waitFree(holder, timeout)
        timeout = timeout or 1.0
        local deadline = U.clock() + timeout
        while U.clock() < deadline do
            if H.acquire(holder, 1.0) then return true end
            task.wait(0.05)
        end
        return false
    end

    --============================================================
    -- TAP
    --============================================================
    function H.tap(holder, key, wait)
        if not H.acquire(holder, (wait or 0.4) + 0.2) then return false end
        local before = readEquippedName()
        if not U.fireSkill(tostring(key)) then
            U.tap(tostring(key), 0.05)
        end
        S.hotbarLastKey = key
        S.hotbarTaps = S.hotbarTaps + 1
        if wait and wait > 0 then task.wait(wait) end
        local after = readEquippedName()
        if after and after ~= before then
            S.hotbarSlots[key] = after
        end
        return true
    end

    function H.tapVerified(holder, key, expected, wait)
        if not H.acquire(holder, (wait or 0.5) + 0.3) then
            return false, "busy"
        end
        if not U.fireSkill(tostring(key)) then
            U.tap(tostring(key), 0.05)
        end
        S.hotbarLastKey = key
        S.hotbarTaps = S.hotbarTaps + 1
        task.wait(wait or 0.5)
        local eq = readEquippedName()
        if not eq then return false, "no-equip" end
        S.hotbarSlots[key] = eq
        if not expected then return true, eq end
        local n = normalize(eq)
        local e = normalize(expected)
        if n == e or n:find(e, 1, true) or e:find(n, 1, true) then
            return true, eq
        end
        return false, "wrong-item:" .. eq
    end

    --============================================================
    -- SLOT LOOKUP
    --============================================================
    function H.slotOf(itemName)
        if not itemName then return nil end
        local e = normalize(itemName)
        for k, v in pairs(S.hotbarSlots) do
            if v and normalize(v):find(e, 1, true) then return k end
        end
        return nil
    end

    function H.hasItem(itemName)
        return H.slotOf(itemName) ~= nil
    end

    function H.slotsOfCategory(cat)
        local out = {}
        for k, v in pairs(S.hotbarSlots) do
            if v and H.classifyItem(v) == cat then
                table.insert(out, { key = k, item = v })
            end
        end
        return out
    end

    function H.readCurrentSlot() return S.hotbarLastKey end

    --============================================================
    -- SLOT SCANNER — probes 1-9, records what appears
    --============================================================
    function H.scanSlots(holder, onlyLookingFor)
        if not H.acquire(holder or "scan", 6.0) then
            return false
        end
        for k = 1, 9 do
            local key = tostring(k)
            local known = S.hotbarSlots[key]
            if not known or onlyLookingFor then
                local before = readEquippedName()
                if not U.fireSkill(key) then U.tap(key, 0.05) end
                task.wait(0.35)
                local after = readEquippedName()
                if after and after ~= before then
                    S.hotbarSlots[key] = after
                    if onlyLookingFor then
                        local n = normalize(after)
                        local e = normalize(onlyLookingFor)
                        if n:find(e, 1, true) or e:find(n, 1, true) then
                            H.release(holder or "scan")
                            return true
                        end
                    end
                end
            end
        end
        S.hotbarSlotTs = U.clock()
        H.release(holder or "scan")
        return true
    end

    function H.dumpSlots()
        print("[Dingus][Hotbar] slot map:")
        local keys = {}
        for k in pairs(S.hotbarSlots) do table.insert(keys, k) end
        table.sort(keys, function(a, b)
            return (tonumber(a) or 0) < (tonumber(b) or 0)
        end)
        for _, k in ipairs(keys) do
            local item = S.hotbarSlots[k]
            local cat = H.classifyItem(item) or "?"
            print(string.format("  [%s] %-30s (%s)", k, item, cat))
        end
        if #keys == 0 then
            print("  (empty — call scanSlots())")
        end
    end

    --============================================================
    -- EQUIP
    --============================================================
    function H.equip(holder, itemName, wait)
        local key = H.slotOf(itemName)
        if not key then
            H.scanSlots(holder, itemName)
            key = H.slotOf(itemName)
        end
        if not key then return false, "not-slotted" end
        return H.tapVerified(holder, key, itemName, wait)
    end

    function H.equipFirstOf(holder, cat, wait)
        local slots = H.slotsOfCategory(cat)
        if #slots == 0 then
            H.scanSlots(holder)
            slots = H.slotsOfCategory(cat)
        end
        if #slots == 0 then return false, "no-" .. cat end
        -- Prefer highest key (later slots usually stronger in this game)
        table.sort(slots, function(a, b)
            return (tonumber(a.key) or 0) > (tonumber(b.key) or 0)
        end)
        return H.tapVerified(holder, slots[1].key, slots[1].item, wait)
    end

    -- Scans inventory (character + backpack), picks highest-tier weapon,
    -- equips it. Uses U.hum():EquipTool — doesn't touch the hotbar.
    function H.autoEquipBestWeapon(holder)
        local hum = U.hum()
        if not hum then return false, "no-hum" end
        local best, bestTier = nil, -1
        local sources = {}
        local c = U.Lp.Character
        if c then table.insert(sources, c) end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then table.insert(sources, bp) end
        for _, container in ipairs(sources) do
            for _, t in ipairs(container:GetChildren()) do
                if t:IsA("Tool") then
                    local cat = H.classifyItem(t.Name)
                    if cat == "weapon" then
                        local tier = weaponTier(t.Name)
                        if tier > bestTier then
                            best, bestTier = t, tier
                        end
                    end
                end
            end
        end
        if not best then return false, "no-weapon" end
        if best.Parent == c then return true, best.Name end
        if not H.acquire(holder or "auto-equip", 2.0) then
            return false, "busy"
        end
        pcall(function() hum:EquipTool(best) end)
        return true, best.Name
    end

    --============================================================
    -- STATE
    --============================================================
    function H.state()
        tick()
        local slots = 0
        for _ in pairs(S.hotbarSlots) do slots = slots + 1 end
        return {
            holder = S.hotbarHolder,
            remaining = math.max(0, S.hotbarExpiry - U.clock()),
            lastKey = S.hotbarLastKey,
            taps = S.hotbarTaps,
            denied = S.hotbarDenied,
            slotsCached = slots,
        }
    end

    --============================================================
    -- PERSISTENCE — learned slots saved on demand
    --============================================================
    function H.saveSlots()
        F.HotbarSlots = S.hotbarSlots
        if F.save then pcall(function() F.save("default") end) end
    end

    function H.clearSlots()
        S.hotbarSlots = {}
        F.HotbarSlots = {}
    end

    --============================================================
    -- AUTO-SCAN ON BOOT
    --============================================================
    task.spawn(function()
        task.wait(4)
        if next(S.hotbarSlots) == nil then
            print("[Dingus][Hotbar] initial slot scan")
            H.scanSlots("boot-scan")
            H.dumpSlots()
            H.saveSlots()
        else
            print(string.format("[Dingus][Hotbar] loaded %d cached slots",
                (function() local n = 0 for _ in pairs(S.hotbarSlots) do n = n + 1 end return n end)()))
        end
    end)

    --============================================================
    -- RESPAWN
    --============================================================
    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(1.5)
            H.forceRelease()
            -- Slots may change on respawn — invalidate cache
            H.clearSlots()
        end)
    end

    print(string.format("[Dingus][hotbar] v4 · %s · DB=%d items",
        U.Platform,
        (function() local n = 0 for _ in pairs(DB) do n = n + 1 end return n end)()))
end

return H
