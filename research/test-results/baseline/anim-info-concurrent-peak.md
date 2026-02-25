# GR-AI-03 Test Results: Origins Worst-Case Concurrent Overlap

**Date:** _pending_
**Status:** _pending_
**Protocol:** Test 11 in `test-protocol.md`

---

## Objective

Confirm that the crash occurs when a three-robot walk round overlaps a multi-generator capture event — and determine whether the GEN-ZC-01 fix alone prevents it.

---

## Prerequisite

Ceiling K from GR-AI-01: **K = _**

---

## Background: Expected Concurrent Count

| Source | Entries per event | Notes |
|---|---|---|
| 3 robots walking (`zm_robot_walk_nml`) | 3 | Three-robot round only (every R4, R8, …) |
| Active mechz | 0–1 | One mechz per mechz round |
| Dug-rise zombies | varies | ~1–3 briefly during spawn |
| Capture zombies (GEN-ZC-01 patched, 3 zones) | ~6 | ~2/zone |
| Capture zombies (GEN-ZC-01 unpatched, 3 zones) | ~18 | ~6/zone |
| Wind Staff stun zombies | 0–N | Depends on player use |
| **Estimated worst-case patched** | **~10–12** | |
| **Estimated worst-case unpatched** | **~22–24** | |

---

## Run 1: Unpatched (GEN-ZC-01 bug active)

| Step | Observation |
|---|---|
| Round | _ |
| `animoverlap` triggered at | _ |
| Crash occurred? | _ |
| Time from trigger to crash | _ |
| `genstat` output (capture zombie counts) | _ |
| `animstat` output (animsat count) | _ |
| HUD `Probe HR` at event | _ |

```
(paste any console output here)
```

---

## Run 2: Patched (GEN-ZC-01 fix active)

| Step | Observation |
|---|---|
| Round | _ |
| `animoverlap` triggered at | _ |
| Crash occurred? | _ |
| HUD `Probe HR` at event | _ |

```
(paste any console output here)
```

---

## Interpretation

| Scenario | Result | Conclusion |
|---|---|---|
| Unpatched crash + patched no crash | _ | GEN-ZC-01 fix is sufficient mitigation |
| Crash in both | _ | Ceiling < patched peak; further reduction needed |
| No crash in either | _ | Ceiling > 14; crash trigger is elsewhere |

---

**GR-AI-03 verdict:** _PENDING_
