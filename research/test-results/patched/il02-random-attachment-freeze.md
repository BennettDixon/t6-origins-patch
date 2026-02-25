# IL-02 Test Result: `random_attachment()` Infinite Loop Fix

**Date:** 2026-02-20  
**Status: PASS**

---

## Bug

`random_attachment(weaponname, exclude)` in `_zm_weapons.gsc` used an unbounded
`while (true)` loop to pick a random attachment, retrying until it found one that
didn't match the `exclude` parameter. If the weapon's supported attachments list
contained exactly one entry and it equalled the excluded attachment, the loop had
no possible exit — the GSC VM spun forever, hanging the server.

```gsc
// Original (broken)
while ( true )
{
    idx = randomint( attachments.size - lo ) + lo;

    if ( !isdefined( exclude ) || attachments[idx] != exclude )
        return attachments[idx];
    // No exit when every attachment == exclude — infinite spin
}
```

---

## Fix

Replaced `while (true)` with a bounded retry loop capped at 30 iterations.
On exhaustion the function falls through and returns `"none"`:

```gsc
tries = 0;
while ( tries < 30 )  // IL-02 fix: was while(true)
{
    idx = randomint( attachments.size - lo ) + lo;

    if ( !isdefined( exclude ) || attachments[idx] != exclude )
        return attachments[idx];

    tries++;
}
return "none";
```

**Delivery:** `mod.ff` built by OAT Linker from patched source, deployed to
`%LOCALAPPDATA%\Plutonium\storage\t6\mods\zm_hrp\mod.ff`.

---

## Test

In-game console command:

```
set fftest_cmd il02
```

The test calls `random_attachment()` 50 times across three weapons (`an94_zm`,
`hk416_zm`, `ballista_zm`), rotating through four exclude values (`acog`, `grip`,
`quickdraw`, `reflex`). This maximises the chance of hitting a call where the
excluded attachment is the only eligible candidate. A 5-second countdown allows
`map_restart` before execution if the FF is suspected to be missing.

On the original code any call that hits the degenerate case hangs the server
permanently. On the patched code all 50 calls return within microseconds.

---

## Result

```
[FFTEST] IL-02 PASS — 50 random_attachment() calls returned without freeze
```

Confirmed in-game on Plutonium T6, map `zm_transit`, 2026-02-20.
