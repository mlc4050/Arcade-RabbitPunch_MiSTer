# RabbitPunch state inventory

What a savestate or a state dump has to carry, kept current as RTL lands (the skill's
`savestates.md`). "Skip" needs a reason: a ROM table from the `.mra`, or something re-derived
every frame.

## State access implemented on the savestate branch

The production source list now selects the complete VHDL state composition.
The Japanese 1500-frame run passes two SAVEs and four RESTOREs with the
production ABI/config identity, normal score profile, shared rotation DDR and
active sampled audio at both checkpoints. All six 1,548,288-clock continuations
match within their checkpoint groups. See
`reference/state_game_rabiolep_1500_production_shared_checks.json`.
The earlier US active-audio and cold-start results below qualify the same engine
with the US ROM. Full native whole-game timing, ARM/scaler/physical DDR runtime,
CRT and broader hardware coverage remain separate evidence boundaries.
Savestate save and restore work on MiSTer hardware with the October 20 release.

OSD and controller shortcuts share the selected slot, final-successful-save
autoincrement and recovery admission. The additional MRA action is joystick
bit15: hold SS with Down to save or Up to restore. That controller's game
actions are suppressed while SS is held. Native controller/OSD/recovery
regressions and production-shell source analysis pass; see
`reference/state_controls_joystick_ss_button_v1_checks.json` and
`reference/state_emu_sources_production_ss_button_v2_checks.json`.
Both production seed3 fits pass all project timing, hierarchy, memory and clock
checks at source snapshot `6ac4a1b`: instrumented setup/hold +0.310/+0.099 ns,
release +0.225/+0.112 ns. See
`reference/state_production_{stp,release}_seed3_synth_checks.json`.
The source identity audit also binds all 159 frozen game/transport inputs to
the production sources; see
`reference/state_production_game_source_identity_v1_checks.json`.

The receipt history below records each snapshot's own scope and limitations;
earlier integration notes do not override the current implementation above.

The 120-frame real Rabio Lepus diagnostic now passes two successive SAVEs and
two RESTOREs of each checkpoint. Each group reproduces all 1,548,288 observed
clocks exactly, including 162 main writes, visible pixels, sound writes and
cadence/IRQ observations. Both published images pass independent CRC/layout
and counter 1/2 checks. This is a silent NOTICE-screen checkpoint with no
observed STOP/HALT, not active-game/audio or full-shell qualification. See
`reference/state_game_rabiolep_transport_repeat_diagnostic_checks.json`.

The 850-frame US diagnostic also passes two SAVEs and four RESTOREs with
exact 1,548,288-clock continuation windows. Checkpoint 1 includes active sound
(901 distinct sampled PCM values), 2,097 main writes and 5,470 sound writes;
checkpoint 2 is silent before capture and remains exactly reproducible.
Both images have valid CRCs/counters, and both 115-byte high-score tables equal
the MAME reference. See
`reference/state_game_rpunch_850_checkpoint1_audio_checks.json`. This is an
explicit checkpoint-1 audio analysis of the original run; the rejected
all-checkpoints-active requirement is preserved separately. Japanese gameplay,
native whole-game event timing and full-shell execution remain unqualified.

The US cold-start test restores an admitted persisted external DDR slot after
fresh ROM loading. All three initial 1,548,288-clock traces equal the original
active-audio SAVE exactly. A new SAVE and two further restores also match;
the published counter advances from ARM's `FFFFFFFF` marker to zero.
See `reference/state_game_rpunch_arm_loaded_cold_v3_checks.json`. No internal
model state is deposited. This uses the prototype ABI and normal US high-score
profile; full-shell presentation/DDR and hardware remain separate gates.
The comparison checker also passes positive and wrong-checkpoint regressions in
`reference/state_cold_checker_real_trace_v2_checks.json`.

ARM file loading marks the external counter `FFFFFFFF` even for valid files.
The reader now treats zero length as empty and accepts that counter only
through the ordinary stable-control, exact-length and full private preflight
path. The native regression first reproduces the old rejection, then passes
valid, empty, changed-counter and corrupt-body loaded cases; see
`reference/state_arm_slot_sentinel_contract_checks.json` and
`reference/state_slot_reader_arm_sentinel_fixed_v2_checks.json`. The updated
cold seed models ARM's file length, zero fill and counter rewrite; its next
SAVE must publish counter0. The checker regression for that external sequence
is `reference/state_cold_checker_arm_loaded_trace_v1_checks.json`.

The prototype now normalizes the empty shared-ROM arbiter cursor and the
physical SDRAM refresh schedule before common release. A registered drain
ticket prevents an autonomous ROM request from feeding back into GO. These
policies carry no guest image bytes: accepted private read ownership is retained
through cancellation, and all normalization debt retires before release. Native
leaf/controller, release-feedback and connected private-return tests pass;
Japanese gameplay/audio continuation remains pending. See
[STATE_TRANSPORT_NORMALIZATION.md](STATE_TRANSPORT_NORMALIZATION.md).

The first complete real-ROM diagnostic at `bf28f0a` is rejected: after saving,
two restores agree with one another but differ from save continuation. It
executes both CPUs and produces visible pixels; its checkpoint is silent and
does not exercise STOP/HALT. The captured Z80 accumulator precedes a pending
`LD A,E` retirement. The state wrapper now executes that retirement edge without
offering the next fetch, then reloads its retired bank into the same clean
pipeline used for restore. The focused native regression reproduces the old
failure and passes three exact 256-clock continuations with the fix, including
cancellation during normalization. All IM0/1/2, HALT, prefix/EI and repeated
restore regressions also pass. See `reference/t80_retirement_canonical_cancel_checks.json`,
`reference/t80_capture_retired_checks.json` and
`reference/state_game_rabiolep_bf28_diagnostic_rejected.json`.
The corrected real-game rerun removes the extra writes but retains a timing
difference, prompting the transport work above. Corrected whole-game
active-game/audio continuation remains pending. The full-shell fit below
retains this changed wrapper and the transport normalization policy; earlier
isolated receipts describe their own pinned sources.

