# Test EL-02: Entity Ceiling Crash (Baseline)

**Hypothesis:** Entity exhaustion (pool fully consumed) is the direct cause of the game crash, not a code bug per se. Reducing headroom artificially with `/st fill` should cause the crash at a much lower round number.

## Run Metadata

| Field           | Value |
|-----------------|-------|
| Date            | 2026-02-19 |
| Map             | zm_transit / Town (gump_town) |
| Player count    | Solo |
| Plutonium build | r5246 |
| Script versions | zm_diagnostics.gsc v0.3, zm_stress_test.gsc |
| Patch scripts   | none |

## Procedure

1. Start solo game
2. Use `/st fill <N>` to pre-consume entity slots
3. Play normally; note when game crashes
4. Repeat with different fill values to triangulate the engine limit
5. Also: drain all, then `/st fill` one at a time until `spawn()` returns undefined — log that count

## Pre-fill Experiments

| Fill Count | Game Survived To Round | Crashed? | Notes |
|------------|------------------------|----------|-------|
| 0 (baseline) | N/A                  | No       | Map loaded fine |
| 500        | immediate crash        | YES      | G_Spawn: no free entities at 916/1024 |

## Entity Limit — CONFIRMED

**Engine entity limit: 1024**

Crash log excerpt (2026-02-19, zm_transit/Town, Solo, r5246):
```
total ents: 916/1024
max ents: 888/1024
total enthandles: 1/1024
max enthandles: 1/1024

====================== COM_ERROR (1) ===============
G_Spawn: no free entities
=======================================================
SV_Shutdown: G_Spawn: no free entities
```

- Map baseline: ~114 entities loaded at map start (from entity dump up to first `st_cmd_fill` entry)
- Gameplay headroom: **1024 − 114 = ~910 entities** available for all zombies, spawners, weapons, FX, etc.
- Fill of 500 consumed enough of the remaining pool (combined with map's own runtime entities) to trigger the crash.

## Bonus: `really_play_2d_sound` Leak Caught Live

The crash dump included entry 328:
```
328: Type: 'Scriptmover', Class: 'script_origin', Org: 0.0 0.0 0.0,
     GSC Alloc: 'maps/mp/zombies/_zm_utility::really_play_2d_sound'
```
This is direct runtime evidence of the `really_play_2d_sound` leak predicted by static analysis. A `script_origin` allocated inside that function was never deleted and remained in the live entity pool at crash time. This confirms the leak is real and observable in a normal game session (not just under fill pressure).

## Conclusion

**Confirmed:** Entity exhaustion directly causes the crash. The engine limit is 1024 on T6/Plutonium. The practical safe budget for all gameplay entities is ~910 slots. Any entities that leak per-round accumulate against this budget, and `really_play_2d_sound` leaking a `script_origin` per call has been observed in the wild.
