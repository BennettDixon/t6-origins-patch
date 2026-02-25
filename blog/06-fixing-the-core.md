# Phase Two: Opening the Compiled Layer

*Part 6 of the BO2 High-Round Crash Fix series.
[Part 1](01-the-archaeology.md) | [Part 2](02-the-diagnostic-tools.md) | [Part 3](03-entity-leaks.md) | [Part 4](04-the-patch.md) | [Part 5](05-results.md)*

---

Part 4 organized every bug we found into two columns. The left column was the addon
patch — six fixes, shipped, verified, documented. The right column was a list of
bugs with the same note repeated after each one: "Cannot patch from addon —
compiled into `[x].ff`."

That column isn't a to-do list anymore.

---

## The Wall

To understand why those bugs were stuck, a quick recap of how BO2's script system
works.

When Treyarch compiled BO2, they resolved every cross-script function call at compile
time. The bytecode for `_zm.gsc` contains a direct reference to `_zm_weapons::init`
baked in as a (script hash, function hash) pair. When the engine loads the game,
it links these references against whatever version of `_zm_weapons` it finds. If the
function isn't there, the link fails. If the format of the compiled bytecode is wrong,
the link fails.

This meant our addon scripts — which run in a separate namespace with a different
script hash — could never intercept base game cross-script calls. We could hook
function *pointers* stored on `level.`, we could watch variables and clamp them, we
could thread on events. But we could not replace a function that other compiled code
called directly.

The list of bugs on the wrong side of that wall was long:

| Bug | File | Zone FF |
|---|---|---|
| IL-01: `has_attachment()` infinite loop | `_zm_weapons.gsc` | `patch_zm.ff` |
| IL-02: `random_attachment()` infinite loop | `_zm_weapons.gsc` | `patch_zm.ff` |
| EL-01: `lerp()` entity leak | `_zm_utility.gsc` | `patch_zm.ff` |
| SA-10: Fire Staff AoE wrong target variable | `_zm_weap_staff_fire.gsc` | `zm_tomb.ff` |
| MI-06: Wind Staff stale source reference | `_zm_weap_staff_air.gsc` | `zm_tomb.ff` |
| GEN-ZC-01: Generator per-zone spawn limit never applied | `zm_tomb_capture_zones.gsc` | `zm_tomb.ff` |
| GEN-ZC-02: Capture zombie player context not reset on redirect | `zm_tomb_capture_zones.gsc` | `zm_tomb.ff` |
| GEN-ZC-03: Attack point range off-by-one | `zm_tomb_capture_zones.gsc` | `zm_tomb.ff` |
| MI-11: Die Rise elevator `continue` → `break` | `zm_highrise_elevators.gsc` | `zm_highrise.ff` |
| MI-12: Die Rise `shouldsuppressgibs` polling | `zm_highrise_elevators.gsc` | `zm_highrise.ff` |

Every one of these was confirmed, analyzed, and fixed in source. The fix for IL-01
was literally one character. The compiled versions of the fixed files have sat in
this repo since the initial analysis. What we didn't have was a way to get those
compiled files into the game.

---

## The Unlock

