# HDMI aspect and integer-size metadata evaluation

rabbitpunch_video_aspect is a VHDL adapter around unchanged
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
I/O delays. The standalone 80527a6 fit passes all reported corners and six coverage
categories: 260 ALMs, 412 registers, no RAM/DSP/PLL, minimum setup +6.732 ns
and hold +0.120 ns. The complete synthesized-netlist VHDL regression passes,
including distinct narrow/wide integer widths and HDMI resizing. See
reference/video_aspect_synth.json and reference/video_aspect_netlist_checks.json.

The adapter now connects VIDEO_ARX/ARY at the shell, measuring post-effect
CE_PIXEL/VGA_DE/VGA_VS and receiving the framework HDMI dimensions. H5 OSD
selectors use aspect bits 122:121 and scale bits 68:66; they are hidden under
direct video. Original 4:3 remains the default. The original standalone evaluation did not establish physical HDMI behavior.
Subsequent connected full-shell and host regressions are recorded below.
Rotation is now integrated and qualified separately in HDMI_ROTATION.md;
HDMI-only crop remains open.

The expanded native HPS menu now passes its own fitted host and complete protocol
netlist regression, including every new aspect/scale configuration character,
video flags, status transfers, controls, ROM-byte and high-score file transfers.
See reference/host_aspect_synth.json and reference/host_netlist_checks.json.
The connected non-debug full-shell fit 42c1be5 now passes all 144 reported
checks, scoped pin coverage and fitted clock topology. Minimum setup is
+0.525 ns, hold +0.078 ns, recovery +3.154 ns, removal +0.437 ns and pulse
width +1.122 ns. See reference/full_shell_aspect_release_checks.json.
This snapshot predates common flip. Physical HDMI behavior remains unverified.

## HDMI-only crop interface constraint

Source inspection of the unchanged framework confirms why shared DE cannot
provide an HDMI-only crop: sys/sys_top.v feeds VGA_scanlines with
din(de_emu ? {r_out, g_out, b_out} : 24'd0). The same resulting RGB reaches
the native analog OSD/output chain. Narrowing core VGA_DE would therefore
black those rows on analog output as well, even though vga_out itself
only delays its DE signal.

Oversized absolute VIDEO_ARX/ARY metadata is also insufficient: sys_top state 6
clamps videow/videoh to the HDMI dimensions before calculating centered output
limits. It does not select a smaller source rectangle.

This is a source/interface constraint, not a failed crop simulation. The current
adapter keeps CROP_SIZE/CROP_OFF zero. Preserve the one-row native analog path,
unchanged framework and default latency while resolving an independent HDMI
source-crop path. No new presentation framebuffer or sys modification has
been introduced for crop. The already-qualified optional rotation framebuffer
remains a separate feature.
