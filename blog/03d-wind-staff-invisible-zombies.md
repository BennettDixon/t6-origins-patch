# Why the Wind Staff Breaks at High Rounds (and Why It Creates Invisible Zombies)

*A companion to Part 3 — How BO2 Zombies Slowly Runs Out of World*

---

Origins players have a consensus about the Wind Staff: don't use it at high rounds. It stops killing, and when it does interact with zombies, some of them become invisible — still alive, still attacking, but gone from the screen. A ghost that can damage you.

Both observations are real. Both have specific code causes. One is a loop indexing bug with the same shape as a bug we've already documented in the base game. The other is an unlink-ordering error that puts zombie entities in an inconsistent state between their rendered position and their server-side physics.

---

## What the Wind Staff Actually Does

The Wind Staff has two entirely different attack modes depending on upgrade tier, and they work on completely different principles.

### Base and tier-1: a damage beam

`staff_air_zm` and `staff_air_upgraded_zm` fire a wind beam that hits zombies in a forward cone. The damage is hardcoded:

```gsc
// wind_damage_cone() — _zm_weap_staff_air.gsc:473-503
if ( str_weapon == "staff_air_upgraded_zm" )
    n_damage = 3300;
else
    n_damage = 2050;

target do_damage_network_safe( self, n_damage, str_weapon, "MOD_IMPACT" );
```

Fixed. Non-scaling. Round 1 through round 255 — 3300 damage. At round 50, zombie health is around 50,000. At round 100 it's in the hundreds of thousands. The beam is cosmetic at that point. This is a design limitation, not a bug.

### Tier-2 and tier-3: the whirlwind

`staff_air_upgraded2_zm` and `staff_air_upgraded3_zm` work completely differently. Instead of a damage beam, you fire a physical projectile. On impact, the whirlwind system kicks in through a five-step sequence:

**Step 1 — Find a source zombie.**
`staff_air_find_source` looks for the nearest zombie to the explosion point and designates it the "source zombie." The whirlwind forms at the source zombie's location, centred on it. If no zombie is close enough, the whirlwind forms at the explosion point itself.

**Step 2 — Spawn the whirlwind entity.**
`staff_air_position_source` spawns a `script_model` entity at the source zombie's position and sets up the whirlwind FX, sounds, and a timeout timer. Duration is `chargeshotlevel × 3.5` seconds — so 3.5, 7, or 10.5 seconds at charge levels 1, 2, and 3 respectively. Only one whirlwind can be active at a time.

**Step 3 — Physically drag zombies in.**
`whirlwind_kill_zombies` loops while the whirlwind is active, scanning for zombies within range. For each one it finds, it calls `whirlwind_drag_zombie`, which calls `whirlwind_move_zombie`. Here's what that actually does: it spawns a small invisible `script_origin` entity — the "linker" — at the zombie's feet, locks the zombie to it via `linkto`, and then moves the linker across the ground toward the whirlwind center. The zombie follows because it's physically attached to the linker. The zombie also plays a special pulled-toward-the-center animation (`zm_move_whirlwind` or the fast variant) while being dragged.

**Step 4 — Kill zombies that reach the center.**
Once the linker gets within 30 units of the whirlwind center (the `n_fling_range_sq = 900` threshold), the loop exits, the linker is deleted, and `whirlwind_drag_zombie` deals `self.health` damage to the zombie — a guaranteed one-shot kill regardless of round. This is why the whirlwind is supposed to stay effective at high rounds: it doesn't care what the zombie's health is.

**Step 5 — Chain-kill from the source zombie.**
When the source zombie dies — whether dragged to the center or killed by other means — `source_zombie_death` triggers. This calls `staff_air_fling_zombie` on all zombies within blast range of the source's position. Each one either gets ragdolled and killed (`zombie_launch`) or takes `self.health` damage directly. This is the burst-kill that clears the crowd in a single shot when the whirlwind works correctly.

So the intended flow for a tier-3 charged shot is: explosion → whirlwind forms on nearest zombie → whirlwind drags 5–10 zombies into the center over 10 seconds → each one is one-shotted on arrival → source zombie's death also kills everything in the immediate blast radius. The kill mechanism scales correctly with round number because it deals `self.health` rather than a fixed value.

The question isn't "why does the Wind Staff stop doing damage." It's "why do steps 1 and 3–4 break at high rounds."

---

## The Source Zombie Bug — Step 1 Goes Wrong

Step 1 is where the first bug lives. `staff_air_find_source` finds the nearest eligible zombie and hands it to `staff_air_zombie_source` — which sets the whirlwind's anchor position and registers the chain-kill callback. Here's the function:

