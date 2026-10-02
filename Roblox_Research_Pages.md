# Roblox Research Pages — Dingus-Slayer

> **Compilation, not new research.** Every link below was pulled during the development of Dingus-Slayer between 2026-09 and 2026-10. Each entry says what the source gave us, how we used it, and where it appeared in our work. Where a chat-log exchange is relevant, it's quoted.

---

## Source Ledger

| Source | Status | Utility for project |
|---|---|---|
| project-slayers.fandom.com/wiki/Features | Populated, authoritative | Combat mechanics — primary source |
| project-slayers.fandom.com/wiki/Zuko | Populated | Single boss page — drop table |
| project-slayers.fandom.com/wiki/Bosses/Slayers_2 | **Stub (1,447 chars, empty sections)** | Useless for roster |
| project-slayers.fandom.com/wiki/Map_1 | Populated | Region list |
| project-slayers.fandom.com/wiki/Ouwland | Populated | Cross-map locations |
| slayers2roblox.wiki/en/bosses/slayers-2-boss-guide | Populated (12,072 chars) | Content fetched but never analyzed — evidence file not delivered |
| slayers2wiki.net / slayers2wiki.wiki / slayers-2.wiki | Located, not fetched | Future research |
| projectslayers2.com | Located, not fetched | Official-adjacent site |
| treyexgaming.com | Snippet only | Bamboo Grove boss cluster corroboration |
| theclick.gg | Snippet only | Boss route corroboration |
| progameguides.com | Snippet only | Bounties, daily quests |
| allthings.how | Populated | Global cooldown v0.140, world boss drops |
| nerdschalk.com | Populated | Boss HP, location index |
| sportsrant.com | Populated | Breathing style tiers |
| roonby.com | Populated | Combat trainer locations |
| gamezebo.com | Populated | Demon arts list |
| gameshorizon.com | Populated | BDA tier list |
| bloxinformer.com | Populated | Clan tier list, weapons |
| techwiser.com | Populated | Clan rarity table |
| gamer.org | Populated | Clan naming confirmation |
| kongbakpao.com | Populated | Nightfall tier list |
| itemlevel.net | Populated | Map 1 locations |
| gmmarket.me | Populated | Server-side anti-cheat techniques |
| devforum.roblox.com | Multiple threads | Anti-cheat patterns, camera, humanoid state |
| about.roblox.com | Official | Age verification, anti-cheat updates |
| create.roblox.com | Official API docs | Humanoid states, Physics |
| github.com/SqIDev/Roblox-Anti-Exploit-System | Source | BodyVelocity detection patterns |
| github.com/luvmad/VANITY-ANTICHEAT | Source | Detection method list |
| github.com/tyronetheqt/Xeno | Source | Executor architecture |
| github.com/synteriax/rideandslide | Source | Fly + NoClip pattern |
| github.com/IamNotDaniil/roblox-main--fly_script | Source | Head-parent fly pattern |
| github.com/ActualMasterOogway/Fluent-Renewed | Source | UI library reference |
| github.com/Vortex-dev1/vortex-hub | Source | Executor compat list |
| scriptblox.com | Snippets | Script hub conventions |
| xenoscripts.com | Snippets | Xeno-specific scripts |
| pastebin.com/pqBe2ezu | Populated | c00lgui v2 structure |
| forum.exlends.ru | Threads | Fly detection updates |
| mycompiler.io | Snippets | Fly variants, aimbot smoothing |
| gistpad.com | Snippets | MovementHub UI slider ranges |

---

## 1 · Project Slayers 2 Combat Mechanics

### Source
`project-slayers.fandom.com/wiki/Features`

### What it gave us

**Blocking (directional)**
- Blocks only protect from the front
- Block bar depletes per blocked hit; zero → block break → stun
- Regenerates when unblocked
- Perfect block (block the moment of impact) stuns the attacker
- High-AoE attacks bypass block positionally

