# Continuous machine integration

`rabbitpunch_machine` connects the existing platform to the provisional continuous
scanout controller on one system clock. It is a production VHDL integration layer,
now connected to the MiSTer boundary through the PLL/reset wrapper. The full-shell
implementation and external pin timing remain unverified.

The scanout controller supplies the fractional main CPU phase, Z80/YM/ADPCM enables,
vblank/half-frame interrupts, one-row-ahead render requests and tagged pixel reads.
The platform's exact game-ready output controls rendering ownership and blanking.
Loading or gameplay reset clears row ownership and diagnostics without restarting
the beam, sync or shared enable generator. Tile/sprite banks remain the existing
two line banks; no frame buffer is added. PLL initialization is separate.

The optional external main phase mode propagates through platform/system/board.
It defaults off for existing independent diagnostics. The machine explicitly
selects it; the CPU alternates phases only on enabled edges and preserves pause
and outstanding-reply drain behavior.

Verification so far:

- `run_maincpu_phase_tests.py`: real fx68k, both phase modes, byte/word access,
  delayed replies, pause, reset replay and interrupt/autovector/RTE checks pass.
- `run_scanout_tests.py`: 124416 synthetic RGB checks, line-bank tags, steady /7
  cadence, deliberate late-row failure and readiness recovery with sync running.
- `run_machine_tests.py`: real 68000/native SDRAM, DDR/direct-byte image loads,
  controls/DIP readback, pause, soft reset, image replacement and partial-image
  recovery pass while horizontal timing continues. This short diagnostic completes
  before vertical interrupts/rendering; the tiny image omits sound ROM, so audio
  unknown-state warnings are expected and audio function is not scored.
- Existing board and platform regressions pass after phase-port propagation.
- `run_scanout_capture_tests.py`: first continuous real-graphics/shared-SDRAM MAME
  snapshot comparison passes for Rabbit Punch attract: all 62208 RGB pixels match MAME,
  zero underflow, worst render cost 2576 of 3024 clocks. It uses direct ROM chip-model preload and
  synthetic competing CPU traffic; it does not execute a game or prove hardware.
- Combined machine implementation ccb6fa8 passes at the conservative 48 MHz
  evaluation constraint: 929387 RAM bits, worst setup +2.077 ns / hold +0.100 ns,
  all timing corners and six coverage categories pass. Reports are retained under
  debug/fit_archive/machine_ccb6fa8/.
- The clocked-machine wrapper passes the same downloaded-program diagnostics
  using the installed vendor PLL model and production reset-release boundary.
  Fitted PLL counters/phase now pass the isolated implementation check below;
  physical PCB timing remains unverified.

Reports live in `docs/reference/`; private simulator logs/images and fit archives
live under `debug/`. Standalone PLL-model checks do not prove fitted clock counters,
external SDRAM phase or final MiSTer pin timing. Those remain implementation gates.

Generic/constant names now use the user's uppercase type/width prefixes. The
all-authored-source compile audit covers 173 VHDL files; it is compile coverage,
not execution of all benches. Raster/enable, CPU-phase, PLL-driven machine and
RAM startup checks are rerun after the rename. Both regenerated MRAs still match
all 0x210000 bytes against independent assembly and actual MAME-loaded regions.
The renamed native-host netlist was regenerated and verified; its source guard
stays enabled.

The renamed native-host boundary now passes a fresh Quartus fit/netlist test,
raw-command platform loading/control tests and both profiles' native score-file
round trips. Archived host fit: debug/fit_archive/host_d929f0a/. The clocked machine
also passes after synchronizing release of the external framework gameplay reset
through a separate three-register release chain; that reset never restarts the PLL.

The existing RabbitPunch.sv is now only MiSTer macro-port boundary wiring to the
VHDL host and clocked machine. files.qip selects the production sources. Physical
blanking drives VGA_DE independently of game readiness; colors remain black until
rows are armed. Signed mono PCM feeds both channels. The DDR interface currently
has one client, the load-time copier; rotation is not connected. Full-shell fit,
SDRAM pin timing and hardware output remain pending.

