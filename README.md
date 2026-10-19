# Rabbit Punch / Rabio Lepus for MiSTer

Work-in-progress core for Video System's 1987 arcade hardware. Supports the
Rabbit Punch (US) and Rabio Lepus (Japan) ROM sets, using MAME 0.289's
`rpunch.cpp` as the behavioral reference.

## Status

The user has reported successful boot and play on a DE10-Nano with one 128 MB
SDRAM module. Video looks good in that testing and sound effects are working.
Music still needs comparison against MAME. This is a prototype, not a completed
hardware-validation or accuracy claim.

The latest OSD/NVRAM candidate has the requested Video settings submenu,
Audio mix, DIP switches, Pause when OSD is open, Autosave NVRAM and Save NVRAM,
with Reset at the bottom. Save NVRAM now keeps the menu open so MiSTer's host
can process the upload without reopening the OSD. Immediate on-disk saving
still needs confirmation on this candidate.

Full savestates are being implemented. They are not functional or exposed in
the OSD yet. NVRAM saving preserves high scores; it is separate from savestates.

## Hardware and controls

- DE10-Nano, one SDRAM module; hardware feedback so far uses 128 MB.
- fx68k 68000, T80 Z80, JT51 YM2151 and JT7759 ADPCM, with existing MiSTer
  framework and JTFRAME components reused behind descriptive adapters.
- New board logic and testbenches use VHDL and `numeric_std` unsigned types.
- Native video renders one scanline ahead using line buffers. Optional HDMI
  rotation uses a separate DDR3 presentation framebuffer.
- Controls are labeled Fire/Punch and Missile. Controller Pause, coin/start,
  service and test are also wired; see [controls](docs/CONTROLS.md).
- Each game's ROM image occupies 0x210000 bytes. Development MRAs include direct
  and DDR-staged loading alternatives.

## Builds and ROMs

Use Quartus Prime Lite 17.0.2 with Cyclone V device support. ModelSim and Python
3 are used by the native test scripts; the supplemental fast simulation setup
is documented in [toolchain](docs/TOOLCHAIN.md).

Configure local tool/ROM paths in gitignored `mister.env`. MAME executable and
source must both be version 0.289. ROMs are not included or distributed here.
Development MRAs are under `releases/_dev/` and must be used with the matching
prototype core.

On the Windows development setup, build through the staged workflow:

```powershell
.\scripts\d_drive.ps1 scripts/build_staged.py --rev RabbitPunch --seed 3
```

The latest compiled OSD/NVRAM prototype passes all 144 scoped timing checks:
minimum setup +0.419 ns and hold +0.079 ns. The game clock is 46.667 MHz.
Inherited framework electrical timing exclusions and provisional board timing
are documented in [SDRAM timing](docs/SDRAM_PIN_TIMING.md) and
[video timing](docs/PROVISIONAL_RASTER.md). A successful fit is not a substitute
for physical testing.

Before first publication, local author/committer identity was changed for
privacy. Source file trees were verified unchanged. Older verification reports
retain their original build commit IDs; the corresponding rewritten source is
recorded in [build identity mapping](docs/reference/publication_identity_checks.json).
Private backups and development outputs are excluded from publication.

## Verification and remaining work

- Startup tests cover both games' main and sound CPUs, including production
  PLL/enables and a shifted SDRAM chip model.
- Six static video scenes match MAME; qualified native scanout scenes each
  match all 62,208 pixels. Earlier executing-game captures also record a
  34-pixel US temporal difference rather than claiming universal equality.
- Completed 1,800-frame live pad/PCM runs cover both sets; their input schedule,
  archive and scope are recorded in `docs/reference/`.
- All 38 ADPCM sample sequences pass 237,330 decoded-value checks. Keyed FM
  samples match between native and supplemental fast simulation. Complete
  music-track equivalence against MAME is still open.
- Basic masked/unmasked 68000 and Z80 state-continuation tests pass. STOP/HALT,
  integrated RAM/chip capture, storage slots and full-game restore remain work.

See [roadmap](docs/ROADMAP.md), [hardware notes](docs/HARDWARE_NOTES.md),
[prototype limitations](docs/HACKS.md), [sound bring-up](docs/SOUND_BRINGUP.md),
[savestates](docs/SAVESTATES.md) and [state inventory](docs/STATE.md) for details.
Older subsystem documents describe their own test revisions and scopes.

## Credits, license and AI assistance

MAME is the behavioral reference. The MiSTer framework, fx68k, T80, JTFRAME,
JT51, JT7759 and other reused components retain their original authorship and
license notices; provenance is recorded alongside the imported files and in
[third-party documentation](THIRD-PARTY.md).

Codex substantially assisted with research, VHDL implementation, adapters,
testbenches, reference tooling and documentation. Simulation, implementation
results and remaining limitations are documented rather than presented as
unverified hardware results.

Distribution is GPL-3.0-or-later, preserving third-party notices.
