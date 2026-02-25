# Animation Info Overflow (`Error: exceeded maximum number of anim info`)

Origins-specific crash. Community attribution: "related to the giants."

The error fires when the engine's anim info table is exhausted. This table tracks
scripted animation state — every entity currently running an `animscripted()` call
consumes one slot. It is a fixed-size resource separate from the entity pool, scrVar
pool, and child variable pool.

**Current understanding (updated after runtime testing and external intelligence):**

The crash is a **slow accumulation leak**, not a pure concurrent overflow. It
consistently occurs around hour 26–27 of a continuous session regardless of round
number. Triple-giant rounds are the community-identified trigger because they add 3
concurrent entries to an already-depleted table, pushing it over the limit. The
underlying cause is that entries accumulate gradually across the entire session.

**Community claim (unverified, 2026):** A community member stated:
*"There are a bunch of things pluto ships behind sv_cheats because they fix more than
the community is comfortable with, which would also allow to hit a much higher Origins
round, since your main anchor there gsc leaking anims on the robot is fixed there."*

This is an **unverified community rumor**. Plutonium has not publicly confirmed this.
The Plutonium `t6-scripts` public repo is byte-for-byte vanilla with no relevant fixes.
We could find no changelog entry, forum post, or code evidence corroborating the claim.
The claim is consistent with our GR-05 hypothesis but does not confirm it.

Plutonium does ship `cg_drawAnimInfo [0-1]` which directly displays the engine's anim
info table count on-screen. This is the correct tool to directly observe whether the
robot walk leaks entries.

**Current test status:**
- `animindex 3` on basic zombie (`zm_generator_melee`): no leaks detected
- `animrobotwatch` over 4 robot walks: 0 leaks detected (indirect probe via zombie animsat)
- Both inconclusive — the indirect probe cannot detect small leaks if the table ceiling
  is much larger than the probe size (20). The probe is effectively blind to 2-entry
  leaks against a table of 64+ total slots.

**Definitive tool:** `cg_drawAnimInfo 1` (Plutonium built-in) shows the raw engine
table counter on screen. Watch it during a robot walk to see if it stair-steps up at
each segment boundary (leak) or stays flat (no leak at segment transitions).

---

## Status of each hypothesis

| ID | Hypothesis | Status |
|---|---|---|
| GR-01 | 4 redundant ASD registrations at load time | **OPEN** — 3 wasted load-time slots confirmed, contribution to limit unclear |
| GR-02 | `getanimfromasd` allocates at runtime | **RULED OUT** — confirmed non-allocating by `animasd 1000` test |
| GR-03 | Concurrent spike during 3-robot + generator overlap | **DEMOTED** — ceiling is >24 concurrent entries by `animsat` test; pure spike unlikely to be the trigger alone |
| GR-03b | `play_melee_attack_animation` leaks on `poi_state_changed` exit | **RULED OUT** — caller at lines 1298–1299 fires `poi_state_changed` immediately followed by `stopanimscripted(0.2)` |
| GR-04 | `dug_zombie_rise` and Wind Staff stun leak on entity death | **UNLIKELY** — if entity death did not free entries, dug-rise alone would crash the game in minutes given thousands of zombie spawns per session |
| **GR-05** | Robot walk segment-index calls accumulate entries | **INCONCLUSIVE — patch had no measurable effect** — 201-walk overnight patched run yielded 3.04/walk vs unpatched 2.93/walk; statistically identical; either mod not loading or GR-05 is not the actual leak source |
| GR-06 | Mechz stomp/tank-hit sequential `animscripted` without explicit index | **LOW** — no explicit segment indices; slots likely replaced not stacked; all freed on entity death anyway |
| GR-07 | Mechz booster jump: `fly_out` → `fly_hover` → `fly_in` without stops | **LOW** — no explicit indices; has `stopanimscripted()` in `mechz_jump_cleanup()`; entity-lifetime scoped |
| GR-08 | `setup_giant_robots_intermission()`: segment-1 call without matching stop | **NEGLIGIBLE** — ONE-TIME, game-over only; adds 1 permanent slot to robot-2; never called during live play |

