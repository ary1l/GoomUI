--[[
* goomui: resent action packets (0x028).
*
* The server sends a packet the client did not acknowledge again, byte for byte (its header sync count included),
* and the client hands it to addons a second time: AAEV logged weapon skills twice. simplelog (Byrth; Spiken's Ashita
* port) blocks the same repeats in its check_duplicates (identical packets seen in the last three chunks).
*
* Here an identical 0x028 first seen SAME to WINDOW seconds earlier is a repeat. Every goomui 0x028 handler asks;
* the answer is worked out once per packet (the handlers of one packet run within SAME of each other), so the first
* handler's record does not turn the packet into a repeat for the next one. Two identical packets in one chunk (same
* sync count, same moment) both count.
--]]

local M = {};

local WINDOW, SAME, CAP = 4.0, 0.02, 2048;

local seen = {};              -- packet bytes -> os.clock() when first seen
local qk, qt = {}, {};        -- the same keys and times, oldest first (qh .. qn)
local qh, qn = 1, 0;
local cur_key, cur_t, cur_dupe = nil, -1, false;

local function forget(now)
    while (qh <= qn and (now - qt[qh] > WINDOW or (qn - qh) >= CAP)) do
        local k = qk[qh];
        if (seen[k] == qt[qh]) then seen[k] = nil; end
        qk[qh], qt[qh] = nil, nil;
        qh = qh + 1;
    end
    if (qh > qn) then qh, qn = 1, 0; end
end

-- True when e (an incoming 0x028) repeats one already handled.
function M.repeated(e)
    local key = e.data;
    if (key == nil) then return false; end
    local now = os.clock();
    if (key == cur_key and now - cur_t < SAME) then return cur_dupe; end -- this packet, the next goomui handler
    forget(now);
    local t = seen[key];
    local dupe = (t ~= nil) and (now - t >= SAME);
    if (t == nil) then
        seen[key] = now;
        qn = qn + 1;
        qk[qn], qt[qn] = key, now;
    end
    cur_key, cur_t, cur_dupe = key, now, dupe;
    return dupe;
end

return M;
