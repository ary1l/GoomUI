--[[
    goomui: treasure pool window. Items in the pool, time left, and every member's lot / pass.

    Sources (checked 2026-11):
      items ........ Ashita v4 SDK ffxi/inventory.h treasureitem_t via IInventory:GetTreasurePoolItem(0-9)
                     (ItemId, Count, Lot, WinningLot, WinningEntityName, DropTime). Own Lot: 0 = none,
                     65535 = passed (XIUI treasurepool/data.lua).
      0x0D2 ........ XiPackets GP_SERV_COMMAND_TROPHY_LIST: item found -> pool. 0x10 TrophyItemNo u16,
                     0x14 TrophyItemIndex u8 (pool slot).
      0x0D3 ........ XiPackets GP_SERV_COMMAND_TROPHY_SOLUTION: someone lotted / passed, or the item was
                     judged. 0x08 EntryUniqueNo u32, 0x12 EntryPoint i16, 0x14 TrophyItemIndex u8,
                     0x15 JudgeFlg u8 (>= 1: item gone), 0x26 sLootName2[16] (who acted).
                     Lot vs pass is read from EntryPoint (< 0 = pass, as XIUI does): XiPackets and XIUI
                     disagree on the EntryFlg bit, so it is not used. Lots are 0-999 (FFXIclopedia "Cast Lots").
      timeout ...... 5 minutes from the drop (FFXIclopedia "Treasure Pool"). Timed from when goomui saw the
                     0x0D2; items already in the pool at load / zone-in show no timer.
    Lots made before goomui loaded (or before you zoned in) are not known; the leader still comes from memory.

    Docked (pool_dock, the default): a one-line summary (items, how many you have not acted on, soonest time left)
    sits between the party list and alliance 1; clicking it shows or hides the full window. Not docked: the window.

    Buttons (lot / pass, lot all / pass all) send what the client sends from its own treasure menu:
      0x041 ........ XiPackets GP_CLI_COMMAND_TROPHY_ENTRY (size 0x08): 0x04 TrophyItemIndex, 0x05 PropertyItemIndex.
                     PropertyItemIndex sent as 0, as XIUI treasurepool/actions.lua does.
      0x042 ........ XiPackets GP_CLI_COMMAND_TROPHY_ABSENCE (size 0x06, sent padded to 8 as XIUI does):
                     0x04 TrophyItemIndex.
      injected with AshitaCore:GetPacketManager():AddOutgoingPacket(id, bytes) (Ashita v4 IPacketManager).
--]]

local imgui    = require('imgui');
local settings = require('settings');
local theme    = require('modules/theme');

local M = {};

local POOL_SECS  = 300;
local ZONE_GRACE = 5;     -- s after a zone packet: 0x0D2s are the pool resync, not new drops
local GONE_READS = 3;     -- reads a slot must be empty before its lots are dropped
local WIDTH      = 300;

local cfg  = nil;          -- bar.lua settings table (pool_* keys live there)
local hist = {};           -- slot -> { key, item, seen (s or nil), lots = { sid -> {name, lot} }, pass = { sid -> name } }
local fresh = {};          -- slot -> { item, t }: a 0x0D2 for a new drop, waiting for memory to show it
local gone = {};           -- slot -> empty reads in a row
local zoned_at = -100;
local demo = false;
local placed = false;      -- window position applied since it last appeared (then it is dragged freely)
local moved = false;
local passAllAt = -100;    -- 'Pass all' asks for a second click within 3 s
local p_open = { true };

