--[[
* goomui: settings window. Every value here lives in the settings lib's
* per-character files: config/addons/goomui/<Name>_<id>/{bar,ring,aaev,settings}.lua
* (settings.lua = party list; its full options live in its setup window).
--]]

require('common');
local imgui    = require('imgui');
local settings = require('settings');
local theme    = require('modules/theme');

local G = { open = { false } };

local HEADER = { 1.0, 0.75, 0.55, 1.0 };
local DIM    = { 0.70, 0.70, 0.75, 1.0 };

-- Commit-on-release. Absent in some older bindings: then save on every change.
local ig_dae = imgui.IsItemDeactivatedAfterEdit;
local function released(changed)
    if (ig_dae) then return ig_dae(); end
    return changed;
end

local function char_label()
    local name = settings.settings_path():match('([^\\]+)\\+$') or 'defaults';
    if (name == 'defaults') then return 'Not logged in: editing defaults'; end
    return 'Character: ' .. name;
end

local function check(c, alias, label, key, hook)
    local v = { c[key] };
    if (imgui.Checkbox(label, v)) then
        c[key] = v[1];
        if (hook) then hook(key); end
        settings.save(alias);
    end
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

local function tab_bar(c, bar)
    local function hook() end

    local lk = { c.locked };
    if (imgui.Checkbox('Lock position (uncheck to drag)', lk)) then
        c.locked = lk[1];
        if (c.locked) then settings.save('bar'); else bar.force_handle(); end
    end
    check(c, 'bar', 'Show distance', 'show_distance', hook);
    check(c, 'bar', 'Show height offset (+ = target above you)', 'show_height', hook);
    check(c, 'bar', 'Range colors account for hitbox size', 'dynamic_range', hook);
    check(c, 'bar', 'Show menu recast info', 'show_menuinfo', hook);
    check(c, 'bar', 'Show own pet HP bar', 'show_pet', hook);
    check(c, 'bar', 'Show JA flash bar', 'show_jabar', hook);
    check(c, 'bar', 'Show debuffs on the targeted mob', 'show_debuffs', hook);
    check(c, 'bar', 'Debuffs below the HP bar (default: above)', 'debuffs_below', hook);
    check(c, 'bar', 'Show treasure pool window (lots and passes per member)', 'show_pool', hook);
    check(c, 'bar', 'Treasure pool: one-line summary by the party list (click it for the window)', 'pool_dock', hook);
    slider(c, 'bar', 'Debuff icon size##thud_dbsz', 'debuff_icon', 12, 32, '%.0f', true, hook);
    slider(c, 'bar', 'Hold finished cast / JA (s)##thud_linger', 'cast_linger', 0.5, 6.0, '%.1f', false, hook);

    imgui.Separator();
    imgui.TextColored(HEADER, 'Position (pixels)');
    if (edit_int(c, bar.defaults, 'X##thud_pos', 'pos_x', -8192, 16384)) then bar.force_handle(); settings.save('bar'); end
    if (edit_int(c, bar.defaults, 'Y##thud_pos', 'pos_y', -8192, 16384)) then bar.force_handle(); settings.save('bar'); end

    imgui.TextColored(HEADER, 'Bar size');
    local w_done = edit_int(c, bar.defaults, 'Width##thud_bw',  'bar_width',  100, 800);
    local h_done = edit_int(c, bar.defaults, 'Height##thud_bh', 'bar_height',   6,  48);
    bar.update_rcache();                     -- live preview while typing
    if (w_done or h_done) then settings.save('bar'); end

    imgui.Separator();
    if (imgui.Button('Reset bar defaults##thud_bar_reset')) then
        reset(c, bar.defaults);
        bar.set_cfg(c);
        settings.save('bar');
    end
end

-- Target cursor colour: White or a palette colour, each shown with its swatch in the current preset.
local CURSOR_NAMES = { white = 'White', hp_full = 'HP', hp_50 = 'HP half', hp_0 = 'HP low', mp = 'MP', tp = 'TP',
    tp_rdy = 'TP ready', tp_max = 'TP 3000', spell = 'Spell', item = 'Item', hit = 'Hit', crit = 'Crit', ws = 'WS',
    heal = 'Heal', counter = 'Counter', r3 = 'Roll' };
local SWATCH = { 12, 12 };
local function cursor_f4(key)
    local p = (key ~= 'white') and theme.P[key] or nil;
    if (p == nil) then return theme.f4(245, 245, 245); end
    return theme.f4(p[1], p[2], p[3]);
end
local function cursor_colour(c, ring, label, key)
    local cur = c[key];
    imgui.ColorButton('##cur_' .. key, cursor_f4(cur), ImGuiColorEditFlags_NoTooltip, SWATCH);
    imgui.SameLine();
    if (imgui.BeginCombo(label, CURSOR_NAMES[cur] or tostring(cur))) then
        for _, k in ipairs(ring.CURSOR_COLORS) do
            imgui.ColorButton('##sw_' .. key .. k, cursor_f4(k), ImGuiColorEditFlags_NoTooltip, SWATCH);
            imgui.SameLine();
            if (imgui.Selectable((CURSOR_NAMES[k] or k) .. '##' .. key .. k, k == cur)) then
                c[key] = k;
                settings.save('ring');
            end
        end
        imgui.EndCombo();
    end
