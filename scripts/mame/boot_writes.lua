-- Reset after installing taps, so autoboot scheduling cannot lose early accesses.
if _G.boot_writes_started then return end
_G.boot_writes_started = true
local machine = manager.machine
local space = machine.devices[":maincpu"].spaces["program"]
local out = assert(os.getenv("CORE_OUT"))
local file = assert(io.open(out .. "/mame_writes.txt", "w"))
local vector_file = assert(io.open(out .. "/mame_vectors.txt", "w"))
local count, vectors, armed, done = 0, 0, false, false
local limit = tonumber(os.getenv("BOOT_WRITES") or "512")
_G.boot_reset = emu.add_machine_reset_notifier(function()
    armed = true
    print("BOOT_TRACE_RESET_ARMED")
end)
_G.boot_taps = {
    space:install_read_tap(0, 7, "boot_vectors", function(offset, data, mask)
        if armed then
            vectors = vectors + 1
            vector_file:write(string.format("%06x %04x %04x\n", offset, mask, data & mask))
        end
        return data
    end),
    space:install_write_tap(0, 0xfffff, "boot_writes", function(offset, data, mask)
        if armed and not done then
            file:write(string.format("%06x %04x %04x\n", offset, mask, data & mask))
            count = count + 1
            if count == limit then
                done = true
                file:close()
                vector_file:close()
                print(string.format("BOOT_WRITES_OK writes=%d vector_reads=%d", count, vectors))
                machine:exit()
            end
        end
        return data
    end)
}
machine:soft_reset()