The experimental VHDL MiSTer boundary adds host-control state outside the game
image: two previous action levels, a pending operation ticket, operation type,
captured slot/auto flag, one status-feedback payload/pulse and its acknowledgment
ticket/source slot. It consumes
commands only when available and advances the selected slot only after final
successful SAVE publication. Reset abandons this UI ticket; no game-state
fields are inferred from it. The actual image service retains its independent
read/write ownership and reset-drain protocol. See
`reference/state_controls_delayed_host_ack_checks.json`. The actual unchanged
`hps_io` interface and the earlier host-controller snapshot pass a 48 MHz seed 3 fit and synthesized functional
protocol test, including 128-bit status request/ack and four slot increments
with wraparound; see `reference/state_host_{synth,netlist}_checks.json`.
ARM firmware, rendered OSD and full-shell/game integration remain unqualified.
The host now consumes the service's incomplete flag for restore-only readiness.
It rejects SAVE without opening a pending ticket in that state and keeps
RESTORE available, with separate menu masks. Failed/successful retry, held and
simultaneous actions, no deferred SAVE and no slot increment pass native tests;
the complete shell passes updated source analysis. See
`reference/state_controls_partial_incomplete_gate_fixed_v2_checks.json` and
`reference/state_emu_sources_incomplete_host_gate_v1_checks.json`.
This guard has not yet been included in an updated full-shell fit.
The corrected ARM-loaded-slot reader, optional VHDL debug probe and build
identity survive a complete instrumented fit with164 scoped timing checks,
setup +0.507 ns and hold +0.111 ns. See
`reference/state_emu_arm_loaded_synth_checks.json`. This does not qualify
cold-game restoration or physical DDR execution. The earlier debug-only
snapshot is retained in `reference/state_emu_debug_synth_checks.json`.
A successful increment blocks another action on the old slot until
the host acknowledges the changed selection.

The new presentation composition resets derived CRT history and invalidates
rotation publication/queue state during state flush while preserving accepted
DDR read ownership. The state-aware HDMI controller now passes both directions
with the qualified unchanged rotator/aspect netlists and a synthetic32x20
raster: actual complete-frame publication, midframe flush, mode hold across VS,
late accepted state read, held state write and fresh-frame republication. See
`reference/state_hdmi_presentation_netlists_v3_checks.json`. This remains separate
from a full-game/MiSTer presentation test. The prototype boundary stays outside the production
source list with state controls disabled.

The corrected short Japanese cold-start fixture now also passes through the
actual shared ROM/state/rotation DDR composition in both rotation directions. All three
initial traces equal the original SAVE; its new SAVE and repeated restores
match, with 527,574 rotation writes and observed complete-frame publication.
The new saved image equals the original second SAVE after excluding only the
outer counter. See
`reference/state_game_rabiolep_arm_loaded_shared_cw_fixed_v1_checks.json`.
The counterclockwise receipt is
`reference/state_game_rabiolep_arm_loaded_shared_ccw_fixed_v1_checks.json`.
This silent NOTICE checkpoint does not qualify gameplay, the complete
HPS/MiSTer runtime or hardware.

The experimental `rabbitpunch_state_machine` connects these surfaces to the
complete image service. Whole-game restoration and the MiSTer shell remain
unqualified; the gate list and evidence are in [SAVESTATES.md](SAVESTATES.md).

The new `rabbitpunch_state_service` composes private image RAM, snapshot,
slot reader, complete validator, ordered apply and publication. Four bounded
native VHDL groups pass with delayed synthetic machine/body/DDR endpoints:
full107216-byte restore, independent Python-zlib body CRC, repeated-save
counter, corrupt preflight before acquisition/write, partial-apply hold and
complete retry, canceled DDR debt and canceled snapshot-body debt/FAIL cleanup.
See `reference/state_service_group{1,2,3,4}_v1_checks.json`. Cancellation is an
event at child boundaries, allowing cleanup states to retire after their
accepted credits. The original unsigned-literal compile failure and two
wall-capped runs remain under their distinct `debug/ghdl/state_service_*`
directories; none is accepted qualification. Its registered 48 MHz seed3 fit
passes with 858240 image RAM bits, minimum setup +2.331 ns and hold +0.162 ns;
see `reference/state_service_synth_checks.json`. Actual machine whole-image
continuation, full-shell shared DDR and OSD remain gates.

The full logical-machine 48 MHz seed3 fit passes at `3a1ae2d`, retaining
1784608 block-memory bits: 907936 main board/CPU/video, 16384 sound RAM,
2048 NVRAM and 858240 private image. The four 19×16 capture MLABs are checked
separately. Both complete sound-state hierarchies and the service/bank/access/
ROM-identity modules survive. Minimum setup is +0.049 ns and hold +0.138 ns;
see `reference/state_machine_synth_checks.json`. Physical SDRAM pins use the
evaluation I/O delays; this excludes the MiSTer shell, PLL and PCB timing.

The complete MiSTer evaluation now fits at `bdac2b6`, using 22,934 ALMs and
2,303,968 block RAM bits. All 144 scoped timing checks pass: minimum setup
is +0.253 ns and hold +0.080 ns. The game clock is 46.666667 MHz and the
forwarded SDRAM phase is 5.357 ns. The logical machine retains all 1,784,608
block RAM bits, 1,216 capture MLAB bits and both complete sound-state surfaces.
See `reference/state_emu_synth_checks.json`. This is an offline fit with
evaluation controls enabled; physical DDR execution, ARM/UI behavior, CRT
and hardware savestate behavior remain unqualified. No hardware was operated.

The corrected 68000 adapter passes fractional-cadence capture/restore with both
SR2000 and SR2700. Three repeated restores reproduce 400 ordered writes and
1536 observable clocks each, with the guest cadence frozen/reloaded while a
separate free-running phase source executes the private return. STOP recapture,
an IRQ pending before private return, retained user pause and reset during a
65-clock backend debt also pass. See
`reference/state_maincpu_fractional{,_masked}_checks.json`.

With capture inactive, the corrected adapter at `7e7004f` also matches the
original core's complete cycle-stamped main/sound write traces for both real
ROM sets over two startup frames:14663/14688 main writes and9302 sound writes
for Rabio Lepus/Rabbit Punch respectively. Pixels and loaded SDRAM bytes match;
these startup frames are black, so this is not visible-game or active-restore
qualification. See `reference/state_main_game_{rabiolep,rpunch}_2_7e7004f_checks.json`.
The corrected CPU adapter passes a new isolated48MHz seed3 fit at `ff3049f`,
using39584 block RAM bits and four19x16 MLABs. All timing/coverage gates pass;
worst setup slack is +7.972ns. Exact source/project/report hashes are in
`reference/state_maincpu_synth_checks.json`.

