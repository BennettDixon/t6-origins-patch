# GR-AI-01 Test Results: Anim Info Ceiling

**Date:** _pending_
**Status:** _pending_
**Protocol:** Test 9 in `test-protocol.md`

---

## Objective

Find the engine's anim info table size — the maximum number of simultaneous `animscripted` entries before the `exceeded maximum number of anim info` crash.

---

## Calibration

| ASD state tried | Zombie froze in animation? | Notes |
|---|---|---|
| `"zm_walk"` | _ | |
| `"zm_run"` | _ | |
| `"zm_sprint"` | _ | |

**State confirmed:** _

---

## Fill Test Runs

| Run | N requested | N held (`AnimSat` HUD) | Crash? | Error in console? |
|---|---|---|---|---|
| 1 | 4 | _ | No | |
| 1 | 6 | _ | No | |
| 1 | 8 | _ | _ | |
| 1 | 10 | _ | _ | |
| 1 | 12 | _ | _ | |
| 1 | 14 | _ | _ | |
| 1 | 16 | _ | _ | |
| 1 | 18 | _ | _ | |
| 1 | 20 | _ | _ | |
| 1 | 24 | _ | _ | |
| 1 | 28 | _ | _ | |
| 1 | 32 | _ | _ | |
| 2 (repeat) | _ | _ | _ | |
| 3 (repeat) | _ | _ | _ | |

**Confirmed safe maximum:** _  
**Crash threshold N:** _  
**Confirmed consistent across runs:** _

---

## Console Output at Crash

```
(paste exact error from games_mp.log here)
```

---

## Notes

_

---

**GR-AI-01 verdict:** _PENDING_
