# Savestates

Requested controls: Savestate slot (1..4), Autoincrement slot, Save state and
Restore state on the main OSD. The state machine composes capture,
image storage and restoration. Real-ROM diagnostics for both sets now
pass two saves and four restores exactly. The US test includes an active-audio
checkpoint; the Japanese 1500-frame scenario passes active audio at both
checkpoints with the production ABI/configuration and shared rotation DDR path.
The production VHDL composition enables these controls and passes native source
analysis and both instrumented/release physical fits. Savestate save and restore
work on MiSTer hardware. Broader ARM persistence and display-mode coverage
remain separate validation surfaces.
NVRAM is the separate persistent high-score block, not a running-game snapshot.

A controller shortcut is implemented alongside these OSD controls. The US,
Japanese and DDR-load MRAs append `Savestate (SS)` at joystick bit15 without
moving existing actions. Bind SS in MiSTer's controller setup; it has no default
assignment. Hold SS and press Down to save or Up to restore;
both use the OSD slot and autoincrement setting. The controller's game actions
are suppressed while SS is held. The default-disabled configuration and input
behavior remain unchanged. The native shortcut, partial-restore recovery and
complete OSD-control regressions pass in
`reference/state_controls_joystick_ss_button_v1_checks.json`,
`reference/state_controls_partial_ss_button_recovery_v1_checks.json` and
`reference/state_controls_ss_button_regression_v1_checks.json`.
Both production full-shell fits include the shortcut and recovery guard.

The production source snapshot `6ac4a1b` passes seed3 fits in separate fresh
worktrees, preserving the complete state/presentation hierarchy and expected
memory geometry:

| Revision | ALMs | Registers | Minimum setup | Minimum hold | Timing checks |
|---|---:|---:|---:|---:|---:|
| RabbitPunch_stp | 23,212 | 31,188 | +0.310 ns | +0.099 ns | 164 |
| RabbitPunch | 22,889 | 29,824 | +0.225 ns | +0.112 ns | 144 |

Both retain 2,303,968 block-memory bits, 292 RAM blocks, 34 DSP blocks and three
PLLs. The fitted game clock is 46.666667 MHz and the forwarded SDRAM phase is
5.357 ns. The instrumented build retains its debug probe; the release build
omits it. See `reference/state_production_stp_seed3_synth_checks.json` and
`reference/state_production_release_seed3_synth_checks.json` for source/artifact
hashes, state-memory checks and the inherited framework electrical timing gaps.
All 159 frozen game/transport inputs match the production sources after only
CRLF-to-LF normalization; see
`reference/state_production_game_source_identity_v1_checks.json`.

The Japanese run reproduces all 1,548,288 observed clocks in each of its six
windows, including CPU writes, pixels, interrupts and sampled PCM. Both
checkpoints have 2,074 nonzero PCM samples, with 1,279/1,122 distinct values.
Both images pass independent layout/CRC/counter checks and retain initialized
score flags. The shared DDR path accepts 93,731,982 rotation writes and publishes
a complete frame. See `reference/state_game_rabiolep_1500_production_shared_checks.json`.
STOP/HALT are covered by the focused native tests rather than this checkpoint;
the passive recorder is not a native whole-game event miter. ARM execution,
complete HPS/scaler/physical DDR runtime, CRT and hardware remain separate
qualification surfaces.

The source-list generator's `--production` mode selects the actual VHDL boundary
in `files.qip` and requires that boundary to enable state controls. Its default
continues generating only the offline evaluation. Build hierarchy and
state-memory preservation gates follow the selected source list.

The current branch has native-tested image validation, held-bank packing,
ordered application and a connected machine barrier, including accepted
transaction debt and incomplete-machine hold. The instrumented MiSTer evaluation
snapshot at `6dab351` passes its scoped physical fit with the ARM-loaded-slot correction and
debug probe:164 timing checks, setup +0.507 ns and hold +0.111 ns. See
`reference/state_emu_arm_loaded_synth_checks.json`.
Complete MiSTer runtime and ARM firmware/UI behavior remain open
gates. The earlier host-controller snapshot with unchanged `hps_io` passes an isolated fit and
synthesized protocol test; see `reference/state_host_{synth,netlist}_checks.json`.
The short real-game result and its coverage limits are recorded in
`reference/state_game_rabiolep_transport_repeat_diagnostic_checks.json`.
The US 850-frame test also reproduces every observed clock across both
checkpoints, including CPU writes, visible pixels, interrupts and PCM. Its
first checkpoint has 901 distinct sampled PCM values; its second is already
silent before capture. All six windows match within their groups, both images
pass CRC/layout checks, and both high-score tables match the MAME reference.
See `reference/state_game_rpunch_850_checkpoint1_audio_checks.json`. The original
requirement for active audio in both checkpoints remains recorded as a rejected
coverage result in `reference/state_game_rpunch_850_all_audio_rejected.json`;
the positive receipt is an explicit checkpoint-1 analysis of the same run.
See [STATE.md](STATE.md) for the implemented surfaces and evidence boundaries.

