# Entity Leaks

Entity leaks are the primary cause of high-round crashes. The BO2 engine has a hard limit on concurrent entities (~1024). When a spawned entity (`script_origin`, `script_model`, `trigger_radius`, etc.) is never deleted, it permanently consumes a slot. Once the limit is reached, the engine crashes.

---

## EL-01: `lerp()` leaks `script_origin` on zombie death (CRITICAL)

**File:** `_zm_utility.gsc:53-63`

```gsc
lerp( chunk )
{
    link = spawn( "script_origin", self getorigin() );
    link.angles = self.first_node.angles;
    self linkto( link );
    link rotateto( self.first_node.angles, level._contextual_grab_lerp_time );
    link moveto( self.attacking_spot, level._contextual_grab_lerp_time );
    link waittill_multiple( "rotatedone", "movedone" );
    self unlink();
    link delete();
}
```

**Mechanism:** Called during zombie window-attack animations. A `script_origin` is spawned as a movement anchor. There is no `self endon("death")` — if the zombie (`self`) is killed mid-animation, the GSC thread terminates at the `waittill_multiple` and `link delete()` is never reached. The entity is permanently orphaned.

**High-round impact:** Window attacks are one of the most frequent zombie interactions. At round 100+ with 24 active zombies cycling rapidly, a significant fraction die mid-animation from splash damage, traps, or Insta-Kill. Each leak is permanent. This is likely the single largest contributor to entity exhaustion.

**Fix approach:**
```gsc
lerp( chunk )
{
    link = spawn( "script_origin", self getorigin() );
    self thread lerp_cleanup_on_death( link );
    link.angles = self.first_node.angles;
    self linkto( link );
    link rotateto( self.first_node.angles, level._contextual_grab_lerp_time );
    link moveto( self.attacking_spot, level._contextual_grab_lerp_time );
    link waittill_multiple( "rotatedone", "movedone" );
    self unlink();
    link delete();
}

lerp_cleanup_on_death( link )
{
    self waittill( "death" );

    if ( isdefined( link ) )
        link delete();
}
```

---

## EL-02: `do_zombie_rise()` leaks anchor on death (CRITICAL)

**File:** `_zm_spawner.gsc:2776-2830`

```gsc
do_zombie_rise( spot )
{
    self endon( "death" );
    // ...
    self.anchor = spawn( "script_origin", self.origin );
    self.anchor.angles = self.angles;
    self linkto( self.anchor );
    // ... long animation sequence (several seconds) ...
    self unlink();

    if ( isdefined( self.anchor ) )
        self.anchor delete();
```

**Mechanism:** `self endon("death")` is present, which means if the zombie dies during the rise animation, the thread exits immediately — *before* `self.anchor delete()` is reached. The death handler `zombie_rise_death()` (line 2858) watches for damage but does **not** clean up the anchor entity.

**High-round impact:** Rise animations take several seconds. At high rounds with Insta-Kill active or traps near spawn barriers, zombies frequently die mid-rise. Each occurrence permanently leaks a `script_origin`.

**Fix approach:** Thread a cleanup watcher before the `endon`:
```gsc
do_zombie_rise( spot )
{
    self thread zombie_rise_anchor_cleanup();
    self endon( "death" );
    // ... rest unchanged ...
}

zombie_rise_anchor_cleanup()
{
    self waittill( "death" );

    if ( isdefined( self.anchor ) )
        self.anchor delete();
}
```

---

## EL-03: `do_zombie_spawn()` leaks anchor on death (CRITICAL)

**File:** `_zm_spawner.gsc:2612-2774`

```gsc
do_zombie_spawn()
{
    self endon( "death" );
    // ...
    self.anchor = spawn( "script_origin", self.origin );
    self.anchor.angles = self.angles;
    self linkto( self.anchor );
    // ... movement to spawn point ...
    self unlink();

    if ( isdefined( self.anchor ) )
        self.anchor delete();
```

**Mechanism:** Identical pattern to EL-02. The anchor is spawned for movement interpolation during the spawn sequence. `endon("death")` kills the thread before cleanup.

**High-round impact:** Less frequent than EL-02 since the spawn movement is shorter, but still contributes to entity exhaustion over hundreds of rounds.

**Fix approach:** Same pattern as EL-02 — thread a death watcher before the `endon`.

---

## EL-04: `really_play_2d_sound()` leaks on failed sound notify (HIGH)

**File:** `_zm_utility.gsc:2792-2799`

```gsc
really_play_2d_sound( sound )
{
    temp_ent = spawn( "script_origin", ( 0, 0, 0 ) );
    temp_ent playsoundwithnotify( sound, sound + "wait" );
    temp_ent waittill( sound + "wait" );
    wait 0.05;
    temp_ent delete();
}
```

**Mechanism:** If the sound alias is invalid, missing, or the sound engine fails to fire the notify callback, the `waittill` blocks forever. The `script_origin` is permanently leaked and the thread hangs indefinitely.

**High-round impact:** Called from `play_sound_2d()` which is used in powerup drops and various game events. Under heavy load at high rounds, the sound engine may drop callbacks.

