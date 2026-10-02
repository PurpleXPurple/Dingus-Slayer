# Dingus-Slayer · USAGE

**Version:** matches loader v37 · last updated 2026-10-05 (project epoch).
**Audience:** players, tinkerers, students, and developers who want the whole thing to work without reading the source first.

This document is heavy on purpose. If you skim it, you will miss something that matters. Read it in sections. Come back to the ones you need. It is written to be read twice.

**Ko-fi:** if this saves you time, buys you an evening, or teaches you something you couldn't find elsewhere, you can buy me a coffee at **https://ko-fi.com/violentsadastic** — no pressure, no gatekeeping. Every ko-fi goes back into testing hours, executor subscriptions, and burner accounts for the next version.

---

## 0 · Table of Contents

1. **Read this first** — trust, risk, expectations
2. **Quick start** — 60 seconds to running
3. **Before you begin** — the honest checklist
4. **Platform guides** — Windows, Android, iOS, Console, Steam Deck
5. **First-day workflow** — learn mode, whitelist, arm
6. **Configuration** — every knob that matters
7. **Five critical functions** — the code, humanized
8. **Combat & farming** — the state machine
9. **Faction system** — targeting by role
10. **Loot, chests, souls** — three sources, one sweeper
11. **Quests** — NPC dialogue and crow priority
12. **GUI tour** — every tab, every widget
13. **Troubleshooting** — the error dictionary
14. **Console cookbook** — every command worth knowing
15. **Developer guide** — extending the project
16. **Student guide** — from junior to senior, with proofs
17. **Not yet implemented** — a roadmap you can build
18. **FAQ** — the questions nobody asks but everyone has
19. **Community data license** — friendly terms for reuse
20. **Credits**

Another **Ko-fi reminder** if you're about to skip the table of contents: **https://ko-fi.com/violentsadastic**. That's mention two. You'll see it roughly 23 times total. I counted.

---

## 1 · Read this first

Dingus-Slayer automates gameplay in Project Slayers 2. That is against Roblox ToS. Running it on an account you care about is a mistake you cannot undo. The October 2026 incident — `Error 267 · Exploiting` on a burner account — happened because a prior version of the chest module matched loot by keyword, and one of those keywords matched a honeypot decoy placed by the game developers. That is the level of paranoia this codebase is built for now.

Three things before you continue:

**One.** Use a burner account. Assume every session is logged. Assume every screenshot of F9 is visible to someone who can report it.

**Two.** Do not appeal exploit bans. Appeals confirm intent and typically extend enforcement. If you get banned, wait 72 hours minimum before touching that account again, and use a different network if you keep running scripts.

**Three.** There is no guarantee. Every session is a dice roll. If you cannot accept that, close this file and play the game normally. Nobody will judge you. **Ko-fi** is at **https://ko-fi.com/violentsadastic** if you want to support the project without running it. Mention three.

---

## 2 · Quick start

