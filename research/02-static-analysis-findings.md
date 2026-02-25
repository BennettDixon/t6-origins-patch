# Static Analysis Findings

This document tells the story of the audit as a narrative — what we looked at, what drew our attention, the reasoning chain for each finding, and how the issues interact with each other. This is the "lab notebook" version of the bug catalog in `docs/`.

For the structured reference format with severity tags and fix code, see the `docs/` subdocuments. This document explains the *why* and the *how we got there*.

## The Starting Hypothesis

High-round BO2 zombies crashes have been reported by the community for over a decade. Players consistently report:
- Crashes correlate with **game duration**, not a specific round number
- More frequent with **aggressive playstyles** (traps, explosives, splash weapons near barriers)
- More frequent with **box usage** and **grenade-heavy strategies**
- Games that "should" crash sometimes don't if the player uses a conservative strategy (training, headshots only)

This pattern pointed us toward **accumulated state** rather than a single threshold. Something is building up over the course of the game that eventually overwhelms a limit.

The most likely candidate: **entity leaks**. The BO2 engine has a hard limit on game entities. If entities are being allocated and never freed, the count climbs until it hits the ceiling.

## Phase 1: Scanning for `spawn()` Without Matching `delete()`

We started by searching every core zombies file for `spawn()` calls and tracing each one to its corresponding `delete()`.

### The `lerp()` Discovery

The first major find was in `_zm_utility.gsc`, line 53:

```gsc
lerp( chunk )
{
    link = spawn( "script_origin", self getorigin() );
    // ... animation ...
    link waittill_multiple( "rotatedone", "movedone" );
    self unlink();
    link delete();
}
```

What drew our attention: **no `self endon("death")`**. In GSC's cooperative model, if `self` (the zombie) is killed while this thread is blocked at `waittill_multiple`, the thread is terminated by the engine (the entity it's running on is destroyed). But `link` — the `script_origin` — is a separate entity. It survives the zombie's death and is never deleted.

**Reasoning chain:**
1. `lerp()` is called during window/barrier attacks
2. Window attacks are one of the most common zombie interactions
3. At high rounds, zombies die frequently from splash damage, traps, and Insta-Kill while mid-attack
4. Each death mid-`lerp()` permanently leaks one `script_origin`
5. Over hundreds of rounds, these accumulate
6. The engine has a finite entity budget

This became finding **EL-01** and our primary crash hypothesis.

### The Anchor Pattern

After finding `lerp()`, we searched for similar patterns. The `_zm_spawner.gsc` file revealed two more:

**`do_zombie_rise()` (line 2776):** Spawns `self.anchor` as a `script_origin`, has `self endon("death")` at the top. The irony: the `endon` is *supposed* to be a safety mechanism, but it's actually what *causes* the leak. When the zombie dies, the thread terminates at `endon` — before reaching `self.anchor delete()`.

**`do_zombie_spawn()` (line 2612):** Same pattern. Spawn, `endon("death")`, use, delete-at-end-that-never-runs.

**Reasoning chain for `do_zombie_rise()`:**
1. Every riser zombie executes this function
2. `endon("death")` terminates the thread if the zombie dies during the rise animation
3. The rise animation takes several seconds (the zombie is visible, climbable, damageable)
4. Insta-Kill powerup, traps near barriers, or splash damage can kill rising zombies
5. The death handler `zombie_rise_death()` (line 2858) watches for damage but does NOT clean up `self.anchor`
6. Result: one leaked `script_origin` per zombie killed mid-rise

Together, these three functions — `lerp()`, `do_zombie_rise()`, `do_zombie_spawn()` — form what we call the **entity leak trifecta**. They cover the three most common zombie animation states: attacking a barrier, rising from the ground, and moving to a spawn point. Any zombie killed during any of these states leaks an entity.

> **⚠ Runtime Correction (2026-02-19):** Dynamic testing of `do_zombie_rise()` and `do_zombie_spawn()` revealed a critical misreading of the static code. Point 3 above ("the rise animation takes several seconds") is **wrong**. The anchor does NOT span the entire visual animation. Reading the actual execution order:
>
> ```
> self.anchor = spawn(...)          ← anchor created
> self.anchor moveto(anim_org, 0.05) ← moves zombie to spot in 50ms
> self.anchor waittill("movedone")  ← yields for one frame (~50ms)
> [optional] rotateto(0.05) + waittill ← another ~50ms
> self.anchor delete()              ← anchor GONE after ~50-100ms total
>
> self thread hide_pop()            ← visual animation STARTS HERE
> level thread zombie_rise_death()  ← no anchor involved
> ```
>
> The anchor is a **positioning aid** used to teleport the zombie to its spawn spot in 50ms. The visual "rising from ground" animation that players see begins *after* `self.anchor delete()` already ran. The anchor window is therefore **~50-100ms per zombie, not several seconds**.
>
> **Implications:**
> - Leak probability per zombie is substantially lower than our estimate
> - A zombie must be killed within its first ~100ms of existence to leak an anchor
> - Normal weapons fire at a zombie you can see (visible after the anchor phase) will NOT trigger the leak
> - Grenades landing at a spawn point the moment a zombie spawns is the realistic trigger
> - The automated `elpkill` test in `zm_stress_test.gsc` was designed specifically to catch this narrow window
>
> **`lerp()` remains the higher-severity leak** (EL-01 original finding, now reclassified as primary). Its `link` entity spans the entire zombie walk from the spawn door to the playspace (typically 1–4 seconds), covering the window when players are most likely to kill approaching zombies. However, `link` is a function-local variable and cannot be cleaned up by any addon watchdog.

### Estimating Leak Rate (Revised)

| Source | Anchor window | Practical kill probability | Leak rate estimate |
|--------|---------------|---------------------------|-------------------|
| `lerp()` link | Entire spawn walk (1–4s) | Moderate — player kills approaching zombies | **Primary** — ~1-4 leaks/round at high rounds |
| `do_zombie_rise()` anchor | ~50-100ms (positioning only) | Very low — zombie not yet visible | **Low** — ~0-1 leaks/round |
| `do_zombie_spawn()` anchor | ~50-100ms (positioning only) | Very low — zombie not yet visible | **Low** — ~0-1 leaks/round |
| `_zm_ai_faller.gsc` anchor | ~50-100ms (same moveto pattern) | Very low | **Low** — rare spawn type |

> **Empirical correction (2026-02-19 — extended testing):** `elpkill` was run without ELP patch for 32 rounds / 1600 kills with hundreds of confirmed "killed mid-anchor" events. The spawn-based probe remained at HR=128 throughout with no degradation. **Conclusion: anchor entities from `do_zombie_rise()` and `do_zombie_spawn()` do NOT persist as real leaks.**
>
> The most consistent explanation is **thread-scoped entity ownership**: entities spawned within a GSC thread appear to be reclaimed by the engine when that thread exits via `endon("death")`. Since `do_zombie_rise()` begins with `self endon("death")`, when the zombie dies the thread exits cleanly and the engine auto-reclaims the `script_origin` it created. This is not documented behavior but is the only explanation consistent with 32 rounds of negative probe evidence.
>
> **Why `elpsynth` showed real leaks:** `elpsynth` creates `script_origin` entities from `level`'s thread context (not `self`'s), then assigns them as `self.anchor`. These externally-spawned entities are NOT reclaimed when the zombie dies, because the engine has no ownership link between `self`'s death and `level`'s thread. ELP correctly frees these. `elpsynth` was inadvertently testing a different leak scenario — external-thread entity assignment — which is real, but does not occur in normal gameplay.
>
> **Revised status of anchor leaks:** `do_zombie_rise()`, `do_zombie_spawn()`, and `do_zombie_faller()` anchor leaks are **not real persistent leaks** under normal engine behavior. The static analysis code reading was correct (code path exists where `delete()` is not reached) but the engine reclaims the entity anyway via implicit thread ownership cleanup.

### Revised Leak Assessment

| Source | Static analysis | Runtime finding | Real leak? |
|--------|----------------|-----------------|-----------|
| `do_zombie_rise()` anchor | Code path misses `delete()` | Engine auto-cleans on `endon` exit | **No** |
| `do_zombie_spawn()` anchor | Same pattern | Same mechanism | **No** |
| `_zm_ai_faller.gsc` anchor | Same pattern | Inferred same | **Probably no** |
| `lerp()` local `link` | No `endon`, force-terminated thread | **Unknown — open question** | **TBD** |

