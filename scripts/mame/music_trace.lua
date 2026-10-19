-- SPDX-License-Identifier: GPL-3.0-or-later
-- Appended to an immutable, already-qualified gameplay capture script.
local music_file = assert(io.open(OUT .. "/music_writes.txt", "w"))
local audio_space = assert(m.devices[":audiocpu"].spaces["program"])
core_subs[#core_subs + 1] = audio_space:install_write_tap(0xf000, 0xf601, "music_trace", guard("music_trace", function(address, data, mask)
    if address == 0xf000 or address == 0xf001 or address == 0xf400 or address == 0xf600 then
        music_file:write(string.format("%.9f %d %04X %02X\n", m.time:as_double(), m.screens[":screen"]:frame_number(), address, data & 0xff))
        music_file:flush()
    end
end))
