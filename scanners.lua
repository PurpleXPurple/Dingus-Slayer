-- Dingus-Slayer · scanners.lua v5

local S = {}

function S.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg

    local function getComponentsHolder()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        return pg and pg:FindFirstChild("ComponentsHolder") or nil
    end

    function S.findCrowTool()
        local c = U.Lp.Character
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") and U.isCrowName(t.Name) then return t end
            end
        end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and U.isCrowName(t.Name) then return t end
            end
        end
        return nil
    end

    function S.findCancelButton()
        local cc = getComponentsHolder()
        if not cc then return nil end
        local stack = { { cc, 0 } }
        while #stack > 0 do
            local item = table.remove(stack)
            local inst, d = item[1], item[2]
            if inst and d <= 6 then
                if inst:IsA("TextButton") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok then
                        local l = string.lower(txt or ""):gsub("^%s+", ""):gsub("%s+$", "")
                        if l == "cancel" or l == "close" then
                            local okV, vis = pcall(function() return inst.Visible end)
                            if okV and vis then return inst end
                        end
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do
                    table.insert(stack, { k, d + 1 })
                end
            end
        end
        return nil
    end

    function S.readCrowQuests()
        local cc = getComponentsHolder()
        if not cc then return {} end
        local found = {}
        local stack = { cc }
        while #stack > 0 do
            local inst = table.remove(stack)
            if inst then
                if inst:IsA("TextLabel") then
                    local ok, txt = pcall(function() return inst.Text end)
                    if ok and type(txt) == "string" then
                        local name = txt:match("^%s*Defeat%s+(.+)$")
                        if name then
                            name = name:gsub("%s+$", "")
                            if #name > 0 and #name < 40 then
                                table.insert(found, name)
                            end
                        end
                    end
                end
                for _, k in ipairs(inst:GetChildren()) do table.insert(stack, k) end
            end
        end
        return found
    end

    function S.findCrowMenu() return nil end

    function S.stats()
        return {
            toolCached = S.findCrowTool() ~= nil,
            platform = U.Platform,
        }
    end

    print(string.format("[Dingus][scanners] v5 · %s", U.Platform))
end

return S