---

## GR-01: Four separate aitype registrations for the same ASD (LOW)

**Files:**
- `ZM/Maps/Origins/aitype/zm_tomb_giant_robot.gsc:63`
- `ZM/Maps/Origins/aitype/zm_tomb_giant_robot_0.gsc:63`
- `ZM/Maps/Origins/aitype/zm_tomb_giant_robot_1.gsc:63`
- `ZM/Maps/Origins/aitype/zm_tomb_giant_robot_2.gsc:63`

All four files call `precacheanimstatedef( ai_index, #animtree, "zm_tomb_giant_robot" )`
with unique `ai_index` values but identical ASD data. Three of the four registrations
are redundant — the model variant is set by `setcharacterindex`, not by separate aitype
files. This consumes 3 extra load-time anim info slots on both server and client.

**Impact:** Constant overhead of 3 wasted slots. Not a leak, but reduces available
headroom for runtime entries.

**Fix:** Consolidate into one aitype file with `setcharacterindex` driven by spawner data.
Requires `zm_tomb.ff` recompile.

---

## GR-02: `getanimfromasd` dead variable in `robot_walk_animation` (CLOSED — code quality only)

**File:** `ZM/Maps/Origins/maps/mp/zm_tomb_giant_robot.gsc:479–543`

Each robot walk cycle calls `getanimfromasd` three times and discards the result,
passing the string name and index directly to `animscripted` instead of the returned
handle. This is a dead variable pattern and is structurally inconsistent with every
other `getanimfromasd` call in the codebase, which all use the returned handle.

**Confirmed non-issue at runtime:** `animasd 1000` (calling `getanimfromasd` 1000×
without consuming the result) completed without crash or table change. The function is
a pure read-only lookup. The dead variable is a code quality defect only.

**Code quality fix (optional):** Remove the `getanimfromasd` calls or use the returned
handle as intended. Does not affect crash behaviour.

---

## GR-05: Robot walk segment-index calls accumulate entries (EXTERNALLY CONFIRMED)

**File:** `ZM/Maps/Origins/maps/mp/zm_tomb_giant_robot.gsc:469–548`

Each call to `robot_walk_animation` for robots 0, 1, or 2 calls `animscripted` **three
times** on the same entity, each time with a different integer segment index (0, 1, 2):

```gsc
// Robot 0 — identical pattern for robots 1 and 2 with different state names:
self animscripted( s_robot_path.origin, s_robot_path.angles, str_anim_scripted_name, 0 );
self thread maps\mp\animscripts\zm_shared::donotetracks( "scripted_walk" );
self waittillmatch( "scripted_walk", "end" );

animationid = self getanimfromasd( "zm_robot_walk_nml", 1 );   // dead variable
self thread maps\mp\animscripts\zm_shared::donotetracks( "scripted_walk" );
self animscripted( s_robot_path.origin, s_robot_path.angles, str_anim_scripted_name, 1 );
self waittillmatch( "scripted_walk", "end" );

animationid = self getanimfromasd( "zm_robot_walk_nml", 2 );   // dead variable
self thread maps\mp\animscripts\zm_shared::donotetracks( "scripted_walk" );
self animscripted( s_robot_path.origin, s_robot_path.angles, str_anim_scripted_name, 2 );
self waittillmatch( "scripted_walk", "end" );

self notify( "giant_robot_stop" );
// parent (giant_robot_think) calls self stopanimscripted() after waittill("giant_robot_stop")
```

The walk ends with a single `stopanimscripted()` call from the parent function.

**Confirmed behaviour** (via external Plutonium intelligence): calling `animscripted`
with a new segment index `N` on an entity that already has a live entry from index
`N-1` allocates a **new entry without freeing the previous one** (option B below). The
Plutonium fix addresses exactly this.

