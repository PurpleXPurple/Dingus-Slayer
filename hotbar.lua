--[[
    Dingus-Slayer · hotbar.lua v2
    Mutex + item database + slot scanner + category lookup.

    Slayers 2 hotbar facts (2026-10):
      - 9 keys (1-9), HUD shows 5 (1-5)
      - Slot 1 = fists (default, always present)
      - Crow (Kasugai Crow) occupies a slot when equipped
      - Weapons, consumables, utility items all share the same hotbar
      - Loadout saving preserves the slot layout by item name

    Public:
      -- Mutex (v1 retained, unchanged)
      Hotbar.acquire(holder, duration) → bool
      Hotbar.release(holder)           → bool
      Hotbar.isLocked()                → holder or nil
      Hotbar.forceRelease()
      Hotbar.tap(holder, key, wait)    → bool
      Hotbar.state()                   → table

      -- Item intelligence (new)
      Hotbar.slotOf(itemName)          → key string or nil
      Hotbar.slotsOfCategory(cat)      → { {key, item}, ... }
      Hotbar.hasItem(itemName)         → bool
      Hotbar.scanSlots()               → { [key]=itemName }  (probe all 1-9)
      Hotbar.equip(holder, itemName)   → bool  (tap the key that has it)
      Hotbar.equipFirstOf(holder,cat)  → bool  (tap first matching category)
      Hotbar.readCurrentSlot()         → key string or nil
      Hotbar.classifyItem(name)        → category string or nil
      Hotbar.dumpSlots()               → prints cached mapping

    Detects current slot by:
      1. Watching the character for equipped mesh/Tool appearing
      2. Reading the hotbar UI selection highlight
      3. Falling back to a probe sweep (tap each key, see what appears)
]]--

local H = {}