The longer Rabio Lepus comparison also passes at `7e7004f`:93549462 system
clocks,93386 main writes,336258 sound writes and all429644 recorded write
timestamps/address/data rows match the original. The loaded SDRAM and62208
pixels match exactly, including5106 nonblack NOTICE-screen pixels. See
`reference/state_main_game_rabiolep_120_7e7004f_checks.json`. This still exercises
capture inactive; active whole-game restore remains pending.

The NVRAM controller/service now expose a default-inactive state lease. A
quiesce request prevents new whole-table operations, finishes an active one
and waits for announced host transfers before granting the lease. Reconciliation
keeps game RAM authoritative after both save continuation and restoration.
A captured readiness flag permits a new capture even when gameplay has changed
the initial guard bytes. An image captured before readiness instead rechecks
the MAME guards. Neither path injects an older cached file into restored RAM.
The last committed upload bank stays stable until a new capture completes.
Manual save during a lease waits for valid restored scores; an HPS download
announced while blocked retains its first-byte position when admitted.
Both pinned MAME table geometries pass the native VHDL gate with a delayed
byte backend and logical RAM model, including changed initialized guard bytes,
uninitialized guard retry and gameplay reset before a held host announcement.
See `reference/state_nvram_checks.json`.
The default full-platform regression also passes both sets with executing
68000, actual SDRAM/Intel RAM, config3/dump4,234 upload bytes, external-client
arbitration, OSD autosave, soft-reset restore and ROM-generation/DIP isolation.
See `reference/platform_hiscore_state_ports_sampled_interfaces_checks.json`.
The prototype connects this lease/reconciliation path to the state barrier;
whole-game NVRAM coexistence remains unqualified.

The body now assigns board bits352/353 to FM startup primed/valid and354
to captured NVRAM readiness. Reserved bits start at355. The corrected ADPCM
inventory measures189 bits rather than192; its six-word section retains24
bytes with three high padding bits. The generated model passes normal-mode
formal correspondence and native complete scan/three4096-clock restores;
its previous model and receipts are archived. The updated semantics pass34
complete bodies, including startup/readiness legality and corrected-chip tail
padding. Body/bank gates pass both full patterns with unknown discarded scan
bits; the complete image validator also passes. The corrected ADPCM wrapper
passes nine1024-clock continuations, pending commands, bank/start/reset loads
and reset during partial scan. See the `reference/*_corrected_189_checks.json`
receipts and
[ADPCM_STATE_REGENERATION.md](ADPCM_STATE_REGENERATION.md). Updated body
fields are now assigned, while the actual machine/backend composition still
needs whole-image game continuation; the complete image ABI remains provisional.

The corrected model also matches the corrected production audio baseline for
the complete real E4 cases on both sets and the nine-second Japanese command99
music case:187493/187493/562493 samples, exact raw PCM/WAV and every timed
sound write. This uses the pinned `fd3434b` sound frontend with only the189-bit
chip substituted. See `reference/state_sound_corrected_189_music_checks.json`.
It does not certify the newer upper state ports or active restoration.

`rabbitpunch_state_machine_backend` now connects the actual machine, coherent
access barrier and complete body banks. Its normal432×256/7 native gate passes
paired GX68000/T80 acquisition, actual main/sound RAM and selected CPU/board/
generated-chip reads, the independent zlib CRC of a DDR-loaded64-byte image,
and one drained private return at physical beam/phase alignment. Pixel cadence
and sync remain continuous through the16.83ms run. See
`reference/state_machine_backend_first_connected_initialized_checks.json`.
The first attempt rejected an undefined initial state-memory pulse; the dense
adapter now initializes request/response/error pulses to zero. The sound
boundary's strict assertions and imported sources are unchanged. Both attempts
retain exact inputs and native logs. Sound ROM is absent; architectural fields
not initialized by the synthetic program are not claimed defined. This gate
does not apply a full image or qualify actual game/audio/video restoration.
The full bank/body gate also passes after this initialization change, including
both complete patterns, padding, ordered commit and accepted debt handling:
`reference/state_banks_initialized_pulses_checks.json`.

`rabbitpunch_state_machine` also composes that backend with the image service,
edge-detected save/restore commands and separate loader/state DDR clients. Its
full interface is analyzed in the native gate; its whole-image execution is
not yet qualified. ROM identity observes accepted words after byte/DDR selection
and publishes only after the physical loader completes. A game reset preserves
that identity; cold transport initialization or a new download invalidates it.

Default-inactive state ports now propagate through system, platform, machine
and the PLL boundary. The optional machine selects independent physical main
phases during private return while guest cadence stays held. Presentation
readiness/renderer flush leaves physical sync running. The default path passes
the clocked-machine diagnostic through the installed PLL model and shifted
SDRAM clock: two DDR images, one byte image, rejected-image recovery, CPU input
reads, RAM inspection, pause/reload, OSD and preserved DIPs. It finishes before
the first vertical render; this is not active state release, complete video,
audio-waveform, fitted PLL or hardware qualification. See
`reference/clocked_machine_state_ports_pcm_settle_checks.json`.

Native startup exposed concurrent inactive-state assertions evaluating implicit
port-expression unknowns before elaboration deltas settled. The authored Z80,
FM and ADPCM boundaries now retain the same fatal interface checks at each
rising edge. The clocked diagnostic's PCM monitor samples1ns after an edge,
including the first PLL edge that initializes the mixer; all silence and
definedness checks remain enabled. Failed trials and the reset/PCM diagnostic
remain under their separate `debug/baselines` case directories.

The optional main-board path now composes the captured 68000 with the actual
shared bus owner, five physical RAM banks and I/O/IRQ registers. Native tests
snapshot/reload the complete16KiB work bank, exercise both byte lanes in every
bank and repeat three400-write/512-clock exact continuations with a masked
pending IRQ, preserved stack sentinel and retained user pause. The renderer is
held in reset during bank access; this gate has a synthetic program ROM and
does not qualify rendered video, combined sound or whole-game restoration.
See `reference/state_board_checks.json`. The default main CPU remains selected
unless `GBOOL_STATE_CAPABLE` is true.

