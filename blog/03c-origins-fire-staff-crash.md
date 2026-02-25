# The Fire Staff's Hidden Tax: One Wrong Variable, Hundreds of Threads

*A companion to Part 3 — How BO2 Zombies Slowly Runs Out of World*

---

In the previous posts we traced one scrVar crash to Tranzit's Jet Gun + Tazer Knuckles knife glitch — a strategy that enables such a long session that the weapon string accumulation in `self.hitsthismag` eventually fills the pool. The fix is a round-start prune.

Origins players report the same crash, but earlier, and specifically associated with the Fire Staff — not box cycling, not a particular glitch, just using the Fire Staff normally. The weapon is the same one everyone builds on Origins. This post explains why.

There are two mechanisms. One is a more severe version of the SA-08 accumulation story we've already told. The other is a coding bug in the Fire Staff's area-of-effect logic that creates hundreds of unnecessary threads on every shot — and is unfixable from an addon script.

---

## The Fire Staff's AoE: How It's Supposed to Work

The upgraded Fire Staff (`staff_fire_upgraded2_zm` / `staff_fire_upgraded3_zm`) fires a grenade-type projectile. On impact, the projectile detonates and creates a lingering AoE that deals fire damage and sets zombies aflame. Each zombie that catches fire gets a dedicated "burning" state: damage-over-time ticks, visual fire effect, a slowed-down run cycle, a death animation override. Fire state lasts 8 seconds.

The function managing this is `fire_staff_area_of_effect`. It runs as a thread on the projectile entity, looping every 0.2 seconds for 5 seconds:

```gsc
fire_staff_area_of_effect( e_attacker, str_weapon )
{
    self waittill( "explode", v_pos );   // self = projectile entity
    // ...
    while ( n_alive_time > 0.0 )
    {
        a_targets = getaiarray( "axis" );
        a_targets = get_array_of_closest( v_pos, a_targets, undefined, undefined, aoe_radius );
        wait( n_step_size );   // 0.2 seconds

        foreach ( e_target in a_targets )
        {
            if ( isdefined( e_target ) && isalive( e_target ) )
            {
                if ( !is_true( self.is_on_fire ) )
                    e_target thread flame_damage_fx( str_weapon, e_attacker );
            }
        }
    }
}
```

The guard on line `if ( !is_true( self.is_on_fire ) )` is meant to skip zombies that are already burning — don't ignite something that's already on fire, just let it burn. A sensible optimization.

It doesn't work. At all.

---

## The Bug: `self` Is the Projectile

`fire_staff_area_of_effect` is threaded onto the projectile entity:

```gsc
// in watch_staff_fire_upgrade_fired():
e_projectile thread fire_staff_area_of_effect( self, str_weapon );
```

Inside the function, `self` is therefore `e_projectile` — the fired grenade. The loop iterates over zombies stored in `e_target`. The guard should read `e_target.is_on_fire`. It reads `self.is_on_fire`.

The `is_on_fire` flag is set on zombie entities inside `flame_damage_fx`:

```gsc
flame_damage_fx( damageweapon, e_attacker, pct_damage )
{
    was_on_fire = is_true( self.is_on_fire );   // self = zombie
    // ...
    if ( !was_on_fire )
    {
        self.is_on_fire = 1;    // sets flag on zombie, not on projectile
        self thread zombie_set_and_restore_flame_state();
        wait 0.5;
        self thread flame_damage_over_time( e_attacker, damageweapon, pct_damage );
    }
}
```

No code anywhere sets `is_on_fire` on a projectile entity. The projectile always returns false for this check. The condition `!is_true(projectile.is_on_fire)` is permanently true.

**The deduplication guard is completely non-functional.** Every zombie in AoE range receives a new `flame_damage_fx` thread on every 0.2-second tick, for the full 5-second AoE lifetime — 25 ticks total — regardless of whether they've been on fire since tick 1.

---

## What This Costs

When `flame_damage_fx` runs on an already-burning zombie, `was_on_fire` is true and the thread just deals impact damage and exits. The cost is small — a brief thread frame that vanishes in under a frame. That's the tick-2-through-25 behavior for any zombie that was ignited on tick 1.

