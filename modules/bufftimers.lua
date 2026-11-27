--[[
    goomui: time left on party members' buffs, for the party list's buff icon hover tips (party.lua).

    The client gets timers for its own buffs only; other members come as ids, no times (XiPackets 0x0076).
      own ......... IPlayer StatusIcons / StatusTimers and the game's UTC stamp, as statustimers party.lua
                    (HealsCodes: get_utcstamp, buff_duration). XiPackets 0x0063 type 0x09: statusicons_t
                    { int16 icon[32]; uint32 timestamp[32] }, the timestamp overflows on purpose, 0x7FFFFFFF = no
                    timer. The overflow is undone mod 2^32 (statustimers adds 0xFFFFFFFF per wrap: 1/60 s off each).
      crew ........ other goomui boxes send their own list (party.lua crew payload, 'B<id>=<sec>'): exact.
      others ...... estimate, from when the buff landed:
                      gained:  the id shows up in 0x0076 (own list for self), or a 0x028 result lands it (refreshes
                               too: a recast does not change the 0x0076 ids). 0x028 only reaches us in range.
                      'same':  an exact member (self / crew) gained the same id within SAME s (same caster when both
                               are known): that member's end time. AoE: songs, rolls, -ra spells.
                      'learned': last full length seen on an exact member for this id (this caster when known).
                      unknown: had it when first seen (addon load, join, back in zone): no gain time.
    0x028: XiPackets world/server/0x0028 (cmd_no). Messages whose ${status} is the result value, i.e. the status
    id the target gets: Windower Resources action_messages.lua.
]]--

require('common');
local parse_action = require('modules/action');
local dupes = require('modules/dupes'); -- resent 0x028 (modules/dupes.lua)

local M = {};

local SAME, PEND, FRESH_S, ZONE_S, EXACT_S = 2.0, 3.0, 5.0, 10.0, 5.0;
local NO_TIMER, VANA_BASE, U32, I32 = 0x7FFFFFFF, 0x3C307D70, 0x100000000, 0x80000000;
local floor = math.floor;

-- 0x028 cmd_no with buffs / debuffs on players: WS, magic, item, JA, mob skill, pet, DNC, RUN (XiPackets 0x0028)
local CATS = { [3] = true, [4] = true, [5] = true, [6] = true, [11] = true, [13] = true, [14] = true, [15] = true };
-- "<target> gains / receives the effect of ${status}", "<target> is ${status}" (Windower action_messages.lua)
local GAIN = {};
for _, m in ipairs({ 82, 127, 141, 186, 194, 203, 205, 230, 236, 237, 242, 243, 266, 267, 268, 269, 270, 271, 272,
                     277, 278, 279, 280, 319, 320, 375, 412, 645, 754, 755, 804 }) do GAIN[m] = true; end

-------------------------------------------------------------------------------
-- own timers
-------------------------------------------------------------------------------
local utcPtr = ashita.memory.find('FFXiMain.dll', 0, '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3', 2, 0) or 0;

local function utcStamp()
    if (utcPtr == 0) then return nil; end
    local p = ashita.memory.read_uint32(utcPtr);
    if (p == nil or p == 0) then return nil; end
    p = ashita.memory.read_uint32(p);
    if (p == nil or p == 0) then return nil; end
    return ashita.memory.read_uint32(p + 0x0C);
end

-- Own buffs into ids[i], secs[i] (-1 = no timer), slot order. Returns the count (0 when unavailable).
-- GetStatusIcons / GetStatusTimers build tables: call about once a second.
function M.readSelf(ids, secs)
    local n, u = 0, utcStamp();
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    local icons, timers = player:GetStatusIcons(), player:GetStatusTimers();
    if (u ~= nil and icons ~= nil and timers ~= nil) then
        local base = (u - VANA_BASE) * 60;
        for i = 0, 32 do -- covers 0- or 1-based tables
            local id, raw = icons[i], timers[i];
            if (id ~= nil and raw ~= nil and id > 0 and id ~= 255) then
                local s = -1;
                if (raw ~= NO_TIMER) then
                    local d = (raw - base) % U32; -- 1/60 s ticks left
                    if (d >= I32) then d = d - U32; end
                    s = (d < 1) and 0 or math.ceil(d / 60);
                end
                n = n + 1;
                ids[n], secs[n] = id, s;
            end
        end
    end
    for i = #ids, n + 1, -1 do ids[i], secs[i] = nil, nil; end
    return n;
