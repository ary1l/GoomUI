--[[
* goomui: hide the game's own party list, alliance lists and target frame (Party tab > Game UI), for goomui's party
* list and target cursor in their place.
*
* Method of Ashita's bundled hideparty addon (atom0s): two signatures give the frames' objects; each frame, a hidden
* frame's primitive gets its two visibility bytes set to 0 (+0x69 and +0x6A of the object pointed to at +0x08 of the
* frame object). atom0s notes the game's stock target cursor goes too when its frames are hidden.
*
* Only frames switched on here are written. One switched back off (or goomui unloaded) is shown once and then left
* alone, so the game and other addons keep control of it. Do not run hideparty as well: while loaded it writes
* every frame.
--]]

local M = {};

-- hideparty.lua: main party (+0x19) and target (+0x23) frames; alliance frames (+0x01, +0x07).
local SIG_MAIN = '66C78182000000????C7818C000000????????C781900000';
local SIG_ALLY = 'A1????????8B0D????????89442424A1????????33DB89';

local ptrs = nil   -- { party, ally1, ally2, target }; false: a signature was not found
local hidden = {}  -- frame name -> true while goomui keeps it hidden

local function resolve()
    local p1 = ashita.memory.find(0, 0, SIG_MAIN, 0, 0) or 0;
    local p2 = ashita.memory.find(0, 0, SIG_ALLY, 0, 0) or 0;
    if (p1 == 0 or p2 == 0) then return false; end
    return {
        party  = ashita.memory.read_uint32(p1 + 0x19),
        target = ashita.memory.read_uint32(p1 + 0x23),
        ally1  = ashita.memory.read_uint32(p2 + 0x01),
        ally2  = ashita.memory.read_uint32(p2 + 0x07),
    };
end

local function set_visible(p, v)
    if (p == nil or p == 0) then return; end
    local o = ashita.memory.read_uint32(p);
    if (o == 0) then return; end
    o = ashita.memory.read_uint32(o + 0x08);
    if (o == 0) then return; end
    ashita.memory.write_uint8(o + 0x69, v);
    ashita.memory.write_uint8(o + 0x6A, v);
end

-- name -> the frames it covers
local FRAMES = { party = { 'party' }, alliance = { 'ally1', 'ally2' }, target = { 'target' } };

-- Each frame (d3d_present): cfg = the bar settings (hide_game_party / hide_game_alliance / hide_game_target).
function M.apply(cfg)
    if (cfg == nil) then return; end
    local want = { party = cfg.hide_game_party == true, alliance = cfg.hide_game_alliance == true,
        target = cfg.hide_game_target == true };
    if (ptrs == nil and (want.party or want.alliance or want.target)) then ptrs = resolve(); end
    if (not ptrs) then return; end
    for name, frames in pairs(FRAMES) do
        if (want[name]) then
            for _, f in ipairs(frames) do set_visible(ptrs[f], 0); end
            hidden[name] = true;
        elseif (hidden[name]) then
            for _, f in ipairs(frames) do set_visible(ptrs[f], 1); end
            hidden[name] = nil;
        end
    end
end

-- False when a signature was not found (this client build): the GUI says the options do nothing.
function M.available() return ptrs ~= false; end

-- Unload: show what goomui hid.
function M.restore()
    if (not ptrs) then return; end
    for name in pairs(hidden) do
        for _, f in ipairs(FRAMES[name]) do set_visible(ptrs[f], 1); end
    end
    hidden = {};
end

return M;
