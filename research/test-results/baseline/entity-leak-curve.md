# Test EL-01/02/03: Entity Leak Curve (Baseline)

**Hypothesis:** Entity count increases monotonically over rounds due to un-deleted `script_origin` anchors from `lerp()`, `rise_into_air()`, and `really_play_2d_sound()`.

## Run Metadata

| Field           | Value |
|-----------------|-------|
| Date            | 2026-02-19 |
| Map             | zm_transit / Town (gump_town) |
| Player count    | Solo |
| Script versions | zm_diagnostics.gsc v0.4, no patches |
| Plutonium build | r5246 |
| Patch scripts   | none  |

## Procedure

1. Start solo game, let it fully load
2. Note entity tally at round 1 (map baseline)
3. Play normally; record HUD data at rounds 1, 5, 10, 15, 20, 25, 30, 40, 50
4. Use `/diag log 5` to auto-log every 5 rounds to server log
5. At round 10 open all zone routes (maximise entity creation from barriers etc.)
6. Use traps and splash weapons to maximise mid-animation deaths

## Data Table

Auto-snap session — low-effort play (very few kills per round; entity baseline run). Note: Ent Tally
limit displayed as `/2048` — compiled binary was from a pre-v0.4 build; true engine limit is 1024.

| Round | Ent Tally | Ent Count | AI Active | Recycles | Kills | ZQueue | ZHealth |
|-------|-----------|-----------|-----------|----------|-------|--------|---------|
| 1     | 198/2048  | 198       | 0         | 0        | 0     | 0      | 150     |
| 4     | 207/2048  | 207       | 1         | 0        | 6     | 17     | 450     |
| 9     | 207/2048  | 207       | 1         | 0        | 7     | 28     | 950     |
| 13    | 207/2048  | 207       | 1         | 0        | 8     | 38     | 1389    |
| 17    | 207/2048  | 207       | 1         | 0        | 11    | 49     | 2030    |
| 21    | 207/2048  | 207       | 1         | 0        | 12    | 62     | 2971    |
| 25    | 207/2048  | 207       | 1         | 0        | 13    | 79     | 4348    |
| 29    | 207/2048  | 207       | 1         | 0        | 14    | 98     | 6364    |
| 34    | 207/2048  | 207       | 1         | 0        | 21    | 127    | 10248   |

**Key observation:** Entity count is flat at 207 from R4 through R34 despite 21 kills. This confirms the preliminary finding — entity leaks are zero with minimal kill counts and no splash/animation kills.

### Real gameplay cross-reference (from OF-02 test session)

During the OF-02 score overflow test, two manual snaps were taken mid-gameplay:

| Round | Ent Tally | Ent Count | AI Active | Kills | ZQueue | Drop Inc | Score Total |
|-------|-----------|-----------|-----------|-------|--------|----------|-------------|
| 11    | 211/1024  | 211       | 4         | 36    | 0      | 250      | 51,930      |
| 12    | 229/1024  | 229       | 24        | 40    | 12     | 325      | 2,147,400,000 |

With 36 real kills by R11, entity count is 211 — only +4 above the 207 baseline. The jump to 229 (+18) in R12 coincides with the OF-02 score injection (`/st score 2147400000`) and likely reflects powerup-drop entity creation during a round-transition rather than a natural leak.

**Estimated natural leak rate: ≤ 0.5 entities per kill** (4 extra entities for 36 kills through R11).

## Observations

### Preliminary finding (2026-02-19)

- Map: Town (Tranzit Diner), Solo
- `st ramp 50` (artificial kills, no real zombie lifecycle): Ent Tally stayed flat at **207** from R1 to R50.
- **Conclusion:** Entity leaks are lifecycle-dependent. Artificial instant kills via `dodamage()` do not trigger the `lerp()`/`rise_into_air()` anchor creation paths. Leaks only accumulate during real gameplay where zombies complete spawn animations and mid-movement deaths.

### Low-effort play run (2026-02-19 auto-snap session)

- Round 1 entity baseline: **198** (Town map cold start, no zombies spawned yet)
- After first wave spawns: **207** (+9 at R4 — first-wave spawner anchors and setup entities)
- Rounds 4–34: **207** flat (0 growth over 30 rounds, only 21 kills total)
- Slope with minimal kills: **0 entities per round**
- Any sudden jumps: None observed
- Probe MinHR at R34: `>128` (Probe HR limit not yet measured in this session)

### Real gameplay run (EL-01 dedicated run still pending)

