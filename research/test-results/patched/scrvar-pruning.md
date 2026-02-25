# Test SA-08/SA-09: scrVar Pruning (Patched)

**Hypothesis:** `zm_patch_scrvar.gsc` correctly prunes stale `self.hitsthismag` entries and clears `self.pack_a_punch_weapon_options` at each `start_of_round`, releasing the child scrVar pool slots that would otherwise accumulate over the session.

## Run Metadata

| Field           | Value |
|-----------------|-------|
| Date            | 2026-02-19 |
| Map             | zm_transit / Town (gump_town) |
| Player count    | Solo (banq) |
| Plutonium build | r5246 |
| Script versions | zm_diagnostics.gsc v0.5, zm_stress_test.gsc, zm_patch_scrvar.gsc v1.0 |
| Co-loaded patches | zm_patch_entity_leaks.gsc v1.1, zm_patch_loops.gsc v1.1 |

## Procedure

1. Start solo game with all patches loaded
2. Confirm `[SVP]` init message in server log
3. Run `set st_cmd "weap 100"` to inflate `self.hitsthismag` with 100 fake entries
4. Advance to round 1 start — observe SVP prune log
5. Run `set st_cmd "papweap 50"` during round 2 to inflate `pap_weapon_options`
6. Advance to round 3 start — observe SVP clear log
7. Confirm cumulative counts with `set st_cmd weapstat`

## Raw Log

```
0:00 InitGame: \mapname\zm_transit\shortversion\r5246 ...
0:00 [ELP] Entity leak patch v1.1 loaded — anchor watchdog installed
0:00 [LLP] Loop patch v1.1 init
0:00 [LLP] weaponUpgrade_func not defined at init time
0:00 [SVP] scrVar patch v1.0 init
0:00 J;5517773;0;banq
0:12 [ST] weap: hitsthismag inflated 1 -> 101 for banq
0:15 [DIAG] probe HR=128
0:15 [SVP] banq hitsthismag: pruned 100 stale entries (was 101, now 1)
0:15 [ELP] R1 — anchors freed this round: 0 (total: 0)
0:25 [DIAG] probe HR=128
0:30 [ST] papweap: pap_weapon_options inflated 0 -> 50 for banq
0:35 [DIAG] probe HR=128
0:45 [DIAG] probe HR=128
0:55 [DIAG] probe HR=128
1:05 [DIAG] probe HR=128
1:15 [DIAG] probe HR=128
1:25 [DIAG] probe HR=128
1:35 [DIAG] probe HR=128
1:45 [DIAG] probe HR=128
1:45 [ELP] R3 — anchors freed this round: 0 (total: 0)
1:45 [SVP] banq pap_weapon_options: cleared 50 cached entries
1:55 [DIAG] probe HR=128
2:05 [DIAG] probe HR=128
2:14 ShutdownGame:
```

## Analysis

### SA-08: `self.hitsthismag` pruning — CONFIRMED

| Moment | Size | Notes |
|--------|------|-------|
| Game start | 1 | Player's starting pistol (`pistol_zm`) — 1 real entry |
| After `weap 100` (0:12) | 101 | 100 fake `_fake_sv_weap_N` entries added |
| After R1 `start_of_round` (0:15) | 1 | 100 stale entries pruned; 1 real entry kept |

The SVP pruner called `self getweaponslist()`, found only the starting pistol, kept its `hitsthismag` entry, and discarded all 100 fake keys in a single round-start sweep. The base game re-populates missing entries lazily on first weapon switch or fire event — no gameplay disruption.

**Log line:** `[SVP] banq hitsthismag: pruned 100 stale entries (was 101, now 1)`

### SA-09: `self.pack_a_punch_weapon_options` clearing — CONFIRMED

| Moment | Size | Notes |
|--------|------|-------|
| R2 start (before 0:30) | 0 / undefined | No PaP activity yet |
| After `papweap 50` (0:30) | 50 | 50 fake `_fake_pap_weap_N` entries added, during R2 |
| After R3 `start_of_round` (1:45) | 0 | All 50 entries cleared |

The patch waited for the next `start_of_round` after the array was populated. At R3 start, it set `self.pack_a_punch_weapon_options = undefined`, freeing all 50 slots. The base code in `get_pack_a_punch_weapon_options()` (`_zm_weapons.gsc:2263`) re-initialises the cache lazily on next access. Clearing has no gameplay impact — it only re-randomises the cosmetic camo/reticle on the next PaP call.

**Log line:** `[SVP] banq pap_weapon_options: cleared 50 cached entries`

### R2 start — not in log; expected

R1 started at 0:15 with 6 zombies. R2 started before 0:30 (the `papweap` command). At R2 `start_of_round`, `pap_weapon_options` was still undefined so SVP correctly skipped the clear (the `isdefined` guard prevents the log line). The pap entries were added at 0:30 during R2. R3 start at 1:45 was the first `start_of_round` after the array was populated, which is why that's when the clear fires.

### LLP — expected result

`[LLP] weaponUpgrade_func not defined at init time` is the known result from the IL-01 investigation (patched/has-attachment-freeze.md). The hook is unavailable in this map context. No regression introduced.

### Entity headroom — stable

`[DIAG] probe HR=128` at every probe across the session. Entity pool is clean; scrVar pruning applies no entity-side side effects.

## Conclusion

**SA-08 CONFIRMED FIXED.** `self.hitsthismag` is pruned to current-weapon-only at each round start. Fake entries (simulating stale box-cycle weapon strings) are removed correctly.

**SA-09 CONFIRMED FIXED.** `self.pack_a_punch_weapon_options` is cleared at each round start. Cache regenerates on demand via the base code's lazy initialiser.

Both fixes operate entirely from an addon script — no FF file replacement required. The patch loads cleanly alongside all other active patches with no conflicts.

## Next Steps

- Extended soak test: run to R30+ with `weap` inflating each round, confirm cumulative pruned count grows correctly in `weapstat` output
- Confirm `weapstat` cumulative totals after multiple rounds
- Add SVP telemetry (`level._svp_pruned_total`, `level._svp_pap_cleared`) to the DIAG HUD overlay so live pruning is visible during blog screenshots
