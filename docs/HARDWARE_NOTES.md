# Rabbit Punch / Rabio Lepus hardware notes

Status: source research plus first MAME captures/coarse timing sweeps. No game RTL,
synthesis or FPGA hardware validation yet. See TOOLCHAIN.md for verified setup.

## Reference

Local checkout: `D:/git/mame`, HEAD `00ab4817bd741382a37a99655629407acbb4fc9d`.
Line references below are to the local `src/mame/vsystem/rpunch.cpp`, not current upstream.
The driver and both GGA files have no working-tree changes. Checkout identifies as
`mame0289-1577-g00ab4817bd7`, newer than release 0.289. Pin matching release source
alongside a release executable before trusting captured references.
Inspected driver SHA256: `856dffea9e6c101bbf3a0c8fca20e41ad5913f6a16437212a0c4b79385fd0fce`.
An independent parser check of the two ROM_START blocks confirmed both totals below.

The driver contains the video implementation itself; no separate `rpunch_v.cpp` is needed.
Additional board model: `src/mame/vsystem/vsystem_gga.{cpp,h}`. Device references:
`src/devices/sound/{ymopm,upd7759}.{cpp,h}`, `src/devices/cpu/m68000/`,
`src/devices/cpu/z80/`; packed tile decoding comes from MAME's shared graphics layouts.
Active capture reference is now MAME 0.289 with source tag mame0289 at
commit f34f02505e32c1993c6a782b6814232cbfc74e36, in a separate workspace snapshot.
Earlier line citations above/below describe the initial checkout; active source hashes
are in reference/rom_manifest.json. Both sets pass the executable's ROM verification.
The merged archive contains all 18 required ROM files per set.

## Games and ROM capacity

| Set | Description | Relationship | Driver lines |
|---|---|---|---|
| rabiolep | Rabio Lepus (Japan), 1987 | Parent | 948, 1178 |
| rpunch | Rabbit Punch (US), 1987 | Clone of rabiolep | 914, 1179 |

Both use machine configuration `rpunch`, ROT0, and have `MACHINE_SUPPORTS_SAVE`
and `MACHINE_NO_COCKTAIL`. Neither declares protection hardware in this configuration.
Super Volleyball and its bootleg share the driver but are outside this project scope.

| Region | Declared bytes per set | File-loaded bytes per set |
|---|---:|---:|
| maincpu | 0x40000 | 0x20000 |
| audiocpu | 0x10000 | 0x10000 |
| tiles1 | 0x80000 | 0x50000 |
| tiles2 | 0x80000 | 0x50000 |
| sprites | 0x80000 | 0x60000 |
| upd | 0x40000 | 0x20000 |
| Total | 0x210000 = 2.0625 MiB | 0x150000 = 1.3125 MiB |

These totals come from the two ROM_START blocks, excluding the commented alternate
sample ROM. Preserve ROM_FILL, erase values, interleave, and unloaded region tails.
The sets share all tiles1 files, the first two tiles2 files, the first four sprite
files, and the sample ROM (matching CRC/SHA1 entries). Program, audio program, and
some graphics files differ. Load one selected set at a time; no cross-set storage
deduplication is necessary. Confirm the generated layout using matching-version `-listxml`.

## Chips and clocks

| Part | MAME clock | Evidence |
|---|---:|---|
| Main 68000 | 16 MHz / 2 = 8 MHz | 809, 815 |
| Sound Z80 | 16 MHz / 4 = 4 MHz | 818 |
| YM2151 | 16 MHz / 4 = 4 MHz | 845 |
| Video System C7-01 GGA | 13.333 MHz / 2 = 6.6665 MHz | 810, 839; schematic attribution in driver |
| uPD7759 | 640 kHz default | 850 and `src/devices/sound/upd7759.h:21,130` |

The GGA clock is NOT proof of the output pixel clock. The driver has no `set_raw`:
it requests 60 Hz, size 304 x 224, visible x=8..295, y=0..215 (288 x 216).
These are MAME screen coordinates, not established PCB horizontal/vertical totals.
Physical sync, blanking, pixel clock, and PLL plan remain open.

## Main CPU map

`svolley_map` at 547 and `rpunch_map` at 566; global address mask 0xfffff.

