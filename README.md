# Rabbit Punch / Rabio Lepus for MiSTer

Early development for Video System's 1987 arcade hardware, using MAME's rpunch.cpp
as the behavioral reference. Target sets: rabiolep (Japan), rpunch (US).

Status: CPU/JTFRAME baselines and first VHDL board interfaces pass; both development
MRAs are generated and their ROM streams match MAME. CPU integration diagnostics pass,
all 52224 main RAM words pass read/write checks, and each game's first 10000 writes
match MAME exactly using the VHDL memory backend in simulation.
The VHDL board registers also match 24 state fields reconstructed from MAME writes.
Level-1 IRQ/autovector handling passes a STOP/handler/RTE diagnostic through VHDL RAM.
The logical VHDL video pipeline matches six MAME frames through native line,
bitmap and palette RAM, with direct HDL RGB comparison and standalone timing closure.
Shared CPU/video BRAM now passes all six scenes, concurrent writes and live
bitmap/palette updates, with all-corner implementation timing closure. All six captured
scenes also match through the actual shared SDRAM controller/model and tiny
ROM caches, with competing synthetic CPU ROM reads. SDRAM, ROM mapping and tiny ROM burst caches pass
separate implementation and synthesized-netlist tests. Physical raster/PLL,
full raster scheduling and real-pin SDRAM timing remain open. The connected
logical CPU/I/O/video board passes 10000-write MAME comparisons for both games
while lines render; combined board placement/routing/timing passes at 48 MHz
under documented evaluation-interface constraints.
The board, ROM subsystem and download control now form a connected logical
system that executes downloaded synthetic 68000 diagnostics, including image
replacement, soft reset and incomplete-download recovery.
The connected logical audio subsystem includes T80, JT51 and JT7759 with sample
bank/reset/start control and shared SDRAM scheduling. Both real sound ROMs match
4096 MAME startup writes with documented CPU/RAM seeds. Both CPUs running together
also match bounded MAME prefixes of 2000 main writes and 256 sound writes per set.
Downloaded 68000 commands drive the sound latch/IRQ/ack, native sound RAM and
sample playback. CPU pause preserves chip playback. Active-playback image
replacement now drains correctly, aborts/mutes playback and recovers. A mono
mixer passes 283135 integer arithmetic checks; startup silence, active replacement and
defined-output regressions and the updated 48 MHz implementation pass. All 38
real sample sequences also pass 237330 native-decoder value checks against a
pinned-MAME-source model. Audible real-game sound remains unverified.
See [sound bring-up](docs/SOUND_BRINGUP.md), [board integration](docs/BOARD_INTEGRATION.md) and
[system integration](docs/SYSTEM_INTEGRATION.md) for exact test scope.
No complete game or playable RBF.
The inherited template demo remains connected.

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
