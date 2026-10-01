local O = {}

function O.init(Ctx)
    local U = Ctx.Util

    O.Stats = { parts = 0, sounds = 0, textures = 0, lastGc = 0 }

    function O.warmWorkspace()
        local n = 0
        U.walkTree(workspace, 6, function(inst)
            n = n + 1
        end, 2500)
        O.Stats.parts = n
        if Ctx.Log then Ctx.Log("OPT", "walked " .. n .. " instances") end
    end

    function O.preloadCommon()
        local assets = {}
        U.walkTree(workspace, 5, function(inst)
            local cls = inst.ClassName
            if cls == "Sound" then
                local id = inst.SoundId
                if type(id) == "string" and #id > 5 and #assets < 200 then
                    assets[#assets+1] = id
                end
            elseif cls == "ImageLabel" or cls == "ImageButton" then
                local img = inst.Image
                if type(img) == "string" and #img > 5 and #assets < 300 then
                    assets[#assets+1] = img
                end
            end
        end, 3000)
        if #assets > 0 then
            pcall(function()
                game:GetService("ContentProvider"):PreloadAsync(assets)
            end)
        end
        O.Stats.sounds = #assets
        if Ctx.Log then Ctx.Log("OPT", "preloaded " .. #assets .. " assets") end
    end

    function O.gc()
        local now = U.clock()
        if now - O.Stats.lastGc < 60 then return end
        O.Stats.lastGc = now
        pcall(function() collectgarbage("collect") end)
    end

    function O.stripLighting()
        local L = game:GetService("Lighting")
        pcall(function() L.GlobalShadows = false end)
        pcall(function() L.FogEnd = 500 end)
        pcall(function() L.ShadowSoftness = 0 end)
        for _, c in ipairs(L:GetChildren()) do
            if c:IsA("PostEffect") then
                pcall(function() c.Enabled = false end)
            end
        end
    end
end

return O
