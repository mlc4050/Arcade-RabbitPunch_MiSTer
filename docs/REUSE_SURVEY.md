# Local RTL reuse survey

Scope: the user's D:/git checkouts, including meatsauce. File-name and HDL/Markdown/MRA
content searches for Rabbit Punch, Rabio Lepus, rpunch, vsystem_gga and C7-01 did not
locate a complete board implementation in the files searched. This is a local survey,
not a claim that no implementation exists elsewhere. Donors below are candidates;
no new donor is validated or vendored by this survey.

## Reuse existing chip implementations

| Block | Local candidate | Integration still required |
|---|---|---|
| 68000 | Arcade-Seta_MiSTer/rtl/cpu/tg68k/ | VHDL board bus adapter, effective execution timing, interrupts, byte lanes |
| Z80 | Arcade-Psikyo_MiSTer/rtl/cpu/t80/ | VHDL sound address map, RAM, command and Yamaha IRQ merge |
| YM2151 | Arcade-JalecoMS1BCD_MiSTer/rtl/third_party/jt51/hdl/ | Clock/enable phases, register bus, IRQ, audio level |
| uPD7759 | Arcade-SystemC2_MiSTer/rtl/jt7759/hdl/; alternate SNK68/rtl/jt7759/hdl/ | Standalone mode, 128 KiB bank selection, reset/start, ROM handshake |
| SDRAM | Arcade-Seta_MiSTer/rtl/memory/sdram/ | ROM client routing, priorities, load layout and measured deadlines |
| MiSTer output/HPS | Already bootstrapped Template sys/ | Board wrapper and configuration; retain sys unchanged |

TG68K and T80 are VHDL. JT51 and JT7759 are Verilog, explicitly permitted by the
approved mixed-language approach. Their inspected headers state GPL-3.0-or-later;
CPU provenance and memory provenance are linked in ROADMAP.md. Record exact donor
revision, modifications and full dependency list before copying; run baseline tests.

SystemC2's c2_system.sv instantiates JT7759 and its top-level describes the level-to-toggle
ROM request bridge. Inspect that bridge before copying a transport contract: jt7759's
rom_cs is not necessarily a one-cycle request. Chip reuse does not remove bus validation.

## Adapt proven video architecture and write board-specific VHDL

| New board block | Existing reference | Rabbit Punch differences to implement |
|---|---|---|
| Tile fetch/decode and scrolling | Arcade-Psikyo_MiSTer/rtl/video/tilemap_line_engine.sv | Two 64x64 column-major 8x8 maps; packed 4 bpp; specific bank/palette bits; 9-bit scroll |
| Sprite list and scanline scheduling | meatsauce/cores/ikki/rtl/ikki_video.sv | Different descriptors, count/split registers, coordinate wrap, snapshots and priority |
| Sprite row drawer / line buffers | Arcade-KonamiGX_MiSTer/rtl/jtframe/jtframe_objdraw.v and jtframe_obj_buffer.v | Map 16x32 sprite rows onto the generic row architecture; packed pixel permutation and sprite ordering |
| Packed bitmap path | MAME rpunch_state::pixmap_r/w and draw_bitmap | 64 KiB CPU RAM, byte lanes, source-X offset, pen-15 transparency and palette bank |
| Palette and mixer | MAME rpunch_state::screen_update and draw_sprites | xRGB555, BG0/BG1/sprite split priority/bitmap priority; preserve sprite-to-sprite behavior |
| GGA/register/interrupt model | MAME vsystem_gga plus rpunch_state::gga_data_w | Indexed 16-register latch and register-0x0b IRQ cadence; incomplete hardware model |
| Main/sound board glue | meatsauce/cores/MCR-68K/rtl/mcr68_addr_decode.sv and mcr68_main_board.sv | Different address map, TG68K bus contract, inputs, DIPs, sound pending and reset/pause |

The inspected generic JTFRAME drawer has a 16-pixel object width and 4-bit ysub;
do not assume it accepts Rabbit Punch's entire 32-line object without mapping it.
Use a standard fetch/pipeline structure, not a serial translation of MAME drawing loops.
Any translated/copied logic retains its licence and provenance.

The Suna8bit sprite renderer was also inspected. Its header describes a full-frame
renderer with simplified priority; that architecture is not selected for this board.
Rabbit Punch's own writable bitmap is retained, independently of line-based compositing.

## MRA deliverables

Generate two development MRAs, Rabbit Punch (US) and Rabio Lepus (Japan), using one
RabbitPunch RBF identity. They are XML launch/ROM/control descriptions, not HDL blocks.
Keep drafts under releases/_dev until there is a corresponding verified released RBF.

The generator must:

1. Read a single shared ROM layout definition used by VHDL; keep six regions and their
   exact sizes, byte interleave, fill behavior and CRCs. Current proposal ends at 0x210000.
2. Support merged rabiolep.zip for both sets, with rpunch.zip as a clone source when present.
   Find ROMs by checksum, including files inside archive subdirectories.
3. Extract each game's own DIP masks, defaults and choices, and use verified control names
   Missile/Punch, Start, Coin, Pause, Service and Test. Confirm button order against driver
   ports and ROM behavior; don't reuse another core's status-bit assignments.
4. Write mameversion from the actual reference executable, not a hand-entered guess.
   The downloaded package is not yet an installed/configured reference executable.
5. Reassemble the XML with scripts/mra.py and compare it byte-for-byte with a separate
   ROM_START-based image. Then run validate_mra.py for XML, controls, DIP width/defaults,
   version and rotation. Retain checksums/results rather than copyrighted ROM bytes.

The existing rom_manifest.json and passing DIP parser checks supply research inputs.
Final load/download constants and button/status wiring do not exist yet, so a draft MRA
would describe a proposed interface until those checks pass. It must not be advertised
as playable before the core and ROM loader are implemented.