| Byte address | Function | Storage / access notes |
|---|---|---|
| 000000..03ffff | Program ROM | 256 KiB declared region, 128 KiB file-loaded |
| 040000..04ffff | Packed bitmap | 64 KiB, 512 x 256 x 4 bpp; u8 handlers on 16-bit CPU map |
| 060000..060fff | Sprite RAM | 4 KiB; four 16-bit words per entry |
| 080000..083fff | Tilemap RAM | Two 8 KiB maps |
| 0a0000..0a07ff | Palette RAM | 1024 x 16 bits, xRGB555 |
| 0c0000..0c0007 | Scroll | BG0 Y/X, BG1 Y/X; MAME updates only on full-word writes |
| 0c0009, 0c0029 | GGA data / register select | Low-byte ports via select(0x20) |
| 0c000c..0c000d | Video flags | Byte-mask merge |
| 0c000f | Sound command | Low byte; sets pending latch |
| 0c0010..0c0013 | Sprite count / priority split | Low byte, each masked to 6 bits |
| 0c0018..0c001b | P1 / P2 inputs | Active high; shared service/start/coin upper bits |
| 0c001c..0c001d | DIP switches | Set-specific input definitions |
| 0c001e..0c001f | Sound busy | Sound-command pending, not sample-chip busy |
| 0fc000..0fffff | Work RAM | 16 KiB |

Verify bitmap byte-lane dispatch using actual MAME accesses: the header's word diagram
and the u8 handlers must not be conflated. Test both byte lanes and CPU mirror addresses.

## Video model

- Tilemaps: two 64 x 64 maps of 8 x 8, 4 bpp tiles, column-major indexing (474).
  Background 0 is opaque, background 1 uses transparent pen 15. Decode callbacks
  at 237 and 250 select tile bank and palette from VRAM plus video flags.
- Sprites: 16 x 32, 4 bpp with the explicit packed layout at 755; pen 15 transparent.
  `draw_sprites` at 393 processes count-1 down to zero. Count and priority split are
  six-bit values, despite RAM having room for 512 descriptors. Word 0 supplies Y,
  word 2 X; the old header describes those positions differently, so follow the code.
  Word 1 gives 11-bit code, Y/X flip bits 11/12, and three palette bits, extended
  by video flag bit 6. Rabbit Punch sprite palette starts at 0x300.
- Priority: BG0, transparent BG1, priority-tested sprites, then transparent bitmap
  (457). A sprite below the split is blocked by BG1; other sprites are above BG1.
  Preserve sprite-to-sprite priority semantics from MAME's priority renderer in tests.
- Bitmap: real CPU-writable image memory, not a proposed full-frame renderer.
  Four-bit pixels, transparent value 15, palette base 512 + ((flags & 15) << 4).
  Source X is (screen X + 4) & 511 (433). MAME starts the inner loop at clip-left/4:
  preserve and document this behavior when building the reference model.
- Flip: driver header mentions a flag; the renderer does not visibly implement a
  complete global flip path and games declare NO_COCKTAIL. Verify actual ROM writes
  and DIP behavior before selecting the core's flip implementation.
- GGA: device is explicitly a skeleton. It retains 16 registers and an address
  latch. Driver register 0x0b schedules IRQ1: 0xc0 requests two interrupts per frame,
  other values one. First callback at vblank then periodic at frame-period/count
  (`crtc_interrupt_gen`, `gga_data_w`). Do not reduce this to unconditional vblank IRQ.

Per-field attract and scripted-play sweeps for both sets are now recorded in
VIDEO_WRITE_TIMING.md. They show writes outside vblank and do not establish a
common original-board snapshot/latch point. Continuous active-play coverage and
PCB timing remain open; the logical-line renderer is not evidence of that policy.

## Sound map and behavior

`sound_map` at 589: 0000..efff ROM; f000..f001 YM2151;
f200 command read; f400 sample control; f600 sample command/start; f800..ffff 2 KiB RAM.
Z80 IRQ is the OR of YM2151 IRQ and command pending. Reading the command acknowledges
the generic latch. Sample control bit 0 selects ROM bank, bit 7 drives reset;
sample command writes data then pulses start low/high (526, 533). Preserve mono routing:
both YM outputs and sample output each have gain 0.50 in the MAME model.

## Feasibility and limitations

User-confirmed hardware: one Mister Addons 128 MB SDRAM module; no dual-SDRAM requirement. All game storage
can live below 32 MiB, making physical high-address support unnecessary for this scope.
Confirm the installed module/controller electrical compatibility during bring-up.
ROM capacity is comfortable. CPU and multiple video blocks now have bounded
simulation/standalone-fit evidence in ROADMAP.md. Full CPU/video/sound integration,
shared-memory deadlines and the complete MiSTer fit remain unverified.

The main uncertainties are physical video timing, incomplete GGA behavior,
dynamic CPU/video agreement, shared-memory deadlines and sound integration.
MAME 0.289 and matching ROM audits are available, and the user approved unchanged
Verilog dependencies behind VHDL wrappers. No playable core or full-core build is claimed.

A first-hand [Rabio Lepus PCB repair log](https://jammarcade.net/rabio-lepus-repair-log/)
traces shared sprite-ROM address A7 through a 74LS273 at 8A to data D0 of a
2Kx8 SRAM at 10A. It supports an address-latch path on that board, but supplies
no pixel-clock, raw-raster or frame-latch measurement. Do not infer those from it.