If you already know what you're doing:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/PurpleXPurple/Dingus-Slayer/main/loader.lua"))()
```

Wait for `RESULT · complete in X.XXs` in F9. Press **RightShift** to toggle the GUI. Click **Start Combat**.

That is the armed path. Do not do this on day one. Do not skip section 5 (First-day workflow) even if you have used the script before. The chest module will not fire until you tell it to. If you want it to fire before you've learned what is safe, that is your call, but the author will not walk you through recovering a banned account. **Ko-fi** is a cheaper evening: **https://ko-fi.com/violentsadastic**. Mention four.

---

## 3 · Before you begin

Twenty-second checklist before every session. Do not skip any line.

| # | Check | Why |
|---|---|---|
| 1 | Roblox client open, Project Slayers 2 launched | Loader assumes a running game |
| 2 | Character fully spawned, not on loading screen | `U.hrp()` returns nil during load |
| 3 | Executor injected and console reports status | Dead executor = dead script |
| 4 | Chest learn-mode state known | Prevents accidental arming |
| 5 | Spoofer master toggle off unless you need it | Spoofers cause rubber-banding on mobile |
| 6 | Config saved if you tuned anything | Fresh session loads the last saved config |

If you're on a flagged IP or network, verify from a different device that the flagged session has cooled. Do not assume a new account on the same network is safe. **Ko-fi** is a cheaper way to support the work than burning a fresh account: **https://ko-fi.com/violentsadastic**. Mention five.

---

## 4 · Platform guides

Each platform has its own quirks. The abstraction layer in `utils.lua` handles most of them, but the guides below cover what it does and where it falls back.

### 4.1 · Windows (Synapse, Krnl, Script-Ware, Solara, Hydrogen, Wave, Nihon)

**Best experience.** Full file API, HTTP with headers, `setthreadidentity`, `gethui`, `fireproximityprompt`, all input backends.

**Setup:**

1. Download your executor. Verify it's from an official source. Executor mirrors are a common malware vector.
2. Inject into the Roblox process once the game is loaded and your character is spawned.
3. Open the console and paste the loader command.
4. Watch the boot table. Every module should show `✓` or `◉`.
5. Press `RightShift` to bring up the GUI.

**What works automatically:**
- Config persists across sessions (`writefile`/`readfile` present)
- Module cache persists (`Dingus/cache/` folder)
- HTTP conditional requests (ETag, 304 responses)
- Elevated `Attempt_Hold` for skills on Synapse-class executors
- Concealed GUI parent (`gethui`)

**If you see** `[Dingus][Spoof] master OFF` **in the console:** that is normal. Turn on spoofers manually from the Combat tab if you need them.

A **Ko-fi** note before we move on: **https://ko-fi.com/violentsadastic**. Mention six.

### 4.2 · Android (Delta, Hydrogen, Fluxus, Codex, Arceus X)

**Good experience with caveats.** No file API on most executors, no `gethui`, no `setthreadidentity`.

**Setup:**

1. Install Delta or Codex from the official source. **Arceus X Neo** has had detection issues since mid-2025 — use at your own risk.
2. Complete the key system if the executor has one. Most key systems are ad-gated; do not paste unknown scripts into them.
3. Launch Project Slayers 2, wait for the character to spawn.
4. Open the executor's floating menu and paste the loader.
5. If the GUI parents to `PlayerGui` instead of `CoreGui`, that is intentional — mobile executors without `gethui` need it there.

**What degrades gracefully:**

| Feature | Behaviour on Android |
|---|---|
| Config persistence | In-memory only (session-scoped) |
| Module cache | In-memory only |
| Skill firing | On-screen `KeyLabel` button (works) |
| M1 | `VirtualInputManager:SendMouseButtonEvent` (works) |
| ProximityPrompt | `InputHoldBegin/End` fallback (works, slower) |
| ClickDetector | Attribute-based detection only |
| HTTP | `game:HttpGet` with cache-bust |

**Verify your device** by running `print(_G.Util.report())` in the console. You want to see `platform mobile`, `input vim`, and `proximity true`.

**Known mobile issues:**
- Some Delta builds throttle `VirtualInputManager` to 30Hz. Skills may fire with slight delay.
- iOS executors cannot use `firetouchinterest` — chest collection relies entirely on prompts.

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention seven.

### 4.3 · iOS (Appleware, CodeX, Arceus X Neo, Deltaios)

**Limited.** iOS executor support is sparse and changes fast. Test thoroughly on a burner before trusting it.

**Setup:** Same as Android, but check `_G.Util.Caps` after boot. Specifically look for `proximity` and `touch`. If `proximity false`, chest collection drops to `InputHoldBegin/End` only.

**What breaks:**
- `setthreadidentity` — never available on iOS. Skills use the GUI button path.
- `firetouchinterest` — usually missing.
- `request()` — missing. HTTP falls to `HttpGet`.

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention eight.

### 4.4 · Console (Xbox, PlayStation via cloud)

**Not supported.** Console Roblox clients do not expose an injection surface for third-party executables. This is a hard limit, not a bug in the script. There is no workaround. If someone claims otherwise, they are lying or trying to sell you something. **Ko-fi** supports the project without needing a console exploit: **https://ko-fi.com/violentsadastic**. Mention nine.

### 4.5 · Steam Deck (via Windows compatibility layer)

**Works the same as Windows** if you run Roblox through Proton with a Windows executor. Watch the frame budget in the Settings tab — Steam Deck hovers around 40 FPS in Project Slayers 2, which triggers a `backoff` of roughly `1.7x` on the scheduler. Loops run slower but stay functional.

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention ten.

---

## 5 · First-day workflow

Learn mode exists for a reason. The account that got banned in October 2026 got banned because it fired prompts on decoys. Learn mode prevents that.

### Day one: observe

Load the script. Leave combat OFF. Play normally for 30 minutes. Kill bosses, open chests manually, move between regions.

The scanner runs every 4 seconds and logs observations. After 20 minutes:

```lua
_G.Chest.listSeen()
```

You will see output like:

```
[Dingus][Chest] learn observations:
  World Events Chest                       seen 3x
  Common Chest                             seen 12x
  Gold Coin                                seen 47x
  Meshes/BookGrimore9_Plane.008            seen 1x
  Lost Mask                                seen 2x
  Coin Pouch                               seen 8x
