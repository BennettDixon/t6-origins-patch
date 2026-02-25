# Origins Tank: Five More Bugs, One of Them Already Familiar

*Part 11 of the BO2 High-Round Crash Fix series.
[Part 1](01-the-archaeology.md) | [Part 2](02-the-diagnostic-tools.md) | [Part 3](03-entity-leaks.md) | [Part 4](04-the-patch.md) | [Part 5](05-results.md) | [Part 6](06-fixing-the-core.md) | [Part 7](07-origins-patched.md) | [Part 8](08-die-rise-patched.md) | [Part 9](09-the-full-patch.md) | [Part 10](10-generators-patched.md) | [Part 12](12-testing-origins-staffs.md) | [Part 13](13-fire-staff-balance-gap.md)*

---

Having found bugs in Origins' staff weapons and generator system, we looked at the
remaining unique subsystem: the tank. Players pay 500 points to ride it around the map.
Zombies board it to chase players. It has flamethrowers. It runs over players who stand
too close to its treads.

`zm_tomb_tank.gsc` has five bugs, one of which was already half-fixed by the SA-10 patch.

---

## The SA-10 Connection

The tank's two side flamethrowers (gunner1 and gunner2) kill zombies by calling
`_zm_weap_staff_fire::flame_damage_fx`:

```gsc
// flamethrower_damage_zombies():
ai_zombie thread maps\mp\zombies\_zm_weap_staff_fire::flame_damage_fx( "zm_tank_flamethrower", self );
```

That's the same function SA-10 broke. Before the SA-10 fix, every flame hit from a side
gunner spawned redundant burn threads on each target zombie — same dedup guard, same wrong
entity, same thread burst as a Fire Staff blast. The tank's flamethrowers were a second,
independent source of the SA-10 pressure on every Origins session that used the tank.

The SA-10 fix in `_zm_weap_staff_fire.gsc` covers this path for free. No additional fix is
needed for the tank's use of `flame_damage_fx`.

---

## TANK-EL-01: Entity Leak in the Run-Over Animation

When the tank runs over a player, the game spawns a `script_origin` entity, links the
player to it, and moves it to the nearest safe nav node so the player doesn't end up
inside the tank's collision geometry:

```gsc
// tank_ran_me_over():
e_linker = spawn( "script_origin", self.origin );
self playerlinkto( e_linker );
e_linker moveto( node.origin + vectorscale( ( 0, 0, 1 ), 8.0 ), 1.0 );
e_linker wait_to_unlink( self );
node.b_player_downed_here = undefined;
e_linker delete();
```

The 4-second drag uses a helper function:

```gsc
wait_to_unlink( player )
{
    player endon( "disconnect" );
    wait 4;
    self unlink();
}
```

`wait_to_unlink` is called synchronously (no `thread` keyword), so it runs in the same
execution context as `tank_ran_me_over`. The `player endon("disconnect")` line means: if
the player disconnects, terminate the current thread.

When that happens, the entire `tank_ran_me_over` thread is killed — including the
`e_linker delete()` call that follows. The `script_origin` entity remains allocated
indefinitely with no owner and no cleanup.

This is EL-01's pattern exactly. `lerp()` had the same structure: a spawned entity, a
blocking wait with an `endon` that could kill the parent thread, and a `delete()` after
the wait that was reachable only if the thread survived. The fix is also the same: expose
the entity before the blocking call so a separate disconnect watcher can clean it up.

```gsc
// Fixed tank_ran_me_over():
e_linker = spawn( "script_origin", self.origin );
self._tank_runover_linker = e_linker;  // expose for disconnect cleanup
self playerlinkto( e_linker );
e_linker moveto( node.origin + vectorscale( ( 0, 0, 1 ), 8.0 ), 1.0 );
e_linker wait_to_unlink( self );
self._tank_runover_linker = undefined;
node.b_player_downed_here = undefined;
e_linker delete();

// New function threaded in onplayerconnect():
watch_tank_runover_disconnect()
{
    self waittill( "disconnect" );
    if ( isdefined( self._tank_runover_linker ) )
    {
        self._tank_runover_linker delete();
        self._tank_runover_linker = undefined;
    }
}
```

---

## TANK-TL-01: Thread Leak on Player Disconnect While on Tank

When a player boards the tank, two threads are started on them — one per rear tread
trigger — to detect when a player walks off the back edge and push them clear:

```gsc
foreach ( trig in self.t_rear_tread )
    e_player thread tank_push_player_off_edge( trig );
```

Each thread:

```gsc
tank_push_player_off_edge( trig )
{
    self endon( "player_jumped_off_tank" );

    while ( self.b_already_on_tank )
    {
        trig waittill( "trigger", player );

        if ( player == self && self isonground() )
        {
            v_push = anglestoforward( trig.angles ) * 150;
            self setvelocity( v_push );
        }

        wait 0.05;
    }
}
```

The exit condition is `"player_jumped_off_tank"` — a notify sent when the player leaves
the tank normally. If the player disconnects while on the tank, that notify is never sent.
`b_already_on_tank` stays 1. Both threads sit indefinitely at `trig waittill("trigger", player)`.

The `waittill` wakes on any player touching the trigger. The thread wakes, checks
`if (player == self)` against a disconnected player entity that never matches, and blocks
again. Two threads per disconnect, permanent.

The fix is one line:

```gsc
tank_push_player_off_edge( trig )
{
    self endon( "player_jumped_off_tank" );
    self endon( "disconnect" );  // TANK-TL-01 fix
    // ...
}
```

---

