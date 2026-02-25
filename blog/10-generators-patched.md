# Origins Generators: Three More Bugs Behind the Highest-Pressure Map

*Part 10 of the BO2 High-Round Crash Fix series.
[Part 1](01-the-archaeology.md) | [Part 2](02-the-diagnostic-tools.md) | [Part 3](03-entity-leaks.md) | [Part 4](04-the-patch.md) | [Part 5](05-results.md) | [Part 6](06-fixing-the-core.md) | [Part 7](07-origins-patched.md) | [Part 8](08-die-rise-patched.md) | [Part 9](09-the-full-patch.md) | [Part 11](11-tank-patched.md) | [Part 12](12-testing-origins-staffs.md)*

---

After fixing the Fire Staff and Wind Staff, the generator system was the remaining
Origins-specific candidate. The generators have their own spawn management, their
own persistent threads per zone, and a recapture system that triggers every 3–6
rounds after round 10 — indefinitely, for the entire session. A long Origins run
has dozens of recapture events. Any overhead that compounds per-event accumulates
into the same scrVar pool we've been fighting.

Three bugs were found.

---

## GEN-ZC-01: The Spawn Limiter That Was Never Limiting

`get_capture_zombies_needed()` serves two callers. Called without arguments, it
answers "how many total capture zombies do we need right now?" Called with
`b_per_zone = 1`, it should answer "how many per contested zone?"

The per-zone branch:

```gsc
// get_capture_zombies_needed() — original (broken):
if ( b_per_zone )
    b_capture_zombies_needed = n_capture_zombies_needed_per_zone;

return n_capture_zombies_needed;
```

`b_capture_zombies_needed` is a brand-new local variable. It's never referenced
anywhere else in the file. The variable `n_capture_zombies_needed` — the one that
`return` reads — goes completely unmodified. The function always returns the total,
regardless of which caller asked.

The fix is one variable name:

```gsc
// Fixed:
if ( b_per_zone )
    n_capture_zombies_needed = n_capture_zombies_needed_per_zone;  // GEN-ZC-01 fix
```

This is the same shape as every other bug in this project: SA-10 checked
`self.is_on_fire` instead of `e_target.is_on_fire`, MI-09 passed `a_zombies[0]`
instead of `a_zombies[i]`, MI-11 wrote `continue` instead of `break`. One wrong
name, compiles silently, fails silently.

### What the broken limiter was doing to captures

Every contested generator runs a `monitor_capture_zombies()` loop that calls
`spawn_zombie()` every 0.5 seconds until its zone's zombie count reaches
`capture_zombie_limit`. That limit comes from `set_capture_zombies_needed_per_zone()`:

```gsc
n_zombies_needed_per_zone = get_capture_zombies_needed( 1 );  // always gets total
zone.capture_zombie_limit = n_zombies_needed_per_zone;
```

With the bug, each zone is assigned the full total quota:

| Active captures | Intended limit/zone | Actual limit/zone |
|---|---|---|
| 1 zone  | 4 | 4 (same — no effect) |
| 2 zones | 3 | 6 (2×) |
| 3 zones | 2 | 6 (3×) |
| 4 zones | 2 | 8 (4×) |

Single-zone captures are unaffected — the total and per-zone values are identical
when there's only one contest. But Origins players routinely trigger two generators
simultaneously once they know the mechanics, and experienced teams will capture
three or four at once. That's exactly when the bug is most active.

