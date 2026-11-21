--[[
* goomui: bar module.
* From targetbar 1.1 (aryl). Settings, GUI and events live in goomui.lua / modules/gui.lua.
--]]

require('common')
local bit      = require('bit')
local ffi      = require('ffi')
local imgui    = require('imgui')
local settings = require('settings')
local theme    = require('modules/theme')
local crumb    = require('modules/crumb') -- crash marker steps (modules/crumb.lua)
local mobdebuff = require('modules/mobdebuff')

local M = {}

local mm = AshitaCore:GetMemoryManager()
local rm = AshitaCore:GetResourceManager()

local pMenuHelp = ashita.memory.find(0, 0, '5350E8????????5F885D??5E5D5BC3A1????????85C0????538BCDE8', 16, 0)

------------------------------------------------------------
-- WINDOW FLAGS
------------------------------------------------------------
local FLAGS_LOCKED = bit.bor(
    ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize,
    ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav,
    ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoMove,
    ImGuiWindowFlags_NoMouseInputs)

local FLAGS_MOVABLE = bit.bor(
    ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize,
    ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav,
    ImGuiWindowFlags_NoBackground)

------------------------------------------------------------
-- CONFIG & CONSTANTS
------------------------------------------------------------
local default_cfg = T{
    pos_x = 1010, pos_y = 820, bar_width = 400, bar_height = 14,
    show_distance = true,
    show_height   = false,
    dynamic_range = true,
    show_menuinfo = true,
    show_pet      = true,
    show_jabar    = true,
    show_debuffs  = true,    -- debuffs on the targeted mob, under its HP bar (modules/mobdebuff.lua)
    debuff_icon   = 18,      -- their icon size, px
    show_pool     = true,    -- treasure pool window (modules/pool.lua); shown while the pool has items
    pool_x = 1010, pool_y = 520,
    pool_dock     = true,    -- a one-line summary by the party list; click it for the full window (false: window only)
    pool_open     = false,   -- the full window shown (docked: toggled by clicking the summary)
    debuffs_below = false,   -- debuff row under its target panel instead of above (other panels still stack up)
    locked        = true,
    theme         = 'vivid', -- colour preset for every goomui bar (modules/theme.lua)
    bar_style     = 'soft',  -- bar shape: soft / flat / glass
    bar_texture   = 'none',  -- none / segmented / striped
    bar_frame     = false,   -- hollow frame in the fill colour
    cast_linger   = 2.5,     -- seconds a finished / interrupted cast and a JA stay on screen
    panel_style   = 'tinted',-- panel backgrounds: tinted / dark / clear / framed
    panel_alpha   = 1.0,     -- panel opacity multiplier (0.25 - 2)
    ui_scale      = 1.0,     -- goomui-wide UI scale, text + sizes (0.5 - 3): small / high-DPI screens
    migrated      = false,   -- old targetbar settings imported
}
M.defaults = default_cfg
local cfg = default_cfg

local CAST_BAR_HEIGHT = 8
local UPDATE_INTERVAL = 0.15
local SCAN_INTERVAL   = 1.0
local FINISH_DELAY    = 1.5
local JA_BAR_LINGER   = 2.0

local PANEL_PADDING   = 4
local TOP_PADDING     = 2
local SP              = 8      -- ItemSpacing.x allowance for a SameLine() gap
local DEBUFF_PAD      = { 4, 2 }
local DEBUFF_GAP      = 4

local CAST_IDLE_EPS     = 0.02
local CAST_RESTART_DROP = 0.05
local CAST_RISE_GRACE   = 0.5
local CAST_TIME_DIVISOR = 4.0

local function resource_cast_seconds(r)
    local ct = r and r.CastTime
    if not ct or ct <= 0 then return nil end
    return ct / CAST_TIME_DIVISOR
end

local FALLBACK_GRACE     = 0.30
local FALLBACK_CAST_TIME = 3.00
local PENDING_TTL        = 2.00   -- unconfirmed attempts die silently after this
local RECAST_SENTINEL = 0xFFFF0000

-- Action packet (0x028) category/param constants.
-- Category 8 = magic start/interrupt, 9 = item start/interrupt (self only).
-- Param 24931 ('begins') = server committed the action; 28787 = failed/interrupted.
local ACT_BEGIN     = 24931
local ACT_INTERRUPT = 28787

------------------------------------------------------------
-- COLORS & TABLES
------------------------------------------------------------
local C = {
    -- goomui theme: dark plate tinted by target kind + 5px accent stripe on the left.
    PANEL_BG     = theme.u32( 8, 12, 14, 125),
    PANEL_BLUE   = theme.u32(14, 20, 48, 160),
    PANEL_NPC    = theme.u32(12, 30, 16, 155),
    PANEL_PET    = theme.u32(10, 28, 30, 155),
    PANEL_MOB    = theme.u32(38, 12, 12, 155),
    PANEL_PC     = theme.u32(12, 20, 38, 155),
    ACC_BLUE     = theme.u32(127, 163, 196),
    ACC_NPC      = theme.u32(127, 176, 122),
    ACC_PET      = theme.u32(100, 180, 180),
    ACC_MOB      = theme.u32(196,  84,  74),
    ACC_PC       = theme.u32( 93, 143, 194),
    PANEL_CAST   = theme.u32(10, 16, 20, 130),
    PANEL_ITEM   = theme.u32(20, 14, 28, 130),
    PANEL_JA     = theme.u32(10, 20, 14, 130),
    BAR_DEAD     = theme.U.DEAD,
    SPELL_BAR    = theme.U.SPELL,
    ITEM_BAR     = theme.U.ITEM,
    SPELL_TXT    = {0.35, 0.62, 1.00, 1.0},
    ITEM_TXT     = {0.72, 0.46, 1.00, 1.0},
    JA_TXT       = {0.45, 0.90, 0.45, 1.0},
    MENU_TXT     = {0.55, 0.80, 1.00, 1.0},
    HP_TXT       = {0.80, 0.80, 0.80, 1.0},
    DEAD_TXT     = {0.60, 0.20, 0.20, 1.0},
    DIST_RED     = {1.00, 0.20, 0.20, 1.0},
    DIST_MID     = {1.00, 0.475, 0.00, 1.0},
    DIST_NEAR    = {0.20, 1.00, 0.20, 1.0},
    HEIGHT_OK    = {0.70, 0.70, 0.75, 1.0},
    HEIGHT_WARN  = {1.00, 0.35, 0.35, 1.0},
    NPC          = {0.55, 0.89, 0.52, 1.0},
    PC_SELF      = {0.26, 0.53, 0.96, 1.0},
    PC_PARTY     = {0.27, 0.78, 1.00, 1.0},
    PC_ALLY      = {0.62, 0.89, 1.00, 1.0},
    PC_OTHER     = {0.80, 0.90, 1.00, 1.0},
    ENEMY        = {0.97, 0.93, 0.55, 1.0},
    CLAIM        = {1.00, 0.30, 0.30, 1.0},
    STEALTH      = {0.83, 0.42, 0.83, 1.0},
    ARROW        = {1.00, 1.00, 1.00, 1.0},
    PANEL_MENU   = theme.u32( 8, 12, 14, 125),
    MENU_NAME    = {0.35, 0.62, 1.00, 1.0},
    MENU_READY   = {0.32, 0.86, 0.36, 1.0},
    MENU_NOTRDY  = {0.96, 0.32, 0.32, 1.0},
    MENU_BAR_SP  = theme.U.MENU_SP,
    MENU_BAR_JA  = theme.U.MENU_JA,
    HANDLE_BG    = theme.u32(12, 18, 40, 200),
    HANDLE_TXT   = {0.80, 0.86, 1.00, 1.0},
}

local HP_COLOR_LUT         = {}
local PERCENT_STR_LUT      = {}
local CAST_PERCENT_STR_LUT = {}
for i = 0, 100 do
    PERCENT_STR_LUT[i]      = tostring(i) .. '%'
    CAST_PERCENT_STR_LUT[i] = ' ' .. tostring(i) .. '%'
end

local EXCLUDED_KEYWORDS = {
    'commands', 'magic list', 'abilities', 'items', 'trade', 'conquest',
    'chat', 'status', 'equipment', 'synthesis', 'party', 'search',
    'linkshell', 'region info', 'map', 'log', 'window', 'besieged',
    'campaign', 'colonization', 'wide scan', 'communication',
    'log out', 'shut down', 'friend list', 'emote list', 'current time',
    'help desk', 'config', 'markers', 'macropalette', 'set bazaar',
    'view house', 'key items', 'quests', 'missions',
}

local function is_excluded_text(lower)
    for i = 1, #EXCLUDED_KEYWORDS do
        if string.find(lower, EXCLUDED_KEYWORDS[i], 1, true) then return true end
    end
    return false
end

------------------------------------------------------------
-- STATE
------------------------------------------------------------
local cast_state = {
    name='', target_color={1,1,1,1},
    target_idx=0, is_item=false,
    display_target='Self', bar_color_txt=C.SPELL_TXT,
    start_time=0, started=false,
    time_driven=false, duration=0,
    render_frac=0, cr_last_start=-1, last_present=0,  -- render-side cast-fill smoothing
    action_id=nil,                     -- spell / item id (matched against 0x028 cat 4/5)
    done_at=0, done_ok=true, done_frac=1  -- finished (ok) or interrupted: held cfg.cast_linger s
}

local pending_cast_state = {
    name='', target_color={1,1,1,1},
    target_idx=0, is_item=false,
    display_target='Self', bar_color_txt=C.SPELL_TXT,
    duration=0,
    action_id=nil,    -- spell id / item id sent (nil = unknown, any matching begin confirms)
    confirmed=false   -- set true only when the server echoes 'begins' (0x028 cat 8/9)
}

