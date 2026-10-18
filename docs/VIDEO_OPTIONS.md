# Optional video output path

The VHDL rabbitpunch_video_options adapter is currently an isolated evaluation;
it is not yet connected to RabbitPunch.sv. Native RGB, data enable and pixel
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
and minimum hold is +0.125 ns. This virtual-I/O fit is not full-shell timing.
See reference/video_options_synth.json. Native bypass, forced doubling and HQ2x
compact tests have passed; the remaining effect/direct modes and separate
full-width control are running before shell integration.
