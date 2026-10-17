# Provisional raster proposal — approval pending

The user approved proceeding provisionally and accepts MAME accuracy when no
better evidence is available. Continue implementation without asking again.
This plan does not claim verified original-board timing. The approved ROADMAP.md requires unresolved
clock/raster decisions to close before dependent RTL. The alternative is to keep
that gate until original-board measurements or a documented C7-01 timing model
are available.

## Evidence and assumptions

MAME 0.289 supplies a 60 Hz software screen, not raw sync totals. Its GGA device
stores registers but does not decode a raster. The original manual's video-board
sheet shows a 13.333 MHz oscillator and divide-by-two path feeding the GGA.
That does not by itself prove the output dot clock or the timing register map.

Both real-ROM startup traces program matching GGA fields. Treating registers
0..3 as four-pixel counts minus one, and 8..11 as two-line counts minus one,
produces the candidate below. The active dimensions agree with the 288x216
MAME-visible image; this supports investigating the pattern but does not prove
its sync or total interpretation. Trace hashes and arithmetic are recorded in
reference/raster_candidate.json. Unwritten registers remain marked unknown.

| Candidate | Active end | Sync start | Sync end | Total |
|---|---:|---:|---:|---:|
| Horizontal, `(register + 1) * 4` | 288 | 352 | 392 | 432 |
| Vertical, `(register + 1) * 2` | 216 | 232 | 240 | 256 |

For the provisional build only, interpret the oscillator label as nominal
13 1/3 MHz and use half for pixels. A 46 2/3 MHz system clock with pixel enable
once every seven clocks gives a steady 6 2/3 MHz dot cadence, 15.432 kHz lines
and 60.2816 Hz frames. This differs from MAME's assumed 60 Hz. Actual oscillator
accuracy, sync polarity and output phase remain to be verified. The PLL must be
generated and checked by Quartus; the arithmetic is not a validated PLL setup.

Clock enables on the same system clock preserve the MAME CPU/audio rates:
68000 alternating phase pulses at 12/35 of system clocks (16 MHz pulses, 8 MHz
full cycles), Z80/YM at 3/35 (4 MHz), YM half-rate at 3/70 (2 MHz), and ADPCM at
12/875 (640 kHz). Keep all board processes on that single system clock.
The external SDRAM clock/phase and I/O constraints need their own bring-up proof.

A candidate line is 3024 system clocks. The largest previously measured cached
graphics line took 2557 clocks, leaving 467 clocks in that test. This is not
proof that every live scene with executing CPUs/sound fits. Before hardware,
run continuous scanout with late-line/underflow detection and concurrent clients.
Render one line ahead into the existing two banks; add no full-frame buffer.
Map visible x=0..287 to the renderer's MAME coordinates x=8..295, y=0..215.

## Authorized implementation

Implement explicit, adjustable raster parameters and clock enables, then verify
counter wraps, sync/blanking widths, line-bank ownership, output alignment,
interrupt events and reset using VHDL tests. Treat the GGA interpretation as a
named approximation in HACKS.md. Generate the PLL, connect the existing logical
platform to the unchanged MiSTer shell and run the complete implementation and
external-memory timing checks. Add debug probes and retain underflow counters.
Only then prepare an RBF for hardware testing; launching it still requires the
user's direction. Physical measurements can replace the provisional parameters
without changing the render/memory architecture.

The standalone VHDL clock-enable generator and adjustable raster are implemented
and connected to the production platform through rabbitpunch_machine. The
MiSTer framework top remains the inherited demo until shell integration lands. Enable tests check 175065
rational-cadence/reset conditions; raster tests cover two complete default frames
(221184 beam pixels), a small odd-sized positive-sync case, sparse enables,
coordinate offsets and reset while stopped. See reference/raster_checks.json.
The isolated raster/enable implementation at d23887d passes all 48 MHz timing
and coverage gates: 86 ALMs, 114 registers, zero RAM/DSP, worst setup +11.514 ns
and hold +0.147 ns. See reference/raster_synth.json; full reports are retained
under debug/fit_archive/raster_d23887d/. No playable RBF exists.

The descriptive VHDL PLL wrapper now requests a 50 MHz input and two
46.666667 MHz outputs. System logic uses output 0; output 1 provisionally shifts
by 10714 ps (half a period) for the external SDRAM clock only. This is an initial
controller bring-up choice, adjustable through SDRAM_PHASE_SHIFT. The installed
vendor PLL model passes lock/relock, 448 individual period/phase observations and
two 224-period average-frequency checks. Its documented 10 ps synchronization
drift is allowed per edge; the 4.8 us average span must remain within 20 ps.
This model result does not establish the fitted PLL counters or physical SDRAM
sampling window. Those checks belong to clock-tree/full-shell implementation.

A separate three-register reset-release wrapper asserts asynchronously if the
PLL loses lock and releases on three system-clock edges. Its test covers reset
assertion/release and loss/recovery of the clock. It is cold initialization;
game reset and pause do not reset the ROM transport/PLL. See
reference/pll_checks.json. Next: scanline bank ownership and production timing
connections, then the complete clock/SDRAM implementation.


The standalone line scheduler now passes delayed/backpressured render tests:
two four-line frames alternate banks without overwriting the active bank,
startup stays blank until armed, late rows remain invalid until a later handoff,
same-edge completion is eligible, and initialization flushes queued/active work.
Only ownership/tags are added; tile/sprite pixels remain in the existing two
banks. See reference/scanline_scheduler_checks.json. Continuous real-renderer
scanout and CPU/audio contention tests follow production wiring.

The continuous scanout controller passes 124416 synthetic RGB checks, including
an intentionally late row and readiness loss/recovery without stopping sync.
The connected machine passes downloaded 68000 diagnostic programs with external
fractional phases and continuous pixel cadence through loading, pause, reset,
replacement and partial-image recovery. That short test ends before the first
vertical interrupt/render window; it does not prove a complete executing frame.
A separate static-MAME capture test drives the real graphics/ROM path at continuous
raster cadence; Rabbit Punch attract passes all 62208 pixels with zero differences
and no underflow. Maximum render cost is 2576 of 3024 system clocks per line.
The combined machine fit passes all 48 MHz timing/coverage gates (+2.077 ns setup,
+0.100 ns hold); the clocked wrapper also passes vendor-model CPU/load tests. See MACHINE_INTEGRATION.md.
