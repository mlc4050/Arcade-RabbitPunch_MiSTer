# Video RAM write timing

Four 1800-frame MAME 0.289 sweeps now separate sprite Y, code, flip, color and X,
both tilemaps, scroll registers and video flags. Attract counts after frame 600.
The scripted runs insert a coin at 600, press Start at 690 and count after 1500.
All use neutral brightness/contrast/gamma with INI loading and HLSL disabled.

`scripts/check_write_timing.py` verifies that the new coarse histograms are
identical to the earlier captures, that the two tilemap histograms partition
every tile RAM write, and that sprite fields do not count a descriptor word
twice. No observed sprite write fell outside the first 64 descriptor slots.
The six-bit sprite count still limits the rendered count to at most 63.

| Set / run | Sprite Y writes | Y writes in vblank | Sprite code writes | Code writes in vblank |
|---|---:|---:|---:|---:|
| rabiolep attract | 21247 | 2.51% | 12781 | 4.98% |
| rabiolep scripted | 21993 | 0.00% | 4904 | 0.00% |
| rpunch attract | 17164 | 0.49% | 4581 | 2.05% |
| rpunch scripted | 11666 | 0.06% | 2963 | 0.13% |

Position writes and graphics-field writes have different timing. These results
do not establish a single vblank snapshot point for every field. A buffer policy
must account for the measured writes and be checked against visible behavior;
no sprite snapshot or full-frame rendering buffer has been added here.

These are MAME's synthetic 224-line frames, with vblank beginning at 216, not a
measurement of the original PCB raster. The US scripted endpoint contains a
GAME OVER / CONTINUE PLAY? prompt. Scripted runs include selection, gameplay,
deaths and possibly attract; they do not prove 1800 uninterrupted active frames.
That coverage and original-board latch timing remain open.

Raw histograms live under reference/write_timing/. Their hashes and per-field
counts are in reference/write_timing_checks.json. These files contain counts,
not ROM data. Endpoint screenshots remain under debug/wtiming/snap_fields_play/.

Reproduce on D: through scripts/d_drive.ps1:

```text
scripts/write_timing.py rabiolep rpunch --fields --skip 600 --frames 1800 --tag _fields_attract
scripts/write_timing.py rabiolep rpunch --fields --coin 600 --skip 1500 --frames 1800 --tag _fields_play
scripts/check_write_timing.py
```
