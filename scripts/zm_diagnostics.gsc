#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm;

// T6 entity pool limit — confirmed 1024 by crash log (G_Spawn: no free entities
// fired at total ents: 916/1024 during fill test on zm_transit, 2026-02-19).
#define DIAG_ENT_LIMIT 1024

// How many entities to speculatively spawn per probe.
// Must stay well below expected free headroom so the probe itself
// doesn't push the count over the limit on a healthy game.  If the
// game DOES crash during the probe the logprint trail in the server
// log will record exactly how many slots were free at that instant.
#define DIAG_PROBE_CAP 128

// CS_LOCALIZED_STRINGS budget: 512 total slots, ~195 used by base game, ~317 for scripts.
// Every unique string ever passed to settext() burns one slot permanently.
// HUD display uses diag_hud_fmt() to abbreviate numbers and reduce unique string count.
// Snap output (logprint) is unaffected — snaps always show exact values.

init()
{
    level.diag_version = "0.6";
    level.diag_headroom_warning_round = 0;
    level.diag_entity_headroom = -1;
    level.diag_entity_headroom_min = 9999;
    level.diag_ent_count = 0;
    level.diag_probe_interval = 10;
    level.diag_hud_rows = [];
    level.diag_log_interval = 5;
    level.diag_snap_count = 0;

    // Register the command dvar so it exists before the poll loop reads it.
    setDvar("diag_cmd", "");
    setDvar("diag_arg", "");

    // Only write the default if the dvar hasn't been set yet.
    // HUD is off by default — enable with "set diag_hud 1" before loading.
    if (getDvar("diag_hud") == "")
        setDvar("diag_hud", "0");

    level thread diag_entity_probe_loop();
    level thread diag_round_tracker();
    level thread diag_command_listener();
    level thread on_player_connect();
}

on_player_connect()
{
    for (;;)
    {
        level waittill("connected", player);
        player thread on_player_spawned();
    }
}

on_player_spawned()
{
    self endon("disconnect");

    for (;;)
    {
        self waittill("spawned_player");

        if (!isdefined(self._diag_hud_init))
        {
            self._diag_hud_init = 1;

            if (getDvar("diag_hud") == "1")
            {
                self thread diag_hud_create();
                self thread diag_hud_update_loop();
                self thread diag_key_listener();
                iprintln("^3[DIAG] Press ^2F1^3=snap ^2F2^3=probe ^2F3^3=log5");
            }
        }
    }
}

// --- KEY LISTENER ---

// Polls for the USE button held for 1+ second with no zombies nearby.
// In practice: stand still and hold F (use) for 1 second = triggers a snap.
// Works without any console binds or chat.
diag_key_listener()
{
    self endon("disconnect");
    self endon("death");

    held_time = 0;

    for (;;)
    {
        wait 0.1;

        if (self usebuttonpressed())
        {
            held_time += 0.1;

            if (held_time >= 1.0)
            {
                self thread diag_cmd_snap();
                held_time = 0;
                // cooldown so one long hold doesn't fire multiple times
                wait 1.0;
            }
        }
        else
        {
            held_time = 0;
        }
    }
}

// --- HUD CREATION ---

diag_hud_create()
{
    self endon("disconnect");

    row_height = 14;
    start_x = 22;
    start_y = 56;
    font_size = 1.15;
    label_color = (0.6, 0.8, 1.0);

    self._diag_hud = [];

    row_names = [];
    row_names[0]  = "header";
    row_names[1]  = "round";
    row_names[2]  = "health";
    row_names[3]  = "ztotal";
    row_names[4]  = "ai_count";
    row_names[5]  = "headroom";
    row_names[6]  = "headroom_min";
    row_names[7]  = "ent_tally";
    row_names[8]  = "sep1";
    row_names[9]  = "kills";
    row_names[10] = "timeout_sub";
    row_names[11] = "timeout_play";
    row_names[12] = "chest_hits";
    row_names[13] = "sep2";
    row_names[14] = "drop_inc";
    row_names[15] = "score_total";
    row_names[16] = "grenade_ct";
    row_names[17] = "sep3";
    row_names[18] = "warning";

    for (i = 0; i < row_names.size; i++)
    {
        name = row_names[i];
        hud = newclienthudelem(self);
        hud.foreground = 1;
        hud.sort = 100;
        hud.hidewheninmenu = 1;
        hud.alignx = "left";
        hud.aligny = "top";
        hud.horzalign = "user_left";
        hud.vertalign = "user_top";
        hud.x = start_x;
        hud.y = start_y + (i * row_height);
        hud.alpha = 1;
        hud.fontscale = font_size;
        hud.color = label_color;
        hud settext("");
        self._diag_hud[name] = hud;
    }

    self._diag_hud["header"].color = (0.4, 1.0, 0.4);
    self._diag_hud["header"].fontscale = 1.3;
    self._diag_hud["sep1"].alpha = 0.3;
    self._diag_hud["sep2"].alpha = 0.3;
    self._diag_hud["sep3"].alpha = 0.3;
    self._diag_hud["headroom"].color = (1.0, 1.0, 0.4);
    self._diag_hud["headroom_min"].color = (1.0, 0.6, 0.2);
    self._diag_hud["ent_tally"].color = (0.5, 0.8, 0.5);
    self._diag_hud["warning"].color = (1.0, 0.3, 0.3);
}

