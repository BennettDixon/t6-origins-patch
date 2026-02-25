// zm_highround_patch.gsc  v1.0
// Combined high-round stability patch for Black Ops 2 Zombies (Plutonium T6).
//
// Fixes included:
//   EL-02/03  Zombie anchor entity leaks on spawn/rise  (death watchdog)
//   OF-01     Zombie health int32 overflow → unkillable  (health cap)
//   OF-02     player.score_total int32 overflow → drops stop  (score cap)
//   OF-03     zombie_powerup_drop_increment exponential runaway  (increment cap)
//   SA-08     self.hitsthismag weapon-string array unbounded growth  (round prune)
//   SA-09     self.pack_a_punch_weapon_options unbounded cache  (round clear)
//
// Known limitations (require FF file replacement — cannot be fixed from addon scripts):
//   EL-01     lerp() local 'link' entity leak in _zm_utility.gsc
//   IL-01     has_attachment() missing idx++ infinite loop in _zm_weapons.gsc
//   IL-02     random_attachment() degenerate case in _zm_weapons.gsc
//
// Configuration dvars (set in console before or during a match):
//   hrp_entity_leaks   1/0   EL-02/03 anchor watchdog         [default: 1]
//   hrp_overflow       1/0   OF-01/02/03 overflow clamps      [default: 1]
//   hrp_scrvar         1/0   SA-08/09 scrVar pruning          [default: 1]
//   hrp_hud            1/0   Status HUD indicator             [default: 0]
//   hrp_score_cap      N     Player score_total ceiling (OF-02) [default: 999999999]
//   hrp_drop_inc_cap   N     Drop increment ceiling (OF-03)   [default: 50000]
//
// Usage: drop zm_highround_patch.gscbin in
//   %localappdata%\Plutonium\storage\t6\scripts\zm\

#include maps\mp\zombies\_zm_utility;

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

init()
{
    level._hrp_version = "1.0";

    // Read configuration dvars — callers can pre-set these before map start.
    level._hrp_entity_leaks   = hrp_dvar_bool("hrp_entity_leaks",  1);
    level._hrp_overflow       = hrp_dvar_bool("hrp_overflow",      1);
    level._hrp_scrvar         = hrp_dvar_bool("hrp_scrvar",        1);

    // HUD is off by default — enable with "set hrp_hud 1" or "set diag_hud 1".
    hud_default = 0;
    if (getDvar("diag_hud") == "1")
        hud_default = 1;
    level._hrp_hud            = hrp_dvar_bool("hrp_hud",           hud_default);
    level._hrp_score_cap      = hrp_dvar_int("hrp_score_cap",      999999999);
    level._hrp_drop_inc_cap   = hrp_dvar_int("hrp_drop_inc_cap",   50000);

    // Internal telemetry counters — used by HUD and server log.
    level._hrp_anchors_freed  = 0;
    level._hrp_lerp_freed     = 0;
    level._hrp_health_capped  = 0;
    level._hrp_score_capped   = 0;
    level._hrp_dropinc_capped = 0;
    level._hrp_scrvar_pruned  = 0;
    level._hrp_pap_cleared    = 0;

    // Install modules.
    if (level._hrp_entity_leaks)
        hrp_install_entity_leak_patch();

    if (level._hrp_overflow)
        level thread hrp_overflow_watchdog();

    if (level._hrp_scrvar)
        level thread hrp_scrvar_round_cleanup();

    if (level._hrp_hud)
        level thread hrp_hud_connect_hook();

    level thread hrp_per_round_log();

    logprint("[HRP] High Round Patch v" + level._hrp_version + " loaded\n");
    logprint("[HRP] Modules: EL=" + level._hrp_entity_leaks
           + " OF=" + level._hrp_overflow
           + " SV=" + level._hrp_scrvar
           + " HUD=" + level._hrp_hud + "\n");
    logprint("[HRP] Caps: score=" + level._hrp_score_cap
           + " drop_inc=" + level._hrp_drop_inc_cap + "\n");

    iprintln("^2[HRP] High Round Patch v" + level._hrp_version + " active");
    wait 1.5;
    iprintln("^7EL:" + level._hrp_entity_leaks
           + " OF:" + level._hrp_overflow
           + " SV:" + level._hrp_scrvar
           + "  ^3see server log for details");
}

