--[[
* goomui: settings window. Every value here lives in the settings lib's
* per-character files: config/addons/goomui/<Name>_<id>/{bar,ring,aaev,settings}.lua
* (settings.lua = party list). Layout: page list on the left, the page on the right (scrolls).
--]]

require('common');
local imgui    = require('imgui');
local settings = require('settings');
local theme    = require('modules/theme');
local hidegame = require('modules/hidegame');
local W        = require('modules/widgets');

local G = { open = { false }, page = 'look', aaev_page = 1 };

local WARN = { 1.0, 0.45, 0.40, 1.0 };
local BIG  = 16384;

local function char_label()
    local name = settings.settings_path():match('([^\\]+)\\+$') or 'defaults';
    if (name == 'defaults') then return 'Not logged in: editing defaults'; end
    return name;
end

local function check(c, alias, label, key, hook)
    local v = { c[key] };
    if (imgui.Checkbox(label, v)) then
        c[key] = v[1];
        if (hook) then hook(key); end
        settings.save(alias);
    end
end

-- Commit on release where the binding has IsItemDeactivatedAfterEdit, else on every change.
local function released(changed)
    if (imgui.IsItemDeactivatedAfterEdit ~= nil) then return imgui.IsItemDeactivatedAfterEdit(); end
    return changed;
end

-- SliderFloat for ints too (format %.0f + floor): no reliance on SliderInt.
local function slider(c, alias, label, key, lo, hi, fmt, is_int, hook)
    local v = { c[key] };
    local changed = imgui.SliderFloat(label, v, lo, hi, fmt, ImGuiSliderFlags_AlwaysClamp);
    if (changed) then
        local n = v[1];
        if (is_int) then n = math.floor(n + 0.5); end
        if (n < lo) then n = lo; elseif (n > hi) then n = hi; end
        c[key] = n;
        if (hook) then hook(key); end
    end
    if (released(changed)) then settings.save(alias); end
end

-- InputInt typed into cfg live; clamp + save once on release.
local function edit_int(c, defaults, label, key, lo, hi)
    local v = { c[key] };
    local changed = imgui.InputInt(label, v);
    if (changed) then c[key] = v[1]; end
    if (not released(changed)) then return false; end

    local n = c[key];
    if (type(n) ~= 'number') then n = defaults[key]; end
    if (n < lo) then n = lo; elseif (n > hi) then n = hi; end
    c[key] = n;
    return true;
end

local function reset(c, defaults, keep)
    for k, v in pairs(defaults) do
        if (k ~= 'migrated' and not (keep and keep[k])) then
            c[k] = v;
        end
    end
end

-- Left column for row labels: the widest of these texts plus a gap.
local function label_col(...)
    local w = 0;
    for _, t in ipairs({ ... }) do
        local tw = imgui.CalcTextSize(t) or 0;
        if (tw > w) then w = tw; end
    end
    return w + imgui.GetFontSize();
end

-- Look keys live in bar.lua but belong to the Look page: Reset bar defaults leaves them alone.
local LOOK_KEYS = { theme = true, bar_style = true, bar_texture = true, bar_frame = true, panel_style = true,
    panel_alpha = true, ui_scale = true };

----------------------------------------------------------------------------------------------------
-- Target bar
----------------------------------------------------------------------------------------------------
local STACK_ITEMS = { { 'auto', 'Auto' }, { 'up', 'Up' }, { 'down', 'Down' } };

