# Optional video output path

The VHDL rabbitpunch_video_options adapter now connects the native machine to
RabbitPunch.sv output ports; a new full-shell fit is pending. Native RGB, data enable and pixel
enable pass through without storage. Active-low native sync is normalized to
active-high pulses expected by the MiSTer mixer. Direct video overrides all
optional effects and forced doubling. Reserved effect values disable the effect.

Forced doubling, HQ2x and the three CRT scanline levels reuse unchanged
sys/video_mixer.sv, scandoubler.v, hq2x.sv and video_freezer.sv. Freeze is explicitly
inactive. The wrapper has one clock and clock enables. These optional modes add
the framework's line-buffer latency; they do not change the game's per-row
renderer or introduce a full-frame render buffer. Gamma is disabled in this first
adapter and is not advertised as supported.

The framework line RAM capacity is two 292x24 input banks and a 584x96 output
bank: 70080 bits total. The 256x6 HQ rule table is combinational in this fit and
is not counted as block memory. Geometry and colour verification use a VHDL
bench at the /7 enable ratio. The routine seven-mode regression uses 32 visible/
48 total pixels and one visible/four total vertical lines, after two startup
frames. --full-width restores 288/432 horizontal geometry; --full-raster restores
216/256 vertical geometry as well. This keeps slow Starter Edition netlist
simulation bounded; actual scene and raster proofs are separate.
Detailed
HQ2x edge-filter accuracy and physical video output are outside that test.

Quartus 17's bundled ModelSim cannot compile the unchanged framework sources
as written (forward declarations and a procedural assignment to a net output).
Tests therefore use Quartus's exported functional netlist and the unchanged
vendor simulation libraries. No vendor source is edited for this workaround.
The standalone staged fit checks VHDL synthesizability and routed timing;
functional simulation has no SDF back-annotation.

Run build_staged.py --synth-check video_options from a clean committed checkout,
then run_video_options_tests.py through scripts/d_drive.ps1. Both operations
retain all generated files on D and use the shared no-JTAG guard. Complete
seven-mode results, once passed, go to reference/video_options_checks.json;
partial diagnostics remain private under debug/.

The first standalone compilation (3cccb99) passes routed timing but its wrapper
rejects an overestimated RAM budget of 71616 bits. The actual line RAM geometry
is 70080 bits; the rule table does not contribute block-memory bits. That gate
is corrected explicitly and a clean snapshot is refitted. The first full-height
native netlist run hits its 180-second wall budget without an assertion failure;
no pass is claimed for that interrupted run.

The corrected standalone bf511c5 fit passes at 48 MHz with 767 ALMs, 1373
registers, 70080 RAM bits in 14 M10Ks, zero DSPs and no PLL. All reported corner
checks and all six timing-coverage categories pass. Minimum setup is +5.816 ns
and minimum hold is +0.111 ns. This virtual-I/O fit is not full-shell timing.
See reference/video_options_synth.json. All seven compact tests pass: native bypass, forced doubling, HQ2x, three
scanline strengths, and direct-video override. The separate full-width forced-scandoubler control also passes: 288 visible
pixels on a 432-pixel raster produce exactly 576 visible output pixels in two
rows, with exact RGB values after warm-up. It uses one visible/four total
vertical lines; full-height and physical output remain unverified. See
reference/video_options_full_width_checks.json. The connected shell now exposes the Scandoubler Fx menu at status
bits 46:44, hides it under direct video, and honors forced doubling when direct
video is off. Native renderer telemetry stays before this presentation path.

The expanded native HPS configuration passes its separate host fit and complete
host functional-netlist regression. Every configuration character, forced/direct
video flags, 128-bit status ordering, keyboard/joysticks, byte download and native
high-score upload/request behavior pass with the new menu string. See
reference/host_video_options_synth.json and reference/host_netlist_checks.json.
The physical ARM/menu interaction is still part of hardware bring-up.

The connected non-debug full fit 6397a94 passes all 144 reported timing checks
and fitted clock/coverage gates: minimum setup +0.323 ns and hold +0.100 ns,
14242 ALMs, 23916 registers, 180 M10Ks, 34 DSPs and three PLLs. Its qualified
archive contains only the selected revision's artifacts; see
reference/full_shell_video_options_release_checks.json. This is a timed
prototype, not a hardware-verified release.

The independent instrumented default-seed fit 1b3e33f is rejected: a slow -40 C
HDMI-domain setup path fails by 0.204 ns. All game-clock setup checks pass
(minimum +1.035 ns), as does SDRAM output setup (+0.767 ns). No timing exception
was added. A second placement seed will be checked before touching unchanged
framework logic. The failed bitstream remains archived and is not accepted.

The clean instrumented placement retry f64d68b at seed 2 passes all 164
reported timing checks and the same scoped clock/pin gates. Minimum setup is
+0.373 ns, hold +0.067 ns, recovery +3.393 ns, removal +0.444 ns and minimum
pulse width +1.122 ns. No constraints or framework logic were changed for
this retry. See reference/full_shell_video_options_debug_seed2_checks.json.
This snapshot includes scanline/HQ2x options, but does not connect the later
HDMI aspect adapter. Physical output remains unverified.

The combined CRT/HQ2x path now also passes an asymmetric patterned comparison:
64x4 native pixels produce a complete 128x8 output, all 1024 RGB pixels exactly
matching an independent native qualified-framework run with black blanking.
The pattern includes diagonals, four-pixel bars, alternating rows and distinct
colour lanes. Both fixtures use /7 input enables; the enabled CRT adapter has
H-position +8 and the production size gate disabled in doubled mode. This is
a compact integration proof against the framework, not MAME's unfiltered frame
or a full native raster/physical CRT measurement. See reference/crt_hq_pattern_checks.json.
