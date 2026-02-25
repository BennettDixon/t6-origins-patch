# The Full Patch: Every Bug Found, Every Bug Fixed

*Part 9 of the BO2 High-Round Crash Fix series.
[Part 1](01-the-archaeology.md) | [Part 2](02-the-diagnostic-tools.md) | [Part 3](03-entity-leaks.md) | [Part 4](04-the-patch.md) | [Part 5](05-results.md) | [Part 6](06-fixing-the-core.md) | [Part 7](07-origins-patched.md) | [Part 8](08-die-rise-patched.md) | [Part 10](10-generators-patched.md) | [Part 11](11-tank-patched.md) | [Part 12](12-testing-origins-staffs.md)*

---

The project started with a question: why does Origins crash at 26 hours and Buried
at 120? The answer turned out to be twenty-three separate bugs, spread across four
compiled game files, none of which had been documented or fixed in the twelve years
since BO2 shipped.

Every one of them is now fixed.

---

## The Complete Bug List

| ID | Bug | File | Fix | Status |
|---|---|---|---|---|
| EL-01 | `lerp()` entity leak — `script_origin` not deleted when zombie dies mid-lerp | `_zm_utility.gsc` | Expose `link` as `self._lerp_link` before waittill; death watchdog cleans it up | ✅ Fixed |
| EL-02 | Anchor entity leak — zombie anchor not deleted on death | addon script | Death watchdog: `self.anchor delete()` on `"death"` notify | ✅ Fixed |
| EL-03 | Anchor entity leak — second assignment (same root cause as EL-02) | addon script | Same watchdog | ✅ Fixed |
| IL-01 | `has_attachment()` infinite loop — `idx` never incremented | `_zm_weapons.gsc` | `idx++` inside while body | ✅ Fixed — verified in-game |
| IL-02 | `random_attachment()` infinite loop — `while(true)` with unescapable exclude | `_zm_weapons.gsc` | Bounded loop (max 30 tries) | ✅ Fixed |
| IL-03 | Failsafe recycle loop — not triggered; insta-kill rounds complete naturally | indirect | Not triggered — zombies die from any hit during insta-kill rounds, ZQueue depletes normally | ✅ Not an issue |
| OF-01 | Zombie health int32 overflow → wraps negative → insta-kill rounds at ~R163+ | addon script | No fix applied — negative health causes zombies to die from any hit; this is accepted high-round community behavior | ➖ No fix needed |
| OF-02 | Score int32 overflow — powerup drops stop permanently | addon script | Cap `player.score_total` at 999,999,999 | ✅ Fixed |
| OF-03 | Drop increment float overflow — drops silently stop | addon script | Cap `zombie_powerup_drop_increment` at 50,000 | ✅ Fixed |
| SA-08 | `hitsthismag` weapon array accumulation — per-weapon scrVar leak | addon script | Prune to current weapons at round start | ✅ Fixed |
| SA-09 | `pack_a_punch_weapon_options` cache accumulation | addon script | Clear array at round start | ✅ Fixed |
| SA-10 | Fire Staff AoE dedup checks wrong entity — redundant thread burst | `_zm_weap_staff_fire.gsc` | `self.is_on_fire` → `e_target.is_on_fire` | ✅ Fixed |
| MI-06 | Wind Staff anchors to wrong (possibly dead) source zombie | `_zm_weap_staff_air.gsc` | `a_zombies[0]` → `a_zombies[i]` | ✅ Fixed |
| MI-11 | Die Rise elevator `continue` → logic error — `zombie_climb_elevator` never fires | `zm_highrise_elevators.gsc` | `continue` → `break` | ✅ Fixed |
| MI-12 | Die Rise `shouldsuppressgibs` polls all zombies × 7 volumes every cycle | `zm_highrise_elevators.gsc` | Per-zombie spawn threads with early exit | ✅ Fixed |
| GEN-ZC-01 | Origins generator `b_capture_zombies_needed` typo — per-zone limit never applied; 2–4× excess spawn attempts during multi-zone captures | `zm_tomb_capture_zones.gsc` | `b_capture_zombies_needed` → `n_capture_zombies_needed` | ✅ Fixed |
| GEN-ZC-02 | Origins capture zombie `ignore_player[]` not reset on generator redirect; disconnected player entries persist | `zm_tomb_capture_zones.gsc` | Clear `ignore_player` in `set_recapture_zombie_attack_target` | ✅ Fixed |
| GEN-ZC-03 | Origins attack point off-by-one — last slot of each 4-point pillar group never allocated | `zm_tomb_capture_zones.gsc` | `i < n_end` → `i <= n_end` in both range functions | ✅ Fixed |
| TANK-EL-01 | Origins tank: `e_linker` entity not deleted if player disconnects during 4s run-over drag | `zm_tomb_tank.gsc` | Expose linker via `self._tank_runover_linker`; disconnect watcher cleans it up | ✅ Fixed |
| TANK-TL-01 | Origins tank: `tank_push_player_off_edge` threads leak if player disconnects while on tank | `zm_tomb_tank.gsc` | Add `self endon("disconnect")` | ✅ Fixed |
| TANK-MI-01 | Origins tank: flamethrower cone check dot-products raw world position instead of direction vector | `zm_tomb_tank.gsc` | `vectordot(v_tag_fwd, ai_zombie.origin)` → `vectordot(v_tag_fwd, v_to_zombie)` | ✅ Fixed |
| TANK-MI-02 | Origins tank: stopped-tank zombie routing — identical distance expressions always route to back | `zm_tomb_tank.gsc` | Replace `level.vh_tank.origin` with `tank_front` / `tank_back` in each comparison | ✅ Fixed |
| TANK-MI-03 | Origins tank: `zombies_watch_tank` polls full zombie array at 20Hz to assign think-threads | `zm_tomb_tank.gsc` | Replace loop with `add_custom_zombie_spawn_logic(::tank_zombie_think)` | ✅ Fixed |

