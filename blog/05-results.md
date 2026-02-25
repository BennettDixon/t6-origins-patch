# The Results: Why Origins Crashes at 26 Hours and Buried Doesn't

*Part 5 of the BO2 High-Round Crash Fix series. [Part 1](01-the-archaeology.md) | [Part 2](02-the-diagnostic-tools.md) | [Part 3](03-entity-leaks.md) | [Part 4](04-the-patch.md)*

---

The most common question in the high-round community is some variation of: "how many
rounds can you realistically reach?" It's asked about specific maps — Origins specifically
has a reputation for being harder to run long than other maps. Players compare their
"ceiling" by round number.

That framing is wrong, and understanding why explains both the map-specific limits and
what the patch actually does.

---

## The Fundamental Insight: Time Limits Are Clock-Based, Not Round-Based

The entity pool depletes at a rate proportional to kills per hour. Entity leaks — from
whatever source — happen when a zombie spawns, animates, and dies. The number of those
events per hour depends on how fast rounds go, which depends on zombie count, zombie HP,
and player efficiency.

Round number is a proxy for time, and it's a lousy one. A round at round 50 takes roughly
3–5 minutes in real play; a round at round 200 can take 10–15 minutes because zombie HP
is astronomical. The total number of zombie kills per hour is roughly constant across all
rounds in optimized high-round play — you kill zombies as fast as your weapons allow,
which doesn't change dramatically from round 80 to round 150.

**The crash ceiling is therefore approximately fixed in wall-clock time, not round number.**

A session running 1,000 kills at 2 leaked entities per kill accumulates the same entity
pressure whether those kills happened across 10 rounds or 30 rounds. The round number
where the ceiling hits depends entirely on how fast rounds go — which varies by map.

This reframes every map-specific "time limit":

| Map | Known ceiling | Why |
|-----|--------------|-----|
| Buried | ~120h (round 255 reached) | Simple geometry, low entity overhead, no special AI |
| Origins | ~26h | High entity overhead from robots, Panzers, complex scripted zones |
| Mob of the Dead | ~104h (WR ~233) | Moderate overhead but plane sequence crash risk |
| TranZit | Unstable from round 1 | Zone transition crashes independent of entity accumulation |
| Nuketown | ~R27 | Separate stat-overflow crash, not entity-limited |

The 26-hour Origins limit and 120-hour Buried limit are not "Origins runs out of round
space" — they are "Origins consumes entity budget 4–5x faster per unit time than Buried
does."

---

## Why Origins Burns Entity Budget Faster

Origins is the most technically demanding BO2 zombies map. Three Giant Robots patrol the
battlefield continuously. Panzer Soldaten — complex AI with multiple hitbox entities,
flamethrowers, and grab animations — spawn with increasing frequency. Dynamic weather
systems change active hazard zones. Four elemental staves each have their own entity
chains.

Every active entity is a permanent slot in the 1024-entity pool. The map starts with more
slots occupied than any other map. The gap between baseline pool usage and the ceiling is
smaller, so accumulated leaks hit the ceiling faster.

There's also a deliberate engine concession: when all three robots are active, the zombie
spawn cap drops from 24 to 22. Treyarch acknowledged the map's entity overhead by reducing
the live-zombie count to compensate. This means slightly more rounds are needed to reach
any given kill count, which slightly extends the wall-clock time — but the baseline
entity overhead from the robots themselves more than offsets this.

**The 26-hour wall is not a round limit. It's the point where the entity leak rate and
Origins' higher baseline overhead together exhaust the pool.**

---

## Before and After: What the Patch Does

### Entity pool

The watchdog (EL-02/03 fix) prevents anchor leaks in the ~50–100ms zombie spawn window.
Runtime testing confirmed the natural spawn-time anchor leak is likely handled by engine
auto-cleanup in the common case (the probe stayed flat across 32 rounds of forced
mid-anchor kills). The watchdog provides belt-and-suspenders coverage for the
external-thread-assignment case that isn't auto-cleaned.

The EL-01 (`lerp()`) case remains open: force-terminated threads may or may not trigger
the same implicit cleanup as `endon`-exited threads. The FF replacement of `_zm_utility.gsc`
adds `self._lerp_link = link` before the waittill, which lets the watchdog clean it up
definitively regardless of how the engine handles force-terminated thread cleanup. This
is the remaining highest-leverage fix.

| Issue | Unpatched ceiling | Patched (addon) | Patched (addon + FF) |
|-------|-----------------|-----------------|---------------------|
| EL-02/03 anchor leaks | Accumulates (low probability) | Eliminated | Eliminated |
| EL-01 lerp() leaks | Accumulates (unknown rate) | No change | **Eliminated** |
| IL-01 has_attachment freeze | Crashes on trigger | No change | **Fixed** |
| OF-01 zombie health overflow | Insta-kill rounds at R163+ (int32 overflow → negative health → dies from any hit) | Natural — no fix applied | Natural — no fix applied |
| OF-02 score overflow | Drops stop eventually | No drop cessation | No drop cessation |
| OF-03 drop increment runaway | Silent drop stoppage | Capped 50k | Capped 50k |
| SA-08/09 scrVar accumulation | Crash at extreme rounds | Cleared per round | Cleared per round |
| IL-03 failsafe soft-lock | Round never ends | Not triggered — insta-kill rounds complete normally | Not triggered |

