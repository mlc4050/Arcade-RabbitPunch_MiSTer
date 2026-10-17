# Sound bring-up

The logical sound board connects T80, the VHDL memory map, native 2 KiB sound
RAM and unchanged JT51. It passes command/interrupt diagnostics, full Quartus
implementation and a synthesized-netlist diagnostic. It is not connected to
rabbitpunch_system yet. Audio ROM transport remains external; uPD7759 playback,
sample banking, mixing, shared SDRAM scheduling and audible game sound remain open.

## Sound CPU and memory map

rabbitpunch_soundcpu presents one outstanding byte transaction. o_request is a
one-clock pulse; address/data/write are latched and every request owes one reply,
including writes. T80 advances on i_enable only when its active memory cycle is
complete. Refresh/interrupt acknowledge are not memory requests. Acknowledge
supplies FF for IM1; long backend replies stretch CPU execution through enables.
This is not proof of original-board instruction/bus timing.

i_pause stops new requests and drains an accepted reply before o_paused. A
completed read stays available on resume. Reset holds T80 reset until an old
response drains, preventing it from becoming a new opcode. The backend must
remain live during CPU reset/pause. soundcpu_tb checks RAM readback, peripheral
writes, 65-clock replies, pause mid-read, reset mid-read and replay. Evidence:
reference/soundcpu_checks.json. Its isolated fit passes at 48 MHz: 1109 ALMs,
zero RAM, worst setup +5.642 ns / hold +0.156 ns (soundcpu_synth.json).

rabbitpunch_sound_bus follows the pinned MAME map:

| Address | Behavior |
|---|---|
| 0000-EFFF | External audio ROM reads; writes ignored |
| F000 | YM address write; unused read returns FF |
| F001 | YM data write / status read |
| F200 | Command byte read and acknowledgement pulse |
| F400 | ADPCM control-byte strobe |
| F600 | ADPCM command-byte strobe |
| F800-FFFF | Native 2048-byte sound RAM |

Other reads return FF; other writes have no peripheral effect. YM read-offset
semantics were checked against mame0289:3rdparty/ymfm/src/ymfm_opm.cpp. Address/data
are held while waiting for the P1 half-chip enable, then JT51 receives exactly
one system-clock write pulse. Its register logic consumes writes on every
system clock, while busy status samples on cen_p1; both pulse width and phase
matter. The board's i_ym_half_enable supplies that write qualification.

ROM request/address hold until ready, followed by a separate response. Native
rabbitpunch_ram8 has explicit dual ports on i_clk and no RAM reset. Inspection
is read-only and permitted only after CPU pause drains; same-address CPU-write /
inspection collisions are forbidden. sound_bus_tb writes/checks all 2048 bytes
through CPU and inspection ports, exercises address boundaries, exact peripheral
strobes, 17-clock ROM backpressure and 53-clock replies. Evidence:
reference/sound_bus_checks.json. ADPCM strobes are not chip playback yet.

## Connected board verification

The main board remains owner of the command byte/pending flag. A sound read
acknowledges that latch. Z80 IRQ is YM IRQ OR command pending. All logic uses
i_clk with supplied enables; pause stops the CPU while JT51/ROM transport stay
live. PCM buses contain raw two's-complement bits despite their unsigned types.

sound_board_tb first writes YM register 14 and checks busy status through the
CPU. It then exercises two command interrupts, FF acknowledge, IM1 handler,
mailbox acknowledgement, native RAM storage/inspection, RETI and resume. During
each pause, at least two JT51 sample-marker periods continue without CPU writes.
This synthetic program initializes its own CPU state. Report:
reference/sound_board_checks.json.

The same behavior passes against the Quartus-generated sound_board_check
functional netlist, with no DUT RTL in that simulation. Its launch/capture
registers add evaluation-interface latency, accounted for by the inspection
stimulus. Report: reference/sound_board_netlist_checks.json. This is not an SDF
simulation; routed timing is checked separately. The protected DSP simulation
model emits port-width warnings; no keyed FM waveform has been verified.

The final logical sound-board implementation uses 2405 ALMs, 1755 registers,
11 RAM blocks, 19403 RAM bits and one DSP. All reported 48 MHz timing corners
pass: worst setup +2.621 ns / hold +0.105 ns, with six zero-issue clock/path
coverage categories. reference/sound_board_synth.json records the staged commit.
Registered logical boundaries and synthetic external timing are evaluation
constraints, not final PLL, board-pin or complete-core timing proof.

Its strict resource gate checks native sound RAM and seven inferred JT51 state
memories individually: 2048x8, 8x68, 4x21, 27x10, 28x2, 32x45, 3x15 and 29x20.
No chip state or pipeline was removed to meet the gate.

## MAME sound startup comparison

