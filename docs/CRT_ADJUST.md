# CRT Adjust evaluation

The optional CRT adapter remains disconnected from the production output.
Native analog output already uses the framework RGB/sync path. These tests do
not establish physical CRT operation.

The unchanged rmonic79 CRT Adjust copy is pinned from the Seta sibling core,
including Seta's signed-zero correction for negative horizontal position.
See rtl/video/crt_adjust/PROVENANCE.md and reference/vendor_manifest.json.
New glue and stimulus are VHDL, use unsigned ports and one system clock, and
translate the vendor's cryptic pins only inside rabbitpunch_crt_adjust.

Off is a direct RGB/sync/blanking/enable bypass, with no extra pipeline or
memory latency. On uses the donor's two 512-pixel line banks (1024 x 24 bits),
reading the completed row while writing the next. This optional path adds
one buffered row plus pixel/read-rate alignment; it is separate from the
native one-row-ahead game renderer. It adds no complete frame buffer. The
expected 24576 RAM bits and resource/timing cost still require a fit.

Horizontal size changes the read enable, not a generated clock. The fixed
/7 native cadence gives a period of 140 twentieths of a system clock. Each
signed five-bit size step adds five twentieths, using shifts/adds. Position
uses the 97-entry 0,+1..+48,-48..-1 encoding, with invalid indices clamped to
zero. Vertical shift retains the vendor's signed six-bit VSYNC offset.
A separate size-enable gate allows forced doubling/effects to turn off
horizontal stretching while retaining position controls.

The first strict active-image test caught a vertical-blank mismatch: the
unadapted donor suppressed the first visible row and selected an extra bottom
row for our raster. Native HSync follows the visible window, so each bank
switch completes the row whose current VBlank bit must accompany its pixels.
The wrapper holds that one-bit bank tag and carries it through the two
read-enable stages. It disables the donor's additional vertical RGB gate and
uses the aligned tag for output blanking. The imported file is unchanged.

Passing RTL checks:

- Every-clock native bypass across 256 unequal RGB/timing patterns.
- All 32 signed size read-enable densities and size-disable restoration.
- Full-width 288-visible/432-total image order at /7 enable, including the
  first/last of six visible rows in a twelve-row test raster.
- Normal, left/right eight-pixel position and wider/narrower two-step sizes;
  each checks all 1728 output pixels after warm-up.

Evidence: reference/crt_adjust_control_checks.json and
reference/crt_adjust_geometry_checks.json. These synthetic geometry tests
complement the game-renderer MAME comparisons; they are not MAME captures.

Still open: routed standalone fit, functional-netlist replay, vertical-shift
semantics and sync checks, full-height output, extreme-size clipping, setting
changes, main-OSD wiring and actual monitor behavior. No CRT Adjust option is
advertised by the production menu yet. Vertical-size ring buffering is not
included in this evaluation: it adds multiple rows and its cabinet mode expects
at least eight system clocks per native pixel, whereas this core uses seven.
