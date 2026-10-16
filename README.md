# Rabbit Punch / Rabio Lepus for MiSTer

Early development for Video System's 1987 arcade hardware, using MAME's rpunch.cpp
as the behavioral reference. Target sets: rabiolep (Japan), rpunch (US).

Status: framework bootstrapped; tools verified and first MAME reference captures taken.
No game RTL or playable RBF. The inherited template demo remains connected.

New board logic will use VHDL, with fx68k (SystemVerilog), T80 (VHDL), directly reused JTFRAME
modules, and approved mixed-language sound/framework dependencies. Target: DE10-nano, Quartus Prime Lite 17.0.2, one
SDRAM module of at least 32 MB. Each set declares 0x210000 ROM bytes (2.0625 MiB).

See [ROADMAP](docs/ROADMAP.md), [hardware notes](docs/HARDWARE_NOTES.md), and
[WORKFLOW](docs/WORKFLOW.md) for scope, evidence, and build coordination.
Installed versions and baseline results are recorded in [TOOLCHAIN](docs/TOOLCHAIN.md).

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
sound dependencies have not been vendored yet. See [BASELINES](docs/BASELINES.md).

Codex assisted with research, documentation and reference tooling. Future RTL needs
simulation, timing closure and board verification before release. No hardware
results or release artifacts exist yet. Distribution: GPL-3.0-or-later, preserving
third-party notices and recording provenance for each added dependency.
