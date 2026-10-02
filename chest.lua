--[[
    Dingus-Slayer · chest.lua
    Chest / loot collection. Multi-source detection.
    Standalone module: attack.lua delegates, gui.lua reads stats.

    Detection sources:
      1. Models/Parts by name (chest / loot keyword match)
      2. ProximityPrompt instances (ObjectText + ActionText)
      3. ClickDetector instances (name + parent name)

    Fire methods (all tried in order):
      a. fireproximityprompt(prompt)
      b. prompt:InputHoldBegin / InputHoldEnd
      c. fireclickdetector(detector)
      d. Physical T / E tap fallback

    Public API:
      Chest.scan(radius)              → { target, ... }
      Chest.sweep(radius)             → fired count
      Chest.collectAll(radius, maxT)  → fired, passes
      Chest.collectBossDrop()         → runs full multi-pass cycle
      Chest.collectPassive()          → single sweep, only if idle
      Chest.setEnabled(bool)
      Chest.resetCooldowns()
      Chest.dump()                    → prints live scan to F9
      Chest.stats()                   → table for GUI
      Chest.lastTargets()             → cached scan list
]]--

local Chest = {}

function Chest.init(Ctx)
    local U   = Ctx.Util
    local Cfg = Ctx.Cfg
    local St  = Ctx.St

    --============================================================
    -- CONFIG DEFAULTS
    --============================================================
    Cfg.ChestEnabled           = Cfg.ChestEnabled           ~= false
    Cfg.ChestOnKill            = Cfg.ChestOnKill            ~= false
    Cfg.ChestPassive           = Cfg.ChestPassive           ~= false
    Cfg.ChestPassiveInterval   = Cfg.ChestPassiveInterval   or 15
    Cfg.ChestRadius            = Cfg.ChestRadius            or 50
    Cfg.ChestMaxPasses         = Cfg.ChestMaxPasses         or 6
    Cfg.ChestPassDeadline      = Cfg.ChestPassDeadline      or 12
    Cfg.ChestScanDepth         = Cfg.ChestScanDepth         or 8
    Cfg.ChestPerTargetCooldown = Cfg.ChestPerTargetCooldown or 45
    Cfg.ChestUseProximity      = Cfg.ChestUseProximity      ~= false
    Cfg.ChestUseClick          = Cfg.ChestUseClick          ~= false
    Cfg.ChestUseKey            = Cfg.ChestUseKey            ~= false
    Cfg.ChestKeyChar           = Cfg.ChestKeyChar           or "T"
    Cfg.ChestFallbackKeyChar   = Cfg.ChestFallbackKeyChar   or "E"
    Cfg.ChestSkipLocked        = Cfg.ChestSkipLocked        ~= false
    Cfg.ChestVerbose           = Cfg.ChestVerbose           or false
    Cfg.ChestApproachDist      = Cfg.ChestApproachDist      or 4

    Cfg.ChestKeywords = Cfg.ChestKeywords or {
        "chest", "cache", "crate",
    }
    Cfg.ChestLootKeywords = Cfg.ChestLootKeywords or {
        "coin", "pouch", "metal scrap", "refinement", "silk thread",
        "ore", "relic", "orb", "scroll", "totem",
        "drop", "loot", "pick up", "pickup",
    }

    --============================================================
    -- STATE
    --============================================================
    St.chestCollected      = St.chestCollected      or 0
    St.chestLootCollected  = St.chestLootCollected  or 0
    St.chestFailed         = St.chestFailed         or 0
    St.chestSkipped        = St.chestSkipped        or 0
    St.chestPasses         = St.chestPasses         or 0
    St.chestCooldowns      = St.chestCooldowns      or {}
    St.chestLastSweep      = 0
    St.chestLastPassive    = 0
    St.chestLastTargets    = {}
    St.chestLastScanTs     = 0
    St.chestRunning        = false
    St.chestLastFired      = 0
    St.chestTotalSweeps    = 0

    --============================================================
    -- HELPERS
    --============================================================
    local function hasKeyword(str, list)
        if not str or not list then return false end
        local l = string.lower(str)
        for i = 1, #list do
            if string.find(l, list[i], 1, true) then return true end
        end
        return false
    end

    local function modelPos(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Attachment") and inst.Parent
           and inst.Parent:IsA("BasePart") then
            return inst.Parent.Position
        end
        if inst:IsA("Model") then
            if inst.PrimaryPart then return inst.PrimaryPart.Position end
            local any = inst:FindFirstChildWhichIsA("BasePart")
            if any then return any.Position end
        end
        if inst:IsA("ClickDetector") or inst:IsA("ProximityPrompt") then
            return modelPos(inst.Parent)
        end
        return nil
    end

    local function classifyName(name)
        if hasKeyword(name, Cfg.ChestKeywords) then return "chest" end
        if hasKeyword(name, Cfg.ChestLootKeywords) then return "loot" end
        return nil
    end

    local function isCooling(inst)
        local exp = St.chestCooldowns[inst]
        if not exp then return false end
        if U.clock() >= exp then
            St.chestCooldowns[inst] = nil
            return false
        end
        return true
    end

    local function setCooldown(inst)
        St.chestCooldowns[inst] = U.clock() + (Cfg.ChestPerTargetCooldown or 45)
    end

    --============================================================
    -- SCAN
    --============================================================
    function Chest.scan(radius)
        radius = radius or Cfg.ChestRadius or 50
        local r = U.hrp()
        if not r then return {} end
        local myPos = r.Position
        local out = {}
        local seen = {}
        local stack = { { workspace, 0 } }
        local iter = 0
        local depthCap = Cfg.ChestScanDepth or 8

        while #stack > 0 do
            local item = table.remove(stack)
            local inst, depth = item[1], item[2]
            if inst and depth <= depthCap then
                local kind, label = nil, nil

                if inst:IsA("Model") or inst:IsA("Part") or inst:IsA("MeshPart") then
                    kind  = classifyName(inst.Name)
                    label = inst.Name
                end
                if not kind and inst:IsA("ProximityPrompt") then
                    local name = (inst.ObjectText or "") .. " " ..
                                 (inst.ActionText or "") .. " " ..
                                 (inst.Name or "")
                    kind  = classifyName(name)
                    label = name
                end
                if not kind and inst:IsA("ClickDetector") then
                    local name = inst.Name
                    if inst.Parent then
                        name = name .. " " .. inst.Parent.Name
                    end
                    kind  = classifyName(name)
                    label = name
                end

                if kind and not seen[inst] then
                    local pos = modelPos(inst)
                    if pos then
                        local d = (pos - myPos).Magnitude
                        if d <= radius then
                            seen[inst] = true
                            table.insert(out, {
                                inst = inst,
                                pos  = pos,
                                dist = d,
                                kind = kind,
                                name = label or inst.Name,
                            })
                        end
                    end
                end

                for _, c in ipairs(inst:GetChildren()) do
                    table.insert(stack, { c, depth + 1 })
                end
                iter = iter + 1
                if iter % 3000 == 0 then task.wait() end
            end
        end

        table.sort(out, function(a, b) return a.dist < b.dist end)
        St.chestLastTargets = out
        St.chestLastScanTs = U.clock()
        return out
    end

    function Chest.lastTargets()
        return St.chestLastTargets or {}
    end

    --============================================================
    -- FIRE METHODS
    --============================================================
    local function tryFireProximity(prompt)
        if not Cfg.ChestUseProximity then return false end
        if type(fireproximityprompt) == "function" then
            local ok = pcall(fireproximityprompt, prompt)
            if ok then return true end
        end
        local ok = pcall(function()
            if prompt.InputHoldBegin then prompt:InputHoldBegin() end
            task.wait(prompt.HoldDuration or 0.1)
            if prompt.InputHoldEnd then prompt:InputHoldEnd() end
        end)
        return ok
    end

    local function tryFireClick(detector)
        if not Cfg.ChestUseClick then return false end
        if type(fireclickdetector) == "function" then
            local ok = pcall(fireclickdetector, detector)
            if ok then return true end
        end
        return false
    end

    local function tryPhysicalKey()
        if not Cfg.ChestUseKey then return false end
        U.tap(Cfg.ChestKeyChar or "T")
        task.wait(0.08)
        if Cfg.ChestFallbackKeyChar
           and Cfg.ChestFallbackKeyChar ~= Cfg.ChestKeyChar then
            U.tap(Cfg.ChestFallbackKeyChar)
            task.wait(0.08)
        end
        return true
    end

    --============================================================
    -- APPROACH + INTERACT
    --============================================================
    local function moveTo(pos)
        local r = U.hrp()
        if not r or not pos then return end
        local approach = pos - r.Position
        local flat = Vector3.new(approach.X, 0, approach.Z)
        if flat.Magnitude < 0.5 then return end
        local margin = Cfg.ChestApproachDist or 4
        local dest = r.Position + flat.Unit * math.max(0, flat.Magnitude - margin)
        dest = Vector3.new(dest.X, r.Position.Y, dest.Z)
        local dx = pos.X - dest.X
        local dz = pos.Z - dest.Z
        if dx*dx + dz*dz < 0.25 then
            dest = Vector3.new(dest.X + 1, dest.Y, dest.Z)
        end
        local cf = pcall(function()
            return CFrame.new(dest, Vector3.new(pos.X, dest.Y, pos.Z))
        end) and CFrame.new(dest, Vector3.new(pos.X, dest.Y, pos.Z))
            or CFrame.new(dest)
        pcall(function() r.CFrame = cf end)
        task.wait(0.12)
    end

    local function interact(target)
        local inst = target.inst
        if not inst or not inst.Parent then return false end

        -- If target is already a prompt/detector, try it directly
        if inst:IsA("ProximityPrompt") then
            if tryFireProximity(inst) then return true end
        elseif inst:IsA("ClickDetector") then
            if tryFireClick(inst) then return true end
        end

        -- Walk children for prompt / detector
        local got = false
        for _, child in ipairs(inst:GetDescendants()) do
            if not got then
                if child:IsA("ProximityPrompt") then
                    if tryFireProximity(child) then got = true end
                elseif child:IsA("ClickDetector") then
                    if tryFireClick(child) then got = true end
                end
            end
        end
        if got then return true end

        -- Physical key fallback
        if tryPhysicalKey() then return true end
        return false
    end

    --============================================================
    -- SWEEP (single pass)
    --============================================================
    function Chest.sweep(radius)
        radius = radius or Cfg.ChestRadius or 50
        local targets = Chest.scan(radius)
        if #targets == 0 then
            St.chestLastFired = 0
            return 0
        end

        local fired = 0
        for i = 1, #targets do
            local t = targets[i]
            if t.inst and t.inst.Parent and not isCooling(t.inst) then
                moveTo(t.pos)
                local ok = interact(t)
                if ok then
                    fired = fired + 1
                    if t.kind == "chest" then
                        St.chestCollected = St.chestCollected + 1
                        print(string.format("[Dingus][Chest] opened %s @%.0f",
                            tostring(t.name):gsub("^%s+", ""), t.dist))
                    else
                        St.chestLootCollected = St.chestLootCollected + 1
                    end
                else
                    St.chestFailed = St.chestFailed + 1
                    if Cfg.ChestSkipLocked then setCooldown(t.inst) end
                end
                task.wait(0.08)
            elseif t.inst and isCooling(t.inst) then
                St.chestSkipped = St.chestSkipped + 1
            end
        end
        St.chestLastFired = fired
        St.chestLastSweep = U.clock()
        St.chestTotalSweeps = St.chestTotalSweeps + 1
        return fired
    end

    --============================================================
    -- MULTI-PASS CYCLE
    --============================================================
    function Chest.collectAll(radius, maxPasses, deadline)
        radius     = radius     or Cfg.ChestRadius or 50
        maxPasses  = maxPasses  or Cfg.ChestMaxPasses or 6
        deadline   = deadline   or Cfg.ChestPassDeadline or 12

        if not Cfg.ChestEnabled then return 0, 0 end
        if St.chestRunning then return 0, 0 end
        St.chestRunning = true

        local startT = U.clock()
        local totalFired, emptyPasses, pass = 0, 0, 0

        while U.clock() < startT + deadline
              and pass < maxPasses
              and emptyPasses < 3 do
            pass = pass + 1
            local fired = Chest.sweep(radius)
            totalFired = totalFired + fired
            if fired == 0 then
                emptyPasses = emptyPasses + 1
            else
                emptyPasses = 0
            end
            task.wait(0.4)
        end

        St.chestRunning = false
        return totalFired, pass
    end

    --============================================================
    -- PUBLIC TRIGGERS
    --============================================================
    function Chest.collectBossDrop()
        if not Cfg.ChestEnabled then return end
        if not Cfg.ChestOnKill then return end
        print("[Dingus][Chest] boss dropped — running cycle")
        local fired, pass = Chest.collectAll()
        print(string.format("[Dingus][Chest] cycle done · fired=%d passes=%d",
            fired, pass))
    end

    function Chest.collectPassive()
        if not Cfg.ChestEnabled then return end
        if not Cfg.ChestPassive then return end
        local now = U.clock()
        if now - St.chestLastPassive < (Cfg.ChestPassiveInterval or 15) then
            return
        end
        St.chestLastPassive = now
        local fired = Chest.sweep(Cfg.ChestRadius or 50)
        if fired > 0 then
            print(string.format("[Dingus][Chest] passive · %d", fired))
        end
    end

    function Chest.setEnabled(v)
        Cfg.ChestEnabled = not not v
    end

    function Chest.resetCooldowns()
        St.chestCooldowns = {}
    end

    function Chest.dump()
        local list = Chest.scan(Cfg.ChestRadius or 50)
        print(string.format("[Dingus][Chest] %d targets within %d studs:",
            #list, Cfg.ChestRadius or 50))
        for i = 1, math.min(#list, 20) do
            local t = list[i]
            print(string.format("  [%s] %s @ %.0f",
                t.kind, (t.name or ""):gsub("^%s+", ""), t.dist))
        end
        return list
    end

    --============================================================
    -- STATS (for GUI)
    --============================================================
    function Chest.stats()
        return {
            enabled        = Cfg.ChestEnabled,
            onKill         = Cfg.ChestOnKill,
            passive        = Cfg.ChestPassive,
            radius         = Cfg.ChestRadius or 50,
            passes         = St.chestPasses or 0,
            totalSweeps    = St.chestTotalSweeps or 0,
            collected      = St.chestCollected or 0,
            lootCollected  = St.chestLootCollected or 0,
            failed         = St.chestFailed or 0,
            skipped        = St.chestSkipped or 0,
            lastFired      = St.chestLastFired or 0,
            lastScanAge    = U.clock() - (St.chestLastScanTs or 0),
            lastTargets    = #(St.chestLastTargets or {}),
            cooldowns      = (function()
                local n = 0
                for _ in pairs(St.chestCooldowns or {}) do n = n + 1 end
                return n
            end)(),
            running        = St.chestRunning or false,
        }
    end

    --============================================================
    -- RESPAWN
    --============================================================
    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(1.5)
            Chest.resetCooldowns()
        end)
    end

    print("[Dingus][chest] initialized · multi-source detection")
end

return Chest