When `flame_damage_fx` runs on a fresh zombie (`was_on_fire = false`), it spawns three sub-threads on the zombie entity:

- `zombie_set_and_restore_flame_state()` — blocks on `self waittill("stop_flame_damage")`, alive for **8 seconds**
- `flame_damage_over_time()` — loops every second dealing burn damage, ends on `"stop_flame_damage"`, alive for **8 seconds**
- `on_fire_timeout()` — `wait 8`, then fires `notify("stop_flame_damage")`, alive for **8 seconds**

These are the 8-second threads. Each holds a thread frame with local variables — `n_damage`, `n_duration`, `e_attacker`, loop state — consuming scrVar pool slots for their entire lifetime.

Now count what a single tier-3 shot produces. The tier-3 staff fires 3 projectiles via `fire_additional_shots`, each with its own `fire_staff_area_of_effect` thread. With 24 zombies in range:

| | Count |
|---|---|
| Total `flame_damage_fx` threads spawned per shot | 3 projectiles × 25 ticks × 24 zombies = **1,800** |
| Threads that spawn the 3 long-lived sub-threads (first hit only) | 3 projectiles × 24 zombies × 1 first tick = **72** |
| Long-lived sub-threads alive concurrently | 72 × 3 sub-threads = **216** |
| scrVar slots consumed by those 216 threads | 216 × ~7 local vars = **~1,512 slots** |

1,512 scrVar slots held for 8 seconds, refreshed on every shot. At rapid fire, multiple AoE windows overlap. The pool never drains between shots.

This is not permanent monotonic accumulation like SA-08. It's burst pressure — a spike on every shot. The distinction matters for understanding when the crash happens: it's not "eventually, after enough rounds" like the Jet Gun run. It's "when the baseline pool level from SA-08/SA-09 accumulation gets high enough that a single Fire Staff volley at a dense horde pushes it past the limit."

---

## The Bug as a Feature — And Why QA Never Caught It

SA-10 has a second consequence that only surfaces once the bug is fixed: the Fire
Staff's charged shot loses its ability to one-shot zombies at high rounds.

Each of those 25 `flame_damage_fx` calls delivers `get_impact_damage()` instantly —
20,000 damage for a fully charged shot. 25 × 20,000 = **500,000 effective damage per
zombie** per blast, due entirely to the broken dedup guard. The intended design is
one application: 20,000 impact damage plus an 8-second 450 DPS burn — roughly 24,000
total.

Comparing the four staffs' charged-shot kill paths in source makes the gap obvious:

- **Water Staff** — `always_kill = 1` hardcoded in `ice_staff_blizzard_do_kills()`.
  Routes through `do_damage(self.health)`. Kills at any round number.
- **Wind Staff** — both fling and gib paths call `do_damage(self.health)`.
  Kills at any round number.
- **Fire Staff** — fixed 20,000 impact + 450 DPS burn. Insta-kill path exists but
  requires `impact_damage > zombie.health && cointoss()`, which becomes
  permanently false above approximately round 30.

The patched Fire Staff stops one-shotting at round 41–44, exactly where zombie HP
crosses the 20,000 impact damage value. That is a very common QA and casual high-round
target — the kind of round developers would actively test an upgraded weapon at. A
QA tester reaching round 40–50 with the unpatched staff would see it still clearing
hordes cleanly, because SA-10 was delivering 500,000 damage per zombie rather than
24,000. There was no observable failure to catch.

This is the reason the design gap was never noticed: the bug happened to produce
convincing weapon performance at exactly the rounds where testing would have revealed
the problem. The developers shipped Origins in 2013 with a Fire Staff that appeared
to work correctly at high rounds in every internal test — because at R40–50, with
SA-10 active, it did. The underlying weakness only becomes visible once the crash bug
is removed, twelve years later.