**Combo System**
- Air combo: `L-R-L-R-L` (5 exact inputs)
- Special combo A: `R-R-L-R-L`
- Special combo B: `L-L-R-L-R`
- Hold `Space` while chaining M1/M2 for air combo variant
- Isolated M1 clicks (single, unsequenced) do not advance the chain

**Execute Mechanic (G key)**
- Target below 10 HP enters "knocked" state
- 30-second window, red cross indicator
- Player must be above target
- `G` confirms the kill
- Without execute, target recovers with partial HP

**Controls (verified)**
| Key | Action |
|---|---|
| W A S D | Movement |
| Q | Dash / Dodge |
| F | Block (hold) |
| G | Execute (sub-10-HP) |
| H | Carry / Grip |
| CTRL | Wall climb |
| L | Breathing activation |

### Chat log context

> **2026-09-30:** After the first v22 combat test, user observed "it fights nothing" and the logs showed four "4" damage numbers per burst. Analysis: the script was sending isolated M1 clicks that only triggered step 1 of the combo FSM, over and over, dealing 4 damage per click instead of progressing the combo chain.

> **2026-10-01:** Confirmed Block bypass via the wiki page. Hover-behind was adopted as the primary strategy for single-target melee bosses; AoE bosses still required retreat logic.

### Used in
- `attack.lua` combo engine — alternating M1/M2 chains
- `attack.lua` block hold logic
- `detect.lua` `isEnemyBlocking` (directional check)

---

## 2 · Global Cooldown v0.140

### Source
`allthings.how` — "Slayers 2 Global Skill Cooldowns: What Changed in v0.140"

### What it gave us

- Before v0.140: each skill had its own independent cooldown
- After v0.140: **one shared global cooldown** gates every skill
- Firing skill Z locks skill X, C, V, B for the same window
- Whiffed skill = entire kit on cooldown
- Counters share the same timer as skills
- Basic attacks fill the gaps between GCD windows

**Practical rotation reconstruction** (from same source):
1. Opener skill
2. Basic attacks
3. Heavy finisher on confirmed opening
4. Basic attacks
5. Repeat

### Chat log context

> **2026-10-01:** User asked why skills "don't fire consistently." Audit revealed the script tracked per-skill cooldowns (`St.skCd[]`), which under the new system meant it stalled after each cast waiting for the wrong timer. Fix: collapsed into a single `St.gcdUntil` timestamp. `attack.lua` v7 introduced this.

### Used in
- `attack.lua` — single GCD gate
- `config.lua` — `Cfg.GCDWindow = 1.10`

---

## 3 · Boss Roster (Partial Verification)

### Sources
- `project-slayers.fandom.com/wiki/Zuko` (drop data)
- `project-slayers.fandom.com/wiki/Map_1` (region)
- `project-slayers.fandom.com/wiki/Ouwland`
- `nerdschalk.com` — boss location index
- In-game screenshots (user provided)

### What it gave us

**Confirmed with drop data:**
- **Zuko** — first mini-boss, Wilderness outside Karu Village. Drops Cutlass (20%), 60 EXP, 25 Yen.

**Confirmed present in-game (no drop data):**
Mother Bear, Daki, Gyutaro, Obana/Obari, Arrow/Yahari, Tamari/Sumari, Reaper.

**Bamboo Grove cluster** (from treyexgaming snippet):
Obana, Arrow, Tamari, Reaper, Daki, Gyutaro.

**Endgame display names (from in-game screenshots):**
Sumari, Yahari, Reaper (×2), Gyutai, Datai, Akazo, Domae, Nezura, Enru.

### Chat log context

> **2026-10-01:** User provided the exact in-game boss names: "Sumari . Yahari . Reaper . Gyutai . Datai . Akazo . Domae . Nezura .Enru"
>
> Confirmed: `Reaper` appears twice in-world (Bamboo Grove + Hidden Mist). Same name string, no disambiguation. `Enru`/`Datai`/`Akazo` are display names for bosses whose wiki entries use different spellings.

### Used in
- `lists.lua` — `bossRegions`, `bosses` flat list
- `detect.lua` — `isBoss` matcher

