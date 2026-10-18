# HDMI aspect and integer-size metadata evaluation

rabbitpunch_video_aspect is an isolated, unconnected VHDL adapter around unchanged
sys/video_freak.sv and math.sv. It selects original 4:3, full screen and two
framework custom aspect slots, and the four standard integer-scaling modes.
Direct video selects original 4:3 and disables integer scaling. Reserved scale
values select normal sizing. No RGB, data-enable or sync stream passes through
this adapter; it adds no pixel storage or render delay.

Normal/custom ratio metadata bypasses the framework arithmetic and is valid
immediately. Integer sizing waits for two observed vertical-sync edges so the
framework has geometry to measure. Those are configuration-initialized counters
on the single system clock, unrelated to game reset or pause. An initial smoke
exposed undefined framework startup arithmetic before its first frame; the ratio
bypass makes this explicit rather than changing imported HDL.

The RTL smoke checks startup with integer mode already requested. The complete
VHDL bench uses a deliberately non-square 32x20 scene to distinguish integer
choices at 1920x1050: vertical target height 1040, ideal width 1386, narrow width
1376 and wide width 1408. It also covers original/full/custom selectors, HDMI
resolution changes, direct-video override and reserved scale settings. Full
functional validation will use a Quartus-generated netlist, including FPGA
configuration values; the RTL smoke alone is not the integer-mode proof.

The staged standalone project times all paths at 48 MHz with explicit virtual
I/O delays. Synthesis, routed timing and the complete netlist regression are
pending. The current shell remains at the preceding scanline-options revision;
this adapter is not in files.qip or RabbitPunch.sv yet. Crop and rotation are
separate work, and are not advertised by this evaluation.
