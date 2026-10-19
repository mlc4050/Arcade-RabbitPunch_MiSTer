# Rabbit Punch / Rabio Lepus for MiSTer

A MiSTer FPGA core for Video System's 1987 arcade hardware, supporting **Rabbit Punch** and **Rabio Lepus**. Built for the DE10-Nano with Quartus Prime Lite 17.0.2, using MAME 0.289's `vsystem/rpunch.cpp` as the reference.

**Work in progress. Both games run with video and sound. Savestates are in development.**

## Contents

- [History](#history)
- [Games](#games)
- [Features](#features)
- [Controls](#controls)
- [High scores and NVRAM](#high-scores-and-nvram)
- [Savestates](#savestates)
- [Installation](#installation)
- [Hardware](#hardware)
- [Building](#building)
- [Verification](#verification)
- [Acknowledgements](#acknowledgements)
- [Repository layout](#repository-layout)
- [License](#license)

## History

### Arcade-RabbitPunch_20261018

- Initial public WIP build for Rabbit Punch (US) and Rabio Lepus (Japan).
- Video settings submenu, with aspect ratio, rotation, scaling, flip screen and CRT adjustment.
- DIP switches available through the OSD.
- Corrected Fire/Punch and Missile button labels for both games.
- Optional pause when the OSD is open; audio is muted while paused.
- High-score persistence, with automatic and manual NVRAM saving.

## Games

| Game | Year | Region | MAME set |
|---|---|---|---|
| Rabbit Punch | 1987 | US | `rpunch` |
| Rabio Lepus | 1987 | Japan | `rabiolep` |

Both games use the same RBF. Select the appropriate MRA for the game you want to play. Super Volleyball and other games sharing MAME's driver are outside this core's scope.

## Features

- Two-player controls, keyboard support and controller pause.
- Game-specific DIP switches.
- Aspect ratio and HDMI scaling options.
- HDMI rotation and flip screen; flip screen also applies to analog video.
- CRT position and size adjustment, subject to output-mode restrictions.
- Audio mix options and mute during pause.
- High-score saving through MiSTer's NVRAM interface.
- Direct ROM loading, with optional DDR-staged loading MRAs.

The Video settings submenu holds the display options. DIP switches, audio mix, pause behavior and NVRAM controls are available from the main OSD page.

## Controls

Define controller buttons through MiSTer's **Define joystick buttons** menu. If upgrading from an earlier MRA with Shoot/Missile labels, redefine the buttons to match the corrected order.

| Action | Player 1 keyboard | Player 2 keyboard |
|---|---|---|
| Move | Arrow keys | R / F / D / G |
| Fire/Punch | Left Ctrl | A |
| Missile | Left Alt | S |
| Start | 1 | 2 |
| Coin | 5 | 6 |

| Common action | Keyboard |
|---|---|
| Pause | P |
| Service coin | 9 |
| Test switch | F2 |

Service adds a credit without using the normal coin input. Test is a separate board input; F2 can be held during boot. See [control mapping](docs/CONTROLS.md) for the underlying wiring.

## High scores and NVRAM

High-score tables are saved separately for each game through MiSTer's `.nvm` files. Enable **Autosave NVRAM**, or use **Save NVRAM** in the OSD to request a manual save.

NVRAM contains the high-score table; a full game snapshot requires savestates. DIP settings are handled by MiSTer's per-game configuration.

## Savestates

Savestates are not available in this release.

## Installation

1. Download [`Arcade-RabbitPunch_20261018.rbf`](releases/Arcade-RabbitPunch_20261018.rbf) and the desired game MRA from [`releases/`](releases/).
2. Copy the RBF to `_Arcade/cores/` on your MiSTer.
3. Copy the MRA to `_Arcade/`.
4. Place the matching ROM ZIP files in `games/mame/` and launch the game through its MRA.

The MRAs were verified against **MAME 0.289**. A merged `rabiolep.zip` includes the files needed for both games. ROMs are not included.

Optional DDR-loading MRAs are under [`releases/_alternatives/_ddr/`](releases/_alternatives/_ddr/). These stage the download through onboard DDR3; the games still run from the external SDRAM module. The diagnostic MRA is intended for development and requires a separately generated test ROM.

## Hardware

| Component | Function | Implementation |
|---|---|---|
| Motorola 68000, 8 MHz | Main game CPU | fx68k |
| Z80, 4 MHz | Sound CPU | T80 |
| YM2151, 4 MHz | FM music | JT51 |
| uPD7759, 640 kHz | ADPCM samples | JT7759 |
| Video System video hardware | Tile layers, sprites, bitmap layer and priority | VHDL board logic with reused JTFRAME drawing components |
| External SDRAM | Game ROM storage | Single-module SDRAM controller |
| FPGA block RAM | Board RAM, caches and line buffers | Inferred FPGA memory |

The game runs on one system clock with clock enables for the board components. Rendering proceeds one scanline ahead through alternating line buffers. Optional HDMI rotation uses the MiSTer DDR3 presentation path.

### Video timing

- System clock: **46.667 MHz**.
- Pixel clock: **6.667 MHz**, one pixel every seven system clocks.
- Raster: **432 pixels x 256 lines**, with **288 x 216** visible.
- Horizontal frequency: approximately **15.432 kHz**.
- Refresh rate: approximately **60.282 Hz**.
- Display aspect: **4:3**, or **3:4** when rotated.

These are the implemented timings. Original-board raw raster timings have not been established; [the timing notes](docs/PROVISIONAL_RASTER.md) record the evidence and assumptions.

### Resource usage

RabbitPunch revision, fitted October 18, 2026, seed 3:

| Resource | Used | Available |
|---|---:|---:|
| Logic (ALMs) | 15,285 | 41,910 |
| Registers | 25,260 | 83,820 |
| Block memory bits | 1,445,728 | 5,662,720 |
| M10K blocks | 187 | 553 |
| DSP blocks | 35 | 112 |
| PLLs | 3 | 6 |

All **144 scoped timing checks** pass, with minimum setup slack **+0.419 ns** and hold slack **+0.079 ns**. Framework timing exclusions are documented in [SDRAM timing](docs/SDRAM_PIN_TIMING.md); the [build report](docs/reference/full_shell_final_osd_nvram_checks.json) records the full scope.

### Floorplan

RabbitPunch revision, fitted October 18, 2026. Colors identify the game machine, video processing, host interface and MiSTer framework; brightness indicates occupancy.

![RabbitPunch FPGA floorplan](docs/floorplan/RabbitPunch.png)

[Resource groups](docs/floorplan/RabbitPunch_groups.md).

## Building

Use **Quartus Prime Lite 17.0.2**, including Cyclone V device support. Native simulation uses ModelSim; scripts require Python 3. Additional simulation tools are described in [toolchain setup](docs/TOOLCHAIN.md).

Set local tool and ROM paths in the gitignored `mister.env`. Reference captures require matching MAME 0.289 source and executable.

From a clean, committed checkout on Windows:

```powershell
.\scripts\d_drive.ps1 scripts/build_staged.py --rev RabbitPunch --seed 3
```

The staged build records its source commit and fitter seed and checks implementation results before accepting the artifact. See [working practice](docs/WORKFLOW.md) and [release process](docs/RELEASE_PROCESS.md).

## Verification

The core is checked against MAME for ROM loading, graphics and sound, with simulation tests and Quartus timing analysis. Complete music comparison and broader hardware testing remain in progress.

Detailed results are in [`docs/reference/`](docs/reference/). See [build identity mapping](docs/reference/publication_identity_checks.json) for the published RBF's source revision.

[Roadmap](docs/ROADMAP.md) | [Known approximations](docs/HACKS.md) | [MAME behavior notes](docs/MAME_KLUDGES.md) | [Sound](docs/SOUND_BRINGUP.md) | [Savestates](docs/SAVESTATES.md)

## Acknowledgements

- **MiSTer developers and contributors** for the platform and core template.
- **MAME developers** for the Rabbit Punch / Rabio Lepus hardware model and reference implementation.
- **Jorge Cwik** for fx68k.
- **Daniel Wallner and contributors** for T80.
- **Jose Tejada Gomez (jotego)** for JTFRAME, JT51 and JT7759.
- **Sorgelig and contributors** for the SDRAM and MiSTer video components.
- **Umberto Parisi and Andrea Bogazzi** for CRT Adjust.
- **ppriest** for [MiSTer-CoreSkill](https://github.com/ppriest/MiSTer-CoreSkill), worked core examples and development guidance.

Development assisted by OpenAI Codex.

Component origins, donor revisions and license notices are recorded in [THIRD-PARTY.md](THIRD-PARTY.md) and the individual `PROVENANCE.md` files.

## Repository layout

| Path | Contents |
|---|---|
| `releases/` | RBF, game MRAs and loading alternatives |
| `rtl/` | Board implementation, adapters and third-party components |
| `sys/` | MiSTer framework |
| `sim/` | Testbenches and simulation support |
| `scripts/` | Build, capture, validation and development tools |
| `docs/` | Hardware notes, design, verification and development status |

## License

[GPL-3.0-or-later](LICENSE), with third-party components retaining their own license notices. See [THIRD-PARTY.md](THIRD-PARTY.md).