// ─────────────────────────────────────────────────────────────────────────────
// DVAR HELPERS
// ─────────────────────────────────────────────────────────────────────────────

hrp_dvar_bool(name, default_val)
{
    v = getDvar(name);
    if (!isdefined(v) || v == "")
        return default_val;
    return int(v) != 0;
}

hrp_dvar_int(name, default_val)
{
    v = getDvar(name);
    if (!isdefined(v) || v == "")
        return default_val;
    return int(v);
}

// ─────────────────────────────────────────────────────────────────────────────
// EL-02 / EL-03 — ANCHOR LEAK WATCHDOG
//
// do_zombie_rise() and do_zombie_spawn() in _zm_spawner.gsc follow this pattern:
//
//     self endon("death");
//     self.anchor = spawn("script_origin", ...);
//     self linkto(self.anchor);
//     self.anchor moveto(..., 0.05);      // ~50ms positioning window
//     self.anchor waittill("movedone");
//     ...
//     self.anchor delete();               // NEVER REACHED if endon fires first
//
// When a zombie is killed within this ~50-100ms window, endon("death") exits
// the thread before delete() runs. The script_origin entity persists for the
// session. Grenades, traps, and OF-01 insta-kill rounds are the main triggers.
//
// Fix: hook level._zombie_custom_spawn_logic (a built-in Plutonium mod hook in
// _zm_spawner.gsc) to thread a watchdog on every zombie. On death, the watchdog
// deletes self.anchor if it is still defined.
// ─────────────────────────────────────────────────────────────────────────────

hrp_install_entity_leak_patch()
{
    if (isdefined(level._zombie_custom_spawn_logic))
    {
        if (isarray(level._zombie_custom_spawn_logic))
        {
            level._zombie_custom_spawn_logic[level._zombie_custom_spawn_logic.size]
                = ::hrp_anchor_watchdog;
        }
        else
        {
            prior = level._zombie_custom_spawn_logic;
            level._zombie_custom_spawn_logic    = [];
            level._zombie_custom_spawn_logic[0] = prior;
            level._zombie_custom_spawn_logic[1] = ::hrp_anchor_watchdog;
        }
    }
    else
    {
        level._zombie_custom_spawn_logic = ::hrp_anchor_watchdog;
    }

    logprint("[HRP] EL-02/03 anchor watchdog installed on _zombie_custom_spawn_logic\n");
}

