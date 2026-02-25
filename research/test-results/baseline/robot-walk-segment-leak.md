# GR-AI-05 Test Results: Robot Walk Segment-Index Leak

**Date:** _pending_
**Status:** _pending_
**Protocol:** Test 13 in `test-protocol.md`

---

## Objective

Determine whether `animscripted(entity, origin, angles, state, N)` with different N
values accumulates separate anim info entries (instead of replacing the active one).

If confirmed: each robot walk cycle leaks 2 entries × 3 robots = 6 entries per
triple-giant round. This is the primary accumulation hypothesis for the hour 26–27 crash.

---

## Prerequisite

Baseline ceiling from GR-AI-01: **K = _** (or use animsat 20 as a relative baseline)

---

## Part A — Single cycle probe

| Step | Command | Result | Notes |
|---|---|---|---|
| Baseline | `animsat 20` | held 20 / crashed at _ | |
| Release | `animstop` | | |
| Index test | `animindex 3` | completed / crashed during | |
| Re-probe | `animsat 20` | held 20 / crashed at _ | |

**Entries leaked by one 3-call sequence:** _  
*(0 = no leak; 2 = GR-05 confirmed)*

---

## Part B — Accumulated rate (run only if Part A shows a leak)

| Simulated walk cycles | animsat probe | Entries held | Slots consumed |
|---|---|---|---|
| 0 (baseline) | 20 | _ | 0 |
| 5 | _ | _ | _ |
| 10 | _ | _ | _ |
| 20 | _ | _ | _ |

**Entries leaked per walk cycle:** _  
**Projected rounds to crash (assuming K=_ and concurrent usage of ~5):** _

---

## Conclusion

- [ ] No leak — segment-indexed calls replace existing entry; GR-05 ruled out
- [ ] 2 entries leaked per 3-call sequence — GR-05 confirmed; fix required in `robot_walk_animation`
- [ ] Other result: _

---

**GR-AI-05 verdict:** _PENDING_