local ja_state = {
    name = '',
    display_target = 'Self',
    target_color = C.PC_SELF,
    expires = 0,
}

local ja_pending = {
    name = '',
    display_target = 'Self',
    target_color = C.PC_SELF,
    deadline = 0,
}

local cast_finished_time     = 0
local last_cast_frac         = 0
local last_disp_frac         = 0
local last_frac_change_time  = 0
local pending_time           = 0
local cb_alive               = false
local cast_rise_pending      = false
local cast_rise_time         = 0
local sub_target_persistence = 0
local sub_target_expires     = 0

local last_menu_update = 0

-- Mount recast: 1 minute from the summon (bg-wiki Category:Mounts), timed client-side from the Mount status
-- (buff 252) 0->1 edge. id starts at -1 ('not yet sampled') so a reload while mounted records the baseline
-- instead of a phantom 1:00.
local mount = { id = -1, cd_until = 0, chk = 0, recast = 60.0, interval = 0.20 }

local main_target_cache   = {}
local sub_target_cache    = {}
local packet_target_cache = {}
local party_id_cache      = {}
local party_masked_cache  = {}

local last_logic_update  = 0
local last_main_idx      = 0
local last_sub_idx       = 0
local last_scan_time     = 0
local self_id_cache      = 0
local self_id_masked     = 0
local last_menu_text     = ''
local last_raw_menu_text = ''

local main_data     = nil
local sub_data      = nil
local pet           = { data = nil, cache = {}, bar_h = 24, idx = 0 }

local force_handle  = false

local v_pos  = {0, 0}
local v_size = {0, 0}
local v_p1   = {0, 0}
local v_p2   = {0, 0}
local p_open = {true}

-- Cached manager interfaces, refreshed on load and zone-in.
local mgr = {
    player = nil, party = nil, recast = nil, inv = nil,
    cb = nil, targ = nil, entity = nil,
}

local function refresh_managers()
    mgr.player = mm:GetPlayer()
    mgr.party  = mm:GetParty()
    mgr.recast = mm:GetRecast()
    mgr.inv    = mm:GetInventory()
    mgr.cb     = mm:GetCastBar()
    mgr.targ   = mm:GetTarget()
    mgr.entity = mm:GetEntity()
end

local rcache = { bw = 400, bh = 14, win_w = 0, h_main = 32, h_sub = 24, h_cast = 28, h_ja = 22, h_menu = 28, h_debuff = 30, h_debuff_sub = 30, bar_dx = 12 }

-- The GUI writes bar_width/bar_height live while a value is being typed; draw
-- with clamped copies so a half-typed '1' or '-' never reaches Dummy/AddRect.
local tw_cache, tw_n = {}, 0   -- text widths (text_w); cleared when the UI scale changes the font size
local fit_cache, fit_n = {}, 0   -- fit_text results (string x width budget); cleared with tw_cache
local tw_scale = 1.0
local function update_rcache()
    if tw_scale ~= theme.ui_scale then table.clear(tw_cache); tw_n = 0; table.clear(fit_cache); fit_n = 0; tw_scale = theme.ui_scale end
    -- Pixel sizes follow the global UI scale (theme.ui_scale); the settings stay in scale-1 pixels.
    rcache.bw     = theme.px(math.max(100, math.min(800, tonumber(cfg.bar_width)  or 400)))
    rcache.bh     = theme.px(math.max(6,   math.min(48,  tonumber(cfg.bar_height) or 14)))
    CAST_BAR_HEIGHT = theme.px(8)
    PANEL_PADDING   = theme.px(4)
    TOP_PADDING     = theme.px(2)
    SP              = theme.px(8)
    DEBUFF_PAD[1], DEBUFF_PAD[2] = theme.px(4), theme.px(2)
    DEBUFF_GAP      = theme.px(4)
    rcache.icon     = theme.px(tonumber(cfg.debuff_icon) or 18)
    rcache.win_w  = rcache.bw + theme.px(16)
end

------------------------------------------------------------
-- RANGE & POSITION HELPERS
------------------------------------------------------------
-- Ashita's entity Distance is center-to-center, so the real reach of anything
-- you cast or swing is (base range + your hitbox + theirs). A big NM can be
-- inside casting range while the raw number reads well past 22.
--
-- With two average PCs (~1.0 hitbox each) the edges land on 22 / 30, the fixed
-- cuts used when dynamic_range is off.
local RANGE = {
    base    = 20.0,   -- standard magic range
    mid_pad =  8.0,   -- width of the amber 'close, but out of range' band
    up      =  8.5,   -- target this far above you: height is the problem, not distance
    down    = -7.5,   -- ...or this far below (thresholds taken from DistancePlus)
}

local pos = { self_idx = 0, self_hb = 0.0 }

-- ModelSize is usually -1; ModelHitboxSize is the size the server sends.
local function hitbox_of(entity, idx)
    if not entity or not idx or idx == 0 then return 0.0 end
    local h = entity:GetModelHitboxSize(idx)
    if type(h) ~= 'number' or h <= 0.0 or h > 20.0 then return 0.0 end
    return h
end

------------------------------------------------------------
-- UTILITY FUNCTIONS
------------------------------------------------------------
local function is_game_active()
    local pl = mgr.player
    if not pl then                                  -- addon loaded at title screen
        pl = mm:GetPlayer()
        mgr.player = pl
    end
    return pl ~= nil and pl:GetLoginStatus() == 2   -- 2 = logged in / in the game world
end

local function reset_cast()
    cast_state.name        = ''
    cast_state.target_idx  = 0
    cast_state.is_item     = false
    cast_state.started     = false
    cast_state.time_driven = false
    cast_finished_time     = 0
    last_cast_frac         = 0
    last_disp_frac         = 0
    last_frac_change_time  = 0
    cast_state.render_frac  = 0
    cast_state.done_at      = 0
    pending_cast_state.name      = ''
    pending_cast_state.confirmed = false
end

local function promote_pending()
    cast_state.name          = pending_cast_state.name
    cast_state.target_color  = pending_cast_state.target_color
    cast_state.target_idx    = pending_cast_state.target_idx
    cast_state.is_item       = pending_cast_state.is_item
    cast_state.display_target= pending_cast_state.display_target
    cast_state.bar_color_txt = pending_cast_state.bar_color_txt
    cast_state.action_id     = pending_cast_state.action_id
    cast_state.started       = true
    cast_state.done_at       = 0
end

-- Server said the cast / item finished (ok) or was interrupted: freeze the bar
-- (full when ok) and keep it cfg.cast_linger seconds, so a fast cast is seen.
local function mark_done(ok)
    cast_state.done_at   = os.clock()
    cast_state.done_ok   = ok
    cast_state.done_frac = ok and 1.0 or math.max(0.05, cast_state.render_frac)
end

local function GetMenuHelpText()
    if pMenuHelp == 0 then return '' end
    local offset = ashita.memory.read_uint32(pMenuHelp)
    if offset == 0 then return '' end
    offset = ashita.memory.read_uint32(offset)
    if offset == 0 then return '' end
    offset = ashita.memory.read_uint32(offset + 0xEC)
    if offset ~= 0 then
        local str = ashita.memory.read_string(offset, 256)
        if str then
            local null_pos = string.find(str, '\x00', 1, true)
            if null_pos then return string.sub(str, 1, null_pos - 1) end
            return str
        end
    end
    return ''
end

------------------------------------------------------------
-- MENU HOVER INFO
------------------------------------------------------------
-- (only rebuild_menu_info reads msig, at <=10Hz when a menu is open).
local msig = {}
do
    msig.magic   = ashita.memory.find('FFXiMain.dll', 0, '81EC80000000568B35????????578BCE8B7E3057', 0x09, 0)
    msig.ability = ashita.memory.find('FFXiMain.dll', 0, '81EC80000000568B35????????8BCE8B463050E8', 0x09, 0)
    msig.mount   = ashita.memory.find('FFXiMain.dll', 0, '8B4424048B0D????????50E8????????8B0D????????C7411402000000C3', 0x06, 0)

    local sig_getitem_ability = ashita.memory.find('FFXiMain.dll', 0, '8B44240485C07C??3B41447D??8B49208D04C185C075??83C8FFC204008B108B', 0, 0)
    local sig_getitem_spell   = ashita.memory.find('FFXiMain.dll', 0, '8B44240485C07C??3B41447D??8B49208D04C185C075??83C8FFC204008B108B', 0, 1)
    local sig_getitem_mount   = ashita.memory.find('FFXiMain.dll', 0, '8B44240485C07C??3B41447D??8B49208D04C185C075??83C8FFC204008B00C20400', 0, 0)
    local sig_spell_getitem   = (sig_getitem_spell ~= 0) and sig_getitem_spell or sig_getitem_ability

    pcall(function()
        ffi.cdef[[ typedef int32_t (__thiscall* KaListBox_GetItem_f)(uint32_t, int32_t); ]]
    end)

    local function make_getitem(ptr)
        if not ptr or ptr == 0 then return nil end
        local ok, fn = pcall(ffi.cast, 'KaListBox_GetItem_f', ptr)
        return (ok and fn) or nil
    end

    msig.fn_ability = make_getitem(sig_getitem_ability)
    msig.fn_spell   = make_getitem(sig_spell_getitem)
    msig.fn_mount   = make_getitem(sig_getitem_mount)
end

local MENU_UPDATE = 0.10