local COL = {
    title  = { 0.85, 0.75, 0.45, 1.0 },
    item   = { 1.00, 1.00, 1.00, 1.0 },
    timer  = { 0.70, 0.70, 0.75, 1.0 },
    urgent = { 1.00, 0.45, 0.35, 1.0 },
    lead   = { 1.00, 0.82, 0.25, 1.0 },
    lot    = { 0.80, 0.90, 1.00, 1.0 },
    me     = { 0.55, 1.00, 0.55, 1.0 },
    pass   = { 0.55, 0.55, 0.55, 1.0 },
    wait   = { 0.45, 0.45, 0.50, 1.0 },
};
local PANEL_BG = theme.u32(14, 12, 6, 150);
local ACCENT   = theme.u32(200, 165, 70);
-- the summary chip's outlined text (same hues as COL)
local CHIP_COL = {
    title = theme.u32(217, 191, 115), item = theme.u32(255, 255, 255), me = theme.u32(140, 255, 140),
    timer = theme.u32(190, 190, 200), urgent = theme.u32(255, 115, 89), dim = theme.u32(160, 160, 170),
};

-- Clickable (buttons) and draggable anywhere off the buttons; position saved on release.
local FLAGS = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize,
    ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground);

local function now() return ashita.time.get_tick64() / 1000; end

local function cstr(data, off, n) -- fixed-size, NUL-padded name
    local s = data:sub(off + 1, off + n);
    return s:match('^[^%z]*') or '';
end

local names = {};
local function item_name(id)
    local n = names[id];
    if (n == nil) then
        local r = AshitaCore:GetResourceManager():GetItemById(id);
        n = (r ~= nil and r.Name ~= nil and r.Name[1] ~= nil and r.Name[1] ~= '') and r.Name[1] or ('item ' .. id);
        names[id] = n;
    end
    return n;
end

local function new_hist(key, item, seen)
    return { key = key, item = item, seen = seen, lots = {}, pass = {} };
end

------------------------------------------------------------
-- lot / pass (outgoing)
------------------------------------------------------------
local function send(id, slot)
    AshitaCore:GetPacketManager():AddOutgoingPacket(id, { id, 0x04, 0x00, 0x00, slot, 0x00, 0x00, 0x00 });
end
local function lot(slot)  if (not demo) then send(0x41, slot); end end
local function pass(slot) if (not demo) then send(0x42, slot); end end

------------------------------------------------------------
-- packets
------------------------------------------------------------
function M.packet_in(e)
    if (e.id == 0x000A) then
        zoned_at = now();
    elseif (e.id == 0x00D2) then
        local item = struct.unpack('H', e.data, 0x10 + 1);
        local slot = struct.unpack('B', e.data, 0x14 + 1);
        if (item ~= 0 and slot < 10 and now() - zoned_at > ZONE_GRACE) then
            fresh[slot] = { item = item, t = now() };
        end
    elseif (e.id == 0x00D3) then
        local slot = struct.unpack('B', e.data, 0x14 + 1);
        if (slot >= 10) then return; end
        if (struct.unpack('B', e.data, 0x15 + 1) >= 1) then -- judged: won, lost or cleared
            hist[slot], fresh[slot] = nil, nil;
            return;
        end
        local sid  = struct.unpack('I4', e.data, 0x08 + 1);
        local pt   = struct.unpack('h', e.data, 0x12 + 1);
        local name = cstr(e.data, 0x26, 16);
        if (sid == 0 or name == '') then return; end
        local h = hist[slot];
        if (h == nil) then h = new_hist(nil, 0, nil); hist[slot] = h; end -- memory catches up next frame
        if (pt < 0) then
            h.lots[sid], h.pass[sid] = nil, name;
        else
            h.lots[sid], h.pass[sid] = { name = name, lot = pt }, nil;
        end
    end
end

------------------------------------------------------------
-- memory read (once per frame)
------------------------------------------------------------
local rows = {};  -- reused: { slot, h, my, lead, leadLot }

