# CRT Adjust

The optional CRT adapter is connected before the existing output-effects wrapper.
The main OSD exposes Adjust, horizontal size/position and vertical sync shift.
Adjust defaults Off; position/shift are hidden until enabled, and size is also
hidden and disabled during forced doubling or output effects. Direct video
uses the native effect-free path, so size remains available.
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
native one-row-ahead game renderer. It adds no complete frame buffer. The qualified d9dfc8a standalone fit uses 24705 bits in four M10Ks:
1024x24 RGB and 129x1 inferred VSYNC history, both checked exactly. It uses
199 ALMs, 288 registers, zero DSPs and no PLL at a conservative 48 MHz.
All reported corners and all six timing-coverage categories pass, with minimum
setup +6.297 ns and hold +0.145 ns. The original 24576-bit estimate was
rejected before the sync RAM was audited; that failure is preserved in
reference/crt_adjust_budget_rejected.json. No donor change was made.
See reference/crt_adjust_synth.json.

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
  first/last of six visible rows in a twelve-row horizontal-control fixture and the actual 256-line frame
  geometry for vertical-shift cases.
- Normal, left/right eight-pixel position and wider/narrower two-step sizes;
  each checks all 1728 output pixels after warm-up. Positive/negative one-line
  vertical shifts also pass, with exact 3024-clock HSync and 36288-clock
  frame periods, bounded read-pixel sync-width quantization and exact
  one-line shifts in VSYNC phase. The production-period control uses
  774144 system clocks per frame.

Evidence: reference/crt_adjust_control_checks.json and
reference/crt_adjust_geometry_checks.json. These synthetic geometry tests
complement the game-renderer MAME comparisons; they are not MAME captures.

Full-height RTL and synthesized-netlist controls now check all 62208 pixels across 216 visible
rows in a 256-line frame with no missing first or last row. Evidence:
reference/crt_adjust_geometry_full_height_checks.json and
reference/crt_adjust_geometry_netlist_full_height_checks.json.

The synthesized bypass/all-32-rate control also passes. Five compact netlist
picture cases pass, and the longer production-256-line control plus positive/
negative one-line vertical shifts now pass, including exact phase comparisons.
The initial 300-second wall timeout was a performance limit; completed compact
cases and the uncompleted transcript were preserved, and only unfinished cases
were retried with progress logging and a larger budget. See
reference/crt_adjust_netlist_checks.json,
reference/crt_adjust_geometry_netlist_compact_checks.json and
reference/crt_adjust_geometry_netlist_selected_checks.json.

The exact provisional native raster also passes the synthesized scoreboard:
432x256 total, 288x216 visible, HSync 352..392 and VSync 232..240. All 62208
source pixels and sync periods pass; see
reference/crt_adjust_native_raster_netlist_checks.json.

The actual renderer, shared SDRAM and production PLL also pass through the
enabled zero-adjustment path: all 62208 Rabbit Punch attract pixels match
the raw MAME image, with no underflow and maximum 2484/3024 cycles per row.
This is a captured static scene with synthetic competing CPU traffic, not
executing-CPU gameplay. See
reference/scanout_pll_5357ps_crt_rpunch_attract_checks.json.

The production controls use status bit 94 (enable), 99:95 (signed horizontal
size), 106:100 (the 97-entry horizontal position index) and 112:107 (signed
vertical sync shift). Menu masks H6 and H7 control visibility. All encoded
fields default to zero; no offset is implied by an untouched configuration.

The expanded production menu also passes a fresh standalone host fit and
functional synthesized HPS protocol test, including every configuration
character, status and file transfers. See reference/host_crt_synth.json and
reference/host_netlist_checks.json.

Live size/position changes in vertical blank recover exact source pixels and
sync periods after two bounded fixture frames. Disabling the optional path
also restores exact native bypass on every tested system clock before reenable.
See reference/crt_live_controls_checks.json. This checks settled recovery; it
does not promise a glitch-free picture while changing a setting.

Still open: the newly connected full-shell implementation checks,
extreme-size clipping, live vertical-shift/combined-output transitions and
actual monitor behavior. Vertical-size ring buffering is omitted: it adds
multiple rows and its cabinet mode expects at least eight system clocks per
native pixel, whereas this core uses seven. V-Shift changes sync phase,
not vertical picture size.