```gsc
staff_air_find_source( v_detonate, str_weapon )
{
    a_zombies = getaiarray( level.zombie_team );
    a_zombies = get_array_of_closest( v_detonate, a_zombies );  // sorted nearest-first

    if ( a_zombies.size )
    {
        for ( i = 0; i < a_zombies.size; i++ )
        {
            if ( isalive( a_zombies[i] ) )
            {
                if ( is_true( a_zombies[i].staff_hit ) )
                    continue;

                if ( distance2dsquared( v_detonate, a_zombies[i].origin ) <= 10000 )
                    self thread staff_air_zombie_source( a_zombies[0], str_weapon );   // ← BUG
                else
                    self thread staff_air_position_source( v_detonate, str_weapon );

                return;
            }
        }
    }
    else
        self thread staff_air_position_source( v_detonate, str_weapon );
}
```

The loop iterates over `a_zombies` — sorted by distance from the explosion — and skips zombies that are dead or already flagged `staff_hit`. When it finds a valid one at index `i`, it calls `staff_air_zombie_source( a_zombies[0], str_weapon )`.

Not `a_zombies[i]`. `a_zombies[0]`.

`a_zombies[0]` is always the **closest zombie**, regardless of whether it passed the validation checks the loop just ran. When `i == 0`, this works. When `i > 0` — meaning the closest zombie was dead or flagged — the function finds a valid zombie at index `i` and immediately ignores it, passing `a_zombies[0]` instead.

**What `staff_air_zombie_source` does with the wrong zombie:**

```gsc
staff_air_zombie_source( ai_zombie, str_weapon )
{
    ai_zombie.staff_hit = 1;
    ai_zombie.is_source = 1;
    v_whirlwind_pos = ai_zombie.origin;            // whirlwind positioned here
    self thread staff_air_position_source( v_whirlwind_pos, str_weapon );

    if ( !isdefined( ai_zombie.is_mechz ) )
        self thread source_zombie_death( ai_zombie );  // chain-kill threaded on this zombie
}
```

If `ai_zombie` (i.e. `a_zombies[0]`) is dead:
- `v_whirlwind_pos = ai_zombie.origin` — whirlwind forms at the dead zombie's last position, not the explosion point. Off by however far the corpse has drifted.
- `source_zombie_death(ai_zombie)` runs on a dead zombie. Inside, `staff_air_fling_zombie` exits immediately: `if (!isalive(self)) return`. The chain-kill burst fires nobody. The whirlwind's central attraction-and-kill mechanic misfires entirely.

If `ai_zombie` is already `staff_hit` (previously a source, which is why the loop skipped it):
- `is_source` and `staff_hit` flags are set redundantly on the wrong zombie
- `source_zombie_death` may fire on a zombie that's still alive but was already processed — potentially triggering a duplicate chain-kill

**At high rounds this is the common case, not an edge case.** Zombie mortality is high. Between when `getaiarray` captures the sorted list and when the loop runs, `a_zombies[0]` frequently dies. The loop finds a valid replacement at `i = 1` or later, but the function has already committed to `a_zombies[0]`. The whirlwind misfires on most shots.

The fix is one character: `a_zombies[i]`.

Compare with IL-01 (`has_attachment` infinite loop) — that was also a loop indexing defect in zombie-targeting code. The pattern is the same: a loop that finds the right element at index `i` but uses a hardcoded index to act on it.

---

## The Invisible Zombie Bug — Step 3 Leaves Zombies Stranded

Recall how step 3 actually moves zombies: a small invisible `script_origin` linker entity is spawned at the zombie's feet, the zombie is locked to it via `linkto`, and the linker is driven toward the whirlwind center. The zombie follows because it's physically attached. Here's that code:

```gsc
whirlwind_move_zombie( e_whirlwind )
{
    self.e_linker = spawn( "script_origin", ( 0, 0, 0 ) );
    self.e_linker.origin = self.origin;
    self.e_linker.angles = self.angles;
    self linkto( self.e_linker );              // zombie's world transform now follows linker
    self thread whirlwind_unlink( e_whirlwind );

    // ... movement loop, zombie pulled toward whirlwind ...

    self notify( "reached_whirlwind" );
    self.e_linker delete();                    // linker deleted — zombie still linked
}
```

And the unlink function:

```gsc
whirlwind_unlink( e_whirlwind )
{
    self endon( "death" );
    e_whirlwind waittill( "death" );           // waits for the WHIRLWIND entity to die
    self unlink();
}
```

After the movement loop, the linker is deleted. But `unlink()` is deferred to when the **whirlwind entity** dies — not the linker. The whirlwind entity doesn't die until `whirlwind_timeout` runs its course:

```gsc
whirlwind_timeout( n_time )
{
    self endon( "death" );
    level waittill_any_or_timeout( n_time, "whirlwind_stopped" );
    level notify( "whirlwind_stopped" );
    flag_clear( "whirlwind_active" );
    wait 1.5;       // 1.5 second delay
    self delete();  // whirlwind entity dies here → triggers whirlwind_unlink
}
```