-- Pet commands and Blood Pacts by name -> recast timer id (Windower resources ability_recasts.lua).
local ABILITY_TIMER = {
    ['Blood Pact: Rage'] = 173, ['Blood Pact: Ward'] = 174, ['Apogee'] = 108, ['Mana Cede'] = 71,
    ['Ready'] = 102, ['Sic'] = 102, ['Reward'] = 103, ['Call Beast'] = 104, ['Call Wyvern'] = 163,
    ['Spirit Link'] = 162, ['Deep Breathing'] = 164, ['Steady Wing'] = 70, ['Activate'] = 205,
    ['Repair'] = 206, ['Deploy'] = 207, ['Deactivate'] = 208, ['Retrieve'] = 209, ['Deus Ex Automata'] = 115,
}

-- An ability recast's full length is not in client data (IAbility has no recast delay; 0x119 sends time left), so
-- it is the highest value seen since the timer last read 0. Sampled for all 32 slots by the render loop.
local recast_peak = {}  -- timer id -> 1/60 s
local function sample_recast_peaks(rc)
    for slot = 0, 31 do
        local tid = rc:GetAbilityTimerId(slot)
        if tid ~= 0 or slot == 0 then
            local t = rc:GetAbilityTimer(slot)
            if t and t > 0 and t < RECAST_SENTINEL then
                if t > (recast_peak[tid] or 0) then recast_peak[tid] = t end
            else
                recast_peak[tid] = nil
            end
        end
    end
end

local SCH_JOB_ID = 20

local function get_job_level(job_id)
    local pl = mgr.player
    if not pl then return 0 end
    if pl:GetMainJob() == job_id then return pl:GetMainJobLevel() or 0 end
    if pl:GetSubJob()  == job_id then return pl:GetSubJobLevel()  or 0 end
    return 0
end

local function stratagem_max_charges()
    local lvl = get_job_level(SCH_JOB_ID)
    if lvl < 10 then return 0 end
    local c = math.floor((lvl - 10) / 20) + 1
    if c < 1 then c = 1 elseif c > 5 then c = 5 end
    return c
end

local CHARGE_POOLS = {
    [231] = { base = 240 },
    [195] = { max = 2, base = 120 },
    [102] = { max = 3, base = 90 },
}

local function charge_params(timerId, calc1, calc2)
    local pool = timerId and CHARGE_POOLS[timerId]
    if not pool then return nil end
    local mc = pool.max or stratagem_max_charges()
    if mc <= 0 then return nil end
    local full = pool.base + (calc2 or 0)
    full = full - bit.band(calc1 or 0, 0x3F) * full / 60
    if full < mc then full = mc end
    return mc, full / mc
end

local function compute_charges(recast_sec, max_charges, charge_time)
    if max_charges <= 0 or charge_time <= 0 then return max_charges, 0 end
    local used = math.ceil(recast_sec / charge_time - 1e-6)
    if used < 0 then used = 0 elseif used > max_charges then used = max_charges end
    local avail = max_charges - used
    local next_t = 0
    if recast_sec > 0 and used > 0 then
        next_t = recast_sec - (used - 1) * charge_time
        if next_t < 0 then next_t = recast_sec % charge_time end
    end
    return avail, next_t
end

local function menu_obj(sel_sig)
    if sel_sig == 0 then return 0 end
    local p = ashita.memory.read_uint32(sel_sig)
    if p == 0 then return 0 end
    p = ashita.memory.read_uint32(p)
    return p or 0
end

local function menu_selected_raw(sel_sig, getitem_fn)
    if sel_sig == 0 or not getitem_fn then return -1 end
    local obj = menu_obj(sel_sig)
    if obj == 0 then return -1 end
    if ashita.memory.read_int32(obj + 0x40) <= 0 then return -1 end
    local idx = ashita.memory.read_int32(obj + 0x30)
    return getitem_fn(obj, idx)
end

local function menu_selected_id(sel_sig, getitem_fn)
    crumb.sub('target bar: menu item (game call)')
    local id = menu_selected_raw(sel_sig, getitem_fn)
    crumb.back()
    return id
end

local function fmt_recast(s)
    if s < 0 then s = 0 end
    local n = math.floor(s + 0.5)
    return string.format('%d:%02d', math.floor(n / 60), n % 60)
end

local function ability_recast_raw_by_timer(timerId)
    if not timerId then return 0, 0, 0 end
    local rc = mgr.recast
    if not rc then return 0, 0, 0 end
    for slot = 0, 31 do
        if rc:GetAbilityTimerId(slot) == timerId then
            local t = rc:GetAbilityTimer(slot)
            local raw = (t and t > 0 and t < RECAST_SENTINEL) and t or 0
            return raw, rc:GetAbilityCalc1(slot) or 0, rc:GetAbilityCalc2(slot) or 0
        end
    end
    return 0, 0, 0
end

-- raw (1/60 s), full length (s), timer id, calc1, calc2
local function get_ability_recast_raw(ab)
    local tid = ABILITY_TIMER[ab.Name[1]] or ab.RecastTimerId
    local raw, c1, c2 = ability_recast_raw_by_timer(tid)
    return raw, (recast_peak[tid] or 0) / 60, tid, c1, c2
end

local menu_cache = {
    active=false, name='', name_color=C.MENU_NAME,
    cost='', cost_color=C.MENU_READY,
    recast='', recast_color=C.MENU_READY,
    on_cd=false, cd_frac=0,
    is_charge=false, charge_color=C.MENU_READY, charge_str='', next_str='',
    bar_color=C.MENU_BAR_SP,
    last_recast_str_sec=-1, last_sid=-2, last_aid=-2, last_mid=-2,
}

local function set_menu_recast(raw, max_sec)
    if raw and raw > 0 then
        local rem = raw / 60
        local rem_int = math.floor(rem + 0.5)
        menu_cache.on_cd = true

        if rem_int ~= menu_cache.last_recast_str_sec then
            menu_cache.recast = fmt_recast(rem)
            menu_cache.last_recast_str_sec = rem_int
        end

        menu_cache.recast_color = C.MENU_NOTRDY
        menu_cache.cd_frac      = (max_sec and max_sec > 0)
            and math.max(0.0, math.min(1.0, 1 - rem / max_sec)) or 0
    else
        menu_cache.on_cd = false
        if menu_cache.last_recast_str_sec ~= 0 then
            menu_cache.recast = 'Ready'
            menu_cache.last_recast_str_sec = 0
        end
        menu_cache.recast_color = C.MENU_READY
        menu_cache.cd_frac      = 1
    end
end

local function rebuild_menu_info()
    menu_cache.active    = false
    menu_cache.is_charge = false

    -- Magic menu --------------------------------------------------------------
    local sid = menu_selected_id(msig.magic, msig.fn_spell)
    if sid >= 0 then
        local sp = rm:GetSpellById(sid)
        if sp then
            menu_cache.active     = true
            if sid ~= menu_cache.last_sid then
                menu_cache.name       = sp.Name[1] or 'Spell'
                menu_cache.last_sid = sid
            end
            -- name is shared: back in the ability/mount menu on the same entry
            -- must rebuild it, not keep this spell's name.
            menu_cache.last_aid = -2
            menu_cache.last_mid = -2
            menu_cache.name_color = C.MENU_NAME
            menu_cache.bar_color  = C.MENU_BAR_SP
            local mp = sp.ManaCost or 0
            if mp > 0 then
                menu_cache.cost = 'MP ' .. mp
                local pmp = 0
                local pt = mgr.party; if pt then pmp = pt:GetMemberMP(0) or 0 end
                menu_cache.cost_color = (pmp >= mp) and C.MENU_READY or C.MENU_NOTRDY
            else
                menu_cache.cost = ''
            end
            local raw = 0
            local rc = mgr.recast
            if rc then local t = rc:GetSpellTimer(sid); raw = (t and t > 0) and t or 0 end
            set_menu_recast(raw, (sp.RecastDelay or 0) / 4)
            return
        end
    end
    menu_cache.last_sid = -2

    -- Abilities menu ----------------------------------------------------------
    local aid = menu_selected_id(msig.ability, msig.fn_ability)
    if aid >= 0 then
        local ab = rm:GetAbilityById(aid)
        if ab then
            menu_cache.active     = true
            if aid ~= menu_cache.last_aid then
                menu_cache.name       = ab.Name[1] or 'Ability'
                menu_cache.last_aid = aid
            end
            menu_cache.last_mid = -2
            menu_cache.name_color = C.MENU_NAME
            menu_cache.bar_color  = C.MENU_BAR_JA

            local raw, maxs, tid, c1, c2 = get_ability_recast_raw(ab)
            local recast_sec = (raw and raw > 0) and (raw / 60) or 0

            local mc, ctime = charge_params(tid, c1, c2)
            if mc then
                local avail, next_t = compute_charges(recast_sec, mc, ctime)
                menu_cache.is_charge    = true
                menu_cache.cost         = ''
                menu_cache.charge_str   = avail .. '/' .. mc
                menu_cache.charge_color = (avail > 0) and C.MENU_READY or C.MENU_NOTRDY
                menu_cache.next_str     = (recast_sec > 0) and ('Next ' .. fmt_recast(next_t)) or ''
                menu_cache.on_cd        = (recast_sec > 0)
                menu_cache.cd_frac      = (recast_sec > 0 and ctime > 0)
                    and math.max(0.0, math.min(1.0, 1 - next_t / ctime)) or 0
                return
            end

            menu_cache.is_charge = false
            local isWS = (aid >= 1 and aid <= 255)
            local ptp  = 0

            if isWS then
                local pt = mgr.party; if pt then ptp = pt:GetMemberTP(0) or 0 end
                menu_cache.cost       = 'TP ' .. ptp
                menu_cache.cost_color = (ptp >= 1000) and C.MENU_READY or C.MENU_NOTRDY

                set_menu_recast(raw, maxs)
                -- Force the menu action bar off for Weaponskills
                menu_cache.on_cd = false
                menu_cache.cd_frac = 0

                menu_cache.recast_color = (ptp >= 1000) and C.MENU_READY or C.MENU_NOTRDY
            else
                menu_cache.cost = ''
                set_menu_recast(raw, maxs)
            end
            return
        end
    end
    menu_cache.last_aid = -2

    -- Mount menu --------------------------------------------------------------
    local mid = menu_selected_id(msig.mount, msig.fn_mount)
    if mid >= 0 then
        menu_cache.active = true
        -- The recast is read every rebuild; only the name waits for a new mount id.
        if mid ~= menu_cache.last_mid then
            local nm = rm:GetString('mounts.names', mid)
            menu_cache.name = (nm and nm ~= '') and nm or 'Mount'
            menu_cache.last_mid = mid
        end
        menu_cache.name_color = C.MENU_NAME
        menu_cache.bar_color  = C.MENU_BAR_JA
        menu_cache.cost       = ''
        -- Remaining mount cooldown, timed by the render loop (see the mount table).
        local raw  = 0
        local rnow = os.clock()
        if mount.cd_until > rnow then
            raw = (mount.cd_until - rnow) * 60   -- seconds left -> 1/60s for set_menu_recast
        end
        set_menu_recast(raw, 60)
        return
    end
    menu_cache.last_mid = -2
