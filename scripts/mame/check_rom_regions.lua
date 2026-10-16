-- Dump the reference emulator's loaded regions for an independent MRA comparison.
local machine = manager.machine
local out = assert(os.getenv("ROMCHECK_OUT"))
for _, tag in ipairs({"maincpu", "audiocpu", "tiles1", "tiles2", "sprites", "upd"}) do
    local region = assert(machine.memory.regions[":" .. tag], "missing ROM region " .. tag)
    local file = assert(io.open(out .. "/" .. tag .. ".bin", "wb"))
    for base = 0, region.size - 1, 4096 do
        local bytes = {}
        for offset = base, math.min(base + 4095, region.size - 1) do
            bytes[#bytes + 1] = string.char(region:read_u8(offset))
        end
        file:write(table.concat(bytes))
    end
    file:close()
end
print("ROM_REGIONS_OK")
machine:exit()
