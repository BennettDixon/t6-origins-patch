# SA-10 / MI-06 Test Results: Origins Staff Fixes

**Date:** _pending_  
**Status:** _pending_

---

## Bugs Fixed

### SA-10 — Fire Staff AoE wrong target variable
`_zm_weap_staff_fire.gsc` line 143

Original: `if ( !is_true( self.is_on_fire ) )` — `self` is the projectile entity, not
the zombie being damaged. The burn-state dedup check always read from the wrong entity,
so it always evaluated false. Every zombie in the AoE was threaded with a new
`flame_damage_fx` call on every damage tick, regardless of whether they were already
burning. At high rounds with many zombies in the AoE, this generates O(zombies × ticks)
threads per Fire Staff discharge.

Fix: `if ( !is_true( e_target.is_on_fire ) )` — checks the actual target zombie.

### MI-06 — Wind Staff stale zombie source reference
`_zm_weap_staff_air.gsc` line 104

Original: `self thread staff_air_zombie_source( a_zombies[0], str_weapon )` — the loop
iterated through `a_zombies` at index `i` to find the first alive zombie, but still
passed `a_zombies[0]` (the closest, possibly dead, zombie) as the whirlwind source.

Fix: `self thread staff_air_zombie_source( a_zombies[i], str_weapon )` — passes the
actually-alive zombie at index `i`.

---

## Prerequisites

- Map: `zm_origins`
- Mod: `zm_hrp` enabled (Private Match → Select Mod)
- Scripts loaded: `zm_diagnostics.gsc`, `zm_stress_test.gsc`, `zm_highround_patch.gsc`
- Load into a game and use `set st_cmd skip 15` to reach round 15+ (elevated zombie count)

---

## SA-10 Test Procedure

**Goal:** Confirm the burn-state dedup check fires correctly and only one
`flame_damage_fx` thread runs per zombie at a time.

**Note on metrics:** The `SV` counter in the HRP HUD tracks SA-08/SA-09 scrVar
pruning (stale `hitsthismag` entries) — it does **not** reflect Fire Staff thread
pressure. There is no real-time thread counter in the HUD for SA-10. The fix is
verified by code inspection + behavioral observation.

**Observable behavior:**
- Unpatched: `flame_damage_fx` is re-threaded on every damage tick for every zombie
  in the AoE regardless of burn state. Multiple simultaneous burn threads stack their
  periodic damage, causing zombies to die much faster than normal from a single staff
  discharge and causing noticeable hitching at R50+ with 20+ burning zombies.
- Patched: each zombie gets at most one `flame_damage_fx` thread. Burn duration and
  damage match expected values from the weapon design.

1. Load `zm_origins`. Skip to R15: `set st_cmd skip 15`
2. Enable god mode: `set st_cmd god`
3. Give the fully upgraded Fire Staff: `set st_cmd givestafffire`
   (weapon given via `givestartammo`, matching the game's own craftable pickup path)
4. Fire the Fire Staff at a group of 5+ tightly-clustered zombies.
5. Observe how quickly the zombies die and whether the game hitches/lags.
6. For a soak comparison: reach R50+ and continuously re-fire into groups of 20+.

**Pass (patched):**
- Zombies take a normal number of hits to kill; burn duration matches the weapon design
- No noticeable lag or hitching at R50+ when re-firing into a burning group

**Fail (unpatched):**
- Zombies die almost instantly from a single burst (stacked burn threads)
- Server script tick becomes sluggish with 20+ burning zombies at high rounds

**Verifying the `SV` counter itself** (unrelated to SA-10, but useful):
1. `set st_cmd weap 20` — inflates your `hitsthismag` with 20 fake stale entries
2. `set st_cmd skip 1` — drains the zombie queue; round ends naturally
3. On the next round's `start_of_round`, `hrp_prune_player()` fires and removes the 20 fake entries
4. `SV` in the HRP HUD should jump by 20

---

## MI-06 Test Procedure

**Goal:** Confirm the whirlwind anchors to the correct (alive) zombie when the
closest zombie (`a_zombies[0]`) has just died.

**Observable behavior:**
- Unpatched: whirlwind attaches to the dead/recycled entity → no visible whirlwind
  or an "invisible zombie" that can't be killed but counts toward the zombie total
- Patched: whirlwind attaches to the first alive zombie → visible whirlwind, normal behavior

1. Load `zm_origins`. Skip to R10: `set st_cmd skip 10`
2. Enable god mode: `set st_cmd god`
3. Give the Wind Staff: `set st_cmd givestaffair`
4. Kill all but 2 zombies: `set st_cmd kill` then wait for 2 to remain naturally,
   or manually kill down to 2.
5. Ensure one zombie is closer to you than the other (it will be `a_zombies[0]`).
6. Kill that closest zombie.
7. **Immediately** fire the Wind Staff while the corpse is still settling.
8. Observe the whirlwind effect.

**Pass (patched):**
- Whirlwind renders visibly and pulls/kills the remaining alive zombie
- No invisible zombie spawned; zombie total reaches 0 normally

**Fail (unpatched):**
- Whirlwind attaches to the dead zombie's position — no visible effect, or the
  game spawns a replacement zombie that can't be damaged (invisible)
- `level.zombie_count` stays > 0 even after the visible zombie is killed

---

## Results

### SA-10 — Fire Staff AoE dedup

| Condition | Zombies die at normal speed? | Hitching at R50+? | Notes |
|-----------|------------------------------|-------------------|-------|
| Patched   | _                            | _                 | _     |
| Unpatched (optional control) | _ | _ | _ |

Notes: _

**SA-10 verdict:** _PASS / FAIL_

---

### MI-06 — Wind Staff zombie source

| Condition | Whirlwind visible? | Invisible zombie? | Round ends normally? |
|-----------|--------------------|-------------------|----------------------|
| Patched   | _                  | _                 | _                    |
| Unpatched (optional control) | _ | _ | _ |

Notes: _

**MI-06 verdict:** _PASS / FAIL_

---

**Overall:** _PASS / FAIL_
