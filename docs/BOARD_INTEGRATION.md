# Logical board integration

`rtl/rabbitpunch_board.vhd` connects the executing fx68k, CPU bus adapter, native
board RAM, logical RGB renderer, board I/O and interrupt latch. It introduces
no new clock domain, RAM copy or transaction pipeline. Every component uses
`i_clk`; the main CPU advances through the existing phase enables.

The external ROM requester interface serves program, tile and sprite requests.
Connect it to `rabbitpunch_roms`, whose loader/cache/controller continues running
through game reset. Hold gameplay reset until ROM initialization/loading is
complete. This board module contains neither the physical SDRAM interface nor
the MiSTer HPS loader.

The caller supplies logical line requests, rendering/display bank selection,
pixel coordinates and vblank/half-frame events. The module does not select a
PLL, pixel divider, raster totals, blanking or line deadline. Those remain open
physical-timing decisions. The visible logical X range is 8..295, Y 0..215.
Set a pixel coordinate before checking address-dependent `o_pixel_ready`.

Video scroll, sprite count/priority and flags come from the CPU-written I/O
registers. Line rendering samples its control inputs using the existing line
acceptance contract; pixel flags follow the existing scanout interface. This
wiring does not introduce new frame snapshots. Sound command write/data/pending
and command-read ports are exposed for the future sound subsystem.

`i_initialize` clears cold-start I/O/IRQ state. `i_reset` resets CPU/video while
accepted memory/ROM transactions still drain. Neither clears native RAM. Pause
finishes the CPU bus cycle and stops CPU enables; it does not stop video or ROM
transport. State inspection requires the CPU paused and the relevant video
RAM bank drained, as documented in BOARD_VIDEO_MEMORY.md. Read-only CPU request
monitor ports support ordered-write comparisons without adding another bus master.

## Simulation

Run `./scripts/d_drive.ps1 scripts/check_board_sdram_boot.py --writes 1000` for
the connected-board regression. It executes both games, renders logical lines
concurrently, checks pixel tags/progress and compares every CPU write plus all
24 checked I/O state fields against the existing pinned MAME reset prefix.
The default extends to 10000 writes per game; it is still a bounded reset
prefix, not full game boot or gameplay verification.

This prefix writes work RAM, bitmap RAM and I/O only. The runner verifies that
precondition and explicitly seeds both arrays of each native simulation RAM
model with MAME-style zeros before releasing reset. Consequently the untouched
palette produces black RGB throughout this particular test. Hardware RAM stays
uninitialized; this seed is not a proposed reset circuit. Graphics appearance
is established separately by six captured-scene MAME pixel comparisons.
ROM bytes are preloaded directly into the SDRAM command model; word loading and
replacement-image invalidation have their own ROM subsystem tests.

No raster interrupt events or sound CPU are generated in this regression.
Logical lines run as soon as their resources allow, not at a claimed PCB cadence.

## Implementation check

`./scripts/d_drive.ps1 scripts/build_staged.py --synth-check board` implements
CPU, I/O, IRQ, native RAM and video together on Cyclone V. Its evaluation-only
wrapper adds same-clock launch/capture registers at logical interfaces. Synthetic
inputs change at half a clock period and outputs use zero delay. These assumptions
bound internal paths without exempting them; no false/multicycle paths are added.
It is not a constraint set for final MiSTer pins, PLL, SDRAM electrical timing or
physical raster. Check the resulting report before claiming timing closure.

The exact RAM-bit gate is 907936: native board/line RAM 868352, CPU micro ROM
17 x 1024 and CPU nano ROM 66 x 336. The pinned 68-bit nano-ROM file has constant
zero columns 2 and 23; Quartus explicitly removes those two columns. This is
verified against the donor data and synthesis report, not missing CPU state.