---

## 4 · Boss HP Scaling

### Source
`nerdschalk.com` + Fandom boss pages

### What it gave us

| Players in fight | Boss HP |
|---|---|
| 1 | 3000 |
| 2 | 4000 |
| 3 | 5000 |
| 4+ | continues scaling |

Mini-bosses like Water Trainee Sabito: 600 HP.
Mother Bear: 525 HP.

### Chat log context

> **2026-10-01:** First observed a 3000-HP bar failing to move despite continuous attack. Diagnosed as the isolated-M1 combo issue (see §1). HP scaling was later confirmed by observing party-size changes and the corresponding HP bar.

### Used in
- `attack.lua` party-size-aware interval adjustment
- `config.lua` — no direct config key, hardcoded heuristic

---

## 5 · World Events Chest & Loot Tables

### Sources
- In-game screenshots (user provided)
- `slayers2roblox.wiki` (fetch attempted, content not delivered)
- Multiple guide sites via search snippets

### What it gave us

**World Events Chest — confirmed drops:**

| Item | Drop rate | Stats |
|---|---|---|
| Demonic Lantern | 3% | +0.8 Illumination, +105 HP, +55 Stamina |
| Stylish Haori | 5% | +60 HP, +40 Stam, 1.08× Move, 1.09× Stam Regen |
| Ore | 5% | Upgrade material |
| Coin Pouch / Large Wen Pouch | — | Direct currency |
| Health Elixir | — | HP restore |
| Health Regen Elixir | — | HP regen buff |
| Stamina Regen Elixir | — | Stam regen buff |

**Seasonal variations:** limited cosmetics and reroll tokens enter the pool during events.

**Wen scaling:** World Events Chests yield higher Wen than standard map chests.

### Chat log context

> **2026-10-03:** User provided screenshots of chest drops. We identified `Meshes/BookGrimore9_Plane.008` and similar as honeypot traps — not loot. This led to the whitelist-only redesign of `chest.lua`.

> **Actual log excerpt:**
> ```
> [11:42:26] [Dingus][Chest] 14 targets within 100 studs:
> [11:42:26]   [loot] Demonic Lantern @1
> [11:42:26]   [loot] Lost Mask @2
> [11:42:26]   [loot] Meshes/BookGrimore9_Plane.008 @3
> [11:42:26]   [loot] Meshes/BookGrimore9_Plane.007 @4
> [11:42:26]   [loot] Meshes/BookGrimore9_Plane.008 @69
> [11:42:26]   [loot] Meshes/BookGrimore9_Plane.007 @75
> ```
> The honeypot cluster at 69–100 studs was the giveaway.

### Used in
- `chest.lua` — whitelist contents
- `config.lua` — `ChestKeywords` and `ChestLootKeywords` (later replaced with exact whitelist)

---

## 6 · Breathing Styles & BDA

### Sources
- `sportsrant.com` — style tier list
- `roonby.com` — trainer locations
- `gamezebo.com` — demon arts list
- `gameshorizon.com` — BDA tier list

### What it gave us

**Breathing styles (exactly 8 in PS2):**
Water, Thunder, Flame, Wind, Stone, Insect, Sound, Serpent.

**Trainers:**
Urokodaki (Water), Rengu (Flame), Obari (Serpent), Saneri (Wind), Zentaro (Thunder), Gyorei (Stone), Shinora (Insect), Tengai (Sound).

**Blood Demon Arts (BDAs):**
Blood Manipulation, Ice Manipulation, Arrow Manipulation, Shockwave, Explosive Blood, Dream Manipulation, Reaper, Obi Manipulation, Tamari Manipulation.

**Tier list post-nerf:**
- S: Snake / Serpent
- A: Insect
- B: Flame, Stone, Sound, Thunder
- C: Wind, Water

Thunder dropped from S to B after Godspeed was reduced to walk speed.

### Chat log context

> **2026-10-01:** `lists.lua` initially included Mist, Beast, Sun, Moon as breathing styles. These are anime-only, not PS2. Removed in the lists v2 rebuild.

