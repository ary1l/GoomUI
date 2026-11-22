addon.name    = 'goomui';
addon.author  = 'aryl (targetbar); Broguypal / Ashita v4 port (targetring); darkewaffle / Ashita v4 port (aaev); Tylas, Tirem (XivParty) / goomUI (party)';
addon.version = '2.0';
addon.desc    = 'Party list + target/cast/JA/menu bars + ground rings + GEO bubbles + optional AAEV, one look. Per-character settings.';
addon.link    = 'https://github.com/ary1l/goomui';

require('common');
local chat     = require('chat');
local settings = require('settings');
local bar      = require('modules/bar');
local ring     = require('modules/ring');
local aaev     = require('modules/aaev');
local gui      = require('modules/gui');
local party    = require('modules/party');   -- registers its own draw / packet / mouse events
local theme    = require('modules/theme');
local mobdebuff = require('modules/mobdebuff');
local pool     = require('modules/pool');
local hidegame = require('modules/hidegame'); -- the game's own party / alliance / target frames (Party tab)
local crumb    = require('modules/crumb');  -- crash marker: names the step a native crash happened in

--[[
* Settings: Ashita's settings lib is per-character by design.
*   config/addons/goomui/<Name>_<id>/bar.lua, ring.lua, aaev.lua   (logged in)
*   config/addons/goomui/<Name>_<id>/settings.lua                  (party list, same file goomUI 1.6 used)
*   config/addons/goomui/defaults/...                              (logged out)
* On a character switch the lib saves, then loads a NEW table per alias and raises
* settings.register callbacks. Modules must adopt that table (the lib saves by
* reference), which is what set_cfg does.
--]]
local cfg = { bar = nil, ring = nil, aaev = nil };

local function say(s) print(chat.header(addon.name):append(chat.message(s))); end

local function char_folder()
    return settings.settings_path():match('([^\\]+)\\+$') or 'defaults';
end

local function load_file(file)
    if (not ashita.fs.exists(file)) then return nil; end
    local ok, t = pcall(dofile, file);
    return (ok and type(t) == 'table') and t or nil;
end

-- Copies the keys defaults has, when the old value has the same type; returns how many.
local SKIP = { migrated = true };
local function copy_keys(old, s, defaults)
    local n = 0;
    for k, v in pairs(defaults) do
        if (not SKIP[k] and old[k] ~= nil and type(old[k]) == type(v)) then
            s[k] = old[k];
            n = n + 1;
        end
    end
    return n;
end

-- targethud 1.x kept bar/ring/aaev under config/addons/targethud/<char>/<alias>.lua.
local function from_targethud(alias, s, defaults)
    local old = load_file(('%s\\config\\addons\\targethud\\%s\\%s.lua'):fmt(AshitaCore:GetInstallPath(), char_folder(), alias));
    if (old == nil) then return false; end
    say(('Imported %d targethud %s settings (%s).'):fmt(copy_keys(old, s, defaults), alias, char_folder()));
    return true;
end

-- One-time import of the old addon's file for the same character folder.
local function migrate(alias, s, defaults, old_addon)
    if (s.migrated) then return; end
    s.migrated = true;
    if (not from_targethud(alias, s, defaults)) then
        local old = load_file(('%s\\config\\addons\\%s\\%s\\settings.lua'):fmt(AshitaCore:GetInstallPath(), old_addon, char_folder()));
        if (old ~= nil) then
            say(('Imported %d %s settings (%s).'):fmt(copy_keys(old, s, defaults), old_addon, char_folder()));
        end
    end
    settings.save(alias);
end

-- AAEV kept one shared (not per-char) set in its addon folder:
-- aaev_settings.lua (hand-edited) < aaev_saved.lua (GUI) < aaev_positions.lua.
-- Imported into each character's aaev.lua once. Found files => module enabled.
local function migrate_aaev(s)
    if (s.migrated) then return; end
    s.migrated = true;
    if (from_targethud('aaev', s, aaev.defaults)) then settings.save('aaev'); return; end

    local dir = ('%s\\addons\\aaev\\'):fmt(AshitaCore:GetInstallPath());
    local keys, found = { }, false;

    local function take(t)
        if (t == nil) then return; end
        found = true;
        for k, v in pairs(aaev.defaults) do
            if (k ~= 'enabled' and k ~= 'migrated' and t[k] ~= nil and type(t[k]) == type(v)) then
                s[k] = t[k];
                keys[k] = true;
            end
        end
    end

    take(load_file(dir .. 'aaev_settings.lua'));
    take(load_file(dir .. 'aaev_saved.lua'));

    local pos = load_file(dir .. 'aaev_positions.lua');
    if (pos ~= nil) then
        found = true;
        local map = { px = 'ChartStartX', py = 'ChartStartY', ex = 'PetChartStartX', ey = 'PetChartStartY' };
        for pk, sk in pairs(map) do
            if (type(pos[pk]) == 'number') then s[sk] = pos[pk]; keys[sk] = true; end
        end
    end

    if (found) then
        s.enabled = true;
        local n = 0;
        for _ in pairs(keys) do n = n + 1; end
        say(('Imported %d aaev settings (%s); AAEV enabled.'):fmt(n, char_folder()));
    end

    settings.save('aaev');
