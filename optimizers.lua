-- Dingus-Slayer · optimizers.lua v3

local O = {}

function O.init(Ctx)
    local U = Ctx.Util

    O.Stats = {
        particles = 0, lights = 0, post = 0, sounds = 0,
        enabled = false, lastGc = 0,
    }

    local Cache = {
        lighting = {}, post = {}, terrain = {},
        particles = {}, lights = {}, sounds = {},
    }

    local LIGHT_KEYS = {
        "Ambient","OutdoorAmbient","Brightness","GlobalShadows",
        "FogEnd","FogStart","FogColor","ShadowSoftness",
        "EnvironmentDiffuseScale","EnvironmentSpecularScale","ExposureCompensation",
    }

    local function cacheLighting()
        local L = game:GetService("Lighting")
        for _, k in ipairs(LIGHT_KEYS) do
            local ok, v = pcall(function() return L[k] end)
            if ok then Cache.lighting[k] = v end
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
        for k, v in pairs(Cache.lighting) do
            pcall(function() L[k] = v end)
        end
    end

    local function disablePost()
        local L = game:GetService("Lighting")
        for _, c in ipairs(L:GetChildren()) do
            if c:IsA("PostEffect") then
                local ok, en = pcall(function() return c.Enabled end)
                if ok and en then
                    Cache.post[c] = true
                    pcall(function() c.Enabled = false end)
                    O.Stats.post = O.Stats.post + 1
                end
            end
        end
    end

    local function restorePost()
        for inst in pairs(Cache.post) do
            if inst and inst.Parent then pcall(function() inst.Enabled = true end) end
        end
        Cache.post = {}
    end

    local function killInstance(inst)
        local cls = inst.ClassName
        if cls == "ParticleEmitter" or cls == "Beam" or cls == "Trail"
            or cls == "Fire" or cls == "Smoke" or cls == "Sparkles" then
            local ok, en = pcall(function() return inst.Enabled end)
            if ok and en then
                Cache.particles[inst] = true
                pcall(function() inst.Enabled = false end)
                O.Stats.particles = O.Stats.particles + 1
            end
        elseif cls == "PointLight" or cls == "SpotLight" or cls == "SurfaceLight" then
            local ok, en = pcall(function() return inst.Enabled end)
            if ok and en then
                Cache.lights[inst] = true
                pcall(function() inst.Enabled = false end)
                O.Stats.lights = O.Stats.lights + 1
            end
        end
    end

    local function walkAndKill(root, maxDepth, yieldEvery)
        yieldEvery = yieldEvery or (U.IsMobile and 500 or 2000)
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
                    for i = 1, #kids do table.insert(stack, { kids[i], d + 1 }) end
                end
                iter = iter + 1
                if iter % yieldEvery == 0 then task.wait() end
            end
        end
    end

    function O.enable()
        if O.Stats.enabled then return end
        O.Stats.enabled = true
        cacheLighting()
        applyLighting()
        disablePost()
        task.spawn(function()
            task.wait(0.5)
            pcall(walkAndKill, workspace, 6)
            pcall(walkAndKill, game:GetService("Lighting"), 3)
        end)
    end

    function O.disable()
        if not O.Stats.enabled then return end
        O.Stats.enabled = false
        restoreLighting()
        restorePost()
        for inst in pairs(Cache.particles) do
            if inst and inst.Parent then pcall(function() inst.Enabled = true end) end
        end
        for inst in pairs(Cache.lights) do
            if inst and inst.Parent then pcall(function() inst.Enabled = true end) end
        end
        Cache.particles = {}
        Cache.lights = {}
    end

    function O.warmWorkspace() return 0 end
    function O.stripLighting() cacheLighting(); applyLighting(); disablePost() end
    function O.gc() pcall(function() collectgarbage("collect") end) end

    Ctx.Cleanup = Ctx.Cleanup or {}
    table.insert(Ctx.Cleanup, function() O.disable() end)

    print(string.format("[Dingus][optimizers] v3 · %s", U.Platform))
end

return O