`capture_event_handle_ai_limit()` correctly reserves only the total-needed slots
(6 for two zones), so the AI ceiling prevents more than 6 capture zombies from
existing at once. But both zones' loops are still calling `spawn_zombie()` every
0.5 seconds trying to reach their inflated limit of 6, even after the 6-slot budget
is exhausted. Each attempt invokes `array_removedead()` (temporary array allocation),
calls `get_emergence_hole_spawn_point()` (which has its own inner poll loop if
emergence holes aren't ready), and appends to the zone's capture zombie tracking
array. None of this work produces a zombie. All of it produces scrVar pressure.

---

## GEN-ZC-02: Player Context That Followed Zombies to the Wrong Generator

During a recapture event, zombies are sent toward a generator to tear it down. If
they succeed — or if the players repel them — they get redirected to the next
generator via `set_recapture_zombie_attack_target()`.

The redirection updates the target and resets the attack state:

```gsc
// set_recapture_zombie_attack_target() — original (broken):
foreach ( zombie in level.zone_capture.recapture_zombies )
{
    zombie.is_attacking_zone = 0;
    zombie.s_attack_generator = s_recapture_target_zone;
    zombie.attacking_new_generator = 1;
}
```

What it doesn't update: `zombie.ignore_player[]`.

Each capture zombie maintains an `ignore_player` array through
`should_capture_zombie_attack_generator()`, which runs every 0.5 seconds.
The array tracks which players are "not valid targets" — players outside the
700-unit threat radius of the current generator get added to the ignore list, and
removed when they come back in range.

The spatial layout of generator A is not the layout of generator B. Players who
were far from A may be standing right next to B. Players who were at A may now be
half the map away. When the zombie arrives at B carrying A's `ignore_player` state,
its proximity decisions are drawn from the wrong geometry until the 0.5-second poll
cycle catches up — if it catches up at all.

More persistently: the cleanup path is `arrayremovevalue( self.ignore_player, player, 0 )`
which iterates `foreach ( player in get_players() )`. Players who disconnected are
never in `get_players()`, so their entries are never removed. A player who
disconnected mid-recapture-event leaves a permanent entry in every recapture
zombie's `ignore_player` array for the rest of that zombie's life.

The fix is one line in the redirection function:

```gsc
// Fixed:
foreach ( zombie in level.zone_capture.recapture_zombies )
{
    zombie.is_attacking_zone = 0;
    zombie.s_attack_generator = s_recapture_target_zone;
    zombie.attacking_new_generator = 1;
    zombie.ignore_player = [];  // GEN-ZC-02 fix: clear stale player-proximity state
}
```

Clearing the array on redirect means every zombie starts fresh at the new
generator. The 0.5-second poll will immediately rebuild correct proximity context
for the new zone. Disconnected player entries are naturally swept away.

---

## GEN-ZC-03: The Off-by-One That Left One Attack Point Permanently Vacant

Each generator has 12 zombie attack positions, arranged in three groups of four
around the generator's structure:

- Center pillar: indices 0–3
- Left pillar: indices 4–7
- Right pillar: indices 8–11

Both functions that scan these groups use `i < n_end`:

```gsc
// Original (broken):
for ( i = n_start; i < n_end; i++ )
```

The callers pass `(0, 3)`, `(4, 7)`, `(8, 11)`, and `(0, 11)` as range endpoints.
With `i < n_end`, the final index in every range is excluded: indices 3, 7, and 11
are never returned as unclaimed, and never counted as claimed.

The fix in both functions:

```gsc
// Fixed:
for ( i = n_start; i <= n_end; i++ )  // GEN-ZC-03 fix: include the last index
```

The practical impact here is modest — index 11 (the last right-pillar attack
position) was the only one permanently unreachable from any call path, including
the `(0, 11)` full-range fallback. With up to 6 recapture zombies competing for
positions, 11 usable slots out of 12 was always sufficient. But the symmetry was
broken: the right pillar effectively had 3 usable positions while the others had 4,
and any assert-based crash if every slot were simultaneously claimed would have
triggered at 12 claims rather than 11 — in practice impossible, but wrong.

---

## The Pattern Across Origins

All three Origins-specific findings follow the same theme. The map was built with
significantly more system complexity than any other BO2 zombies map — three Giant
Robots with their own threading, six generators each running multiple monitoring
loops, a recapture system that cycles every few rounds, four buildable staves with
unique upgrade mechanics. Each of these systems had at least one variable-name typo,
a forgotten cleanup, or a loop boundary that was slightly wrong.

None of them crashed the game immediately. All of them added pressure to the same
shared resource pools that eventually terminate the session.

The full picture for Origins:

| Finding | Effect |
|---|---|
| SA-10 (Fire Staff) | Thread flood during AoE — O(zombies × ticks) redundant threads |
| MI-06 (Wind Staff) | Wrong zombie source — invisible zombie, possible soft-lock |
| GEN-ZC-01 (generator spawn limiter) | 2–4× excess spawn attempts per contested zone, every 0.5s |
| GEN-ZC-02 (player context) | Stale scrVar entries per recapture zombie, each redirect event |
| GEN-ZC-03 (attack point range) | One unused slot per generator — minor asymmetry |

With all five fixed, Origins' only remaining pressure source is the baseline entity
accumulation rate that applies to every map — modulated by its above-average
persistent overhead (three robots, six generators, larger map geometry).

---

## Deploying the Generator Fixes

Same `mod.ff`, same deployment step:

```bash
./build_ff.sh
```

The generator fixes live in `zm_tomb_capture_zones.gsc`. Like the staff weapon
fixes, they only activate when `zm_tomb.ff` is loaded — dormant on every other map.

*Source and test data at [github.com/banq/t6-high-round-fix](#).*
