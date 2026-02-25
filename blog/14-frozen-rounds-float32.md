# Frozen Rounds: Solved After a Decade — A Four-Character Fix Buried in IEEE 754

*Part 14 of the BO2 High-Round Crash Fix series.
[Part 1](01-the-archaeology.md) | [Part 2](02-the-diagnostic-tools.md) | [Part 3](03-entity-leaks.md) | [Part 4](04-the-patch.md) | [Part 5](05-results.md) | [Part 6](06-fixing-the-core.md) | [Part 7](07-origins-patched.md) | [Part 8](08-die-rise-patched.md) | [Part 9](09-the-full-patch.md) | [Part 10](10-generators-patched.md) | [Part 11](11-tank-patched.md) | [Part 12](12-testing-origins-staffs.md) | [Part 13](13-fire-staff-balance-gap.md)*

---

If you have played Origins at high rounds, you know the moment. You fire a fully-charged Ice
Staff blizzard into a horde at round 127. The ice effect hits every zombie. They all slow down.
The animation plays. And then — nothing. They just stand there. Frozen. Alive. You pull out
your starting pistol and one-shot each of them in turn, twenty-four times, wondering what
went wrong.

The community named it. "Frozen rounds" or "big frozen rounds" — rounds where the staffs simply
refuse to kill, where every zombie in the horde survives the shot with a thin sliver of health,
requiring a follow-up to finish. It has been a fixture of Origins high-round play since the
map was first pushed into the hundreds. Players developed workarounds. Theories circulated.
Nobody found the cause.

The cause is four characters: `+ 128`.

That is the entire fix. One addition, in one function, in one file. It has been reproducible
on demand since the map shipped in 2013. It affects every version of the game that has ever
existed. It was invisible to automated testing because the branching logic was correct — the
bug happened one layer below the branch decision, at the boundary between the script runtime
and the engine, where a floating-point value silently lost precision before being handed to
the damage calculator.

This post is a full account of what "frozen rounds" actually are, why they start at round 127
specifically, why only the Ice and Wind staffs are affected and not Fire or Lightning, and
how `+ 128` permanently ends them.

---

## The Community Observation

High-round Origins players have noted a consistent pattern since the map became a target for
long runs:

> *"Big frozen rounds first happened on 110. The difference between big frozen rounds and small
> frozen rounds is that on bigs the zombies get the frozen effect from the ice staff no matter
> what, even if they are undamaged. As for the Wind Staff it will create at least a few invisible
> zombies from every horde."*

Two distinct phenomena are bundled together here. "Small frozen rounds" — occasionally a zombie
in an ice blizzard survives and stands there frozen with near-zero HP — start appearing around
round 112. "Big frozen rounds" — every zombie in the blizzard survives with residual HP —
become consistent around round 127. The distinction turns out to correspond exactly to two
different float32 precision thresholds.