## TANK-MI-01: Broken Flamethrower Cone Check

`tank_flamethrower_get_targets` is supposed to filter zombies by distance and angular
position relative to each flamethrower. The distance filter works. The angular filter
doesn't:

```gsc
// Original (broken):
v_to_zombie = vectornormalize( ai_zombie.origin - v_tag_pos );
n_dot = vectordot( v_tag_fwd, ai_zombie.origin );  // ← wrong

if ( n_dot < 0.95 )
    continue;
```

`v_to_zombie` is the normalized direction from the flamethrower to the zombie. The dot
product of that with the forward vector would give the cosine of the angle between them
— that's a valid cone check.

Instead, the code takes the dot product of the forward vector with `ai_zombie.origin` —
a raw world-space position. The result is the scalar projection of the zombie's world
coordinates onto the flamethrower's forward axis. It has no meaningful relationship to
whether the zombie is in front of or behind the flamethrower.

The 0.95 threshold applied to a world position will be satisfied or not depending purely
on where the tank happens to be on the map and which direction it's facing. Zombies
behind the flamethrower might be included; zombies directly in front might be excluded.

`v_to_zombie` is computed correctly and then never used. The fix:

```gsc
n_dot = vectordot( v_tag_fwd, v_to_zombie );  // TANK-MI-01 fix
```

---

## TANK-MI-02: Stopped-Tank Zombies Always Route to the Back

When the tank is stopped and a zombie's favorite enemy is on it, `enemy_location_override`
should route the zombie to whichever end is closer:

```gsc
// Original (broken):
tank_front = tank gettagorigin( "window_right_front_jmp_jnt" );
tank_back  = tank gettagorigin( "window_left_rear_jmp_jnt" );

// ...

front_dist = distance2dsquared( enemy.origin, level.vh_tank.origin );
back_dist  = distance2dsquared( enemy.origin, level.vh_tank.origin );  // ← identical

if ( front_dist < back_dist )
    location = tank_front;
else
    location = tank_back;   // always taken
```

`tank_front` and `tank_back` are computed correctly on the lines above. Then both
distance calculations use `level.vh_tank.origin` — the tank's center — instead of the
respective tag positions. The two expressions are identical; the comparison is always
false; zombies always navigate to `tank_back`.

```gsc
// Fixed:
front_dist = distance2dsquared( enemy.origin, tank_front );
back_dist  = distance2dsquared( enemy.origin, tank_back );
```

The visible symptom is zombies piling up at the rear of a stopped tank even when the
front entry point is closer. Not a crash vector, but a consistent routing anomaly that
concentrates zombie density asymmetrically around the vehicle.

---

## TANK-MI-03: The Polling Loop

`zombies_watch_tank` is responsible for assigning the tank AI state machine to each
zombie. It runs at 20Hz, scanning the full zombie array on every tick:

```gsc
while ( true )
{
    a_zombies = get_round_enemy_array();

    foreach ( e_zombie in a_zombies )
    {
        if ( !isdefined( e_zombie.tank_state ) )
            e_zombie thread tank_zombie_think();
    }

    wait_network_frame();  // 0.05s
}
```

Once a zombie has been threaded, `isdefined(e_zombie.tank_state)` returns true and the
inner body is skipped — but the loop still traverses the array every frame. At high
rounds with 24 active zombies, this is 480 isdefined checks per second that do nothing.

The spawner already provides `add_custom_zombie_spawn_logic()`, which accepts a function
pointer and calls it as a thread on each zombie at spawn time. This is the event-driven
equivalent of what the polling loop does:

```gsc
// Fixed zombies_watch_tank():
zombies_watch_tank()
{
    a_tank_tags = tank_tag_array_setup();
    self.a_tank_tags = a_tank_tags;
    a_mechz_tags = mechz_tag_array_setup();
    self.a_mechz_tags = a_mechz_tags;

    maps\mp\zombies\_zm_spawner::add_custom_zombie_spawn_logic( ::tank_zombie_think );
}
```

The O(n) 20Hz loop is gone. Each zombie gets `tank_zombie_think()` threaded on it exactly
once, at spawn, with no ongoing scan cost. Behavior is identical.

This is the same pattern as Die Rise's MI-12 fix: a polling loop that checked every
entity at a fixed interval, replaced by a spawn-time callback that does the work exactly
once. The overhead difference scales with zombie count and session length.

---

## Deployment

Same `mod.ff`, same deployment step:

```bash
./build_ff.sh
cp /tmp/oat_hrp_build/zone_out/zm_hrp/mod.ff \
   "%LOCALAPPDATA%\Plutonium\storage\t6\mods\zm_hrp\mod.ff"
```

The tank fixes live in `zm_tomb_tank.gsc`. Like the staff weapon and generator fixes,
they only activate when `zm_tomb.ff` is loaded — dormant on every other map.

---

## What This Changes

The SA-10 amplification finding is the most significant: the tank's side flamethrowers
were a second emission source for the same broken burn thread burst, throughout every
Origins session where players used the tank (which is every Origins session at high
rounds — it's the only reliable way to traverse the map under pressure). The SA-10 fix
was already covering this before we knew the tank was involved.

TANK-MI-03 removes the last 20Hz scan loop in Origins — the map now has no polling
loops left across any of its three unique systems (staffs, generators, tank).

TANK-EL-01 closes the last entity leak variant in the same pattern as EL-01. The
structural lesson of EL-01 — expose entities to watchdogs before blocking waits with
endon guards — applies here without modification.

*All scripts, research, and source are at [github.com/banq/t6-high-round-fix](#).*
