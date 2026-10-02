-- Dingus-Slayer · faction.lua v1
-- Auto-detects player role (Slayer / Demon / Hybrid / Hashira) and exposes
-- a name-based faction classifier for target filtering.

local Fac = {}

function Fac.init(Ctx)
    local U, F, S, L = Ctx.Util, Ctx.Cfg, Ctx.St, Ctx.Lists

    --============================================================
    -- CONFIG DEFAULTS
    --============================================================
    F.FactionAuto        = F.FactionAuto ~= false     -- auto-detect on
    F.FactionManual      = F.FactionManual or "auto"  -- auto | slayer | demon | hybrid | none
    F.FactionIncludeNeutral = F.FactionIncludeNeutral ~= false
    F.FactionPriorityUpper  = F.FactionPriorityUpper ~= false  -- prefer Upper Moons
    F.FactionDetectInterval = F.FactionDetectInterval or 8.0
    F.FactionHashiraBoost   = F.FactionHashiraBoost ~= false

    --============================================================
    -- STATE
    --============================================================
    S.faction             = S.faction or "unknown"     -- slayer | demon | hybrid | unknown
    S.factionRank         = S.factionRank or "unknown"
    S.isHashira           = S.isHashira or false
    S.factionLastDetect   = 0
    S.factionDetectCount  = 0
    S.factionDetectErrors = 0

    local Utility, RS
    RS = U.RS
    pcall(function()
        local cam = RS:FindFirstChild("CAM")
        local glob = cam and cam:FindFirstChild("Global")
        Utility = glob and glob:FindFirstChild("Utility")
        if Utility then
            local ok, mod = pcall(require, Utility)
            if ok then Utility = mod else Utility = nil end
        end
    end)

    --============================================================
    -- DATA HELPERS
    --============================================================
    local function getData()
        if not Utility or not Utility.GetData then return nil, nil end
        local ok, d1, d2 = pcall(Utility.GetData, U.Lp, true)
        if not ok then return nil, nil end
        return d1, d2
    end

    --============================================================
    -- RACE DETECTION
    --============================================================
    local function detectRace()
        local d1, d2 = getData()
        local function val(d)
            if not d then return nil end
            local r = d:FindFirstChild("Race")
            return r and r.Value ~= "" and tostring(r.Value) or nil
        end
        local r1, r2 = val(d1), val(d2)
        local race = (r1 or r2 or "Slayer"):lower()
        if race == "demon" then return "demon" end
        if race == "hybrid" then return "hybrid" end
        return "slayer"
    end

    --============================================================
    -- RANK DETECTION (Hashira check)
    --============================================================
    -- Hashira is a Slayer-only rank. We look in multiple places because
    -- PS2 changes paths between patches.
    local HASHIRA_KEYWORDS = { "hashira", "pillar", "hashira rank", "shinazugawa", "rengoku rank" }

    local function hasHashiraKeyword(s)
        if not s then return false end
        local l = string.lower(tostring(s))
        for _, k in ipairs(HASHIRA_KEYWORDS) do
            if l:find(k, 1, true) then return true end
        end
        return false
    end

    local function detectRank()
        local d1, d2 = getData()
        local sources = { d1, d2 }

        -- 1. Slot.Ranks / Slot.Rank
        for _, d in ipairs(sources) do
            if d then
                local ranks = d:FindFirstChild("Ranks")
                    or d:FindFirstChild("Rank")
                if ranks then
                    if typeof(ranks) == "Instance" and ranks.Value then
                        if hasHashiraKeyword(ranks.Value) then return "hashira" end
                    end
                    if typeof(ranks) == "Instance" and ranks.GetChildren then
                        for _, r in ipairs(ranks:GetChildren()) do
                            if hasHashiraKeyword(r.Name)
                               or (r.Value and hasHashiraKeyword(r.Value)) then
                                return "hashira"
                            end
                        end
                    end
                end
            end
        end

        -- 2. Player_Service.Values.<name>.Rank
        local ps = RS:FindFirstChild("Player_Service")
        local vals = ps and ps:FindFirstChild("Values")
        local me = vals and vals:FindFirstChild(U.Lp.Name)
        if me then
            local r = me:FindFirstChild("Rank")
                or me:FindFirstChild("PlayerRank")
            if r and r.Value and hasHashiraKeyword(r.Value) then
                return "hashira"
            end
        end

        -- 3. Character attribute
        local char = U.Lp.Character
        if char then
            local ok, r = pcall(function() return char:GetAttribute("Rank") end)
            if ok and hasHashiraKeyword(r) then return "hashira" end
        end

        -- 4. Inventory tool check (some builds give a "Hashira" badge tool)
        for _, container in ipairs({ char, U.Lp:FindFirstChildOfClass("Backpack") }) do
            if container then
                for _, t in ipairs(container:GetChildren()) do
                    if t:IsA("Tool") and hasHashiraKeyword(t.Name) then
                        return "hashira"
                    end
                end
            end
        end

        -- 5. Attribute on player
        local ok2, r2 = pcall(function() return U.Lp:GetAttribute("Rank") end)
        if ok2 and hasHashiraKeyword(r2) then return "hashira" end
        local ok3, r3 = pcall(function() return U.Lp:GetAttribute("IsHashira") end)
        if ok3 and r3 == true then return "hashira" end

        return "unknown"
    end

    --============================================================
    -- DETECT (single pass)
    --============================================================
    local function detect()
        S.factionDetectCount = S.factionDetectCount + 1
        local ok, err = pcall(function()
            S.faction = detectRace()
            local rank = detectRank()
            S.factionRank = rank
            S.isHashira = (rank == "hashira")
            S.factionLastDetect = U.clock()
        end)
        if not ok then
            S.factionDetectErrors = S.factionDetectErrors + 1
            if S.factionDetectErrors == 1 then
                warn("[Dingus][Faction] detect error: " .. tostring(err))
            end
        end
    end

    --============================================================
    -- NPC FACTION CLASSIFIER
    --============================================================
    local function nameFaction(name)
        if not name then return "neutral" end
        return L.factionOf(name)
    end

    --============================================================
    -- TARGET FILTER API
    --============================================================
    -- Returns the set of NPC factions the player should attack.
    -- {"demon"} for Slayer/Hashira, {"slayer"} for Demon, both for Hybrid.
    function Fac.getTargetFactions()
        local manual = F.FactionManual
        if manual and manual ~= "auto" then
            if manual == "slayer" then return { "demon" } end
            if manual == "demon"  then return { "slayer" } end
            if manual == "hybrid" then
                return F.FactionIncludeNeutral
                    and { "demon", "slayer", "neutral" }
                    or  { "demon", "slayer" }
            end
            if manual == "none"   then return nil end
        end
        if not F.FactionAuto then return nil end
        local f = S.faction
        if f == "slayer" then return { "demon" } end
        if f == "demon"  then return { "slayer" } end
        if f == "hybrid" then
            return F.FactionIncludeNeutral
                and { "demon", "slayer", "neutral" }
                or  { "demon", "slayer" }
        end
        return nil
    end

    function Fac.isAutoEnabled()
        return F.FactionAuto and (F.FactionManual == "auto" or not F.FactionManual)
    end

    -- Returns true if attack.lua should target this mob.
    function Fac.shouldTarget(mobName)
        local targets = Fac.getTargetFactions()
        if not targets then return true end  -- no filter active
        local npcFac = nameFaction(mobName)
        for _, t in ipairs(targets) do
            if npcFac == t then return true end
        end
        -- Neutral always allowed if flag set
        if npcFac == "neutral" and F.FactionIncludeNeutral then return true end
        return false
    end

    -- Priority boost for specific NPCs (used by attack.pickTarget)
    function Fac.priorityWeight(mobName)
        if not mobName then return 0 end
        local n = string.lower(mobName)
        -- Hashira players get a boost on Upper Moons
        if S.isHashira and F.FactionHashiraBoost then
            if n:find("akaza") or n:find("douma") or n:find("muzan") then
                return 50
            end
        end
        -- Demon players get a boost on Hashiras
        if S.faction == "demon" then
            if n:find("sanemi") or n:find("giyu") or n:find("rengoku")
               or n:find("tengen") or n:find("hashira") then
                return 50
            end
        end
        return 0
    end

    --============================================================
    -- PUBLIC
    --============================================================
    function Fac.detect() detect(); return S.faction, S.factionRank end
    function Fac.get() return S.faction end
    function Fac.getRank() return S.factionRank end
    function Fac.isHashiraPlayer() return S.isHashira end

    function Fac.setAuto(v)
        F.FactionAuto = not not v
        print("[Dingus][Faction] auto = " .. tostring(F.FactionAuto))
    end

    function Fac.setManual(v)
        F.FactionManual = v or "auto"
        print("[Dingus][Faction] manual = " .. tostring(F.FactionManual))
    end

    function Fac.setIncludeNeutral(v)
        F.FactionIncludeNeutral = not not v
    end

    -- Live enemy list matching current filter
    function Fac.getEnemyList()
        if not Ctx.Scan or not Ctx.Scan.humanoids then return {} end
        local list = Ctx.Scan.humanoids(500)
        local out = {}
        for _, m in ipairs(list) do
            if Fac.shouldTarget(m.inst.Name) then
                table.insert(out, {
                    name = m.inst.Name,
                    faction = nameFaction(m.inst.Name),
                    dist = m.dist,
                    health = m.health,
                    maxHealth = m.maxHealth,
                    inst = m.inst,
                })
            end
        end
        table.sort(out, function(a, b) return a.dist < b.dist end)
        return out
    end

    function Fac.stats()
        return {
            faction = S.faction,
            rank = S.factionRank,
            isHashira = S.isHashira,
            auto = F.FactionAuto,
            manual = F.FactionManual,
            includeNeutral = F.FactionIncludeNeutral,
            detectCount = S.factionDetectCount,
            detectErrors = S.factionDetectErrors,
            lastDetectAge = U.clock() - (S.factionLastDetect or 0),
            targets = Fac.getTargetFactions(),
        }
    end

    --============================================================
    -- DETECT LOOP
    --============================================================
    task.spawn(function()
        while S.run do
            if F.FactionAuto then
                local now = U.clock()
                if now - S.factionLastDetect >= (F.FactionDetectInterval or 8.0) then
                    detect()
                end
            end
            task.wait(2)
        end
    end)

    -- Initial detection
    task.spawn(function()
        task.wait(2)
        detect()
        print(string.format(
            "[Dingus][Faction] detected: race=%s rank=%s hashira=%s",
            S.faction, S.factionRank, tostring(S.isHashira)))
    end)

    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(2)
            -- Force re-detect on respawn
            S.factionLastDetect = 0
        end)
    end

    print(string.format("[Dingus][faction] v1 · %s · auto=%s",
        U.Platform, tostring(F.FactionAuto)))
end

return Fac