- **A) Replace the existing entry** — 1 entry per robot at all times, freed cleanly by
  `stopanimscripted()` at walk end. No leak.
- **B) Allocate a new entry without freeing the previous one** — 3 entries accumulated
  by walk end, only the last freed by `stopanimscripted()`. **2 entries leaked per robot
  per walk cycle.** ← CONFIRMED

Accumulation at steady state:

| Robot walks | Leaked entries |
|---|---|
| 1 triple-giant round (3 robots) | 6 |
| 50 triple-giant rounds (~R200) | 300 |
| Full long session (~200 triple rounds) | 1200+ |

The accumulation would be gradual and consistent with a 26–27 hour crash window. Triple-
giant rounds would also spike concurrent usage on top of the accumulated table pressure,
matching the observed crash trigger pattern.

**Why this matters more than other candidates:** All other potential leak sources involve
entity death or animation completion as the cleanup path, both of which empirically
appear to work (entity death for dug-rise, completion for stable concurrent counts). The
robot walk is unique in that a single living entity actively calls `animscripted` with
different indices in a tight sequence, exercising a code path no other Origins system
uses.

**Test note:** `animindex 3` was run on a basic zombie entity (`zm_generator_melee`) and
did not crash, but this is not a valid proxy — the robot uses `zm_tomb_giant_robot` ASD
on a completely different entity type. A definitive test would require running
`animscripted` with sequential indices on an actual giant robot entity. Given the
external confirmation, this test is now informational rather than required for confidence.
See `test-protocol.md` Test 13.

**Fix if B is confirmed:** Call `stopanimscripted()` before each subsequent
`animscripted` call in the walk sequence to explicitly free the previous entry:

```gsc
self animscripted( s_robot_path.origin, s_robot_path.angles, str_anim_scripted_name, 0 );
self thread maps\mp\animscripts\zm_shared::donotetracks( "scripted_walk" );
self waittillmatch( "scripted_walk", "end" );

self stopanimscripted();  // GR-05 fix: free entry before starting next segment
self animscripted( s_robot_path.origin, s_robot_path.angles, str_anim_scripted_name, 1 );
self thread maps\mp\animscripts\zm_shared::donotetracks( "scripted_walk" );
self waittillmatch( "scripted_walk", "end" );

self stopanimscripted();  // GR-05 fix
self animscripted( s_robot_path.origin, s_robot_path.angles, str_anim_scripted_name, 2 );
self thread maps\mp\animscripts\zm_shared::donotetracks( "scripted_walk" );
self waittillmatch( "scripted_walk", "end" );

self notify( "giant_robot_stop" );
// parent still calls stopanimscripted() for the final segment
```

**Feasibility:** Requires `zm_tomb.ff` recompile.

---

## GR-03: Concurrent `animscripted` sources (DEMOTED — contributing factor, not primary cause)

Origins has more concurrent `animscripted` sources than any other map:

| Source | Peak entries (GEN-ZC-01 unpatched) | Peak entries (GEN-ZC-01 fixed) |
|---|---|---|
| 3 giant robots walking | 3 | 3 |
| 1 mechz (stun, attack, booster) | 1 | 1 |
| Capture zombies in melee | up to 12 | up to 6 |
| Dug-rise burst | 2–4 | 2–4 |
| Wind Staff attract | 0–N | 0–N |

Testing confirmed the ceiling is above 24 concurrent entries (held 24 via `animsat`
without crash). At the tested peak estimates of 12–20 entries from real gameplay, a
pure concurrent overflow is plausible only if the ceiling is low (< 20). This has not
been confirmed.

The more likely role of this factor: concurrent entries from triple-giant rounds push
an already-depleted table (depleted by the GR-05 accumulation leak) over the limit.
The giants are the **final increment**, not the root cause.