**Fix approach:** Add a timeout:
```gsc
really_play_2d_sound( sound )
{
    temp_ent = spawn( "script_origin", ( 0, 0, 0 ) );
    temp_ent playsoundwithnotify( sound, sound + "wait" );
    temp_ent thread sound_delete_failsafe();
    temp_ent waittill( sound + "wait" );
    temp_ent notify( "sound_done" );
    wait 0.05;
    temp_ent delete();
}

sound_delete_failsafe()
{
    self endon( "sound_done" );
    wait 10;

    if ( isdefined( self ) )
        self delete();
}
```

---

## EL-05: `start_bonfire_sale()` leaks `script_origin` on overlap (HIGH)

**File:** `_zm_powerups.gsc:1182-1206`

```gsc
start_bonfire_sale( item )
{
    level notify( "powerup bonfire sale" );
    level endon( "powerup bonfire sale" );
    temp_ent = spawn( "script_origin", ( 0, 0, 0 ) );
    temp_ent playloopsound( "zmb_double_point_loop" );
    // ... timer logic ...
    temp_ent delete();
}
```

**Mechanism:** When a second bonfire sale is triggered while one is active, line 1183 sends `"powerup bonfire sale"`, which kills the previous thread via `endon` at line 1184 — *after* the previous `temp_ent` was spawned but *before* it's deleted. The old entity is orphaned.

**High-round impact:** Each overlapping fire sale leaks one entity. With fire sale powerups spawning more frequently at high rounds, this accumulates.

**Fix approach:** Store `temp_ent` on `level` and delete it in a cleanup handler before spawning the new one.

---

## EL-06: Magic box `box_locked` orphans weapon models (HIGH)

**File:** `_zm_magicbox.gsc:1065-1074`

```gsc
treasure_chest_weapon_spawn( chest, player, respin )
{
    if ( isdefined( level.using_locked_magicbox ) && level.using_locked_magicbox )
    {
        self.owner endon( "box_locked" );
        self thread maps\mp\zombies\_zm_magicbox_lock::clean_up_locked_box();
    }

    self endon( "box_hacked_respin" );
    // ... weapon models spawned later at line 1130 ...
```

**Mechanism:** If `box_locked` fires after weapon models are spawned (line 1130), `endon` terminates the entire function. The cleanup thread at line 1070 only handles its own specific case. The weapon model entities at `self.weapon_model` and `self.weapon_model_dw` are orphaned. Additionally, `treasure_chest_think` hangs at line 515 waiting for `"randomization_done"` which never fires, and `treasure_chest_glowfx` hangs waiting for `"weapon_grabbed"` — so 3 threads also leak.

**High-round impact:** Depends on whether the locked magicbox feature is active on the map. When it is, each occurrence leaks 1-2 entities + 3 threads.

---

## EL-07: Insta-Kill / Double Points timer sound entities (MEDIUM)

**File:** `_zm_powerups.gsc:1715-1728, 1745-1764`

```gsc
time_remaning_on_insta_kill_powerup( player_team )
{
    temp_enta = spawn( "script_origin", ( 0, 0, 0 ) );
    temp_enta playloopsound( "zmb_insta_kill_loop" );
    // ... countdown loop ...
    temp_enta delete();
}
```

**Mechanism:** These functions spawn a `script_origin` for looping sound playback during the powerup timer. If the game ends or host migration occurs mid-countdown, the entity is not cleaned up (no `level endon("end_game")` with a cleanup path).

**High-round impact:** Low-frequency leak, but each interrupted timer permanently leaks an entity.

---

## EL-08: `check_point_in_playable_area()` temporary entity risk (MEDIUM)

**File:** `_zm_utility.gsc:431-445`

```gsc
check_point_in_playable_area( origin )
{
    playable_area = getentarray( "player_volume", "script_noteworthy" );
    check_model = spawn( "script_model", origin + vectorscale( ( 0, 0, 1 ), 40.0 ) );
    // ... collision check ...
    check_model delete();
    return valid_point;
}
```

**Mechanism:** Spawns a temporary `script_model` for an `istouching` collision check, then deletes it. If called when the entity count is at or near the limit, the `spawn` itself can fail or crash. If a script error interrupts execution between spawn and delete, the entity leaks.

**High-round impact:** Called during powerup drops. The temporary entity competes for slots with all the permanently leaked entities from EL-01 through EL-07.

---

## Entity Leak Budget Estimate

Rough estimate of leak rate at round 150 (solo, normal gameplay):

| Source | Leaks/Round | Cumulative by R150 |
|--------|-------------|-------------------|
| `lerp()` window attacks | ~2-5 | ~300-750 |
| `do_zombie_rise()` | ~1-3 | ~150-450 |
| `do_zombie_spawn()` | ~0-1 | ~0-150 |
| Sound / powerup / box | ~0.1 | ~15 |
| **Total** | **~3-9** | **~465-1365** |

With an entity ceiling of ~1024, the math shows crashes becoming likely somewhere between round 80-200 depending on playstyle, map, and how many zombies die mid-animation. Aggressive players using traps and splash weapons near barriers will hit it faster.