The connected optional board also passes its isolated48MHz seed3 fit at
`0c41030`:3836 ALMs,4421 registers and907936 block RAM bits. The exact CPU
ROM/register-bank geometries and all five game RAM banks survive fitting;
all reported timing and coverage checks pass, with worst setup+5.965ns and
hold+0.114ns. See `reference/state_board_synth_checks.json`. This fits the
board state surface, not the complete machine, image store or MiSTer core.

The ROM subsystem now exposes a default-inactive drained cache flush. Its
native test uses the actual SDRAM controller/chip model and all five readers:
an accepted sample read is withdrawn, its debt drains, and both image epochs
clear/refill every cache without restarting the physical controller. Each
normalization produces exactly five fresh bursts; the warm repeat produces
none. See `reference/state_roms_checks.json`. The complete state coordinator
must perform this same normalization on save continuation and restoration.

The new `rabbitpunch_state_machine_access` barrier passes native protocol tests
with synthetic CPU/bank/transport endpoints. It pairs CPU acquisition after
NVRAM/legacy drain, freezes chips only after CPU debt retires, normalizes caches
at entry and private return, and releases on the actual single matching beam/
pixel-phase clock. Three partial-apply retries remain held until complete;
cancellation, acquisition/alignment timeouts and reset debt also pass. Captured
score readiness loads while held and reconciles before release. See
`reference/state_machine_access_checks.json`. It is not yet connected to the
actual complete machine/image service and has no FPGA qualification.

Legacy maintenance now blocks new external sessions during state acquisition
without blocking an already accepted whole score operation whose first byte
has not reached the arbiter yet. Native ownership/admission tests pass, and
the refreshed default full-platform NVRAM regression passes both sets. Passive
sound-bus-idle and combined maintenance-owner/byte-drain outputs reach the
machine boundary. See `reference/state_maintenance_clients_checks.json` and
`reference/platform_hiscore_state_maintenance_quiesce_checks.json`.

The initial cache-drain test alone did not qualify physical SDRAM refresh
phase. The later transport normalization gate explicitly covers all162 starting
refresh ages, all three read ports and exact256-clock continuations. The short
real-game checkpoint passes with that policy; active-game/audio continuation
remains a separate gate described at the start of this document.

`rabbitpunch_state_image_validator` now reads the complete sealed private image
through an acknowledged byte port and combines framing, both CRC checks and
body-field legality. It exposes no game-state write interface. Nine native
integration cases cover independently generated valid and CRC-valid illegal-SR
images, corrupt body data, wrong ROM identity, an unsealed image, delayed-read
cancel/reset debt, injected read failure and successful retry. The permission
output also tracks live ROM/config identity and sealing. This validates the
restore input; application to a complete running game remains unfinished.
See `reference/state_image_validator_checks.json`.

`rabbitpunch_state_apply` now sequences the validated private image into an
acknowledged body backend, then waits for a final register-commit acknowledgement.
It issues no writes without validated-image permission and a held machine.
Fifteen native protocol cases pass full ordered-body transfers, backpressure,
late read/write/commit replies, cancellation, reset, identity/hold loss and
backend errors including final commit failure. Once any write is accepted, incomplete-state hold persists
through failures until a complete retry or explicit full-game-reset completion.
Its test backend is synthetic; wiring the real RAM/register banks and complete
machine return/release remains unfinished. See `reference/state_apply_checks.json`.

`rabbitpunch_state_body` now maps the byte image to RAM, CPU registers, wide
board/T80 state and FM/ADPCM scan words. Every body byte passes capture, complete
ordered write and readback against two independently calculated patterns with
delayed RAM replies. Native tests verify canonical zero padding despite unknown
donor placeholders, all20 meaningful 68000 words,126 FM words,6 ADPCM words,
deferred simultaneous T80/board commit, rejected partial/out-of-order writes and
cancel/reset debt retirement. Register endpoints are synthetic; actual CPU/chip
endpoint composition still requires integration qualification.
See `reference/state_body_checks.json`.

The composed `rabbitpunch_state_banks` parent also passes the same full-body
exercise through the actual dense RAM adapter. Its physical RAM model independently
checks every main/sound address and big-endian byte lane. Accepted transactions
survive session loss and a one-clock reset through both real adapter layers,
including their late error reply. The lower session stays open until the upper
owner retires; canceling the lower adapter early would suppress its reply and
strand the upper debt. Physical RAM and register endpoints remain test models.
See `reference/state_banks_checks.json`; complete game continuation remains open.

An isolated `rabbitpunch_state_main_bus` now retains CPU/NVRAM/state reply
ownership through canceled access and reset. Nine native packets verify direct
CPU timing/priority, accepted NVRAM pulses after new admission closes, latched
state payloads, a state request arriving on the reset edge, late replies and
reset retention until state debt/session retirement. It wraps the actual shared
bus owner; the backend is synthetic. Board/NVRAM service-level admission and
whole-game integration are not connected yet. See `reference/state_main_bus_checks.json`.

`rabbitpunch_state_image_words` reads a validated sealed image into the slot
writer's little-endian64-bit stream. Native tests check all107280 bytes twice,
all13410 words, extended backpressure with stable output, read-debt ownership
through cancel/reset, permission loss, source error and successful retry.
Its source is a synthetic acknowledged image port in this gate; complete game
restore requires further qualification.
See `reference/state_image_words_checks.json`.

The composed `rabbitpunch_state_publish` also passes nine native cases through
the actual image-word stream and DDR slot writer. Every13410-word image is
checked in order, including all four slot addresses and repeated counter updates.
Publication invalidates the old slot before overwriting and accepts its final
counter only after the complete payload. Stalls, final-commit cancellation,
dual image/DDR read debt, reset, permission loss, source error and retry pass.
The image and DDR endpoints are test models; no host SD acknowledgement or
whole-game capture/restore is claimed. See `reference/state_publish_checks.json`.

The isolated 68000 adapter, two-pass snapshot serializer and complete optional
audio parent pass 48 MHz FPGA fits. Exact source, project and report hashes are
recorded in `reference/state_{maincpu,snapshot,audio}_synth_checks.json`.
These are isolated parent fits, not whole-core timing or hardware validation.

Five additional parent fits at commit `2e16e024da480820a4eceab81167263784087f0a`
pass the same48MHz seed3 hierarchy, memory, unconstrained-path and nonnegative
timing gates. Counts include registered evaluation boundaries; physical RAM
and the private image RAM have separate qualification.

