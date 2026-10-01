--[[
    Dingus-Slayer · optimizers.lua v25
    Reversible optimization. Cached originals. Batched with yields.
    Dynamic particle handling for spawns after optimization runs.
]]--

local O = {}

function O.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg

    --============================================================
    -- STATE
    --============================================================
    O.Stats = {
        particlesKilled = 0,
        partsHidden = 0,
        lightsDisabled = 0,
        postEffectsDisabled = 0,
        soundsMuted = 0,
        lastGc = 0,
        lastMemoryCheck = 0,
        dynamicCleanups = 0,
        enabled = false,
    }

    -- Cached original values — restored on disable
    O.Cache = {
        lighting = {},
        postEffects = {},
        terrain = {},
        particles = {},       -- instance → original Enabled
        parts = {},           -- instance → original LocalTransparencyModifier
        lights = {},          -- instance → original Enabled
        sounds = {},          -- instance → original Volume
        atmosphere = {},
    }

    O.DynamicConnections = {}

    --============================================================
    -- LIGHTING
    --============================================================
    local LIGHTING_KEYS = {
        "Ambient", "OutdoorAmbient", "Brightness",
        "GlobalShadows", "FogEnd", "FogStart", "FogColor",
        "ShadowSoftness", "EnvironmentDiffuseScale", "EnvironmentSpecularScale",
        "ExposureCompensation",
    }

    local function cacheLighting()
        local L = game:GetService("Lighting")
        for i = 1, #LIGHTING_KEYS do
            local k = LIGHTING_KEYS[i]
            local ok, v = pcall(function() return L[k] end)
            if ok then O.Cache.lighting[k] = v end
        end
    end

    local function applyLighting()
        local L = game:GetService("Lighting")
        pcall(function()
            L.GlobalShadows = false
            L.ShadowSoftness = 0
            L.EnvironmentDiffuseScale = 0
            L.EnvironmentSpecularScale = 0
            L.FogEnd = 100000
            L.FogStart = 0
        end)
    end

    local function restoreLighting()
        local L = game:GetService("Lighting")
        for k, v in pairs(O.Cache.lighting) do
            pcall(function() L[k] = v end)
        end
    end

    --============================================================
    -- POST-EFFECTS
    --============================================================
    local function disablePostEffects()
        local L = game:GetService("Lighting")
        for _, c in ipairs(L:GetChildren()) do
            if c:IsA("PostEffect") then
                local ok, wasEnabled = pcall(function() return c.Enabled end)
                if ok and wasEnabled then
                    O.Cache.postEffects[c] = true
                    pcall(function() c.Enabled = false end)
                    O.Stats.postEffectsDisabled = O.Stats.postEffectsDisabled + 1
                end
            end
        end
    end

    local function restorePostEffects()
        for inst, _ in pairs(O.Cache.postEffects) do
            if inst and inst.Parent then
                pcall(function() inst.Enabled = true end)
            end
        end
        O.Cache.postEffects = {}
    end

    --============================================================
    -- TERRAIN
    --============================================================
    local function flattenTerrain()
        local ws = workspace
        local terrain = ws:FindFirstChildOfClass("Terrain")
        if not terrain then return end
        local keys = { "WaterWaveSize", "WaterWaveSpeed", "WaterReflectance", "WaterTransparency" }
        for i = 1, #keys do
            local k = keys[i]
            local ok, v = pcall(function() return terrain[k] end)
            if ok then O.Cache.terrain[k] = v end
        end
        pcall(function()
            terrain.WaterWaveSize = 0
            terrain.WaterWaveSpeed = 0
            terrain.WaterReflectance = 0
            terrain.WaterTransparency = 0.6
        end)
    end

    local function restoreTerrain()
        local ws = workspace
        local terrain = ws:FindFirstChildOfClass("Terrain")
        if not terrain then return end
        for k, v in pairs(O.Cache.terrain) do
            pcall(function() terrain[k] = v end)
        end
    end

    --============================================================
    -- PARTICLE / VISUAL KILL (batched + dynamic)
    --============================================================
    local KILL_CLASSES = {
        ParticleEmitter = true,
        Beam = true,
        Trail = true,
        Fire = true,
        Smoke = true,
        Sparkles = true,
        PointLight = true,
        SpotLight = true,
        SurfaceLight = true,
    }

    local function killInstance(inst)
        local cls = inst.ClassName
        if cls == "ParticleEmitter" or cls == "Beam" or cls == "Trail"
            or cls == "Fire" or cls == "Smoke" or cls == "Sparkles" then
            local ok, wasEnabled = pcall(function() return inst.Enabled end)
            if ok and wasEnabled then
                O.Cache.particles[inst] = true
                pcall(function() inst.Enabled = false end)
                O.Stats.particlesKilled = O.Stats.particlesKilled + 1
            end
        elseif cls == "PointLight" or cls == "SpotLight" or cls == "SurfaceLight" then
            local ok, wasEnabled = pcall(function() return inst.Enabled end)
            if ok and wasEnabled then
                O.Cache.lights[inst] = true
                pcall(function() inst.Enabled = false end)
                O.Stats.lightsDisabled = O.Stats.lightsDisabled + 1
            end
        elseif cls == "Sound" then
            local ok, vol = pcall(function() return inst.Volume end)
            if ok and vol > 0 and (inst.Name:lower():find("swing") or
                inst.Name:lower():find("footstep") or
                inst.Name:lower():find("ambient")) then
                O.Cache.sounds[inst] = vol
                pcall(function() inst.Volume = 0 end)
                O.Stats.soundsMuted = O.Stats.soundsMuted + 1
            end
        end
    end

    -- Batched walker: yields every N instances to keep FPS up
    local function walkAndKill(root, maxDepth, yieldEvery)
        yieldEvery = yieldEvery or 2000
        maxDepth = maxDepth or 6
        local stack = { { root, 0 } }
        local iter = 0

        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= maxDepth then
                pcall(killInstance, inst)

                local ok, kids = pcall(function() return inst:GetChildren() end)
                if ok and kids then
                    for i = 1, #kids do
                        table.insert(stack, { kids[i], d + 1 })
                    end
                end

                iter = iter + 1
                if iter % yieldEvery == 0 then task.wait() end
            end
        end
    end

    local function restoreParticles()
        for inst, _ in pairs(O.Cache.particles) do
            if inst and inst.Parent then
                pcall(function() inst.Enabled = true end)
            end
        end
        O.Cache.particles = {}
    end

    local function restoreLights()
        for inst, _ in pairs(O.Cache.lights) do
            if inst and inst.Parent then
                pcall(function() inst.Enabled = true end)
            end
        end
        O.Cache.lights = {}
    end

    local function restoreSounds()
        for inst, vol in pairs(O.Cache.sounds) do
            if inst and inst.Parent then
                pcall(function() inst.Volume = vol end)
            end
        end
        O.Cache.sounds = {}
    end

    --============================================================
    -- DYNAMIC CLEANUP
    -- Handles particles/lights that spawn AFTER optimization ran.
    --============================================================
    local function installDynamicCleanup()
        if #O.DynamicConnections > 0 then return end

        -- Watch workspace for new particles/lights
        local ws = workspace
        local conn1 = ws.DescendantAdded:Connect(function(inst)
            if not O.Stats.enabled then return end
            local cls = inst.ClassName
            if KILL_CLASSES[cls] then
                task.defer(function()
                    pcall(killInstance, inst)
                    O.Stats.dynamicCleanups = O.Stats.dynamicCleanups + 1
                end)
            end
        end)
        table.insert(O.DynamicConnections, conn1)

        -- Watch Lighting for new PostEffects
        local L = game:GetService("Lighting")
        local conn2 = L.ChildAdded:Connect(function(inst)
            if not O.Stats.enabled then return end
            if inst:IsA("PostEffect") then
                task.defer(function()
                    pcall(function() inst.Enabled = false end)
                    O.Cache.postEffects[inst] = true
                end)
            end
        end)
        table.insert(O.DynamicConnections, conn2)
    end

    local function uninstallDynamicCleanup()
        for i = 1, #O.DynamicConnections do
            pcall(function() O.DynamicConnections[i]:Disconnect() end)
        end
        O.DynamicConnections = {}
    end

    --============================================================
    -- MEMORY MANAGEMENT
    --============================================================
    local function gc()
        local now = U.clock()
        if now - O.Stats.lastGc < 45 then return end
        O.Stats.lastGc = now
        pcall(function() collectgarbage("collect") end)
    end

    local function memoryReport()
        local now = U.clock()
        if now - O.Stats.lastMemoryCheck < 60 then return nil end
        O.Stats.lastMemoryCheck = now

        local ok, kb = pcall(function() return collectgarbage("count") end)
        if not ok then return nil end
        return math.floor(kb / 1024 * 10) / 10  -- MB
    end

    --============================================================
    -- PUBLIC API
    --============================================================
    function O.enable()
        if O.Stats.enabled then return end
        O.Stats.enabled = true

        cacheLighting()
        applyLighting()
        disablePostEffects()
        flattenTerrain()

        -- Background batched walk — doesn't block boot
        task.spawn(function()
            task.wait(0.5)
            pcall(walkAndKill, workspace, 6, 2000)
            pcall(walkAndKill, game:GetService("Lighting"), 3, 500)
            pcall(walkAndKill, game:GetService("ReplicatedStorage"), 4, 1500)
            print(string.format(
                "[Dingus][Opt] enabled — particles:%d lights:%d postfx:%d sounds:%d",
                O.Stats.particlesKilled, O.Stats.lightsDisabled,
                O.Stats.postEffectsDisabled, O.Stats.soundsMuted))
        end)

        installDynamicCleanup()
    end

    function O.disable()
        if not O.Stats.enabled then return end
        O.Stats.enabled = false

        uninstallDynamicCleanup()
        restoreLighting()
        restorePostEffects()
        restoreTerrain()
        restoreParticles()
        restoreLights()
        restoreSounds()

        print("[Dingus][Opt] disabled — originals restored")
    end

    function O.warmWorkspace()
        -- Light walk to prime spatial caches — does not modify anything
        local count = 0
        local stack = { { workspace, 0 } }
        local iter = 0
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 5 then
                count = count + 1
                local ok, kids = pcall(function() return inst:GetChildren() end)
                if ok and kids then
                    for i = 1, #kids do
                        table.insert(stack, { kids[i], d + 1 })
                    end
                end
                iter = iter + 1
                if iter % 2000 == 0 then task.wait() end
            end
        end
        return count
    end

    function O.stripLighting()
        -- One-shot flat lighting for immediate FPS win
        local L = game:GetService("Lighting")
        cacheLighting()
        applyLighting()
        disablePostEffects()
    end

    function O.gc()
        gc()
    end

    function O.memory()
        return memoryReport()
    end

    --============================================================
    -- CLEANUP HOOK
    --============================================================
    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function()
        O.disable()
    end)

    print("[Dingus][optimizers] initialized · reversible · dynamic cleanup")
end

return O