capture_sound_boot.py installs guarded taps before resetting MAME 0.289. Each
set's 4096-write prefix contains 3881 RAM writes, 107 YM address/data pairs and
one ADPCM control write. Neither prefix contains a main-CPU command or mailbox
read: these are initialization traces, not attract/game music. Source/ROM/trace
hashes are in reference/sound_boot_reference.json.

check_sound_boot.py compares T80/JT51 with a behavioral backend; all 4096 writes
match for both sets (sound_boot_checks.json). check_sound_board_boot.py repeats
that comparison through production sound decode and native RAM with periodic
53-clock external ROM replies. Both games pass all 4096 writes through the final single-pulse/P1/status-decode
RTL. The aggregate report is reference/sound_board_boot_checks.json.

These strict comparisons explicitly load captured MAME reset registers through
the vendor's existing DIR simulation input and seed fixture RAM with zeros.
MAME resets A=00/F=40; T80 resets A/F=FF and leaves register RAM uninitialized.
An initial unseeded Rabio Lepus run matched every peripheral write but differed
in four temporary stack bytes, one unknown. Normalizing the starting condition
avoids masking any write difference. Production CPU/RAM reset behavior is
unchanged. Ordered startup writes are not full boot, interrupt timing or PCM
waveform verification.

## Reused chip provenance and isolated tests

JT51 is unchanged from Arcade-JalecoMS1BCD_MiSTer commit
f16ec2b84c14409b5ae7b8ade761fffd7ec34b8e. Its exact upstream JT51 revision is
not recorded by that donor. Two simulation-only diagnostic helpers come from
the complete upstream checkout at 00dd3f935c8d73bbebe7a16c4af1c6f32ac742ed;
no chip versions are mixed. GPL-3.0-or-later, manifest/provenance under rtl/sound/jt51.
The native/wrapped chip baseline checks explicit channel mute, sample cadence,
timer A/B IRQ and clearing. Initial FM storage is not assumed silent. The full
B period is measured between overflows because its first overflow includes
free-running prescaler phase. Evidence: reference/ym2151_checks.json.

JT7759 is an unchanged evaluation copy from SNK68 commit
566133699ecd2ec2aa6897de6f0995ebefb60624 (GPL-3.0-or-later). Its exact upstream
revision is not recorded by the donor. Native ROM addressing is 17 bits and PCM
is signed 9 bits; the README's port table is stale. Manifest/provenance are
under rtl/sound/jt7759. The alternate SystemC2 controller holds DONE until reset,
so that candidate was not selected.

The imported JT7759 automatic test has reset/start and multi-sample fixture
limitations. Its original sources are retained; a simulator-controlled first
sample completes with an explicit idle assertion (jt7759_donor_checks.json).
Its failed automatic multi-sample transcript is retained in debug; it is not
reported as a passing retrigger proof. No vendor source was changed to pass it.

The separate VHDL native and rabbitpunch_upd7759 wrapper tests pass two different
complete synthetic commands, retriggering, 13-clock delayed ROM data, nonzero
PCM presence and reset mute at a nominal 48 MHz/75 = 640 kHz enable. Evidence:
reference/jt7759_checks.json. The ROM-valid response is qualified by request and
address. The descriptive wrapper exposes active-high start/busy and raw signed
PCM bits on unsigned ports. This is not a decoded-value/MAME waveform, bank
switching, shared SDRAM, Quartus implementation or audible game proof. The board adapter below now implements those control signals; the chip is
still separate from the logical sound board and shared ROM scheduler.


## Board sample control and banking

rabbitpunch_adpcm translates F400 bit 7 into active-low physical reset and bit 0
into the extra ROM bank. F600 latches the command before a one-clock start
pulse. A command immediately after reset release waits for the chip's first
control enable, so its edge cannot be lost while the native controller leaves
reset. Commands during asserted control reset are ignored. A command while
busy still reaches the chip, which owns whether that start is accepted.

The output is an 18-bit byte address within the 256 KiB sample region, formed
from bank plus the native 17-bit address. The external ROM frontend must qualify
valid data against that full current address; an old bank's pending response
must never assert valid for the new address. This module supplies no transport
queue/cache or shared SDRAM arbitration. PCM retains raw 9-bit signed encoding.

adpcm_tb passes three complete synthetic samples across both banks, immediate
commands after reset release, an ignored command during reset, and reset abort
after actual nonzero PCM decoding. ROM replies are delayed 23 system clocks
and address-qualified. Evidence: reference/adpcm_checks.json. These are board
control tests, not real game samples, PCM-value comparison or audio mixing.
Standalone ADPCM placement/routing passes all reported 48 MHz timing corners:
worst setup +11.312 ns / hold +0.134 ns, with zero block RAM/DSP inferred.
The unchanged decoder lookup implements in logic for this configuration.
reference/adpcm_synth.json pins the commit and six zero-issue coverage categories.
The same bank/reset/abort sequence passes the synthesized functional netlist
(adpcm_netlist_checks.json), without the DUT RTL in that simulation. Evaluation
boundary registers are accounted for; final external timing remains open.