The first PLL/chip-clock SDRAM test exposed a one-word-late read burst. Existing
same-edge command-model tests did not cover that phase. The production clocked
machine now selects GINT_SDRAM_READ_CAPTURE_ADJUST=1; logical same-phase users
retain zero. The VHDL adapter keeps rd_adj at zero during initialization, since
the unchanged donor uses it in its state-wrap condition as well as read capture.
At runtime one selects the earlier read window. An ungated nonzero adjustment
prevents initialization from finishing; explicit negative controls detect both
that stall and the original burst shift.

The corrected PLL/chip-clock test passes 372 word checks, 63 transactions, both
chips/three clients, byte masks, refresh and reinitialization preserving data.
The clocked CPU/download machine also passes with the chip actually clocked from
the shifted PLL output. Continuous MAME graphics with that same clock relationship
passes for Rabbit Punch attract: 62208 exact pixels, no underflow, worst row
2484 of 3024 clocks. Additional gameplay cases are running. These are command-model
proofs, not PCB setup/hold measurements.

Clock-tree fit 02d3b39 was rejected for a 3.3 V clock output mixed with the
standalone project's default 2.5 V SDRAM-bank I/O. Its target commit was reverted
(c829698); reports are archived in debug/fit_archive/clocked_machine_02d3b39_rejected/.
The corrected evaluation target assigns 3.3 V consistently. The full MiSTer shell
already inherits explicit 3.3 V SDRAM assignments from the unchanged sys files.

The corrected 3.3 V fit b2d5328 met timing but failed the six-category coverage
gate because the exported SDRAM clock pin was not declared as a generated clock.
That target was reverted in bcf5e36 and archived under
`debug/fit_archive/clocked_machine_b2d5328_unconstrained/`. Private-database analysis
of the explicit exported-clock constraint reports zero in all six categories.
The corrected implementation 2374ddc passes every timing gate. Clock inspection
includes the internal PLL VCO and exported clock as distinct hard-block/pin roles;
TimeQuest's register counts include those endpoints, so the validator checks their
exact expected counts instead of treating them as extra functional logic domains.
The fitted integer ratios are 42/5 for the VCO and /9 for each output, giving the
nominal 46.6666667 MHz; the displayed timing periods are truncated to picoseconds.

The accepted clocked-machine fit at 2374ddc uses 6703 ALMs, 8373 registers,
124 M10K blocks and one PLL. Worst setup is +2.141 ns; worst hold is +0.091 ns.
All reported timing corners and six coverage categories pass. The fitted VCO
and output dividers, half-period SDRAM phase and exported clock are checked.
This isolated target has hypothetical external I/O budgets, not final board
pin timing. Evidence: reference/clocked_machine_synth.json and
debug/fit_archive/clocked_machine_2374ddc/.

Both real-ROM CPUs also pass short 32-main/8-sound ordered MAME startup comparisons
using the vendor PLL, shifted SDRAM chip clock, early runtime read window and
production fractional enables. Both games also pass 2000 main and 256 sound ordered writes
(reference/system_boot_pll_phase_boot_checks.json). Raster events stay
idle in this CPU-specific bench, so it does not prove interactive gameplay.

Full-shell fit 660a45a is rejected: 13551 ALMs, 166 M10Ks, positive hold, but
-4.338 ns setup on all sixteen SDRAM DQ inputs and inherited framework pin
coverage gaps. The worst internal game setup path is +4.823 ns at 100 C slow.
DQ inputs are already packed in I/O cells; the forwarded clock's insertion
delay consumes the initial half-period read window. The next physical-shell
candidate uses 5357 ps (quarter-period), with runtime read adjustment one.
Low-level SDRAM and clocked-machine diagnostics are rerun for that phase.
Historical half-period graphics proofs retain their exact source/phase scope.
See SDRAM_PIN_TIMING.md for the bounded, source-locked treatment of inherited
framework peripheral I/O and the distinction from fully timed SDRAM/game paths.
