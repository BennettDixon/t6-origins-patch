# Prior Art

What the community has already done to address high-round instability in BO2 zombies, what they got right, what they missed, and where our work fits in.

## Bandit's High Round Fix (Plutonium)

**Source:** [teh-bandit/Plutonium-T6ZM](https://github.com/teh-bandit/Plutonium-T6ZM/tree/main/High%20Round%20Fix)
**Platform:** Plutonium T6 (PC)
**Status:** Active, widely used in the competitive high-round community

### What It Does

The script (`high_round_fix.gsc`, 113 lines) does the following:

1. **Health cap:** Caps zombie health at the round 155 value. Every round start, if `level.zombie_health` exceeds `ai_zombie_health(155)`, it's clamped.

```gsc
zombie_health()
{
    for (;;)
    {
        level waittill("start_of_round");
        if(level.zombie_health > maps/mp/zombies/_zm::ai_zombie_health(155))
        {
            level.zombie_health = maps/mp/zombies/_zm::ai_zombie_health(155);
        }
    }
}
```

2. **Movement speed normalization:** Sets `player_backSpeedScale`, `player_strafeSpeedScale`, and `player_sprintStrafeSpeedScale` to 1, matching console movement feel.

3. **Persistent upgrades:** Grants all persistent upgrades on first spawn (boarding, revive, multikill headshots, cash back, insta kill, jugg, flopper, etc.).

4. **Weapon locker:** Pre-loads an upgraded AN-94 with reflex sight in the weapon locker with max ammo.

5. **Bank balance:** Sets starting bank to 250.

### What It Gets Right

- The health cap is the correct response to OF-01 (health overflow). Without it, zombies become unkillable past round ~163, which cascades into the failsafe soft-lock.
- It's well-tested by the competitive community and known to work.
- The persistent upgrades and weapon locker setup save hours of grinding before high-round attempts.

### What It Misses

- **No entity leak fixes.** The three critical entity leaks (EL-01, EL-02, EL-03) are untouched. Games will still crash from entity exhaustion — just at a slightly higher round since the health cap prevents the failsafe soft-lock cascade.
- **No infinite loop fixes.** The `has_attachment()` bug (IL-01) and `random_attachment()` edge case (IL-02) remain.
- **No powerup overflow fix.** The exponential drop increment (OF-03) and score total overflow (OF-02) are untouched.
- **No state accumulation fixes.** All counters still grow unbounded.
- **No race condition fixes.** The `array_flag_wait_any` typo and grenade position race remain.

### Our Assessment

Bandit's fix is a pragmatic bandaid — it addresses the most visible symptom (unkillable zombies) without touching the underlying structural issues. It extends playability but doesn't solve the crash. A player using this fix will still crash from entity exhaustion; they just won't soft-lock from health overflow first.

**Our work complements it.** The health cap is still a good idea (and we include a similar cap in our patch). But we also fix the entity leaks, infinite loops, and overflow issues that the health cap can't address.

## Resxt's Plutonium T6 Scripts

**Source:** [Resxt/Plutonium-T6-Scripts](https://github.com/Resxt/Plutonium-T6-Scripts)
**Platform:** Plutonium T6

A collection of QOL and gameplay modification scripts. Includes things like custom HUD elements, game mode tweaks, and utility functions. None of the scripts target high-round crash fixes specifically, but the codebase is a useful reference for Plutonium GSC modding patterns and conventions.

## plutoniummod/t6-scripts (Official)

**Source:** [plutoniummod/t6-scripts](https://github.com/plutoniummod/t6-scripts)
**Platform:** Plutonium T6

The official Plutonium team's script repository. Contains the base game scripts as a reference for modders. Useful for understanding the full decompiled codebase but doesn't include patches or fixes.

## JezuzLizard's Recompilable GSCs

**Source:** [JezuzLizard/Recompilable-gscs-for-BO2-zombies-and-multiplayer](https://github.com/JezuzLizard/Recompilable-gscs-for-BO2-zombies-and-multiplayer)
**Platform:** Plutonium T6 / Xbox 360

A project to make the decompiled BO2 scripts recompilable — fixing decompilation artifacts and syntax issues so the scripts can be modified and recompiled with gsc-tool. Includes an engine function reference document.

**Relevance:** Demonstrates the feasibility of modifying and recompiling core game scripts. Their function reference could be useful for understanding available engine builtins.

## Se7enSins Forum Knowledge

The Se7enSins modding forums have scattered discussions about BO2 high-round crashes dating back to 2012-2013. Key observations from the community:

- "Entity overflow" is mentioned as a suspected cause, but without systematic analysis
- Various hacky workarounds (periodically killing all zombies, disabling certain features) are suggested
- The entity limit number "1024" appears in multiple threads, though its source is unclear
- Some users have done memory monitoring on Xbox 360 via JTAG/RGH, observing entity count climb
- No one has published a systematic code audit or a principled fix

## Plutonium Forum Discussions

The Plutonium forums have several relevant threads:

- **Zombies Counter and Health Counter** ([forum thread](https://forum.plutonium.pw/topic/40568/release-zombies-zombies-counter-and-health-counter)): A custom HUD script that displays zombie count and health. Demonstrates the HUD API we'll use for our diagnostic tool.
- **Start at Round X** ([forum thread](https://forum.plutonium.pw/topic/38199/t5-t6-start-at-round-x)): How to skip to a specific round for testing. Confirms that `level.round_number` can be set directly but requires accompanying state updates (health, speed).
- **Scripts for Competitive Players** ([forum thread](https://forum.plutonium.pw/topic/15658/release-zombies-scripts-for-competitive-players)): Various competitive QOL scripts. Some overlap with Bandit's fix.

## What Our Work Adds

| Aspect | Prior Art | Our Work | Status |
|--------|-----------|----------|--------|
| Health cap | Bandit's fix caps at round 155 | Similar cap, but explained as overflow mitigation with math | Planned (Phase 3) |
| Entity leak analysis | Community suspicion, no proof | 8 specific leaks identified with code paths and line numbers | **Done** (docs/) |
| Entity leak fix | None | Death watchdog pattern for all 3 critical leaks | Planned (Phase 3) |
| Infinite loop fixes | None | 3 loops fixed (has_attachment, random_attachment, failsafe) | Planned (Phase 3) |
| Overflow fixes | None (beyond health cap) | Powerup increment clamp, score overflow handling | Planned (Phase 3) |
| Diagnostic tooling | Basic zombie counter HUD | Full entity/state monitoring HUD with leak detection | **Done** (`zm_diagnostics.gsc`, compiles) |
| Stress testing | Manual play to high rounds | Automated round acceleration and entity pressure simulation | **Done** (`zm_stress_test.gsc`, compiles) |
| Systematic audit | None | 25 issues across 7 files, categorized and severity-ranked | **Done** (docs/, research/) |
| Reproducible methodology | None | Documented test protocol, before/after data | **Done** (test-protocol.md, awaiting runtime) |

The key differentiator is that we're not just applying a symptom-level fix — we're identifying and addressing root causes with evidence. The blog series will show the full chain: hypothesis -> instrumentation -> data -> fix -> validation.
