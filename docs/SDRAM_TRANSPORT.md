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


The staged sdram_check fit passes every reported setup/hold/pulse corner and all
six timing-coverage gates with 404 ALMs, 920 registers including the evaluation
boundary, and no M10K blocks. Exact timing and scope are recorded in
reference/sdram_synth.json. The Quartus-exported functional netlist passes the
same VHDL command-level scoreboard: 60 writes, 360 checked read words and no
warnings/errors. Its measured maximum per-chip refresh gap is 324 clocks.
reference/sdram_netlist_checks.json pins that netlist, bench and transcript.
These results retain the hypothetical external tester timing limitation above.

A new video_sdram_capture_tb.vhd connects the native board/video path to the ROM
requester, actual SDRAM controller and command model. Captured graphics ROM bytes
are loaded directly into model memory through ModelSim's mem load command;
physical loader writes are verified separately, so a successful screenshot must
not be described as loader proof. The bench runs competing synthetic main-ROM
reads and work-RAM writes, checking CPU byte order, complete RGB, scanline tags,
streaming latency and reset draining. The Rabbit Punch play1000 replay passes every one of 62208 RGB pixels, with
17256 checked competing CPU ROM reads and 129559 work-RAM writes. Reset draining,
live bitmap/palette updates, tags and fixed pixel output latency also pass.
The worst line is 3806 clocks (about 79.3 us at 48 MHz). This is throughput
measurement under synthetic traffic, not an established physical deadline.
reference/video_sdram_checks.json currently contains this one completed capture;
it must not be presented as all six shared-SDRAM scenes. A Rabio Lepus replay
is running separately.


The ROM address/lane adapter also passes standalone Quartus implementation and
its synthesized functional netlist passes all 288 delayed/backpressured replies
in the VHDL scoreboard. Reports: reference/rom_requests_synth.json and
reference/rom_requests_netlist_checks.json. No new state or latency is added by
the wire-only flattening harness used for that proof.

## Last-burst ROM cache

rabbitpunch_rom_cache.vhd retains one eight-byte aligned ROM burst per client,
24 data bytes total plus tags/valid bits. It is read-only and contains no pixels.
It reuses adjacent graphics halves and the four 68000 words already returned by
one SDRAM burst. Misses keep independent client requests pending until the
backend accepts/responds; hits return registered data without SDRAM access.
Game reset leaves immutable ROM cache entries valid. Image replacement must
first drain all clients, then pulse invalidate before any new request.

The directed test passes 444 replies using 54 backend fetches, with independent
stalls, tag replacements, changed input pins and changed backing data after
invalidation. This is synthetic hit/miss coverage, not a gameplay speed claim.
The cache's isolated implementation and synthesized functional netlist also
pass, including mixed hits/misses on independent clients. It uses 441 ALMs,
577 registers and no M10K blocks under the documented synthetic tester contract.
Exact reports: reference/rom_cache_synth.json and rom_cache_netlist_checks.json.
The cached full-RGB comparison is next. A separate cached bench preserves the
completed uncached timing baseline.


## Connected ROM subsystem

rabbitpunch_roms.vhd connects the requester, cache and physical SDRAM adapter.
Its word-loader shares port 2 under an explicit loading mode. Enter/leave that
mode only after o_idle; a registered ownership flag prevents a loader response
from reaching the CPU/cache path. Beginning a load invalidates the drained ROM
caches. Externally hold CPU/video reset while loading and issue word requests
only with loader-ready. The transport itself remains active throughout download.
No HPS ioctl/DDR staging interface is connected yet.

The connected VHDL/chip-model test passes 34 loader writes across two distinct
images and 42 simultaneous requester replies. It checks partial-byte loading,
CPU byte order, both tile banks, adjacent words hitting one cached burst,
loader-response isolation and replacement-image invalidation of all three warm
caches. Ten physical read bursts serve the checks. The completed report is
reference/rom_subsystem_checks.json. Its production-top implementation/netlist
verification is next; this test does not establish electrical pin timing.

Uncached full-pixel SDRAM proof now includes both Rabbit Punch play1000 and
Rabio Lepus attract, 124416 matching RGB pixels total. The report has exactly
those two captures; the six-scene native-BRAM proof is a separate regression.


The connected production ROM top passes staged implementation in every reported
corner, with 520 ALMs, 1196 registers and no M10K blocks. Its exported functional
netlist passes the same 34-write/42-reply/two-image VHDL loader/cache scoreboard.
Reports: reference/roms_synth.json and roms_netlist_checks.json. The explicit
synthetic external tester timing limitation remains; no physical PLL/PCB timing
or HPS loader claim follows from these fits.

The first cached full-pixel replay, Rabbit Punch play1000, matches all 62208 RGB
pixels, including live updates, tags, fixed scanout latency and reset draining.
Worst line cost drops from 3806 uncached to 1939 cached clocks (about 79.3 to
40.4 us at 48 MHz). The same synthetic CPU request generator completes 33956
checked ROM reads and 72199 work-RAM writes; 8956 physical SDRAM READ commands
are counted. CPU traffic is response-driven, so the read counts differ between
runs; this is an identical captured image and generator, not an identical
bus-request trace. No complete physical scanline deadline is claimed. The
cached report currently contains this one scene; the remaining five run serially.
