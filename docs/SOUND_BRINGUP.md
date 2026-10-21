# Sound bring-up

The connected logical sound system includes T80, native 2 KiB sound RAM,
YM2151 and uPD7759 with board bank/reset/start controls. Program and sample ROMs
share SDRAM with the main CPU; the complete system connects command IRQ/read
acknowledgment and coordinated CPU pause. Directed playback, chip baselines,
synthesized-netlist diagnostics and implementation checks pass at the scopes
below. Active-playback image replacement exposed an ownership-idle race; its
fix passes directed and active-playback replacement regressions. Mono output is
connected with startup qualification; audible real-game sound remains open.

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
system wrapper now connects the complete audio instance and main command latch;
its end-to-end executing-CPU diagnostic passes
(reference/system_audio_checks.json); expanded implementation is pending.


Production ROM fit/netlist evidence: reference/roms_synth.json and
reference/roms_netlist_checks.json. The expanded subsystem uses 806 ALMs,
1878 registers, zero block RAM, worst setup +5.284 ns and hold +0.165 ns
at the 48 MHz evaluation constraint. All reported corners and six timing
coverage checks pass. This is not final PLL or PCB SDRAM timing.


## Mono PCM arithmetic

rabbitpunch_audio_mixer is a registered mono mixer connected to the system
output alongside its raw PCM buses. Pinned MAME rpunch.cpp routes each YM channel and the sample channel
to mono at 0.50 gain. JT7759's own raw logger expands its nine-bit sample by
seven bits. The mixer sums sign-extended raw bit patterns, halves the combined
sum and saturates to signed 16-bit range. Negative odd sums round down by one
LSB. All authored ports/intermediates remain unsigned. There is one system-clock
output register and no audio/frame buffer. audio_mixer_tb passes 283135 integer-
reference checks including every sample code across FM boundary combinations,
every FM code on each channel, cancellation and reset mute. This arithmetic
proof does not establish original-board analog gain or game waveform accuracy.


The expanded end-to-end diagnostic now checks four downloaded main programs,
explicit F400 bank/reset values, active-sample image replacement, recovery,
coordinated pause and mixed-output mute. Defined-bit assertions and absence of
mixer arithmetic warnings also pass. The loader ownership-idle fix excludes
currently offered requests, preventing acceptance and image invalidation on the
same edge. Disabled audio enables hold mono at zero through download and reset.


## ADPCM decoded-value reference

adpcm_decode_tb exercises the unchanged native nibble decoder. All 256
state/nibble combinations match the exact MAME 0.289 step/state tables while
the sample stays in nine-bit range. Balanced state walks reach every state
without clipping, so this compares actual native output values rather than
only checking nonzero playback. There are 2208 checked nibble updates including
walks and separate positive/negative native saturation sequences, plus enable
hold and reset checks. reference/adpcm_decode_checks.json pins the MAME source,
vectors and unchanged vendor source hashes. This does not compare full-chip
stream timing, resampling or game audio. MAME update_adpcm has no nine-bit sample
clamp; the reused decoder saturates. That difference is explicit in MAME_KLUDGES.md.

The final ROM idle fix also passes the refreshed standalone fit and functional
netlist tests: 810 ALMs, 1872 registers, zero block RAM, worst setup +6.144 ns
and hold +0.156 ns at 48 MHz. Final-wiring 32/8 main/sound boot smoke comparisons
pass for both sets (reference/system_boot_32_8_checks.json).


All 38 real bank-0 sample sequences now replay through the actual native nibble
decoder and match 237330 PCM values against a pinned-MAME-source block/repeat/
step model. Both sets have identical sample ROM bytes. There are no clipping
cases in those sequences; bank 1 is zero-filled/unpopulated. ROM-derived vectors
stay private under debug/. reference/adpcm_samples_checks.json records hashes,
per-command counts and the distinction from whole-chip timing or MAME-binary
waveform comparison. The final combined mono system also passes implementation:
6000 ALMs, 7176 registers, 927339 RAM bits, setup +2.775 ns / hold +0.089 ns.
The Quartus 17 output-port association restriction was resolved with internal
PCM nets; VHDL-2008 simulation acceptance alone had not caught that restriction.

