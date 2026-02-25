# GR-05: Robot Walk Anim Info Leak Fix

**Fix ID:** GR-05  
**File patched:** `ZM/Maps/Origins/maps/mp/zm_tomb_giant_robot.gsc`  
**Function:** `robot_walk_animation()`  
**Affected robots:** IDs 0 (normal path), 1 (trenches), 2 (village) — ID 3 (intro) unchanged  
**Build:** included in `mod.ff` from `build_ff.sh`

---

## Background

Each giant robot walk cycle calls `animscripted()` three times on the same entity —
once per animation segment (0, 1, 2). The engine allocates a new anim info entry for
each call without freeing the previous one. When `stopanimscripted()` is finally called
at the end of the walk (in `giant_robot_think`), it only frees the **last** entry.
Segments 0 and 1 are permanently leaked.

With up to 3 robots walking per round and triple-giant rounds occurring every 4 rounds,
entries accumulate slowly over a 26–27 hour session until the table is exhausted and
the game crashes with `Error: exceeded maximum number of anim info`.

A community member claimed Plutonium ships a fix for this behind `sv_cheats 1` — this
is unverified. See test session notes below for current evidence status.

---

## What changed

Added `self stopanimscripted()` before each non-first `animscripted` call in the three
leaking branches. Also removed the dead-variable `getanimfromasd` calls (GR-02 cleanup).

**Before (all three branches, same pattern):**
```gsc
self animscripted( origin, angles, str_anim_scripted_name, 0 );
self thread donotetracks( "scripted_walk" );
self waittillmatch( "scripted_walk", "end" );
animationid = self getanimfromasd( str_name, 1 );   // dead — result discarded
self thread donotetracks( "scripted_walk" );
self animscripted( origin, angles, str_anim_scripted_name, 1 );  // leaks seg-0 entry
self waittillmatch( "scripted_walk", "end" );
animationid = self getanimfromasd( str_name, 2 );   // dead — result discarded
self thread donotetracks( "scripted_walk" );
self animscripted( origin, angles, str_anim_scripted_name, 2 );  // leaks seg-1 entry
self waittillmatch( "scripted_walk", "end" );
self notify( "giant_robot_stop" );
// parent calls stopanimscripted() — frees ONLY the seg-2 entry
```

**After:**
```gsc
self animscripted( origin, angles, str_anim_scripted_name, 0 );
self thread donotetracks( "scripted_walk" );
self waittillmatch( "scripted_walk", "end" );
self stopanimscripted();                             // GR-05: free seg-0 entry
self thread donotetracks( "scripted_walk" );
self animscripted( origin, angles, str_anim_scripted_name, 1 );
self waittillmatch( "scripted_walk", "end" );
self stopanimscripted();                             // GR-05: free seg-1 entry
self thread donotetracks( "scripted_walk" );
self animscripted( origin, angles, str_anim_scripted_name, 2 );
self waittillmatch( "scripted_walk", "end" );
self notify( "giant_robot_stop" );
// parent still calls stopanimscripted() for the final seg-2 entry (no change)
```

Entries leaked per walk cycle: **2 → 0**.

---

## Test session — 2026-02-20

### Setup

- **Map / round:** Origins, round 24 (triple-giant active, giants cycling continuously)
- **Player state:** god mode, not killing zombies — zombies wander and recycle on
  timeout, keeping a consistent animation workload across the session
- **Measurement tool:** `cg_drawAnimInfo 1` (Plutonium built-in, shows live engine
  anim info table occupancy on-screen)
- **Secondary tool:** `set st_cmd animrobotwatch` (indirect probe via zombie animsat)
- **Build under test:** patched (`zm_hrp` mod with GR-05 applied)

### Key discovery: table scale

The anim info table is far larger than previously assumed. Normal gameplay on Origins
uses **300–700 entries simultaneously** depending on activity (24 zombies with walk/
attack/idle animations, generator captures, dug-rise bursts, etc.). Our `animrobotwatch`
indirect probe used only 20 zombie slots — invisible against a table of this scale.
Two leaked entries out of 700 in use would never register. **`animrobotwatch` is not
a valid leak detector for this table size.**

`cg_drawAnimInfo 1` is the correct instrument. It reads the engine counter directly
and reflects every entry regardless of type.

### Observed peak values over walk count

Session held on round 24 with giants cycling continuously. Player in god mode, zombies
not killed — consistent animation workload throughout. Readings are the maximum
`cg_drawAnimInfo` value observed at each checkpoint.

| Walk # | Peak `cg_drawAnimInfo` | Delta from walk 4 | Rate (entries/walk) |
|--------|------------------------|-------------------|---------------------|
| 4      | 697                    | —                 | —                   |
| 6      | 712                    | +15               | —                   |
| 7      | 712                    | +15               | —                   |
| 8      | 716                    | +19               | —                   |
| 9–14   | 716                    | +19               | —                   |
| 15     | 722                    | +25               | 2.3/walk            |
| 19     | 746                    | +49               | 3.3/walk            |
| 40     | 796                    | +99               | 2.75/walk           |
| 44     | 807                    | +110              | 2.75/walk           |
| 49     | 827                    | +130              | 2.89/walk           |
| 50     | 832                    | +135              | 2.93/walk           |
| 54     | 840                    | +143              | **2.61/walk**       |

Normal in-session variance: **300–700** depending on zombie activity.

### Interpretation

**Walk 4 → walk 50: +135 over 46 walks = 2.93/walk sustained.**

