# Tile pipeline

`rabbitpunch_tile_lookup.vhd` samples a coordinate, layer, scroll and flags when
its request is accepted. It requests a word from the column-major 64x64 tilemap:
layer bit, six column bits, six row bits. Coordinates and scrolling wrap at 512.
The descriptor selects the tile code and palette using the pinned MAME rules.
One decoded descriptor may wait while the preceding row is being drawn.

`rabbitpunch_tile_row.vhd` wraps the unchanged JTFRAME `jtframe_draw` with
descriptive unsigned ports. Eight-pixel truncation draws one native 8x8 tile
row. The adapter converts packed low-nibble-first tile ROM words into the
drawer's four bitplanes. The lowest-address ROM byte belongs in bits 7..0 of
the 32-bit response. ROM word addresses are local to tiles1 or tiles2; the
foreground output selects that region. Physical SDRAM transport is not wired.

Output is a burst of eight consecutive X-tagged, Y-tagged pixels. BG0 is opaque;
BG1 pen 15 is transparent. The palette index is nine bits, covering entries
0..255 for BG0 and 256..511 for BG1. A consumer must accept the entire burst.
Viewport cropping belongs downstream. There is no line RAM or frame RAM in
these modules. `rabbitpunch_tile_layer.vhd` connects lookup and row drawing.

Both request channels accept one external read at a time. Reset drops queued
pixels/descriptors and drains accepted RAM/ROM replies before reusing their
channels. Input changes while an accepted transaction is busy cannot change its
metadata. Scroll/flag sampling is per request; no PCB frame-latch point or
physical raster timing is claimed by this clock-independent plumbing.

## Verification

The row, queued-layer and captured-data benches are VHDL-2008, compiled with
ModelSim `vcom -2008`. A shared VHDL package reads unsigned hex vectors and
generates synthetic memory data. The captured-data bench selects a capture mode
of the layer bench; the imported JTFRAME drawer remains unchanged Verilog.
Only synthesizable RTL is passed to Quartus; simulation-only file I/O, waits
and assertions in these benches are not part of the hardware build.

The row test checks 4611 complete rows, plus a deliberately interrupted burst:
all eight tile rows, palette banks, both layers, code-bank boundaries, X wrap,
changing upstream inputs, ROM delays and reset before/during fetch/drawing.

The pipeline test checks all 8192 tilemap addresses, scroll wrapping, code and
palette bank flags, one queued descriptor, 0/3/11 extra memory wait cycles,
alternating layers and stale RAM reply draining. It verifies 8256 complete rows,
66048 pixels. These responders use deterministic synthetic data.

Six capture tests load real VRAM, video registers and both graphics ROM regions
from the MAME reference fixtures. For each scene, all 124416 visible layer pixels
and opacity bits match an independent per-pixel tile sampler: 746496 pixels
total. This sampler uses the layout already checked by the complete offline
renderer against MAME screenshots. It is not a direct screenshot comparison
of an integrated VHDL frame. The capture responders are behavioral memories;
the native board RAM has separate full-address and boot-integration tests.

Results and source/dump hashes are in reference/tile_checks.json. Each test's
debug/baselines/tiles_*/pixels.hex contains actual HDL palette indices/opacity.
`tiles.png` composites the two HDL tile layers using the captured palette in
Python. Those previews omit sprites and bitmap graphics and are not hardware
screenshots. Image storage used by the test tool is not part of the FPGA design.

```powershell
./scripts/d_drive.ps1 scripts/run_tile_tests.py
./scripts/d_drive.ps1 scripts/build_staged.py --synth-check tiles
```

The standalone fit uses a 48 MHz evaluation constraint and virtual I/O. It is
not a whole-core fit or a final board clock selection. Commit d48e724 passes
on 5CSEBA6U23I7 using 139 ALMs, 201 registers and zero M10K blocks. Worst setup
slack is +10.265 ns and worst hold slack is +0.108 ns; every reported corner
and pulse-width check passes, with no unconstrained paths. The lookup and
JTFRAME drawer hierarchy survive synthesis. See reference/tiles_synth.json.
Shared memory arbitration,
continuous raster scheduling, sprite priority/mixing, final palette logic and
dynamic CPU-write timing still need integration and verification.

## Packed tile-line storage

`rabbitpunch_tiles.vhd` now schedules both layers into two native 512-word line
banks. BG0 writes the low byte, FG the high byte, using the RAM's actual byte
enables. Both bytes in the configured X window are filled before a bank is
readable. No bulk clear or assigned power-up contents are required. Coordinates
outside the configured window are not accepted by its view port. Output has
valid and the bank's saved line-Y tag; the opposite valid bank can be read
concurrently with rendering.

The default standalone window is 0..511. Misaligned scrolling emits an extra
edge row, whose wrapping duplicate pixels have identical data. The logical video
controller selects MAME's visible X 8..295, avoiding work outside its viewport.
The window does not define physical sync/blanking or a PCB latch policy.
Reset invalidates both banks, drops partial output and drains accepted descriptor/
graphics transactions before a fresh line command is accepted.

`tile_line_tb.vhd` compares every X in both packed layers for all 216 visible Y
coordinates in six fixtures: 663552 packed words, 1327104 layer pixels. It also
checks input changes after acceptance, concurrent previous-bank reads, repeated
bank use and reset during RAM/ROM fetch. Native vendor RAM is used. Results:
reference/tile_line_checks.json. This is separate from CPU/shared-memory timing.
See VIDEO_PIPELINE.md for the complete mixed logical-line replay.