The only remaining leak candidate is `lerp()`'s `link` entity. Unlike the anchor functions, `lerp()` has **no `self endon("death")`** — the thread is force-killed by the engine when `self` is deleted, rather than exiting cleanly. Whether force-terminated threads also trigger the engine's implicit entity cleanup is unconfirmed. A long natural-gameplay run (no elpkill automation, many rounds, probe monitoring) is needed to determine whether `lerp()` link entities genuinely accumulate.

## Phase 2: Looking for Infinite Loops

After the entity leak discovery, we scanned all loops for termination guarantees.

### The `has_attachment()` Freeze

`_zm_weapons.gsc`, line 1730:

```gsc
has_attachment( weaponname, att )
{
    split = strtok( weaponname, "+" );
    idx = 1;
    while ( split.size > idx )
    {
        if ( att == split[idx] )
            return true;
    }
    return false;
}
```

The `idx` variable is never incremented. If the weapon has more than one segment (attachments) and the first one doesn't match, the loop spins forever.

**How we found it:** Systematic scan of all `while` loops checking for increment/modification of the loop variable.

**Why it hasn't been widely reported:** This function may only be called in specific code paths that are rarely triggered in vanilla zombies. But it's a guaranteed server freeze if hit — the GSC VM is single-threaded with no preemption.

**Fix:** Added `idx++` inside the `while` loop body in `ZM/Core/maps/mp/zombies/_zm_weapons.gsc`.  
**Status: ✅ VERIFIED** — `set fftest_cmd il01` returned `[FFTEST] IL-01 PASS — returned true, no freeze` in-game on 2026-02-20. Fix delivered via `mod.ff` (OAT-compiled from source, deployed to Plutonium `mods/zm_hrp/`).

### The `random_attachment()` Edge Case

Same file, line 1636. A `while (true)` loop that picks a random attachment, excluding one. If there's exactly one eligible attachment and it matches the exclude parameter, the loop has no exit.

**How we found it:** After finding `has_attachment`, we reviewed every `while (true)` in the weapons system.

### The Failsafe Recycling Loop

`_zm.gsc`, line 3635. This is subtler — it's not a single infinite loop, but a **systemic** one. When a zombie gets stuck, the failsafe kills it and re-queues a replacement. If the replacement also gets stuck (common at high rounds due to unkillable health + pathfinding issues), it gets recycled too. The round's `zombie_total` never reaches 0, so `round_wait()` never completes, and the round never ends.

**How we found it:** While analyzing the round lifecycle, we noticed `level.zombie_total_subtract` is incremented in the failsafe but never used as a termination condition. We traced the round completion logic and realized the recycle loop has no upper bound.

## Phase 3: Checking for Overflow

### Health Scaling Math

`_zm.gsc`, line 3572. Zombie health starts at 150 and compounds at +10% per round from round 10 onward. We computed the growth:

- Round 10: ~1,050
- Round 50: ~11,739
- Round 100: ~1,252,783
- Round 150: ~133,599,277
- Round 163: ~2,147,483,647 (int32 max)

The code has an overflow check (`if (level.zombie_health < old_health)`) that caps health at the pre-overflow value. So it doesn't crash — but it makes zombies unkillable, which feeds into the failsafe recycling soft-lock.

### The Powerup Drop Cascade

`_zm_powerups.gsc`, line 405. The drop increment is multiplied by 1.14 on every powerup drop. Starting at 2000:

- After 10 drops: ~7,424
- After 100 drops: ~1.25 billion
- After 200 drops: ~7.8e17

This is exponential growth in a 32-bit float. By ~200 drops, the value exceeds float precision, and the comparison that triggers drops becomes unreliable.

