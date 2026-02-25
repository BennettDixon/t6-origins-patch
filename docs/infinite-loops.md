# Infinite Loops

These bugs cause the game server to freeze permanently when triggered. Unlike entity leaks which degrade gradually, an infinite loop is an instant hard-lock.

---

## IL-01: `has_attachment()` missing loop increment (CRITICAL)

**File:** `_zm_weapons.gsc:1730-1742`

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

**The bug:** `idx` is never incremented inside the while loop. If `split.size > 1` (the weapon has attachments) and `split[1] != att`, the loop condition remains true forever.

**Trigger condition:** Any call to `has_attachment()` with a weapon that has at least one attachment, where the target attachment is not the first one in the `+`-delimited string. For example, checking for `"grip"` on a weapon string `"an94_zm+reflex+grip"` — `split[1]` is `"reflex"`, which doesn't match, and the loop never advances to `split[2]`.

**Impact:** Immediate server freeze. The GSC VM is single-threaded, so an infinite loop in any script halts all game logic.

**Fix:**
```gsc
has_attachment( weaponname, att )
{
    split = strtok( weaponname, "+" );
    idx = 1;

    while ( split.size > idx )
    {
        if ( att == split[idx] )
            return true;

        idx++;
    }

    return false;
}
```

**Note:** This function may be rarely called in vanilla zombies gameplay (it depends on which code paths reference it), which is why the bug can exist without being caught in normal testing. But any mod or custom script that calls it with multi-attachment weapons will trigger the freeze.

---

## IL-02: `random_attachment()` degenerate case (HIGH)

**File:** `_zm_weapons.gsc:1636-1648`

```gsc
    if ( attachments.size > minatt )
    {
        while ( true )
        {
            idx = randomint( attachments.size - lo ) + lo;

            if ( !isdefined( exclude ) || attachments[idx] != exclude )
                return attachments[idx];
        }
    }
```

**The bug:** If `attachments.size - lo == 1` (exactly one eligible attachment) and that attachment equals `exclude`, the condition `attachments[idx] != exclude` is always false. The loop generates the same `idx` every iteration and never exits.

**Trigger condition:** A weapon with limited attachment options is Pack-a-Punched, and the only available random attachment is the one being excluded. This becomes more likely with repeated Pack-a-Punch usage at high rounds.

**Impact:** Server freeze, same as IL-01.

**Fix:** Add a fallback after N attempts:
```gsc
    if ( attachments.size > minatt )
    {
        attempts = 0;

        while ( attempts < 100 )
        {
            idx = randomint( attachments.size - lo ) + lo;

            if ( !isdefined( exclude ) || attachments[idx] != exclude )
                return attachments[idx];

            attempts++;
        }

        return attachments[randomint( attachments.size - lo ) + lo];
    }
```

---

## IL-03: Failsafe zombie recycling loop (HIGH)

**File:** `_zm.gsc:3635-3698`

```gsc
round_spawn_failsafe()
{
    self endon( "death" );
    prevorigin = self.origin;

    while ( true )
    {
        wait 30;
        // ...
        if ( distancesquared( self.origin, prevorigin ) < 576 )
        {
            if ( isdefined( level.put_timed_out_zombies_back_in_queue ) && level.put_timed_out_zombies_back_in_queue && !flag( "dog_round" ) )
            {
                // ...
                level.zombie_total++;
                level.zombie_total_subtract++;
            }

            self dodamage( self.health + 100, ( 0, 0, 0 ) );
            break;
        }
        // ...
    }
}
```

**The bug:** When a zombie is stuck (moves < 24 units in 30 seconds), the failsafe kills it and increments `level.zombie_total` to queue a replacement. If the replacement zombie also gets stuck (geometry, pathfinding failure, unkillable health at high rounds), it also triggers the failsafe. This creates a cycle: stuck -> kill -> respawn -> stuck -> kill -> respawn...

**Why it's worse at high rounds:**
- At round 163+, zombie health overflows and is capped at max int — zombies become effectively unkillable by normal damage, making more of them trigger the stuck timer
- The failsafe cycle time is 30-40 seconds per zombie, so the round stretches to hours or days
- `round_wait()` at line 3700 waits for `get_current_zombie_count() == 0 && level.zombie_total == 0`, which never happens if zombies keep recycling

**Impact:** Not a hard freeze, but a soft-lock where the round can never end. The game remains responsive but unplayable.

**Fix approach:** Add a maximum recycle count per round. After N recycles, force-kill the zombie without re-queuing:
```gsc
if ( level.zombie_total_subtract > level.zombie_total * 2 )
{
    // Don't re-queue, just kill
    self dodamage( self.health + 100, ( 0, 0, 0 ) );
    break;
}
```