local function page_bar(c, bar)
    W.section('Panels');
    check(c, 'bar', 'Single bar', 'single_bar');
    W.tip('Only the target panel: no pet, sub-target, cast, JA or menu panel.');
    check(c, 'bar', 'Own pet HP bar', 'show_pet');
    check(c, 'bar', 'JA flash bar', 'show_jabar');
    check(c, 'bar', 'Menu recast info', 'show_menuinfo');
    local pick = W.choice_row('Extra panels stack', STACK_ITEMS, c.stack or 'auto', 'thud_stack',
        label_col('Extra panels stack'));
    W.tip('Auto: above the target panel, or under it when they would not all fit above the bar.');
    if (pick ~= nil) then c.stack = pick; settings.save('bar'); end

    W.section('Target');
    check(c, 'bar', 'Distance', 'show_distance');
    check(c, 'bar', 'Height offset', 'show_height');
    W.tip('+ = target above you.');
    check(c, 'bar', 'Range colours account for hitbox size', 'dynamic_range');
    W.tip('Off: fixed 22 / 30 yalm colour cuts.');
    slider(c, 'bar', 'Hold finished cast / JA (s)##thud_linger', 'cast_linger', 0.5, 6.0, '%.1f', false);

    W.section('Mob debuffs');
    check(c, 'bar', 'Show debuffs on the targeted mob', 'show_debuffs');
    check(c, 'bar', 'Below the HP bar', 'debuffs_below');
    W.tip('Off: above the HP bar. Other panels still stack up.');
    slider(c, 'bar', 'Icon size##thud_dbsz', 'debuff_icon', 12, 32, '%.0f', true);

    W.section('Treasure pool');
    check(c, 'bar', 'Treasure pool window', 'show_pool');
    W.tip('Lots and passes per member. Shown while the pool has items.');
    check(c, 'bar', 'One-line summary by the party list', 'pool_dock');
    W.tip('Click the summary for the full window. Off: window only.');

    W.section('Position and size', 'Pixels.');
    local lk = { c.locked };
    if (imgui.Checkbox('Lock position', lk)) then
        c.locked = lk[1];
        if (c.locked) then settings.save('bar'); else bar.force_handle(); end
    end
    W.tip('Uncheck to drag the bar.');
    if (edit_int(c, bar.defaults, 'X##thud_pos', 'pos_x', -8192, 16384)) then bar.force_handle(); settings.save('bar'); end
    if (edit_int(c, bar.defaults, 'Y##thud_pos', 'pos_y', -8192, 16384)) then bar.force_handle(); settings.save('bar'); end
    local w_done = edit_int(c, bar.defaults, 'Width##thud_bw',  'bar_width',  100, 800);
    local h_done = edit_int(c, bar.defaults, 'Height##thud_bh', 'bar_height',   6,  48);
    bar.update_rcache();                     -- live preview while typing
    if (w_done or h_done) then settings.save('bar'); end

    W.section('Reset');
    if (imgui.Button('Reset target bar defaults##thud_bar_reset')) then
        reset(c, bar.defaults, LOOK_KEYS);
        bar.set_cfg(c);
        settings.save('bar');
    end
    W.tip('Look page settings (preset, bar look, panels, UI scale) are kept.');
end

----------------------------------------------------------------------------------------------------
-- Cursor colour picker
----------------------------------------------------------------------------------------------------
-- Target cursor colour: White or a palette colour, each shown with its swatch in the current preset.
local CURSOR_NAMES = { white = 'White', kind = 'Target kind', hp_full = 'HP', hp_50 = 'HP half', hp_0 = 'HP low',
    mp = 'MP', tp = 'TP',
    tp_rdy = 'TP ready', tp_max = 'TP 3000', spell = 'Spell', item = 'Item', hit = 'Hit', crit = 'Crit', ws = 'WS',
    heal = 'Heal', counter = 'Counter', r3 = 'Roll' };
local SWATCH = { 12, 12 };
local KIND_SWATCH = { 255, 106, 60 }; -- Target kind: mobs (the ring colours; players blue, NPCs green)
local function cursor_f4(key)
    local p = (key == 'kind') and KIND_SWATCH or ((key ~= 'white') and theme.P[key] or nil);
    if (p == nil) then return theme.f4(245, 245, 245); end
    return theme.f4(p[1], p[2], p[3]);
end
-- A plain colour name from hue / lightness. The palette follows the colour preset, so the name is worked out from
-- the colour the preset gives, not stored: 'Sky blue (MP)' under Vivid.
local HUE_NAMES = { { 12, 'Red' }, { 38, 'Orange' }, { 64, 'Yellow' }, { 90, 'Lime' }, { 150, 'Green' },
    { 172, 'Teal' }, { 195, 'Cyan' }, { 222, 'Sky blue' }, { 246, 'Blue' }, { 285, 'Purple' }, { 310, 'Magenta' },
    { 340, 'Pink' }, { 361, 'Red' } };
