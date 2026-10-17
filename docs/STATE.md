# RabbitPunch state inventory

What a savestate or a state dump has to carry, kept current as RTL lands (the skill's
`savestates.md`). "Skip" needs a reason: a ROM table from the `.mra`, or something re-derived
every frame.

## RAMs

| Region | RTL | Width x depth | Bytes | Save? |
|---|---|---|---|---|
| Bitmap | rabbitpunch_board_memory / rabbitpunch_ram16 | 16 x 32768 | 65536 | Yes; read-only view port, restore through paused CPU request port |
| Sprites | rabbitpunch_board_memory / rabbitpunch_ram16 | 16 x 2048 | 4096 | Yes; same access paths |
| Tilemaps | rabbitpunch_board_memory / rabbitpunch_ram16 | 16 x 8192 | 16384 | Yes; same access paths |
| Palette | rabbitpunch_board_memory / rabbitpunch_ram16 | 16 x 1024 | 2048 | Yes; same access paths |
| Main work | rabbitpunch_board_memory / rabbitpunch_ram16 | 16 x 8192 | 16384 | Yes; same access paths |
| Sprite line banks | rabbitpunch_sprite_line / rabbitpunch_ram16 | 2 x 16 x 512 | 2048 | Derived pixels and occupancy/index/tag; finish/flush and re-render before resuming video, or capture both banks with scheduler phase |
| Packed tile line banks | rabbitpunch_tiles / rabbitpunch_ram16 | 2 x 16 x 512 | 2048 | Derived BG0/FG pixels; finish/flush and re-render, or capture banks and scheduler phase |

## Registers and FSMs

| What | RTL | Bits | Save? | MAME `save_item` equivalent |
|---|---|---|---|---|
| Bus FSM: idle/waiting/complete/draining | rabbitpunch_bus.vhd | 2 logical | Future capture at drained/idle boundary | Transport, no direct MAME device counterpart |
| Latched request address/data/byte enables/write flag | rabbitpunch_bus.vhd | 43 | Future; can be discarded only at drained/idle boundary | Current 68000 bus access |
| CPU read-data holding register | rabbitpunch_bus.vhd | 16 | Future | Current 68000 bus access |
| Request pulse register | rabbitpunch_bus.vhd | 1 | Must be inactive at proposed capture boundary | Transport |
| CPU phase divider count and phase | rabbitpunch_maincpu.vhd | ceil(log2(PHASE_DIVIDER)) + 1 | Future, together with CPU | CPU clock phase |
| Memory backend FSM / target / write flag | rabbitpunch_memory.vhd | 2 logical + 5 + 1 | Capture at idle boundary | Transport |
| ROM request address and response holding data | rabbitpunch_memory.vhd | 18 + 16 | Capture at idle boundary | Transport |
| Inspection target, valid and per-bank read holding data | rabbitpunch_board_memory / rabbitpunch_ram16 | Derived pipeline state | Discard only when inspection idle | Debug/video port pipeline |
| Video flags / scroll registers / sprite count and priority | rabbitpunch_io.vhd | 16 + 36 + 12 | Read through explicit outputs; restore through CPU write path | m_videoflags, tilemap scroll, m_sprite_num, m_sprite_pri |
| GGA register file and selected index | rabbitpunch_io.vhd | 128 + 4 | Indexed GGA view; restore through select/data writes | GGA m_regs / m_address_latch |
| Sound command and pending flag | rabbitpunch_io.vhd | 8 + 1 | Capture with sound CPU stopped; future coordinated state loader | generic_latch_8 state |
| IRQ enabled / first-event state / frequency / pending | rabbitpunch_irq.vhd | 4 | Future explicit state loader | CRTC timer configuration and CPU HOLD_LINE |
| CPU previous interrupt-acknowledge cycle | rabbitpunch_maincpu.vhd | 1 | Capture outside acknowledge cycle | Bus protocol edge detection |
| Bitmap fetch FSM and X/Y/nibble/palette-bank metadata | rabbitpunch_bitmap.vhd | 2 logical + 9 + 8 + 2 + 4 | Future capture or drain before video restart | Pixel pipeline, no direct MAME saved state |
| Bitmap request address and pixel output registers | rabbitpunch_bitmap.vhd | 15 + 9 + 8 + 10 + opacity/valid strobes | Drain/flush before video restart | Pixel pipeline |
| Tile lookup FSM, queued descriptor, flags and RAM request | rabbitpunch_tile_lookup.vhd | 58 logical | Drain RAM and consume/drop queued row before capture | Derived tile pipeline; source VRAM and registers are saved separately |
| Tile row FSM, code/row/palette/X/Y metadata and planar ROM word | rabbitpunch_tile_row.vhd | Transport and row metadata | Drain ROM and finish/flush active row before capture | Derived tile pipeline |
| Sprite row FSM, latched code/row/position/palette/flips/priority, last ROM address and planar word | rabbitpunch_sprite_row.vhd | Transport and row metadata | Drain ROM and finish/flush active row before capture | Derived sprite pipeline; source RAM and registers are saved separately |
| Sprite scan FSM, line Y, current index, priority/palette bank and queued candidate metadata | rabbitpunch_sprite_scan.vhd | Transport and candidate metadata | Drain descriptor read and finish/flush queued candidate and drawer before capture | Derived line selection; no original-board list snapshot implemented |
| Sprite line FSM, clear cursor, active bank, bank validity/line tags, staged candidate, forwarding entry and view response | rabbitpunch_sprite_line.vhd | Derived line/pipeline state | Finish/flush and re-render before video restart; no complete save interface | Line buffering and hazard bypass, not game-visible source RAM |
| Sprite logical-line controller FSM, latched command, scan-finished flag and accepted draw index | rabbitpunch_sprites.vhd | Derived line-command state | Finish/flush whole renderer before capture and rebuild the line before output | Coordinates selector, row drawer and line storage; no PCB raster policy |
| Tile logical-line FSM, bank/window cursor, scroll/flags, issued/written counts, pending transport flags and view tags | rabbitpunch_tiles.vhd | Derived line state | Drain transport and rebuild both layer bytes before resuming output | Packed tile-line scheduling; no complete save interface |
| Video line FSM, command, completion flags and aligned pixel/tag registers | rabbitpunch_video.vhd | Derived line/pixel pipeline | Finish/flush and rebuild lines, suppress output until valid | Coordinates renderers and fixed-rate native bitmap read/mixing |
| Native bitmap/palette frontend metadata and valid stage | rabbitpunch_bitmap_pixel / rabbitpunch_palette_pixel | Derived coordinate/color stages | Flush on restore before accepting output | Fixed one-clock native RAM read contract; palette RGB wrapper passes six complete MAME scenes |

