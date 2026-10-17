# Logical-line video pipeline

`rabbitpunch_rgb_video.vhd` connects actual tile and sprite rendering, native line
RAM, bitmap decoding, palette-index mixing and native palette RGB output. It has
no physical raster, PLL, MiSTer output wrapper or composed frame memory. It is
not a playable RBF. `rabbitpunch_video.vhd` remains the inner palette-index stage.

A line command latches bank, Y, scroll, flags, sprite count and priority. Tile
and sprite preparation run concurrently. Each has two native line banks; one
can be prepared while the previous line is read. Completion is reported only
after both renderers finish their writes. The visible tile window is logical
X 8..295 from MAME; sprite storage remains 512 entries. No raw line period or
original-board register/list latch point is chosen here. Descriptor RAM must
be supplied consistently by the caller during the scan.

Each accepted pixel reads both line banks and native bitmap RAM in parallel.
`rabbitpunch_bitmap_pixel.vhd` supplies X+4 wrapping, high-nibble-first word
decoding and the sampled bitmap palette bank. The aligned mixer combines BG0,
FG, sprite occupancy/foreground priority and bitmap into a ten-bit palette index.
`rabbitpunch_palette_pixel.vhd` then reads native palette RAM and expands RGB555
to RGB888 by replicating the upper three channel bits. Bit 15 is ignored.
There are no gamma, brightness or CRT shader adjustments.

Both bitmap and palette ports require fixed one-clock native RAM read latency;
a variable-latency transport cannot connect directly. All stages use the same
i_clk. The index is registered two clocks after acceptance, RGB four clocks
after acceptance. The bench observes RGB on its following sampling edge and
checks that five-clock sampled interval for every request. The pipeline accepts
one pixel per clock once the selected bank is valid, with no output backpressure.

Pixel Y must match both stored line tags. A mismatch produces o_pixel_error
instead of a valid RGB pixel; error and coordinate tags reach the same pipeline
slot. Global reset flushes derived pixel stages and invalidates line banks.
Pixel bitmap flags are sampled per request independently of line-command flags.
Physical bank switching, blanking/sync and CPU-time sampling remain integration work.

## Verification

`video_capture_tb.vhd` preloads the five actual shared board RAM banks through
the CPU transaction port, then keeps work-RAM writes running during rendering
and display. It uses native tile/sprite descriptor, bitmap, palette and line
RAM and the unchanged JTFRAME drawer. Only graphics ROMs remain static fixture
responders with independent 0/3/11-cycle delays. No software-decoded layer pixels
feed the bench. While one bank is rendered, the previous line is requested in
288-pixel bursts at one pixel per clock; every coordinate and latency is checked.

All six fixtures match every MAME screenshot pixel: 62208 per scene, 373248 total.
The runner writes HDL-generated 24-bit RGB directly to each comparison image;
Python no longer converts palette indices to RGB. Results, exact source hashes,
transcript hashes and matching RGB hashes are in reference/video_pipeline_checks.json.
Previews are under debug/baselines/video_*/video.png. The tests also check a wrong
line tag and reset with an external graphics ROM response pending and a pixel
in flight, then re-render and compare the first pixel. A directed live CPU
bitmap/palette write changes X=8/Y=0 to green on the next requested pixel.
The report records the competing work-RAM write count for each scene.

Independently, bitmap_pixel_tb.vhd checks all 131072 coordinates, palette banks,
wrap/nibble order, dense traffic, gaps and reset against native RAM. The palette
bench checks all 65536 RAM word values, all palette addresses, continuous traffic,
gaps, coordinate tags and fixed latency. It resets after accepting a pixel but
before palette output, checks that the pixel is dropped, and verifies two fresh
pixels. Reports: reference/bitmap_pixel_checks.json and palette_pixel_checks.json.
ModelSim Starter warns that the combined design exceeds its recommended statement
capacity; all checks complete within the wall-clock guard.

These tests include CPU-interface writes, but exclude executing CPU integration,
physical raster/PLL, shared SDRAM transport and dynamic state across frame
boundaries. Same-word CPU/video collisions are separately exercised in
board_memory_video_tb.vhd. Measured line cycles are not a physical deadline
proof; the renderer still uses independent synthetic graphics ROM transports.

## Isolated fitting

All fits use a 48 MHz evaluation constraint and virtual I/O. They do not establish
the physical raster deadline or shared-SDRAM bandwidth.

| Block | ALMs | Registers | M10K blocks | RAM bits | Report |
|---|---:|---:|---:|---:|---|
| Packed tile lines | 202 | 302 | 2 | 16384 | reference/tile_line_synth.json |
| Combined palette-index video | 506 | 864 | 4 | 32768 | reference/video_synth.json |
| Combined RGB video (historical isolated fit) | 546 | 977 | 4 | 32768 | reference/video_rgb_synth.json |
| Shared board RAM + RGB, including evaluation boundary registers | 817 | 1440 | 106 | 868352 | reference/board_video_synth.json |

The earlier isolated video fits predate the corrected foreign-port index mapping;
they are resource/timing history, not proof of current synthesized graphics
behavior. Corrected tile and sprite netlist tests are documented in
BOARD_VIDEO_MEMORY.md. The current shared-board fit uses a same-clock registered
evaluation wrapper, a documented half-period synthetic input contract and no
false/multicycle exceptions. It passes every reported corner (worst setup
+7.070 ns, hold +0.131 ns). Final external pin timing remains unproven.

All reported setup, hold and minimum-pulse checks pass, with no illegal clocks
or unconstrained paths. The reports identify each source commit and fitter seed.
The initial RGB seed-1 fit was rejected for -0.054 ns hold slack in the slow
1100 mV/-40 C corner, from virtual iu9_pixel_x[6] to the sprite line read-valid
register. Seed 2 passes every corner with unchanged RTL and constraints. No
pipeline or timing exception was added to hide the failure. The reporter reads
the seed from the project's QSF.

```powershell
./scripts/d_drive.ps1 scripts/run_tile_line_tests.py
./scripts/d_drive.ps1 scripts/run_bitmap_pixel_tests.py
./scripts/d_drive.ps1 scripts/run_palette_pixel_tests.py
./scripts/d_drive.ps1 scripts/run_video_tests.py
./scripts/d_drive.ps1 scripts/build_staged.py --synth-check tile_line
./scripts/d_drive.ps1 scripts/build_staged.py --synth-check video
./scripts/d_drive.ps1 scripts/build_staged.py --synth-check video_rgb
```
