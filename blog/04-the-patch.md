# The Patch: Fixing What Can Be Fixed, Documenting What Can't

*Part 4 of the BO2 High-Round Crash Fix series. [Part 1](01-the-archaeology.md) | [Part 2](02-the-diagnostic-tools.md) | [Part 3 — Entity Leaks](03-entity-leaks.md)*

---

After three posts of methodology, instrumentation, and finding bugs, this is the one with
the code. Six confirmed fixes. Two things that can't be fixed from addon scripts. And one
function containing a bug that is, depending on how you look at it, either the most
catastrophic single missing character in BO2 history or barely a problem in practice.

---

## The Architecture of What's Fixable

Plutonium T6's addon script system allows you to attach new behavior to game events,
override function pointers stored on `level.`, and write watchdogs that monitor and clamp
values. What it does not allow is replacing functions that base game scripts call through
hardcoded compile-time references.

This splits the 25 issues we found into two groups:

**Fixable from addon scripts:**
- EL-02/03 (anchor leaks) — stored on `self`, accessible via death watchdog
- OF-01/02/03 (health/score/drop increment overflows) — level variable clamping
- SA-08/09 (weapon array accumulation) — plain player entity fields, writable at round start

**Requires FF file replacement:**
- EL-01 (`lerp()` link) — function-local variable, inaccessible from outside
- IL-01 (`has_attachment()` infinite loop) — base game calls are compile-time linked
- IL-02 (`random_attachment()` infinite loop) — same

All six fixable issues are shipped in the combined patch. Both FF replacement issues have
working fixes in the repo source that require a modified `.ff` archive to distribute.

---

## Fix 1: Entity Leak Watchdog (EL-02/03)

The watch code is absurdly simple. Thread it on every zombie at spawn via
`level._zombie_custom_spawn_logic`. Wait for death. Delete the anchor if still there.

```gsc
hrp_anchor_watchdog()
{
    self waittill("death");

    if (isdefined(self.anchor))
    {
        self.anchor delete();
        self.anchor = undefined;
        level._hrp_anchors_freed++;
    }

    // EL-01: populated only when _zm_utility.gsc FF replacement is active.
    // Without FF replacement this is always undefined — safe no-op.
    if (isdefined(self._lerp_link))
    {
        self._lerp_link delete();
        self._lerp_link = undefined;
        level._hrp_lerp_freed++;
    }
}
```

Eight lines that eliminate anchor leaks entirely. Validated with `elpsynth` A/B: ELP
off → 4 anchors permanently leaked. ELP on → 6/6 freed, zero leaked.

The second block (`self._lerp_link`) is the EL-01 fix that only activates when the
FF-replaced `_zm_utility.gsc` is also installed. If it isn't, `self._lerp_link` is never
set by the base game, `isdefined()` returns false, and the check costs one comparison per
zombie death — effectively free.

---

## Fix 2: Zombie Health (OF-01 — No Fix Applied)

The zombie health formula scales exponentially starting at round 10. At high rounds
(~R163 in BO1, ~R223 in BO2) the accumulated value overflows int32 and wraps negative.
Zombies then spawn with health ≤ 0 and die from any damage — a bullet, fire, anything.
This is the insta-kill round: the overflow is the mechanic, not a bug to suppress.

Health continues to oscillate through the int32 range as the formula keeps running on
the wrapped value, producing insta-kill rounds at irregular intervals. This is accepted
high-round community behavior — no health clamping is applied by the patch.

---

## Fix 3: Score Total Cap (OF-02)

`player.score_total` is a signed int32. When it exceeds 2,147,483,647 it wraps to a large
negative number. The powerup drop condition — `curr_total_score > score_to_drop` — becomes
permanently false. No more drops for the rest of the session.

Cap at 999,999,999:

```gsc
if (p.score_total > level._hrp_score_cap || p.score_total < 0)
    p.score_total = level._hrp_score_cap;
```

At 999M, earned points no longer advance the stored total, but the drop distance
calculation (`score_to_drop = current + drop_increment`) is still based on the capped
value. Drops continue firing at the expected rate.