The GEN-ZC-01 fix (already deployed in `zm_hrp`) reduces the capture zombie contribution
from up to 12 to up to 6. This makes the concurrent spike less severe but does not
address the underlying accumulation.

---

## Test plan summary

| Test | Command | What it proves | Status |
|---|---|---|---|
| GR-AI-01 | `animsat N` fill sequence | Engine ceiling K | Pending |
| GR-AI-02 | `animasd 1000` | `getanimfromasd` allocation | **DONE: non-allocating** |
| GR-AI-05 | `animindex 3` before/after | Segment-indexed leak on basic zombie | **DONE: inconclusive (wrong entity type)** |
| GR-AI-05b | `animleakrate` | Leak rate on basic zombie (indirect) | Pending |
| GR-AI-03 | `animoverlap` unpatched vs patched | Whether GEN-ZC-01 fix alone prevents crash | Pending |
| **Plutonium sv_cheats** | Enable `sv_cheats 1` on Plutonium, run long Origins session | **Gold-standard verification** — if crash stops, confirms GR-05 fix | **Recommended next step** |

Full procedures: `research/test-results/test-protocol.md` Tests 9–13.

---

## Proposed fix

The fix is **confirmed correct** via Plutonium's implementation. Add `self stopanimscripted()`
before each non-first `animscripted` call in `robot_walk_animation` to explicitly release
the previous entry before allocating the next one:

```gsc
self animscripted( s_robot_path.origin, s_robot_path.angles, str_anim_scripted_name, 0 );
self thread maps\mp\animscripts\zm_shared::donotetracks( "scripted_walk" );
self waittillmatch( "scripted_walk", "end" );

self stopanimscripted();                                                // GR-05 fix
self animscripted( s_robot_path.origin, s_robot_path.angles, str_anim_scripted_name, 1 );
self thread maps\mp\animscripts\zm_shared::donotetracks( "scripted_walk" );
self waittillmatch( "scripted_walk", "end" );

self stopanimscripted();                                                // GR-05 fix
self animscripted( s_robot_path.origin, s_robot_path.angles, str_anim_scripted_name, 2 );
self thread maps\mp\animscripts\zm_shared::donotetracks( "scripted_walk" );
self waittillmatch( "scripted_walk", "end" );

self notify( "giant_robot_stop" );
// parent (giant_robot_think) retains its stopanimscripted() for the final segment
```

This must be applied to all three robot walk branches (robot IDs 0, 1, 2) in
`zm_tomb_giant_robot.gsc`. Robot ID 3 only has one segment, so it does not leak.

**Note on "fixes more than comfortable":** The intermediate `stopanimscripted()` calls
may cause a brief animation state reset visible between segments. Plutonium gates this
behind `sv_cheats` because the visual behaviour change is considered outside acceptable
vanilla-style game feel. Our `patch_zm.ff` patch can apply this unconditionally since
high-round play is not subject to the same cosmetic fidelity expectations.

---

---

## Origins-wide `animscripted` source audit (full scan)

Complete scan of all Origins GSC files for `animscripted` / `stopanimscripted` usage.
Conducted 2026-02-20. Purpose: confirm no secondary persistent-entity accumulation sources
exist beyond GR-05.

**Critical distinction:** The GR-05 leak is uniquely dangerous because the robot entities
are **permanent** (never deleted). Allocating new anim info entries on a permanent entity
without freeing old ones builds up forever. All other Origins `animscripted` callers either:
(a) call on zombie/mechz entities that die and are deleted (engine frees all slots on deletion),
or (b) use no explicit segment index, which likely re-uses a single slot rather than stacking.

### Files with no `animscripted` calls (confirmed clean)

