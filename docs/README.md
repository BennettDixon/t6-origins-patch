# BO2 Zombies GSC Code Audit

Full audit of the decompiled Black Ops 2 GSC scripts, focused on identifying issues that cause crashes, soft-locks, and instability during high-round play (round 100+).

## Scope

Files analyzed (all under `ZM/Maps/Tranzit Diner/maps/mp/zombies/`):

| File | Lines | Role |
|------|-------|------|
| `_zm.gsc` | 5,435 | Core zombies round logic, spawning, health, failsafe |
| `_zm_magicbox.gsc` | 1,531 | Mystery box weapon selection, entity management |
| `_zm_weapons.gsc` | 2,726 | Weapon systems, attachments, grenades, Pack-a-Punch |
| `_zm_spawner.gsc` | 3,054 | Zombie spawn/rise animations, damage/death events |
| `_zm_utility.gsc` | 5,065 | Shared helpers, HUD, sound, entity checks, flags |
| `_zm_powerups.gsc` | 2,789 | Powerup drops, effects, timers (nuke, insta-kill, etc.) |
| `_zm_stats.gsc` | 1,011 | Stat tracking and persistence |

Map-specific variants (Origins `_zm_magicbox_tomb.gsc`, Mob of the Dead `_zm_magicbox_prison.gsc`, etc.) share the same core patterns and are affected by the same classes of bugs.

## Summary of Findings

**25 distinct issues** identified across 7 severity tiers.

### By Category

| Category | Count | Worst Severity | Doc |
|----------|-------|---------------|-----|
| [Entity Leaks](./entity-leaks.md) | 8 | CRITICAL | Spawned entities never deleted on thread termination |
| [Infinite Loops](./infinite-loops.md) | 3 | CRITICAL | Missing loop increments, degenerate exit conditions |
| [Integer/Float Overflow](./overflow-issues.md) | 5 | HIGH | Uncapped counters, exponential growth, precision loss |
| [State Accumulation](./state-accumulation.md) | 4 | MEDIUM | Arrays and counters that grow without cleanup |
| [Race Conditions & Logic Bugs](./race-conditions.md) | 3 | MEDIUM | Shared globals, variable name typos, iteration bugs |
| [Misc / Low Severity](./misc-issues.md) | 2 | LOW | Performance, HUD stacking |

### By Severity

| Severity | Count | Description |
|----------|-------|-------------|
| CRITICAL | 5 | Will crash or freeze the game |
| HIGH | 5 | Degrades over time, eventually fatal |
| MEDIUM | 10 | Contributes to instability, incorrect behavior |
| LOW | 5 | Theoretical or cosmetic |

## Root Cause of High-Round Crashes

The crashes that occur deep into long games (round 100+) are almost certainly driven by **entity exhaustion**. The BO2 engine has a hard entity limit (~1024 total `script_origin`, `script_model`, triggers, etc.). Three functions leak a `script_origin` entity every time a zombie dies mid-animation:

1. **`lerp()`** in `_zm_utility.gsc:53` — zombie dies during window-attack
2. **`do_zombie_rise()`** in `_zm_spawner.gsc:2776` — zombie dies during ground-rise animation
3. **`do_zombie_spawn()`** in `_zm_spawner.gsc:2612` — zombie dies during spawn movement

At high rounds, zombie throughput is enormous (thousands per round) and deaths mid-animation are frequent due to traps, Insta-Kill, splash damage near barriers, etc. Each leaked entity is permanent for the session. Once the engine hits its ceiling, it crashes.

The correlation with **box hits** and **grenades** exists because:
- Box hits spawn additional entities (weapon models, FX, triggers) that compete for the same entity budget
- Grenades cause splash kills on rising/spawning zombies, accelerating the leak rate
- The box code itself has entity leak paths (`box_locked` orphaning, timeout race conditions)

## Highest-Impact Fixes

If patching via GSC injection on RGH, these four changes would have the biggest effect:

### 1. Add death cleanup to `lerp()` (Biggest single fix)
Add `self endon("death")` and wrap the spawn/delete in a death handler so the `script_origin` is always cleaned up.

### 2. Fix anchor cleanup in `do_zombie_rise()` / `do_zombie_spawn()`
Thread a death watcher that deletes `self.anchor` if the zombie dies before the animation completes.

### 3. Fix `has_attachment()` infinite loop
Add the missing `idx++` increment in the while loop at `_zm_weapons.gsc:1730`.

### 4. Cap powerup drop increment
Clamp `zombie_powerup_drop_increment` to prevent float overflow after hundreds of drops.

These four patches alone would likely push the crash ceiling from ~round 100-150 out to round 500+ or beyond, depending on map and player count.

## Project Status

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Research and static analysis | **Complete** — 25 issues documented across 6 categories |
| 1 | Toolchain setup (gsc-tool, build pipeline) | **Complete** — compiling on macOS, deploying to Plutonium |
| 2a | Diagnostics HUD (`zm_diagnostics.gsc`) | **Complete** — entity probe, round tracker, accumulation monitor |
| 2b | Stress test tool (`zm_stress_test.gsc`) | **Complete** — round skip, entity fill, variable manipulation |
| 2c | Baseline testing on Plutonium | **In progress** — test protocol written, awaiting runtime |
| 3 | Patch scripts (entity leaks, loops, overflows) | Pending |
| 4 | Blog series | Pending |

### Custom Scripts

All scripts compile successfully via `build.sh`:

- **`zm_diagnostics.gsc`** (5,639 bytes) — Live HUD overlay showing entity headroom, round state, accumulation counters, overflow risk indicators, and entity ceiling warnings. Probes entity headroom every 5 seconds. Logs round-start snapshots to console.
- **`zm_stress_test.gsc`** (6,413 bytes) — Chat-command tool for rapid hypothesis testing. Skip to any round, kill all zombies, fill/drain entity slots, manipulate scores and counters, toggle god mode. Commands via `/st <cmd>` in game chat.
- **`zm_test.gsc`** (1,018 bytes) — Hello world script to verify the compilation and loading pipeline.

See `research/04-toolchain-setup.md` for full toolchain documentation and `research/test-results/test-protocol.md` for the testing methodology.

## How to Use These Docs

Each subdocument contains:
- The exact file path and line numbers for every issue
- The relevant code snippet
- An explanation of the mechanism
- Why it matters at high rounds specifically
- Suggested fix approach where applicable

The line numbers reference the decompiled GSC as it exists in this repo. If the decompiler version or game update differs, search for the function names instead.
