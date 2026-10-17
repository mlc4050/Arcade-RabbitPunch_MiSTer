-- Install taps before resetting, retaining every subscription across Lua GC.
if _G.sound_boot_started then return end
_G.sound_boot_started = true
local machine = manager.machine
local audio = machine.devices[":audiocpu"].spaces["program"]
local main = machine.devices[":maincpu"].spaces["program"]
local out = assert(os.getenv("CORE_OUT"))
local writes = assert(io.open(out .. "/sound_writes.txt", "w"))
local events = assert(io.open(out .. "/sound_events.txt", "w"))
local limit = assert(tonumber(os.getenv("SOUND_WRITES")))
local count, armed, done = 0, false, false
local function fail(message)
    if done then return end
    done = true
    local file = assert(io.open(out .. "/lua_error.txt", "w"))
    file:write(tostring(message) .. "\n")
    file:close()
    writes:close()
    events:close()
    machine:exit()
end
local function guarded(callback)
    return function(offset, data, mask)
        if armed and not done then
            local ok, err = pcall(callback, offset, data, mask)
            if not ok then fail(err) end
        end
        return data
    end
end
_G.sound_boot_reset = emu.add_machine_reset_notifier(function()
    local state_file = assert(io.open(out .. "/reset_state.txt", "w"))
    for key, value in pairs(machine.devices[":audiocpu"].state) do
        state_file:write(string.format("%s %s\n", key, tostring(value.value)))
    end
    state_file:close()
    armed = true
    print("SOUND_RESET_ARMED")
end)
_G.sound_boot_taps = {
    audio:install_write_tap(0, 0xffff, "sound_boot_writes", guarded(function(address, data, mask)
        count = count + 1
        writes:write(string.format("%04x %02x %02x\n", address, mask, data & mask))
        if address < 0xf800 then
            events:write(string.format("W %d %04x %02x\n", count, address, data & mask))
        end
        if count == limit then
            done = true
            writes:close()
            events:close()
            print(string.format("SOUND_BOOT_OK writes=%d", count))
            machine:exit()
        end
    end)),
    audio:install_read_tap(0xf200, 0xf200, "sound_command_read", guarded(function(address, data, mask)
        events:write(string.format("L %d %04x %02x\n", count, address, data & mask))
    end)),
    main:install_write_tap(0xc000e, 0xc000f, "sound_command_write", guarded(function(address, data, mask)
        if mask & 0xff ~= 0 then
            events:write(string.format("C %d %06x %02x\n", count, address, data & 0xff))
        end
    end))
}
machine:soft_reset()
