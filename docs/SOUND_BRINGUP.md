# Sound bring-up

The sound board is not integrated or audible yet. The main board's command
mailbox is implemented, and the T80 CPU donor has its earlier baseline. A new
active-high unsigned VHDL T80 adapter also passes opcode fetch, held WAIT,
memory/I/O writes, HALT and clock-enable stopping at a safe halted point.
Its raw enable is not a bus-draining pause handshake; the future sound board
must own that scheduling. reference/z80_wrapper_checks.json records the scope. This
checkpoint adds an unchanged JT51/YM2151 evaluation copy, descriptive unsigned
VHDL wrapper and an isolated chip baseline. uPD7759 and Z80 board/ROM scheduling
remain open.

## YM2151 donor and baseline

Selected chip RTL: Arcade-JalecoMS1BCD_MiSTer commit
f16ec2b84c14409b5ae7b8ade761fffd7ec34b8e, clean selected JT51 files.
Upstream is jotego/jt51, GPL-3.0-or-later. Its exact upstream JT51 revision is
not recorded by that donor. Dependency hashes and source paths are in
reference/vendor_manifest.json and rtl/sound/jt51/PROVENANCE.md. No donor RTL
is modified. Two SIMULATION-only diagnostic helpers come from the complete
local upstream JT51 checkout at 00dd3f935c8d73bbebe7a16c4af1c6f32ac742ed.
They are not synthesis dependencies or a mixed version of the sound chip.

The selected donor has no original regression suite. The older complete JT51
checkout has a top-level test using DAC ports absent from this selected copy;
its tests and chip interfaces must not be silently mixed. The new VHDL native
baseline runs before wrapper testing and states its limits explicitly.

run_ym2151_tests.py verifies native and wrapped interfaces using a 48 MHz
evaluation clock, 4 MHz chip enable and 2 MHz half-enable. Both enable inputs
advance the same clock domain. Measured sample-marker edges are 768 system
clocks apart (chip clock/64). Explicit channel mute/key-off programming produces
zero PCM. Do not assume FM parameter storage is initialized by reset alone.
Timer A/B status, IRQ assertion/clearing and a complete timer B period pass.
The first B overflow includes free-running prescaler phase, so its full period
is measured between consecutive overflows while load remains asserted.
Results: reference/ym2151_checks.json.

This is not a keyed-tone waveform, game-register trace, analog-level or by-ear
comparison. The sound CPU and MAME command traces must drive further verification
before game sound is claimed. The wrapper has descriptive chip select/write,
register/data selection, status and active-high interrupt ports. PCM outputs
use unsigned buses containing raw two's-complement bits, including separate
chip-quantized and full-resolution pairs; mixing must preserve that encoding.
The sample marker is forwarded unchanged and consumed synchronously, not as a
new clock. Peripheral CT pins are unused by the board adapter.

## uPD7759 candidate

Arcade-SystemC2_MiSTer commit acb146209bcbb58a7f2687c4b162b2ee9a3ff88c has
a clean selected JT7759 directory, not copied or validated here yet. Its current
README port table differs from the actual entry point: native ROM address is
17 bits and PCM output is signed 9 bits. Bind the HDL declaration, not that
stale table. Rabbit Punch's extra sample-ROM bank is outside the 128 KiB native
address window and needs board-specific VHDL handling. Reset/start polarity,
standalone mode, ROM latency and command timing must be checked against the
MAME driver/device and the actual donor before connection.

The sound ROM clients still need a verified path into shared SDRAM, with measured
impact on line deadlines. Do not add a frame buffer or silently increase clocks
to accommodate them.

## Executing sound CPU and MAME startup reference

rabbitpunch_soundcpu wraps the descriptive T80 adapter with one outstanding
memory transaction. o_request pulses for one i_clk; the backend owes exactly
one response, including writes. Address/write/data are latched. The CPU advances
only at i_enable when the active memory cycle has completed. Refresh and Z80
interrupt-acknowledge cycles are not memory requests; interrupt acknowledge
supplies FF for the board's Z80 interrupt convention. No new clock is generated.
Long backend replies stretch execution through clock enables; this is not proof
of original Z80 bus timing or of the final SDRAM bandwidth budget.