end

------------------------------------------------------------
-- TEXT FITTING
------------------------------------------------------------
-- Panels are a fixed bar_width + 16 wide and ImGui clips text at the window edge, so every variable-length
-- string is measured and shortened to the space left on its line. CalcTextSize runs on a cache miss only:
-- results are keyed by string + a 4px-quantized budget; table.clear at 256 keys bounds the cache.
local ELLIPSIS  = '...'

local function measure(s)
    return (imgui.CalcTextSize(s))
end

-- Width memo (split_fit, menu reserve).
local function text_w(s)
    if s == nil or s == '' then return 0 end
    local w = tw_cache[s]
    if w then return w end
    w = measure(s)
    tw_n = tw_n + 1
    if tw_n > 256 then table.clear(tw_cache); tw_n = 1 end
    tw_cache[s] = w
    return w
end

local function fit_text(s, max_w)
    if s == nil or s == '' then return '' end
    local bucket = math.floor(max_w * 0.25)          -- quantize to 4px
    if bucket <= 0 then return '' end
    max_w = bucket * 4

    -- Two-level lookup: no per-frame key concat.
    local row = fit_cache[s]
    local hit = row and row[bucket]
    if hit ~= nil then return hit end

    local out = s
    if text_w(s) > max_w then
        local budget = max_w - text_w(ELLIPSIS)
        if budget <= 0 then
            out = ''
        else
            local lo, hi = 0, #s                      -- longest prefix that fits
            while lo < hi do
                local mid = math.floor((lo + hi + 1) * 0.5)
                if measure(string.sub(s, 1, mid)) <= budget then lo = mid else hi = mid - 1 end
            end
            out = (lo > 0) and (string.sub(s, 1, lo) .. ELLIPSIS) or ''
        end
    end

    fit_n = fit_n + 1
    if fit_n > 256 then table.clear(fit_cache); fit_n = 1; row = nil end
    if not row then row = {}; fit_cache[s] = row end
    row[bucket] = out
    return out
end

-- Two strings sharing one budget (spell -> target, JA -> target). Whichever is
-- short keeps its full width; only the greedy one gets cut. If both overflow
-- they split the space evenly instead of one eating the other.
local function split_fit(a, b, avail)
    if avail <= 0 then return '', '' end
    local wa, wb = text_w(a), text_w(b)
    if wa + wb <= avail then return a, b end
    local half = avail * 0.5
    if wa <= half then return a, fit_text(b, avail - wa) end
    if wb <= half then return fit_text(a, avail - wb), b end
    return fit_text(a, half), fit_text(b, half)
end

local function begin_panel(win_id, px, py, panel_col, accent)
    v_pos[1], v_pos[2] = px, py
    imgui.SetNextWindowPos(v_pos, ImGuiCond_Always)

    v_size[1], v_size[2] = rcache.win_w, 0
    imgui.SetNextWindowSize(v_size, ImGuiCond_Always)

    p_open[1] = true
    if not imgui.Begin(win_id, p_open, FLAGS_LOCKED) then return false, nil, 0 end

    local wx, wy = imgui.GetWindowPos()
    local ww, wh = imgui.GetWindowSize()
    local dl = imgui.GetWindowDrawList()
    if dl then
        -- imgui clips a window's draw list inside half the window padding (left /
        -- right) and the border (top / bottom): the stripe and frame sit on the
        -- edges, so draw them with the whole window rect as the clip rect.
        v_p1[1], v_p1[2] = wx, wy
        v_p2[1], v_p2[2] = wx + ww, wy + wh
        local clipped = pcall(dl.PushClipRect, dl, v_p1, v_p2, false)

        -- Look tab > Panels: tinted (by kind) / dark / clear / framed, times opacity.
        -- Clear keeps a faint neutral plate so the text stays readable.
        local ps = theme.panel_style
        if ps == 'dark' then panel_col = C.PANEL_BG
        elseif ps == 'clear' then panel_col = theme.scale_alpha(C.PANEL_BG, 0.45) end
        dl:AddRectFilled(v_p1, v_p2, theme.scale_alpha(panel_col, theme.panel_alpha), 4.0)
        if ps == 'framed' and accent then
            local fc = theme.scale_alpha(accent, 0.85)
            theme.frect(dl, wx, wy, wx + ww, wy + 1, fc)
            theme.frect(dl, wx, wy + wh - 1, wx + ww, wy + wh, fc)
            theme.frect(dl, wx + ww - 1, wy, wx + ww, wy + wh, fc)
        end
        if accent then
            v_p1[1], v_p1[2] = wx, wy + 2
            v_p2[1], v_p2[2] = wx + theme.px(5), wy + wh - 2
            dl:AddRectFilled(v_p1, v_p2, accent)
        end
        if clipped then pcall(dl.PopClipRect, dl) end
    end
    return true, dl, wh
end

local function draw_menu_panel(px, py)
    local opened, dl, win_h = begin_panel('##thud_menu', px, py, C.PANEL_MENU)
    if opened then
        local base = imgui.GetCursorPosX()
        imgui.SetCursorPosX(base + PANEL_PADDING)
        imgui.SetCursorPosY(imgui.GetCursorPosY() + TOP_PADDING)

        -- Reserve the right-hand cost/recast/charge text, then fit the name to
        -- whatever is left: the numbers matter more than the full spell name.
        local reserve
        if menu_cache.is_charge then
            reserve = SP + text_w(menu_cache.charge_str)
            if menu_cache.next_str ~= '' then reserve = reserve + SP + text_w(menu_cache.next_str) end
        else
            reserve = SP + text_w(menu_cache.recast)
            if menu_cache.cost ~= '' then reserve = reserve + SP + text_w(menu_cache.cost) end
        end

        imgui.TextColored(menu_cache.name_color,
            fit_text(menu_cache.name, base + rcache.bw - imgui.GetCursorPosX() - reserve))

        if menu_cache.is_charge then
            imgui.SameLine()
            imgui.TextColored(menu_cache.charge_color, menu_cache.charge_str)
            if menu_cache.next_str ~= '' then
                imgui.SameLine()
                imgui.TextColored(C.MENU_NOTRDY, menu_cache.next_str)
            end
        else
            if menu_cache.cost ~= '' then
                imgui.SameLine()
                imgui.TextColored(menu_cache.cost_color, menu_cache.cost)
            end
            imgui.SameLine()
            imgui.TextColored(menu_cache.recast_color, menu_cache.recast)
        end

        if menu_cache.on_cd then
            imgui.SetCursorPosX(imgui.GetCursorPosX() + PANEL_PADDING)
            local cx, cy = imgui.GetCursorScreenPos()
            v_size[1], v_size[2] = rcache.bw, CAST_BAR_HEIGHT
            imgui.Dummy(v_size)
            if dl then
                theme.bar(dl, cx, cy, rcache.bw, CAST_BAR_HEIGHT, menu_cache.cd_frac, menu_cache.bar_color)
            end
        end
    end
    imgui.End()
    return win_h
end

------------------------------------------------------------
-- DRAG HANDLE + SETTINGS PANEL
------------------------------------------------------------
local handle_moved = false

local function save_cfg() pcall(settings.save, 'bar') end

local function draw_drag_handle()
    local offset = math.max(rcache.bh, 18) + 10
    if force_handle then
        v_pos[1], v_pos[2] = cfg.pos_x, cfg.pos_y + offset
        imgui.SetNextWindowPos(v_pos, ImGuiCond_Always)
        force_handle = false
    end
    p_open[1] = true
    if imgui.Begin('##thud_handle', p_open, FLAGS_MOVABLE) then
        local wx, wy = imgui.GetWindowPos()
        local ww, wh = imgui.GetWindowSize()
        local dl = imgui.GetWindowDrawList()
        if dl then
            v_p1[1], v_p1[2] = wx, wy
            v_p2[1], v_p2[2] = wx + ww, wy + wh
            dl:AddRectFilled(v_p1, v_p2, C.HANDLE_BG, 4.0)
        end
        imgui.SetCursorPosX(imgui.GetCursorPosX() + PANEL_PADDING)
        imgui.SetCursorPosY(imgui.GetCursorPosY() + TOP_PADDING)
        imgui.TextColored(C.HANDLE_TXT, 'goomui - drag to move  -  re-check Lock when done')

        local nx, ny = math.floor(wx + 0.5), math.floor(wy + 0.5) - offset
        if nx ~= cfg.pos_x or ny ~= cfg.pos_y then
            cfg.pos_x, cfg.pos_y = nx, ny
            handle_moved = true
        end
        -- Save on release, only if the handle moved.
        if handle_moved and imgui.IsMouseReleased(0) then
            handle_moved = false
            save_cfg()
        end
    end
    imgui.End()
