-- SPDX-License-Identifier: GPL-3.0-or-later
-- Exercise CPU read overrides without writing cheated values into physical RAM.
local m = manager.machine
local out = assert(os.getenv('CORE_OUT'))
local space = assert(m.devices[':maincpu'].spaces['program'])
local codes = {
    {address=0xfc269, value=0x90}, {address=0xfc3d9, value=3}, {address=0xfc3d8, value=0},
    {address=0xfc2a9, value=0x90}, {address=0xfc3f9, value=3}, {address=0xfc3f8, value=0}
}
for _, code in ipairs(codes) do
    code.active_reads, code.changed_reads = 0, 0
end
local trace = assert(io.open(out .. '/cheat_reads.txt', 'w'))
local states = assert(io.open(out .. '/cheat_states.txt', 'w'))
local writes = assert(io.open(out .. '/cheat_writes.txt', 'w'))
local semantics = assert(io.open(out .. '/cheat_semantics.txt', 'w'))
local perturbations = assert(io.open(out .. '/cheat_perturbations.txt', 'w'))
local active, monitor, bypass, failed = false, false, false, false
local frame = 0
local natural_reads, overridden_reads = 0, 0
local function guard(name, fn)
    return function(...)
        local ok, result = pcall(fn, ...)
        if not ok then
            failed = true
            local file = assert(io.open(out .. '/lua_error.txt', 'a'))
            file:write(name .. ': ' .. tostring(result) .. '\n')
            file:close()
            print('CHEAT_REFERENCE_ERROR ' .. tostring(result))
            m:exit()
        else
            return result
        end
    end
end
local subs = {}
local on_read = guard('read', function(offset, data, mask)
    local result = data
    local matched = false
    for _, code in ipairs(codes) do
        if (offset & 0xffffe) == (code.address & 0xffffe) then
            local shift = (code.address & 1) == 0 and 8 or 0
            local byte_mask = 0xff << shift
            -- The hardware overrides the complete 16-bit response, independent
            -- of which lane the CPU ultimately consumes.
            matched = true
            if active and not bypass then
                result = (result & ~byte_mask) | (code.value << shift)
                if not monitor and (mask & byte_mask) ~= 0 then
                    code.active_reads = code.active_reads + 1
                    if ((data >> shift) & 0xff) ~= code.value then
                        code.changed_reads = code.changed_reads + 1
                    end
                end
            end
        end
    end
    if matched and not monitor then
        natural_reads = natural_reads + 1
        if active then overridden_reads = overridden_reads + 1 end
        trace:write(string.format('%d %06X %04X %04X %04X %d\n', frame, offset, data, mask, result, active and 1 or 0))
    end
    if active and not bypass and matched then return result end
end)
local on_write = guard('write', function(offset, data, mask)
    for _, code in ipairs(codes) do
        if (offset & 0xffffe) == (code.address & 0xffffe) then
            writes:write(string.format('%d %06X %04X %04X %06X\n', frame, offset, data, mask,m.devices[':maincpu'].state['PC'].value))
            break
        end
    end
end)
-- MAME already masks this space to 20 bits; the RTL explicitly masks its bus.
for _, address in ipairs({0xfc268,0xfc2a8,0xfc3d8,0xfc3f8}) do
    local name = string.format('%06x',address)
    subs[#subs + 1] = space:install_read_tap(address,address+1,'cheat_read_'..name,on_read)
    subs[#subs + 1] = space:install_write_tap(address,address+1,'cheat_write_'..name,on_write)
end
local inputs = {}
for _, spec in ipairs({{':SERVICE',8},{':SERVICE',16},{':SERVICE',32},{':SERVICE',64},{':P1',16},{':P1',32},{':P2',16},{':P2',32}}) do
    inputs[#inputs + 1] = {tag=spec[1],mask=spec[2],field=assert(m.ioport.ports[spec[1]]:field(spec[2]))}
end
subs[#subs + 1] = emu.add_machine_frame_notifier(guard('frame', function()
    frame = m.screens[':screen']:frame_number()
    for _, input in ipairs(inputs) do
        local enabled = false
        if input.tag == ':SERVICE' then
            if input.mask == 16 then enabled = frame >= 600 and frame < 720 and (frame % 12) < 6 end
            if input.mask == 64 then enabled = frame >= 760 and frame < 766 end
        elseif frame >= 810 then
            enabled = (frame % 20) < 10
        end
        input.field:set_value(enabled and 1 or 0)
    end
    active = frame >= 800 and frame < 5000
    if frame == 3000 then
        -- Controlled stimulus exercises full-life and damage counters even when
        -- a player has not been hit. This is a test-only RAM perturbation.
        monitor, bypass = true, true
        for _, address in ipairs({0xfc3d9,0xfc3f9}) do
            space:write_u8(address,1)
            perturbations:write(string.format('%d %06X 01\n',frame,address))
        end
        for _, address in ipairs({0xfc3d8,0xfc3f8}) do
            space:write_u8(address,2)
            perturbations:write(string.format('%d %06X 02\n',frame,address))
        end
        monitor, bypass = false, false
    end
    if frame % 10 == 0 then
        monitor = true
        states:write(string.format('%d %d %06X', frame, active and 1 or 0, m.devices[':maincpu'].state['PC'].value))
        for _, code in ipairs(codes) do
            bypass = true
            local raw = space:read_u8(code.address)
            bypass = false
            local seen = space:read_u8(code.address)
            bypass = true
            local after = space:read_u8(code.address)
            bypass = false
            assert(after == raw, 'Read override modified underlying RAM')
            assert(seen == (active and code.value or raw), string.format('CPU byte read mismatch frame=%d addr=%06X raw=%02X seen=%02X expected=%02X',frame,code.address,raw,seen,active and code.value or raw))
            states:write(string.format(' %02X:%02X', raw, seen))
        end
        states:write('\n')
        monitor = false
    end
    if frame == 3600 then m.screens[':screen']:snapshot(out .. '/gameplay.png') end
    if frame >= 6600 then
        assert(not failed and natural_reads > 0 and overridden_reads > 0, 'No natural game CPU cheat reads')
        for _, code in ipairs(codes) do
            assert(code.active_reads > 0 and code.changed_reads > 0,'Cheat field not exercised by natural CPU reads')
            semantics:write(string.format('%06X %02X %d %d\n',code.address,code.value,code.active_reads,code.changed_reads))
        end
        trace:close()
        states:close()
        writes:close()
        semantics:close()
        perturbations:close()
        print(string.format('CHEAT_REFERENCE_PASS natural_reads=%d overridden_reads=%d',natural_reads,overridden_reads))
        m:exit()
    end
end))
_G.cheat_reference_subscriptions = subs