// --- HUD UPDATE ---

diag_hud_update_loop()
{
    self endon("disconnect");

    for (;;)
    {
        wait 0.5;

        if (!isdefined(self._diag_hud))
            continue;

        self._diag_hud["header"] settext("BANQ DIAG v" + level.diag_version);

        r = 0;
        if (isdefined(level.round_number))
            r = level.round_number;
        self._diag_hud["round"] settext("Round: " + r);

        h = 0;
        if (isdefined(level.zombie_health))
            h = level.zombie_health;
        self._diag_hud["health"] settext("ZHealth: " + diag_hud_fmt(h));

        zt = 0;
        if (isdefined(level.zombie_total))
            zt = level.zombie_total;
        self._diag_hud["ztotal"] settext("ZQueue: " + diag_hud_fmt(zt));

        ai_ct = diag_get_ai_count();
        self._diag_hud["ai_count"] settext("AI Active: " + diag_hud_fmt(ai_ct));

        hr = level.diag_entity_headroom;
        if (hr >= 0)
            self._diag_hud["headroom"] settext("Probe HR: >" + hr);
        else
            self._diag_hud["headroom"] settext("Probe HR: ...");

        hrm = level.diag_entity_headroom_min;
        if (hrm < 9999)
            self._diag_hud["headroom_min"] settext("Probe Min: >" + hrm);
        else
            self._diag_hud["headroom_min"] settext("Probe Min: ...");

        tally = diag_count_ents();
        level.diag_ent_count = tally;
        self._diag_hud["ent_tally"] settext("Ent Tally: " + diag_hud_fmt(tally) + "/" + DIAG_ENT_LIMIT);

        self._diag_hud["sep1"] settext("----------");

        gk = 0;
        if (isdefined(level.global_zombies_killed))
            gk = level.global_zombies_killed;
        self._diag_hud["kills"] settext("Kills: " + diag_hud_fmt(gk));

        ts = 0;
        if (isdefined(level.zombie_total_subtract))
            ts = level.zombie_total_subtract;
        self._diag_hud["timeout_sub"] settext("Recycles: " + diag_hud_fmt(ts));

        tp = 0;
        if (isdefined(level.zombies_timeout_playspace))
            tp = level.zombies_timeout_playspace;
        self._diag_hud["timeout_play"] settext("Timeouts: " + diag_hud_fmt(tp));

        ch = 0;
        if (isdefined(level.chest_accessed))
            ch = level.chest_accessed;
        self._diag_hud["chest_hits"] settext("Box Hits: " + diag_hud_fmt(ch));

        self._diag_hud["sep2"] settext("----------");

        di = 0;
        if (isdefined(level.zombie_vars) && isdefined(level.zombie_vars["zombie_powerup_drop_increment"]))
            di = level.zombie_vars["zombie_powerup_drop_increment"];
        self._diag_hud["drop_inc"] settext("Drop Inc: " + diag_hud_fmt(di));

        st = diag_get_score_total();
        self._diag_hud["score_total"] settext("ScoreTotal: " + diag_hud_fmt(st));

        gc = 0;
        if (isdefined(self.grenade_multiattack_count))
            gc = self.grenade_multiattack_count;
        self._diag_hud["grenade_ct"] settext("Grenade Ct: " + diag_hud_fmt(gc));

        self._diag_hud["sep3"] settext("----------");

        hr = level.diag_entity_headroom;
        if (hr >= 0 && hr < DIAG_PROBE_CAP)
            self._diag_hud["warning"] settext("!! LOW PROBE HR: " + hr + " !!");
        else if (level.diag_headroom_warning_round > 0)
            self._diag_hud["warning"] settext("Low ent @ R" + level.diag_headroom_warning_round);
        else
            self._diag_hud["warning"] settext("");
    }
}

