# GSC Hooking Techniques on Plutonium T6

How Plutonium loads custom scripts, what hooks are available, techniques for overriding base game behavior, and limitations -- documented from building `zm_test.gsc`, `zm_diagnostics.gsc`, and `zm_stress_test.gsc`.

## How Plutonium Loads Custom Scripts

Custom compiled scripts placed in `%localappdata%\Plutonium\storage\t6\scripts\zm\` are loaded **alongside** (not replacing) the base game scripts. Each custom script's `init()` function runs after the base game's initialization chain completes.

Key implications:
- We can **add** new behavior (thread new functions, register callbacks)
- We can **override** `level.` variables and function references after init
- We **cannot** directly replace a function that has already been called or threaded during base init
- Multiple custom scripts can coexist -- each gets its own `init()` called independently

Scripts must:
- Have an `init()` entry point (the engine calls this automatically)
- Be compiled to T6 bytecode via `gsc-tool -m comp -g t6 -s pc`
- Use the `zm_` filename prefix for zombies mode

Reloading without restarting: `map_restart` in the Plutonium console reloads all scripts. Bind it for fast iteration: `bind P "map_restart"`.

## Script Entry Points and Lifecycle

### init() Timing

Our `init()` runs after the base game has already:
- Set up `level.zombie_vars[]` (health, speed, spawn delay, etc.)
- Initialized the entity system and spawn locations
- Registered base callbacks
- Set `level.zombie_team`, `level.zombie_ai_limit`, `level.zombie_actor_limit`

But **before**:
- Any player has connected or spawned
- `round_think()` has started the first round
- `flag("start_zombie_round_logic")` is set

This means our `init()` is the right place to:
- Override function pointers (`level.round_spawn_func`, etc.)
- Thread background monitors (entity probe, round tracker)
- Set up the player connect listener

### Player Connect/Spawn Pattern

The standard pattern for per-player initialization, verified working across all three scripts:

```gsc
init()
{
    level thread on_player_connect();
}

on_player_connect()
{
    for (;;)
    {
        level waittill("connected", player);
        player thread on_player_spawned();
    }
}

on_player_spawned()
{
    self endon("disconnect");

    for (;;)
    {
        self waittill("spawned_player");
        // per-player logic here
    }
}
```

The `"connected"` event fires once per player join. The `"spawned_player"` event fires each time a player spawns (initial spawn, respawn after bleedout, etc.). The `endon("disconnect")` ensures the thread cleans up if the player leaves.

### Chat Command Listener

Plutonium T6 exposes chat messages as level events:

```gsc
level waittill("say", player, message);
```

Where `player` is the entity who typed the message and `message` is the full string. This runs on the server thread, so commands execute with full access to game state. We use this in `zm_stress_test.gsc` with `/st` prefixed commands.

The message includes the full `say` text. Use `strtok(message, " ")` to split into arguments. `issubstr()` works for prefix matching.

## Hook Points in Base Game Scripts

### Function Pointer Overrides

The base game stores many behaviors as function pointers on `level.` that can be replaced in our `init()`:

| Variable | Default | What it controls |
|----------|---------|-----------------|
| `level.round_spawn_func` | `::round_spawning` | How zombies spawn each round |
| `level.round_wait_func` | `::round_wait` | When a round is considered "complete" |
| `level.round_think_func` | `::round_think` | The main round loop |
| `level.round_prestart_func` | undefined | Custom logic before round starts |
| `level.round_start_custom_func` | undefined | Custom logic at round start |
| `level.round_end_custom_logic` | undefined | Custom logic at round end |
| `level.zombie_round_change_custom` | undefined | Override round transition animation |
| `level.custom_ai_spawn_func` | undefined | Per-zombie spawn hook |
| `level.max_zombie_func` | (varies) | Controls zombie count per round |

These are set in `_zm.gsc`'s `round_start()` and `round_think()`. Since our `init()` runs before `round_start()`, overrides take effect for the first round.

### Callback Registration

The base game provides `onplayerconnect_callback(func)` and `onplayerdisconnect_callback(func)` via `_zm_utility.gsc` for registering callbacks without replacing the connect handler. These call `addcallback()` internally.

### Notification Events

Key `level notify()` events we can `waittill()` on:

| Event | When it fires |
|-------|--------------|
| `"connected"` | Player joins (passes player entity) |
| `"start_of_round"` | New round begins spawning |
| `"end_of_round"` | All zombies killed, round ending |
| `"between_round_over"` | Between-round intermission complete |
| `"end_game"` | Game over triggered |
| `"intermission"` | Intermission started |
| `"zombie_total_set"` | Zombie count for round is determined |
| `"say"` | Chat message (passes player, message) |

Player-level events (`self waittill()`):

| Event | When it fires |
|-------|--------------|
| `"spawned_player"` | Player spawns/respawns |
| `"disconnect"` | Player leaves |
| `"death"` | Player enters last stand |
| `"player_downed"` | Player downed |
| `"bled_out"` | Player bled out |

## Techniques for Overriding Base Functions

### Method 1: Function Pointer Override

If the base game calls a function through a `level.` variable:
```gsc
[[ level.round_wait_func ]]();
```

We replace it in our `init()`:
```gsc
init()
{
    level._orig_round_wait = level.round_wait_func;
    level.round_wait_func = ::our_round_wait;
}