| Parent | ALMs | Registers | Worst setup slack |
|---|---:|---:|---:|
| Complete image validator | 1397 | 1344 | +4.713ns |
| Ordered application | 102 | 134 | +11.068ns |
| Held banks/dense RAM adapter | 1663 | 2813 | +9.850ns |
| Complete image publication | 246 | 395 | +10.901ns |
| Optional guest/physical scanout timing | 314 | 539 | +11.028ns |

All five use zero inferred RAM. Exact committed and fitted source hashes,
project inputs and fitter-report hashes are in the corresponding
`reference/state_*_synth_checks.json` receipts. These establish isolated FPGA
fitness, not post-fit functional equivalence or complete-core closure.

| Surface | Fixed image layout |
|---|---|
| `rabbitpunch_state_memory` dense bytes | 0..65535 bitmap; 65536..69631 sprites; 69632..86015 tiles; 86016..88063 palette; 88064..104447 main work; 104448..106495 sound work |
| I/O bits 0..63 | 15..0 flags; 24..16 scroll0 Y; 33..25 scroll0 X; 42..34 scroll1 Y; 51..43 scroll1 X; 57..52 sprite count; 63..58 sprite priority |
| I/O bits 64..223 | 191..64 sixteen GGA bytes, lowest byte first; 195..192 selected index; 203..196 command; 204 pending; 205 twice-per-frame output; 223..206 reserved zero |
| IRQ bits 3..0 | enabled, first-event started, twice-per-frame, pending |
| Clock-enable bits 31..0 | 2..0 pixel phase; 8..3 main accumulator; 14..9 sound accumulator; 24..15 ADPCM accumulator; 25 sound half-rate phase; 31..26 reserved zero |
| Raster bits 17..0 | 8..0 horizontal; 17..9 vertical |
| GX CPU capture bank | D0..D7 in words 0..7; A0..A6 in 8..14; USP in 15; 16..17 donor placeholders; interrupted SSP minus 6 in 18; SR in 19; architectural PC in 20; format placeholder in 21; STOP flag in 22 |
| Isolated T80 capture | 229..0 pinned donor REG; 237..230 input-data latch; 255..238 reserved zero; clean fetch acquisition with prefix/EI guards |
| ADPCM wrapper | 1..0 pending-start state (idle 0, waiting 1, start 2); 2 bank; 3 control reset; 4 start readiness; 12..5 command; 15..13 reserved zero |

Sound chip wrappers now have default-original selection and inactive state ports.
The state-capable ADPCM path freezes wrapper state and masks outward ROM requests
during chip scan loading. Its pending WAITING/START snapshots and active playback
pass nine immediate 1024-clock continuations with complete chip-state reload.
The audio parent now propagates optional CPU, FM, ADPCM and sound-RAM state
ports through `GBOOL_STATE_CAPABLE` (default false). CPU acquisition drains
normal transactions before chip hold or RAM borrowing. RAM borrowing retains
the backend response contract and is confined to F800..FFFF. Pending command
wrapper state is included separately from the generated chip bits. Full
combined-audio normal-mode and save/restore qualification remains pending;
the machine-level coordinator does not select this path yet.

Sound-RAM replies now carry a latched owner across access-mode cancellation.
A short gameplay reset retains CPU reset until an accepted state reply and its
access session retire. A native VHDL protocol test runs the actual sound board,
state CPU and generated FM against a deliberately delayed backend architecture;
late read/write replies, held cancellation, reset debt, clean reboot and retained
user pause pass. This injection test does not qualify the production RAM itself.
See `reference/sound_state_owner_checks.json`. ADPCM also passes global reset
during an interrupted chip scan: global reset takes priority while ordinary
internal control reset remains masked during state loading.

The registered mono mixer now exposes default-inactive hold/load/read ports.
Its 16-bit output is part of board bytes42..43, preserving the first resumed
sample instead of inserting an unspecified settling sample. Independent integer
arithmetic checks (283137 vectors), three complementary state round trips,
changed-input holds, first/following resumed samples and reset priority pass.
See `reference/audio_mixer_state_checks.json`; complete-core timing is pending.

The isolated Z80 implementation passes directed IM0/1/2 continuation, HALT and
pending EI/IRQ checks. See [T80_STATE_CAPTURE.md](T80_STATE_CAPTURE.md) for
admission rules, evidence and remaining production qualification gates.

`rabbitpunch_capture_phase` is an isolated 68000 phase controller. While the
monitor waits on its private bank read, it observes two E falling edges and
then freezes at E-counter zero with phi1 next. A recurrence-model test passes
60 acquisition phases and 12000 resume clocks for both divider and fractional
enable configurations, including user-pause override/preservation. This tests
the phase contract, not full CPU hidden-state or private RTE/STOP behavior;
the standalone recurrence test is in
`reference/capture_phase_checks.json`.

The complete isolated `rabbitpunch_state_maincpu` adapter now joins CPU,
monitor, RAM-qualified stack undo, entry normalization and private return.
SR=2000 and SR=2700 native cases each pass 1536 exact resume bus/phase clocks,
1200 ordered writes, three STOP round trips, normal IRQ wake, capture while
user pause is asserted, retained pause after return, and reset with a 65-clock
backend read owed. It validates the journal against captured SSP-2 before
exposing hold. Cancellation never implicitly releases loaded state. The parent
must explicitly release the private return together with the saved machine
enable phases and normalize ROM caches on both save and restore. Evidence:
`reference/state_maincpu_checks.json` and `state_maincpu_masked_checks.json`.
The adapter and unchanged donor remain outside the production source profile;
complete game integration and timing are still pending.

The first real-ROM normal-mode comparison rejected commit `87560ad`: main-write
data retained its common prefix, but the candidate accumulated48253 extra clocks
over14380 writes. The normal undo path added a response register, and its phase
controller restarted phase on reset instead of matching the original wrapper.
Both are corrected: ordinary backend replies now reach the CPU's acknowledgement
edge directly, and phases continue through CPU reset while capture metadata clears.
The rejected sources and trace diagnosis are retained in
`reference/state_main_game_87560ad_timing_diagnosis.json` and the local archive.

