# Test EL-01 Extended Soak: Does the lerp() Leak Actually Persist?

**Test ID:** EL-01-SOAK

**Open question from earlier testing:**
Run D of the entity-leak-watchdog test (elpkill, no ELP) showed the entity tally
staying flat at 206–207 for 5 rounds despite 40+ mid-anchor kills being logged.
Two hypotheses were proposed:

- **Hypothesis A (Real leak, invisible to tally):** Orphaned `script_origin` entities
  persist in the raw engine pool but `getentarray("script_origin", "classname")` doesn't
  enumerate them (orphaned entities with no active GSC owner may be invisible to GSC
  queries). The entity tally has a blind spot; the probe headroom would eventually degrade
  and cause a crash near the ceiling.

- **Hypothesis B (Engine auto-cleanup):** When the zombie entity is freed after death,
  the engine's reference-counting frees any entities still referenced only by that zombie's
  properties (including `self.anchor`). The anchor is automatically reclaimed along with
  the zombie. ELP is cleaning something the engine would free anyway; the tally stays flat
  because there is no persistent leak.

**Resolution:** Run `elpkill` without ELP for 25–30 rounds and monitor whether probe
headroom degrades. If it does, Hypothesis A is correct and EL-01 is a real engine-pool
drain. If headroom stays stable, Hypothesis B is correct and EL-01 can be closed
as a false positive.

## Run Metadata

| Field           | Value |
|-----------------|-------|
| Date            | TODO  |
| Map             | zm_transit / Town (gump_town) |
| Player count    | Solo |
| Plutonium build | r5246 |
| Script versions | zm_diagnostics.gsc v0.6, zm_stress_test.gsc |
| Patch scripts   | **NONE** — this is the control run; do NOT load zm_patch_entity_leaks.gsc |

## Procedure

This test must be run **without** `zm_patch_entity_leaks.gsc` loaded. Load only
`zm_diagnostics.gsc` and `zm_stress_test.gsc`.

1. Confirm `[ELP]` banner does NOT appear — entity leak patch must be absent.
2. Confirm diagnostic HUD is running (Probe HR and Ent Tally visible).
3. Note initial entity tally and probe headroom at R1.
4. Arm elpkill at round 1:
   `set st_cmd elpkill`
   Confirm: `[ST] elpkill armed (CONTROL — no ELP loaded)`
5. Enable god mode so you are not killed by the zombies that are rising:
   `set st_cmd god`
6. Let the game run. elpkill kills every zombie within 50ms of spawn
   (while the anchor is set), cycling rounds automatically.
7. **Do not intervene** — let elpkill run for 25+ rounds.
8. Record the following from the server log (`games_mp.log`) after each round:
   - `[ST] elpkill RN ent=X` — entity count at round N
   - `Probe HR` from auto-snap logs (`[AUTO RN] Probe HR: >X`)
   - Any `"killed mid-anchor"` lines (confirms anchors are present at kill time)

### Key log lines to collect

From `zm_stress_test.gsc` (elpkill round log):
```
[ST] elpkill R2  ent=207  anchors_freed_this_round=--  total_freed=--  ELP=off
[ST] elpkill R5  ent=???  anchors_freed_this_round=--  total_freed=--  ELP=off
...
[ST] elpkill R25 ent=???  anchors_freed_this_round=--  total_freed=--  ELP=off
```

From diagnostics auto-snap (fires every 5 rounds):
```
DIAG_SNAP [AUTO R5]  Ent Tally: ???/1024  Probe HR: >???  Probe Min: >???  ...
DIAG_SNAP [AUTO R25] Ent Tally: ???/1024  Probe HR: >???  Probe Min: >???  ...
```

## Expected Results

### If Hypothesis A (real persistent leak):

| Round | Ent Tally | Probe HR |
|-------|-----------|----------|
| 1     | ~207      | >128     |
| 5     | ~235–250  | ~105–115 |
| 10    | ~280–300  | ~80–100  |
| 20    | ~380–440  | ~30–60   |
| 25    | ~440–510  | <30      |

The `Probe Min` metric (running minimum of all probe readings) would decline steadily.
At ~R30–40 the game would crash with a `G_Spawn: no free entities` engine error.

### If Hypothesis B (engine auto-cleans zero-reference entities):

| Round | Ent Tally | Probe HR |
|-------|-----------|----------|
| 1     | ~207      | >128     |
| 5     | ~207      | >128     |
| 10    | ~207      | >128     |
| 20    | ~207      | >128     |
| 25    | ~207–210  | >128     |

Entity tally and probe headroom remain stable. No degradation. No crash at R30+.

## Actual Results

### Entity Tally per Round

| Round | Ent Tally | Probe HR | Notes |
|-------|-----------|----------|-------|
| R1    | TODO      | TODO     |       |
| R5    | TODO      | TODO     |       |
| R10   | TODO      | TODO     |       |
| R15   | TODO      | TODO     |       |
| R20   | TODO      | TODO     |       |
| R25   | TODO      | TODO     |       |

### Summary

| Check | Hypothesis A | Hypothesis B | Actual |
|-------|--------------|--------------|--------|
| Ent tally grows over 25 rounds | Yes (+~15/round) | No (flat) | TODO |
| Probe HR degrades | Yes | No | TODO |
| Game crashes at R30+ | Yes | No | TODO |
| EL-01 is a real pool drain | YES | NO | TODO |

## Impact on Time Limit Projections

**If Hypothesis A confirmed (real leak):**
EL-01 is the dominant remaining entity drain. At ~15 leaked entities per round (the
elpkill stress rate is higher than real play since every kill is mid-anchor), the real-play
rate would be closer to 1–4 per round at high rounds. Without FF replacement:
- Usable pool: ~910 entities
- Effective leak rate (real play, high rounds): ~2/round average
- Projected ceiling: 910 ÷ 2 = ~455 rounds
- Estimated session time at ~3 min/round: ~23 hours

The FF replacement of `_zm_weapons.gsc` (EL-01 fix: store `link` as `self._lerp_link`)
would eliminate this and push time limits toward Buried-class stability.

**If Hypothesis B confirmed (no persistent leak):**
EL-01 closes as a false positive. The entity pool is stable under all patched conditions.
EL-02/03 anchor leaks are the only remaining pool pressure (validated at ~0–1/round from
the elpsynth/elpkill tests). The time limit on all maps becomes effectively uncapped by
entity exhaustion — only the 8–10h idle session freeze and health/score overflows remain.
Both of those are already addressed by `zm_patch_overflow.gsc`.

## Conclusion

TODO — fill in after running the 25-round soak in-game.

**Prior evidence leans Hypothesis B:** The 5-round control run (Run D in entity-leak-watchdog.md)
showed a flat entity tally at 206–207 with 40+ confirmed mid-anchor kills. The entity probe
did not degrade. Either the engine auto-cleans zero-reference `script_origin` entities,
or these specific leaks are invisible to the GSC entity enumeration API. The 25-round soak
will distinguish between these two cases by using the spawn-probe headroom measurement,
which is not subject to enumeration blind spots.