## Connected audio subsystem

rabbitpunch_audio wires the logical sound board's F400/F600 strobes into the
ADPCM board adapter. T80, native RAM, JT51 and JT7759 now share i_clk; the caller
supplies CPU/YM/P1/640 kHz enables. Main-system command ownership stays outside.
Program ROM has the pulse/ready/reply transport; sample ROM uses current full
18-bit address-qualified valid data. No transport arbitration/cache or mixer
is added by this wrapper. FM and 9-bit sample PCM remain separate raw signed
bit patterns on unsigned buses.

audio_tb executes a synthetic Z80 interrupt handler that reads/acknowledges each
main command, stores it in native RAM, selects the sample bank through F400 and
starts sample 0 through F600. Both banks produce complete nonzero PCM playback.
CPU pause drains and permits RAM inspection while both sample playback and YM
sample cadence continue. YM busy status readback and IM1/RETI also pass. Both
ROM backends have delayed replies; this is not shared SDRAM or real game audio.
Evidence: reference/audio_checks.json. Combined logical-audio implementation passes all reported 48 MHz timing
corners with worst setup +2.371 ns / hold +0.105 ns. It preserves all eight
sound RAM geometries and 19403 RAM bits (reference/audio_synth.json). The
connected test also passes the synthesized functional netlist, without DUT
RTL in that simulation (reference/audio_netlist_checks.json).


## Sound ROM transport and shared controller diagnostic

rabbitpunch_audio_roms maps sound-program bytes at ROM_AUDIOCPU_BASE and sample
bytes at ROM_UPD_BASE through the existing burst cache, using two eight-byte
entries. Program requests use ready plus one reply pulse; sample valid is
qualified by the full current 18-bit address. A bank change during an outstanding
miss cannot expose its old bank's reply. Withdrawing a sample request drains
the old miss; an image change requires quiescent clients and explicit invalidation.
All eight byte lanes, region limits, simultaneous misses and invalidation pass
(reference/audio_roms_checks.json).

rabbitpunch_audio_rom_transport places those two cache clients beside a main
CPU burst client in rabbitpunch_read_arbiter. The resulting read port is intended
for the controller's physical port 2; sprite/tile ports remain separate and retain
priority. This transport adds no pixel or frame storage. Its standalone
48 MHz implementation passes all reported corners with worst setup +10.815 ns
and hold +0.160 ns, zero block RAM and no unconstrained paths
(reference/audio_rom_transport_synth.json).

audio_sdram_tb now runs the complete audio subsystem and transport through the
unchanged SDRAM controller and chip-command model. A directly preloaded synthetic
image contains the Z80 program and two sample banks. Continuous synthetic main
bursts share port 2; independently paced synthetic reads use high-priority ports
0/1. Both CPU-commanded sample banks play and pause/IRQ/YM checks pass, alongside
2511 checked main bursts and 696 checked priority bursts. Longest measured
program/sample byte replies are 50/30 system clocks (1.04/0.625 us at nominal
48 MHz). Evidence: reference/audio_sdram_checks.json. These traffic generators
are not the executing main CPU or captured video renderer and do not establish
worst-case video deadlines, real game audio or physical SDRAM timing. No ROM
loader is exercised in this directly preloaded diagnostic.


## Real sound startup through shared SDRAM

Both rabiolep and rpunch match all 4096 ordered sound-CPU writes from MAME 0.289
through the native sound board, audio ROM cache, shared read queue, unchanged
SDRAM controller and chip-command model (reference/sound_sdram_boot_checks.json).
The fixture seeds the captured MAME CPU registers and zero sound RAM after cold
SDRAM initialization; production reset behavior is unchanged. Actual ROM images
are directly preloaded. Competing main and priority reads are synthetic traffic.
ADPCM remains reset-held during this startup prefix, so this proves program-fetch
integration and startup register writes, not game music or sample playback.

The production rabbitpunch_roms now shares controller port 2 between main cache
misses, sound-program reads and banked sample reads. Sprite/tile ports 0/1 keep
priority. Loading owns port 2 exclusively and invalidates both main/video and
audio caches only after all clients drain. roms_tb checks concurrent reads from
all five clients, both sample banks, cached adjacent accesses, loader byte masks,
and replacement-image invalidation. Loader acknowledgments must never appear
as client replies. Download and main-only system regressions also pass. The
system wrapper still ties off audio until the complete audio instance is added.