i_pause stops new transactions while an accepted reply drains, then o_paused
asserts. The held completed read remains available on resume. Reset holds the
CPU in reset until any old response drains, so it cannot become a new opcode.
The backend must remain live during pause/reset. Diagnostic soundcpu_tb uses
65-clock delayed replies, RAM readback, peripheral writes, pause mid-read,
reset mid-read and replay. Evidence: reference/soundcpu_checks.json.

capture_sound_boot.py installs MAME write/command taps before soft reset and
captures both audio ROMs' first 4096 ordered writes. Each prefix contains 3881
RAM writes, 107 YM2151 address/data pairs and one uPD control write; neither
contains a main-CPU command or mailbox read. This is sound-board initialization,
not an attract/game music capture. Lua subscriptions are retained globally and
callback faults are propagated to the runner. Hashes: reference/sound_boot_reference.json.

check_sound_boot.py executes the actual audio ROM using T80, actual JT51,
behavioral ROM/RAM/peripheral decoding and periodic 53-clock delayed replies.
Every one of 4096 writes matches MAME for each set. The simulation explicitly
loads MAME's captured reset register state through the vendor's existing DIR
state input after reset. It does not change the CPU's production reset behavior.
MAME resets A=00/F=40 and general registers to defined values; native T80 resets
A/F=FF and leaves its register RAM uninitialized. An initial unseeded Rabio
Lepus run matched all peripheral writes but differed in four temporary stack
bytes (one unknown). The strict seeded comparison normalizes that starting
condition instead of masking any write differences. RAM is also explicitly
zero-initialized in this behavioral fixture. Evidence: reference/sound_boot_checks.json.

The startup test does not contain production sound RAM, ROM arbitration,
uPD playback, main-board commands or final interrupt timing. JT51 keeps running
while the CPU waits/pauses. Its register initialization is exercised, but no
PCM waveform or audible game result is claimed. Native vendor sources remain
unchanged. The new staged soundcpu fit target checks the transaction adapter
and T80 only, with registered logical evaluation interfaces at 48 MHz.

The sound CPU implementation passes all reported 48 MHz timing corners with
zero block RAM, worst setup +5.642 ns and hold +0.156 ns.
reference/soundcpu_synth.json pins the staged commit and six zero-issue timing
coverage categories. This checks T80 and the transaction adapter; JT51 and the
future native sound RAM/backend are outside that fit.

## Native sound backend and logical sound board

rabbitpunch_sound_bus implements the pinned sound map: ROM 0000-EFFF,
YM2151 F000/F001, command read/ack F200, ADPCM control F400 and command F600,
and native 2 KiB RAM F800-FFFF. Unmapped reads return FF and unmapped/ROM
writes have no device effect. One request pulse receives one reply. ROM
request/address hold until ready, followed by a separate response. YM writes
hold until one chip enable; they are not repeated on subsequent enables.
The two ADPCM outputs are byte strobes for a future chip adapter, not playback.

rabbitpunch_ram8 uses explicit native M10K dual ports, both driven by i_clk.
RAM is not reset. The inspection port is read-only; sound_board permits it only
when the sound CPU has drained into pause. CPU writes and inspection must not
collide. sound_bus_tb initializes every byte by ordinary writes before checking
all 2048 CPU reads and all 2048 inspection reads; it also verifies peripheral
boundaries, exact strobes, 17-clock ROM backpressure and 53-clock response delay.
Evidence: reference/sound_bus_checks.json.

rabbitpunch_sound_board connects the transaction CPU, native backend and JT51.
The main board still owns the existing command latch/pending flag; command reads
return its byte and pulse its acknowledgement. Z80 IRQ is YM IRQ OR command
pending. CPU/half-chip/chip enables are supplied by the caller, all on i_clk.
Pause stops the CPU and drains its transaction while JT51 and ROM transport stay
live. PCM remains raw two's-complement in unsigned buses. No ADPCM sound is
mixed, and audio ROM transport is external; the main system does not instantiate
this board yet. The connected native-RAM two-game startup regression and the
full sound-board implementation target have been prepared; results are pending.