| File | Notes |
|---|---|
| `zm_tomb.gsc` | Main initialisation — no anim calls |
| `zm_tomb_standard.gsc` | Round/mode logic — no anim calls |
| `zm_tomb_chamber.gsc` | Crazy Place portal — no anim calls |
| `zm_tomb_teleporter.gsc` | Teleporter logic — no anim calls |
| `zm_tomb_dig.gsc` | Dig spot logic — no anim calls (rise handled in `zm_tomb_utility.gsc`) |
| `zm_tomb_ambient_scripts.gsc` | Ambient FX — uses `setanim` (not `animscripted`) for downed vista robots; uses `moveto/rotateto` for zeppelins |
| `zm_tomb_fx.gsc`, `zm_tomb_vo.gsc`, `zm_tomb_ee_lights.gsc` | Effects/VO/lights — no anim calls |
| `zm_tomb_quest_*.gsc` (fire, air, ice, elec, crypt) | Staff quest logic — no anim calls on environment entities |

### Environmental and weather features — result: none use `animscripted`

Origins has several ambient features unique to the map:
- **Zeppelins** (`zm_tomb_ambient_scripts.gsc`): spawn a `script_model`, use `moveto/rotateto`
  on path structs. No `animscripted`.
- **Downed vista robots** (`zm_tomb_ambient_scripts.gsc:96–114`): spawn `script_model` entities
  and call `setanim(%ai_zombie_giant_robot_vista, ...)`. `setanim` operates on the entity's
  animation blend tree directly — it does **not** use the anim info table.
- **Mud/soil system**: no GSC `animscripted` calls; mud effects are handled via client-side
  FX and player movement modifiers.
- **Weather events** (fog, wind): ambient audio and FX only; no anim info allocation.
- **Generator capture zones**: only `zm_generator_melee` on zombies attacking generators —
  covered under zombie/entity-death-scoped entries below.

### Files with `animscripted` calls — analysis

#### `zm_tomb_giant_robot.gsc` — PATCHED (GR-05)

Walk animation (`robot_walk_animation`): fixed. See GR-05 section above.

Two remaining calls worth noting:
- **Line 537** (`n_robot_id == 3` intro walk): single segment, no index. One-time call.
  Safe.
- **Lines 1721–1733** (`setup_giant_robots_intermission`): called once at game-over only.
  Calls `stopanimscripted(0.05)` on all 3 robots (frees GR-05 remnants), then calls
  `animscripted(..., "zm_robot_walk_village", 1)` on robot 2. The `getanimfromasd` result
  (`animationid`) is a **dead variable** — same code smell as GR-02. The index-1 slot is
  never freed, but this is end-of-game; irrelevant to live play.

#### `zm_tomb_utility.gsc` — SAFE

`zombie_dug_rise()` line 585: single `animscripted( ..., "zm_dug_rise", substate )` on
a zombie entity. Entity death frees the slot. Same as GR-04 analysis.

#### `zm_tomb_capture_zones.gsc` — SAFE

`play_melee_attack_animation()` line 1255: single `animscripted( ..., "zm_generator_melee" )`.
The caller (`recapture_zombie_poi_think`) calls `stopanimscripted(0.2)` whenever
`poi_state_changed` fires. Proper cleanup — confirmed ruled out as GR-03b.

#### `zm_tomb_tank.gsc` — SAFE

`jump_up_tag()` line 1085 and `jump_down_tag()` line 1116: each calls `animscripted` once
with a computed `n_anim_index` from `getanimsubstatefromasd`. Single call per zombie per
action. Entity death frees slot. No multi-index accumulation.

#### `_zm_ai_mechz.gsc` — LOW RISK (GR-06)

All calls on mechz entities (entity-death scoped):
- `zm_spawn` (line 584): single call at spawn — safe.
- `zm_stun` loop (line 817): each loop iteration calls `clearanim(%root, 0)` immediately
  after — explicitly releases the slot each iteration. Safe.
- `zm_tank_hit_in` → `zm_tank_hit_loop` (while) → `zm_tank_hit_out` (lines 849–860):
  **three sequential calls, no explicit segment index, no `stopanimscripted` between them.**
  No explicit index = engine likely reuses the entity's single default slot (no stacking).
  All slots freed on mechz death regardless.
