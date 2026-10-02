--[[
    Dingus-Slayer · hotbar.lua
    Serializes access to the 1-8 hotbar keys.

    Problem: quest cycle taps "2" for crow, attack taps "3" for weapon,
    200ms later. Whichever runs second drops the other's equip.

    Solution: single holder lock with expiry. Any tap goes through
    Hotbar.tap(). If another subsystem holds the lock, the tap is
    queued (or refused, depending on mode).

    Public:
      Hotbar.acquire(holder, duration) — lock, returns true if acquired
      Hotbar.release(holder)           — release if we hold it
      Hotbar.isLocked()                — (holder or nil)
      Hotbar.tap(holder, key, wait)    — acquire + tap + optional wait
      Hotbar.state()                   — diagnostics
]]--

local H = {}

function H.init(Ctx)
    local U = Ctx.Util
    local St = Ctx.St

    St.hotbarHolder = nil
    St.hotbarExpiry = 0
    St.hotbarLastKey = nil
    St.hotbarTaps = 0
    St.hotbarDenied = 0

    local function tick()
        if St.hotbarHolder and U.clock() >= St.hotbarExpiry then
            St.hotbarHolder = nil
            St.hotbarExpiry = 0
        end
    end

    function H.acquire(holder, duration)
        tick()
        if St.hotbarHolder and St.hotbarHolder ~= holder then
            St.hotbarDenied = St.hotbarDenied + 1
            return false
        end
        St.hotbarHolder = holder
        St.hotbarExpiry = U.clock() + (duration or 1.0)
        return true
    end

    function H.release(holder)
        tick()
        if not St.hotbarHolder then return true end
        if St.hotbarHolder == holder then
            St.hotbarHolder = nil
            St.hotbarExpiry = 0
            return true
        end
        return false
    end

    function H.isLocked()
        tick()
        return St.hotbarHolder
    end

    function H.tap(holder, key, wait)
        if not H.acquire(holder, (wait or 0.4) + 0.2) then
            return false
        end
        pcall(function() U.tap(key) end)
        St.hotbarLastKey = key
        St.hotbarTaps = St.hotbarTaps + 1
        if wait and wait > 0 then task.wait(wait) end
        return true
    end

    function H.forceRelease()
        St.hotbarHolder = nil
        St.hotbarExpiry = 0
    end

    function H.state()
        tick()
        return {
            holder = St.hotbarHolder,
            remaining = math.max(0, St.hotbarExpiry - U.clock()),
            lastKey = St.hotbarLastKey,
            taps = St.hotbarTaps,
            denied = St.hotbarDenied,
        }
    end

    -- Auto-release on death / respawn
    if U.Lp then
        U.Lp.CharacterAdded:Connect(function()
            task.wait(1.5)
            H.forceRelease()
        end)
    end

    print("[Dingus][hotbar] initialized")
end

return H
