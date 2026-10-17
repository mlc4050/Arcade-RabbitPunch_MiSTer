-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
-- Live MAME input-port reference; no ROM bytes or rendered pixels are exported.
local machine = manager.machine
local outdir = assert(os.getenv("CORE_OUT"))
local ports = machine.ioport.ports
local cases = {}
local function add(id, joy0, joy1, key, pause, fields)
    cases[#cases + 1] = {id=id, joy0=joy0, joy1=joy1, key=key or 0xfff, pause=pause or 0, fields=fields or {}}
end
add("idle", 0, 0)
local p1 = {{"up",1,3,0x175},{"down",2,2,0x172},{"left",4,1,0x16b},{"right",8,0,0x174},{"missile",16,4,0x014},{"punch",32,5,0x011}}
local p2keys = {0x02d,0x02b,0x023,0x034,0x01c,0x01b}
for i, item in ipairs(p1) do
    add("p1_"..item[1], 1 << item[3], 0, item[4], 0, {{":P1",item[2]}})
    add("p2_"..item[1], 0, 1 << item[3], p2keys[i], 0, {{":P2",item[2]}})
end
add("service_p1",1<<13,0,0x046,0,{{":SERVICE",1}})
add("service_p2",0,1<<13,0x046,0,{{":SERVICE",1}})
add("test_p1",1<<14,0,0x006,0,{{":SERVICE",2}})
add("test_p2",0,1<<14,0x006,0,{{":SERVICE",2}})
add("coin1",1<<11,0,0x02e,0,{{":SERVICE",16}})
add("coin2",0,1<<11,0x036,0,{{":SERVICE",8}})
add("start1",1<<10,0,0x016,0,{{":SERVICE",32}})
add("start2",0,1<<10,0x01e,0,{{":SERVICE",64}})
add("pause_p1",1<<12,0,0x04d,1)
add("pause_p2",0,1<<12,0x04d,1)
local padkeys1 = {0x029,0x012,0x01a,0x022}
local padkeys2 = {0x015,0x01d,0x024,0xfff}
for i=1,4 do
    add("p1_padding"..i,1<<(i+5),0,padkeys1[i])
    add("p2_padding"..i,0,1<<(i+5),padkeys2[i])
end
add("unused_service2",0,0,0x045)
add("p1_diagonal",0x19,0,0xfff,0,{{":P1",1},{":P1",8},{":P1",16}})
add("two_players",0x19,0x26,0xfff,0,{{":P1",1},{":P1",8},{":P1",16},{":P2",2},{":P2",4},{":P2",32}})
add("both_buttons",0x30,0,0xfff,0,{{":P1",16},{":P1",32}})
local controlled = {}
for _, tag in ipairs({":P1",":P2"}) do
    for bit=0,5 do controlled[#controlled+1] = assert(ports[tag]:field(1<<bit)) end
end
for _, mask in ipairs({1,2,8,16,32,64}) do controlled[#controlled+1] = assert(ports[":SERVICE"]:field(mask)) end
local file = assert(io.open(outdir.."/input_vectors.txt","w"))
local index, applied, done = 1, false, false
local function fail(message)
    if done then return end
    done=true
    local errors=assert(io.open(outdir.."/lua_error.txt","w"))
    errors:write(tostring(message).."\n")
    errors:close()
    file:close()
    machine:exit()
end
emu.register_frame_done(function()
    if done then return end
    local ok, message=pcall(function()
        if applied then
            local case=cases[index]
            file:write(string.format("%s %08X %08X %03X %d %02X %02X %02X\n",case.id,case.joy0,case.joy1,case.key,case.pause,
                ports[":P1"]:read()&255,ports[":P2"]:read()&255,ports[":SERVICE"]:read()&255))
            index=index+1
            if index>#cases then
                file:close()
                done=true
                print("INPUT_VECTORS_OK cases="..#cases.." dips="..ports[":DSW"]:read())
                machine:exit()
                return
            end
        end
        for _, field in ipairs(controlled) do field:set_value(0) end
        for _, field in ipairs(cases[index].fields) do
            assert(ports[field[1]]:field(field[2])):set_value(1)
        end
        applied=true
    end)
    if not ok then fail(message) end
end)
