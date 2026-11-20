--[[
* goomui: AAEV module (Auto Attacks Easily Visualized).
* Original Windower addon by darkewaffle; Ashita v4 port (aaev 2.0.2).
* Settings now live in the settings lib (alias 'aaev', per character).
--]]

require('common');
local imgui = require('imgui');
local chat  = require('chat');
local slib  = require('settings');
local data  = require('modules/aaev_data');
local theme = require('modules/theme');
local parse_action = require('modules/action');

-- Ashita's ImGui (1.92.3) binding has no SetWindowFontScale: the text keeps its size and
-- the fit logic falls back to dropping cells. IsItemDeactivatedAfterEdit: commit on release where bound.
local font_scale_ok = imgui.SetWindowFontScale ~= nil;
local set_font_scale = imgui.SetWindowFontScale or function () end;
local function released(changed)
    if (imgui.IsItemDeactivatedAfterEdit ~= nil) then return imgui.IsItemDeactivatedAfterEdit(); end
    return changed;
end
local scaling = require('scaling');

local M = { };

----------------------------------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------------------------------

local default_settings = T{
    enabled = false,      -- module toggle (off = no packet parsing, no draw)
    migrated = false,     -- old addons/goomui aaev files imported
    DisplayMode = 'full',
    DisplayContinuous = false,
    AdditionalEffectSingleBar = false,
    AdditionalEffectStackBars = true,
    AutoHide = true,
    HideDelay = 4.0,
    AlwaysShow = false,
    FixedSize = true,
    AutoDemo = false,
    ChartBars = 20, ChartStartX = 500, ChartStartY = 500, ChartWidth = 100, ChartHeight = 43,
    BarsAlpha = 255,
    -- 'round' = one bar per attack round (packet): height = round damage, colour = swing count.
    -- 'swing' = one bar per swing.
    BarMode = 'round',
    ColorRound1 = { 0, 0, 237 }, ColorRound2 = { 0, 170, 255 },
    ColorRound3 = { 60, 220, 120 }, ColorRound4 = { 255, 200, 0 },
    ColorRound5 = { 255, 90, 0 },
    RoundCritCap = true, RoundCritCapPx = 2,
    LastShowHits = true,
    ColorHit = { 0, 0, 237 }, ColorCrit = { 119, 119, 237 }, ColorMiss = { 255, 255, 255 },
    ColorBlock = { 64, 64, 64 }, ColorHitZero = { 128, 128, 128 }, ColorCounter = { 237, 0, 0 },
    ColorHeal = { 102, 255, 7 }, ColorAdditionalEffect = { 192, 192, 192 },
    ColorAdditionalEffectHeal = { 102, 255, 7 },
    BGDisplay = true, BGColor = { 0, 0, 0 }, BGAlpha = 128, BGPaddingX = 5, BGPaddingY = 4,
    DisplayMax = false, MaxLabelPrefix = 'Max: ',
    DisplayHitRate = true, HitRateLabelPrefix = 'Acc: ',
    DisplayCritRate = true, CritRateLabelPrefix = 'Crit: ',
    DisplayTH = true, ColorTH = { 255, 200, 0 },
    DisplayAvg = true, AvgLabelPrefix = 'Avg: ',
    DisplayZoneAcc = true, ZoneAccLabelPrefix = 'Zone: ',
    DisplayLast = true, LastLabelPrefix = 'Last: ',
    DisplayRoundCount = false, RoundLabelPrefix = 'Rd: ',
    -- Single-letter label prefixes (M L A C ~ Z + #), per key overridable (GlyphMax etc.; ASCII only).
    GlyphLabels = false,
    ResetOnTargetChange = true,
    SingleLineLabels = false,
    WidthFromLabels = false,
    AutoFitLabels = true,
    MinFontScale = 0.55,
    CompactLabels = true,
    HitRateColorize = true,
    LabelColor = { 255, 255, 255 }, LabelAlpha = 255, FontScale = 1.0,
    DisplayWeaponskills = true, ReverseWeaponskills = false, WeaponskillCount = 5,
    PetChart = true, PetChartBars = 20, PetChartStartX = 500, PetChartStartY = 650,
    PetChartWidth = 100, PetChartHeight = 43, PetWeaponskillCount = 5,
    -- goomui look
    -- Player chart position: 'chat' = one-line strip in the gap under the chat log
    -- (default), 'bar' = docked under the target bar, 'free' = ChartStartX/Y (drag).
    Position = 'chat',
    StripX = -1, StripW = -1,   -- -1 = auto: 0.75% / 30.2% of screen width (default chat log, 2560x1080)
    StripH = 15, StripBottom = 1,     -- min height (grows to fit the font), gap to screen bottom
    StripRounds = 25, StripBarPx = 5, -- last N rounds in the strip, px per bar
    ThemeColors = true,   -- shared goomui palette (false = the Color* values above)
    StatGrid = true,      -- labeled stat cells (two rows) instead of the label lines
    DisplayMulti = true,  -- DA / TA / QA share of rounds (main-hand swings per round)
};
M.defaults = default_settings;

local settings = default_settings;   -- per-char table from the settings lib (M.set_cfg)

-- Change counters: label rows, colours and window size rebuild only when these move.
local ver = { cfg = 0 };
local saved_dirty_at = nil;   -- debounce: a slider drag writes the file once, 0.5 s after it stops

local function save_saved()
    return slib.save('aaev');
end

-- Normalize + invalidate caches (load, char switch, reset, reload).
local function load_settings()
    -- SingleBar wins if both AE modes set (original behavior).
    if (settings.AdditionalEffectSingleBar) then
        settings.AdditionalEffectStackBars = false;
    end
    -- AlwaysShow means the chart is a permanent HUD element; AutoHide is meaningless.
    if (settings.AlwaysShow) then
        settings.AutoHide = false;
    end
    ver.cfg = ver.cfg + 1;
end

-- Positions are ordinary keys in the per-char table now.
local function save_positions()
    return save_saved();
end

----------------------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------------------

local TYPE_PLAYER = 'player';
local TYPE_PET    = 'pet';

local logs = {
    [TYPE_PLAYER] = {},
    [TYPE_PET]    = {},
};

local state = {
    dead_ids = {},
    reset_at = nil,               -- os.clock time to purge dead target logs
    display_target = { [TYPE_PLAYER] = nil, [TYPE_PET] = nil },
    visible = { [TYPE_PLAYER] = false, [TYPE_PET] = false },
    pet_enemy = nil,
    hide_at = { [TYPE_PLAYER] = nil, [TYPE_PET] = nil },
    last_status = nil,
    last_job = nil,
    unlocked = false,
    applied_pos = { [TYPE_PLAYER] = false, [TYPE_PET] = false },
    forced_hidden = false,        -- /goomui aaev hide beats AlwaysShow until /goomui aaev show
    show_config = false,
    last_target = nil,
};

-- Zone-lifetime melee accuracy for the player. Survives target death and log
-- purges; only a zone change (0x00B) or /goomui aaev zonereset clears it.
local zone_stats = { count = 0, miss = 0, crit = 0, v = 0 };

local function zone_reset()
    zone_stats.count, zone_stats.miss, zone_stats.crit = 0, 0, 0;
    zone_stats.v = zone_stats.v + 1;
end

-- Placeholder log so AlwaysShow can render an empty frame with no data.
local idle_log = { count = 0, max = 0, miss = 0, crit = 0, th = 0, rounds = 0, last_dmg = 0,
                   max_round = 0, max_round_sw = 0, last_hits = 0, last_swings = 0, rlist = {},
                   attacks = {}, ws = {}, v = 0 };

local function target_override()
    if (settings.DisplayContinuous) then
        return 'ALLTARGETS';
    end
    return nil;
end

-- Charts linger HideDelay seconds after disengage / target death; new data or a re-engage cancels the hide.
local function set_visible(log_type)
    state.visible[log_type] = true;
    state.hide_at[log_type] = nil;
end

local function schedule_hide(log_type)
    if (settings.AlwaysShow and log_type == TYPE_PLAYER) then return; end
    if (not settings.AutoHide) then return; end
    if (settings.HideDelay == nil or settings.HideDelay <= 0) then
        state.visible[log_type] = false;
        state.hide_at[log_type] = nil;
    else
        state.hide_at[log_type] = os.clock() + settings.HideDelay;
    end
end

----------------------------------------------------------------------------------------------------
-- Game state helpers
----------------------------------------------------------------------------------------------------

local function player_status()
    local p = GetPlayerEntity();
    if (p ~= nil) then
        return p.Status;
    end
    return nil;
end

local function main_job()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (player ~= nil) then
        return player:GetMainJob();
    end
    return 0;
end

local function is_pet_job()
    return data.pet_jobs[main_job()] == true;
end

-- Own + pet server ids, refreshed once per frame in M.render (no stale pet id after release / charm).
local ids = { pid = nil, petid = nil };

local function pet_id(p)
    p = p or GetPlayerEntity();
    if (p == nil or p.PetTargetIndex == nil or p.PetTargetIndex == 0) then
        return nil;
    end
    local pet = GetEntity(p.PetTargetIndex);
    if (pet ~= nil and pet.ServerId ~= nil and pet.ServerId > 0) then
        return pet.ServerId;
    end
    return nil;
end

local function current_target_id()
    local tmgr = AshitaCore:GetMemoryManager():GetTarget();
    if (tmgr == nil) then return nil; end
    local idx = tmgr:GetTargetIndex(0);
    if (idx == nil or idx == 0) then return nil; end
    local ent = GetEntity(idx);
    if (ent ~= nil and ent.ServerId ~= nil and ent.ServerId > 0) then
        return ent.ServerId;
    end
    return nil;
end

-- Local mob server ids encode their index in the low 12 bits; players won't
-- match this check and are correctly excluded (original used spawn_type == 16).
local function is_monster(server_id)
    if (type(server_id) ~= 'number' or server_id == 0) then return false; end
    local idx = bit.band(server_id, 0xFFF);
    if (idx >= 0x900) then return false; end
    local ent = GetEntity(idx);
    if (ent ~= nil and ent.ServerId == server_id) then
        return bit.band(ent.SpawnFlags or 0, 0x10) ~= 0;
    end
    return false;
end

local function ws_name(ws_id, category)
    local rm = AshitaCore:GetResourceManager();
    if (category == 13) then
        -- Bloodpact / wyvern breath: param is a JA id; ability resource = id + 512.
        local res = rm:GetAbilityById(ws_id + 512);
        if (res ~= nil) then return res.Name[1]; end
    elseif (ws_id > 0 and ws_id <= 255) then
        local res = rm:GetAbilityById(ws_id);
        if (res ~= nil) then return res.Name[1]; end
    elseif (ws_id >= 257) then
        -- Mob skill (BST Ready / pet TP move). Names live in the
        -- 'monsters.abilities' string table at id - 256 (as LuAshitacast reads them).
        local auto = data.automaton_whitelist[ws_id];
        if (auto ~= nil) then return auto.en; end
        local s = rm:GetString('monsters.abilities', ws_id - 256);
        if (type(s) == 'string') then
            local nul = s:find('\0', 1, true);
            if (nul ~= nil) then s = s:sub(1, nul - 1); end
            -- Non-ASCII (JP client) would render as garbage in the default font.
            if (#s > 0 and not s:find('[\128-\255]')) then return s; end
        end
        return ('#%d'):format(ws_id);
    end
    return 'WS?';
end

----------------------------------------------------------------------------------------------------
-- Attack log
----------------------------------------------------------------------------------------------------

local function get_target_log(log_type, tid, create)
    local log = logs[log_type];
    if (log[tid] == nil) then
        if (not create) then return nil; end
        log[tid] = {
            count = 0, max = 0, miss = 0, crit = 0, th = 0, rounds = 0, last_dmg = 0,
            -- round mode: rlist is the per-round ring buffer
            max_round = 0, max_round_sw = 0, last_hits = 0, last_swings = 0, rlist = {},
            attacks = {}, ws = {}, v = 0,
        };
    end
    return log[tid];
end

local function chart_bars(log_type)
    if (log_type == TYPE_PET) then return settings.PetChartBars; end
    return settings.ChartBars;
end

-- Docked: player chart width follows the target bar (set per frame in M.render).
local dock = { on = false, x = 0, y = 0, w = 0, win_w = 0, pad = { 12, 4 } };
-- Chat strip: player chart as one line under the chat log (set per frame in M.render).
local strip = { on = false, x = 0, y = 0, w = 0, h = 15, bw = 100, bh = 11, n = 25, pad = { 3, 1 }, sp = { 4, 0 } };

-- Chart sizes follow the global UI scale (theme.px); docked / strip sizes already come from scaled panels.
local function chart_width(log_type)
    if (log_type == TYPE_PET) then return theme.px(settings.PetChartWidth); end
    if (strip.on) then return strip.bw; end
    if (dock.on) then return dock.w; end
    return theme.px(settings.ChartWidth);
end

local function chart_height(log_type)
    if (log_type == TYPE_PET) then return theme.px(settings.PetChartHeight); end
    if (strip.on) then return strip.bh; end
    return theme.px(settings.ChartHeight);
end

local function ws_count(log_type)
    if (log_type == TYPE_PET) then return settings.PetWeaponskillCount; end
    return settings.WeaponskillCount;
end

local function record_attacks(pkt, log_type)
    local tgt = pkt.targets[1];
    if (tgt == nil) then return nil; end
    local tid = target_override() or tgt.id;
    local tlog = get_target_log(log_type, tid, true);
    -- One 0x028 category-1 packet == one attack round (main + off + multi-attack).
    local round_dmg = 0;
    -- Round accumulators. swings = actions in the packet = the multi-attack tier (1-4, 5+ occasional).
    local r_swings, r_hits, r_crit, r_counter, r_ae = 0, 0, 0, 0, 0;
    -- Main-hand swings this round. XiPackets 0x0028: melee result sub_kind 0 = main hand, 1 = off hand,
    -- 2/3 = kicks, 4 = throw.
    local r_mh = 0;
    -- LAST cell: melee damage and additional-effect damage of this round, kept apart.
    local r_melee, r_ae_hit = 0, 0;

    for _, act in ipairs(tgt.results) do
        local a_msg    = act.message;
        local a_dmg    = act.value;
        local a_result = data.attack_messages[a_msg] or data.ATTACK_HIT;

        -- Countered attacks carry no attack message but do carry a spike message.
        if (a_msg == 0) then
            local spike_msg = 0;
            if (act.react ~= nil) then spike_msg = act.react.message; end
            a_result = data.attack_messages[spike_msg] or data.ATTACK_HIT;
            a_dmg = 0;
        end

        if (a_result == data.ATTACK_MISS) then
            tlog.miss = tlog.miss + 1;
        elseif (a_result == data.ATTACK_CRIT) then
            tlog.crit = tlog.crit + 1;
        end

        r_swings = r_swings + 1;
        if (act.sub_kind == 0) then r_mh = r_mh + 1; end
        if (a_result == data.ATTACK_CRIT) then
            r_crit = r_crit + 1;
        elseif (a_result == data.ATTACK_COUNTER) then
            r_counter = r_counter + 1;
        end
        if (a_result ~= data.ATTACK_MISS and a_result ~= data.ATTACK_COUNTER
            and a_result ~= data.ATTACK_SHADOW) then
            r_hits = r_hits + 1;
        end

        -- Zone accumulator: same hit/miss definition as the per-target rate.
        if (log_type == TYPE_PLAYER) then
            zone_stats.v = zone_stats.v + 1;
            zone_stats.count = zone_stats.count + 1;
            if (a_result == data.ATTACK_MISS) then
                zone_stats.miss = zone_stats.miss + 1;
            elseif (a_result == data.ATTACK_CRIT) then
                zone_stats.crit = zone_stats.crit + 1;
            end
        end

        if (a_result ~= data.ATTACK_MISS and a_result ~= data.ATTACK_COUNTER and a_dmg == 0) then
            a_result = data.ATTACK_HIT_ZERO;
        end

        local ae_result = data.AE_NONE;
        local ae_dmg = 0;
        if (act.proc ~= nil) then
            ae_result = data.ae_messages[act.proc.message] or data.AE_NONE;
            ae_dmg = act.proc.value or 0;
            -- TH proc: param is the new TH tier, not damage.
            if (ae_result == data.AE_TREASURE_HUNTER) then
                tlog.th = ae_dmg;
                ae_result = data.AE_NONE;
                ae_dmg = 0;
            end
        end

        local total = 0;
        if (a_result ~= data.ATTACK_HEAL) then
            total = total + a_dmg;
        end
        if ((settings.AdditionalEffectSingleBar or settings.AdditionalEffectStackBars)
            and ae_result ~= data.AE_HEAL) then
            total = total + ae_dmg;
        end

        if (a_result ~= data.ATTACK_HEAL) then r_melee = r_melee + a_dmg; end
        if (ae_result == data.AE_HIT) then r_ae_hit = r_ae_hit + ae_dmg; end

        tlog.max = math.max(tlog.max, total);
        tlog.count = tlog.count + 1;
        round_dmg = round_dmg + total;
        r_ae = r_ae + ae_dmg;

        table.insert(tlog.attacks, { result = a_result, dmg = a_dmg, ae_result = ae_result, ae_dmg = ae_dmg });
        while (#tlog.attacks > chart_bars(log_type)) do
            table.remove(tlog.attacks, 1);
        end
    end

    tlog.rounds = (tlog.rounds or 0) + 1;
    tlog.last_dmg = round_dmg;
    tlog.last_hits = r_hits;
    tlog.last_swings = r_swings;
    tlog.last_melee, tlog.last_ae, tlog.last_crit = r_melee, r_ae_hit, (r_crit > 0);

    -- Multi-attack tally from main-hand swing count: 2 = DA, 3 = TA, 4+ = QA.
    -- 'Occasionally attacks N times' weapons / aftermath land here too.
    if (r_mh > 0) then
        tlog.mh_rounds = (tlog.mh_rounds or 0) + 1;
        if (r_mh == 2) then tlog.mh2 = (tlog.mh2 or 0) + 1;
        elseif (r_mh == 3) then tlog.mh3 = (tlog.mh3 or 0) + 1;
        elseif (r_mh >= 4) then tlog.mh4 = (tlog.mh4 or 0) + 1; end
    end

    -- Round entry for BarMode == 'round'.
    if (r_swings > 0) then
        -- swing count of the round that set max_round (for the label)
        if (round_dmg > (tlog.max_round or 0)) then
            tlog.max_round = round_dmg;
            tlog.max_round_sw = r_swings;
        end
        table.insert(tlog.rlist, {
            dmg = round_dmg, swings = r_swings, hits = r_hits,
            crit = r_crit, counter = r_counter, ae_dmg = r_ae,
        });
        while (#tlog.rlist > chart_bars(log_type)) do
            table.remove(tlog.rlist, 1);
        end
    end

    tlog.v = tlog.v + 1;
    return tid;
end

local function record_ws(pkt, log_type, msg_map)
    local tgt = pkt.targets[1];
    if (tgt == nil or tgt.results[1] == nil) then return nil; end
    local tid = target_override() or tgt.id;
    local act = tgt.results[1];

    local result = msg_map[act.message];
    if (result == nil) then return nil; end

    local tlog = get_target_log(log_type, tid, true);
    local entry = {
        name   = ws_name(pkt.param, pkt.category),
        dmg    = act.value,
        result = result,
    };
    if (act.proc ~= nil) then
        local sc = data.skillchain_messages[act.proc.message];
        if (sc ~= nil) then
            entry.sc_name = sc.name;
            entry.sc_dmg = act.proc.value;
            entry.sc_result = sc.result;
        end
    end

    table.insert(tlog.ws, entry);
    while (#tlog.ws > ws_count(log_type)) do
        table.remove(tlog.ws, 1);
    end

    tlog.v = tlog.v + 1;
    return tid;
end

local function reset_dead_logs()
    for tid, _ in pairs(state.dead_ids) do
        logs[TYPE_PLAYER][tid] = nil;
        logs[TYPE_PET][tid] = nil;
        state.dead_ids[tid] = nil;
    end
    state.reset_at = nil;
end

local function reset_all_logs()
    logs[TYPE_PLAYER] = {};
    logs[TYPE_PET] = {};
    state.dead_ids = {};
    state.reset_at = nil;
    state.display_target[TYPE_PLAYER] = nil;
    state.display_target[TYPE_PET] = nil;
    state.pet_enemy = nil;
end

----------------------------------------------------------------------------------------------------
-- Packet parsing
----------------------------------------------------------------------------------------------------

local function handle_action(e)
    -- Cheap actor pre-check before full bit parse.
    local actor = struct.unpack('I4', e.data, 0x05 + 1);
    local pid, petid = ids.pid, ids.petid;
    if (pid == nil) then
        -- No frame yet (load / zone): live lookup, as before.
        local p = GetPlayerEntity();
        if (p == nil) then return; end
        pid, petid = p.ServerId, pet_id(p);
    end
    if (actor == pid) then
        petid = nil;
    elseif (petid == nil or actor ~= petid) then
        return;
    end

    local pkt = parse_action(e);
    if (pkt == nil or pkt.targets[1] == nil) then return; end
    pkt.param = bit.band(pkt.param, 0xFFFF);   -- ws / ability / mob skill id
    -- Raw server id, not 'ALLTARGETS' (DisplayContinuous): is_monster needs a number.
    local tid = pkt.targets[1].id;

    if (actor == pid and pkt.category == 1) then
        -- Player melee round.
        local rec = record_attacks(pkt, TYPE_PLAYER);
        if (rec ~= nil) then
            state.display_target[TYPE_PLAYER] = rec;
            set_visible(TYPE_PLAYER);
        end

    elseif (actor == petid and pkt.category == 1) then
        -- Pet melee round.
        local rec = record_attacks(pkt, TYPE_PET);
        if (rec ~= nil and not state.dead_ids[rec]) then
            state.display_target[TYPE_PET] = rec;
            state.pet_enemy = rec;
            set_visible(TYPE_PET);
        end

    elseif (actor == pid and pkt.category == 3) then
        -- Player weaponskill.
        local rec = record_ws(pkt, TYPE_PLAYER, data.ws_messages);
        if (rec ~= nil) then
            state.display_target[TYPE_PLAYER] = rec;
            set_visible(TYPE_PLAYER);
        end

    elseif (actor == petid and is_monster(tid)) then
        -- Pet ability landing on a monster.
        local rec = nil;
        local job = main_job();
        if (pkt.category == 11 and job == 9) then
            -- BST Ready.
            rec = record_ws(pkt, TYPE_PET, data.ws_messages);
        elseif (pkt.category == 11 and job == 18) then
            -- Automaton TP move, whitelist gated.
            local auto = data.automaton_whitelist[pkt.param];
            if (auto ~= nil and auto.display) then
                rec = record_ws(pkt, TYPE_PET, data.ws_messages);
            end
        elseif (pkt.category == 13) then
            -- Avatar bloodpact / wyvern breath.
            rec = record_ws(pkt, TYPE_PET, data.bloodpact_messages);
        end
        if (rec ~= nil and not state.dead_ids[rec]) then
            state.display_target[TYPE_PET] = rec;
            state.pet_enemy = rec;
            set_visible(TYPE_PET);
        end

    elseif (actor == pid and pkt.category == 6) then
        -- Player JA that dismisses/parks the pet: hide the pet chart.
        if (data.hide_pet_triggers[pkt.param] ~= nil and settings.AutoHide) then
            state.visible[TYPE_PET] = false;
        end
    end
end

-- 0x00E: NPC update; detect deaths/despawns to retire logs.
local function handle_npc_update(e)
    if (settings.DisplayContinuous) then return; end
    if (e.size < 0x0B) then return; end

    local mask = struct.unpack('B', e.data, 0x0A + 1);
    if (bit.band(mask, 0x24) == 0) then return; end
    local npc_id = struct.unpack('I4', e.data, 0x04 + 1);
    -- only mobs with data matter
    if (logs[TYPE_PLAYER][npc_id] == nil and logs[TYPE_PET][npc_id] == nil
        and npc_id ~= state.pet_enemy) then
        return;
    end
    local status_changed = bit.band(mask, 0x04) ~= 0;
    local terminated = bit.band(mask, 0x20) ~= 0;

    local died = false;
    if (status_changed and e.size >= 0x20) then
        local status = struct.unpack('B', e.data, 0x1F + 1);
        died = status >= 2 and status <= 3;
    end

    if ((died or terminated) and not state.dead_ids[npc_id]) then
        state.dead_ids[npc_id] = true;
        if (state.reset_at == nil) then
            state.reset_at = os.clock() + 20.0;
        end
        if (npc_id == state.pet_enemy) then
            schedule_hide(TYPE_PET);
            state.pet_enemy = nil;
        end
    end
end

function M.packet_in(e)
    if (not settings.enabled) then return; end
    if (e.id == 0x028) then
        handle_action(e);
    elseif (e.id == 0x00E) then
        handle_npc_update(e);
    elseif (e.id == 0x00B) then
        -- Zone exit. Zone accuracy is per-zone, so it clears here too.
        ids.pid, ids.petid = nil, nil;
        reset_all_logs();
        zone_reset();
        state.last_target = nil;
        state.visible[TYPE_PLAYER] = settings.AlwaysShow;
        state.visible[TYPE_PET] = false;
        state.hide_at[TYPE_PLAYER] = nil;
        state.hide_at[TYPE_PET] = nil;
    end
end

----------------------------------------------------------------------------------------------------
-- Frame polling (status / job change)
----------------------------------------------------------------------------------------------------

local function poll_state(p)
    -- hit% / crit% / avg are per mob: follow the target, so the numbers switch with it.
    if (settings.ResetOnTargetChange and not settings.DisplayContinuous) then
        local ttid = current_target_id();
        if (ttid ~= nil and ttid ~= state.last_target) then
            state.last_target = ttid;
            if (is_monster(ttid)) then
                state.display_target[TYPE_PLAYER] = ttid;
            end
        end
    end

    local status = p.Status;
    if (status ~= state.last_status) then
        if (status == 1) then
            -- Engaged: show existing data for current target immediately.
            local tid = target_override() or current_target_id();
            if (tid ~= nil and logs[TYPE_PLAYER][tid] ~= nil) then
                state.display_target[TYPE_PLAYER] = tid;
                set_visible(TYPE_PLAYER);
            end
        elseif (state.last_status == 1) then
            schedule_hide(TYPE_PLAYER);
        end
        state.last_status = status;
    end

    local job = main_job();
    if (job ~= state.last_job) then
        if (not data.pet_jobs[job]) then
            state.visible[TYPE_PET] = false;
            state.display_target[TYPE_PET] = nil;
        end
        state.last_job = job;
    end

    local now = os.clock();
    if (state.reset_at ~= nil and now >= state.reset_at) then
        reset_dead_logs();
    end

    local h = state.hide_at;
    if (h[TYPE_PLAYER] ~= nil and now >= h[TYPE_PLAYER]) then
        state.visible[TYPE_PLAYER] = false;
        h[TYPE_PLAYER] = nil;
    end
    if (h[TYPE_PET] ~= nil and now >= h[TYPE_PET]) then
        state.visible[TYPE_PET] = false;
        h[TYPE_PET] = nil;
    end

    if (saved_dirty_at ~= nil and now - saved_dirty_at >= 0.5) then
        saved_dirty_at = nil;
        save_saved();
    end
end

----------------------------------------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------------------------------------

-- U32 colours cached per settings version.
local u32_cache, u32_ver = {}, -1;
local function col_u32(c, alpha)
    if (u32_ver ~= ver.cfg) then u32_cache, u32_ver = {}, ver.cfg; end
    alpha = alpha or 255;
    local byc = u32_cache[c];
    if (byc == nil) then byc = {}; u32_cache[c] = byc; end
    local v = byc[alpha];
    if (v == nil) then
        v = imgui.GetColorU32({ c[1] / 255, c[2] / 255, c[3] / 255, alpha / 255 });
        byc[alpha] = v;
    end
    return v;
end

-- Reused ImVec2 tables (the binding copies values at call time).
local V1, V2, VD, VS = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local function rect(dl, x1, y1, x2, y2, col)
    V1[1], V1[2], V2[1], V2[2] = x1, y1, x2, y2;
    dl:AddRectFilled(V1, V2, col);
end

local COLOR_SHADOW = { 192, 192, 192 };
local TP_ = theme.P;
local THEME_RESULT = {
    [data.ATTACK_HIT] = TP_.hit, [data.ATTACK_CRIT] = TP_.crit, [data.ATTACK_MISS] = TP_.miss,
    [data.ATTACK_BLOCK] = TP_.block, [data.ATTACK_HIT_ZERO] = TP_.zero, [data.ATTACK_COUNTER] = TP_.counter,
    [data.ATTACK_HEAL] = TP_.heal, [data.AE_HIT] = TP_.ae, [data.AE_HEAL] = TP_.heal,
};
local THEME_ROUND = { TP_.r1, TP_.r2, TP_.r3, TP_.r4, TP_.r5 };

local function result_color(result)
    if (settings.ThemeColors and result ~= data.ATTACK_SHADOW) then
        local c = THEME_RESULT[result];
        if (c ~= nil) then return c, settings.BarsAlpha; end
    end
    if (result == data.ATTACK_HIT)      then return settings.ColorHit, settings.BarsAlpha; end
    if (result == data.ATTACK_CRIT)     then return settings.ColorCrit, settings.BarsAlpha; end
    if (result == data.ATTACK_MISS)     then return settings.ColorMiss, settings.BarsAlpha; end
    if (result == data.ATTACK_BLOCK)    then return settings.ColorBlock, settings.BarsAlpha; end
    if (result == data.ATTACK_HIT_ZERO) then return settings.ColorHitZero, settings.BarsAlpha; end
    if (result == data.ATTACK_COUNTER)  then return settings.ColorCounter, settings.BarsAlpha; end
    if (result == data.ATTACK_SHADOW)   then return COLOR_SHADOW, 1; end
    if (result == data.ATTACK_HEAL)     then return settings.ColorHeal, settings.BarsAlpha; end
    if (result == data.AE_HIT)          then return settings.ColorAdditionalEffect, settings.BarsAlpha; end
    if (result == data.AE_HEAL)         then return settings.ColorAdditionalEffectHeal, settings.BarsAlpha; end
    return nil, 0;
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v));
end

-- Round bar color == multi-attack tier. A round that landed nothing paints as a
-- miss (or counter) marker instead, so whiffs stay visible.
local ROUND_KEY = { 'ColorRound1', 'ColorRound2', 'ColorRound3', 'ColorRound4' };
local function round_color(r)
    if (r.hits <= 0) then
        if ((r.counter or 0) > 0) then return result_color(data.ATTACK_COUNTER); end
        return result_color(data.ATTACK_MISS);
    end
    local n = r.swings;
    if (n < 1) then n = 1; end
    if (settings.ThemeColors) then return THEME_ROUND[math.min(n, 5)], settings.BarsAlpha; end
    if (n >= 5) then return settings.ColorRound5, settings.BarsAlpha; end
    return settings[ROUND_KEY[n]], settings.BarsAlpha;
end

local function draw_bars(tlog, log_type)
    local width, height, nbars;
    if (log_type == TYPE_PET) then
        width, height, nbars = chart_width(log_type), chart_height(log_type), settings.PetChartBars;
    else
        width, height, nbars = chart_width(log_type), chart_height(log_type), settings.ChartBars;
        if (strip.on) then nbars = strip.n; end
    end

    local cx, cy = imgui.GetCursorScreenPos();
    VD[1], VD[2] = width, height;
    imgui.Dummy(VD);

    local dl = imgui.GetWindowDrawList();
    local bar_w = width / nbars;
    local gap = 0;
    if (bar_w >= 3) then gap = 1; end
    local bottom = cy + height;
    local marker_h = math.min(bar_w, height);

    -- Round mode: one bar per attack round; height from round damage, colour from swing count, thin cap on a crit.
    if (settings.BarMode == 'round') then
        local list = tlog.rlist or {};
        local off = math.max(0, #list - nbars);   -- newest nbars (strip shows fewer than are kept)
        local scale = tlog.max_round or 0;
        for i = 1, nbars do
            local r = list[off + i];
            if (r ~= nil) then
                local x1 = cx + (bar_w * (i - 1));
                local x2 = x1 + bar_w - gap;
                local color, alpha = round_color(r);
                local h = marker_h;
                if (settings.DisplayMode ~= 'simple' and scale > 0 and r.dmg > 0) then
                    h = clamp(math.floor(r.dmg / scale * height), 1, height);
                end
                if (color ~= nil) then
                    rect(dl, x1, bottom - h, x2, bottom, col_u32(color, alpha));
                    if (settings.RoundCritCap and (r.crit or 0) > 0) then
                        local cap = math.min(settings.RoundCritCapPx or 2, h);
                        local cc, ca = result_color(data.ATTACK_CRIT);
                        rect(dl, x1, bottom - h, x2, bottom - h + cap, col_u32(cc, ca));
                    end
                end
            end
        end
        return;
    end

    for i = 1, nbars do
        local entry = tlog.attacks[math.max(0, #tlog.attacks - nbars) + i];
        if (entry ~= nil) then
            local x1 = cx + (bar_w * (i - 1));
            local x2 = x1 + bar_w - gap;
            local result = entry.result;
            local dmg = entry.dmg;

            if (settings.DisplayMode == 'simple') then
                -- Uniform squares; crits fold into hits, AE hidden.
                local r = result;
                if (r == data.ATTACK_CRIT) then r = data.ATTACK_HIT; end
                local color, alpha = result_color(r);
                if (color ~= nil) then
                    rect(dl, x1, bottom - marker_h, x2, bottom, col_u32(color, alpha));
                end
            else
                if (settings.AdditionalEffectSingleBar) then
                    dmg = dmg + entry.ae_dmg;
                end

                local h = marker_h;
                local ae_h = 0;
                if (tlog.max > 0) then
                    h = clamp(math.floor(dmg / tlog.max * height), 1, height);
                    ae_h = clamp(math.floor(entry.ae_dmg / tlog.max * height), 0, height);
                    if (result == data.ATTACK_HEAL) then
                        h = clamp(h, 1, height);
                    end
                end

                -- Zero-ish outcomes render as fixed-size markers.
                if (result == data.ATTACK_MISS or result == data.ATTACK_HIT_ZERO
                    or result == data.ATTACK_COUNTER or result == data.ATTACK_SHADOW) then
                    h = marker_h;
                end

                local color, alpha = result_color(result);
                if (color ~= nil) then
                    rect(dl, x1, bottom - h, x2, bottom, col_u32(color, alpha));
                end

                -- Stacked additional effect bar on top of the physical hit.
                if (settings.AdditionalEffectStackBars and entry.ae_dmg > 0 and ae_h > 0
                    and entry.ae_result ~= data.AE_NONE) then
                    local ae_color, ae_alpha = result_color(entry.ae_result);
                    if (ae_color ~= nil) then
                        local top = clamp(bottom - h - ae_h, cy, bottom);
                        rect(dl, x1, top, x2, bottom - h, col_u32(ae_color, ae_alpha));
                    end
                end
            end
        end
    end
end

-- Label prefix: glyph mode = single-letter prefixes, word mode = the *LabelPrefix settings (TH is inline).
local GLYPH_DEFAULT = {
    -- ASCII only (the font atlas has no box / dingbat glyphs)
    Max = 'M', Last = 'L', Acc = 'A', Crit = 'C',
    Avg = '~', Zone = 'Z', Round = '#', TH = '+',
};
local WORD_PREFIX = {
    Max = 'MaxLabelPrefix', Last = 'LastLabelPrefix', Acc = 'HitRateLabelPrefix',
    Crit = 'CritRateLabelPrefix', Avg = 'AvgLabelPrefix', Zone = 'ZoneAccLabelPrefix',
    Round = 'RoundLabelPrefix',
};
local function lp(key)
    if (settings.GlyphLabels) then
        return settings['Glyph' .. key] or GLYPH_DEFAULT[key] or '';
    end
    return settings[WORD_PREFIX[key]] or (key .. ': ');
end
-- TH is its own gold '+N' token. Text / background colour tables are built once per settings version.
local tc = { v = -1 };
local RATE_GOOD, RATE_BAD = { 0.4, 1.0, 0.03, 1.0 }, { 0.93, 0.0, 0.0, 1.0 };
local T_GOOD, T_BAD = theme.f4(150, 210, 140), theme.f4(230, 110, 100);
local function refresh_cols()
    if (tc.v == ver.cfg) then return; end
    local a = settings.LabelAlpha / 255;
    local c = settings.LabelColor;
    tc.label = { c[1] / 255, c[2] / 255, c[3] / 255, a };
    c = settings.ColorTH or { 255, 200, 0 };
    tc.th = { c[1] / 255, c[2] / 255, c[3] / 255, a };
    c = settings.ColorHeal;
    tc.heal = { c[1] / 255, c[2] / 255, c[3] / 255, 1.0 };
    c = settings.BGColor;
    tc.bg = { c[1] / 255, c[2] / 255, c[3] / 255, settings.BGAlpha / 255 };
    if (settings.ThemeColors) then
        -- Same plate as the target bar panels (Look tab > Panels: clear = none, opacity).
        local pa = (theme.panel_style == 'clear') and 0 or math.min(255, theme.PLATE[4] * theme.panel_alpha);
        tc.bg = theme.f4(theme.PLATE[1], theme.PLATE[2], theme.PLATE[3], pa);
    end
    tc.good = settings.ThemeColors and T_GOOD or RATE_GOOD;
    tc.bad  = settings.ThemeColors and T_BAD or RATE_BAD;
    tc.val  = settings.ThemeColors and theme.TXT or tc.label;
    tc.lbl  = settings.ThemeColors and theme.TXT_LABEL or tc.label;
    tc.pad = { settings.BGPaddingX, settings.BGPaddingY };
    tc.spacing = { 4, 4 };
    tc.v = ver.cfg;
end
local function th_col()
    refresh_cols();
    return tc.th;
end

-- WS names cut to 12 characters.
local function clean_ws_name(name)
    name = name:gsub('Blade: ', ''):gsub('Tachi: ', ''):gsub('\'', '');
    return name:sub(1, 12);
end

local function label_col()
    refresh_cols();
    return tc.label;
end

local function draw_ws_lines(tlog)
    local i0, i1, step = 1, #tlog.ws, 1;
    if (settings.ReverseWeaponskills) then
        i0, i1, step = #tlog.ws, 1, -1;
    end
    for i = i0, i1, step do
        local ws = tlog.ws[i];
        -- formatted once per entry
        if (ws.line == nil) then
            local dmg = tostring(ws.dmg);
            if (ws.result == data.ATTACK_MISS) then dmg = 'MISS'; end
            ws.line = ('%s %s'):format(clean_ws_name(ws.name), dmg);
            if (ws.sc_name ~= nil) then
                ws.sc_line = ('> %s %s'):format(ws.sc_name:sub(1, 4), tostring(ws.sc_dmg));
            end
        end
        local line_col = tc.label;
        if (ws.result == data.ATTACK_HEAL) then line_col = tc.heal; end

        imgui.TextColored(line_col, ws.line);
        if (ws.sc_line ~= nil) then
            imgui.SameLine();
            local sc_col = tc.label;
            if (ws.sc_result == data.ATTACK_HEAL) then sc_col = tc.heal; end
            imgui.TextColored(sc_col, ws.sc_line);
        end
    end
end

local function rate_color(rate, count)
    -- >= 95 green, < 80 red
    if (settings.HitRateColorize and count > 0) then
        refresh_cols();
        if (rate >= 95) then return tc.good; end
        if (rate < 80) then return tc.bad; end
    end
    return label_col();
end

-- Average damage: whole rounds in round mode, else landed swings (heals excluded); nil when nothing landed.
local function avg_dmg(tlog)
    local sum, n = 0, 0;
    if (settings.BarMode == 'round') then
        for _, r in ipairs(tlog.rlist or {}) do
            if (r.dmg > 0) then sum, n = sum + r.dmg, n + 1; end
        end
    else
        for _, a in ipairs(tlog.attacks) do
            if (a.result ~= data.ATTACK_HEAL and a.dmg > 0) then sum, n = sum + a.dmg, n + 1; end
        end
    end
    return (n > 0) and math.floor(sum / n) or nil;
end

local function rate_fmt()
    if (settings.CompactLabels) then return '%s%d%%'; end
    return '%s%.1f%%';
end

-- Max / TH / Last round / round count group.
local function label_items_max(tlog)
    local t = {};
    local is_round = (settings.BarMode == 'round');
    if (settings.DisplayMax) then
        -- in round mode Max is the biggest round, as the bars show
        local mx = tlog.max;
        if (is_round) then mx = tlog.max_round or 0; end
        local mtxt = lp('Max') .. tostring(math.floor(mx));
        -- with the swing count of the round that set it, like Last
        if (is_round and (tlog.max_round_sw or 0) > 0) then
            mtxt = mtxt .. (' (%d)'):format(tlog.max_round_sw);
        end
        t[#t + 1] = { text = mtxt, col = label_col() };
    end
    if (settings.DisplayLast) then
        -- swings behind the number: (4) all landed, (2/4) two of a quad-attack round landed
        local s = ('%s%d'):format(lp('Last'), tlog.last_dmg or 0);
        local sw = tlog.last_swings or 0;
        if (settings.LastShowHits and sw > 0) then
            local hs = tlog.last_hits or 0;
            if (hs == sw) then
                s = s .. (' (%d)'):format(sw);
            else
                s = s .. (' (%d/%d)'):format(hs, sw);
            end
        end
        t[#t + 1] = { text = s, col = label_col() };
        -- TH: gold '+N' right after Last
        if (settings.DisplayTH and (tlog.th or 0) > 0) then
            t[#t + 1] = { text = ('+%d'):format(tlog.th), col = th_col() };
        end
    end
    if (settings.DisplayRoundCount) then
        t[#t + 1] = { text = ('%s%d'):format(lp('Round'), tlog.rounds or 0),
                      col = label_col() };
    end
    return t;
end

-- Hit / Crit / Avg / Zone group.
local function label_items_rate(tlog, log_type)
    local t = {};
    if (not settings.DisplayHitRate) then return t; end
    local fmt = rate_fmt();

    local rate = 0;
    if (tlog.count > 0) then
        rate = (tlog.count - tlog.miss) / tlog.count * 100;
    end
    t[#t + 1] = { text = fmt:format(lp('Acc'), rate),
                  col = rate_color(rate, tlog.count) };

    -- Zone accuracy in brackets after Hit ('Hit: 98% (97%)'), coloured on its own.
    if (settings.DisplayZoneAcc and log_type == TYPE_PLAYER) then
        local zrate = 0;
        if (zone_stats.count > 0) then
            zrate = (zone_stats.count - zone_stats.miss) / zone_stats.count * 100;
        end
        local zfmt = settings.CompactLabels and '(%d%%)' or '(%.1f%%)';
        t[#t + 1] = { text = zfmt:format(zrate),
                      col = rate_color(zrate, zone_stats.count) };
    end

    if (settings.DisplayAvg) then
        local avg = avg_dmg(tlog);
        if (avg ~= nil) then t[#t + 1] = { text = ('%s%d'):format(lp('Avg'), avg), col = label_col() }; end
    end

    if (settings.DisplayCritRate and tlog.count > 0) then
        t[#t + 1] = { text = fmt:format(lp('Crit'), tlog.crit / tlog.count * 100),
                      col = label_col() };
    end

    return t;
end

-- Stat grid: two rows of labeled cells, equal width, dim label + bright value.
--   LAST <dmg> <landed>/<swings> | MAX | AVG | TH
--   ACC | ZONE | CRIT | DA | TA | QA
local function pct_str(n, d)
    if (d == nil or d <= 0) then return '--'; end
    return ('%d%%'):format(math.floor(n / d * 100 + 0.5));
end

local function grid_rows(tlog, log_type)
    refresh_cols();
    local val = tc.val;
    local r1, r2 = {}, {};
    local is_round = (settings.BarMode == 'round');
    if (settings.DisplayLast) then
        local sw, hs = tlog.last_swings or 0, tlog.last_hits or 0;
        local sub, subc = nil, val;
        if (sw > 0) then
            sub = ('%d/%d'):format(hs, sw);
            subc = (hs == sw) and tc.good or ((hs == 0) and tc.bad or val);
        end
        -- melee damage, '!' when the round had a crit, (additional-effect damage) when any:
        -- 412!(96) = 412 melee incl. a crit + 96 from enspell / added effect.
        local v = tostring(tlog.last_dmg or 0);
        if (tlog.last_melee ~= nil) then
            v = tostring(tlog.last_melee) .. (tlog.last_crit and '!' or '');
            if ((tlog.last_ae or 0) > 0) then v = v .. '(' .. tostring(tlog.last_ae) .. ')'; end
        end
        r1[#r1 + 1] = { l = 'LAST', v = v, c = val, s = sub, sc = subc };
    end
    if (settings.DisplayMax) then
        local mx = is_round and (tlog.max_round or 0) or tlog.max;
        r1[#r1 + 1] = { l = 'MAX', v = tostring(math.floor(mx)), c = val };
    end
    if (settings.DisplayAvg) then
        local avg = avg_dmg(tlog);
        r1[#r1 + 1] = { l = 'AVG', v = avg and tostring(avg) or '--', c = val };
    end
    if (settings.DisplayTH and (tlog.th or 0) > 0) then
        r1[#r1 + 1] = { l = 'TH', v = tostring(tlog.th), c = th_col() };
    end
    if (settings.DisplayRoundCount) then
        r1[#r1 + 1] = { l = 'RDS', v = tostring(tlog.rounds or 0), c = val };
    end
    -- ACC <target> (<zone>): zone in brackets, own colour. ZONE alone if ACC is off.
    local zone_on = settings.DisplayZoneAcc and log_type == TYPE_PLAYER and zone_stats.count > 0;
    local zr = zone_on and ((zone_stats.count - zone_stats.miss) / zone_stats.count * 100) or 0;
    if (settings.DisplayHitRate) then
        local rate = (tlog.count > 0) and ((tlog.count - tlog.miss) / tlog.count * 100) or 0;
        local cell = { l = 'ACC', v = pct_str(tlog.count - tlog.miss, tlog.count), c = rate_color(rate, tlog.count) };
        if (zone_on) then
            cell.s = '(' .. pct_str(zone_stats.count - zone_stats.miss, zone_stats.count) .. ')';
            cell.sc = rate_color(zr, zone_stats.count);
        end
        r2[#r2 + 1] = cell;
    elseif (zone_on) then
        r2[#r2 + 1] = { l = 'ZONE', v = pct_str(zone_stats.count - zone_stats.miss, zone_stats.count),
                        c = rate_color(zr, zone_stats.count) };
    end
    if (settings.DisplayCritRate) then
        r2[#r2 + 1] = { l = 'CRIT', v = pct_str(tlog.crit, tlog.count), c = val };
    end
    if (settings.DisplayMulti) then
        -- One cell: MULTI 24/11/5% = DA / TA / QA  (share of rounds, main hand 2 / 3 / 4+ swings)
        local n = tlog.mh_rounds or 0;
        local v = '--';
        if (n > 0) then
            local function p(x) return math.floor((x or 0) / n * 100 + 0.5); end
            v = ('%d/%d/%d%%'):format(p(tlog.mh2), p(tlog.mh3), p(tlog.mh4));
        end
        r2[#r2 + 1] = { l = 'MULTI', v = v, c = val };
    end
    return r1, r2;
end

-- Fit uses fixed templates so the font size does not jitter as values change.
local CELL_TMPL = { LAST = '99999!(9999) 8/8', MAX = '99999', AVG = '99999', TH = '99', RDS = '999',
                    ACC = '100% (100%)', ZONE = '100%', CRIT = '100%', MULTI = '99/99/99%' };
local function cell_text(c)
    return c.l .. ' ' .. (CELL_TMPL[c.l] or c.v);
end

local GRID_GAP_MIN, GRID_PIECE_GAP = 10, 3;

-- Measure each cell at the current font scale (called on rebuild only).
local function measure_row(cells)
    local total = 0;
    for _, c in ipairs(cells) do
        c.wl = imgui.CalcTextSize(c.l) or 0;
        c.wv = imgui.CalcTextSize(c.v) or 0;
        c.ws = (c.s ~= nil) and (imgui.CalcTextSize(c.s) or 0) or 0;
        c.w = c.wl + GRID_PIECE_GAP + c.wv + ((c.s ~= nil) and (GRID_PIECE_GAP + c.ws) or 0);
        total = total + c.w;
    end
    cells.total = total;
end

-- Cells spread across the chart width (first at the left edge, last at the right),
-- never overlapping. SameLine offsets are relative to the BeginGroup start.
local function draw_grid_row(cells, avail)
    local n = #cells;
    if (n == 0) then return; end
    local gap = GRID_GAP_MIN;
    if (n > 1) then gap = math.max(GRID_GAP_MIN, (avail - (cells.total or 0)) / (n - 1)); end
    local x = 0;
    for i, c in ipairs(cells) do
        if (i > 1) then imgui.SameLine(x); end
        imgui.TextColored(tc.lbl, c.l);
        imgui.SameLine(x + c.wl + GRID_PIECE_GAP);
        imgui.TextColored(c.c, c.v);
        if (c.s ~= nil) then
            imgui.SameLine(x + c.wl + GRID_PIECE_GAP + c.wv + GRID_PIECE_GAP);
            imgui.TextColored(c.sc or c.c, c.s);
        end
        x = x + (c.w or 0) + gap;
    end
end

local function draw_label_row(items)
    for i, it in ipairs(items) do
        if (i > 1) then imgui.SameLine(); end
        imgui.TextColored(it.col, it.text);
    end
end

local win_flags_base = bit.bor(
    ImGuiWindowFlags_NoTitleBar,
    ImGuiWindowFlags_NoResize,
    ImGuiWindowFlags_NoScrollbar,
    ImGuiWindowFlags_NoScrollWithMouse,
    ImGuiWindowFlags_NoCollapse,
    ImGuiWindowFlags_NoFocusOnAppearing,
    ImGuiWindowFlags_NoNav);


-- Constant window size: stacked layout, width from the widest real row.
local fws_cache = {};
local fixed_window_size_calc;
local function fixed_window_size(log_type)
    local c = fws_cache[log_type];
    local cw = chart_width(log_type);
    if (c == nil or c.v ~= ver.cfg or c.cw ~= cw) then
        local w, h = fixed_window_size_calc(log_type);
        c = { v = ver.cfg, cw = cw, w = w, h = h };
        fws_cache[log_type] = c;
    end
    return c.w, c.h;
end

fixed_window_size_calc = function (log_type)
    local width, height;
    if (log_type == TYPE_PET) then
        width, height = chart_width(log_type), chart_height(log_type);
    else
        width, height = chart_width(log_type), theme.px(settings.ChartHeight);
    end

    -- Measured at scale 1 outside the window; the chart draws at FontScale
    -- (AutoFit only ever shrinks below it), so size for FontScale or rows clip.
    local fs = tonumber(settings.FontScale) or 1.0;
    local spacing = 4;
    local _, line_h = imgui.CalcTextSize('Hg');
    line_h = (line_h or 13) * fs;

    local rows = 1; -- chart dummy
    local content_h = height;
    local content_w = width;

    local max_tmpl, rate_tmpl;
    if (settings.DisplayMax) then
        max_tmpl = lp('Max') .. '99999 (8)';
    end
    if (settings.DisplayLast) then
        max_tmpl = (max_tmpl or '') .. ' ' .. lp('Last') .. '99999';
        if (settings.LastShowHits) then max_tmpl = max_tmpl .. ' (8/8)'; end
        if (settings.DisplayTH) then
            max_tmpl = max_tmpl .. ' +9';
        end
    end
    if (settings.DisplayRoundCount) then
        max_tmpl = (max_tmpl or '') .. ' ' .. lp('Round') .. '999';
    end
    if (settings.DisplayHitRate) then
        rate_tmpl = lp('Acc') .. '100%';
        if (not settings.CompactLabels) then rate_tmpl = lp('Acc') .. '100.0%'; end
        if (settings.DisplayCritRate) then
            rate_tmpl = rate_tmpl .. ' ' .. lp('Crit') .. '100%';
        end
        if (settings.DisplayAvg) then
            rate_tmpl = rate_tmpl .. ' ' .. lp('Avg') .. '9999';
        end
        if (settings.DisplayZoneAcc and log_type ~= TYPE_PET) then
            rate_tmpl = rate_tmpl .. (settings.CompactLabels and ' (100%)' or ' (100.0%)');
        end
    end

    if (settings.StatGrid) then
        content_h = content_h + 2 * line_h;
        rows = rows + 2;
    elseif (settings.SingleLineLabels) then
        if (max_tmpl ~= nil or rate_tmpl ~= nil) then
            local combined = ((max_tmpl or '') .. ' ' .. (rate_tmpl or '')):gsub('^%s+', '');
            content_h = content_h + line_h;
            rows = rows + 1;
            if (settings.WidthFromLabels) then
                local w = imgui.CalcTextSize(combined);
                content_w = math.max(content_w, (w or 0) * fs);
            end
        end
    else
        if (max_tmpl ~= nil) then
            content_h = content_h + line_h;
            rows = rows + 1;
            if (settings.WidthFromLabels) then
                local w = imgui.CalcTextSize(max_tmpl);
                content_w = math.max(content_w, (w or 0) * fs);
            end
        end
        if (rate_tmpl ~= nil) then
            content_h = content_h + line_h;
            rows = rows + 1;
            if (settings.WidthFromLabels) then
                local w = imgui.CalcTextSize(rate_tmpl);
                content_w = math.max(content_w, (w or 0) * fs);
            end
        end
    end

    if (settings.DisplayWeaponskills) then
        local n = ws_count(log_type);
        content_h = content_h + (n * line_h);
        rows = rows + n;
        if (settings.WidthFromLabels) then
            local w = imgui.CalcTextSize('Wwwwwwwwwwww 99999 > Wwww 99999');
            content_w = math.max(content_w, (w or 0) * fs);
        end
    end

    content_h = content_h + ((rows - 1) * spacing);

    return content_w + (2 * settings.BGPaddingX),
           content_h + (2 * settings.BGPaddingY);
end

local WIN_NAME = { [TYPE_PLAYER] = 'aaev_' .. TYPE_PLAYER, [TYPE_PET] = 'aaev_' .. TYPE_PET };
local row_cache = { [TYPE_PLAYER] = {}, [TYPE_PET] = {} };

local function draw_chart(log_type)
    local tid = state.display_target[log_type];
    local tlog = nil;
    if (tid ~= nil) then tlog = logs[log_type][tid]; end
    if (tlog ~= nil and #tlog.attacks == 0 and #tlog.ws == 0) then tlog = nil; end
    if (tlog == nil) then
        -- No live data: AlwaysShow keeps an empty player frame on screen.
        if (not (settings.AlwaysShow and log_type == TYPE_PLAYER)) then return; end
        tlog = idle_log;
    end

    local start_x, start_y;
    if (log_type == TYPE_PET) then
        start_x, start_y = settings.PetChartStartX, settings.PetChartStartY;
    else
        start_x, start_y = settings.ChartStartX, settings.ChartStartY;
    end

    local flags = win_flags_base;
    if (not state.unlocked) then
        flags = bit.bor(flags, ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoMouseInputs);
    end
    if (not settings.BGDisplay) then
        flags = bit.bor(flags, ImGuiWindowFlags_NoBackground);
    end

    local docked = (log_type == TYPE_PLAYER and dock.on);
    if (docked) then
        VS[1], VS[2] = dock.x, dock.y;
        imgui.SetNextWindowPos(VS, ImGuiCond_Always);
        flags = bit.bor(flags, ImGuiWindowFlags_NoMove);
        state.applied_pos[log_type] = false;   -- re-apply saved pos if undocked later
    elseif (not state.applied_pos[log_type]) then
        imgui.SetNextWindowPos({ start_x, start_y }, ImGuiCond_Always);
        state.applied_pos[log_type] = true;
    end

    if (settings.FixedSize) then
        local fw, fh = fixed_window_size(log_type);
        if (docked) then fw = dock.win_w; end
        VS[1], VS[2] = fw, fh;
        imgui.SetNextWindowSize(VS, ImGuiCond_Always);
    else
        flags = bit.bor(flags, ImGuiWindowFlags_AlwaysAutoResize);
    end

    refresh_cols();
    imgui.PushStyleColor(ImGuiCol_WindowBg, tc.bg);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, docked and dock.pad or tc.pad);
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, tc.spacing);
    -- Theme: rounded plate, no border (same look as the target bar panels).
    local nvars = 2;
    if (settings.ThemeColors) then
        imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 3.0);
        imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0);
        nvars = 4;
    end

    if (imgui.Begin(WIN_NAME[log_type], nil, flags)) then
        -- Label rows + fit scale rebuilt only when this log, zone stats or settings change.
        local lc = row_cache[log_type];
        local zv = (log_type == TYPE_PLAYER) and zone_stats.v or 0;
        local cw_now = chart_width(log_type);
        if (settings.StatGrid and (not lc.grid or lc.tlog ~= tlog or lc.v ~= tlog.v or lc.zv ~= zv or lc.cv ~= ver.cfg or lc.cw ~= cw_now)) then
            local g1, g2 = grid_rows(tlog, log_type);
            -- Fit: widest cell x cell count must fit the chart width.
            local scale = settings.FontScale or 1.0;
            if (settings.AutoFitLabels) then
                set_font_scale(1.0);
                for _, row in ipairs({ g1, g2 }) do
                    local need = 0;
                    for _, c in ipairs(row) do need = need + (imgui.CalcTextSize(cell_text(c)) or 0); end
                    local gaps = math.max(0, #row - 1) * GRID_GAP_MIN;
                    if (need > 0 and cw_now > gaps and need * scale + gaps > cw_now) then
                        scale = math.max(settings.MinFontScale or 0.55, (cw_now - gaps) / need);
                    end
                end
            end
            -- Real widths at the scale actually drawn.
            set_font_scale(scale);
            measure_row(g1);
            measure_row(g2);
            lc.top, lc.bot, lc.scale, lc.grid = g1, g2, scale, true;
            lc.tlog, lc.v, lc.zv, lc.cv, lc.cw = tlog, tlog.v, zv, ver.cfg, cw_now;
        elseif ((not settings.StatGrid) and (lc.grid or lc.tlog ~= tlog or lc.v ~= tlog.v or lc.zv ~= zv or lc.cv ~= ver.cfg)) then
            lc.grid = false;
            local top_row = label_items_max(tlog);
            local bot_row = label_items_rate(tlog, log_type);
            -- SingleLineLabels folds Max / TH onto the stat row (one text line).
            if (settings.SingleLineLabels) then
                for i = #top_row, 1, -1 do
                    table.insert(bot_row, 1, top_row[i]);
                end
                top_row = {};
            end

            -- Width follows ChartWidth: a row that would overflow shrinks the font.
            local scale = settings.FontScale or 1.0;
            if (settings.AutoFitLabels and not settings.WidthFromLabels) then
                -- Measure at 1.0.
                set_font_scale(1.0);
                local widest = 0;
                for _, row in ipairs({ top_row, bot_row }) do
                    if (#row > 0) then
                        local parts = {};
                        for i, it in ipairs(row) do parts[i] = it.text; end
                        local w = imgui.CalcTextSize(table.concat(parts, ' ')) or 0;
                        if (w > widest) then widest = w; end
                    end
                end
                local avail = chart_width(log_type);
                if (widest > 0 and avail > 0 and (widest * scale) > avail) then
                    scale = math.max(settings.MinFontScale or 0.55, avail / widest);
                end
            end
            lc.top, lc.bot, lc.scale = top_row, bot_row, scale;
            lc.tlog, lc.v, lc.zv, lc.cv = tlog, tlog.v, zv, ver.cfg;
        end
        local top_row, bot_row = lc.top, lc.bot;
        set_font_scale(lc.scale);

        imgui.BeginGroup();

        if (lc.grid) then
            -- Bars on top (flush under the target bar), stat cells below.
            draw_bars(tlog, log_type);
            draw_grid_row(top_row, cw_now);
            draw_grid_row(bot_row, cw_now);
        else
            if (#top_row > 0) then
                draw_label_row(top_row);
            end

            draw_bars(tlog, log_type);

            if (#bot_row > 0) then
                draw_label_row(bot_row);
            end
        end

        -- Weaponskill results below the chart (narrower window than a side column).
        if (settings.DisplayWeaponskills and (#tlog.ws > 0 or settings.FixedSize)) then
            draw_ws_lines(tlog);
            if (settings.FixedSize) then
                for _ = #tlog.ws + 1, ws_count(log_type) do
                    imgui.Text(' ');
                end
            end
        end

        imgui.EndGroup();

        if (state.unlocked) then
            local wx, wy = imgui.GetWindowPos();
            state['pos_' .. log_type] = { math.floor(wx), math.floor(wy) };
        end
    end
    imgui.End();
    imgui.PopStyleVar(nvars);
    imgui.PopStyleColor(1);
end

-- One-line strip: [round bars][LAST .. ACC .. CRIT .. AVG .. MULTI .. WS], cells spread
-- over the rest of the width; text shrinks to fit the width and the strip height.
local strip_cache = { };
-- Dropped first when the line is too wide; LAST, ACC/CRIT and MULTI always stay.
local STRIP_DROP = { 'MAX', 'RDS', 'TH', 'AVG', 'WS' };
local STRIP_GAP = 12;   -- px between cells (packed left, not spread)

-- Strip cells: LAST | AVG | ACC/CRIT (zone-wide) | MULTI (DA/TA/QA) | WS (last) | MAX / TH / RDS if shown.
local function strip_cells(tlog, log_type)
    local g1, g2 = grid_rows(tlog, log_type);
    local by = { };
    for _, c in ipairs(g1) do by[c.l] = c; end
    for _, c in ipairs(g2) do by[c.l] = c; end
    local cells = { };
    local function add(c) if (c ~= nil) then cells[#cells + 1] = c; end end
    add(by['LAST']);
    add(by['AVG']);
    if (settings.DisplayHitRate or settings.DisplayCritRate) then
        -- Zone-wide accuracy / crit rate (survives target changes; resets on zone).
        local n = zone_stats.count;
        local acc = (n > 0) and ((n - zone_stats.miss) / n * 100) or 0;
        local v = (n > 0) and ('%d/%d%%'):format(math.floor(acc + 0.5), math.floor(zone_stats.crit / n * 100 + 0.5)) or '--';
        add({ l = 'ACC/CRIT', v = v, c = rate_color(acc, n) });
    end
    add(by['MULTI']);
    if (settings.DisplayWeaponskills and #tlog.ws > 0) then
        local ws = tlog.ws[#tlog.ws];
        local dmg = (ws.result == data.ATTACK_MISS) and 'MISS' or tostring(ws.dmg);
        add({ l = 'WS', v = clean_ws_name(ws.name) .. ' ' .. dmg, c = tc.val });
    end
    add(by['MAX']);
    add(by['TH']);
    add(by['RDS']);
    return cells;
end
local function draw_strip(log_type)
    local tid = state.display_target[log_type];
    local tlog = (tid ~= nil) and logs[log_type][tid] or nil;
    if (tlog ~= nil and #tlog.attacks == 0 and #tlog.ws == 0) then tlog = nil; end
    if (tlog == nil) then
        if (not settings.AlwaysShow) then return; end
        tlog = idle_log;
    end

    local flags = bit.bor(win_flags_base, ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoMouseInputs);
    if (not settings.BGDisplay) then flags = bit.bor(flags, ImGuiWindowFlags_NoBackground); end
    VS[1], VS[2] = strip.x, strip.y;
    imgui.SetNextWindowPos(VS, ImGuiCond_Always);
    VS[1], VS[2] = strip.w, strip.h;
    imgui.SetNextWindowSize(VS, ImGuiCond_Always);

    refresh_cols();
    imgui.PushStyleColor(ImGuiCol_WindowBg, tc.bg);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, strip.pad);
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, strip.sp);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 2.0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0);
    VD[1], VD[2] = 1, 1;
    imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, VD);   -- imgui's 32px minimum would not fit the gap
    local nvars = 5;

    if (imgui.Begin('aaev_strip', nil, flags)) then
        local lc = strip_cache;
        local zv = zone_stats.v;
        if (lc.tlog ~= tlog or lc.v ~= tlog.v or lc.zv ~= zv or lc.cv ~= ver.cfg or lc.w ~= strip.w or lc.h ~= strip.h) then
            local cells = strip_cells(tlog, log_type);
            local avail = strip.w - strip.bw - 2 * strip.pad[1] - 10;
            local scale = settings.FontScale or 1.0;
            -- Shrink a little for width (not below 0.85: stays readable); then drop cells.
            set_font_scale(1.0);
            local need = 0;
            for _, c in ipairs(cells) do
                local t = (c.l == 'WS') and 'WS Wwwwwwwwwwww 99999' or cell_text(c);
                need = need + (imgui.CalcTextSize(t) or 0);
            end
            local gaps = math.max(0, #cells - 1) * STRIP_GAP;
            if (need > 0 and avail > gaps and need * scale + gaps > avail) then
                scale = math.max(0.85, (avail - gaps) / need);
            end
            set_font_scale(scale);
            local _, lh = imgui.CalcTextSize('Hg');
            lc.text_y = math.max(0, math.floor((strip.h - (lh or 0)) / 2));
            measure_row(cells);
            -- Still too wide: drop the least important cells first.
            for _, drop in ipairs(STRIP_DROP) do
                if ((cells.total or 0) + math.max(0, #cells - 1) * STRIP_GAP <= avail) then break; end
                for i = #cells, 1, -1 do
                    if (cells[i].l == drop) then
                        cells.total = cells.total - (cells[i].w or 0);
                        table.remove(cells, i);
                    end
                end
            end
            lc.cells, lc.scale, lc.avail = cells, scale, avail;
            lc.tlog, lc.v, lc.zv, lc.cv, lc.w, lc.h = tlog, tlog.v, zv, ver.cfg, strip.w, strip.h;
        end
        set_font_scale(lc.scale);

        -- bars (vertically centred), then the cells; SameLine offsets are from the window's left edge
        imgui.SetCursorPosY(math.floor((strip.h - strip.bh) / 2));
        draw_bars(tlog, log_type);
        local cells = lc.cells;
        local x = strip.pad[1] + strip.bw + 10;
        local gap = STRIP_GAP;
        for _, c in ipairs(cells) do
            imgui.SameLine(x);
            imgui.SetCursorPosY(lc.text_y or 0);
            imgui.TextColored(tc.lbl, c.l);
            imgui.SameLine(x + c.wl + GRID_PIECE_GAP);
            imgui.TextColored(c.c, c.v);
            if (c.s ~= nil) then
                imgui.SameLine(x + c.wl + GRID_PIECE_GAP + c.wv + GRID_PIECE_GAP);
                imgui.TextColored(c.sc or c.c, c.s);
            end
            x = x + (c.w or 0) + gap;
        end
    end
    imgui.End();
    imgui.PopStyleVar(nvars);
    imgui.PopStyleColor(1);
end

function M.render()
    if (not settings.enabled) then
        -- GUI edits made while disabled still need flushing.
        if (saved_dirty_at ~= nil) then saved_dirty_at = nil; save_saved(); end
        return;
    end

    local p = GetPlayerEntity();
    if (p == nil or p.ServerId == nil or p.ServerId == 0) then
        ids.pid, ids.petid = nil, nil;
        return;
    end
    ids.pid, ids.petid = p.ServerId, pet_id(p);
    poll_state(p);

    -- Chat strip (default): one line in the gap under the chat log.
    strip.on = (settings.Position == 'chat');
    if (strip.on) then
        local sw = (scaling.window.w > 0) and scaling.window.w or 1920;
        local sh = (scaling.window.h > 0) and scaling.window.h or 1080;
        local h = math.max(8, math.min(40, math.floor(tonumber(settings.StripH) or 15)));
        local w = tonumber(settings.StripW) or -1;
        if (w <= 0) then w = math.floor(sw * 0.302 + 0.5); end
        local x = tonumber(settings.StripX) or -1;
        if (x < 0) then x = math.floor(sw * 0.0075 + 0.5); end
        -- Height grows to fit the font (imgui text is not shrunk for height).
        local _, lh = imgui.CalcTextSize('Hg');
        h = math.max(h, math.ceil((lh or 13) * (settings.FontScale or 1.0)) + 2 * strip.pad[2]);
        strip.n = math.max(5, math.min(100, math.floor(tonumber(settings.StripRounds) or 25)));
        local px = math.max(2, math.min(20, math.floor(tonumber(settings.StripBarPx) or 5)));
        strip.x, strip.w, strip.h = x, w, h;
        strip.y = sh - (tonumber(settings.StripBottom) or 1) - h;
        strip.bw = math.min(math.floor(w * 0.6), strip.n * px);
        strip.bh = math.max(4, h - 2 * strip.pad[2] - 2);
    end

    -- Dock under the target bar: same x and outer width as the bar panel.
    dock.on = false;
    if (settings.Position == 'bar' and M.anchor_fn ~= nil) then
        local ok, x, y, win_w, dx, bw = pcall(M.anchor_fn);
        if (ok and type(x) == 'number' and type(win_w) == 'number' and win_w > 0) then
            -- Chart spans exactly the HP bar's columns; window = the bar's panel.
            dock.on, dock.x, dock.y, dock.win_w = true, x, y + 1, win_w;
            dock.pad[1] = (type(dx) == 'number' and dx >= 0) and dx or 12;
            dock.pad[2] = settings.BGPaddingY or 4;
            dock.w = math.max(20, (type(bw) == 'number' and bw > 0) and bw or (win_w - 2 * dock.pad[1]));
        end
    end

    local show_player = state.visible[TYPE_PLAYER] or settings.AlwaysShow;
    if (state.forced_hidden) then show_player = false; end
    if (show_player) then
        if (strip.on) then draw_strip(TYPE_PLAYER); else draw_chart(TYPE_PLAYER); end
    end
    strip.on = false;   -- pet chart always uses its own size
    if (state.visible[TYPE_PET] and settings.PetChart and data.pet_jobs[state.last_job]) then
        draw_chart(TYPE_PET);
    end
end

----------------------------------------------------------------------------------------------------
-- Demo dataset
----------------------------------------------------------------------------------------------------

local function make_demo(log_type)
    math.randomseed(os.time());
    local tlog = get_target_log(log_type, 'DEMO', true);
    tlog.count, tlog.max, tlog.miss, tlog.crit, tlog.th = 100, 0, 16, 21, 5;
    tlog.rounds, tlog.last_dmg = 37, 412;
    tlog.attacks = {};
    tlog.ws = {};

    -- Round-mode demo set: mixed multi-attack tiers so every color shows up.
    tlog.rlist = {};
    tlog.max_round = 0;
    tlog.max_round_sw = 0;
    for _ = 1, chart_bars(log_type) do
        local sw = 1;
        local roll = math.random(100);
        if (roll > 92) then sw = 4;
        elseif (roll > 78) then sw = 3;
        elseif (roll > 50) then sw = 2; end
        local hits, dmg = 0, 0;
        for _ = 1, sw do
            if (math.random(100) > 12) then
                hits = hits + 1;
                dmg = dmg + math.random(180, 460);
            end
        end
        local crit = 0;
        if (hits > 0 and math.random(100) > 75) then
            crit = 1;
            dmg = dmg + math.random(120, 300);
        end
        if (dmg > tlog.max_round) then tlog.max_round = dmg; tlog.max_round_sw = sw; end
        table.insert(tlog.rlist, { dmg = dmg, swings = sw, hits = hits,
                                   crit = crit, counter = 0, ae_dmg = 0 });
    end
    tlog.mh_rounds, tlog.mh2, tlog.mh3, tlog.mh4 = 37, 9, 4, 2;
    local lastr = tlog.rlist[#tlog.rlist];
    if (lastr ~= nil) then
        tlog.last_dmg, tlog.last_hits, tlog.last_swings = lastr.dmg, lastr.hits, lastr.swings;
        tlog.last_melee, tlog.last_crit, tlog.last_ae = lastr.dmg, (lastr.crit or 0) > 0, 96;
    end

    local results = {
        data.ATTACK_HIT, data.ATTACK_HIT, data.ATTACK_HIT, data.ATTACK_CRIT,
        data.ATTACK_BLOCK, data.ATTACK_MISS, data.ATTACK_HIT_ZERO, data.ATTACK_HIT,
        data.ATTACK_CRIT, data.ATTACK_HEAL,
    };
    for _ = 1, chart_bars(log_type) do
        local r = results[math.random(#results)];
        local dmg = 0;
        if (r == data.ATTACK_HIT or r == data.ATTACK_CRIT or r == data.ATTACK_HEAL) then
            dmg = math.random(40, 125);
        elseif (r == data.ATTACK_BLOCK) then
            dmg = math.random(10, 35);
        end
        local ae = data.AE_NONE;
        local ae_dmg = 0;
        if (settings.AdditionalEffectStackBars and math.random() < 0.5 and dmg > 0) then
            ae = data.AE_HIT;
            ae_dmg = math.random(5, 25);
        end
        local total = dmg;
        if (r == data.ATTACK_HEAL) then total = 0; end
        if (settings.AdditionalEffectSingleBar or settings.AdditionalEffectStackBars) then
            total = total + ae_dmg;
        end
        tlog.max = math.max(tlog.max, total);
        table.insert(tlog.attacks, { result = r, dmg = dmg, ae_result = ae, ae_dmg = ae_dmg });
    end

    tlog.ws = {
        { name = 'Evisceration',  dmg = 1500,  result = data.ATTACK_HIT },
        { name = 'Rudra\'s Storm', dmg = 2000, result = data.ATTACK_HEAL, sc_name = 'Darkness', sc_dmg = 5000, sc_result = data.ATTACK_HIT },
        { name = 'Rudra\'s Storm', dmg = 3000, result = data.ATTACK_HIT, sc_name = 'Darkness', sc_dmg = 10000, sc_result = data.ATTACK_HEAL },
        { name = 'Viper Bite',    dmg = 666,   result = data.ATTACK_HIT },
        { name = 'Viper Bite',    dmg = 99999, result = data.ATTACK_HIT, sc_name = 'Scission', sc_dmg = 123, sc_result = data.ATTACK_HIT },
    };
    while (#tlog.ws > ws_count(log_type)) do
        table.remove(tlog.ws, 1);
    end
    tlog.v = (tlog.v or 0) + 1;
end

local function demo()
    make_demo(TYPE_PLAYER);
    state.display_target[TYPE_PLAYER] = 'DEMO';
    state.visible[TYPE_PLAYER] = true;
    if (settings.PetChart and is_pet_job()) then
        make_demo(TYPE_PET);
        state.display_target[TYPE_PET] = 'DEMO';
        state.visible[TYPE_PET] = true;
    end
end

----------------------------------------------------------------------------------------------------
-- Config window (mirrors the targetbar settings UI)
----------------------------------------------------------------------------------------------------

local function set_setting(key, value)
    settings[key] = value;
    ver.cfg = ver.cfg + 1;
    saved_dirty_at = os.clock();   -- flushed by poll_state after 0.5s idle
end

local function cfg_check(label, key)
    local v = { settings[key] == true };
    if (imgui.Checkbox(label, v)) then
        set_setting(key, v[1]);
        return true;
    end
    return false;
end

-- Same-line checkbox pair: label A + label B share one row. Callers pass a
-- shared min width so the two columns stay aligned when the labels differ in
-- length (imgui's default SameLine just butts them together).
local function cfg_check_pair(la, ka, lb, kb, col_w)
    cfg_check(la, ka);
    if (kb ~= nil) then
        imgui.SameLine(col_w or 220, 0);
        return cfg_check(lb, kb);
    end
end

-- InputInt buffered per widget id: commit + clamp + save when the field loses focus (no clamping mid-typing).
local int_buf = {};

local function cfg_int(label, key, lo, hi)
    local id = label .. '#' .. key;
    local cur = math.floor(tonumber(settings[key]) or 0);
    if (int_buf[id] == nil or not int_buf[id].editing) then
        int_buf[id] = { v = { cur }, editing = false };
    end
    local buf = int_buf[id];
    local changed = imgui.InputInt(label, buf.v);
    if (changed) then buf.editing = true; end

    if (not released(changed)) then return false; end

    buf.editing = false;
    local n = math.floor(tonumber(buf.v[1]) or cur);
    if (n < lo) then n = lo; elseif (n > hi) then n = hi; end
    buf.v[1] = n;
    if (n ~= cur) then set_setting(key, n); return true; end
    return false;
end

local function cfg_slider(label, key, lo, hi)
    local v = { math.floor(tonumber(settings[key]) or 0) };
    if (imgui.SliderInt(label, v, lo, hi)) then
        set_setting(key, clamp(math.floor(v[1]), lo, hi));
        return true;
    end
    return false;
end

local function cfg_float(label, key, lo, hi)
    local v = { tonumber(settings[key]) or 0 };
    if (imgui.SliderFloat(label, v, lo, hi)) then
        set_setting(key, clamp(v[1], lo, hi));
        return true;
    end
    return false;
end

local function cfg_note(text) imgui.TextDisabled(text); end

-- '(?)' with a hover tooltip
local function help_marker(text)
    imgui.SameLine();
    imgui.TextDisabled('(?)');
    if (imgui.IsItemHovered()) then
        imgui.BeginTooltip();
        imgui.Text(text);
        imgui.EndTooltip();
    end
end

local function apply_chart_pos()
    state.applied_pos[TYPE_PLAYER] = false;
    state.applied_pos[TYPE_PET] = false;
    save_positions();
end

local function tab_display()
    local full = { settings.DisplayMode ~= 'simple' };
    if (imgui.Checkbox('Damage-scaled bars', full)) then
        set_setting('DisplayMode', full[1] and 'full' or 'simple');
    end
    help_marker('Off: uniform result squares. On: bar height scales with damage.');

    local rmode = { settings.BarMode == 'round' };
    if (imgui.Checkbox('One bar per attack round', rmode)) then
        set_setting('BarMode', rmode[1] and 'round' or 'swing');
    end
    help_marker('Off: one bar per swing. On: one bar per round, color = swing count.');

    if (settings.BarMode == 'round' and settings.ThemeColors) then
        cfg_note('  dark blue single / blue double / light blue triple / lavender quad / violet 5+');
        cfg_note('  grey bar = round landed nothing. Gold cap = round had a crit.');
    elseif (settings.BarMode == 'round') then
        cfg_note('  blue single / cyan double / green triple / yellow quad / orange 5+');
        cfg_note('  white or red bar = round landed nothing. Max and Avg are per round.');
        cfg_check('  Cap rounds that crit with a thin bar', 'RoundCritCap');
    end

    imgui.Separator();

    cfg_check('Always show (permanent chart, ignores disengage)', 'AlwaysShow');
    if (settings.AlwaysShow) then
        cfg_note('  Auto-hide ignored while Always show is on.');
    else
        cfg_check('Auto-hide on disengage', 'AutoHide');
        cfg_float('Hide delay (sec)', 'HideDelay', 0.0, 20.0);
    end
    cfg_check_pair('Continuous log', 'DisplayContinuous',
                   'Follow target', 'ResetOnTargetChange', 200);
    cfg_check('Fixed window size (no resize jumps)', 'FixedSize');
end

local function tab_layout()
    imgui.Text('Player chart position');
    for _, p in ipairs({ { 'chat', 'Under chat log' }, { 'bar', 'Under target bar' }, { 'free', 'Free (drag)' } }) do
        imgui.SameLine();
        if (imgui.Button(((settings.Position == p[1]) and '> ' or '  ') .. p[2] .. '##aaev_pos_' .. p[1])) then
            set_setting('Position', p[1]);
        end
    end
    if (settings.Position == 'chat') then
        cfg_note('  One line in the gap under the chat log. -1 = auto (fits the default log).');
        cfg_int('X (-1 auto)##strip', 'StripX', -1, 8000);
        imgui.SameLine();
        cfg_int('Width (-1 auto)##strip', 'StripW', -1, 8000);
        cfg_int('Height##strip', 'StripH', 8, 40);
        imgui.SameLine();
        cfg_int('Gap to screen bottom##strip', 'StripBottom', 0, 400);
        cfg_int('Rounds shown##strip', 'StripRounds', 5, 100);
        imgui.SameLine();
        cfg_int('Px per round##strip', 'StripBarPx', 2, 20);
        cfg_note('  ACC/CRIT here are zone-wide. Cells that do not fit are dropped: MAX, TH, AVG, WS.');
        cfg_note('  Weaponskills show as one WS cell (last one). Pet chart is unchanged.');
    elseif (settings.Position == 'bar') then
        cfg_note('  Flush under the target bar, same x and width. Move the bar to move both.');
    end
    cfg_check('goomui colours', 'ThemeColors');
    help_marker('Shared palette with the target bar and party list. Off: the Color* values in aaev.lua.');
    cfg_check('Stat grid (labeled cells under the bars)', 'StatGrid');
    if (settings.StatGrid) then
        cfg_check('  DA / TA / QA columns', 'DisplayMulti');
        help_marker('Share of rounds where the main hand swung 2 / 3 / 4+ times (0x028 sub_kind 0). '
            .. 'Weapons that occasionally attack 2-4 times count here too.');
    end
    imgui.Separator();
    imgui.Text('Player chart');
    if (settings.Position ~= 'free') then cfg_note('  X / Y / Width below apply to the Free position.'); end
    local unlocked = { state.unlocked };
    if (imgui.Checkbox('Unlock -- drag charts with the mouse', unlocked)) then
        state.unlocked = unlocked[1];
        if (not state.unlocked) then
            local p = state['pos_' .. TYPE_PLAYER];
            if (p ~= nil) then
                settings.ChartStartX, settings.ChartStartY = p[1], p[2];
            end
            local pp = state['pos_' .. TYPE_PET];
            if (pp ~= nil) then
                settings.PetChartStartX, settings.PetChartStartY = pp[1], pp[2];
            end
            save_positions();
        end
    end
    if (cfg_int('X##chartpos', 'ChartStartX', 0, 8000)) then apply_chart_pos(); end
    imgui.SameLine();
    if (cfg_int('Y##chartpos', 'ChartStartY', 0, 8000)) then apply_chart_pos(); end
    cfg_int('Width', 'ChartWidth', 20, 2000);
    imgui.SameLine();
    cfg_int('Height', 'ChartHeight', 4, 400);
    cfg_int((settings.BarMode == 'round') and 'Bars (rounds)' or 'Bars (swings)',
            'ChartBars', 1, 100);
    cfg_check('Let labels widen the window', 'WidthFromLabels');
    if (not settings.WidthFromLabels) then
        if (font_scale_ok) then cfg_check('Shrink label text to fit the width', 'AutoFitLabels'); end
    end

    imgui.Separator();
    imgui.Text('Appearance');
    cfg_slider('Bar alpha',        'BarsAlpha', 0, 255);
    cfg_check('Draw background panel', 'BGDisplay');
    if (settings.BGDisplay) then
        cfg_slider('  Background alpha', 'BGAlpha', 0, 255);
    end
    if (font_scale_ok) then cfg_float('Font scale', 'FontScale', 0.5, 3.0); end
end

local function tab_stats()
    -- two-column checkbox grid, ~220 px per column
    imgui.Text('Which numbers to show');
    cfg_check_pair('Max damage',              'DisplayMax',
                   'Average damage',          'DisplayAvg',      220);
    cfg_check_pair('Last round damage',       'DisplayLast',
                   'Round counter (this mob)','DisplayRoundCount', 220);
    cfg_check_pair('Hit rate (current mob)',  'DisplayHitRate',
                   'Crit rate',               'DisplayCritRate', 220);
    cfg_check_pair('Zone accuracy',           'DisplayZoneAcc',
                   'Treasure Hunter tier',    'DisplayTH',       220);
    if (settings.DisplayLast) then
        cfg_check('  Last: include swing count, e.g. "Last: 2547 (4)"', 'LastShowHits');
    end
    help_marker('TH rides on Last; disabling Last hides it.');

    imgui.Separator();
    imgui.Text('Format');
    -- stored as GlyphLabels
    cfg_check('Short prefixes  ("M 999" instead of "Max: 999")', 'GlyphLabels');
    help_marker(
        'Off: "Max: 999   Last: 2547   Acc: 92%   Crit: 8%"\n'
     .. 'On:  "M 999   L 2547   A 92%   C 8%"\n'
     .. 'Single-letter labels save room when the chart is narrow.');
    cfg_check_pair('One label row',           'SingleLineLabels',
                   'Whole-number rates',      'CompactLabels', 220);
    cfg_check('Colorize accuracy  (green >=95, red <80)', 'HitRateColorize');
end

local function tab_weaponskills()
    cfg_check('Show weaponskill list', 'DisplayWeaponskills');
    if (settings.DisplayWeaponskills) then
        cfg_check('Newest at top', 'ReverseWeaponskills');
        cfg_int('Lines kept', 'WeaponskillCount', 1, 20);
    end
end

local function tab_effects()
    local single = { settings.AdditionalEffectSingleBar == true };
    if (imgui.Checkbox('Fold AE damage into the hit bar', single)) then
        set_setting('AdditionalEffectSingleBar', single[1]);
        if (single[1]) then set_setting('AdditionalEffectStackBars', false); end
    end
    if (not settings.AdditionalEffectSingleBar) then
        cfg_check('Stack AE damage as a second bar', 'AdditionalEffectStackBars');
    end
    cfg_note('Additional effects: enspells, TH procs, aftermath damage, etc.');
end

local function tab_pet()
    cfg_check('Show pet chart (BST / DRG / SMN / PUP)', 'PetChart');
    if (not settings.PetChart) then return; end
    imgui.Separator();
    if (cfg_int('X##petpos', 'PetChartStartX', 0, 8000)) then apply_chart_pos(); end
    imgui.SameLine();
    if (cfg_int('Y##petpos', 'PetChartStartY', 0, 8000)) then apply_chart_pos(); end
    cfg_int('Width##pet',  'PetChartWidth',  20, 2000);
    imgui.SameLine();
    cfg_int('Height##pet', 'PetChartHeight', 4,  400);
    cfg_int('Bars##pet',   'PetChartBars', 1, 100);
    cfg_int('Weaponskill lines##pet', 'PetWeaponskillCount', 1, 20);
end

local function tab_footer()
    imgui.Separator();
    if (imgui.Button('Demo data')) then demo(); end
    imgui.SameLine();
    if (imgui.Button('Reset zone accuracy')) then
        zone_reset();
    end
    imgui.SameLine();
    if (imgui.Button('Reset all to defaults')) then
        M.reset_defaults();
    end
    cfg_note('Changes save per character as you make them.');
end

local TABS = { { 'Display', tab_display }, { 'Layout', tab_layout }, { 'Stats', tab_stats },
               { 'Weaponskills', tab_weaponskills }, { 'Effects', tab_effects }, { 'Pet', tab_pet } };
function M.draw_config_body()
    if (imgui.BeginTabBar('##aaev_tabs')) then
        for _, t in ipairs(TABS) do
            if (imgui.BeginTabItem(t[1])) then t[2](); imgui.EndTabItem(); end
        end
        imgui.EndTabBar();
    end
    tab_footer();
end

----------------------------------------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------------------------------------

local function msg(s)
    print(chat.header(addon.name):append(chat.message(s)));
end

local function show_help()
    msg('/goomui aaev <cmd>  (settings: /goomui, AAEV tab). Commands:');
    msg('  (bare)  - toggle charts');
    msg('  on|off  - enable / disable AAEV');
    msg('  config  - open the settings window');
    msg('  show    - force charts visible');
    msg('  hide    - force charts hidden');
    msg('  simple  - simple display mode');
    msg('  full    - full display mode');
    msg('  demo    - draw charts with a sample dataset');
    msg('  unlock  - allow dragging chart windows');
    msg('  lock    - lock windows and auto-save positions');
    msg('  bars N  - set bar count on both charts (runtime)');
    msg('  autohide - toggle AutoHide (runtime)');
    msg('  always  - toggle permanent player chart (runtime)');
    msg('  zone    - print zone accuracy totals to chat');
    msg('  zonereset - clear zone accuracy counters');
    msg('  delay N - set HideDelay seconds 0-20 (runtime)');
    msg('  reload  - re-read this character\'s aaev.lua');
end

-- args[1] ignored; args[2..] = the old /goomui aaev sub-commands.
function M.command(args)

    local cmd = '';
    if (args[2] ~= nil) then cmd = args[2]:lower(); end

    -- bare /goomui aaev toggles visibility
    if (cmd == '') then
        if (state.forced_hidden) then
            cmd = 'show';
        elseif (state.visible[TYPE_PLAYER] or state.visible[TYPE_PET] or settings.AlwaysShow) then
            cmd = 'hide';
        else
            cmd = 'show';
        end
    end

    if (cmd == 'show') then
        state.forced_hidden = false;
        state.visible[TYPE_PLAYER] = settings.AlwaysShow or state.display_target[TYPE_PLAYER] ~= nil;
        state.visible[TYPE_PET] = state.display_target[TYPE_PET] ~= nil;
        if (not state.visible[TYPE_PLAYER] and not state.visible[TYPE_PET]) then
            msg('No attack data recorded yet; nothing to show. Try /goomui aaev demo.');
        end
    elseif (cmd == 'hide') then
        state.forced_hidden = true;
        state.visible[TYPE_PLAYER] = false;
        state.visible[TYPE_PET] = false;
        state.hide_at[TYPE_PLAYER] = nil;
        state.hide_at[TYPE_PET] = nil;
    elseif (cmd == 'simple') then
        settings.DisplayMode = 'simple';
        msg('Display mode: simple.');
    elseif (cmd == 'full') then
        settings.DisplayMode = 'full';
        msg('Display mode: full.');
    elseif (cmd == 'demo') then
        demo();
    elseif (cmd == 'unlock') then
        state.unlocked = true;
        msg((settings.Position ~= 'free') and 'Player chart follows its position (AAEV tab > Layout). Pet chart unlocked; /goomui aaev lock when done.' or 'Charts unlocked; drag to position, then /goomui aaev lock.');
    elseif (cmd == 'lock') then
        state.unlocked = false;
        local p = state['pos_' .. TYPE_PLAYER];
        if (p ~= nil) then
            settings.ChartStartX, settings.ChartStartY = p[1], p[2];
        end
        local pp = state['pos_' .. TYPE_PET];
        if (pp ~= nil) then
            settings.PetChartStartX, settings.PetChartStartY = pp[1], pp[2];
        end
        if (save_positions()) then
            msg('Charts locked; positions saved.');
        else
            msg('Charts locked; position save FAILED.');
        end
    elseif (cmd == 'delay') then
        local n = tonumber(args[3] or '');
        if (n ~= nil and n >= 0 and n <= 20) then
            settings.HideDelay = n;
            msg(('HideDelay: %.1fs.'):format(n));
        else
            msg('Usage: /goomui aaev delay <0-20> (seconds; 0 = instant hide)');
        end
    elseif (cmd == 'autohide') then
        settings.AutoHide = not settings.AutoHide;
        if (settings.AutoHide) then
            msg('AutoHide: on.');
        else
            msg('AutoHide: off (charts stay until zone or /goomui aaev hide).');
            state.hide_at[TYPE_PLAYER] = nil;
            state.hide_at[TYPE_PET] = nil;
        end
    elseif (cmd == 'config' or cmd == 'settings' or cmd == 'menu') then
        if (M.on_config ~= nil) then M.on_config(); end
    elseif (cmd == 'always') then
        settings.AlwaysShow = not settings.AlwaysShow;
        if (settings.AlwaysShow) then
            settings.AutoHide = false;
            state.forced_hidden = false;
            state.hide_at[TYPE_PLAYER] = nil;
            msg('AlwaysShow: on (player chart is permanent; AutoHide forced off).');
        else
            msg('AlwaysShow: off.');
        end
    elseif (cmd == 'zonereset') then
        zone_reset();
        msg('Zone accuracy reset.');
    elseif (cmd == 'zone') then
        if (zone_stats.count > 0) then
            msg(('Zone: %d swings, %d miss, %.2f%% acc, %.2f%% crit.'):format(
                zone_stats.count, zone_stats.miss,
                (zone_stats.count - zone_stats.miss) / zone_stats.count * 100,
                zone_stats.crit / zone_stats.count * 100));
        else
            msg('Zone: no swings recorded this zone.');
        end
    elseif (cmd == 'bars') then
        local n = tonumber(args[3] or '');
        if (n ~= nil and n >= 1 and n <= 100) then
            n = math.floor(n);
            settings.ChartBars = n;
            settings.PetChartBars = n;
            msg(('Chart bars: %d (both charts).'):format(n));
        else
            msg('Usage: /goomui aaev bars <1-100>');
        end
    elseif (cmd == 'reload') then
        slib.reload('aaev');      -- raises the switch event -> M.set_cfg
        msg('Settings reloaded.');
    else
        show_help();
    end
    ver.cfg = ver.cfg + 1;
    saved_dirty_at = os.clock();   -- command changes persist per character
end

----------------------------------------------------------------------------------------------------
-- Load
----------------------------------------------------------------------------------------------------

function M.init()
    state.last_status = player_status();
    state.last_job = main_job();
    if (settings.AutoDemo) then
        demo();
    end
end

function M.unload()
    if (saved_dirty_at ~= nil) then save_saved(); end
    -- Persist drag positions user forgot to lock in.
    if (state['pos_' .. TYPE_PLAYER] ~= nil or state['pos_' .. TYPE_PET] ~= nil) then
        local p = state['pos_' .. TYPE_PLAYER];
        if (p ~= nil) then
            settings.ChartStartX, settings.ChartStartY = p[1], p[2];
        end
        local pp = state['pos_' .. TYPE_PET];
        if (pp ~= nil) then
            settings.PetChartStartX, settings.PetChartStartY = pp[1], pp[2];
        end
        save_positions();
    end
end

----------------------------------------------------------------------------------------------------
-- Module API
----------------------------------------------------------------------------------------------------

-- Settings lib hands a NEW table on every character switch; adopt it as-is
-- (the lib saves it by reference).
function M.set_cfg(t)
    settings = t;
    saved_dirty_at = nil;
    for k in pairs(int_buf) do int_buf[k] = nil; end
    load_settings();
    state.applied_pos[TYPE_PLAYER] = false;
    state.applied_pos[TYPE_PET] = false;
end

function M.enabled() return settings.enabled == true; end

-- Colour preset changed: theme.P values were updated in place; drop cached U32s / rows.
function M.retheme() ver.cfg = ver.cfg + 1; end

function M.set_enabled(on)
    settings.enabled = (on == true);
    if (settings.enabled) then
        state.last_status = player_status();
        state.last_job = main_job();
        state.visible[TYPE_PLAYER] = settings.AlwaysShow;
    else
        reset_all_logs();
        zone_reset();
        state.visible[TYPE_PLAYER] = false;
        state.visible[TYPE_PET] = false;
        state.hide_at[TYPE_PLAYER] = nil;
        state.hide_at[TYPE_PET] = nil;
        state.unlocked = false;
    end
    saved_dirty_at = nil;
    save_saved();
end

function M.reset_defaults()
    for k, v in pairs(default_settings) do
        if (k ~= 'enabled' and k ~= 'migrated') then
            settings[k] = (type(v) == 'table') and { unpack(v) } or v;
        end
    end
    saved_dirty_at = nil;
    for k in pairs(int_buf) do int_buf[k] = nil; end
    load_settings();
    save_saved();
    state.applied_pos[TYPE_PLAYER] = false;
    state.applied_pos[TYPE_PET] = false;
end

return M;