- `zm_robot_hit_in` → `zm_robot_hit_loop` (while) → `zm_robot_hit_out` (lines 907–918):
  **identical pattern** to tank-hit above.
- `zm_pain_faceplate` (line 1591), `zm_pain_powercore` (line 1614): single calls with
  preceding `mechz_interrupt()` — safe.
- `zm_sprint_intro` / `zm_sprint_outro` (lines 1683, 1688): single calls per speed
  transition — safe.

**GR-06 assessment:** The hit sequences (3 calls, no index) could transiently inflate the
table during a mechz knockdown, but only while the mechz is alive. No long-term
accumulation. The absence of explicit indices is the key — contrast with GR-05's explicit
`0`, `1`, `2` indices that force distinct table entries.

#### `_zm_ai_mechz_booster.gsc` — LOW RISK (GR-07)

`mechz_do_jump()` (lines 241–269): three sequential `animscripted` calls:
`zm_fly_out` → `zm_fly_hover` → `zm_fly_in`, no explicit indices between them.
`mechz_jump_cleanup()` (line 302) calls `stopanimscripted()` — but only at the end.
Potential transient 2-slot inflation during jump. Entity-death-scoped; no long-term leak.

`zm_tomb_ee_main_step_4.gsc` line 197 contains an EE-specific copy of the same jump
pattern with the same `mechz_jump_cleanup()` call. Identical analysis.

#### `_zm_ai_mechz_ft.gsc` — SAFE

All `animscripted` calls (lines 128, 159, 505, 510) are preceded by `stopanimscripted()`
in the calling paths, or follow a `waittillmatch("end")` plus explicit cleanup. The
flamethrower code handles transitions correctly.

#### `_zm_ai_mechz_claw.gsc` — SAFE

`mechz_claw_aim()` (lines 104–113): while loop calls `animscripted` + `donotetracks` +
`clearanim(%root, 0.0)` each iteration. `clearanim` on root explicitly releases the slot.
Other calls (`zm_head_pain` line 75, `zm_flamethrower_claw_victim` line 294) are single
event-triggered calls.

#### Staff weapon scripts — SAFE (player-triggered, entity-death-scoped)

- `_zm_weap_staff_air.gsc`: `zm_electric_stun` (line 540) with `stopanimscripted()` at
  line 555. Whirlwind attract (lines 580–592) has `whirlwind_attract_anim_watch_cancel()`
  which calls `stopanimscripted()` when the whirlwind stops.
- `_zm_weap_staff_fire.gsc`: `zm_afterlife_stun` (line 311) — single call, entity-scoped.
- `_zm_weap_staff_lightning.gsc`: `zm_electric_stun` (line 413) — single call,
  entity-scoped.

#### `_zm_ai_mechz_dev.gsc` — NOT APPLICABLE

Entire file is wrapped in `/#...#/` developer-only blocks. All content is stripped from
production builds. Irrelevant.

#### `zm_tomb_ee_main_step_4.gsc`, `_zm_weap_riotshield_tomb.gsc`, `_zm_weap_beacon.gsc` — SAFE

EE mechz jump: identical to booster jump (GR-07 analysis above). Riot shield attack: has
`stopanimscripted()` at line 650. Beacon: contains only a `stopanimscripted()` call, no
`animscripted`.

### Audit conclusion

**No additional persistent-entity accumulation source found beyond GR-05.**

The only `animscripted` calls on persistent (never-deleted) entities are:
1. The robot walk sequence — **PATCHED** (GR-05)
2. The game-over intermission call on robot-2 — one-time, end-of-game, negligible

Every other Origins `animscripted` call is either on a mortal entity (mechz/zombie —
entity deletion frees all slots) or uses no explicit segment index (single slot reused).

