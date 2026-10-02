<div align="center">

# Dingus-Slayer

**An automation suite for Project Slayers 2 on Roblox.**

Auto-combat · Target detection · Loot collection · Quest routing · Client-state hardening

[![Status](https://img.shields.io/badge/status-active-brightgreen)]()
[![Version](https://img.shields.io/badge/version-v21--v34-blue)]()
[![Platform](https://img.shields.io/badge/platform-Roblox-red)]()
[![Executor](https://img.shields.io/badge/executor-Xeno%20%7C%20Solara%20%7C%20SynapseZ-purple)]()

</div>

---

## ⚠️ Read this first

Dingus-Slayer automates gameplay in a live multiplayer experience. Roblox anti-cheat, project-specific anti-cheat, and manual moderator review **can and do flag, kick, and ban** accounts running scripts like this.

**Observed in practice:** an account was kicked with `Error 267 · Exploiting` on 2026-10-03 after a keyword-based loot collector fired proximity prompts on honeypot decoy instances scattered by the project's developers.

The current codebase has been hardened against the specific vector that caused that ban (whitelist-only loot collection, per-interaction rate limits, cluster honeypot detection). It is **not** risk-free. Running any game automation is against the Roblox Terms of Service.

- Do not run this on an account you care about.
- Do not run this on an account that shares a network with an account you care about.
- Do not appeal exploit bans — appeals confirm intent and can extend enforcement.
- Assume every session is logged.

The rest of this document assumes you have read the above.

---

## Table of contents

1. [What it does](#what-it-does)
2. [Architecture](#architecture)
3. [Module reference](#module-reference)
4. [Installation](#installation)
5. [First-time setup](#first-time-setup)
6. [Configuration](#configuration)
7. [GUI tour](#gui-tour)
8. [Combat system](#combat-system)
9. [Loot system](#loot-system)
10. [Quest system](#quest-system)
11. [Spoofer system](#spoofer-system)
12. [Diagnostics](#diagnostics)
13. [Troubleshooting](#troubleshooting)
14. [Changelog](#changelog)
15. [Repository layout](#repository-layout)

---

## What it does

Dingus-Slayer is a modular automation suite for Project Slayers 2. It runs entirely client-side via a Roblox script executor and orchestrates the following:

| Category | Behavior |
|---|---|
| **Auto-combat** | Detects nearby bosses, teleports into striking range, chains M1/M2 inputs, fires all six skill slots in randomized combo orders, retreats at configured HP thresholds |
| **Target acquisition** | Multi-container BFS scan finds bosses across `Humanoids`, `Regions`, `NPCs`, and other containers; priority filter restricts to crow-assigned quests |
| **Auto-loot** | Detects chests and ground items via ProximityPrompt, ClickDetector, and named-model matching; opens them within physical reach; boss-kill cycles wait for drop settlement before collecting |
| **Quest routing** | Reads crow quest assignments from the in-game panel, restricts combat to assigned bosses, refreshes on a schedule |
| **Client hardening** | 40 methods to resist environmental debuffs (blind, fog, dark, freeze, ragdoll, seat lock, camera shake, force field, invisibility, warp, dismount) |
| **GUI** | Nine-tab control panel with concealment options, live stats, per-boss toggles, chest collection controls |
| **Diagnostics** | Structured per-module health checks, walk-timing telemetry, boot trace, extended error reporting |

**Not in scope:** Any game-agnostic exploit toolkit. No remote spam. No server-side manipulation. No hitbox modification. No aimbot against players.

---

## Architecture

### Loader-driven modular layout

Every `.lua` file is fetched over HTTPS from GitHub at runtime, compiled, and registered into a shared `Ctx` (context) table. Modules communicate only through `Ctx` — there are no cross-module `require` statements.

```
                    loader.lua
                         │
                         │  fetches, compiles, executes
                         ▼
    ┌────────────────────┼────────────────────┐
    │                    │                    │
    ▼                    ▼                    ▼
 config ──────► utils ──► detect ──────► attack ──────► main
              lists  ──► scanners ──► chest          │
                    ──► hotbar  ──► quests           │
                    ──► spoofers                     │
                    ──► optimizers                   │
                    ──► gui ◄────────────────────────┘
```

### Boot sequence

| Phase | What happens | Owning file |
|---|---|---|
| 1 · Fetch | Every module downloaded from GitHub (with jsdelivr and statically fallbacks) | `loader.lua` |
| 2 · Compile | Each source `loadstring`'d once | `loader.lua` |
| 3 · Execute | Each compiled chunk runs, returns its module table, slots into `Ctx` | `loader.lua` |
| 4 · boot main | `main.boot(Ctx)` called with everything wired | `loader.lua` → `main.lua` |
| 5 · state | Initialize shared state table `St` | `main.lua` |
| 6 · scrub | Strip BodyMovers from HRP, reset character state | `main.lua` |
| 7 · config | Load persisted config from disk | `main.lua` |
| 8 · subsystems | Call `.init(Ctx)` on every module in dependency order | `main.lua` |
| 9 · scheduler | Build the loop table | `main.lua` |
| 10 · deferred | Warm workspace cache, strip lighting, first scan | `main.lua` |

### Shared state: `Ctx` and `St`

| Key | Type | Contents |
|---|---|---|
| `Ctx.St` | table | Runtime state — combat flags, target, counters, timers, caches |
| `Ctx.Cfg` | table | Configuration — tunables, persistence list, defaults |
| `Ctx.Util` | table | Safe service loader, input helpers, capability probes |
| `Ctx.Detect` | table | Humanoid scanning, threat assessment, animation reading |
| `Ctx.Scan` | table | Crow tool/panel scanners |
| `Ctx.Hotbar` | table | Hotbar mutex, item database, slot lookup |
| `Ctx.Spoof` | table | Client-state hardening methods |
| `Ctx.Chest` | table | Chest and loot collection |
| `Ctx.Quest` | table | Crow panel reader, quest routing |
| `Ctx.Atk` | table | Combat state machine |
| `Ctx.Opt` | table | Workspace and lighting optimizers |
| `Ctx.Gui` | table | Nine-tab control panel |
| `Ctx.Loops` | table | Active scheduler loop metadata |
| `Ctx.Errors` | table | Boot error list |

Every module reads `Ctx` for its dependencies and writes to `Ctx.St` for its runtime state.

---

## Module reference

### `loader.lua`

Fetches, compiles, executes, and registers every module. Multi-CDN chain (GitHub → jsdelivr → statically) with retry backoff. Optional disk cache with 1-hour TTL. Breadcrumb tracing for crash diagnosis.

**Key behavior:**
- Sequential fetch (parallel crashes Xeno's HTTP layer)
- Source released after compile to prevent memory spikes
- Structured boot log with per-module timing
- Full error text surfaced in summary

### `main.lua`

Boot orchestrator and scheduler. Owns the loop table, respawn handler, RightShift UI toggle, and unload contract.

**Scheduler loops:**

| Loop | Interval | Purpose |
|---|---|---|
| `combat` | 0.05s | Attack state machine |
| `spoofers` | 0.10s | Client-state hardening |
| `threats` | 0.10s | Threat assessment |
| `quest` | 0.50s | Quest refresh cycle |
| `chest` | 3.00s | Passive loot sweep |
| `config` | 30s | Autosave |
| `gc` | 60s | Garbage collection |

Each loop has its own error counter. Five consecutive failures disable that loop until respawn.

### `config.lua`

Central configuration table. Persisted keys save to `dingus_config.json`. Auto-save with debounced writes. Change observers via `Cfg.observe(key, fn)`.

**Persisted categories:** combat tuning, retreat thresholds, scan timing, skills, combo order, hold detection, auto-block, emergency, loot, F-key mode, teleport, hover, spoofer methods, crow menu, GUI, caching.

### `lists.lua`

Boss name lists, region grouping, weapon classification, keyword tables.

- `bosses` — flat list
- `bossRegions` — grouped for GUI
- `selectedBosses` — per-boss enable flags
- `weapons`, `nonWeapons` — tool classification
- `mobKeywords`, `crowKeywords`, `questKeywords` — matchers

Matching uses word-boundary awareness for short entries (`ren`, `claw`) to prevent false positives on longer names.

### `utils.lua`

Safe service loading, capability probing, input helpers.

**Public API:**
- `U.hum()` — local humanoid
- `U.hrp()` — local HumanoidRootPart
- `U.tap(key)` — press and release
- `U.keyDown` / `U.keyUp`
- `U.m1()` / `U.m2()` — mouse clicks
- `U.clock()` — monotonic time
- `U.xzDist(a, b)` — planar distance
- `U.walkTree(root, depth, fn, yieldEvery)` — safe recursive walk
- `U.notify(title, text, dur)` — Roblox notification
- `U.report()` — executor capability dump

### `detect.lua`

Multi-container BFS humanoid scanner with 3-tier caching.

**Scan targets:**
- `workspace.Humanoids.Regions`
- `workspace.Humanoids`
- `workspace.NPCs` / `Enemies` / `Mobs` / `Entities` / `Units` / `Characters` / `Monsters`
- `workspace` (final fallback)

**Public API:**
- `D.scanBosses(force, includeNonPriority)` — filtered by quest priority
- `D.scanMobs(force)` — non-boss humanoids with tier and boss-adjacency annotation
- `D.nearbyAll(force)` — all humanoids
- `D.pickTarget()` — composite-scored target selection with sticky behavior
- `D.isEnemyAttacking/B locked/Stunned(enemy)` — cached animation + attribute reads
- `D.updateThreats()` — scored threat list with decay and angular bias
- `D.scanItems(radius)` / `D.scanChests(radius)` — proximity scans
- `D.dump()` — per-root walk diagnostics
- `D.walkStats` — last scan per-root iteration, hit, and timing data

### `scanners.lua`

Crow-specific scanners.

- `S.findCrowTool()` — cached, Character + Backpack only
- `S.findCrowModel()` — cached, single return value
- `S.findCancelButton()` — crow panel Cancel/Close button
- `S.findQuestCards(cancelBtn)` — clickable rows in open panel
- `S.readCrowQuests()` — text scrape of panel
- `S.activateCrowMenu(btn)` — dedup-aware activation
- `S.waitForCaw(timeout)` — sound-based trigger detection

### `hotbar.lua`

Hotbar mutex + item database + slot scanner.

**Why it exists:** the crow tool and weapons share the same hotbar. Without coordination, quests tap slot 5, attack taps slot 3, and they drop each other's equips in sequence. The mutex serializes access.

**Public API:**
- `H.acquire(holder, duration)` / `H.release(holder)` — mutex
- `H.tap(holder, key, wait)` — mutex-guarded tap
- `H.tapVerified(holder, key, expectedName, wait)` — fires and verifies equip
- `H.equipFirstOf(holder, category, wait)` — finds and equips an item by category
- `H.slotOf(itemName)` — reverse lookup
- `H.scanSlots()` — probe all 9 slots, cache result
- `H.dumpSlots()` — print slot map
- `H.state()` — current holder + timing

**Item categories:** `weapon`, `crow`, `potion`, `gourd`, `utility`, `accessory`.

### `spoofers.lua`

Forty client-state hardening methods. All default off unless marked safe.

| Category | Methods |
|---|---|
| Movement | antiSlow, antiFreeze, antiFall, spoofWalkSpeed, spoofJumpPower, spoofHipHeight, spoofGravity |
| Combat state | spoofBlock, spoofMaxHealth, antiStun, antiRagdoll, antiKnock, antiFling |
| Vision | antiBlind, antiFog, antiDark, antiShake, antiColor |
| Audio | antiDeafen, antiScream |
| Position | antiSit, antiTeleportBack, antiVoid, antiState |
| Persistence | antiAFK, antiUnequip, antiToolDrain, antiLoadout |
| Visuals | antiNametag, antiHighlight |
| Advanced | antiSpectate |
| Lock prevention | antiZoom, antiCinematic, antiWarp, antiDisarm, antiInvisible, antiForceField, antiSeatLock, antiSoundSpam, antiShakeLock |

Each runs at a per-method Hz. Errors are counted per method and logged once.

### `chest.lua`

Chest and loot collection. **Whitelist-only.** No keyword matching.

**Learn mode (default ON):**
- Scans and logs items but never fires prompts
- Use `Chest.listSeen()` to see observations
- Use `Chest.approve(name)` to add a real item to the whitelist
- When whitelist has 2+ entries, `Chest.setLearnMode(false)` arms it

**Safety features:**
- Exact-name whitelist (no substring matching)
- 4-stud reach limit (never fires beyond physical touch)
- 10 interactions/minute cap
- 40 interactions/session cap
- Honeypot cluster detection (≥3 clones of same base name → refuse)
- Reject signatures (`grimore`, `book`, `/`, `\`)
- Prompt validity check (Enabled, MaxActivationDistance > 0, no Humanoid ancestor)
- Per-target cooldown after failure

**Boss-kill cycle:**
1. Boss dies
2. Wait 3–9s random jitter
3. Scan 15-stud radius around corpse
4. Attempt exactly the number found
5. Jittered 1.5–3s between attempts
6. Exit cycle regardless of success

### `quests.lua`

Crow quest reader and priority router.

**Behavior:**
- Reads player level via 4 fallback paths
- Reads `ReplicatedStorage.BossHunts` configs
- Opens crow menu, reads "Defeat X" quest labels, closes menu
- Exposes priority boss list to detect.lua
- Auto-disables the priority filter after 20 consecutive drop-all scans

### `optimizers.lua`

Workspace and lighting optimizers.

- Kill particle emitters, beams, trails, lights
- Flatten terrain water
- Reduce lighting complexity
- Dynamic cleanup via throttled `DescendantAdded`
- Memory GC at interval

All reversible via `O.disable()`.

### `gui.lua`

Nine-tab control panel.

| Tab | Contents |
|---|---|
| Dashboard | Live stats, start/stop combat, force scan |
| Combat | Automation toggles, range/interval sliders |
| Targets | Per-region, per-boss enable toggles |
| Chests | Loot master switches, method toggles, range sliders, live stats |
| Quests | Crow controls, quest read, priority info |
| Config | Save/load/delete config slots |
| Files | File browser for the Dingus folder |
| Logs | Live log capture with filters |
| Settings | Concealment, panic keybind, diagnostics |

**Concealment:** parents to `gethui()` → CoreGui → PlayerGui (in order). Random-named ScreenGui. RightShift minimizes to pill.

---

## Installation

### Prerequisites

- A Roblox script executor that supports:
  - `game:HttpGet`
  - `loadstring`
  - `task.wait` / `task.spawn`
  - `fireproximityprompt` (for loot)
  - `gethui` (for concealed UI, optional)
- Project Slayers 2 launched in Roblox

**Tested executors:** Xeno, Solara, SynapseZ. Others should work if they implement the above.

### Bootstrap

Paste into your executor's script field and run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/PurpleXPurple/Dingus-Slayer/main/loader.lua"))()
```

The loader will:
1. Show a banner with session ID
2. Fetch all modules from GitHub
3. Compile and execute them in dependency order
4. Call `main.boot(Ctx)`
5. Print a summary table
6. Enable `_G.Ctx`, `_G.St`, and `_G.<ModuleName>` for diagnostics

### First boot log (expected)

```
──────────────────────────────────────────────────────────────
  DINGUS-SLAYER · boot-loader v34
  session a3f2 · 2026-10-03 14:22:01 · branch=main
  modules=13 · cdn-chain=3 · cache=on · http=request()
──────────────────────────────────────────────────────────────

----- PHASE 1/4 · LOAD ----------------------------------------
  ◆ config       github/304      12ms  304
  ✓ lists        github         184ms  miss
  ✓ utils        github          78ms  miss
  ✓ detect       github         320ms  miss
  ✓ scanners     github         165ms  miss
  ✓ hotbar       github         150ms  miss
  ✓ spoofers     github         240ms  miss
  ✓ chest        github         212ms  miss
  ✓ quests       github         290ms  miss
  ✓ attack       github         380ms  miss
  ✓ optimizers   github         205ms  miss
  ✓ gui          github         892ms  miss
  ✓ main         github         290ms  miss     boot fn present

----- PHASE 2/4 · BOOT ----------------------------------------
  ✓ main.boot · 421ms

----- PHASE 3/4 · EXPOSE --------------------------------------
----- PHASE 4/4 · NOTIFY --------------------------------------

──────────────────────────────────────────────────────────────
  RESULT · complete in 2.84s
  13/13 modules · 0 errors · 0 warnings
  fetch: 1.8s wall (max 892) · compile: 48ms · execute: 176ms
  slowest: gui · 892ms · github
  cache: 3 hits · 10 misses · 0 stale
──────────────────────────────────────────────────────────────
```

---

## First-time setup

### 1 · Verify module load

Open F9. Confirm:

- All 13 modules show `✓` or `◆`
- No `✗` marks
- `main.boot` succeeded

If any module shows `✗`, that module's error is printed below the summary.

### 2 · Learn mode for chests

Chest collection ships in **learn mode** — it observes but never fires. This is intentional.

```lua
_G.Chest.listSeen()
```

Prints observations like:

```
[Dingus][Chest] learn observations:
  World Events Chest                       seen 3x
  Common Chest                             seen 12x
  Meshes/BookGrimore9_Plane.008            seen 1x
  Gold Coin                                seen 4x
```

`Meshes/BookGrimore9_Plane.008` is a honeypot — never approve it.

### 3 · Approve real names

Only add names you personally saw in-game:

```lua
_G.Chest.approve("World Events Chest")
_G.Chest.approve("Common Chest")
_G.Chest.approve("Gold Coin")
_G.Chest.approve("Coin Pouch")
```

### 4 · Arm the collector

Once 3–5 names are approved:

```lua
_G.Chest.setLearnMode(false)
```

Now it fires — but only on approved names, only within reach, only at rate-limited cadence.

### 5 · Enable combat

RightShift to open the GUI. Dashboard → **Start Combat**. Or:

```lua
_G.St.cbt = true
```

---

## Configuration

### Config file

`dingus_config.json` in the executor workspace. JSON structure:

```json
{
  "_version": 6,
  "_saved_at": 1730000000,
  "AtkRange": 8,
  "AtkInterval": 0.38,
  "RetreatHP": 0.30,
  "RetreatCooldown": 8.0,
  "FKeyMode": "auto",
  "ChestLearnMode": true,
  "ChestWhitelist": ["World Events Chest", "Common Chest"],
  "SpoofMethods": {
    "antiSlow": true,
    "antiFall": true,
    "antiWarp": true
  }
}
```

### Auto-save

Config saves on a 30-second scheduler loop. Change observers can be registered at runtime:

```lua
_G.Cfg.observe("AtkRange", function(v)
    print("[Config] AtkRange changed to " .. tostring(v))
end)
```

### Reset

```lua
_G.Cfg.reset()      -- restore factory defaults
_G.Cfg.delete()     -- delete the config file
```

### Config slots

Multiple named configs:

```lua
_G.Cfg.save("aggressive")   -- saves to dingus_config_aggressive.json
_G.Cfg.load("aggressive")
```

---

## GUI tour

Press **RightShift** to toggle. The window parents to a concealed container if available.

### Concealment mode

Three options for where the UI lives:

1. `gethui()` (executor hidden container) — undetectable by game scripts
2. `CoreGui` — visible to elevated-scope scripts only
3. `PlayerGui` — visible to any local script (not recommended)

Check the Settings tab for current parent.

### Panic hide

**RightCtrl + Backspace** instantly detaches the GUI. Reload the script to restore. Toggle in Settings.

### Navigation

Left sidebar, 9 items. Each page is independently scrollable with proper scrollbar lane reserved.

---

## Combat system

### State machine

```
   IDLE ──► TELEPORT ──► STRIKE ──► BREAK ──► PUNISH
             ▲              │         │
             │              ▼         ▼
             └──── DODGE ◄── BLOCK ◄── RETREAT
                   │
                   ▼
                  LOOT (blocks all until cycle done)
```

| State | Trigger | Action |
|---|---|---|
| `IDLE` | No target | Wait |
| `TELEPORT` | Target beyond `AtkRange` | CFrame-hopping toward boss rear |
| `STRIKE` | Target in range, no special condition | Chain M1/M2, fire combo |
| `BLOCK` | Damage taken + F is block key | Hold F |
| `BREAK` | Target is blocking | Heavy rotation |
| `PUNISH` | Target is stunned | Fast attack |
| `DODGE` | Telegraph detected | Tap Q |
| `RETREAT` | HP < `RetreatHP` | Run away, cooldown 8s |
| `LOOT` | Boss just died | Wait for Chest cycle |

### Combo engine

At boot, generates 4 distinct permutations of all unlocked skill indices. Rotates through them, firing one skill per GCD window (~1.1s). Every 3 full rotations, reshuffles.

```
combo orders:
  1: F → C → Z → V → B → X
  2: X → F → B → Z → C → V
  3: V → B → X → Z → F → C
  4: C → V → Z → X → B → F
```

### Retreat thresholds

| Setting | Default | Behavior |
|---|---|---|
| `RetreatHP` | 0.30 | Retreat when below 30% HP |
| `CriticalHP` | 0.12 | Force retreat regardless of cooldown |
| `RetreatCooldown` | 8.0s | Minimum gap between retreats |
| `RetreatClearHP` | 0.55 | Exit retreat early if HP recovers above 55% |

### Auto-block

Hold F when `St.imm > 0` (imminent threat detected by detect.lua) or when HP just dropped. Release when boss idle for `BlockGraceRelease` seconds.

### Emergency mode

Below 30% HP: fires skills without ultimate gating, drops interval to 0.15s, doubles combo chain length. Below 12% HP: hard retreat.

---

## Loot system

### Detection sources

- Named models matching whitelist
- `ProximityPrompt` instances with `ObjectText`/`ActionText` matching whitelist
- `ClickDetector` instances with matching name + parent name

### Collection flow

```
boss dies
  ↓
wait 3-9s (jitter)
  ↓
scan 15-stud radius around corpse
  ↓
count found items
  ↓
attempt exactly that many
  ↓ (for each)
  ├─ approach to within 4 studs
  ├─ fire prompt / click / tap T
  ├─ jitter 1.5-3s
  └─ move to next item
  ↓
exit cycle regardless of success
```

### Whitelist management

```lua
-- see what has been observed
_G.Chest.listSeen()

-- add a name
_G.Chest.approve("World Events Chest")

-- remove a name
_G.Chest.unapprove("Common Chest")

-- current stats
_G.Chest.stats()

-- dump current scan targets
_G.Chest.dump()
```

### Rate limits

| Limit | Default | Purpose |
|---|---|---|
| Per-minute cap | 10 | Prevents clustered honeypot triggers |
| Session cap | 40 | Bounded total exposure |
| Per-target cooldown | 90s | Failed items skip |
| Interaction gap | 3s | Non-mechanical cadence |

---

## Quest system

### Crow panel

Crow quests auto-assign every ~32 seconds (5-slot pool). The panel shows "Defeat X" rows with reward and time-remaining columns. There is no accept button — the game assigns them automatically.

### Priority routing

When a quest panel is read, the boss names go into `St.questPriorityBosses`. `detect.scanBosses` filters out any boss not in that list. Combat only engages quest-assigned bosses.

If the priority list becomes stale (>180s without a successful read), the filter auto-disables and combat targets any boss.

### Forcing a quest read

```lua
_G.Quest.cycle()          -- fires an immediate refresh
_G.Quest.getPriorityBosses()   -- current list
_G.Quest.stats()          -- full state
```

---

## Spoofer system

All 40 methods are independently toggleable.

```lua
-- list all
_G.Spoof.listMethods()

-- toggle one
_G.Spoof.setMethod("antiWarp", false)
_G.Spoof.setMethod("antiSoundSpam", true)

-- fire counts
_G.Spoof.stats()
```

### Default-on methods

```
antiSlow, antiFreeze, antiFall, spoofWalkSpeed, spoofJumpPower,
spoofBlock, antiStun, antiBlind, antiFog, antiDark, antiShake,
antiColor, antiSit, antiVoid, antiState, antiAFK,
antiSpectate, antiZoom, antiCinematic, antiWarp, antiDisarm,
antiInvisible, antiForceField, antiSeatLock, antiShakeLock
```

### Default-off (opt-in)

```
spoofHipHeight, spoofGravity, spoofMaxHealth, antiRagdoll,
antiKnock, antiFling, antiDeafen, antiScream, antiTeleportBack,
antiUnequip, antiToolDrain, antiLoadout, antiNametag,
antiHighlight, antiSoundSpam
```

---

## Diagnostics

### Global helpers

```lua
_G.Ctx       -- everything
_G.St        -- runtime state
_G.Detect    -- scanner
_G.Atk       -- combat
_G.Chest     -- loot
_G.Quest     -- quests
_G.Hotbar    -- hotbar
_G.Spoof     -- hardening
_G.Gui       -- UI
_G.Cfg       -- config
```

### Common checks

```lua
-- What's my combat state?
print(_G.St.cbtS, _G.St.tgt and _G.St.tgt.ch.Name)

-- How many bosses are visible?
print(_G.Detect.stats())

-- Where did the scanner look?
_G.Detect.dump()

-- Why is combat idle?
_G.Atk.telemetry()

-- What does the chest scanner see?
_G.Chest.dump()
```

### Combat idle reason logger

v21 prints `[Dingus][Atk] no target · detect: bosses=N mobs=N humans=N` every 10 seconds if combat is idle with no target. If `bosses=0` but you can see a boss on screen, run `_G.Detect.dump()`.

### Watchdog logging

If a retreat or loot cycle runs longer than expected, the watchdog fires and logs `[Dingus][Atk] retreat watchdog fired` or `[Dingus][Atk] loot cycle watchdog fired`.

---

## Troubleshooting

### Combat doesn't attack anything

1. Check `_G.Atk.telemetry().state` — should show `STRIKE` or `TELEPORT` while near a boss
2. Check `_G.Detect.stats().bosses` — if 0, run `_G.Detect.dump()` to see per-root walk output
3. If `state = "RETREAT"` and doesn't clear within 8s, the retreat cooldown is stuck — call `_G.Atk.forceStopRetreat()`
4. If `state = "LOOT"` and doesn't clear within 20s, call `_G.Atk.abortLoot()`

### It retreats constantly

Retreat thresholds are 30% / 12%. If HP is between those, it retreats every 8 seconds. Either heal or lower `Cfg.RetreatHP`.

### Chests never open

1. Confirm learn mode is off: `_G.Chest.stats().learnMode` should be `false`
2. Confirm whitelist has entries: `_G.Chest.stats().whitelistSize` > 0
3. Run `_G.Chest.dump()` while near a chest to see if it's detected
4. If detected but not opening, check `_G.Chest.stats().killed` — session cap hit

### Crow panel never reads

1. Confirm crow is equipped: `_G.St.crT` is not nil
2. Confirm hotbar slot: `_G.Cfg.QuestCrowHotbar` should match your crow key
3. Check `_G.Quest.stats().crowTool` — should show the crow name

### "Session cap" warning

The chest module has a hard 40-interactions-per-session cap. Reset:

```lua
_G.Chest.resetKillswitch()
```

Only do this after verifying the game is safe.

### Boot fails at "fetch X"

A CDN is down or rate-limiting. The loader tries GitHub → jsdelivr → statically. If all fail:
- Check internet connectivity
- Try again in 60 seconds
- If a cached copy exists, it's used automatically (with `stale` flag)

### "Module returned nil"

The file exists but has no `return` statement at the end. Check the file on GitHub.

### Error 267 · Exploiting

The account was flagged by Roblox-level enforcement. This is terminal for that account on this game. Do not appeal.

---

## Changelog

### v21 (attack) — current

- **Fixed** retreat loop firing permanently when HP stays below RetreatHP
- **Added** retreat cooldown (8s default)
- **Changed** RetreatHP default 0.55 → 0.30
- **Changed** RetreatClearHP default 0.75 → 0.55
- **Added** state transition logging
- **Added** idle-reason logging every 10s
- **Added** pcall wrapper around combat tick body
- **Added** `A.forceStopRetreat()`

### v8 (detect) — current

- **Fixed** shared iteration counter across walk roots
- **Changed** walker to multi-container BFS
- **Added** per-root time and iteration budgets
- **Added** `D.walkStats` per-root diagnostics
- **Changed** queue from DFS stack to BFS queue

### v6 (chest) — current

- **Fixed** v5 keyword-based honeypot triggering
- **Added** whitelist-only exact-name matching
- **Added** reach limit (4 studs)
- **Added** rate limits (per-minute, per-session)
- **Added** honeypot cluster detection
- **Added** learn mode (default on)
- **Added** `approve()` / `unapprove()` / `listSeen()`

### v5 (spoofers) — current

- **Added** 9 new methods: antiZoom, antiCinematic, antiWarp, antiDisarm, antiInvisible, antiForceField, antiSeatLock, antiSoundSpam, antiShakeLock
- **Added** per-method fire counters and error counters
- **Added** `Sp.listMethods()` and `Sp.setMethod()`

### v34 (loader) — current

- **Added** HTTP headers on request() path
- **Added** ETag conditional requests (304 Not Modified)
- **Added** structured boot banner and phase dividers
- **Added** per-module timing columns
- **Added** cache statistics in summary
- **Added** `_G.DINGUS_BOOT` structured result

### v20 (attack) — superseded by v21

- **Added** watchdog for stuck retreat and loot cycle
- **Changed** `retreating` from local to `S.retreating`

### v19 (attack)

- **Added** boss-anchored loot cycle with corpse position
- **Changed** target acquisition blocked during loot cycle

### v18 (attack)

- **Changed** loot delegation to `Ctx.Chest`

### v17 (attack)

- **Added** multi-source loot detection
- **Changed** chest scan from keyword to prompt+click

---

## Repository layout

```
Dingus-Slayer/
├── README.md                    ← this file
├── loader.lua                   ← bootstrap
├── main.lua                     ← orchestrator + scheduler
├── config.lua                   ← configuration
├── lists.lua                    ← data tables
├── utils.lua                    ← helpers
├── detect.lua                   ← scanning + threats
├── scanners.lua                 ← crow scanners
├── hotbar.lua                   ← hotbar mutex + item DB
├── spoofers.lua                 ← 40 hardening methods
├── chest.lua                    ← loot collection
├── quests.lua                   ← quest routing
├── attack.lua                   ← combat state machine
├── optimizers.lua               ← workspace optimizers
├── gui.lua                      ← control panel
└── deep-research-*.md           ← research notes
```

---

## Standing notes

**On anti-cheat.** Every client-side write to a server-owned property (HP, WalkSpeed, block bar) is a local echo — the server sees the true value. Spoofers extend the visibility window of what you did, not what the server accepted. Nothing here defeats a server-side check.

**On performance.** The scanner walks 30,000–80,000 instances per cold scan. Per-root budgets cap wall-clock time at 800ms per container and 2500ms total. On a light server, a full scan completes in ~200ms.

**On persistence.** The `Dingus/cache/` folder holds module copies for warm boots. Delete it to force a fresh fetch. `Dingus/` also contains your config file and log exports.

**On public commits.** Everything pushed to a public repo is discoverable. Do not commit API keys, session tokens, or personal identifiers. The current repo contains only Lua source and documentation.

---

<div align="center">

**Maintained by PurpleXPurple**

[![GitHub](https://img.shields.io/badge/GitHub-PurpleXPurple-black)](https://github.com/PurpleXPurple/Dingus-Slayer)

</div>
