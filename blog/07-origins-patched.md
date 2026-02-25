# Origins Fixed: The Two Weapons That Were Quietly Draining the Server

*Part 7 of the BO2 High-Round Crash Fix series.
[Part 1](01-the-archaeology.md) | [Part 2](02-the-diagnostic-tools.md) | [Part 3](03-entity-leaks.md) | [Part 4](04-the-patch.md) | [Part 5](05-results.md) | [Part 6](06-fixing-the-core.md) | [Part 8](08-die-rise-patched.md) | [Part 9](09-the-full-patch.md) | [Part 10](10-generators-patched.md) | [Part 11](11-tank-patched.md) | [Part 12](12-testing-origins-staffs.md) | [Part 13](13-fire-staff-balance-gap.md)*

---

Part 5 projected that a fully-patched game would push Origins toward Buried-class
stability — around 100 hours of wall-clock runtime. That projection was based on
fixing the general entity leaks and overflow issues. It didn't yet model two
Origins-specific weapons that had their own bugs compounding the problem.

Both are now fixed.

---

## The Fire Staff: One Wrong Variable, Every Zombie, Every Tick

The upgraded Fire Staff's area-of-effect function spawns threads on nearby zombies
to apply burn damage over time. The relevant check is a dedup guard — if a zombie
is already burning, don't re-start the effect on it:

```gsc
// fire_staff_area_of_effect() — original (broken):
foreach ( e_target in a_targets )
{
    if ( isdefined( e_target ) && isalive( e_target ) )
    {
        if ( !is_true( self.is_on_fire ) )
            e_target thread flame_damage_fx( str_weapon, e_attacker );
    }
}
```

The check is `self.is_on_fire`. Inside `fire_staff_area_of_effect()`, `self` is the
projectile entity — the fireball that just landed. The projectile doesn't have an
`is_on_fire` field. `is_true( undefined )` returns false. So `!is_true( self.is_on_fire )`
is always true.

Every zombie in the AoE gets a new `flame_damage_fx` thread threaded on them, on
every tick of the AoE effect's duration, regardless of whether they're already
burning. The dedup guard never fires because it's checking the wrong entity.

The fix is one variable name:

```gsc
// Fixed:
if ( !is_true( e_target.is_on_fire ) )
    e_target thread flame_damage_fx( str_weapon, e_attacker );
```

Now it checks whether the target zombie is already on fire, not the projectile.

### Why this mattered at high rounds

At low rounds, this bug generates modest overhead. You're firing into groups of
5–10 zombies and the AoE duration is short. A few extra threads per fire blast
disappear into background noise.

At high rounds, the calculus changes. Panzer Soldaten appear — and players are
frequently using the Fire Staff specifically because its AoE is one of the few
reliable ways to handle groups when zombie HP is astronomical. High-round play on
Origins involves sustained Fire Staff usage against large, dense groups over many
rounds. The thread burst is no longer background noise — it's a recurring spike that
compounds with every other source of scrVar pressure already in the pool.

The underlying issue is a thread leak. `flame_damage_fx` runs for the full burn
duration. At high rounds with 15+ zombies in an AoE radius, a single upgraded fire
blast could generate 15 × N_ticks duplicate threads where the original intent was
to generate 15 × 1 (one per zombie, deduplicated). Each redundant thread holds
scrVar pool slots until it completes. The pool doesn't recover between blasts.

### The damage side-effect

The SA-10 fix has a visible gameplay consequence worth understanding. The AoE loop
runs for 5 seconds at 0.2-second intervals — 25 ticks. On each tick, every zombie
in range was getting a new `flame_damage_fx` call, which applies `get_impact_damage()`
instantly. For a fully charged shot (`staff_fire_upgraded3_zm`: 20,000 impact damage):

- **Unpatched:** 20,000 × 25 ticks = **500,000 damage** per zombie
- **Patched:** 20,000 (first tick) + 450 DPS × 8s burn = **~24,000 damage** per zombie

The bug was stacking 25 impact hits instead of one per zombie per blast. At R150
with millions of HP per zombie, the patched staff no longer kills outright.

This is a "bug as a feature" situation — and the reason it was never caught is
telling. The patched staff stops one-shotting at R41–44, exactly the round range
where a QA tester would have caught a weapon failing. But with SA-10 active, a
tester at R40–50 saw a staff that still cleared hordes effortlessly, because the
bug was delivering 500,000 damage rather than 24,000. The weapon appeared to work
correctly at every round that internal testing would have covered. The underlying
gap in the kill path was only visible from outside that window.

The full analysis — comparing all four staff kill paths, the in-game round measurements,
and the crash reproduction — is in [Part 13](13-fire-staff-balance-gap.md).

---

## The Wind Staff: The Invisible Zombie

The upgraded Wind Staff creates a whirlwind that needs a zombie to anchor to. The
function `staff_air_find_source()` iterates through zombies sorted by proximity to
the impact point, looking for the first alive one:

```gsc
// staff_air_find_source() — original (broken):
for ( i = 0; i < a_zombies.size; i++ )
{
    if ( isalive( a_zombies[i] ) )
    {
        if ( distance2dsquared( v_detonate, a_zombies[i].origin ) <= 10000 )
            self thread staff_air_zombie_source( a_zombies[0], str_weapon );
        // ...
        return;
    }
}
```

When zombie `i` passes the alive check and distance check, the code passes
`a_zombies[0]` — always the closest zombie by sort order — as the source, not
`a_zombies[i]` the zombie that actually passed both checks.

If `a_zombies[0]` is alive (the common case) these are the same. But at high
rounds, zombie death and recycling is rapid. By the time the loop has iterated to
find zombie `i` (because zombies 0 through i-1 are dead), the entity slot for
`a_zombies[0]` may have been recycled and assigned to an entirely different entity.
The whirlwind anchors to that recycled entity instead of the intended zombie.

The result: a zombie counted by the round system with no visible entity in the world.
The round completion check waits for `zombie_total` to reach 0. A zombie referencing
a recycled entity never dies from a gameplay perspective — its "death" event doesn't
fire through the normal path. The round can soft-lock.

The fix:

```gsc
// Fixed:
self thread staff_air_zombie_source( a_zombies[i], str_weapon );
```

Pass the actually-alive zombie at index `i`, not `a_zombies[0]`.

---

## The Combined Effect on Origins

Origins already consumed entity budget faster than any other map due to its baseline
overhead: three active Giant Robots, Panzer Soldaten with complex AI, dynamic weather
zones. Both of these bugs added additional pressure on top:

- SA-10 (Fire Staff) compounded scrVar pool usage via redundant thread bursts during
  heavy AoE use
- MI-06 (Wind Staff) created invisible zombies that could soft-lock round completion,
  preventing the map from advancing and extending the session artificially

With both bugs fixed, the Origin-specific pressure sources are eliminated. The
remaining ceiling is the same entity accumulation rate that applies to all maps —
modulated by Origins' higher baseline entity overhead.

---

## Deploying the Origins Fixes

Both fixes ship in the same `mod.ff` as the core patch. There are no separate mods
to enable — the combined `mod.ff` in `mods/zm_hrp/` covers everything:

```bash
./build_ff.sh
```

Copy the resulting `/tmp/oat_hrp_build/zone_out/zm_hrp/mod.ff` to
`%LOCALAPPDATA%\Plutonium\storage\t6\mods\zm_hrp\mod.ff`. The existing mod
selection in Plutonium stays the same.

The Origins fixes only activate when playing Origins — the patched scripts are only
loaded when `zm_tomb.ff` is in scope. On other maps they're dormant.

*Source and test data at [github.com/banq/t6-high-round-fix](#).*