The full story is in [Part 4b](04b-patching-the-fastfile.md). The short version:
[OpenAssetTools](https://github.com/Laupetin/OpenAssetTools) — a community-built
BO2 asset tool — has its own T6 GSC compiler. You give it source `.gsc` files, it
outputs format-compatible compiled bytecode inside a `.ff` archive. Deploy that
archive to Plutonium's `mods/` folder, and the engine loads your compiled functions
in place of the originals.

The pattern is the same as Plutonium's addon script system, except it reaches all
the way down into the compiled layer. Instead of attaching new behavior to hooks, you
replace the actual functions. Every call from every other script — base game included
— goes to your version.

That changes what's possible.

---

## What's Now Deployed

`mod.ff` contains patched versions of both files from `patch_zm.ff`:

**`_zm_weapons.gsc`** — two fixes:

```gsc
// IL-01: was missing entirely, causing an infinite spin whenever
// att didn't match the first attachment token
while ( split.size > idx )
{
    if ( att == split[idx] )
        return true;
    idx++;
}

// IL-02: was while(true) with no exit if all attachments == exclude
tries = 0;
while ( tries < 30 )
{
    idx = randomint( attachments.size - lo ) + lo;
    if ( !isdefined( exclude ) || attachments[idx] != exclude )
        return attachments[idx];
    tries++;
}
```

**`_zm_utility.gsc`** — one fix:

```gsc
// EL-01: lerp() spawns a script_origin linked to a zombie and threads
// a waittill_multiple() on it. If the zombie is force-killed mid-lerp,
// the thread terminates but the link entity is never cleaned up.
// Fix: expose the link as self._lerp_link so the death watchdog can delete it.
lerp( link, start, end, time, ... )
{
    self._lerp_link = link;    // EL-01 fix: expose for death watchdog cleanup
    self waittill_multiple( "death", "lerp_stop" );
    self._lerp_link = undefined;
    link delete();
}
```

IL-01 is verified: `set fftest_cmd il01` → `[FFTEST] IL-01 PASS — returned true, no freeze`.
IL-02 and EL-01 are deployed and pending dedicated tests.

---

## The Next Targets

The `patch_zm.ff` bugs are done. The remaining items on the wall are in two other
zone files.

### `zm_tomb.ff` — Origins

Origins is the map that drove this whole investigation. Its 26-hour wall isn't just
entity leaks — it's entity leaks compounded by two weapons that generate unusual
entity pressure on top of them.

**SA-10: Fire Staff AoE wrong target variable.** When the upgraded Fire Staff hits a
group of zombies, it runs a thread-per-zombie to apply the burn effect:

```gsc
// _zm_weap_staff_fire.gsc — the broken version:
fire_staff_area_of_effect( ... )
{
    for ( i = 0; i < zombie_array.size; i++ )
    {
        e_target = zombie_array[i];
        e_target thread fire_staff_target_burn();
    }
}

fire_staff_target_burn()
{
    // Bug: checks e_target.is_on_fire — a local variable from
    // the calling scope that no longer exists here.
    // Should be: self.is_on_fire
    while ( e_target.is_on_fire )  // ← undefined, evaluates false immediately
        wait 0.1;
}
```

The `while` condition references `e_target` from the parent scope. Inside the thread,
`e_target` is out of scope — it evaluates as undefined, and the loop exits immediately
on the first check. This means every Fire Staff AoE burst spawns N threads that each
run one iteration and exit, but any ongoing burn state tracking is broken. At high
round counts with frequent AoE hits, this generates sustained thread pressure that the
SA-08/09 scrVar fixes only partially offset.

The fix is one variable name: `self.is_on_fire` instead of `e_target.is_on_fire`.

**MI-06: Wind Staff stale source reference.** The upgraded Wind Staff whirlwind needs
to anchor to a zombie position. `staff_air_find_source` sets a source zombie as the
whirlwind's origin. But the reference can become stale — the zombie dies, the entity
is recycled, and the whirlwind is now attached to a different entity that happens to
occupy the same slot. This produces the "invisible zombie" phenomenon (a zombie
counted by the round system but with no renderable entity) and breaks the round
completion check.

Both of these are single-file fixes in `_zm_weap_staff_fire.gsc` and
`_zm_weap_staff_air.gsc`. Both ship in `zm_tomb.ff`.

Three additional bugs in `zm_tomb_capture_zones.gsc` (GEN-ZC-01/02/03) were found
later — covered in [Part 10](10-generators-patched.md).

### `zm_highrise.ff` — Die Rise

Die Rise has a separate class of crash that can trigger before entity accumulation
would normally be a problem.

**MI-11: Elevator loop `continue` instead of `break`.** `elevator_roof_watcher()`
monitors elevator state and should exit when the elevator reaches the top. A `continue`
where a `break` belongs means it re-evaluates the loop condition instead of exiting.
Under specific timing — arriving while multiple players are near the shaft — the
watcher can spin for hundreds of iterations before the condition eventually resolves.
At high rounds this can lock the GSC VM long enough to trigger a "connection
interrupted" from the server watchdog.

The fix is one keyword. The file is `zm_highrise_elevators.gsc` in `zm_highrise.ff`.

**MI-12: `shouldsuppressgibs` polling overhead.** A polling loop checks gib
suppression state every frame for every nearby entity around elevator shafts. At
high entity counts this creates O(n) per-frame work that grows with session length.
An event-driven rewrite reduces it to O(1).

Both of these go into the same `zm_hrp` mod as everything else.

---

## The Architecture

All fixes ship in a single `mod.ff`:

```
mods/
  zm_hrp/
    mod.ff  — all FF-layer overrides (patch_zm.ff + zm_tomb.ff + zm_highrise.ff)
```

`build_ff.sh` writes one zone spec, stages all patched source files, and runs a
single OAT Linker invocation. The output is one `mod.ff` containing every compiled
script override. Map-specific overrides (Origins, Die Rise) are dormant on other
maps — they only activate when their parent zone file is loaded.

---

## What This Changes for the Projections

Part 5 projected two scenarios: addon-only (+30–60% on Origins), and addon + FF
(Origins approaching Buried-class ~100h). That was based only on the `patch_zm.ff`
fixes. The `zm_tomb.ff` and `zm_highrise.ff` fixes weren't in the model.

With the Origins-specific fixes (SA-10, MI-06) on top:

- The scrVar pressure from Fire Staff AoE burst threads is eliminated, not just
  mitigated. The pool has significantly more headroom.
- The Wind Staff "invisible zombie" state that stalls round completion is removed.
  Rounds that would have soft-locked due to the stale entity reference now complete
  normally.

The revised ceiling for a fully-patched Origins is likely above the 100h projection
from Part 5, because that projection didn't model the removed thread burst pressure.
Whether that ceiling is constrained by the engine's native 8–10 hour process
stability limit or by something else in the map's scripting is what the extended
soak test will determine.

For Die Rise, MI-11 and MI-12 remove the elevator-specific crash vectors entirely.
The map becomes limited by the same entity accumulation factors as other maps, rather
than crashing early due to elevator timing bugs.

---

## Status

| Bug | Fix | Status |
|---|---|---|
| IL-01: `has_attachment()` loop | `idx++` | ✅ Deployed — `fftest_cmd il01` passes |
| IL-02: `random_attachment()` loop | Bounded retry | ✅ Deployed |
| EL-01: `lerp()` entity leak | `_lerp_link` cleanup | ✅ Deployed |
| SA-10: Fire Staff AoE variable | `self.is_on_fire` → `e_target.is_on_fire` | ✅ Deployed — see [Part 7](07-origins-patched.md) |
| MI-06: Wind Staff stale source | `a_zombies[0]` → `a_zombies[i]` | ✅ Deployed — see [Part 7](07-origins-patched.md) |
| GEN-ZC-01: Generator spawn limit | `b_capture_zombies_needed` → `n_capture_zombies_needed` | ✅ Deployed — see [Part 10](10-generators-patched.md) |
| GEN-ZC-02: Player context on redirect | Clear `ignore_player` | ✅ Deployed — see [Part 10](10-generators-patched.md) |
| GEN-ZC-03: Attack point range | `i < n_end` → `i <= n_end` | ✅ Deployed — see [Part 10](10-generators-patched.md) |
| MI-11: Die Rise elevator `continue` | `break` | ✅ Deployed — see [Part 8](08-die-rise-patched.md) |
| MI-12: Die Rise gib polling | Event-driven rewrite | ✅ Deployed — see [Part 8](08-die-rise-patched.md) |

All ten FF-layer fixes are live in the single `zm_hrp/mod.ff`. Run `./build_ff.sh`
to rebuild and redeploy.

*Source, scripts, and test data are at [github.com/banq/t6-high-round-fix](#).*