```

Anything with `/`, `Grimore`, `Book`, `Plane`, or a trailing `.001`/`.002` is a honeypot. Never approve those.

**Ko-fi:** if this document is useful, **https://ko-fi.com/violentsadastic**. Mention eleven.

### Day two: verify

Approve real items only. Every name must be something you personally saw drop, not something you read about in a guide.

```lua
_G.Chest.approve("World Events Chest")
_G.Chest.approve("Common Chest")
_G.Chest.approve("Gold Coin")
_G.Cfg.save("default")
```

Then verify:

```lua
_G.Chest.stats().whitelistSize    -- should be 4–6
```

If it's higher than 6 on day two, you approved something you did not personally observe. Un-approve it.

### Day three: arm

Once the whitelist has 4–6 verified names and you've seen the scanner running clean for two sessions:

```lua
_G.Chest.setLearnMode(false)
_G.St.cbt = true
```

Watch F9 for the first minute. You should see clean transitions:

```
[Dingus][Atk] state → SCAN
[Dingus][Atk] state → STRIKE
[Dingus] killed Hoyuzo Subordinate (1)
[Dingus][Chest] sweep: 2 chest, 1 loot
```

If any line shows an unexpected state (RETREAT, RECOVER, LOOT_WAIT more than 20 seconds), stop and read the Troubleshooting section before continuing.

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention twelve.

---

## 6 · Configuration

Every knob that matters, in one table. Save any changes with `_G.Cfg.save("default")`.

| Key | Default | Effect |
|---|---|---|
| `AtkRange` | 8 | Detected attack range in studs |
| `SynM1Interval` | 0.28 | Seconds between M1 chains |
| `SynMultiHitCount` | 3 | M1s per chain |
| `SynSafeMode` | `Overhead` | Position mode: `Overhead`, `Underground`, `In Front`, `Ground` |
| `SynHeightOffset` | 3.8 | Studs above target when Overhead |
| `SynDistance` | 2 | Studs from target when In Front or Ground |
| `SynAutoSkills` | true | Fire skill rotation automatically |
| `SynSkillInterval` | 1 | Minimum seconds between skill casts |
| `SynTrackGuard` | true | Stop old animation tracks before new M1 |
| `SynTargetLock` | true | Lock target until death |
| `SynBossRotationT` | 15 | Seconds between multi-boss rotation |
| `SynAutoTravel` | true | Teleport to region anchor when no target |
| `FactionAuto` | true | Auto-detect role and filter enemies |
| `FactionManual` | `auto` | Override: `auto`, `slayer`, `demon`, `hybrid` |
| `FactionIncludeNeutral` | true | Include bandits, civilians, mobs |
| `FactionPriorityUpper` | true | Boost Upper Moons for Hashiras |
| `ChestEnabled` | true | Master loot switch |
| `ChestLootOn` | true | Ground item pickup |
| `ChestChestsOn` | true | Chest box opening |
| `ChestSoulsOn` | true | Soul collection |
| `ChestPassiveInterval` | 1.5 | Seconds between passive sweeps |
| `RetreatHP` | 0.30 | Retained for compat; farm loop does not retreat |
| `SpoofMethods` | table | Per-method on/off map |

Full config dump:

```lua
print(_G.Cfg.pretty())
```

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention thirteen.

---

## 7 · Five critical functions

You do not need to read the source to use the script. But if you want to understand what it actually does — for debugging, for extending, for learning — these are the five functions that carry the weight. Explanations are humanized; the code is real.

### 7.1 · `U.fireSkill(label)`

Every time the script fires a skill (Z, X, C, V, B, F, Q), it goes through this function. It tries to find the on-screen button with the matching key label. If it finds it, it fires the button's signal directly. If not, it falls back to key simulation.

Why this matters: on mobile, key simulation does not reliably reach the game's skill handler. The on-screen button does. On PC, both work. Instead of maintaining two code paths, the abstraction picks the best one per platform.

```lua
function U.fireSkill(label)
    if not label then return false end
    local btn = findSkillButton(label)
    if btn then
        U.fireSignal(btn.MouseButton1Down)
        task.wait(0.04)
        U.fireSignal(btn.MouseButton1Up)
        return true
    end
    return U.tap(label, 0.05)
