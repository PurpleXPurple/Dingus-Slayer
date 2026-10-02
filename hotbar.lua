-- Dingus-Slayer · hotbar.lua v3
-- Cross-device: uses U.fireSkill when the key is a skill label.

local H = {}

function H.init(Ctx)
    local U = Ctx.Util
    local St = Ctx.St
    local Cfg = Ctx.Cfg

    St.hotbarHolder = nil
    St.hotbarExpiry = 0
    St.hotbarSlots = St.hotbarSlots or {}
    St.hotbarLastEquipName = nil
    St.hotbarLastEquipKey = nil

    local function normalize(n)
        if not n then return "" end
        return string.lower(n):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function readEquippedName()
        local c = U.Lp.Character
        if not c then return nil end
        for _, x in ipairs(c:GetChildren()) do
            if x:IsA("Tool") then return x.Name end
        end
        for _, hand in ipairs({"RightHand","LeftHand"}) do
            local h = c:FindFirstChild(hand)
            if h then
                for _, ch in ipairs(h:GetChildren()) do
                    if ch:IsA("BasePart") or ch:IsA("MeshPart") or ch:IsA("Model") then
                        return ch.Name
                    end
                end
            end
        end
        for _, attr in ipairs({"EquippedItem","CurrentItem","HeldItem"}) do
            local ok, v = pcall(function() return c:GetAttribute(attr) end)
            if ok and type(v) == "string" then return v end
        end
        return nil
    end

    local function tick()
        if St.hotbarHolder and U.clock() >= St.hotbarExpiry then
            St.hotbarHolder = nil
            St.hotbarExpiry = 0
        end
    end

    function H.acquire(holder, duration)
        tick()
        if St.hotbarHolder and St.hotbarHolder ~= holder then return false end
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
        end
        return true
    end

    function H.isLocked() tick(); return St.hotbarHolder end
    function H.forceRelease() St.hotbarHolder = nil; St.hotbarExpiry = 0 end

    function H.tap(holder, key, wait)
        if not H.acquire(holder, (wait or 0.4) + 0.2) then return false end
        local before = readEquippedName()
        -- Cross-device: try GUI button first (mobile), then key sim
        if not U.fireSkill(tostring(key)) then
            U.tap(tostring(key))
        end
        if wait then task.wait(wait) end
        local after = readEquippedName()
        if after and after ~= before then
            St.hotbarSlots[key] = after
            St.hotbarLastEquipName = after
            St.hotbarLastEquipKey = key
        end
        return true
    end

    function H.slotOf(itemName)
        if not itemName then return nil end
        local e = normalize(itemName)
        for k, v in pairs(St.hotbarSlots) do
            if v and normalize(v):find(e, 1, true) then return k end
        end
        return nil
    end

    function H.hasItem(itemName) return H.slotOf(itemName) ~= nil end

    function H.readCurrentSlot() return St.hotbarLastEquipKey end

    function H.equipFirstOf(holder, cat, wait)
        -- Category lookup requires the item DB; without it, return false
        return false, "no-db"
    end

    function H.state()
        tick()
        return {
            holder = St.hotbarHolder,
            remaining = math.max(0, St.hotbarExpiry - U.clock()),
            lastEquipName = St.hotbarLastEquipName,
            lastEquipKey = St.hotbarLastEquipKey,
            slotsCached = (function()
                local n = 0
                for _ in pairs(St.hotbarSlots) do n = n + 1 end
                return n
            end)(),
        }
    end

    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(1.5)
            H.forceRelease()
            St.hotbarSlots = {}
        end)
    end

    print(string.format("[Dingus][hotbar] v3 · %s · gui-buttons=%s",
        U.Platform, tostring(U.hasSkillButton("Z"))))
end

return H
