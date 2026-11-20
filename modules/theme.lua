--[[
* goomui: shared look (style B "soft gauge"; colour presets, see PRESET_ORDER).
* One place for every bar/plate colour so the target bar, cast/JA/menu panels,
* AAEV chart and party list read as one HUD.
*
* Two consumers:
*   - imgui draw lists (modules/bar, modules/aaev): U32 colours from imgui.GetColorU32
*   - the party list's D3D sprite pass (modules/party): 0xAARRGGBB numbers
* Bars are drawn as: dark track -> flat fill -> light upper band + 1px top
* highlight + 1px dark bottom edge. Plain filled rects only (no gradient API).
--]]

require('common');
local imgui = require('imgui');

local T = { };
local floor = math.floor;

-- rgb 0-255 -> imgui float table / U32 / argb
local function f4(r, g, b, a) return { r / 255, g / 255, b / 255, (a or 255) / 255 }; end
local function u32(r, g, b, a) return imgui.GetColorU32(f4(r, g, b, a)); end
local function argb(r, g, b, a) return (a or 255) * 0x1000000 + r * 0x10000 + g * 0x100 + b; end
T.f4, T.u32, T.argb = f4, u32, argb;

-- Colour presets (rgb). Only bar / chart colours change; plates, tints, stripes
-- and text stay the same. Pick in the settings window (Look tab); saved per
-- character in bar.lua as `theme`.
local PRESETS = {
    vivid = {   -- default: saturated, readable at a glance
        hp_full = {  95, 211, 106 }, hp_75 = { 184, 217,  74 }, hp_50 = { 242, 201,  76 },
        hp_25   = { 240, 138,  60 }, hp_0  = { 229,  72,  77 },
        mp      = {  76, 156, 255 }, tp = { 140, 124, 240 }, tp_rdy = { 180, 156, 255 }, tp_max = { 255, 207,  74 },
        spell   = { 111, 208, 160 }, item = { 196, 156, 255 }, menu_sp = {  76, 156, 255 }, menu_ja = {  90, 168, 255 },
        hit     = {  90, 168, 255 }, crit = { 255, 207,  74 }, miss = {  95, 102, 112 }, ws = { 224, 124, 240 },
        counter = { 229,  72,  77 }, block = {  72,  78,  86 }, zero = { 120, 126, 134 }, heal = {  95, 211, 106 },
        ae      = { 196, 156, 255 },
        r1 = {  61, 116, 201 }, r2 = {  90, 168, 255 }, r3 = { 140, 202, 255 }, r4 = { 180, 156, 255 }, r5 = { 224, 124, 240 },
    },
    aurora = { -- mint HP, blue MP, violet TP, green-cyan-violet rounds
        hp_full = {  79, 240, 181 }, hp_75 = { 155, 227, 138 }, hp_50 = { 242, 208, 107 },
        hp_25 = { 240, 144,  90 }, hp_0 = { 229,  84, 106 },
        mp = {  90, 160, 255 }, tp = { 138, 108, 255 }, tp_rdy = { 184, 156, 255 }, tp_max = { 255, 211, 107 },
        spell = {  79, 209, 232 }, item = { 184, 156, 255 }, menu_sp = {  90, 160, 255 }, menu_ja = {  79, 209, 232 },
        hit = {  47, 184, 160 }, crit = { 255, 211, 107 }, miss = {  78,  94,  90 }, ws = { 199, 125, 255 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = {  79, 240, 181 },
        ae = { 184, 156, 255 },
        r1 = {  31, 122, 107 }, r2 = {  47, 184, 160 }, r3 = {  79, 209, 232 }, r4 = { 138, 140, 255 }, r5 = { 199, 125, 255 },
    },
    abyss = { -- deep: teal HP, indigo MP, magenta TP, blue-to-pink rounds
        hp_full = {  89, 195, 195 }, hp_75 = { 127, 200, 169 }, hp_50 = { 233, 196, 106 },
        hp_25 = { 244, 132,  95 }, hp_0 = { 247,  37, 133 },
        mp = {  67,  97, 238 }, tp = { 114,   9, 183 }, tp_rdy = { 181,  23, 158 }, tp_max = { 247,  37, 133 },
        spell = {  76, 201, 240 }, item = { 181,  23, 158 }, menu_sp = {  67,  97, 238 }, menu_ja = {  76, 201, 240 },
        hit = {  67,  97, 238 }, crit = { 247,  37, 133 }, miss = {  58,  63,  88 }, ws = { 181,  23, 158 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = {  89, 195, 195 },
        ae = { 181,  23, 158 },
        r1 = {  58,  12, 163 }, r2 = {  67,  97, 238 }, r3 = {  76, 201, 240 }, r4 = { 181,  23, 158 }, r5 = { 247,  37, 133 },
    },
    moss = { -- earthy: olive HP, sage MP, tan TP, green rounds
        hp_full = { 156, 191,  90 }, hp_75 = { 184, 194,  90 }, hp_50 = { 224, 195,  90 },
        hp_25 = { 217, 135,  74 }, hp_0 = { 196,  84,  74 },
        mp = { 111, 159, 160 }, tp = { 168, 148, 106 }, tp_rdy = { 210, 182, 122 }, tp_max = { 240, 210, 122 },
        spell = { 156, 191,  90 }, item = { 210, 182, 122 }, menu_sp = { 111, 159, 160 }, menu_ja = { 143, 176, 122 },
        hit = { 143, 191,  95 }, crit = { 240, 210, 122 }, miss = {  90,  94,  82 }, ws = { 210, 182, 122 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = { 156, 191,  90 },
        ae = { 210, 182, 122 },
        r1 = {  63,  95,  47 }, r2 = {  95, 143,  63 }, r3 = { 143, 191,  95 }, r4 = { 191, 223, 143 }, r5 = { 224, 240, 176 },
    },
    frost = { -- ice: white-blue HP, light blue MP, pale rounds
        hp_full = { 223, 246, 255 }, hp_75 = { 168, 224, 255 }, hp_50 = { 242, 208, 107 },
        hp_25 = { 240, 144,  90 }, hp_0 = { 229,  84, 106 },
        mp = { 127, 184, 255 }, tp = { 154, 166, 224 }, tp_rdy = { 220, 226, 255 }, tp_max = { 255, 233, 168 },
        spell = { 168, 224, 255 }, item = { 220, 226, 255 }, menu_sp = { 127, 184, 255 }, menu_ja = { 168, 224, 255 },
        hit = { 160, 208, 255 }, crit = { 255, 233, 168 }, miss = {  78,  90, 102 }, ws = { 220, 226, 255 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = { 191, 240, 216 },
        ae = { 220, 226, 255 },
        r1 = {  74, 111, 143 }, r2 = { 111, 159, 207 }, r3 = { 160, 208, 255 }, r4 = { 208, 236, 255 }, r5 = { 255, 255, 255 },
    },
    ember = {   -- warm: amber HP, teal MP, orange rounds
        hp_full = { 255, 179,  71 }, hp_75 = { 255, 140,  66 }, hp_50 = { 255, 107,  61 },
        hp_25   = { 232,  69,  60 }, hp_0  = { 192,  38,  45 },
        mp      = {  63, 193, 201 }, tp = { 199, 125, 255 }, tp_rdy = { 224, 163, 255 }, tp_max = { 255, 209, 102 },
        spell   = { 255, 159,  67 }, item = { 224, 163, 255 }, menu_sp = {  63, 193, 201 }, menu_ja = { 255, 159,  67 },
        hit     = { 240, 138,  60 }, crit = { 255, 224, 138 }, miss = {  95,  85,  80 }, ws = { 255, 110, 199 },
        counter = { 192,  38,  45 }, block = {  80,  70,  66 }, zero = { 130, 120, 114 }, heal = { 120, 214, 120 },
        ae      = { 224, 163, 255 },
        r1 = { 140,  59,  31 }, r2 = { 199,  91,  42 }, r3 = { 240, 138,  60 }, r4 = { 255, 193,  94 }, r5 = { 255, 224, 138 },
    },
    ocean = {   -- aqua HP, blue MP, teal rounds
        hp_full = {  46, 230, 198 }, hp_75 = { 123, 224, 166 }, hp_50 = { 242, 208, 107 },
        hp_25   = { 240, 144,  90 }, hp_0  = { 229,  84, 106 },
        mp      = {  58, 134, 255 }, tp = { 108,  99, 255 }, tp_rdy = { 157, 140, 255 }, tp_max = { 255, 209, 102 },
        spell   = {  46, 196, 182 }, item = { 157, 140, 255 }, menu_sp = {  58, 134, 255 }, menu_ja = {  46, 196, 182 },
        hit     = {  26, 159, 176 }, crit = { 255, 209, 102 }, miss = {  80,  96, 104 }, ws = { 157, 140, 255 },
        counter = { 229,  84, 106 }, block = {  64,  80,  88 }, zero = { 110, 126, 134 }, heal = {  46, 230, 198 },
        ae      = { 157, 140, 255 },
        r1 = {  16, 109, 122 }, r2 = {  26, 159, 176 }, r3 = {  63, 208, 217 }, r4 = { 159, 243, 240 }, r5 = { 195, 247, 255 },
    },
    synth = {   -- neon: green / cyan / magenta
        hp_full = {  57, 255, 136 }, hp_75 = { 198, 255,  61 }, hp_50 = { 255, 225,  77 },
        hp_25   = { 255, 138,  61 }, hp_0  = { 255,  61, 110 },
        mp      = {   0, 212, 255 }, tp = { 200,  60, 170 }, tp_rdy = { 255,  79, 216 }, tp_max = { 255, 240,  77 },
        spell   = {   0, 212, 255 }, item = { 255,  79, 216 }, menu_sp = {   0, 212, 255 }, menu_ja = { 122,  61, 255 },
        hit     = {   0, 212, 255 }, crit = { 255, 240,  77 }, miss = {  90,  80, 110 }, ws = { 255,  79, 216 },
        counter = { 255,  61, 110 }, block = {  70,  60,  90 }, zero = { 120, 110, 140 }, heal = {  57, 255, 136 },
        ae      = { 255, 138, 240 },
        r1 = {  61,  43, 255 }, r2 = { 122,  61, 255 }, r3 = { 194,  61, 255 }, r4 = { 255,  61, 200 }, r5 = { 255,  61, 110 },
    },
    royal = { -- gold HP, purple TP, purple-to-gold rounds
        hp_full = { 212, 175,  55 }, hp_75 = { 224, 184,  74 }, hp_50 = { 224, 154,  60 },
        hp_25 = { 217, 102,  60 }, hp_0 = { 192,  57,  43 },
        mp = { 122, 106, 224 }, tp = { 155,  89, 182 }, tp_rdy = { 195, 155, 211 }, tp_max = { 241, 196,  15 },
        spell = { 212, 175,  55 }, item = { 195, 155, 211 }, menu_sp = { 122, 106, 224 }, menu_ja = { 195, 155, 211 },
        hit = { 155,  89, 182 }, crit = { 241, 196,  15 }, miss = {  85,  72,  94 }, ws = { 212, 175,  55 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = { 127, 209, 127 },
        ae = { 195, 155, 211 },
        r1 = {  74,  35,  90 }, r2 = { 108,  52, 131 }, r3 = { 155,  89, 182 }, r4 = { 195, 155, 211 }, r5 = { 241, 196,  15 },
    },
    sakura = { -- pink HP, sky MP, lilac TP, pink rounds
        hp_full = { 255, 158, 199 }, hp_75 = { 255, 179, 167 }, hp_50 = { 255, 210, 127 },
        hp_25 = { 255, 154,  90 }, hp_0 = { 229,  72,  77 },
        mp = { 143, 211, 255 }, tp = { 200, 162, 255 }, tp_rdy = { 226, 198, 255 }, tp_max = { 255, 241, 168 },
        spell = { 255, 158, 199 }, item = { 226, 198, 255 }, menu_sp = { 143, 211, 255 }, menu_ja = { 255, 179, 209 },
        hit = { 255, 143, 191 }, crit = { 255, 241, 168 }, miss = { 106,  85,  96 }, ws = { 226, 198, 255 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = { 159, 224, 176 },
        ae = { 226, 198, 255 },
        r1 = { 143,  59,  95 }, r2 = { 194,  90, 135 }, r3 = { 255, 143, 191 }, r4 = { 255, 194, 220 }, r5 = { 255, 230, 240 },
    },
    dusk = { -- soft: sand HP, sky MP, lavender TP, muted rounds
        hp_full = { 246, 193, 119 }, hp_75 = { 242, 180, 122 }, hp_50 = { 234, 154, 151 },
        hp_25 = { 224, 113, 122 }, hp_0 = { 235, 111, 146 },
        mp = { 156, 207, 216 }, tp = { 166, 139, 214 }, tp_rdy = { 196, 167, 231 }, tp_max = { 246, 193, 119 },
        spell = { 235, 188, 186 }, item = { 196, 167, 231 }, menu_sp = { 156, 207, 216 }, menu_ja = {  49, 116, 143 },
        hit = { 156, 207, 216 }, crit = { 246, 193, 119 }, miss = {  78,  74,  94 }, ws = { 196, 167, 231 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = { 156, 207, 216 },
        ae = { 196, 167, 231 },
        r1 = {  49, 116, 143 }, r2 = { 156, 207, 216 }, r3 = { 196, 167, 231 }, r4 = { 235, 188, 186 }, r5 = { 246, 193, 119 },
    },
    citrus = { -- lime HP, cyan MP, pink TP, lime-to-orange rounds
        hp_full = { 163, 230,  53 }, hp_75 = { 217, 224,  33 }, hp_50 = { 250, 204,  21 },
        hp_25 = { 251, 146,  60 }, hp_0 = { 239,  68,  68 },
        mp = {  34, 211, 238 }, tp = { 236,  72, 153 }, tp_rdy = { 244, 114, 182 }, tp_max = { 253, 224,  71 },
        spell = { 163, 230,  53 }, item = { 244, 114, 182 }, menu_sp = {  34, 211, 238 }, menu_ja = { 132, 204,  22 },
        hit = { 132, 204,  22 }, crit = { 253, 224,  71 }, miss = {  86,  89,  74 }, ws = { 244, 114, 182 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = { 163, 230,  53 },
        ae = { 249, 168, 212 },
        r1 = {  77, 124,  15 }, r2 = { 132, 204,  22 }, r3 = { 250, 204,  21 }, r4 = { 251, 146,  60 }, r5 = { 249, 115,  22 },
    },
    nord = { -- arctic pastels: sage HP, frost blue MP, purple TP
        hp_full = { 163, 190, 140 }, hp_75 = { 194, 201, 138 }, hp_50 = { 235, 203, 139 },
        hp_25 = { 208, 135, 112 }, hp_0 = { 191,  97, 106 },
        mp = { 129, 161, 193 }, tp = { 157, 132, 184 }, tp_rdy = { 180, 142, 173 }, tp_max = { 235, 203, 139 },
        spell = { 136, 192, 208 }, item = { 180, 142, 173 }, menu_sp = { 129, 161, 193 }, menu_ja = { 136, 192, 208 },
        hit = { 129, 161, 193 }, crit = { 235, 203, 139 }, miss = {  76,  86, 106 }, ws = { 180, 142, 173 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = { 163, 190, 140 },
        ae = { 180, 142, 173 },
        r1 = {  94, 129, 172 }, r2 = { 129, 161, 193 }, r3 = { 136, 192, 208 }, r4 = { 143, 188, 187 }, r5 = { 180, 142, 173 },
    },
    dracula = { -- green HP, cyan MP, purple / pink TP
        hp_full = {  80, 250, 123 }, hp_75 = { 164, 240, 122 }, hp_50 = { 241, 250, 140 },
        hp_25 = { 255, 184, 108 }, hp_0 = { 255,  85,  85 },
        mp = { 139, 233, 253 }, tp = { 189, 147, 249 }, tp_rdy = { 255, 121, 198 }, tp_max = { 241, 250, 140 },
        spell = { 139, 233, 253 }, item = { 255, 121, 198 }, menu_sp = { 139, 233, 253 }, menu_ja = { 189, 147, 249 },
        hit = { 189, 147, 249 }, crit = { 241, 250, 140 }, miss = {  68,  71,  90 }, ws = { 255, 121, 198 },
        counter = { 255,  85,  85 }, block = {  68,  71,  90 }, zero = {  98, 114, 164 }, heal = {  80, 250, 123 },
        ae = { 255, 121, 198 },
        r1 = {  98, 114, 164 }, r2 = { 139, 233, 253 }, r3 = { 189, 147, 249 }, r4 = { 255, 121, 198 }, r5 = { 255, 184, 108 },
    },
    candy = { -- pastels: cyan HP, mint MP, pink TP
        hp_full = { 123, 223, 242 }, hp_75 = { 178, 247, 239 }, hp_50 = { 255, 243, 176 },
        hp_25 = { 255, 180, 162 }, hp_0 = { 255, 107, 129 },
        mp = { 162, 210, 255 }, tp = { 242, 181, 212 }, tp_rdy = { 255, 175, 204 }, tp_max = { 255, 243, 176 },
        spell = { 178, 247, 239 }, item = { 255, 175, 204 }, menu_sp = { 162, 210, 255 }, menu_ja = { 205, 180, 219 },
        hit = { 189, 224, 254 }, crit = { 255, 243, 176 }, miss = { 106, 100, 112 }, ws = { 255, 175, 204 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = { 178, 247, 239 },
        ae = { 205, 180, 219 },
        r1 = { 205, 180, 219 }, r2 = { 189, 224, 254 }, r3 = { 162, 210, 255 }, r4 = { 255, 200, 221 }, r5 = { 255, 175, 204 },
    },
    toxic = { -- acid lime HP, deep purple MP, hot pink TP
        hp_full = { 198, 255,   0 }, hp_75 = { 228, 245,  42 }, hp_50 = { 255, 214,  10 },
        hp_25 = { 255, 140,   0 }, hp_0 = { 255,   0, 110 },
        mp = { 123,  44, 191 }, tp = { 255,   0, 110 }, tp_rdy = { 255,  77, 148 }, tp_max = { 255, 190,  11 },
        spell = { 198, 255,   0 }, item = { 255,  77, 148 }, menu_sp = { 157,  78, 221 }, menu_ja = { 198, 255,   0 },
        hit = { 157,  78, 221 }, crit = { 255, 190,  11 }, miss = {  60,  52,  70 }, ws = { 255,   0, 110 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = { 198, 255,   0 },
        ae = { 255,  77, 148 },
        r1 = {  60,   9, 108 }, r2 = { 123,  44, 191 }, r3 = { 157,  78, 221 }, r4 = { 198, 255,   0 }, r5 = { 255,   0, 110 },
    },
    retro = { -- amber CRT: everything amber; low HP red
        hp_full = { 255, 176,   0 }, hp_75 = { 255, 160,   0 }, hp_50 = { 255, 140,   0 },
        hp_25 = { 255, 106,   0 }, hp_0 = { 229,  72,  77 },
        mp = { 204, 138,   0 }, tp = { 153, 102,   0 }, tp_rdy = { 255, 204, 102 }, tp_max = { 255, 240, 179 },
        spell = { 255, 176,   0 }, item = { 255, 204, 102 }, menu_sp = { 204, 138,   0 }, menu_ja = { 255, 176,   0 },
        hit = { 255, 176,   0 }, crit = { 255, 240, 179 }, miss = {  74,  58,  26 }, ws = { 255, 204, 102 },
        counter = { 229,  72,  77 }, block = {  74,  58,  26 }, zero = { 122, 106,  74 }, heal = { 255, 204, 102 },
        ae = { 255, 204, 102 },
        r1 = { 102,  68,   0 }, r2 = { 153, 102,   0 }, r3 = { 204, 138,   0 }, r4 = { 255, 176,   0 }, r5 = { 255, 224, 138 },
    },
    matrix = { -- terminal green: everything green; low HP red
        hp_full = {   0, 255,  65 }, hp_75 = {  32, 232,  64 }, hp_50 = { 184, 240,   0 },
        hp_25 = { 255, 160,   0 }, hp_0 = { 229,  72,  77 },
        mp = {   0, 179,  44 }, tp = {   0, 143,  17 }, tp_rdy = {  92, 255, 138 }, tp_max = { 208, 255, 216 },
        spell = {   0, 255,  65 }, item = {  92, 255, 138 }, menu_sp = {   0, 179,  44 }, menu_ja = {   0, 255,  65 },
        hit = {   0, 200,  55 }, crit = { 208, 255, 216 }, miss = {  23,  61,  31 }, ws = {  92, 255, 138 },
        counter = { 229,  72,  77 }, block = {  23,  61,  31 }, zero = {  61, 107,  71 }, heal = {  92, 255, 138 },
        ae = {  92, 255, 138 },
        r1 = {   0,  77,  20 }, r2 = {   0, 143,  17 }, r3 = {   0, 200,  55 }, r4 = {   0, 255,  65 }, r5 = { 179, 255, 198 },
    },
    sunset = { -- golden HP, purple MP, pink-orange TP, purple-to-gold rounds
        hp_full = { 255, 207, 107 }, hp_75 = { 255, 178, 107 }, hp_50 = { 255, 150, 113 },
        hp_25 = { 255, 111, 145 }, hp_0 = { 201,  24,  74 },
        mp = { 132,  94, 194 }, tp = { 214,  93, 177 }, tp_rdy = { 255, 111, 145 }, tp_max = { 255, 199,  95 },
        spell = { 255, 150, 113 }, item = { 214,  93, 177 }, menu_sp = { 132,  94, 194 }, menu_ja = { 255, 150, 113 },
        hit = { 214,  93, 177 }, crit = { 255, 199,  95 }, miss = {  78,  61,  82 }, ws = { 255, 111, 145 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = { 255, 207, 107 },
        ae = { 214,  93, 177 },
        r1 = { 132,  94, 194 }, r2 = { 214,  93, 177 }, r3 = { 255, 111, 145 }, r4 = { 255, 150, 113 }, r5 = { 255, 199,  95 },
    },
    mocha = { -- coffee browns: latte HP, cream MP, roast TP
        hp_full = { 212, 163, 115 }, hp_75 = { 204, 173, 122 }, hp_50 = { 224, 178,  82 },
        hp_25 = { 200, 118,  60 }, hp_0 = { 164,  50,  43 },
        mp = { 233, 216, 166 }, tp = { 141, 110,  99 }, tp_rdy = { 188, 138,  95 }, tp_max = { 255, 209, 102 },
        spell = { 212, 163, 115 }, item = { 188, 138,  95 }, menu_sp = { 233, 216, 166 }, menu_ja = { 188, 138,  95 },
        hit = { 161, 136, 127 }, crit = { 255, 209, 102 }, miss = {  62,  47,  42 }, ws = { 188, 138,  95 },
        counter = { 229,  72,  77 }, block = {  62,  47,  42 }, zero = { 109,  93,  88 }, heal = { 212, 163, 115 },
        ae = { 188, 138,  95 },
        r1 = {  78,  52,  46 }, r2 = { 109,  76,  65 }, r3 = { 141, 110,  99 }, r4 = { 188, 170, 164 }, r5 = { 239, 235, 233 },
    },
    duality = { -- ice and fire: cyan HP and MP, red-orange TP, blue-to-red rounds
        hp_full = {  76, 201, 240 }, hp_75 = { 123, 211, 216 }, hp_50 = { 249, 199,  79 },
        hp_25 = { 248, 150,  30 }, hp_0 = { 249,  65,  68 },
        mp = {  67,  97, 238 }, tp = { 243, 114,  44 }, tp_rdy = { 248, 150,  30 }, tp_max = { 249, 199,  79 },
        spell = {  76, 201, 240 }, item = { 243, 114,  44 }, menu_sp = {  67,  97, 238 }, menu_ja = { 243, 114,  44 },
        hit = {  76, 201, 240 }, crit = { 249, 199,  79 }, miss = {  61,  68,  82 }, ws = { 249,  65,  68 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = {  76, 201, 240 },
        ae = { 248, 150,  30 },
        r1 = {  39, 125, 161 }, r2 = {  76, 201, 240 }, r3 = { 249, 199,  79 }, r4 = { 248, 150,  30 }, r5 = { 249,  65,  68 },
    },
    galaxy = { -- deep space: lilac HP, violet MP, starlight TP
        hp_full = { 224, 170, 255 }, hp_75 = { 212, 166, 245 }, hp_50 = { 255, 214, 165 },
        hp_25 = { 255, 158, 125 }, hp_0 = { 255,  77, 109 },
        mp = { 123,  44, 191 }, tp = { 157,  78, 221 }, tp_rdy = { 199, 125, 255 }, tp_max = { 255, 243, 176 },
        spell = { 199, 125, 255 }, item = { 224, 170, 255 }, menu_sp = { 123,  44, 191 }, menu_ja = { 199, 125, 255 },
        hit = { 157,  78, 221 }, crit = { 255, 243, 176 }, miss = {  43,  33,  64 }, ws = { 224, 170, 255 },
        counter = { 229,  72,  77 }, block = {  43,  33,  64 }, zero = {  90,  78, 110 }, heal = { 224, 170, 255 },
        ae = { 199, 125, 255 },
        r1 = {  36,   0,  70 }, r2 = {  90,  24, 154 }, r3 = { 157,  78, 221 }, r4 = { 199, 125, 255 }, r5 = { 255, 243, 176 },
    },
    vaporwave = { -- pink HP, cyan MP, violet TP, cyan / mint / violet / pink rounds
        hp_full = { 255, 113, 206 }, hp_75 = { 255, 155, 224 }, hp_50 = { 255, 251, 150 },
        hp_25 = { 255, 184, 108 }, hp_0 = { 255,  56, 100 },
        mp = {   1, 205, 254 }, tp = { 185, 103, 255 }, tp_rdy = { 212, 160, 255 }, tp_max = { 255, 251, 150 },
        spell = {   5, 255, 161 }, item = { 185, 103, 255 }, menu_sp = {   1, 205, 254 }, menu_ja = {   5, 255, 161 },
        hit = {   1, 205, 254 }, crit = { 255, 251, 150 }, miss = {  63,  58,  90 }, ws = { 255, 113, 206 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = {   5, 255, 161 },
        ae = { 185, 103, 255 },
        r1 = {   1, 205, 254 }, r2 = {   5, 255, 161 }, r3 = { 185, 103, 255 }, r4 = { 255, 113, 206 }, r5 = { 255, 251, 150 },
    },
    desert = { -- sand HP, turquoise MP, terracotta TP
        hp_full = { 233, 196, 106 }, hp_75 = { 230, 184,  92 }, hp_50 = { 244, 162,  97 },
        hp_25 = { 231, 111,  81 }, hp_0 = { 181,  23,  46 },
        mp = {  42, 157, 143 }, tp = { 231, 111,  81 }, tp_rdy = { 244, 162,  97 }, tp_max = { 255, 209, 102 },
        spell = { 233, 196, 106 }, item = { 231, 111,  81 }, menu_sp = {  42, 157, 143 }, menu_ja = { 233, 196, 106 },
        hit = {  42, 157, 143 }, crit = { 255, 209, 102 }, miss = {  74,  66,  56 }, ws = { 231, 111,  81 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = {  42, 157, 143 },
        ae = { 244, 162,  97 },
        r1 = {  38,  70,  83 }, r2 = {  42, 157, 143 }, r3 = { 233, 196, 106 }, r4 = { 244, 162,  97 }, r5 = { 231, 111,  81 },
    },
    gems = { -- emerald HP, sapphire MP, ruby TP, gem rounds
        hp_full = {  46, 204, 113 }, hp_75 = { 143, 209,  79 }, hp_50 = { 255, 215,   0 },
        hp_25 = { 255, 140,   0 }, hp_0 = { 224,  17,  95 },
        mp = {  15,  82, 186 }, tp = { 155,  17,  30 }, tp_rdy = { 224,  17,  95 }, tp_max = { 255, 215,   0 },
        spell = {  46, 204, 113 }, item = { 153, 102, 204 }, menu_sp = {  15,  82, 186 }, menu_ja = { 153, 102, 204 },
        hit = {  15,  82, 186 }, crit = { 255, 215,   0 }, miss = {  58,  58,  72 }, ws = { 224,  17,  95 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = {  46, 204, 113 },
        ae = { 153, 102, 204 },
        r1 = {  15,  82, 186 }, r2 = { 153, 102, 204 }, r3 = { 224,  17,  95 }, r4 = { 255, 140,   0 }, r5 = { 255, 215,   0 },
    },
    gameboy = { -- four-shade olive handheld; low HP red
        hp_full = { 155, 188,  15 }, hp_75 = { 139, 172,  15 }, hp_50 = { 200, 180,   0 },
        hp_25 = { 224, 138,   0 }, hp_0 = { 229,  72,  77 },
        mp = {  95, 143,  47 }, tp = {  48,  98,  48 }, tp_rdy = { 139, 172,  15 }, tp_max = { 224, 248, 208 },
        spell = { 155, 188,  15 }, item = { 139, 172,  15 }, menu_sp = {  95, 143,  47 }, menu_ja = { 155, 188,  15 },
        hit = { 139, 172,  15 }, crit = { 224, 248, 208 }, miss = {  15,  56,  15 }, ws = { 155, 188,  15 },
        counter = { 229,  72,  77 }, block = {  15,  56,  15 }, zero = {  74, 106,  58 }, heal = { 155, 188,  15 },
        ae = { 139, 172,  15 },
        r1 = {  15,  56,  15 }, r2 = {  48,  98,  48 }, r3 = { 139, 172,  15 }, r4 = { 155, 188,  15 }, r5 = { 224, 248, 208 },
    },
    bloodmoon = { -- silver HP, dusk-blue MP, blood-red TP and rounds
        hp_full = { 217, 217, 217 }, hp_75 = { 201, 184, 184 }, hp_50 = { 224, 159,  62 },
        hp_25 = { 208,   0,   0 }, hp_0 = { 139,   0,   0 },
        mp = {  74,  78, 105 }, tp = { 157,   2,   8 }, tp_rdy = { 208,   0,   0 }, tp_max = { 253, 240, 213 },
        spell = { 192, 192, 192 }, item = { 157,   2,   8 }, menu_sp = {  74,  78, 105 }, menu_ja = { 154, 140, 152 },
        hit = { 157,   2,   8 }, crit = { 253, 240, 213 }, miss = {  43,  43,  43 }, ws = { 208,   0,   0 },
        counter = { 255,  77,  77 }, block = {  43,  43,  43 }, zero = {  90,  90,  90 }, heal = { 192, 192, 192 },
        ae = { 154, 140, 152 },
        r1 = {  61,   0,   0 }, r2 = { 106,   4,  15 }, r3 = { 157,   2,   8 }, r4 = { 208,   0,   0 }, r5 = { 220,  47,   2 },
    },
    crystal = { -- FFXI crystals: crystal-blue HP, elemental rounds (ice, wind, earth, lightning, fire)
        hp_full = { 155, 232, 255 }, hp_75 = { 180, 230, 214 }, hp_50 = { 242, 226, 122 },
        hp_25 = { 245, 162,  93 }, hp_0 = { 232,  74,  74 },
        mp = {  91, 140, 255 }, tp = { 169, 139, 255 }, tp_rdy = { 217, 184, 255 }, tp_max = { 255, 241, 184 },
        spell = { 155, 232, 255 }, item = { 217, 184, 255 }, menu_sp = {  91, 140, 255 }, menu_ja = { 155, 232, 255 },
        hit = {  91, 200, 255 }, crit = { 255, 241, 184 }, miss = {  63,  74,  86 }, ws = { 217, 184, 255 },
        counter = { 229,  72,  77 }, block = {  74,  78,  86 }, zero = { 122, 126, 134 }, heal = { 126, 224, 138 },
        ae = { 217, 184, 255 },
        r1 = {  91, 200, 255 }, r2 = {  76, 207, 122 }, r3 = { 232, 197,  71 }, r4 = { 166, 107, 255 }, r5 = { 255,  90,  74 },
    },
    mono = {    -- greys; colour only for low HP, TP 3000 and crits
        hp_full = { 232, 232, 232 }, hp_75 = { 207, 207, 207 }, hp_50 = { 242, 201,  76 },
        hp_25   = { 240, 138,  60 }, hp_0  = { 229,  72,  77 },
        mp      = { 159, 180, 200 }, tp = { 138, 138, 138 }, tp_rdy = { 208, 208, 208 }, tp_max = { 255, 210,  74 },
        spell   = { 200, 200, 200 }, item = { 160, 160, 160 }, menu_sp = { 159, 180, 200 }, menu_ja = { 180, 180, 180 },
        hit     = { 170, 170, 170 }, crit = { 255, 210,  74 }, miss = {  60,  60,  60 }, ws = { 230, 230, 230 },
        counter = { 229,  72,  77 }, block = {  70,  70,  70 }, zero = { 110, 110, 110 }, heal = { 200, 230, 200 },
        ae      = { 200, 200, 200 },
        r1 = {  85,  85,  85 }, r2 = { 119, 119, 119 }, r3 = { 153, 153, 153 }, r4 = { 187, 187, 187 }, r5 = { 221, 221, 221 },
    },
    classic = { -- the old targetbar / goomUI / AAEV colours
        hp_full = {  31, 140,  31 }, hp_75 = { 128, 166,  26 }, hp_50 = { 255, 204,   0 },
        hp_25   = { 255, 115,   0 }, hp_0  = { 230,  26,  26 },
        mp      = {  63, 127, 232 }, tp = { 106,  99, 214 }, tp_rdy = { 150, 140, 255 }, tp_max = { 255, 208,  64 },
        spell   = {  89, 158, 255 }, item = { 184, 117, 255 }, menu_sp = {  89, 158, 255 }, menu_ja = {  51, 102, 199 },
        hit     = {   0,   0, 237 }, crit = { 119, 119, 237 }, miss = { 255, 255, 255 }, ws = { 184, 117, 255 },
        counter = { 237,   0,   0 }, block = {  64,  64,  64 }, zero = { 128, 128, 128 }, heal = { 102, 255,   7 },
        ae      = { 192, 192, 192 },
        r1 = {   0,   0, 237 }, r2 = {   0, 170, 255 }, r3 = {  60, 220, 120 }, r4 = { 255, 200,   0 }, r5 = { 255,  90,   0 },
    },
};
T.PRESETS = PRESETS;
T.PRESET_ORDER = { 'vivid', 'ember', 'ocean', 'synth', 'aurora', 'abyss', 'moss', 'frost', 'royal', 'sakura',
                   'dusk', 'citrus', 'nord', 'dracula', 'candy', 'toxic', 'retro', 'matrix',
                   'sunset', 'mocha', 'duality', 'galaxy', 'vaporwave', 'desert', 'gems', 'gameboy', 'bloodmoon', 'crystal',
                   'mono', 'classic' };
T.PRESET_LABEL = { vivid = 'Vivid', ember = 'Ember', ocean = 'Ocean', synth = 'Synth', aurora = 'Aurora',
                   abyss = 'Abyss', moss = 'Moss', frost = 'Frost', royal = 'Royal', sakura = 'Sakura',
                   dusk = 'Dusk', citrus = 'Citrus', nord = 'Nord', dracula = 'Dracula', candy = 'Candy',
                   toxic = 'Toxic', retro = 'Retro', matrix = 'Matrix', sunset = 'Sunset', mocha = 'Mocha',
                   duality = 'Duality', galaxy = 'Galaxy', vaporwave = 'Vaporwave', desert = 'Desert', gems = 'Gems',
                   gameboy = 'Gameboy', bloodmoon = 'Blood Moon', crystal = 'Crystal', mono = 'Mono', classic = 'Classic' };
T.DEFAULT = 'vivid';
T.current = nil;

-- Live palette: these tables keep their identity (modules hold references);
-- T.apply() overwrites their values.
local P = { };
for k, v in pairs(PRESETS.vivid) do P[k] = { v[1], v[2], v[3] }; end
T.P = P;

-- Track / plates (rgba)
T.TRACK   = { 10, 16, 20, 185 };
T.PLATE   = {  8, 12, 14, 120 };

-- Text (imgui floats)
T.TXT       = f4(235, 240, 250);
T.TXT_LABEL = f4(128, 138, 152);

local HP_STOPS = {
    { 1.00, P.hp_full }, { 0.75, P.hp_75 }, { 0.50, P.hp_50 }, { 0.25, P.hp_25 }, { 0.00, P.hp_0 },
};

-- HP colour at pct (0-100) as rgb.
local function hp_rgb(pct)
    local f = pct / 100;
    for i = 1, #HP_STOPS - 1 do
        local hi, lo = HP_STOPS[i], HP_STOPS[i + 1];
        if (f <= hi[1] and f >= lo[1]) then
            local t = (hi[1] - lo[1] > 0) and (f - lo[1]) / (hi[1] - lo[1]) or 0;
            return floor(lo[2][1] + (hi[2][1] - lo[2][1]) * t + 0.5),
                   floor(lo[2][2] + (hi[2][2] - lo[2][2]) * t + 0.5),
                   floor(lo[2][3] + (hi[2][3] - lo[2][3]) * t + 0.5);
        end
    end
    return P.hp_0[1], P.hp_0[2], P.hp_0[3];
end

local function rgb_u32(c, a) return u32(c[1], c[2], c[3], a); end
local function rgb_argb(c, a) return argb(c[1], c[2], c[3], a); end

T.HP_U32, T.HP_ARGB = { }, { };
T.U = {
    TRACK   = u32(T.TRACK[1], T.TRACK[2], T.TRACK[3], T.TRACK[4]),
    HI_BAND = u32(255, 255, 255, 22),   -- upper band of a fill
    HI_LINE = u32(255, 255, 255, 64),   -- 1px top highlight
    LO_LINE = u32(0, 0, 0, 70),         -- 1px bottom edge
};
T.A = {
    TRACK   = argb(T.TRACK[1], T.TRACK[2], T.TRACK[3], T.TRACK[4]),
    HI_BAND = argb(255, 255, 255, 22),
    HI_LINE = argb(255, 255, 255, 64),
    LO_LINE = argb(0, 0, 0, 70),
    TICK    = argb(0, 0, 0, 120),
};

-- Switch preset (unknown name -> default). Values are copied into the live
-- tables in place; U32 / ARGB colours and the HP LUTs are rebuilt.
-- Returns true when the palette changed (callers then refresh their caches).
function T.apply(name)
    if (PRESETS[name] == nil) then name = T.DEFAULT; end
    if (T.current == name) then return false; end
    T.current = name;
    for k, v in pairs(PRESETS[name]) do
        local d = P[k];
        d[1], d[2], d[3] = v[1], v[2], v[3];
    end
    for pct = 0, 100 do
        local r, g, b = hp_rgb(pct);
        T.HP_U32[pct]  = u32(r, g, b);
        T.HP_ARGB[pct] = argb(r, g, b);
    end
    local U, A = T.U, T.A;
    U.MP, U.TP, U.TP_RDY, U.TP_MAX = rgb_u32(P.mp), rgb_u32(P.tp), rgb_u32(P.tp_rdy), rgb_u32(P.tp_max);
    U.SPELL, U.ITEM = rgb_u32(P.spell), rgb_u32(P.item);
    U.MENU_SP, U.MENU_JA = rgb_u32(P.menu_sp), rgb_u32(P.menu_ja);
    U.DEAD = rgb_u32(P.hp_0);
    A.MP, A.TP, A.TP_RDY, A.TP_MAX = rgb_argb(P.mp), rgb_argb(P.tp), rgb_argb(P.tp_rdy), rgb_argb(P.tp_max);
    return true;
end
T.apply(T.DEFAULT);

-- TP fill colour (U32 / ARGB)
function T.tp_u32(tp)
    if (tp >= 3000) then return T.U.TP_MAX; end
    if (tp >= 1000) then return T.U.TP_RDY; end
    return T.U.TP;
end
function T.tp_argb(tp)
    if (tp >= 3000) then return T.A.TP_MAX; end
    if (tp >= 1000) then return T.A.TP_RDY; end
    return T.A.TP;
end

-- imgui: one themed bar. frac 0..1, col = fill U32. Reused vec tables.
local V1, V2 = { 0, 0 }, { 0, 0 };
local function frect(dl, x1, y1, x2, y2, col, r)
    V1[1], V1[2], V2[1], V2[2] = x1, y1, x2, y2;
    if (r) then dl:AddRectFilled(V1, V2, col, r); else dl:AddRectFilled(V1, V2, col); end
end
T.frect = frect;

-- Bar look = shape + texture + frame, any colour preset (Look tab; bar.lua keys
-- bar_style / bar_texture / bar_frame).
--   shape    soft  rounded; light upper band, 1px top highlight, 1px dark bottom edge
--            flat  square, plain fill
--            glass rounded; strong shine on the upper half, darker lower half
--   texture  none | segmented (10 blocks) | striped (thin dark ribs every 4px)
--            quarters (marks at 25/50/75% across the track) | scanline (dark line every 2px)
--            fade (fill darkens toward the empty end)
--   frame    hollow 1px frame in the fill colour, fill inset by 2px
T.SHAPE_ORDER   = { 'soft', 'flat', 'glass' };
T.TEXTURE_ORDER = { 'none', 'segmented', 'striped', 'quarters', 'scanline', 'fade' };
T.STYLE_LABEL = { soft = 'Soft', flat = 'Flat', glass = 'Glass',
                  none = 'None', segmented = 'Segmented', striped = 'Striped',
                  quarters = 'Quarters', scanline = 'Scanline', fade = 'Fade',
                  tinted = 'Tinted', dark = 'Dark', clear = 'Clear', framed = 'Framed' };
local TEXTURES = { segmented = true, striped = true, quarters = true, scanline = true, fade = true };

-- Panel backgrounds (target / cast / JA / menu panels and the AAEV plate).
--   tinted  dark plate tinted by target kind (default)
--   dark    one dark plate for every kind (the kind stripe stays)
--   clear   no plate, only the kind stripe
--   framed  tinted, plus a 1px frame in the kind colour
-- panel_alpha multiplies the plate opacity (0.25 - 2).
T.PANEL_ORDER = { 'tinted', 'dark', 'clear', 'framed' };
local PANELS = { tinted = true, dark = true, clear = true, framed = true };
T.panel_style, T.panel_alpha = 'tinted', 1.0;
function T.set_panel(style, alpha)
    T.panel_style = PANELS[style] and style or 'tinted';
    alpha = tonumber(alpha) or 1.0;
    T.panel_alpha = (alpha < 0.25) and 0.25 or ((alpha > 2.0) and 2.0 or alpha);
end

-- UI scale (0.5 - 3): one multiplier for goomui's text and pixel sizes, for small or high-DPI screens.
-- Text: ImGui 1.92's PushFont(font, size) sets the base font size and recomputes the current size at once
-- (imgui.cpp PushFont -> SetCurrentFont -> UpdateCurrentFontSize); Begin keeps it, PopFont restores it. So
-- goomui pushes base * scale around its own draws and other addons keep their size. Same call XIUI uses for
-- its config window (XIUI.lua PushChromeFont), gated the same way: Ashita 4.3 (ImGui 1.92) exposes a numeric
-- style.FontSizeBase; older builds have no size argument, so text stays unscaled there.
-- Pixel sizes: modules multiply by T.ui_scale (T.px).
T.ui_scale = 1.0;
function T.set_ui_scale(v)
    v = tonumber(v) or 1.0;
    T.ui_scale = (v < 0.5) and 0.5 or ((v > 3.0) and 3.0 or v);
end
function T.px(n) return floor(n * T.ui_scale + 0.5); end

local font_size_ok = nil;   -- Ashita 4.3+: PushFont takes a size
local font_pushed = false;
-- Wrap every goomui draw (d3d_present) in these two. No-ops at scale 1.
function T.scale_begin()
    if (T.ui_scale == 1.0 or font_pushed) then return; end
    local st = imgui.GetStyle();
    if (font_size_ok == nil) then font_size_ok = (st ~= nil and type(st.FontSizeBase) == 'number'); end
    if (not font_size_ok) then return; end
    imgui.PushFont(imgui.GetFont(), floor(st.FontSizeBase * T.ui_scale + 0.5));
    font_pushed = true;
end
function T.scale_end()
    if (not font_pushed) then return; end
    imgui.PopFont();
    font_pushed = false;
end

-- Alpha byte times m (imgui U32 and sprite ARGB both keep alpha in the top byte).
function T.scale_alpha(c, m)
    local a = floor(floor(c / 0x1000000) * m + 0.5);
    if (a > 255) then a = 255; elseif (a < 0) then a = 0; end
    return (c % 0x1000000) + a * 0x1000000;
end
T.shape, T.texture, T.frame = 'soft', 'none', false;

-- Old single-style names (goomui 2.0) map onto shape + texture + frame.
local OLD_STYLE = { segmented = { 'soft', 'segmented' }, striped = { 'flat', 'striped' }, outline = { 'flat', 'none', true } };
function T.set_look(shape, texture, frame)
    local old = OLD_STYLE[shape];
    if (old ~= nil) then shape, texture, frame = old[1], old[2], old[3] or frame; end
    T.shape   = (shape == 'soft' or shape == 'flat' or shape == 'glass') and shape or 'soft';
    T.texture = TEXTURES[texture] and texture or 'none';
    T.frame   = (frame == true);
end

for _, K in ipairs({ { T.U, u32 }, { T.A, argb } }) do
    local t, mk = K[1], K[2];
    t.GLASS_HI  = mk(255, 255, 255, 46);
    t.GLASS_TOP = mk(255, 255, 255, 110);
    t.GLASS_LO  = mk(0, 0, 0, 46);
    t.GAP       = mk(0, 0, 0, 120);
    t.STRIPE    = mk(0, 0, 0, 70);
    t.SCAN      = mk(0, 0, 0, 55);
    t.MARK      = mk(255, 255, 255, 70);
end

-- Same alpha byte position in imgui U32 (AABBGGRR) and sprite ARGB (AARRGGBB).
local function with_alpha(c, a) return (c % 0x1000000) + a * 0x1000000; end

-- One bar in the current look through R(x, y, w, h, colour, rounding).
-- K = T.U (imgui) or T.A (sprite): the overlay colours for that backend.
function T.draw(R, K, x, y, w, h, frac, col)
    local shape, tex, frame = T.shape, T.texture, T.frame;
    local round = (not frame and shape ~= 'flat') and 2.0 or nil;
    R(x, y, w, h, K.TRACK, round);
    if (frac == nil or frac <= 0) then frac = 0; end
    if (frac > 1) then frac = 1; end

    -- Frame: hollow outline over the whole track; the fill sits inside it.
    local fx, fy, fwmax, fh = x, y, w, h;
    if (frame) then
        local bc = with_alpha(col, 170);
        R(x, y, w, 1, bc); R(x, y + h - 1, w, 1, bc);
        R(x, y, 1, h, bc); R(x + w - 1, y, 1, h, bc);
        if (h < 5 or w < 5) then return; end
        fx, fy, fwmax, fh = x + 2, y + 2, w - 4, h - 4;
    end
    local fw = floor(fwmax * frac + 0.5);
    if (fw < 1) then
        if (tex == 'quarters' and fwmax >= 20) then
            for k = 1, 3 do R(fx + floor(fwmax * k / 4), fy, 1, fh, K.MARK); end
        end
        return;
    end
    R(fx, fy, fw, fh, col, round);

    if (fh >= 3 and fw >= 3) then
        if (shape == 'glass') then
            local half = floor(fh * 0.5 + 0.5);
            R(fx + 1, fy, fw - 2, half, K.GLASS_HI);
            R(fx + 1, fy, fw - 2, 1, K.GLASS_TOP);
            R(fx + 1, fy + half, fw - 2, fh - half, K.GLASS_LO);
        elseif (shape == 'soft') then
            R(fx + 1, fy, fw - 2, floor(fh * 0.45 + 0.5), K.HI_BAND);
            R(fx + 1, fy, fw - 2, 1, K.HI_LINE);
            R(fx + 1, fy + fh - 1, fw - 2, 1, K.LO_LINE);
        end
    end
    if (tex == 'segmented' and fwmax >= 40) then
        for i = 1, 9 do
            local gx = fx + floor(fwmax * i / 10);
            if (gx < fx + fw) then R(gx, fy, 1, fh, K.GAP); end
        end
    elseif (tex == 'striped') then
        for sx = fx + 3, fx + fw - 2, 4 do R(sx, fy, 1, fh, K.STRIPE); end
    elseif (tex == 'scanline') then
        for sy = fy + 1, fy + fh - 1, 2 do R(fx, sy, fw, 1, K.SCAN); end
    elseif (tex == 'fade') then
        -- dark-to-clear ramp across the track (darkest at the left), clipped to the fill: ~3 px bands (5-16)
        -- so the steps don't show. Black with alpha a is a * 0x1000000 in both imgui U32 and sprite ARGB.
        -- Rounded shapes: 1 px in from each end so the overlay doesn't square off the round corners.
        local n = floor(fwmax / 3);
        n = (n < 5) and 5 or ((n > 16) and 16 or n);
        local x0, x1 = fx, fx + fw;
        if (round ~= nil) then x0, x1 = x0 + 1, x1 - 1; end
        local bw = fwmax / n;
        for i = 1, n do
            local bx = math.max(x0, fx + floor((i - 1) * bw));
            local bx2 = math.min(x1, fx + floor(i * bw));
            if (bx2 > bx) then R(bx, fy, bx2 - bx, fh, floor(90 * (n - i + 0.5) / n + 0.5) * 0x1000000); end
        end
    end
    if (tex == 'quarters' and fwmax >= 20) then
        for k = 1, 3 do R(fx + floor(fwmax * k / 4), fy, 1, fh, K.MARK); end
    end
end

local cur_dl = nil;
local function dl_rect(x, y, w, h, c, r) frect(cur_dl, x, y, x + w, y + h, c, r); end

function T.bar(dl, x, y, w, h, frac, col)
    cur_dl = dl;
    T.draw(dl_rect, T.U, x, y, w, h, frac, col);
    cur_dl = nil;
end

-- Job colours: copied verbatim from GoomSwap common/gcdisplay.lua JOB_COL (keep in sync).
-- Keyed by the client's job abbreviation (resource 'jobs.names_abbr'). JOB_F4: imgui floats, JOB_ARGB: party sprite tint.
local JOB_COL = {
    WAR = { 1.00, 0.45, 0.40 }, MNK = { 0.96, 0.70, 0.04 }, WHM = { 1.00, 0.82, 0.75 },
    BLM = { 0.71, 0.39, 1.00 }, RDM = { 1.00, 0.22, 0.61 }, THF = { 0.53, 1.00, 0.14 },
    PLD = { 0.12, 0.71, 1.00 }, DRK = { 0.73, 0.44, 0.80 }, BST = { 0.85, 0.58, 0.33 },
    BRD = { 0.80, 0.85, 0.02 }, RNG = { 0.52, 0.65, 0.36 }, SAM = { 0.72, 0.49, 0.48 },
    NIN = { 0.53, 0.62, 0.70 }, DRG = { 0.02, 0.98, 1.00 }, SMN = { 0.18, 1.00, 0.76 },
    BLU = { 0.19, 0.54, 1.00 }, COR = { 0.65, 0.61, 0.10 }, PUP = { 1.00, 0.55, 0.74 },
    DNC = { 1.00, 0.18, 0.89 }, SCH = { 0.82, 0.75, 1.00 }, GEO = { 0.11, 0.81, 0.33 },
    RUN = { 1.00, 0.45, 0.04 },
};
T.JOB_F4, T.JOB_ARGB = {}, {};
for j, c in pairs(JOB_COL) do
    local r, g, b = floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5);
    T.JOB_F4[j], T.JOB_ARGB[j] = { c[1], c[2], c[3], 1.0 }, argb(r, g, b);
end

-- imgui: text with a 1px black outline (readable on any background, like the party list text).
local OUTLINE, TP, BLACK = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }, { 0, 0 }, u32(0, 0, 0);
function T.text_outlined(dl, x, y, col, s)
    for k = 1, 4 do
        TP[1], TP[2] = x + OUTLINE[k][1], y + OUTLINE[k][2];
        dl:AddText(TP, BLACK, s);
    end
    TP[1], TP[2] = x, y;
    dl:AddText(TP, col, s);
end

return T;