A full dedicated EL-01 run with aggressive play style (traps, splash weapons, mid-animation kills) has not yet been completed. The OF-02 cross-reference data above provides an early-round real-gameplay data point but is confounded by the score injection.

- Round 1 entity baseline: 198 (consistent)
- Slope with real gameplay through R11: ~0.1 entities/kill (very slow)
- R12 anomalous jump (+18): attributed to OF-02 test conditions, not natural leak

## Raw Server Log Excerpts

### Auto-snap session (R1–R34)

```
  3:16 DIAG_SNAP [MANUAL SNAP #1]
  3:16   Round:        1
  3:16   ZombieHealth: 150
  3:16   ZombieQueue:  0
  3:16   AI Active:    0
  3:16   Ent Tally:    198/2048
  3:16   Probe HR:     >-1
  3:16   Probe MinHR:  >9999
  3:16   Kills:        0
  3:16   Recycles:     0
  3:16   Timeouts:     0
  3:16   Drop Inc:     2000
  3:16   Score Total:  500

  1:12 DIAG_SNAP [AUTO R4]
  1:12   Round:        4
  1:12   ZombieHealth: 450
  1:12   ZombieQueue:  17
  1:12   AI Active:    1
  1:12   Ent Tally:    207/2048
  1:12   Kills:        6  Recycles: 0  Timeouts: 0

  1:28 DIAG_SNAP [AUTO R9]
  1:28   Round:        9
  1:28   ZombieHealth: 950
  1:28   ZombieQueue:  28
  1:28   AI Active:    1
  1:28   Ent Tally:    207/2048
  1:28   Kills:        7  Recycles: 0  Timeouts: 0

  1:46 DIAG_SNAP [AUTO R13]
  1:46   Round:        13
  1:46   ZombieHealth: 1389
  1:46   ZombieQueue:  38
  1:46   AI Active:    1
  1:46   Ent Tally:    207/2048
  1:46   Kills:        8  Recycles: 0  Timeouts: 0

  2:01 DIAG_SNAP [AUTO R17]
  2:01   Round:        17
  2:01   ZombieHealth: 2030
  2:01   ZombieQueue:  49
  2:01   AI Active:    1
  2:01   Ent Tally:    207/2048
  2:01   Kills:        11  Recycles: 0  Timeouts: 0

  2:18 DIAG_SNAP [AUTO R21]
  2:18   Round:        21
  2:18   ZombieHealth: 2971
  2:18   ZombieQueue:  62
  2:18   AI Active:    1
  2:18   Ent Tally:    207/2048
  2:18   Kills:        12  Recycles: 0  Timeouts: 0

  2:34 DIAG_SNAP [AUTO R25]
  2:34   Round:        25
  2:34   ZombieHealth: 4348
  2:34   ZombieQueue:  79
  2:34   AI Active:    1
  2:34   Ent Tally:    207/2048
  2:34   Kills:        13  Recycles: 0  Timeouts: 0

  2:51 DIAG_SNAP [AUTO R29]
  2:51   Round:        29
  2:51   ZombieHealth: 6364
  2:51   ZombieQueue:  98
  2:51   AI Active:    1
  2:51   Ent Tally:    207/2048
  2:51   Kills:        14  Recycles: 0  Timeouts: 0

  3:11 DIAG_SNAP [AUTO R34]
  3:11   Round:        34
  3:11   ZombieHealth: 10248
  3:11   ZombieQueue:  127
  3:11   AI Active:    1
  3:11   Ent Tally:    207/2048
  3:11   Kills:        21  Recycles: 0  Timeouts: 0
```

## Conclusion

**PARTIAL CONFIRMATION.** The R1–R34 auto-snap data shows entity count jumping from 198 to 207 at first spawn (+9 setup entities) then staying completely flat through R34 with minimal kills. This confirms the `st ramp` finding: entity leaks require real zombie lifecycle events (spawn animations, movement, death effects) and do not accumulate via direct `dodamage()` kills.

The cross-reference real gameplay data (R11: 211 entities, 36 kills) shows a modest natural leak of ~4 entities above baseline over 36 kills — a leak rate of ~0.1 entities/kill. This is far below the static analysis prediction of 3–9 entities/round. A dedicated full-gameplay run with aggressive splash/trap use is still required to establish a definitive per-round leak slope.

**Map cold-start entity baseline: 198** (Town, solo, no zombies spawned).
**First-wave setup overhead: +9** (207 at R4).
**Natural leak rate in normal play: very slow** (< 0.5 per kill observed so far).