end

------------------------------------------------------------
-- MODULE API (lifecycle / settings)
------------------------------------------------------------
function M.init()
    -- HP fill colours come from the shared theme (same gradient as the party list).
    for pct = 0, 100 do HP_COLOR_LUT[pct] = theme.HP_U32[pct] end
    refresh_managers()
end

-- Settings lib hands a NEW table on every character switch; keep that exact
-- table (the lib saves it by reference).
function M.set_cfg(t)
    cfg = t
    update_rcache()
    force_handle = true
end

function M.update_rcache() update_rcache() end

-- Colour preset changed (theme.apply): re-copy colours and recolour HP fills.
function M.retheme()
    C.BAR_DEAD, C.SPELL_BAR, C.ITEM_BAR = theme.U.DEAD, theme.U.SPELL, theme.U.ITEM
    C.MENU_BAR_SP, C.MENU_BAR_JA = theme.U.MENU_SP, theme.U.MENU_JA
    for pct = 0, 100 do HP_COLOR_LUT[pct] = theme.HP_U32[pct] end
    main_target_cache.hp_pct, sub_target_cache.hp_pct = nil, nil
    packet_target_cache.hp_pct, pet.cache.hp_pct = nil, nil
end

-- Where a chart docked under the target bar goes: left x, top y (just below the
-- main target panel; its last drawn height is kept when no target), panel width,
-- HP bar left offset inside the panel, HP bar width.
-- With debuffs_below, under the mob's debuff row when it shows.
function M.anchor()
    return cfg.pos_x, cfg.pos_y + rcache.h_main + (rcache.h_below or 0), rcache.win_w, rcache.bar_dx, rcache.bw
end
function M.force_handle() force_handle = true end

function M.unload()
    main_data = nil
    sub_data  = nil
    reset_cast()
end

------------------------------------------------------------
-- PARTY CACHE
------------------------------------------------------------
local function refresh_party_cache(now)
    if now - last_scan_time < SCAN_INTERVAL then return end
    last_scan_time = now
    local party = mgr.party
    if not party then return end

    table.clear(party_id_cache)
    table.clear(party_masked_cache)

    local sid = party:GetMemberServerId(0)
    self_id_cache  = sid or 0
    self_id_masked = bit.band(self_id_cache, 0xFFFF)
    pos.self_idx   = party:GetMemberTargetIndex(0) or 0
    pos.self_hb    = hitbox_of(mgr.entity, pos.self_idx)
    for i = 0, 17 do
        if party:GetMemberIsActive(i) ~= 0 then
            local sId = party:GetMemberServerId(i)
            if sId and sId ~= 0 then
                party_id_cache[sId] = (i < 6) and 1 or 2
                party_masked_cache[bit.band(sId, 0xFFFF)] = true
            end
        end
    end
end

------------------------------------------------------------
-- PARSE TARGET DATA
------------------------------------------------------------
-- NEAR inside range, MID within mid_pad past it, RED beyond.
local function dist_color_for(dist, near_edge, mid_edge)
    return (dist < near_edge) and C.DIST_NEAR
        or (dist < mid_edge)  and C.DIST_MID
        or C.DIST_RED
end

-- Where the colour changes for this target; fixed 22 / 30 cuts when dynamic_range is off.
local function range_edges(entity, idx)
    if not cfg.dynamic_range then return 22.0, 30.0 end
    local near = RANGE.base + pos.self_hb + hitbox_of(entity, idx)
    return near, near + RANGE.mid_pad
end

-- The string is rebuilt only when the displayed value (tenths of a yalm) changes.
local function update_dist(cache, dist_sq, near_edge, mid_edge)
    local dist = math.sqrt(dist_sq)
    local q    = math.floor(dist * 10.0 + 0.5)   -- quantize to tenths, matches '%.1f'
    if cache.last_dq ~= q then
        cache.last_dq  = q
        cache.dist_str = string.format('%.1f', q * 0.1)   -- format q, not dist, so string and gate never disagree
    end
    cache.dist_color = dist_color_for(dist, near_edge, mid_edge)
end

-- Height is Ashita's Z (SDK position_t order X, Z, Y; XiPackets 0x00E x, z, y). Sign as targetbar had it:
-- self - target, + = target above (the height axis taken to point down). Worth showing because GetDistance is
-- 3D: a mob on a ledge reads far away while standing almost on top of you in ground terms.
local function update_height(cache, entity, idx)
    if idx == 0 or pos.self_idx == 0 then
        cache.hgt_str = nil
        return
    end
    local ty = entity:GetLocalPositionZ(idx)
    local sy = entity:GetLocalPositionZ(pos.self_idx)
    if type(ty) ~= 'number' or type(sy) ~= 'number' then
        cache.hgt_str = nil
        return
    end
    local h = sy - ty
    local q = math.floor(h * 10.0 + 0.5)   -- round half toward +inf, same as the distance gate
    if cache.last_hq ~= q then
        cache.last_hq = q
        cache.hgt_str = string.format('%+.1f', q * 0.1)
    end
    cache.hgt_color = (h > RANGE.up or h < RANGE.down) and C.HEIGHT_WARN or C.HEIGHT_OK
end

local function apply_hp(cache, hp_pct)
    cache.hp_pct    = hp_pct
    cache.hp_str    = PERCENT_STR_LUT[hp_pct] or (tostring(hp_pct) .. '%')
    cache.dead      = (hp_pct == 0)
    cache.hp_frac   = math.max(0.0, math.min(1.0, hp_pct / 100.0))
    cache.bar_color = cache.dead and C.BAR_DEAD
                    or HP_COLOR_LUT[math.max(0, math.min(100, hp_pct))]
end

local function parse_target_data(tIdx, out_cache, _, entity, targ)
    if not tIdx or tIdx == 0 then return nil end

    local cur_name = entity:GetName(tIdx) or 'Unknown'
    local sId      = entity:GetServerId(tIdx) or 0
    if sId == 0 and cur_name == 'Unknown' then return nil end

    local hp_pct  = entity:GetHPPercent(tIdx) or 0
    local spawn   = entity:GetSpawnFlags(tIdx) or 0
    local dist_sq = entity:GetDistance(tIdx)  or 0

    if out_cache.spawn ~= spawn then
        out_cache.spawn  = spawn
        out_cache.is_pc  = bit.band(spawn, 0x01) ~= 0
        out_cache.is_npc = bit.band(spawn, 0x02) ~= 0
        out_cache.is_mob = bit.band(spawn, 0x10) ~= 0
    end
    local is_pc  = out_cache.is_pc
    local is_npc = out_cache.is_npc
    local is_mob = out_cache.is_mob

    local name_color
    local is_real_npc = false
    if is_pc then
        if sId == self_id_cache then
            name_color = C.PC_SELF
        elseif party_id_cache[sId] == 1 then
            name_color = C.PC_PARTY
        elseif party_id_cache[sId] == 2 then
            name_color = C.PC_ALLY
        else
            name_color = C.PC_OTHER
        end
    elseif is_npc and not is_mob then
        name_color  = C.NPC
        is_real_npc = true
    else
        local cs     = entity:GetClaimStatus(tIdx)
        local claim_status = bit.band(cs or 0, 0xFFFF)
        if claim_status == 0 then
            name_color = C.ENEMY
        elseif claim_status == self_id_masked then
            name_color = C.CLAIM
        else
            local by_group = party_masked_cache[claim_status] or false
            name_color = by_group and C.CLAIM or C.STEALTH
        end
    end

    -- Lock-on brackets only for the locked (held <t>) target, not for a cast target picked while locked on.
    -- Ashita libs/ffxi/targets.lua: while sub-targeting, slot 0 is the pick (<st>) and slot 1 the held <t>.
    local is_locked = false
    if targ then
        local lf   = targ:GetLockedOnFlags()
        local held = (targ:GetIsSubTargetActive() ~= 0) and targ:GetTargetIndex(1) or targ:GetTargetIndex(0)
        is_locked  = (lf ~= nil) and (bit.band(lf, 0x01) ~= 0) and held == tIdx
    end

    if out_cache.raw_name ~= cur_name or out_cache.is_locked ~= is_locked then
        out_cache.raw_name     = cur_name
        out_cache.is_locked    = is_locked
        out_cache.display_name = is_locked and ('[' .. cur_name .. ']') or cur_name
    end

    if out_cache.hp_pct ~= hp_pct then apply_hp(out_cache, hp_pct) end

    local near_edge, mid_edge = range_edges(entity, tIdx)
    update_dist(out_cache, dist_sq, near_edge, mid_edge)
    if cfg.show_height then update_height(out_cache, entity, tIdx) else out_cache.hgt_str = nil end

    out_cache.name_color  = name_color
    out_cache.is_real_npc = is_real_npc
    out_cache.is_self     = (sId == self_id_cache)
    out_cache.sid         = sId
    return out_cache
end