local function read_pool()
    local inv = AshitaCore:GetMemoryManager():GetInventory();
    local n = 0;
    for slot = 0, 9 do
        local it = inv:GetTreasurePoolItem(slot);
        local id = (it ~= nil) and it.ItemId or 0;
        if (id ~= nil and id > 0 and id ~= 65535) then
            gone[slot] = 0;
            local key = id .. ':' .. tostring(it.DropTime);
            local h = hist[slot];
            if (h ~= nil and h.key == nil and (h.item == 0 or h.item == id)) then
                h.key, h.item = key, id; -- lots arrived before memory showed the item
            end
            if (h == nil or h.key ~= key) then
                local f = fresh[slot];
                local seen = (f ~= nil and f.item == id) and f.t or nil;
                h = new_hist(key, id, seen);
                hist[slot] = h;
            end
            local f = fresh[slot];
            if (h.seen == nil and f ~= nil and f.item == id) then h.seen = f.t; end
            fresh[slot] = nil;
            n = n + 1;
            local r = rows[n] or {};
            rows[n] = r;
            r.slot, r.h, r.my = slot, h, it.Lot or 0; -- one item per slot: three crystals are three slots (XiPackets 0x0D2 TrophyItemNum)
            r.lead = (it.WinningEntityName ~= nil) and tostring(it.WinningEntityName):match('^[^%z]*') or '';
            r.leadLot = it.WinningLot or 0;
        else
            gone[slot] = (gone[slot] or 0) + 1;
            if (gone[slot] >= GONE_READS and hist[slot] ~= nil and hist[slot].key ~= nil) then hist[slot] = nil; end
        end
    end
    for i = n + 1, #rows do rows[i] = nil; end
    return n;
end

------------------------------------------------------------
-- demo rows (/goomui pool demo)
------------------------------------------------------------
local function demo_rows()
    local t = now();
    local function H(id, seen, lots, passes, n)
        local h = new_hist('demo' .. id .. ':' .. (n or 1), id, seen);
        for i, l in ipairs(lots) do h.lots[i] = { name = l[1], lot = l[2] }; end
        for i, p in ipairs(passes) do h.pass[100 + i] = p; end
        return h;
    end
    -- Member1 = you (same placeholder names as the party list setup)
    rows[1] = { slot = 0, my = 0, lead = 'Member3', leadLot = 912,
        h = H(16555, t - 40, { { 'Member3', 912 }, { 'Member4', 455 } }, { 'Member6' }) };
    rows[2] = { slot = 1, my = 65535, lead = '', leadLot = 0,
        h = H(13014, t - 250, {}, { 'Member2', 'Member5' }) };
    -- three of the same drop: three slots, one item each (the pool never stacks them)
    for i = 0, 2 do
        rows[3 + i] = { slot = 2 + i, my = 0, lead = '', leadLot = 0, h = H(844, t - 15, {}, {}, i + 1) };
    end
    for i = 6, #rows do rows[i] = nil; end
    return 5;
end

