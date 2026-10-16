# Logical-line video pipeline

`rabbitpunch_video.vhd` connects actual tile and sprite rendering, native line
RAM, bitmap decoding and palette-index mixing. It has no physical raster,
PLL, MiSTer output wrapper or composed frame memory. Its outputs are logical
pixel coordinates and the ten-bit palette address, one pixel per clock once
the selected bank is valid. It is not a playable RBF.

A line command latches bank, Y, scroll, flags, sprite count and priority. Tile
and sprite preparation run concurrently. Each has two native line banks; one
can be prepared while the previous line is read. The controller reports line
completion only after both renderers have finished their writes. The visible
tile window is logical X 8..295 from MAME; sprite storage remains 512 entries.
No raw line period or original-board register/list latch point is chosen here.
Descriptor RAM must be supplied consistently by the caller during the scan.

Each accepted pixel request reads both line banks and the native bitmap RAM
in parallel. `rabbitpunch_bitmap_pixel.vhd` supplies X+4 wrapping, high-nibble-first
word decoding and the sampled bitmap palette bank. Its RAM port requires fixed
one-clock native read latency; a variable-latency transport cannot be connected
directly. The pipeline aligns these inputs and mixes BG0, FG, sprite occupancy/
foreground priority and bitmap. Output is registered two clocks after acceptance.
The testbench observes this on its following sampling edge and checks that
three-clock sampled interval for every request, while accepting one per clock.

The requested pixel Y must match both stored line tags. An invalid tag generates
`o_pixel_error` rather than a valid mixed pixel. The caller must accept each
asserted output; there is no output backpressure. Pixel flags for bitmap color
are sampled per request independently of the line-command flags. Physical
bank switching, blanking/sync and CPU-time register sampling remain integration work.

## Verification

`video_capture_tb.vhd` loads actual native bitmap RAM through its write port,
and uses the real native tile/sprite line banks and the unchanged JTFRAME drawer.
Sprite/tile descriptors and graphics ROMs are static fixture responders with
independent 0/3/11-cycle delays. No software-generated layer pixels feed this
bench. While one bank is rendered, the previous line is requested in 288-pixel
bursts at one pixel per clock. Every tag and fixed streaming latency is checked.

All six fixtures match every MAME screenshot pixel: 62208 per scene, 373248 total.
The actual HDL output is the palette index; the current replay runner converts
it to RGB with the captured palette for comparison. Palette-RAM/RGB frontend
integration is a subsequent gate. `rabbitpunch_palette_pixel.vhd` is the new
frontend awaiting that integration test. Results and exact source/RGB hashes
are in reference/video_pipeline_checks.json. Previews are under
debug/baselines/video_*/video.png.

The bench also checks a deliberately wrong line tag and global reset with
descriptor transactions deliberately held pending while a pixel is in flight,
then re-renders and compares the first pixel. Independently,
`bitmap_pixel_tb.vhd` checks all 131072 bitmap coordinates, all palette banks,
wrap/nibble order, dense traffic, gaps and reset against native RAM; report:
reference/bitmap_pixel_checks.json. ModelSim Starter warns that the combined
design exceeds its recommended statement capacity, which slows replay; the
checks complete within the wall-clock guard.

These tests do not include CPU execution/writes, physical raster/PLL, a shared
SDRAM arbiter, palette-write collisions or dynamic state across frame boundaries.
The measured line cycles are not a physical deadline proof. Source RAM/ROM
accesses still need to be connected to the board memory system before hardware.

```powershell
./scripts/d_drive.ps1 scripts/run_tile_line_tests.py
./scripts/d_drive.ps1 scripts/run_bitmap_pixel_tests.py
./scripts/d_drive.ps1 scripts/run_video_tests.py
./scripts/d_drive.ps1 scripts/build_staged.py --synth-check tile_line
./scripts/d_drive.ps1 scripts/build_staged.py --synth-check video
```