our_round_wait()
{
    // Custom logic before
    [[ level._orig_round_wait ]]();
    // Custom logic after
}
```

This is the cleanest approach. We can chain the original function to preserve base behavior while adding our own.

### Method 2: Thread Watchdog

For behavior we can't intercept via function pointers, we thread a background monitor:

```gsc
init()
{
    level thread entity_leak_watchdog();
}

entity_leak_watchdog()
{
    level endon("end_game");

    for (;;)
    {
        wait 5;
        // Probe entity headroom, log state, clean up leaks
    }
}
```

Used in `zm_diagnostics.gsc` for the entity headroom probe (`diag_entity_probe_loop`) and the round-start logger (`diag_round_tracker`).

### Method 3: Per-Entity Death Handler

Attach a cleanup thread to entities when they spawn. The thread waits for death/deletion and ensures associated entities are cleaned up:

```gsc
zombie thread death_cleanup_handler();

death_cleanup_handler()
{
    self waittill("death");
    // Clean up any script_origin entities linked to this zombie
}
```

This is the approach planned for the entity leak patches -- attaching watchdogs to zombie spawns that ensure `lerp()` origins, rise struct origins, and spawn anchors get deleted even if `endon("death")` terminates the owning thread prematurely.

### Method 4: Variable Clamping

For overflow and accumulation issues, periodically clamp values:

```gsc
init()
{
    level thread overflow_watchdog();
}

overflow_watchdog()
{
    level endon("end_game");

    for (;;)
    {
        wait 10;

        if (isdefined(level.zombie_vars["zombie_powerup_drop_increment"]))
        {
            if (level.zombie_vars["zombie_powerup_drop_increment"] > 100000)
                level.zombie_vars["zombie_powerup_drop_increment"] = 100000;
        }
    }
}
```

Simple but effective for values that grow without bound. The clamp interval should be longer than the game's update rate for that value to avoid excessive polling.

## Verified Capabilities

From building the three scripts, the following are confirmed working at compile time (runtime verification pending on Plutonium):

| Capability | Script | Status |
|------------|--------|--------|
| HUD creation with `newclienthudelem()` | zm_test, zm_diagnostics | Compiles |
| `settext()` with string concatenation | zm_diagnostics | Compiles |
| `spawn("script_origin", pos)` + `delete()` | zm_diagnostics | Compiles |
| `getaiarray(team)` for AI counting | zm_diagnostics | Compiles |
| `level waittill("say", ...)` for chat commands | zm_stress_test | Compiles |
| `strtok()` for argument parsing | zm_stress_test | Compiles |
| `dodamage()` on AI entities | zm_stress_test | Compiles |
| `enableinvulnerability()` / `disableinvulnerability()` | zm_stress_test | Compiles |
| Direct manipulation of `level.zombie_vars[]` | zm_stress_test | Compiles |
| `setroundsplayed()` | zm_stress_test | Compiles |
| `level notify("end_of_round")` to force round end | zm_stress_test | Compiles |
| `iprintln()` for in-game console output | zm_stress_test | Compiles |

## Limitations Discovered

### Compile-Time

- **No runtime type checking:** `int()` cast on a string that isn't numeric may silently produce 0. Our chat command parser relies on this (invalid `/st skip abc` becomes `/st skip 0`).
- **No string formatting:** GSC has no `sprintf`. Dynamic text must be built with `+` concatenation, which auto-converts numbers to strings. This works but is verbose.
- **Include resolution is deferred:** `#include` directives are recorded but not validated at compile time. A typo in an include path compiles fine but crashes at load time on the game.

### Architectural

- **Cannot replace already-threaded functions:** If `round_think()` is already running by the time our `init()` executes, we can't replace it mid-execution. We can only override function pointers that haven't been called yet, or that are re-read each time (like `level.round_spawn_func` which is called fresh each round).
- **Cannot intercept engine builtins:** Functions like `spawn()`, `delete()`, `dodamage()` are native engine calls. We can't wrap or override them -- only observe their effects.
- **Single-threaded cooperative:** GSC uses cooperative multitasking. A `wait` or `waittill` yields control. A tight loop without `wait` blocks the entire game. This is why `has_attachment()`'s missing increment is fatal -- it blocks the VM permanently.
- **Entity limit is engine-enforced:** The ~1024 entity ceiling is a hard limit in the native engine. GSC can only manage entities within that limit, not expand it.

## What Can't Be Fixed from GSC

Some issues exist below the scripting layer and would require binary patches to the game executable:

- Expanding the entity limit beyond ~1024
- Changing the underlying data types (int32 to int64 for scores)
- Fixing native memory leaks in the render/audio engines
- Modifying the GSC VM's stack size or thread limits

Our approach works around these by keeping values within safe ranges (clamping) and preventing the conditions that trigger the limits (cleanup watchdogs).
