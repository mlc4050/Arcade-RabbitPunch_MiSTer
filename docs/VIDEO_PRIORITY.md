# Sprite occupancy and layer mixing

`rabbitpunch_sprite_priority.vhd` computes the update for one sprite-line entry.
It accepts an opaque candidate when the entry is empty or the candidate has a
higher descriptor index. Equal/lower indices and transparent pen 15 leave all
stored metadata untouched. This makes the result independent of arrival order
while reproducing MAME's descending-index drawing and priority=31 occupancy.
The index, palette and behind-foreground tag must be stored with each entry.
An opaque winner remains occupied even when a foreground tile hides it.

The block is combinational, with no memory, reset or buffering policy. Its caller
must provide the previous entry and commit the returned metadata when `o_write`
is asserted. A future line RAM pipeline must forward overlapping in-flight
updates and clear occupancy for each new line. Those memory hazards are not
tested by a standalone combinational update.

`rabbitpunch_pixel_mixer.vhd` takes layer-local eight-bit palette indices for the
same output coordinate and emits the ten-bit final palette address. BG0 is
always opaque, including pen 15. FG replaces BG0 unless its pen is 15. An occupied,
opaque sprite replaces the selected tile unless its behind-foreground tag is set
and FG is opaque. Nontransparent bitmap pixels replace everything. The selected
layer supplies palette base 0, 256, 768 or 512 respectively. The mixer performs
no RGB conversion and adds no clock or frame of storage.

## Verification

`priority_tb.vhd` checks 262144 sprite insertion cases: every old/new descriptor
index pair, all sixteen new pens, occupied/empty and valid/invalid candidates,
including equal indices. Stored and selected metadata are checked. Another
32768 mixer cases cover all palette values in each layer and combinations of
transparency, sprite occupancy and foreground priority.

`run_priority_tests.py` also builds per-pixel inputs from the six MAME fixtures.
The VHDL capture bench folds all overlapping sprite candidates through the actual
arbitration module, then feeds its winner into the actual mixer. Half the pixel
positions reverse candidate arrival order. Transparent candidates remain present,
and a fixture with zero on-screen candidates tests the empty-list path. All
62208 RGB pixels per scene, 373248 total, match MAME's reference screenshots.
Results and RGB hashes are in reference/priority_checks.json.

These captures use software-decoded tile, bitmap and sprite pens as stimulus.
They do not connect the row engines or actual line RAM to the mixer, and do not
prove physical raster, shared-memory latency, CPU-write behavior or a playable
RBF. Palette-to-RGB conversion and the preview file are Python test operations.
The actual VHDL output is the palette address. Previews live under
debug/baselines/mixer_*/mixed.png.

```powershell
./scripts/d_drive.ps1 scripts/run_priority_tests.py
./scripts/d_drive.ps1 scripts/build_staged.py --synth-check priority
```

The synthesis-only priority_check harness places output registers after the two
combinational modules to evaluate their timing at 48 MHz with virtual I/O. It
does not prescribe the final video pipeline's register placement.