end

-- Colour preset (stored in bar.lua as `theme`): rebuild theme colours, then
-- let modules that copied them refresh. The party list reads theme live.
local function apply_theme(name)
    if (theme.apply(name)) then
        bar.retheme();
        aaev.retheme();
    end
end

local function adopt_bar(s)
    migrate('bar', s, bar.defaults, 'targetbar');
    cfg.bar = s;
    bar.set_cfg(s);
    pool.set_cfg(s);       -- pool window keys live in bar.lua
    apply_theme(s.theme);
    theme.set_look(s.bar_style, s.bar_texture, s.bar_frame);
    theme.set_panel(s.panel_style, s.panel_alpha);
    theme.set_ui_scale(s.ui_scale);
    bar.update_rcache();
    aaev.retheme();
    -- goomui 2.0 single-style names (segmented / striped / outline) -> new keys
    if (s.bar_style ~= theme.shape or s.bar_texture ~= theme.texture or s.bar_frame ~= theme.frame) then
        s.bar_style, s.bar_texture, s.bar_frame = theme.shape, theme.texture, theme.frame;
        settings.save('bar');
    end
end

local function adopt_ring(s)
    migrate('ring', s, ring.defaults, 'targetring');
    cfg.ring = s;
    ring.set_cfg(s);
end

local function adopt_aaev(s)
    migrate_aaev(s);
    cfg.aaev = s;
    aaev.set_cfg(s);
end

ashita.events.register('load', 'thud_load', function ()
    local crashed = crumb.report();
    if (crashed ~= nil) then
        print(chat.header(addon.name):append(chat.error(
            ('Last time goomui was unloaded by a crash during: %s. Please report this line.'):fmt(crashed))));
    end
    bar.init();
    adopt_bar(settings.load(bar.defaults, 'bar'));
    adopt_ring(settings.load(ring.defaults, 'ring'));
    adopt_aaev(settings.load(aaev.defaults, 'aaev'));
    aaev.init();
    aaev.on_config = gui.open_window;
    aaev.anchor_fn = bar.anchor;   -- docked AAEV chart follows the target bar
    aaev.dock_report = bar.set_dock_h; -- and the bar's downward stack starts under it
    gui.on_theme = function (name)
        if (cfg.bar == nil) then return; end
        cfg.bar.theme = name;
        settings.save('bar');
        apply_theme(name);
    end
    gui.on_panel = function (style, alpha)
        if (cfg.bar == nil) then return; end
        theme.set_panel(style, alpha);
        cfg.bar.panel_style, cfg.bar.panel_alpha = theme.panel_style, theme.panel_alpha;
        settings.save('bar');
        aaev.retheme();   -- AAEV plate follows the panel look
    end
    gui.on_scale = function (v)
        if (cfg.bar == nil) then return; end
        theme.set_ui_scale(v);
        cfg.bar.ui_scale = theme.ui_scale;
        settings.save('bar');
        bar.update_rcache();
        aaev.retheme();   -- AAEV re-measures its window at the new size
    end
    gui.on_look = function (shape, texture, frame)
        if (cfg.bar == nil) then return; end
        theme.set_look(shape, texture, frame);
        cfg.bar.bar_style, cfg.bar.bar_texture, cfg.bar.bar_frame = theme.shape, theme.texture, theme.frame;
        settings.save('bar');
    end

    settings.register('bar',  'thud_bar_switch',  adopt_bar);
    settings.register('ring', 'thud_ring_switch', adopt_ring);
    settings.register('aaev', 'thud_aaev_switch', adopt_aaev);
end);