Four native original-control comparisons now pass every request/packet/write,
IRQ and pause clock with no offset, using shared unchanged GX instruction cores,
both divider/fractional enables and two reset-duration pairs. The original
byte/readback, STOP, pause, variable-latency and autovector checks also pass.
Both SR2000/SR2700 repeated400-write/STOP/reset-debt continuation cases pass again
with the corrected adapters. See `reference/state_maincpu_compat_checks.json`,
`reference/state_maincpu_normal_compat_checks.json`,
`reference/state_maincpu_masked_normal_compat_checks.json` and the primitive
`reference/capture_*_normal_compat_checks.json` receipts. Real-ROM requalification
and a new CPU fit remain pending; older CPU fit receipts pin the earlier source.

The provisional six-section body layout is now centralized in
`rabbitpunch_state_layout`: RAM106496, M68K96, T8032, board64, FM504 and
ADPCM24 bytes. The read-only `rabbitpunch_state_semantics` checks register,
padding, interrupt-mode, cadence and beam constraints before application.
Twenty-eight native complete-body cases pass SR/PC/SSP, interrupt mode,
padding, cadence, beam and ADPCM wrapper bounds, valid edge values, abort,
length errors and retry. See `reference/state_semantics_checks.json`.
Connection to the machine service and FPGA timing remain pending.

Optional scanout timing now separates a held/loaded guest cadence and beam from
the continuously running physical raster. A release barrier compares beam and
pixel phase; the 68000 private return can use a separate continuously running
phase enable while guest timing remains held. The production default still
uses the original continuous game timing. Native checks use an independent
integer recurrence for every guest enable and IRQ event, compare actual native
scanout metadata every clock in both modes, and cover all seven pixel phases
with21 restored loads in compact geometry plus a full432x256 frame case with
three restored loads. Eight aligned releases each pass12000 continuation clocks.
The original default-mode regression also passes124416 synthetic RGB pixels,
deadline-underflow and readiness recovery. See `reference/state_game_timing_checks.json`
and `reference/state_scanout_default_checks.json`. The first full-size all-phase
fixture exceeded90 seconds and is preserved; it is not counted as a pass.
Whole-game renderer/cache normalization and machine-level release remain pending;
CRT hardware output remains untested.

I/O, IRQ, cadence and raster loaders act only while their state hold input is
asserted; initialization/reset takes priority. The caller must validate images
before loading: cadence and beam bounds are simulation assertions, not an
external image validator. Constant GGA bit-slice arithmetic is elaborated
indexing and introduces no multiplier. The read-only inputs/DIPs and live
controller metadata still need the enclosing snapshot's policy.

The isolated capture-stack undo adapter is maintenance transport. Before taking
the RAM image, its backend debt must be zero, undo must have completed, and the
journal must be invalid. Its retained journal address is checked against
captured SSP-2; the journal itself is not emulated CPU/RAM state to serialize.

The isolated ROM identity observer holds 62 logical bits: a 32-bit running CRC,
27-bit accepted-byte count, and active/valid/error flags. These belong to the ROM
load generation, independent of game reset. A valid CRC is compatibility metadata
for an image header; restoring a game must not rewind the loader or substitute
an older ROM identity. The observer remains outside production source lists.

The isolated shared-DDR arbiter holds ten logical transport bits: two owner
bits and an eight-bit remaining-response count. They survive initialization
until accepted read responses drain and are not serialized emulated state.
The parent must wait for read-idle and complete command ownership before
releasing a state operation or handing the port to a new loader generation.

The standalone RAM adapter requires exclusive main/sound backend ownership and
a fully drained boundary. Its session/accepted-main/accepted-sound/draining
states are transport debt, not bytes in the emulated RAM image. Canceling a
session never cancels an issued read/write; pause stays asserted until its reply
is consumed. Sound RAM restore is proved through the unchanged sound backend,
but no production sound-board mux connects that writer yet.

The tables below retain the production integration status. Existing RAM view
ports, sound chips and CPU wrappers still have their documented restrictions
until the new service is connected and qualified.

An isolated state-enabled BoogieWings JT51 donor additionally exports a 2820-bit
persistent vector. It reloads that vector exactly but fails the native nonzero
tone's 32768-clock observable continuation test, including after a 4096-clock
settling interval. Its operator/feedback/padding and accumulator state surfaces
are incomplete. It is deliberately excluded from production; the vector is
not the game's accepted FM-state format. See
`reference/fm_state_audit_checks.json` and SAVESTATES.md.

The newer generated-VHDL evaluation exports all 192 reachable JT7759 bits and
4016 mapped JT51 bits (six and 126 32-bit scan words respectively). It covers
operator/feedback/accumulator pipelines, controls, timers, FIFO and registered
enables rather than a hand-selected architectural subset. Normal-mode formal
correspondence and native all-bit scan/three-restore continuation pass for both.
Their isolated registered-boundary Quartus fits also pass at 48 MHz, with zero
RAM and nonnegative reported timing. These do not qualify whole-core integration.
See SOUND_STATE_NETLIST.md; none of these sources are in `files.qip`.

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

| Sound work RAM | rabbitpunch_sound_bus / rabbitpunch_ram8 | 8 x 2048 | 2048 | Yes; read-only view after drained sound CPU pause, restore writer not implemented |

## Baseline component inventory

The following inventory describes the original component interfaces and why
their storage matters. References below to future or missing state access apply
to that baseline, not the experimental state composition described above.
The state branch supplies coordinated RAM writers, architectural CPU capture,
direct board-register loads and complete generated sound-chip state. It drains
transport debt and rebuilds derived video state rather than serializing every
baseline pipeline register. Full-game continuation is still an open gate.

### Registers and FSMs

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


The connected ROM subsystem adds previous-loading and loader-ownership flags.
A load transition requires drained mapper/cache/controller transactions, and
invalidates derived ROM cache entries. Game reset must not touch these flags;
HPS download integration will hold gameplay reset while this path keeps running.


The logical rabbitpunch_board integration adds wiring only. CPU, I/O, IRQ,
renderer and shared native RAM retain the state and inspection restrictions
listed above. Cold initialization and CPU/video reset remain separate inputs;
CPU pause alone does not make video-owned inspection ports available.


Download control owns an image-valid flag, loading/error flags, acknowledged byte
count, latched pending word/address and transfer/drain FSM. This is load-time
state independent of CPU/video reset. Do not capture/restore during an active
image transfer; complete or reject and drain the image first. HPS/DDR staging
state is not implemented yet.