This is a classic "bug as a feature" situation — the most insidious kind, where the
bug is not misbehaviour that gets caught, but compensation that prevents a different
flaw from being noticed at all. The full analysis, including in-game measurements that
confirm the damage cliff at exactly the predicted round, is in
[Part 13](13-fire-staff-balance-gap.md).

---

## The Other Mechanism: Four Names for One Weapon

The Fire Staff also amplifies the SA-08 accumulation issue we've documented on Tranzit, independently of the AoE bug.

Each upgrade tier of the Fire Staff uses a completely distinct weapon name string:

```
staff_fire_zm               (base staff, from the buildable)
staff_fire_upgraded_zm      (after Puzzle 1 and soul collection)
staff_fire_upgraded2_zm     (after Puzzle 2 and soul collection)
staff_fire_upgraded3_zm     (after the final charger upgrade)
staff_fire_melee_zm         (melee variant, separate slot)
```

Every time you upgrade — which means `takeweapon` + `giveweapon` on the new tier name — you get a `weapon_change` event. `watchweaponchangezm()` sees a new string, checks `self.hitsthismag["staff_fire_upgraded2_zm"]`, finds it undefined, and writes a permanent new entry:

```gsc
if ( !isdefined( self.hitsthismag[newweapon] ) )
    self.hitsthismag[newweapon] = weaponclipsize( newweapon );
```

All four elemental staves follow the same pattern:

| Staff | Weapon name variants |
|---|---|
| Fire | `staff_fire_zm`, `staff_fire_upgraded_zm`, `staff_fire_upgraded2_zm`, `staff_fire_upgraded3_zm`, `staff_fire_melee_zm` |
| Air | `staff_air_zm`, `staff_air_upgraded_zm`, `staff_air_upgraded2_zm`, `staff_air_upgraded3_zm`, `staff_air_melee_zm` |
| Water | `staff_water_zm`, `staff_water_upgraded_zm`, `staff_water_upgraded2_zm`, `staff_water_upgraded3_zm`, `staff_water_melee_zm` |
| Lightning | `staff_lightning_zm`, `staff_lightning_upgraded_zm`, `staff_lightning_upgraded2_zm`, `staff_lightning_upgraded3_zm`, `staff_lightning_melee_zm` |

A player who builds and fully upgrades all four staves accumulates up to **20 permanent `hitsthismag` entries** from staff weapons alone. A Tranzit box cycling session of equal length doesn't come close — Tranzit weapons have one or two name variants at most.

Origins sessions are also longer by design. The Easter egg, four staves to build and upgrade, the generators and challenges — all of it extends play time, which means more box cycling, which means more SA-08 accumulation on top of the 20 staff entries. The map is structurally adversarial against the scrVar pool in a way Tranzit isn't.

---

## Why Specifically the Fire Staff

The community associates the crash with the Fire Staff rather than the Air, Water, or Lightning staves. Both mechanisms explain this:

**The AoE bug is Fire Staff-only.** Look at how the Air Staff handles per-zombie operations in `whirlwind_kill_zombies`:

```gsc
// _zm_weap_staff_air.gsc — correct pattern
for ( i = 0; i < a_zombies.size; i++ )
{
    // ...
    a_zombies[i] thread whirlwind_drag_zombie( self, str_weapon );
    wait 0.5;
}

whirlwind_drag_zombie( e_whirlwind, str_weapon )
{
    if ( isdefined( self.e_linker ) )    // guard checks the ZOMBIE, not the whirlwind
        return;
    // ...
}
```

The Air Staff's deduplication guard reads from the zombie entity. It works. The Water (Frost) Staff uses a water damage-over-time pattern with no per-tick thread flooding. The Lightning Staff arcs between targets but doesn't maintain a per-zombie-per-tick thread loop. The `is_on_fire` pattern — a multi-second loop spawning per-zombie threads on every tick — is specific to how the Fire Staff's AoE was implemented.

**The tier-3 multiplier.** `fire_additional_shots` fires 2 extra projectiles for tier-3, tripling the AoE thread cost. The other staves don't have this multi-projectile behavior on their highest tier.