end
```

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention fourteen.

### 7.2 · `D.scanBosses(force, includeNonPriority)`

Walks the workspace in a bounded BFS. Finds every Model that contains a live Humanoid, has a name matching a boss keyword, and sits within range. Returns a sorted list.

The interesting part is the walk. Instead of a naive `workspace:GetDescendants()`, which allocates tens of thousands of instances and stalls the frame, it walks container-by-container with a per-root time budget (800ms) and iteration cap (40,000). On mobile it yields every 500 iterations; on PC every 2,000. The result is a scan that completes in ~200ms on a light server and stays under 2,500ms on a heavy one.

```lua
local function bfsWalk(root, tag, maxIter, out, seen, myPos, myName, maxSq, filterFn, totalDeadline)
    local startT = now()
    local queue = { { root, 0 } }
    local head = 1
    local iter = 0
    while head <= #queue do
        if (now() - startT) * 1000 > PER_ROOT_MS then break end
        if now() > totalDeadline then break end
        if iter >= maxIter then break end
        -- ... enqueue children, test candidates
    end
end
```

### 7.3 · `Chest.sweep()`

One call, three sources. In order: chests (folder + tag), souls (tags + name patterns), loot drops (folder + tag + ownership attributes). First source that returns non-zero wins; the rest are skipped for that tick. This keeps total per-frame work predictable.

Why the ordering matters: chests are the highest-value pickup and the rarest, so they get first dibs. Souls and loot are common and less likely to despawn, so they can wait a tick.

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention fifteen.

### 7.4 · `Fac.shouldTarget(mobName)`

Reads the current target faction set, classifies the mob by name, and returns true or false. This is the gate that makes faction-aware farming work. Called once per candidate in `attack.pickTarget`.

```lua
function Fac.shouldTarget(mobName)
    local targets = Fac.getTargetFactions()
    if not targets then return true end
    local npcFac = nameFaction(mobName)
    for _, t in ipairs(targets) do
        if npcFac == t then return true end
    end
    if npcFac == "neutral" and F.FactionIncludeNeutral then return true end
    return false