## Native reset startup comparison

Both real sound ROMs now also pass without DIR register loading or RAM deposits.
For each set, all 4096 ordered write addresses and byte masks match MAME, all
215 peripheral data writes match, and 3877 RAM data writes match exactly. Four
early stack-save bytes are reported separately, not counted as exact data:

| Zero-based write index | Address | MAME | Native T80 | Source |
|---|---|---|---|---|
| 4 | FFFC | 00 | FF | PUSH AF at 081A (Japan)/0817 (US), reset-dependent flags after EX AF,AF' |
| 5 | FFFB | 00 | XX | PUSH BC at 081B (Japan)/0818 (US), B not initialized by the program yet |
| 13 | FFF8 | 28 | EC | PUSH AF at 0836 (Japan)/0833 (US), inherited flag bits after ADD HL,BC |
| 18 | FFF8 | 28 | EC | Same save in the second YM wait call |

This audit comes from local disassembly of the supplied pinned sound ROM. The
program then executes XOR A at 0013 and LD BC at 0014 before the RAM clear at
001E. That clear overwrites the temporary stack locations. XX is the simulator's
undefined byte, not a value hardware can store. No production reset circuitry or
vendor CPU source was changed to make these save bytes resemble MAME.

check_sound_board_boot.py --native-reset enforces exact address/mask ordering and
all other data, permitting differences only at those four indexed stack-save
locations. It reports their values explicitly. Four negative controls per set
reject changed peripheral data, ordinary RAM data, an address and a byte mask.
The existing normalized mode remains a strict full-write-prefix comparison.

reference/sound_board_native_reset_checks.json records a retrospective audit of
the completed source/log-hashed native runs. --reuse-existing requires their
unchanged HDL sources, ROM/log hashes, pass marker and original difference list;
it does not claim a fresh simulation. The test uses the production sound bus,
native configuration-initialized RAM and JT51, with a behavioral delayed ROM
transport at the legacy 48 MHz/4 MHz enable ratio. No main-game commands,
ADPCM playback, production SDRAM/PLL timing, long-run game audio or audible
hardware verification is established by this prefix.

The bootstrap audit covers both ROMs separately. Rabbit Punch's configure entry
is 085E and save routine 0817, three bytes before the Japanese 0861/081A entries;
the corresponding save/wait instruction blocks are byte-identical. The shared
0013/0014/001E initialization/clear path is also identical. Native exceptions
are locked to separate hashes of each ROM's first 0x867 bytes; changing that
code requires a fresh audit rather than silently retaining the exceptions.

## Framework audio-mix menu

The VHDL host boundary decodes status 124:123 as Mono/None/25%/50% and
exports framework mix codes 3/0/1/2. Zero status defaults to Mono. Native
signed PCM remains the same mono sample on both output channels; the option
selects the framework mix and does not add another game-audio pipeline.
The host fit and complete functional-netlist HPS regression pass, including
all four selections and preservation of unrelated status bits. Connected
CPU/SDRAM host and both-set high-score restore/autosave regressions also pass
against the new host netlist. See reference/host_audio_mix_synth.json,
host_netlist_checks.json, platform_host_checks.json and
platform_hiscore_host_checks.json. Full-shell qualification of the new menu
and audible physical output remain pending.


The connected audio-menu release 86c437a (seed 3) passes all 144 full-shell
timing checks, required hierarchy/MISTER_FB, the fitted clock tree and unchanged
pin-coverage gates. Minimum setup/hold are +0.139/+0.084 ns; utilization is
15263 ALMs, 25388 registers, 187 M10Ks, 35 DSPs and three PLLs. The selected
bitstream/source/timing artifacts are archived in the report's named worktree;
see reference/full_shell_hdmi_audio_release_checks.json. The instrumented 896da70 seed-2 implementation also passes all 164 checks,
with setup/hold +0.306/+0.078 ns; its exact archive is recorded in
reference/full_shell_hdmi_audio_debug_seed2_checks.json. No physical audio
playback is claimed.