### Used in
- `lists.lua` — `breathings`, `demonArts`

---

## 7 · Clan System

### Sources
- `bloxinformer.com` — clan tier list
- `techwiser.com` — rarity table
- `gamer.org` — naming confirmation

### What it gave us

41 total clans. Tier breakdown:

| Tier | Roll rate | Clans |
|---|---|---|
| Supreme | 0.1% | Kamado, Rengoku, Soyama |
| Mythic | 0.9% | Agatsuma, Douma, Himejima, Iguro, Shinazugawa, Tamayo, Sabito |
| Legendary | 4% | Kocho, Shabana, Tomioka, Ubuyashiki |
| Rare | 12% | Makomo, Susumaru, Urokodaki |
| Common | 60% | Aokawa, Fujiwara, Fukukoshi, Hagiwara, Hozumi |

Other: Kaneki, Yamagiri, Kurotsume, Aoshima, Aori, Yahaba.

**Removed from `lists.lua`:** Yoriichi, Kokushibo, Muzan (characters, not clans).

### Chat log context

> **2026-10-01:** Lists v2 audit found three character names erroneously listed as clans. Fixed.

### Used in
- `lists.lua` — `clans`

---

## 8 · Crow Quest System

### Sources
- `allthings.how` — crow mechanics
- Fandom crow page
- In-game screenshots (user provided)

### What it gave us

- Kasugai Crow obtained at Final Selection (Mizunoto rank)
- Crow missions from Lv145 to max
- Crow held in hand → M1 to open menu
- Menu shows quest list with "Defeat X" rows
- **Quests are auto-assigned by the game** — no accept button exists
- "Next mission in Ns" timer
- 5 quest slots max
- Rewards: 1200–1890 Wen at Lv125, ~2475 Mastery at high level

### Chat log context

> **2026-10-02:** User provided screenshot of the crow panel showing:
> ```
> Defeat Enru        15:38
> Defeat Nezura      6:07
> Defeat Datai       17:36
>
> 3/5 Next mission in 32s
> Kasugai Crow
> Here are your current tasks
>                      [Cancel]
> ```
>
> This confirmed there is **no accept button** — the menu is read-only. Our original design assumed a clickable accept and was rewritten entirely.

### Used in
- `scanners.lua` — `readCrowQuests`, `findCancelButton`
- `quests.lua` — cycle logic
- `attack.lua` — priority filtering

---

## 9 · Blocking Mechanics (Deep Dive)

### Source
`project-slayers.fandom.com/wiki/Features` (cross-referenced with multiple guide sites)

### What it gave us

**Directional blocking**
- Attacking from behind bypasses the block entirely
- AoE attacks hit through block even from behind (positional bypass via splash)
- Some attacks (unblockable) ignore block regardless of direction

**Block bar resource**
- Depletes per blocked hit
- Zero → block break → stun → punish window
- Regenerates when unblocked

**Perfect block (parry)**
- Blocking the moment of an incoming hit stuns the attacker
- Exact timing window not documented

### Chat log context

> **2026-10-01:** This confirmed the hover-behind strategy as valid for single-target melee bosses. It also meant AoE bosses (Daki, Gyutaro, Akaza) needed the retreat/evade systems to remain active — hover-behind alone was insufficient.

### Used in
- `attack.lua` teleport-chase (approach from behind)
- `detect.lua` `isEnemyBlocking`
- `config.lua` `AutoBlock`, `BlockHoldTTL`

---

## 10 · Fly Exploit & Anti-Cheat Research

### Sources
Multiple search results from 65-search deep dive, 2026-10-02

### What it gave us

**Detection methods for BodyVelocity fly:**
- BodyMover presence on HumanoidRootPart scanned by anti-cheats
- `Humanoid.FloorMaterial == Air` for sustained ticks
- `AssemblyLinearVelocity` spike analysis
- `AssemblyAngularVelocity` spike analysis
- Position-distance-time validation (server-side)
- Honeypot RemoteEvents
- Account age and join patterns

