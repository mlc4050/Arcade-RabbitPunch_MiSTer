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

The harness passes Quartus 17.0.2 fitting for commit e0ed3d6 on 5CSEBA6U23I7:
69 ALMs, 27 output registers and zero block RAM/DSP. Worst setup slack is
+7.155 ns and worst hold slack is +0.129 ns. All corners and pulse-width
checks pass, with zero illegal clocks/unconstrained paths. See
reference/priority_synth.json. The registers belong to the evaluation harness.

## Native sprite line RAM

`rabbitpunch_sprite_line.vhd` now stores two 512-entry lines using the actual
`rabbitpunch_ram16`/`altera_mf.altsyncram` wrapper, not a simulation substitute.
Each 16-bit word contains occupancy, foreground tag, descriptor index and palette.
The caller starts a chosen bank with a line-Y tag, waits for its 512-cycle clear,
then streams candidates at up to one per clock. A finish strobe stops new input
and drains the final update before the bank becomes readable. Line completion
does not itself swap banks or choose a raster/snapshot policy.

The active render bank's read port fetches the old entry; its write port commits
the preceding candidate. Consecutive candidates for the same X use the complete
just-written entry through a bypass and suppress the conflicting physical read.
This avoids depending on undefined mixed-port read-during-write values. A losing
or transparent candidate cannot erase an occupied entry. The inactive valid bank
can be read concurrently, one pixel per clock, with valid and the saved line-Y tag.
Read requests to an active or uninitialized bank are rejected through `o_view_ready`.

Reset invalidates both banks and drops in-flight derived updates; it does not
clear RAM in one cycle. Each new line explicitly clears all 512 entries before
accepting candidates. `i_line_finish` must follow the last accepted candidate;
asserting it stops candidate acceptance on that edge. There is no frame buffer.

`sprite_line_tb.vhd` checks 33844 candidates and 37954 concurrent display reads
against an independent word-array scoreboard, using the native vendor model.
It checks every X, transparent pixels, ascending/descending index collisions,
continuous same-X updates, deterministic random traffic, both banks reused,
512-cycle clears, line tags, reset during clear and reset during an update.
The final run has no simulation errors or warnings. Results are in
reference/sprite_line_checks.json. This is a directed RAM/pipeline test.

Connected scan/draw tests now also write into the actual native line banks and
compare every stored word, including unused/transparent positions, for both
synthetic lists and all six captures. Results: reference/sprite_scan_line_checks.json.
This checks 2764800 entries across eight cases. The crowded case takes 3291 clocks
including line clearing and update draining, or 68.56 microseconds at the
evaluation clock. This excludes shared SDRAM contention and is not a physical
deadline proof. Continuous opposite-bank display and global-controller reset
receive further tests in the complete renderer bench.

The standalone native line-RAM fit for cf6032f passes Quartus 17.0.2 at the
48 MHz evaluation clock: 139 ALMs, 106 registers and exactly two M10K blocks
(16384 data bits), zero DSP. Worst setup slack is +8.957 ns and worst hold
is +0.167 ns. All reported corners and pulse-width checks pass, with no
illegal clocks or unconstrained timing paths. See reference/sprite_line_synth.json.

```powershell
./scripts/d_drive.ps1 scripts/run_sprite_line_tests.py
./scripts/d_drive.ps1 scripts/build_staged.py --synth-check sprite_line
```