local function colour_name(r, g, b)
    r, g, b = r / 255, g / 255, b / 255;
    local mx, mn = math.max(r, g, b), math.min(r, g, b);
    local l, d = (mx + mn) / 2, mx - mn;
    if (d < 0.08) then return (l > 0.8) and 'White' or ((l < 0.2) and 'Black' or 'Grey'); end
    local h;
    if (mx == r) then h = 60 * (((g - b) / d) % 6);
    elseif (mx == g) then h = 60 * ((b - r) / d + 2);
    else h = 60 * ((r - g) / d + 4); end
    local name = 'Red';
    for _, e in ipairs(HUE_NAMES) do
        if (h < e[1]) then name = e[2]; break; end
    end
    if (l >= 0.75) then name = 'Light ' .. name:lower(); elseif (l < 0.3) then name = 'Dark ' .. name:lower(); end
    return name;
end
local function cursor_label(k)
    local role = CURSOR_NAMES[k] or tostring(k);
    local p = (k ~= 'white' and k ~= 'kind') and theme.P[k] or nil;
    if (p == nil) then return role; end
    return ('%s (%s)'):fmt(colour_name(p[1], p[2], p[3]), role);
end
local function cursor_colour(c, ring, label, key)
    local cur = c[key];
    imgui.ColorButton('##cur_' .. key, cursor_f4(cur), ImGuiColorEditFlags_NoTooltip, SWATCH);
    imgui.SameLine();
    if (imgui.BeginCombo(label, cursor_label(cur))) then
        for _, k in ipairs(ring.CURSOR_COLORS) do
            imgui.ColorButton('##sw_' .. key .. k, cursor_f4(k), ImGuiColorEditFlags_NoTooltip, SWATCH);
            imgui.SameLine();
            if (imgui.Selectable(cursor_label(k) .. '##' .. key .. k, k == cur)) then
                c[key] = k;
                settings.save('ring');
            end
        end
        imgui.EndCombo();
    end
end

----------------------------------------------------------------------------------------------------
-- Rings / cursor / GEO
----------------------------------------------------------------------------------------------------
local function page_ring(c, ring)
    local hook = ring.on_change;

    W.section('Target ring');
    check(c, 'ring', 'Target rings', 'enabled', hook);
    check(c, 'ring', 'Facing arrow', 'arrow', hook);
    check(c, 'ring', 'Flip arrow heading', 'flip', hook);
    W.tip('Use if the arrow points the wrong way.');
    check(c, 'ring', 'Runes', 'runes', hook);
    check(c, 'ring', 'Rear fade', 'fade', hook);
    slider(c, 'ring', 'Scale##thud_scale', 'scale', 0.1, 8.0, '%.2f', false, hook);
    slider(c, 'ring', 'Slices##thud_slices', 'slices', 8, 128, '%.0f', true, hook);

    W.section('Range fill', 'In range the ring is lightly filled; out of range it is an empty outline.');
    check(c, 'ring', 'Fill when in range', 'range', hook);
    check(c, 'ring', 'Add both hitboxes', 'range_hitbox', hook);
    W.tip('So a big NM reads correctly.');
    check(c, 'ring', 'Fill GEO rings too', 'range_geo', hook);
    slider(c, 'ring', 'Base range##thud_rbase', 'range_base', 1.0, 50.0, '%.1f', false, hook);
    slider(c, 'ring', 'Fill strength##thud_rfill', 'range_fill', 0.02, 0.60, '%.2f', false, hook);

    W.section('Reset');
    if (imgui.Button('Reset ring defaults##thud_ring_reset')) then
        reset(c, ring.defaults, { geo = true, geo_slices = true, geo_radius = true, geo_cap = true, geo_scan = true,
            geo_cure = true, geo_buffs = true, geo_bubble = true, geo_indi_jp = true, cursor = true, cursor_color = true,
            cursor_sub = true, cursor_size = true, cursor_style = true, cursor_float = true, cursor_spin = true,
            cursor_lift = true });
        ring.set_cfg(c);
        settings.save('ring');
    end
    W.tip('Cursor and GEO settings are kept.');
