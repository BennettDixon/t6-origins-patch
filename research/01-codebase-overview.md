# BO2 GSC Codebase Overview

A map of the Black Ops 2 scripting architecture — what GSC is, how the engine executes it, and how the ~2,000 files in this repository fit together.

## What is GSC?

GSC (Game Script Code) is Treyarch's scripting language for Call of Duty. It's a C-like language that compiles to bytecode and runs on a virtual machine inside the game engine. It handles game logic, spawning, AI behavior, HUD, scoring, and most gameplay mechanics. The native engine (C++) handles rendering, physics, networking, and low-level systems.

GSC is **not** a general-purpose language. It's tightly integrated with the engine and relies heavily on built-in functions (`spawn()`, `getentarray()`, `dodamage()`, etc.) that are implemented in native code.

### Key Language Features

**Cooperative multitasking:** GSC is single-threaded but supports cooperative concurrency through `thread`, `waittill`, `notify`, and `endon`. A thread yields control when it hits a `wait`, `waittill`, or similar blocking call. There is no preemptive scheduling — a tight loop with no `wait` will freeze the entire game.

```gsc
// Thread A spawns Thread B, both run concurrently
init()
{
    thread monitor_round();   // starts a new thread
    thread monitor_zombies(); // starts another
}

monitor_round()
{
    while (true)
    {
        level waittill("end_of_round");  // yields until notified
        // ... do round-end logic ...
    }
}
```

**`endon` — thread termination:** A thread can register to terminate when a specific notification fires. This is used extensively for cleanup but is also the source of many entity leak bugs:

```gsc
do_something()
{
    self endon("death");  // if self dies, this thread terminates HERE
    link = spawn("script_origin", self.origin);  // entity allocated
    // ... do work ...
    link delete();  // never reached if endon fires above
}
```

**`notify` / `waittill` — event system:** Entities and the `level` object can send and receive named events. This is the primary coordination mechanism between threads.

**No garbage collection for entities:** GSC has automatic memory management for script variables (strings, arrays, structs), but **game entities** (`script_origin`, `script_model`, triggers) allocated via `spawn()` are not garbage collected. They must be explicitly `delete()`-ed. An entity that loses all script references is permanently leaked until the game session ends.

### File Types

- **`.gsc` (server-side):** Game logic, AI, spawning, scoring, round management. Runs on the host/server.
- **`.csc` (client-side):** Effects, HUD updates, animations, client-side rendering. Runs on each client.

Server crashes in zombies are caused by `.gsc` code, which is why our analysis focuses there.

## Repository Structure

```
t6-scripts/
├── MP/                              # Multiplayer (not analyzed)
│   ├── Core/                        # Shared MP systems
│   ├── Factions/                    # Team/faction definitions
│   └── Maps/                        # 32 MP maps
├── ZM/                              # Zombies (our focus)
│   ├── Core/                        # Shared ZM systems (minimal)
│   └── Maps/                        # 7 zombies maps
│       ├── Tranzit/                 # TranZit (bus map)
│       ├── Tranzit Diner/           # Town/Farm/Diner (+ CORE SYSTEMS)
│       ├── Mob of the Dead/         # Alcatraz
│       ├── Buried/                  # Underground town
│       ├── Die Rise/                # Skyscrapers
│       ├── Nuketown/                # Nuketown zombies
│       └── Origins/                 # WWI, staffs
├── scripts/                         # Our custom GSC scripts (source)
│   ├── zm_test.gsc                  # Hello world / pipeline verification
│   ├── zm_diagnostics.gsc           # Entity/state monitoring HUD
│   └── zm_stress_test.gsc           # Round accelerator and testing tool
├── docs/                            # Audit findings documentation
├── research/                        # Research log and methodology
├── build.sh                         # Compilation script (uses gsc-tool)
├── compiled/                        # gsc-tool output (gitignored)
└── tools/                           # gsc-tool binary (gitignored)
```

### Why Tranzit Diner Contains the Core

The `ZM/Maps/Tranzit Diner/` directory contains not just the Diner survival map, but the **shared core zombies systems** that all maps include. This is a Treyarch convention — the first map in the DLC cycle hosts the core scripts, and subsequent maps extend them. The critical files are:

```
ZM/Maps/Tranzit Diner/maps/mp/zombies/
├── _zm.gsc                  # Round logic, spawning pipeline, health, failsafe
├── _zm_magicbox.gsc         # Mystery box
├── _zm_weapons.gsc          # Weapon systems, PaP, grenades
├── _zm_spawner.gsc          # Zombie spawn/rise animations, death events
├── _zm_utility.gsc          # Shared helpers (HUD, sound, entity checks, flags)
├── _zm_powerups.gsc         # Powerup drops and effects
├── _zm_stats.gsc            # Stat tracking
├── _zm_ai_basic.gsc         # Basic zombie AI
├── _zm_ai_dogs.gsc          # Hellhound AI
├── _zm_perks.gsc            # Perk machines
├── _zm_blockers.gsc         # Barriers/doors
├── _zm_equipment.gsc        # Equipment system
├── _zm_buildables.gsc       # Craftable items
├── _zm_zonemgr.gsc          # Zone/area management
├── _zm_laststand.gsc        # Down/revive system
├── _zm_score.gsc            # Point system
├── _zm_power.gsc            # Power switch
├── _zm_unitrigger.gsc       # Trigger system
└── ... (40+ more files)
```

Map-specific files extend the core. For example:
- `Origins/maps/mp/zombies/_zm_magicbox_tomb.gsc` — extends the base magic box with Origins-specific behavior (Dig Site locations, staff drops)
- `Mob of the Dead/maps/mp/zombies/_zm_afterlife.gsc` — adds the Afterlife mechanic unique to that map