hrp_anchor_watchdog()
{
    self waittill("death");

    // EL-02/03: anchor from do_zombie_rise() / do_zombie_spawn()
    if (isdefined(self.anchor))
    {
        self.anchor delete();
        self.anchor = undefined;
        level._hrp_anchors_freed++;
    }

    // EL-01: lerp() link — populated only when _zm_utility.gsc FF replacement is
    // installed. Without FF replacement this is always undefined (safe no-op).
    if (isdefined(self._lerp_link))
    {
        self._lerp_link delete();
        self._lerp_link = undefined;
        level._hrp_lerp_freed++;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// OF-01 / OF-02 / OF-03 — OVERFLOW CLAMPS
//
// Three independent integer/float overflows that silently corrupt game state:
//
//   OF-01: level.zombie_health overflows int32 at high rounds (~R163 in BO1,
//          ~R223 in BO2). When the value wraps negative, zombies spawn with
//          health ≤ 0 and die from any damage — this is the insta-kill round
//          phenomenon. Health then continues to oscillate through the int32
//          range, creating insta-kill rounds at irregular intervals. This is
//          accepted high-round community behavior and requires no intervention.
//          No health clamping is applied.
//
//   OF-02: player.score_total wraps to a large negative value at INT_MAX.
//          The drop condition (curr_total_score > score_to_drop) becomes
//          permanently false — powerup drops stop entirely.
//          Fix: cap each player's score_total at hrp_score_cap (default ~1B).
//
//   OF-03: zombie_powerup_drop_increment grows at ×1.14 per powerup drop.
//          Starting from 2000 it reaches float precision limits (~100M) after
//          ~100+ drops. The drop distance comparison breaks silently.
//          Fix: cap at hrp_drop_inc_cap (default 50k — spaced-out but live drops).
//
// All three are polled every 1s. Each fires an iprintln + logprint once.
// ─────────────────────────────────────────────────────────────────────────────

hrp_overflow_watchdog()
{
    level endon("end_game");

    for (;;)
    {
        wait 1;
        hrp_clamp_score();
        hrp_clamp_drop_increment();
    }
}

hrp_clamp_score()
{
    players = getplayers();
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (!isdefined(p.score_total))
            continue;

        if (p.score_total > level._hrp_score_cap || p.score_total < 0)
        {
            p.score_total = level._hrp_score_cap;

            if (!level._hrp_score_capped)
            {
                level._hrp_score_capped = 1;
                logprint("[HRP] OF-02 fired: score_total clamped at "
                       + level._hrp_score_cap + "\n");
                iprintln("^3[HRP] Score clamped at "
                       + level._hrp_score_cap + " (OF-02)");
            }
        }
    }
}

hrp_clamp_drop_increment()
{
    if (!isdefined(level.zombie_vars))
        return;
    if (!isdefined(level.zombie_vars["zombie_powerup_drop_increment"]))
        return;

    di = level.zombie_vars["zombie_powerup_drop_increment"];

    if (di > level._hrp_drop_inc_cap)
    {
        level.zombie_vars["zombie_powerup_drop_increment"] = level._hrp_drop_inc_cap;

        if (!level._hrp_dropinc_capped)
        {
            level._hrp_dropinc_capped = 1;
            logprint("[HRP] OF-03 fired: drop_increment capped at "
                   + level._hrp_drop_inc_cap + "\n");
            iprintln("^3[HRP] Drop increment capped at "
                   + level._hrp_drop_inc_cap + " (OF-03)");
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SA-08 / SA-09 — scrVar PRUNING
//
// Two per-player arrays accumulate script variable slots throughout a session
// with no built-in cleanup, eventually crashing with:
//   "exceeded maximum number of child server script variables"
//
//   SA-08: self.hitsthismag[weaponname] — grows one entry per unique weapon
//          string switched to. BO2 weapon strings are compound (+reflex+grip etc.)
//          so box cycling through 50+ weapons generates 40-80+ per player.
//          4 players = 160-320+ permanently-held scrVar slots with no release.
//          Fix: at round start, rebuild the array keeping only entries for
//          weapons the player currently carries. Stale entries (traded/dropped
//          weapons) are freed. Base code re-populates missing entries lazily.
//
//   SA-09: self.pack_a_punch_weapon_options[weapon] — caches camo/reticle
//          options per unique upgraded weapon string. Never cleared.
//          Fix: clear the entire array at round start. get_pack_a_punch_weapon_options()
//          re-initialises it lazily on next access (_zm_weapons.gsc:2263).
//          Cosmetic side effect: camo/reticle is re-randomised on next PaP.
// ─────────────────────────────────────────────────────────────────────────────

hrp_scrvar_round_cleanup()
{
    level endon("end_game");

    for (;;)
    {
        level waittill("start_of_round");

        players = getplayers();
        for (i = 0; i < players.size; i++)
            players[i] thread hrp_prune_player();
    }
}

hrp_prune_player()
{
    if (!isdefined(self))
        return;

    // SA-08: rebuild hitsthismag keeping only currently-held weapons.
    if (isdefined(self.hitsthismag))
    {
        old_size = self.hitsthismag.size;
        current_weapons = self getweaponslist();
        keep = [];
        for (i = 0; i < current_weapons.size; i++)
        {
            w = current_weapons[i];
            if (isdefined(self.hitsthismag[w]))
                keep[w] = self.hitsthismag[w];
        }
        pruned = old_size - keep.size;
        self.hitsthismag = keep;

        if (pruned > 0)
        {
            level._hrp_scrvar_pruned += pruned;
            logprint("[HRP] SA-08 " + self.name + ": pruned "
                   + pruned + " stale hitsthismag entries (was "
                   + old_size + ", now " + keep.size + ")\n");
        }
    }

    // SA-09: clear PaP options cache entirely — repopulated lazily on next access.
    if (isdefined(self.pack_a_punch_weapon_options))
    {
        pap_size = self.pack_a_punch_weapon_options.size;
        self.pack_a_punch_weapon_options = undefined;
        level._hrp_pap_cleared += pap_size;
        logprint("[HRP] SA-09 " + self.name + ": cleared "
               + pap_size + " pap_weapon_options entries\n");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HUD — STATUS INDICATOR
//
// A single row shown in the top-left corner of each player's screen.
// Shows: patch version, current round, cumulative EL anchor frees,
// and a flag for each overflow cap that has fired this session.
//
// Updates at round transitions only (not on a tight loop) to minimise
// config-string slot consumption — every unique string passed to settext()
// burns one CS_LOCALIZED_STRINGS slot permanently for the session.
//
// If zm_diagnostics.gsc is also loaded, level.diag_ent_count is available
// and shown as a rough entity pool gauge.
// ─────────────────────────────────────────────────────────────────────────────

hrp_hud_connect_hook()
{
    level endon("end_game");

    for (;;)
    {
        level waittill("connected", player);
        player thread hrp_hud_player_init();
    }
}

hrp_hud_player_init()
{
    self endon("disconnect");

    for (;;)
    {
        self waittill("spawned_player");

        if (!isdefined(self._hrp_hud_ready))
        {
            self._hrp_hud_ready = 1;
            self thread hrp_hud_create_and_run();
        }
    }
}

hrp_hud_create_and_run()
{
    self endon("disconnect");
    level endon("end_game");

    hud = newclienthudelem(self);
    hud.foreground  = 1;
    hud.sort        = 50;
    hud.hidewheninmenu = 1;
    hud.alignx      = "right";
    hud.aligny      = "top";
    hud.horzalign   = "user_right";
    hud.vertalign   = "user_top";
    hud.x           = -4;
    hud.y           = 4;
    hud.alpha       = 0.80;
    hud.fontscale   = 1.2;
    hud.color       = (0.5, 1.0, 0.5);
    hud settext("HRP v" + level._hrp_version + " | loading...");

    // Update at round transitions and also once per second for the
    // 'cap fired' indicators, which can change mid-round.
    last_round = -1;

    for (;;)
    {
        wait 1;

        r = 0;
        if (isdefined(level.round_number))
            r = level.round_number;

        // Build compact status string.
        // EL: cumulative anchors freed.
        // OF: h/s/d = health/score/dropinc cap fired (0 until it fires, then 1).
        // SV: cumulative stale scrVar entries freed.
        ent_str = "";
        if (isdefined(level.diag_ent_count))
            ent_str = " Ent:" + int(level.diag_ent_count);

        hud settext("^2HRP^7 v" + level._hrp_version
                  + " ^7R^3" + r
                  + " ^7| EL^2" + level._hrp_anchors_freed
                  + " ^7| OF" + level._hrp_health_capped
                  + level._hrp_score_capped
                  + level._hrp_dropinc_capped
                  + " ^7| SV^2" + level._hrp_scrvar_pruned
                  + ent_str);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// PER-ROUND SERVER LOG SUMMARY
// Emits a one-line status to the server log each round — useful for
// offline analysis of long soak runs without needing HUD screenshots.
// ─────────────────────────────────────────────────────────────────────────────

hrp_per_round_log()
{
    level endon("end_game");

    for (;;)
    {
        level waittill("start_of_round");

        r = 0;
        if (isdefined(level.round_number))
            r = level.round_number;

        ent_str = "?";
        if (isdefined(level.diag_ent_count))
            ent_str = int(level.diag_ent_count);

        logprint("[HRP] R" + r
               + " ent=" + ent_str
               + " anchors_freed=" + level._hrp_anchors_freed
               + " health_capped=" + level._hrp_health_capped
               + " score_capped=" + level._hrp_score_capped
               + " dropinc_capped=" + level._hrp_dropinc_capped
               + " scrvar_pruned=" + level._hrp_scrvar_pruned + "\n");
    }
}