rabbitpunch_system adds no storage beyond its constituent blocks. Download reset
also initializes board I/O for a new image, while native RAM remains preserved.
Soft reset reaches CPU/video only; ROM loading/caches/controller remain live.


The JT51 evaluation copy owns FM register/shift storage, operator/envelope/phase
state, timers, LFO/noise and accumulators. Its current native interface has no
complete state capture/restore port. The VHDL adapter adds no state. Register
programming can be traced; full sound savestate capture remains unavailable.


The descriptive T80 adapter adds no state. Its enable directly controls CPU
advancement; software pause must first drain/retain external bus transactions.
T80 register/interrupt/machine-cycle state remains inside the unchanged CPU.
A complete sound CPU capture/restore interface is not implemented.


Sound CPU transaction adapter: styp_state tracks idle/waiting/completed/draining;
latched request address/data/write and read reply persist while CPU enables
stall. Pause drains an accepted response; reset drains before CPU restart.
No runtime state-load interface is added. The T80 DIR input is used by simulator
setup only to normalize the MAME comparison's initial CPU registers; no production
savestate support is claimed. JT51's internal state remains vendor-owned.


Native sound RAM contains 2048 bytes, exposed through the read-only sound-board
inspection address/data port only after o_paused. It has no reset clear or
restore writer. The sound bus owns an outstanding ROM address, YM write
address/data and transaction state; it deliberately remains live during CPU
reset/pause to finish the request owed by soundcpu. The main board remains the
owner of command byte/pending state. ADPCM strobes are not chip state or audio.


JT7759 is now an unchanged isolated evaluation component behind an unsigned
VHDL standalone wrapper. It has no production state capture/restore interface.
The native 17-bit ROM address and 9-bit raw signed PCM are exposed; bank and
board-control state are not implemented yet. Native/wrapped synthetic tests
exercise playback and reset, not savestates or game audio.


ADPCM board-control adapter owns one bank bit, physical reset state, latched
8-bit command, reset-release readiness and idle/waiting/start FSM. Its bank is
part of every exposed 18-bit sample ROM address. A future frontend must reject
stale responses after address/bank changes; no frontend cache or queue is added
by this adapter. No restore interface is implemented yet.


rabbitpunch_audio adds no storage: it connects sound_board's ADPCM strobes/data
to the sample controller. Program/sample transport, main command ownership and
PCM mixing remain external. Pause drains the sound CPU while both chips keep
running; this is a logical CPU-pause contract, not complete-system savestates.


Prepared read arbiter owns three pending credits, three latched 27-bit aligned
addresses, selected/active owner, round-robin next index and three returned
64-bit data registers. Idle means no backend request remains outstanding;
parent clients must also consume visible replies before image invalidation.
There is no reset cancellation or new RAM. The production ROM subsystem now uses it on physical port 2 beside the
loader ownership mux.


Audio ROM frontend state: independent program/sample request FSMs, burst byte
offsets, pending sample address and one returned sample byte/tag. Existing
burst-cache instances retain 16 bytes across game reset. Invalidate after both
clients and shared-read queue drain, before changing images. The sample output
valid compares the complete current banked address, so a stale pending reply
cannot escape after a bank change. No production reset cancels an accepted read.


The complete logical system connects the existing main command latch/pending
bit directly to audio's command input/IRQ and returns its read acknowledgment.
No second mailbox is added. System pause reports complete only when both CPU
adapters have drained; chip clock enables continue independently of CPU pause.
Sound native RAM has its own paused inspection port. Sound/sample caches retain
ROM data through a game reset and invalidate on drained image replacement.
Separate raw FM and sample PCM outputs remain available before final mixing.


Mono output adds a 16-bit registered PCM word and two FM warmup flags. Reset
clears the flags; the second Yamaha sample marker qualifies its contribution
after one complete accumulator period. Stopped chip enables cannot release the
warmup mask. Mixing adds no RAM or video buffering. No restore interface is added.


The load-time DDR wrapper adds one pending 16-bit stream word/address and a
previous-active flag. Native rom_loader owns the 64-bit granule, word index,
byte offset and copy FSM; ddram_phy owns one outstanding external read. These
are load-time transport state and must drain before ownership changes; neither
is reset by a gameplay soft reset. No additional RAM or gameplay DDR use is added.


The HPS-signal frontend owns its load-mode FSM, previous ROM-download flag,
seen-write/error/mode bits, byte count, one held low byte and one pending word.
Copy and direct-stream paths share one downstream ready/valid contract. A
framework reset only gates starting a pending DDR transaction; it does not
clear loader state or rearm a completed image. Errors remain latched until a
fresh ROM transaction, with accepted word/read debt drained before release.


Input state adds the downloaded 16-bit DIP word; only cold initialization clears
it. Inherited per-key latches/toggle state retain held keyboard actions. Manual
pause owns one latch and previous-button bit, separate from OSD/debug/state
pause levels. Game reset clears manual pause while preserving DIP metadata.
No full savestate restore path is added by these controls.


The logical platform adds no state. It joins host status/reset and the existing
controls, download frontend and complete system. The frontend now defers a
fresh image until the previous downstream loader drains; no generation queue
or clock domain is introduced. Physical HPS/DDR ownership and raster remain
external.


The output adapter owns five stages of enable/active/sync/blanking/accepted
metadata and coordinates, output RGB/control registers, and one sticky
underflow flag. Reset flushes all stages. They are ordinary registers (zero
RAM in Quartus), no line/frame pixel storage or additional clock domain.


The standalone maintenance adapter owns a one-request FSM, byte-lane selector
and held bus payload. Initialization drains outstanding memory debt before
releasing pause and suppresses its stale client response. It adds no RAM; the integrated system uses it through the shared bus owner.


The standalone bus owner adds one held packet/pending bit per requester and
one active-owner FSM. Its all-idle output includes offered requests as well
as pending/active debt; image replacement must consume that output when the
owner is integrated. No reset cancels ownership or an accepted memory request.


Maintenance is now connected through board/system/platform. Its pause joins
the main and sound adapters, and ready waits for both to drain. ROM generation
handoff also waits for all board-owner packets, including currently offered
requests. The idle CPU path bypasses packet storage; selected backend payload
is held for the reply. Reset clears I/O effects but acknowledges accepted I/O
so no owner debt is stranded. HPS persistence/restore orchestration now connects through the high-score service described below.