**All maps share the same entity leak, overflow, and infinite loop bugs** because those bugs live in the core files.

## The Include System

GSC uses `#include` directives that work like C's `#include` — they make functions from the included file available for calling. The paths use backslash separators:

```gsc
#include common_scripts\utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_spawner;
```

The `_zm.gsc` core file includes 40+ other modules, creating a deeply interconnected dependency graph. This is important for modding because Plutonium's script loading lets custom scripts include and override functions from these modules.

## The Entity Model

Understanding the entity model is critical because entity leaks are the primary crash cause.

### Entity Types

| Type | Created By | Purpose |
|------|-----------|---------|
| `script_origin` | `spawn("script_origin", origin)` | Invisible point for linking, movement anchors, sound playback |
| `script_model` | `spawn("script_model", origin)` | Visible model (weapons in box, pandora light, etc.) |
| `trigger_radius` | `spawn("trigger_radius", ...)` | Invisible touch trigger |
| AI actors | `spawnactor(...)` / recycled from pool | Zombies, dogs, Brutus, etc. |

### Entity Lifecycle

```
spawn() --> entity exists, consumes a slot
  |
  v
[used by game logic]
  |
  v
delete() --> entity destroyed, slot freed
```

If `delete()` is never called (because the thread that would call it was terminated by `endon`, or because a `waittill` never fires), the entity slot is permanently consumed.

### The Entity Limit

The engine has a hard limit on total concurrent entities. Community consensus is ~1024 for script entities (separate from AI actor limits). When this limit is reached:
- New `spawn()` calls fail (return `undefined` or crash)
- The game becomes unstable or crashes outright

**This has not been verified at runtime yet** — the entity headroom probe in `zm_diagnostics.gsc` is built to measure this. It spawns `script_origin` entities until `spawn()` fails, counting the remaining slots. The `/st fill` command in `zm_stress_test.gsc` can also push the limit directly.

### AI Actor Limits

Separate from script entities, there's a limit on concurrent AI actors (zombies). The game manages this through `level.zombie_vars["zombie_ai_limit"]`, typically set to 24. The spawning pipeline in `_zm.gsc` respects this limit — it never spawns more than 24 zombies at once. Instead, it queues zombies in `level.zombie_total` and spawns them as active ones die.

The per-round zombie count is calculated in `round_spawning()` (`_zm.gsc:2928`) and grows quadratically with round number. At round 255 with 4 players, the total for a single round exceeds 35,000 — but only 24 exist at any given time.

## Execution Flow

### Game Start

```
_zm.gsc::init()
  ├── Sets level variables and dvars
  ├── Initializes subsystems (weapons, perks, powerups, etc.)
  ├── Registers callbacks
  └── Threads round_think()

round_think()  [main game loop]
  └── for each round:
      ├── ai_calculate_health(round_number)
      ├── round_spawning()  [spawn all zombies for this round]
      ├── round_wait()      [wait for all zombies to die]
      └── round_over()      [cleanup, advance to next round]
```

### Zombie Lifecycle

```
round_spawning() picks a spawner
  └── zombie_spawn() creates/recycles an AI actor
      └── do_zombie_spawn()
          ├── spawns script_origin anchor (LEAK RISK)
          ├── moves zombie to spawn position
          └── deletes anchor (if not killed first)
              └── OR do_zombie_rise()
                  ├── spawns script_origin anchor (LEAK RISK)
                  ├── plays rise animation
                  └── deletes anchor (if not killed first)

zombie is active in the world
  └── can attack barriers via lerp()
      ├── spawns script_origin link (LEAK RISK)
      ├── animates to barrier
      └── deletes link (if not killed first)

zombie dies
  └── zombie_death_event()
      ├── increments kill counters (never reset)
      ├── may trigger ragdoll (2.35s entity linger)
      └── slot becomes available for next spawn
```

The three "LEAK RISK" points are where the entity leak bugs live. Each one spawns a `script_origin` that can be orphaned if the zombie dies mid-animation.

## Key Global Variables

These are the `level.` variables most relevant to high-round stability:

| Variable | Purpose | Issue |
|----------|---------|-------|
| `level.round_number` | Current round (capped at 255) | Cap prevents overflow but creates infinite loop at 255 |
| `level.zombie_total` | Zombies remaining to spawn this round | Grows to 35,000+ at round 255 |
| `level.zombie_health` | Current zombie HP | Overflows at ~round 163 |
| `level.zombie_move_speed` | Zombie speed | 255 * 8 = 2040 at cap |
| `level.zombie_total_subtract` | Failsafe recycle counter | Never reset, grows indefinitely |
| `level.zombie_vars["zombie_powerup_drop_increment"]` | Powerup drop threshold | Multiplied by 1.14 each drop, exponential growth |
| `level.chest_accessed` | Box hit counter | Never reset on single-box maps |
| `level.global_zombies_killed` | Total kills | Never reset |
| `level.active_powerups` | Array of active powerup entities | Can contain stale refs |

## What Can and Can't Be Fixed From GSC

### Fixable from GSC (via Plutonium script injection)
- Entity leak cleanup (threading death watchers)
- Infinite loop fixes (adding increments, attempt limits)
- Counter resets between rounds
- Overflow clamping (health caps, score handling)
- Logic bug fixes (variable name typos, array iteration)

### NOT fixable from GSC
- Native engine entity limit (hard-coded in C++)
- AI actor pool size
- Memory allocator behavior
- Network protocol issues
- Rendering/physics bugs
- Sound engine callback failures (can only add timeouts as workarounds)

Our patches target everything in the first category. The second category would require binary patching of the XEX/EXE — a different project.