The claymore-swap community workaround ("holding a claymore when the ice storm goes makes
zombies die") is unrelated to damage values. It does not change damage output. What it does is
alter the weapon string passed into the death callback, which affects whether a specific
animation branch fires. The zombies were already at near-zero HP from the blizzard; the visual
difference comes from the death animation path, not from the claymore dealing additional damage.

---

## Float32 and Zombie Health

The T6 engine stores each zombie's health as a signed 32-bit integer internally. When GSC reads
`self.health`, the engine converts that integer to a 32-bit floating-point value (float32, i.e.
IEEE 754 single precision) for the script runtime.

Float32 has a 23-bit mantissa. For a value in the range \([2^k, 2^{k+1})\), the smallest
representable step is \(2^{k-23}\). Any integer in that range whose low bits don't fit in 23
bits is silently rounded down to the nearest representable multiple.

Zombie health at high rounds:

| Round | Approximate health | Representable step | Max rounding error |
|---|---|---|---|
| R112 | 16.8M | 2 | 1 HP |
| R119 | 33.6M | 4 | 3 HP |
| R127 | ~72M | 8 | **7 HP** |
| R136 | ~134M | 16 | 15 HP |
| R149 | ~537M | 64 | 63 HP |
| R160 | ~1.07B | 128 | 127 HP |
| R223+ | overflow → negative | — | insta-kill rounds |

Below round 112, health is below \(2^{24} \approx 16.7\text{M}\). In that range all integers
are exactly representable in float32 — zero rounding error. The bug does not exist there.

At round 112, health first crosses \(2^{24}\) and the step becomes 2. One in two integers is
rounded down by 1 HP. The effect is nearly invisible — a rare zombie survives with 1 HP.

At round 127 (~72M), health has crossed \(2^{26} = 67.1\text{M}\) and the step jumps to 8.
Up to 7 in every 8 integers round down. The majority of zombies survive the staff shot with
residual HP in the range 1–7. The frozen effect appears on nearly every zombie in the horde,
consistently, every blizzard. This is "big frozen rounds."

The threshold at round 127 is not magic. It is simply where health crosses the next power of 2.

---

## The Kill Chain

When a staff intends to kill a zombie outright, it calls `do_damage_network_safe` in
`zm_tomb_utility.gsc` with the zombie's health as the damage amount:

```gsc
// staff_water_kill_zombie() — _zm_weap_staff_water.gsc:124
self do_damage_network_safe( player, self.health, str_weapon, "MOD_RIFLE_BULLET" );

// whirlwind_drag_zombie() — _zm_weap_staff_air.gsc:190
self do_damage_network_safe( player, self.health, str_weapon, "MOD_IMPACT" );
```

`do_damage_network_safe` queues the actual kill through the network choke system:

```gsc
// do_damage_network_safe() — zm_tomb_utility.gsc
do_damage_network_safe( e_attacker, n_amount, str_weapon, str_mod )
{
    if ( isdefined( self.is_mechz ) && self.is_mechz )
        self dodamage( n_amount, ... );              // mechz: direct
    else if ( n_amount < self.health )
        // partial damage path (queued, choked)
    else
        // kill path (queued, choked)
        self maps\mp\zombies\_zm_net::network_choke_action(
            "dodamage_kill", ::_kill_zombie_network_safe_internal, e_attacker, str_weapon );
}
```

For the kill path, `_kill_zombie_network_safe_internal` executes after the network choke clears:

```gsc
_kill_zombie_network_safe_internal( e_attacker, str_weapon )
{
    if ( !isdefined( self ) || !isalive( self ) )
        return;

    self.staff_dmg = str_weapon;
    self dodamage( self.health, self.origin, e_attacker, e_attacker, "none",
                   self.kill_damagetype, 0, str_weapon );
}
```

**The problem is on the last line.** `self.health` is read again as float32 and passed directly
to the engine's `dodamage`. The engine receives a float and converts it back to an integer for
health subtraction.

At round 127, let the zombie's true integer health be \(H\). GSC reads \(H_f = \lfloor H / 8
\rfloor \times 8\) (float32 rounds down to the nearest multiple of 8). The `dodamage` call
deals \(H_f\) damage. The zombie's remaining health is:

$$H - H_f = H \bmod 8$$

For any zombie whose health is not a multiple of 8, this is 1–7 HP. The zombie survives.

**Crucially, this does not register as an error in the branching logic.** Both reads of
`self.health` in `do_damage_network_safe` and `_kill_zombie_network_safe_internal` return the
same float32 value \(H_f\). The comparison `n_amount < self.health` evaluates as `H_f < H_f` —
false — so the kill path is always taken. The branching is correct. The rounding happens at the
engine boundary, after the script has already committed to the kill path.

---

## Why Ice and Wind Are Affected; Fire and Lightning Are Not

All four staffs include `zm_tomb_utility.gsc` and call `do_damage_network_safe`. The difference
is *when* they reach the `self.health` path — and for two of them, the answer is never at high
rounds.

### Ice Staff — unconditional `self.health`

The blizzard kill loop calls `ice_affect_zombie` with `always_kill = 1` hardcoded:

```gsc
// ice_staff_blizzard_do_kills() — _zm_weap_staff_water.gsc:254
if ( isalive( zombie ) )
    zombie thread ice_affect_zombie( str_weapon, player, 1 );  // always_kill = 1

// ice_affect_zombie() — _zm_weap_staff_water.gsc:~380
if ( instakill_on || always_kill )         // always true from blizzard
{
    wait_network_frame();
    staff_water_kill_zombie( e_player, str_weapon );
}

// staff_water_kill_zombie() — _zm_weap_staff_water.gsc:124
self do_damage_network_safe( player, self.health, str_weapon, "MOD_RIFLE_BULLET" );
```