end

local function tab_ring(c, ring)
    local hook = ring.on_change;

    check(c, 'ring', 'Target rings', 'enabled', hook);
    check(c, 'ring', 'Depth test (hide behind terrain)', 'depth', hook);
    check(c, 'ring', 'Facing arrow', 'arrow', hook);
    check(c, 'ring', 'Runes', 'runes', hook);
    check(c, 'ring', 'Rear fade', 'fade', hook);
    check(c, 'ring', 'Flip arrow heading', 'flip', hook);
    slider(c, 'ring', 'Scale##thud_scale', 'scale', 0.1, 8.0, '%.2f', false, hook);
    slider(c, 'ring', 'Slices##thud_slices', 'slices', 8, 128, '%.0f', true, hook);

    imgui.Separator();
    imgui.TextColored(HEADER, 'Range fill');
    check(c, 'ring', 'Fill when in range', 'range', hook);
    check(c, 'ring', 'Add both hitboxes', 'range_hitbox', hook);
    check(c, 'ring', 'Fill GEO rings too', 'range_geo', hook);
    slider(c, 'ring', 'Base range##thud_rbase', 'range_base', 1.0, 50.0, '%.1f', false, hook);
    slider(c, 'ring', 'Fill strength##thud_rfill', 'range_fill', 0.02, 0.60, '%.2f', false, hook);

    imgui.Separator();
    imgui.TextColored(HEADER, 'Target cursor');
    check(c, 'ring', 'Cursor over your target', 'cursor', hook);
    cursor_colour(c, ring, 'Colour##thud_ccol', 'cursor_color');
    cursor_colour(c, ring, 'Sub-target colour##thud_csub', 'cursor_sub');
    slider(c, 'ring', 'Size##thud_csize', 'cursor_size', 0.5, 3.0, '%.2f', false, hook);

    imgui.Separator();
    if (imgui.Button('Reset ring defaults##thud_ring_reset')) then
        reset(c, ring.defaults, { geo = true, geo_slices = true, geo_radius = true, geo_cap = true, geo_scan = true,
            geo_cure = true, geo_buffs = true, geo_bubble = true, geo_indi_jp = true });
        ring.set_cfg(c);
        settings.save('ring');
    end
end

local function tab_aaev(c, aaev)
    local on = { c.enabled == true };
    if (imgui.Checkbox('Enable AAEV (auto-attack chart)', on)) then
        aaev.set_enabled(on[1]);
    end
    if (not c.enabled) then
        imgui.TextColored(DIM, 'Off: no 0x028 parsing, no chart.');
        return;
    end
    imgui.Separator();
    aaev.draw_config_body();
end

local function tab_geo(c, ring)
    local hook = ring.on_change;

    check(c, 'ring', 'GEO bubble rings', 'geo', hook);
    check(c, 'ring', 'Ring party in buff bubbles', 'geo_buffs', hook);
    check(c, 'ring', 'Cure on ally tags that ally\'s mobs', 'geo_cure', hook);
    check(c, 'ring', 'Draw bubble boundary', 'geo_bubble', hook);
    slider(c, 'ring', 'Bubble radius##thud_grad', 'geo_radius', 1.0, 40.0, '%.1f', false, hook);
    slider(c, 'ring', 'Max rings##thud_gcap', 'geo_cap', 1, 50, '%.0f', true, hook);
    slider(c, 'ring', 'Scan radius##thud_gscan', 'geo_scan', 5.0, 60.0, '%.0f', false, hook);
    slider(c, 'ring', 'GEO slices##thud_gslices', 'geo_slices', 8, 96, '%.0f', true, hook);

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

    imgui.Separator();
    imgui.TextColored(DIM, (ring.geo_status():gsub(' | ', '\n')));
end

-- Colour presets: one button each, with a strip of its bar colours.
local function swatch(c, w)
    local cx, cy = imgui.GetCursorScreenPos();
    if (type(cx) == 'table') then cx, cy = cx.x, cx.y; end
    local dl = imgui.GetWindowDrawList();
    if (dl ~= nil) then
        dl:AddRectFilled({ cx, cy + 3 }, { cx + w, cy + 13 }, theme.u32(c[1], c[2], c[3]), 2.0);
    end
    imgui.Dummy({ w, 16 });
end

local SWATCH_KEYS = { 'hp_full', 'hp_50', 'hp_0', 'mp', 'tp', 'tp_rdy', 'tp_max', 'r1', 'r3', 'r5' };

local function look_button(label, on, id)
    return imgui.Button((on and '> ' or '  ') .. label .. '##' .. id);
end

