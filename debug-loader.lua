-- Dingus-Slayer · debug-loader.lua v2
-- Diagnostics only. Does not boot main.

local REPO_USER = "PurpleXPurple"
local REPO_NAME = "Dingus-Slayer"
local REPO_BRANCH = "main"
local RAW_BASE = string.format("https://raw.githubusercontent.com/%s/%s/%s/", REPO_USER, REPO_NAME, REPO_BRANCH)

local MODULES = {
    "lists","config","utils","detect","scanners","hotbar",
    "spoofers","chest","quests","attack","optimizers","fly","gui","main",
}

local function probe(name)
    if type(_G[name]) == "function" then return _G[name] end
    local ok, v = pcall(function() return getfenv()[name] end)
    return (ok and type(v) == "function") and v or nil
end

local function httpGet(url)
    local req = probe("request") or probe("http_request")
    if not req and type(syn) == "table" then req = syn.request end
    if req then
        local ok, res = pcall(req, { Url = url, Method = "GET" })
        if ok and type(res) == "table" then
            return res.Body or res.body
        end
    end
    local ok, b = pcall(function() return game:HttpGet(url, true) end)
    return ok and b or nil
end

print("=================================================")
print("  Dingus-Slayer · DEBUG LOADER")
print("  " .. RAW_BASE)
print("  executor: " .. tostring(probe("identifyexecutor") and probe("identifyexecutor")() or "?"))
print("=================================================")

local results = {}

for _, name in ipairs(MODULES) do
    local url = RAW_BASE .. name .. ".lua"
    print(string.format("\n--- %s ---", name))
    local status = nil
    local src = httpGet(url)
    if not src or type(src) ~= "string" or #src < 16 then
        print("  FETCH FAILED")
        status = "fetch-fail"
    elseif src:find("404: Not Found", 1, true) then
        print("  404")
        status = "404"
    else
        print(string.format("  fetched %d bytes", #src))
        local fn, cerr = loadstring(src, "@" .. name .. ".lua")
        if not fn then
            print("  COMPILE ERROR:")
            print("  " .. tostring(cerr))
            status = "compile-fail"
        else
            print("  compiled OK")
            local okR, mod = pcall(fn)
            if not okR then
                print("  RUNTIME ERROR:")
                print("  " .. tostring(mod))
                status = "runtime-fail"
            elseif mod == nil then
                print("  RETURNED NIL")
                status = "returns-nil"
            elseif type(mod) ~= "table" then
                print("  RETURNED " .. type(mod))
                status = "wrong-type"
            else
                print("  OK")
                status = "ok"
            end
        end
    end
    results[name] = status
end

print("\n=================================================")
print("  SUMMARY")
print("=================================================")
for _, name in ipairs(MODULES) do
    print(string.format("  %-12s  %s", name, results[name] or "unknown"))
end
print("=================================================")
