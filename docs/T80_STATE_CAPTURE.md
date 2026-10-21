# Z80 instruction-boundary capture

`rabbitpunch_t80_capture` wraps an unchanged, pinned T80 with a 230-bit
register interface in the separate `state_t80` library. Production CPU selection
is unchanged. The donor includes WZ, alternate-bank selection and HALT state;
its DIR load normalizes execution to a fresh fetch. This is an architectural
boundary implementation, not arbitrary microcycle capture.

The 256-bit image contains donor REG bits 229..0 and the input-data latch in
237..230. Bits 255..238 must be zero. Acquisition waits for a drained bus,
inactive requests and a clean fetch. Accepted prefix bytes and EI require
additional admission guards: stopping between DD and its opcode loses prefix
state, and stopping immediately after EI loses its deferred interrupt effect.
NMI and BUSRQ remain inactive, matching this board. A parent must hold outward
interrupt inputs stable during acquisition and coordinate all other devices.

Capture cancellation clears pending acquisition without releasing an already
held CPU. Image writes require hold; only explicit resume or reset releases it.
The parent remains responsible for validating and restoring the complete image
and RAM before resume.

Native GHDL tests compare normal bus timing against the original T80se, then
check three 400-write continuations in each interrupt mode. They cover both
register banks, WZ, live I/R reads, R bit 7 and wrap, stack wrap, complementary
writes to all 238 used bits, cancellation, prefix admission, three exact
512-clock HALT continuations and interrupt wakes, and deferred EI with pending
IRQ. Results and source hashes are in
[t80_capture_checks.json](reference/t80_capture_checks.json).

Run with `scripts/d_drive.ps1 scripts/run_t80_capture_tests.py --ghdl PATH`.
The isolated 48 MHz Quartus fit passes with 1538 ALMs, 987 total registers,
zero RAM and worst setup slack +5.490 ns. All reported timing is nonnegative
and the unconstrained-path gate passes. The separate native real sound-ROM
startup comparison matches all 983 peripheral writes and 3743 PCM samples,
with the candidate hierarchy verified and original CPU absent. This first
60 ms is startup silence. Separate nine-second command-99 captures for both
games match all 562493 PCM samples and complete timestamped peripheral streams
against their original-core recordings. These qualify normal CPU behavior for
that passage, separately from state loading.
Receipts are [the fit](reference/t80_capture_synth_checks.json) and
[native startup](reference/state_t80_sound_native_active_high_checks.json).
Music receipts are
[Japan](reference/state_t80_music_rabiolep_cmd99_checks.json) and
[US](reference/state_t80_music_rpunch_cmd99_checks.json).
The production Z80/sound-CPU wrappers now expose default-inactive capture ports.
Both CPU selections pass delayed-response pause/reset regressions. The state
selection also captures HALT while user pause is asserted, reloads its image and
resumes three times while preserving pause and avoiding replayed writes. See
[soundcpu_state_paths_checks.json](reference/soundcpu_state_paths_checks.json).
These tests do not establish full ISA, NMI,
production audio or whole-game restore correctness. The inherited block-I/O
operand-width construct also prevents pristine GHDL synthesis; no vendor source
is silently patched to bypass that failure.
