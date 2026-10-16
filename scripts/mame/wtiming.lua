-- Count a set's video RAM writes by scanline, for scripts/write_timing.py.
--
--   CORE_CPU, CORE_SPACE  the CPU and address space to tap (regions.json)
--   WT_IN_COIN/START/HOLD/PULSE  input field names (regions.json "inputs")
--   WT_OUT     output file
--   WT_TAPS    "name:hexlo:hexhi,..." regions to count
--   WT_FIELDS  "name:region:first:last:stride:offset:mask,..." (hex byte offsets)
--   WT_SKIP    frames to run before counting (boot)
--   WT_FRAMES  frames to count
--   WT_COIN    frame to insert a coin and then press Start (0 = attract only);
--              from Start, HOLD is held and PULSE pulsed, so play goes on
--
-- The scanline comes from time_until_pos, as in capture.lua (0.28x's screen
-- binding has no vpos). Writes are binned by line; per frame the last write
-- line of each region is binned too.

local OUT    = os.getenv("WT_OUT")
local TAPS   = os.getenv("WT_TAPS") or ""
local SKIP   = tonumber(os.getenv("WT_SKIP") or "600")
local FRAMES = tonumber(os.getenv("WT_FRAMES") or "1200")
local COIN   = tonumber(os.getenv("WT_COIN") or "0")

local mach = manager.machine
local cpu  = mach.devices[os.getenv("CORE_CPU") or ":maincpu"]
local prog = cpu.spaces[os.getenv("CORE_SPACE") or "program"]
local scr  = mach.screens[":screen"]

local function split(s, sep)
    local out = {}
    for tok in string.gmatch(s, "([^" .. sep .. "]+)") do out[#out + 1] = tok end
    return out
end

local frame_period = 1.0 / scr.refresh
local line_period
for _ = 1, 64 do
    local d = scr:time_until_pos(1) - scr:time_until_pos(0)
    if d > 0 and (line_period == nil or d < line_period) then line_period = d end
end
local vtotal = math.floor(frame_period / line_period + 0.5)

local function cur_line()
    return math.floor((frame_period - scr:time_until_pos(0)) / line_period + 0.5) % vtotal
end

-- vblank start line: frame_done runs when MAME finishes a frame, at vblank
-- start, so the line in force there (most common over the skipped frames) is
-- taken as vblank start. (time_until_vblank_start from an autoboot script
-- crashed MAME 0.285.)
local vbstart = -1
local vb_votes = {}

local names, hist, lastl = {}, {}, {}
local counting = false
local frame_last = {}
local fields = {}
local function add_histogram(name)
    assert(hist[name] == nil, "duplicate write histogram: " .. name)
    names[#names + 1] = name
    hist[name] = {}
    lastl[name] = {}
end
local function count_write(name, line)
    hist[name][line] = (hist[name][line] or 0) + 1
    frame_last[name] = line
end
for _, entry in ipairs(split(os.getenv("WT_FIELDS") or "", ",")) do
    local f = split(entry, ":")
    assert(#f == 7, "malformed WT_FIELDS entry: " .. entry)
    local item = {name=f[1], first=tonumber(f[3],16), last=tonumber(f[4],16),
                  stride=tonumber(f[5],16), offset=tonumber(f[6],16), mask=tonumber(f[7],16)}
    assert(item.stride > 0 and item.first <= item.last, "invalid video field: " .. entry)
    fields[f[2]] = fields[f[2]] or {}
    table.insert(fields[f[2]], item)
    add_histogram(item.name)
end
_G.__wt_taps = {}
local tapped = {}
for _, spec in ipairs(split(TAPS, ",")) do
    local f = split(spec, ":")
    local name, lo, hi = f[1], tonumber(f[2], 16), tonumber(f[3], 16)
    add_histogram(name)
    tapped[name] = true
    local tap = prog:install_write_tap(lo, hi, "wt_" .. name, function(offset, data, mask)
        if counting then
            local l = cur_line()
            count_write(name, l)
            local relative = offset - lo
            for _, item in ipairs(fields[name] or {}) do
                if relative >= item.first and relative <= item.last
                    and (relative - item.first) % item.stride == item.offset
                    and (mask & item.mask) ~= 0 then
                    count_write(item.name, l)
                end
            end
        end
        return data
    end)
    _G.__wt_taps[#_G.__wt_taps + 1] = tap
end
for name, _ in pairs(fields) do
    assert(tapped[name], "video field source is not tapped: " .. name)
end

local function field(name)
    for _, port in pairs(mach.ioport.ports) do
        local f = port.fields[name]
        if f then return f end
    end
    return nil
end
local f_coin, f_start = field(os.getenv("WT_IN_COIN") or "Coin 1"), field(os.getenv("WT_IN_START") or "1 Player Start")
local f_right, f_b1 = field(os.getenv("WT_IN_HOLD") or "P1 Right"), field(os.getenv("WT_IN_PULSE") or "P1 Button 1")
if COIN > 0 then
    assert(f_coin and f_start and f_right and f_b1, "a scripted-play input field is missing")
end

local n = 0
emu.register_frame_done(function()
    n = n + 1
    if COIN > 0 and f_coin and f_start then
        f_coin:set_value((n >= COIN and n < COIN + 6) and 1 or 0)
        f_start:set_value((n >= COIN + 90 and n < COIN + 96) and 1 or 0)
        if n >= COIN + 96 then
            if f_right then f_right:set_value(1) end
            if f_b1 then f_b1:set_value((n % 20) < 4 and 1 or 0) end
        end
    end
    if n > 10 and n <= SKIP then
        local l = cur_line()
        vb_votes[l] = (vb_votes[l] or 0) + 1
    end
    if n == SKIP then
        counting = true
        local best = 0
        for l, c in pairs(vb_votes) do
            if c > best then best = c; vbstart = l end
        end
    end
    if counting then
        -- a frame's last write, binned at the end of the frame MAME rendered
        for name, l in pairs(frame_last) do
            lastl[name][l] = (lastl[name][l] or 0) + 1
        end
        frame_last = {}
    end
    if n == SKIP + FRAMES then
        if os.getenv("WT_SNAP") == "1" then mach.video:snapshot() end
        local f = assert(io.open(OUT, "w"))
        f:write(string.format("vtotal %d\nvbstart %d\nframes %d\n", vtotal, vbstart, FRAMES))
        for _, name in ipairs(names) do
            local parts = {}
            for l = 0, vtotal - 1 do parts[#parts + 1] = tostring(hist[name][l] or 0) end
            f:write("hist " .. name .. " " .. table.concat(parts, ",") .. "\n")
            parts = {}
            for l = 0, vtotal - 1 do parts[#parts + 1] = tostring(lastl[name][l] or 0) end
            f:write("last " .. name .. " " .. table.concat(parts, ",") .. "\n")
        end
        f:close()
        mach:exit()
    end
end)