function H.init(Ctx)
    local U = Ctx.Util
    local St = Ctx.St
    local Cfg = Ctx.Cfg

    --================================================================
    -- MUTEX STATE (from v1)
    --================================================================
    St.hotbarHolder = nil
    St.hotbarExpiry = 0
    St.hotbarLastKey = nil
    St.hotbarTaps = 0
    St.hotbarDenied = 0

    --================================================================
    -- SLOT CACHE
    --================================================================
    St.hotbarSlots = St.hotbarSlots or {}      -- [key] = itemName
    St.hotbarSlotTs = 0                        -- last full scan time
    St.hotbarLastEquipName = nil               -- last verified equip
    St.hotbarLastEquipKey = nil
    St.hotbarLastEquipTs = 0

    --================================================================
    -- ITEM DATABASE
    --================================================================
    -- Full item registry from Slayers 2 (2026-10). Each entry: name,
    -- category. Categories used by Hotbar.classifyItem().
    --
    -- Categories:
    --   weapon   — combat tools (katanas, scythes, claws, etc.)
    --   crow     — Kasugai Crow quest item
    --   potion   — health/stamina/breathe consumables
    --   gourd    — breathing-progress gourds
    --   utility  — misc (lanterns, maps, tools)
    --   accessory — equippables (haori, masks, etc.) — NOT hotbar
    --   other    — anything else

    local ITEM_DB = {
        --========================================================
        -- WEAPONS — Katanas
        --========================================================
        ["regular katana"]        = "weapon",
        ["fancy katana"]          = "weapon",
        ["green katana"]          = "weapon",
        ["cutlass"]               = "weapon",
        ["water katana"]          = "weapon",
        ["flame katana"]          = "weapon",
        ["wind katana"]           = "weapon",
        ["thunder katana"]        = "weapon",
        ["stone katana"]          = "weapon",
        ["mist katana"]           = "weapon",
        ["insect katana"]         = "weapon",
        ["serpent katana"]        = "weapon",
        ["sound katana"]          = "weapon",
        ["sound katanas"]         = "weapon",
        ["beast katanas"]         = "weapon",
        ["ocean wave katana"]     = "weapon",
        ["waterfall katana"]      = "weapon",
        ["cloud katana"]          = "weapon",
        ["butterfly katana"]      = "weapon",
        ["champion katana"]       = "weapon",
        ["thundercloud katana"]   = "weapon",
        ["devourer katana"]       = "weapon",

        -- V2 forged
        ["volcanic katana"]       = "weapon",
        ["tornadic katana"]       = "weapon",
        ["serpentine katana"]     = "weapon",

        -- Hidden Mist forge
        ["enryu katana"]          = "weapon",
        ["shinkage katana"]       = "weapon",
        ["tengoku katana"]        = "weapon",

        --========================================================
        -- WEAPONS — Nightfall set
        --========================================================
        ["nightfall katana"]         = "weapon",
        ["nightfall serpent katana"] = "weapon",
        ["nightfall scythe"]         = "weapon",
        ["nightfall sickles"]        = "weapon",
        ["nightfall claws"]          = "weapon",
        ["nightfall gauntlets"]      = "weapon",
        ["nightfall axe and mace"]   = "weapon",

        --========================================================
        -- WEAPONS — Firstlight set
        --========================================================
        ["firstlight katana"]         = "weapon",
        ["firstlight tanto"]          = "weapon",
        ["firstlight spear"]          = "weapon",
        ["firstlight war fans"]       = "weapon",
        ["firstlight bladed wagasa"]  = "weapon",
        ["firstlight sound cleavers"] = "weapon",
        ["firstlight insect katana"]  = "weapon",

        --========================================================
        -- WEAPONS — Polar set
        --========================================================
        ["polar katana"]  = "weapon",
        ["polar scythe"]  = "weapon",
        ["polar fans"]    = "weapon",
        ["polar mask"]    = "accessory",

        --========================================================
        -- WEAPONS — Devourer set
        --========================================================
        ["devourer scythe"] = "weapon",
        ["devourer fans"]   = "weapon",
        ["devourer claws"]  = "weapon",

        --========================================================
        -- WEAPONS — Mugen Train / demon-only
        --========================================================
        ["metal scythe"]  = "weapon",
        ["skull scythe"]  = "weapon",
        ["bone claws"]    = "weapon",
        ["blood sickles"] = "weapon",
        ["war fans"]      = "weapon",

        --========================================================
        -- WEAPONS — standalones
        --========================================================
        ["spear"]        = "weapon",
        ["tanto"]        = "weapon",
        ["gauntlet"]     = "weapon",
        ["gauntlets"]    = "weapon",
        ["axe and mace"] = "weapon",
        ["shotgun"]      = "weapon",
        ["lost shotgun"] = "weapon",
        ["bladed wagasa"] = "weapon",
        ["scythe"]       = "weapon",
        ["sickles"]      = "weapon",
        ["claws"]        = "weapon",
        ["cleaver"]      = "weapon",
        ["katana"]       = "weapon",
        ["sword"]        = "weapon",

        --========================================================
        -- CROW / QUEST ITEMS
        --========================================================
        ["kasugai crow"]    = "crow",
        ["kasugai"]         = "crow",
        ["crow"]            = "crow",
        ["the crow"]        = "crow",

        --========================================================
        -- POTIONS / ELIXIRS
        --========================================================
        ["health potion"]             = "potion",
        ["health regen potion"]       = "potion",
        ["health elixir"]             = "potion",
        ["health regen elixir"]       = "potion",
        ["stamina potion"]            = "potion",
        ["stamina regen potion"]      = "potion",
        ["stamina regen elixir"]      = "potion",
        ["underwater breathing potion"] = "potion",
        ["muzan's blood"]             = "potion",

        --========================================================
        -- GOURDS (breathing progression)
        --========================================================
        ["small gourd"]  = "gourd",
        ["medium gourd"] = "gourd",
        ["large gourd"]  = "gourd",
        ["clay gourd"]   = "gourd",
        ["focus gourd"]  = "gourd",
        ["rage gourd"]   = "gourd",

        --========================================================
        -- UTILITY
        --========================================================
        ["lantern"]             = "utility",
        ["demonic lantern"]     = "utility",
        ["nichirin lantern"]    = "utility",
        ["frozen heart lantern"] = "utility",
        ["ember heart lantern"]  = "utility",
        ["everburn lantern"]     = "utility",
        ["horse"]                = "utility",
        ["fishing rod"]          = "utility",
        ["shovel"]               = "utility",
        ["permit"]               = "utility",
        ["key"]                  = "utility",
        ["serpent key"]          = "utility",

        --========================================================
        -- ACCESSORIES (informational — not hotbar-slotted)
        --========================================================
        ["red oni mask"]         = "accessory",
        ["bamboo muzzle"]        = "accessory",
        ["stone haori"]          = "accessory",
        ["reaper's outfit"]      = "accessory",
        ["kintsugi haori"]       = "accessory",
        ["black dragon armour"]  = "accessory",
        ["black lotus crown"]    = "accessory",
        ["golden kanzashi"]      = "accessory",
        ["stylish haori"]        = "accessory",
        ["stylish mask"]         = "accessory",
        ["fox mask"]             = "accessory",
        ["straw hat"]            = "accessory",
        ["demonic horns"]        = "accessory",
        ["demonic horns ii"]     = "accessory",
        ["sabito's mask"]        = "accessory",
        ["nezuko's bamboo pacifier"] = "accessory",
        ["riyaku's necklace"]    = "accessory",
        ["scare dwarding mask"]  = "accessory",
    }

    --================================================================
    -- CLASSIFY
    --================================================================
    local function normalize(name)
        if not name then return "" end
        return string.lower(name):gsub("^%s+", ""):gsub("%s+$", "")
    end

    function H.classifyItem(name)
        local n = normalize(name)
        if #n == 0 then return nil end
        if ITEM_DB[n] then return ITEM_DB[n] end
        -- Fallback substring matching
        for key, cat in pairs(ITEM_DB) do
            if n:find(key, 1, true) or key:find(n, 1, true) then
                return cat
            end
        end
        -- Heuristic
        if n:find("katana", 1, true) or n:find("sword", 1, true)
           or n:find("scythe", 1, true) or n:find("claw", 1, true)
           or n:find("sickle", 1, true) or n:find("spear", 1, true)
           or n:find("tanto", 1, true) or n:find("fans", 1, true)
           or n:find("gauntlet", 1, true) then
            return "weapon"
        end
        if n:find("potion", 1, true) or n:find("elixir", 1, true) then
            return "potion"
        end
        if n:find("gourd", 1, true) then return "gourd" end
        if n:find("crow", 1, true) or n:find("kasugai", 1, true) then
            return "crow"
        end
        return nil
    end

    --================================================================
    -- MUTEX (v1)
    --================================================================
    local function tick()
        if St.hotbarHolder and U.clock() >= St.hotbarExpiry then
            St.hotbarHolder = nil
            St.hotbarExpiry = 0
        end
    end

    function H.acquire(holder, duration)
        tick()
        if St.hotbarHolder and St.hotbarHolder ~= holder then
            St.hotbarDenied = St.hotbarDenied + 1
            return false
        end
        St.hotbarHolder = holder
        St.hotbarExpiry = U.clock() + (duration or 1.0)
        return true
    end

    function H.release(holder)
        tick()
        if not St.hotbarHolder then return true end
        if St.hotbarHolder == holder then
            St.hotbarHolder = nil
            St.hotbarExpiry = 0
            return true
        end
        return false
    end

    function H.isLocked()
        tick()
        return St.hotbarHolder
    end

    function H.forceRelease()
        St.hotbarHolder = nil
        St.hotbarExpiry = 0
    end

    --================================================================
    -- EQUIPPED-ITEM READER
    --================================================================
    -- Reads whatever item the character currently has in hand, trying
    -- every known representation: Roblox Tool, hand mesh, character
    -- attribute.
    local function readEquippedName()
        local plr = U.Lp
        local char = plr.Character
        if not char then return nil end

        -- Roblox Tool
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Tool") then return c.Name end
        end

        -- Hand mesh: crow lives here after equip, weapons too
        for _, handName in ipairs({"RightHand", "LeftHand"}) do
            local hand = char:FindFirstChild(handName)
            if hand then
                for _, child in ipairs(hand:GetChildren()) do
                    if child:IsA("BasePart")
                       or child:IsA("MeshPart")
                       or child:IsA("Model") then
                        return child.Name
                    end
                end
            end
        end

        -- Character attribute (some builds use this)
        for _, attr in ipairs({"EquippedItem", "CurrentItem", "HeldItem"}) do
            local ok, v = pcall(function() return char:GetAttribute(attr) end)
            if ok and type(v) == "string" then return v end
        end

        return nil
    end

    --================================================================
    -- TAP + VERIFY
    --================================================================
    -- Blind tap (v1). Fires a key without verification.
    function H.tap(holder, key, wait)
        if not H.acquire(holder, (wait or 0.4) + 0.2) then
            return false
        end
        local before = readEquippedName()
        pcall(function() U.tap(tostring(key)) end)
        St.hotbarLastKey = key
        St.hotbarTaps = St.hotbarTaps + 1
        if wait and wait > 0 then task.wait(wait) end
        local after = readEquippedName()
        if after and after ~= before then
            St.hotbarSlots[key] = after
            St.hotbarLastEquipName = after
            St.hotbarLastEquipKey = key
            St.hotbarLastEquipTs = U.clock()
        end
        return true
    end

    -- Verified tap: fires key, waits, confirms intended item equipped.
    function H.tapVerified(holder, key, expectedName, wait)
        if not H.acquire(holder, (wait or 0.5) + 0.3) then
            return false, "mutex-busy"
        end
        pcall(function() U.tap(tostring(key)) end)
        St.hotbarLastKey = key
        St.hotbarTaps = St.hotbarTaps + 1
        task.wait(wait or 0.5)

        local equipped = readEquippedName()
        if not equipped then
            return false, "no-equip"
        end

        St.hotbarSlots[key] = equipped

        if not expectedName then
            return true, equipped
        end

        local n = normalize(equipped)
        local e = normalize(expectedName)
        if n == e or n:find(e, 1, true) or e:find(n, 1, true) then
            St.hotbarLastEquipName = equipped
            St.hotbarLastEquipKey = key
            St.hotbarLastEquipTs = U.clock()
            return true, equipped
        end
        return false, "wrong-item:" .. equipped
    end

    --================================================================
    -- SLOT LOOKUP
    --================================================================
    function H.slotOf(itemName)
        if not itemName then return nil end
        local e = normalize(itemName)
        for key, cached in pairs(St.hotbarSlots) do
            if cached and normalize(cached):find(e, 1, true) then
                return key
            end
        end
        return nil
    end

    function H.hasItem(itemName)
        return H.slotOf(itemName) ~= nil
    end

    function H.slotsOfCategory(cat)
        local out = {}
        for key, cached in pairs(St.hotbarSlots) do
            if cached and H.classifyItem(cached) == cat then
                table.insert(out, { key = key, item = cached })
            end
        end
        return out
    end

    function H.readCurrentSlot()
        return St.hotbarLastEquipKey
    end

    --================================================================
    -- EQUIP HELPERS
    --================================================================
    function H.equip(holder, itemName, wait)
        local key = H.slotOf(itemName)
        if not key then
            -- Unknown slot: probe all keys to find it
            H.scanSlots(holder, itemName)
            key = H.slotOf(itemName)
        end
        if not key then return false, "not-slotted" end
        return H.tapVerified(holder, key, itemName, wait)
    end

    function H.equipFirstOf(holder, cat, wait)
        local slots = H.slotsOfCategory(cat)
        if #slots == 0 then
            -- Refresh cache first
            H.scanSlots(holder)
            slots = H.slotsOfCategory(cat)
        end
        if #slots == 0 then return false, "no-" .. cat end
        -- Prefer highest key (later slots usually better in-game)
        table.sort(slots, function(a, b)
            return tonumber(a.key) > tonumber(b.key)
        end)
        return H.tapVerified(holder, slots[1].key, slots[1].item, wait)
    end

    --================================================================
    -- SLOT SCANNER
    --================================================================
    -- Probes keys 1-9, notes what appears. Populates St.hotbarSlots.
    -- Only scans keys that are unknown OR when forceRescan is set.
    function H.scanSlots(holder, onlyLookingFor)
        if not H.acquire(holder or "scan", 5.0) then
            return false
        end

        for k = 1, 9 do
            local key = tostring(k)
            local known = St.hotbarSlots[key]
            if not known or onlyLookingFor then
                local before = readEquippedName()
                pcall(function() U.tap(key) end)
                task.wait(0.35)
                local after = readEquippedName()
                if after and after ~= before then
                    St.hotbarSlots[key] = after
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

        St.hotbarSlotTs = U.clock()
        H.release(holder or "scan")
        return true
    end

    function H.dumpSlots()
        print("[Dingus][Hotbar] slot map (age " ..
            string.format("%.1fs", U.clock() - St.hotbarSlotTs) .. "):")
        local keys = {}
        for k in pairs(St.hotbarSlots) do table.insert(keys, k) end
        table.sort(keys, function(a, b)
            return (tonumber(a) or 0) < (tonumber(b) or 0)
        end)
        for _, k in ipairs(keys) do
            local item = St.hotbarSlots[k]
            local cat = H.classifyItem(item) or "?"
            print(string.format("  [%s] %-30s (%s)", k, item, cat))
        end
        if #keys == 0 then
            print("  (empty — call scanSlots())")
        end
    end

    --================================================================
    -- STATE
    --================================================================
    function H.state()
        tick()
        return {
            holder = St.hotbarHolder,
            remaining = math.max(0, St.hotbarExpiry - U.clock()),
            lastKey = St.hotbarLastKey,
            lastEquipName = St.hotbarLastEquipName,
            lastEquipKey = St.hotbarLastEquipKey,
            taps = St.hotbarTaps,
            denied = St.hotbarDenied,
            slotsCached = (function()
                local n = 0
                for _ in pairs(St.hotbarSlots) do n = n + 1 end
                return n
            end)(),
        }
    end

    --================================================================
    -- AUTO-SCAN ON BOOT
    --================================================================
    task.spawn(function()
        task.wait(4)
        if St.hotbarSlotTs == 0 then
            print("[Dingus][Hotbar] initial slot scan")
            H.scanSlots("boot-scan")
            H.dumpSlots()
        end
    end)

    --================================================================
    -- RESPAWN
    --================================================================
    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(1.5)
            H.forceRelease()
            -- Slots may change on respawn. Invalidate.
            St.hotbarSlots = {}
            St.hotbarSlotTs = 0
        end)
    end

    print("[Dingus][hotbar] v2 initialized · item DB loaded")
end

return H
