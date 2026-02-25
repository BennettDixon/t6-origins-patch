# State Accumulation

These are values — arrays, counters, and tracking structures — that grow monotonically throughout the game session with no cleanup or reset mechanism. They don't overflow quickly, but they contribute to memory pressure and can cause incorrect behavior at high rounds.

---

## SA-01: `level.chest_accessed` unbounded on single-box maps (MEDIUM)

**File:** `_zm_magicbox.gsc:83, 599, 1199`

```gsc
// Init
level.chest_accessed = 0;

// Incremented every box grab (line 599)
level.chest_accessed = level.chest_accessed + 1;

// Only reset when box moves (teddy bear, line 1199)
level.chest_accessed = 0;
```

**Mechanism:** On maps with a single chest location, `no_fly_away` is set, which forces `chance_of_joker = -1` — the box never moves and the counter never resets. It grows by 1 per box hit for the entire game.

**Impact:** The counter is used in joker chance calculation (`chance_of_joker = level.chest_accessed + 20`). At thousands of hits, the value is meaninglessly large. It's also passed to `bbprint` logging — excessively large values in telemetry can cause buffer issues at the engine level.

**Related counters:**
- `level.pulls_since_last_ray_gun` — incremented every pull (line 601), only reset when Ray Gun is drawn
- `level.pulls_since_last_tesla_gun` — incremented every pull (line 605), only reset when Tesla Gun is drawn

On maps where these weapons are unavailable, these counters grow indefinitely.

---

## SA-02: Global kill/timeout counters never reset (MEDIUM)

**File:** `_zm.gsc:4752-4761`

```gsc
initializestattracking()
{
    level.global_zombies_killed = 0;
    level.zombies_timeout_spawn = 0;
    level.zombies_timeout_playspace = 0;
    level.zombies_timeout_undamaged = 0;
    level.zombie_player_killed_count = 0;
    level.zombie_trap_killed_count = 0;
    level.zombie_pathing_failed = 0;
    level.zombie_breadcrumb_failed = 0;
}
```

Initialized once at game start, incremented throughout:
- `level.global_zombies_killed` — every zombie death (`_zm_spawner.gsc:2177`)
- `level.total_zombies_killed` — every zombie death (`_zm_spawner.gsc:2249`)
- `level.zombie_total_subtract` — every failsafe recycle (`_zm.gsc:3667`)
- `level.zombies_timeout_playspace` — every playspace timeout (`_zm.gsc:3688`)
- Per-player: `attacker.kills`, `attacker.headshots`