`always_kill = 1` is not a runtime check — it is always 1 from the blizzard path. Every zombie
inside the radius on every blizzard tick, at every round number, goes through `self.health` as
kill damage. There is no condition that could make this path avoid the float32 issue.

### Wind Staff — unconditional `self.health`

`whirlwind_drag_zombie` deals `self.health` when a zombie reaches the whirlwind center:

```gsc
// whirlwind_drag_zombie() — _zm_weap_staff_air.gsc
self whirlwind_move_zombie( e_whirlwind );

if ( isdefined( self ) && isdefined( e_whirlwind ) && flag( "whirlwind_active" ) )
{
    player = e_whirlwind.player_owner;
    self do_damage_network_safe( player, self.health, str_weapon, "MOD_IMPACT" );
    level thread staff_air_gib( self );
}
```

Same structure: the damage is `self.health`, no qualifying condition on round number. Every
zombie that successfully reaches the whirlwind center is subject to the rounding error.

This produces a different visual symptom than the ice staff. The zombie has completed the
whirlwind-drag animation — it is at the center of the whirlwind, linked to a `script_origin`
entity. With 1–7 HP remaining rather than being dead, it enters the "alive but linked to a
deleted entity" orphaned state described in [Part 3d](03d-wind-staff-invisible-zombies.md).
The zombie is invisible or frozen, still alive, still damaging players. The float32 bug
contributes a second distinct cause of invisible wind staff zombies on top of the
orphaned-link timing bug already documented.

### Lightning Staff — `self.health` unreachable above round ~15

The lightning ball applies repeated timed pulses. The `self.health` path is only reached when
a single pulse already exceeds the zombie's HP:

```gsc
// staff_lightning_ball_damage_over_time() — _zm_weap_staff_lightning.gsc:251
n_damage_per_pulse = get_lightning_ball_damage_per_sec( chargeshotlevel );
// maximum: 3,500 (charge level 3)

if ( n_damage_per_pulse < e_target.health && !instakill_on )
    e_target do_damage_network_safe( e_attacker, n_damage_per_pulse, ... );  // fixed value
else
    e_target thread staff_lightning_kill_zombie( e_attacker, str_weapon );
    // → do_damage_network_safe( player, self.health, ... )
```

`get_lightning_ball_damage_per_sec` returns at most 3,500. Zombie health crosses 3,500 around
round 15. Above that, the condition `n_damage_per_pulse < e_target.health` is always true and
the `self.health` kill path is permanently unreachable. The lightning staff kills by attrition —
repeated 3,500-damage pulses until the zombie's health naturally reaches zero through the
partial-damage branch. Each pulse uses a fixed value, never `self.health`. No float32 rounding
issue at any round.

### Fire Staff — `self.health` unreachable above round ~4

The fire staff's impact handler has a `self.health` fast-kill path, but it is guarded by two
conditions: the fixed impact damage must already exceed the zombie's HP, and a coin flip must
succeed:

```gsc
// flame_damage_fx() — _zm_weap_staff_fire.gsc:276
n_initial_dmg = get_impact_damage( damageweapon );
// maximum: 20,000 (staff_fire_upgraded3_zm — confirmed in get_impact_damage() switch block)

if ( is_upgraded && pct_damage > 0.5 && n_initial_dmg > self.health && cointoss() )
{
    self do_damage_network_safe( e_attacker, self.health, damageweapon, "MOD_BURNED" );
    return;  // fast-kill path
}

// Otherwise: apply n_initial_dmg impact + start flame_damage_over_time (450 DPS)
self do_damage_network_safe( e_attacker, n_initial_dmg, damageweapon, "MOD_BURNED" );
```

`n_initial_dmg` tops out at 20,000 for the fully upgraded staff. Zombie health exceeds 20,000
by approximately round 22. Above that, `n_initial_dmg > self.health` is permanently false, the
fast-kill branch is dead code, and the staff deals fixed 20,000 impact damage plus the burn
thread — both using fixed values, never `self.health`. No float32 exposure.

