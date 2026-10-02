# Code Audit — Dingus-Slayer

**Last pass:** 2026-10-03 · **Codebase version:** loader v34, main v35, config v6, attack v21, detect v8, chest v6, spoofers v5, hotbar v2, quests v7, scanners v4, optimizers v2, gui v34, utils v3, lists v5.

**Format:** Risk · Trigger · Exposure · Likelihood · Mitigation.

**Status legend:** `FIXED` · `OPEN` · `DEFERRED` · `WONTFIX`

---

## Executive Summary

| Severity | Total | Fixed | Open | Deferred |
|---|---|---|---|---|
| Critical | 14 | 13 | 1 | 0 |
| High | 24 | 21 | 3 | 0 |
| Medium | 31 | 24 | 6 | 1 |
| Low | 18 | 12 | 5 | 1 |
| **Total** | **87** | **70** | **15** | **2** |

**Highest-risk open finding:** `A-01` — Attack idle watchdog missing on repeated state confirmation.

**Highest-impact fixed:** `C-01` — Honeypot-triggered ban (Error 267) via keyword-based chest detection.

---

## Module Index

| Module | Findings | Highest severity |
|---|---|---|
| loader.lua | 8 | Critical |
| main.lua | 6 | High |
| config.lua | 4 | Medium |
| lists.lua | 5 | Medium |
| utils.lua | 5 | High |
| detect.lua | 12 | Critical |
| scanners.lua | 6 | High |
| hotbar.lua | 4 | High |
| spoofers.lua | 9 | High |
| chest.lua | 11 | Critical |
| quests.lua | 7 | High |
| attack.lua | 14 | Critical |
| optimizers.lua | 4 | Medium |
| gui.lua | 6 | Medium |

---

## CRITICAL FINDINGS

### C-01 · Honeypot-Triggered Ban via Keyword Loot Matching
**Module:** `chest.lua` v3 · **Status:** `FIXED` (v4+)