// --- COMMAND LISTENER ---

// Polls the "diag_cmd" dvar every 0.25s.
// Usage in Plutonium console:
//   set diag_cmd snap
//   set diag_cmd probe
//   set diag_cmd log       (then: set diag_arg 5)
//   set diag_cmd help
diag_command_listener()
{
    level endon("end_game");

    for (;;)
    {
        wait 0.25;

        raw = getDvar("diag_cmd");
        if (!isdefined(raw) || raw == "")
            continue;

        // Clear immediately so holding the same value doesn't re-fire.
        setDvar("diag_cmd", "");

        // Split on space: "log 5" -> ["log","5"].  Single-word commands work too.
        args = strtok(raw, " ");
        if (args.size == 0)
            continue;

        cmd = args[0];
        arg1 = getDvar("diag_arg");
        if (args.size > 1)
            arg1 = args[1];
        setDvar("diag_arg", "");

        players = getplayers();
        if (players.size == 0)
            continue;
        player = players[0];

        if (cmd == "snap")
            player thread diag_cmd_snap();
        else if (cmd == "log")
            player thread diag_cmd_log(arg1);
        else if (cmd == "probe")
            level thread diag_cmd_probe();
        else if (cmd == "help")
            player thread diag_cmd_help();
        else
            iprintln("^1[DIAG] Unknown: " + cmd + "  |  set diag_cmd help");
    }
}

diag_cmd_snap()
{
    level.diag_snap_count++;
    diag_print_snapshot("MANUAL SNAP #" + level.diag_snap_count);
}

diag_cmd_log(arg)
{
    if (arg == "")
    {
        iprintln("^1[DIAG] Usage: /diag log <rounds|0>");
        return;
    }
    n = int(arg);
    level.diag_log_interval = n;
    if (n == 0)
        iprintln("^3[DIAG] Auto-log disabled");
    else
        iprintln("^3[DIAG] Auto-log every " + n + " rounds");
}

diag_cmd_probe()
{
    iprintln("^3[DIAG] Running entity probe now...");
    headroom = diag_probe_headroom();
    level.diag_entity_headroom = headroom;
    if (headroom < level.diag_entity_headroom_min)
        level.diag_entity_headroom_min = headroom;
    iprintln("^2[DIAG] On-demand probe: headroom >=" + headroom);
}

diag_cmd_help()
{
    iprintln("^3[DIAG] Console commands (in Plutonium console):");
    wait 0.1;
    iprintln("^2set diag_cmd snap         ^7- Dump all metrics to server log");
    wait 0.1;
    iprintln("^2set diag_cmd probe        ^7- Run entity headroom probe now");
    wait 0.1;
    iprintln("^2set diag_arg 5            ^7- (set interval first)");
    wait 0.1;
    iprintln("^2set diag_cmd log          ^7- Auto-log every N rounds (0=off)");
}

// --- ROUND TRACKER ---

diag_round_tracker()
{
    level endon("end_game");

    for (;;)
    {
        level waittill("start_of_round");

        r = 0;
        if (isdefined(level.round_number))
            r = level.round_number;

        gk = 0;
        if (isdefined(level.global_zombies_killed))
            gk = level.global_zombies_killed;

        ts = 0;
        if (isdefined(level.zombie_total_subtract))
            ts = level.zombie_total_subtract;

        hr = level.diag_entity_headroom;
        hrm = level.diag_entity_headroom_min;
        tally = diag_count_ents();
        logprint("[DIAG] R" + r + " | ProbeHR:>" + hr + " Min:>" + hrm + " Tally:" + tally + " Kills:" + gk + " Recycles:" + ts + "\n");

        if (level.diag_log_interval > 0 && (r % level.diag_log_interval == 0))
            diag_print_snapshot("AUTO R" + r);
    }
}

// --- SNAPSHOT DUMP ---