ashita.events.register('unload', 'thud_unload', function ()
    pcall(hidegame.restore);
    bar.unload();
    aaev.unload();
    settings.save('bar');
    settings.save('ring');
    settings.save('aaev');
end);

-- Separate registrations: an error in one module cannot stop the other.
ashita.events.register('packet_in',  'thud_bar_in',   function (e) bar.packet_in(e);  end);
ashita.events.register('packet_in',  'thud_ring_in',  function (e) ring.packet_in(e); end);
ashita.events.register('packet_in',  'thud_aaev_in',  function (e) aaev.packet_in(e); end);
-- Mob debuffs: 0x028 / 0x029 only while the row is on (Bar tab); zone, merit and job point packets always.
local debuffs_on = true;
ashita.events.register('packet_in',  'thud_debuff_in', function (e)
    local on = (cfg.bar == nil) or (cfg.bar.show_debuffs ~= false);
    if (on ~= debuffs_on) then
        debuffs_on = on;
        if (not on) then mobdebuff.clear(); end
    end
    if (not on and (e.id == 0x028 or e.id == 0x029)) then return; end
    mobdebuff.packet_in(e);
end);
ashita.events.register('packet_in',  'thud_pool_in',  function (e) pool.packet_in(e); end);
ashita.events.register('packet_out', 'thud_bar_out',  function (e) bar.packet_out(e);  end);
ashita.events.register('packet_out', 'thud_ring_out', function (e) ring.packet_out(e); end);
-- Draw callbacks run guarded: an error turns that one piece off until reload and prints where it happened
-- (message + Lua stack), instead of Ashita unloading all of goomui on the first bad frame.
local function guard(label, fn, noscale)
    local failed = false;
    local function trace(err) return debug.traceback(tostring(err), 1); end
    return function (...)
        if (failed) then return; end
        crumb.begin(label);
        if (not noscale) then theme.scale_begin(); end
        local ok, err = xpcall(fn, trace, ...);
        if (not noscale) then theme.scale_end(); end
        crumb.done();
        if (ok) then return; end
        failed = true;
        print(chat.header(addon.name):append(chat.error(label .. ' off until reload (please report this):')));
        local n = 0;
        for line in tostring(err):gmatch('[^\n]+') do
            n = n + 1;
            if (n > 10) then break; end
            print(chat.header(addon.name):append(chat.message((line:gsub('^%s+', ''):gsub('^.-[\\/]addons[\\/]', '')))));
        end
    end
end

ashita.events.register('d3d_present', 'thud_ring_draw', guard('Rings', function () ring.render(); end, true)); -- world-space, no ImGui text
ashita.events.register('d3d_present', 'thud_bar_draw',  guard('Target bar', function () bar.render(); end));
ashita.events.register('d3d_present', 'thud_pool_draw', guard('Treasure pool window', function () pool.render(); end));
ashita.events.register('d3d_present', 'thud_aaev_draw', guard('AAEV', function () aaev.render(); end));
ashita.events.register('d3d_present', 'thud_gui_draw',  guard('Settings window', function () gui.render(cfg, bar, ring, aaev, party); end));
ashita.events.register('d3d_present', 'thud_hidegame',  guard('Game UI hiding', function () hidegame.apply(cfg.bar); end, true));