local function parse_pet_data(petIdx, c, entity)
    if not petIdx or petIdx == 0 then return nil end
    local sId = entity:GetServerId(petIdx) or 0
    if sId == 0 then return nil end
    local nm = entity:GetName(petIdx) or 'Pet'

    local hp_pct  = entity:GetHPPercent(petIdx) or 0
    local dist_sq = entity:GetDistance(petIdx)  or 0

    if c.raw_name ~= nm then
        c.raw_name     = nm
        c.display_name = nm
    end
    if c.hp_pct ~= hp_pct then apply_hp(c, hp_pct) end
    local near_edge, mid_edge = range_edges(entity, petIdx)
    update_dist(c, dist_sq, near_edge, mid_edge)
    if cfg.show_height then update_height(c, entity, petIdx) else c.hgt_str = nil end
    c.name_color  = C.PC_PARTY
    c.is_real_npc = false
    c.is_mob      = false
    c.is_pet      = true
    c.is_self     = false
    return c
end
pet.parse = parse_pet_data

-- Distance and height are two float reads and a sqrt. Run them every frame
-- rather than on the UPDATE_INTERVAL logic tick: at 0.15s the readout only
-- moves in ~0.7 yalm jumps at walking speed, which defeats the point of
-- showing tenths at all.
local function refresh_pos(cache, idx, entity)
    if not cache or idx == 0 then return end
    local near_edge, mid_edge = range_edges(entity, idx)
    update_dist(cache, entity:GetDistance(idx) or 0, near_edge, mid_edge)
    if cfg.show_height then update_height(cache, entity, idx) else cache.hgt_str = nil end
end

------------------------------------------------------------
-- DRAW: HP BAR
------------------------------------------------------------
-- Panel tint and stripe by target kind (a debuff row takes its target panel's, so they read as one block).
local function panel_colors(data, force_blue)
    if force_blue then             return C.PANEL_BLUE, C.ACC_BLUE
    elseif data.is_pet then        return C.PANEL_PET,  C.ACC_PET
    elseif data.is_real_npc then   return C.PANEL_NPC,  C.ACC_NPC
    elseif data.is_mob then        return C.PANEL_MOB,  C.ACC_MOB
    elseif data.is_pc then         return C.PANEL_PC,   C.ACC_PC
    end
    return C.PANEL_BG, nil
end

local function draw_bar(data, win_id, pos_x, pos_y, bar_h, is_sub, force_blue, menu_text, bar_width, show_distance, show_height)
    local panel_col, accent = panel_colors(data, force_blue)
    local opened, dl, win_h = begin_panel(win_id, pos_x, pos_y, panel_col, accent)
    local npc_pad = 0
    if opened then
        local base = imgui.GetCursorPosX()
        imgui.SetCursorPosX(base + PANEL_PADDING)
        imgui.SetCursorPosY(imgui.GetCursorPosY() + TOP_PADDING)

        if show_distance and not data.is_self then
            imgui.TextColored(data.dist_color, data.dist_str)
            imgui.SameLine()
        end

        if show_height and data.hgt_str and not data.is_self then
            imgui.TextColored(data.hgt_color, data.hgt_str)
            imgui.SameLine()
        end

        if not data.is_real_npc then
            if data.dead then
                imgui.TextColored(C.DEAD_TXT, 'DEAD')
            else
                imgui.TextColored(C.HP_TXT, data.hp_str)
            end
            imgui.SameLine()
        end

        if force_blue and menu_text and menu_text ~= '' then
            imgui.TextColored(C.MENU_TXT, menu_text)
            imgui.SameLine()
        end

        -- Name is last on the line, so the cursor already accounts for the
        -- distance / height / HP / menu-hint prefixes: fit to what is left.
        local line_y = imgui.GetCursorPosY()
        imgui.TextColored(data.name_color,
            fit_text(data.display_name, base + bar_width - imgui.GetCursorPosX()))

        -- Bar left edge, computed without moving the cursor: a SetCursorPos with no item after it trips
        -- ImGui's "SetCursorPos to extend window boundaries" check (the NPC panel below submits nothing).
        local cx, cy = imgui.GetCursorScreenPos()
        cx = cx + PANEL_PADDING
        if not is_sub then rcache.bar_dx = cx - pos_x end

        -- Non-mob NPCs have no HP to show: name line only, no empty bar. npc_pad = the height the bar row
        -- would have taken (bar + item spacing), so the docked chart under main does not jump.
        if data.is_real_npc then
            npc_pad = bar_h + math.max(0, imgui.GetCursorPosY() - line_y - imgui.GetFontSize())
        else
            imgui.SetCursorPosX(imgui.GetCursorPosX() + PANEL_PADDING)
            v_size[1], v_size[2] = bar_width, bar_h
            imgui.Dummy(v_size)
            if dl then theme.bar(dl, cx, cy, bar_width, bar_h, data.hp_frac, data.bar_color) end
        end
    end
    imgui.End()
    return win_h, npc_pad
end

-- Debuffs on a mob target: their own row on its target panel, in that panel's colours (force_blue as the panel
-- had it). Above the panel by default, under it with cfg.debuffs_below. Main target and sub-target each get their
-- own (win_id, rcache height key). A DEBUFF_GAP splits the row from the next panel up.
local function debuff_shown(data)
    return data and data.is_mob and cfg.show_debuffs and mobdebuff.has(data.sid)
end
local function draw_debuff_row(data, px, top, bar_width, win_id, hkey, force_blue)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, DEBUFF_PAD) -- slim: 2px above / below the icons
    local panel_col, accent = panel_colors(data, force_blue)
    local opened, dl, win_h = begin_panel(win_id, px, top, panel_col, accent)
    if opened then
        crumb.sub('target bar: debuff icons')
        mobdebuff.draw(dl, data.sid, rcache.bar_dx - DEBUFF_PAD[1], bar_width, rcache.icon or 18, data.raw_name)
        crumb.back()
    end
    imgui.End()
    imgui.PopStyleVar(1)
    if win_h and win_h > 0 then rcache[hkey] = win_h end
end

------------------------------------------------------------
-- DRAW: CAST BAR
------------------------------------------------------------
local function draw_cast_bar(cast_frac, pos_x, pos_y, bar_width)
    local opened, dl, win_h = begin_panel('##thud_cast', pos_x, pos_y,
        cast_state.is_item and C.PANEL_ITEM or C.PANEL_CAST)
    if opened then
        local base = imgui.GetCursorPosX()
        imgui.SetCursorPosX(base + PANEL_PADDING)
        imgui.SetCursorPosY(imgui.GetCursorPosY() + TOP_PADDING)

        local done = cast_state.done_at > 0
        local pct = (cast_frac > 0) and CAST_PERCENT_STR_LUT[math.floor(cast_frac * 100)] or nil
        if done then pct = cast_state.done_ok and ' done' or ' interrupted' end

        -- The percent is the whole point of the bar, so it gets its width first
        -- (measured against ' 100%' so the layout does not shift at 100).
        local avail = base + bar_width - imgui.GetCursorPosX() - text_w(' -> ') - SP * 2
        if pct then avail = avail - math.max(text_w(' 100%'), text_w(pct)) - SP end

        local nm, tgt = split_fit(
            cast_state.name ~= '' and cast_state.name or (cast_state.is_item and 'Item' or 'Action'),
            cast_state.display_target, avail)

        imgui.TextColored(cast_state.bar_color_txt, nm)
        imgui.SameLine()
        imgui.TextColored(C.ARROW, ' -> ')
        imgui.SameLine()
        imgui.TextColored(cast_state.target_color, tgt)

        if pct then
            imgui.SameLine()
            imgui.TextColored(done and (cast_state.done_ok and C.MENU_READY or C.MENU_NOTRDY) or C.HP_TXT, pct)
        end

        imgui.SetCursorPosX(imgui.GetCursorPosX() + PANEL_PADDING)
        local cx, cy = imgui.GetCursorScreenPos()

        v_size[1], v_size[2] = bar_width, CAST_BAR_HEIGHT
        imgui.Dummy(v_size)

        if dl then
            theme.bar(dl, cx, cy, bar_width, CAST_BAR_HEIGHT, cast_frac,
                (done and not cast_state.done_ok) and C.BAR_DEAD
                or (cast_state.is_item and C.ITEM_BAR or C.SPELL_BAR))
        end
    end
    imgui.End()
    return win_h
end

------------------------------------------------------------
-- DRAW: JA FLASH BAR
------------------------------------------------------------
local function draw_ja_bar(pos_x, pos_y)
    local opened, _, win_h = begin_panel('##thud_ja', pos_x, pos_y, C.PANEL_JA)
    if opened then
        local base = imgui.GetCursorPosX()
        imgui.SetCursorPosX(base + PANEL_PADDING)
        imgui.SetCursorPosY(imgui.GetCursorPosY() + TOP_PADDING)

        local nm, tgt = split_fit(ja_state.name, ja_state.display_target,
            base + rcache.bw - imgui.GetCursorPosX() - text_w(' -> ') - SP * 2)

        imgui.TextColored(C.JA_TXT, nm)
        imgui.SameLine()
        imgui.TextColored(C.ARROW, ' -> ')
        imgui.SameLine()
        imgui.TextColored(ja_state.target_color, tgt)
    end
    imgui.End()
    return win_h
end

------------------------------------------------------------
-- ITEM NAME LOOKUP
------------------------------------------------------------
local function resolve_item_name(data)
    local slot      = struct.unpack('B', data, 15)
    local container = struct.unpack('B', data, 17)
    local inv       = mgr.inv

    if not inv then return 'Item', nil end
    local item = inv:GetContainerItem(container, slot)

    if not item then return 'Item', nil end
    local r = rm:GetItemById(item.Id)

    return (r and r.Name[1]) or 'Item', r