Practical note: reaching 999M in actual gameplay requires extraordinary box cycling over
dozens of hours. This is not a theoretical fix for an imaginary edge case — it's the
exact crash mode for any serious marathon session with active powerup farming.

---

## Fix 4: Drop Increment Cap (OF-03)

`zombie_powerup_drop_increment` starts at 2,000 and multiplies by 1.14 after each
powerup collected. Left uncapped:

```
Drop 1:    2,000
Drop 10:   7,000
Drop 50:   530,000
Drop 100:  2,800,000
Drop 200:  ~3.7 trillion
```

At ~100 drops, the value exceeds float32 precision limits. The comparison
`curr_total_score > score_to_drop` evaluates using the broken value and becomes
permanently false — drops stop, silently, with no error.

Cap at 50,000. The watchdog runs every 1 second and clamps if exceeded:

```gsc
di = level.zombie_vars["zombie_powerup_drop_increment"];
if (di > level._hrp_drop_inc_cap)
    level.zombie_vars["zombie_powerup_drop_increment"] = level._hrp_drop_inc_cap;
```

50,000 points between drops is achievable in 3–4 rounds of normal play at high rounds.
Drops remain functional, remain rare enough to feel meaningful, and the increment never
breaks the comparison.

---

## Fix 5: hitsthismag Pruning (SA-08)

`watchweaponchangezm()` threads once per player and runs for the entire session. Every
unique weapon string the player switches to gets a permanent entry in `self.hitsthismag`:

```gsc
self.hitsthismag[newweapon] = weaponclipsize(newweapon);  // never freed
```

BO2 weapon strings encode all attachments: `"an94_zm"`, `"an94_zm+reflex"`,
`"an94_zm+reflex+grip"`, and their PaP variants are four distinct keys. 50+ box rolls
in a long session generates 40–80 keys per player. Four players = 160–320 permanently
occupied child scrVar slots.

Fix: at each round start, rebuild the array keeping only entries for weapons the player
currently carries. Stale entries (traded, dropped, or box-replaced weapons) are freed.

```gsc
current_weapons = self getweaponslist();
keep = [];
for (i = 0; i < current_weapons.size; i++)
{
    w = current_weapons[i];
    if (isdefined(self.hitsthismag[w]))
        keep[w] = self.hitsthismag[w];
}
self.hitsthismag = keep;
```

The base code at `_zm_weapons.gsc:398-412` re-initialises missing entries on weapon
switch. There's no data loss from pruning — only the values for currently-held weapons
matter, and those are preserved.

Validated: inflated a player's `hitsthismag` to 101 entries via the `weap` stress test
command, advanced one round, confirmed 100 stale entries pruned down to 1.

---

## Fix 6: PaP Options Cache Clear (SA-09)

`get_pack_a_punch_weapon_options()` caches visual customization (camo, scope, reticle)
per unique upgraded weapon name. Never cleared. Every unique PaP'd weapon is a new
permanent child scrVar entry.

Fix: clear the array entirely at round start. The function re-initialises it lazily:

```gsc
if (isdefined(self.pack_a_punch_weapon_options))
    self.pack_a_punch_weapon_options = undefined;
```

The only observable side effect: Pack-a-Punch weapon cosmetics re-randomise once per
round. Purely aesthetic.

---

## The Thing We Eventually Fixed: `has_attachment()`

*Update: this section originally ended with "the distribution mechanism doesn't exist."
It now does. The full story is in [Part 4b](04b-patching-the-fastfile.md). The
summary is below.*

`has_attachment()` is a function in `_zm_weapons.gsc` that checks whether a compound
weapon name string (like `"an94_zm+reflex+grip"`) includes a given attachment. It parses
the `+`-delimited tokens and loops through them.

```gsc
// The shipped version (broken):
has_attachment( weaponname, att )
{
    split = strtok( weaponname, "+" );
    idx = 1;

    while ( split.size > idx )
    {
        if ( att == split[idx] )
            return true;
        // ← idx is never incremented
        // if att != split[1], this loops forever
    }

    return false;
}
```

