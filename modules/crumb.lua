--[[
* goomui crash marker.
*
* A native crash inside a d3d_present callback (EXCEPTION_ACCESS_VIOLATION) makes Ashita unload goomui without a
* Lua stack, so the chat line cannot say which part of goomui crashed. Each draw step writes its name into a small
* block of process memory before it runs and clears it when its callback ends. That block outlives the addon: it
* is VirtualAlloc'd once and its address kept in a process environment variable (kernel32 through LuaJIT's ffi.C,
* which on Windows includes kernel32.dll: luajit.org/ext_ffi_api.html). On the next load a name still there is the
* step that was running when goomui was unloaded.
*
* begin(name): a d3d_present callback starts. A name already there means the previous step never finished; the
*              first such name is kept apart, so a later callback in the same frame cannot overwrite it.
* step(name):  a part of that callback starts (replaces the name).
* sub(name) / back(): a nested part (texture builds, game calls) and the name it interrupted, restored.
* done():      the callback finished (also after a Lua error, which goomui catches and prints itself).
* report():    the step a previous load died in, or nil; then clears it.
--]]

local ffi = require('ffi');

local M = {};

local SIZE = 64;              -- bytes per slot; names are shorter
local ENV  = 'GOOMUI_CRASH_MARKER';
local cur, first = nil, nil;  -- char* slots: the step running now / the first step found unfinished
local now, prev = '', '';     -- Lua copies of the names: sub() / back() restore without reading the slot

local function decl(s) pcall(ffi.cdef, s); end -- already declared (another lib, a reload): keep that one
decl('void* __stdcall VirtualAlloc(void* address, size_t size, uint32_t type, uint32_t protect);');
decl('uint32_t __stdcall GetEnvironmentVariableA(const char* name, char* buffer, uint32_t size);');
decl('int __stdcall SetEnvironmentVariableA(const char* name, const char* value);');

local function init()
    local C = ffi.C;
    local buf = ffi.new('char[32]');
    local n = C.GetEnvironmentVariableA(ENV, buf, 32);
    local addr = (n > 0 and n < 32) and tonumber(ffi.string(buf, n)) or nil;
    if (addr == nil or addr == 0) then
        local p = C.VirtualAlloc(nil, 4096, 0x3000, 0x04); -- MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE; never freed
        if (p == nil) then return; end
        ffi.fill(p, SIZE * 2, 0);
        addr = tonumber(ffi.cast('uintptr_t', p));
        C.SetEnvironmentVariableA(ENV, string.format('%.0f', addr));
    end
    cur   = ffi.cast('char*', addr);
    first = cur + SIZE;
end
if (not pcall(init)) then cur, first = nil, nil; end -- no marker; goomui runs as before

local function fit(name) return (#name < SIZE) and name or name:sub(1, SIZE - 1); end

function M.begin(name)
    if (cur == nil) then return; end
    name = fit(name);
    if (cur[0] ~= 0 and first[0] == 0) then ffi.copy(first, cur, SIZE); end
    ffi.copy(cur, name);
    now = name;
end

function M.step(name)
    if (cur == nil) then return; end
    name = fit(name);
    ffi.copy(cur, name);
    now = name;
end

function M.sub(name)
    if (cur == nil) then return; end
    prev = now;
    M.step(name);
end

function M.back()
    if (cur ~= nil) then M.step(prev); end
end

function M.done()
    if (cur ~= nil) then cur[0] = 0; end
end

function M.report()
    if (cur == nil) then return nil; end
    local s = nil;
    if (first[0] ~= 0) then s = ffi.string(first); elseif (cur[0] ~= 0) then s = ffi.string(cur); end
    ffi.fill(cur, SIZE * 2, 0);
    return s;
end

return M;
