local S = {}

function S.init(Ctx)
    local U = Ctx.Util
    local Cfg = Ctx.Cfg

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
        local rs = game:GetService("ReplicatedStorage")
        local svc = rs:FindFirstChild("Player_Service")
        local data = svc and svc:FindFirstChild("Data")
        local me = data and data:FindFirstChild(U.Lp.Name)
        local slots = me and me:FindFirstChild("slots")
        if slots then
            for _, slot in ipairs(slots:GetChildren()) do
                local inv = slot:FindFirstChild("Inventory")
                local invF = inv and inv:FindFirstChild("Inventory")
                if invF then
                    for _, item in ipairs(invF:GetChildren()) do
                        if U.isCrowName(item.Name) then return item end
                    end
                end
            end
        end
        return nil
    end

    function S.findCrowModel()
        local c = U.Lp.Character
        if c then
            for _, d in ipairs(c:GetChildren()) do
                if (d:IsA("Model") or d:IsA("Accessory")) and U.isCrowName(d.Name) then
                    return d
                end
            end
            local ut = c:FindFirstChild("UpperTorso")
            if ut then
                local att = ut:FindFirstChild("Crow-Shoulder-Attachment")
                if att then return att, "attachment" end
            end
        end
        local myHrp = U.hrp()
        if myHrp then
            for _, d in ipairs(workspace:GetChildren()) do
                if d:IsA("Model") and U.isCrowName(d.Name) then
                    local p = d:FindFirstChild("HumanoidRootPart") or d.PrimaryPart
                    if p and (p.Position - myHrp.Position).Magnitude < 50 then
                        return d, "nearby"
                    end
                end
            end
        end
        return nil
    end

    function S.findCrowMenu()
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        local cc = pg:FindFirstChild("ComponentsHolder")
        if not cc then return nil end
        local found = nil
        U.walkTree(cc, 10, function(inst)
            if found then return end
            if inst:IsA("TextButton") or inst:IsA("ImageButton") then
                if inst.Visible then
                    local t = string.lower(inst.Text or "")
                    if string.find(t, "accept", 1, true)
                        or string.find(t, "eliminate", 1, true)
                        or string.find(t, "hunt", 1, true)
                        or string.find(t, "quest", 1, true)
                        or string.find(t, "take", 1, true)
                        or (string.find(t, "ok", 1, true) and #t <= 5)
                        or (string.find(t, "yes", 1, true) and #t <= 6) then
                        found = inst
                    end
                end
            end
        end, 3000)
        return found
    end

    function S.findCawSound()
        local w = workspace:GetDescendants()
        for i = 1, #w do
            local s = w[i]
            if s:IsA("Sound") and string.find(string.lower(s.Name), "caw", 1, true) then
                if s.IsPlaying then return s end
            end
        end
        local rs = game:GetService("ReplicatedStorage"):GetDescendants()
        for i = 1, #rs do
            local s = rs[i]
            if s:IsA("Sound") and string.find(string.lower(s.Name), "caw", 1, true) then
                if s.IsPlaying then return s end
            end
        end
    end

    function S.deepScan(keywords)
        keywords = keywords or { "crow", "quest", "boss", "hunt" }
        local hits = {}
        local function check(inst)
            local nm = string.lower(inst.Name)
            for i = 1, #keywords do
                if string.find(nm, keywords[i], 1, true) then
                    hits[#hits+1] = { path = inst:GetFullName(), cls = inst.ClassName }
                    return
                end
            end
        end
        U.walkTree(workspace, 6, check, 2000)
        U.walkTree(game:GetService("ReplicatedStorage"), 8, check, 2000)
        local pg = U.Lp:FindFirstChildOfClass("PlayerGui")
        if pg then U.walkTree(pg, 10, check, 2000) end
        return hits
    end

    function S.dumpInventory()
        local out = {}
        local c = U.Lp.Character
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") then out[#out+1] = "equipped:" .. t.Name end
            end
        end
        local bp = U.Lp:FindFirstChildOfClass("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") then out[#out+1] = "backpack:" .. t.Name end
            end
        end
        return out
    end
end

return S