**Impact:** These are 32-bit integers. Overflow requires ~2 billion kills — unrealistic in practice. But the failsafe-related counters (`zombie_total_subtract`, `zombies_timeout_playspace`) can grow rapidly when zombies are stuck in a recycling loop (see [IL-03](./infinite-loops.md#il-03-failsafe-zombie-recycling-loop-high)).

---

## SA-03: `grenade_multiattack_count` never reset (MEDIUM)

**File:** `_zm_spawner.gsc:1947, 2210`

```gsc
// On grenade damage (line 1947)
player.grenade_multiattack_count++;
player.grenade_multiattack_ent = self;

// On grenade kill (line 2210)
attacker.grenade_multiattack_count++;
attacker.grenade_multiattack_ent = zombie;
```

**Mechanism:** Incremented every time a zombie takes grenade damage or dies from grenade splash. Never reset between throws or between rounds.

**Impact:** Any downstream logic that branches on this value (scoring, achievements, persistent upgrades) will behave incorrectly. After hundreds of rounds of grenade usage, the count is enormous.

---

## SA-04: `level._spawned_path_nodes` never cleaned (MEDIUM)

**File:** `_zm_utility.gsc:4827-4857`

```gsc
spawn_path_node( origin, angles, k1, v1, k2, v2 )
{
    if ( !isdefined( level._spawned_path_nodes ) )
        level._spawned_path_nodes = [];
    node = spawnstruct();
    // ...
    level._spawned_path_nodes[level._spawned_path_nodes.size] = node;
    return node.node;
}

delete_spawned_path_nodes()
{
    // Empty function body
}
```

**Mechanism:** Path nodes are appended to the array but the cleanup function is a no-op. Either the implementation was never written, was stripped during decompilation, or the developers considered it unnecessary because path nodes are small.

**Impact:** Memory growth proportional to the number of path nodes spawned. In practice this is likely bounded by the number of zone activations (which is finite per map), but it's still a missing cleanup.

---

## SA-05: `level.retrievable_knife_init_names` grows on reconnect (MEDIUM)

**File:** `_zm_weapons.gsc:460-465`

```gsc
weaponobjects_on_player_connect_override()
{
    add_retrievable_knife_init_name( "knife_ballistic" );
    add_retrievable_knife_init_name( "knife_ballistic_upgraded" );
    onplayerconnect_callback( ::weaponobjects_on_player_connect_override_internal );
}
```

**Mechanism:** Called on every player connect. Appends two entries to `level.retrievable_knife_init_names` each time. In `weaponobjects_on_player_connect_override_internal`, the array is iterated to create ballistic knife watchers per player (line 437).

**Impact:** With player disconnects/reconnects in long games, the array grows and each reconnect creates additional duplicate watchers. Each watcher likely spawns threads and potentially trigger entities.

---

## SA-06: `level._link_node_list` / `level._unlink_node_list` growth (LOW)

**File:** `_zm_utility.gsc:4749-4784`

```gsc
link_nodes( a, b, bdontunlinkonmigrate )
{
    // ...
    if ( !isdefined( level._link_node_list[a_index_string] ) )
    {
        level._link_node_list[a_index_string] = spawnstruct();
        level._link_node_list[a_index_string].node = a;
        level._link_node_list[a_index_string].links = [];
        level._link_node_list[a_index_string].ignore_on_migrate = [];
    }
    // ...
}
```

**Mechanism:** Used for host migration replay. Each unique node linkage creates struct entries with sub-arrays. Never pruned, even for nodes that are later unlinked.

**Impact:** Growth proportional to total link/unlink operations. Bounded by map geometry but contributes to memory pressure in long sessions.

---

## SA-07: `weighted_rounds_played` stat accumulates round number (LOW)

**File:** `_zm.gsc:3525-3526`

```gsc
if ( level.curr_gametype_affects_rank && level.round_number > 3 + level.start_round )
    player maps\mp\zombies\_zm_stats::add_client_stat( "weighted_rounds_played", level.round_number );
```

**Mechanism:** Each round cycle **adds** `level.round_number` to this stat (not sets). At round 255 (the cap), this adds 255 per cycle. After 8.4 million round-255 cycles it overflows int32 — unrealistic, but the stat grows unboundedly.

---

## SA-08: `self.hitsthismag` grows with every unique weapon string encountered (HIGH)

**File:** `_zm_weapons.gsc:390-414`

```gsc
watchweaponchangezm()
{
    self endon( "death" );
    self endon( "disconnect" );
    self.hitsthismag = [];    // initialized once at thread start, never reset
    weapon = self getcurrentweapon();

    if ( isdefined( weapon ) && weapon != "none" && !isdefined( self.hitsthismag[weapon] ) )
        self.hitsthismag[weapon] = weaponclipsize( weapon );

    while ( true )
    {
        self waittill( "weapon_change", newweapon );
        // ...
        if ( !isdefined( self.hitsthismag[newweapon] ) )
            self.hitsthismag[newweapon] = weaponclipsize( newweapon );  // ← new entry per unique weapon
    }
}
```

**Mechanism:** `watchweaponchangezm()` is threaded once per player connect and runs for the entire game session. `self.hitsthismag` is initialized as an empty array at thread start and never cleared. Every unique weapon string the player switches to adds a new key to the array. In BO2 zombies, weapon names are `+`-delimited compound strings that include all attachments — `"an94_zm"`, `"an94_zm+reflex"`, `"an94_zm+reflex+grip"`, and their PaP variants (`"an94_upgraded_zm"`, etc.) are all distinct keys.

**Impact:** This is a per-player associative array on the player entity, so each new entry is one child variable slot in the engine's global scrVar pool. With aggressive box cycling through 50+ weapons and their attachment variants, a single player can accumulate 40–80+ unique weapon strings across the session. With 4 players at high rounds, this is 160–320+ permanently-held scrVar slots. The array is never pruned between rounds, between box hits, or on weapon drop.

**Severity note:** This is the primary per-player contributor to the "exceeded maximum number of child server script variables" crash — see `research/02-static-analysis-findings.md` Phase 6 for the full analysis of how this interacts with the scrVar pool limit.

---

## SA-09: `self.pack_a_punch_weapon_options` caches every PaP'd weapon permanently (MEDIUM)

**File:** `_zm_weapons.gsc:2261-2316`

```gsc
get_pack_a_punch_weapon_options( weapon )
{
    if ( !isdefined( self.pack_a_punch_weapon_options ) )
        self.pack_a_punch_weapon_options = [];    // initialized lazily, never cleared

    if ( isdefined( self.pack_a_punch_weapon_options[weapon] ) )
        return self.pack_a_punch_weapon_options[weapon];   // cache hit

    // ... compute options (camo, lens, reticle indices) ...

    self.pack_a_punch_weapon_options[weapon] = self calcweaponoptions( ... );  // ← new entry per unique weapon
    return self.pack_a_punch_weapon_options[weapon];
}
```

**Mechanism:** `get_pack_a_punch_weapon_options()` is called each time a player PaPs a weapon, to compute the visual customization (camo, scope, reticle). It caches the result in a per-player array keyed by the full upgraded weapon name string. The array is never cleared. Every unique upgraded weapon string a player PaPs creates a permanent child variable entry on the player entity.

**Impact:** Less severe than SA-08 in isolation — typical high-round play might cycle through 10–20 unique PaP'd weapons per player. But each entry holds a value from `calcweaponoptions()`, which returns a packed options integer. Combined with SA-08, the two arrays together mean a high-round player entity is continuously accumulating scrVar slots from all box and PaP activity, with no release path until the session ends.

---

## SA-10: `fire_staff_area_of_effect` always floods per-zombie threads — wrong `is_on_fire` target (HIGH, Origins only)

**File:** `_zm_weap_staff_fire.gsc:113–151` (Origins DLC, `zm_tomb.ff`)

```gsc
fire_staff_area_of_effect( e_attacker, str_weapon )
{
    // self = projectile entity
    self waittill( "explode", v_pos );
    // ...
    while ( n_alive_time > 0.0 )
    {
        a_targets = getaiarray( "axis" );
        a_targets = get_array_of_closest( v_pos, a_targets, undefined, undefined, aoe_radius );
        wait( n_step_size );   // 0.2s

        foreach ( e_target in a_targets )
        {
            if ( isdefined( e_target ) && isalive( e_target ) )
            {
                if ( !is_true( self.is_on_fire ) )        // ← BUG: self is the PROJECTILE
                    e_target thread flame_damage_fx( str_weapon, e_attacker );
            }
        }
    }
}
```

**Mechanism:** `fire_staff_area_of_effect` runs as a thread on the fired **projectile** entity (`e_projectile thread fire_staff_area_of_effect(...)`). Inside the loop, `self` refers to that projectile. The `is_on_fire` field is a state flag set on **zombie** entities by `flame_damage_fx`:

```gsc
flame_damage_fx( damageweapon, e_attacker, pct_damage )
{
    was_on_fire = is_true( self.is_on_fire );  // self = zombie here
    // ...
    if ( !was_on_fire )
    {
        self.is_on_fire = 1;                   // set on zombie, not on projectile
        self thread zombie_set_and_restore_flame_state();
        wait 0.5;
        self thread flame_damage_over_time( e_attacker, damageweapon, pct_damage );
    }
}
```

Because `is_on_fire` is never set on the projectile entity, `!is_true(self.is_on_fire)` is **always true**. The guard intended to skip already-burning zombies is completely bypassed. On every 0.2-second tick for the full 5-second AoE lifetime (25 ticks), every zombie in range receives a new `flame_damage_fx` thread regardless of its fire state.

The correct code should be `if ( !is_true( e_target.is_on_fire ) )`.

**Thread cost breakdown:**

The AoE loop creates two categories of threads:

1. **Ticks 2–25 — zombie already on fire** (`was_on_fire = true`): thread reads the flag, deals impact damage, and returns immediately. Cost is negligible (a few scrVar slots for < 1 frame).

2. **Tick 1 — zombie hit for the first time** (`was_on_fire = false`): thread sets `self.is_on_fire = 1`, then spawns three long-lived sub-threads on the zombie:
   - `zombie_set_and_restore_flame_state()` — blocks on `waittill("stop_flame_damage")`, lives up to **8 seconds**
   - `flame_damage_over_time()` — loops every second, ends on `"stop_flame_damage"`, lives up to **8 seconds**
   - `on_fire_timeout()` — `wait 8`, then `notify("stop_flame_damage")`, lives **8 seconds**

With 24 zombies and the tier-3 staff (3 projectiles per shot via `fire_additional_shots`), a single shot creates:

- 3 projectiles × 25 ticks × 24 zombies = **1,800 threads spawned**
- 3 projectiles × 24 zombies × 3 sub-threads = **216 threads running concurrently for 8 seconds**

Each long-lived thread frame holds ~5–8 local scrVar slots. At peak: **216 frames × ~7 slots ≈ 1,512 concurrent scrVar slots** consumed by fire state management alone, per shot.

At high rounds (24+ zombies present, player firing rapidly), multiple AoE windows overlap, keeping these frames continuously active. If zombies survive more than 8 seconds, they can be re-ignited, restarting the 3-thread set and sustaining the pressure indefinitely.

**Why the crash is round-gated — the multi-shot stacking mechanism:**

This is the key causal link between round number and crash frequency. At low rounds, a charged shot one-shots every zombie in range. The `flame_damage_fx` threads terminate almost immediately after the zombie dies — the long-lived sub-threads (`zombie_set_and_restore_flame_state`, `flame_damage_over_time`, `on_fire_timeout`) are cut short by the kill. Thread frames are freed quickly, pool pressure dissipates before the next shot. A second charged shot fires into a clean (or near-clean) pool.

At high rounds, the same shot does not kill. All three long-lived sub-threads per zombie per projectile run to their full 8-second lifetime because the zombie is still alive. The player fires a second shot — necessary now to kill — on top of the first batch of threads, which are still running. Then a third shot. Then a fourth. By the time three or four charged shots are active simultaneously, the overlapping thread sets from all of them are holding the pool concurrently. The crash is not caused by firing too fast — it is caused by the weapon requiring multiple shots at high rounds, which makes overlapping thread lifetimes structurally unavoidable.

This is reproducible and round-gated: at round 44 the weapon can still one-shot, threads clean up between shots, no crash. At round 80 each shot requires three or four follow-up shots to kill, threads from all active shots overlap for the full 8-second window, pool saturates, game terminates. The round 70–74 "put it down" rule the community follows is the empirical trace of exactly this threshold.

**Contrast with other staves:** The Air Staff (`_zm_weap_staff_air.gsc`) correctly guards per-zombie operations using `a_zombies[i].is_mechz` on the zombie entity, and `whirlwind_drag_zombie` returns early if `self.e_linker` is already defined — preventing duplicate processing. No other staff has this missed-guard pattern.

**Impact:** Unlike SA-08/SA-09 (permanent monotonic accumulation), SA-10 creates **burst concurrent pressure** rather than a steadily growing baseline. The burst pressure is itself round-gated: at low rounds, short thread lifetimes (kills terminate threads quickly) prevent meaningful overlap between shots. At high rounds, long thread lifetimes (no kills, threads run 8 seconds) cause shots to stack. Combined with the SA-08/SA-09 baseline depletion already present at high rounds, the overlapping thread sets from three to four concurrent shots push the pool past its limit.

**Fix:** Change line 143 from `self.is_on_fire` to `e_target.is_on_fire`. The function is compiled into `zm_tomb.ff` and is called directly from compiled code (`e_projectile thread fire_staff_area_of_effect(...)`), so it cannot be replaced from an addon script — the same FF replacement limitation that applies to IL-01. The SA-08 component (see SA-11 below) is addressable via `zm_patch_scrvar.gsc`.

**Broader pattern — thread accumulation as a crash class (future video scope):**

SA-10 is the cleanest known example of a wider crash class in BO2 Zombies: a game action that spawns threads which live longer than the action's lifetime, causing cumulative pool pressure when the action is repeated. The same crash signature (`exceeded maximum number of child server script variables` or engine-level termination on pool exhaustion) appears in other maps for different reasons. Die Rise elevators produce a structurally similar effect: elevator-related threads (`elevator_roof_watcher` and associated zombie state threads) stack during high-round play in ways that compound pool pressure. The community has historically attributed these crashes to general "high round instability" without a specific mechanism. SA-10 provides a clear documented example of exactly what that mechanism is — a thread that is not correctly scoped to its triggering action's lifetime. This will be covered in a dedicated video on the BO2 ScrVar crash class.

---

## SA-11: Fire Staff upgrade tiers multiply SA-08 weapon-string accumulation (MEDIUM, Origins only)

**File:** `_zm_weap_staff_fire.gsc` (precache), `_zm_weapons.gsc:411`

```gsc
// precache() in _zm_weap_staff_fire.gsc
precacheitem( "staff_fire_melee_zm" );

// Weapon names generated as player upgrades the staff:
// staff_fire_zm           (base, received from buildable)
// staff_fire_upgraded_zm  (after puzzle 1 + soul collection)
// staff_fire_upgraded2_zm (after puzzle 2 + soul collection)
// staff_fire_upgraded3_zm (after final upgrade)
// staff_fire_melee_zm     (melee variant, separate weapon slot)
```

**Mechanism:** Each upgrade tier is a distinct weapon name. Because the upgrade path **replaces** the weapon (takeweapon / giveweapon), the player generates a `weapon_change` event for each tier transition. `watchweaponchangezm()` adds any new weapon string to `self.hitsthismag[weapon]` on first encounter. The 4 fire staff tier names plus the melee name produce up to **5 permanent entries** in `self.hitsthismag` per player, on top of all box weapons.

On Origins, all four elemental staves follow the same multi-tier pattern:

| Staff | Tier names |
|---|---|
| Fire | `staff_fire_zm`, `staff_fire_upgraded_zm`, `staff_fire_upgraded2_zm`, `staff_fire_upgraded3_zm`, `staff_fire_melee_zm` |
| Air | `staff_air_zm`, `staff_air_upgraded_zm`, `staff_air_upgraded2_zm`, `staff_air_upgraded3_zm`, `staff_air_melee_zm` |
| Water | `staff_water_zm`, `staff_water_upgraded_zm`, `staff_water_upgraded2_zm`, `staff_water_upgraded3_zm`, `staff_water_melee_zm` |
| Lightning | `staff_lightning_zm`, `staff_lightning_upgraded_zm`, `staff_lightning_upgraded2_zm`, `staff_lightning_upgraded3_zm`, `staff_lightning_melee_zm` |

A player who fully upgrades all four staves generates up to **20 additional permanent `hitsthismag` entries** — roughly double the per-player accumulation rate compared to a Tranzit session of the same length with equivalent box cycling.

**Impact:** Origins sessions are inherently longer than Tranzit (Easter egg, challenges, four staves to build and upgrade). More play time × more weapon strings per unit of play time = faster SA-08 pool depletion. Combined with SA-10's burst pressure, Origins players hit the scrVar ceiling substantially earlier than Tranzit players.

**Fix:** The existing `zm_patch_scrvar.gsc` patch (`svp_prune_player()` at round start) already addresses this — stale staff weapon strings for tiers the player no longer holds are pruned just as any other discarded weapon string. No additional fix needed, but the patch's benefit is proportionally larger on Origins than on any other map due to the volume of staff tier names.