**The Fire Staff is built first.** Origins players almost universally build and upgrade the Fire Staff before the others. They've accumulated the most fire staff play-hours by the time they crash — and the crash happens during Fire Staff use because that's when the burst pressure peaks.

---

## Fix Feasibility

The two mechanisms have different fix pictures.

**SA-11 (weapon string accumulation):** `zm_patch_scrvar.gsc` already handles this. At round start, the prune checks `self getweaponslist()` and discards any `hitsthismag` entry for a weapon the player no longer holds. A player who upgraded from `staff_fire_zm` to `staff_fire_upgraded3_zm` and no longer has the lower tiers loses those entries at the next round boundary. The patch's benefit is proportionally larger on Origins than any other map because there are so many more stale staff tier names to clear.

**SA-10 (the AoE `is_on_fire` reference bug):** This is not fixable from an addon script.

```gsc
// The fix is one change:
if ( !is_true( e_target.is_on_fire ) )    // was: self.is_on_fire
    e_target thread flame_damage_fx( str_weapon, e_attacker );
```

But `fire_staff_area_of_effect` is compiled into `zm_tomb.ff` — the Origins DLC zone file. The function is called directly from compiled code in `watch_staff_fire_upgrade_fired` via a direct function pointer: `e_projectile thread fire_staff_area_of_effect(...)`. An addon script can define a new function with the same name, but the compiled caller already holds a reference to the original. The new definition is never invoked. This is the same FF replacement limitation we documented for `has_attachment` (IL-01) — the fix exists, the distribution path doesn't.

What the patch does accomplish: by keeping the scrVar pool drained of stale weapon strings, there's substantially more headroom before the next Fire Staff volley tips it over. The burst pressure from SA-10 is still there; the floor it's pushing against is much lower.

---

## The Shape of the Two Crashes

The Jet Gun and Fire Staff crashes look different in practice, even though they share the same error message:

| | Jet Gun (Transit) | Fire Staff (Origins) |
|---|---|---|
| Session length at crash | Extreme (world record territory) | Long but achievable by typical high-round players |
| Primary mechanism | SA-08 accumulation over extraordinary session | SA-10 burst pressure on top of SA-11 accumulation |
| Crash trigger | Pool gradually fills to limit over many hours | Pool pre-depleted by accumulation, then tipped by a heavy volley |
| Fixable from addon | Yes — SA-08 prune addresses it entirely | Partially — SA-11 addressed, SA-10 requires FF replacement |
| Gameplay enabler | Glitch allows indefinitely long session | No glitch needed — the weapon is legitimately strong |

The Jet Gun crash is a consequence of a player being exceptionally skilled and the scrVar pool not being designed for a 100-hour session. The Fire Staff crash is a consequence of a coding bug that the player triggers every time they fire an upgraded shot.

---

The one-character fix that would resolve SA-10 — changing `self` to `e_target` on a single line — is sitting in the decompiled source right now, visible and obvious. The zone file it lives in is the barrier. For anyone running Origins from source-compiled scripts rather than the shipped zone file, it's a trivial patch. For the rest of the player base, the scrVar prune is the best available mitigation: keep the pool low enough that the burst has somewhere to go.

> **Update:** SA-10 was subsequently fixed via FF replacement using
> [OpenAssetTools](https://github.com/Laupetin/OpenAssetTools). The technique and
> its application to Origins are covered in [Part 6](06-fixing-the-core.md) and
> [Part 7](07-origins-patched.md). The fix ships in the `zm_hrp/mod.ff` patch.
>
> **Update:** The thread-burst theory was confirmed in-game. Testing at R80 with
> the unpatched mod reproduced the crash on demand by spamming charged shots —
> directly demonstrating the link between the thread count and the game termination.
> Round-by-round damage measurements also confirmed the 500k effective damage cap
> and the exact round where the patched staff loses its one-shot kill (R41→R44,
> precisely where zombie HP crosses the 20,000 impact damage value). Full test
> results and the balance gap analysis are in [Part 13](13-fire-staff-balance-gap.md).

*All scripts and test data are at [github.com/banq/t6-high-round-fix](#).*