local function tab_look(c)
    imgui.TextColored(HEADER, 'Colour preset (bars, party list, AAEV)');
    -- two presets per row: [name][swatches]   [name][swatches]
    for i, name in ipairs(theme.PRESET_ORDER) do
        local p = theme.PRESETS[name];
        if (i % 2 == 0) then imgui.SameLine(0, 18); end
        if (imgui.Button(((theme.current == name) and '> ' or '  ') .. theme.PRESET_LABEL[name] .. '##gui_theme_' .. name, { 96, 0 })
            and G.on_theme ~= nil) then
            G.on_theme(name);
        end
        for _, k in ipairs(SWATCH_KEYS) do
            imgui.SameLine(0, 2);
            swatch(p[k], 14);
        end
    end

    imgui.Separator();
    imgui.TextColored(HEADER, 'Bar look (combine freely)');
    imgui.Text('Shape  ');
    for _, name in ipairs(theme.SHAPE_ORDER) do
        imgui.SameLine();
        if (look_button(theme.STYLE_LABEL[name], theme.shape == name, 'gui_shape_' .. name) and G.on_look ~= nil) then
            G.on_look(name, theme.texture, theme.frame);
        end
    end
    imgui.Text('Texture');
    for i, name in ipairs(theme.TEXTURE_ORDER) do
        if (i == 4) then imgui.Text('       '); end   -- second row, aligned under the first
        imgui.SameLine();
        if (look_button(theme.STYLE_LABEL[name], theme.texture == name, 'gui_tex_' .. name) and G.on_look ~= nil) then
            G.on_look(theme.shape, name, theme.frame);
        end
    end
    local fr = { theme.frame };
    if (imgui.Checkbox('Frame (hollow outline, fill inset)', fr) and G.on_look ~= nil) then
        G.on_look(theme.shape, theme.texture, fr[1]);
    end

    imgui.Separator();
    imgui.TextColored(HEADER, 'Panels (target / cast / menu panels, AAEV plate)');
    imgui.Text('Style  ');
    for _, name in ipairs(theme.PANEL_ORDER) do
        imgui.SameLine();
        if (look_button(theme.STYLE_LABEL[name], theme.panel_style == name, 'gui_panel_' .. name) and G.on_panel ~= nil) then
            G.on_panel(name, theme.panel_alpha);
        end
    end
    local op = { theme.panel_alpha };
    if (imgui.SliderFloat('Opacity##gui_panel_alpha', op, 0.25, 2.0, '%.2f') and G.on_panel ~= nil) then
        G.on_panel(theme.panel_style, op[1]);
    end

    imgui.Separator();
    imgui.TextColored(DIM, 'Saved per character (bar.lua). Panel tints and stripes do not change.');
    imgui.TextColored(DIM, 'Try them in game: /goomui look next | prev | <preset>');
    imgui.TextColored(DIM, 'AAEV uses its own colours if Layout > goomui colours is off.');
end

local function tab_party(party)
    local on = party.in_setup();
    if (imgui.Button(on and 'Save + close party setup##gui_psetup' or 'Party setup: drag lists + options##gui_psetup')) then
        party.toggle_setup();
    end
    local lf = { party.lowfi() };
    if (imgui.Checkbox('Low-fi (this char): text only, 250 ms poll', lf)) then
        party.set_lowfi(lf[1]);
    end
    imgui.Separator();
    imgui.TextColored(DIM, 'Setup opens drag boxes for party / alliance 1 / alliance 2');
    imgui.TextColored(DIM, 'and the list options window (buffs, filters, crew hover, sizes).');
    imgui.TextColored(DIM, '/goomui setup does the same. /goomui crew = crew link status.');
end

function G.toggle() G.open[1] = not G.open[1]; end
function G.open_window() G.open[1] = true; end

function G.render(cfg, bar, ring, aaev, party)
    local bar_cfg, ring_cfg, aaev_cfg = cfg.bar, cfg.ring, cfg.aaev;
    if (not G.open[1] or bar_cfg == nil or ring_cfg == nil or aaev_cfg == nil) then return; end

    if (imgui.Begin('goomui', G.open, ImGuiWindowFlags_AlwaysAutoResize)) then
        imgui.TextColored(HEADER, char_label());
        if (imgui.BeginTabBar('##thud_tabs', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton)) then
            if (imgui.BeginTabItem('Look##thud_tab_look')) then
                tab_look(bar_cfg);
                imgui.EndTabItem();
            end
            if (party ~= nil and imgui.BeginTabItem('Party##thud_tab_party')) then
                tab_party(party);
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Bar##thud_tab_bar')) then
                tab_bar(bar_cfg, bar);
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Ring##thud_tab_ring')) then
                tab_ring(ring_cfg, ring);
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('GEO##thud_tab_geo')) then
                tab_geo(ring_cfg, ring);
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('AAEV##thud_tab_aaev')) then
                tab_aaev(aaev_cfg, aaev);
                imgui.EndTabItem();
            end
            imgui.EndTabBar();
        end
    end
    imgui.End();

    -- Closing with X: flush both blocks once.
    if (not G.open[1]) then
        settings.save('bar');
        settings.save('ring');
        settings.save('aaev');
    end
end

return G;
