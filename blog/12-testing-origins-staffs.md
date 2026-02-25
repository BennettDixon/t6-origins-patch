# Testing Origins: What It Takes to Give Yourself a Staff

*Part 12 of the BO2 High-Round Crash Fix series.
[Part 1](01-the-archaeology.md) | [Part 2](02-the-diagnostic-tools.md) | [Part 3](03-entity-leaks.md) | [Part 4](04-the-patch.md) | [Part 5](05-results.md) | [Part 6](06-fixing-the-core.md) | [Part 7](07-origins-patched.md) | [Part 8](08-die-rise-patched.md) | [Part 9](09-the-full-patch.md) | [Part 10](10-generators-patched.md) | [Part 11](11-tank-patched.md) | [Part 13](13-fire-staff-balance-gap.md)*

---

Part 7 documented two Origins bugs — SA-10 (Fire Staff AoE thread burst) and MI-06
(Wind Staff whirlwind anchoring to a dead zombie). To verify those fixes in-game, the
test script needed to hand the player a staff directly, bypassing the hours of Easter
Egg progress the game normally requires.

That turned out to be more interesting than expected.

---

## What the Game Actually Does

Origins staffs are not Mystery Box weapons. They're craftables — assembled from four
pieces found around the map, then placed into an elemental pedestal. Picking up the
completed staff from the pedestal is handled by `zm_tomb_craftables.gsc`:

```gsc
// tomb_check_crafted_weapon_persistence():
s_elemental_staff = get_staff_info_from_weapon_name( self.stub.weaponname, 0 );
player maps\mp\zombies\_zm_weapons::weapon_give( s_elemental_staff.weapname, 0, 0 );

if ( isdefined( s_elemental_staff.prev_ammo_stock ) && isdefined( s_elemental_staff.prev_ammo_clip ) )
{
    player setweaponammostock( s_elemental_staff.weapname, s_elemental_staff.prev_ammo_stock );
    player setweaponammoclip( s_elemental_staff.weapname, s_elemental_staff.prev_ammo_clip );
}
```