end

------------------------------------------------------------
-- PACKETS
------------------------------------------------------------
function M.packet_in(e)
    if e.id == 0x028 then
        if e.size < 0x1D then return end   -- header + one target + first result (value ends at bit 230)

        -- Actor id (bits 40-71) first: most 0x028 traffic is other actors.
        local me = self_id_cache
        if me == 0 then
            local pt = mgr.party
            me = pt and pt:GetMemberServerId(0) or 0
        end
        if me == 0 or struct.unpack('I', e.data_modified, 0x06) ~= me then return end

        local b10 = struct.unpack('B', e.data_modified, 0x0B)
        local cat = math.floor(b10 / 4) % 16          -- category: bits 82-85

        if cat == 8 or cat == 9 then
            -- Magic (8) / item (9) start-or-interrupt. Param: bits 86-101.
            local param = math.floor(b10 / 64)
                        + struct.unpack('B', e.data_modified, 0x0C) * 4
                        + (struct.unpack('B', e.data_modified, 0x0D) % 64) * 1024
            -- XiPackets 0x0028: cmd_no 8 result value = spell id, cmd_no 9 = item id
            -- (0 when interrupted). First result's value: bits 213-229.
            -- Only an echo of the same kind (and id, when known) may confirm or cancel a pending
            -- attempt, so a spell 'begin' never confirms an item the server refused.
            local is_item_pkt = (cat == 9)
            if param == ACT_INTERRUPT then
                if pending_cast_state.name ~= '' and pending_cast_state.is_item == is_item_pkt then
                    pending_cast_state.name      = ''
                    pending_cast_state.confirmed = false
                end
                if cast_state.name ~= '' and cast_state.is_item == is_item_pkt and cast_state.done_at == 0 then
                    mark_done(false)
                end
            elseif param == ACT_BEGIN and pending_cast_state.name ~= ''
            and pending_cast_state.is_item == is_item_pkt then
                local id  = pending_cast_state.action_id
                local val = ashita.bits.unpack_be(e.data_raw, 0, 213, 17)
                if id == nil or val == id then
                    pending_cast_state.confirmed = true
                end
            end
        elseif cat == 4 or cat == 5 then
            -- Magic (4) / item (5) finished. XiPackets 0x0028: cmd_arg = spell id /
            -- item id (low 16 bits read here). The matching bar is held as done;
            -- a cast so fast it never got a bar (still pending) is shown as done.
            -- A pending action of another id is left alone (chain casting: the
            -- finish for A can arrive after B was sent).
            local id = math.floor(b10 / 64)
                     + struct.unpack('B', e.data_modified, 0x0C) * 4
                     + (struct.unpack('B', e.data_modified, 0x0D) % 64) * 1024
            local is_item_pkt = (cat == 5)
            if cast_state.name ~= '' and cast_state.done_at == 0 and cast_state.is_item == is_item_pkt
            and (cast_state.action_id == nil or cast_state.action_id == id) then
                mark_done(true)
            elseif pending_cast_state.name ~= '' and pending_cast_state.is_item == is_item_pkt
            and (pending_cast_state.action_id == nil or pending_cast_state.action_id == id) then
                promote_pending()
                cast_state.time_driven = false
                cast_state.start_time  = os.clock()
                pending_cast_state.name, pending_cast_state.confirmed = '', false
                mark_done(true)
            end
        elseif (cat == 6 or cat == 14 or cat == 15) and ja_pending.deadline > 0 then
            local jnow = os.clock()
            if jnow >= ja_pending.deadline then
                ja_pending.deadline = 0
            else
                ja_state.name           = ja_pending.name
                ja_state.display_target = ja_pending.display_target
                ja_state.target_color   = ja_pending.target_color
                ja_state.expires        = jnow + (tonumber(cfg.cast_linger) or JA_BAR_LINGER)
                ja_pending.deadline     = 0
            end
        end
    elseif e.id == 0x00A then
        reset_cast()
        cb_alive               = false
        sub_target_persistence = 0
        sub_target_expires     = 0
        last_main_idx          = -1
        last_sub_idx           = -1
        last_logic_update      = 0
        last_scan_time         = 0
        self_id_cache          = 0
        self_id_masked         = 0
        last_menu_text         = ''
        last_raw_menu_text     = ''
        ja_state.expires       = 0
        ja_pending.deadline    = 0
        main_data              = nil
        sub_data               = nil
        refresh_managers()
    end
end

function M.packet_out(e)
    if e.id ~= 0x1A and e.id ~= 0x37 then return end
    if e.size < 0x0E then return end

    -- ActIndex: 0x1A at 0x08, 0x37 at 0x0C (XiPackets GP_CLI_ACTION / GP_CLI_ITEM_USE). Items are used
    -- through 0x37 only (0x1A ActionID 5 is /help).
    local target_idx = struct.unpack('H', e.data_modified, (e.id == 0x1A) and 0x09 or 0x0D)
    local category   = (e.id == 0x1A) and struct.unpack('H', e.data_modified, 0x0B) or 0
    local action_id  = (e.id == 0x1A) and struct.unpack('H', e.data_modified, 0x0D) or 0

    local entity_mgr = mgr.entity

    if e.id == 0x1A and category == 9 then
        local r  = rm:GetAbilityById(action_id + 512)
        local nm = r and r.Name[1]
        if nm and nm ~= '' then
            local t_name, t_color = 'Self', C.PC_SELF
            if target_idx ~= 0 and entity_mgr then
                local tdata = parse_target_data(target_idx, packet_target_cache, false, entity_mgr, mgr.targ)
                if tdata then
                    t_name  = tdata.display_name
                    t_color = tdata.name_color
                end
            end
            ja_pending.name           = nm
            ja_pending.display_target = t_name
            ja_pending.target_color   = t_color
            ja_pending.deadline       = os.clock() + 3.0
        end
        return
    end

    local action_name, is_item, cast_secs, sent_id = '', false, nil, nil
    if e.id == 0x1A and category == 3 then
        local r = rm:GetSpellById(action_id)
        if r then
            action_name = r.Name[1] or ''
            cast_secs   = resource_cast_seconds(r)
            sent_id     = action_id
        end
    elseif e.id == 0x37 then
        local r
        action_name, r = resolve_item_name(e.data_modified)
        sent_id   = r and r.Id or nil
        is_item   = true
        cast_secs = resource_cast_seconds(r)
    end

    if is_excluded_text(string.lower(action_name)) then return end

    if action_name == '' or action_name == 'Gil' then return end

    local target_name  = 'Self'
    local target_color = C.PC_SELF
    if target_idx ~= 0 and entity_mgr then
        local tdata = parse_target_data(target_idx, packet_target_cache, false, entity_mgr, mgr.targ)
        if tdata then
            target_name  = tdata.display_name
            target_color = tdata.name_color
        end
    end

    pending_cast_state.name          = action_name
    pending_cast_state.target_color  = target_color
    pending_cast_state.target_idx    = target_idx
    pending_cast_state.is_item       = is_item
    pending_cast_state.display_target= target_name
    pending_cast_state.bar_color_txt = is_item and C.ITEM_TXT or C.SPELL_TXT
    pending_cast_state.duration      = cast_secs or 0
    pending_cast_state.action_id     = sent_id
    pending_cast_state.confirmed     = false   -- attempt only; server has not committed yet
    pending_time                     = os.clock()
end