---

## How It's Delivered

Everything ships as two components:

**`zm_highround_patch.gsc`** — the addon script. Drop in Plutonium's
`scripts/zm/` folder. Fixes EL-02/03, OF-02/03, SA-08/09. OF-01 (insta-kill rounds) is natural behavior — no fix applied.

**`mod.ff`** (56KB) — the compiled game override. Deploy to
`%LOCALAPPDATA%\Plutonium\storage\t6\mods\zm_hrp\mod.ff`, enable via
Private Match → Select Mod. Fixes EL-01, IL-01, IL-02, SA-10, MI-06, MI-11, MI-12, GEN-ZC-01, GEN-ZC-02, GEN-ZC-03, TANK-EL-01, TANK-TL-01, TANK-MI-01, TANK-MI-02, TANK-MI-03.

One mod covers everything. The map-specific fixes (Origins staff weapons, Die Rise
elevators) only activate when those maps' zone files are loaded — they're dormant on
other maps.

```bash
./build_ff.sh   # builds and deploys mod.ff in one command
```

---

## What the Numbers Look Like Now

### Map ceilings (revised)

| Map | Unpatched | Addon only | Full patch |
|---|---|---|---|
| Origins | ~26h | ~35–40h | ~130h+ |
| Mob of the Dead | ~104h (WR ~233) | ~120h+ | ~120h+ |
| Buried | ~120h (round 255 cap) | ~120h | ~120h |
| Die Rise | Crash risk from MI-11 regardless of round | Soft-lock risk remains | Elevator bugs eliminated; entity-limited only |
| TranZit | Unstable from round 1 (zone transition crashes) | No change | No change |
| Nuketown | ~R27 (stat overflow, engine-level) | No change | No change |

Buried doesn't move much — its ceiling is the `uint8` round counter overflow at 255,
which is below the GSC layer. TranZit and Nuketown have separate crash modes that are
engine-level or platform-level and aren't addressable in script.