(This is the same structural limitation documented in Part 13: the fire staff's effective
kill ceiling is a design gap exposed after the SA-10 bug was fixed, not a consequence of this
float32 issue.)

### Summary

| Staff | `self.health` kill path | Reachable at R127? | Float32 affected? |
|---|---|---|---|
| Ice | `always_kill = 1` — unconditional | **Always** | **Yes** |
| Wind | Whirlwind center arrival — unconditional | **Always** | **Yes** |
| Lightning | `pulse_damage >= zombie HP` — impossible above R15 | Never | No |
| Fire | `impact_damage >= zombie HP` — impossible above R22 | Never | No |

The fire and lightning staffs are immune not because they avoid the `do_damage_network_safe`
function, but because the specific branch inside it that reads `self.health` is unreachable
once zombie health has grown beyond those weapons' fixed damage caps. The ice and wind staffs
have no such gate.

---

## The Fix

The rounding error occurs inside `_kill_zombie_network_safe_internal` when it passes `self.health`
(a float32, potentially 1–127 less than the true integer value) to the engine's `dodamage`. The
fix is to add a buffer that always exceeds the maximum possible rounding error for any round up
to the int32 overflow at ~R223.

The maximum float32 rounding error for a value in the range \([2^k, 2^{k+1})\) is \(2^{k-23} -
1\). The worst case before R223 is \([2^{30}, 2^{31})\) (~R160–R222), where the precision step
is 128 and the maximum error is 127.

Choosing 128 as the buffer:
- It is a power of 2, so `self.health + 128` is always exactly representable in float32 (adding
  an exact power of 2 to a float32 value never introduces a new rounding error).
- 128 \(>\) 127 — it strictly exceeds the worst-case error at every round from R112 to R222.
- Above R223, zombie health wraps negative in the engine and zombies die from any hit. The kill
  path here is moot.

```gsc
// zm_tomb_utility.gsc — _kill_zombie_network_safe_internal (patched)
_kill_zombie_network_safe_internal( e_attacker, str_weapon )
{
    if ( !isdefined( self ) )
        return;

    if ( !isalive( self ) )
        return;

    self.staff_dmg = str_weapon;
    // [HRP] At high rounds, GSC reads self.health as float32, which truncates to the
    // nearest representable multiple, losing up to (precision_step - 1) from the true
    // integer health stored in the engine.  The precision step doubles each time health
    // crosses a power of 2:
    //
    //   R127+ (~67M, 2^26): step = 8,   max error = 7
    //   R136+ (~134M, 2^27): step = 16,  max error = 15
    //   R149+ (~537M, 2^29): step = 64,  max error = 63
    //   R160+ (~1.07B, 2^30): step = 128, max error = 127  ← worst case before R223 overflow
    //
    // Adding 128 is the minimum buffer that beats every possible rounding error for all
    // rounds up to the int32 overflow at ~R223 (where insta-kill rounds begin and this
    // code path no longer matters).  At each range, 128 is an exact float32 value (a
    // power of 2), so the addition itself introduces no additional rounding.
    self dodamage( self.health + 128, self.origin, e_attacker, e_attacker, "none",
                   self.kill_damagetype, 0, str_weapon );
}
```

This fix applies to the single shared kill function used by both the Ice Staff blizzard and the
Wind Staff whirlwind. One change covers both weapons at all round numbers.

---

## A Note on the Diagnostic Results

During testing, the MI-09 diagnostic (`do_damage_network_safe` branch counter) consistently
showed 0 on both the kill path and the partial path even when frozen zombies were visible. This
was confusing until the mechanism was understood.

The counter shows 0 on the partial path because `n_amount < self.health` evaluates as `H_f < H_f`
— false. The kill path IS taken. The counter shows 0 on the kill path because the diagnostic was
armed after the shots were fired, not before. The branch counters only accumulate while
`level._hrp_mi09_diag` is defined.

The correct takeaway from those results was not "the function isn't being called" but rather
"the function is taking the kill path, but the kill path itself produces wrong results at the
engine boundary." The bug was one level deeper than the branch decision — it was in what the
kill path passed to `dodamage`.