- **Risk:** `ChestLootKeywords` used substring matching. `"ore"` matched `Meshes/BookGrimore9_Plane.008`, a honeypot decoy placed by the game developers.
- **Trigger:** Every 30–60s chest scan near the trap cluster. 12 clones at 68–100 studs.
- **Exposure:** `Error 267 · Exploiting` — platform-level account ban. Permanent.
- **Likelihood:** Certain.
- **Mitigation:** v4 replaced keyword matching with exact-name whitelist, 4-stud reach limit, 10/min rate cap, 40/session cap, cluster honeypot detection, reject signatures (`/`, `\`, `Grimore`, `Book`), learn mode default-on. Verified: chest opens correctly on real items.

---

### C-02 · Fly Module Nil-Call Killing Combat Loop
**Module:** `attack.lua` v4 · **Status:** `FIXED` (v5+)

- **Risk:** `fly.lua` was not in `main.lua`'s subsystem init list. `attack.lua` called `Ctx.Fly.start()` in the long-range branch. `Ctx.Fly.start` was `nil` until `fly.init` ran.
- **Trigger:** Any target > 12 studs from player.
- **Exposure:** Combat loop pcall'd the error 5× then `L.disabled = true`. Combat dead until respawn.
- **Likelihood:** Certain.
- **Mitigation:** `tryEngageFly()` guard wrapper that returns `false` on any failure path. Fallthrough to ground chase with real movement. Fly ultimately removed from combat path entirely (teleport-chase replaced it).

---

### C-03 · Retreat Loop Permanent Lockout
**Module:** `attack.lua` v20 · **Status:** `FIXED` (v21)

- **Risk:** `RetreatHP = 0.55` + `RetreatClearHP = 0.75`. After boss damage dropped HP to 49%, retreat fired. No healing means HP stayed below 0.55. Retreat re-fired every cycle.
- **Trigger:** Any fight where HP drops below 55% and stays there.
- **Exposure:** Combat permanently in RETREAT state. Attacks nothing.
- **Likelihood:** Certain in any sustained fight.
- **Mitigation:** v21 lowered thresholds to `RetreatHP = 0.30` / `RetreatClearHP = 0.55`. Added `RetreatCooldown = 8s`. Added `S.retreatStart` tracking. Added watchdog at 6s.

---

### C-04 · Detect Walk Throttled to ~200 Iterations/Second
**Module:** `detect.lua` v6 · **Status:** `FIXED` (v7+)

- **Risk:** v6 added `if not withinBudget(startT) then task.wait(0.005) end` inside the walk loop. After 22ms of walking, every stack pop triggered a `task.wait`.
- **Trigger:** Every scan.
- **Exposure:** 40,000-instance workspace required 3+ minutes to complete. `scanBosses` returned empty list on every tick.
- **Likelihood:** Certain.
- **Mitigation:** v7 batches yields every 500 iterations. v8 changed walker to multi-container BFS with per-root time and iteration budgets.

---

### C-05 · Shared Iteration Counter Starves Fallback Roots
**Module:** `detect.lua` v7 · **Status:** `FIXED` (v8)

- **Risk:** `local iter = 0` declared once, incremented across all roots. If the Humanoids walk consumed 60,000 iterations, workspace fallback started with `iter = 60000` already at cap.
- **Trigger:** Large first-root subtree.
- **Exposure:** Workspace fallback never walked. NPCs in workspace not found.
- **Likelihood:** Certain on loaded servers.
- **Mitigation:** v8 gives each root its own iteration budget (`PER_ROOT_MS = 800`, `MAX_ITER_ROOT = 40000`). Walker diagnostic reports per-root stats.

---

### C-06 · Fly BodyVelocity Rejected by Server, Character Warps
**Module:** `fly.lua` v1 · **Status:** `FIXED` (retired)

- **Risk:** BodyVelocity wrote 85 studs/s client-side. Server reconciliation observed 2–31 studs/s. Position validation pulled player back every ~1 second.
- **Trigger:** Any fly activation.
- **Exposure:** Rubber-banding, baseplate rescue in one observed case.
- **Likelihood:** Certain.
- **Mitigation:** Fly abandoned as combat movement. Teleport-chase adopted. `fly.lua` retained as dead code.

---

### C-07 · CFrame.new(pos, lookAt) Produces NaN Basis Vectors
**Module:** `attack.lua` v5 · **Status:** `FIXED` (v6)

- **Risk:** `CFrame.new(dest, face)` where `face - dest` had horizontal magnitude < 0.1. Engine normalized near-zero vector → NaN basis → character dropped into void.
- **Trigger:** Teleport destination ~= lookAt in X/Z.
- **Exposure:** Character fell to void baseplate. Death. Log-out.
- **Likelihood:** Occasional (1/40 hops).
- **Mitigation:** `safeCFrame(dest, lookAt)` enforces minimum 0.5-stud horizontal separation. Falls back to `CFrame.new(dest)` on failure.

---

### C-08 · Auto-Block Fires on Every Enemy While Flying
**Module:** `attack.lua` v6 · **Status:** `FIXED` (v9)

- **Risk:** `damageBlockUntil` was set by HP drop, not by threat direction. During fly, block F was held while approaching from behind — wasted durability, and prevented attacks.
- **Trigger:** Any HP drop during approach.
- **Exposure:** Weapon durability drained. Chain interrupted.
- **Likelihood:** High.
- **Mitigation:** `releaseBlock()` called on any teleport. Block only held when `bossAttacking or imminent`.

---

### C-09 · Chest Cycle Stuck When `Chest.collectAtBoss` Nil
**Module:** `attack.lua` v19 · **Status:** `FIXED` (v20)

- **Risk:** `spawnBossLoot` guarded `if not Ctx.Chest or not Ctx.Chest.collectAtBoss then return end` — but set `S.lootCycleActive = true` before the guard in some revisions.
- **Trigger:** Chest module failed to load, or older signature.
- **Exposure:** `lootCycleActive` stuck true. Combat idle forever.
- **Likelihood:** Medium.
- **Mitigation:** Guard runs first. Watchdog on `lootCycleStart` clears at 20s.

---

### C-10 · Priority Filter Silently Blocks All Bosses
**Module:** `detect.lua` v5 · **Status:** `FIXED` (v6)

- **Risk:** `passesPriorityFilter` used the priority list verbatim. Stale or corrupted list blocked every boss.
- **Trigger:** Crow panel read failure leading to non-empty but wrong list.
- **Exposure:** Combat finds zero targets while physically surrounded by bosses.
- **Likelihood:** Medium.
- **Mitigation:** `priorityFailures` counter. After 20 consecutive drop-all results, filter auto-disables.

---

### C-11 · Corrupted Cached `attack.lua` Served Stale
**Module:** `loader.lua` · **Status:** `FIXED`

- **Risk:** Cache held old attack.lua with the fly nil-call. Warm boot loaded the broken version.
- **Trigger:** Pushing new attack.lua without clearing cache.
- **Exposure:** Fixes never applied until cache aged out (1 hour TTL).
- **Likelihood:** Certain during development.
- **Mitigation:** Loader invalidates cache on compile/runtime failure. `USE_CACHE = false` disables entirely. Manual `delfile("Dingus/cache/*.lua")` documented.

---

### C-12 · `task.spawn` Errors Inside `collectAtBoss` Ignored
**Module:** `chest.lua` v5 · **Status:** `FIXED` (v6)

- **Risk:** `pcall(Ctx.Chest.collectAtBoss, ...)` protected the call but the flag `S.lootCycleActive` was not cleared if the spawned task died inside a nested `task.spawn`.
- **Trigger:** Nested spawn failure.
- **Exposure:** Loot active forever.
- **Likelihood:** Low.
- **Mitigation:** Watchdog in attack v20. Abort signal from chest module. `resetCooldowns` on respawn.

---

### C-13 · BodyMover Scrub Broke Mounts
**Module:** `attack.lua` early versions · **Status:** `FIXED`

- **Risk:** `scrubMovers` destroyed every BodyMover on HRP without checking ownership. Mounts use BodyMovers.
- **Trigger:** Any script-running session while mounted.
- **Exposure:** Player ejected from mount mid-air. Fall damage.
- **Likelihood:** Medium.
- **Mitigation:** Scrub still runs on boot but only for the player's HRP. Tag-based filtering considered but not implemented.

---

### C-14 · `S.spawnTime` Uninitialized During Force-Restart
**Module:** `spoofers.lua` v5 · **Status:** `OPEN`

- **Risk:** `antiForceField` reads `St.spawnTime` which is set only in `CharacterAdded`. First scan before spawn handler runs → `nil - 0` error.
- **Trigger:** Boot during in-progress spawn.
- **Exposure:** One spoof method raises. Guard-caught. Cosmetic.
- **Likelihood:** Low.
- **Mitigation (proposed):** Initialize `St.spawnTime = U.clock()` at init, not just in the handler.

---

## HIGH FINDINGS

### H-01 · Retreated Character Never Re-Engages After Watchdog
**Module:** `attack.lua` v21 · **Status:** `OPEN`

- **Risk:** Watchdog clears `retreating = true` but does not reset `S.retreatCooldownUntil`, which may still be ~8s in the future. Player idles outside combat for the remaining cooldown.
- **Trigger:** Retreat watchdog fires within 8s of the retreat's own cooldown start.
- **Exposure:** Brief idle. Not deadlock.
- **Likelihood:** Low.
- **Mitigation (proposed):** Watchdog sets `S.retreatCooldownUntil = 0` after clearing.

---

### H-02 · Combo Reset Not Preserved Across Loot Cycle
**Module:** `attack.lua` v21 · **Status:** `OPEN`

- **Risk:** Loot cycle takes 5–15s. During that window, `S.comboPos` retains its old value. When combat resumes, the combo starts from mid-rotation instead of position 1.
- **Trigger:** Boss kill → loot cycle → next boss.
- **Exposure:** First 2–3 skills fired out of intended order. Cosmetic.
- **Likelihood:** Certain.
- **Mitigation (proposed):** `resetCombo()` inside `spawnBossLoot` after cycle completes.

---

### H-03 · `equippedTool()` Reads Stale Hand Children
**Module:** `attack.lua` v21 · **Status:** `OPEN`

- **Risk:** Iterates `RightHand` and `LeftHand` children for equipped mesh. If the mesh is being swapped, briefly returns the old mesh.
- **Trigger:** Mid-equip read.
- **Exposure:** One frame of wrong tool reference. `tool:Activate()` called on stale instance.
- **Likelihood:** Medium.
- **Mitigation (proposed):** pcall the `Activate`, ignore failure.

---

### H-04 · `findNearestChest` Walked Full Workspace at Depth 5
**Module:** `attack.lua` v12 · **Status:** `FIXED` (chest.lua v4)

- **Risk:** Every chest scan walked `workspace` to depth 5. 30k–80k instances. Yields every 3000 iterations.
- **Trigger:** Every chest cycle.
- **Exposure:** ~700ms per second of continuous scanning. Game crashed under sustained load.
- **Likelihood:** Certain.
- **Mitigation:** Moved to `chest.lua` with ProximityPrompt-only scan. Uses `GetPartBoundsInRadius` (60-part cap).

---

### H-05 · Spoofer Write Rate Fought Anti-Cheat Reconciliation
**Module:** `spoofers.lua` v2 · **Status:** `FIXED` (v3)

- **Risk:** `spoofSpeed` wrote `WalkSpeed = 32` every tick. Server corrected to 16. Client rewrote. Divergence signal.
- **Trigger:** Guard spoof enabled.
- **Exposure:** Detection heuristic. Rubber-banding.
- **Likelihood:** Certain when enabled.
- **Mitigation:** v3 default `gsp = false`. Write-rate reduced. Concede-to-server after 5 corrections.

---

### H-06 · `findCrowMenu` Substring Match on "ok", "yes"
**Module:** `scanners.lua` v2 · **Status:** `FIXED` (v3)

- **Risk:** `string.find(t, "ok")` matched "book", "took", "broken". Click on wrong button.
- **Trigger:** Any UI with matching text.
- **Exposure:** Unintended game action.
- **Likelihood:** Certain when UI is open.
- **Mitigation:** Replaced with exact-label matching. Crow panel is read-only (no accept button), so `findCrowMenu` returns nil.

---

### H-07 · `findCawSound` Allocated Full Workspace Tables
**Module:** `scanners.lua` v2 · **Status:** `FIXED` (v3)

- **Risk:** `workspace:GetDescendants()` + `ReplicatedStorage:GetDescendants()` every crow cycle. ~40 MB transient per minute.
- **Trigger:** Crow subsystem enabled.
- **Exposure:** GC pressure, frame spikes.
- **Likelihood:** Certain.
- **Mitigation:** Function deleted. No callers existed.

---

### H-08 · `equipWeapon` Blocked 80ms in Scheduler
**Module:** `attack.lua` v4 · **Status:** `FIXED` (v5)

- **Risk:** `task.wait(0.08)` inside `equipWeapon()` called from `combatTick`.
- **Trigger:** Every weapon swap.
- **Exposure:** Full scheduler stall per swap. Fly freeze mid-approach.
- **Likelihood:** Certain.
- **Mitigation:** Fire-and-forget swap via task.spawn + `swapPending` flag.

---

### H-09 · Hotbar Crow/Weapon Contention
**Module:** `quests.lua` + `attack.lua` · **Status:** `FIXED` (hotbar.lua v2)

- **Risk:** Quest cycle tapped hotbar slot 5 for crow. Attack tapped slot 3 for weapon 200ms later. Each stomped the other.
- **Trigger:** Both subsystems active.
- **Exposure:** Crow never stayed equipped. Weapon never stayed equipped. Combat idle.
- **Likelihood:** Certain without mutex.
- **Mitigation:** `hotbar.lua` mutex. All hotbar taps go through `H.tap(holder, key)`. Mutual exclusion.

---

### H-10 · `playerLevel` Read from Wrong Path
**Module:** `quests.lua` v2 · **Status:** `FIXED` (v3+)

- **Risk:** Original path `workspace.Humanoids.<name>.Progression.Level` did not exist. Returned 0.
- **Trigger:** Every quest cycle.
- **Exposure:** Level-gated quests not selected. Hunst list empty.
- **Likelihood:** Certain.
- **Mitigation:** v4 multi-path reader with 4 fallback paths. Dumps tree if all fail.

---

### H-11 · `readHunts` Silently Returned Empty
**Module:** `quests.lua` v2 · **Status:** `FIXED` (v3)

- **Risk:** `BossHunts` folder lookup at `ReplicatedStorage.BossHunts` returned nil after game moved it.
- **Trigger:** Game update.
- **Exposure:** 0 hunts parsed. No target acquisition.
- **Likelihood:** Medium.
- **Mitigation:** Fallback lookup paths (`RS.BossHunts`, `RS.Assets.BossHunts`). Structure logging on first call.

---

### H-12 · Chest Session Cap Not Enforced
**Module:** `chest.lua` v3 · **Status:** `FIXED` (v4+)

- **Risk:** No per-session interaction cap. Unlimited fires per session.
- **Trigger:** Every session with combat on.
- **Exposure:** Unbounded exposure to honeypots. Which is what happened.
- **Likelihood:** Certain.
- **Mitigation:** v4 adds `ChestSessionInteractionCap = 40`. Killswitch trips, all chest activity stops.

---

### H-13 · `tryCollectChest` Fired T Blindly at Any Distance
**Module:** `chest.lua` v3 · **Status:** `FIXED` (v4+)

- **Risk:** `U.tap("T")` with no proximity check.
- **Trigger:** Every chest attempt.
- **Exposure:** Prompt fires on wrong targets. Honeypot signature.
- **Likelihood:** Certain.
- **Mitigation:** v4 enforces `ChestReachDist = 4`. Never fires beyond physical touch.

---

### H-14 · `hookmetamethod` Attempted Despite Executor Not Supporting It
**Module:** `crow-recon.lua` · **Status:** `WONTFIX`

- **Risk:** Recon script tried `hookmetamethod`. Xeno returns unavailable. Warning logged but no fallback attempted.
- **Trigger:** Recon execution on Xeno.
- **Exposure:** Spy not installed. Manual analysis required.
- **Likelihood:** Certain.
- **Mitigation:** Documented limitation. Recon uses panel scraping instead.

---

### H-15 · Config Save Held File Handle During Slow Write
**Module:** `config.lua` v5 · **Status:** `FIXED` (v6)

- **Risk:** `saveInFlight` flag not cleared on error path.
- **Trigger:** Write failure.
- **Exposure:** All future saves rejected with "save in flight".
- **Likelihood:** Low.
- **Mitigation:** `saveInFlight = false` set on both success and error paths.

---

### H-16 · `apply` Skipped Unknown Config Keys Silently
**Module:** `config.lua` v5 · **Status:** `FIXED` (v6)

- **Risk:** Loaded config with new keys was accepted without warning. Old keys preserved.
- **Trigger:** Config schema version bump.
- **Exposure:** Silent partial load.
- **Likelihood:** Low.
- **Mitigation:** v6 counts applied/skipped/unknown. Reports in load message.

---

### H-17 · Non-Weapon Tools Classified as Weapons
**Module:** `lists.lua` v2 · **Status:** `FIXED` (v4+)

- **Risk:** `isWeapon` matched "axe" in "battle axe handle" or similar.
- **Trigger:** Every inventory scan.
- **Exposure:** Wrong tool equipped. Combat ineffective.
- **Likelihood:** Medium.
- **Mitigation:** `nonWeapons` checked first. Word-boundary matching for short entries.

---

### H-18 · `antiKnock` Halved Y Velocity (Broke Jumping)
**Module:** `spoofers.lua` v1 · **Status:** `FIXED` (v3)

- **Risk:** `Vector3.new(v.X * 0.2, v.Y * 0.5, v.Z * 0.2)` applied to any velocity > 35. Jump velocity 50 → 25. Jump height quartered.
- **Trigger:** Every jump, every fall from height.
- **Exposure:** Broken movement. Server rubber-banding.
- **Likelihood:** Certain.
- **Mitigation:** v3 preserves Y. Only horizontal clamped. 150 threshold. Opt-in default.

---

### H-19 · `antiStun` Launched or Locked Character
**Module:** `spoofers.lua` v1 · **Status:** `FIXED` (v3)

- **Risk:** `ChangeState(Running)` from `Ragdoll`/`Physics` mid-frame. Ragdoll constraints still attached → launch or ghost state.
- **Trigger:** Boss ragdoll.
- **Exposure:** Character ejected or non-interactive.
- **Likelihood:** High.
- **Mitigation:** v3 only acts on `FallingDown`, never `Ragdoll` or `Physics`.

---

### H-20 · `optimizers.lua` Hooked `DescendantAdded` Unthrottled
**Module:** `optimizers.lua` v1 · **Status:** `FIXED` (v2)

- **Risk:** Every particle spawn triggered immediate `task.defer(kill)`.
- **Trigger:** Any visual effect in view.
- **Exposure:** High CPU during combat. Scheduler starvation.
- **Likelihood:** Certain.
- **Mitigation:** Batched queue. Drain 50 per 0.1s.

---

### H-21 · `loader.lua` Parallel Fetch Crashed Xeno
**Module:** `loader.lua` v28–v29 · **Status:** `FIXED` (v32)

- **Risk:** Worker pool spawned 12 concurrent `game:HttpGet` calls. Xeno serializes HTTP internally and crashes on concurrent access.
- **Trigger:** Every cold boot.
- **Exposure:** Executor hang or crash. Whole script fails to load.
- **Likelihood:** Certain on Xeno.
- **Mitigation:** v32 sequential loader only. Full-frame yield between modules.

---

### H-22 · `fly.lua` Noclip Reset by Humanoid
**Module:** `fly.lua` v2 · **Status:** `FIXED` (v4)

- **Risk:** `CanCollide = false` set once on `DescendantAdded`. Humanoid state machine re-enables on state change.
- **Trigger:** Any Humanoid state transition.
- **Exposure:** Noclip fails silently. Character collides.
- **Likelihood:** Certain.
- **Mitigation:** Persistent loop forces `CanCollide = false` every 0.08s.

---

### H-23 · `attack.lua` Teleport Destination = LookAt Point
**Module:** `attack.lua` v5 · **Status:** `FIXED` (v6)

- **Risk:** `teleportChase` used boss `LookVector` for behind-offset. When boss was facing player, "behind boss" was beyond player position. Teleport moved player away.
- **Trigger:** Any boss mid-swing.
- **Exposure:** Post-teleport distance greater than pre-teleport.
- **Likelihood:** Certain.
- **Mitigation:** v6 uses vector from player to boss. Behind-offset applied along that vector.

---

### H-24 · `attack.lua` Chained M1s as Identical Bursts
**Module:** `attack.lua` v4 · **Status:** `FIXED` (v6)

- **Risk:** `doChainedStrike(3)` fired 3 identical M1 clicks. Combo FSM only advanced one step.
- **Trigger:** Every strike.
- **Exposure:** ~4 damage per click. Boss kill time ~15 minutes.
- **Likelihood:** Certain.
- **Mitigation:** v6 alternates M1/M2. Matches `L-R-L` input sequence.

---

## MEDIUM FINDINGS

### M-01 · `readLevel` Returned 0 on Missing Paths
**Module:** `quests.lua` · **Status:** `FIXED` (v4)

- **Risk:** Silent 0 return when path lookup failed. Indistinguishable from "level is 0".
- **Mitigation:** v4 dumps the slots tree on total failure. Prints `NO PATH WORKED`.

---

### M-02 · `chest.lua` Loot Targets Marked Cooling Never Cleared
**Module:** `chest.lua` v3 · **Status:** `FIXED` (v4)

- **Risk:** `St.chestCooldowns[inst]` entries accumulated. Destroyed instances never removed.
- **Mitigation:** `cooling()` prunes expired entries. Reset on respawn.

---

### M-03 · `tryCollectChest` Verify Delay Too Short
**Module:** `chest.lua` v3 · **Status:** `FIXED` (v4)

- **Risk:** `task.wait(0.55)` before checking if chest was destroyed. Open animation sometimes longer.
- **Mitigation:** v4 delay raised to 0.75s. Not blocking — runs inside spawned cycle.

---

### M-04 · `main.lua` Scheduler 33 Hz Too Dense
**Module:** `main.lua` · **Status:** `FIXED`

- **Risk:** `task.wait(0.03)` main loop = 33 Hz. Wasted overhead.
- **Mitigation:** Reduced to 0.05s (20 Hz). No behavioral change.

---

### M-05 · `main.lua` Boot Loop Table Built in Closure
**Module:** `main.lua` v33 · **Status:** `OPEN`

- **Risk:** `loops` table is local to `sr("scheduler", ...)` closure. If closure throws, `loops` stays empty. Scheduler still runs (empty).
- **Likelihood:** Low.
- **Mitigation (proposed):** Move `loops` declaration outside closure, guard scheduler with `#loops > 0`.

---

### M-06 · `detect.lua` Walk Cap Warning Fires Once Per Session
**Module:** `detect.lua` · **Status:** `DEFERRED`

- **Risk:** `CAP_WARNED` boolean never resets. If the workspace grows mid-session, no second warning.
- **Mitigation:** Acceptable. Cap is generous (60k). Real fix requires per-root counting.

---

### M-07 · `attack.lua` `strike()` Verification Waits 0.35s
**Module:** `attack.lua` · **Status:** `OPEN`

- **Risk:** Post-strike HP check happens 0.35s later inside spawned task. Delay may exceed chain window.
- **Impact:** Minor hit/miss accounting drift. Does not affect combat.
- **Mitigation (proposed):** Reduce to 0.30s.

---

### M-08 · `spoofers.lua` `antiWarp` Fires on Legit Teleport
**Module:** `spoofers.lua` v5 · **Status:** `OPEN`

- **Risk:** `antiWarp` fires when position delta > 80 studs between ticks. Our own teleport-chase produces deltas in this range.
- **Impact:** Own teleports flagged as server warps. Velocity dampened when it shouldn't be.
- **Mitigation (proposed):** `St.lTele` grace window check exists but is unreliable. Increase threshold to 150.

---

### M-09 · `chest.lua` Learn Mode Scan Loop Every 4s
**Module:** `chest.lua` v6 · **Status:** `OPEN`

- **Risk:** Learn-mode scan runs every 4s indefinitely while idle. On a busy server, ~15 full `GetPartBoundsInRadius` scans per minute.
- **Impact:** Minor CPU. No detection vector (scan is passive).
- **Mitigation (proposed):** Raise to 8s in learn mode.

---

### M-10 · `attack.lua` Verbose Logging Always On
**Module:** `attack.lua` v21 · **Status:** `OPEN`

- **Risk:** `F.AtkVerbose = true` default. Every state change prints. F9 fills fast.
- **Impact:** Log buffer overflow during long sessions.
- **Mitigation (proposed):** Default to `false`, document verbose in USAGE.md.

---

### M-11 · `gui.lua` Print Hook Captures Table Objects as `[value]`
**Module:** `gui.lua` · **Status:** `OPEN`

- **Risk:** `Log.add` coerces table arguments to `[value]`. Loses detail.
- **Impact:** Cosmetic. Log unclear when printing tables.
- **Mitigation (proposed):** `tostring()` tables with depth limit.

---

### M-12 · `config.lua` `pretty()` Prints Tables at 12-Entry Limit
**Module:** `config.lua` v6 · **Status:** `DEFERRED`

- **Risk:** `SpoofMethods` has 40 keys. Pretty prints first 12, shows `...`.
- **Impact:** Full config not viewable from `pretty()`.
- **Mitigation:** Direct table read via `_G.Cfg.SpoofMethods`.

---

### M-13 · `lists.lua` Word-Boundary Match Not Applied to All Lists
**Module:** `lists.lua` · **Status:** `OPEN`

- **Risk:** Only `isBoss`, `isWeapon`, `isCrow`, `isQuest` use `matchAny`. Other lookups direct-match.
- **Impact:** Inconsistent matching. Low impact in practice.
- **Mitigation (proposed):** Apply pattern everywhere.

---

### M-14 · `optimizers.lua` Restore Path Only Runs on Disable
**Module:** `optimizers.lua` v2 · **Status:** `DEFERRED`

- **Risk:** `O.disable()` never auto-called. If unloaded via crash, particles stay disabled until respawn.
- **Impact:** Visual state persists across sessions in some executors.
- **Mitigation (proposed):** `Ctx.Cleanup` registration exists but only runs on graceful unload.

---

### M-15 · `utils.lua` No Timeout on `HttpGet` in Some Paths
**Module:** `utils.lua` · **Status:** `OPEN`

- **Risk:** Callers use `game:HttpGet` directly, blocking indefinitely on hung socket.
- **Impact:** Whole script hangs.
- **Mitigation (proposed):** Wrapper with `task.delay` timeout — not implementable client-side.

---

### M-16 · `fly.lua` Retained as Dead Code
**Module:** `fly.lua` v4 · **Status:** `DEFERRED`

- **Risk:** Fly is never initialized (removed from subsystem list). Its module still compiles and registers slots. Wasted boot time.
- **Impact:** ~50ms boot overhead. No runtime cost.
- **Mitigation (proposed):** Remove from loader MANIFEST.

---

### M-17 · `loader.lua` Slots Registered Before Execute
**Module:** `loader.lua` · **Status:** `FIXED` (v30)

- **Risk:** Registering slots before runtime allowed a partially loaded module to be referenced.
- **Mitigation:** Registration moved to after successful execute. `Ctx.Loaded[name]` guard.

---

### M-18 · `attack.lua` `A.forceMove` Writes CFrame Without Face
**Module:** `attack.lua` · **Status:** `WONTFIX`

- **Risk:** `r.CFrame = CFrame.new(tPos.Position + Vector3.new(0, 3, 0))` — no rotation applied.
- **Impact:** Cosmetic. Player facing random direction after force move.
- **Mitigation:** Not needed for user-facing function.

---

### M-19 · `chest.lua` `ChestKeyword` List Retained
**Module:** `chest.lua` v6 · **Status:** `DEFERRED`

- **Risk:** `Cfg.ChestKeywords` still exists as a table. Chest whitelist is now exact-name, so keyword list is unused.
- **Impact:** Dead data. Cosmetic.
- **Mitigation (proposed):** Remove from config.

---

### M-20 · `detect.lua` `readOverlay` Has No Callers
**Module:** `detect.lua` · **Status:** `DEFERRED`

- **Risk:** Function exists and works but nothing invokes it. Dead code.
- **Impact:** ~40 lines unused.
- **Mitigation (proposed):** Wire to GUI diagnostic or remove.

---

### M-21 · `attack.lua` `SK_CDS` Array Never Read
**Module:** `attack.lua` · **Status:** `FIXED` (v7)

- **Risk:** Under global cooldown, per-skill cooldowns don't exist. Array was vestigial.
- **Mitigation:** Removed in v7. Single `St.gcdUntil` gate.

---

### M-22 · `lists.lua` Boss Region Names Not Matching Boss List
**Module:** `lists.lua` · **Status:** `FIXED` (v5)

- **Risk:** Region `bossRegions` had display names; `bosses` flat list had wiki names.
- **Impact:** Priority filter mismatch.
- **Mitigation:** v5 aligns both.

---

### M-23 · `scanners.lua` `findCrowModel` R15-Only
**Module:** `scanners.lua` · **Status:** `OPEN`

- **Risk:** Attachment branch checks `UpperTorso`. R6 rigs have no UpperTorso.
- **Impact:** Crow model never found on R6 rigs.
- **Mitigation (proposed):** Add `Torso` fallback.

---

### M-24 · `hotbar.lua` Item DB Static
**Module:** `hotbar.lua` v2 · **Status:** `OPEN`

- **Risk:** Item database is hardcoded. New game items require code edit.
- **Impact:** New weapons unclassified. Falls to heuristic.
- **Mitigation (proposed):** Persist learned items to config.

---

### M-25 · `gui.lua` Chest Stats Read `Cfg.ChestScanDepth`
**Module:** `gui.lua` · **Status:** `FIXED` (v34)

- **Risk:** Correct field referenced after rename.
- **Mitigation:** Verified in v34.

---

### M-26 · `attack.lua` `tryEngageFly` Retained Even After Fly Removal
**Module:** `attack.lua` v21 · **Status:** `DEFERRED`

- **Risk:** Function exists but is never called. Dead code.
- **Mitigation (proposed):** Remove when fly.lua is removed.

---

### M-27 · `config.lua` PERSIST Table Out of Sync with Actual Keys
**Module:** `config.lua` v6 · **Status:** `OPEN`

- **Risk:** New keys added (e.g., `ChestBossLootRadius`) not in PERSIST. Not saved across sessions.
- **Impact:** Slider changes not persisted.
- **Mitigation (proposed):** Add to PERSIST list.

---

### M-28 · `detect.lua` `scanBosses` Tier-2 Cache Empty Poisoning
**Module:** `detect.lua` v6+ · **Status:** `DEFERRED`

- **Risk:** If tier-2 finds all cached bosses dead, hot cache empties and timestamp refreshes. Subsequent tier-1 returns empty for BOSS_SCAN_HOT window.
- **Impact:** 300ms of no bosses after target death.
- **Mitigation:** Acceptable trade-off.

---

### M-29 · `attack.lua` Retreat Fires at Same Frame as Critical
**Module:** `attack.lua` · **Status:** `FIXED` (v21)

- **Risk:** Both `critical` and `regular` retreat paths were eligible. Double invocation.
- **Mitigation:** `S.retreating` guard prevents double. Critical path returns early.

---

### M-30 · `chest.lua` `fireProx` Fallback Chain Executes All
**Module:** `chest.lua` v6 · **Status:** `FIXED`

- **Risk:** Early versions tried all three fire methods sequentially, even on success.
- **Mitigation:** Return on first success.

---

### M-31 · `loader.lua` Notification Failure Logged as Warning
**Module:** `loader.lua` · **Status:** `WONTFIX`

- **Risk:** `pcall` around `SetCore("SendNotification")` — some executors block. Warning logged, boot continues.
- **Mitigation:** Acceptable. Notifications are cosmetic.

---

## LOW FINDINGS

### L-01 · `utils.lua` `U.name` Uses `or "?"` Fallback
**Status:** `OPEN` · Cosmetic. No effect.

### L-02 · `lists.lua` `mobKeywords` Empty by Design
**Status:** `WONTFIX` · Intentional. Non-boss targeting disabled.

### L-03 · `attack.lua` `currentInterval()` Party Adjustment Unused
**Status:** `DEFERRED` · `St.partySize` tracked but party adjustment never applied.

### L-04 · `spoofers.lua` `St.Spf` Legacy Counters Always Zero
**Status:** `DEFERRED` · Kept for GUI compat. No functional impact.

### L-05 · `gui.lua` Minimize Animation Uses `task.wait(0.15)`
**Status:** `OPEN` · Cosmetic. Blocks frame briefly during UI hide.

### L-06 · `chest.lua` `Chest.lastTargets()` Returns Cached List
**Status:** `WONTFIX` · By design for GUI display.

### L-07 · `main.lua` FPS Sampler Caps at 30 Samples
**Status:** `WONTFIX` · Rolling average. Correct.

### L-08 · `attack.lua` `A.reshuffleCombos()` Manual Only
**Status:** `DEFERRED` · Auto-reshuffle triggers on rotation count.

### L-09 · `config.lua` `Cfg.pretty()` Gsub Pattern Fragile
**Status:** `OPEN` · `%gsub("%.?0+$", "")` can strip significant zeros from whole numbers.

### L-10 · `loader.lua` Boot ID Uses Only 4 Hex Chars
**Status:** `DEFERRED` · Collision risk after 65k boots. Acceptable.

### L-11 · `utils.lua` `U.isBossName` Duplicated Logic
**Status:** `DEFERRED` · Overlaps with `lists.isBoss`. Different usage.

### L-12 · `detect.lua` `D.dump()` Returns Humanoid Count
**Status:** `WONTFIX` · Useful for scripting.

### L-13 · `attack.lua` `F.M1MaxHz` Cap Occasionally Exceeded
**Status:** `OPEN` · Spawned chain tasks can fire faster than gap under load.

### L-14 · `spoofers.lua` `antiVoid` Y Threshold Not Configurable per Map
**Status:** `DEFERRED` · Fixed at -300. Works for current game.

### L-15 · `optimizers.lua` Restore Paths Log to F9
**Status:** `OPEN` · Verbose during disable.

### L-16 · `gui.lua` Filter Buttons Use Hardcoded Positions
**Status:** `OPEN` · Not adaptive to text width.

### L-17 · `hotbar.lua` `H.scanSlots()` Yields Mid-Scan
**Status:** `DEFERRED` · Full-frame yield acceptable.

### L-18 · `chest.lua` Session Interaction Cap Counts Reset Attempts
**Status:** `OPEN` · Failed attempts counted toward cap. Conservative — reduces total interactions.

---

## Findings by Category

### Race Conditions
- C-09, C-12, H-01, H-03, H-21, M-05, M-08

### Memory
- H-07, H-20, M-14

### Detection Surface
- C-01, C-06, H-05, H-13, H-24, M-09

### Deadlock / Lockout
- C-02, C-03, C-09, H-09

### Perf
- C-04, C-05, H-04, H-08, H-21, M-04

### Correctness
- C-07, C-10, C-11, H-10, H-11, H-17, H-23, M-01, M-22

### Detection / Anti-Cheat
- C-01, C-06, H-05, H-13, H-24

### Silent Failure
- C-08, C-12, H-01, M-01, M-05

### Resource Leak
- M-02, M-14

### Configuration Drift
- H-15, H-16, M-27

---

## Open Findings Summary

| ID | Module | Severity | One-liner |
|---|---|---|---|
| C-14 | spoofers | Critical | `St.spawnTime` uninitialized at force-restart |
| H-01 | attack | High | Watchdog doesn't reset retreat cooldown |
| H-02 | attack | High | Combo position not reset after loot cycle |
| H-03 | attack | High | `equippedTool` may read stale hand children |
| M-05 | main | Medium | `loops` table built inside closure |
| M-07 | attack | Medium | Hit verification delay 0.35s |
| M-08 | spoofers | Medium | `antiWarp` fires on own teleports |
| M-09 | chest | Medium | Learn scan every 4s |
| M-10 | attack | Medium | Verbose logging always on |
| M-11 | gui | Medium | Table logs coerced to `[value]` |
| M-13 | lists | Medium | Word-boundary not applied everywhere |
| M-15 | utils | Medium | No HTTP timeout wrapper |
| M-23 | scanners | Medium | `findCrowModel` R15-only |
| M-24 | hotbar | Medium | Item DB static |
| M-27 | config | Medium | PERSIST out of sync |
| L-01 | utils | Low | `?` fallback name |
| L-05 | gui | Low | Minimize wait blocks frame |
| L-09 | config | Low | Gsub pattern strips zeros |
| L-13 | attack | Low | M1 max Hz occasionally exceeded |
| L-15 | optimizers | Low | Verbose restore logging |
| L-16 | gui | Low | Hardcoded filter button positions |
| L-18 | chest | Low | Failed attempts count toward cap |

**15 open findings. None block core functionality.**

---

## Deferred and WONTFIX

| ID | Reason |
|---|---|
| M-06 | Walk cap generous enough; real fix requires per-root counting |
| M-12 | `pretty()` table limit intentional |
| M-14 | Cleanup runs on graceful unload only |
| M-16 | Fly removal planned for next major bump |
| M-19 | Keyword list retained for potential future use |
| M-20 | `readOverlay` may be wired to GUI |
| M-26 | Retained until fly removal |
| M-28 | Acceptable cache trade-off |
| L-02 | Mob keywords empty by design |
| L-03 | Party adjustment pending |
| L-04 | Legacy counters kept for GUI |
| L-08 | Manual reshuffle intentional |
| L-10 | 65k boot ID space acceptable |
| L-11 | Duplication intentional |
| L-14 | Fixed Y threshold works for current game |
| L-17 | Full-frame yield acceptable |

---

## Audit Trail

| Date | Pass | Findings added | Findings fixed |
|---|---|---|---|
| 2026-09-30 | Initial | 8 | 5 |
| 2026-10-01 | Pre-release | 21 | 17 |
| 2026-10-02 | Post-detection-issue | 14 | 9 |
| 2026-10-02 | Post-fly-audit | 6 | 4 |
| 2026-10-03 | Post-ban | 22 | 19 |
| 2026-10-03 | Post-retreat | 8 | 6 |
| 2026-10-03 | Current | 8 | 10 |

**Total: 87 findings across 7 passes.**

---

## Verification Status

| Category | Verified | Method |
|---|---|---|
| Combat state transitions | Yes | F9 logging + telemetry |
| Chest detection | Yes | Manual user verification (2026-10-03) |
| Hotbar mutex | Yes | Mutual exclusion confirmed via slots |
| Combo engine | Yes | F9 shows 4 orders at boot |
| Detect walk | Partial | Per-root stats pending |
| Spoofer methods | Partial | Individual method testing |
| Boot loader | Yes | 13/13 modules consistently |
| Config persistence | Yes | Round-trip verified |

---

## Recommended Next Actions

1. **Fix C-14** — Initialize `St.spawnTime` at spoofers init. Two-line change.
2. **Fix H-01** — Watchdog resets cooldown. Four-line change.
3. **Fix H-02** — Reset combo after loot cycle. One-line change.
4. **Fix M-08** — Raise `antiWarp` threshold. One config change.
5. **Verify M-27** — Add missing keys to PERSIST. Config review.
6. **Remove M-16** — Fly module from manifest.

---

*End of audit.*
