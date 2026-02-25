# The Fire Staff Balance Gap: A Bug That Hid a Design Flaw for Twelve Years

*Part 13 of the BO2 High-Round Crash Fix series.
[Part 1](01-the-archaeology.md) | [Part 2](02-the-diagnostic-tools.md) | [Part 3](03-entity-leaks.md) | [Part 4](04-the-patch.md) | [Part 5](05-results.md) | [Part 6](06-fixing-the-core.md) | [Part 7](07-origins-patched.md) | [Part 8](08-die-rise-patched.md) | [Part 9](09-the-full-patch.md) | [Part 10](10-generators-patched.md) | [Part 11](11-tank-patched.md) | [Part 12](12-testing-origins-staffs.md) | [Part 14](14-frozen-rounds-float32.md)*

---

When the SA-10 fix was verified in-game, an unexpected result appeared: the upgraded
Fire Staff charged shot no longer kills a horde at higher rounds. The Water Staff charged
shot still does. The assumption was that the Fire Staff was a mid-game weapon by design.
Closer inspection of all four staff kill paths suggests something different — the SA-10
bug had been silently compensating for a design gap in the Fire Staff for as long as
Origins has existed.

---

## How Each Staff Kills at High Rounds

Each staff has a charged-shot mechanic. When you hold fire, `chargeshotlevel` builds
up. On release, a projectile is fired as `staff_*_upgraded2_zm` (partial charge) or
`staff_*_upgraded3_zm` (full charge). The impact triggers the staff's dedicated damage
handler. Here is exactly what each handler does to a zombie at high rounds:

### Water Staff — unconditional `self.health`

```gsc
// ice_staff_blizzard_do_kills() calls:
zombie thread ice_affect_zombie( str_weapon, player, 1 );  // always_kill = 1

// ice_affect_zombie():
if ( instakill_on || always_kill )  // always_kill is always 1 from blizzard
    staff_water_kill_zombie( e_player, str_weapon );

// staff_water_kill_zombie():
self do_damage_network_safe( player, self.health, str_weapon, "MOD_RIFLE_BULLET" );
```

`always_kill = 1` is hardcoded. The blizzard always calls `do_damage(self.health)`.
Every zombie inside the blast radius at any round number is killed. Round 150, round
1000 — irrelevant. The Water Staff scales infinitely by construction.

### Wind Staff — unconditional `self.health`

```gsc
// staff_air_fling_zombie():
if ( isdefined( self.is_source ) || cointoss() )
    self thread zombie_launch( player, "staff_air_upgraded_zm" );
else
    self do_damage_network_safe( player, self.health, "staff_air_upgraded_zm", "MOD_IMPACT" );

// zombie_launch():
self do_damage_network_safe( e_attacker, self.health, str_weapon, "MOD_IMPACT" );
```

Both paths deal `self.health`. The `cointoss()` determines launch-and-die vs
gib-in-place, not whether the zombie dies. Every zombie caught in the whirlwind
is killed regardless of HP. The Wind Staff also scales infinitely.

### Lightning Staff — `self.health` when `damage >= health`

```gsc
// staff_lightning_ball_damage_over_time():
n_damage_per_pulse = get_lightning_ball_damage_per_sec( chargeshotlevel );
// max charge = 3500 per second

if ( n_damage_per_pulse < e_target.health && !instakill_on )
    e_target do_damage_network_safe( e_attacker, n_damage_per_pulse, ... );
else
{
    e_target thread staff_lightning_kill_zombie( e_attacker, str_weapon );
    // → do_damage_network_safe( player, self.health, ... )
}
```

The lightning ball deals 3,500 damage per second. When that exceeds the zombie's HP
it switches to `do_damage(self.health)`. At round 30–40, zombie HP crosses 3,500 and
the instant-kill path becomes unreachable. From that point the lightning staff is
chipping damage, not killing. The Lightning Staff degrades above roughly round 40 but
does not soft-floor — it still applies stun and chip damage useful for crowd control.

### Fire Staff — `self.health` only when `impact_damage > health && cointoss()`