-- /goomui look ...: preset by name or next / prev; shape / texture / frame.
local function look_command(a, b, args)
    if (cfg.bar == nil) then return; end
    local order = theme.PRESET_ORDER;
    if (a == 'next' or a == 'prev') then
        local i = 1;
        for k, n in ipairs(order) do if (n == theme.current) then i = k; end end
        i = (a == 'next') and (i % #order + 1) or ((i - 2) % #order + 1);
        gui.on_theme(order[i]);
    elseif (a ~= nil and theme.PRESETS[a] ~= nil) then
        gui.on_theme(a);
    elseif (a == 'shape' and b ~= nil) then
        gui.on_look(b, theme.texture, theme.frame);
    elseif (a == 'texture' and b ~= nil) then
        gui.on_look(theme.shape, b, theme.frame);
    elseif (a == 'panel' and b ~= nil) then
        gui.on_panel(b, theme.panel_alpha);
    elseif (a == 'opacity' and tonumber(b) ~= nil) then
        gui.on_panel(theme.panel_style, tonumber(b));
    elseif (a == 'frame') then
        local on = (b == 'on') or (b == nil and not theme.frame);
        gui.on_look(theme.shape, theme.texture, on);
    elseif (a == 'set' and args ~= nil and #args >= 9) then
        -- /goomui look set <preset> <shape> <texture> <frame on|off> <panel> <opacity>: all at once (Apply to all)
        local v = function (i) return args[i]:lower(); end
        if (theme.PRESETS[v(4)] == nil or tonumber(args[9]) == nil) then
            say('look set <preset> <shape> <texture> <frame on|off> <panel> <opacity>');
            return;
        end
        gui.on_theme(v(4));
        gui.on_look(v(5), v(6), v(7) == 'on');
        gui.on_panel(v(8), tonumber(args[9]));
    elseif (a ~= nil) then
        local names = {};
        for _, n in ipairs(order) do names[#names + 1] = n; end
        say('Presets: ' .. table.concat(names, ' '));
        return;
    end
    say(('Look: %s | shape %s | texture %s | frame %s | panel %s x%.2f'):fmt(theme.PRESET_LABEL[theme.current] or '?',
        theme.shape, theme.texture, theme.frame and 'on' or 'off', theme.panel_style, theme.panel_alpha));
end

local HELP = {
    '/goomui  (or /gui)              toggle settings window',
    '/goomui setup                   party list setup: drag lists, list options (again = save)',
    '/goomui lowfi | crew | perf     party: low-fi toggle / crew link status / 10 s timing',
    '/goomui tdebug                  party: target-marker diagnostics',
    '/goomui pool [demo|open|dock]   treasure pool on/off / sample items / full window / summary by the party',
    '/goomui look [next|prev|<preset>] colour preset (no word = show current)',
    '/goomui look shape soft|flat|glass | texture none|segmented|striped|quarters|scanline|fade | frame [on|off]',
    '/goomui look panel tinted|dark|clear|framed | opacity <0.25-2>',
    '/goomui scale <0.5-3>           UI scale: text + sizes of every goomui window (small / high-DPI screens)',
    '/goomui ring                    ring status',
    '/goomui ring on|off|depth|arrow|runes|fade|flip',
    '/goomui ring scale <n> | slices <n>',
    '/goomui ring range on|off|geo|hitbox | base <n> | fill <n>',
    '/goomui cursor [on|off] | style|color|sub <x> | size <n> | float|spin [on|off] | lift <px>',
    '/goomui geo [on|off|buffs|cure|bubble|clear | radius|cap|scan|slices <n>]',
    '/goomui aaev on|off             enable / disable auto-attack chart',
    '/goomui aaev [show|hide|demo|lock|unlock|zone|help ...]',
};

ashita.events.register('command', 'thud_command', function (e)
    local args = e.command:args();
    if (#args == 0) then return; end
    local c = args[1]:lower();
    if (c ~= '/goomui' and c ~= '/gui') then return; end
    e.blocked = true;

    local sub = args[2] and args[2]:lower() or nil;

    if (sub == nil) then
        gui.toggle();
    elseif (party.command(sub)) then
        return;
    elseif (sub == 'pool') then
        local m = pool.command(args[3] and args[3]:lower() or nil);
        if (m ~= nil) then say(m); end
    elseif (sub == 'scale') then
        if (args[3] ~= nil and tonumber(args[3]) ~= nil) then gui.on_scale(tonumber(args[3])); end
        say(('UI scale x%.2f (0.5 - 3). /goomui scale <n>'):fmt(theme.ui_scale));
    elseif (sub == 'look') then
        look_command(args[3] and args[3]:lower() or nil, args[4] and args[4]:lower() or nil, args);
    elseif (sub == 'ring') then
        -- Old /tring layout: args[2] = sub-command. Drop the 'ring' word.
        local a = { args[1] };
        for i = 3, #args do a[#a + 1] = args[i]; end
        ring.command(a);
    elseif (sub == 'geo') then
        ring.command(args);     -- already /tring geo <opt> <val> layout
    elseif (sub == 'cursor') then
        ring.cursor_command(args);
    elseif (sub == 'aaev') then
        local opt = args[3] and args[3]:lower() or nil;
        if (opt == 'on' or opt == 'off') then
            aaev.set_enabled(opt == 'on');
            say('AAEV ' .. opt .. '.');
        elseif (not aaev.enabled() and opt ~= 'config') then
            say('AAEV is off: /goomui aaev on');
        else
            local a = { args[1] };
            for i = 3, #args do a[#a + 1] = args[i]; end
            aaev.command(a);
        end
    else
        for _, line in ipairs(HELP) do say(line); end
    end
end);
