# Race Conditions and Logic Bugs

Concurrency issues in GSC's cooperative multitasking model, plus outright logic errors that cause incorrect behavior.

---

## RC-01: `array_flag_wait_any()` variable name mismatch (MEDIUM)

**File:** `_zm_utility.gsc:3547-3560`

```gsc
array_flag_wait_any( flag_array )
{
    if ( !isdefined( level._array_flag_wait_any_calls ) )
        level._n_array_flag_wait_any_calls = 0;
    else
        level._n_array_flag_wait_any_calls++;

    str_condition = "array_flag_wait_call_" + level._n_array_flag_wait_any_calls;

    for ( index = 0; index < flag_array.size; index++ )
        level thread array_flag_wait_any_thread( flag_array[index], str_condition );

    level waittill( str_condition );
}
```

**The bug:** Line 3549 checks `isdefined( level._array_flag_wait_any_calls )` (without `_n_` prefix), but line 3550 sets `level._n_array_flag_wait_any_calls` (with `_n_` prefix). Since `_array_flag_wait_any_calls` is never defined anywhere, the `isdefined` always returns false. The counter is reset to 0 on every call.

**Impact:** Every invocation of `array_flag_wait_any` generates the same condition string: `"array_flag_wait_call_0"`. If two different systems both call this function concurrently, their flag waits use the same notify. When either one's flag is set, both waiters wake up — meaning unrelated game logic can prematurely resolve.

**How it manifests:** Depending on which systems use this function, it could cause premature zone activations, incorrect game state transitions, or skipped logic. The effects are subtle and timing-dependent.

**Fix:**
```gsc
array_flag_wait_any( flag_array )
{
    if ( !isdefined( level._n_array_flag_wait_any_calls ) )
        level._n_array_flag_wait_any_calls = 0;
    else
        level._n_array_flag_wait_any_calls++;

    str_condition = "array_flag_wait_call_" + level._n_array_flag_wait_any_calls;
    // ... rest unchanged ...
}
```

---

## RC-02: Grenade explosion position shared globals (MEDIUM)

**File:** `_zm_weapons.gsc:165-173`

```gsc
wait_for_explosion( time )
{
    level.explode_position = ( 0, 0, 0 );
    level.explode_position_valid = 0;
    self thread wait_explode();
    self thread wait_timeout( time );
    self waittill( "done" );
    self notify( "death_or_explode", level.explode_position_valid, level.explode_position );
}
```

**The bug:** `level.explode_position` and `level.explode_position_valid` are level-scoped globals shared across all grenade instances. When multiple grenades are in-flight simultaneously (common at high rounds), they clobber each other's explosion position data.

**Sequence:**
1. Grenade A calls `wait_for_explosion`, sets `level.explode_position = (0,0,0)`
2. Grenade B calls `wait_for_explosion`, sets `level.explode_position = (0,0,0)`
3. Grenade A explodes, sets `level.explode_position = (100, 200, 50)`
4. Grenade B explodes, sets `level.explode_position = (300, 400, 60)`
5. Grenade A reads `level.explode_position` — gets B's position

**Impact:** Incorrect explosion positions used for downstream damage calculations and entity spawning. At high rounds with frequent grenade usage, this is triggered constantly.

**Fix:** Store explosion data on `self` instead of `level`:
```gsc
wait_for_explosion( time )
{
    self.explode_position = ( 0, 0, 0 );
    self.explode_position_valid = 0;
    self thread wait_explode();
    self thread wait_timeout( time );
    self waittill( "done" );
    self notify( "death_or_explode", self.explode_position_valid, self.explode_position );
}
```

---

## RC-03: Spawner array modification during iteration (MEDIUM)

**File:** `_zm_spawner.gsc:55-63`

```gsc
if ( isdefined( level.ignore_spawner_func ) )
{
    for ( i = 0; i < level.zombie_spawners.size; i++ )
    {
        ignore = [[ level.ignore_spawner_func ]]( level.zombie_spawners[i] );

        if ( ignore )
            arrayremovevalue( level.zombie_spawners, level.zombie_spawners[i] );
    }
}
```

**The bug:** `arrayremovevalue` removes an element and shifts all subsequent elements down by one. But `i` increments unconditionally on the next loop iteration, skipping the element that shifted into the current index.

**Example:**
- Array: `[A, B, C, D]`, `i = 1`, B should be ignored
- `arrayremovevalue` removes B: `[A, C, D]`
- `i` increments to 2, checking D — C is skipped entirely

**Impact:** Some spawners that should be filtered out remain in `level.zombie_spawners`. This could cause zombies to spawn from unexpected locations or increase the total spawner pool. Not a crash risk but incorrect behavior.

**Fix:** Decrement `i` after removal, or iterate in reverse:
```gsc
for ( i = level.zombie_spawners.size - 1; i >= 0; i-- )
{
    ignore = [[ level.ignore_spawner_func ]]( level.zombie_spawners[i] );

    if ( ignore )
        arrayremovevalue( level.zombie_spawners, level.zombie_spawners[i] );
}
```

---

## RC-04: Magic box timeout race condition (LOW)

**File:** `_zm_magicbox.gsc:852-859, 1328-1337`

```gsc
// treasure_chest_timeout — 12 second flat wait
wait 12;
self notify( "trigger", level );

// timer_til_despawn — 12 second moveto + wait
self moveto( self.origin - v_float * 0.85, putbacktime, putbacktime * 0.5 );
wait( putbacktime );
if ( isdefined( self ) )
    self delete();
```

**The bug:** Both timers start near-simultaneously with the same duration (12 seconds). The timeout handler fires first (simpler codepath), which triggers the grab logic with `self.timedout = 1`. In that path, weapon models are *not* deleted — the code relies on `timer_til_despawn` to handle it. But if `treasure_chest_think` recurses before the old timer fires (server lag at high rounds), `self.weapon_model` is overwritten with a new entity, orphaning the old one.

**Impact:** Brief window where two weapon model entities coexist per chest. The old one is eventually cleaned up by `timer_til_despawn`, but during high entity pressure at high rounds, even a temporary +1 entity can push past the limit.