```gsc
// flame_damage_fx():
n_initial_dmg = get_impact_damage( damageweapon );
// staff_fire_upgraded3_zm = 20,000

if ( is_upgraded && pct_damage > 0.5 && n_initial_dmg > self.health && cointoss() )
{
    self do_damage_network_safe( e_attacker, self.health, damageweapon, "MOD_BURNED" );
    // gib and return
}

// Otherwise: apply fixed 20,000 damage + start 450 DPS burn thread
```

The `self.health` path requires two conditions: impact damage (fixed at 20,000)
exceeds the zombie's HP, **and** a coin flip succeeds. At round 30+, zombie HP exceeds
20,000 and this branch becomes permanently unreachable. From that point the charged
Fire Staff deals 20,000 on impact and 450 DPS for 8 seconds — roughly 24,000 total
per zombie, at a round where zombies have hundreds of thousands of HP.

---

## The Effect of SA-10 on Effective Fire Staff Damage

The SA-10 bug caused `fire_staff_area_of_effect()` to call `flame_damage_fx` on every
zombie on every AoE tick, bypassing the dedup check that was supposed to fire once per
zombie. The AoE runs for 5 seconds at 0.2-second intervals — 25 ticks. Each call
delivers `n_initial_dmg` immediately, regardless of burn state.

For a fully charged shot (`staff_fire_upgraded3_zm`, 20,000 impact damage per call):

| | Damage per zombie |
|---|---|
| Unpatched (SA-10 active) | 20,000 × 25 ticks = **500,000** |
| Patched (SA-10 fixed) | 20,000 × 1 tick + 3,600 DOT = **~24,000** |

SA-10 gave the Fire Staff effective round-scaling by repeating the fixed impact damage
25 times per blast. 500,000 damage kills at round 50+. 24,000 does not. The Fire Staff
appeared to be a functional high-round weapon for the entire twelve-year history of the
map, but that capability was entirely provided by the bug, not by the weapon's design.

---

## In-Game Test Results

The following was tested with the `givestafffire` command (upgraded Fire Staff) and
`set st_cmd god` active, firing fully charged shots into single zombies. Zombie HP was
read from the diagnostics HUD. Both patched (`zm_hrp` mod enabled) and unpatched
(`zm_hrp` mod disabled) runs were recorded.

### Patched (`zm_hrp` enabled — SA-10 fixed, ~24,000 effective damage)

| Round | Zombie HP | Charged shots to kill | Notes |
|---|---|---|---|
| 41 | ~19,000 | 1 | HP < 20,000 impact — still within single-shot range |
| 44 | ~26,000 | 2 | HP exceeds 20,000 impact — one shot no longer kills |

The crossover at R41→R44 is exactly where the code predicts it: `get_impact_damage`
returns 20,000 for `staff_fire_upgraded3_zm`. Once zombie HP exceeds that, a single
charged shot cannot kill regardless of burn DOT. The burn adds ~3,600 over 8 seconds
but that is negligible when the HP gap is already 6,000+.

### Unpatched (`zm_hrp` disabled — SA-10 active, up to ~500,000 effective damage)

| Round | Zombie HP | Charged shots to kill | Notes |
|---|---|---|---|
| 46 | ~30,000 | 1 | Well within 500k cap — instant kill |
| 60 | ~122,000 | 1 | Still well within cap |
| 70 | ~316,000 | 1 | Approaching midpoint of cap |
| 74 | ~463,000 | 1–2 | Near the 500k ceiling — occasional 2nd shot needed |
| 80 | ~821,000 | 2–3 | Exceeds cap — threads compete, not all deliver |

The unpatched staff kills reliably up to round 74 (~463k HP), then starts requiring
2–3 shots at round 80 (~821k HP). This matches the 500,000 theoretical cap (25 ticks
× 20,000). Above that ceiling the 25 simultaneous threads are competing for execution
on the same zombie in the same script frame — not all of their `do_damage_network_safe`
calls land cleanly, so effective damage is somewhat less than the theoretical maximum.

### What this proves

The two datasets confirm the theory from both sides:

1. **Patched** — the damage cliff appears exactly at zombie HP = 20,000 (R41→R44).
   This is the `get_impact_damage` return value for `staff_fire_upgraded3_zm`. There
   is no ambiguity: one shot kills below this threshold, two are required above it.

