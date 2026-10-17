# SDRAM transport

The selected unchanged donor is the configurable Vamphalf controller in
rtl/memory/sdram/, pinned with its command model in the vendor manifest.
rabbitpunch_sdram.vhd presents three pulse/ready clients with descriptive names
and numeric_std unsigned buses. The nonzero [26:1] vendor address ranges are
preserved inside the wrapper. Public addresses are 27-bit byte addresses.

Each client may have one pending request. Capture occurs only when ready;
request/address/data/byte fields are latched until the toggle acknowledgment.
Each response granule is captured immediately at acknowledgment because the
vendor read-data register is shared. Client 0 has fixed priority over 1 and 2;
this is not a fairness or game-throughput guarantee.

Reads are eight-byte aligned, return four ascending 16-bit words in low-to-high
lanes, and writes are even-addressed 16-bit words with independent byte enables.
Double reads and extra write beats are disabled. iou16_sdram_data is the
bidirectional unsigned pin bus. Its iou prefix denotes inout.

The power-up path holds vendor initialization high for 6000 clocks after the
external initialize input releases, then allows 1024 clocks for its falling-edge
initialization sequence. At 48 MHz the first interval exceeds 100 us. A game
reset must not connect to i_initialize; reinitialization requires drained
clients. The transport never stops for CPU pause or ROM download/game reset.

REFRESH_INTERVAL_CYCLES defaults to 160 at the 48 MHz evaluation clock. The
donor alternates commands between the two chips on the single 128 MB module.
Clock-specific timing is explicit: it must be recalculated and retested if the
system clock changes. No final PLL, pin clock phase or I/O-delay constraints
are selected here.

Run ./scripts/d_drive.ps1 scripts/run_sdram_tests.py. The VHDL testbench drives
the actual controller pins into the unchanged command-decoding model, writes
and reads distinct bursts at region boundaries, banks, column bit 9, both chips
and the highest module address, alters inputs after pulse capture, queues all
three clients together, checks masked writes and neighboring burst words,
response stability and idle duplicate prevention, and monitors refresh gaps
per chip during traffic and idle time. The model does not simulate charge
retention, PCB delays or electrical timing. This is functional evidence only;
full integration still needs Quartus implementation and real-pin timing.

The board's CPU/graphics ROM clients and MiSTer loader are not connected yet.
Their mapping must preserve raw stream bytes: graphics requests consume packed
little-endian words; 68000 words require explicit big-endian byte assembly.


## ROM requester mapping

rabbitpunch_rom_requests queues one pulse from each of sprite, tile and main CPU
clients until the corresponding backend port is ready. Its latched address
includes the tile foreground bank and the requested word offset within a burst.
It aligns backend reads to eight bytes, selects the correct 32-bit graphics
half or 16-bit CPU word, and assembles CPU bytes in 68000 order. Transport state
must drain before a consumer restarts its request stream. No cache is present.

run_rom_request_tests.py checks 288 replies against address-dependent byte data
with changing input pins and independent backend backpressure. The same VHDL
scoreboard also runs through the actual controller and chip-command model after
192 physical preload writes. Region starts/ends, both tile banks, both graphics
halves and all four CPU word lanes are covered. Reports are in
reference/rom_request_checks.json. Real ROM/video integration is still pending.

The sdram_check implementation target adds same-clock registered client inputs
and outputs, preserving the physical pin command/data latency. It pins the SDRAM
bus to the template's module pins. Its half-period synthetic DQ input contract
is explicitly hypothetical: it checks elaboration, placement and internal paths,
not real chip/PCB electrical timing. No final PLL or chip-clock phase is proven.
The same VHDL pin scoreboard binds to this wrapper for RTL and synthesized
functional-netlist tests. Do not include it in the production core.
