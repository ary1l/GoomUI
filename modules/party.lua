--[[
    goomui: party module. Was the standalone goomUI 1.6.0 addon;
    now loaded by goomui.lua next to the bar / ring / AAEV modules. Bars use theme.lua.
    Lean party + alliance list for Ashita v4.
    Based on XivParty: Tylas (Windower original), Tirem (Ashita port). See LICENSE-XivParty.
    Debuff ids: debuffs.lua (from XIUI bufftable.lua + 5 corrections). Buffs shown in game order.

    Render: one ID3DXSprite pass (bars, icons, borders) then Ashita font objects with
    text = Thorny's gdifonts objects (manual, not auto-rendered); their textures are drawn in the same sprite pass,
    after bars/icons. Ashita font objects were dropped in 1.3: perf showed each creation batch stalling frames.
    Text textures are built white and tinted by the sprite Draw colour, so colour/fade changes never rebuild them.

    Sources:
      0x0076 layout ................... atom0s XiPackets world/server/0x0076
      0x00DD GP_GROUP_ATTR bits ....... atom0s XiPackets (leader 0x04, a.leader 0x08, QM 0x10, a.QM 0x20, sync 0x100)
      0x000A / 0x000B ................. atom0s XiPackets (0x000B LogoutState 4 = cancelled, stays in zone)
      IParty / statusiconsentry_t ..... Ashita v4 SDK ffxi/party.h
      recast loop / names ............. Ashita 'recast' addon (atom0s)
      hide-UI sigs, mouse position .... modules/ui.lua (Tirem statushelpers / Velyn; atom0s crosshair)
      ManualRender + get_text_size .... Ashita 'equipmon' addon (atom0s)
      sprite Draw colour .............. alpha scaling as Ashita 'equipmon' (atom0s); RGB tint as this addon's bar fills
      gdifonts destroy_interface ...... libs/gdifonts/readme.md (Thorny): required on unload
      Distance squared ................ Ashita 'distance' addon; XIUI partylist
      <stpt> cursor / t / st .......... XIUI libs/target.lua; Ashita libs/ffxi/targets.lua
      icon override 623 -> 62 ......... XIUI libs/texturemanager.lua
      20.8' Cure range, 50' target .... FFXIclopedia "Distance"
]]--

require('common');
local chat     = require('chat');
local ffi      = require('ffi');
local d3d      = require('d3d8');
local imgui    = require('imgui');
local settings = require('settings');
local scaling  = require('scaling');
local socket   = require('socket');
local theme    = require('modules/theme');
local ui       = require('modules/ui');
local crumb    = require('modules/crumb'); -- crash marker steps (modules/crumb.lua)

local M = { };

-------------------------------------------------------------------------------
-- settings (per character: config/addons/goomui/<Name_Id>/settings.lua)
-------------------------------------------------------------------------------
local defaults = T{
    lowfi        = false, -- alt profile: 250 ms poll, no distance, no hover/receive (still sends crew data)
    updateMs     = 50,
    lofiMs       = 250,
    hideSolo     = false,
    hideAlliance = false,
    hideCutscene = true,
    group        = true,  -- dragging one list moves all three
    font         = 'Arial',
    textScale    = 1.0,   -- text size multiplier
    barW         = 200,
    layoutVer    = 1,     -- one-time migrations of saved layout values (missing key -> 1)
    castRange    = 21.8,  -- FFXIclopedia: most spells 21.8' (varies w/ target size); Cure ~20.8'
    targetRange  = 50,    -- FFXIclopedia: max draw/target 50'
    showDist     = true,
    showBuffs    = true,
    debuffLine   = true,  -- debuffs on their own icon line (closest to the list), XIUI-style
    buffRight    = false,
    buffSize     = 16,
    buffsPerRow  = 12,
    buffGap      = 6,     -- px between the list edge and the buff icons (raise if big text overlaps)
    whitelist    = false,
    filters      = T{ },  -- [buffId] = true
    jobColors    = true,  -- main/sub job text in GoomSwap's job colours (theme.JOB_ARGB)
    leaderStar   = true,  -- star after party / alliance leader names
    crewShare    = true,  -- send own recasts to other goomui boxes (localhost UDP)
    crewHover    = true,  -- show crew recasts on hover
    lofiHover    = false, -- low-fi: hover is opt-in (needs rx socket)
    allyStack    = true,  -- snap: alliances stacked above party (false = side by side)
    crewPort     = 37810, -- uses crewPort .. crewPort+7
    party        = T{ x = -1, y = -1, scale = 1.0 },
    alliance1    = T{ x = -1, y = -1, scale = 0.9 },
    alliance2    = T{ x = -1, y = -1, scale = 0.9 },
    color        = T{
        hp      = 0xFFE07070, -- (unused since 1.4: HP bar uses the targetbar gradient LUT)
        mp      = 0xFF3F7FE8, -- MP bar: blue
        tp      = 0xFF6A63D6, -- TP bar: purple-blue
        tpReady = 0xFF968CFF, -- TP bar at 1000+: brighter purple-blue
        tpText1k = 0xFF60E060, -- TP number at 1000+ (green)
        tpText3k = 0xFFFFD040, -- TP number at 3000 (gold)
        debuffBg = 0xFFFF2828, -- frame drawn over debuff icons
        plate    = 0x99000000, -- dark plate behind numbers inside bars
        mpText   = 0xFF9CC8FF, -- MP number (light blue)
        barBg   = 0xC0181818,
        target  = 0x50FFFFFF,
        sub     = 0x604080FF, -- sub-target row fill (under the bars)
        subFrame = 0xFF60A8FF, -- sub-target row frame (over bars and icons)
        leader  = 0xFFFFD040, -- party leader name
        aLeader = 0xFFFF9030, -- alliance leader name
        qm      = 0xFF40E060, -- party quartermaster border
        aQm     = 0xFF40E0C0, -- alliance quartermaster border
    },
};

local S = settings.load(defaults);


-------------------------------------------------------------------------------
-- shared state
-------------------------------------------------------------------------------
local mm       = AshitaCore:GetMemoryManager();
local resMgr   = AshitaCore:GetResourceManager();
local listKeys = { [0] = 'party', 'alliance1', 'alliance2' };
local floor    = math.floor;
local setup    = false;
local visible  = false;
local zoning   = false;
local zoneHold = 0;
local lastTick = 0;
local tickNow = 0; -- ms, set each tick

-- /goomui perf: 10 s tick / draw timing report.
local perf = { on = false, stop = 0, tickMax = 0, tickSum = 0, tickN = 0, drawMax = 0, drawSum = 0, drawN = 0 };

-- Errors inside the frame callbacks are caught and printed at most once per 10 s (no chat spam).
local errNext = 0;
local function reportErr(where, err)
    local now = ashita.time.get_tick64();
    if (now < errNext) then return; end
    errNext = now + 10000;
    local n = 0; -- message, then the Lua stack when there is one (xpcall + debug.traceback), max 10 lines
    for line in tostring(err):gmatch('[^\n]+') do
        n = n + 1;
        if (n > 10) then break; end
        line = (line:gsub('^%s+', ''):gsub('^.-[\\/]addons[\\/]', ''));
        print(chat.header(addon.name):append((n == 1) and chat.error(('%s error: %s'):fmt(where, line)) or chat.message(line)));
    end
end

-- row geometry (unscaled px)
local P = { h = 50, jw = 50, x0 = 56 };
local A = { h = 26, jw = 30, x0 = 34 };
-- low-fi: one text line per member, no bars
local PL = { h = 40, w = 236 };
local AL = { h = 18, w = 248 };
local function pW() return P.x0 + S.barW; end
local function aBW() return floor(S.barW * 0.85); end
local function aW() return A.x0 + aBW(); end
local function fsz(px, s) return math.max(6, floor(px * s + 0.5)); end

local jobCache, zoneCache = {}, {};
local function jobName(id)
    local s = jobCache[id];
    if (s == nil) then s = resMgr:GetString('jobs.names_abbr', id) or ''; jobCache[id] = s; end
    return s;
end
-- job text colour: the job's GoomSwap colour, or dflt (setting off / no job)
local function jobArgb(id, dflt)
    if (not S.jobColors) then return dflt; end
    return theme.JOB_ARGB[jobName(id)] or dflt;
end
local function zoneName(id)
    local s = zoneCache[id];
    if (s == nil) then s = resMgr:GetString('zones.names', id) or '?'; zoneCache[id] = s; end
    return s;
end

local function hpColor(p)
    if (p > 75) then return 0xFFFFFFFF; end
    if (p > 50) then return 0xFFFFFF80; end
    if (p > 25) then return 0xFFFFA040; end
    return 0xFFFF5050;
end