// Prints all diagnostic metrics to console in a block that can be directly
// copy-pasted into a test-results .md file.
diag_print_snapshot(label)
{
    r = 0;
    if (isdefined(level.round_number))
        r = level.round_number;

    h = 0;
    if (isdefined(level.zombie_health))
        h = level.zombie_health;

    zt = 0;
    if (isdefined(level.zombie_total))
        zt = level.zombie_total;

    ai_ct = diag_get_ai_count();
    hr = level.diag_entity_headroom;
    hrm = level.diag_entity_headroom_min;
    tally = diag_count_ents();

    gk = 0;
    if (isdefined(level.global_zombies_killed))
        gk = level.global_zombies_killed;

    ts = 0;
    if (isdefined(level.zombie_total_subtract))
        ts = level.zombie_total_subtract;

    tp = 0;
    if (isdefined(level.zombies_timeout_playspace))
        tp = level.zombies_timeout_playspace;

    ch = 0;
    if (isdefined(level.chest_accessed))
        ch = level.chest_accessed;

    di = 0;
    if (isdefined(level.zombie_vars) && isdefined(level.zombie_vars["zombie_powerup_drop_increment"]))
        di = level.zombie_vars["zombie_powerup_drop_increment"];

    st = diag_get_score_total();

    logprint("DIAG_SNAP [" + label + "]\n");
    logprint("  Round:        " + r + "\n");
    logprint("  ZombieHealth: " + h + "\n");
    logprint("  ZombieQueue:  " + zt + "\n");
    logprint("  AI Active:    " + ai_ct + "\n");
    logprint("  Ent Tally:    " + tally + "/" + DIAG_ENT_LIMIT + "\n");
    logprint("  Probe HR:     >" + hr + "\n");
    logprint("  Probe MinHR:  >" + hrm + "\n");
    logprint("  Kills:        " + gk + "\n");
    logprint("  Recycles:     " + ts + "\n");
    logprint("  Timeouts:     " + tp + "\n");
    logprint("  Box Hits:     " + ch + "\n");
    logprint("  Drop Inc:     " + di + "\n");
    logprint("  Score Total:  " + st + "\n");

    iprintln("^2[DIAG] Snapshot [" + label + "] written to server log");
}

// --- ENTITY HEADROOM PROBE ---

diag_entity_probe_loop()
{
    level endon("end_game");

    // Wait for map init to settle before the first probe.
    wait 15;

    for (;;)
    {
        // Update count before probing so diag_probe_headroom() has a fresh value.
        level.diag_ent_count = diag_count_ents();

        headroom = diag_probe_headroom();
        level.diag_entity_headroom = headroom;

        if (headroom < level.diag_entity_headroom_min)
            level.diag_entity_headroom_min = headroom;

        // Record the first round where the probe returned a concrete value
        // (less than the cap), meaning real headroom is visibly low.
        if (headroom < DIAG_PROBE_CAP && level.diag_headroom_warning_round == 0 && isdefined(level.round_number))
        {
            level.diag_headroom_warning_round = level.round_number;
            logprint("[DIAG] WARNING — probe HR dropped below cap (" + headroom + ") at R"
                     + level.round_number + " | ent_tally=" + int(level.diag_ent_count)
                     + " | real pool pressure likely from non-enumerable entities (e.g. leaked anchors)\n");
        }

        // Escalating warnings as headroom continues to shrink.
        if (headroom < 64 && headroom > 0)
            logprint("[DIAG] CRITICAL — probe HR=" + headroom + " | crash imminent | ent_tally=" + int(level.diag_ent_count) + "\n");

        wait level.diag_probe_interval;
    }
}

// Spawns up to DIAG_PROBE_CAP script_origins to measure free entity slots.
//
// SAFETY: DIAG_PROBE_CAP must stay well below expected free headroom on a
// healthy game so the probe never reaches the engine limit itself.  If the
// game IS near the limit and the probe crashes, the logprint trail in the
// server log records exactly how many slots were free at that instant — look
// for the last "DIAG_PROBE N" line before the crash to read the headroom.
//
// The return value is a lower-bound: if all DIAG_PROBE_CAP spawns succeed the
// real headroom is >=DIAG_PROBE_CAP (displayed as ">N" on the HUD).
diag_probe_headroom()
{
    // T6 spawn() is a hard crash (COM_ERROR) when the entity pool is exhausted —
    // it does NOT return undefined.  Guard with a count-based check first.
    // diag_count_ents() undercounts entities whose classname isn't enumerated
    // there (e.g. info_volume, script_brushmodel, zbarrier_*) so use a generous
    // buffer on top of DIAG_PROBE_CAP.
    safe_free = DIAG_ENT_LIMIT - diag_count_ents();
    if (safe_free < DIAG_PROBE_CAP + 100)
    {
        logprint("DIAG_PROBE_SKIP free_est=" + safe_free + "\n");
        return 0;
    }

    probes = [];
    count = 0;

    for (i = 0; i < DIAG_PROBE_CAP; i++)
    {
        ent = spawn("script_origin", (0, 0, -10000));

        if (!isdefined(ent))
            break;

        probes[count] = ent;
        count++;
    }

    for (i = 0; i < count; i++)
    {
        if (isdefined(probes[i]))
            probes[i] delete();
    }
    // ONLY LOG EVERY % 60 (ONE MINUTE) UNLESS APPROACHING Limitations
    // Single summary line instead of per-slot spam.
    // If the game ever crashes mid-probe (entity limit hit), the last
    // DIAG_SNAP before the crash will show the headroom trend; per-slot
    // logging is no longer needed now that ELP reduces leak rate.
    if (count < DIAG_PROBE_CAP)
    {
        // Only log immediately if we're low (approaching entity limit) so admins notice fast.
        logprint("[DIAG] probe HR=" + count + "\n");
    }
    else
    {
        // Only log frequently (every minute, i.e. every 60 calls)
        if (!isdefined(level.diag_probe_tick))
            level.diag_probe_tick = 0;
        level.diag_probe_tick++;
        if (level.diag_probe_tick >= 60)
        {
            logprint("[DIAG] probe HR=>" + count + "\n");
            level.diag_probe_tick = 0;
        }
    }
    return count;
}