2. **Unpatched** — the staff one-shots at R60 (122k HP) and R70 (316k HP) where the
   patched version cannot. The only source of that extra damage is 24 additional
   `flame_damage_fx` calls landing their 20,000 impact hits per tick. It stops being
   reliable around R74–R80 because the 25-thread burst begins exceeding what the
   script runtime can execute cleanly in a single frame, not because of any design
   limit.

Together these measurements directly demonstrate SA-10 as a damage bug, not just a
thread-leak bug. The unpatched staff is effectively a different weapon to the patched
one — not because of a balance decision, but because a one-variable typo (`self` vs
`e_target`) caused 24 extra damage applications per zombie per shot.

### Crash reproduction at round 80

Spamming charged shots on round 80 with the unpatched mod reproduced a game crash.
This closes the loop on SA-10 entirely. At R80 each charged shot spawns approximately
25 `flame_damage_fx` threads per zombie in the blast radius. With a full horde that
is hundreds of concurrent threads per shot. Spam several charged shots in quick
succession and the thread pool saturates — the same failure mode that causes the
high-round crash under sustained play, reproduced on demand in a single session.

This is the clearest possible proof that SA-10 is a crash bug, not only a damage bug:
the thread accumulation is directly observable as degrading kill performance (the
R74–R80 shot-count increase above), and with sufficient pressure it terminates the
game. The patched version handles the same scenario without issue because each
zombie receives exactly one `flame_damage_fx` call regardless of how many shots are
fired.

---

## Patched Fire Staff Playstyle: CC Combo

Testing the patched staff in-game surfaced a detail that the damage numbers alone miss:
the Fire Staff has twelve ammo slots — enough for two full charged bursts before
reloading. Combined with the burn effect's crowd control, a specific playstyle emerges
that the weapon was clearly designed around.

The burn DOT slows and staggers zombies in the AoE. Below round 44, a charged burst
clears a horde outright. Above round 44, the burst no longer kills — but it does
suppress. Firing two consecutive charged shots into a tight group from a corner produces
a dense burn zone that slows incoming zombies to a crawl, allowing the player to hold
position safely while the DOT ticks down.

This CC loop is effective as a support tool alongside Ice and Wind:

A key mechanical distinction: Ice and Wind each provide a single charged shot per clip.
The Fire Staff's twelve ammo slots provide two full charged bursts per clip. This is
not incidental — it is the weapon's damage model. Past round 44, where a single burst
no longer kills in one hit, the ammo economy allows the player to cycle both bursts
into a group. Combined with the burn CC stagger slowing incoming zombies, this produces
a sustained suppression loop that the single-shot scalers are not designed to replicate.

- **Early game (R1–R44):** each charged burst one-shots. Primary damage weapon, clears
  hordes faster than Ice or Wind due to AoE spread and double burst per clip.
- **Mid game (R44–R70 approx.):** single bursts no longer kill outright, but two bursts
  plus CC stagger can still work through a horde. Functional area-denial with sustained
  output — viable in a corner hold against mid-round densities.
- **Late game (R70+):** burst damage falls too far behind zombie HP for multi-hit kills
  to be time-efficient. CC utility remains but put down as a primary damage tool.
  Switch to Ice/Wind for kill output.

This is not a degenerate playstyle created by the fix — it is the playstyle the weapon
was built for. Twelve ammo slots make no sense for a one-shot-or-nothing design. They
make complete sense for a weapon intended to cycle burst pairs over multiple rounds of
sustained suppression. Ice and Wind's one-shot-per-clip design reflects their role as
instant scalers. Fire's two-shot-per-clip design reflects its role as a sustained
burst CC tool. The SA-10 bug was not giving the Fire Staff a role — it was replacing
its actual role with "delete everything," which made the weapon's real design invisible
for twelve years.

The patched Fire Staff is, in practice, in line with the other staffs through early-to-
mid rounds. Its two-burst-per-clip ammo economy compensates for the fixed damage ceiling
in a way that no other staff can replicate — Ice and Wind are single-shot tools. The
Fire Staff is a sustained-cycle tool. Both approaches are functional. They are simply
designed for different positions in the rotation.

---

## Why QA Never Caught This

The most striking aspect of this gap is that it should have been easy to catch in
testing — and almost certainly would have been, if SA-10 had not existed.