-- HP number gradient (low-fi text). Bar fills use theme.HP_ARGB.
-- Precomputed once as 0xAARRGGBB: no per-tick color math or allocation.
local function gradLUT(stops)
    local lut = {};
    for pct = 0, 100 do
        local f = pct / 100;
        local r, g, b = stops[#stops][2], stops[#stops][3], stops[#stops][4];
        for i = 1, #stops - 1 do
            local hi, lo = stops[i], stops[i + 1];
            if (f <= hi[1] and f >= lo[1]) then
                local t = (hi[1] - lo[1] > 0) and (f - lo[1]) / (hi[1] - lo[1]) or 0;
                r, g, b = lo[2] + (hi[2] - lo[2]) * t, lo[3] + (hi[3] - lo[3]) * t, lo[4] + (hi[4] - lo[4]) * t;
                break;
            end
        end
        lut[pct] = 0xFF000000 + floor(r * 255 + 0.5) * 0x10000 + floor(g * 255 + 0.5) * 0x100 + floor(b * 255 + 0.5);
    end
    return lut;
end
local HP_TXT_LUT = gradLUT({ { 1.00, 0.35, 0.95, 0.35 }, { 0.75, 0.75, 0.95, 0.25 }, { 0.50, 1.00, 0.85, 0.20 },
                             { 0.25, 1.00, 0.55, 0.15 }, { 0.00, 1.00, 0.25, 0.25 } });
local function lutPct(p) return (p < 0) and 0 or ((p > 100) and 100 or floor(p)); end

-- distance text: green <= cast range (21.8'), yellow up to 50', grey beyond / unknown
local function distColor(d)
    if (d == nil or d > S.targetRange) then return 0xFF909090; end
    if (d > S.castRange) then return 0xFFFFE040; end
    return 0xFF50E050;
end

-- low-fi number colors (targetbar-like): MP blue; TP light blue < 1000, blue 1000+, purple at 3000
local LO_MP = 0xFF6FA8FF;
local function tpColorLo(tp)
    if (tp >= 3000) then return 0xFFC080FF; end
    if (tp >= 1000) then return 0xFF4A9AFF; end
    return 0xFFA8D4FF;
end

-- TP number color (full mode): white < 1000, green 1000+, gold at 3000
local TP_TXT_1K, TP_TXT_3K = 0xFFD6CEFF, 0xFFF0D27A; -- theme: lavender 1000+, gold 3000
local function tpColor(tp)
    if (tp >= 3000) then return TP_TXT_3K; end
    if (tp >= 1000) then return TP_TXT_1K; end
    return 0xFFFFFFFF;
end

local function fade(c, m)
    if (m >= 1) then return c; end
    return floor(floor(c / 0x1000000) * m) * 0x1000000 + (c % 0x1000000);
end

-------------------------------------------------------------------------------
-- game state helpers
-------------------------------------------------------------------------------
-- Cutscene / hidden interface / map (modules/ui.lua): signatures resolved one per tick (no load-time burst).
local uiCache, uiNext = false, 0;
local function uiBlockedRaw()
    if (not ui.warm()) then return false; end
    return ui.event() or ui.hidden() or ui.menu():find('map', 1, true) ~= nil;
end

local function uiBlocked()
    if (tickNow >= uiNext) then uiCache, uiNext = uiBlockedRaw(), tickNow + 200; end
    return uiCache;
end

-- same as XIUI libs/target.lua GetStPartyIndex
local function stPartyIndex()
    local p = AshitaCore:GetPointerManager():Get('party');
    if (p == nil or p == 0) then return nil; end
    p = ashita.memory.read_uint32(p);
    if (p == 0) then return nil; end
    p = ashita.memory.read_uint32(p);
    if (p == 0) then return nil; end
    if (ashita.memory.read_uint32(p + 0x54) == 0) then return nil; end
    return ashita.memory.read_uint8(p + 0x50);
end

-- held target idx, subtarget idx, party-cursor member idx
local function getTargets()
    local t = mm:GetTarget();
    local st = stPartyIndex();
    if (st ~= nil) then return t:GetTargetIndex(0), 0, st; end
    if (t:GetIsSubTargetActive() == 0) then return t:GetTargetIndex(0), 0, nil; end
    return t:GetTargetIndex(1), t:GetTargetIndex(0), nil;
end

local function anyOtherActive(party)
    for i = 1, 17 do
        if (party:GetMemberIsActive(i) ~= 0) then return true; end
    end
    return false;
end

-------------------------------------------------------------------------------
-- member data (one reused table) + setup dummies
-------------------------------------------------------------------------------
local D = {};
local function readMember(party, idx, myZone, entity)
    D.idx    = idx;
    D.name   = party:GetMemberName(idx) or '';
    D.sid    = party:GetMemberServerId(idx);
    D.zone   = party:GetMemberZone(idx);
    D.inZone = (idx == 0) or (D.zone == myZone);
    D.zoneName = nil;
    D.flags  = party:GetMemberFlagMask(idx);
    D.hp, D.hpp = party:GetMemberHP(idx), party:GetMemberHPPercent(idx);
    if (idx < 6) then -- alliance rows show neither MP nor sub job: skip 4 reads x 12 rows per tick
        D.mp, D.mpp = party:GetMemberMP(idx), party:GetMemberMPPercent(idx);
    else
        D.mp, D.mpp = 0, 0;
    end
    D.tp     = party:GetMemberTP(idx);
    D.mj, D.ml = party:GetMemberMainJob(idx), party:GetMemberMainJobLevel(idx);
    if (idx < 6) then
        D.sj, D.sl = party:GetMemberSubJob(idx), party:GetMemberSubJobLevel(idx);
    else
        D.sj, D.sl = 0, 0;
    end
    D.tidx   = party:GetMemberTargetIndex(idx);
    D.dist   = nil;
    D.buffs  = nil;
    if (entity ~= nil) then
        if (idx == 0) then
            D.dist = 0;
        elseif (D.inZone and D.tidx ~= 0 and entity:GetRawEntity(D.tidx) ~= nil) then
            -- entity exists -> 0 is valid (stacked boxes). Field is squared.
            local d = math.sqrt(entity:GetDistance(D.tidx));
            D.dist = d; -- shown grey past targetRange
        end
    end
end

local fakes = nil;
local fakeBuffIds = { 33, 34, 40, 41, 42, 43, 116, 251, 580, 37, 39, 195, 196, 214 };
local function makeFakes()
    fakes = {};
    for idx = 0, 17 do
        local f = { idx = idx };
        f.name = ('Member%d'):fmt(idx + 1);
        f.sid, f.zone, f.tidx = 1000 + idx, 0, idx + 1;
        f.inZone = (idx % 6) ~= 4;
        f.zoneName = 'Other Zone';
        f.flags = (idx == 0) and 0x0C or ((idx == 6 or idx == 12) and 0x04 or ((idx == 2) and 0x10 or 0));
        f.hp, f.hpp = 900 + (idx * 137) % 1800, 25 + (idx * 17) % 76;
        f.mp, f.mpp = 200 + (idx * 91) % 1200, 20 + (idx * 29) % 81;
        f.tp = (idx * 413) % 3000;
        f.mj, f.ml = 1 + idx % 22, 99;
        f.sj, f.sl = 1 + (idx * 7) % 22, 49;
        f.dist = (idx == 0) and 0 or ((idx * 7.3) % 49);
        f.buffs = { b = {}, d = {} };
        if (idx < 6) then
            for b = 1, 3 + idx * 3 do f.buffs.b[b] = fakeBuffIds[(b - 1) % #fakeBuffIds + 1]; end
            for b = 1, idx % 3 do f.buffs.d[b] = ({ 4, 134, 13 })[b]; end -- paralysis, dia, slow
        end
        fakes[idx] = f;
    end
end

-------------------------------------------------------------------------------
-- buffs
-------------------------------------------------------------------------------
local DEBUFF = require('modules/debuffs'); -- [id] = true
local rawBuffs, shownBuffs = {}, {};
local selfRaw, selfShown   = {}, { b = {}, d = {} };

-- filtered, game order (no sorting); out.b = buffs, out.d = debuffs. Runs only when a list changes.
local function derive(raw, out)
    local nb, nd, wl, f = 0, 0, S.whitelist, S.filters;
    local ob, od = out.b, out.d;
    for i = 1, #raw do
        local id = raw[i];
        if ((f[id] == true) == wl) then
            if (DEBUFF[id]) then nd = nd + 1; od[nd] = id; else nb = nb + 1; ob[nb] = id; end
        end
    end
    for i = #ob, nb + 1, -1 do ob[i] = nil; end
    for i = #od, nd + 1, -1 do od[i] = nil; end
    return out;
end

local function newShown() return { b = {}, d = {} }; end

local function rederiveAll()
    for sid, raw in pairs(rawBuffs) do shownBuffs[sid] = derive(raw, shownBuffs[sid] or newShown()); end
    derive(selfRaw, selfShown);
end

-- XiPackets 0x0076 member: u32 UniqueNo, u16 ActIndex, u16 pad, u64 Bits, u8 Buffs[32] (48 bytes)
-- id = ((Bits[i>>2] >> 2*(i%4)) & 3) << 8 | Buffs[i]; 0xFF + hi 0 = empty; 0 ignored.
local function readEntry(get, base, out)
    local n = 0;
    for j = 0, 31 do
        local lo = get(base + 0x10 + j);
        local hi = bit.band(bit.rshift(get(base + 8 + bit.rshift(j, 2)), 2 * (j % 4)), 3);
        if (not (lo == 0xFF and hi == 0)) then
            local id = hi * 256 + lo;
            if (id ~= 0) then n = n + 1; out[n] = id; end
        end
    end
    for i = #out, n + 1, -1 do out[i] = nil; end
end

local function u32(get, o)
    return get(o) + get(o + 1) * 0x100 + get(o + 2) * 0x10000 + get(o + 3) * 0x1000000;
end

-- Each 0x0076 (and the statusicons block) is a full snapshot of the other 5 members, so ids not
-- in it are dropped: a member who left/rejoined shows no stale icons.
local seenSid = {};
local function readAllEntries(get, start)
    for k in pairs(seenSid) do seenSid[k] = nil; end
    for i = 0, 4 do
        local base = start + i * 0x30;
        local sid  = u32(get, base);
        if (sid ~= 0) then
            seenSid[sid] = true;
            local raw = rawBuffs[sid] or {};
            rawBuffs[sid] = raw;
            readEntry(get, base, raw);
            shownBuffs[sid] = derive(raw, shownBuffs[sid] or newShown());
        end
    end
    for sid in pairs(rawBuffs) do
        if (not seenSid[sid]) then rawBuffs[sid] = nil; shownBuffs[sid] = nil; end
    end
end

local function seedBuffs()
    local p = AshitaCore:GetPointerManager():Get('party.statusicons');
    if (p == nil or p == 0) then return; end
    p = ashita.memory.read_uint32(p);
    if (p == nil or p == 0) then return; end
    readAllEntries(function (o) return ashita.memory.read_uint8(p + o); end, 0);
end

local function updateSelfBuffs()
    local b = mm:GetPlayer():GetBuffs();
    if (b == nil) then return; end
    local n, changed = 0, false;
    for i = 0, 32 do -- covers 0- or 1-based tables
        local id = b[i];
        if (id ~= nil and id > 0 and id ~= 255) then
            n = n + 1;
            if (selfRaw[n] ~= id) then selfRaw[n] = id; changed = true; end
        end
    end
    if (#selfRaw ~= n) then
        for i = #selfRaw, n + 1, -1 do selfRaw[i] = nil; end
        changed = true;
    end
    if (changed) then derive(selfRaw, selfShown); end
end

-------------------------------------------------------------------------------
-- crew recasts over localhost UDP (independent of crewcd; different ports)
-------------------------------------------------------------------------------
local crew = { tx = nil, rx = nil, port = nil, nextBind = 0, nextSend = 0, namesNext = 0, data = {}, abil = {}, spell = {}, buf = {},
               scanMap = {}, scanPos = 0, scanWant = false, scanDone = false };

local function abilityName(id, x)
    if (x == 0) then return 'SP1 (1-Hr)'; end -- atom0s recast: slot 0 = job one hour
    if (id == 254) then return 'SP2'; end      -- shared timer id across jobs
    if (id == 231) then return 'Stratagems (full)'; end
    local n = crew.abil[id];
    if (n ~= nil) then return n; end
    local a = resMgr:GetAbilityByTimerId(id);
    if (a ~= nil and a.Name[1] ~= nil and a.Name[1] ~= '') then
        crew.abil[id] = a.Name[1];
        return a.Name[1];
    end
    -- atom0s recast fallback (scan abilities by RecastTimerId), done in chunks by crewScanStep()
    n = crew.scanMap[id];
    if (n ~= nil) then crew.abil[id] = n; return n; end
    crew.scanWant = true;
    if (crew.scanDone) then crew.abil[id] = ('Recast %d'):fmt(id); return crew.abil[id]; end
    return ('Recast %d'):fmt(id); -- not cached: retried once the scan finishes
end

local function crewScanStep() -- 128 ability ids per call, only when a fallback was needed
    if (not crew.scanWant or crew.scanDone) then return; end
    local last = math.min(crew.scanPos + 127, 2048);
    for i = crew.scanPos, last do
        local b = resMgr:GetAbilityById(i);
        if (b ~= nil and crew.scanMap[b.RecastTimerId] == nil and b.Name[1] ~= nil and b.Name[1] ~= '') then
            crew.scanMap[b.RecastTimerId] = b.Name[1];
        end
    end
    crew.scanPos = last + 1;
    if (crew.scanPos > 2048) then crew.scanDone = true; end
end

local function spellName(id)
    local n = crew.spell[id];
    if (n ~= nil) then return n; end
    local sp = resMgr:GetSpellById(id);
    n = (sp ~= nil and sp.Name[1] ~= nil and sp.Name[1] ~= '') and sp.Name[1] or ('Spell %d'):fmt(id);
    crew.spell[id] = n;
    return n;
end

local function buildPayload()
    local party = mm:GetParty();
    if (party:GetMemberIsActive(0) == 0) then return nil; end
    local me = party:GetMemberName(0);
    if (me == nil or me == '') then return nil; end
    local player, rc, buf = mm:GetPlayer(), mm:GetRecast(), crew.buf;
    local n = 4;
    buf[1], buf[2], buf[3], buf[4] = 'GMU1', me, tostring(player:GetMainJob()), tostring(player:GetSubJob());
    for x = 0, 31 do
        local id, t = rc:GetAbilityTimerId(x), rc:GetAbilityTimer(x);
        if ((id ~= 0 or x == 0) and t > 0) then
            n = n + 1; buf[n] = ('A%s=%.1f'):fmt(abilityName(id, x), t / 60);
        end
    end
    for x = 0, 1024 do
        local t = rc:GetSpellTimer(x);
        if (t > 0) then n = n + 1; buf[n] = ('S%s=%.1f'):fmt(spellName(x), t / 60); end
    end
    for i = #buf, n + 1, -1 do buf[i] = nil; end
    return table.concat(buf, '\t');
end

local function cmpRecast(a, b)
    if (a.k ~= b.k) then return a.k < b.k; end -- abilities (A) before spells (S)
    return a.s < b.s;
end

-- Wire format 'GMU1' (goomui 2.x boxes only).
-- Any local program can send to these ports, so everything is validated: size, item count,
-- name (letters, current party/alliance member only), job ids (integers 0-255), seconds (finite).
local CREW_MAX_MSG, CREW_MAX_ITEMS = 8192, 160; -- Ashita's LuaSocket already caps a UDP receive at 8192
local crewParts, crewNames = {}, {};

local function crewJob(v)
    v = tonumber(v);
    if (v == nil or v ~= v or v < 0 or v > 255 or v % 1 ~= 0) then return nil; end
    return v;
end

-- lowercased names of active party/alliance members (refreshed at most once per second, on receive)
local function crewRefreshNames()
    for k in pairs(crewNames) do crewNames[k] = nil; end
    local party = mm:GetParty();
    for i = 0, 17 do
        if (party:GetMemberIsActive(i) ~= 0) then
            local nm = party:GetMemberName(i);
            if (nm ~= nil and nm ~= '') then crewNames[nm:lower()] = true; end
        end
    end
end

local function crewParse(msg, now)
    if (#msg > CREW_MAX_MSG) then return; end
    local parts, np = crewParts, 0;
    for p in msg:gmatch('[^\t]+') do
        np = np + 1;
        parts[np] = p;
        if (np >= CREW_MAX_ITEMS + 4) then break; end
    end
    if (np < 4 or parts[1] ~= 'GMU1') then return; end
    local name = parts[2];
    if (#name > 15 or not name:match('^%a+$')) then return; end
    local key = name:lower();
    local own = (msg == crew.lastPayload); -- built locally from party slot 0: no membership check
    if (not own) then
        if (now >= crew.namesNext) then crew.namesNext = now + 1; crewRefreshNames(); end
        if (not crewNames[key]) then return; end
    end
    local mj, sj = crewJob(parts[3]), crewJob(parts[4]);
    if (mj == nil or sj == nil) then return; end
    if (own) then crew.selfKey = key; elseif (key == crew.selfKey) then return; end -- no spoofing our own row
    local e = crew.data[key] or { list = {} };
    crew.data[key] = e;
    e.name, e.mj, e.sj, e.t = name, mj, sj, now;
    local list, n = e.list, 0;
    for i = 5, np do
        local k, nm, sec = parts[i]:match('^([AS])(.-)=([%d%.]+)$');
        sec = tonumber(sec);
        if (k ~= nil and sec ~= nil and sec == sec) then
            n = n + 1;
            local it = list[n] or {};
            list[n] = it;
            it.k, it.n, it.s = k, (#nm > 48) and nm:sub(1, 48) or nm, math.min(sec, 86400);
        end
    end
    for i = #list, n + 1, -1 do list[i] = nil; end
    table.sort(list, cmpRecast);
end

local function hoverOn()
    return S.crewHover and ((not S.lowfi) or S.lofiHover);
end

local function crewClose()
    if (crew.rx ~= nil) then crew.rx:close(); crew.rx = nil; crew.port = nil; end
    if (crew.tx ~= nil) then crew.tx:close(); crew.tx = nil; end
end

local function crewTick(now)
    if (not S.crewShare and not S.crewHover) then crewClose(); return; end
    local wantRx = hoverOn();
    if (not wantRx and crew.rx ~= nil) then crew.rx:close(); crew.rx = nil; crew.port = nil; end
    if (wantRx and crew.rx == nil and now >= crew.nextBind) then
        crew.nextBind = now + 10;
        for k = 0, 7 do
            local s = socket.udp();
            if (s ~= nil) then
                s:settimeout(0);
                if (s:setsockname('127.0.0.1', S.crewPort + k)) then
                    crew.rx, crew.port = s, S.crewPort + k;
                    break;
                end
                s:close();
            end
        end
    end
    if (crew.rx ~= nil) then
        for _ = 1, 64 do
            local msg, err = crew.rx:receive();
            if (msg ~= nil) then crewParse(msg, now);
            elseif (err == 'timeout') then break; end -- other errors (e.g. ICMP reset): keep draining
        end
    end
    crewScanStep();
    if (now >= crew.nextSend) then
        crew.nextSend = now + (S.lowfi and 2 or 1);
        for key, e in pairs(crew.data) do -- forget boxes silent for 60 s (setup preview entry excepted)
            if (key ~= 'member2' and now - e.t > 60) then crew.data[key] = nil; end
        end
        local payload = buildPayload();
        if (payload ~= nil) then
            if (payload ~= crew.lastPayload) then -- own entry for self-hover; re-parse only on change
                crew.lastPayload = payload;
                crewParse(payload, now);
            else
                local me = crew.data[crew.selfKey or ''];
                if (me ~= nil) then me.t = now; else crewParse(payload, now); end -- re-create after the 60 s forget
            end
            if (S.crewShare) then
                if (crew.tx == nil) then
                    local s = socket.udp();
                    if (s ~= nil) then
                        s:settimeout(0);
                        if (s:setsockname('127.0.0.1', 0)) then -- loopback-only source, ephemeral port
                            crew.tx = s;
                        else
                            s:close(); -- retried on the next send
                        end
                    end
                end
                if (crew.tx ~= nil) then
                    for k = 0, 7 do
                        local p = S.crewPort + k;
                        if (p ~= crew.port) then crew.tx:sendto(payload, '127.0.0.1', p); end
                    end
                end
            end
        end
    end
end

local function fmtTime(s)
    s = floor(s + 0.5);
    if (s < 60) then return s .. 's'; end
    if (s < 3600) then return ('%d:%02d'):fmt(floor(s / 60), s % 60); end
    return ('%d:%02d:%02d'):fmt(floor(s / 3600), floor(s / 60) % 60, s % 60);
end

local COL_TITLE, COL_DIM, COL_SOON, COL_CD, COL_READY = { 1, 0.85, 0.4, 1 }, { 0.55, 0.55, 0.58, 1 }, { 1, 0.8, 0, 1 }, { 0.9, 0.9, 0.92, 1 }, { 0.35, 0.85, 0.45, 1 };
local function jobF4(id) return (S.jobColors and theme.JOB_F4[jobName(id)]) or COL_TITLE; end
local function drawCrewTip(e, now)
    local age = now - e.t;
    imgui.BeginTooltip();
    imgui.TextColored(COL_TITLE, e.name .. '  ');
    imgui.SameLine(0, 0); imgui.TextColored(jobF4(e.mj), jobName(e.mj));
    imgui.SameLine(0, 0); imgui.TextColored(COL_DIM, '/');
    imgui.SameLine(0, 0); imgui.TextColored(jobF4(e.sj), jobName(e.sj));
    if (age > 5) then imgui.TextColored(COL_DIM, ('no data for %ds'):fmt(floor(age))); end
    local shown = 0;
    if (imgui.BeginTable('goomui_crew', 2, ImGuiTableFlags_SizingFixedFit)) then
        for i = 1, #e.list do
            local it = e.list[i];
            local rem = it.s - age;
            if (rem > 0) then
                shown = shown + 1;
                imgui.TableNextRow();
                imgui.TableNextColumn();
                imgui.TextColored((it.k == 'A') and COL_CD or COL_DIM, it.n);
                imgui.TableNextColumn();
                local whole = floor(rem + 0.5);
                if (it.fs ~= whole) then it.fs, it.ft = whole, fmtTime(rem); end
                imgui.TextColored((rem <= 10) and COL_SOON or COL_CD, it.ft);
            end
        end
        imgui.EndTable();
    end
    if (shown == 0) then imgui.TextColored(COL_READY, 'All ready'); end
    imgui.EndTooltip();
end

-------------------------------------------------------------------------------
-- renderer: sprite (bars/icons/borders) then ManualRender Ashita fonts
-------------------------------------------------------------------------------
local F = nil;
local ICON_MAX  = 128; -- soft cap: past it, icons unused for ICON_IDLE drawn passes are released
local ICON_IDLE = 200; -- fullTick passes (~10 s at 50 ms); passes, not time, so hiding the list ages nothing
local ICON_OVERRIDE = { [623] = 62 }; -- XIUI: Rampart shows BCNM icon
local gdiFailed = false; -- gdifonts DLL / font manager unavailable: bars and icons still draw, no text

local function iconsClear()
    for _, e in pairs(F.icons) do
        if (e) then e.tex:Release(); end
    end
    F.icons, F.iconCount = {}, 0;
end

-- Old behaviour flushed the whole cache past 64 ids, so every visible icon blinked out and was
-- reloaded 4 per tick. Now only icons idle for ICON_IDLE drawn passes go, and the cap is soft.
local function iconsTrim()
    if (F.iconCount <= ICON_MAX) then return; end
    local cut = F.pass - ICON_IDLE;
    for id, e in pairs(F.icons) do
        if (e and e.used < cut) then
            e.tex:Release();
            F.icons[id] = nil;
            F.iconCount = F.iconCount - 1;
        end
    end
end

local function getIcon(id)
    local e = F.icons[id];
    if (e ~= nil) then
        if (e) then e.used = F.pass; return e; end
        return nil;
    end
    if (F.iconBudget <= 0) then return nil; end -- load next tick
    F.iconBudget = F.iconBudget - 1;
    F.icons[id] = false;
    local rid = ICON_OVERRIDE[id] or id;
    if (rid < 1 or rid > 0x3FF) then return nil; end
    local res = resMgr:GetStatusIconByIndex(rid);
    if (res == nil or res.Bitmap == nil or res.ImageSize == nil or res.ImageSize <= 0) then return nil; end
    local tp   = ffi.new('IDirect3DTexture8*[1]');
    local info = ffi.new('D3DXIMAGE_INFO');
    crumb.sub('party list: status icon texture');
    local hr = ffi.C.D3DXCreateTextureFromFileInMemoryEx(F.dev, res.Bitmap, res.ImageSize, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
        ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, info, nil, tp);
    crumb.back();
    if (hr ~= ffi.C.S_OK) then
        return nil;
    end
    local w = (info.Width > 0) and info.Width or 32;
    local h = (info.Height > 0) and info.Height or 32;
    e = { tex = ffi.cast('IDirect3DTexture8*', tp[0]), rect = ffi.new('RECT', { 0, 0, w, h }), w = w, used = F.pass };
    F.icons[id] = e;
    F.iconCount = F.iconCount + 1;
    return e;
end

local function rect(x, y, w, h, c)
    if (w < 1 or h < 1) then return; end
    local n = F.nR + 1;
    F.nR = n;
    F.RX[n], F.RY[n], F.RW[n], F.RH[n], F.RC[n] = floor(x), floor(y), floor(w + 0.5), floor(h + 0.5), c;
end

local function box(x, y, w, h, c) -- 1px outline
    rect(x, y, w, 1, c); rect(x, y + h - 1, w, 1, c);
    rect(x, y, 1, h, c); rect(x + w - 1, y, 1, h, c);
end

-- overlay rect: drawn after icons (e.g. debuff frames on top of the icon)
local function orect(x, y, w, h, c)
    if (w < 1 or h < 1) then return; end
    local n = F.nO + 1;
    F.nO = n;
    F.OX[n], F.OY[n], F.OW[n], F.OH[n], F.OC[n] = floor(x), floor(y), floor(w + 0.5), floor(h + 0.5), c;
end

-- overlay frame, t px thick, inside x,y,w,h
local function oframe(x, y, w, h, t, c)
    orect(x, y, w, t, c); orect(x, y + h - t, w, t, c);
    orect(x, y + t, t, h - 2 * t, c); orect(x + w - t, y + t, t, h - 2 * t, c);
end

-- row highlight: target = light fill; sub-target = blue fill + bright frame on top (the fill alone hides
-- under the bars, hard to see while picking a party member for <stpt>)
local function rowMark(x, y, w, h, s, sel, sub)
    if (sel) then rect(x, y, w, h, S.color.target);
    elseif (sub) then
        rect(x, y, w, h, S.color.sub);
        oframe(x, y, w, h, math.max(2, floor(2 * s + 0.5)), S.color.subFrame);
    end
end

-- Themed bar (theme.lua style B): track, fill, light upper band, 1px top highlight,
-- 1px dark bottom edge. m = range fade multiplier (alpha).
local tbar_m = 1;
local function tbar_rect(x, y, w, h, c) rect(x, y, w, h, fade(c, tbar_m)); end
local function tbar(x, y, w, h, frac, col, m)
    tbar_m = m;
    theme.draw(tbar_rect, theme.A, floor(x), floor(y), floor(w + 0.5), floor(h + 0.5), frac, col); -- Look tab style
end

local function icon(e, x, y, size, c)
    local n = F.nI + 1;
    F.nI = n;
    F.IE[n], F.IX[n], F.IY[n], F.IS[n], F.IC[n] = e, floor(x), floor(y), size / e.w, c or 0xFFFFFFFF;
end

-- 5-point star texture (STAR_PX square): white fill, 2 px black outline, 4x4 supersampled edges.
-- Straight alpha (sprite blends SRCALPHA): rgb = fill share of the covered area, a = outline coverage.
local STAR_PX = 32;
local function makeStarTex()
    local res, tex = F.dev:CreateTexture(STAR_PX, STAR_PX, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED);
    if (res ~= ffi.C.S_OK or tex == nil) then return nil; end
    local hr, lr = tex:LockRect(0, nil, 0);
    if (hr ~= ffi.C.S_OK or lr == nil) then tex:Release(); return nil; end
    local okP, pitch = pcall(function () return tonumber(lr.Pitch); end);
    local stride = (okP and pitch ~= nil and pitch > 0) and floor(pitch / 4) or STAR_PX;
    local px = ffi.cast('uint32_t*', lr.pBits);
    local c, ol = STAR_PX / 2, 2.0;
    local ro = c - ol - 0.5;
    local ri = ro * 0.381966; -- regular star: inner / outer radius
    local vx, vy = {}, {};
    for k = 0, 9 do
        local r, a = (k % 2 == 0) and ro or ri, -math.pi / 2 + k * math.pi / 5;
        vx[k + 1], vy[k + 1] = c + r * math.cos(a), c + 0.6 + r * math.sin(a); -- +0.6: centre the star's box
    end
    local function inside(x, y)
        local inS, j = false, 10;
        for i = 1, 10 do
            if ((vy[i] > y) ~= (vy[j] > y)) and (x < (vx[j] - vx[i]) * (y - vy[i]) / (vy[j] - vy[i]) + vx[i]) then inS = not inS; end
            j = i;
        end
        return inS;
    end
    local function near(x, y) -- within ol of an edge
        local j = 10;
        for i = 1, 10 do
            local ex, ey = vx[i] - vx[j], vy[i] - vy[j];
            local t = ((x - vx[j]) * ex + (y - vy[j]) * ey) / (ex * ex + ey * ey);
            t = (t < 0) and 0 or ((t > 1) and 1 or t);
            local dx, dy = x - (vx[j] + t * ex), y - (vy[j] + t * ey);
            if (dx * dx + dy * dy <= ol * ol) then return true; end
            j = i;
        end
        return false;
    end
    for y = 0, STAR_PX - 1 do
        for x = 0, STAR_PX - 1 do
            local f, o = 0, 0;
            for sy = 0, 3 do
                for sx = 0, 3 do
                    local qx, qy = x + (sx + 0.5) / 4, y + (sy + 0.5) / 4;
                    if (inside(qx, qy)) then f, o = f + 1, o + 1; elseif (near(qx, qy)) then o = o + 1; end
                end
            end
            local a = floor(o * 255 / 16 + 0.5);
            local g = (o > 0) and floor(f * 255 / o + 0.5) or 0;
            px[y * stride + x] = a * 0x1000000 + g * 0x10000 + g * 0x100 + g;
        end
    end
    tex:UnlockRect(0);
    return { tex = tex, rect = ffi.new('RECT', { 0, 0, STAR_PX, STAR_PX }), w = STAR_PX };
end

-- text object: gdifonts object (manual: not in gdifonts' own render list) + cached props.
-- Texture is (re)built by GDI+ inside put() -> cost shows up in tick timing; old texture released explicitly.
local gdi = nil; -- lazy require (in initRenderer)
local FONT_BUDGET = 8;     -- max new text objects per tick
local ICON_BUDGET = 4;     -- max new icon textures per tick
-- Text texture rebuilds (GDI+ in gdifonts' DLL) run in present(), at most REBUILD_PER_FRAME a frame, oldest change
-- first. They used to run in the tick, up to 60 in one frame on a low-fi tick (budget = tick length * 240/s), which
-- showed up as 10-20 ms frames in combat.
local REBUILD_PER_FRAME = 3;
local function gdiH(h) return floor(h * S.textScale * 1.3 + 0.5); end -- gdifonts px vs old Ashita sizes
local VC_FIX = 0.6; -- vertical-centering correction (fraction of font px)

local function newText(h)
    local ok, g = pcall(gdi.create_object, gdi, {
        box_height = 0, box_width = 0, font_alignment = gdi.Alignment.Left,
        font_color = 0xFFFFFFFF, font_family = S.font, font_flags = gdi.FontFlags.Bold,
        font_height = gdiH(h or 10), gradient_color = 0, gradient_style = 0,
        outline_color = 0xFF000000, outline_width = 2,
        position_x = 0, position_y = 0, visible = true, text = '',
    }, true);
    if (not ok or g == nil) then -- e.g. CreateFontManager returned NULL ('Interface doesn't exist.')
        gdiFailed = true;
        reportErr('gdifonts', g);
        return nil;
    end
    local o = { g = g, text = '', x = -1000, y = -1000, h = -1, c = 0xFFFFFFFF, fam = S.font, w = 0, hh = 0, on = false, tex = nil, rect = nil };
    F.texts[#F.texts + 1] = o;
    F.budget = F.budget - 1;
    return o;
end

-- Texture builds. A text whose texture exists and changed takes a ticket (refreshTex, in the tick); serveTexts
-- rebuilds the oldest tickets each frame and puts the text back in place, so no text starves whatever the put()
-- order and the old texture stays on screen until then. A failed build keeps the old texture and retries in 1 s
-- (gdifonts clears is_dirty before building, so a failure used to blank the text until its text changed). Old
-- textures are released explicitly. First builds (o.tex == nil) run at once: FONT_BUDGET new objects per tick.
local function buildTex(o)
    local g = o.g;
    o.ticket = nil;
    local old = g.texture;
    g.is_dirty = true;
    crumb.sub('party list: text texture (gdifonts)');
    local tex, r = g:get_texture();
    crumb.back();
    if (tex ~= nil) then
        if (old ~= nil and old ~= tex) then ffi.gc(old, nil); old:Release(); end
        o.tex, o.rect, o.w, o.hh, o.retryAt = tex, r, r.right, r.bottom, nil;
    else
        g.texture, g.is_dirty, o.retryAt = old, true, tickNow + 1000;
    end
end

local function refreshTex(o)
    local g = o.g;
    if (tickNow < (o.retryAt or 0)) then return; end
    if (o.tex == nil) then buildTex(o); return; end
    if (not g.is_dirty) then o.ticket = nil; return; end
    if (o.ticket == nil) then o.ticket = F.ticketNext; F.ticketNext = F.ticketNext + 1; end
end

-- Screen position from what put() was given and the current texture size (again after a deferred rebuild).
local function place(o)
    local x = (o.rx ~= nil) and (o.rx - o.w) or o.lx;
    local y = o.ly;
    if (o.vc) then
        -- gdifonts textures carry extra space under the glyphs: texture-center put glyphs ~0.6 px-size too high
        -- (measured in-game 1.3.4: name 10 px, numbers 8 px above target). Shift down by VC_FIX * font px.
        y = o.cy - o.hh / 2 + VC_FIX * o.px;
    end
    o.x, o.y = floor(x), floor(y);
end

-- Up to n queued rebuilds of texts shown in the last tick, oldest ticket first.
local function serveTexts(n)
    local texts, pass = F.texts, F.pass;
    for _ = 1, n do
        local best = nil;
        for i = 1, #texts do
            local o = texts[i];
            if (o.ticket ~= nil and o.seen == pass and (best == nil or o.ticket < best.ticket)) then best = o; end
        end
        if (best == nil) then return; end
        if (tickNow < (best.retryAt or 0) or not best.g.is_dirty) then
            best.ticket = nil;
        else
            buildTex(best);
            if (best.tex ~= nil) then place(best); end
        end
    end
end

local function textSize(o) return o.w, o.hh; end

local function releaseText(o)
    local g = o.g;
    if (g.texture ~= nil) then
        local old = g.texture;
        g.texture = nil;
        ffi.gc(old, nil);
        old:Release();
    end
    o.tex, o.rect = nil, nil;
end

-- put(R, key, ...): text objects are created on first real use (lazy, budgeted).
-- rightX ~= nil: right-align at rightX. vc: y is the vertical center (measured height).
local function put(R, key, text, x, y, h, color, rightX, vc)
    local o = rawget(R, key);
    if (text == nil or text == '') then
        if (o ~= nil) then o.on = false; end
        return;
    end
    if (o == nil) then
        if (gdiFailed or F.budget <= 0) then return; end -- next tick
        o = newText(h);
        if (o == nil) then return; end
        R[key] = o;
        R.list[#R.list + 1] = o;
    end
    local g = o.g;
    if (o.h ~= h) then o.h = h; g:set_font_height(gdiH(h)); end
    if (o.text ~= text) then o.text = text; g:set_text(text); end
    o.c = color or 0xFFFFFFFF; -- applied as the sprite tint in draw(): no rebuild on colour/fade change
    o.seen = F.pass;
    if (g.is_dirty or o.tex == nil) then refreshTex(o); end
    if (o.tex == nil) then o.on = false; return; end
    o.rx, o.lx, o.ly, o.vc = rightX, x, y, vc;
    if (vc) then o.cy, o.px = y, gdiH(h); end
    place(o);
    o.on = true;
end

local NOTEXT = { on = false }; -- inert stand-in for not-yet-created text slots
local TEXT_KEYS = { main = true, sub = true, name = true, hp = true, hpp = true, mp = true, tp = true, dist = true,
                    zone = true, mark = true, l1 = true, l2 = true, l3 = true, sl = true };
local ROW_MT = { __index = function (_, k) if (TEXT_KEYS[k]) then return NOTEXT; end end };

local function newRow(ally)
    return setmetatable({ ally = ally, list = {} }, ROW_MT);
end

local function getRow(idx)
    local R = F.rows[idx];
    if (R == nil) then R = newRow(idx >= 6); F.rows[idx] = R; end
    return R;
end

local function hideRow(R)
    if (R == nil) then return; end
    for i = 1, #R.list do R.list[i].on = false; end
end

local function hideAll()
    visible = false;
    if (F == nil) then return; end
    for idx = 0, 17 do hideRow(F.rows[idx]); end
    F.nR, F.nI, F.nHit, F.nO = 0, 0, 0, 0;
end

-- Font family and text size (textScale) for existing texts: run on settings load / character
-- switch and by the setup controls. o.h = -1 makes the next put() re-apply gdiH(); set_font_height
-- only marks the text dirty if the pixel size really changed.
local function applyFont()
    if (F == nil) then return; end
    for i = 1, #F.texts do
        local o = F.texts[i];
        o.h = -1;
        if (o.fam ~= S.font) then o.fam = S.font; o.g:set_font_family(S.font); end
    end
end

-- D3DXCreateSprite failure used to be silent (nothing drawn, text still rebuilt every tick):
-- report once and retry every 5 s; tick() skips layout until it exists.
local function createSprite()
    local sp = ffi.new('ID3DXSprite*[1]');
    if (ffi.C.D3DXCreateSprite(F.dev, sp) == ffi.C.S_OK) then
        F.sprite = ffi.cast('ID3DXSprite*', sp[0]);
        return;
    end
    F.spriteRetry = ashita.time.get_tick64() + 5000;
    if (not F.spriteWarned) then
        F.spriteWarned = true;
        print(chat.header(addon.name):append(chat.error('D3DXCreateSprite failed; retrying every 5 s.')));
    end
end

local function initRenderer()
    if (gdi == nil and not gdiFailed) then
        local ok, lib = pcall(require, 'libs/gdifonts/include'); -- ffi.load of the DLL + font manager
        if (ok and type(lib) == 'table') then
            gdi = lib;
            gdi:set_auto_render(false); -- we draw the textures ourselves (our copy starts off: no event change mid-frame)
        else
            gdiFailed = true;
            print(chat.header(addon.name):append(chat.error('gdifonts failed to load; text disabled: ' .. tostring(lib))));
        end
    end
    F = { rows = {}, texts = {}, icons = {}, iconCount = 0, selfNext = 0, budget = FONT_BUDGET, iconBudget = ICON_BUDGET,
          ticketNext = 1, spriteRetry = 0, pass = 0,
          RX = {}, RY = {}, RW = {}, RH = {}, RC = {}, nR = 0,
          OX = {}, OY = {}, OW = {}, OH = {}, OC = {}, nO = 0,
          IE = {}, IX = {}, IY = {}, IS = {}, IC = {}, nI = 0,
          HX = {}, HY = {}, HW = {}, HH = {}, HN = {}, nHit = 0 };
    F.dev = d3d.get_device();
    createSprite();
    -- 1x1 white texture built in code (IDirect3DDevice8::CreateTexture via Ashita d3d8 wrapper)
    local res, tex = F.dev:CreateTexture(1, 1, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED);
    if (res == ffi.C.S_OK and tex ~= nil) then
        local hr, lr = tex:LockRect(0, nil, 0);
        if (hr == ffi.C.S_OK and lr ~= nil) then
            ffi.cast('uint32_t*', lr.pBits)[0] = 0xFFFFFFFF;
            tex:UnlockRect(0);
        end
        F.white = tex;
    end
    F.star = makeStarTex();
    F.vpos = ffi.new('D3DXVECTOR2', { 0, 0 });
    F.one  = ffi.new('D3DXVECTOR2', { 1, 1 });
    F.vscl = ffi.new('D3DXVECTOR2', { 1, 1 });
    F.unit = ffi.new('RECT', { 0, 0, 1, 1 });
    seedBuffs();
    rederiveAll();
end

local function destroyRenderer()
    if (F == nil) then return; end
    for i = 1, #F.texts do releaseText(F.texts[i]); end
    iconsClear();
    if (F.white ~= nil) then F.white:Release(); end
    if (F.star ~= nil) then F.star.tex:Release(); end
    if (F.sprite ~= nil) then F.sprite:Release(); end
    F = nil;
end

-- Buff icons, 2 lines centered in the row, in READING order (left -> right, line 1 then line 2) so they
-- read like the game's own buff bar. Buffs on the left: each line is right-aligned to the list edge.
-- debuffLine: debuffs (tinted) end line 2, i.e. nearest the bars; overflow buffs come before them.
local LID1, LDB1, LID2, LDB2 = {}, {}, {}, {}; -- reused line buffers (ids, debuff flags)
local n1, n2 = 0, 0;

local function push(line, id, deb)
    if (line == 1) then n1 = n1 + 1; LID1[n1], LDB1[n1] = id, deb;
    else n2 = n2 + 1; LID2[n2], LDB2[n2] = id, deb; end
end

local function drawLine(ids, debs, n, ox, y, W, s, bs)
    for j = 1, n do
        local e = getIcon(ids[j]);
        if (e ~= nil) then
            local g = S.buffGap or 6;
            local x = S.buffRight and (ox + (W + g) * s + (j - 1) * bs) or (ox - g * s - (n - j + 1) * bs);
            icon(e, x, y, bs);
            if (debs[j]) then -- red frame on top of the icon edge (needs no spacing between icons)
                local t, c = math.max(2, floor(2 * s + 0.5)), S.color.debuffBg;
                orect(x, y, bs, t, c); orect(x, y + bs - t, bs, t, c);
                orect(x, y + t, t, bs - 2 * t, c); orect(x + bs - t, y + t, t, bs - 2 * t, c);
            end
        end
    end
end

local function drawBuffs(list, ox, oy, rowH, W, s, cap)
    local b, d = list.b, list.d;
    local nb, nd = #b, #d;
    if (nb + nd == 0) then return; end
    local bs, per = math.min(S.buffSize, cap) * s, S.buffsPerRow;
    n1, n2 = 0, 0;
    if (nd == 0 or not S.debuffLine) then -- one stream: buffs then debuffs, wrapped over 2 lines
        local n = 0;
        for i = 1, nb + nd do
            if (n >= per * 2) then break; end
            local deb = i > nb;
            push((n < per) and 1 or 2, deb and d[i - nb] or b[i], deb);
            n = n + 1;
        end
    else
        for i = 1, math.min(nb, per) do push(1, b[i], false); end   -- line 1: first buffs
        local nds = math.min(nd, per);
        local room = per - nds;                                     -- line 2: overflow buffs, then debuffs
        if (S.buffRight) then                                       -- (right side: debuffs nearest the list)
            for i = 1, nds do push(2, d[i], true); end
            for i = per + 1, math.min(nb, per + room) do push(2, b[i], false); end
        else
            for i = per + 1, math.min(nb, per + room) do push(2, b[i], false); end
            for i = 1, nds do push(2, d[i], true); end
        end
    end
    local y1 = oy + (rowH * s - 2 * bs - s) / 2;
    drawLine(LID1, LDB1, n1, ox, y1, W, s, bs);
    drawLine(LID2, LDB2, n2, ox, y1 + bs + s, W, s, bs);
end

local function rangeMult(d)
    if (d.idx == 0 or not S.showDist) then return 1; end
    if (d.dist == nil or d.dist > S.targetRange) then return 0.3; end
    if (d.dist > S.castRange) then return 0.55; end
    return 1;
end

local function cacheTexts(R, d)
    if (R.hpV ~= d.hp) then R.hpV = d.hp; R.hpT = tostring(d.hp); end
    if (R.hppV ~= d.hpp) then R.hppV = d.hpp; R.hppT = d.hpp .. '%'; end
    if (R.mpV ~= d.mp) then R.mpV = d.mp; R.mpT = tostring(d.mp); end
    if (R.tpV ~= d.tp) then R.tpV = d.tp; R.tpT = tostring(d.tp); end
    local mk = d.mj * 1000 + d.ml;
    if (R.mjK ~= mk) then
        R.mjK = mk;
        if (d.mj > 0) then
            R.mjT = R.ally and jobName(d.mj) or (jobName(d.mj) .. ((d.ml > 0) and tostring(d.ml) or ''));
        else
            R.mjT = '';
        end
    end
    local sk = d.sj * 1000 + d.sl;
    if (R.sjK ~= sk) then
        R.sjK = sk;
        R.sjT = (d.sj > 0 and d.sl > 0) and (jobName(d.sj) .. tostring(d.sl)) or '';
    end
    if (R.jbMK ~= R.mjK or R.jbSK ~= R.sjK) then
        R.jbMK, R.jbSK = R.mjK, R.sjK;
        R.jbT = (R.sjT ~= '' and not R.ally) and (R.mjT .. '/' .. R.sjT) or R.mjT;
    end
    local q = d.dist and floor(d.dist * 10 + 0.5) or -1;
    if (R.dQ ~= q and (R.dT == nil or tickNow >= (R.dNext or 0))) then
        R.dQ, R.dNext = q, tickNow + 500;
        R.dT = (q >= 0) and ('%.1f'):fmt(q / 10) or '--';
    end
    if (R.nmV ~= d.name) then R.nmV = d.name; R.nmL = d.name:lower(); end
end

-- leader color: alliance leader > party leader > nil. Flags per XiPackets GP_GROUP_ATTR.
local function leaderColor(d, c)
    local fl = d.flags or 0;
    if (d.sid ~= 0 and (d.sid == c.al or bit.band(fl, 0x08) ~= 0)) then return S.color.aLeader; end
    if (bit.band(fl, 0x04) ~= 0 or (d.sid ~= 0 and (d.sid == c.l1 or d.sid == c.l2 or d.sid == c.l3))) then return S.color.leader; end
    return nil;
end
local function nameColor(d, c) return leaderColor(d, c) or 0xFFFFFFFF; end

-- leader star: a drawn sprite (white star, black outline like the text), tinted the name's leader colour, right
-- after the name. Not a font glyph: the bundled gdifonttexture.dll reads text as ANSI, so U+2605 came out garbled.
local function leaderStar(R, d, c, m, s)
    local col = S.leaderStar and leaderColor(d, c) or nil;
    local n = R.name;
    if (col == nil or not n.on or n.cy == nil or F.star == nil) then return; end
    local sz = floor(n.px * 1.05 + 0.5);
    icon(F.star, n.x + n.w + 1 * s, n.cy - sz / 2, sz, fade(col, m));
end

local function qmBorder(o, d)
    local fl = d.flags or 0;
    local col = (bit.band(fl, 0x20) ~= 0) and S.color.aQm or ((bit.band(fl, 0x10) ~= 0) and S.color.qm or nil);
    if (col == nil or not o.on) then return; end
    local w = textSize(o);
    if (w > 0 and o.cy ~= nil) then box(o.x - 2, o.cy - o.px * 0.6, w + 4, o.px * 1.2, col); end -- around glyphs
end

local function addHit(x, y, w, h, nameL)
    local n = F.nHit + 1;
    F.nHit = n;
    F.HX[n], F.HY[n], F.HW[n], F.HH[n], F.HN[n] = x, y, w, h, nameL;
end

-- dark plate behind an in-bar number (clamped to the bar's right edge)
local function plate(R, key, y, h, maxX, s)
    local o = rawget(R, key);
    if (o == nil or not o.on or o.w <= 0) then return; end
    local x = o.x - 1 * s;
    local w = math.min(o.w + 2 * s, maxX - x);
    rect(x, y, w, h, S.color.plate);
end

local function lofiOff(R)
    R.mark.on, R.l1.on, R.l2.on, R.l3.on, R.sl.on = false, false, false, false, false;
    if (R.hpp ~= nil) then R.hpp.on = false; end
end

-- full party row (46 px):
--   MNK99  Arin
--   WAR55  [5114 ========== HP ==========]
--     1.3  [415 ==== MP ====] [3000 === TP ===]   (all bars 13 px, numbers left, outline 2)
local function layParty(R, d, ox, oy, s, sel, sub, c)
    local bw, W, C = S.barW, pW(), S.color;
    local m = rangeMult(d);
    cacheTexts(R, d);
    lofiOff(R);
    rowMark(ox - 2 * s, oy - s, (W + 4) * s, P.h * s, s, sel, sub);

    local jx, nx = ox + P.jw * s, ox + P.x0 * s;
    local hy, my = oy + 17 * s, oy + 33 * s;  -- HP bar 13 px, MP|TP bars 13 px (readable text)
    put(R, 'main', R.mjT, 0, oy + 8 * s, fsz(12, s), jobArgb(d.mj, 0xFFFFFFFF), jx, true);
    put(R, 'sub',  R.sjT, 0, hy + 6 * s, fsz(10, s), jobArgb(d.sj, 0xFFA8A8A8), jx, true);
    put(R, 'name', d.name, nx, oy + 8 * s, fsz(12, s), fade(nameColor(d, c), m), nil, true);
    qmBorder(R.name, d);
    leaderStar(R, d, c, m, s);

    if (d.inZone) then
        local half = (bw - 4) / 2;
        local tx = nx + (half + 4) * s;
        tbar(nx, hy, bw * s, 13 * s, d.hpp / 100, theme.HP_ARGB[lutPct(d.hpp)], m);
        tbar(nx, my, half * s, 13 * s, d.mpp / 100, theme.A.MP, m);
        tbar(tx, my, half * s, 13 * s, math.min(d.tp, 3000) / 3000, theme.tp_argb(d.tp), m);
        rect(tx + half * s / 3, my, 1, 13 * s, theme.A.TICK);     -- 1000 tick
        rect(tx + half * s * 2 / 3, my, 1, 13 * s, theme.A.TICK); -- 2000 tick
        -- numbers: colored per bar (HP by %, MP light blue, TP white/green/gold) on a dark plate so they
        -- stay readable on any fill color; plate is drawn after the fills (rect order = insertion order)
        put(R, 'hp', R.hpT, nx + 3 * s, hy + 6.5 * s, fsz(10, s), hpColor(d.hpp), nil, true);
        put(R, 'mp', R.mpT, nx + 3 * s, my + 6.5 * s, fsz(10, s), C.mpText, nil, true);
        put(R, 'tp', R.tpT, tx + 3 * s, my + 6.5 * s, fsz(10, s), tpColor(d.tp), nil, true);
        plate(R, 'hp', hy, 13 * s, nx + bw * s, s);
        plate(R, 'mp', my, 13 * s, nx + half * s, s);
        plate(R, 'tp', my, 13 * s, tx + half * s, s);
        if (S.showDist and d.idx ~= 0) then
            -- left column, 3rd line (under sub job)
            put(R, 'dist', R.dT, 0, my + 6.5 * s, fsz(10, s), distColor(d.dist), jx, true);
        else
            R.dist.on = false;
        end
        R.zone.on = false;
    else
        R.hp.on, R.mp.on, R.tp.on, R.dist.on = false, false, false, false;
        put(R, 'zone', d.zoneName or zoneName(d.zone), nx, hy + 6 * s, fsz(10, s), 0xFF909090, nil, true);
    end

    if (S.showBuffs and d.inZone and d.buffs ~= nil) then drawBuffs(d.buffs, ox, oy, P.h, W, s, 32); end
    addHit(ox, oy, W * s, P.h * s, R.nmL);
end

-- full alliance row (26 px): NIN  Name  2544 / HP bar / TP bar
local function layAlly(R, d, ox, oy, s, sel, sub, c)
    local bw, W = aBW(), aW();
    local m = rangeMult(d);
    cacheTexts(R, d);
    lofiOff(R);
    R.tp.on = false;
    rowMark(ox - 2 * s, oy - s, (W + 4) * s, A.h * s, s, sel, sub);

    local nx, cy = ox + A.x0 * s, oy + 7 * s;
    put(R, 'main', R.mjT, 0, cy, fsz(10, s), jobArgb(d.mj, 0xFFFFFFFF), ox + A.jw * s, true);
    put(R, 'name', d.name, nx, cy, fsz(10, s), fade(nameColor(d, c), m), nil, true);
    qmBorder(R.name, d);
    leaderStar(R, d, c, m, s);
    if (d.inZone) then
        tbar(nx, oy + 15 * s, bw * s, 5 * s, d.hpp / 100, theme.HP_ARGB[lutPct(d.hpp)], m);
        tbar(nx, oy + 21 * s, bw * s, 3 * s, math.min(d.tp, 3000) / 3000, theme.tp_argb(d.tp), m);
        put(R, 'hp', R.hpT, 0, cy, fsz(10, s), hpColor(d.hpp), nx + bw * s, true);
        R.zone.on = false;
    else
        R.hp.on = false;
        put(R, 'zone', d.zoneName or zoneName(d.zone), nx, oy + 19 * s, fsz(9, s), 0xFF909090, nil, true);
    end
    addHit(ox, oy, W * s, A.h * s, R.nmL);
end

-- low-fi name color: alliance leader > party leader > QM green > white (no boxes/bars)
local function lofiNameColor(d, c)
    local col = nameColor(d, c);
    if (col ~= 0xFFFFFFFF) then return col; end
    local fl = d.flags or 0;
    if (bit.band(fl, 0x30) ~= 0) then return S.color.qm; end
    return col;
end

-- low-fi selected / sub-target member: the row gets full mode's fill (rowMark: light fill; sub-target blue fill +
-- frame) and a '>' right-aligned to rightX, the gap left of the name (gold; sub-target in the sub frame blue).
local LO_MARK_SEL = 0xFFFFD040;
local function lofiMark(R, sel, sub, rightX, cy, h)
    if (sel) then put(R, 'mark', '>', 0, cy, h, LO_MARK_SEL, rightX, true);
    elseif (sub) then put(R, 'mark', '>', 0, cy, h, S.color.subFrame, rightX, true);
    else R.mark.on = false; end
end

local LBL = 0xFF8C8C8C; -- label grey

-- grey label hugging the left side of an existing number text
local function putLbl(R, key, text, numKey, cy, f, s)
    local n = rawget(R, numKey);
    if (n == nil or not n.on) then put(R, key, nil); return; end
    put(R, key, text, 0, cy, f, LBL, n.x - 4 * s, true);
end

-- low-fi party row (40 px, labeled, no bars; the selected / sub-target row gets a fill, rowMark):
--   > Arin                 MNK99/WAR55
--     HP  5114   MP  415   TP 3000    0.3
-- HP number colored by HP%, TP cyan at 1000+, distance orange past cast range.
local function layPartyLo(R, d, ox, oy, s, sel, sub, c)
    cacheTexts(R, d);
    R.hpp.on = false;
    local f9, f10, f11, f12 = fsz(9, s), fsz(10, s), fsz(11, s), fsz(12, s);
    local cy1, cy2 = oy + 9 * s, oy + 28 * s;
    rowMark(ox - 2 * s, oy - s, (PL.w + 4) * s, PL.h * s, s, sel, sub);
    lofiMark(R, sel, sub, ox + 13 * s, cy1, fsz(16, s));
    put(R, 'name', d.name, ox + 14 * s, cy1, f12, fade(lofiNameColor(d, c), rangeMult(d)), nil, true);
    leaderStar(R, d, c, rangeMult(d), s);
    if (S.jobColors) then -- MNK99 / WAR55 as three texts (right to left): sub, grey slash, main
        local rx = ox + PL.w * s;
        put(R, 'sub', R.sjT, 0, cy1, f10, jobArgb(d.sj, 0xFFA8A8A8), rx, true);
        if (R.sub.on) then
            put(R, 'sl', '/', 0, cy1, f10, 0xFF8C8C8C, R.sub.x, true);
            if (R.sl.on) then rx = R.sl.x; end
        else
            R.sl.on = false;
        end
        put(R, 'main', R.mjT, 0, cy1, f10, jobArgb(d.mj, 0xFFA8A8A8), rx, true);
    else
        R.sub.on, R.sl.on = false, false;
        put(R, 'main', R.jbT, 0, cy1, f10, 0xFFA8A8A8, ox + PL.w * s, true);
    end
    if (d.inZone) then
        -- numbers right-aligned in fixed columns; each label hugs its number
        put(R, 'hp', R.hpT, 0, cy2, f11, HP_TXT_LUT[lutPct(d.hpp)], ox + 64 * s, true);
        put(R, 'mp', R.mpT, 0, cy2, f11, LO_MP, ox + 128 * s, true);
        put(R, 'tp', R.tpT, 0, cy2, f11, tpColorLo(d.tp), ox + 192 * s, true);
        putLbl(R, 'l1', 'HP', 'hp', cy2, f9, s);
        putLbl(R, 'l2', 'MP', 'mp', cy2, f9, s);
        putLbl(R, 'l3', 'TP', 'tp', cy2, f9, s);
        if (S.showDist and d.idx ~= 0) then
            put(R, 'dist', R.dT, 0, cy2, f10, distColor(d.dist), ox + PL.w * s, true);
        else
            R.dist.on = false;
        end
        R.zone.on = false;
    else
        R.l1.on, R.l2.on, R.l3.on = false, false, false;
        R.hp.on, R.mp.on, R.tp.on, R.dist.on = false, false, false, false;
        put(R, 'zone', d.zoneName or zoneName(d.zone), ox + 14 * s, cy2, f10, 0xFF909090, nil, true);
    end
    if (S.showBuffs and d.inZone and d.buffs ~= nil) then drawBuffs(d.buffs, ox, oy, PL.h, PL.w, s, 16); end
    addHit(ox, oy, PL.w * s, PL.h * s, R.nmL);
end

-- low-fi alliance row (18 px):  NIN  Name        HP 2544  TP 1956
local function layAllyLo(R, d, ox, oy, s, sel, sub, c)
    cacheTexts(R, d);
    R.l2.on = false;
    local f9, f10 = fsz(9, s), fsz(10, s);
    local cy = oy + 8 * s;
    rowMark(ox - 2 * s, oy - s, (AL.w + 4) * s, AL.h * s, s, sel, sub);
    lofiMark(R, sel, sub, ox + 9 * s, cy, fsz(13, s));
    put(R, 'main', R.mjT, ox + 10 * s, cy, f10, jobArgb(d.mj, 0xFFA8A8A8), nil, true);
    put(R, 'name', d.name, ox + 40 * s, cy, f10, fade(lofiNameColor(d, c), rangeMult(d)), nil, true);
    leaderStar(R, d, c, rangeMult(d), s);
    if (d.inZone) then
        put(R, 'hp', R.hpT, 0, cy, f10, HP_TXT_LUT[lutPct(d.hpp)], ox + 196 * s, true);
        put(R, 'tp', R.tpT, 0, cy, f10, tpColorLo(d.tp), ox + AL.w * s, true);
        putLbl(R, 'l1', 'HP', 'hp', cy, f9, s);
        putLbl(R, 'l3', 'TP', 'tp', cy, f9, s);
        R.zone.on = false;
    else
        R.l1.on, R.l3.on, R.hp.on, R.tp.on = false, false, false, false;
        put(R, 'zone', d.zoneName or zoneName(d.zone), 0, cy, f10, 0xFF909090, ox + AL.w * s, true);
    end
    addHit(ox, oy, AL.w * s, AL.h * s, R.nmL);
end

local function fullTick(party, c)
    F.nR, F.nI, F.nHit, F.nO = 0, 0, 0, 0;
    F.budget, F.iconBudget = FONT_BUDGET, ICON_BUDGET;
    F.pass = F.pass + 1;
    iconsTrim(); -- nothing queued yet this tick
    local entity = S.showDist and mm:GetEntity() or nil;
    if (S.showBuffs and not setup) then
        local now = ashita.time.get_tick64();
        if (now >= F.selfNext) then -- GetBuffs() builds a new table: cap rate
            F.selfNext = now + (S.lowfi and 1000 or 250);
            updateSelfBuffs();
        end
    end
    for li = 0, 2 do
        local L = S[listKeys[li]];
        local s = L.scale * theme.ui_scale;
        local n = 0;
        local enabled = (li == 0) or not S.hideAlliance;
        for k = 0, 5 do
            local idx = li * 6 + k;
            if (enabled and (setup or party:GetMemberIsActive(idx) ~= 0)) then
                local d;
                if (setup) then
                    d = fakes[idx];
                else
                    readMember(party, idx, c.myZone, entity);
                    d = D;
                    if (idx == 0) then d.buffs = selfShown; elseif (idx < 6) then d.buffs = shownBuffs[d.sid]; end
                end
                local sel = d.tidx ~= 0 and d.tidx == c.tMain;
                local sub = (c.stIdx == idx) or (d.tidx ~= 0 and d.tidx == c.tSub);
                local R = getRow(idx);
                if (S.lowfi) then
                    if (li == 0) then layPartyLo(R, d, L.x, L.y + n * PL.h * s, s, sel, sub, c);
                    else layAllyLo(R, d, L.x, L.y + n * AL.h * s, s, sel, sub, c); end
                elseif (li == 0) then
                    layParty(R, d, L.x, L.y + n * P.h * s, s, sel, sub, c);
                else
                    layAlly(R, d, L.x, L.y + n * A.h * s, s, sel, sub, c);
                end
                n = n + 1;
            else
                hideRow(F.rows[idx]);
            end
        end
    end
end

local function drawBody(sp)
    local vpos, vscl = F.vpos, F.vscl;
    if (F.white ~= nil) then
        local RX, RY, RW, RH, RC, white, unit = F.RX, F.RY, F.RW, F.RH, F.RC, F.white, F.unit;
        for i = 1, F.nR do
            vpos.x, vpos.y = RX[i], RY[i];
            vscl.x, vscl.y = RW[i], RH[i];
            sp:Draw(white, unit, vscl, nil, 0.0, vpos, RC[i]);
        end
    end
    local IE, IX, IY, IS, IC = F.IE, F.IX, F.IY, F.IS, F.IC;
    for i = 1, F.nI do
        local e = IE[i];
        vpos.x, vpos.y = IX[i], IY[i];
        vscl.x, vscl.y = IS[i], IS[i];
        sp:Draw(e.tex, e.rect, vscl, nil, 0.0, vpos, IC[i]);
    end
    if (F.white ~= nil) then
        local OX, OY, OW, OH, OC, white, unit = F.OX, F.OY, F.OW, F.OH, F.OC, F.white, F.unit;
        for i = 1, F.nO do
            vpos.x, vpos.y = OX[i], OY[i];
            vscl.x, vscl.y = OW[i], OH[i];
            sp:Draw(white, unit, vscl, nil, 0.0, vpos, OC[i]);
        end
    end
    local texts, one = F.texts, F.one;
    for i = 1, #texts do
        local o = texts[i];
        if (o.on and o.tex ~= nil) then
            vpos.x, vpos.y = o.x, o.y;
            sp:Draw(o.tex, o.rect, one, nil, 0.0, vpos, o.c); -- white glyphs x tint; black outline stays black
        end
    end
end

-- End() always runs, so an error mid-pass cannot leave the sprite begun.
local function draw()
    local sp = F.sprite;
    if (sp == nil) then return; end
    sp:Begin();
    local ok, err = xpcall(drawBody, debug.traceback, sp);
    sp:End();
    if (not ok) then reportErr('draw', err); end
end

-- Queued text rebuilds (a few a frame), then the sprite pass: /goomui perf's draw time includes both.
local function drawFrame()
    if (not gdiFailed) then
        local ok, err = xpcall(serveTexts, debug.traceback, REBUILD_PER_FRAME);
        if (not ok) then reportErr('text', err); end
    end
    draw();
end

local function hoverTip()
    if (F == nil or not hoverOn()) then return; end
    for i = 1, F.nHit do
        local x, y = F.HX[i], F.HY[i];
        local mx, my = ui.mouse_x, ui.mouse_y;
        if (mx >= x and mx < x + F.HW[i] and my >= y and my < y + F.HH[i]) then
            local e = crew.data[F.HN[i]];
            if (e ~= nil) then drawCrewTip(e, ashita.time.get_tick64() / 1000); end
            return;
        end
    end
end

-------------------------------------------------------------------------------
-- tick
-------------------------------------------------------------------------------
local ctx = {};
local function tick()
    tickNow = ashita.time.get_tick64();
    crewTick(tickNow / 1000);
    local party, player = mm:GetParty(), mm:GetPlayer();
    local show = setup or (player:GetLoginStatus() == 2 and player:GetMainJob() ~= 0
                 and party:GetMemberIsActive(0) ~= 0 and not zoning
                 and tickNow >= zoneHold and AshitaCore:GetFontManager():GetVisible());
    if (show and not setup) then
        if (S.hideCutscene and uiBlocked()) then show = false;
        elseif (S.hideSolo and not anyOtherActive(party)) then show = false; end
    end
    if (not show) then hideAll(); return; end
    if (F == nil) then crumb.step('party list: renderer init (gdifonts DLL)'); initRenderer(); end
    if (F.sprite == nil) then
        if (tickNow >= F.spriteRetry) then crumb.step('party list: sprite create'); createSprite(); end
        if (F.sprite == nil) then hideAll(); return; end
    end
    visible = true;

    crumb.step('party list: update (party / target reads)');
    ctx.myZone = party:GetMemberZone(0);
    ctx.tMain, ctx.tSub, ctx.stIdx = getTargets();
    ctx.l1 = party:GetAlliancePartyLeaderServerId1();
    ctx.l2 = party:GetAlliancePartyLeaderServerId2();
    ctx.l3 = party:GetAlliancePartyLeaderServerId3();
    ctx.al = party:GetAllianceLeaderServerId();
    if (setup) then
        ctx.tMain, ctx.tSub, ctx.stIdx, ctx.l1, ctx.l2, ctx.l3, ctx.al = 2, 3, nil, 0, 0, 0, 0;
        local fe = crew.data['member2'];
        if (fe ~= nil) then fe.t = ashita.time.get_tick64() / 1000; end
    end
    fullTick(party, ctx);
end

local function safeTick()
    local ok, err = xpcall(tick, debug.traceback);
    if (not ok) then reportErr('tick', err); hideAll(); end
end

-------------------------------------------------------------------------------
-- setup / config (/goomui or /gui)
-------------------------------------------------------------------------------
local dragInit  = {};
local filterBuf = { '' };
local fontBuf   = { '' };

local function screenSize()
    local w = (scaling.window.w > 0) and scaling.window.w or 1920;
    local h = (scaling.window.h > 0) and scaling.window.h or 1080;
    return w, h;
end

local function listSize(li)
    local s = S[listKeys[li]].scale * theme.ui_scale;
    if (S.lowfi) then
        if (li == 0) then return PL.w * s, PL.h * 6 * s; end
        return AL.w * s, AL.h * 6 * s;
    end
    if (li == 0) then return pW() * s, P.h * 6 * s; end
    return aW() * s, A.h * 6 * s;
end

-- alliance1 above party (right edges aligned), alliance2 left of alliance1
local function snapLists()
    local p, a1, a2 = S.party, S.alliance1, S.alliance2;
    local pw = listSize(0);
    local a1w, a1h = listSize(1);
    local a2w = listSize(2);
    local a2h = select(2, listSize(2));
    a1.x, a1.y = floor(p.x + pw - a1w), floor(p.y - a1h - 6);
    if (S.allyStack) then
        a2.x, a2.y = floor(p.x + pw - a2w), floor(a1.y - a2h - 6); -- above alliance1, right edges aligned
    else
        a2.x, a2.y = floor(a1.x - a2w - 10), a1.y;                 -- left of alliance1
    end
    dragInit = {};
end

-- clamp a list fully on screen (saved position is updated so the drag box matches)
local function clampLists()
    local sw, sh = screenSize();
    for li = 0, 2 do
        local L = S[listKeys[li]];
        local w, h = listSize(li);
        L.x = math.max(0, math.min(L.x, floor(sw - w - 2)));
        L.y = math.max(0, math.min(L.y, floor(sh - h - 2)));
    end
end

local function ensurePositions()
    local w, h = screenSize();
    if ((S.layoutVer or 1) < 2) then -- 1.3.2: wider bars by default (old saves kept 110)
        if (S.barW < 200) then S.barW = 200; end
        S.layoutVer = 2;
    end
    if (S.layoutVer < 3) then -- 1.4: targetbar-style colors, 21.8' cast range
        S.color.mp, S.color.tp, S.color.tpReady = defaults.color.mp, defaults.color.tp, defaults.color.tpReady;
        if (S.castRange == 20.8) then S.castRange = 21.8; end
        S.layoutVer = 3;
    end
    if (S.layoutVer < 4) then -- 1.5.2: debuff marker is a bright frame over the icon
        S.color.debuffBg = defaults.color.debuffBg;
        S.layoutVer = 4;
    end
    if (S.layoutVer < 5) then -- 2.0: sub-target row is brighter and framed
        S.color.sub, S.color.subFrame = defaults.color.sub, defaults.color.subFrame;
        S.layoutVer = 5;
    end
    if (S.party.x < 0) then S.party.x, S.party.y = w - pW() - 20, floor(h * 0.62); end
    if (S.alliance1.x < 0 or S.alliance2.x < 0) then snapLists(); end
    clampLists();
end

local function filtersToString()
    local ids = {};
    for id, on in pairs(S.filters) do
        if (on == true) then ids[#ids + 1] = tonumber(id); end
    end
    table.sort(ids);
    return table.concat(ids, ',');
end

local function setSetup(on)
    setup = on;
    if (on) then
        makeFakes();
        dragInit = {};
        filterBuf[1] = filtersToString();
        fontBuf[1] = S.font;
        crew.data['member2'] = { name = 'Member2', mj = 2, sj = 8, t = ashita.time.get_tick64() / 1000, list = {
            { k = 'A', n = 'Focus', s = 23 }, { k = 'A', n = 'Hundred Fists', s = 3540 }, { k = 'S', n = 'Cure IV', s = 4.5 } } };
        print(chat.header(addon.name):append(chat.message('Party setup on. Drag boxes, hover Member2 for recast preview. /goomui setup again = save.')));
    else
        fakes = nil;
        crew.data['member2'] = nil;
        clampLists();
        settings.save();
        print(chat.header(addon.name):append(chat.message('Saved.')));
    end
end

local function check(label, key, after)
    local v = { S[key] };
    if (imgui.Checkbox(label, v)) then S[key] = v[1]; if (after) then after(); end end
end

local function drawSetup()
    for li = 0, 2 do
        local L = S[listKeys[li]];
        if (li == 0 or not S.hideAlliance) then
            local w, h = listSize(li);
            if (not dragInit[li]) then
                imgui.SetNextWindowPos({ L.x, L.y }, ImGuiCond_Always);
                dragInit[li] = true;
            end
            imgui.SetNextWindowSize({ w, h }, ImGuiCond_Always);
            imgui.PushStyleColor(ImGuiCol_WindowBg, { 1, 1, 0, 0.15 });
            if (imgui.Begin(('goomui drag %d'):fmt(li), true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_NoSavedSettings))) then
                local x, y = imgui.GetWindowPos();
                x, y = floor(x), floor(y);
                if (x ~= L.x or y ~= L.y) then
                    local dx, dy = x - L.x, y - L.y;
                    L.x, L.y = x, y;
                    if (S.group) then
                        for o = 0, 2 do
                            if (o ~= li) then
                                local O = S[listKeys[o]];
                                O.x, O.y = O.x + dx, O.y + dy;
                                dragInit[o] = false; -- re-place next frame
                            end
                        end
                    end
                end
            end
            imgui.End();
            imgui.PopStyleColor(1);
        end
    end

    local open = { true };
    if (imgui.Begin('goomui config', open, ImGuiWindowFlags_AlwaysAutoResize)) then
        check('Low-fi (this char): text only (no bars), 250ms poll', 'lowfi', snapLists);
        check('Move lists together', 'group');
        imgui.SameLine();
        if (imgui.Button('Snap alliances above party')) then snapLists(); end
        check('Snap stacks alliances vertically', 'allyStack', snapLists);
        check('Hide solo', 'hideSolo');
        check('Hide alliance', 'hideAlliance');
        check('Hide in cutscene/map', 'hideCutscene');
        check('Show distance', 'showDist');
        check('Job colours (GoomSwap palette)', 'jobColors');
        check('Leader star', 'leaderStar');
        check('Show buffs', 'showBuffs');
        check('Debuffs on own line (tinted red)', 'debuffLine');
        check('Buffs on right side', 'buffRight');
        check('Filter = whitelist', 'whitelist', rederiveAll);
        if (imgui.InputText('Filter IDs (comma)', filterBuf, 512)) then
            S.filters = T{ };
            for id in filterBuf[1]:gmatch('%d+') do S.filters[tonumber(id)] = true; end
            rederiveAll();
        end
        check('Crew: share my recasts', 'crewShare');
        check('Crew: show recasts on hover', 'crewHover');
        check('Low-fi: allow hover (opt-in)', 'lofiHover');
        local v = { S.updateMs };
        if (imgui.SliderInt('Update ms', v, 16, 250)) then S.updateMs = v[1]; end
        v = { S.lofiMs };
        if (imgui.SliderInt('Low-fi update ms', v, 100, 1000)) then S.lofiMs = v[1]; end
        v = { S.barW };
        if (imgui.SliderInt('Bar width', v, 80, 320)) then S.barW = v[1]; end
        v = { S.textScale };
        if (imgui.SliderFloat('Text size', v, 0.6, 1.6, '%.2f')) then S.textScale = v[1]; applyFont(); end
        v = { S.buffSize };
        if (imgui.SliderInt('Buff size', v, 10, 32)) then S.buffSize = v[1]; end
        v = { S.buffsPerRow };
        if (imgui.SliderInt('Buffs per line', v, 4, 32)) then S.buffsPerRow = v[1]; end
        v = { S.buffGap or 6 };
        if (imgui.SliderInt('Buff spacing', v, 0, 60)) then S.buffGap = v[1]; end
        v = { S.castRange };
        if (imgui.SliderFloat('Cast range', v, 5, 30, '%.1f')) then S.castRange = v[1]; end
        for li = 0, 2 do
            local L = S[listKeys[li]];
            v = { L.scale };
            if (imgui.SliderFloat(listKeys[li] .. ' scale', v, 0.5, 2.5, '%.2f')) then L.scale = v[1]; end
        end
        if (imgui.InputText('Font', fontBuf, 64)) then
            if (fontBuf[1] ~= '' and gdi ~= nil and gdi:get_font_available(fontBuf[1])) then S.font = fontBuf[1]; applyFont(); end
        end
        if (imgui.Button('Save + close')) then open[1] = false; end
    end
    imgui.End();
    if (not open[1]) then setSetup(false); end
end

-------------------------------------------------------------------------------
-- events
-------------------------------------------------------------------------------
settings.register('settings', 'goomui_settings_update', function (s)
    if (s ~= nil) then S = s; end
    ensurePositions();
    applyFont();
    rederiveAll();
end);

ashita.events.register('load', 'goomui_load', function ()
    ensurePositions();
end);

ashita.events.register('unload', 'goomui_unload', function ()
    destroyRenderer();
    if (gdi ~= nil) then gdi:destroy_interface(); gdi = nil; end -- gdifonts readme: required on unload
    crewClose();
end);

-- Commands (dispatched by goomui.lua): /goomui setup | lowfi | crew | perf | tdebug
function M.command(sub)
    if (sub == 'lowfi') then
        S.lowfi = not S.lowfi;
        snapLists();
        settings.save();
        print(chat.header(addon.name):append(chat.message('Low-fi ' .. (S.lowfi and 'on' or 'off') .. ' (this char).')));
        return true;
    end
    if (sub == 'perf') then
        perf.on, perf.stop = true, ashita.time.get_tick64() + 10000;
        perf.tickMax, perf.tickSum, perf.tickN, perf.drawMax, perf.drawSum, perf.drawN = 0, 0, 0, 0, 0, 0;
        print(chat.header(addon.name):append(chat.message('Measuring 10 s...')));
        return true;
    end
    if (sub == 'crew') then
        local names = {};
        local now = ashita.time.get_tick64() / 1000;
        for _, d in pairs(crew.data) do names[#names + 1] = ('%s(%ds)'):fmt(d.name, floor(now - d.t)); end
        print(chat.header(addon.name):append(chat.message(('crew rx port=%s  seen: %s'):fmt(
            tostring(crew.port), (#names > 0) and table.concat(names, ' ') or 'none'))));
        return true;
    end
    if (sub == 'tdebug') then -- target-marker diagnostics: what each check sees right now
        local t, pt = mm:GetTarget(), mm:GetParty();
        local out = function (m) print(chat.header(addon.name):append(chat.message(m))); end
        local stA, stI = 'nil', 'nil';
        local p = AshitaCore:GetPointerManager():Get('party');
        if (p ~= nil and p ~= 0) then
            p = ashita.memory.read_uint32(p);
            if (p ~= 0) then p = ashita.memory.read_uint32(p); end
            if (p ~= 0) then stA, stI = ashita.memory.read_uint32(p + 0x54), ashita.memory.read_uint8(p + 0x50); end
        end
        local tm, ts, st = getTargets();
        out(('isSub=%s idx0=%d idx1=%d act0=%d act1=%d | stpt act=%s idx=%s | tMain=%d tSub=%d stIdx=%s lowfi=%s'):fmt(
            tostring(t:GetIsSubTargetActive()), t:GetTargetIndex(0), t:GetTargetIndex(1),
            t:GetIsActive(0), t:GetIsActive(1), tostring(stA), tostring(stI), tm, ts, tostring(st), tostring(S.lowfi)));
        for idx = 0, 5 do
            if (pt:GetMemberIsActive(idx) ~= 0) then
                local ti = pt:GetMemberTargetIndex(idx);
                local R = F and F.rows[idx];
                local mk = (R ~= nil and rawget(R, 'mark') ~= nil) and tostring(R.mark.on) or '-';
                out(('  [%d] %s tidx=%d sel=%s sub=%s markOn=%s'):fmt(idx, pt:GetMemberName(idx) or '?', ti,
                    tostring(ti ~= 0 and ti == tm), tostring(st == idx or (ti ~= 0 and ti == ts)), mk));
            end
        end
        return true;
    end
    if (sub == 'setup' or sub == 'party') then
        setSetup(not setup);
        return true;
    end
    return false;
end

function M.toggle_setup() setSetup(not setup); end
function M.in_setup() return setup; end

-- Where a widget can sit between the party list and the alliance lists above it (the treasure pool summary), in
-- screen pixels: the party list's right edge and top; the bottom of the lowest alliance member row above it and the
-- top of the highest (nil, nil: no alliance list shown there). Rows are counted, as drawn (full and low-fi heights).
-- Nothing while the lists are hidden.
function M.dock()
    if (not visible) then return nil; end
    local p = S.party;
    local right, top = p.x + listSize(0), p.y;
    local above, stack = nil, nil;
    if (not S.hideAlliance) then
        local party = mm:GetParty();
        for li = 1, 2 do
            local L = S[listKeys[li]];
            if (L.y < top and L.x < right and L.x + listSize(li) > p.x) then
                local n = 0;
                for k = li * 6, li * 6 + 5 do
                    if (setup or party:GetMemberIsActive(k) ~= 0) then n = n + 1; end
                end
                if (n > 0) then
                    local bottom = L.y + n * (S.lowfi and AL.h or A.h) * L.scale * theme.ui_scale;
                    if (above == nil or bottom > above) then above = bottom; end
                    if (stack == nil or L.y < stack) then stack = L.y; end
                end
            end
        end
    end
    return right, top, above, stack;
end
function M.lowfi() return S.lowfi == true; end
function M.set_lowfi(on)
    if ((S.lowfi == true) == on) then return; end
    M.command('lowfi');
end

ashita.events.register('packet_in', 'goomui_packet_in', function (e)
    if (e.id == 0x0076) then
        local data = e.data;
        readAllEntries(function (o) return data:byte(o + 1); end, 4); -- 4-byte header
    elseif (e.id == 0x000B) then
        -- LogoutState 4 (CANCELL): logout cancelled, client stays in zone and no 0x000A follows.
        -- Treating it as a zone left the list hidden until the next zone-in.
        if (e.data:byte(5) ~= 4) then
            zoning = true;
            hideAll();
        end
    elseif (e.id == 0x000A) then
        zoning = false;
        zoneHold = ashita.time.get_tick64() + 3000; -- skip stale pre-zone party data
    end
end);

local function perfReport()
    perf.on = false;
    local function ms(us) return us / 1000; end
    print(chat.header(addon.name):append(chat.message(('tick avg %.3f / max %.3f ms (%d)  draw avg %.3f / max %.3f ms (%d)'):fmt(
        ms(perf.tickSum / math.max(perf.tickN, 1)), ms(perf.tickMax), perf.tickN,
        ms(perf.drawSum / math.max(perf.drawN, 1)), ms(perf.drawMax), perf.drawN))));
end

-- Microseconds fn() took (only while /goomui perf runs: ashita.time.clock() builds a table per call).
local function timed(fn)
    local t0 = ashita.time.clock().micro;
    fn();
    return ashita.time.clock().micro - t0;
end

local function present()
    local now = ashita.time.get_tick64();
    if (setup or now - lastTick >= (S.lowfi and S.lofiMs or S.updateMs)) then
        lastTick = now;
        crumb.step('party list: update');
        if (perf.on) then
            local dt = timed(safeTick);
            perf.tickSum, perf.tickN = perf.tickSum + dt, perf.tickN + 1;
            if (dt > perf.tickMax) then perf.tickMax = dt; end
        else
            safeTick();
        end
    end
    if (visible and F ~= nil and AshitaCore:GetFontManager():GetVisible()) then
        crumb.step('party list: sprite draw');
        if (perf.on) then
            local dt = timed(drawFrame);
            perf.drawSum, perf.drawN = perf.drawSum + dt, perf.drawN + 1;
            if (dt > perf.drawMax) then perf.drawMax = dt; end
        else
            drawFrame();
        end
        crumb.step('party list: hover tip');
        hoverTip();
    end
    if (setup) then crumb.step('party list: setup window'); drawSetup(); end
    if (perf.on and now >= perf.stop) then perfReport(); end
end
-- Whole frame guarded (hover tip, setup window, perf too): an error is printed with its Lua stack instead of
-- Ashita unloading goomui.
ashita.events.register('d3d_present', 'goomui_present', function ()
    crumb.begin('party list');
    theme.scale_begin();
    local ok, err = xpcall(present, debug.traceback);
    theme.scale_end();
    crumb.done();
    if (not ok) then reportErr('frame', err); end
end);

return M;