### Projected time limits

**Addon patch only (no FF replacement):**

The scrVar crash is eliminated — weapon arrays can't accumulate past one round's worth of
data. The OF-02/03 overflow cascades are eliminated — drops keep firing, rounds keep
ending. OF-01 (zombie health overflow) is left natural: at high rounds health
overflows int32, wraps negative, and zombies die from any hit — the insta-kill
round phenomenon. No fix applied; this is accepted high-round behavior. The entity pool accumulation is slowed by the EL-02/03
watchdog.

IL-01 (`has_attachment` freeze) remains a risk in long sessions with heavy PaP cycling
through compound-attachment weapons. In standard BO2 zombies most weapons are
`weaponname_zm` or `weaponname_zm_upgraded` (no extra `+`-tokens after the name), so
the specific trigger condition — three-token weapon names where the checked attachment
isn't the first — is less common than the static analysis initially suggested. For the
majority of high-round sessions the addon-only patch provides a substantial improvement.

**Estimated improvement: +30–60% extended runtime on Origins** (from ~26h toward 35–40h)
based on eliminating the overflow cascades that compound entity pressure.

**Addon patch + FF replacement (EL-01 and IL-01 fixed):**

Entity pool becomes effectively stable. The watch-and-clean pattern covers all identified
leak sources. IL-01 can no longer freeze the server during PaP upgrades. The only
remaining session-duration constraint is the 8–10 hour engine stability limit — a native
process issue that exists even when the game is left idle on the main menu. That limit is
below the GSC layer, unreachable by any script-level fix.

**Projected improvement: Origins approaches Buried-class stability (~100h+)** contingent
on EL-01 runtime verification confirming force-terminated thread cleanup doesn't already
handle it.

---

## The Comparison Table

| Metric | Unpatched | Addon patch | Addon + FF |
|--------|-----------|-------------|-----------|
| Origins practical ceiling | ~26h | ~35–40h | ~100h+ |
| Buried practical ceiling | ~120h | ~120h+ | ~120h+ |
| Drops stop at INT_MAX score | Yes | No | No |
| Zombies unkillable at R163+ | Yes | No | No |
| Round-never-ends at R200+ | Yes | No | No |
| PaP upgrade freeze (IL-01) | Risk | Risk | No |
| scrVar crash (long box sessions) | Yes | No | No |

Buried's ceiling doesn't change much with the addon patch because Buried doesn't
accumulate entity pressure fast enough for leaks to be the binding constraint in a 120h
run — the round 255 cap (uint8 overflow) is the actual ceiling there, and that's in the
engine, not in script.

---

## What's Left

The project is not entirely complete. Two items remain pending:

**In-game soak test.** The 25-round `elpkill` control run (no ELP patch) to definitively
resolve whether naturally-spawned anchors persist or are auto-cleaned. If Hypothesis A
is confirmed (real leak), the FF replacement becomes critical. If Hypothesis B
(auto-cleanup), the pool is already stable with the addon patch alone and the Origins
ceiling improvement would be even larger than projected. The test protocol is documented
in `research/test-results/patched/el01-extended-soak.md`.

**FF replacement.** *Update: this is no longer pending.* The `patch_zm.ff` overrides
are deployed and IL-01 is verified. The full story of how FF modding was unlocked is
in [Part 4b](04b-patching-the-fastfile.md). Part 6 covers what that means for the
remaining compiled-layer bugs.

---

## The Bandit Comparison

The existing community fix — [teh-bandit's High Round Fix](https://github.com/teh-bandit/Plutonium-T6ZM/blob/main/High%20Round%20Fix/high_round_fix.gsc) — caps zombie health at round 155 and adjusts movement speed. It addresses OF-01 (the health overflow) and as a side effect prevents the IL-03 failsafe soft-lock that OF-01 causes.

It doesn't address entity leaks, script variable accumulation, the score overflow that
stops drops, the drop increment that breaks the drop rate silently, the `has_attachment`
infinite loop, or the `lerp()` entity leak. It's a single-fix band-aid on the most
visible symptom.

This project goes deeper: 6 confirmed fixes in the addon patch, 2 more in the FF
replacement, systematic test coverage for each, before/after data, and source-level
explanation of every root cause.

---

## Try It

`zm_highround_patch.gsc` is a single file. Drop it in your Plutonium scripts directory,
compile with gsc-tool, restart the map. The `[HRP] High Round Patch v1.0 active` banner
confirms it loaded. Watch the `OF` digits in the corner HUD — the first digit is the score cap
(flips to `1` at ~999M), the second is the drop increment cap. Around R163+
health overflows naturally into insta-kill rounds with no intervention from the
patch.

Full install instructions, source, and test data are at the GitHub repository.

For the FF replacement (`mod.ff` with the compiled-layer fixes): follow
`research/07-ff-replacement-guide.md`. Build and deploy with `./build_ff.sh`. See
[Part 4b](04b-patching-the-fastfile.md) for how it works.

---

The crashes in BO2 zombies were never random. They were a predictable accumulation process
running against fixed resource budgets in a 32-bit engine descended from Quake III Arena.
The community tracked the symptoms accurately for a decade — the correlation with time,
with playstyle, with map complexity. The root causes just needed someone to read the code
carefully enough to find them.

*All scripts, test data, and raw logs are at [github.com/banq/t6-high-round-fix](#).*