---

## In-Game Validation

The MI-12 diagnostic was built specifically to verify this fix. It hooks on the `blizzard_shot`
level notification the ice staff already fires, waits for the blizzard to end (via a
`blizzard_ended` notification added as part of the patch), then scans every living zombie for
the `is_on_ice = 1` flag three seconds later. A zombie still alive and flagged at that point is
unambiguously a frozen-round survivor — the kill call ran, but the damage fell short.

**Unpatched (baseline at R127):**

```
[ST] MI-12 R127: 21 frozen survivor(s) — fix NOT active.
```

Of a 24-zombie horde, 21 survived with 1–7 HP each. The 3 that died were the ones whose true
integer health happened to be divisible by 8, meaning the float32 truncation matched exactly.

**Patched (`self.health + 128` in `_kill_zombie_network_safe_internal`):**

```
[ST] MI-12 R127: blizzard clean — 0 frozen survivors.
[ST] MI-12 R134: blizzard clean — 0 frozen survivors.
[ST] MI-12 R144: blizzard clean — 0 frozen survivors.
```

Zero frozen survivors across every round tested. The blizzard kills cleanly at every round,
including rounds well past the original threshold.

The diagnostic was run over multiple blizzards per round and across multiple sessions. The
result is consistent: before the patch, frozen rounds are reproducible on demand above R127.
After the patch, they do not occur.

---

## Correcting Part 13

Part 13 stated that the Water and Wind staffs "always killed regardless of round number via
`self.health` paths." This was the design intent, not the observed behaviour. Both weapons
always reach the `self.health` path — but the value they read is a float32 truncation, not the
true integer health. The intent fails at round 127 precisely because the mechanism meant to
guarantee round-scaling (passing `self.health` as damage) develops a precision gap just as
health grows large enough for float32 to misrepresent integers.

The fire and lightning staffs, which appear weaker in Part 13, are accidentally immune to this
specific failure because their damage floors are low enough that they never reach the
`self.health` path at high rounds.

---

## Summary

"Frozen rounds" — a community-named phenomenon that has affected Origins high-round play since
2013 — are caused by a float32 precision error at the boundary between the GSC script runtime
and the engine's `dodamage` function. The cause is now confirmed and the fix is deployed.

- GSC reads `self.health` as float32. Above round 127 (~72M health), float32 can only represent
  multiples of 8 in this range. The value is silently rounded down by 1–7.
- The staff passes this rounded value to `dodamage`. The engine subtracts it from the zombie's
  true integer health. The zombie survives with the difference: 1–7 HP.
- The branching in `do_damage_network_safe` is not wrong — the kill path is taken correctly.
  The error happens after the branch decision, when the truncated float is converted back to an
  integer by the engine. This is why diagnostic logging on the branch itself showed nothing
  unusual — the branch was fine. The damage calculation below it was not.
- "Small frozen rounds" (occasional single-zombie residuals) start at ~R112, when health first
  crosses \(2^{24}\) and float32 precision drops to 2. "Big frozen rounds" (whole-horde
  residuals) start at ~R127, when health crosses \(2^{26}\) and the precision step reaches 8.
  The thresholds are not magic — they are just powers of 2.
- The Ice and Wind staffs are affected because they unconditionally use `self.health` as kill
  damage. The Fire and Lightning staffs are not affected because their fixed-value damage caps
  make the `self.health` path unreachable above rounds 22 and 15 respectively — an accidental
  immunity.
- The fix is `self.health + 128` in `_kill_zombie_network_safe_internal`. One function, one
  line, four characters. 128 is the minimum power-of-2 buffer that exceeds the worst-case
  float32 rounding error at every round from R112 to the int32 overflow at ~R223. It is exactly
  representable as float32, so the addition itself introduces no further error.
- Validated in-game with the MI-12 diagnostic: 21 of 24 zombies survived the blizzard at R127
  before the patch; 0 survived after. The fix holds at every round tested through R144.

The fix is four characters. The bug is twelve years old. In retrospect, it was always going to
be something like this.

*All scripts and source at [github.com/banq/t6-high-round-fix](#).*
