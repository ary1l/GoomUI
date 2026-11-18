--[[
* goomui: 0x028 action packet (XiPackets GP_SERV_COMMAND_BATTLE2) as plain tables, for the rings, AAEV and the
* mob debuff row. Bit widths:
*   head    m_uID 32 (from bit 40), trg_sum 6, res_sum 4, cmd_no 4, cmd_arg 32, info 32
*   target  m_uID 32, result_sum 4
*   result  miss 3, kind 2, sub_kind 12, info 5, scale 5, value 17, message 10, bit 31,
*           has_proc 1 (+ proc_kind 6, proc_info 4, proc_value 17, proc_message 10),
*           has_react 1 (+ react_kind 6, react_info 4, react_value 14, react_message 10)
* Returns nil when the packet is shorter than its counts say.
--]]

local unpack_bits = ashita.bits.unpack_be;

return function (e)
    local raw, pos, max, short = e.data_raw, 40, e.size * 8, false;
    local function take(n)
        if (pos + n > max) then short = true; return 0; end
        local v = unpack_bits(raw, 0, pos, n);
        pos = pos + n;
        return v;
    end

    local a = { actor = take(32), targets = {} };
    local nt = take(6);
    take(4);
    a.category = take(4);
    a.param = take(32);
    a.info = take(32);
    for t = 1, nt do
        local tg = { id = take(32), results = {} };
        for r = 1, take(4) do
            take(5);
            local x = { sub_kind = take(12) };
            take(10);
            x.value, x.message = take(17), take(10);
            take(31);
            if (take(1) == 1) then take(10); x.proc = { value = take(17), message = take(10) }; end
            if (take(1) == 1) then take(10); x.react = { value = take(14), message = take(10) }; end
            tg.results[r] = x;
        end
        a.targets[t] = tg;
        if (short) then return nil; end
    end
    if (short) then return nil; end
    return a;
end
