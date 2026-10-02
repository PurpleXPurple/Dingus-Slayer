--[[
    Dingus-Slayer · debug-loader.lua
    Diagnostics only. Does not boot main.
    Prints every module's fetch/compile/execute status with full error text.
]]--

local REPO_USER   = "PurpleXPurple"
local REPO_NAME   = "Dingus-Slayer"
local REPO_BRANCH = "main"
local RAW_BASE = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/",
    REPO_USER, REPO_NAME, REPO_BRANCH
)

local MODULES = {
    "lists", "config", "utils", "detect", "scanners",
    "spoofers", "fly", "attack", "optimizers", "gui", "main",
}

print("=================================================")
print("  Dingus-Slayer · DEBUG LOADER")
print("  " .. RAW_BASE)
print("=================================================")

local results = {}

for _, name in ipairs(MODULES) do
    local url = RAW_BASE .. name .. ".lua"
    print(string.format("\n--- %s ---", name))

    local status = nil

    -- 1. Fetch
    local okF, src = pcall(function() return game:HttpGet(url, true) end)
    if not okF or type(src) ~= "string" or #src < 16 then
        print(string.format("  FETCH FAILED: %s", tostring(src)))
        status = "fetch-fail"
    elseif string.find(src, "404: Not Found", 1, true) then
        print("  404 NOT FOUND")
        status = "404"
    else
        print(string.format("  fetched %d bytes", #src))

        -- 2. Compile
        local fn, compileErr = loadstring(src, "@" .. name .. ".lua")
        if not fn then
            print("  COMPILE ERROR:")
            print("  " .. tostring(compileErr))
            status = "compile-fail"
        else
            print("  compiled OK")

            -- 3. Execute
            local okR, mod = pcall(fn)
            if not okR then
                print("  RUNTIME ERROR:")
                print("  " .. tostring(mod))
                status = "runtime-fail"
            elseif mod == nil then
                print("  RETURNED NIL — file missing 'return' at end")
                status = "returns-nil"
            elseif type(mod) ~= "table" then
                print(string.format("  RETURNED %s (expected table)", type(mod)))
                status = "wrong-type"
            else
                if name == "main" then
                    if type(mod.boot) == "function" then
                        print("  has .boot function: OK")
                        status = "ok"
                    else
                        print("  MISSING .boot function")
                        status = "no-boot-fn"
                    end
                else
                    if type(mod.init) == "function" then
                        print("  has .init function: OK")
                    else
                        print("  no .init function (may be OK)")
                    end
                    status = "ok"
                end
            end
        end
    end

    results[name] = status
end

print("\n=================================================")
print("  SUMMARY")
print("=================================================")
local counts = {}
for _, name in ipairs(MODULES) do
    local status = results[name] or "unknown"
    counts[status] = (counts[status] or 0) + 1
    print(string.format("  %-12s  %s", name, status))
end
print("-------------------------------------------------")
for status, count in pairs(counts) do
    print(string.format("  %-15s %d", status, count))
end
print("=================================================")
