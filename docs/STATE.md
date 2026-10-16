# RabbitPunch state inventory

What a savestate or a state dump has to carry, kept current as RTL lands (the skill's
`savestates.md`). "Skip" needs a reason: a ROM table from the `.mra`, or something re-derived
every frame.

## RAMs

| Region | RTL | Width x depth | Bytes | Save? |
|---|---|---|---|---|
| Bitmap | rabbitpunch_memory / rabbitpunch_ram16 | 16 x 32768 | 65536 | Yes; read-only view port, restore through paused CPU request port |
| Sprites | rabbitpunch_memory / rabbitpunch_ram16 | 16 x 2048 | 4096 | Yes; same access paths |
| Tilemaps | rabbitpunch_memory / rabbitpunch_ram16 | 16 x 8192 | 16384 | Yes; same access paths |
| Palette | rabbitpunch_memory / rabbitpunch_ram16 | 16 x 1024 | 2048 | Yes; same access paths |
| Main work | rabbitpunch_memory / rabbitpunch_ram16 | 16 x 8192 | 16384 | Yes; same access paths |

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
| Inspection target, valid and per-bank read holding data | rabbitpunch_memory / rabbitpunch_ram16 | Derived pipeline state | Discard only when inspection idle | Debug/video port pipeline |
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