end

local CURSOR_STYLE_NAMES = { gem = 'Gem', flat = 'Flat', hollow = 'Hollow', crystal = 'Crystal' };
local cursor_items = nil;

local function page_cursor(c, ring)
    if (cursor_items == nil) then
        cursor_items = { };
        for _, k in ipairs(ring.CURSOR_STYLES) do cursor_items[#cursor_items + 1] = { k, CURSOR_STYLE_NAMES[k] or k }; end
    end

    W.section('Target cursor');
    check(c, 'ring', 'Cursor over your target', 'cursor');
    local pick = W.choice_row('Style', cursor_items, c.cursor_style, 'gui_cstyle', label_col('Style'));
    if (pick ~= nil) then c.cursor_style = pick; settings.save('ring'); end
    cursor_colour(c, ring, 'Colour##thud_ccol', 'cursor_color');
    W.tip('Your held target. Target kind: the ring colours.');
    cursor_colour(c, ring, 'Sub-target colour##thud_csub', 'cursor_sub');
    W.tip('The target you are picking (<st>), and item / <stnpc> / <stpc> picks.');
    slider(c, 'ring', 'Size##thud_csize', 'cursor_size', 0.5, 3.0, '%.2f', false);
    slider(c, 'ring', 'Lift over players##thud_clift', 'cursor_lift', 0, 40, '%.0f px', true);
    W.tip('Clears the master level stars on their nameplate.');
    check(c, 'ring', 'Float', 'cursor_float');
    W.tip('Drifts up and down.');
    check(c, 'ring', 'Spin (crystal)', 'cursor_spin');

    W.section('All characters');
    if (imgui.Button('Apply cursor to all characters##gui_cursor_all')) then ring.cursor_apply_all(); end
    W.tip('Sends these cursor settings to every character with /mss (MultiSend).');
end

local function page_geo(c, ring)
    local hook = ring.on_change;

    W.section('GEO bubbles');
    check(c, 'ring', 'GEO bubble rings', 'geo', hook);
    check(c, 'ring', 'Draw bubble boundary', 'geo_bubble', hook);
    check(c, 'ring', 'Ring party in buff bubbles', 'geo_buffs', hook);
    check(c, 'ring', 'Cure on ally tags that ally\'s mobs', 'geo_cure', hook);
    slider(c, 'ring', 'Bubble radius##thud_grad', 'geo_radius', 1.0, 40.0, '%.1f', false, hook);
    W.tip('Base Geo- / Indi- bubble radius in yalms.');
    slider(c, 'ring', 'Max rings##thud_gcap', 'geo_cap', 1, 50, '%.0f', true, hook);
    slider(c, 'ring', 'Scan radius##thud_gscan', 'geo_scan', 5.0, 60.0, '%.0f', false, hook);
    W.tip('Yalms around the luopan to consider.');
    slider(c, 'ring', 'GEO slices##thud_gslices', 'geo_slices', 8, 96, '%.0f', true, hook);

    W.section('Status');
    imgui.TextDisabled((ring.geo_status():gsub(' | ', '\n')));

    W.section('Reset');
    if (imgui.Button('Clear tags##thud_gclear')) then ring.clear_tags(); end
    imgui.SameLine();
    if (imgui.Button('Reset GEO defaults##thud_geo_reset')) then
        local keep = { };
        for k in pairs(ring.defaults) do
            if (k:sub(1, 4) ~= 'geo_' and k ~= 'geo') then keep[k] = true; end
        end
        keep.geo_indi_jp = true;
        reset(c, ring.defaults, keep);
        ring.set_cfg(c);
        settings.save('ring');
    end
end

----------------------------------------------------------------------------------------------------
-- Look
----------------------------------------------------------------------------------------------------
local SWATCH_KEYS = { 'hp_full', 'hp_50', 'hp_0', 'mp', 'tp', 'tp_rdy', 'tp_max', 'r1', 'r3', 'r5' };

-- A strip of a preset's bar colours, as tall as a button.
local function swatch_strip(p, sw, fh)
    local cx, cy = imgui.GetCursorScreenPos();
    local dl = imgui.GetWindowDrawList();
    if (dl ~= nil) then
        local y1, y2 = cy + fh * 0.28, cy + fh * 0.72;
        for j, k in ipairs(SWATCH_KEYS) do
            local c, x = p[k], cx + (j - 1) * (sw + 2);
            dl:AddRectFilled({ x, y1 }, { x + sw, y2 }, theme.u32(c[1], c[2], c[3]), 2.0);
        end
    end
    imgui.Dummy({ #SWATCH_KEYS * (sw + 2) - 2, fh });
end

local look_items = nil;
local preset_w = { fs = nil, w = 0 };

local function items_of(order)
    local t = { };
    for _, k in ipairs(order) do t[#t + 1] = { k, theme.STYLE_LABEL[k] or k }; end
    return t;
end

local function page_look()
    if (look_items == nil) then
        look_items = { shape = items_of(theme.SHAPE_ORDER), texture = items_of(theme.TEXTURE_ORDER),
            panel = items_of(theme.PANEL_ORDER) };
    end
    local fs = imgui.GetFontSize();
    local fh = imgui.GetFrameHeight();

    W.section('Colour preset', 'Bar colours of the target bar, party list and AAEV (and this window\'s accent). '
        .. 'Panel tints, stripes and text stay the same. AAEV keeps its own colours when its Layout > goomui colours '
        .. 'is off. In game: /goomui look next | prev | <preset>');
    if (preset_w.fs ~= fs) then             -- widest preset name, re-measured when the font size changes
        local w = 0;
        for _, name in ipairs(theme.PRESET_ORDER) do
            local tw = W.button_w(theme.PRESET_LABEL[name]);
            if (tw > w) then w = tw; end
        end
        preset_w.fs, preset_w.w = fs, math.floor(w + 0.5);
    end
    local bw, sw, gap = preset_w.w, math.max(6, math.floor(fs * 0.8)), math.floor(fs * 1.2);
    local colw = bw + 4 + #SWATCH_KEYS * (sw + 2) - 2;
    local avail = imgui.GetContentRegionAvail();
    local ncol = math.max(1, math.floor((avail + gap) / (colw + gap)));
    for i, name in ipairs(theme.PRESET_ORDER) do
        if ((i - 1) % ncol ~= 0) then imgui.SameLine(0, gap); end
        if (W.choice(theme.PRESET_LABEL[name], theme.current == name, 'gui_theme_' .. name, { bw, 0 })
            and G.on_theme ~= nil) then
            G.on_theme(name);
        end
        imgui.SameLine(0, 4);
        swatch_strip(theme.PRESETS[name], sw, fh);
    end

    local x = label_col('Texture', 'Opacity', 'Scale');

    W.section('Bar look', 'Shape, texture and frame combine freely.');
    local pick = W.choice_row('Shape', look_items.shape, theme.shape, 'gui_shape', x);
    if (pick ~= nil and G.on_look ~= nil) then G.on_look(pick, theme.texture, theme.frame); end
    pick = W.choice_row('Texture', look_items.texture, theme.texture, 'gui_tex', x);
    if (pick ~= nil and G.on_look ~= nil) then G.on_look(theme.shape, pick, theme.frame); end
    imgui.SetCursorPosX(x);
    local fr = { theme.frame };
    if (imgui.Checkbox('Frame##gui_frame', fr) and G.on_look ~= nil) then
        G.on_look(theme.shape, theme.texture, fr[1]);
    end
    W.tip('Hollow outline in the fill colour, fill inset.');

    W.section('Panels', 'Target / cast / JA / menu panels and the AAEV plate.');
    pick = W.choice_row('Style', look_items.panel, theme.panel_style, 'gui_panel', x);
    if (pick ~= nil and G.on_panel ~= nil) then G.on_panel(pick, theme.panel_alpha); end
    W.row_label('Opacity', x);
    local op = { theme.panel_alpha };
    if (imgui.SliderFloat('##gui_panel_alpha', op, 0.25, 2.0, '%.2f') and G.on_panel ~= nil) then
        G.on_panel(theme.panel_style, op[1]);
    end

    W.section('UI scale', 'Text and sizes of every goomui window. Also: /goomui scale <0.5-3>. '
        .. 'Party lists keep their own scale on top of this.');
    -- Applied on release: this window scales too, so a live drag would move the slider under the mouse.
    W.row_label('Scale', x);
    if (G.scale_edit == nil) then G.scale_edit = { theme.ui_scale }; end
    local sc_changed = imgui.SliderFloat('##gui_ui_scale', G.scale_edit, 0.5, 3.0, '%.2f', ImGuiSliderFlags_AlwaysClamp);
    local sc_done = released(sc_changed);
    local sc_active = (imgui.IsItemActive ~= nil) and imgui.IsItemActive() or false;
    if (not sc_active) and (not sc_done) then G.scale_edit[1] = theme.ui_scale; end
    if (sc_done and G.on_scale ~= nil) then G.on_scale(G.scale_edit[1]); end
    imgui.SameLine();
    if (imgui.Button('1x##gui_ui_scale_reset') and G.on_scale ~= nil) then G.on_scale(1.0); end

    W.section('All characters');
    if (imgui.Button('Apply look to all characters##gui_look_all')) then
        AshitaCore:GetChatManager():QueueCommand(-1, ('/mss /goomui look set %s %s %s %s %s %.2f'):fmt(
            theme.current or theme.DEFAULT, theme.shape, theme.texture, theme.frame and 'on' or 'off', theme.panel_style,
            theme.panel_alpha));
    end
    W.tip('Sends preset, bar look and panel style to every character with /mss (MultiSend). '
        .. 'Each saves it in its own bar.lua.');
end

----------------------------------------------------------------------------------------------------
-- Party
----------------------------------------------------------------------------------------------------
local function page_party(party, c)
    party.draw_options();

    W.section('Game UI', 'Hide the game\'s own frames (this character). Same as Ashita\'s hideparty: '
        .. 'unload hideparty if you use these, it keeps showing them.');
    if (not hidegame.available()) then
        imgui.TextColored(WARN, 'Not found in this client: these do nothing.');
    end
    check(c, 'bar', "Hide the game's party list##gui_hide_party", 'hide_game_party');
    check(c, 'bar', "Hide the game's alliance lists##gui_hide_ally", 'hide_game_alliance');
    check(c, 'bar', "Hide the game's target frame##gui_hide_target", 'hide_game_target');
    W.tip("The game's target arrow goes with it (goomui's cursor takes its place).");
end

----------------------------------------------------------------------------------------------------
-- AAEV
----------------------------------------------------------------------------------------------------
local function page_aaev(c, aaev)
    local on = { c.enabled == true };
    if (imgui.Checkbox('Enable AAEV (auto-attack chart)', on)) then
        aaev.set_enabled(on[1]);
    end
    if (not c.enabled) then
        W.tip('Off: no 0x028 parsing, no chart.');
        return;
    end
    local pages = aaev.CONFIG_PAGES;
    local i = (G.aaev_page >= 1 and G.aaev_page <= #pages) and G.aaev_page or 1;
    W.section(pages[i]);
    aaev.draw_config_page(i);
    W.section('Tools');
    aaev.draw_config_footer();
end

----------------------------------------------------------------------------------------------------
-- Window
----------------------------------------------------------------------------------------------------
local PAGES = {
    { 'look',   'Look' },
    { 'party',  'Party list' },
    { 'bar',    'Target bar' },
    { 'ring',   'Rings' },
    { 'cursor', 'Cursor' },
    { 'geo',    'GEO' },
    { 'aaev',   'AAEV' },
};
local nav_w = { fs = nil, w = 0 };

local function nav(aaev, aaev_on)
    local fs = imgui.GetFontSize();
    local pages = aaev.CONFIG_PAGES;
    if (nav_w.fs ~= fs) then
        local w = 0;
        for _, p in ipairs(PAGES) do w = math.max(w, imgui.CalcTextSize(p[2]) or 0); end
        for _, n in ipairs(pages) do w = math.max(w, (imgui.CalcTextSize(n) or 0) + fs); end
        nav_w.fs, nav_w.w = fs, math.floor(w + fs * 1.6);
    end

    imgui.PushStyleColor(ImGuiCol_ChildBg, W.nav_bg());
    imgui.BeginChild('##gui_nav', { nav_w.w, 0 });
    imgui.PopStyleColor(1);
    imgui.Dummy({ 0, fs * 0.2 });
    imgui.Indent(fs * 0.5);
    for _, p in ipairs(PAGES) do
        if (imgui.Selectable(p[2] .. '##gui_nav_' .. p[1], G.page == p[1])) then G.page = p[1]; end
        if (p[1] == 'aaev' and aaev_on) then
            imgui.Indent(fs);
            for i, n in ipairs(pages) do
                if (imgui.Selectable(n .. '##gui_nav_aaev' .. i, G.page == 'aaev' and G.aaev_page == i)) then
                    G.page, G.aaev_page = 'aaev', i;
                end
            end
            imgui.Unindent(fs);
        end
    end
    imgui.Unindent(fs * 0.5);
    imgui.EndChild();
end

function G.toggle() G.open[1] = not G.open[1]; end
function G.open_window() G.open[1] = true; end
function G.show_page(name) G.page = name; G.open[1] = true; end

function G.render(cfg, bar, ring, aaev, party)
    local bar_cfg, ring_cfg, aaev_cfg = cfg.bar, cfg.ring, cfg.aaev;
    if (not G.open[1] or bar_cfg == nil or ring_cfg == nil or aaev_cfg == nil) then return; end
    if (G.page == 'party' and party == nil) then G.page = 'look'; end

    local fs = imgui.GetFontSize();
    -- UI scale changed: grow / shrink the window with its text.
    if (G.win_scale ~= nil and G.win_scale ~= theme.ui_scale and G.win_w ~= nil) then
        local r = theme.ui_scale / G.win_scale;
        imgui.SetNextWindowSize({ G.win_w * r, G.win_h * r }, ImGuiCond_Always);
    else
        imgui.SetNextWindowSize({ fs * 46, fs * 38 }, ImGuiCond_FirstUseEver);
    end
    G.win_scale = theme.ui_scale;
    imgui.SetNextWindowSizeConstraints({ fs * 30, fs * 18 }, { BIG, BIG });

    local nc, nv = W.style_push();
    if (imgui.Begin('goomui##gui_main', G.open, ImGuiWindowFlags_NoCollapse)) then
        G.win_w, G.win_h = imgui.GetWindowSize();
        imgui.TextDisabled('Settings for');
        imgui.SameLine();
        imgui.Text(char_label());
        W.tip('Saved per character: config/addons/goomui/<Name>_<id>/');

        nav(aaev, aaev_cfg.enabled == true);
        imgui.SameLine(0, fs);
        imgui.BeginChild('##gui_body', { 0, 0 });
        imgui.PushItemWidth(fs * 14);
        local p = G.page;
        if (p == 'look') then page_look();
        elseif (p == 'party') then page_party(party, bar_cfg);
        elseif (p == 'bar') then page_bar(bar_cfg, bar);
        elseif (p == 'ring') then page_ring(ring_cfg, ring);
        elseif (p == 'cursor') then page_cursor(ring_cfg, ring);
        elseif (p == 'geo') then page_geo(ring_cfg, ring);
        elseif (p == 'aaev') then page_aaev(aaev_cfg, aaev);
        end
        imgui.PopItemWidth();
        imgui.EndChild();
    end
    imgui.End();
    W.style_pop(nc, nv);

    -- Closing with X: flush every block once; party setup (drag boxes) ends with the window.
    if (not G.open[1]) then
        settings.save('bar');
        settings.save('ring');
        settings.save('aaev');
        if (party ~= nil and party.in_setup()) then party.toggle_setup(); end
    end
end

return G;
