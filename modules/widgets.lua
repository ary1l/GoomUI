--[[
* goomui: settings window look + small widgets shared by gui.lua, party.lua and aaev.lua.
* Colours follow the colour preset: accent = the preset's MP colour (theme.P.mp).
* Only calls that exist in both Ashita ImGui builds (main and 4.3): constants are looked up by name and skipped
* when missing, BeginChild is called without flags (its 3rd argument differs between the builds).
--]]

require('common');
local imgui = require('imgui');
local theme = require('modules/theme');

local W = { };

local function mix(a, b, t, alpha)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, alpha or 1.0 };
end

local WHITE = { 1.0, 1.0, 1.0 };
local BTN   = { 0.17, 0.19, 0.23 };
local FRAME = { 0.13, 0.14, 0.17 };
local DARK  = { 0.08, 0.09, 0.11 };

local cache_key, C = nil, nil;

-- Window colours for the current preset (rebuilt when the preset changes).
local function colours()
    local key = theme.current or theme.DEFAULT;
    if (key == cache_key and C ~= nil) then return C; end
    local p = theme.P.mp;
    local a = { p[1] / 255, p[2] / 255, p[3] / 255 };
    C = {
        accent      = { a[1], a[2], a[3], 1.0 },
        head        = mix(a, WHITE, 0.45),
        choice      = mix(BTN, a, 0.75),
        choice_hov  = mix(BTN, a, 0.90),
        nav_bg      = { 0.05, 0.06, 0.07, 0.55 },
        list = {
            { 'ImGuiCol_WindowBg',             { 0.07, 0.08, 0.10, 0.97 } },
            { 'ImGuiCol_PopupBg',              { 0.09, 0.10, 0.12, 0.98 } },
            { 'ImGuiCol_Border',               { 0.24, 0.26, 0.30, 0.60 } },
            { 'ImGuiCol_FrameBg',              { FRAME[1], FRAME[2], FRAME[3], 1.0 } },
            { 'ImGuiCol_FrameBgHovered',       mix(FRAME, a, 0.25) },
            { 'ImGuiCol_FrameBgActive',        mix(FRAME, a, 0.40) },
            { 'ImGuiCol_TitleBg',              { DARK[1], DARK[2], DARK[3], 1.0 } },
            { 'ImGuiCol_TitleBgActive',        mix(DARK, a, 0.45) },
            { 'ImGuiCol_TitleBgCollapsed',     { DARK[1], DARK[2], DARK[3], 1.0 } },
            { 'ImGuiCol_ScrollbarBg',          { 0.0, 0.0, 0.0, 0.20 } },
            { 'ImGuiCol_ScrollbarGrab',        { 0.25, 0.27, 0.31, 1.0 } },
            { 'ImGuiCol_ScrollbarGrabHovered', mix(BTN, a, 0.50) },
            { 'ImGuiCol_ScrollbarGrabActive',  { a[1], a[2], a[3], 1.0 } },
            { 'ImGuiCol_CheckMark',            mix(a, WHITE, 0.25) },
            { 'ImGuiCol_SliderGrab',           { a[1], a[2], a[3], 1.0 } },
            { 'ImGuiCol_SliderGrabActive',     mix(a, WHITE, 0.30) },
            { 'ImGuiCol_Button',               { BTN[1], BTN[2], BTN[3], 1.0 } },
            { 'ImGuiCol_ButtonHovered',        mix(BTN, a, 0.45) },
            { 'ImGuiCol_ButtonActive',         mix(BTN, a, 0.70) },
            { 'ImGuiCol_Header',               mix(BTN, a, 0.60) },
            { 'ImGuiCol_HeaderHovered',        mix(BTN, a, 0.35) },
            { 'ImGuiCol_HeaderActive',         mix(BTN, a, 0.75) },
            { 'ImGuiCol_Separator',            { 0.24, 0.26, 0.30, 1.0 } },
            { 'ImGuiCol_ResizeGrip',           mix(BTN, a, 0.30, 0.50) },
            { 'ImGuiCol_ResizeGripHovered',    mix(BTN, a, 0.60, 0.80) },
            { 'ImGuiCol_ResizeGripActive',     { a[1], a[2], a[3], 1.0 } },
            { 'ImGuiCol_TextDisabled',         { 0.56, 0.59, 0.65, 1.0 } },
        },
    };
    cache_key = key;
    return C;
