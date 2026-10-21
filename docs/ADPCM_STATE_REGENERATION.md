# Corrected ADPCM state source

The audio branch qualified a VHDL standalone controller with a17-bit silence
counter. Its MAME duration is1024*(N+1); the earlier generated192-bit state
model still implements the imported controller's shorter silence interval.
The corrected controller is retained as the regeneration input. The optional
state path now uses its qualified generated model. The default playback path
uses `rabbitpunch_upd7759_playback`, the qualified `ea4c83e` production wrapper
with only its entity name and provenance comment changed.
The default/state wrapper selections pass13957 exact busy/ROM/address/PCM
clocks with throttled ROM, a2048-enable silence packet and a following nonzero
sample. First PCM is8897 clocks after the start pulse; an explicit lower bound
rejects the former short silence. Disabled state reads remain zero. See
`reference/upd7759_selection_corrected_default_lf_checks.json`, which retains
both production `develop/ea4c83e` and state `codex/savestates/f1a552d` identities.

`rtl/rabbitpunch_upd7759_control.vhd` comes from develop commit `ea4c83e`.
Its committed LF source hashes to
`b3fabe48db6731c86fda4a54e7d8b7ce212a71fccb83a0b258facf8af1ede454`.
Expanding only LF to CRLF reproduces the audio qualification source hash
`438055e81965378999d67ae07a55f1de60b457f176b1654ac333ca71bfcf8888`.
The controller logic has no other changes.

The copied exact-byte admission receipt is
`reference/state_adpcm_source_admission.json`. The all38 corrected-sample
comparison from develop `3c5776e` is
`reference/state_adpcm_all38_absolute_checks.json`. These qualify the audio
correction's source and sample timing, not state capture or FPGA fitness here.

Regeneration must preserve the imported JT7759 top, divider, FIFO and decoder.
Lower the corrected VHDL controller, translate its descriptive port names to
the original controller module's pins within the tool frontend, and inventory
the complete composed chip. Measure the resulting functional state count:
the four extra counter bits do not imply that total state is192+4, because
the controller FSM encoding can differ. Verification-only repeat monitoring
is outside game state.

Retain the previous canonical model and qualification artifacts. Generate a
candidate in a separate D-drive directory, prove normal-mode output/next-state/
reset correspondence, compare corrected real-sample playback, and repeat the
freeze/complementary-write/restore tests before promoting it. Update the body
padding, semantic validation, section lengths and provisional ABI from that
measured model; also pack the exposed FM-startup and NVRAM-readiness bits.
Complete parent/native continuation and FPGA checks before enabling OSD state
controls. The current state format remains provisional and the controls hidden.

`scripts/inventory_corrected_adpcm_state.py` prepares that independent inventory
in a fresh tagged directory. It retains the raw controller export, audits only
proven one-bit `Z ? scalar : X` identities, and rejects wider/unclassified
expressions. It never replaces unknowns with zero. Yosys performs the explicit
pin/module renames before composing the unchanged imported shell. The existing
state generator accepts its `inventory.json`; the normal-mode prover accepts
`--native-netlist` to bind the proof to this source JSON rather than the older
inventory.

The first corrected inventory measured189 functional bits in six32-bit words;
the last three bits are zero padding. Normal-mode formal output/next-state/
reset correspondence passes for arbitrary corresponding state and inputs.
The native test uses an independent copy of the `ea4c83e` VHDL production
wrapper, with only entity naming and a passive DRQ output added. It passes
nonzero synthetic playback against that reference, delayed ROM responses,
complementary writes to every189 bits and three4096-clock immediate restores.
See `reference/jt7759_corrected_ea4c83e_state_normal_proof.json` and
`reference/adpcm_corrected_ea4c83e_state_checks.json`.

The canonical candidate SHA256 is
`6fdc86fa46e21bd97109e1cafa221d0e31c04deb2c1af48d2e15be388be5c3a9`.
The previous canonical model and receipts are retained under
`debug/fit_archive/sound_before_word_group_promotion/jt7759/2d1600ca4d84`.
The section still occupies24 bytes; its bit ordering changed and is not
compatible with the earlier provisional model.

Corrected real-ROM normal-mode comparison also passes: both sets run E4
for187493 samples each, and Rabio Lepus command99 runs for562493 samples.
Complete raw PCM, WAV and every timed peripheral write match corrected
production exactly. The aggregate receipt is
`reference/state_sound_corrected_189_music_checks.json`; its exact bundle,
results, output audio and export audits are retained under
`debug/state_sound_corrected_189_music`. The test substitutes only this model
into the previously qualified `fd3434b` frontend. It does not qualify the
latest machine/barrier wiring, active whole-game continuation or FPGA timing.

The corrected chip's isolated48MHz seed3 fit now passes at `9e8d026` with zero
RAM,246 fitted core registers preserving the189-bit image, and all reported
timing/coverage checks nonnegative. Worst setup slack is+11.515ns. See
`reference/jt7759_state_synth_checks.json`. This is a chip fit; parent and
whole-core preservation/timing remain separate gates.

The corrected sound parent also passes its48MHz seed3 fit at `995de74`:
7032 ALMs,6101 registers and16384 sound RAM bits. Fitted chip hierarchies retain
4484 FM and251 ADPCM registers, above the4016/189 complete scan counts. All
timing/coverage gates pass, with worst setup+5.601ns and hold+0.108ns. See
`reference/state_audio_synth_checks.json`. This is not a whole-machine fit.