Two things happen: a call to `weapon_give` (a GSC wrapper in `_zm_weapons.gsc`, not the
engine's `giveweapon` builtin), followed by explicit ammo restoration via
`setweaponammostock` / `setweaponammoclip`.

The ammo values come from a struct initialized at map start in `zm_tomb_main_quest.gsc`:

```gsc
// For each upgraded staff, at map load:
staff_upgraded.prev_ammo_clip  = weaponclipsize( staff_upgraded.weapname );
staff_upgraded.prev_ammo_stock = weaponmaxammo( staff_upgraded.weapname );
```

This means the ammo values are read from the weapon table once at startup and stored on
the level. `track_staff_weapon_respawn()` then updates them every half-second while the
player holds the staff, so if the player drops it, the pedestal can hand it back with
the exact ammo it had when dropped.

---

## Why the Naive Approach Crashed

The first test command tried the obvious:

```gsc
self giveweapon( "staff_fire_upgraded3_zm" );
self setweaponammoclip( "staff_fire_upgraded3_zm", 60 );
self setweaponammostock( "staff_fire_upgraded3_zm", 300 );
```

This hard crashed with `0xC0000005` (access violation) inside
`plutonium-bootstrapper-win32.exe`. No GSC log survived — the crash happened before the
log buffer flushed. Because the crash address was inside the bootstrapper rather than a
script, it was a native engine crash triggered by the GSC call.

The culprit was `setweaponammoclip` / `setweaponammostock` being called on a weapon
that was given via plain `giveweapon` without the engine first having fully initialized
its internal ammo state. For ordinary weapons, `giveweapon` allocates the ammo
structure. For staves, it doesn't — the craftables system normally manages this through
`weapon_give`, which calls `givestartammo` internally before any ammo setters are used.
Calling the setters on an uninitialized ammo struct dereferences a null pointer inside
the engine.

Attempts to fix this by waiting a frame, adding `hasweapon` guards, or calling
`givestartammo` manually before the setters all crashed the same way. `givemaxammo`
didn't crash but left the staff at 0/0 because the weapon table definition for upgraded
staves deliberately lists `start_ammo = 0` and `max_ammo = 0` — ammo is meant to be
set by the craftables system, not the weapon table.

The attempt to use `get_pack_a_punch_weapon_options` (mimicking what `weapon_give`
internally does for PaP weapons) also crashed:

```gsc
// This crashes — staves are not PaP weapons and have no options table entry:
pap_opts = self maps\mp\zombies\_zm_weapons::get_pack_a_punch_weapon_options( weap );
self giveweapon( weap, 0, pap_opts );
```

`weapon_give` calls this function only when `is_weapon_upgraded()` returns true — which
it does for any weapon whose name contains "upgraded". Staves satisfy that check but
don't have an entry in the PaP options table. The function derefs a null struct field.

---

## The Key Insight: Base Staves Have Real Ammo

At this point the investigation turned diagnostic. A simpler command was added that
just gave the base (un-upgraded) Fire Staff and read back its ammo:

```gsc
weap = "staff_fire_zm";
self giveweapon( weap );
clip  = self getweaponammoclip( weap );
stock = self getweaponammostock( weap );
iprintln( "^2[ST] " + weap + " — ammo: " + clip + "/" + stock );
```

Result: **9/81**. The base staff had fully initialized ammo from a plain `giveweapon`.

The difference: the base staff (`staff_fire_zm`) has a normal weapon table definition
with real ammo counts. The upgraded variants (`staff_fire_upgraded_zm`,
`staff_fire_upgraded2_zm`, `staff_fire_upgraded3_zm`) all have 0 in the weapon table —
their ammo is entirely managed externally by the craftables system's
`prev_ammo_clip`/`prev_ammo_stock` tracking. When those variants are given via plain
`giveweapon` without the craftables context, the engine's ammo struct is allocated with
zero capacity, and any subsequent ammo setter crashes against it.

For the Fire Staff fix (SA-10), this was enough. The AoE dedup bug applies identically
to all fire staff tiers — the `flame_damage_fx` thread burst happens whether you're
using the base staff or the fully upgraded one. Using `staff_fire_zm` (base, 9/81 ammo
out of the box) is sufficient to observe and verify the fix.

---

## The Wind Staff Is Different

MI-06 is more specific. The bug lives in `staff_air_find_source()`:

```gsc
watch_staff_air_impact()
{
    while ( true )
    {
        self waittill( "projectile_impact", str_weap_name, v_explode_point, ... );

        if ( str_weap_name == "staff_air_upgraded2_zm" || str_weap_name == "staff_air_upgraded3_zm" )
            self thread staff_air_find_source( v_explode_point, str_weap_name );
    }
}
```

The function only fires on `projectile_impact` events from `staff_air_upgraded2_zm`
or `staff_air_upgraded3_zm`. The base Wind Staff fires a direct cone (handled by
`watch_staff_air_fired`, which listens to `missile_fire`) with no projectile impact
event at all. The base staff never triggers the MI-06 code path.

`staff_air_upgraded2_zm` and `staff_air_upgraded3_zm` are not separate weapons you
pick up. They are the **charged shots** of `staff_air_upgraded_zm` — the standard
charger-pedestal upgrade. When the player holds the fire button, the staff charges up
via `chargeshotlevel`. When they release it, the charged projectile fires and its
impact registers in the engine as `upgraded2_zm` (one charge tier) or `upgraded3_zm`
(full charge). The two weapon names represent the charged blast at different power
levels, not two separate weapons in inventory.

This meant we needed `staff_air_upgraded_zm` specifically — the first EE upgrade.

---

## Giving the Upgraded Staff

The craftables system gives the upgraded staff via `weapon_give`, which calls the
`giveweapon` engine function without PaP options (the `is_weapon_upgraded()` check
returns true for the staff but the staff isn't in the PaP table — the game's own
`weapon_give` avoids calling `get_pack_a_punch_weapon_options` for it through a
different code path). We replicated that by calling plain `giveweapon` and mirroring
the craftables ammo initialization:

```gsc
weap = "staff_air_upgraded_zm";
self giveweapon( weap );

// Mirror zm_tomb_craftables.gsc lines 1149-1152:
// read ammo capacity from weapon table, fall back to base staff values if 0.
n_clip  = weaponclipsize( weap );
n_stock = weaponmaxammo( weap );
if ( n_clip  <= 0 ) n_clip  = 9;
if ( n_stock <= 0 ) n_stock = 81;
self setweaponammoclip( weap, n_clip );
self setweaponammostock( weap, n_stock );
```

This did not crash, gave the staff with working ammo — and then the staff was
immediately taken away.

---

## The Validator

`watch_staff_usage()` in `zm_tomb_utility.gsc` runs a check on every `weapon_change`
event. It walks the player's primary weapon list and enforces a rule:

```gsc
// watch_staff_usage(), called on every weapon_change:
foreach ( str_weapon in a_str_weapons )
{
    if ( is_weapon_upgraded_staff( str_weapon ) )
    {
        has_upgraded_staff = 1;
        str_upgraded_staff_weapon = str_weapon;
    }
    if ( str_weapon == "staff_revive_zm" )
        has_revive_staff = 1;
}

// Developer-only bypass:
/#
if ( has_upgraded_staff && !has_revive_staff )
    has_revive_staff = 1;
#/

// In retail/Plutonium:
if ( has_upgraded_staff && !has_revive_staff )
{
    self takeweapon( str_upgraded_staff_weapon );
    has_upgraded_staff = 0;
}
```

An upgraded staff can only be held if `staff_revive_zm` — the Origins Zombie Shield —
is also in inventory. The `/#...#/` developer bypass that would skip this check is not
compiled in Plutonium builds. In normal gameplay this invariant is always satisfied:
you craft the Zombie Shield before you can complete the staff pedestal step. When
giving the staff directly, the check fires on the next `weapon_change` event — which
is immediately, because the command calls `switchtoweapon` right after the give — and
the staff is revoked before the player can blink.

The fix is one extra line before the staff give:

```gsc
self giveweapon( "staff_revive_zm" );  // satisfy watch_staff_usage() validator
self giveweapon( "staff_air_upgraded_zm" );
// ... ammo init ...
```

With both weapons in inventory when `switchtoweapon` fires, `watch_staff_usage()`
finds `has_upgraded_staff = 1` and `has_revive_staff = 1`, passes the check, and
leaves everything alone.

---

## The Final Command

The complete `givestaffair` command, after all of the above:

```gsc
st_cmd_givestaffair()
{
    // watch_staff_usage() takes back upgraded staff if staff_revive_zm absent.
    // Give both together so the validator is satisfied on the weapon_change event.
    self giveweapon( "staff_revive_zm" );

    weap = "staff_air_upgraded_zm";
    self giveweapon( weap );
    if ( !self hasweapon( weap ) )
    {
        iprintln( "^1[ST] giveweapon failed for " + weap + " — zm_origins only" );
        return;
    }
    n_clip  = weaponclipsize( weap );
    n_stock = weaponmaxammo( weap );
    if ( n_clip  <= 0 ) n_clip  = 9;
    if ( n_stock <= 0 ) n_stock = 81;
    self setweaponammoclip( weap, n_clip );
    self setweaponammostock( weap, n_stock );
    self switchtoweapon( weap );
    iprintln( "^2[ST] Given " + weap + " + staff_revive_zm — " + n_clip + "/" + n_stock );
    iprintln( "^3[ST] MI-06 test: HOLD fire to charge up a shot, then release." );
}
```

This is what it takes to hand someone a staff without the Easter Egg: replicate the
craftables ammo initialization, satisfy the weapon validator, and understand that the
charged shots are ephemeral weapon name events, not inventory items.

---

## What This Reveals About the Staff System

The Origins staff system is the most complex weapon subsystem in the game:

- **Ammo is not in the weapon table.** Upgraded staves define 0/0 in the weapon table.
  Ammo is tracked externally by the craftables system and restored on each pickup.
- **Weapon names are not one-to-one with inventory slots.** `upgraded2_zm` and
  `upgraded3_zm` are event labels for projectile impacts, not distinct pickups.
- **Inventory has enforced invariants.** `watch_staff_usage()` validates weapon
  combinations on every switch. The developer bypass for this check is not present
  in Plutonium.
- **`weapon_give` and `giveweapon` are not equivalent.** The GSC wrapper `weapon_give`
  handles ammo initialization, equipment tracking, PaP option lookup, and several
  special cases. Calling the engine builtin directly bypasses all of that — and for
  some weapons, that bypass is fatal.

For testing purposes: base staves (`staff_fire_zm`, `staff_air_zm`) work with plain
`giveweapon` because their weapon table definitions are complete. Upgraded staves
require replicating the craftables system's give sequence.

*All scripts, research, and source are at [github.com/banq/t6-high-round-fix](#).*