------------------------------------------------------------
-- draw
------------------------------------------------------------
local list = {};
local function sorted_lots(h)
    for i = #list, 1, -1 do list[i] = nil; end
    for _, l in pairs(h.lots) do list[#list + 1] = l; end
    table.sort(list, function (a, b) return a.lot > b.lot; end);
    return list;
end

-- A row's lots, passes and waiting count flow left to right and start a new line when the next piece does not fit
-- (always on the same line, a piece near the edge wrapped one letter per line). A piece wider than the row wraps
-- from a line start (the window's wrap position), and the next one starts below it.
local ROW_W = WIDTH - 24; -- inside the window padding and the row indent
local lineX = 0;          -- px used on the current line
local function inline(col, s, first)
    local w = imgui.CalcTextSize(s);
    if (not first) and (lineX + 6 + w <= ROW_W) then
        imgui.SameLine(0, 6);
        lineX = lineX + 6 + w;
    else
        lineX = (w > ROW_W) and ROW_W or w;
    end
    imgui.TextColored(col, s);
end

local function draw_row(r, party, myName, myZone)
    local h = r.h;
    local name = item_name(h.item);
    -- [Lot] while you have not acted, [Pass] until you passed; then the name; time left at the right edge
    local sid = tostring(r.slot);
    if (r.my == 0) then
        if (imgui.SmallButton('Lot##goomui_pool_lot' .. sid)) then lot(r.slot); end
        imgui.SameLine(0, 4);
    end
    if (r.my ~= 65535) then
        if (imgui.SmallButton('Pass##goomui_pool_pass' .. sid)) then pass(r.slot); end
        imgui.SameLine(0, 6);
    end
    imgui.TextColored(COL.item, name);
    if (h.seen ~= nil) then
        local left = math.max(0, POOL_SECS - (now() - h.seen));
        local t = ('%d:%02d'):fmt(math.floor(left / 60), math.floor(left % 60));
        imgui.SameLine(WIDTH - 12 - imgui.CalcTextSize(t));
        imgui.PushTextWrapPos(-1); -- never wrap the timer
        imgui.TextColored(left < 60 and COL.urgent or COL.timer, t);
        imgui.PopTextWrapPos();
    end

    -- who acted: lots high to low (leader gold, you green), then passes, then members still to act
    local acted, first = {}, true;
    imgui.Indent(8);
    local lots = sorted_lots(h);
    local mineShown = false;
    for i = 1, #lots do
        local l = lots[i];
        acted[l.name] = true;
        local col = (l.name == myName) and COL.me or ((l.name == r.lead or (i == 1 and r.lead == '')) and COL.lead or COL.lot);
        if (l.name == myName) then mineShown = true; end
        inline(col, ('%s %d'):fmt(l.name, l.lot), first); first = false;
    end
    if (not mineShown and r.my > 0 and r.my < 65535) then -- own lot from memory (e.g. made before goomui saw it)
        inline(COL.me, ('%s %d'):fmt(myName, r.my), first); first = false; acted[myName] = true;
    end
    if (#lots == 0 and r.lead ~= '' and r.leadLot > 0 and not acted[r.lead]) then
        inline(COL.lead, ('%s %d'):fmt(r.lead, r.leadLot), first); first = false; acted[r.lead] = true;
    end
    local ps = {};
    for _, nm in pairs(h.pass) do acted[nm] = true; ps[#ps + 1] = nm; end
    if (r.my == 65535 and not acted[myName]) then acted[myName] = true; ps[#ps + 1] = myName; end -- own pass (memory)
    if (#ps > 0) then
        table.sort(ps);
        inline(COL.pass, 'pass: ' .. table.concat(ps, ', '), first); first = false;
    end
    if (party ~= nil and not demo) then
        -- members in this zone still to act; trusts (entity index 1792+, XiPackets 0x00E: spawnables) never lot
        local w = {};
        for i = 0, 17 do
            if (party:GetMemberIsActive(i) ~= 0 and party:GetMemberZone(i) == myZone
                and party:GetMemberTargetIndex(i) < 1792) then
                local nm = party:GetMemberName(i);
                if (nm ~= nil and nm ~= '' and not acted[nm]) then w[#w + 1] = nm; end
            end
        end
        if (#w > 0) then -- a count; the names on hover (an alliance's 17 names were most of the window)
            inline(COL.wait, ('waiting %d'):fmt(#w), first); first = false;
            if (imgui.IsItemHovered()) then imgui.SetTooltip(table.concat(w, ', ')); end
        end
    end
    if (first) then imgui.TextColored(COL.wait, 'no lots yet'); end
    imgui.Unindent(8);
end

local function draw_rows(n, party, myName, myZone)
    for i = 1, n do
        imgui.Separator();
        draw_row(rows[i], party, myName, myZone);
    end
end

-- title row: Lot all (items you have not acted on) / Pass all (needs a second click within 3 s)
local function draw_title(n)
    imgui.TextColored(COL.title, demo and 'Treasure pool (demo)' or 'Treasure pool');
    imgui.SameLine(0, 10);
    if (imgui.SmallButton('Lot all##goomui_pool_lotall')) then
        for i = 1, n do if (rows[i].my == 0) then lot(rows[i].slot); end end
    end
    imgui.SameLine(0, 4);
    local confirm = (now() - passAllAt) < 3;
    if (imgui.SmallButton((confirm and 'Pass all? again' or 'Pass all') .. '##goomui_pool_passall')) then
        if (confirm) then
            passAllAt = -100;
            for i = 1, n do if (rows[i].my ~= 65535) then pass(rows[i].slot); end end
        else
            passAllAt = now();
        end
    end
end

------------------------------------------------------------
-- summary (docked between the party list and alliance 1)
------------------------------------------------------------
local CHIP_FLAGS = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize,
    ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoMove);
local chipW, chipH = 150, 16; -- its size last frame (placement uses it)
local CHIP_PAD = { 6, 1 };     -- one text line high: fits the low-fi gap under an alliance (one empty 12 px row + 6)
local CHIP_GAP = 10;           -- px between its pieces
local chip_open = { true };
local chip_t, chip_c, chip_n = {}, {}, 0;
local function piece(t, c) chip_n = chip_n + 1; chip_t[chip_n], chip_c[chip_n] = t, c; end

local function dock()
    local party = package.loaded['modules/party'];
    if (party == nil or party.dock == nil) then return nil; end
    return party.dock();
end

local function summary(n) -- items you have not acted on, soonest time left (nil: none timed), newest drop seen
    local act, soon, newest = 0, nil, nil;
    for i = 1, n do
        local r = rows[i];
        if (r.my == 0) then act = act + 1; end
        local seen = r.h.seen;
        if (seen ~= nil) then
            local left = math.max(0, POOL_SECS - (now() - seen));
            if (soon == nil or left < soon) then soon = left; end
            if (newest == nil or seen > newest) then newest = seen; end
        end
    end
    return act, soon, newest;
end

-- Right-aligned to the party list: centred in the gap under the alliance's last member row; no room there (a full
-- alliance), above the alliance lists, never over a member; no alliance, just above the party list. With the lists
-- hidden, just above the window's saved spot.
local function draw_chip(n)
    local right, top, above, stack = dock();
    local x, y = cfg.pool_x, cfg.pool_y - chipH - 4;
    if (right ~= nil) then
        x = math.floor(right - chipW);
        if (above == nil) then
            y = math.floor(top - chipH - 4);
        elseif ((top - above) >= chipH + 4) then
            y = math.floor(above + ((top - above) - chipH) / 2);
        else
            y = math.floor(stack - chipH - 4);
        end
    end
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    chip_open[1] = true;
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, CHIP_PAD);
    if (imgui.Begin('##goomui_pool_chip', chip_open, CHIP_FLAGS)) then
        local wx, wy = imgui.GetWindowPos();
        local ww, wh = imgui.GetWindowSize();
        chipW, chipH = ww, wh;
        local act, soon, newest = summary(n);
        local dl = imgui.GetWindowDrawList();
        dl:AddRectFilled({ wx, wy }, { wx + ww, wy + wh }, theme.scale_alpha(PANEL_BG, theme.panel_alpha), 4.0);
        dl:AddRectFilled({ wx, wy + 2 }, { wx + 3, wy + wh - 2 }, ACCENT);
        if (newest ~= nil and now() - newest < 4) then -- a new drop: outlined for a few seconds
            dl:AddRect({ wx, wy }, { wx + ww, wy + wh }, ACCENT, 4.0, 0, 1.5);
        end
        -- Pool  5 items  4 to lot  0:50 left  [+]   (outlined like the party list text)
        chip_n = 0;
        piece(demo and 'Pool (demo)' or 'Pool', CHIP_COL.title);
        piece((n == 1) and '1 item' or (n .. ' items'), CHIP_COL.item);
        if (act > 0) then piece(act .. ' to lot', CHIP_COL.me); end
        if (soon ~= nil) then
            piece(('%d:%02d left'):fmt(math.floor(soon / 60), math.floor(soon % 60)),
                (soon < 60) and CHIP_COL.urgent or CHIP_COL.timer);
        end
        piece(cfg.pool_open and '[-]' or '[+]', CHIP_COL.dim);
        local tw = 0;
        for i = 1, chip_n do tw = tw + imgui.CalcTextSize(chip_t[i]) + ((i > 1) and CHIP_GAP or 0); end
        local _, th = imgui.CalcTextSize('Hg');
        local tx, ty = imgui.GetCursorScreenPos();
        imgui.Dummy({ tw + 2, th });
        tx = tx + 1;
        for i = 1, chip_n do
            theme.text_outlined(dl, tx, ty, chip_c[i], chip_t[i]);
            tx = tx + imgui.CalcTextSize(chip_t[i]) + CHIP_GAP;
        end
        if (imgui.IsWindowHovered()) then
            imgui.SetTooltip(cfg.pool_open and 'Click: hide the pool window' or 'Click: show the pool window');
            if (imgui.IsMouseClicked(0)) then
                cfg.pool_open = not cfg.pool_open;
                placed = false;
                pcall(settings.save, 'bar');
            end
        end
    end
    imgui.End();
    imgui.PopStyleVar();
end

function M.render()
    if (cfg == nil or cfg.show_pool == false) then return; end
    local n = demo and demo_rows() or read_pool();
    if (n == 0) then placed = false; return; end
    if (cfg.pool_dock ~= false) then
        draw_chip(n);
        if (not cfg.pool_open) then placed = false; return; end
    end

    local party = AshitaCore:GetMemoryManager():GetParty();
    local myName = demo and 'Member1' or (party:GetMemberName(0) or '');
    local myZone = party:GetMemberZone(0);

    if (not placed) then -- saved spot once when it appears; dragged freely after that
        imgui.SetNextWindowPos({ cfg.pool_x, cfg.pool_y }, ImGuiCond_Always);
        placed = true;
    end
    p_open[1] = true;
    if (imgui.Begin('##goomui_pool', p_open, FLAGS)) then
        local wx, wy = imgui.GetWindowPos();
        local ww, wh = imgui.GetWindowSize();
        local dl = imgui.GetWindowDrawList();
        dl:AddRectFilled({ wx, wy }, { wx + ww, wy + wh }, theme.scale_alpha(PANEL_BG, theme.panel_alpha), 4.0);
        dl:AddRectFilled({ wx, wy + 2 }, { wx + 5, wy + wh - 2 }, ACCENT);
        imgui.PushTextWrapPos(WIDTH - 8);
        imgui.Dummy({ WIDTH - 16, 0 }); -- fixed width (the window auto-sizes to its content)
        local ok, err = pcall(draw_title, n);
        if (ok) then ok, err = pcall(draw_rows, n, party, myName, myZone); end
        imgui.PopTextWrapPos();
        if (not ok) then imgui.End(); error(err, 0); end -- keep Begin / End and the wrap stack paired
        local nx, ny = math.floor(wx + 0.5), math.floor(wy + 0.5);
        if (nx ~= cfg.pool_x or ny ~= cfg.pool_y) then
            cfg.pool_x, cfg.pool_y, moved = nx, ny, true;
        end
        if (moved and imgui.IsMouseReleased(0)) then moved = false; pcall(settings.save, 'bar'); end
    end
    imgui.End();
end

function M.set_cfg(t) cfg = t; placed = false; end

-- /goomui pool [demo|open|dock]
function M.command(arg)
    if (arg == 'demo') then demo = not demo; return demo and 'Treasure pool demo on.' or 'Treasure pool demo off.'; end
    if (cfg == nil) then return nil; end
    if (arg == 'open') then
        cfg.pool_open, placed = not cfg.pool_open, false;
        pcall(settings.save, 'bar');
        return 'Treasure pool window ' .. (cfg.pool_open and 'shown.' or 'hidden (summary only).');
    elseif (arg == 'dock') then
        cfg.pool_dock = (cfg.pool_dock == false);
        pcall(settings.save, 'bar');
        return cfg.pool_dock and 'Treasure pool: summary by the party list (click it for the window).'
            or 'Treasure pool: window only.';
    end
    cfg.show_pool = (cfg.show_pool == false);
    pcall(settings.save, 'bar');
    return 'Treasure pool window ' .. (cfg.show_pool and 'on.' or 'off.');
end

return M;