High-score persistence adds a 256-byte native dual-port RAM split into two
128-byte banks, the saved-bank selector/valid/dirty/notified flags, initialized
flag, pending OSD capture, byte index, download count/error, prior host flags,
startup/retry counter and acknowledged-access FSM. Only complete snapshots switch
banks. A game reset cancels partial work and keeps the last saved bank; a new ROM
or metadata generation invalidates it. The profile parser owns a 192-bit packet,
count/error/previous-active state and decoded profile/wait fields. Full savestate
support must preserve the selected set/generation alongside those flags, or drain
and rebuild persistence without mixing files from another game.

The maintenance-client arbiter owns a session FSM (idle/external/score) and one
accepted-byte pending bit. Client payload is held by the selected caller until
acceptance; no extra memory transaction queue is introduced. Drain the shared
helper/backend before taking a stable state. A canceled score client initializes
only its helper session; backend bus ownership still drains independently.


Native RAM configuration now uses zeroed physical M10K storage. Bitmap uses
constant FFFF XOR encoding to expose MAME's transparent-15 startup pixels;
other production word banks and byte RAM use zero. State view/maintenance APIs
return logical values and need no format change. A raw vendor-memory dump of
the bitmap must be decoded with FFFF. CPU/game reset does not clear these banks.
See RAM_POWERUP.md for startup scope and tests.


The provisional clock-enable generator adds a /7 pixel phase, modulo-35 main
and sound accumulators, a sound half-rate phase bit and modulo-875 ADPCM
accumulator. These advance on the system clock and are separate from user pause
and game reset. The raster adds two nine-bit beam counters; it has no pixel RAM.
The PLL/reset boundary adds three cold-initialization release registers. Its
asynchronous assertion covers PLL clock loss; game reset does not reset the PLL.

The scanline scheduler adds a t_state/styp_state request/render FSM, one held
render bank/Y, two ready-bank bits and eight-bit row tags, display bank/valid,
armed and sticky-underflow flags. It starts row zero during vertical blank and
prepares each following visible row in the spare bank. A handoff consumes the
ready tag before the next physical row. Late completion cannot switch banks
mid-line. Initialization must also reset/drain the connected renderer before
new requests; no extra line/frame pixel storage or full savestate interface is
added. These blocks are connected by the production continuous machine.

The continuous scanout wiring now connects the scheduler, beam and output adapter
with the platform in rabbitpunch_machine. It adds no pixel storage. Game readiness
loss clears scheduler ownership and sticky output diagnostics while beam counters,
sync and clock-enable phases continue. The main CPU's optional external-phase mode
stores its alternating phase only when enabled and not frozen; pause leaves the
shared fractional enable generator running. The legacy internal divider remains
available by default for independent logical tests. Full savestate capture must
include both the shared enable phases and the CPU adapter phase, or cold-restart
that timing boundary rather than independently restoring only one of them.

The instrumented revision adds read-only rabbitpunch_debug telemetry, separate
from emulated game state: seven saturating 32-bit counters, last main request,
last main write/data/byte mask, last sound request/data, sampled beam/status and
a registered 511-bit packet with core/build/layout identity. Counters have only
configuration-time initialization and survive gameplay/PLL reset. This telemetry
is not a savestate and is omitted from the release revision. See DEBUG.md.

Optional video presentation adds only unchanged framework line-buffer/filter
state after native scanout. It is not emulated board RAM. Native bypass has no
added pixel storage; optional modes rebuild their line history from the running
raster after reset/restore. Frame/pixel debug counters remain tied to native
scanout. No full-frame render buffer or game-clock domain is introduced.

HDMI sizing metadata adds two bits counting observed vertical-sync edges and
a previous-sync bit, plus unchanged framework arithmetic/geometry state. It
holds normal ratio metadata while geometry is first measured; no pixels or
emulated game state pass through it. It has no game-reset/pause dependence,
and uses the existing system clock with pixel enables.


The common viewport flip adapter adds three single-bit presentation registers:
applied orientation, outstanding render and outstanding pixel transaction.
Initialization clears them; game-not-ready clears transaction ownership and
selects the requested orientation while output is blanked. Once ready,
orientation changes only at a safe frame-prepare boundary, before the next
row-zero request. Requests accepted on the same edge as a previous completion
retain ownership. Restore must drain or reset this boundary together with the
renderer/scanout. No RGB, line or frame storage is added.


The optional connected CRT Adjust wrapper adds presentation-only size/position/
shift latches, a ten-bit read-rate accumulator, two sync-edge histories and
three one-bit row-blanking tags. The unchanged donor adds two 512x24 line banks
and horizontal/vertical sync history. Initialization resets wrapper state;
native Off bypass does not read any of that history. Optional adjusted output
must rebuild line/sync history after restore. This is not emulated board RAM
and is not connected to the production savestate surface.


The external status LED now has one configuration-initialized game-clock bit.
It registers loading/download/error/underflow indication only. It is not game
state and adds no renderer, CPU, audio or RGB latency; underlying debug flags
remain directly available. It need not be restored as part of a savestate.


The isolated HDMI write queue has a 512x101 presentation RAM plus a 101-bit
output packet, three nine-bit pointers/count and output-valid/overflow bits.
Initialization discards pending presentation writes and clears overflow; it
never clears game RAM. Derived framebuffer validity must be discarded and a
complete image recaptured after queue reset, overflow or ROM replacement.
The queue and rotation donor are now in the experimental production source
list behind the HDMI-only option; full-shell qualification is pending.


The isolated HDMI rotation adapter adds four configuration-initialized event
history/pending bits to serialize framebuffer advances. The publication guard
tracks the pixel count, source-frame slot, three valid-slot bits and capture/
bad-frame/edge history. It never holds game pixels. The rotation transport
combines that derived state with the existing 512x101 presentation queue;
loader priority is a combinational mux and does not cancel read responses.
Discard all presentation validity/queued writes after restore, overflow or ROM
replacement and recapture a complete image at a clean frame boundary. These
blocks are derived presentation state outside the game savestate surface.


The connected HDMI controller adds a two-bit applied mode, native sync history
and a one-cycle registered mode-change flush. Requests latch only at a clean
native sync boundary with the loader idle. None/direct video never inserts
storage into the analog pixel stream. Normal ratio metadata becomes 3:4 only
while rotation is applied; integer geometry is calculated against transposed
HDMI dimensions and transposed back. This is presentation state to discard on
restore, not original-board memory.
