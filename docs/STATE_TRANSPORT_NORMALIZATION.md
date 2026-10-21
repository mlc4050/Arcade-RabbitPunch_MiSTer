# Transport state at game release

Immutable ROM bytes do not need an image section, but ROM access latency can
depend on unsaved transport history. A strict continuation test must account
for that history before releasing either CPU.

The corrected Z80 diagnostic at `67bb84c` still fails exact continuation. All
three windows have 5541 sound writes and identical release beam/IRQ/STOP/HALT
values; the first matching sound write occurs at clock915 after SAVE and939
after RESTORE. The earlier incorrect accumulator image has been fixed. The
remaining transport timing difference is not accepted as deterministic restore.

The experimental SDRAM phase wrapper uses ordinary read-only requests on the
shared ROM port after the existing return/drain/cache-flush barriers. The
controller and loaded image remain live. Requests repeat every128 system
clocks, with release gated by four observed128-clock refresh intervals and
the common raster edge. A shift/add projection of physical minus held guest
beam seeds the schedule before that edge, avoiding a mandatory extra frame.
The432×256×7 frame has6048 such periods. No controller
registers are forced, no vendor source changes and no reset is issued.

The wrapper owns each accepted dummy read until its reply retires, including
after cancellation. Private replies cannot reach the normal client. With
preparation inactive and no private debt, the normal interface is a direct
pass-through. ROM loading withdraws preparation and waits for old ownership.

The native controller/adapter/chip test passes163 initial-delay cases spanning
all162 observed refresh ages,1304 normal burst readbacks and16 cancellation
positions around completion. Ready/valid and RAS/CAS/WE timing match for256
clocks after each aligned release. Refresh chip-select parity is excluded:
it selects which chip is refreshed, without changing the controller's request
schedule. Both chips retain the existing alternating refresh policy. See
`reference/state_sdram_phase_eager_phase_checked_checks.json`. The beam
projection matches an independent integer oracle for compact and full raster
hold/load/release tests in `reference/state_game_timing_transport_phase_checks.json`.

The phase wrapper is connected to the prototype's final alignment state.
Native VHDL source analysis and the phase-inactive five-reader/cache regression
pass. The first connected attempt exceeded its old25ms return bound: starting
the schedule at one raster match could require a second match about33ms after
capture. That attempt remains rejected. Eager beam-phase seeding and a40ms
per-return bound pass the connected native test at `35ef7c8`: both actual CPUs,
selected native RAM/board/chip reads and private return finish at16.831801ms,
with physical pixel cadence and sync checked continuously. See
`reference/state_machine_backend_phase_eager_ticket_cursor_checks.json`.
This uses a synthetic64-byte main program and no sound ROM; complete image
apply and real-game continuation are separate gates. Active-game/audio
continuation and hardware behavior remain unqualified. The full MiSTer
evaluation passes scoped timing and state-preservation checks at `bdac2b6`;
see `reference/state_emu_synth_checks.json`. The corrected120-frame Rabio Lepus diagnostic passes two saves
and four restores exactly, including both independently validated images.
It is silent and has no observed STOP/HALT; see
`reference/state_game_rabiolep_transport_repeat_diagnostic_checks.json`.

The expanded native convergence test also passes simultaneous reads on all
three physical ports:1956 burst readbacks across163 starting-delay cases,
with every refresh age0..161 explicitly required. All three ready/valid signals
and RAS/CAS/WE match for256 clocks after release. The single-port regression
and16 cancellation positions pass with the stricter age assertions too. See
`reference/state_sdram_phase_three_ports_v1_checks.json` and
`reference/state_sdram_phase_exact_age_single_port_v1_checks.json`.

The seven-level bidirectional data path also passes a focused native/export
comparison in `reference/state_sdram_alias_deep_v3_checks.json`:256 ordinary
writes initialize512 bytes, then192 bursts use all three ports. Every
initialized ready/request/valid event, valid read word and meaningful physical
command matches after CRLF/LF normalization. Address/bank pins are excluded
only for NOP, refresh and burst termination; DQM/select/command timing remain
visible on every clock. The first two rejected attempts sampled undefined
idle address pins and remain preserved. This is a focused data-path proof,
not a whole-game event-monitor or full-shell qualification.

`scripts/admit_state_game_dq.py` binds this focused native/export trace,
the native full Japanese-image address coverage and an exact replay of the
seven-association graph audit to a frozen game export. It admits only the DQ
abstraction. CPU/event-monitor, active-game/audio and full-shell evidence are
independent. Exact receipt/recorder snapshots stay with the local admission.

The shared ROM arbiter now normalizes its cursor on explicit drained state
flushes. Normal loading/playback retains the original policy. Three seeded
cursor positions, simultaneous clients, stalls and variable replies pass;
normalization with pending requests is rejected. See
`reference/state_read_arbiter_normalized_v2_checks.json`. Cache invalidation
alone does not establish the same ordering for simultaneous clients.

Release uses a registered ticket for the held epoch's drained ownership.
Unholding an autonomous chip can create its next ROM request immediately;
feeding that new request back into the same combinational GO decision creates
a loop. The native regression reproduces that loop before the change and
passes afterward, alongside the baseline debt/reset/unsafe-retry tests. See
`reference/state_machine_access_release_feedback_fixed_checks.json` and
`reference/state_machine_access_release_ticket_baseline_checks.json`.