------------------------------------------------------------
-- RENDER
------------------------------------------------------------
function M.render()
    if not is_game_active() then return end

    local now = os.clock()
    local dt  = now - cast_state.last_present
    if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
    cast_state.last_present = now
    local px  = cfg.pos_x
    local bw  = rcache.bw
    local bh  = rcache.bh

    -- Slow tick: ability recast peaks, and the mount timer armed on the Mount status (buff 252) 0->1 edge.
    if now - mount.chk >= mount.interval then
        mount.chk = now
        if mgr.recast then sample_recast_peaks(mgr.recast) end
        local mpl = mgr.player
        if mpl and mpl:GetIsZoning() == 0 then
            local is_mounted = false
            local buffs = mpl:GetBuffs()
            if buffs then
                for _, b in pairs(buffs) do
                    if b == 252 then
                        is_mounted = true
                        break
                    end
                end
            end
            local cur = is_mounted and 1 or 0
            if cur ~= 0 and mount.id == 0 then
                mount.cd_until = now + mount.recast
            end
            mount.id = cur
        end
    end

    local cb        = mgr.cb
    local cast_frac = (cb and cb:GetPercent()) or 0

    local cast_rising = (last_cast_frac < CAST_IDLE_EPS and cast_frac >= CAST_IDLE_EPS)
    if cast_rising then
        cast_rise_pending = true
        cast_rise_time    = now
    end

    -- Castbar-driven promotion also needs the server's matching 'begins' echo:
    -- the castbar can be moving for another action (chain cast, item refused
    -- mid-cast), and an unconfirmed attempt must never take its name.
    if pending_cast_state.name ~= '' and pending_cast_state.confirmed and cast_frac > 0
    and (cast_rising
         or last_cast_frac - cast_frac > CAST_RESTART_DROP
         or (cast_rise_pending and now - cast_rise_time <= CAST_RISE_GRACE)) then
        promote_pending()
        cast_state.time_driven       = false
        cast_state.start_time        = now
        pending_cast_state.name      = ''
        pending_cast_state.confirmed = false
        cb_alive                     = true
        cast_rise_pending            = false
    end

    if cast_rising and pending_cast_state.name == '' and cast_finished_time > 0 then
        reset_cast()
    end

    -- Fallback (time-driven) promotion needs the server's 'begins' echo (0x028 cat 8/9, param 24931): an
    -- attempt the server rejects never confirms, so it never paints a bar.
    if pending_cast_state.name ~= ''
    and pending_cast_state.confirmed
    and (now - pending_time) >= FALLBACK_GRACE
    and (pending_cast_state.is_item or not cb_alive) then
        promote_pending()
        cast_state.time_driven   = true
        cast_state.start_time    = pending_time
        cast_state.duration      = (pending_cast_state.duration > 0)
                                   and pending_cast_state.duration or FALLBACK_CAST_TIME
        pending_cast_state.name      = ''
        pending_cast_state.confirmed = false
    elseif pending_cast_state.name ~= ''
    and not pending_cast_state.confirmed
    and (now - pending_time) > PENDING_TTL then
        -- Attempt never committed (no confirm, no castbar rise): forget it so
        -- it cannot be promoted later by an unrelated confirmation.
        pending_cast_state.name = ''
    end

    if cast_frac > 0 then
        cast_state.started = true
    end
    local disp_frac = cast_frac
    if cast_state.time_driven then
        if cast_frac > 0 then
            cast_state.time_driven = false
            cb_alive               = true
        else
            local d = cast_state.duration
            disp_frac = (d > 0) and math.min(1.0, (now - cast_state.start_time) / d) or 0
        end
    end

    if cast_state.name ~= '' and cast_state.done_at == 0 and disp_frac > 0 and disp_frac < 1.0 then
        if math.abs(disp_frac - last_disp_frac) > 0.001 then
            last_frac_change_time = now
        elseif (now - last_frac_change_time > 0.25) then
            reset_cast()
        end
    end
    last_cast_frac = cast_frac
    last_disp_frac = disp_frac

    -- Frame-rate-independent smoothing of the cast fill (cb:GetPercent() steps coarsely): ease a render-only
    -- fraction toward disp_frac; snap on a new cast (start_time edge) and when idle / complete.
    if cast_state.name == '' then
        cast_state.render_frac   = 0.0
        cast_state.cr_last_start = cast_state.start_time
    elseif disp_frac <= 0.0 or disp_frac >= 1.0 then
        cast_state.render_frac   = disp_frac
        cast_state.cr_last_start = cast_state.start_time
    elseif cast_state.start_time ~= cast_state.cr_last_start then
        cast_state.cr_last_start = cast_state.start_time
        cast_state.render_frac   = disp_frac
    else
        local a  = dt / (dt + 0.06)   -- 1-pole low-pass, tau=0.06s
        local rf = cast_state.render_frac + (disp_frac - cast_state.render_frac) * a
        if rf < 0.0 then rf = 0.0 elseif rf > 1.0 then rf = 1.0 end
        cast_state.render_frac = rf
    end

    if cast_state.done_at > 0 then
        -- Held after the server's finish / interrupt; a new cast replaces it
        -- (promote_pending clears done_at).
        if now - cast_state.done_at >= (tonumber(cfg.cast_linger) or 2.5) then reset_cast() end
    elseif cast_state.name ~= '' then
        if (now - cast_state.start_time > 10.0) then
            reset_cast()
        elseif not cast_state.started and (now - cast_state.start_time > 0.5) then
            reset_cast()
        elseif disp_frac >= 1.0 then
            -- Full but no finish echo matched yet: give it FINISH_DELAY, then drop.
            if cast_finished_time == 0 then cast_finished_time = now
            elseif now - cast_finished_time >= FINISH_DELAY then reset_cast() end
        elseif disp_frac > 0 and disp_frac < 1.0 then
            cast_finished_time = 0
        elseif cast_finished_time > 0 and (now - cast_finished_time >= FINISH_DELAY) then
            reset_cast()
        end
    end

    local has_cast = cast_state.name ~= ''
    local targ     = mgr.targ
    local entity   = mgr.entity

    if targ and entity then
        -- Ashita libs/ffxi/targets.lua: while sub-targeting, slot 0 is the pick (<st>) and slot 1 the held <t>.
        -- Main panel = held <t>, sub panel = the <st> pick.
        local sub_raw         = targ:GetIsSubTargetActive()
        local main_idx        = (sub_raw ~= 0) and targ:GetTargetIndex(1) or targ:GetTargetIndex(0)
        local current_sub_idx = (sub_raw ~= 0) and targ:GetTargetIndex(0) or 0
        local sub_idx
        if sub_raw ~= 0 and current_sub_idx ~= 0 then
            sub_target_persistence = current_sub_idx
            sub_target_expires     = now + 2.0
        end
        if now < sub_target_expires then
            sub_idx = sub_target_persistence
        else
            sub_idx                = 0
            sub_target_persistence = 0
        end

        if (now - last_logic_update > UPDATE_INTERVAL)
        or (main_idx ~= last_main_idx)
        or (sub_idx  ~= last_sub_idx) then
            last_logic_update = now
            last_main_idx     = main_idx
            last_sub_idx      = sub_idx
            refresh_party_cache(now)

            crumb.sub('target bar: menu help read')
            local raw_text = GetMenuHelpText()
            crumb.back()
            if raw_text ~= last_raw_menu_text then
                last_raw_menu_text = raw_text
                -- no letter or digit (spaces, control bytes): nothing to show, not an empty '( )'
                if not string.find(raw_text, '%w') then
                    last_menu_text = ''
                else
                    last_menu_text = is_excluded_text(string.lower(raw_text))
                        and '' or ('(' .. raw_text .. ')')
                end
            end

            main_data = (main_idx ~= 0)
                and parse_target_data(main_idx, main_target_cache, false, entity, targ) or nil

            sub_data  = (sub_idx ~= 0)
                and parse_target_data(sub_idx, sub_target_cache, true, entity, targ) or nil

            local party = mgr.party
            local self_idx = party and party:GetMemberTargetIndex(0) or 0
            local pet_idx  = (cfg.show_pet and self_idx ~= 0)
                and (entity:GetPetTargetIndex(self_idx) or 0) or 0
            pet.data = (pet_idx ~= 0) and pet.parse(pet_idx, pet.cache, entity) or nil
            pet.idx  = pet_idx
        end

        if cfg.show_distance or cfg.show_height then
            refresh_pos(main_data, main_idx, entity)
            refresh_pos(sub_data,  sub_idx,  entity)
            refresh_pos(pet.data,  pet.idx,  entity)
        end
    else
        main_data = nil
        sub_data  = nil
        pet.data  = nil
    end

    -- Panels stack upward from pos_y: target at the bottom, the rest above it. With cfg.debuffs_below each mob's
    -- debuff row goes under its target panel instead of above it.
    local below = cfg.debuffs_below
    local y = cfg.pos_y
    rcache.h_below = 0

    if main_data then
        -- Blue = the target being picked: the sub panel while sub-targeting, else main when a target menu is up.
        local force_blue = (sub_data == nil) and (last_menu_text ~= '')
        local mh, npc_pad = draw_bar(main_data, '##thud_main', px, y,
            bh, false, force_blue, last_menu_text, bw, cfg.show_distance, cfg.show_height)
        rcache.h_main = mh and (mh + npc_pad) or rcache.h_main
        if debuff_shown(main_data) then
            if below then
                draw_debuff_row(main_data, px, y + rcache.h_main, bw, '##thud_debuff', 'h_debuff', force_blue)
                rcache.h_below = rcache.h_debuff
            else
                y = y - rcache.h_debuff
                draw_debuff_row(main_data, px, y, bw, '##thud_debuff', 'h_debuff', force_blue)
                y = y - DEBUFF_GAP
            end
        end
    end

    if pet.data then
        y = y - pet.bar_h
        pet.bar_h = draw_bar(pet.data, '##thud_pet', px, y,
            bh, false, false, nil, bw, cfg.show_distance, cfg.show_height) or pet.bar_h
    end

    if sub_data then
        -- same mob as the main target: its row is already on the main panel
        local sub_db = not (main_data and main_data.sid == sub_data.sid) and debuff_shown(sub_data)
        local db_top
        if sub_db and below then -- row first (under the sub panel), gap below it
            y = y - DEBUFF_GAP - rcache.h_debuff_sub
            db_top = y
        end
        y = y - rcache.h_sub
        rcache.h_sub = draw_bar(sub_data, '##thud_sub', px, y,
            bh, true, true, last_menu_text, bw, cfg.show_distance, cfg.show_height) or rcache.h_sub
        if sub_db then
            if not below then
                y = y - rcache.h_debuff_sub
                db_top = y
                y = y - DEBUFF_GAP
            end
            draw_debuff_row(sub_data, px, db_top, bw, '##thud_debuff_sub', 'h_debuff_sub', true)
        end
    end

    -- Also at 100% before the server's finish arrives, so the bar does not blink out.
    if has_cast and (cast_state.done_at > 0 or disp_frac > 0) then
        y = y - rcache.h_cast
        rcache.h_cast = draw_cast_bar((cast_state.done_at > 0) and cast_state.done_frac or cast_state.render_frac,
            px, y, bw) or rcache.h_cast
    end

    if cfg.show_jabar and now < ja_state.expires then
        y = y - rcache.h_ja
        rcache.h_ja = draw_ja_bar(px, y) or rcache.h_ja
    end

    if cfg.show_menuinfo then
        if now - last_menu_update > MENU_UPDATE then
            last_menu_update = now
            rebuild_menu_info()
        end
        if menu_cache.active then
            y = y - rcache.h_menu
            rcache.h_menu = draw_menu_panel(px, y) or rcache.h_menu
        end
    end

    if not cfg.locked then draw_drag_handle() end
end

return M