If you call `has_attachment("an94_zm+reflex+grip", "grip")`, the function checks index 1
(`"reflex"`), finds it doesn't match `"grip"`, and loops back. Index 1 forever. The server
freezes. The process becomes "Not Responding" within 1300ms. No recovery.

The fix is one character:

```gsc
// Fixed version:
while ( split.size > idx )
{
    if ( att == split[idx] )
        return true;
    idx++;  // ← this
}
```

This fix exists in the repo's `ZM/Core/maps/mp/zombies/_zm_weapons.gsc`. It compiles
correctly. The compiled output is in `compiled/t6/_zm_weapons.gsc`. But getting that
compiled file to override the base game calls requires replacing the function's bytecode
inside the game's `.ff` archive — the compiled fast-file bundle.

We tried three approaches to work around the FF requirement:

1. **Function shadowing** — Define `has_attachment()` in our addon script. Failed:
   Plutonium resolves function calls at compile time, namespace-scoped. Our definition
   exists in our namespace; base game scripts use their namespace. Confirmed by:
   ```
   **** Unresolved external: "has_attachment" with 2 parameters in "" at lines [,1,1] ****
   ```
   Even with a same-name definition, the engine couldn't find it without an explicit
   `#include`.

2. **Function pointer override** — Wrap `level.weaponUpgrade_func`. Failed: that pointer
   doesn't exist. The PaP upgrade system in `_zm_weapons.gsc` is entirely self-contained
   with no externally-accessible function pointers. The console confirmed:
   ```
   [LLP] weaponUpgrade_func not defined at init time
   ```

3. **Raw script placement** — Place the compiled `_zm_weapons.gsc` in the Plutonium
   scripts directory. Loads without error, but `has_attachment()` in FF-compiled code
   still calls the FF version. Our compiled script is added to the namespace alongside
   the FF version, not replacing it.

All three failed. The fix works. Getting it deployed required a separate investigation
into BO2's FF toolchain — see [Part 4b](04b-patching-the-fastfile.md) for the full
story.

**Short version:** BO2 has no official mod tools. The community-built
[OpenAssetTools](https://github.com/Laupetin/OpenAssetTools) has its own T6 GSC
compiler built in. Pass source `.gsc` files to its Linker, and it produces
format-compatible T6 bytecode. Deploy the resulting `mod.ff` to Plutonium's
`mods/zm_hrp/` folder. One command — `./build_ff.sh` — does the whole thing.

**Verified:** `set fftest_cmd il01` → `[FFTEST] IL-01 PASS — returned true, no freeze`

---

## The Combined Patch

All six addon-fixable issues are combined in `zm_highround_patch.gsc`. Single file,
single `init()`, dvar toggles:

```
hrp_entity_leaks   1/0   EL-02/03 anchor watchdog    [default: 1]
hrp_overflow       1/0   OF-01/02/03 clamps          [default: 1]
hrp_scrvar         1/0   SA-08/09 pruning            [default: 1]
hrp_hud            1/0   Status indicator            [default: 0]
hrp_score_cap      N     Score ceiling (OF-02)       [default: 999999999]
hrp_drop_inc_cap   N     Drop increment ceiling      [default: 50000]
```

The HUD shows a one-line status in the top-left corner:

```
HRP v1.0 R34 | EL14 | OF000 | SV200
```

Where `EL14` is cumulative anchors freed, `OF000` is three digits showing whether each
overflow cap has fired (0 = not yet, 1 = has fired), and `SV200` is cumulative stale
scrVar entries pruned.

Compile and install:

```bash
bash build.sh
bash deploy.sh   # or deploy.ps1 on Windows
```

Compiled scripts land in `%LOCALAPPDATA%\Plutonium\storage\t6\scripts\zm\`. Reload with
`map_restart` in the Plutonium console.

---

## Next

Part 5 covers what changes after the patch. Entity accumulation rates before and after.
Why Origins crashes at 26 hours and Buried at 120 hours. What it means that those limits
are clock-time limits, not round limits. And the revised ceiling for a fully-patched game.

*All scripts, test data, and raw logs are at [github.com/banq/t6-high-round-fix](#).*
