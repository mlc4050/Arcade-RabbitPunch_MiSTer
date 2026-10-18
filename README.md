# Rabbit Punch / Rabio Lepus for MiSTer

Early development for Video System's 1987 arcade hardware, using MAME's rpunch.cpp
as the behavioral reference. Target sets: rabiolep (Japan), rpunch (US).

Status: the VHDL CPU, memory, video, audio, ROM-loading, controls and high-score
services are connected to the MiSTer boundary. The non-debug full build passes the documented prototype timing
gates; the latest debug placement is being rechecked; no hardware-verified playable RBF or release exists.

Verification includes:

- Both games match 10,000 main and 4,096 sound startup writes in the documented
  logical tests. With the production PLL/fractional enables and shifted SDRAM
  chip-clock model, both pass 2,000 main and 256 sound ordered startup writes.
- Six static graphics scenes match MAME through shared SDRAM and concurrent
  synthetic CPU traffic. Continuous PLL-driven scanout currently passes Rabbit
  Punch attract and Rabio Lepus gameplay, with all 62,208 pixels matching each
  and no underflow. At the production 5.357 ns phase, Rabbit Punch attract and
  Rabio Lepus gameplay at frame 1000 both match exactly.
- The current non-debug MiSTer fit passes all reported corners at a fitted
  46.667 MHz game clock and 5.357 ns SDRAM phase, with minimum setup/hold
  margins +0.323/+0.100 ns. The prior native-output debug baseline also passes. The prototype SDRAM budgets and
  inherited peripheral/debug pin coverage scope are explicit in
  [SDRAM pin timing](docs/SDRAM_PIN_TIMING.md); physical margins remain unverified.
- Native RAM startup contents, DDR/direct ROM loading, replacement/reset/pause,
  controls/DIPs and high-score host-file transfers pass subsystem tests. All
  38 real ADPCM sample sequences pass 237,330 decoded-value checks.

The core renders one row ahead into two line banks; it adds no composite frame
buffer. Provisional geometry and clock assumptions are documented in
[video timing](docs/PROVISIONAL_RASTER.md). Sound listening, physical outputs,
interactive game execution and the remaining standard video features still
require bring-up. Optional forced doubling, HQ2x and scanline modes now pass
functional tests and the non-debug full fit; the latest debug placement has one
small HDMI timing failure under investigation. See [machine integration](docs/MACHINE_INTEGRATION.md),
[sound bring-up](docs/SOUND_BRINGUP.md), [prototype limitations](docs/HACKS.md)
and [read-only debug probes](docs/DEBUG.md) for exact scope.

New board logic will use VHDL, with fx68k (SystemVerilog), T80 (VHDL), directly reused JTFRAME
modules, and approved mixed-language sound/framework dependencies. Target: DE10-nano, Quartus Prime Lite 17.0.2, one
SDRAM module of at least 32 MB. Each set declares 0x210000 ROM bytes (2.0625 MiB).

See [ROADMAP](docs/ROADMAP.md), [hardware notes](docs/HARDWARE_NOTES.md), and
[WORKFLOW](docs/WORKFLOW.md) for scope, evidence, and build coordination.
Installed versions and baseline results are recorded in [TOOLCHAIN](docs/TOOLCHAIN.md).
ROM/control definitions and board-interface tests are in [BOARD_INTERFACE](docs/BOARD_INTERFACE.md).
Video reference and bitmap RTL evidence are in [VIDEO_REFERENCE](docs/VIDEO_REFERENCE.md).

## Reference setup

Configure MAME_SRC, MAME_DIR, MAME_EXE and MAME_ROMPATH in gitignored mister.env.
Use a matching release source/executable before collecting trusted MAME captures.
ROMs are not distributed or committed here.

    python scripts/coretools.py
    python scripts/extract_dips.py --selftest
    python scripts/reference_manifest.py

The ROM manifest is source research, not an executable MRA. It preserves load
interleave, explicit fills, and region flags. Physical video timing is unresolved.

## Provenance and AI assistance

Framework: MiSTer-devel/Template_MiSTer 9c8eadb40067c8ce3aef90899844f62d688ac73a.
The sys directory is unchanged apart from Windows checkout line endings.
Bootstrap tooling and workflows came from the local MiSTer-CoreSkill checkout.
CPU and initial JTFRAME evaluation sources are pinned with passing baseline checks;
an unchanged YM2151 evaluation copy and VHDL wrapper now pass isolated timer/IRQ,
sample-cadence and explicit-mute tests. JT7759 is a separately baselined evaluation
copy; all selected vendor sources remain unchanged. See [BASELINES](docs/BASELINES.md)
and [sound bring-up](docs/SOUND_BRINGUP.md).

Codex assisted with research, documentation, board RTL, adapters, testbenches and
reference tooling. Simulation and implementation checks are recorded; board
verification is still required before release. No hardware
results or release artifacts exist yet. Distribution: GPL-3.0-or-later, preserving
third-party notices and recording provenance for each added dependency.
