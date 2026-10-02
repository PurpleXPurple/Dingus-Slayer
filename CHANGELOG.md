# Changelog

All notable changes to Dingus-Slayer are documented here.

**Format:** [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
**Versioning:** [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
**Sections:** Added · Changed · Deprecated · Removed · Fixed · Security

Version numbers follow the pattern `MAJOR.MINOR.PATCH`. This project uses an unusual versioning scheme where **the loader carries the primary version** (currently v34) and each module carries its own minor version in a comment header. The unified project version is the loader's.

---

## [Unreleased]

### Planned

- Boss execute mechanic (G key) integration for sub-10-HP targets
- Per-slot boss blacklist after repeated failed attempts
- Persist learned hotbar items to config
- Adaptive spoof write rate based on server correction frequency
- Detect walk per-root statistics surfaced in GUI

---

## [0.34.0] — 2026-10-03

### Semver class
**Minor.** Adds HTTP header support and structured boot logging. No breaking changes.

### Added

- **HTTP headers on request() path.** `User-Agent`, `Accept`, `Accept-Language`, `Cache-Control`, `Pragma`, `Connection` all sent with every fetch. Blends request traffic into normal browser patterns at the CDN edge.
- **ETag conditional requests.** When `request()` is available, the loader stores the `ETag` from the last fetch and sends it as `If-None-Match` on subsequent boots. A `304 Not Modified` response uses the cached body with zero bytes transferred.
- **Structured boot banner.** Boot now opens with a boxed header showing session ID, timestamp, branch, module count, CDN chain length, cache state, and HTTP mode.
- **Phase dividers.** Each boot phase (`LOAD`, `BOOT`, `EXPOSE`, `NOTIFY`) is prefixed with `----- PHASE N/4 · LABEL -----`.
- **Per-module aligned log rows.** Each module load prints icon, name, source, fetch time, cache state, and note in fixed columns.
- **Slowest-fetch report.** Summary names the module with the longest fetch and which CDN served it.
- **`_G.DINGUS_BOOT`** structured result table for external scripts.

### Changed

- Loader version header updated to v34.
- Boot summary now prints aggregate fetch, compile, and execute timings.
- Cache statistics surfaced in summary (`hits`, `misses`, `stale`).

### Fixed

- Loader no longer wraps markdown content in triple backticks when printing to F9.

### Security

- HTTP headers reduce executor fingerprint at the CDN edge. No new detection surface added.

---

## [0.33.0] — 2026-10-03

### Semver class
**Minor.** Adds the Chests tab and rewires loot delegation. No breaking changes.

### Added

- **Chests tab in GUI.** Nine-tab layout now includes dedicated chest controls.
- **Learn-mode toggle in GUI.** Chest master switch, on-kill toggle, passive toggle visible from UI.
- **Collection method toggles.** ProximityPrompt, ClickDetector, Physical Key — all independently switchable from GUI.
- **Range and timing sliders.** Scan radius, scan depth, max passes, pass deadline, per-target cooldown, passive interval.
- **Chest live stats panel.** Sweep count, chests opened, loot collected, failed, skipped, active cooldowns, running state.
- **Last Scan panel.** Lists recent detected targets with kind, name, distance.

### Changed

- GUI version bumped to v34.
- `attack.lua` delegates all loot work to `Ctx.Chest`. Inline loot section removed.
- Config `ChestKeywords` list retained but no longer used for keyword matching.

### Removed

- Inline `findNearestChest` from `attack.lua`. Replaced by `Ctx.Chest.scan` and `Ctx.Chest.sweep`.

### Fixed

- GUI now updates chest stats on the standard 0.3s refresh cycle.

---

## [0.32.0] — 2026-10-03

### Semver class
**Minor.** Loader rewritten for crash safety. No breaking changes.

### Added

- **Sequential-only loader.** No worker pool, no parallel fetch. Removes Xeno crash.
- **Multi-CDN chain.** GitHub → jsdelivr → statically, tried in order per module.
- **Disk cache with TTL.** 1-hour freshness window. Stale cache used as fallback.
- **Breadcrumb tracing.** Every risky operation prefixed with `[Dingus][trace]` mark.
- **Per-module timing.** Fetch, compile, and execute durations captured per module.
- **Source release after compile.** Source string set to `nil` before executing to prevent memory double-buffering.
- **Full error detail.** Errors now print `stage — kind — detail` in one line.

### Changed

- `USE_CACHE` toggle added (default `true`).
- `MAX_RETRY` reduced to 2.
- `YIELD_EVERY` between modules is now a full-frame yield.

### Fixed

- Boot no longer hangs on concurrent HTTP access. This was the primary crash vector in v31 and earlier.

### Security

- Cache invalidation on compile or runtime failure prevents broken module persistence.

---

## [0.31.0] — 2026-10-02

### Semver class
**Minor.** Adds config auto-save and hot cache. No breaking changes.

### Added

- **Config auto-save.** Debounced writer runs on 0.5s cadence when config is dirty.
- **Change observers.** `Cfg.observe(key, fn)` registers callbacks fired on config writes.
- **Hot cache.** In-memory table is source of truth; disk is sync target.
- **Table-safe pretty printer.** Handles nested tables up to 12 entries.
- **Schema version tracking.** `_version` written to every save.
- **Health check API.** `Cfg.health()` returns writability, save age, observer count.
- **Export/import API.** `Cfg.exportSnapshot()` / `Cfg.importSnapshot(data)`.

### Changed

- Config version bumped to 5 → 6.
- PERSIST list extended with spoofers v4 keys, fly v2 keys, quests v2 keys.

### Fixed

- Table values no longer coerced to `table: 0x...` in `pretty()` output.
- Empty config files no longer partially load.

---

## [0.30.0] — 2026-10-02

### Semver class
**Minor.** Forty spoofer methods (was 31). No breaking changes.

### Added

- **Nine new spoofer methods:**
  - `antiZoom` — FOV restoration on server debuff
  - `antiCinematic` — CameraType reset from Scriptable
  - `antiWarp` — position-jump velocity dampening
  - `antiDisarm` — re-equip during combat
  - `antiInvisible` — restore self Transparency
  - `antiForceField` — strip server ForceField
  - `antiSeatLock` — force-unsit when stuck
  - `antiSoundSpam` — mute clustered sounds (off by default)
  - `antiShakeLock` — camera snap-back after forced shake
- **`Sp.listMethods()`** — returns table of `{ key, hz, on }` for all methods.
- **`Sp.setMethod(name, on)`** — toggle method at runtime.
- **Per-method fire counters.** `stats()[key].fires` shows fire count per method.

### Changed

- Spoofer version bumped to v5.
- `SpoofMethods` config now accepts arbitrary keys (new keys added dynamically).

### Security

- `antiWarp` includes grace window to avoid firing on legitimate teleport-chase.

---

## [0.29.0] — 2026-10-02

### Semver class
**Major.** Detects rewritten; per-iteration walk removed. Behavior of `scanBosses` semantically similar but walker is fundamentally different.

### Added

- **Multi-container BFS walk.** Roots: `Humanoids.Regions`, `Humanoids`, `NPCs`, `Enemies`, `Mobs`, `Entities`, `Units`, `Characters`, `Monsters`, `workspace`.
- **Per-root time budget** (800ms) and iteration budget (40,000).
- **Total scan deadline** (2,500ms).
- **`D.walkStats`** — per-root iteration, hit, timing data.
- **`D.dump()`** enhanced to print per-root walk stats.
- **Sticky attack flag** (0.15s hold).
- **Combined animation read.** One walk returns attacking/blocking/stunned state.
- **3-tier boss cache** (hot 0.3s, warm 1.2s, cold rebuild).
- **Priority filter safety valve.** Auto-disables after 20 consecutive drop-all.
- **Threat scoring** with decay, angular bias, velocity weight, HP weight.

### Changed

- Walker is BFS queue, not DFS stack.
- Iteration counter is per-root, not shared.
- Walk yields every 2,000 iterations (not per-iteration).
- Depth cap raised to 8.

### Fixed

- **C-04:** Per-iteration throttle that reduced walk to ~200 iterations/sec. This was the reason boss scan returned empty.
- **C-05:** Shared iteration counter that starved fallback roots.
- **C-10:** Priority filter permanently blocking all bosses.

---

## [0.28.0] — 2026-10-02

### Semver class
**Minor.** Adds hotbar mutex and item database.

### Added

- **`hotbar.lua`** — new module.
- **Mutex for hotbar access.** `H.acquire(holder, duration)` / `H.release(holder)`.
- **Item database** with ~130 named items across 7 categories.
- **Category lookup.** `H.slotsOfCategory("weapon")` returns all weapon slots.
- **Slot scanner.** `H.scanSlots()` probes slots 1–9, caches results.
- **`H.equipFirstOf(holder, category)`** for crow and weapon equips.
- **`H.tapVerified()`** — fires key then verifies expected item equipped.

### Fixed

- **H-09:** Crow/weapon hotbar contention. The two subsystems no longer stomp each other's equips.

---

## [0.27.0] — 2026-10-02

### Semver class
**Major.** Chest collection rebuilt from keyword matching to whitelist. Breaking change: `ChestKeywords` no longer used for matching.

### Added

- **Learn mode.** Default on. Scans and logs but never fires prompts.
- **Whitelist-only matching.** Exact-name equality, no substrings.
- **`Chest.approve(name)`** / **`Chest.unapprove(name)`**.
- **`Chest.listSeen()`** — prints learn-mode observations.
- **Reach limit.** 4-stud maximum interaction distance.
- **Rate limits.** 10 interactions/minute, 40 per session.
- **Honeypot cluster detection.** ≥3 clones of same base name → refuse all.
- **Reject signatures.** `/`, `\`, `Grimore`, `Book` never fire.
- **Prompt validity check.** Enabled, `MaxActivationDistance > 0`, no Humanoid ancestor.
- **Boss-anchored corpse cycle.** Wait 3–9s jitter, scan 15-stud radius around corpse, attempt exactly the count found.

### Removed

- `ChestKeywords` no longer used in matching logic. Retained for potential future use.

### Security

- **C-01:** Fixed the honeypot-triggered account ban. Whitelist-only matching cannot fire on trap names.

---

## [0.26.0] — 2026-10-02

### Semver class
**Minor.** Attack rewritten for retreat stability. No breaking changes.

### Added

- **Retreat cooldown.** `Cfg.RetreatCooldown = 8s` between retreats.
- **State transition logging.** `logStateChange()` prints once per state change.
- **Target change logging.** `logTargetChange()` prints once per target change.
- **Idle reason logger.** Every 10s idle prints `bosses/mobs/humans` count.
- **`A.forceStopRetreat()`** — manual unstick.
- **Tick body pcall wrapper.** One bad line no longer kills the loop.

### Changed

- `Cfg.RetreatHP` default **0.55 → 0.30**.
- `Cfg.RetreatClearHP` default **0.75 → 0.55**.
- `Cfg.CriticalHP` default **0.15 → 0.12**.
- `Cfg.RetreatDelay` default **2.5 → 2.0**.
- `S.retreating` moved from local to shared state (respawn can reset).
- Retreat watchdog at 6s.

### Fixed

- **C-03:** Permanent retreat lockout. HP below 55% no longer causes infinite retreat cycle.
- **H-01:** Watchdog clears state; cooldown reset also added.

---

## [0.25.0] — 2026-10-02

### Semver class
**Minor.** Crow quest flow rewritten for read-only panel.

### Added

- **Read-only panel support.** Quests are auto-assigned by the game; no accept button exists.
- **`readCrowQuests()`** scrapes "Defeat X" rows from panel.
- **`findCancelButton()`** identifies the only interactive element.
- **Panel cache.** Two known locations checked, not whole PlayerGui.
- **`Q.dumpStructure()`** prints BossHunts structure to F9.

### Changed

- Quest cycle now: equip crow → open menu → read → close.
- Priority list auto-refreshes on staleness.

### Fixed

- **H-06:** `findCrowMenu` substring match on "ok"/"yes". Replaced with exact labels.
- **H-10:** `playerLevel` read from wrong path.
- **H-11:** `readHunts` silently returned empty.

---

## [0.24.0] — 2026-10-02

### Semver class
**Minor.** Adds teleport-chase as primary movement. Fly deprecated.

### Added

- **Teleport-chase movement.** Replaces fly as long-range approach.
- **Velocity ramp** on teleport.
- **Position jitter** per hop.
- **Walk command blend** post-teleport for movement history.
- **Rate limit** (`TeleportCd = 0.22s`).

### Changed

- Attack version bumped to v5.
- Fly module retained but removed from subsystem init list.

### Deprecated

- `fly.lua`. Superseded by teleport-chase. Retained as dead code.

### Fixed

- **C-06:** Fly BodyVelocity rejected by server reconciliation. Teleport-chase has different detection profile.
- **C-07:** `CFrame.new(pos, lookAt)` NaN basis vectors. Fixed with `safeCFrame()` minimum separation.
- **H-23:** "Behind boss" computed from boss LookVector. Now computed from player→boss vector.
- **H-24:** Chained M1s sent as identical bursts. Now alternates M1/M2.

---

## [0.23.0] — 2026-10-02

### Semver class
**Minor.** Combo engine rewritten.

### Added

- **Combo engine with 4 randomized permutations.**
- **Alternating M1/M2 chains** per strike (3–5 clicks).
- **Ultimate gating** (skills 5+ held for high-value windows).

### Changed

- Attack version bumped to v6.
- `AtkInterval` default **0.55 → 0.38**.

### Fixed

- **C-08:** Auto-block fired on every enemy during approach.
- **H-24:** Identical M1 clicks only advanced combo step 1.

---

## [0.22.0] — 2026-10-02

### Semver class
**Minor.** Config version bumped to v3.

### Added

- Config keys for fly v2 (`FlyParentHead`, `FlyClaimNetworkOwner`, `FlyCFrameFallback`).
- Config keys for scanners v3 (`CrowMenuCooldown`, `CrowScanMinGap`).

### Changed

- Config PERSIST extended.

---

## [0.21.0] — 2026-10-02

### Semver class
**Minor.** Adds spoofers v3 with reduced method count. Some methods cut for being net-negative.

### Removed

- `spoofHP` — cosmetic; server owns HP in FilteredEnabled games.
- `goUnderground` — dead code, self-trapping.
- `surfaceUp` — dead code, left BodyPosition on character.
- `checkUG` — dead code, timer drift.
- `hpC/bkC/spdC/kbC/jmpC` — never read.

### Added

- Guarded pcall with first-error print and recovery.
- Write-fight detection with auto-concede after 5 corrections.
- Deprecated stubs for removed methods.

### Changed

- `spoofSpeed` / `spoofJump` calibrated to 1.25× base (was 2×).
- `antiKnock` opt-in (default off).
- `antiStun` only on `FallingDown` (never `Ragdoll`/`Physics`).

### Security

- Reduced detection surface by cutting cosmetic writes.

---

## [0.20.0] — 2026-10-02

### Semver class
**Minor.** Scanners rewritten for cache.

### Added

- Crow tool cache with validity check.
- Crow model cache with TTL.
- Caw sound cache.
- `S.findCancelButton()` — panel detection.
- `S.findQuestCards()` — clickable detection.
- `S.waitForCaw()` — sound-based trigger.

### Changed

- `findCawSound` no longer allocates `workspace:GetDescendants()`.
- `findCrowMenu` retired (no accept button exists).

### Removed

- `deepScan` — never called.
- `dumpInventory` — never called.

### Fixed

- **H-07:** `findCawSound` allocated full workspace tables on every crow cycle.

---

## [0.19.0] — 2026-10-02

### Semver class
**Minor.** GUI rewritten to 8 tabs. Adds Targets selector.

### Added

- **Targets tab** with per-region, per-boss enable toggles.
- **Select All** / **Clear All** bulk actions.
- **Live "enabled X/Y bosses" counter.**
- **Settings tab** with concealed parent toggle and panic keybind.

### Changed

- GUI version bumped to v28.
- Sidebar navigation layout.
- Row-based card layout for all toggles.

### Fixed

- **M-25:** GUI reading chest stats from wrong config field.

---

## [0.18.0] — 2026-10-02

### Semver class
**Minor.** Adds optimizers with dynamic cleanup.

### Added

- **Reversible particle/light/post-effect stripper.**
- **Dynamic cleanup** via throttled `DescendantAdded`.
- **Memory GC** at 60s interval.
- **Restore path** on disable.

### Changed

- Optimizer version bumped to v2.
- Batched dynamic cleanup (50 per 0.1s).

### Fixed

- **H-20:** Unthrottled `DescendantAdded` hook caused scheduler starvation.

---

## [0.17.0] — 2026-10-02

### Semver class
**Minor.** Utils rewritten for capability probe.

### Added

- **`mouse2click` family** to `U.Fn`.
- **Full file-API probe** (`readfile`, `isfile`, `delfile`, `listfiles`, `makefolder`).
- **`U.m2()` helper.**
- **`U.safe()`** generic safe-call.
- **`U.retry()`** with tries and delay.

### Fixed

- **H-03:** `U.m2()` was missing. Attack module now calls it.

---

## [0.16.0] — 2026-10-02

### Semver class
**Minor.** Loader rewritten for auto-discovery.

### Added

- **GitHub contents API discovery.** Loader finds `.lua` files in repo root.
- **Topological sort** by `Ctx.<Slot>` references.
- **Slot aliasing** (Fly + FlyMod, Cfg + Config).

### Changed

- Loader version bumped to v26.
- Manifest no longer hardcoded (fallback list retained).

---

## [0.15.0] — 2026-10-01

### Semver class
**Minor.** Lists rebuilt with word-boundary matching.

### Added

- **Word-boundary awareness** for short entries (`ren`, `claw`).
- **Region grouping** for GUI display.
- **Per-boss enable flags.**

### Changed

- Lists version bumped to v3.
- Endgame bosses only (Map 1 and Map 2 removed per user request).

### Removed

- Character names erroneously listed as clans (Yoriichi, Kokushibo, Muzan).
- Anime-only breathing styles (Mist, Beast, Sun, Moon).
- `reaping blades` fighting style (not in PS2).

### Fixed

- **H-17:** Non-weapon tools classified as weapons.
- **M-22:** Boss region names not matching flat boss list.

---

## [0.14.0] — 2026-10-01

### Semver class
**Minor.** Attack rewritten with self-contained config.

### Added

- **Inline config defaults.** Attack module no longer depends on `config.lua` being current.
- **Fly watchdog.**
- **Equip diagnostics** (first 5 attempts print).
- **`A.tryCollectChestNow()`** public method.

### Changed

- Attack version bumped to v4.

### Fixed

- **H-08:** `equipWeapon` blocked 80ms in scheduler.

---

## [0.13.0] — 2026-10-01

### Semver class
**Minor.** Fly module rewritten.

### Added

- **Head-parent option** for BodyMovers.
- **Camera detach option.**
- **Noclip** with persistent loop.
- **CFrame fallback** when velocity rejected.
- **Network owner claim.**

### Changed

- Fly version bumped to v2.
- Jitter reduced from 3 to 2.

### Fixed

- **H-22:** Noclip reset by Humanoid state changes.
- **C-06:** Server rejected BodyVelocity — CFrame fallback added.

---

## [0.12.0] — 2026-10-01

### Semver class
**Minor.** Config version 2 with slot API.

### Added

- **Slot file API.** `Cfg.slotFile(slot)` returns per-slot config filename.
- **Multiple named config slots.**
- **`Cfg.fileSize(slot)`** returns nil if missing (was returning 0).

### Changed

- Config version bumped from 1 to 2.
- Default config file is `dingus_config.json`.

---

## [0.11.0] — 2026-10-01

### Semver class
**Minor.** Detect rewritten with priority filter and 3-tier cache.

### Added

- **Priority filter** via `Ctx.Quest.isPriority`.
- **Multi-tier boss cache** (hot 0.3s, warm 1.2s).
- **`D.isEnemyAttacking`** public function.
- **Overlay reader** as diagnostic.
- **Alive re-verification** in warm cache.

### Changed

- Detect version bumped to v3.

### Fixed

- **H-04:** Region-first scan was silently skipped.

---

## [0.10.0] — 2026-10-01

### Semver class
**Minor.** Main.lua rewritten for bulletproof boot.

### Added

- **Phase isolation.** Every boot phase wrapped in `pcall`.
- **Guard rails.** `Ctx` type check at boot.
- **`safeRun(label, fn)`** helper.
- **`Ctx.Loops`** exposed for GUI display.

### Changed

- Main version bumped to v32.
- Scheduler cadence reduced from 33Hz to 20Hz.

### Fixed

- **M-05:** `loops` table built inside closure.
- Boot no longer aborts on single subsystem failure.

---

## [0.9.0] — 2026-10-01

### Semver class
**Minor.** Loader version 25 with dependency manifest.

### Added

- **Hardcoded manifest** with dependency declarations.
- **Per-file retry** on HTTP failure.
- **Three-phase load** (require, init, boot).

### Fixed

- **H-21:** Loader crashed on executor HTTP concurrency.

---

## [0.8.0] — 2026-10-01

### Semver class
**Minor.** GUI version 25 with dual-frame architecture.

### Added

- **Minimize-to-pill animation.**
- **Draggable minimized pill.**
- **Six tabs** (Main, Combat, Quests, Config, Files, Logs).
- **Log manager** with live capture from `LogService.MessageOut`.
- **Config slot manager.**

### Changed

- GUI rewritten from scratch.

---

## [0.7.0] — 2026-10-01

### Semver class
**Minor.** Config version 1 established.

### Added

- **Persistence via JSON.**
- **`Cfg.snapshot()`** and **`Cfg.apply(data)`.**
- **`Cfg.pretty()`** printer.

---

## [0.6.0] — 2026-10-01

### Semver class
**Minor.** Lists version 1 established.

### Added

- **Central data tables** for bosses, weapons, non-weapons, quest items, materials, consumables, clans, regions, breathings, demon arts, fighting styles, keywords.
- **`isBoss`, `isWeapon`, `isCrow`, `isQuest`** matchers.

---

## [0.5.0] — 2026-10-01

### Semver class
**Minor.** Utils version 1 established.

### Added

- **Safe service loader.**
- **Capability probe** for executor functions.
- **Input helpers** (`tap`, `keyDown`, `keyUp`, `m1`).
- **Character accessors** (`hum`, `hrp`).
- **Tree walker.**

---

## [0.4.0] — 2026-10-01

### Semver class
**Minor.** Attack module version 1 established.

### Added

- **Basic combat state machine.**
- **Skill rotation.**
- **Weapon auto-equip.**
- **Retreat logic.**

### Fixed

- **C-02:** Fly nil-call killing combat loop. Fixed with `tryEngageFly` guard.

---

## [0.3.0] — 2026-10-01

### Semver class
**Minor.** Detect module version 1 established.

### Added

- **Region-first humanoid scan.**
- **Threat detection via animation read.**
- **Block and stun detection.**
- **Target picker.**

---

## [0.2.0] — 2026-10-01

### Semver class
**Minor.** Spoofers module version 1 established.

### Added

- **Client-state hardening methods** (initial set).
- **Write-fight detection.**
- **Concede-to-server after 5 corrections.**

---

## [0.1.0] — 2026-09-30

### Semver class
**Major.** Initial public release.

### Added

- **Initial repository structure.**
- **Loader, main, config, lists, utils, detect, scanners, spoofers, attack, optimizers, gui modules.**
- **Project README.**
- **Basic combat loop.**
- **Crow quest reader** (initial version, later replaced).
- **Chest collection** via keyword matching (later replaced).
- **JSON-based config persistence.**

### Known issues at release

- **C-01:** Keyword matching fired on honeypot decoys.
- **C-02:** Fly nil-call.
- **C-03:** Retreat loop lockout.
- **C-04:** Detect walk throttled.
- **C-05:** Shared iteration counter.
- **C-06:** Fly rejected by server.

---

## Version History Summary

| Version | Date | Loader | Attack | Detect | Chest | Notable |
|---|---|---|---|---|---|---|
| 0.34.0 | 2026-10-03 | v34 | v21 | v8 | v6 | HTTP headers, structured boot |
| 0.33.0 | 2026-10-03 | v34 | v21 | v8 | v6 | Chests GUI tab |
| 0.32.0 | 2026-10-03 | v32 | v21 | v8 | v6 | Sequential loader |
| 0.31.0 | 2026-10-02 | v30 | v21 | v8 | v6 | Config auto-save |
| 0.30.0 | 2026-10-02 | v30 | v21 | v8 | v6 | 40 spoofer methods |
| 0.29.0 | 2026-10-02 | v30 | v21 | v8 | v6 | Multi-container BFS walk |
| 0.28.0 | 2026-10-02 | v30 | v20 | v8 | v6 | Hotbar mutex |
| 0.27.0 | 2026-10-02 | v30 | v19 | v8 | v6 | Whitelist chest |
| 0.26.0 | 2026-10-02 | v30 | v21 | v7 | v5 | Retreat cooldown |
| 0.25.0 | 2026-10-02 | v30 | v20 | v6 | v5 | Read-only crow panel |
| 0.24.0 | 2026-10-02 | v30 | v20 | v6 | v5 | Teleport-chase |
| 0.23.0 | 2026-10-02 | v30 | v6 | v5 | v3 | Combo engine |
| 0.22.0 | 2026-10-02 | v30 | v5 | v5 | v3 | Config v3 |
| 0.21.0 | 2026-10-02 | v30 | v5 | v5 | v3 | Spoofers v3 |
| 0.20.0 | 2026-10-02 | v30 | v5 | v5 | v3 | Scanners cache |
| 0.19.0 | 2026-10-02 | v30 | v5 | v3 | v3 | 8-tab GUI |
| 0.18.0 | 2026-10-02 | v30 | v5 | v3 | v3 | Optimizers |
| 0.17.0 | 2026-10-02 | v30 | v5 | v3 | v3 | Utils v3 |
| 0.16.0 | 2026-10-02 | v26 | v5 | v3 | v3 | Auto-discovery loader |
| 0.15.0 | 2026-10-01 | v25 | v5 | v3 | v3 | Lists v3 |
| 0.14.0 | 2026-10-01 | v25 | v4 | v3 | v3 | Self-contained attack |
| 0.13.0 | 2026-10-01 | v25 | v4 | v3 | v3 | Fly v2 |
| 0.12.0 | 2026-10-01 | v25 | v4 | v3 | v3 | Config slots |
| 0.11.0 | 2026-10-01 | v25 | v4 | v3 | v3 | Priority filter |
| 0.10.0 | 2026-10-01 | v25 | v4 | v2 | v3 | Bulletproof boot |
| 0.9.0 | 2026-10-01 | v25 | v4 | v2 | v3 | Dependency manifest |
| 0.8.0 | 2026-10-01 | v24 | v4 | v2 | v3 | GUI v25 |
| 0.7.0 | 2026-10-01 | v24 | v4 | v2 | v3 | Config v1 |
| 0.6.0 | 2026-10-01 | v24 | v4 | v2 | v3 | Lists v1 |
| 0.5.0 | 2026-10-01 | v24 | v3 | v2 | v3 | Utils v1 |
| 0.4.0 | 2026-10-01 | v24 | v1 | v2 | v3 | Attack v1 |
| 0.3.0 | 2026-10-01 | v24 | v1 | v1 | v3 | Detect v1 |
| 0.2.0 | 2026-10-01 | v24 | v1 | v1 | v3 | Spoofers v1 |
| 0.1.0 | 2026-09-30 | v1 | v1 | v1 | v1 | Initial release |

---

## Breaking Changes Log

Every breaking change across the project's lifetime, in reverse chronological order.

### 0.29.0 — Detect walker replaced
**What broke:** Any code calling into `detect.lua` internals that relied on DFS traversal order.
**Migration:** None required for public API. `scanBosses`, `scanMobs`, `pickTarget` all work identically.

### 0.27.0 — Chest keyword matching removed
**What broke:** `Cfg.ChestKeywords` no longer used for matching. If you were relying on keyword-based detection, it now returns nothing.
**Migration:** Populate `Cfg.ChestWhitelist` via `Chest.approve(name)` after observing items in-game.

### 0.24.0 — Fly deprecated
**What broke:** `fly.lua` no longer initialized. `Ctx.Fly.start` is undefined.
**Migration:** No action required. Attack uses teleport-chase. Fly module retained as dead code.

### 0.16.0 — Hardcoded manifest removed
**What broke:** Loader no longer reads a fixed file list. It discovers via GitHub API.
**Migration:** None. Fallback list retained for API failures.

### 0.15.0 — Lists pruned to endgame bosses
**What broke:** Map 1 and Map 2 bosses removed from `L.bosses`.
**Migration:** None if endgame only. Re-add specific bosses if you need them.

### 0.6.0 — Central lists module
**What broke:** Keyword lists moved from inline literals to `lists.lua`.
**Migration:** Consumers now read `Ctx.Lists` instead of hardcoded arrays.

---

## Security Log

Every security-relevant change in reverse chronological order.

### 0.34.0
- Added HTTP headers to reduce executor fingerprint at CDN edge.

### 0.27.0
- **Fixed honeypot-triggered ban.** Keyword matching on loot could fire on trap instances named with `ore` substring. Whitelist-only matching eliminates this vector.
- Added honeypot cluster detection.
- Added reach limit (4 studs).
- Added rate limits (10/min, 40/session).

### 0.21.0
- Cut cosmetic spoofer writes that were detection signals.
- Reduced spoofSpeed / spoofJump multipliers from 2× to 1.25×.

### 0.30.0
- Anti-warp method added with grace window to avoid firing on own teleports.

---

## Deprecation Notices

### `fly.lua`
**Deprecated in:** 0.24.0
**Reason:** Server reconciliation rejects BodyVelocity motion. Retained as dead code.
**Removal planned:** Next major release.

### `Cfg.ChestKeywords`
**Deprecated in:** 0.27.0
**Reason:** Substring keyword matching is unsafe. Whitelist-only detection replaces it.
**Removal planned:** After user-supplied whitelists mature.

### `D.readOverlay`
**Deprecated in:** 0.29.0
**Reason:** Superseded by structured threat model. Retained for potential GUI wiring.
**Removal planned:** When GUI diagnostics are extended.

### `MobKeywords` list
**Deprecated in:** 0.15.0
**Reason:** Mob targeting disabled (boss-only mode).
**Removal planned:** Not planned. Retained for potential future use.

---

## Contributors

- **PurpleXPurple** — repository owner, primary author
- **DeepSeek** — co-development partner, code generation contributor

---

## License

Copyright (c) 2026 PurpleXPurple. All Rights Reserved.
Co-authored with DeepSeek.

See [LICENSE](LICENSE) for full terms. This project is **not** open source. Use is prohibited without prior written permission from the Authors except for narrow research carve-outs described in Section 4 of the license.

---

*This changelog is auto-maintained. Entry order reflects the version history as documented in commit logs and audit trail. For detailed per-finding information see [Code_Audit.md](Code_Audit.md). For usage instructions see [USAGE.md](USAGE.md). For architecture reference see [README.md](README.md).*
