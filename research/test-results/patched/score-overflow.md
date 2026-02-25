# Test OF-02 (Patched): Score Overflow

**Patch:** `zm_patch_overflow.gsc v1.0` — `ofp_clamp_score()` watchdog caps `player.score_total` at 999,999,999.

**Baseline result (unpatched):** Score wrapped to −2,147,483,619 at INT_MAX. Powerup drops stopped permanently. Hard crash via `G_FindConfigstringIndex: overflow` on round rollover.

## Run Metadata

| Field           | Value |
|-----------------|-------|
| Date            | 2026-02-19 |
| Map             | zm_transit / Town (gump_town) |
| Player count    | Solo |
| Plutonium build | r5246 |
| Script versions | zm_diagnostics.gsc v0.4, zm_patch_overflow.gsc v1.0, zm_stress_test.gsc |
| Patch scripts   | zm_patch_overflow.gsc |

## Procedure

1. Load `zm_patch_overflow.gsc` alongside diagnostics and stress test
2. Confirm patch banner appears: `[OFP] Overflow patch v1.0 loaded`
3. Run `/st dropinc 100` — lower threshold so drops fire frequently (confirms they're working pre-clamp)
4. Run `/st score 2147400000` — set score near INT_MAX (~83k points from overflow)
5. Kill zombies until the `[OFP] Score clamped at 999999999` message appears
6. Continue playing 2+ rounds after clamp fires
7. Verify powerup drops continue occurring after the clamp

## Results

| Check | Expected | Actual |
|-------|----------|--------|
| Patch banner on load | `[OFP] Overflow patch v1.0 loaded` | **CONFIRMED** |
| Score clamp message fires | `[OFP] Score clamped at 999999999` | **CONFIRMED** |
| Score on HUD after clamp | `999M` (not negative) | **CONFIRMED** |
| Powerup drops after clamp | Drops continue firing | **CONFIRMED** |
| Hard crash on round rollover | No crash | **CONFIRMED** |
| `G_FindConfigstringIndex` error | Does not appear | **CONFIRMED** |

## Comparison: Baseline vs Patched

| Metric | Unpatched | Patched |
|--------|-----------|---------|
| Score at overflow | −2,147,483,619 (wrapped) | 999,999,999 (clamped) |
| Powerup drops after overflow | ZERO — permanently stopped | **Continue normally** |
| Crash on round rollover | YES — `G_FindConfigstringIndex: overflow` | **No crash** |
| Config string table exhaustion | YES — 45 unique strings consumed | **Not triggered** |
| Game survives past overflow event | NO | **YES** |

## Analysis

The clamp fires when `score_total` would exceed 999,999,999. Since points are still being earned but the stored value is frozen at 999M, the powerup drop comparison `curr_total_score > score_to_drop` continues to evaluate correctly: the summed score stays above the current `score_to_drop` threshold as long as that threshold hasn't grown past 999M itself.

The `G_FindConfigstringIndex` crash is also eliminated as a side effect: the diagnostic HUD's `ScoreTotal` field no longer generates a unique config string per kill (it stays at `999M` indefinitely), so no new CS slots are consumed post-clamp.

**The fix is intentionally conservative** — a 64-bit score would be the ideal engine fix, but from GSC we can only clamp. The 999M ceiling is well above what any player reaches in normal gameplay (a 4-player high-round session rarely breaks 100M legitimately), so the clamp only fires in extreme cases and has no practical impact on normal play.

## Conclusion

**FIX CONFIRMED.** `zm_patch_overflow.gsc v1.0` successfully prevents the OF-02 score overflow bug. Powerup drops survive the previous overflow point and the game no longer crashes on round rollover. The fix required 0 changes to game logic — a single watchdog clamping one field is sufficient.
