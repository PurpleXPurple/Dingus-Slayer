--[[
    Dingus-Slayer · quests.lua v1
    Centralized quest logic. Reads game state, exposes quest routing.

    Paths discovered from recon (2026-10-02):
      ReplicatedStorage.BossHunts              — configs 3-10+
      ReplicatedStorage.Assets.Quests          — quest item templates
      ReplicatedStorage.Assets.Chests          — chest templates
      Players.<me>.PlayerGui.ComponentsHolder  — HUD (crow panel appears on demand)

    Remote handling:
      Xeno blocks hookmetamethod. We can't spy.
      Fallback: probe common remote paths on init, expose the first
      one that exists. If none, quest acceptance must be manual.

    Integration:
      attack.lua reads Q.isPriority(bossName) to focus the target list.
      main.lua calls Q.cycle() from a dedicated scheduler loop.
      gui.lua can display Q.stats() in the Quests tab.
]]--

local Q = {}

function Q.init(Ctx)
    local U     = Ctx.Util
    local Cfg   = Ctx.Cfg
    local St    = Ctx.St
    local Lists = Ctx.Lists

    --============================================================
    -- CONFIG
    --============================================================
    Cfg.QuestAutoAccept       = Cfg.QuestAutoAccept ~= false
    Cfg.QuestPriority         = Cfg.QuestPriority or "xp"      -- "xp" | "wen" | "time"
    Cfg.QuestCycleT           = Cfg.QuestCycleT or 5.0
    Cfg.QuestMaxActive        = Cfg.QuestMaxActive or 5
    Cfg.QuestMinDuration      = Cfg.QuestMinDuration or 60      -- skip quests expiring in <60s
    Cfg.QuestRemotePath       = Cfg.QuestRemotePath or ""       -- explicit override
    Cfg.QuestLogStructure     = Cfg.QuestLogStructure ~= false  -- one-time log

    --============================================================
    -- STATE
    --============================================================
    St.questHunts          = {}
    St.questAvailable      = {}
    St.questActive         = {}
    St.questPriorityBoss   = nil
    St.questCycleCount     = 0
    St.questLastCycle      = 0
    St.questRemote         = nil
    St.questRemoteName     = "?"
    St.questStructureLogged = false
    St.questTemplates      = {}
    St.chestTemplates      = {}
    St.questMinuteCooldown = 0

    --============================================================
    -- FOLDER RESOLUTION (lazy, cached)
    --============================================================
    local rs = game:GetService("ReplicatedStorage")
    local folders = {
        bossHunts = nil,
        assets    = nil,
        quests    = nil,
        chests    = nil,
    }

    local function resolveFolders()
        if not folders.bossHunts then
            folders.bossHunts = rs:FindFirstChild("BossHunts")
        end
        if not folders.assets then
            folders.assets = rs:FindFirstChild("Assets")
        end
        if folders.assets and not folders.quests then
            folders.quests = folders.assets:FindFirstChild("Quests")
        end
        if folders.assets and not folders.chests then
            folders.chests = folders.assets:FindFirstChild("Chests")
        end
    end

    --============================================================
    -- PLAYER LEVEL
    --============================================================
    function Q.readLevel()
        local ok, result = pcall(function()
            -- Path 1: workspace.Humanoids.<me>.Progression.Level
            local hf = workspace:FindFirstChild("Humanoids")
            local me = hf and hf:FindFirstChild(U.Lp.Name)
            if me then
                local prog = me:FindFirstChild("Progression")
                local lvl = prog and prog:FindFirstChild("Level")
                if lvl and (lvl:IsA("NumberValue") or lvl:IsA("IntValue")) then
                    return lvl.Value
                end
            end
            -- Path 2: ReplicatedStorage.Player_Service.Data.<me>.slots.SlotN.Progression.Level
            local ps = rs:FindFirstChild("Player_Service")
            local data = ps and ps:FindFirstChild("Data")
            local me2 = data and data:FindFirstChild(U.Lp.Name)
            local slots = me2 and me2:FindFirstChild("slots")
            if slots then
                for _, slot in ipairs(slots:GetChildren()) do
                    local prog = slot:FindFirstChild("Progression")
                    local lvl = prog and prog:FindFirstChild("Level")
                    if lvl and (lvl:IsA("NumberValue") or lvl:IsA("IntValue")) then
                        return lvl.Value
                    end
                end
            end
            return 0
        end)
        return ok and result or 0
    end

    --============================================================
    -- BOSS HUNTS READER
    -- Walks ReplicatedStorage.BossHunts. On first pass, logs the
    -- full structure of one config so we can see field names.
    --============================================================
    local function describeConfig(cfg)
        local fields = {}
        for _, child in ipairs(cfg:GetChildren()) do
            local ok, v = pcall(function() return child.Value end)
            if ok then
                table.insert(fields, string.format("%s=%s", child.Name, tostring(v)))
            else
                table.insert(fields, string.format("%s<%s>", child.Name, child.ClassName))
            end
        end
        return table.concat(fields, " ")
    end

    function Q.readHunts()
        resolveFolders()
        if not folders.bossHunts then
            return {}
        end

        local out = {}
        local firstStructure = nil
        for _, cfg in ipairs(folders.bossHunts:GetChildren()) do
            if cfg:IsA("Configuration") then
                local entry = {
                    id = tonumber(cfg.Name) or cfg.Name,
                    name = cfg.Name,
                    fields = {},
                    raw = cfg,
                }
                for _, child in ipairs(cfg:GetChildren()) do
                    local ok, v = pcall(function() return child.Value end)
                    entry.fields[child.Name] = ok and v or child.ClassName
                end
                -- Try common field names for boss + xp + wen + duration
                entry.boss = entry.fields.Boss
                    or entry.fields.BossName
                    or entry.fields.Target
                    or entry.fields.Name
                entry.xp = tonumber(entry.fields.XP
                    or entry.fields.Experience
                    or entry.fields.Reward)
                entry.wen = tonumber(entry.fields.Wen
                    or entry.fields.Money
                    or entry.fields.Currency)
                entry.side = tonumber(entry.fields.Side)
                    or entry.fields.Side

                if not firstStructure then
                    firstStructure = describeConfig(cfg)
                end
                table.insert(out, entry)
            end
        end

        table.sort(out, function(a, b)
            return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
        end)

        if Cfg.QuestLogStructure and not St.questStructureLogged and firstStructure then
            St.questStructureLogged = true
            print("[Dingus][Quest] BossHunts config structure: " .. firstStructure)
            print(string.format("[Dingus][Quest] parsed %d hunts (ids: %s)",
                #out, table.concat((function()
                    local ids = {}
                    for _, h in ipairs(out) do table.insert(ids, tostring(h.id)) end
                    return ids
                end)(), ", ")))
        end

        return out
    end

    --============================================================
    -- TEMPLATE READERS
    --============================================================
    function Q.readQuestTemplates()
        resolveFolders()
        if not folders.quests then return {} end
        local out = {}
        for _, child in ipairs(folders.quests:GetChildren()) do
            table.insert(out, {
                name = child.Name,
                class = child.ClassName,
                inst = child,
            })
        end
        return out
    end

    function Q.readChestTemplates()
        resolveFolders()
        if not folders.chests then return {} end
        local out = {}
        for _, child in ipairs(folders.chests:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then
                table.insert(out, {
                    name = child.Name,
                    class = child.ClassName,
                    inst = child,
                })
            end
        end
        return out
    end

    --============================================================
    -- CROW MENU ACTIVE QUESTS
    -- Reads the currently open crow menu if visible. Returns a
    -- list of { boss, xp, wen, timeLeft, element }.
    --============================================================
    local function parseTimeLeft(s)
        -- Accepts "15:38" or "6:07" or "1:23:45"
        if type(s) ~= "string" then return nil end
        local parts = {}
        for p in s:gmatch("%d+") do table.insert(parts, tonumber(p)) end
        if #parts == 2 then
            return parts[1] * 60 + parts[2]
        elseif #parts == 3 then
            return parts[1] * 3600 + parts[2] * 60 + parts[3]
        end
        return nil
    end

    function Q.readActiveQuests()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return {} end
        local cc = pg:FindFirstChild("ComponentsHolder")
        if not cc then return {} end

        local quests = {}
        local stack = { cc }
        local iter = 0
        while #stack > 0 do
            local inst = table.remove(stack)
            if inst then
                if inst:IsA("TextLabel") then
                    local okT, txt = pcall(function() return inst.Text end)
                    if okT and type(txt) == "string" then
                        local bossName = txt:match("^%s*Defeat%s+(.+)$")
                            or txt:match("^%s*Eliminate%s+(.+)$")
                        if bossName then
                            bossName = bossName:gsub("%s+$", ""):gsub("^%s+", "")
                            -- Walk up to find the container for this quest
                            local container = inst.Parent
                            local xp, wen, timeLeft
                            for _ = 1, 4 do
                                if not container then break end
                                -- Search siblings for XP, Wen, time
                                for _, sib in ipairs(container:GetChildren()) do
                                    if sib ~= inst and sib:IsA("TextLabel") then
                                        local s = sib.Text
                                        if s:find("^%d+:%d+") or s:find("^%d+:%d+:%d+") then
                                            timeLeft = parseTimeLeft(s)
                                        end
                                    end
                                end
                                container = container.Parent
                            end
                            table.insert(quests, {
                                boss = bossName,
                                timeLeft = timeLeft,
                                element = inst,
                            })
                        end
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do
                    table.insert(stack, k)
                end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        return quests
    end

    --============================================================
    -- AVAILABLE QUESTS (level-filtered)
    --============================================================
    function Q.availableQuests()
        local level = Q.readLevel()
        local hunts = Q.readHunts()
        local out = {}
        for _, h in ipairs(hunts) do
            if not h.boss then
                -- fall through to include entries without a boss field
            end
            -- Level requirement: id <= floor(level/20) is the observed pattern
            local req = tonumber(h.id) or 0
            local levelGate = math.max(1, math.floor(level / 20))
            if req <= levelGate or req == 0 then
                table.insert(out, h)
            end
        end
        return out
    end

    --============================================================
    -- RANKING
    --============================================================
    function Q.rankQuests(quests, by)
        by = by or Cfg.QuestPriority or "xp"
        local filtered = {}
        for _, q in ipairs(quests) do
            local ok = true
            if q.timeLeft and q.timeLeft < Cfg.QuestMinDuration then
                ok = false
            end
            if ok then table.insert(filtered, q) end
        end
        table.sort(filtered, function(a, b)
            if by == "wen" then
                return (a.wen or 0) > (b.wen or 0)
            elseif by == "time" then
                return (a.timeLeft or math.huge) < (b.timeLeft or math.huge)
            else
                return (a.xp or 0) > (b.xp or 0)
            end
        end)
        return filtered
    end

    function Q.bestQuest(by)
        return Q.rankQuests(Q.availableQuests(), by)[1]
    end

    --============================================================
    -- PRIORITY BOSS ROUTING
    -- attack.lua reads Q.isPriority(bossName) to filter its target list.
    --============================================================
    function Q.setPriority(bossName)
        St.questPriorityBoss = bossName
        if bossName then
            print("[Dingus][Quest] priority target: " .. tostring(bossName))
        end
    end

    function Q.isPriority(bossName)
        if not bossName then return false end
        if not St.questPriorityBoss then return true end  -- no priority set → all allowed
        local lower = string.lower(bossName)
        local target = string.lower(St.questPriorityBoss)
        return lower:find(target, 1, true) ~= nil
            or target:find(lower, 1, true) ~= nil
    end

    function Q.clearPriority()
        St.questPriorityBoss = nil
    end

    --============================================================
    -- REMOTE DISCOVERY
    -- Xeno blocks hookmetamethod. We probe common paths instead.
    --============================================================
    local REMOTE_CANDIDATES = {
        -- Full paths under ReplicatedStorage
        { "Quest_Service", "AcceptQuest" },
        { "Quest_Service", "TakeQuest" },
        { "Quest_Service", "Accept" },
        { "QuestService", "AcceptQuest" },
        { "Remotes", "AcceptQuest" },
        { "Remotes", "Quest", "Accept" },
        { "Communication", "AcceptQuest" },
        { "Communication", "Quest_Accept" },
        { "Net", "Quest", "Accept" },
        { "Net", "AcceptQuest" },
        { "GameRemotes", "Quest", "Accept" },
        { "Shared", "Remotes", "AcceptQuest" },
        { "Packets", "AcceptQuest" },
        { "Quest", "AcceptQuest" },
        { "Events", "QuestAccept" },
        { "RemoteEvents", "QuestAccept" },
        { "RemoteEvents", "AcceptQuest" },
    }

    function Q.findQuestRemote()
        if Cfg.QuestRemotePath and Cfg.QuestRemotePath ~= "" then
            -- Explicit override: user pastes path
            local parts = {}
            for p in Cfg.QuestRemotePath:gmatch("[^%.]+") do
                table.insert(parts, p)
            end
            local cur = game
            for i, p in ipairs(parts) do
                if i == 1 and p == "game" then
                    -- skip
                else
                    local ok, next = pcall(function() return cur:FindFirstChild(p) end)
                    if not ok or not next then
                        cur = nil
                        break
                    end
                    cur = next
                end
            end
            if cur and (cur:IsA("RemoteEvent") or cur:IsA("RemoteFunction")) then
                St.questRemote = cur
                St.questRemoteName = Cfg.QuestRemotePath
                return cur
            end
            print("[Dingus][Quest] override path not found: " .. Cfg.QuestRemotePath)
        end

        for _, path in ipairs(REMOTE_CANDIDATES) do
            local cur = rs
            local ok = true
            for _, p in ipairs(path) do
                local nxt = cur:FindFirstChild(p)
                if not nxt then ok = false; break end
                cur = nxt
            end
            if ok and cur and (cur:IsA("RemoteEvent") or cur:IsA("RemoteFunction")) then
                St.questRemote = cur
                St.questRemoteName = table.concat(path, ".")
                print("[Dingus][Quest] found remote: ReplicatedStorage." .. St.questRemoteName)
                return cur
            end
        end

        print("[Dingus][Quest] no quest remote found by probing (path unknown)")
        return nil
    end

    --============================================================
    -- ACCEPT QUEST
    --============================================================
    function Q.acceptQuest(bossName)
        if not Cfg.QuestAutoAccept then return false end
        if not St.questRemote then
            St.questRemote = Q.findQuestRemote()
        end
        if not St.questRemote then return false end

        -- Guard: max active
        if #St.questActive >= Cfg.QuestMaxActive then
            return false
        end

        local ok, err = pcall(function()
            if St.questRemote:IsA("RemoteEvent") then
                St.questRemote:FireServer(bossName)
            else
                St.questRemote:InvokeServer(bossName)
            end
        end)
        if ok then
            table.insert(St.questActive, {
                boss = bossName,
                acceptedAt = U.clock(),
            })
            print(string.format("[Dingus][Quest] accepted: %s", bossName))
            return true
        end
        print("[Dingus][Quest] accept failed: " .. tostring(err))
        return false
    end

    --============================================================
    -- CYCLE · periodic
    --============================================================
    function Q.cycle()
        local now = U.clock()
        if now - St.questLastCycle < Cfg.QuestCycleT then return end
        St.questLastCycle = now
        St.questCycleCount = St.questCycleCount + 1

        -- Refresh hunts and level
        St.questHunts = Q.readHunts()
        St.playerLevel = Q.readLevel()
        St.huntCount = #St.questHunts

        -- Read active crow quests if menu visible
        local active = Q.readActiveQuests()
        if #active > 0 then
            St.questActive = active
        end

        -- Pick best available quest
        local available = Q.availableQuests()
        local ranked = Q.rankQuests(available, Cfg.QuestPriority)
        St.questAvailable = ranked

        if #ranked > 0 then
            local best = ranked[1]
            local bossName = best.boss or ("hunt_" .. tostring(best.id))
            Q.setPriority(bossName)
            St.questTarget = bossName

            -- Attempt auto-accept
            if Cfg.QuestAutoAccept and #St.questActive < Cfg.QuestMaxActive then
                Q.acceptQuest(bossName)
            end
        else
            Q.clearPriority()
        end
    end

    --============================================================
    -- BOOT · one-shot discovery
    --============================================================
    task.spawn(function()
        task.wait(3)
        resolveFolders()

        print("[Dingus][Quest] initializing...")

        -- Log folder structure
        if folders.bossHunts then
            print(string.format("[Dingus][Quest] BossHunts: %d configs",
                #folders.bossHunts:GetChildren()))
        else
            print("[Dingus][Quest] BossHunts folder NOT FOUND")
        end

        if folders.quests then
            St.questTemplates = Q.readQuestTemplates()
            print(string.format("[Dingus][Quest] Quests: %d templates", #St.questTemplates))
        else
            print("[Dingus][Quest] Assets.Quests NOT FOUND")
        end

        if folders.chests then
            St.chestTemplates = Q.readChestTemplates()
            print(string.format("[Dingus][Quest] Chests: %d templates", #St.chestTemplates))
        else
            print("[Dingus][Quest] Assets.Chests NOT FOUND")
        end

        -- Initial hunts read (logs structure on first call)
        St.questHunts = Q.readHunts()

        -- Probe for remote
        Q.findQuestRemote()

        print(string.format("[Dingus][Quest] ready · level=%d hunts=%d remote=%s",
            Q.readLevel(), #St.questHunts, St.questRemoteName))
    end)

    --============================================================
    -- STATS
    --============================================================
    function Q.stats()
        return {
            level = Q.readLevel(),
            hunts = #St.questHunts,
            available = #St.questAvailable,
            active = #St.questActive,
            priority = St.questPriorityBoss,
            remote = St.questRemoteName,
            remoteFound = St.questRemote ~= nil,
            cycles = St.questCycleCount,
            chestTemplates = #St.chestTemplates,
            questTemplates = #St.questTemplates,
        }
    end

    print("[Dingus][quests] v1 initialized")
end

return Q
