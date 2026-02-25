# BO2 Origins High-Round Fix

Fixes crashes, freezes, and instability on the Origins (zm_tomb) map in Call of Duty: Black Ops 2 Zombies during high-round play (round 100+). Designed for use with the [Plutonium T6](https://plutonium.pw/) client.

This is a focused release covering Origins and core script fixes. A broader all-maps patch is planned separately.

## What This Fixes

### Staff Weapon Fixes

| ID | File | Bug | Effect |
|----|------|-----|--------|
| SA-10 | `_zm_weap_staff_fire.gsc` | Fire Staff AoE checks `self.is_on_fire` instead of `e_target.is_on_fire` | Every zombie in AoE gets re-threaded with burn damage every tick — causes massive thread buildup and server lag at high rounds |
| MI-06 | `_zm_weap_staff_air.gsc` | Wind Staff whirlwind anchors to `a_zombies[0]` (possibly dead) instead of `a_zombies[i]` (first alive) | Whirlwind attaches to dead zombie — invisible/unkillable zombie, round won't end |
| FRZ-01 | `zm_tomb_utility.gsc` | `+128` health addition loses precision at float32 limits | Zombies become unkillable at extreme high rounds due to float rounding |
| FRZ-02 | `_zm_weap_staff_water.gsc` | Ice Staff blizzard end notify hook | Diagnostic hook for blizzard state tracking |

### Origins Map Fixes

| ID | File | Bug |
|----|------|-----|
| GEN-ZC-01/02/03 | `zm_tomb_capture_zones.gsc` | Generator spawn limiter dead variable + cleanup on redirect + attack point range off-by-one |
| GR-05 | `zm_tomb_giant_robot.gsc` | `stopanimscripted()` missing between robot walk segments — anim info slots leak every cycle |
| TANK-EL-01 | `zm_tomb_tank.gsc` | Run-over linker entity leak on player disconnect |
| TANK-TL-01 | `zm_tomb_tank.gsc` | Push-player thread leak on player disconnect |
| TANK-MI-01/02/03 | `zm_tomb_tank.gsc` | Flamethrower cone dead variable + identical distance bug + O(n) poll optimization |

### Core Fixes (affect all maps including Origins)

| ID | File | Bug |
|----|------|-----|
| EL-01 | `_zm_utility.gsc` | `lerp()` leaks a `script_origin` entity every zombie death mid-animation |
| IL-01 | `_zm_weapons.gsc` | `has_attachment()` missing `idx++` — infinite loop freeze |
| IL-02 | `_zm_weapons.gsc` | `random_attachment()` unbounded `while(true)` loop |

## Installation (Pre-built)

1. Copy `zone/mod.ff` to `%LOCALAPPDATA%\Plutonium\storage\t6\mods\zm_origins_fix\mod.ff`
2. Copy the addon scripts from `scripts/` to `%LOCALAPPDATA%\Plutonium\storage\t6\scripts\zm\`
3. In Plutonium, enable the `zm_origins_fix` mod before launching Origins

## Building from Source

### Prerequisites

- [gsc-tool](https://github.com/xensik/gsc-tool/releases) — extract into a `tools/` directory
- [OpenAssetTools (OAT)](https://github.com/Joelrau/OpenAssetTools) — for building the `.ff` fastfile
- A legitimate copy of Call of Duty: Black Ops II (for base game `.ff` files)

### Compile Addon Scripts

```bash
./build.sh        # macOS / Linux / WSL
.\build.ps1       # Windows PowerShell
```

### Build the Fastfile

```bash
./build_ff.sh
```

Compiles the 9 patched scripts from `patched/` into `mod.ff` using OAT's native T6 GSC compiler. Requires base game `.ff` files (`patch_zm.ff`, `common_zm.ff`, `zm_tomb.ff`) for dependency resolution.

### Deploy

```bash
./deploy.sh       # Addon scripts (WSL)
.\deploy.ps1      # Addon scripts (PowerShell)
.\deploy_ff.ps1   # Fastfile (PowerShell)
```

## Project Structure

```
scripts/          Addon GSC scripts (high-round patch, diagnostics, stress test)
patched/          Modified game scripts (9 files — 2 core + 7 Origins)
zone/             Pre-built mod.ff ready to install
zone_source/      Zone spec for OAT Linker
docs/             Technical documentation of bugs
research/         Methodology, findings, test results
blog/             Blog series about the project
```

## Diagnostic & Testing Tools

The addon scripts include diagnostic and stress-testing tools that run via Plutonium's developer console. These are the same tools used internally to find and verify the bugs documented in this project. We're releasing them as-is so players can test the fixes, reproduce the original bugs, skip to high rounds, and give themselves weapons for experimentation.

> **These tools are experimental and may be buggy.** They were built for internal development and testing, not as a polished player-facing feature. Some commands may not work perfectly in all situations — staff-giving commands in particular skip the normal crafting flow, so ammo counts, upgrade states, or visual effects may not match a legitimately-crafted staff. Round skipping can occasionally leave the game in an odd state. If something breaks, a `map_restart` in the console will reset things. We wanted to include them anyway because they're useful for anyone who wants to verify the fixes or push Origins to its limits.

### Enabling the HUD

The diagnostic HUD overlay is **off by default**. To enable it, run this in the Plutonium console (`~` key) **before** loading a map:

```
set diag_hud 1
```

This shows a live overlay with entity headroom, round number, zombie health, kill counts, and other internal counters. The HRP status indicator (patch telemetry) can be enabled independently:

```
set hrp_hud 1
```

### Console Commands

All commands are entered via the Plutonium console. The general pattern is:

```
set st_cmd <command>
set st_cmd "skip 50"          // command with argument (use quotes)
```

Or for two-part commands:

```
set st_arg 50
set st_cmd skip
```

#### General

| Command | Description |
|---------|-------------|
| `help` | Print all available commands in-game |
| `god` | Toggle god mode (invulnerability) |
| `perks` | Give Juggernog, Quick Revive, Speed Cola, Stamin-Up |
| `kill` | Kill all zombies on the map |
| `status` | Print current game state (round, entities, counters) |
| `openmap` | Force-open all doors and clear all debris |

#### Round Control

| Command | Description |
|---------|-------------|
| `skip <N>` | Instant jump to round N (kills current zombies, sets round number) |
| `ramp <N>` | Step to round N one round at a time with a 3s gap between each |
| `score <N>` | Set player score (default 250,000 if no argument) |
| `health <N>` | Set zombie health to N |

#### Origins Staffs

These commands give you upgraded staff weapons directly, bypassing the normal crafting/Easter Egg process. Useful for testing the SA-10, MI-06, and FRZ fixes without playing through 20+ rounds of setup.

| Command | Description |
|---------|-------------|
| `givestafffire` | Give the upgraded Fire Staff (Kagutsuchi's Blood) |
| `givestaffair` | Give the upgraded Wind Staff (Boreas' Fury) |
| `givestafflightning` | Give the upgraded Lightning Staff (Kimat's Bite) |
| `givestaffwater` | Give the upgraded Ice Staff (Ull's Arrow) |
> **Caveat:** The staff-give commands use `weapon_give()` directly, which doesn't run the full craftable pickup flow. The staffs work for combat testing (firing, AoE, damage) but some cosmetic or state details may differ from a legitimately crafted staff. For example, ammo might not match exactly, or certain visual effects tied to the crafting sequence may not trigger.

#### Giant Robot Testing

Origins has three giant robots that walk across the map on a timer. The GR-05 bug causes each walk cycle to permanently leak anim info table slots, eventually crashing the game. These commands let you force robot walks and measure whether the leak is fixed.

| Command | Description |
|---------|-------------|
| `roboforce` | Force a three-robot round (advances round to next multiple of 4) |
| `roboforce1` | Trigger a single-robot walk on the next cycle |
| `robosoak <N>` | Run N sequential single-robot walks and report each one |
| `animrobotleak` | Measure anim info entries leaked by one robot walk cycle |
| `animrobotleak <N>` | Measure leak over N consecutive walk cycles (cumulative) |
| `animrobotwatch` | Start a passive background watcher that probes after every walk automatically |
| `animrobotstat` | Print current watcher state (walks completed, headroom, total leaked) |
| `animrobotstop` | Stop the background watcher |
| `freezeround` | Freeze zombie spawning (useful for isolating robot walks from combat) |
| `thawround` | Resume zombie spawning |

**Typical workflow to verify GR-05 is patched:**

```
set st_cmd god
set st_cmd freezeround
set st_cmd animrobotwatch
set st_cmd roboforce
```

Then watch the console output after each walk cycle. With the patch applied, you should see `leaked_this_walk=0` every time. Without the patch, each walk leaks 2 anim info entries (6 per triple-robot round).

Run `set st_cmd help` in-game for the full list of commands, including additional bug-specific test commands for reproducing and verifying individual fixes.

## Blog Series

This project is documented in a narrative blog series covering the archaeology, analysis, and patching process:

- [Introduction](blog/00-introduction.md)
- [The Archaeology](blog/01-the-archaeology.md) — digging up a decade-old engine
- [Origins Fixed](blog/07-origins-patched.md) — the two weapons draining the server
- [Generators Patched](blog/10-generators-patched.md)
- [Tank Patched](blog/11-tank-patched.md)
- [Testing Origins Staffs](blog/12-testing-origins-staffs.md)
- [Frozen Rounds & Float32](blog/14-frozen-rounds-float32.md)

## Disclaimer

This project is not affiliated with, endorsed by, or connected to Activision, Treyarch, or any of their subsidiaries. "Call of Duty" and "Black Ops" are trademarks of Activision Publishing, Inc.

This project is provided for educational and research purposes — documenting and fixing bugs in a 13-year-old game that was never patched by the original developer. A legitimate copy of the game is required.

## License

The original code, documentation, and tooling in this repository are released under the [MIT License](LICENSE).

The patched game scripts in `patched/` are derived from Treyarch's original GSC code (decompiled via [gsc-tool](https://github.com/xensik/gsc-tool)) with bug fixes applied. These are provided under fair use for the purpose of interoperability and bug correction.
