# Dingus-Slayer · USAGE

**How to actually use this thing, session by session.**

This is the operational guide. The [README](README.md) explains architecture, modules, and design. This document is the playbook: install, first run, day-to-day workflows, emergency procedures, and every console command worth knowing.

---

## Table of contents

1. [Before you start](#before-you-start)
2. [Quick start — 60 seconds](#quick-start--60-seconds)
3. [Pre-flight checklist](#pre-flight-checklist)
4. [First-ever boot (learn mode)](#first-ever-boot-learn-mode)
5. [Second boot (armed)](#second-boot-armed)
6. [Running combat](#running-combat)
7. [Reading crow quests](#reading-crow-quests)
8. [Collecting chests safely](#collecting-chests-safely)
9. [GUI walkthrough](#gui-walkthrough)
10. [Common workflows](#common-workflows)
11. [Session lifecycle](#session-lifecycle)
12. [Emergency procedures](#emergency-procedures)
13. [Console cookbook](#console-cookbook)
14. [What NOT to do](#what-not-to-do)

---

## Before you start

### What you need

- Roblox installed and logged in
- A working executor (Xeno, Solara, SynapseZ, etc.) that supports:
  - `game:HttpGet`
  - `loadstring`
  - `task.wait` / `task.spawn`
  - `fireproximityprompt`
- Internet connection (loader fetches modules from GitHub)
- Project Slayers 2 launched and your character spawned

### What you need to understand

1. **This violates Roblox ToS.** Every session carries ban risk.
2. **Do not use on accounts you care about.** Use a burner. Assume every session could be your last on that account.
3. **Chest collection is dangerous.** The v5 honeypot incident that got an account banned happened because of keyword-based chest detection. Learn mode is the default for a reason.
4. **You cannot undo a ban.** Do not appeal. Do not rejoin on the same IP.

---

## Quick start — 60 seconds

If you already know what you're doing and just want the command:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/PurpleXPurple/Dingus-Slayer/main/loader.lua"))()
```

Wait for `RESULT · complete` in F9. Press RightShift. Click **Start Combat**.

That's the armed path. **Do not skip [First-ever boot](#first-ever-boot-learn-mode)** if you've never run this before — learn mode exists to prevent exactly the kind of ban that happened in October 2026.

---

## Pre-flight checklist

Before **every** session (takes 20 seconds):

| # | Check | Why |
|---|---|---|
| 1 | Roblox client open, Project Slayers 2 launched | Loader assumes running game |
| 2 | Character fully spawned (not loading screen) | `U.hrp()` returns nil during load |
| 3 | Executor injected and console shows its status | Dead executor = dead script |
| 4 | `ChestLearnMode` state known (on/off) | Prevents accidental arming |
| 5 | `St.gsp` off unless you need a spoofer | Spoofers cause rubber-banding |
| 6 | Config slot saved if you tuned things | Fresh session = fresh config load |

If you're on a flagged IP/network, verify from a different device that the flagged session has cooled. Do not assume a new account on the same network is safe.

---

## First-ever boot (learn mode)

The chest module ships in **learn mode**. This means:

- It scans for chests and items
- It logs what it sees
- It never fires a proximity prompt
- **Nothing gets opened**

This is intentional. Learn mode is how you build a safe whitelist without tripping honeypots.

### Step 1 · Load the script

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/PurpleXPurple/Dingus-Slayer/main/loader.lua"))()
```

Watch F9. Wait for:

```
──────────────────────────────────────────────────────────────
  RESULT · complete in 2.84s
  13/13 modules · 0 errors · 0 warnings
──────────────────────────────────────────────────────────────
```

### Step 2 · Play normally for one session

Kill bosses. Open chests manually. Move around. Do not turn on combat yet.

The scanner runs every 4 seconds and accumulates observations. After 10–20 minutes of play:

```lua
_G.Chest.listSeen()
```

You'll see output like:

```
[Dingus][Chest] learn observations:
  World Events Chest                       seen 3x
  Common Chest                             seen 12x
  Gold Coin                                seen 47x
  Meshes/BookGrimore9_Plane.008            seen 1x
  Meshes/BookGrimore9_Plane.007            seen 1x
  Lost Mask                                seen 2x
  Coin Pouch                               seen 8x
```

### Step 3 · Identify honeypots

Anything with:
- A `/` in the name → asset path, not a world item
- `Grimore`, `Book`, `Plane`, `Effect`, `VFX`, `Particle` → decoy
- Numbers like `.008`, `.007` at the end → cloned instances

Those are traps. **Never approve them.** The v6 honeypot detector would catch them anyway, but you shouldn't whitelist them in the first place.

### Step 4 · Approve real items

For each name you personally saw in-game and know is a real chest or drop:

```lua
_G.Chest.approve("World Events Chest")
_G.Chest.approve("Common Chest")
_G.Chest.approve("Gold Coin")
_G.Chest.approve("Coin Pouch")
_G.Chest.approve("Lost Mask")
```

Each call prints confirmation:

```
[Dingus][Chest] approved: World Events Chest (whitelist=1)
[Dingus][Chest] approved: Common Chest (whitelist=2)
...
```

### Step 5 · Save the whitelist

Whitelist lives in `Cfg.ChestWhitelist`. It persists if `ChestWhitelist` is in the config PERSIST list. Save it:

```lua
_G.Cfg.save("default")
```

### Step 6 · Verify whitelist size

```lua
_G.Chest.stats().whitelistSize
```

Should be 4–6 entries for a first pass. Do not approve everything. Fewer names = less exposure.

### Step 7 · End the session

Do not arm the collector yet. Close Roblox. Wait at least 15 minutes before the next session. This gives you a clean window to review the whitelist and check nothing anomalous happened.

---

## Second boot (armed)

After learning mode gathered a safe whitelist:

### Step 1 · Load the script

Same command as before. The whitelist loads from config automatically.

### Step 2 · Verify state

```lua
_G.Chest.stats()
```

Look for:

```
learnMode = true       ← still learning
whitelistSize = 5      ← your approved items
killed = false         ← killswitch not tripped
enabled = true
```

### Step 3 · Arm the collector

```lua
_G.Chest.setLearnMode(false)
```

Prints:

```
[Dingus][Chest] learn mode = false
```

### Step 4 · Verify caps

```lua
_G.Chest.stats()
```

Confirm:
- `minuteCap = 10` — max 10 interactions/minute
- `sessionCap = 40` — max 40 interactions/session
- `reach = 4` — only fires within 4 studs
- `gap = 3.0` — 3 seconds between interactions

If any of those numbers look wrong, do not proceed. Reset defaults:

```lua
_G.Cfg.reset()
```

### Step 5 · Test on a single boss

Do **not** turn combat on yet. Manually walk to a boss, let the module detect the corpse after you kill it. Watch F9:

```
[Dingus] killed Common Enemy (1)
[Dingus][Chest] boss died — waiting 5.2s then scanning corpse
[Dingus][Chest] 3 items at corpse — attempting exactly 3
[Dingus][Chest] collected World Events Chest (attempt 1/3)
[Dingus][Chest] collected Gold Coin (attempt 2/3)
[Dingus][Chest] collected Coin Pouch (attempt 3/3)
[Dingus][Chest] corpse cycle done · 3/3 collected · moving to next boss
```

If all three items collected cleanly, the module is safe to arm fully.

If any item shows `skip <name> (attempt N/M)` — that's a locked/empty container or the prompt failed. Not a honeypot signature. The cycle continues.

### Step 6 · Enable combat

Now you can turn on combat. RightShift → Dashboard → **Start Combat**. Or:

```lua
_G.St.cbt = true
```

---

## Running combat

### Enabling

Three ways:

1. **GUI:** RightShift → Dashboard → Start Combat
2. **Console:** `_G.St.cbt = true`
3. **Auto:** set `Cfg.DefaultToggles.combat = true` and reload

### What happens when combat is on

Every 50ms the combat loop runs. Sequence:

1. Check for retreat trigger (HP thresholds)
2. Equip weapon if no weapon held
3. Acquire target if none
4. If target beyond `AtkRange` → teleport closer
5. If target in range → strike with chained M1/M2 and skill rotation
6. Check for threat → block/dodge
7. Repeat

### Reading F9 during combat

v21 prints state transitions once:

```
[Dingus][Atk] state → IDLE
[Dingus][Atk] target → Hoyuzo Subordinate
[Dingus][Atk] state → TELEPORT
[Dingus][Atk] state → STRIKE
[Dingus] killed Hoyuzo Subordinate (1)
[Dingus][Chest] boss died — waiting 5.2s then scanning corpse
[Dingus][Atk] state → LOOT
[Dingus][Chest] corpse cycle done · 3/3 collected
[Dingus][Atk] target → Sumari
```

Every state change is one line. If you see the same state for more than 15 seconds, something is stuck.

### If combat does nothing

Run:

```lua
_G.Atk.telemetry()
```

Look at `state`:
- `IDLE` + no target → scanner issue. See [console cookbook](#console-cookbook).
- `RETREAT` and not clearing within 8s → call `_G.Atk.forceStopRetreat()`
- `LOOT` and not clearing within 20s → call `_G.Atk.abortLoot()`
- `NO_CHAR` → character missing. Wait for respawn.

### Retreat behavior

Default thresholds:

| Threshold | Value | Effect |
|---|---|---|
| `RetreatHP` | 30% | Retreat when HP drops below 30% |
| `CriticalHP` | 12% | Force retreat regardless of cooldown |
| `RetreatCooldown` | 8s | Minimum gap between retreats |
| `RetreatClearHP` | 55% | Exit early if HP climbs above 55% |

If you're dying constantly, raise `RetreatHP` to 0.40 or 0.45:

```lua
_G.Cfg.RetreatHP = 0.40
```

If you're wasting time retreating, lower it to 0.25.

### Disabling

```lua
_G.St.cbt = false
```

Everything stops. Loot cycle aborts. Fly disengages. Combat state resets to IDLE.

---

## Reading crow quests

### Automatic

The quest cycle runs every 6 seconds (configurable). It:

1. Equips the crow tool
2. Opens the crow menu
3. Reads the "Defeat X" quest rows
4. Records the boss names into `St.questPriorityBosses`
5. Closes the menu

Combat then only targets bosses on that priority list.

### Manual trigger

```lua
_G.Quest.cycle()
```

Forces an immediate refresh. Useful right after a quest completes.

### Reading the current list

```lua
_G.Quest.getPriorityBosses()
```

Returns something like:

```
{"Sumari", "Datai", "Nezura"}
```

If empty, no quests are currently assigned. Combat targets any boss.

### Reading from an open panel

If the crow menu is already open (you clicked the crow), you can scrape it directly:

```lua
_G.Quest.readActiveQuests()
```

Returns the same list without reopening the panel.

### If crow tool isn't found

Check:

```lua
_G.St.crT          -- current crow tool reference
_G.Cfg.QuestCrowHotbar   -- configured slot (should be "5")
```

The crow must be in the hotbar. If it's in your inventory but not the hotbar, drag it there manually in-game.

---

## Collecting chests safely

### Every session

1. Verify learn mode state:

```lua
_G.Chest.stats().learnMode
```

2. If `true` and you're ready to collect, arm:

```lua
_G.Chest.setLearnMode(false)
```

3. If `false` and this is a fresh session where you want to be cautious:

```lua
_G.Chest.setLearnMode(true)
```

### Session cap awareness

The killswitch prevents runaway collection. It trips at 40 interactions/session.

```lua
_G.Chest.stats().killed       -- true if tripped
_G.Chest.stats().sessionCount -- current interaction count
```

If killed, all chest activity stops until reset:

```lua
_G.Chest.resetKillswitch()
```

**Do not reset reflexively.** If you've hit the cap during normal play, you're probably doing too much. Investigate before resetting.

### Per-minute rate limiting

10 interactions per minute. This is enforced regardless of session count.

```lua
_G.Chest.stats().minuteCount   -- interactions in last 60s
_G.Chest.stats().minuteCap     -- 10
```

If you're at 10/10, further attempts wait until the window rolls.

### Boss-kill cycle

After every kill, the module:

1. Waits 3–9s (random jitter)
2. Scans a 15-stud radius around the corpse
3. Attempts exactly the number of items found
4. Waits 1.5–3s between attempts
5. Exits regardless of success

You don't need to do anything. It runs automatically.

### Passive collection

While idle (no target engaged), the module sweeps once every 30 seconds within a 10-stud radius. This catches chests that spawn independently.

Disable if you want combat-only collection:

```lua
_G.Cfg.ChestPassive = false
```

### Dumping scan results

```lua
_G.Chest.dump()
```

Prints every detected chest or item within the current radius, marked with `[WL]` if it's on the whitelist. Use this to verify what the scanner sees without firing anything.

### When to add a new whitelist entry

If you see a real item in-game that the scanner isn't collecting:

1. Look at the instance name (right-click → Properties in the game, or hover it)
2. Verify it's not a honeypot (no `/`, no `Grimore`, no `Book`)
3. Add it:

```lua
_G.Chest.approve("Exact Item Name")
```

4. Save config:

```lua
_G.Cfg.save("default")
```

### When to remove a whitelist entry

If an approved name turned out to be a trap:

```lua
_G.Chest.unapprove("Name")
```

Then reset killswitch if it tripped:

```lua
_G.Chest.resetKillswitch()
```

---

## GUI walkthrough

Press **RightShift** to toggle. Window parents to `gethui()` (concealed) if available, else CoreGui.

### Dashboard

- Live stats: state, target, HP, kills
- **Start Combat** / **Stop Combat**
- **Scan Bosses** — forces a fresh scan
- **Force Move To Target** — teleports you to the current target

### Combat

- Toggles: skills, auto-equip, retreat, stun-punish, guard-spoof
- Sliders: attack range, attack interval, teleport cooldown, retreat HP%
- Combat info panel with hit rate and F-mode status

### Targets

- Per-region, per-boss enable toggles
- **Select All** / **Clear All**
- Live "enabled X/Y bosses" counter

Only enabled bosses are targeted. Disable specific bosses to skip them.

### Chests

- **Master switches**: enable, on-kill, passive
- **Collection methods**: ProximityPrompt, ClickDetector, Physical Key
- **Range sliders**: radius, depth, max passes, deadline, per-target cooldown, passive interval
- **Actions**: Force Collect Now, Scan Now (Dump to F9), Reset Cooldowns
- **Live Stats**: sweep count, chests opened, loot collected, failed, skipped, cooldowns, running
- **Last Scan**: list of recent detected targets

### Quests

- **Auto Crow Quests** toggle
- **Equip Crow**, **Force Quest Read**, **Dump Structure** buttons
- Priority info panel

### Config

- Save/load/delete the current config slot
- Reset to defaults
- Print to F9

### Files

- Refresh file list
- Delete boot log

### Logs

- Filter: All / Dingus / Errors
- Pause/Resume capture
- Save log to file
- Copy to clipboard

### Settings

- Concealed parent toggle
- Panic keybind toggle
- Panic Hide Now button
- Diagnostics: parent type, runtime info

---

## Common workflows

### Workflow 1 · Farm a specific boss

1. Open GUI → **Targets** tab
2. Clear all bosses
3. Enable only the boss you want
4. Start combat

Combat will only target that boss. Other bosses nearby are ignored.

### Workflow 2 · Auto-quest crow missions

1. Ensure crow tool is in hotbar slot 5
2. Enable Auto Crow Quests (Quests tab)
3. Enable combat

Combat restricts itself to quest-assigned bosses. When they die, quests auto-refresh on the next cycle and combat retargets.

### Workflow 3 · Add a new chest to whitelist

1. Kill a boss, walk near its drop
2. Enable learn mode:

```lua
_G.Chest.setLearnMode(true)
```

3. Let the corpse cycle run once
4. Check what it saw:

```lua
_G.Chest.listSeen()
```

5. Approve the real names:

```lua
_G.Chest.approve("Rare Chest")
_G.Chest.approve("Silver Coin")
```

6. Rearm:

```lua
_G.Chest.setLearnMode(false)
_G.Cfg.save("default")
```

### Workflow 4 · Recover from a stuck state

Symptoms: combat idle, F9 shows no activity, `telemetry().state` returns a stuck value.

```lua
-- Abort everything
_G.Atk.forceStopRetreat()
_G.Atk.abortLoot()
_G.St.tgt = nil
_G.St.cbt = false

-- Wait 2 seconds

-- Re-scan and re-arm
_G.Detect.invalidate()
_G.St.cbt = true
```

If combat still doesn't engage, restart the script entirely:

```lua
_G.Ctx.Unload()
-- then re-run the loader loadstring
```

### Workflow 5 · Change retreat thresholds mid-session

```lua
_G.Cfg.RetreatHP = 0.40
_G.Cfg.RetreatCooldown = 12.0
_G.Cfg.save("default")
```

Takes effect immediately.

### Workflow 6 · Save a named config for a specific boss

```lua
-- tune everything for boss A
_G.Cfg.save("boss_a")

-- later, for boss B
-- tune again
_G.Cfg.save("boss_b")

-- switch back
_G.Cfg.load("boss_a")
```

Config slots are separate JSON files: `dingus_config_boss_a.json`, etc.

### Workflow 7 · Reduce detection surface

If you're worried about detection:

```lua
-- Slow everything down
_G.Cfg.AtkInterval = 0.55
_G.Cfg.TeleportCd = 0.40
_G.Cfg.ChestPassiveInterval = 60
_G.Cfg.ChestMinInteractGap = 5.0
_G.Cfg.ChestMaxInteractionsPerMin = 5
_G.Cfg.save("default")
```

Everything still works, just slower. Slower = less detectable.

---

## Session lifecycle

### Start of session

```
1. Launch Roblox → Project Slayers 2
2. Wait for character spawn
3. Inject executor
4. Run loader loadstring
5. Verify boot in F9 (all 13 modules loaded)
6. Check Chest.stats() for learn mode state
7. Verify whitelist size (should not be 0)
8. Start combat via GUI or console
```

### Mid-session checks (every 10–15 minutes)

```lua
_G.Atk.telemetry()          -- combat state
_G.Chest.stats()            -- chest state, session count
_G.Detect.stats()           -- how many bosses detected
_G.St.fps                    -- performance
```

### End of session

```
1. Stop combat (_G.St.cbt = false)
2. Save config (_G.Cfg.save("default"))
3. Note any issues in F9
4. Unload script (_G.Ctx.Unload() if available)
5. Close Roblox
```

Do not leave combat running when you close the client. Save your config manually first.

---

## Emergency procedures

### Panic hide GUI

**RightCtrl + Backspace**

Instantly detaches the GUI from CoreGui. Reload the script to restore.

If you need this for a specific reason (someone walked behind you), it's the fastest way to hide.

### Killswitch triggered

If `_G.Chest.stats().killed` is `true`:

1. Do not reset immediately
2. Read F9 for what triggered it (session cap or honeypot)
3. If session cap: keep playing, wait until next session
4. If honeypot: review whitelist, unapprove anything suspicious, then reset

### Script error loop

If F9 shows repeated `[Dingus][loop X] err N`, the loop has an error.

```lua
-- Check which loop
for i = 1, #_G.Ctx.Loops do
    local L = _G.Ctx.Loops[i]
    print(L.name, "disabled=" .. tostring(L.disabled),
        "errors=" .. L.errors)
end
```

A single respawn resets all loops. If it's not a one-off, unload and reload.

### Combat completely dead

```lua
-- 1. Unstick everything
_G.Atk.forceStopRetreat()
_G.Atk.abortLoot()

-- 2. Reset combat state
_G.St.cbt = false
_G.St.tgt = nil
task.wait(0.5)
_G.St.cbt = true

-- 3. If still dead, force a fresh scan
_G.Detect.invalidate()
_G.Detect.dump()   -- check this returns non-zero humanoids
```

If `_G.Detect.dump()` returns 0 humanoids while you can see a boss, the walk is broken. Reload the script.

### Roblox kicked you

If you see:

```
Disconnected
You have been kicked by this experience or its moderators.
Moderation message: [something about exploiting]
(Error Code: 267)
```

**Do not rejoin on that account.** Close Roblox fully. Wait 72 hours minimum before touching that account again.

If you want to keep running the script, use a completely different account on a different network (mobile hotspot, different ISP).

### PANIC: something is very wrong

```lua
_G.St.cbt = false
_G.Chest.setLearnMode(true)          -- disable loot
for k in pairs(_G.Cfg.SpoofMethods) do
    _G.Cfg.SpoofMethods[k] = false    -- disable spoofers
end
_G.Cfg.save("default")
```

Then close Roblox. Do not rejoin on the same account for at least 24 hours.

---

## Console cookbook

### Status checks

```lua
_G.St.cbtS                                 -- combat state
_G.St.tgt and _G.St.tgt.ch.Name             -- current target
_G.Atk.telemetry()                          -- full attack state
_G.Detect.stats()                           -- scanner state
_G.Chest.stats()                            -- loot state
_G.Quest.stats()                            -- quest state
_G.Hotbar.state()                           -- mutex state
_G.St.fps                                    -- FPS
```

### Force actions

```lua
_G.St.cbt = true                             -- start combat
_G.St.cbt = false                            -- stop combat
_G.Detect.invalidate()                       -- clear scan caches
_G.Detect.dump()                             -- dump scan results to F9
_G.Atk.forceScan()                           -- alias for force scan
_G.Atk.forceMove()                           -- teleport to current target
_G.Atk.forceStopRetreat()                    -- clear retreat state
_G.Atk.abortLoot()                           -- abort loot cycle
_G.Chest.collectAll()                        -- force loot sweep
_G.Chest.dump()                              -- dump chest scan results
_G.Quest.cycle()                             -- force quest refresh
```

### Chest whitelist management

```lua
_G.Chest.listSeen()                          -- show learn-mode observations
_G.Chest.approve("Item Name")                -- add to whitelist
_G.Chest.unapprove("Item Name")              -- remove
_G.Chest.setLearnMode(true)                  -- enable learn mode
_G.Chest.setLearnMode(false)                 -- arm collector
_G.Chest.resetCooldowns()                    -- clear per-target skips
_G.Chest.resetKillswitch()                   -- clear session cap
```

### Spoofer control

```lua
_G.Spoof.listMethods()                       -- show all 40
_G.Spoof.stats()                             -- fire counts
_G.Spoof.setMethod("antiWarp", false)        -- disable one
_G.Spoof.setMethod("antiSoundSpam", true)    -- enable one
```

### Config management

```lua
_G.Cfg.save("default")                       -- save
_G.Cfg.load("default")                       -- load
_G.Cfg.reset()                               -- reset to defaults
print(_G.Cfg.pretty())                       -- dump to F9
```

### Debug output

```lua
_G.Detect.dump()                             -- humanoid scan
_G.Chest.dump()                              -- chest scan
_G.Hotbar.dumpSlots()                        -- hotbar slot map
_G.Atk.comboInfo()                           -- combo engine state
```

### Unload everything

```lua
if _G.Ctx and _G.Ctx.Unload then
    _G.Ctx.Unload()
end
```

Stops all loops, saves config, destroys GUI, releases hotbar mutex.

---

## What NOT to do

### Do not

- **Do not** run this on your main account.
- **Do not** approve whitelist entries without seeing them in-game first.
- **Do not** approve anything with a `/`, `\`, or `Grimore` in the name.
- **Do not** reset the killswitch reflexively.
- **Do not** appeal a Roblox exploit ban.
- **Do not** rejoin a game on a banned account.
- **Do not** rejoin on the same IP with a new account after a ban.
- **Do not** run combat at 100% uptime for hours. Take breaks.
- **Do not** leave the script running while AFK for extended periods.
- **Do not** share the script outside the official repo. Distribution is prohibited by the license.
- **Do not** post screenshots of F9 showing the script running.
- **Do not** record video of the script in action.
- **Do not** modify the whitelist to add obvious traps.
- **Do not** test new features on the same account you farm on.

### Do

- **Do** use a burner account.
- **Do** use a separate network (mobile hotspot) if you've been flagged.
- **Do** start with learn mode and stay there for at least one session.
- **Do** check `_G.Chest.stats()` before arming the collector.
- **Do** read F9 after every session for anomalies.
- **Do** save your config before ending a session.
- **Do** verify whitelist size before combat.
- **Do** keep session counts under the caps.
- **Do** report issues (in the repo, not publicly) so they can be patched.

---

## Quick reference card

Print this, tape it to your monitor.

```
═══════════════════════════════════════════════════════════════════
  LOADER
  loadstring(game:HttpGet("https://raw.githubusercontent.com/
    PurpleXPurple/Dingus-Slayer/main/loader.lua"))()

  TOGGLE UI                       RightShift
  PANIC HIDE                      RightCtrl + Backspace

  START COMBAT                    _G.St.cbt = true
  STOP COMBAT                     _G.St.cbt = false

  ARM CHEST COLLECTOR             _G.Chest.setLearnMode(false)
  DISARM / LEARN MODE             _G.Chest.setLearnMode(true)

  STATUS                          _G.Atk.telemetry()
  SCAN DUMP                       _G.Detect.dump()
  CHEST DUMP                      _G.Chest.dump()
  SAVE CONFIG                     _G.Cfg.save("default")

  STUCK RETREAT                   _G.Atk.forceStopRetreat()
  STUCK LOOT                      _G.Atk.abortLoot()
  STUCK EVERYTHING                _G.St.cbt = false; wait; _G.St.cbt = true

  KILLSWITCH TRIPPED              _G.Chest.stats().killed
  RESET (ONLY IF SAFE)            _G.Chest.resetKillswitch()

  BANNED?                         Do not rejoin. Wait 72h minimum.
                                  Do not appeal. Use a different account.
═══════════════════════════════════════════════════════════════════
```

---

<div align="center">

**See [README.md](README.md) for architecture and module reference.**
**See [LICENSE](LICENSE) for terms of use.**

</div>