// Safe zero-crash headroom estimate: counts entities of known classnames
// using getentarray() and returns (DIAG_ENT_LIMIT - tally).  The tally
// will undercount anything whose classname isn't listed here, so treat it
// as a floor on entity usage rather than an exact figure.
diag_count_ents()
{
    classnames = [];
    classnames[0]  = "script_model";
    classnames[1]  = "script_origin";
    classnames[2]  = "item";
    classnames[3]  = "trigger_radius";
    classnames[4]  = "trigger_use";
    classnames[5]  = "trigger_use_touch";
    classnames[6]  = "trigger_damage";
    classnames[7]  = "trigger_lookat";
    classnames[8]  = "trigger_multiple";
    classnames[9]  = "trigger_once";
    classnames[10] = "fx";
    classnames[11] = "light";
    classnames[12] = "node_pathnode";

    total = 0;
    for (i = 0; i < classnames.size; i++)
    {
        arr = getentarray(classnames[i], "classname");
        if (isdefined(arr))
            total += arr.size;
    }

    ai = getaiarray("axis");
    if (isdefined(ai))
        total += ai.size;

    ai = getaiarray("allies");
    if (isdefined(ai))
        total += ai.size;

    players = getplayers();
    if (isdefined(players))
        total += players.size;

    return total;
}

// --- HELPERS ---

diag_get_ai_count()
{
    if (!isdefined(level.zombie_team))
        return 0;

    ai = getaiarray(level.zombie_team);

    if (isdefined(ai))
        return ai.size;

    return 0;
}

diag_get_score_total()
{
    players = getplayers();
    total = 0;

    for (i = 0; i < players.size; i++)
    {
        if (isdefined(players[i].score_total))
            total = total + players[i].score_total;
    }

    return total;
}

// Format a number for HUD display to minimise unique config string consumption.
// CS_LOCALIZED_STRINGS has 512 slots total; every unique string passed to
// settext() burns one permanently.  This formatter bucketes values so that
// fast-changing fields (score, kills, health) produce far fewer unique strings.
//
// Snap output always uses the raw value — this is only for the live HUD.
//
//   |val| < 1000        → exact           e.g. "247", "-83"
//   1000 ≤ |val| < 1M   → nearest 1000k  e.g. "50k", "-2k"
//   |val| ≥ 1M          → nearest 1M      e.g. "2147M", "-2147M"
// Abbreviate a number for HUD display, capping the number of unique config
// string values produced.  Every distinct string passed to settext() permanently
// consumes one of the 316 dynamic config-string slots available per session.
// Rounding buckets (applied to absolute value, sign handled by callers):
//   0-9    → exact           (9 values)
//   10-99  → nearest 10      (9 values)
//   100-999→ nearest 100     (9 values)
//   1k+    → "Xk"            (bounded by game values)
//   1M+    → "XM"
diag_hud_fmt(val)
{
    if (val >= 1000000 || val <= -1000000)
        return int(val / 1000000) + "M";

    if (val >= 1000 || val <= -1000)
        return int(val / 1000) + "k";

    if (val >= 100 || val <= -100)
        return int(val / 100) * 100;

    if (val >= 10 || val <= -10)
        return int(val / 10) * 10;

    return val;
}
