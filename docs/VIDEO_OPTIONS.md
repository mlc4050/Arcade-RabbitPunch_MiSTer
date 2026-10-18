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
bench at the actual /7 enable ratio and provisional 432x256 raster. Detailed
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