| RGB wrapper error-valid/coordinate delay | rabbitpunch_rgb_video.vhd | Derived pixel metadata | Flush on restore | Aligns invalid line tags with native palette latency |

| Held CPU write address/data/byte lanes | rabbitpunch_board_memory.vhd | 42 + shared target/FSM | Drain accepted write or capture pending fields | Preserved across video/CPU reset until a safe native RAM write slot |

## Chip state

| Chip | Module | Addressable? | Tier | Note |
|---|---|---|---|---|
| fx68k | rtl/cpu/fx68k, rabbitpunch_fx68k.vhd | No CPU register state port | CPU simulation integration | Adapter exposes descriptive bus pins; full CPU state capture remains open |
| T80 | rtl/cpu/t80, rabbitpunch_t80.vhd | No CPU register state port | Wrapper test | Descriptive unsigned interface tested; not connected to sound board |
| JTFRAME drawer | rtl/jtframe/jtframe_draw.v, rabbitpunch_tile_row.vhd | No state port | Tile-row simulation | Pixel shifter, counters and request state must finish/flush before restart |
| JTFRAME buffer evaluation copies | rtl/jtframe | Not integrated | Evaluation | Not part of the game state yet |

## Deliberately skipped

| What | Why it need not be saved |
|---|---|
| ROM image and layout constants | Recreated from the selected MRA; no writable ROM state |
| Address decoder | Combinational; derived from the CPU pins |
| Sprite entry arbitration and pixel mixer | Combinational; no stored state. Future line RAM must store occupancy/index/palette/foreground tag separately |

## Frame alignment

No save/restore interface exists yet. Proposed transport capture boundary is a paused
CPU with no outstanding request and an idle adapter; saving an in-flight transaction
would also require the backend's outstanding-response state. Video/frame alignment,
CPU register capture, RAM state arbitration and full savestates remain integration work.

RAM inspection is now implemented: choose a target code and local word address,
assert view enable, then sample data with view valid after the next rising edge.
Shorter banks use the low address bits. The port is read-only; restore must borrow
the CPU request port while paused/drained. No complete state transport/arbitration
exists yet. Simultaneous inspection of the exact byte being written has no promised
hardware value and must be avoided by future snapshot/video scheduling. CPU reset
does not clear any RAM or cancel an accepted ROM/memory request. Power-up RAM contents
are not assigned; comparisons must not rely on uninitialized bytes.

Board I/O initialization is separate from CPU reset. GGA registers can now be read
without borrowing the CPU bus; the boot bench pauses/drains before dumping all 24
video/GGA state fields. IRQ and sound state lack a complete save/restore protocol.
Input/DIP pins must be recorded with the future capture manifest.


## SDRAM transport adapter

rabbitpunch_sdram holds one accepted request per client, byte address, write
word/byte enables, toggle/ack phase, three captured response granules, and the
initialization wait state/counter. The imported controller owns open command,
refresh and burst-capture state. It remains independent of game reset. The
current capture boundary must drain all clients; no save/restore interface is
claimed. ROM contents remain recreated from the MRA rather than saved.


The read-only ROM requester also holds one pending/queued flag per client,
aligned burst addresses, byte-lane offsets and response registers. It has no
cache and no game-reset input; drain it together with the SDRAM adapter before
capturing state or restarting a transaction stream.


Optional last-burst ROM caches add three immutable eight-byte entries with full
aligned addresses, valid bits and per-client miss states/requested addresses.
A restore may invalidate these derived entries after draining transactions;
there is no need to save immutable ROM data. Never invalidate or change images
with pending cache/transport work. This state is independent of game reset.