The cold-start diagnostic now accepts a previously published slot as external
DDR contents after a fresh machine/ROM load. VHDL issues the real restore,
validation, application and return commands; no internal state is deposited.
The seed admission binds the original image CRCs, continuation hashes, ROMs,
guest/transport sources, DIPs, score descriptor and held input level. The first
three cold continuations must match the original SAVE, followed by a new SAVE
and two further RESTOREs. The US cold-machine execution now passes: its first
three 1,548,288-clock traces equal the original active-audio SAVE exactly.
The new SAVE and two further restores also match, and the counter changes
from ARM's `FFFFFFFF` sentinel to zero. See
`reference/state_game_rpunch_arm_loaded_cold_v3_checks.json`. This uses the
prototype image identity with the normal US high-score profile; it does not
qualify physical DDR, ARM execution or the complete MiSTer presentation path.
The new SAVE is also byte-identical to the original run's second SAVE after
excluding only its outer publication counter; see
`reference/state_game_rpunch_arm_loaded_republication_v1_checks.json`.
The comparison checker separately passes same-checkpoint and wrong-checkpoint
regressions using explicitly synthetic cold-run metadata;
see `reference/state_cold_checker_real_trace_v2_checks.json`.

The ARM [slot persistence implementation](https://github.com/MiSTer-devel/Main_MiSTer/blob/master/user_io.cpp)
rewrites the outer change counter to `FFFFFFFF` after loading a saved file.
The earlier reader incorrectly treated this counter as empty. A native
regression reproduces that rejection; the corrected reader uses zero length
for emptiness and still requires the expected length, stable outer control,
complete private staging and CRC/identity preflight. A valid ARM-loaded image,
empty loaded slot, changing loaded counter and corrupt loaded body are covered
in `reference/state_slot_reader_arm_sentinel_fixed_v2_checks.json`.

The complete state-aware HDMI controller also passes a synthetic-raster test
around the qualified, unchanged rotator/aspect functional netlists. Both CW and
CCW publish a complete frame before a midframe state flush, retain accepted
state-read ownership during the flush, permit state writes while display is
held, and capture a fresh frame before republishing. Native/custom/integer and
direct-video controls remain checked. See
`reference/state_hdmi_presentation_netlists_v3_checks.json`. This is separate
from full-game presentation, the physical DDR controller and hardware testing.

The game fixture now has an optional shared-presentation mode. It connects
the real ROM loader, image service and rotator to the same three-client DDR
composition used by the state shell. Its external C++ model supplies ordinary
ROM/slot/rotation memory and delayed responses; VHDL retains all game commands.
The frozen CW fixture passes VHDL interface analysis in
`reference/state_game_fixture_sources_shared_cw_v1_checks.json`.
The first elaborated shared-bus run completes all six operation windows, and
its initial guest traces equal the original SAVE. It is rejected because no
rotation writes reached DDR; this does not qualify shared presentation. See
`reference/state_game_rabiolep_shared_cw_no_rotation_rejected.json`.
A fresh fixture adds passive presentation status to diagnose the missing
traffic; the corrected rerun is described below.

The status fixture narrows that rejection to an export mismatch: sampled
readiness is high and loading/flush clear during continuation, but the exported
applied rotation stays zero. A small constant-input regression reproduces it on the actual
presentation composition: native simulation writes 8,320 pixels and publishes,
while the old export writes none. Removing an unnecessary initializer from the
combinational requested-mode selector makes the raw export match native mode,
write count and publication exactly. See
`reference/state_presentation_constant_initialized_selector_rejected.json` and
`reference/state_presentation_constant_combinational_selector_fixed_v1_checks.json`.
This changes no state-image bytes or imported framework source.

The corrected clockwise shared-game rerun passes ordinary cold restore, a new
SAVE and repeated restores. Its first three 1,548,288-clock traces equal the
original Japanese SAVE exactly; its next group also matches internally.
The common DDR path accepts 527,574 rotation writes and publishes a complete
frame. The new image equals the original second SAVE byte-for-byte except for
the expected outer counter. See
`reference/state_game_rabiolep_arm_loaded_shared_cw_fixed_v1_checks.json` and
`reference/state_game_rabiolep_arm_loaded_shared_cw_republication_v1_checks.json`.
The counterclockwise run also passes all of these checks, with the same
527,574 writes and observed frame publication; see
`reference/state_game_rabiolep_arm_loaded_shared_ccw_fixed_v1_checks.json` and
`reference/state_game_rabiolep_arm_loaded_shared_ccw_fixed_v1_republication_checks.json`.
Both directions restore the same original image and reproduce its guest state.
These remain silent NOTICE checkpoints with prototype ABI/configuration;
Japanese gameplay/production identity and full HPS/MiSTer runtime remain
separate gates. The earlier shared failures stay preserved.

An optional post-restore input scenario is also prepared. It preserves the
three original cold continuations first, then sends ordinary coin/start/action
inputs and captures a new checkpoint after that script. Its new SAVE and two
restores must agree, but its image is intentionally not compared with the
original run's second SAVE because the controller inputs have changed.
This scenario passes VHDL source analysis in
`reference/state_game_fixture_sources_post_restore_us_v1_checks.json`, but has
not executed yet. All command sequencing remains VHDL;
the external recorder adds only passive player/service input observations.

The host controller now distinguishes a partial-apply hold from normal ready.
The service permits RESTORE retry in that condition but cannot accept SAVE;
the earlier host controller could issue SAVE and wait forever for completion.
The actual shell now carries the incomplete flag into command admission.
Save uses a separate availability mask, so Restore remains usable, and a
rejected held Save cannot become a deferred command after recovery.
The old interface fails a native regression; the corrected interface passes
held/simultaneous-action retry, failed/successful recovery and no-increment
checks, plus the complete existing controls suite. See
`reference/state_controls_partial_incomplete_rejected.json`,
`reference/state_controls_partial_incomplete_gate_fixed_v2_checks.json` and
`reference/state_controls_incomplete_gate_regression_v2_checks.json`.
This changes host control state only; image ABI `3A1B6DDE` is unchanged.
The complete VHDL shell also passes interface/source analysis with the new
connection and both menu masks in
`reference/state_emu_sources_incomplete_host_gate_v1_checks.json`.
The earlier isolated host fit predates this recovery guard. The production fits
above include the updated guard and controller shortcut.

The component sections below retain the limits of each historical receipt.
Their isolated passes do not inherit the later integration results, and their
earlier unfinished integration notes do not override the current status above.

The first complete Rabio Lepus diagnostic is rejected. Its two restores match
each other, but continuation differs from SAVE at clock915. The image contains
the accumulator from before a pending `LD A,E` retirement, changing a branch
after restore. The new capture wrapper retires the pending register update
without offering the next opcode fetch, then canonicalizes its pipeline through
the unchanged donor's state port. A focused native VHDL test fails on the old
wrapper and passes three exact 256-clock continuations with the fix, including
cancel during normalization. Existing IM0/IM1/IM2, HALT, prefix/EI and repeated
restore tests also pass. See `reference/t80_retirement_canonical_cancel_checks.json`
and `reference/t80_capture_retired_checks.json`. Active-game/audio continuation
remain pending; the latest full-shell fit retains the corrected wrapper and
transport policy. The latest provisional signature is generated in
`reference/state_abi.json`; it also binds the transport/release policy described
in [STATE_TRANSPORT_NORMALIZATION.md](STATE_TRANSPORT_NORMALIZATION.md).

## Local references inspected

- NMK16 commit 4c9b923a87dcefee27574a8a06361e47e8e9b963:
  rtl/savestate/ss_m68k_park.sv and ss_z80_park.sv use instruction-boundary
  interrupt/monitor overlays for the same fx68k and T80 families. The M68K helper
  uses level 7 and a register-dump stub; Z80 uses NMI and tracks interrupt mode.
  Its savestate.sv streams a flat state bus to four DDR slots; savestate_ui.sv
  connects slot selection, actions and completion/error notifications.
- KonamiGX commit 89124d4f29e1d3f95557e5e5265efcbe9d0d7cb4:
  rtl/cpu/gx_ss_m68k.sv redirects a forced exception and capture bank through
  the bus. docs/SAVESTATES.md documents fx68k entry ordering, STOP handling,
  stack side effects and raster-phase alignment. Its state sequencer/DDR
  client are examples of a sectioned format and consistent simulation files.

These are design references, not a claim that either drop-in works on this
board. Imported RTL must retain provenance and unchanged upstream interfaces
behind descriptive VHDL wrappers; new control/transport/test logic is VHDL.

Further local cross-checks include Jaleco MS1BCD's four-slot DDR control word
and freeze/release handshake, Namco System 2's fixed CPU phase and drained sound
queue, Seibu SPI's section-query bus, and System 11's VHDL state sequencer.
Rabbit Punch retains its independent implementation. In particular, sound
register replay alone cannot provide its required deterministic PCM continuation;
the complete FM and ADPCM running state is captured instead.

## Scope and implementation gates

1. Review STATE.md against current RTL. Writable board RAM totals 106496 bytes
   including sound RAM. Exclude read-only ROM; rebuild derived line/cache and
   optional HDMI framebuffer state. Include CPU architectural state, IRQ/GGA,
   sound command/pending, FM and ADPCM state or an explicitly documented audio
   restoration tier. No full composed-game framebuffer is required.
2. Prove both CPUs park/resume from normal execution, interrupt and stopped/halted
   paths. Account for exception/NMI stack writes and protect original stack RAM.
   No phase advance or accepted memory response may be discarded.
3. Generalize the acknowledged maintenance bus to all RAM banks and sound RAM
   restore, while draining shared SDRAM/renderer transactions. Snapshot latches
   and raster/clock-enable phase at a documented consistent boundary.
4. Define a versioned format with ROM/set identity, section sizes and integrity
   checks. Reject truncated, incompatible, empty or wrong-set states before
   mutating game RAM. Reserve four nonoverlapping DDR slots only after checking
   existing ROM-staging and rotation windows; add a real shared-DDR arbiter.
5. Add the OSD slot/actions and status feedback. Autoincrement advances only on
   successful save; failed saves and restores preserve the selected slot.
6. Test save/restore/save round trips, deterministic continuation, both ROM sets,
   partial/invalid files, timeout release, active audio and rotated/unrotated
   output. Full implementation and timing precede hardware mid-game testing.

Exact sound continuation uses the generated full-state VHDL path described
below. Its isolated native, formal and FPGA checks pass; integration into a
coherent whole-machine snapshot remains unfinished.

## Image construction and validation

The isolated `rabbitpunch_state_header` constructs the 64-byte board header
after the held body's CRC is known. It latches identity and section metadata,
rejects unknown ROM identity and invalid section totals/alignment, and computes
one header CRC byte per clock. Cancellation prevents delayed publication.
The parent must cancel on ROM replacement and publish the separate host
change-counter word only after all payload writes complete.

Three generated header/body streams pass the actual restore preflight validator
with stalls. The header matches an independent Python struct/zlib fixture;
tests also cover all 56 CRC cancellation edges, invalid inputs and successful
retry. Evidence: [state_header_checks.json](reference/state_header_checks.json).
This does not yet implement DDR publication or application to a running game.

The private `rabbitpunch_state_image_buffer` supplies an immutable source for
restore validation and application. Sequential fill must cover every byte
before sealing; a sealed image rejects writes until explicit replacement.
Its synchronous single-port RAM has no reset or initialization on data storage.
Three complete 107280-byte fills/reverse reads pass with stalls, attempted
sealed writes, invalid addresses, partial seals and session cancellation.
See [state_image_buffer_checks.json](reference/state_image_buffer_checks.json).
Sealing proves complete receipt, not CRC/identity/CPU-field validity. The parent
must run preflight on this copy and allow application only after validation.
This provisional size remains separate from a final integrated image ABI;
full-machine integration remains unqualified. The isolated 48 MHz fit uses
858240 RAM bits in 105 M10Ks and 117 ALMs, with worst setup slack +10.858 ns.
Header construction, corrected slot publication and restore staging also pass
isolated fits; all reported timing is nonnegative and unconstrained gates pass.

| Isolated state block | ALMs including test boundary | Worst setup slack | RAM bits |
|---|---:|---:|---:|
| Private image buffer | 117 | +10.858 ns | 858240 |
| Header builder | 733 | +7.330 ns | 0 |
| Slot writer | 200 | +11.065 ns | 0 |
| Slot reader | 159 | +10.661 ns | 0 |

Exact committed inputs and reports are pinned in
`reference/state_{image_buffer,header,slot_writer,slot_reader}_synth_checks.json`.
These block fits do not qualify a complete game core or physical DDR operation.

`rabbitpunch_state_snapshot` now joins held-body reads, header construction and
private staging. It reads the body for CRC, builds the header, then rereads the
held body into staging and verifies the CRC again before sealing. Thirteen
native cases cover exact independent zlib header/body bytes, source and image
stalls, changing body data, backend errors, persistent ROM identity changes,
lost machine hold, invalid sections, cancellation before hold, reset/cancel
with accepted read debt and successful retries. Cleanup precedes completion,
so an immediately following transaction cannot lose its staging begin to a
previous cancel pulse. See [state_snapshot_checks.json](reference/state_snapshot_checks.json).
Actual machine body banks, image semantic checks and full-game integration
remain unfinished.

## Initial CPU qualification

The isolated native fx68k/NMK16 helper test passes a register and 64 KiB RAM
round trip with 400 exact ordered continuation writes and separately checked
USP (m68k_state_checks.json). It uses an interrupt-enabled supervisor program.
The initial fully masked SR=2700 program did not enter the park monitor even
with the external level-7 request visible. That initial failure is resolved below; general CPU capture is still not fully qualified. STOP/normal pending IRQ and original
stack preservation still require dedicated tests. The helpers/wrapper are
quarantined outside files.qip and do not change the timed game core.

The strengthened 68000 loop now initializes and emits all D0-D7/A0-A6 values
through MOVEM, then compares 400 ordered writes after restoration. Z80 also
passes 400 exact writes with both register banks and repeated mode-1 ISR
activity; IRQ trigger phase is part of the bench snapshot, and actual ISR
writes are asserted. Exact sources/logs and the unresolved masked-case
waveform are preserved in reference/cpu_state_archive.json. Neither result
proves STOP/HALT preservation or an integrated game savestate.

## Masked-interrupt startup diagnosis

Both SR=2000 and SR=2700 now pass the native 400-write register/RAM
round trip without simulator forces. The old masked rejection remains archived.
An isolated diagnostic deposit on the donor's ipl_park output made the previously
failing case pass: that always @(*) output had stayed unknown before its
initialized input register first changed. Thus the CPU never saw a clean
inactive-to-level-7 transition. This was a helper startup issue in the native
simulation, not evidence that fx68k cannot take level 7 with SR=2700.
The descriptive wrapper now generates the same acknowledged level-7 request
in resettable VHDL, leaves the imported output unused, and preserves the donor
byte for byte. STOP handling, stack preservation and board integration remain
open; neither basic running-CPU test proves a complete game savestate.

## Isolated implementation and native qualification

The `codex/savestates` branch starts from develop `cf3be57` in a separate
`D:/git/RabbitPunch-savestates` worktree. Deferred GX evaluation sources were
copied into `.local/deferred-state-evaluation` without changing their original
location. Every imported source was checked against its retained SHA-256
manifest before reuse. The GX sources under `rtl/state/vendor/konamigx` remain
byte-identical and outside `files.qip`.

Implemented surfaces, connected in the experimental logical state machine;
the individual tests below do not qualify whole-game continuation:

- `rabbitpunch_state_memory` provides acknowledged byte reads/writes over a
  dense 106496-byte RAM image. It borrows the existing main and sound backend
  request ports; it adds no RAM or replacement memory model. A parent must own
  both muxes and assert `i_drained` only after CPUs, renderer, shared ROM and
  maintenance/persistence debt drain. Session removal or initialization retains
  pause and consumes outstanding replies without publishing a canceled reply.
  Illegal image addresses return an error without issuing a backend request.
- `rabbitpunch_io` exposes a 224-bit image, direct restore and hold. It preserves
  video flags, all scroll fields, sprite count/priority, every GGA byte, selected
  GGA index, sound command/pending and the IRQ-rate output. Restore does not
  emit sound-command, GGA-write or IRQ-configuration strobes.
- `rabbitpunch_irq` exposes all four bits, including the enabled/first-event
  history that pending IRQ alone cannot reconstruct. Hold blocks raster and
  acknowledge inputs; initialization has priority over restore.
- `rabbitpunch_clock_enables` and `rabbitpunch_raster` expose explicit phase/beam
  images and hold/load ports. Hold suppresses all six chip/pixel enables and
  raster event pulses. Existing instantiations omit these default-inactive
  ports and retain their running behavior. These are native simulation results,
  not a Quartus synthesis/timing qualification of state-enabled integration.
- `rabbitpunch_m68k_capture` and `rabbitpunch_state_fx68k` are descriptive VHDL
  wrappers around the unchanged GX banked-capture/STOP-aware CPU evaluation.
  The architectural bank has 23 32-bit entries; the donor records stopped PC
  past STOP and adjusts the RTE return to execute STOP again. It still writes
  PC-low to the game stack before interrupt acknowledgement. The separate
  transactional undo adapter below now preserves that word in native isolated
  tests; the production board does not yet route through this capture path.

Native tests and exact source/log hashes:

| Evidence | Result and scope |
|---|---|
| `reference/state_memory_checks.json` | Every byte of all six native RAM banks captured, perturbed, restored and checked; both lanes and every bank boundary included; main/sound cancellation debt drains; invalid addresses rejected |
| `reference/board_register_state_checks.json` | Eight register round trips, all GGA bytes/index, pending command, IRQ first-event and twice-per-frame continuation; no restore bus effects |
| `reference/timing_state_checks.json` | Eight restores and 160000 exact continuation cycles across all six enable outputs and beam state; frozen outputs stay inactive |
| `reference/m68k_capture_checks.json`, `reference/m68k_capture_masked_checks.json` | At initial SR=2000 and SR=2700: three 400-write continuations from one GX register/RAM image, three STOP recaptures/resumes and normal level-1 wake; original stack sentinel preserved, with undo journal checked against captured SSP-2 |
| `reference/m68k_state_checks.json`, `reference/m68k_state_masked_checks.json` | Original production-CPU/NMK16 evaluation now restores the same image three times, checking 1200 ordered writes at both initial SR values |
| `reference/z80_state_checks.json` | Original T80/NMK16 evaluation restores the same image three times, checking 1200 ordered writes including mode-1 ISR activity |
| `reference/raster_checks.json` | Existing default-port enable-ratio and compact/nominal raster regressions still pass |

Run `scripts/d_drive.ps1 scripts/run_board_state_tests.py`,
`scripts/d_drive.ps1 scripts/run_m68k_capture_tests.py`, and the existing
`run_cpu_state_tests.py` with `--cpu m68k`, `--cpu m68k --masked`, or `--cpu z80`.
Coordinate simulator ownership and check `hwlock.py --status` first.
Use `run_m68k_capture_tests.py --masked` for the new GX SR=2700 case.

## Remaining full-game gates

`rabbitpunch_capture_stack_undo` now provides a separate RAM transaction adapter
for the pre-IACK stack word. Capture-qualified writes first read their old word;
the level-7 acknowledgement restores the last completed write with its original
byte mask. Earlier ordinary game writes stay committed. It drains accepted
backend replies on cancellation and reports a missing journal instead of
issuing an invented undo. The isolated delayed-backend test passes five repeated
undos, both byte lanes, pass-through and canceled read/write debt; exact hashes
are in `reference/capture_stack_undo_checks.json`.

The GX native bench now routes its RAM accesses through this adapter. Both
initial SR values preserve a nonzero original stack sentinel through repeated
captures/restores and STOP recaptures. Every park checks undo completion and
the journal address against captured SSP-2. A separate old-word read precedes
each capture-entry RAM write; CPU acknowledgement follows the actual write.
The IACK-triggered undo completes while the monitor uses its own overlay bank.
The original no-undo test evidence is retained under
`debug/fit_archive/m68k_before_stack_undo` and in earlier branch commits.

Production integration must still qualify every possible stack RAM bank, avoid
speculative MMIO reads, wait for undo completion before RAM capture, and reject
an invalid/missing stack journal. These isolated passes do not connect either
CPU to a whole-machine controller or qualify a running-game snapshot.

A separate complete T80 primitive-state inventory was attempted through GHDL
without changing any imported source. The frontend rejects the existing
`ioq and x"7"` operand widths and reports inferred latches for `DO` and
`Alternate`. `reference/t80_state_inventory_rejected.json` records exact hashes
and diagnostics; no state count or CPU replacement is qualified. The existing
fast fixtures' explicitly trapped block-I/O substitution is intentionally not
used as evidence for complete CPU state. The native T80 remains unchanged.

`rabbitpunch_state_crc` supplies reflected IEEE CRC-32 byte/word updates for
image integrity metadata. `rabbitpunch_rom_identity` is a passive observer of
accepted raw-ROM words: a new download immediately invalidates the previous
identity, and an identity is published only after exact-length sequential data
and downstream commit confirmation. It handles a simultaneous final word and
completion, and rejects truncated, misordered, oversized or uncommitted streams.
The standalone test checks the standard `123456789` result, download byte order,
three repeated identities, ROM replacement and cold invalidation; hashes are in
`reference/rom_identity_checks.json`.

The observer now receives accepted raw words from the platform loader and feeds
image preflight in the experimental state machine. CRC is compatibility/
integrity metadata, not a cryptographic ROM identity. Loader generations remain
serialized and downstream commit is required before identity becomes valid.
Game reset preserves an already loaded ROM identity.

The isolated `rabbitpunch_state_ddr_arbiter` now retains tagged accepted read
debt across cancellation/initialization and prevents loader takeover until old
state responses drain. Loader ownership is exclusive; otherwise queued rotation
writes have priority and may proceed during a pending state read. The test
checks both response owners, physical BUSY, byte masks and canceled three/255
beat bursts (`reference/state_ddr_arbiter_checks.json`). Production rotation
transport still needs to be connected to this arbiter.

[SAVESTATE_HOST.md](SAVESTATE_HOST.md) records the four proposed 256 KiB DDR
slots at 0x3E000000, current window disjointness, standard host control word and
status/message interface. Slot reservation, integrity-checked board format,
host feedback and complete game-state sequencing remain integration work.

The standalone stream preflight now checks the 64-byte board header, exact
section sizes, ABI/ROM/configuration identity and independent header/body CRCs
before asserting valid. Twenty-one cases pass, including malformed lengths,
overflowing section fields, corruption, abort, late data and valid retry
(`reference/state_preflight_checks.json`). It has no machine-write interface.
Field-specific CPU/beam legality checks and two-pass immutable-source application
are still required; this helper alone does not qualify a game restore.

There is no complete game-state capture/restore service yet. The tested ports
and standalone RAM adapter do not freeze/restore the running machine by
themselves. In particular:

1. Connect both CPU capture engines, bus ownership, RAM access, board state and
   timing through a coherent drained boundary. Preserve the main CPU phase and
   restore IRQ gating only after monitor return finishes. Route the tested GX
   PC-low undo path through production RAM; solve NMK16 monitor stack effects.
   Z80 HALT, exact refresh-register
   behavior, pending NMI and interrupt modes beyond the existing mode-1 program
   remain unqualified.
2. Provide a real exact-state surface for JT51 and JT7759. Their unchanged
   public interfaces have no hidden-state export/load. Register replay cannot
   restore FM operator/envelope/phase/noise/timers, circulating shift storage or
   ADPCM decoder/control/buffer state. Disabling `cen` alone is not proof of a
   whole-chip freeze: registered enables and ungated processes also need an
   inventory. No approximate register-replay tier is accepted as full state.
   If resetting JT51 during a rebuild, its shift storage needs enabled clocks
   throughout reset (`jt51_sh.v`), not a reset with all enables stopped.
   A separately pinned state-enabled JT51 donor was found and tested; see the
   rejected continuation audit below. It does not close this gate.
3. Finish the versioned ROM/set-identified integrity-checked image, four DDR
   slots and shared DDR arbitration. Validate the entire image before changing
   game state; handle failed/partial loads without resuming corrupted state.
4. Flush derived renderer/scanout/rotation validity only after their accepted
   transactions drain, then rebuild valid lines/frames. Coordinate NVRAM and
   metadata generations instead of importing another set's persistence state.
5. Validate complete games for both sets, repeated save/restore/save, active
   sound, invalid/incompatible/empty images, bounded failures and rotated/native
   presentation, then complete Quartus synthesis/timing before hardware testing.

The four OSD controls remain withheld. When all gates pass, place Savestate
slot, Autoincrement slot, Save state and Restore state together after Save
NVRAM, with blank separators around the group and Reset last. Slot increment
must happen only after successful save completion.

## State-enabled JT51 donor: exact continuation rejected

The external [BoogieWings core](https://github.com/rmonic79/Arcade-BoogieWings_MiSTer)
at `84085e3d19be7c0a9b3238579ce99962b0b462e5` exports 2820 JT51 state bits.
All its JT51 Verilog files are imported byte-for-byte into
`rtl/state/vendor/boogiewings_jt51`, with provenance and hashes. The evaluation
wrapper `rabbitpunch_fm_state` is VHDL. Production sound sources and `files.qip`
do not use this donor.

`scripts/d_drive.ps1 scripts/run_fm_state_audit.py` completes a native test with
`accepted: false`; [the report](reference/fm_state_audit_checks.json) pins the
exact source and log hashes. The VHDL bench initializes every register,
explicitly loads both timer counters, keys a nonzero feedback tone, captures
the complete advertised vector and enable-divider phase, records 32768 clocks,
perturbs execution, then restores. The advertised vector itself reloads exactly.
The combined status/interrupt/sample-marker/four-PCM-output trace differs at
all 32768 clocks, including all 28672 clocks after the first 4096 clocks.
This establishes that the exported vector is insufficient for exact observable
continuation in this test. It does not attribute every difference to one module
or imply an audible judgment about the donor core.

Source inspection identifies missing state access on the operator, its feedback
and padding shift banks, and the output accumulator. Native elaboration also
reports forty missing-port warnings on ten `jt51_sh` instances without connected
state ports. These findings are consistent with incomplete state coverage;
they do not justify silently patching the vendor source or adopting it as an
exact-state implementation.

The initial fixture left eighteen stopped timer counter bits unknown: the
donor does not reset those counters. That failure and its exact VHDL source
are preserved under `debug/fit_archive/fm_state_uninitialized_timer_rejected`.
The final test initializes the counters through real YM timer-load edges;
there are no forced/deposited state bits and no donor changes. Reset has at
least 4096 system clocks of live enables so shift storage is initialized.

No state-enabled JT7759 donor has been qualified. Exact sound continuation
therefore remains a substantive implementation gate, alongside the CPU and
whole-machine integration gates above.

## Generated VHDL sound-state path

The actual dense RAM adapter now passes a native comparison against paired
production Intel RAM and renamed logical-model endpoints. All 106496 bytes
receive an initial-content check and two complete write/read patterns, with
both main byte lanes and delayed credits: 532480 transactions. An independent
Python pass checks every trace address, operation and read value. See
`reference/state_ram_native_clean_completion_v2_checks.json`. The earlier
comparison reached its full PASS marker but used an incorrect simulation
completion mode; it remains rejected and preserved in the maintenance tree.

Native SDRAM readback also passes every byte of the complete Rabio Lepus ROM:
1081344 normal writes and 270336 burst reads across all three clients, using
the production 5357 ps shifted clock and capture adjustment1. See
`reference/state_sdram_image_rabiolep_full_checks.json`. This tests the actual
controller/adapter and unchanged chip model, without memory deposits. It does
not independently qualify the full DDR loader or the deeper exported machine
hierarchy. Whole-game continuation remains a separate gate.

The controls now retain an acknowledgment ticket after requesting a slot
increment through `hps_io`. Save/restore actions stay unavailable until the
host writes back the changed slot, or selects a different slot. This prevents
a second action from silently reusing the old slot before the first update
arrives. The delayed acknowledgment and blocked second-save case pass in
`reference/state_controls_delayed_host_ack_checks.json`; the actual HPS netlist
test is prepared but has not yet run.

The complete logical `rabbitpunch_state_machine` passes its registered
virtual-I/O 48 MHz seed3 fit at `3a1ae2d`: 1784608 block RAM bits, 14101 ALMs
and 15993 registers, with minimum setup +0.049 ns and hold +0.138 ns.
The fitted FM/ADPCM hierarchies retain 4798/248 registers. All expected memory,
hierarchy, timing and unconstrained-path checks pass. See
`reference/state_machine_synth_checks.json`. This includes the actual CPU,
board video, sound, state banks and image service, but excludes the MiSTer
shell, physical PLL/SDRAM pin timing and game continuation qualification.

An experimental all-VHDL MiSTer composition is now available as
`rtl/state/rabbitpunch_state_emu{,_boundary}.vhd`. Its boundary preserves the
81 native framework pins for MISTER_FB without palette/dual SDRAM. Native
source analysis passes, including unchanged production RAM/PLL wrappers;
see `reference/state_emu_sources_native_separate_checks.json`. It is outside
the production source list and selects disabled state controls. The existing
MiSTer shell and framework sources are unchanged. CRT presentation resets its
derived history during state flush; the independent DDR owner stays live.
Actual HPS feedback, complete presentation, shell timing and hardware behavior
remain unqualified.

The separate control/configuration test passes all four slots and wraparound,
final-successful-save-only increment, failed save/restore, held buttons,
unavailable edges, reset and host slot/auto edits during transfer. Its enabled
configuration has the requested order/separators and Reset last; disabled
configuration is byte-for-byte the normal menu. See
`reference/state_controls_first_checks.json`. A changed slot or disabled
autoincrement during a save is preserved at completion. Host status feedback
copies the current 128-bit payload and changes only slot bits 6:5.

The ARM [menu action implementation](https://github.com/MiSTer-devel/Main_MiSTer/blob/master/menu.cpp)
drives both `T` and `R` actions high and then low; `R` also closes the menu.
The selected `T8`/`T9` entries therefore match the controls' rising-edge command
detectors. The action itself leaves the menu open; the separate ARM persistence
poll closes it when saving a changed slot. The same firmware reads and writes
all16 status bytes when acknowledging FPGA status feedback. These source
checks establish the pulse/status contract, not rendered UI or hardware execution.

`scripts/generate_state_abi.py` pins the provisional compatibility signature
to section sizes, CPU/board mapping sources and the exact 4016/189-bit chip
models. Its default command checks the generated package/manifest; `--write`
regenerates them. This is a compatibility guard, not functionality proof.
The signature remains provisional until complete game continuation passes.

`scripts/check_state_game_continuation.py` independently streams all three
diagnostic traces, reports the first unequal record and checks the complete
image's layout, ROM identity and both CRCs. It requires main/sound write events,
visible nonblack pixels and audio sample markers. An active-audio scenario must
also use `--require-active-audio`, which requires varying, nonzero sampled PCM.
STOP/HALT/IRQ counts describe the exercised checkpoint; they do not establish
coverage of unobserved interrupt or stopped-state cases. The checker always
labels its output diagnostic rather than awarding native or hardware proof.

The passing dense-RAM receipt is now bound to the frozen game diagnostic with
`scripts/admit_state_game_ram.py`: it checks every native source hash, the
complete trace/log and the exact entity-renaming transform for the logical
models. SDRAM export normalization and event-monitor admission remain separate.

The offline full-shell profile prepared by `scripts/create_state_emu_check.py`
passes its seed3 fit with state logic enabled: 22934 ALMs, 2303968 block RAM
bits, minimum setup +0.253 ns and hold +0.080 ns across144 scoped timing checks.
It retains production constraints, the complete state/presentation hierarchy,
logical-machine RAM, CPU ROM/register geometry and both full chip-state banks.
See `reference/state_emu_synth_checks.json` for exact source/report hashes and
excluded framework electrical paths. Production controls remain disabled.

The connected image service passes its isolated 48 MHz seed3 fit with 858240
block RAM bits, minimum setup slack +2.331 ns and minimum hold slack +0.162 ns.
See `reference/state_service_synth_checks.json`; this is a registered virtual-I/O
evaluation, not a full MiSTer fit or game continuation qualification.

The state presentation transport uses the real framebuffer publication guard
and pixel queue with three independent DDR clients. Its bounded test preserves
accepted state-read ownership across cancellation and presentation flush,
permits a complete retry while video is held, checks loader priority and delayed
response routing, and requires a fresh complete frame before publication.
See `reference/state_rotation_transport_shared_v1_checks.json`. The optional
HDMI composition is analyzed by that test but is not yet connected to the
production MiSTer shell. Presentation flush does not reset DDR ownership.

The complete image-service composition now passes four native protocol groups.
It owns the same private image through snapshot/copy, CRC/field validation and
apply/publication; accepted replies retain their original client through
cancellation. Save returns the machine before DDR publication. Restore validates
before acquisition and retains partial-apply hold through a complete retry.
See `reference/state_service_group{1,2,3,4}_v1_checks.json`. Endpoints are synthetic;
this does not qualify actual CPU/chip continuation, a fitted MiSTer core or OSD
controls. Later complete composition/fit results are recorded above; this
isolated service test alone does not establish them.

A separate implementation path now lowers the pristine production sound chips
to JSON and generates state-capable VHDL. All original imports remain unchanged.
The original mapped implementation exported192 JT7759 bits and4016 JT51 bits.
The corrected ADPCM controller now maps to189 bits; see
[ADPCM_STATE_REGENERATION.md](ADPCM_STATE_REGENERATION.md) for the new
native/formal receipts and archived prior model. Both original generated designs
pass normal-mode formal output/next-state/reset correspondence against the
pristine synthesis RTL with arbitrary corresponding current state and inputs.
The generated JT7759 also passes native nonzero playback comparison, complete
freeze/read/write, complementary writes to every state bit and three immediate
4096-clock continuation checks. The final generated JT51 passes 16256 matching
native clocks, all 4016 scan bits, nonzero feedback tone/timers/pending IRQ and
three immediate 4096-clock restores. Both canonical models are byte-identical
to their matching native/formal qualification inputs. Both original isolated48MHz
Quartus fits pass with zero RAM and nonnegative reported timing. Broader sound
corpus and whole-core integration/timing remain pending. The corrected189-bit
model has not inherited the earlier192-bit FPGA qualification.
See [SOUND_STATE_NETLIST.md](SOUND_STATE_NETLIST.md) for exact inventory, proof
boundaries, initialization policy, evidence and regeneration commands.

## Controller slot selection

Hold Savestate (SS) and press Left/Right to select the previous/next slot.
Selection wraps 1 to 4 in either direction. SS+Down saves and SS+Up restores.
The shared OSD selection is updated through the existing host status handshake.
Each press changes one slot; holding a direction does not repeat. Both players
can select slots, but SS and direction must come from the same controller.
Opposing Left/Right requests are ignored. Save/restore takes priority over a
simultaneous slot-change edge. Commands wait for the host's slot acknowledgment;
edges during a busy transfer or unavailable service are discarded, not queued.

All three state-control tests pass, including failed saves, autoincrement,
delayed host acknowledgment and partial-restore recovery. The savestate ABI
remains 3A1B6DDE. This changes host controls only, with no game/graphics/audio
state mapping changes. Physical controller verification uses the next RBF.
Receipts: reference/state_controls_joystick_slotselect_v2_checks.json,
reference/state_controls_slotselect_v2_checks.json and
reference/state_controls_partial_slotselect_v2_checks.json.

The slot-selection candidate is built from c39670f, release seed3. All144
required timing checks pass (minimum setup +0.178ns, hold +0.088ns), as do the
clock, hierarchy and state-resource checks. The private verified ZIP is
debug/bringup/RabbitPunch_slot_select_20261021.zip, with a dated RBF and both
sets' direct/DDR cheat MRAs. See reference/slot_select_release_seed3_checks.json.
The candidate retains ABI3A1B6DDE; controller operation on physical MiSTer
hardware is still a separate check. No ROMs, deployment or publication.

## Controller slot popup

Each accepted SS + Left/Right selection issues a native MiSTer popup showing
Savestate slot 1 through Savestate slot 4. It uses the unchanged hps_io info
request transport and a final I message table in the host configuration.
Message IDs 2 through 5 match the selected slot; IDs 6 through 9 identify
the slot being restored. Entry 1 is controller help.
Held chords produce one request. Busy, unavailable, opposing and cross-player
chords do not produce a popup. Accepted restore requests show Loading state 1 through Loading state 4.
Save and autoincrement do not emit a slot-selection popup. The existing status acknowledgment guard is retained.

The popup, command and partial-recovery VHDL tests pass:
reference/state_controls_joystick_loading_popup_v1_checks.json,
reference/state_controls_loading_popup_v1_checks.json and
reference/state_controls_partial_loading_popup_v1_checks.json. The Cheats/menu and
ROM-index isolation regression also passes in
reference/cheats_host_loading_popup_v1_checks.json. The state image ABI remains
3A1B6DDE. Physical popup rendering is pending the new candidate RBF.

Main's message lookup and polling implementation is in
https://github.com/MiSTer-devel/Main_MiSTer/blob/master/user_io.cpp
(show_core_info and UIO_INFO_GET). Existing local savestate_ui examples in
Arcade-JalecoMS1BCD_MiSTer and Arcade-SeibuSPI_MiSTer use the same interface.