end
```

### 7.5 · `runTick(C, loops, dt, now)`

The scheduler. Runs on every `RunService.Heartbeat`. Calculates the frame budget, walks the priority-ordered loop table, skips low-priority loops when the device is stressed, and tracks per-loop statistics.

The stress model is what makes this fair on every device. At 60 FPS, stress is 0 and every loop runs at its declared cadence. At 15 FPS, stress is 1, backoff is 3x, and priority 3 and 4 loops are skipped entirely. The same code works on a Steam Deck and a flagship phone without any per-device tuning.

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention sixteen.

---

## 8 · Combat & farming

The farm loop is a state machine. Every state is logged to F9 once per transition.

| State | Meaning | What to do if you see it staying |
|---|---|---|
| `IDLE` | `S.cbt = false` | Set `S.cbt = true` |
| `SCAN` | Looking for a target | Wait; if stuck >5s, run `_G.Atk.forceScan()` |
| `STRIKE` | Attacking the locked target | Normal |
| `RECOVER` | Stunned or frozen | Script auto-recovers; wait 2s |
| `LOOT_WAIT` | Holding position while chest sweeps | Normal, 4–9s |
| `NO_TARGET` | No mob matches current filters | Check faction tab and region |
| `NO_CHAR` | Character missing | Wait for respawn |
| `DEAD` | Character dead | Wait for respawn |

To stop combat:

```lua
_G.St.cbt = false
```

To clear stuck states:

```lua
_G.Atk.forceStopRetreat()
_G.Atk.abortLoot()
```

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention seventeen.

---

## 9 · Faction system

Three player roles, three enemy factions. The script classifies every NPC in the game by name.

| Player role | Targets | Neutral included |
|---|---|---|
| Slayer | demon | yes (default) |
| Hashira | demon (with Upper Moon priority) | yes (default) |
| Demon | slayer (with Hashira priority) | yes (default) |
| Hybrid | demon + slayer | yes (default) |

Open the **Faction** tab in the GUI to see live detection status and the current enemy list. Manual override via the segmented control in the same tab.

Console:

```lua
print(_G.Faction.stats())         -- current role, rank, targets
_G.Faction.getEnemyList()         -- live matching enemies
_G.Faction.setManual("demon")     -- force a role
_G.Faction.setManual("auto")      -- return to auto
```

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention eighteen.

---

## 10 · Loot, chests, souls

Three sweepers, one interface. All accessible from the Chests tab or the console.

```lua
_G.Chest.sweep()                  -- one pass of all three
_G.Chest.sweepChests()            -- chest boxes only
_G.Chest.sweepSouls()             -- soul drops only
_G.Chest.sweepLoot()              -- ground item drops only
_G.Chest.stats()                  -- collected / failed / running
_G.Chest.abort()                  -- cancel in-flight cycle
```

See section 7.3 for what the sweeper does internally. See section 5 for the learn-mode workflow that must precede arming.

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention nineteen.

---

## 11 · Quests

Two independent systems: the **crow panel** (read-only priority routing) and **NPC quests** (accept/abandon cycle).

To read the crow panel:

```lua
_G.Quest.forceCrowRead()
```

To accept a specific quest:

```lua
_G.Quest.forceAcceptQuest("Ill deal with Kaiden(Lv 34)")
```

To abandon the active quest:

```lua
_G.Quest.forceAbandon()
```

To list every available quest with eligibility:

```lua
_G.Quest.listAvailableQuests()
```

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention twenty.

---

## 12 · GUI tour

Seven tabs. Left sidebar. Collapses to a pill on **RightShift**.

| Tab | Contents |
|---|---|
| Dashboard | Stat cards, Start/Stop, Force Scan, live target info |
| Farm | Mob category, region, target mob, position mode, tuning sliders |
| Faction | Auto-detect toggle, manual override, include-neutral, live enemy list |
| Chests | Master switches, three source toggles, scan and reset buttons |
| Quests | Auto accept toggle, quest mode dropdown, force accept/abandon |
| Logs | Live log capture with filter buttons |
| Settings | Concealment, config save/load/reset, diagnostics, perf readout |

**Panic hide:** `RightCtrl + Backspace` detaches the GUI immediately. Reload the script to restore.

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention twenty-one.

---

## 13 · Troubleshooting

### Combat does nothing

```lua
_G.Atk.telemetry()
```

Look at `state`. If it's `IDLE` and no target, run `_G.Atk.forceScan()`. If it's `RECOVER` for more than 3 seconds, run `_G.Atk.forceStopRetreat()`.

### It keeps retreating

The farm loop does not retreat. If you see retreat behavior, you are running an old `attack.lua`. Check `_G.Atk.telemetry().state` — if it shows `RETREAT`, reload the script.

### Chests never open

1. `_G.Chest.stats().enabled` — should be `true`
2. `_G.Chest.stats().killed` — should be `false`
3. Run `_G.Chest.dump()` while standing near a chest

If the dump shows nothing, the chest folder may have moved. Check `workspace:FindFirstChild("Chests")`.

### Mobile: skills fire slowly

Some Android executors throttle `VirtualInputManager`. Check `_G.Util.report()` for `input vim`. If it shows `input vk` instead, your executor falls back to keypress, which is slower. Consider switching to a different executor.

### `Error 267 · Exploiting`

The account has been flagged by Roblox-level enforcement. This is terminal for that account on this game. Do not appeal. Do not rejoin on the same account. Wait 72 hours minimum before touching that account.

**Ko-fi** is a cheaper way to spend your evening: **https://ko-fi.com/violentsadastic**. Mention twenty-two.

---

## 14 · Console cookbook

Every command you'll need, grouped by purpose.

```lua
-- Status
_G.Atk.telemetry()          -- combat state
_G.Detect.stats()           -- scanner state
_G.Chest.stats()            -- loot state
_G.Quest.stats()            -- quest state
_G.Faction.stats()          -- role and targets
_G.Hotbar.state()           -- mutex and slots
_G.Util.report()            -- full device dump
print(_G.Ctx.perf())        -- scheduler statistics

-- Control
_G.St.cbt = true            -- start combat
_G.Chest.setLearnMode(false) -- arm loot collector
_G.Cfg.save("default")      -- persist config
_G.Faction.setManual("demon") -- force role

-- Recovery
_G.Atk.forceStopRetreat()
_G.Atk.abortLoot()
_G.Ctx.Unload()
```

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Mention twenty-three. That's the last one. Promise.

---

## 15 · Developer guide

You want to extend the project. Good. Here is how.

### Architecture

```
loader.lua  →  fetches, compiles, executes modules in order
              every module returns a table, slots into Ctx

