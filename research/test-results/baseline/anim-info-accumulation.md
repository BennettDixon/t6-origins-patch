# GR-AI-04 Test Results: `play_melee_attack_animation` Accumulation

**Date:** _pending_
**Status:** _pending_
**Protocol:** Test 12 in `test-protocol.md`

---

## Objective

Determine whether completed generator capture events permanently consume anim info entries — indicating that `play_melee_attack_animation` leaks on natural animation completion due to a missing `stopanimscripted()` call.

---

## Prerequisite

Ceiling K from GR-AI-01: **K = _**

---

## Method

Hold K-4 entries via `animsat`, complete capture events one at a time, and retest the ceiling after each event to detect whether the effective free headroom shrinks.

A shrinking headroom that survives zombie death confirms the leak is in the ASD entry itself, not just the zombie entity. If entity deletion frees the entry automatically, headroom should be stable.

---

## Results

| Capture events completed | `animsat` target for crash | Effective free slots | Slots consumed per event |
|---|---|---|---|
| 0 (baseline) | K = _ | _ | — |
| 1 | _ | _ | _ |
| 2 | _ | _ | _ |
| 3 | _ | _ | _ |
| 5 | _ | _ | _ |
| 10 | _ | _ | _ |

---

## genstat Snapshot During Active Capture

```
(paste [ST] genstat output here)
```

---

## Interpretation

- [ ] Effective free slots stable across events → entity deletion frees anim info; no accumulation leak; GR-03b hypothesis rejected
- [ ] Effective free slots decrease by N per event → each completed capture permanently consumes N entries; `stopanimscripted()` fix required in `play_melee_attack_animation`
- [ ] Leak only accumulates while zombies are alive, not after death → peak-count problem only, not an accumulation problem

---

**GR-AI-04 verdict:** _PENDING_
