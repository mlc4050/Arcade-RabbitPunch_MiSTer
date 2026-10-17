# Continuous machine integration

`rabbitpunch_machine` connects the existing platform to the provisional continuous
scanout controller on one system clock. It is a production VHDL integration layer,
not yet the MiSTer framework top. The inherited demo remains connected in the RBF
project until the physical shell, PLL and DDR ownership mux are integrated.

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
  Fitted PLL counters/phase and physical SDRAM timing remain unverified.

Reports live in `docs/reference/`; private simulator logs/images and fit archives
live under `debug/`. Standalone PLL-model checks do not prove fitted clock counters,
external SDRAM phase or final MiSTer pin timing. Those remain implementation gates.

Generic/constant names now use the user's uppercase type/width prefixes. The
all-authored-source compile audit covers 173 VHDL files; it is compile coverage,
not execution of all benches. Raster/enable, CPU-phase, PLL-driven machine and
RAM startup checks are rerun after the rename. Both regenerated MRAs still match
all 0x210000 bytes against independent assembly and actual MAME-loaded regions.
The cached native-host netlist must be regenerated because its checked wrapper
source names changed; its source guard stays enabled.

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