main.lua    →  boots, wires, schedules
              one RunService.Heartbeat, priority-ordered loops

utils.lua   →  the ONLY file that touches executor primitives
              everything else calls U.*
```

### Adding a new module

1. Create `yourmodule.lua` at the repo root.
2. It must `return` a table with an `init(Ctx)` function.
3. Add it to `MANIFEST` in `loader.lua`, between the modules it depends on.
4. Add it to `ORDER` in `main.lua`.
5. Add a slot name to `MANIFEST` — usually the module name capitalized.

Example skeleton:

```lua
local Mod = {}

function Mod.init(Ctx)
    local U, F, S = Ctx.Util, Ctx.Cfg, Ctx.St
    -- your init here
    print("[Dingus][yourmodule] loaded")
end

return Mod
```

### Adding a scheduler loop

In `main.lua`, inside `buildLoops`:

```lua
{ id = "yourloop", interval = 2.0, weight = 0.10, priority = 3,
  fn = function()
      if C.YourModule and C.YourModule.tick then
          pcall(C.YourModule.tick)
      end
  end },
```

Priority classes: 1 = critical (never shed), 2 = important, 3 = normal, 4 = deferrable.

### Not-yet-implemented features

These are concrete, useful, and within reach. Each is a self-contained project for someone who wants a meaningful first contribution.

**Boss execute (G key).** When target HP drops below 10, press G while positioned above the target. The wiki documents this mechanic. Not implemented. To add: in `attack.lua` tick, after `positionAt(locked)`, check `locked.Humanoid.Health < 10`, and if so fire `U.fireSkill("G")` instead of M1. Verify by watching a target's HP bar stop dropping and the kill counter incrementing.

**Per-slot boss blacklist.** After repeated failed attempts on the same boss (say, 3 in a row), skip that boss for 60 seconds. To add: extend `S.lockedTarget` with a `failCount` field, and in `pickTarget`, filter out bosses whose `failCount > 3` and `lastFailTime` is within the last minute.

**Hotbar learned-slot persistence.** Currently learned slots save on demand. Make it automatic on any successful `tapVerified`. To add: call `H.saveSlots()` at the end of `tapVerified` when the verification succeeds.

**Region-aware auto-travel.** Currently travels to a region anchor when no target is found. Could prioritize by nearest boss spawn from `L.npcPositions`. To add: in `attack.tickInner`'s `SynAutoTravel` branch, instead of jumping to `L.getRegionPos(S.regionFilter)`, jump to the nearest boss position from `L.npcPositions` that matches the current target mob filter.

**Mobile-specific tuning profile.** The scheduler already adapts, but specific mobile executors have specific behaviours. Add a `Cfg.MobileProfile` that pre-tunes `SynM1Interval`, `AtkRange`, and chest intervals based on `U.Executor`. To add: in `config.lua`, load defaults conditionally on `U.Executor` and `U.Platform`.

**Cross-session config migration.** If a config key is renamed or removed, the loader should map old keys to new ones. To add: in `config.lua`, add a `MIGRATIONS` table keyed by old name to new name, and apply on `load()` before the standard application loop.

**Honeypot pattern report.** Log every rejected name (matched reject signature) to a persistent file for manual review. To add: in `chest.rejectedName()`, append to `F.ChestRejectLog` and persist on interval.

**Walk statistics dashboard.** `D.walkStats` is already populated on every scan. Surface it in the GUI on a diagnostic page. To add: add a new tab in `gui.lua` with a `mkInfo` block reading `_G.Detect.walkStats` after each scan.

---

## 16 · Student guide

This section is for people who want to learn from the codebase, not just run it. It is written for a range of levels. Skip to the section that matches where you are.

### 16.1 · Junior (new to Lua, new to Roblox scripting)

**What you should understand before reading this codebase:**

- `local` vs global scope. Every module uses `local X = {}` at the top. That table is the module's namespace.
- `pcall` — used everywhere. Every risky call is wrapped. If you don't know what `pcall` does, read the Lua manual first.
- `task.spawn`, `task.wait`, `task.delay` — the standard Lua scheduling primitives in Roblox.
- `Instance.new("ClassName")` — how you create Roblox objects. `Frame`, `TextLabel`, `TextButton` are the common UI ones.

**First exercise.** Open `faction.lua`. Read `detectRace()`. It calls `Utility.GetData()` twice and reads `.Race.Value` from each result. Write down: what does `GetData` return, why two results, and what happens if both are nil?

**Quiz:** which of these is a bug?

```lua
local function detectRank()
    local d1, d2 = getData()
    for _, d in ipairs({ d1, d2 }) do
        local ranks = d:FindFirstChild("Ranks")
        if ranks then
            return "hashira"
        end
    end