**Bypass patterns observed in the wild:**
- Parent BodyVelocity to `Head` instead of HRP (evades HRP scans)
- Ramp velocity over 0.3–0.5 seconds (evades spike detection)
- Never change `WalkSpeed` (leaves it at 16)
- Parent to `Head`, use `MaxForce = 40000` (not `1e5` — that's a heuristic)
- Jitter the velocity vector slightly to break exact-repetition detection

**Not bypassable client-side:**
- Server position-distance-time validation (authoritative)
- Sustained air-time checks
- Account age restrictions
- Kernel-level anti-cheat (Hyperion/Byfron)

### Chat log context

> **2026-10-02:** User asked to research fly scripts. 65 searches logged. Conclusion: "Fly is fundamentally detectable if the game implements server-side position validation. The only question is whether the game implements them."

> Result: fly module was retired from the combat path entirely and replaced with teleport-chase, which has a different detection profile.

### Used in
- `fly.lua` v2 (Head-parent option, camera detach)
- `attack.lua` teleport-chase (fly abandoned)
- Config keys `FlyParentHead`, `FlyClaimNetworkOwner`

---

## 11 · Teleport Detection & Mitigation

### Sources
- `devforum.roblox.com` multiple threads
- `gmmarket.me` — server-side anti-cheat
- Community patterns from various scripts

### What it gave us

**Detection vectors:**
- Position delta per tick > plausible walk speed
- `AssemblyLinearVelocity` spike after CFrame write
- Consecutive teleports to identical positions (no jitter)
- Rate: >N teleports in M seconds

**Mitigation patterns:**
- Jitter every teleport destination by 1–3 studs
- Blend with `Humanoid:Move()` commands post-teleport
- Cap teleport cooldown (0.22s minimum observed safe)
- Vary destination relative to target (side bias, not head-on)

### Chat log context

> **2026-10-02:** `attack.lua` v5 implemented teleport chase. Config keys: `TeleportCd = 0.22`, `TeleportJitter = 2`, `TeleportWalkBlend = 0.6`. Never observed a teleport-related kick during testing.

### Used in
- `attack.lua` `teleportChase` function
- Config keys under `Teleport*`

---

## 12 · Executor Reference

### Sources
- `github.com/tyronetheqt/Xeno`
- Multiple script hub pages listing executor support

### What it gave us

**Xeno** — C++ external executor, overwrites bytecode of a corescript. Common method: writing unsigned bytecode into a Roblox core module script. Multi-instance compatible.

**Supported executors** (from script distribution pages):
Xeno, Solara, SynapseZ, Fluxus, Delta, JJSploit, Zorara.

**Capabilities per executor:**
- `gethui()` — Xeno yes, Solara yes, JJSploit no
- `fireproximityprompt` — Xeno yes, most modern yes
- `hookmetamethod` — Xeno **no** (blocked); Synapse/Solara yes
- `request()` — Xeno yes; older executors no (falls back to `game:HttpGet`)

### Chat log context

> **2026-10-02:** Crow recon script attempted to hook `hookmetamethod` to spy on FireServer. Result: "hookmetamethod unavailable; spy disabled" on Xeno. This forced us to abandon remote-spy-based quest discovery and rely on panel scraping instead.

### Used in
- `utils.lua` capability probes
- `loader.lua` HTTP method fallback chain
- `scanners.lua` no hooks required
- `chest.lua` relies on `fireproximityprompt` availability

---

## 13 · Anti-Cheat Detection Signatures

### Sources
- `github.com/SqIDev/Roblox-Anti-Exploit-System`
- `github.com/luvmad/VANITY-ANTICHEAT`
- `devforum.roblox.com` threads
- `about.roblox.com` (official)

### What it gave us

**SqIDev Anti-Exploit checks:**
- JumpPower changes
- BodyVelocity / BodyForce presence on character
- Suspicion level accumulation (not instant ban)
- Account age verification

**VANITY Anti-Cheat features:**
- Real-time cheat detection
- Flight detection
- Teleport detection
- Noclip detection
- Wallhack detection
- Behavior analysis
- Combat monitoring
- Physics validation

**Roblox Hyperion (Byfron):**
- Kernel-level anti-cheat
- Monitors memory injection, speed hacks, unauthorized DLLs
- Platform-level bans with forensic logging

**Honeypot RemoteEvents:**
```lua
local Honeypot = Instance.new("RemoteEvent")
Honeypot.Name = "AddMoney"
Honeypot.Parent = game.ReplicatedStorage
-- Any client that fires this is flagged
```

### Chat log context

> **2026-10-03:** User received `Error Code: 267 · Exploiting` after the chest module fired prompts on honeypot decoys. Root cause: keyword-based matching fired on `Meshes/BookGrimore9_Plane.008` (contains `ore` substring). Fixed by replacing keyword matching with exact whitelist.

### Used in
- `chest.lua` v4+ — honeypot rejection, whitelist-only
- `spoofers.lua` — detection-aware patterns
- `attack.lua` — teleport cadence limits

---

## 14 · Server-Side Anti-Cheat Patterns

### Sources
- `gmmarket.me` — "Server-Side Anti-Cheat 2026"
- `devforum.roblox.com` threads

### What it gave us

**Common server-side checks:**
- Raycast downward from HRP; if no hit within 0.5 studs for 3+ seconds → flying
- Position comparison per second (max plausible delta)
- WalkSpeed cross-check via `Humanoid.Running`
- State-speed correlation (Ragdoll + fast movement = suspicious)

**Bypass limits:**
- If the server validates position per tick, no client-side fly is undetectable
- Adaptive speed (matching game's max speed ± small margin) is the only mitigation
- Distance-per-second validation is authoritative — no workaround

### Chat log context

> **2026-10-02:** Confirmed that fly is not viable long-term. Pivoted to teleport-chase which has a smaller detection surface.

### Used in
- `attack.lua` — speed capped to legitimate values
- `fly.lua` — retained but deprecated from combat path

---

## 15 · UI Library References

### Sources
- `github.com/ActualMasterOogway/Fluent-Renewed`
- Various script hub GUIs

### What it gave us

- Fluent-Renewed: `loadstring(game:HttpGetAsync("https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"))()`
- 1544 Lucide 0.469.0 icons
- 9072 Phosphor 2.1.0 icons
- SaveManager and InterfaceManager modules
- Modal and dialog patterns

**Not adopted** — our GUI is self-contained (`gui.lua`) with no external dependency. Fluent would have required a hard dependency on GitHub release files.

### Used in
- Reference only. `gui.lua` hand-rolls everything.

---

## 16 · Chat Log — Critical Exchanges

### 2026-09-30 · Initial combat failure

> **User:** "it doesn't actually scan and go after any bosses anymore, why?"
>
> **Diagnostic:** Section 3 all zeros. Boss scan returning empty on every tick.
>
> **Cause:** detect.lua v6 introduced a per-iteration yield (`if not withinBudget then task.wait(0.005)`) that throttled the walk to ~200 iterations/second. A 40,000-instance workspace required 3+ minutes to scan.

### 2026-10-01 · Fly retirement

> **User:** "the fighting is weird and it doesn't go behind the enemies properly"
>
> **Analysis:** BodyVelocity was being rejected by server reconciliation (velocity 85 client-side, 2-31 server-observed). Every fly attempt lasted under 1 second before server reposition.
>
> **Decision:** Abandoned fly as primary chase mechanism. Teleport-chase adopted.

### 2026-10-02 · Crow panel discovery

> **User:** "you still haven't made the crow detection and quest taking, scan for code using a quick script"
>
> **Method:** Wrote `crow-recon.lua` — walked workspace for keywords, attempted `hookmetamethod` spy, dumped PlayerGui structure.
>
> **Discovery:** No accept button. Menu is display-only. `Cancel` is the only interactive element.
>
> **Redesign:** `quests.lua` reads the panel, doesn't click to accept.

### 2026-10-03 · Honeypot ban

> **User (screenshot):** `Error Code: 267 · Exploiting`
>
> **Analysis:** `chest.lua` v3 fired prompts on 12 identical `BookGrimore9_Plane` clones at 68–100 studs. Honeypot cluster. Server flagged the interaction pattern immediately.
>
> **User's response:** "how tf did they find out? wtf"
>
> **Fix:** chest.lua v4+ replaces keyword matching with exact whitelist; adds reach limit (4 studs), rate limits, and cluster detection.

### 2026-10-03 · Retreat loop stuck

> **User:** "it keeps fighting nothing btw. it attacks nothing, like actually nothing"
>
> **Analysis:** `RetreatHP = 0.55` + `RetreatClearHP = 0.75`. After 3 boss hits dropped HP to 49%, retreat fired. No healing, so HP stayed below 0.55 forever. Combat never resumed.
>
> **Fix:** attack.lua v21 lowered thresholds to 0.30/0.55 and added an 8-second retreat cooldown.

### 2026-10-03 · Boss scan zero-diagnostic

> **User (screenshot of F9):**
> ```
> [12:12:42] == 3. DETECT STATS ==
> [12:12:42] -- overlay            = 0
> [12:12:42] -- mobs               = 0
> [12:12:42] -- humans             = 0
> [12:12:42] -- bosses             = 0
> ```
>
> Every counter zero. Still on v6. v8's multi-container BFS walk was the fix.

---

## 17 · Open Questions

1. **Full boss roster** — slayers2roblox.wiki holds the complete list with level requirements; content was fetched (12,072 chars) but never delivered as an evidence file.
2. **Crow menu exact key** — confirmed hotbar slot 5 per user, but auto-discovery in `scanners.lua` still probes slots 1–9 if slot 5 fails.
3. **Execute mechanic (G)** — documented but never implemented in `attack.lua`. Bosses below 10 HP currently die by continued damage instead of `G`-execute.
4. **Perfect block timing window** — documented as existing, exact frame window never verified.
5. **Anti-cheat kick recovery** — Error 267 is permanent for the affected account per Roblox enforcement. No client-side recovery exists.

---

## 18 · Confidence Assessment

| Finding | Confidence | Basis |
|---|---|---|
| Directional blocking | **High** | Canonical wiki, matches user gameplay reports |
| Combo input patterns | **High** | Canonical wiki, exact key sequences |
| Execute mechanic (G) | **High** | Canonical wiki, explicit description |
| Zuko drop table | **High** | Canonical wiki, single-entity page |
| Global cooldown v0.140 | **High** | allthings.how + user observation of skill stall |
| Boss roster completeness | **Medium** | Secondary sources only, primary stub |
| Bamboo Grove as farming route | **Medium** | Single commercial guide site |
| World Events Chest drop rates | **Medium** | Single source, not cross-verified |
| Crow quest flow | **High** | Multiple in-game screenshots |
| Anti-cheat detection profile | **Medium** | Community-sourced, not official |
| Executor capabilities | **High** | Direct probe by user during testing |
| Honeypot trap mechanics | **High** | Direct confirmation via kick |

---

## 19 · Recommendations for Future Research

1. **Re-fetch `slayers2roblox.wiki/en/bosses/slayers-2-boss-guide/`** with the evidence file actually delivered — 12KB of content already fetched once but never analyzed.
2. **Research crow quest flow end-to-end** — how quests progress, what happens when they expire, whether incomplete quests penalize.
3. **Research Xeno's `fireproximityprompt` behavior under rate limits** — we know it works, but not the exact cadence threshold.
4. **Audit Project Slayers 2's specific anti-cheat module** — the game is clearly using something more aggressive than a default Roblox server check given the 267 kick.
5. **Verify the World Events Chest drop rates** against a second source — one source is a single point of failure.

---

*Compiled 2026-10-03. All content sourced from session history. No new research performed.*