## Supplemental fast startup qualification

Both sets now pass the fast T80/sound bus/JT51 startup against the existing native
ModelSim and MAME traces: 4096 ordered writes, all 215 peripheral values, and only
the already audited bootstrap stack positions permitted to differ. An executing
INI negative control proves the unsupported fast block-I/O flag path is fatal.
No vendor source was changed; no CPU state or sound-RAM deposit is used. See
TOOLCHAIN.md and reference/fast_sound_boot_archive.json for the conversion boundary,
rejected initial reset-assertion model and exact source/binary/trace archives.
This enables further bounded system simulation; it does not establish audible
output, commands, sample decoding or long game execution in the fast model.

## Keyed FM waveform cross-tool qualification

The native ModelSim and GHDL/Verilator paths now produce exactly the same 256
samples on all four JT51 PCM outputs (raw stereo and full-resolution stereo)
for an explicitly initialized, keyed four-carrier channel-zero tone. VHDL owns
register sequencing, production fractional enables, settling, sample strobes
and assertions. The native run checks known-valued, symmetric and nonzero PCM
and completes with zero errors/warnings. The fast C++ bridge only supplies the
clock and writes sample files. No chip RTL or production adapter was changed.

This qualifies nonzero waveform transport between the two simulation paths.
It does not establish MAME waveform equality, original-board analog gain, live
game music, resampling quality or physical audio. The separate long gameplay
runs remain pending. Reports: reference/fm_waveform_cross_tool_checks.json and
reference/fm_waveform_archive.json; private immutable exact-source/generated/
binary/native-PCM archive is in debug/fit_archive/fm_waveform_cross_tool.

## User pause output mute

The first hardware user reports a sustained note during pause. The sound CPU
stops issuing changes, while the YM2151 and ADPCM enable streams continue.
The system now forces the presented mono PCM output to signed zero for the
explicit pause request. Internal chip clocks, registers and raw diagnostic
PCM taps remain unchanged; unpause restores the current mixer output without
resetting the sound system. This also covers OSD pause when enabled. Brief
internal maintenance ownership alone does not assert this user-output mute.
Physical silence and transition quality require checking the rebuilt RBF.


## Executing-game music comparison

The preserved 1800-frame captures now have an independent offline comparison,
`reference/music_comparison_checks.json`, generated by
`scripts/compare_music_captures.py`. Every input trace/WAV is checked against its
original qualification hash; copies are retained under `debug/audio_reference/`
in the main checkout so this evidence survives worktree cleanup.

Both sets' gameplay YM register streams, starting at the final global register
clear, match the shorter recording in order after excluding register 0x14 timer
control: 1620 writes for Rabio Lepus and 1869 for Rabbit Punch. This includes
key-on, pitch and instrument writes. The raw divergence remains recorded: at
YM write 331 MAME writes 0x0A and RTL writes 0x2A to register 0x14. The extra
bit clears timer B status (`jt51_mmr.v`); it is not a changed note, but timer
behavior is still part of the remaining audit. US attract-mode ordering also
differs before the gameplay restart and is not claimed equal.

For a fixed 5.9-second gameplay excerpt, independently aligned to the first PCM
amplitude above 128 after 20 seconds, RMS ratios RTL/MAME are 1.01787 (Japan)
and 1.01806 (US), about +0.154/+0.155 dB. No capture clips at signed 16-bit limits.
Five-millisecond RMS envelope correlations are 0.887/0.881; mean short-time
spectral cosine is 0.931 for each. Linear resampling converts 62.5 kHz RTL to
48 kHz MAME; no gain correction, time stretch or optimized alignment is applied.
These metrics describe similarity, not percentage accuracy or a pass threshold.
The RTL tune begins 90.857/75.965 ms earlier in these bounded game runs; the
raster and main-game event timing differ, and the old RTL trace lacks per-write
timestamps. Do not interpret that offset alone as a YM tempo error.

No RTL change is justified by this excerpt alone. A longer controlled command
schedule and timestamped sound-only run will separate FM/timer behavior from
main-game/raster scheduling before any music fix is made.
