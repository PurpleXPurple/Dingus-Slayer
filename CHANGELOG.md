CHANGELOG.md — full, unfenced, extra detailed

---

# Changelog

All notable changes to Dingus-Slayer are documented here.

**Format:** [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
**Versioning:** [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
**Sections:** Added · Changed · Deprecated · Removed · Fixed · Security

This project uses a dual-track versioning scheme: the **loader carries the primary version** (currently v37), and each module carries its own minor version in a comment header. The unified project version is the loader's. When a module's internal version and the project version disagree, the project version is authoritative for release decisions.

---

## Table of Contents

1. [Version History](#version-history)
2. [Architecture Reference](#architecture-reference)
3. [Diagrams](#diagrams)
4. [Breaking Changes Log](#breaking-changes-log)
5. [Migration Guides](#migration-guides)
6. [Security Log](#security-log)
7. [Deprecation Notices](#deprecation-notices)
8. [Cross-Device Capability Matrix](#cross-device-capability-matrix)
9. [Module Version Map](#module-version-map)
10. [Contributors](#contributors)
11. [License](#license)

---

## Version History

### [0.41.0] — 2026-10-05

#### Semver Class
**Minor.** Adds the Faction system and rebuilds the GUI. No breaking changes to public APIs, but the GUI layout is entirely new and one prior `mkDropdown` cycling behaviour was replaced with a real popup list.

#### Added

- **`faction.lua` v1** — new module. Auto-detects player role (Slayer / Demon / Hybrid / Hashira) and classifies every nearby NPC into a faction (demon / slayer / neutral) by name pattern. Exposes `shouldTarget`, `priorityWeight`, `getEnemyList`, and manual override controls.
- **Faction tab in GUI** — live role/rank display, manual override segmented control, include-neutral toggle, Hashira priority toggle, live enemy list showing the top 8 matching targets.
- **`L.faction` table** in `lists.lua` — three factions with keyword lists. `L.factionOf(name)` and `L.isHashira(name)` helpers.
- **`S.faction`, `S.factionRank`, `S.isHashira`** state keys in shared runtime state.
- **Config keys** — `FactionAuto`, `FactionManual`, `FactionIncludeNeutral`, `FactionPriorityUpper`, `FactionDetectInterval`, `FactionHashiraBoost`.
- **Faction chip in GUI header** — colour-coded by detected faction (purple for demon, blue for slayer, yellow for hybrid, grey for unknown). Hashiras shown with `★` suffix.
- **`mkDropdown` real popup** — replaces the old cycling button. Opens a scrollable modal with all options. Mobile-safe and PC-friendly.
- **`mkSegment` widget** — segmented control for 2–4 option choices. Used for Mob Category and Farm Mode.
- **`mkStatCard` widget** — dashboard stat cards with icon, label, and live value.
- **`mkNav` sidebar footer** — farm pulse indicator that changes colour with state (green for STRIKE/PUNISH, red for RECOVER/RETREAT, yellow for SCAN/TELEPORT, blue for LOOT_WAIT).
- **7-tab layout** — Dashboard, Farm, Faction, Chests, Quests, Logs, Settings.

#### Changed

- **`gui.lua` rebuilt from scratch as v40** — widget factory pattern, `mkSwitch`/`mkToggle`/`mkButton`/`mkInfo`/`mkSection`/`mkSlider`/`mkDropdown`/`mkSegment`/`mkStatCard`/`mkNav` are now isolated constructors. Prior versions mixed construction with layout. Reduces bugs, improves reuse.
- **Window sizing** — mobile viewport-aware. `WW` scales to `min(vp.X - 16, 560)` on mobile; `1000` on desktop. Was fixed at 520/960.
- **Header** — brand block (title + platform + executor), live state chip, faction chip. Two window controls (minimize, close) unchanged.
- **Nav sidebar** — was 6 tabs, now 7. Farm footer pulse added below the scroll area.
- **`attack.lua` v25** — inserts faction filter at the top of `passesFilter` and applies priority weight in `pickTarget`. Priority weight boosts Upper Moons for Hashira players, Hashiras for Demon players.
- **`lists.lua` v11** — adds faction tables. No changes to existing boss/NPC/quest data.
- **`config.lua` v9** — adds faction keys to defaults and PERSIST. Adds `HotbarSlots` to PERSIST for learned-slot persistence.
- **`loader.lua` v37** — manifest adds `faction` between `hotbar` and `fly`.
- **`main.lua` v38** — ORDER adds `faction` between `hotbar` and `fly`.

#### Fixed

- **F-06** — prior GUI had no controls for `S.mobCategory`, `S.regionFilter`, `F.SynSafeMode`, `S.autoQuest`, or `S.questMode`. All now exposed.
- **F-07** — prior `mkDropdown` (cycling button) made it hard to select from >4 options on mobile. Real popup fixes this.

#### Security

- **Faction detection reads no external input.** All sources are read-only property reads via `pcall`. No remote calls, no attribute writes, no client-side state mutation.

---

### [0.40.0] — 2026-10-05

#### Semver Class
**Minor.** Rebuilds `scanners.lua` and `hotbar.lua`. Public API of `scanners.lua` expands significantly but remains backwards-compatible with prior callers.

#### Added

- **`scanners.lua` v6 — general-purpose scan engine.** Single entry point `S.scan(spec)` walks any container by class, name, tag, attribute, or child presence with radius, depth, and time-budget constraints.
- **Preset scanners** — `S.humanoids`, `S.bosses`, `S.mobs`, `S.npcs`, `S.players`, `S.corpses`, `S.prompts`, `S.clickDetectors`, `S.chests`, `S.loot`, `S.souls`, `S.tagged`, `S.withAttribute`, `S.named`, `S.remotes`.
- **Convenience** — `S.nearest`, `S.count`, `S.dump`.
- **`S.byPath`** — resolves an instance by a dot path like `"workspace.Humanoids.Regions"` or `"RS.CAM.Global.Utility"`.
- **`S.instPosition`** — universal instance position resolver (BasePart, Model, Attachment, ProximityPrompt, ClickDetector).
- **`hotbar.lua` v4 — item database restored** with ~130 entries across 6 categories (weapon, crow, potion, gourd, utility, accessory). Plus a tier system for auto-equip-best-weapon logic.
- **`H.classifyItem`** — exact match first, then substring, then heuristic. Handles unknown item names gracefully.
- **`H.autoEquipBestWeapon`** — scans character and backpack, picks highest-tier weapon, equips via `Humanoid:EquipTool`.
- **`H.waitFree`** — waits up to N seconds for the mutex to become available.
- **`H.lockedBy`** — returns current mutex holder name (used by GUI diagnostics).
- **`H.saveSlots` / `H.clearSlots`** — persist or wipe learned hotbar slot mapping.
- **`S.crow` namespace** — crow-specific helpers (`S.crow.tool`, `S.crow.cancelButton`, `S.crow.quests`).

#### Changed

- **`hotbar.lua`** — tap and tap-verified now use `U.fireSkill` first (fires the on-screen `KeyLabel` button), falling back to `U.tap(key)`. This works on mobile where key simulation alone was unreliable.
- **`hotbar.lua`** — `scanSlots` probes keys 1–9, records whichever tool appears after each tap. Learned map is persisted to `F.HotbarSlots` on demand.
- **`scanners.lua`** — walker uses a BFS queue with adaptive yield (400 iterations on mobile, 2000 on PC).
- **`scanners.lua`** — fast-path for tag-only queries. If `spec.tag` is set and no container override is given, queries `CollectionService:GetTagged` directly instead of walking workspace.

#### Fixed

- **F-05** — prior `hotbar.lua` v3 returned `false, "no-db"` from `equipFirstOf`. Any caller relying on category lookup would silently no-op. Fixed.
- **F-04b** — `scanners.lua` v5 could only find crow-related UI. All other scan needs had to be reimplemented inline by callers. Fixed.

#### Removed

- **`scanners.lua` stub functions** — `findCawSound`, `deepScan`, `dumpInventory` were never called and are gone. `findCrowMenu` retained as a no-op for compatibility.

---

### [0.39.0] — 2026-10-04

#### Semver Class
**Minor.** Rebuilds `quests.lua` to a full NPC quest pipeline. Prior version only read the crow panel.

#### Added

- **`quests.lua` v9 — full NPC quest pipeline** with auto-accept, auto-abandon, and best-quest-by-level selection.
- **Level reader** using `Utility.GetData` + `exp.Goal / expPerLevel`, with slot-path fallback.
- **Race reader** using `Utility.GetData`. Exposes `Q.getPlayerRace`.
- **`Q.acceptQuest`** — full dialogue flow: teleport to NPC, fire prompt, wait for `DialogueFrame`, click quest button by name match, verify via `readActiveQuest`, close dialogue.
- **Remote fallback** — if no dialogue button appears, fires `SignalEvent.ToServer("AddQuest", name)` and `Dialogue.Functions.AddQuest(name)`.
- **`Q.abandonQuest`** — sends `RemoveQuest` remote and cleans empty holder entries.
- **`Q.pickBestQuest`** — filters `L.quests` by level and race, picks highest `minLvl` under current level.
- **Race filtering** — `Any`, `Slayer`, `Hybrid`, `Demon`, or table variants `{Slayer, Hybrid}`.
- **`Q.findNpcPosition`** — 4-tier fallback: `Debree.Regions.*.StationaryNpcs` → `Humanoids.Regions.*` → `Regions.GetNpcSpawn` remote → `L.npcPositions` static table.
- **Auto-disable** after 3 consecutive failures on the same quest.
- **Quest push to attack** — on successful accept, sets `Ctx.Atk.setCategory`, `setTargetMob`, `setRegion` so the farm loop targets the right thing.
- **`Q.listAvailableQuests`** — returns all 18 quests with eligibility flags.
- **`Q.forceAcceptQuest(name)`, `Q.forceAbandon()`, `Q.forceCrowRead()`** public controls.

#### Changed

- **`quests.lua`** — crow cycle and NPC quest cycle run independently. Crow reads priority for filter; NPC quests handle the accept/abandon loop.
- **`quests.lua`** — crow tool cache invalidated on respawn.

#### Fixed

- **Q-04** — prior version had no accept path. Every quest acquisition required manual in-game interaction.

---

### [0.38.0] — 2026-10-04

#### Semver Class
**Minor.** Adds cross-device abstraction layer to `utils.lua`. No breaking changes but every subsequent module depends on the new primitives.

#### Added

- **`utils.lua` v4 — platform detection.** Detects `pc`, `mobile`, `hybrid`, or `unknown` at boot based on `UserInputService.TouchEnabled` and `KeyboardEnabled`.
- **Input backend selection** — `vim` (VirtualInputManager), `vk` (keypress), or `none`.
- **`U.fireSkill(label)`** — fires the game's on-screen `KeyLabel` button. Works on mobile and PC. Falls back to `U.tap(label)` if the button is missing.
- **`U.hasSkillButton(label)`** — probes existence of a skill button by label.
- **`U.firePrompt(prompt)`** — 4-tier ProximityPrompt fallback: `fireproximityprompt` → `InputHoldBegin/End` → `KeyboardKeyCode` tap → `Triggered` signal.
- **`U.fireClick(det)`** — 2-tier ClickDetector fallback: `fireclickdetector` → `MouseClick:Fire`.
- **`U.touchInterest(a, b)`** — wraps `firetouchinterest` when present.
- **`U.httpGet(url, headers)`** — unified HTTP wrapper. Uses `request()` with headers when available, falls back to `game:HttpGet` with cache-bust.
- **`U.File`** — full file API abstraction. `write`, `read`, `exists`, `delete`, `mkdir`, `list`. Falls back to in-memory VFS when executor lacks file primitives.
- **`U.notify`** — rate-limited notification with `SetCore` primary and `print` fallback.
- **`U.resolveGuiParent`** — returns `gethui` → `CoreGui` → `PlayerGui` in order. On mobile, prefers `PlayerGui` since `gethui` is often missing.
- **`U.report`** — capability dump string for diagnostics.
- **`U.IsMobile`, `U.IsPC`, `U.Platform`, `U.Executor`, `U.InputBackend`, `U.MouseBackend`, `U.HttpMode`, `U.Caps`** — new top-level exports.

#### Changed

- **Every input call site** migrated to `U.*` primitives. Direct `VirtualInputManager` usage now only exists inside `utils.lua`.
- **Every file persistence call site** migrated to `U.File`. `writefile`/`readfile` are no longer referenced directly outside `utils.lua`.

#### Fixed

- **D-01 through D-12** — the entire cross-device audit. Twelve findings, all fixed by the abstraction layer.

---

### [0.37.0] — 2026-10-04

#### Semver Class
**Major.** Rebuilds `fly.lua`, `attack.lua`, `chest.lua`, and `lists.lua` to use Synerox's farming approach. Old behaviour retired.

#### Added

- **`fly.lua` v6 (initial)** — Synerox farm movement. Anchor platform under target with `Overhead`, `Underground`, `In Front`, `Ground` modes.
- **`attack.lua` v23 (initial)** — Synerox farm loop. Uses `InputHandler.VirtualPress("Combat")` for M1, `Skill_Provider.get_current_keys()` + `Skill_Controller.Attempt_Hold()` for skills, track guard for animation resets, freeze recovery via `Player_Service.Values` value destruction.
- **`chest.lua` v8** — Synerox loot pipeline. Reads `LootDrops` folder, `LootDrop` tag, ownership attributes `DropOwnerUserId`/`DropReservedFor`, position attribute `DropTarget`. Chest scan filters `ChestState` (`Opened`/`Despawned`/`Locked`). Soul scan checks `Soul`/`Souls`/`DemonSoul` tags.
- **`lists.lua` v10** — full Synerox data. 38 boss names, 80 NPC positions, 12 region anchors, 18 quest entries, 8 trainers, 12 boss timers, full shop tables, clan list, BDA list.
- **`F.SynSafeMode`, `F.SynHeightOffset`, `F.SynDistance`, `F.SynM1Interval`, `F.SynMultiHit`, `F.SynMultiHitCount`, `F.SynAutoSkills`, `F.SynSkillInterval`, `F.SynTrackGuard`, `F.SynBossLootWait`, `F.SynMobLootWait`, `F.SynAutoTravel`, `F.SynTargetLock`, `F.SynBossRotationT`** — new farm config keys.
- **`S.lockedTarget`, `S.bossLootPos`, `S.mobCorpsePos`, `S.bossIndex`, `S.bossRotateTime`** — new farm state keys.

#### Changed

- **`fly.lua`** — no longer wraps BodyMovers. The platform is a single anchored Part moved by CFrame.
- **`attack.lua`** — M1 no longer uses `mouse1click` on PC only. Now uses game's `InputHandler` when available. Track guard stops `Swing`/`Punch`/`Slash`/`React` tracks so new M1s register.
- **`chest.lua`** — no longer uses exact-name whitelist. Uses three source types (folder, tag, attribute) with ownership checks.
- **`lists.lua`** — retired the small boss roster (9 entries). Full roster now 38.

#### Deprecated

- **`chest.lua` learn mode.** Kept as a config key but no longer blocks firing. Kept for compat only.
- **`attack.lua` `RetreatHP`, `CriticalHP`, `RetreatDelay`, `RetreatClearHP`, `RetreatCooldown`.** Farm loop no longer retreats at HP thresholds. Kept as no-op state.

#### Fixed

- **S-01 through S-16** — the entire Synerox parity audit. All sixteen findings fixed or intentionally deprecated.

---

### [0.36.0] — 2026-10-03

#### Semver Class
**Minor.** Optimizes `loader.lua` and `main.lua`. Boot is faster and fairer across devices.

#### Added

- **`loader.lua` v36 — in-memory function cache.** `_G.DINGUS_FN_CACHE` holds compiled modules for the current session. Second boot within a session reuses them instead of re-fetching from CDN.
- **`_G.DINGUS_SESSION`** — session ID persists across re-boots of the same process.
- **`_G.DINGUS_BOOT_COUNT`** — increments on each boot. `IS_REBOOT` flag suppresses verbose banner on subsequent boots.
- **4th CDN (`ghcdn.dev`)** — additional fallback.
- **`FETCH_SLOW` detection** — if any single fetch takes over 2 seconds, subsequent CDN attempts are skipped and the loader falls to disk cache.
- **Prerequisite check** — boot halts with a clean error if `loadstring`, `game.HttpGet`, or `game.GetService` are missing.
- **`main.lua` v37 — single-Heartbeat scheduler.** Replaces `task.wait(0.05)` polling. Runs all loops from one `RunService.Heartbeat` connection.
- **`Perf` tracker** — smoothed frame time (`Perf.avg_dt`), stress level (`Perf.stress`), backoff multiplier (`Perf.backoff`), rolling budget.
- **Priority classes** for loops — 1 (combat, threats, fly), 2 (spoofers), 3 (quests, chest), 4 (config, gc). Higher priority runs first and is never shed.
- **Frame budget shed** — priority 2 loops skipped at stress > 0.5, priority 3 skipped at stress > 0.8.
- **`C.perf()` and `C.perfPrint()`** — per-loop run count, error count, average duration, max duration.
- **Session-level connection guard** — heartbeat from a prior boot is disconnected before a new boot.
- **Deferred init** — mover scrub and `SetCore` notification run in tasks, not on the boot thread.

#### Changed

- **`main.lua`** — `S.fps` sampled every 0.5 seconds, not every frame.
- **`main.lua`** — per-loop auto-disable threshold raised from 5 errors to 10.
- **`loader.lua`** — non-blocking notification phase.
- **`loader.lua`** — reboot prints one line, not a 14-line table.

#### Fixed

- **B-01 through B-08** — the entire loader/main parity audit. All eight findings fixed.

---

### [0.35.0] — 2026-10-03

#### Semver Class
**Minor.** First cross-device groundwork. `loader.lua` v35 and `main.lua` v36 introduced the abstraction patterns that 0.36.0 would optimize.

#### Added

- **`loader.lua` v35** — request() path with headers.
- **`main.lua` v36** — loop table construction isolated from scheduler.

#### Fixed

- **D-06** — prior loader always used `game:HttpGet`. Now probes for `request()` and sends headers when available.

---

### [0.34.0] — 2026-10-03

#### Semver Class
**Minor.** Adds HTTP header support and structured boot logging.

#### Added

- HTTP headers on `request()` path.
- ETag conditional requests.
- Structured boot banner.
- Phase dividers.
- Per-module aligned log rows.
- Slowest-fetch report.
- `_G.DINGUS_BOOT` structured result table.

#### Changed

- Loader version header updated to v34.
- Boot summary prints aggregate timings.

#### Fixed

- Loader no longer wraps markdown content in triple backticks.

#### Security

- HTTP headers reduce executor fingerprint at the CDN edge.

---

### [0.33.0] — 2026-10-03

#### Semver Class
**Minor.** Adds the Chests tab. Rewires loot delegation.

#### Added

- Chests tab in GUI (now 9 tabs).
- Learn-mode toggle.
- Collection method toggles.
- Range and timing sliders.
- Chest live stats panel.
- Last Scan panel.

#### Changed

- `attack.lua` delegates all loot work to `Ctx.Chest`.
- `Cfg.ChestKeywords` retained but no longer used for keyword matching.

#### Removed

- Inline `findNearestChest` from `attack.lua`.

#### Fixed

- GUI updates chest stats on the standard 0.3s refresh cycle.

---

### [0.32.0] — 2026-10-03

#### Semver Class
**Minor.** Loader rewritten for crash safety.

#### Added

- Sequential-only loader.
- Multi-CDN chain.
- Disk cache with TTL.
- Breadcrumb tracing.
- Per-module timing.
- Source release after compile.
- Full error detail.

#### Changed

- `USE_CACHE` toggle.
- `MAX_RETRY` reduced to 2.

#### Fixed

- Boot no longer hangs on concurrent HTTP access (the primary crash vector in v31).

#### Security

- Cache invalidation on compile or runtime failure.

---

### [0.31.0] — 2026-10-02

#### Semver Class
**Minor.** Adds config auto-save and hot cache.

#### Added

- Config auto-save with debounced writes.
- Change observers (`Cfg.observe`).
- Hot cache (in-memory source of truth).
- Table-safe pretty printer.
- Schema version tracking.
- Health check API.
- Export/import API.

#### Changed

- Config version bumped to v6.
- PERSIST extended with spoofers v4, fly v2, quests v2 keys.

#### Fixed

- Table values no longer coerced to `table: 0x...`.
- Empty config files no longer partially load.

---

### [0.30.0] — 2026-10-02

#### Semver Class
**Minor.** Forty spoofer methods (was 31).

#### Added

- `antiZoom`, `antiCinematic`, `antiWarp`, `antiDisarm`, `antiInvisible`, `antiForceField`, `antiSeatLock`, `antiSoundSpam`, `antiShakeLock`.
- `Sp.listMethods()`, `Sp.setMethod()`.
- Per-method fire counters.

#### Changed

- Spoofer version bumped to v5.

#### Security

- `antiWarp` grace window to avoid firing on own teleports.

---

### [0.29.0] — 2026-10-02

#### Semver Class
**Major.** Detects rewritten. Per-iteration walk removed. Walker is fundamentally different.

#### Added

- Multi-container BFS walk.
- Per-root time budget (800ms).
- Per-root iteration budget (40,000).
- Total scan deadline (2,500ms).
- `D.walkStats` — per-root iteration, hit, timing.
- Sticky attack flag (0.15s hold).
- Combined animation read.
- 3-tier boss cache (hot 0.3s, warm 1.2s, cold rebuild).
- Priority filter safety valve.
- Threat scoring with decay, angular bias, velocity weight, HP weight.

#### Changed

- Walker is BFS queue, not DFS stack.
- Iteration counter is per-root, not shared.
- Walk yields every 2,000 iterations (not per-iteration).

#### Fixed

- **C-04** — per-iteration throttle that reduced walk to ~200 iterations/sec.
- **C-05** — shared iteration counter that starved fallback roots.
- **C-10** — priority filter permanently blocking all bosses.

---

### [0.28.0] — 2026-10-02

#### Semver Class
**Minor.** Adds hotbar mutex and item database.

#### Added

- `hotbar.lua` — new module.
- Mutex for hotbar access.
- Item database with ~130 entries.
- Category lookup.
- Slot scanner.
- `H.equipFirstOf`.
- `H.tapVerified`.

#### Fixed

- **H-09** — crow/weapon hotbar contention.

---

### [0.27.0] — 2026-10-02

#### Semver Class
**Major.** Chest collection rebuilt from keyword matching to whitelist. Breaking change.

#### Added

- Learn mode (default on).
- Whitelist-only matching.
- `Chest.approve` / `Chest.unapprove`.
- `Chest.listSeen`.
- Reach limit (4 studs).
- Rate limits (10/min, 40/session).
- Honeypot cluster detection.
- Reject signatures.
- Prompt validity check.
- Boss-anchored corpse cycle.

#### Removed

- `ChestKeywords` no longer used in matching logic.

#### Security

- **C-01** — fixed the honeypot-triggered account ban.

---

### [0.26.0] — 2026-10-02

#### Semver Class
**Minor.** Attack rewritten for retreat stability.

#### Added

- Retreat cooldown.
- State transition logging.
- Target change logging.
- Idle reason logger.
- `A.forceStopRetreat`.
- Tick body pcall wrapper.

#### Changed

- `RetreatHP` default 0.55 → 0.30.
- `RetreatClearHP` default 0.75 → 0.55.
- `CriticalHP` default 0.15 → 0.12.
- `RetreatDelay` default 2.5 → 2.0.

#### Fixed

- **C-03** — permanent retreat lockout.
- **H-01** — watchdog clears state.

---

### [0.25.0] — 2026-10-02

#### Semver Class
**Minor.** Crow quest flow rewritten for read-only panel.

#### Added

- Read-only panel support.
- `readCrowQuests()`.
- `findCancelButton()`.
- Panel cache.
- `Q.dumpStructure()`.

#### Changed

- Quest cycle: equip crow → open menu → read → close.

#### Fixed

- **H-06** — substring match on "ok"/"yes".
- **H-10** — wrong `playerLevel` path.
- **H-11** — `readHunts` silent empty.

---

### [0.24.0] — 2026-10-02

#### Semver Class
**Minor.** Adds teleport-chase as primary movement. Fly deprecated.

#### Added

- Teleport-chase movement.
- Velocity ramp on teleport.
- Position jitter per hop.
- Walk command blend post-teleport.
- Rate limit (`TeleportCd = 0.22s`).

#### Changed

- Fly module removed from subsystem init list.

#### Deprecated

- `fly.lua`. Superseded by teleport-chase.

#### Fixed

- **C-06** — server reconciliation rejected BodyVelocity.
- **C-07** — `CFrame.new(pos, lookAt)` NaN basis vectors.
- **H-23** — "behind boss" computed from player→boss vector.
- **H-24** — chained M1s sent as identical bursts.

---

### [0.23.0] — 2026-10-02

#### Semver Class
**Minor.** Combo engine rewritten.

#### Added

- Combo engine with 4 randomized permutations.
- Alternating M1/M2 chains.
- Ultimate gating.

#### Changed

- `AtkInterval` default 0.55 → 0.38.

#### Fixed

- **C-08** — auto-block fired on every enemy.
- **H-24** — identical M1 clicks only advanced combo step 1.

---

### [0.22.0] — 2026-10-02

#### Semver Class
**Minor.** Config version bumped to v3.

#### Added

- Config keys for fly v2 (`FlyParentHead`, `FlyClaimNetworkOwner`, `FlyCFrameFallback`).
- Config keys for scanners v3 (`CrowMenuCooldown`, `CrowScanMinGap`).

#### Changed

- Config PERSIST extended.

---

### [0.21.0] — 2026-10-02

#### Semver Class
**Minor.** Spoofers v3 with reduced method count.

#### Removed

- `spoofHP`, `goUnderground`, `surfaceUp`, `checkUG`.
- Legacy counters `hpC`/`bkC`/`spdC`/`kbC`/`jmpC`.

#### Added

- Guarded pcall with first-error print.
- Write-fight detection.
- Deprecated stubs.

#### Changed

- `spoofSpeed` / `spoofJump` calibrated to 1.25× base (was 2×).
- `antiKnock` opt-in.
- `antiStun` only on `FallingDown`.

#### Security

- Reduced detection surface.

---

### [0.20.0] — 2026-10-02

#### Semver Class
**Minor.** Scanners rewritten for cache.

#### Added

- Crow tool cache with validity check.
- Crow model cache with TTL.
- Caw sound cache.
- `S.findCancelButton`.
- `S.findQuestCards`.
- `S.waitForCaw`.

#### Removed

- `deepScan`, `dumpInventory`.

#### Fixed

- **H-07** — `findCawSound` allocated full workspace tables.

---

### [0.19.0] — 2026-10-02

#### Semver Class
**Minor.** GUI rewritten to 8 tabs. Adds Targets selector.

#### Added

- Targets tab with per-region, per-boss enable toggles.
- Select All / Clear All bulk actions.
- Live "enabled X/Y bosses" counter.
- Settings tab with concealed parent toggle.

#### Changed

- GUI version bumped to v28.
- Sidebar navigation layout.

#### Fixed

- **M-25** — GUI reading chest stats from wrong config field.

---

### [0.18.0] — 2026-10-02

#### Semver Class
**Minor.** Adds optimizers with dynamic cleanup.

#### Added

- Reversible particle/light/post-effect stripper.
- Dynamic cleanup via throttled `DescendantAdded`.
- Memory GC at 60s interval.
- Restore path on disable.

#### Fixed

- **H-20** — unthrottled `DescendantAdded` hook caused scheduler starvation.

---

### [0.17.0] — 2026-10-02

#### Semver Class
**Minor.** Utils rewritten for capability probe.

#### Added

- `mouse2click` family to `U.Fn`.
- Full file-API probe.
- `U.m2()` helper.
- `U.safe()`, `U.retry()`.

#### Fixed

- **H-03** — `U.m2()` was missing.

---

### [0.16.0] — 2026-10-02

#### Semver Class
**Minor.** Loader rewritten for auto-discovery.

#### Added

- GitHub contents API discovery.
- Topological sort by `Ctx.<Slot>` references.
- Slot aliasing.

#### Changed

- Loader version bumped to v26.

---

### [0.15.0] — 2026-10-01

#### Semver Class
**Minor.** Lists rebuilt with word-boundary matching.

#### Added

- Word-boundary awareness for short entries.
- Region grouping for GUI.
- Per-boss enable flags.

#### Removed

- Character names erroneously listed as clans.
- Anime-only breathing styles.
- `reaping blades` fighting style.

#### Fixed

- **H-17** — non-weapon tools classified as weapons.
- **M-22** — boss region names not matching flat boss list.

---

### [0.14.0] — 2026-10-01

#### Semver Class
**Minor.** Attack rewritten with self-contained config.

#### Added

- Inline config defaults.
- Fly watchdog.
- Equip diagnostics.
- `A.tryCollectChestNow()`.

#### Fixed

- **H-08** — `equipWeapon` blocked 80ms in scheduler.

---

### [0.13.0] — 2026-10-01

#### Semver Class
**Minor.** Fly module rewritten.

#### Added

- Head-parent option.
- Camera detach option.
- Noclip with persistent loop.
- CFrame fallback.
- Network owner claim.

#### Fixed

- **H-22** — noclip reset by Humanoid state changes.
- **C-06** — server rejected BodyVelocity.

---

### [0.12.0] — 2026-10-01

#### Semver Class
**Minor.** Config version 2 with slot API.

#### Added

- Slot file API.
- Multiple named config slots.
- `Cfg.fileSize(slot)`.

#### Changed

- Config version bumped from 1 to 2.

---

### [0.11.0] — 2026-10-01

#### Semver Class
**Minor.** Detect rewritten with priority filter and 3-tier cache.

#### Added

- Priority filter via `Ctx.Quest.isPriority`.
- Multi-tier boss cache.
- `D.isEnemyAttacking`.
- Overlay reader.
- Alive re-verification in warm cache.

#### Fixed

- **H-04** — region-first scan was silently skipped.

---

### [0.10.0] — 2026-10-01

#### Semver Class
**Minor.** main.lua rewritten for bulletproof boot.

#### Added

- Phase isolation.
- Guard rails.
- `safeRun(label, fn)` helper.
- `Ctx.Loops` exposed for GUI display.

#### Changed

- Scheduler cadence reduced from 33 Hz to 20 Hz.

#### Fixed

- **M-05** — `loops` table built inside closure.

---

### [0.9.0] — 2026-10-01

#### Semver Class
**Minor.** Loader version 25 with dependency manifest.

#### Added

- Hardcoded manifest.
- Per-file retry.
- Three-phase load.

#### Fixed

- **H-21** — loader crashed on executor HTTP concurrency.

---

### [0.8.0] — 2026-10-01

#### Semver Class
**Minor.** GUI version 25 with dual-frame architecture.

#### Added

- Minimize-to-pill animation.
- Draggable minimized pill.
- Six tabs.
- Log manager.
- Config slot manager.

---

### [0.7.0] — 2026-10-01

#### Semver Class
**Minor.** Config version 1 established.

#### Added

- Persistence via JSON.
- `Cfg.snapshot()` and `Cfg.apply(data)`.
- `Cfg.pretty()` printer.

---

### [0.6.0] — 2026-10-01

#### Semver Class
**Minor.** Lists version 1 established.

#### Added

- Central data tables.
- `isBoss`, `isWeapon`, `isCrow`, `isQuest` matchers.

---

### [0.5.0] — 2026-10-01

#### Semver Class
**Minor.** Utils version 1 established.

#### Added

- Safe service loader.
- Capability probe.
- Input helpers.
- Character accessors.
- Tree walker.

---

### [0.4.0] — 2026-10-01

#### Semver Class
**Minor.** Attack module version 1 established.

#### Added

- Basic combat state machine.
- Skill rotation.
- Weapon auto-equip.
- Retreat logic.

#### Fixed

- **C-02** — fly nil-call killing combat loop.

---

### [0.3.0] — 2026-10-01

#### Semver Class
**Minor.** Detect module version 1 established.

#### Added

- Region-first humanoid scan.
- Threat detection via animation read.
- Block and stun detection.
- Target picker.

---

### [0.2.0] — 2026-10-01

#### Semver Class
**Minor.** Spoofers module version 1 established.

#### Added

- Client-state hardening methods.
- Write-fight detection.
- Concede-to-server after 5 corrections.

---

### [0.1.0] — 2026-09-30

#### Semver Class
**Major.** Initial public release.

#### Added

- Initial repository structure.
- Loader, main, config, lists, utils, detect, scanners, spoofers, attack, optimizers, gui modules.
- Project README.
- Basic combat loop.
- Crow quest reader.
- Chest collection via keyword matching.
- JSON-based config persistence.

#### Known Issues at Release

- **C-01** — keyword matching fired on honeypot decoys.
- **C-02** — fly nil-call.
- **C-03** — retreat loop lockout.
- **C-04** — detect walk throttled.
- **C-05** — shared iteration counter.
- **C-06** — fly rejected by server.

---

## Architecture Reference

### Module Dependency Graph

```
config ──┐
lists ───┼──► utils ──┐
         │            │
         │            ├──► detect ─────┐
         │            │                 │
         │            ├──► scanners ────┤
         │            │                 │
         │            ├──► hotbar ──────┤
         │            │                 │
         │            ├──► faction ─────┤
         │            │                 │
         │            ├──► fly ─────────┤
         │            │                 │
         │            ├──► spoofers ────┤
         │            │                 │
         │            ├──► chest ───────┤
         │            │                 │
         │            ├──► quests ──────┤
         │            │                 │
         │            └──► attack ◄─────┘
         │                   │
         │                   ▼
         └──────────────► gui ──► main
```

### Boot Sequence

```
┌──────────────────────────────────────────────────────────────┐
│ PHASE 1 · LOAD                                               │
│   For each module in MANIFEST:                               │
│     ┌─ cache lookup (_G.DINGUS_FN_CACHE)                     │
│     ├─ disk read (Dingus/cache/<name>.lua)                   │
│     ├─ CDN fetch (github → jsdelivr → statically → ghcdn)    │
│     ├─ compile (loadstring)                                  │
│     └─ execute (pcall) → returns module table                │
│   Each module slots into Ctx[<slot>]                         │
└──────────────────────────────────────────────────────────────┘
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ PHASE 2 · BOOT                                               │
│   main.boot(Ctx) called                                      │
│     P1 · state init                                          │
│     P2 · scrub movers (deferred task)                        │
│     P3 · config load                                         │
│     P4 · subsystem init in order:                            │
│          detect → scanners → hotbar → faction →              │
│          fly → spoofers → chest → quests →                   │
│          attack → optimizers → gui                           │
│     P5 · scheduler setup                                     │
│     P6 · FPS sampler                                         │
│     P7 · input toggle (RightShift)                           │
│     P8 · respawn handler                                     │
│     P9 · unload contract                                     │
└──────────────────────────────────────────────────────────────┘
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ PHASE 3 · EXPOSE                                             │
│   _G.Ctx, _G.St, _G.Cfg, _G.Atk, _G.Chest, ...               │
│   _G.DINGUS_BOOT = { ... }                                   │
└──────────────────────────────────────────────────────────────┘
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ PHASE 4 · NOTIFY                                             │
│   SetCore SendNotification (non-blocking)                    │
└──────────────────────────────────────────────────────────────┘
```

### Scheduler Tick Flow

```
RunService.Heartbeat (every frame)
         │
         ▼
   ┌─────────────────────────────────────────────┐
   │ Perf.avg_dt = 0.9*avg + 0.1*dt              │
   │ every 1s → recalcStress()                   │
   │   stress = clamp((avg_dt - 1/50)/(1/15-1/50))│
   │   backoff = 1 + stress*2                    │
   └─────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────┐
   │ budget = dt * 0.30                          │
   │ used = 0                                    │
   └─────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────┐
   │ For each loop (priority-ordered):           │
   │   if priority>=4 and stress>0.5 → skip      │
   │   if priority>=3 and stress>0.8 → skip      │
   │   if priority>1 and used>budget → break     │
   │   if now >= nextRun:                        │
   │     t0 = os.clock()                         │
   │     ok,err = pcall(loop.fn)                 │
   │     used += os.clock()-t0                   │
   │     nextRun = now + interval*backoff        │
   │     track stats                             │
   │     if err and errs>=10 → disable loop      │
   └─────────────────────────────────────────────┘
```

### Faction Decision Flow

```
        Player race?          Player rank?
              │                     │
              ▼                     ▼
        ┌────────────┐        ┌────────────┐
        │ Slayer     │        │ Hashira?   │
        │ Demon      │        │  yes / no  │
        │ Hybrid     │        └────────────┘
        └────────────┘
              │
              ▼
        ┌─────────────────────────────────┐
        │ getTargetFactions()             │
        │  Slayer (non-Hashira) → {demon} │
        │  Hashira              → {demon} │
        │  Demon                → {slayer}│
        │  Hybrid               → both    │
        └─────────────────────────────────┘
              │
              ▼
        ┌─────────────────────────────────┐
        │ For each candidate mob:         │
        │   faction = L.factionOf(name)   │
        │   if faction ∈ targets → keep   │
        │   elif neutral and flag → keep  │
        │   else → reject                 │
        └─────────────────────────────────┘
              │
              ▼
        ┌─────────────────────────────────┐
        │ pickTarget applies priority:    │
        │   Hashira + Upper Moon → +50    │
        │   Demon  + Hashira     → +50    │
        │   base score = -distance        │
        └─────────────────────────────────┘
```

### Farm Loop State Machine

```
         ┌─────────┐
         │  IDLE   │◄───────────────────────┐
         └────┬────┘                        │
              │ S.cbt = true                │
              ▼                             │
         ┌─────────┐                        │
         │  SCAN   │                        │
         └────┬────┘                        │
              │ target found                │
              ▼                             │
         ┌─────────┐   target locked         │
    ┌───►│ STRIKE  ├─────────────────────────┤
    │    └────┬────┘                        │
    │         │                             │
    │         │ stunned                     │
    │         ▼                             │
    │    ┌─────────┐                        │
    │    │ RECOVER │  recoverFreeze()       │
    │    └────┬────┘                        │
    │         │                             │
    │         └─────────────────────────────┘
    │                                       │
    │         target died                   │
    │         ┌───────────────────────┐     │
    └─────────┤      LOOT_WAIT        │     │
              │ wait for corpse drop  │     │
              └───────────┬───────────┘     │
                          │                 │
                          └─────────────────┘
```

### Chest Collection Flow

```
┌──────────────────────────────────────────────────────────────┐
│ boss dies → S.bossLootPos = corpse.Position                  │
│             S.bossLootTime = now                              │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ attack tick sees S.bossLootPos and (now - bossLootTime < 4)   │
│ → teleport HRP to corpse + hold                              │
│ → state = LOOT_WAIT                                          │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ chest.lua collectPassive runs on scheduler (1.5s interval)   │
│   sweep() = sweepChests() → sweepSouls() → sweepLoot()       │
└──────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
       ┌────────────┐  ┌────────────┐  ┌────────────┐
       │ sweepChests│  │ sweepSouls │  │ sweepLoot  │
       │ Chests     │  │ Soul/Souls │  │ LootDrops  │
       │ folder +   │  │ DemonSoul  │  │ folder +   │
       │ Chest tag  │  │ tags       │  │ LootDrop   │
       └────────────┘  └────────────┘  └────────────┘
              │               │               │
              └───────────────┼───────────────┘
                              ▼
                    ┌────────────────────┐
                    │ firePrompt 4-tier: │
                    │ 1 fireprox         │
                    │ 2 InputHoldBegin   │
                    │ 3 KeyboardKeyCode  │
                    │ 4 Triggered signal │
                    └────────────────────┘
```

### Cross-Device Input Resolution

```
User fires skill "Z"
         │
         ▼
   ┌───────────────────┐
   │ U.fireSkill("Z")  │
   └─────────┬─────────┘
             │
             ▼
   ┌─────────────────────────────┐
   │ findSkillButton("Z")        │
   │   PlayerGui                 │
   │   .ComponentsHolder         │
   │   .BottomHolder             │
   │   .SkillsHolder             │
   │   .<child with KeyLabel "Z">│
   └─────────┬───────────────────┘
             │
      ┌──────┴──────┐
      │             │
      ▼             ▼
   found        not found
      │             │
      ▼             ▼
 fireSignal    U.tap("Z")
 MouseButton1  ──► VIM keyDown
 Down/Up          keyUp
```

---

## Diagrams

### Text Flow: Loader → Main → Scheduler

```
loadstring(GitHub)
       │
       ▼
   loader.lua ───────► MANIFEST walk ──────► Ctx
       │                                      │
       │                                      │
       └──► main.boot(Ctx) ◄──────────────────┘
                │
                ▼
       ┌────────────────────┐
       │ init subsystems    │
       │ (11 modules)       │
       └─────────┬──────────┘
                 │
                 ▼
       ┌────────────────────┐
       │ build loop table   │
       │ (8 loops)          │
       └─────────┬──────────┘
                 │
                 ▼
       ┌────────────────────┐
       │ RunService         │
       │ .Heartbeat         │
       └─────────┬──────────┘
                 │
                 ▼
       ┌────────────────────┐
       │ runTick()          │
       │   priority-ordered │
       │   budget-capped    │
       │   stress-adaptive  │
       └────────────────────┘
```

### State Diagram: Player Faction Change

```
              ┌──────────────┐
              │   unknown    │
              └──────┬───────┘
                     │ detect()
        ┌────────────┼────────────┐
        │            │            │
        ▼            ▼            ▼
   ┌────────┐   ┌────────┐   ┌────────┐
   │ slayer │   │ hybrid │   │ demon  │
   └───┬────┘   └───┬────┘   └───┬────┘
       │            │            │
       │ rank       │            │
       │ check      │            │
       ▼            │            │
   ┌────────┐       │            │
   │hashira?│       │            │
   └───┬────┘       │            │
       │            │            │
    yes│ no         │            │
       ▼ ▼          │            │
   target demon     target both  target slayer
   + upper moon     + neutral    + hashira boost
   boost            optional
```

---

## Breaking Changes Log

Every breaking change across the project's lifetime, in reverse chronological order.

### 0.37.0 — Synerox Farm Rebuild
**What broke:** `fly.lua` no longer wraps `BodyMovers`. `attack.lua` no longer uses `mouse1click` on PC only. `chest.lua` no longer uses whitelist matching.
**Migration:** None required for GUI users. Programmatic callers using `Ctx.Fly.start()` still work — the method now enables farm movement instead of fly. `Ctx.Chest.approve(name)` is a no-op. If you depended on whitelist semantics, migrate to `Ctx.Chest.setEnabled` toggles.

### 0.29.0 — Detect Walker Replaced
**What broke:** Any code calling into `detect.lua` internals that relied on DFS traversal order.
**Migration:** None required for public API. `scanBosses`, `scanMobs`, `pickTarget` all work identically.

### 0.27.0 — Chest Keyword Matching Removed
**What broke:** `Cfg.ChestKeywords` no longer used for matching.
**Migration:** Populate `Cfg.ChestWhitelist` via `Chest.approve(name)` after observing items in-game.

### 0.24.0 — Fly Deprecated
**What broke:** `fly.lua` no longer initialized. `Ctx.Fly.start` undefined.
**Migration:** No action required. Attack uses teleport-chase. Fly module retained as dead code.

### 0.16.0 — Hardcoded Manifest Removed
**What broke:** Loader no longer reads a fixed file list. It discovers via GitHub API.
**Migration:** None. Fallback list retained for API failures.

### 0.15.0 — Lists Pruned to Endgame Bosses
**What broke:** Map 1 and Map 2 bosses removed from `L.bosses`.
**Migration:** None if endgame only. Re-add specific bosses if you need them.

### 0.6.0 — Central Lists Module
**What broke:** Keyword lists moved from inline literals to `lists.lua`.
**Migration:** Consumers now read `Ctx.Lists` instead of hardcoded arrays.

---

## Migration Guides

### Migrating from 0.36.0 to 0.37.0 (Synerox Farm)

If you wrote code that depended on the old attack flow:

**Old (works, deprecated):**
```lua
_G.Atk.forceStopRetreat()
_G.St.retreating  -- was a boolean
```

**New (recommended):**
```lua
-- Retreat is now a no-op — the farm loop never retreats
-- The new state machine uses S.cbtS:
--   IDLE, NO_CHAR, DEAD, RECOVER, SCAN, STRIKE, LOOT_WAIT, NO_TARGET
print(_G.St.cbtS)
```

**Old combat flags still work:**
```lua
_G.St.cbt = true   -- unchanged
```

### Migrating from 0.39.0 to 0.40.0 (Toolkit)

`scanners.lua` v5 exposed `S.findCrowTool()`, `S.findCancelButton()`, `S.readCrowQuests()`. These were moved under `S.crow.*`:

**Old:**
```lua
_G.Scan.findCrowTool()
```

**New:**
```lua
_G.Scan.crow.tool()
```

Aliases were NOT added. Update call sites. Only `quests.lua` and `gui.lua` referenced the old paths, and both were updated in 0.40.0.

### Migrating from 0.40.0 to 0.41.0 (Faction + GUI)

`mkDropdown` behaviour changed. If you generated a dropdown with the old cycling behaviour and depended on it:

**Old:** Click cycles to next option.
**New:** Click opens a modal list. Clicking an option closes the modal.

No API change to the widget constructor. Behaviour change only.

---

## Security Log

Every security-relevant change in reverse chronological order.

### 0.41.0
- Faction detection reads only local property values via `pcall`. No remote calls, no attribute writes.

### 0.40.0
- `hotbar.tap` now fires on-screen buttons where possible, avoiding raw key simulation which some anti-cheats flag more heavily.
- `scanners.chests` filters by `ChestState` attribute, skipping `Opened`/`Despawned` and rejecting `Locked` prompts.

### 0.38.0
- `U.notify` rate-limited to prevent notification spam detection.
- `U.httpGet` sends cache-busting query param on fallback path.

### 0.37.0
- `chest.lua` respects `DropOwnerUserId` and `DropReservedFor` attributes. Will not attempt to claim drops that belong to other players.
- `attack.lua` fires M1 via `InputHandler.VirtualPress` where available, matching the game's own input path rather than synthesizing raw mouse events.
- `lists.lua` faction tables derived from static in-game observation, not from network traffic.

### 0.36.0
- Loader probes prerequisites and fails loud if `loadstring` or `game.HttpGet` are missing.
- Session-level connection guard prevents duplicate heartbeat.

### 0.34.0
- Added HTTP headers to reduce executor fingerprint at CDN edge.

### 0.27.0
- **Fixed honeypot-triggered ban.** Keyword matching on loot could fire on trap instances named with `ore` substring. Whitelist-only matching eliminates this vector.
- Added honeypot cluster detection.
- Added reach limit (4 studs).
- Added rate limits (10/min, 40/session).

### 0.21.0
- Cut cosmetic spoofer writes that were detection signals.
- Reduced `spoofSpeed` / `spoofJump` multipliers from 2× to 1.25×.

### 0.30.0
- `antiWarp` method added with grace window to avoid firing on own teleports.

---

## Deprecation Notices

### `fly.lua` (original BodyMover implementation)
**Deprecated in:** 0.24.0
**Reason:** Server reconciliation rejects BodyVelocity motion.
**Status:** Retained. Current version implements farm-movement instead of fly. Rename pending.

### `Cfg.ChestKeywords`
**Deprecated in:** 0.27.0
**Reason:** Substring keyword matching is unsafe.
**Removal planned:** After user-supplied whitelists mature.

### `D.readOverlay`
**Deprecated in:** 0.29.0
**Reason:** Superseded by structured threat model.
**Removal planned:** When GUI diagnostics are extended.

### `MobKeywords` list
**Deprecated in:** 0.15.0
**Reason:** Mob targeting disabled (boss-only mode).
**Removal planned:** Not planned. Retained for potential future use.

### `attack.lua` retreat thresholds
**Deprecated in:** 0.37.0
**Reason:** Synerox farm loop does not retreat.
**Status:** Config keys retained as no-op for compat.
**Removal planned:** 0.45.0.

### `scanners.lua` `S.findCrowTool`, `S.findCancelButton`, `S.readCrowQuests`
**Deprecated in:** 0.40.0
**Reason:** Moved to `S.crow.*` namespace.
**Removal planned:** Already removed. Update call sites.

---

## Cross-Device Capability Matrix

| Capability | PC Synapse | PC Xeno | PC Solara | Mobile Delta | Mobile Solara | iOS |
|---|---|---|---|---|---|---|
| `game:HttpGet` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `loadstring` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `request()` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| `writefile`/`readfile` | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| `fireproximityprompt` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `fireclickdetector` | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| `firetouchinterest` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `gethui` | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| `setthreadidentity` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| `firesignal` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `identifyexecutor` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| VIM mouse | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| VIM key | ✓ | ✓ | ✓ | partial | partial | partial |
| Skill buttons | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `CollectionService` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

**Legend:** ✓ works · ✗ missing · partial inconsistent

---

## Module Version Map

| Module | Version | Purpose |
|---|---|---|
| `loader.lua` | v37 | Bootstrap, module fetch, execution |
| `main.lua` | v38 | Boot orchestrator, scheduler |
| `utils.lua` | v4 | Cross-device abstraction |
| `config.lua` | v9 | Configuration, persistence |
| `lists.lua` | v11 | Data tables (bosses, NPCs, quests, faction) |
| `detect.lua` | v9 | Humanoid scanner, threat model |
| `scanners.lua` | v6 | General scan toolkit + crow helpers |
| `hotbar.lua` | v4 | Hotbar mutex, item DB, auto-equip |
| `faction.lua` | v1 | Role detection, NPC faction classifier |
| `fly.lua` | v7 | Synerox farm movement |
| `spoofers.lua` | v6 | Client-state hardening |
| `chest.lua` | v8 | Loot, chest, soul collection |
| `quests.lua` | v9 | NPC quest pipeline, crow routing |
| `attack.lua` | v25 | Combat state machine, faction targeting |
| `optimizers.lua` | v3 | Workspace, lighting optimizer |
| `gui.lua` | v40 | Control panel |
| `debug-loader.lua` | v2 | Diagnostics |

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