Compounding this: `score_total` (the sum of all players' earned points) is accumulated as a 32-bit integer. With 4 players at high rounds, this can overflow to negative, making `curr_total_score > score_to_drop` permanently false. Powerup drops stop entirely.

**The interaction:** These two issues compound. Even if only one overflows, drops are broken. Both overflowing guarantees it.

## Phase 4: Checking for Accumulated State

After the critical findings, we swept for any value that grows without a reset mechanism.

Key finds:
- `level.chest_accessed` — never resets on single-box maps (SA-01)
- All kill/timeout counters — initialized once, never cleared (SA-02)
- `grenade_multiattack_count` — per-player, incremented on every grenade event, never reset (SA-03)
- `level._spawned_path_nodes` — cleanup function is literally empty (SA-04)
- `level.retrievable_knife_init_names` — grows on every player connect (SA-05)

None of these individually cause crashes, but they contribute to memory pressure and incorrect behavior that compounds with the primary issues.

## Phase 5: Race Conditions and Logic Bugs

### The Variable Name Typo

`_zm_utility.gsc`, line 3547. The `array_flag_wait_any()` function checks `isdefined(level._array_flag_wait_any_calls)` but sets `level._n_array_flag_wait_any_calls`. The `isdefined` check always fails (wrong variable name), so the counter always resets to 0, and every flag wait uses the same notify string. Unrelated flag waits can prematurely resolve each other.

**How we found it:** The variable names looked suspiciously similar. We checked whether they were the same and they weren't — classic copy-paste bug.

### The Grenade Position Race

`_zm_weapons.gsc`, line 165. `level.explode_position` is a shared global written by every grenade. Multiple concurrent grenades clobber each other's position data.

### The Iterator Bug

`_zm_spawner.gsc`, line 55. `arrayremovevalue` inside a forward-iterating `for` loop. Removing element `i` shifts subsequent elements down, but `i` still increments, skipping one element per removal.

## How the Issues Interact

The bugs don't exist in isolation. They form a cascade:

```
Entity leaks (EL-01/02/03) accumulate over rounds
                    |
                    v
Entity budget shrinks, approaching ~1024 limit
                    |
         +----------+-----------+
         |                      |
         v                      v
Box hits / powerups         Grenades near barriers
allocate more entities      kill rising/spawning zombies
(EL-06, EL-07, EL-08)      (accelerating EL-01/02/03)
         |                      |
         v                      v
Entity limit reached --> CRASH (G_Spawn: no free entities)
```

A parallel crash path from the same box-heavy playstyle:

```
Box cycling through many weapons (SA-08)
         |
         v
self.hitsthismag grows: 1 child var / unique weapon string
         +-- per player, never pruned, whole session

PaP usage across multiple weapons (SA-09)
         |
         v
self.pack_a_punch_weapon_options grows: 1 entry / PaP variant
         +-- never cleared, whole session

Entity leak orphaned thread frames (EL-01/02/03 side effect)
         |
         v
Leaked script_origin thread contexts hold scrVar pool slots
         |
         v
Global child scrVar pool exhausted
         |
         v
CRASH (exceeded maximum number of child server script variables)
       Terminal: maps/mp/zombies/_zm_utility.gsc:1
```

These two crash paths are not mutually exclusive. Entity ceiling tends to hit first in explosive/trap-heavy play. scrVar pool can be the terminal failure in conservative playstyles where entity leak rate is low but box cycling is sustained over many more rounds.

Separately, the overflow cascade:

```
Health overflow at round ~163 (OF-01)
         |
         v
Zombies become unkillable by normal weapons
         |
         v
More zombies trigger failsafe (stuck > 30s)
         |
         v
Failsafe recycles: kill + re-queue (IL-03)
         |
         v
Replacement also unkillable, also gets stuck
         |
         v
Infinite recycle loop --> SOFT-LOCK (round never ends)
```

And the powerup cascade:

```
Points accumulate (4 players, high rounds)
         |
    +----+----+
    |         |
    v         v
score_total   zombie_powerup_drop_increment
overflows     grows exponentially
int32 max     beyond float precision
    |         |
    v         v
curr_total_score   score_to_drop
goes negative      becomes unreliable/inf
    |              |
    +------+-------+
           |
           v
  curr_total_score > score_to_drop
  is NEVER true again
           |
           v
  Powerup drops stop permanently (OF-02 + OF-03)
```

## Phase 6: The Script Variable Pool Crash

After completing the entity and overflow analyses, we investigated a distinct crash type reported by the community at *very* high rounds — longer sessions than the entity ceiling typically allows:

```
Userver script runtime error
exceeded maximum number of child server script variables
Terminal script error
maps/mp/zombies/_zm_utility.gsc:1
```

This is not the entity ceiling. It's the T6 GSC VM's **child scrVar pool** — a separate, fixed-size block of memory used by the script interpreter to track all live variable values simultaneously. Every `entity.field = value` assignment, every array element, every local variable in a running thread occupies one slot. The pool is global and shared across all entities.

The `_zm_utility.gsc:1` location in the error is the module entry point — the crash bubbled up through the call stack and the VM reports the top-level script file. The bug is not at line 1.

### What fills the pool

Three independent sources compound:

**1. Per-player weapon string accumulation (SA-08)**

`watchweaponchangezm()` (`_zm_weapons.gsc:390`) runs once per player for the whole session. `self.hitsthismag[weapon]` accumulates one child var per unique weapon string switched to, never pruned. BO2 weapon name strings encode all active attachments — `"an94_zm"`, `"an94_zm+reflex"`, `"an94_zm+reflex+grip"`, `"an94_upgraded_zm"` are four distinct keys. With 50+ box cycles across a session, a player can hold 40–80 permanent child var slots in this array alone. Four players: 160–320+ from this source.

**2. PaP weapon options cache (SA-09)**

`get_pack_a_punch_weapon_options()` (`_zm_weapons.gsc:2261`) caches visual customization per upgraded weapon string in `self.pack_a_punch_weapon_options[weapon]`. Never cleared. Each PaP'd weapon variant is a separate key. 10–20 entries per player in typical high-round play.

**3. Leaked entity thread frames (EL-01/02/03)**

The entity leaks we documented earlier also apply pressure here. A leaked `script_origin` entity is mostly inert, but if any thread held a local variable referencing it (e.g., a `waittill` blocked on an event that will never fire due to the zombie being deleted), that thread's entire stack frame — all its local variables — remains allocated in the scrVar pool until the thread is terminated. The more leaked entities accumulate, the more potential for orphaned thread frames holding pool slots.

**4. Path node array never freed (SA-04)**

`level._spawned_path_nodes` (`_zm_utility.gsc:4827`) appends a struct entry per spawned path node. The cleanup function is empty. Each struct and its fields are child vars against the `level` entity. Bounded by map geometry but never released.

### Why this crash appears later than the entity ceiling

The entity ceiling (1024 entities, confirmed at test EL-02) tends to hit first because the entity pool is smaller and entity leaks accumulate quickly from mid-animation zombie deaths. The scrVar crash requires more game time because the per-player weapon arrays only grow one entry per unique weapon string — you need 50+ box cycles before the per-player count becomes significant.

Playstyle matters significantly. A box-heavy, PaP-focused strategy fills SA-08 and SA-09 much faster than a conservative headshot-only strategy. This matches the community observation that box-heavy players crash earlier — previously attributed only to entity pressure from the box mechanism itself, but SA-08 adds a second mechanism that scales with box usage.

### The scrVar cascade

```
Box cycling (50+ weapons per player)
         |
         v
self.hitsthismag grows: 1 child var per unique weapon string
         |
         +-- per player, never pruned, entire session
         |
PaP usage across multiple weapons
         |
         v
self.pack_a_punch_weapon_options grows: 1 entry per PaP'd variant
         |
         +-- never cleared, entire session
         |
Entity leaks (EL-01/02/03) accumulate
         |
         v
Orphaned thread frames may hold local vars in scrVar pool
         |
         v
level._spawned_path_nodes, level._link_node_list, etc.
accumulate across all rounds
         |
         v
Global child scrVar pool exhausted
         |
         v
"exceeded maximum number of child server script variables"
Terminal: maps/mp/zombies/_zm_utility.gsc:1
```

### Relationship to entity ceiling crash

These two crashes are not mutually exclusive. Entity ceiling tends to hit first in aggressive play (explosives, traps, frequent mid-animation kills). scrVar pool can be the terminal crash in conservative play where entity leak rate is low but box cycling is still heavy. Both are present simultaneously and the first pool to exhaust terminates the session.

| Crash | Error message | Resource exhausted | Primary contributors | Typical round |
|---|---|---|---|---|
| Entity ceiling | `G_Spawn: no free entities` | 1024 entity slots | EL-01/02/03 leaked `script_origin`s | Earlier (depends on playstyle) |
| scrVar pool | `exceeded maximum number of child server script variables` | Fixed child var slots (~16k–32k) | SA-08 (box cycling), SA-09 (PaP), EL orphaned thread frames | Later, box-heavy sessions |

### Fixes required

1. **Clear `self.hitsthismag` entries for dropped weapons** — when a player drops or loses a weapon, remove its key from the array. At minimum, clear the array at round start.
2. **Clear `self.pack_a_punch_weapon_options` periodically** — clear or cap the cache at round boundaries. The data is aesthetic (camo/reticle randomization) so there's no gameplay impact to regenerating it.
3. **These cannot be fixed from an addon script in the same way as the entity leaks** — `watchweaponchangezm()` and `get_pack_a_punch_weapon_options()` are not hookable via `level.custom_ai_spawn_func`. They would require patching the source FF files, the same limitation documented for IL-01 (`has_attachment`). The combined patch `zm_highround_patch.gsc` should document this constraint clearly.

**Update:** `zm_patch_scrvar.gsc` v1.0 confirms that SA-08 and SA-09 ARE fixable from addon scripts by pruning `self.hitsthismag` and clearing `self.pack_a_punch_weapon_options` at round start via `level waittill("start_of_round")`. See `research/test-results/patched/scrvar-pruning.md` for validation results.

---

## Phase 7: Origins Fire Staff — Two Compounding Mechanisms

Following the Tranzit world-record crash analysis (Transit / Jet Gun + Tazer Knuckles knife glitch, see `blog/03b-jetgun-transit-crash.md`), we investigated why the community similarly reports the Origins Fire Staff as a reliable trigger for the `exceeded maximum number of child server script variables` crash.

The answer involves two compounding mechanisms: one is an amplified version of SA-08 (weapon string accumulation), the other is a novel burst-pressure pattern from a reference bug in the Fire Staff's AoE logic.

### 7a. SA-08 amplification: multiple upgrade tier weapon names (SA-11)

Origins staves follow a three-tier upgrade path. Each tier uses a **distinct weapon name**:

```
staff_fire_zm           → staff_fire_upgraded_zm → staff_fire_upgraded2_zm → staff_fire_upgraded3_zm
                                                                             + staff_fire_melee_zm
```

Because `watchweaponchangezm()` adds each new weapon name to `self.hitsthismag` on first encounter, a player who fully upgrades the Fire Staff will permanently hold 5 entries in their `hitsthismag` array from fire staff weapons alone — regardless of whether they still hold those weapons or have cycled them out through box play.

All four elemental staves share this pattern (Air, Water, Lightning each generate 4–5 additional names). A player who upgrades all four staves accumulates up to **20 staff-specific entries** on top of all box weapon strings. Origins sessions are also longer by design (Easter egg, four staves to build) so the background SA-08 accumulation rate from box cycling is higher too.

The `zm_patch_scrvar.gsc` round-start prune already addresses this — stale staff tier names are discarded at each round boundary, same as any other dropped weapon. Its benefit is proportionally larger on Origins than on any other map.

### 7b. `fire_staff_area_of_effect` always floods threads — the `is_on_fire` reference bug (SA-10)

This is the more structurally interesting finding. In `_zm_weap_staff_fire.gsc`, the upgraded fire staff's AoE effect runs as a thread on the **projectile entity**:

```gsc
// in watch_staff_fire_upgrade_fired():
e_projectile thread fire_staff_area_of_effect( self, str_weapon );
```

Inside `fire_staff_area_of_effect`, `self` is the projectile. The function loops every 0.2 seconds for 5 seconds, applying flame damage to all zombies in radius. The guard intended to skip already-burning zombies is:

```gsc
if ( !is_true( self.is_on_fire ) )          // self = projectile
    e_target thread flame_damage_fx( str_weapon, e_attacker );
```

The `is_on_fire` state flag is set on **zombie entities** by `flame_damage_fx`:

```gsc
// inside flame_damage_fx, self = zombie:
self.is_on_fire = 1;
```

The guard in the AoE loop reads from the wrong object. No code ever sets `is_on_fire` on a projectile entity. `!is_true(projectile.is_on_fire)` is always true. **The deduplication guard is completely non-functional.** Every zombie in range receives a new `flame_damage_fx` thread on every 0.2-second tick for the full 5-second AoE window.

**What `flame_damage_fx` does when it runs:**

When `was_on_fire = false` (first hit on a zombie): sets `self.is_on_fire = 1` and spawns three long-lived sub-threads:
- `zombie_set_and_restore_flame_state()` — blocks on `waittill("stop_flame_damage")`, lives **8 seconds**
- `flame_damage_over_time()` — loops at 1-second intervals, ends on `"stop_flame_damage"`, lives **8 seconds**
- `on_fire_timeout()` — `wait 8`, fires `notify("stop_flame_damage")`, lives **8 seconds**

When `was_on_fire = true` (zombie already on fire): deals impact damage and returns immediately.

Because the AoE loop checks the projectile (not the zombie), the "already on fire" path is never reached from this loop — all 25 ticks trigger the check as if the zombie is fresh, but after tick 1, the zombie's `is_on_fire` flag IS 1, so `was_on_fire` is read as true and the thread exits quickly. The persistent threads (the three 8-second ones) are only spawned once per zombie (on first hit), but the **transient threads** from ticks 2–25 still run, check `was_on_fire = true`, and exit.

**Concurrent scrVar cost at tier-3 (3 projectiles per shot via `fire_additional_shots`):**

```
Per shot:
  3 projectiles × 25 ticks × 24 zombies = 1,800 threads created
  3 projectiles × 24 zombies × 3 sub-threads = 216 threads alive for 8 seconds

Per 8-second window:
  216 long-lived thread frames × ~7 scrVar slots each ≈ 1,512 scrVar slots
  (on top of baseline SA-08/SA-09 accumulation)
```

At high rounds with dense zombie spawns and rapid fire, multiple AoE windows overlap and the 8-second sub-threads are continuously refreshed. The pool never gets a chance to drain.

**Contrast with other staves:**

The Air Staff's `whirlwind_kill_zombies` correctly guards per-zombie operations using `a_zombies[i].is_mechz` on the zombie entity, and `whirlwind_drag_zombie` short-circuits with `if (isdefined(self.e_linker)) return` to prevent duplicate processing. The Water and Lightning staves use different mechanics that don't involve per-zombie per-tick thread flooding. The `is_on_fire` pattern is specific to Fire Staff.

### 7c. Why "Fire Staff" specifically — not all staves

The community associates this crash with the Fire Staff (not Air/Water/Lightning) because:

1. **SA-10 is Fire Staff-only.** The other staves don't have an AoE-tick-per-zombie thread flood.
2. **Tier-3 multiplier.** `fire_additional_shots` fires 2 extra projectiles for tier-3 (`staff_fire_upgraded3_zm`), tripling the per-shot thread cost. The upgraded-tier weapons of the other staves don't have this multi-projectile pattern.
3. **Fire Staff is the first staff players build and upgrade**, meaning they accumulate the most fire staff play-hours and encounter the crash in that context.

### 7d. Fix feasibility

| Fix | Approach | Feasibility |
|---|---|---|
| SA-11 (weapon string accumulation) | Round-start prune in `zm_patch_scrvar.gsc` | **Already implemented** |
| SA-10 root cause (`e_target.is_on_fire` vs `self.is_on_fire`) | Change line 143 in `_zm_weap_staff_fire.gsc` | **Cannot patch from addon** — `fire_staff_area_of_effect` is compiled into `zm_tomb.ff` and is invoked via direct function pointer from compiled `watch_staff_fire_upgrade_fired`. Same FF replacement limitation as IL-01. |
| SA-10 symptom mitigation | Reduce thread frame cost by pruning scrVar pool more aggressively | `zm_patch_scrvar.gsc` prune already reduces baseline — combined with SA-11 fix, the pool has more headroom before the SA-10 burst tips it over |

The Fire Staff AoE bug is a compile-time defect in `zm_tomb.ff`. For a fully correct fix, the zone file would need to be recompiled. The addon patch mitigates the accumulation components; the burst pressure from SA-10 remains but has more pool headroom to absorb it.

---

---

## Phase 8: Origins Wind Staff — Two Structural Bugs Behind One Community Observation

Players universally describe the Wind Staff (Air Staff) as "useless on high rounds" and report a secondary effect: invisible zombies that can still attack. Both observations trace to specific code defects.

### 8a. Why the Wind Staff stops killing at high rounds

The base and tier-1 Air Staves (`staff_air_zm` / `staff_air_upgraded_zm`) deal fixed damage via `wind_damage_cone`:

```gsc
// _zm_weap_staff_air.gsc:480-503
if ( str_weapon == "staff_air_upgraded_zm" )
    n_damage = 3300;
else
    n_damage = 2050;

target do_damage_network_safe( self, n_damage, str_weapon, "MOD_IMPACT" );
```

These values do not scale with round number. At round 50+, zombie health is in the tens of thousands. 3300 is rounding error.

The tier-2 and tier-3 whirlwind (`staff_air_upgraded2_zm` / `staff_air_upgraded3_zm`) kills correctly — via `self do_damage_network_safe(player, self.health, ...)` (instant kill regardless of health). But the whirlwind kill only triggers when a zombie physically reaches within 30 units of the whirlwind center (`n_fling_range_sq = 900`). At high rounds, several factors reduce the number of zombies that ever reach it:

- `whirlwind_kill_zombies` skips any zombie whose `ai_state != "find_flesh"` — a substantial fraction at high rounds when many are stunned, attacking, or otherwise occupied
- Two line-of-sight `bullet_trace_throttled` checks per zombie both must pass
- Whirlwind duration is at most 10.5 seconds (`chargeshotlevel * 3.5 = 3 * 3.5`), limiting total kill throughput
- Only one whirlwind can be active at a time (singleton via `flag("whirlwind_active")`)

These are design constraints, not bugs. The whirlwind was balanced for normal rounds, and at high rounds the fixed-duration crowd-control becomes less effective.

### 8b. MI-09: Wrong zombie passed as whirlwind source

`staff_air_find_source` (`_zm_weap_staff_air.gsc:84–114`) fires on each upgraded projectile impact. It finds the nearest eligible zombie (alive, not previously a source) and passes it to `staff_air_zombie_source` to anchor the whirlwind's starting position and trigger the chain-kill effect.

The bug is a wrong index on line 104:

```gsc
for ( i = 0; i < a_zombies.size; i++ )
{
    if ( isalive( a_zombies[i] ) )
    {
        if ( is_true( a_zombies[i].staff_hit ) )
            continue;

        if ( distance2dsquared( v_detonate, a_zombies[i].origin ) <= 10000 )
            self thread staff_air_zombie_source( a_zombies[0], str_weapon );  // ← a_zombies[0], not a_zombies[i]
        // ...
        return;
    }
}
```

The loop finds the valid zombie at index `i` but calls `staff_air_zombie_source(a_zombies[0], ...)` — passing the closest zombie in the sorted array, not the one just validated. When `a_zombies[0]` is dead or already `staff_hit` (which made the loop skip it), the whirlwind source is set to the wrong entity. Downstream effects:

- Whirlwind positioned at dead zombie's last origin
- Source-death chain kill fails (dead zombie's `!isalive` guard exits `staff_air_fling_zombie`)
- `is_source = 1` flag set on corpse, affecting fling/kill probability for other nearby zombies

At high round density, zombies die frequently enough that `a_zombies[0]` being dead is the common case, not an edge case. This bug degrades whirlwind behavior from plausible to unreliable on most upgraded shots.

This is the same class of bug as IL-01 (`has_attachment` wrong loop variable). Both are loop indexing defects in zombie-targeting code.

### 8c. MI-10: The invisible zombie — linker deleted before unlink

The whirlwind attracts zombies by linking each one to a `script_origin` linker entity that is physically moved toward the whirlwind center:

```gsc
self.e_linker = spawn( "script_origin", ( 0, 0, 0 ) );
self.e_linker.origin = self.origin;
self linkto( self.e_linker );                      // zombie's world transform tied to linker
self thread whirlwind_unlink( e_whirlwind );       // unlink deferred to whirlwind entity death

// ... movement loop ...

self notify( "reached_whirlwind" );
self.e_linker delete();                            // linker deleted here
// self unlink() NOT called here
```

`whirlwind_unlink` waits for the whirlwind **entity** to die, not the linker:

```gsc
whirlwind_unlink( e_whirlwind )
{
    self endon( "death" );
    e_whirlwind waittill( "death" );    // waits for whirlwind, not e_linker
    self unlink();
}
```

`whirlwind_timeout` clears `flag("whirlwind_active")`, waits 1.5 seconds, then deletes the whirlwind entity. The window between `self.e_linker delete()` and `self unlink()` is therefore 0–1.5 seconds.

During this window, the zombie is linked to a deleted entity. The T6 engine derives the zombie's **rendered world position** from its linker's transform. With the linker gone, the rendered position is either frozen at the linker's last position or disappears entirely, while the server-side AI continues normally. The zombie can walk, attack, and deal damage — all while invisible to players.

This state only occurs for zombies that **survive** the whirlwind (those not killed by `whirlwind_drag_zombie`). `whirlwind_drag_zombie` only kills when `flag("whirlwind_active")` is still true at the moment it resumes after `whirlwind_move_zombie`. If the whirlwind times out during the movement loop, the kill block is skipped and the zombie enters the orphaned state.

### 8d. Fix feasibility

Both bugs are in `zm_tomb.ff`. Neither can be patched from an addon script. The fixes are:

- **MI-09:** Change `a_zombies[0]` to `a_zombies[i]` — one character
- **MI-10:** Add `self unlink()` before `self.e_linker delete()` in `whirlwind_move_zombie` — one line

Neither has a meaningful addon-script workaround. The invisible zombie window can't be shortened without controlling when `self.e_linker delete()` is called, which requires modifying the compiled function.

---

## Phase 9: Die Rise — Why the Power-On Crash Happens at High Rounds

Players consistently report that Die Rise becomes crash-prone at high rounds after the power is on. The crash produces the same "exceeded maximum number of child server script variables" message as the Tranzit and Origins crashes. The underlying cause is a sustained elevated scrVar pressure that the elevator system produces once power is on and the elevators are actively cycling — compounded by a bug (MI-11) that makes one of the polling loops 8–24× more expensive than intended at high zombie counts.

### 9a. Background: Die Rise's elevator system

Die Rise has 7 perk elevators cycling continuously throughout the match. The elevator system starts multiple persistent threads at map initialization, well before power is turned on:

- **`elevator_roof_watcher()`** — one thread per elevator (7 total). Fires when a player stands on an elevator roof trigger. While active, polls every 0.5 seconds for an eligible zombie to climb the shaft unseen.
- **`elevator_depart_early()`** — one thread per elevator (7 total). Polls every 1 second for players touching the elevator platform.
- **`elevator_sparks_fx()`** — one thread per elevator (7 total). Plays a FX every 0.5 seconds when the elevator doors are open.
- **`faller_location_logic()`** — single thread. Loops every 0.5 seconds: iterates all faller spawn points against all elevators to block/unblock spawn zones, and checks all player positions against 7 elevator volumes.
- **`shouldsuppressgibs()`** — single thread. Loops every 0.5–1.5 seconds: iterates all 24 active zombies × 7 elevator volumes to suppress gibs inside shafts.

These all run for the entire match. Before power is on, they add background overhead. At low rounds (12 or fewer zombies) the overhead is negligible. At high rounds (24 zombies), it scales.

When `flag_set("power_on")` fires, one additional system activates:

- **`elevator_think()`** — one thread per elevator (7 total), all waiting at `flag_wait("power_on")`. They all wake up simultaneously and immediately start their cycling loop.

### 9b. MI-11: `elevator_roof_watcher` `continue` vs `break` bug

The most severe Die Rise-specific amplifier is a wrong loop control keyword in `elevator_roof_watcher`:

```gsc
// zm_highrise_elevators.gsc:379–396
zombies = getaiarray( level.zombie_team );

foreach ( zombie in zombies )
{
    climber = zombie zombie_for_elevator_unseen();

    if ( isdefined( climber ) )
        continue;       // ← BUG: should be break
}

if ( isdefined( climber ) )
    zombie zombie_climb_elevator( self );
```

`zombie_for_elevator_unseen()` returns `self` when a zombie is not visible to any player (eligible to climb unseen), or `undefined` when visible. The intended logic is: scan the array for the first eligible zombie, then use it. `break` would exit the loop on first find. `continue` just advances to the next iteration, so the loop always processes every zombie regardless.

After the loop, `climber` holds the result from the **last** zombie in the array (whatever `getaiarray` happened to return last), not the first eligible one. `zombie zombie_climb_elevator(self)` is called on the last zombie if and only if the last zombie happens to be eligible. Eligible zombies earlier in the array are found and then thrown away.

`zombie_for_elevator_unseen()` itself calls `get_players()` and `player_can_see_me()` for every player, per call:

```gsc
zombie_for_elevator_unseen()
{
    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        can_be_seen = self maps\mp\zm_highrise_distance_tracking::player_can_see_me( players[i] );

        if ( can_be_seen || distancesquared( self.origin, players[i].origin ) < distance_squared_check )
            return undefined;
    }

    return self;
}
```

At round 24 with 24 zombies and 4 players, one poll from one `elevator_roof_watcher` thread allocates:
- 1 `getaiarray()` result: 24 entries
- 24 `get_players()` results: 24 × 4 entries = 96 player arrays
- 96 `player_can_see_me()` checks

With 7 active `elevator_roof_watcher` threads (multiple players on roofs): 7 × 96 = 672 `get_players()` allocations per 0.5-second poll window. All temporary, but the concurrent peak load during each poll window is far higher than it should be.

With `break`, the average would be 1–3 calls to `zombie_for_elevator_unseen()` per poll (first eligible zombie found), reducing the scrVar peak by roughly 8–24×.

This is structurally the same class of bug as MI-09 (wrong loop variable in Wind Staff) — a loop indexing/control defect that causes exponentially more work at high zombie counts than at low counts.

### 9c. MI-12: `shouldsuppressgibs` O(N × 7) polling loop

`shouldsuppressgibs` runs unconditionally every 0.5–1.5 seconds for the entire match:

```gsc
// zm_highrise_elevators.gsc:1147–1171
while ( true )
{
    zombies = get_round_enemy_array();    // fresh array allocation each tick

    foreach ( zombie in zombies )         // 24 zombies at high rounds
    {
        shouldnotgib = 0;

        foreach ( zone in elevator_volumes )   // 7 volumes
        {
            if ( is_true( shouldnotgib ) ) continue;
            if ( zombie istouching( zone ) ) shouldnotgib = 1;
        }

        zombie.dont_throw_gib = shouldnotgib;
    }

    wait( randomfloatrange( 0.5, 1.5 ) );
}
```

At high rounds: one tick allocates a 24-entry array and runs 24 × 7 = 168 `istouching` checks. The `continue` short-circuit is correct — once `shouldnotgib = 1`, remaining volumes are skipped. But every zombie is still polled on every tick regardless of whether any zombies are near elevators. An event-driven approach (zombie-entered / zombie-exited elevator zone triggers) would eliminate polling entirely.

On its own this is moderate overhead. It compounds with MI-11 and the power-on burst.

### 9d. Why power-on is where players notice it

Before power is on, `elevator_think` is idle and the elevators are mostly static. The polling loops run, but with less to react to. After power is on, the 7 `elevator_think` threads become active and the elevators cycle continuously. Players use them, explore the newly accessible areas, stand near elevator shafts, and trigger `elevator_roof_watcher`. The full cost of MI-11 and MI-12 is now paid on every tick for every remaining round.

SA-08/SA-09 continue accumulating throughout. Die Rise sessions tend to be long — two buildings, the PAP buildable available early, more areas to explore — and the scrVar pool drains at a higher rate post-power than on other maps due to MI-11.

The crash doesn't occur at the moment of power-on. It occurs at whatever round the combined sustained pressure finally empties the pool. On shorter sessions or with the `zm_patch_scrvar.gsc` prune providing more headroom, that round is later. On long sessions with the full MI-11 pressure, SA-08/SA-09 accumulation, and 24 active zombies, the pool drains within a manageable number of rounds after power.

### 9e. Die Rise has leapers — effective zombie count is higher

Die Rise spawns both standard zombies and leapers (`_zm_ai_leaper.gsc`). `getaiarray(level.zombie_team)` returns both types. At rounds where the total enemy count is 24, a fraction of those will be leapers. This doesn't change the per-zombie scrVar cost meaningfully (leapers use the same entity structure), but it does mean that Die Rise's `getaiarray` results are larger than maps with only one enemy type at the same spawn limit.

More importantly, leapers interact directly with the elevator system — `zombie_for_elevator_unseen`, `zombie_climb_elevator`, and `watch_for_elevator_during_faller_spawn` all handle both types. When a leaper rises through an elevator shaft, `watch_for_elevator_during_faller_spawn` runs as a thread on that leaper with a 0.1-second poll loop until it finishes rising. At high rounds with many leapers, multiple such threads can be active simultaneously.

### 9f. Fix feasibility

| Fix | Approach | Feasibility |
|---|---|---|
| SA-08/SA-09 accumulation | Round-start prune in `zm_patch_scrvar.gsc` | **Already implemented** — gives pool more headroom before power-on burst |
| MI-11 root cause (`continue` → `break`) | Change one keyword in `elevator_roof_watcher` | **Cannot patch from addon** — `zm_highrise_elevators.gsc` is compiled into `zm_highrise.ff`; `elevator_roof_watcher` is invoked via direct thread call from compiled `init_elevator` |
| MI-12 root cause (`shouldsuppressgibs` polling) | Replace polling with event-driven approach | **Cannot patch from addon** — same reason |
| Power-on burst mitigation | Reduce pool depletion before power-on | Indirectly addressed by SA-08/SA-09 fix giving larger remaining pool |

The `zm_patch_scrvar.gsc` round-start prune reduces the SA-08/SA-09 baseline depletion rate, giving the pool more headroom for every round played after power-on. Die Rise sessions long enough to fully exhaust the pool still crash — the MI-11 and MI-12 amplifiers remain active — but the round at which the crash occurs is pushed noticeably later.

---

## Phase 10: Origins Generator System — Three Structural Bugs

Following the Fire Staff and Wind Staff analysis, we examined the other Origins-specific system players most commonly interact with: the six-generator capture mechanic (`zm_tomb_capture_zones.gsc`). The generators have their own spawn management, persistent threads per zone, and a recapture event system that runs on a 3–6 round timer after round 10. All three findings are in the compiled `zm_tomb.ff` and cannot be patched from an addon script.

### 10a. GEN-ZC-01: `get_capture_zombies_needed(b_per_zone)` — dead-variable assignment silences the per-zone limiter

`zm_tomb_capture_zones.gsc` line 779.

The function exists to answer two different questions depending on the caller:
- "How many total capture zombies are needed?" (called without argument by `calculate_capture_event_zombies_needed`)
- "How many per zone?" (called with `b_per_zone = 1` by `set_capture_zombies_needed_per_zone`)

The per-zone branch:

```gsc
// get_capture_zombies_needed() — original (broken):
if ( b_per_zone )
    b_capture_zombies_needed = n_capture_zombies_needed_per_zone;

return n_capture_zombies_needed;
```

`b_capture_zombies_needed` is a newly-introduced local variable that is never read anywhere else. `n_capture_zombies_needed` (the variable that `return` uses) is not modified. The function always returns the total count regardless of `b_per_zone`.

The correct code:

```gsc
// Fixed:
if ( b_per_zone )
    n_capture_zombies_needed = n_capture_zombies_needed_per_zone;
```

This is structurally identical to SA-10 (`self.is_on_fire` vs `e_target.is_on_fire`) and MI-09 (`a_zombies[0]` vs `a_zombies[i]`) — a variable name is wrong in an assignment, the original variable goes unmodified, and the dead write compiles silently.

**Effect on `monitor_capture_zombies()`:**

Each contested generator runs `monitor_capture_zombies()` for the duration of the capture event. At startup:

```gsc
self.capture_zombie_limit = self set_capture_zombies_needed_per_zone();
```

`set_capture_zombies_needed_per_zone()` calls `get_capture_zombies_needed(1)` — which returns the total count (e.g., 6) instead of the per-zone allocation (e.g., 3 with 2 active contests). Each zone's `capture_zombie_limit` is set to the full total.

The inner loop then runs every 0.5 seconds:

```gsc
while ( self ent_flag( "zone_contested" ) )
{
    self.capture_zombies = array_removedead( self.capture_zombies );

    if ( self.capture_zombies.size < self.capture_zombie_limit )
    {
        ai = spawn_zombie( e_spawner_capture_zombie );
        s_spawn_point = self get_emergence_hole_spawn_point();
        ai thread [[ level.zone_capture.spawn_func_capture_zombie ]]( self, s_spawn_point );
        self.capture_zombies[self.capture_zombies.size] = ai;
    }

    wait 0.5;
}
```

With `capture_zombie_limit = 6` (wrong) instead of `3` (correct), each zone keeps attempting spawns once it already has its correct 3. Both zones call `spawn_zombie` simultaneously on a 0.5s timer trying to reach 6, when 6 total slots is the entire budget for both zones combined.

**What happens at the AI limit boundary:**

`capture_event_handle_ai_limit()` sets `level.zombie_ai_limit = 24 - n_capture_zombies_needed`. With 2 active contests, `n_capture_zombies_needed = 6` (correctly calculated), so 6 entity slots are reserved for capture zombies. Once 6 exist, any further `spawn_zombie` call hits the limit. 

With the buggy per-zone limit, both generators think they need more zombies even when the budget is exhausted:
- Zone A has 3 zombies, limit is 6 → calls `spawn_zombie` → hits AI limit, gets undefined or stalls
- Zone B has 3 zombies, limit is 6 → same  
- Neither exits the spawn branch until their count naturally reaches 6 through player kill-and-respawn cycles

Each failed/queued spawn attempt still invokes `array_removedead(self.capture_zombies)` (fresh array allocation), calls `get_emergence_hole_spawn_point()` (which itself contains an inner 0.05s polling loop if emergence holes aren't ready), and adds an undefined entry to `self.capture_zombies`. Dead entries then need to be cleaned at the next iteration.

**Scale vs. Die Rise MI-11:**

| | Die Rise MI-11 | Origins GEN-ZC-01 |
|---|---|---|
| Runs when | Always (7 persistent threads) | During capture events only |
| Thread count | 7 elevator threads × all zombies | 2–4 generators × contested zones |
| Per-tick work | 672 `get_players()` allocs / 0.5s | 2× spawn attempt overhead / 0.5s |
| Duration | Entire match after power-on | 10–40s per capture event |
| Frequency | Continuous | Every 3–6 rounds after round 10 |

The absolute overhead per tick is much smaller than MI-11. But Origins sessions are long — 6 generators to capture, 4+ staves to build, plus recapture events recurring every 3–6 rounds indefinitely. Each recapture event triggers a multi-zone capture contest, and GEN-ZC-01 doubles the spawn call rate for the duration of each contested event.

**Additional entity pressure:**

With both zones calling `spawn_zombie` more aggressively than intended, actual spawned zombie counts during captures may exceed the design intent depending on spawn timing interleave. Capture zombies are full AI entities with their own per-zombie scrVar fields (`is_recapture_zombie`, `s_attack_generator`, `attacking_point`, `ignore_player[]`, `is_attacking_zone`, etc.). Even a 20–30% increase in peak capture zombie count translates directly to entity and scrVar pressure.

### 10b. GEN-ZC-02: `ignore_player[]` arrays on capture zombies accumulate stale entries across generator assignments

`zm_tomb_capture_zones.gsc` line 1216–1240.

`should_capture_zombie_attack_generator()` is called every 0.5 seconds on each active capture zombie. It maintains `self.ignore_player[]` — a per-zombie array of players who are currently in range of the generator. The intent is to track players who are "valid targets" (within 700 units of the generator and alive) so the zombie knows when to disengage and attack the generator instead.

Entries are removed from `ignore_player` when a player becomes a valid target again. Entries are added when a player is not a valid target and not already ignored:

```gsc
if ( b_is_valid_target && b_is_currently_ignored )
{
    arrayremovevalue( self.ignore_player, player, 0 );
    continue;
}

if ( !b_is_valid_target && !b_is_currently_ignored )
    self.ignore_player[self.ignore_player.size] = player;
```

The cleanup iterates `foreach ( player in a_players )` where `a_players = get_players()`. Players who have disconnected are not in `get_players()`, so they are never iterated, and their entries in `self.ignore_player` are never removed by `arrayremovevalue`.

During recapture events, `set_recapture_zombie_attack_target()` redirects zombies to a new generator:

```gsc
foreach ( zombie in level.zone_capture.recapture_zombies )
{
    zombie.is_attacking_zone = 0;
    zombie.s_attack_generator = s_recapture_target_zone;
    zombie.attacking_new_generator = 1;
}
```

`zombie.ignore_player` is not cleared. Player proximity context from generator A is silently inherited when the zombie is redirected to generator B, which has different spatial geometry. Players far from B who were in range of A are still ignored; players near B who were never near A start fresh.

Per zombie: typically 0–4 entries in `ignore_player`. Per recapture event: 6 recapture zombies with stale arrays. Each stale entry for a disconnected player is a scrVar slot that remains allocated until the zombie entity is deleted. This is minor in isolation — at most 24 stale slots per recapture event — but it's a consistent accumulation pattern across a session that plays many recapture rounds.

### 10c. GEN-ZC-03: Off-by-one in attack point index range excludes the last slot of each group

`zm_tomb_capture_zones.gsc` lines 1124–1148.

Each generator has 12 zombie attack points (indices 0–11), organized in three groups of 4:
- Center pillar: indices 0–3  
- Left pillar: indices 4–7
- Right pillar: indices 8–11

Both lookup functions use `i < n_end`:

```gsc
get_unclaimed_attack_points_between_indicies( n_start, n_end )
{
    for ( i = n_start; i < n_end; i++ )
        // ...
}
```

The callers pass `(0, 3)`, `(4, 7)`, `(8, 11)`, and `(0, 11)`. With `i < n_end`, index `n_end` is always excluded: indices 3, 7, and 11 are never considered. The full-range fallback `(0, 11)` also misses index 11.

**Crash vector:** The assert at line 1105 fires if no unclaimed attack points exist: `assert( a_valid_attack_points.size > 0 )`. With 11 usable points (0–10) and at most 6 recapture zombies simultaneously claiming them, the assert never fires in practice — 6 claims against 11 available is safe.

**Correctness impact:** The right pillar group (indices 8–11) always appears to have one fewer usable slot than the center and left groups. Zombie distribution around the generator is slightly asymmetric. No crash risk; minor behavioral anomaly.

---

**GEN-ZC-01 is the primary generator finding.** GEN-ZC-02 and GEN-ZC-03 are structural issues that contribute to the overall Origins scrVar pressure picture but do not independently cause crashes.

| ID | Bug | Effect | Severity |
|---|---|---|---|
| GEN-ZC-01 | `b_capture_zombies_needed` typo silences per-zone limit | 2× spawn call rate during multi-zone captures; inflated capture zombie pressure | Medium — scrVar + entity burst during capture events |
| GEN-ZC-02 | `ignore_player[]` never cleared on zombie reassignment | Stale scrVar entries per recapture zombie, persistent across generator transfers | Low — minor sustained accumulation |
| GEN-ZC-03 | Off-by-one in attack point index range | Attack point 11 unusable; assert could fire with >11 simultaneous claimants (impossible with current zombie limits) | Low — correctness issue only |

---

## Phase 11: Origins Tank System (`zm_tomb_tank.gsc`)

`zm_tomb_tank.gsc` ships in `zm_tomb.ff`. The tank is Origins' central traversal system
— players pay 500 points to ride it around the map, and zombies board it to hunt players
on top. Five bugs were identified.

**SA-10 amplification (already resolved):** Before the SA-10 fix, the tank's two side
flamethrowers (gunner1/gunner2) called `_zm_weap_staff_fire::flame_damage_fx` on every
zombie they hit — the same function that SA-10 broke. The tank was therefore a second,
independent source of the same broken dedup loop: at high rounds with a crowd near the
tank, each flamethrower burst spawned N duplicate burn threads per zombie, amplifying the
exact thread pressure that SA-10 caused. The SA-10 fix in `_zm_weap_staff_fire.gsc` covers
the tank's calls to that function — no separate fix needed.

### 11a. TANK-EL-01: `e_linker` entity leak when player disconnects during run-over animation

`zm_tomb_tank.gsc` lines 706–740 (`tank_ran_me_over`) and 742–747 (`wait_to_unlink`).

When the tank runs over a player, the game spawns a `script_origin` entity (`e_linker`),
links the player to it, and moves it to the nearest safe nav node over 4 seconds:

```gsc
e_linker = spawn( "script_origin", self.origin );
self playerlinkto( e_linker );
e_linker moveto( node.origin + vectorscale( ( 0, 0, 1 ), 8.0 ), 1.0 );
e_linker wait_to_unlink( self );    // blocks for 4 seconds
node.b_player_downed_here = undefined;
e_linker delete();
```

`wait_to_unlink` runs synchronously (no `thread` keyword) and contains `player endon("disconnect")`:

```gsc
wait_to_unlink( player )
{
    player endon( "disconnect" );
    wait 4;
    self unlink();
}
```

When the player disconnects during those 4 seconds, `player endon("disconnect")` terminates
the current thread — including the calling `tank_ran_me_over` context. The `e_linker delete()`
on the line after `wait_to_unlink` is never reached. The `script_origin` entity remains
allocated indefinitely.

This is the same structural pattern as EL-01 (`lerp()` entity leak). The fix follows the same
approach: expose the linker via a player field before the blocking call, and add a disconnect
watcher to clean it up.

**Fix applied:**
```gsc
// In tank_ran_me_over():
e_linker = spawn( "script_origin", self.origin );
self._tank_runover_linker = e_linker;  // TANK-EL-01 fix: expose for disconnect cleanup
self playerlinkto( e_linker );
e_linker moveto( node.origin + vectorscale( ( 0, 0, 1 ), 8.0 ), 1.0 );
e_linker wait_to_unlink( self );
self._tank_runover_linker = undefined;
node.b_player_downed_here = undefined;
e_linker delete();

// New: watch_tank_runover_disconnect() threaded in onplayerconnect():
watch_tank_runover_disconnect()
{
    self waittill( "disconnect" );
    if ( isdefined( self._tank_runover_linker ) )
    {
        self._tank_runover_linker delete();
        self._tank_runover_linker = undefined;
    }
}
```

**Frequency:** The leak requires a player to disconnect during the specific 4-second
animation window. This is infrequent in normal play but can accumulate over a long session
where players disconnect and reconnect between rounds after being run over.

### 11b. TANK-TL-01: Thread leak in `tank_push_player_off_edge` on disconnect

`zm_tomb_tank.gsc` line 421 (`tank_push_player_off_edge`).

When a player boards the tank, `players_on_tank_update` threads two `tank_push_player_off_edge`
instances on them — one per rear tread trigger:

```gsc
foreach ( trig in self.t_rear_tread )
    e_player thread tank_push_player_off_edge( trig );
```

Each thread:
```gsc
tank_push_player_off_edge( trig )
{
    self endon( "player_jumped_off_tank" );
    while ( self.b_already_on_tank )
    {
        trig waittill( "trigger", player );
        // ...
    }
}
```

`"player_jumped_off_tank"` is only notified when the exit branch in `players_on_tank_update`
is reached (player leaves the tank normally). If the player disconnects while on the tank,
`b_already_on_tank` is never cleared (it was set to 1 on entry), `"player_jumped_off_tank"`
is never notified, and both threads remain alive indefinitely — blocking on `trig waittill("trigger", player)`.

The `waittill` on the tread trigger will wake on any player touching it, check `if (player == self)` (disconnected player, never matches), and sleep again. The threads never exit.

**Fix:** Add `self endon("disconnect")`:
```gsc
tank_push_player_off_edge( trig )
{
    self endon( "player_jumped_off_tank" );
    self endon( "disconnect" );  // TANK-TL-01 fix
    while ( self.b_already_on_tank )
    // ...
}
```

### 11c. TANK-MI-01: Dead variable in `tank_flamethrower_get_targets` — cone check uses raw position

`zm_tomb_tank.gsc` lines 1492–1497 (`tank_flamethrower_get_targets`).

```gsc
// Original (broken):
v_to_zombie = vectornormalize( ai_zombie.origin - v_tag_pos );
n_dot = vectordot( v_tag_fwd, ai_zombie.origin );  // ← ai_zombie.origin, not v_to_zombie

if ( n_dot < 0.95 )
    continue;
```

`v_to_zombie` is the correct normalized direction from the flamethrower to the zombie.
`ai_zombie.origin` is a raw world-space position vector. The dot product of a unit forward
vector with a world position is the scalar projection of that position onto the forward axis —
this has no meaningful relationship to the zombie's angular position relative to the flamethrower.

The 0.95 threshold applied to a world position (typical range: –8192 to +8192) will produce
nonsensical results depending on where the tank currently is on the map. In practice, the
distance check (`dist_sq > 80*80`) acts as the primary filter, so the broken cone check has
partial implicit coverage. But targets at the edges of the 80-unit radius that are behind the
flamethrower are not filtered out, and the check's effective behavior varies with tank position.

**Fix:**
```gsc
n_dot = vectordot( v_tag_fwd, v_to_zombie );  // TANK-MI-01 fix: was ai_zombie.origin
```

### 11d. TANK-MI-02: Identical distance expressions in `enemy_location_override` — stopped-tank zombies always route to back

`zm_tomb_tank.gsc` lines 1663–1670 (`enemy_location_override`).

When the tank is stopped and a zombie's favorite enemy is on it, the code should route the
zombie to whichever end of the tank is closer:

```gsc
// Original (broken):
front_dist = distance2dsquared( enemy.origin, level.vh_tank.origin );
back_dist  = distance2dsquared( enemy.origin, level.vh_tank.origin );  // ← identical

if ( front_dist < back_dist )   // always false — equal values
    location = tank_front;
else
    location = tank_back;       // always taken
```

Both expressions use `level.vh_tank.origin` — the tank's center. `front_dist` and `back_dist`
are always equal, so the comparison is always false and zombies always route to `tank_back`.

`tank_front` and `tank_back` were computed on lines 1627–1628 (the two tag origins) and are
the intended targets:

```gsc
// Fixed:
front_dist = distance2dsquared( enemy.origin, tank_front );
back_dist  = distance2dsquared( enemy.origin, tank_back );
```

**Impact:** Not a crash vector. Zombies still reach the tank. The visible symptom is zombies
preferring the rear entry point even when the front is closer, causing suboptimal pathing
and mild pileups at the back of a stopped tank.

### 11e. TANK-MI-03: O(n-zombies) 20Hz polling loop in `zombies_watch_tank`

`zm_tomb_tank.gsc` lines 989–1007 (`zombies_watch_tank`).

```gsc
while ( true )
{
    a_zombies = get_round_enemy_array();

    foreach ( e_zombie in a_zombies )
    {
        if ( !isdefined( e_zombie.tank_state ) )
            e_zombie thread tank_zombie_think();
    }

    wait_network_frame();  // 0.05s
}
```

This loop runs at 20 Hz scanning the entire zombie array. Its purpose is to assign
`tank_zombie_think()` threads to newly-spawned zombies. Once a zombie has been threaded,
`isdefined(e_zombie.tank_state)` is true and the inner body is skipped — but the loop still
traverses the array on every iteration.

At high rounds (24 active zombies), this is 480 `isdefined` checks per second that return true
and do nothing. The work is proportional to zombie count and runs for the entire session.

The spawner already provides `add_custom_zombie_spawn_logic()`, which accepts a function
pointer and calls it as a thread on each zombie as it spawns. This is exactly the event-driven
equivalent.

**Fix:**
```gsc
zombies_watch_tank()
{
    a_tank_tags = tank_tag_array_setup();
    self.a_tank_tags = a_tank_tags;
    a_mechz_tags = mechz_tag_array_setup();
    self.a_mechz_tags = a_mechz_tags;

    // TANK-MI-03 fix: replaced 20Hz O(n-zombies) scan with per-spawn callback
    maps\mp\zombies\_zm_spawner::add_custom_zombie_spawn_logic( ::tank_zombie_think );
}
```

This reduces the recurring overhead from O(n) at 20Hz to a single O(1) registration at map
init, with each `tank_zombie_think` thread started exactly once per zombie at spawn time —
identical behavior, no idle polling.

---

**Summary for Origins tank system:**

| ID | Bug | Effect | Severity |
|---|---|---|---|
| TANK-EL-01 | `e_linker` entity leak on disconnect during run-over animation | 1 entity leaked per occurrence | Low — rare trigger condition |
| TANK-TL-01 | `tank_push_player_off_edge` threads don't terminate on disconnect | 2 threads leaked per disconnect-while-on-tank | Low — rare trigger condition |
| TANK-MI-01 | Flamethrower cone check uses world position instead of direction vector | Broken angular filter; distance check compensates partially | Low — logic error, no crash |
| TANK-MI-02 | Stopped-tank zombie routing: identical distance expressions | Zombies always route to back of stopped tank | Low — behavioral anomaly |
| TANK-MI-03 | 20Hz O(n-zombies) zombie registration poll | Unnecessary sustained CPU pressure at high rounds | Medium — replaced with spawn callback |
| (SA-10 note) | Tank side flamethrowers used same broken `flame_damage_fx` | SA-10 fix already covers this path | Resolved by SA-10 fix |

---

## Unknowns Flagged for Runtime Verification

These are things our static analysis can't determine. Phase 2 diagnostic tools are built and ready to resolve them once we test on Plutonium.

| # | Unknown | How We'll Test It | Tool |
|---|---------|------------------|------|
| 1 | **Exact entity limit:** Is it 1024? Could be different on PC (Plutonium) vs Xbox 360. | Entity headroom probe spawns `script_origin` entities until `spawn()` fails, counting the max. `/st fill 1000` pushes to the limit directly. **RESOLVED: 1024 confirmed (EL-02 test).** | `zm_diagnostics.gsc`, `zm_stress_test.gsc` |
| 2 | **Actual leak rate:** Our estimate of 3-9 per round is based on reasoning about gameplay. | Monitor headroom min across rounds. The slope of headroom decline = leak rate. Round-start logger captures this data automatically. | `zm_diagnostics.gsc` |
| 3 | **`spawn()` failure behavior:** Does it return `undefined`? Crash? Silently fail? | `/st fill` spawns entities until failure and reports the mode of failure. The probe in diagnostics also tests this every 5 seconds. **RESOLVED: hard crash (`COM_ERROR`), no graceful failure.** | Both |
| 4 | **Sound notify reliability:** How often does `playsoundwithnotify` fail to fire the callback under load? | Watch entity headroom during rounds with heavy audio (Insta-Kill, nukes). If headroom drops faster during these events, EL-04 is confirmed. | `zm_diagnostics.gsc` |
| 5 | **`has_attachment()` call frequency:** Is it called during normal zombies gameplay or only in edge cases? | Requires code path analysis. We can write a targeted test script that calls it directly to confirm the freeze. **RESOLVED: freeze confirmed from addon script (IL-01 test); fix requires FF replacement.** | Test protocol (Test 3) |
| 6 | **Float precision threshold:** At what exact value does the powerup drop comparison break? | Monitor `zombie_powerup_drop_increment` via HUD. `/st dropinc` can set it to specific values for threshold testing. | Both |
| 7 | **Whether Plutonium's engine has any patches:** Plutonium may have already fixed some engine-level issues. | Run baseline tests without our patches. If issues don't reproduce, Plutonium may have fixed them. | Test protocol |
| 8 | **Exact scrVar pool size in T6/Plutonium:** The pool size is a compile-time engine constant. We don't have the engine source. Community reports suggest ~16k–32k but this is unconfirmed. | A diagnostic script could count total `level.*` fields + active entity fields + active thread count to estimate current pool usage. The crash itself provides an upper bound. | `zm_diagnostics.gsc` (new probe needed) |
| 9 | **Safe cleanup strategy for `self.hitsthismag`:** Clearing on weapon drop is the obvious fix, but `hitsthismag` may be read in contexts we haven't traced. A round-start clear might be safer. | Trace all read sites of `self.hitsthismag` in the codebase to confirm reads are always guarded by `isdefined`. If so, clearing is safe. **RESOLVED: all read sites are `isdefined`-guarded (see below). Round-start prune is safe. One minor caveat: `updatemagshots` does an unguarded `self.hitsthismag[weaponname]--` write (no read), called in the same frame as the guard — safe. Its `wait 0.05` then `= weaponclipsize(...)` write could re-insert a just-pruned key for the currently-fired weapon, which is harmless (the weapon is still held).** | Static analysis |
