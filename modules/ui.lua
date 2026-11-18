--[[
* goomui: client UI state shared by the party list, the rings and the mob debuff row.
*   hidden / event / menu: signatures from Tirem's statushelpers (credit Velyn), as XIUI uses them.
*   mouse: WM_MOUSEMOVE (512) position, as atom0s' crosshair addon reads it.
--]]

local U = { mouse_x = -1, mouse_y = -1 };

local SIGS = {
    menu   = { '8B480C85C974??8B510885D274??3B05', 16 },
    event  = { 'A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3', 0 },
    hidden = { '8B4424046A016A0050B9????????E8????????F6D81BC040C3', 0 },
};
local ORDER = { 'menu', 'event', 'hidden' };
local ptr = {};

local function find(k)
    local p = ptr[k];
    if (p == nil) then
        p = ashita.memory.find('FFXiMain.dll', 0, SIGS[k][1], SIGS[k][2], 0) or 0;
        ptr[k] = p;
    end
    return p;
end

-- Resolves at most one signature per call (a scan of FFXiMain.dll is slow); true once all are known.
function U.warm()
    for _, k in ipairs(ORDER) do
        if (ptr[k] == nil) then find(k); return false; end
    end
    return true;
end

-- The interface-hidden flag: the UI toggle and the letterboxed part of cutscenes.
function U.hidden()
    local p = find('hidden');
    if (p == 0) then return false; end
    p = ashita.memory.read_uint32(p + 10);
    return p ~= 0 and ashita.memory.read_uint8(p + 0xB4) == 1;
end

-- An event (cutscene / NPC dialogue) is running.
function U.event()
    local p = find('event');
    if (p == 0) then return false; end
    p = ashita.memory.read_uint32(p + 1);
    return p ~= 0 and ashita.memory.read_uint8(p) == 1;
end

-- Name of the menu that holds focus ('' when none).
function U.menu()
    local p = find('menu');
    if (p == 0) then return ''; end
    p = ashita.memory.read_uint32(p);
    if (p == 0) then return ''; end
    p = ashita.memory.read_uint32(p);
    if (p == 0) then return ''; end
    p = ashita.memory.read_uint32(p + 4);
    if (p == 0) then return ''; end
    return ((ashita.memory.read_string(p + 0x46, 16) or ''):gsub('%z', ''));
end

ashita.events.register('mouse', 'goomui_ui_mouse', function (e)
    if (e.message == 512) then U.mouse_x, U.mouse_y = e.x, e.y; end
end);

return U;