end

-------------------------------------------------------------------------------
-- gain tracking: track[sid][id] = { entry, ... } oldest gain first (unknown first); entry = { g, c, l, endt }
--   g = gain time (s) or false (unknown), c = caster server id, l = length learned, endt = end time (exact members)
-------------------------------------------------------------------------------
local track, fresh, pend, exact = {}, {}, {}, {};
local learnId, learnIC = {}, {}; -- [id] = s, [id * 2^32 + caster] = s
local zoneUntil = 0;
local cnt, tmp = {}, {};

local function older(a, b)
    if (a.g == false) then return b.g ~= false; end
    if (b.g == false) then return false; end
    return a.g < b.g;
end

function M.tracked(sid) return track[sid] ~= nil; end

-- Member's current id list (0x0076 entry, or own list). New ids are timed unless the member is new to us or was
-- just away (out of zone, our zone change): then they were likely already on.
function M.sync(sid, raw, now)
    if (sid == nil or sid == 0) then return; end
    local tr = track[sid];
    local first = (tr == nil) or (now < zoneUntil) or (fresh[sid] ~= nil and now - fresh[sid] <= FRESH_S);
    if (tr == nil) then tr = {}; track[sid] = tr; end
    for k in pairs(cnt) do cnt[k] = nil; end
    for i = 1, #raw do cnt[raw[i]] = (cnt[raw[i]] or 0) + 1; end
    for id, arr in pairs(tr) do
        local n = cnt[id] or 0;
        if (n == 0) then tr[id] = nil;
        else while (#arr > n) do table.remove(arr, 1); end end -- fewer copies: the oldest went
    end
    local p = pend[sid];
    for id, n in pairs(cnt) do
        local arr = tr[id];
        if (arr == nil) then arr = {}; tr[id] = arr; end
        local added = false;
        while (#arr < n) do
            local e = { g = false };
            if (not first) then
                e.g = now;
                local q = p and p[id];
                if (q ~= nil and now - q.t <= PEND) then e.g, e.c = q.t, q.c; p[id] = nil; end
            end
            arr[#arr + 1] = e;
            added = true;
        end
        if (added and #arr > 1) then table.sort(arr, older); end
    end
end

function M.drop(sid) track[sid], pend[sid], fresh[sid] = nil, nil, nil; end
function M.away(sid, now) if (sid ~= nil and sid ~= 0) then fresh[sid] = now; end end -- out of zone
function M.zoned(now) zoneUntil = now + ZONE_S; end

-- A 0x028 result put status id on sid (actor = caster).
local function gained(sid, id, actor, now)
    local tr = track[sid];
    local arr = tr[id];
    if (arr ~= nil and #arr > 0) then
        for j = #arr, 1, -1 do -- 0x0076 came first: the entry it just made
            local x = arr[j];
            if (x.g ~= false and x.c == nil and now - x.g <= PEND) then x.c = actor; return; end
        end
        local e = arr[1]; -- refresh: the oldest copy
        e.g, e.c, e.l = now, actor, false;
        if (#arr > 1) then table.sort(arr, older); end
        return;
    end
    local p = pend[sid];
    if (p == nil) then p = {}; pend[sid] = p; end
    local q = p[id];
    if (q == nil) then q = {}; p[id] = q; end
    q.t, q.c = now, actor;
end

function M.action(e, now)
    if (e.size == nil or e.size < 11) then return; end
    if (not CATS[ashita.bits.unpack_be(e.data_raw, 0, 82, 4)]) then return; end -- cmd_no (action.lua layout)
    if (dupes.repeated(e)) then return; end
    local ok, a = pcall(parse_action, e);
    if (not ok or a == nil) then return; end
    for t = 1, #a.targets do
        local tg = a.targets[t];
        if (track[tg.id] ~= nil) then
            for r = 1, #tg.results do
                local x = tg.results[r];
                local id = x.value;
                if (GAIN[x.message] and id > 0 and id < 1024 and id ~= 255) then gained(tg.id, id, a.actor, now); end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- exact members (self, crew boxes)
-------------------------------------------------------------------------------
-- secs of id's copies in ex, ascending, into tmp; returns the count
local function copies(ex, id)
    local m, ei, es = 0, ex.ids, ex.secs;
    for i = 1, ex.n do
        if (ei[i] == id) then
            m = m + 1;
            local s, j = es[i], m;
            while (j > 1 and tmp[j - 1] > s) do tmp[j] = tmp[j - 1]; j = j - 1; end
            tmp[j] = s;
        end
    end
    return m;
end

-- ids[i] / secs[i] (-1 = no timer) as of time t. Copies pair oldest gain <-> least time left.
function M.setExact(sid, name, ids, secs, n, t)
    if (sid == nil or sid == 0) then return; end
    local ex = exact[sid];
    if (ex == nil) then ex = { ids = {}, secs = {}, n = 0 }; exact[sid] = ex; end
    local ei, es = ex.ids, ex.secs;
    for i = 1, n do ei[i], es[i] = ids[i], secs[i]; end
    for i = #ei, n + 1, -1 do ei[i], es[i] = nil, nil; end
    ex.n, ex.t, ex.name = n, t, name;
    local tr = track[sid];
    if (tr == nil) then return; end
    for id, arr in pairs(tr) do
        local m = copies(ex, id);
        for j = 1, #arr do
            local e = arr[j];
            local s = (j <= m) and tmp[j] or nil;
            if (s ~= nil and s >= 0) then
                e.endt = t + s;
                if (e.g ~= false and not e.l) then -- first look after a gain: learn the full length
                    e.l = true;
                    local full = floor(e.endt - e.g + 0.5);
                    if (t - e.g <= 10 and full > 0) then
                        learnId[id] = full;
                        if (e.c ~= nil) then learnIC[id * U32 + e.c] = full; end
                    end
                end
            else
                e.endt = nil;
            end
        end
    end
end

function M.touch(sid, t) local ex = exact[sid]; if (ex ~= nil) then ex.t = t; end end

-------------------------------------------------------------------------------
-- Time left on copy k of id on sid.
-- Returns secs, kind, extra:  'exact' | 'same' (extra = name) | 'learned' (extra = full s; secs may be < 0)
--   | 'notimer' | 'since' (secs = since gained) | 'unknown'
-------------------------------------------------------------------------------
function M.info(sid, id, k, now)
    local ex = exact[sid];
    if (ex ~= nil and now - ex.t <= EXACT_S) then
        local m = copies(ex, id);
        if (m > 0) then
            local s = tmp[math.min(k, m)];
            if (s < 0) then return nil, 'notimer'; end
            return math.max(0, s - (now - ex.t)), 'exact';
        end
    end
    local arr = track[sid] and track[sid][id];
    local e = arr and arr[math.min(k, #arr)];
    if (e == nil or e.g == false) then return nil, 'unknown'; end
    local best, bestD, who = nil, SAME, nil;
    for xs, x in pairs(exact) do
        local xa = (xs ~= sid and now - x.t <= EXACT_S) and track[xs] and track[xs][id];
        if (xa) then
            for j = 1, #xa do
                local y = xa[j];
                if (y.g ~= false and y.endt ~= nil and (e.c == nil or y.c == nil or e.c == y.c)) then
                    local dg = math.abs(y.g - e.g);
                    if (dg <= bestD) then best, bestD, who = y.endt, dg, x.name; end
                end
            end
        end
    end
    if (best ~= nil) then return math.max(0, best - now), 'same', who; end
    local full = (e.c ~= nil and learnIC[id * U32 + e.c]) or learnId[id];
    if (full ~= nil) then return e.g + full - now, 'learned', full; end
    return now - e.g, 'since';
end

-- /goomui bt: what is tracked and learned
function M.debug(out, nameOf)
    local now = ashita.time.get_tick64() / 1000;
    local parts = {};
    for id, s in pairs(learnId) do parts[#parts + 1] = ('%d=%ds'):fmt(id, s); end
    out(('learned (%d): %s'):fmt(#parts, (#parts > 0) and table.concat(parts, ' ') or 'none'));
    for sid, tr in pairs(track) do
        parts = {};
        for id, arr in pairs(tr) do
            for j = 1, #arr do
                local e = arr[j];
                parts[#parts + 1] = ('%d:%s%s'):fmt(id, (e.g == false) and '?' or ('%ds'):fmt(floor(now - e.g)),
                    (e.c ~= nil) and '*' or '');
            end
        end
        local ex = exact[sid];
        out(('  %s%s: %s'):fmt(nameOf(sid) or tostring(sid),
            (ex ~= nil and now - ex.t <= EXACT_S) and ' (exact)' or '', table.concat(parts, ' ')));
    end
end

return M;
