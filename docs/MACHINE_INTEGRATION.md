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
  snapshot comparison is in progress. It uses direct ROM chip-model preload and
  synthetic competing CPU traffic; it does not execute a game or prove hardware.
- The combined machine implementation target is prepared, not yet accepted.

Reports live in `docs/reference/`; private simulator logs/images and fit archives
live under `debug/`. Standalone PLL-model checks do not prove fitted clock counters,
external SDRAM phase or final MiSTer pin timing. Those remain implementation gates.