Round 40–50 is a standard high-round QA milestone. It is the point where upgraded
weapons start to show their limitations, and it is exactly the range where the patched
Fire Staff loses its one-shot capability (R41→R44 in our measurements). Any tester
reaching round 40 with an unpatched staff would see it still clearing hordes with a
single charged shot, because SA-10 was delivering 500,000 damage per zombie. The
staff appeared to behave correctly because, from an observable standpoint, it was: it
was killing everything quickly. The broken dedup guard was doing the killing, not the
weapon design.

A QA tester in 2013 had no reason to check the thread count on a weapon that appeared
to work. The damage looked right. The weapon felt powerful. The game shipped.

This is what makes it an oversight rather than an intentional choice. The four staves
are presented as equivalent high-value weapons — same crafting effort, same upgrade
path, all four required for the Easter Egg. There is no in-game signal that the Fire
Staff is intentionally weaker at high rounds. No easier crafting requirement, no
tooltip, no narrative framing. All four staves are balanced as equals.

At the code level they are not symmetric. Water and Wind have unconditional `self.health`
kill paths that work at any round. Lightning has a conditional `self.health` path that
degrades around round 40. Fire has a conditional `self.health` path behind a coin flip
that also fails above round 30 — and unlike Lightning, has no partial-damage fallback
worth mentioning at high-round HP values.

The most plausible reading is that the Fire Staff's charged shot was intended to have
a proper high-round kill path — similar to Water (`always_kill = 1`) or Wind
(`do_damage(self.health)`) — and it was either left incomplete or introduced after the
point where SA-10 was already present and masking the gap during testing.

---

## What a Corrective Fix Would Look Like

The Water Staff's blizzard kill path is the reference: the charged projectile's area
handler always passes `always_kill = 1`, which routes through `do_damage(self.health)`.
An equivalent fix for the Fire Staff would change the charged AoE handler to use
`self.health` damage for zombies inside the blast radius, matching the design intent
visible in the other three staves:

```gsc
// Proposed correction to fire_staff_area_of_effect() for charged shots:
foreach ( e_target in a_targets )
{
    if ( isdefined( e_target ) && isalive( e_target ) )
    {
        if ( !is_true( e_target.is_on_fire ) )
        {
            if ( str_weapon == "staff_fire_upgraded3_zm" )
                e_target thread flame_damage_fx_always_kill( str_weapon, e_attacker );
            else
                e_target thread flame_damage_fx( str_weapon, e_attacker );
        }
        else if ( isdefined( level._hrp_sa10_diag ) )
            level._hrp_sa10_blocked++;
    }
}

// New variant mirroring water staff's kill mechanic:
flame_damage_fx_always_kill( damageweapon, e_attacker )
{
    self endon( "death" );
    if ( !is_true( self.is_on_fire ) )
    {
        self.is_on_fire = 1;
        self thread zombie_set_and_restore_flame_state();
    }
    // Route through self.health like water/wind:
    self do_damage_network_safe( e_attacker, self.health, damageweapon, "MOD_BURNED" );
    self thread zombie_gib_guts();
}
```

This fix is **not included in the current patch**. It changes game balance, not crash
behaviour. The crash patch restores the Fire Staff to its as-coded state (fixed damage,
degrades above round 30). Whether to also correct the apparent balance gap is a
separate decision.

---

## Summary

SA-10 was a thread-leak bug that was simultaneously a damage bug. Fixing the thread
leak exposed the underlying damage shortfall. The Fire Staff without SA-10 is a
different weapon to what Origins players have experienced since 2013: a burst CC weapon
with a genuine mid-game window (R1–R44 primary damage, R44–R70 area suppression),
not the round-scaling killer the bug was simulating.

Critically, the patched weapon is not dead weight. Its twelve ammo slots, sustained
burn DOT, and crowd-control stagger produce a viable CC playstyle that complements
Ice and Wind in a way the bugged version never could — the bugged version simply
deleted everything, which made its actual toolkit invisible. The fix makes the weapon's
design legible for the first time.

The other three staves are unaffected: Wind and Water always killed regardless of round
number via `self.health` paths; Lightning degraded early for the same structural reason
as Fire but was never propped up by an equivalent compounding bug.

*Revisiting the balance fix is tracked. All scripts and source at
[github.com/banq/t6-high-round-fix](#).*