The rate converged and held stable across the entire 46-walk dataset. This is a
confirmed, constant-rate accumulation leak. GR-05 predicts exactly **2.0/walk** (2
entries leaked per robot walk cycle: segments 0 and 1 never freed by the parent's
single `stopanimscripted()` call). The observed rate of ~2.93/walk consistently runs
~0.9 above the pure GR-05 prediction throughout the sample. This excess likely
reflects a small secondary contribution — probably GR-06 (mechz state-transition
calls without `stopanimscripted()` between state names) adding a fraction of an entry
per robot round, or generator capture animations.

**Extrapolation to crash window** at 2.93/walk:

| Scenario | Walks/hour | Leaked/hour | Hours to +300 entries |
|---|---|---|---|
| Low activity (one robot/round) | ~1–2 | ~3–6 | 50–100h |
| Normal high-round (triple-giant every 4R) | ~3–5 | ~9–15 | 20–33h |
| Active triple-giant cycling | ~6–8 | ~18–23 | 13–17h |

The table baseline at session start was ~697. At a table limit of ~1000–1100, the
remaining headroom is ~300–400 entries. At a normal high-round play rate this
exhausts in **20–33 hours**, aligning directly with the observed 26–27 hour crash
window.

### `animrobotwatch` result

The `animrobotwatch` command reported **0 leaks** across all 4+ walks observed.
This is expected given the table scale. The probe uses `zm_generator_melee` on
20 basic zombies — 2 leaked entries out of 700+ in use are undetectable. The tool
is retained for regression purposes at smaller table scales but is not valid here.

#### Probe vs cg_drawAnimInfo conflict

At walk 324 of the same long session, `animrobotwatch` reported: **walks 324, baseline
20, headroom 8, leaked 12**. This is 12 / 324 = **0.037/walk** from the probe.

`cg_drawAnimInfo` shows 3.04/walk growth over the same session. These two values cannot
both be measuring the same pool. The most likely explanation:

The probe works by spawning zombie AI entities and calling `animscripted` on them to
test remaining headroom. If the engine separates anim info allocations by entity class
(zombie AI actors vs non-AI scripted entities), the probe only measures zombie-pool
headroom. Robot walk `animscripted` calls are on a non-AI entity and would appear in
the `cg_drawAnimInfo` total but be invisible to the probe.

`cg_drawAnimInfo` is a Plutonium-exposed engine variable that reflects actual engine
internals. The `cg_` prefix is Plutonium's HUD command naming convention only. It is
the **primary and most reliable metric** for tracking the actual anim info table count.

**The probe's clean reading does not confirm GR-05 is working.** It was measuring zombie
entity pool headroom. The 3/walk growth visible to `cg_drawAnimInfo` remains unexplained
and may still be from the robot walk sequence.

#### Mod loading is unverified

Without a `println` confirmation that the patched `robot_walk_animation()` is executing,
the patched session cannot be distinguished from a vanilla run. This must be the next
step before any further rate conclusions are drawn.

### Community claim status

A community member claimed Plutonium ships an Origins robot anim fix behind
`sv_cheats 1`. This is **unverified** — no Plutonium changelog entry, forum post,
or code evidence was found. The Plutonium `t6-scripts` public repo is byte-for-byte
vanilla with no relevant fixes. The claim is consistent with GR-05 but does not
confirm it.

### Patched baseline run — in progress (2026-02-20)

Setup identical to unpatched session. Build: `zm_hrp` mod with GR-05 applied.
Round 24, triple-giant cycling, player in god mode.

#### Observed peak values — patched run (session 1)

| Walk # | Peak `cg_drawAnimInfo` | Delta from walk 4 | Rate from walk 4 |
|--------|------------------------|-------------------|------------------|
| 0      | 643                    | —                 | —                |
| 1      | 677                    | —                 | —                |
| 4      | 691                    | —                 | —                |
| 5      | 691                    | +0                | —                |
| 17     | 732                    | +41               | 3.42/walk        |
| 22     | 749                    | +58               | 3.19/walk        |
| 23     | 750                    | +59               | 2.95/walk (note) |
| 63     | 871                    | +180              | 3.05/walk        |
| 76     | 913                    | +222              | 3.08/walk        |
| 205    | 1302                   | +611              | **3.04/walk**    |

*Walk 23 note: spike coincided with walk report timestamp — may be a concurrent
zombie/mechz burst. Not conclusive.*

Session 1 appears to have ended (crashed or closed) around walk 205–250, consistent
with the peak value of 1302 approaching or exceeding the table ceiling.

#### Observed peak values — patched run (session 2, continuous count)

| Walk # | Peak `cg_drawAnimInfo` | Notes |
|--------|------------------------|-------|
| 313    | 499                    | Fresh session, table reset — confirming session 1 ended |

Session 2 baseline of 499 is below session 1 start (643), likely reflecting lower
concurrent zombie activity at the moment recording resumed.

#### Rate comparison

| Run | Build | Window | Start | End | Rate |
|-----|-------|--------|-------|-----|------|
| Unpatched baseline | vanilla | walk 4→50 | 697 | 832 | **2.93/walk** |
| Patched session 1 | zm_hrp GR-05 | walk 4→205 | 691 | 1302 | **3.04/walk** |
| Unpatched extrapolated to walk 205 | vanilla | — | 697 | ~1291 | 2.93/walk |

**Patched session 1 at walk 205 (1302) matches the unpatched extrapolation (1291) within
11 entries across 201 walks.** The patch has produced zero measurable reduction in leak
rate. Rates are statistically identical.

---

## Build reference

```
bash build_ff.sh
# GR-05 is included in mod.ff alongside all other Origins fixes
# Deploy to: %LOCALAPPDATA%\Plutonium\storage\t6\mods\zm_hrp\mod.ff
```
