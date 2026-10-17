-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
-- Capture only the score block and boundary sentinels described by pinned
-- MAME hiscore.dat. This does not install the hiscore plugin or modify RAM.
if _G.rabbitpunch_hiscore_capture then return end
_G.rabbitpunch_hiscore_capture = true
local machine = manager.machine
local memory = machine.devices[":maincpu"].spaces["program"]
local out = assert(os.getenv("CORE_OUT"))
local address = assert(tonumber(os.getenv("HISCORE_ADDRESS")))
local length = assert(tonumber(os.getenv("HISCORE_LENGTH")))
local first = assert(tonumber(os.getenv("HISCORE_FIRST")))
local last = assert(tonumber(os.getenv("HISCORE_LAST")))
local frame, done = 0, false
local function fail(message)
    if done then return end
    done = true
    local file = assert(io.open(out .. "/lua_error.txt", "w"))
    file:write(tostring(message) .. "\n")
    file:close()
    machine:exit()
end
emu.register_frame_done(function()
    if done then return end
    local ok, err = pcall(function()
        frame = frame + 1
        if frame >= 2 and memory:read_u8(address) == first and memory:read_u8(address + length - 1) == last then
            local bytes = {}
            for offset = 0, length - 1 do
                bytes[#bytes + 1] = string.char(memory:read_u8(address + offset))
            end
            local file = assert(io.open(out .. "/initial.bin", "wb"))
            file:write(table.concat(bytes))
            file:close()
            local metadata = assert(io.open(out .. "/boundaries.txt", "w"))
            metadata:write(string.format("%d %06x %x %02x %02x %02x %02x\n", frame, address, length,
                memory:read_u8(address - 1), first, last, memory:read_u8(address + length)))
            metadata:close()
            done = true
            print(string.format("HISCORE_REFERENCE_OK frame=%d bytes=%d", frame, length))
            machine:exit()
        elseif frame >= 600 then
            error("Score-table initialization sentinels did not appear")
        end
    end)
    if not ok then fail(err) end
end)
