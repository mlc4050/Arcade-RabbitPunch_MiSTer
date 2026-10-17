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
but not yet connected to the production platform. Enable tests check 175065
rational-cadence/reset conditions; raster tests cover two complete default frames
(221184 beam pixels), a small odd-sized positive-sync case, sparse enables,
coordinate offsets and reset while stopped. See reference/raster_checks.json.
The new isolated raster implementation check is next. No playable RBF exists.