Between `self.e_linker delete()` and `self unlink()` is a window of up to 1.5 seconds where the zombie is linked to a deleted entity.

**What the engine does with a link to a deleted entity:**

In T6, a zombie's rendered world position is derived from its link parent's transform. When the parent is deleted before `unlink()` is called, the rendering system either reads a stale/null transform (freezing the zombie at the linker's last position) or loses the reference entirely (the zombie disappears from rendering). The zombie's **server-side state** — AI, physics, hitbox, damage processing — continues normally, driven by the entity's own position data.

The result: the zombie is alive, can move, and can deal damage to players. Its visual representation is either frozen in place somewhere or gone entirely. The player is hit by something invisible.

**This only happens to zombies that survive the whirlwind.** A zombie that reaches the center is killed immediately:

```gsc
whirlwind_drag_zombie( e_whirlwind, str_weapon )
{
    self whirlwind_move_zombie( e_whirlwind );

    if ( isdefined( self ) && isdefined( e_whirlwind ) && flag( "whirlwind_active" ) )
    {
        self do_damage_network_safe( player, self.health, str_weapon, "MOD_IMPACT" );  // killed
        // ...
    }
    // if whirlwind_active is false at this point: zombie NOT killed, orphaned state begins
}
```

The kill only fires if `flag("whirlwind_active")` is still true when `whirlwind_drag_zombie` resumes after `whirlwind_move_zombie` completes. If the whirlwind times out **while a zombie is being dragged** — which is more likely at high rounds where the whirlwind's 10.5-second duration may not be enough to pull in a large horde — the kill block is skipped, the zombie survives, and it's in the orphaned state.

**The fix is one line:** add `self unlink()` immediately before `self.e_linker delete()`. `whirlwind_unlink` calling `unlink()` on an already-unlinked zombie is harmless. The deferred call becomes a no-op. The 1.5-second orphaned window disappears.

---

## Both Bugs Share a Root Cause

Neither of these bugs happens in isolation. They reinforce each other:

1. The wrong-zombie bug (MI-09) means the whirlwind frequently misfires at high rounds — it positions itself at dead zombie locations and the chain-kill burst doesn't fire. The whirlwind takes longer to kill zombies because its initial fling-and-kill sequence is broken.

2. Because the whirlwind takes longer to kill zombies, more zombies are still mid-drag when the 10.5-second duration expires. Those zombies survive, enter the orphaned-link state, and become invisible.

The second bug is downstream of the first. If MI-09 were fixed, the whirlwind would kill zombies faster and fewer would survive to encounter the MI-10 window.

---

## Fix Feasibility

Both functions are compiled into `zm_tomb.ff`. The same FF replacement constraint that applies to IL-01 (`has_attachment`) and SA-10 (Fire Staff AoE) applies here. Neither can be patched from an addon script.

| Bug | File | Fix | Patchable from addon? |
|---|---|---|---|
| MI-09 (`a_zombies[0]` wrong index) | `_zm_weap_staff_air.gsc:104` | Change `a_zombies[0]` to `a_zombies[i]` | No — `zm_tomb.ff` |
| MI-10 (orphaned link before unlink) | `_zm_weap_staff_air.gsc:303-304` | Add `self unlink()` before `self.e_linker delete()` | No — `zm_tomb.ff` |

The Wind Staff's degradation at high rounds is partially design (fixed damage values that don't scale) and partially bugs (wrong source zombie, orphaned links). The design limitations exist in the base game and don't require touching `zm_tomb.ff`. The bugs could be one-line fixes if the zone file were recompiled.

This is consistent with the pattern across Origins: the Fire Staff AoE bug (SA-10) was also one character away from being correct (`self.is_on_fire` → `e_target.is_on_fire`), also in `zm_tomb.ff`, also unfixable from addon. For Origins specifically, the DLC zone file is where the interesting bugs live — and the distribution constraint is the same for all of them.

---

The invisible zombie observation has been reported by Origins high-round players for over a decade. The community explanation has always been vague — "it's a glitch with the Wind Staff." The actual mechanism is a 1.5-second window created by the order of two operations: `delete()` and `unlink()`. The wrong order. One line apart. Invisible to the player, but obvious in the source.

> **Update:** The wrong-index bug (`a_zombies[0]` → `a_zombies[i]`, labeled MI-06
> in the patch) was subsequently fixed via FF replacement — see [Part 7](07-origins-patched.md).
> The orphaned-link ordering bug (MI-10) was confirmed but remains in the base game;
> the index fix substantially reduces the frequency of the invisible zombie state by
> ensuring the whirlwind targets the correct zombie in the first place.

*All scripts and test data are at [github.com/banq/t6-high-round-fix](#).*