end

local VARS = { { 'ImGuiStyleVar_WindowRounding', 5.0 }, { 'ImGuiStyleVar_FrameRounding', 3.0 },
    { 'ImGuiStyleVar_GrabRounding', 3.0 } };

-- Push the window style; returns the counts for W.style_pop.
function W.style_push()
    local nc, nv = 0, 0;
    for _, e in ipairs(colours().list) do
        local idx = rawget(_G, e[1]);
        if (idx ~= nil) then imgui.PushStyleColor(idx, e[2]); nc = nc + 1; end
    end
    for _, e in ipairs(VARS) do
        local idx = rawget(_G, e[1]);
        if (idx ~= nil) then imgui.PushStyleVar(idx, e[2]); nv = nv + 1; end
    end
    return nc, nv;
end

function W.style_pop(nc, nv)
    if (nv > 0) then imgui.PopStyleVar(nv); end
    if (nc > 0) then imgui.PopStyleColor(nc); end
end

function W.accent() return colours().accent; end
function W.nav_bg() return colours().nav_bg; end

-- Section title: accent text (optional '(?)' tip) over a separator, a little space above.
function W.section(title, tip)
    imgui.Dummy({ 0, imgui.GetFontSize() * 0.35 });
    imgui.TextColored(colours().head, title);
    if (tip ~= nil) then W.tip(tip); end
    imgui.Separator();
end

-- '(?)' after the last item, text in a wrapped tooltip.
function W.tip(text)
    imgui.SameLine();
    imgui.TextDisabled('(?)');
    if (imgui.IsItemHovered()) then
        imgui.BeginTooltip();
        imgui.PushTextWrapPos(imgui.GetFontSize() * 28);
        imgui.Text(text);
        imgui.PopTextWrapPos();
        imgui.EndTooltip();
    end
end

-- Width of a button that fits text (plus its frame padding).
function W.button_w(text)
    return (imgui.CalcTextSize(text) or 0) + imgui.GetFontSize();
end

-- Button that shows whether it is the current choice (filled with the accent colour). size optional.
function W.choice(label, on, id, size)
    if (on) then
        local c = colours();
        imgui.PushStyleColor(ImGuiCol_Button, c.choice);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, c.choice_hov);
    end
    local hit = imgui.Button(label .. '##' .. id, size or { W.button_w(label), 0 });
    if (on) then imgui.PopStyleColor(2); end
    return hit;
end

-- Row label at the frame's text height, then the cursor moves to column x (window-local) on the same line.
function W.row_label(text, x)
    imgui.AlignTextToFramePadding();
    imgui.Text(text);
    imgui.SameLine(x);
end

-- "Label  [a] [b] [c]": one choice per item ({ key, text }); wraps under the first button when the row is full.
-- Returns the picked key or nil.
function W.choice_row(label, items, cur, id, x)
    W.row_label(label, x);
    local avail = imgui.GetContentRegionAvail();
    local sp = imgui.GetFontSize() * 0.35;
    local used, picked = 0, nil;
    for i, it in ipairs(items) do
        local w = W.button_w(it[2]);
        if (i > 1) then
            if (used + sp + w > avail) then
                imgui.SetCursorPosX(x);
                used = 0;
            else
                imgui.SameLine(0, sp);
                used = used + sp;
            end
        end
        if (W.choice(it[2], it[1] == cur, id .. '_' .. it[1], { w, 0 })) then picked = it[1]; end
        used = used + w;
    end
    return picked;
end

return W;