Origins moves the most because it had the most compounding sources: the core
entity leaks (EL-01/02/03), the two staff weapon thread pressure sources
(SA-10 Fire Staff, MI-06 Wind Staff), three generator system bugs (GEN-ZC-01/02/03
— the capture zombie spawn limiter, stale player tracking, and the attack point
off-by-one), five tank system bugs (TANK-EL-01/TL-01/MI-01/02/03 — entity leak,
thread leaks, broken flamethrower targeting, zombie routing, and a 20Hz polling loop),
and the general overflow cascades. All of them are now addressed.

### What remains below the script layer

Two things can still crash a fully-patched session:

1. **Native process stability (~8–10h continuous)** — The game executable itself has
   memory growth over time. This is independent of GSC, visible even on the main menu,
   and unreachable by any script-level fix. It sets an absolute upper bound that
   applies to every session.

2. **TranZit zone transition engine bug** — The crash on zone transitions in TranZit
   is in native code. Not a scrVar or entity issue. No script can prevent it.

Everything else that was identified is fixed.

---

## How We Got Here

The path was longer than expected.

It started as a static analysis of 2,000 GSC source files, decompiled from the
game's own `.ff` archives with [gsc-tool](https://github.com/xensik/gsc-tool). Six
bugs could be fixed from addon scripts immediately. Five more were inside compiled
functions that had no external hooks.

Those five were "impossible to fix" until Part 4b — when we discovered that
[OpenAssetTools](https://github.com/Laupetin/OpenAssetTools) has its own T6 GSC
compiler built in. Give it source files; it produces format-compatible T6 bytecode;
wrap them in a `mod.ff`; Plutonium loads your versions in place of the originals.
The compiled layer stopped being a wall.

The toolchain lesson: `gsc-tool` produces bytecode that looks structurally correct
but has the wrong section layout and a zero script name hash. T6's runtime linker
rejects it. OAT's compiler produces the right format. Once that was clear, every
bug on the "requires FF replacement" list became a source edit and a build step.

---

## The Series

- **[Part 1 — The Archaeology](01-the-archaeology.md)** — Getting the source, reading
  25,000 lines of a game that stopped being patched in 2014
- **[Part 2 — The Instrument Panel](02-the-diagnostic-tools.md)** — Building the
  HUD diagnostics, stress tests, and entity counters
- **[Part 3 — Entity Leaks](03-entity-leaks.md)** — How BO2 slowly runs out of world
- **[Part 3b — Jet Gun](03b-jetgun-transit-crash.md)** — The 10-year-old variable
- **[Part 3c — Fire Staff](03c-origins-fire-staff-crash.md)** — One wrong variable, hundreds of threads
- **[Part 3d — Wind Staff](03d-wind-staff-invisible-zombies.md)** — Why it makes invisible zombies
- **[Part 3e — Die Rise](03e-die-rise-power-crash.md)** — Why the power-on crash happens at high rounds
- **[Part 4 — The Patch](04-the-patch.md)** — Six fixes from addon scripts; two that required something more
- **[Part 4b — Patching the Compiled Layer](04b-patching-the-fastfile.md)** — How we got past the wall
- **[Part 5 — Results](05-results.md)** — Why Origins crashes at 26 hours and Buried doesn't
- **[Part 6 — Phase Two](06-fixing-the-core.md)** — Every bug that required FF replacement
- **[Part 7 — Origins Fixed](07-origins-patched.md)** — The two weapons that were quietly draining the server
- **[Part 8 — Die Rise Fixed](08-die-rise-patched.md)** — One wrong keyword and a polling loop
- **Part 9 — The Full Patch** — this post
- **[Part 10 — Generators Fixed](10-generators-patched.md)** — Three more Origins bugs in the capture system
- **[Part 11 — Tank Fixed](11-tank-patched.md)** — Five bugs in Origins' tank system, including an entity leak and a broken flamethrower cone

*All scripts, research, test data, and source at [github.com/banq/t6-high-round-fix](#).*
