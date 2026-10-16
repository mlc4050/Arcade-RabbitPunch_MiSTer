# RabbitPunch state inventory

What a savestate or a state dump has to carry, kept current as RTL lands (the skill's
`savestates.md`). "Skip" needs a reason: a ROM table from the `.mra`, or something re-derived
every frame.

## RAMs

| Region | RTL | Width x depth | Bytes | Save? |
|---|---|---|---|---|
| None in new board interfaces yet | decoder/bus/layout | N/A | 0 | No board RAM implemented |

## Registers and FSMs

| What | RTL | Bits | Save? | MAME `save_item` equivalent |
|---|---|---|---|---|
| Bus FSM: idle/waiting/complete/draining | rabbitpunch_bus.vhd | 2 logical | Future capture at drained/idle boundary | Transport, no direct MAME device counterpart |
| Latched request address/data/byte enables/write flag | rabbitpunch_bus.vhd | 43 | Future; can be discarded only at drained/idle boundary | Current 68000 bus access |
| CPU read-data holding register | rabbitpunch_bus.vhd | 16 | Future | Current 68000 bus access |
| Request pulse register | rabbitpunch_bus.vhd | 1 | Must be inactive at proposed capture boundary | Transport |
| CPU phase divider count and phase | rabbitpunch_maincpu.vhd | ceil(log2(PHASE_DIVIDER)) + 1 | Future, together with CPU | CPU clock phase |

## Chip state

| Chip | Module | Addressable? | Tier | Note |
|---|---|---|---|---|
| fx68k | rtl/cpu/fx68k, rabbitpunch_fx68k.vhd | No CPU register state port | CPU simulation integration | Adapter exposes descriptive bus pins; full CPU state capture remains open |
| T80/JTFRAME evaluation copies | rtl/cpu/t80, rtl/jtframe | Not integrated | Evaluation | Not part of the game state yet |

## Deliberately skipped

| What | Why it need not be saved |
|---|---|
| ROM image and layout constants | Recreated from the selected MRA; no writable ROM state |
| Address decoder | Combinational; derived from the CPU pins |

## Frame alignment

No save/restore interface exists yet. Proposed transport capture boundary is a paused
CPU with no outstanding request and an idle adapter; saving an in-flight transaction
would also require the backend's outstanding-response state. Video/frame alignment,
CPU register capture, RAM state ports and full savestates remain integration work.