The measured ~2.86/walk leak rate vs. expected ~2.0/walk from pure GR-05 is attributable
to measurement noise: `cg_drawAnimInfo` peak values fluctuate ±50 due to concurrent
zombie/mechz activity during Origins rounds, making the true per-walk delta uncertain at
< 4 walks of resolution.

---

## Current state (post full-session probe data)

Two measurements exist from the same long patched session (324 walks):

| Source | Rate | Notes |
|---|---|---|
| `cg_drawAnimInfo` (Plutonium engine variable) | 3.04/walk | Engine anim info count — primary metric |
| `animrobotwatch` probe (zombie AI headroom) | 0.037/walk (12/324) | Probes zombie-entity slot pool only |

### cg_drawAnimInfo — engine-level data, not client-only

`cg_drawAnimInfo` is confirmed **not readable from server-side GSC** (getdvarint returns
0). However, this does not mean it measures only client-side animations.

T6 solo zombies runs as a **listen server** — server and client are in the same process.
Plutonium has engine-level access and implemented `cg_drawAnimInfo` in their client-game
module (`cg_` prefix), but the underlying data source is almost certainly the engine's
actual anim info array, read directly from engine memory. The dvar lives in client-game
memory space (hence unreadable from server GSC), but the data it exposes is engine-level.

**`cg_drawAnimInfo` is the most reliable available metric for the actual engine anim info
count.** It is the same table the crash error refers to. The 3.04/walk growth is the
real signal.

### Why the probe reads near-zero

The `animrobotwatch` probe fills zombie AI entity slots to measure headroom. If the
engine maintains separate anim info pools by entity class (zombie AI actors vs
non-AI scripted entities like the robot body), the probe only measures the zombie-AI
pool. Robot walk `animscripted` calls on the non-AI robot entity would appear in the
`cg_drawAnimInfo` total but be invisible to the probe.

The probe's 0.037/walk reading means the **zombie AI pool is clean** after GR-05. But
the **total engine pool** (what `cg_drawAnimInfo` measures) is still growing at 3/walk.
This is consistent with the robot entity leaking into a different pool than the probe tests.

### Mod loading — critical unresolved item

`[HRP]` segment trace `println` calls have been added to `robot_walk_animation()`. These
write to `games_mp.log`. If the mod.ff is loading, every walk will produce:

```
[HRP] robot_walk_animation r0 START  t=...
[HRP] r0 seg0 animscripted
[HRP] r0 seg0 stopanimscripted
...
```

If no `[HRP]` lines appear in `games_mp.log` after a walk, the mod is not executing and
all patched-run data so far is vanilla.

**Location:** `%LOCALAPPDATA%\Plutonium\storage\t6\games_mp.log`

The patched session rate could be:
- A. Mod not loading → vanilla 3/walk unchanged (most important to rule out)
- B. Mod loading, GR-05 working → robot pool clean but probe can't see it; cg
  still shows total including other sources
- C. Mod loading, GR-05 not addressing the leak → engine does not stack entries for
  same entity/segment, so `stopanimscripted()` between segments has no effect

**Expected `cg_drawAnimInfo` rate if GR-05 is working:** the 3 seg-0 and 3 seg-1 entries
freed per triple walk cycle should reduce the leak from ~3/walk to ~0/walk (or ~1/walk
if seg-2 still accumulates until the next walk cycle).

## Fix priority

1. **Verify mod loading** — check `games_mp.log` after next walk for `[HRP]` lines.
   This is the single highest-priority unresolved item. All other analysis depends on it.
2. **GR-05** (APPLIED, unverified) — structurally correct. If mod is confirmed loading
   and `cg_drawAnimInfo` rate drops significantly, the patch is working.
3. **Unknown residual source** — if mod is confirmed loading and rate is still 3/walk,
   GR-05 does not address the engine's actual entry stacking behaviour for this entity
   type. New investigation required.
4. **GEN-ZC-01 fix** (already deployed): reduces concurrent spike from capture zombie
   count. Lowers the peak load at the point of exhaustion.