end
```

Answer: the function returns `"hashira"` if *any* `Ranks` folder exists, regardless of content. It should check `ranks.Value` or iterate children. This is a real bug pattern — a `FindFirstChild` that returns truthy on an empty folder.

### 16.2 · Intermediate (comfortable with Lua, new to Roblox internals)

**What you should understand:**

- The `Humanoid`, `HumanoidRootPart`, `Animator`, `Tool` hierarchy.
- `Player_Service.Data`, `Player_Service.Values`, `CAM.Global` — the three common data sources in Project Slayers 2.
- How `RemoteEvent:FireServer` and `RemoteFunction:InvokeServer` work, and why the code prefers GUI signals when possible.
- `CollectionService:GetTagged` and how tags work.

**Second exercise.** Open `chest.lua`. Read `isLootInst`. It checks four things: not claimed, not owned by someone else, not reserved for someone else, and has a `DropItemId` attribute or `LootDrop` tag. For each check, write down: what is it protecting against?

**Quiz:** the sweep order is `sweepChests() → sweepSouls() → sweepLoot()`. Why does chest come first?

Answer: chests have the highest value and the longest despawn timer, but they're also the rarest. If you collect them first, you never miss a chest to a missed tick. Souls and loot are common enough to survive a one-tick delay. There is no correctness reason; it's a value-density optimization.

### 16.3 · Advanced (writing your own automation)

**What you should understand:**

- Why per-frame budgets matter more than per-call throttling.
- Why `pcall` is not a substitute for correctness — it's a substitute for crash resilience.
- The difference between a state machine and a callback chain.
- How to profile a Roblox script without an external profiler.

**Third exercise.** Open `main.lua`. Read `runTick`. The scheduler uses three guard conditions before running a loop: priority threshold, budget threshold, and due-time. Remove the budget check temporarily and observe what happens on a heavy frame. Why does the scheduler still not stall?

**Quiz:** `Perf.avg_dt` uses an exponential moving average with `alpha = 0.1`. Why 0.1 and not 0.5 or 0.01?

Answer: 0.1 means roughly the last 10 frames dominate the average. A higher alpha (0.5) would react too fast to single-frame spikes and cause the scheduler to oscillate. A lower alpha (0.01) would react too slowly and take ~100 frames to notice a sustained frame-rate drop. 0.1 balances responsiveness against stability.

### 16.4 · Senior (auditing, optimizing, hardening)

**What you should look at:**

- Every `pcall` in the codebase: is it masking a bug?
- Every loop with a `task.wait()`: is it yielding too often or too rarely?
- Every mutable global in `St`: is it written from more than one module?
- Every `Instance:FindFirstChild` at hot-path call sites: is it cached?

**Fourth exercise.** Find every place where `St.hotbarHolder` is read or written. The mutex protects hotbar access from `attack.lua`, `quests.lua`, and `hotbar.lua`. Draw the contention graph. Where is the shortest path that could deadlock?

Answer hint: the deadlock risk is `attack.lua` holding the mutex while waiting for a resource that another module holds. Verify with grep — the answer is that there is currently no deadlock because no module acquires two mutexes at once. Document this invariant in the code so a future contributor doesn't break it.

**Quiz:** `H.acquire` sets a timeout (default 1.0 second). If a caller holds the mutex longer than the timeout, the next `acquire` succeeds and both callers think they hold the mutex. Where is this mitigated?

Answer: the mitigation is social, not technical. Callers are expected to release before their timeout expires. There is no enforcement. A production-grade version would require a monotonic token per acquire and reject stale releases. This is a known limitation.

### 16.5 · Proofs and invariants

**Invariant 1:** No module reads `St.hotbarHolder` directly. All access goes through `H.isLocked()` or `H.acquire()`. This is verified by grep — no direct field accesses exist outside `hotbar.lua`.

**Invariant 2:** Every `Instance.new` call sets `Parent` last. This is a Roblox performance convention — setting `Parent` triggers replication and property-change callbacks; the rest of the setup should be done before that.

**Invariant 3:** The scheduler's `used` accumulator never exceeds `budget * 2`. Proof: the loop breaks when `used > budget` for priority > 1. Priority 1 loops can exceed budget, but there are at most 3 of them, and each has a hard time cap via the frame's own `dt`.

### 16.6 · Prediction exercises

The project maintains a code audit with open findings. Two examples are worth studying because they represent common patterns.

**Finding H-01.** "Retreat watchdog fires but does not reset the cooldown." A watchdog cleared `S.retreating = true` but left `S.retreatCooldownUntil` in the future. Prediction: the player would idle for the remaining cooldown. The fix is one line: set `S.retreatCooldownUntil = 0` alongside the state clear.

**Finding M-08.** "`antiWarp` fires on own teleports." The spoofer detected a position jump and treated it as a server-induced warp, damping velocity. Prediction: the spoofer would fight the script's own movement. The fix is a grace window: ignore jumps within 300ms of a known teleport.

Both patterns show up elsewhere. When you see a watchdog, check whether it clears all related state. When you see a detector, check whether it distinguishes self-caused events from external ones.

---

## 17 · FAQ

**Is this detectable?**
Yes. Every client-side automation is detectable in principle. The question is whether the specific game implements the specific check. Project Slayers 2 has banned accounts before. Assume yours could be next.

**Can I run this on my main?**
You can. You will regret it eventually. The author will not help you recover.

**Why does the scheduler slow down on mobile?**
Because it's adaptive. At 30 FPS, the backoff multiplies all loop intervals by ~1.5x. This keeps the game playable at the cost of slower reaction time.

**Why does the farm platform exist?**
Because M1 registration requires a stable ground reference. Hovering without a platform caused missed M1s in early testing. The platform is invisible and non-colliding with anything except the player.

**Why `SyneroxFarmPlatform` was renamed to a random hash?**
Because the literal name matched a keyword in Project Slayers 2's anti-cheat scanner. The rename makes the platform unidentifiable by name.

**What is `setthreadidentity(2)` and why does it matter?**
It elevates the calling thread to the identity level that game modules run at, so `require`'d modules accept calls without the usual sanity checks. Only Synapse-class executors expose it. The skill-firing code has a four-tier fallback so it works without this.

**Ko-fi?** Already mentioned 23 times. This one does not count.

---

## 18 · Community data license

This is a friendly license for anyone who wants to use the data in this guide — not the code. The code has its own license in the repository. This one is about the *knowledge*.

**You may:**

- Copy any code example from this guide into your own project, with attribution.
- Translate this guide into another language and publish it, with attribution and a link back.
- Use the platform guides in tutorials, classes, or workshops, with attribution.
- Quote from this guide in papers, articles, or blog posts, with attribution.
- Modify and extend the guide for your own purposes, with attribution.

**You may not:**

- Claim authorship of this guide or any substantial portion of it.
- Sell this guide as a standalone product.
- Remove attribution from any copy or derivative.
- Use this guide to justify unauthorized access to systems you do not own.
- Use this guide to harass, dox, or harm any individual.

**Attribution means:** a clear mention of "Dingus-Slayer · USAGE" and, where practical, a link to the repository. If you are redistributing in a format where links are not practical, the name is sufficient.

**No warranty.** This guide is provided as-is. The author is not responsible for what you do with the information, or for any consequences of running the software described in it. See the main LICENSE for full terms.

**In spirit:** if you learn from this, teach someone else. If you build something with this, show it. If you have a platform, use it kindly. That is the whole point.

And the **Ko-fi** is at **https://ko-fi.com/violentsadastic** if you want to support the work. This is not a legal requirement — it is a friendly invitation. There is no obligation. It is only mentioned because the author is the kind of person who names their project "Dingus-Slayer" and then writes a 20-page guide for it, and such a person appreciates coffee.

---

## 19 · Credits

**Primary author:** PurpleXPurple
**Co-development:** DeepSeek
**Inspired by:** Synerox hub (farm platform pattern, quest pipeline structure), the open-source Roblox exploit community (input abstraction patterns), and every person who posted a clear error message on a forum at 3am so the next person could search it.

**Version history** is maintained in [CHANGELOG.md](CHANGELOG.md).
**Architecture reference** is in [README.md](README.md).
**Audit findings** are in [Code_Audit.md](Code_Audit.md).

**Ko-fi:** **https://ko-fi.com/violentsadastic**. Thank you for reading.

---

*End of USAGE.md · last modified 2026-10-05.*
