# Whole-game state diagnostics

The production source composition enables the OSD controls and the additional
MRA SS modifier after both-set continuation and native host-control checks.
See [SAVESTATES.md](SAVESTATES.md) for current results and remaining hardware scope.
A diagnostic process finishing successfully
does not establish a functional savestate: compare complete continuation,
validate execution/audio/video coverage and retain the separate native/export,
full-shell timing and hardware evidence.

The VHDL fixture in `sim/state/state_machine_restore_eval.vhd` owns ROM loading,
checkpoint timing, two successive SAVEs and two RESTOREs per checkpoint. Its
C++ transport supplies only external clocks, DDR storage and observations. It loads the complete ROM
through the DUT's normal loader and SDRAM interface. It does not deposit CPU,
chip or SDRAM state. ROM images and frozen input bundles remain local.

`scripts/prepare_state_game_diagnostic.py` preserves a supplied frozen bundle
in a new directory. `--refresh-core` takes its core inputs from committed HEAD;
reference artifacts and ROMs remain pinned to the base bundle. Passive HALT/IRQ
observation ports are the only export-source additions. The manifest pins the
fixture, transport, core sources, ROMs and scenario parameters.

The execution stages are `scripts/run_state_game_diagnostic.py --phase prepare`,
`--phase export`, `scripts/normalize_state_game_dq.py`, `--phase build`, then
`--phase run --game rabiolep` or `rpunch`. Every command takes the same `--bundle`
and `--out` paths. Run Python tools through `scripts/d_drive.ps1`. Use a fresh
output directory for each export/build attempt. Respect the shared hardware
lock and serialize these jobs with the other compiler/simulator sessions.

Native dense RAM admission uses `scripts/admit_state_game_ram.py`. Missing DQ
or event-monitor admission permits only an explicit `--diagnostic` build/run,
whose result remains unqualified. Source and prepared-transform hashes are
rechecked before every execution stage. Tool timeouts retain partial output
and a rejected receipt. The transport writes `progress.txt` throughout execution.

`scripts/admit_state_game_dq.py` binds native/export data-path conformance and
the restricted DQ connection audit. After compilation,
`scripts/admit_state_game_monitor.py` checks a reviewed recorder/fixture version,
scenario generics, generated public output widths and post-clock sampling.
It permits only external input assignments and two passive HALT/IRQ additions.
This is a source/API recorder admission, not a native whole-game event miter;
its receipt sets `native_game_event_miter` to false. CPU/chip-model evidence,
actual continuation coverage, full-shell fit and hardware remain separate.

`scripts/check_state_game_continuation.py` compares every recorded clock,
main/sound write request and enabled pixel, checks the release endpoints and
independently validates both published image counters, CRCs and layout. Each
SAVE continuation is compared with its own two restores; different saved
checkpoints are allowed to differ. Inactive write lanes and inactive
RGB are excluded at observation time. An active-audio case must pass
`--require-active-audio`, including varying nonzero sampled PCM. STOP/HALT/IRQ
coverage is reported explicitly; a silent running checkpoint cannot qualify
active sound or stopped-state behavior.

The default 120-frame checkpoint is a short visible-game regression. Longer
prepared scenarios use `--checkpoint-frames`, `--dips` and optional `--gameplay`
with `--coin-frame`, `--start-frame` and `--action-frame`. The gameplay sequence
uses normal MiSTer pad bits for Coin, Start, Fire, Missile and movement. Its pad
level freezes at the checkpoint so all six continuation windows receive the
same external inputs. These new scenario variants are prepared, not yet run.
The US default DIP word is `0x2000`; the Japanese default is `0x0000`.

`--hiscore-profile rabiolep` or `rpunch` adds the corresponding committed MRA's
24-byte descriptor through normal file index 3 after ROM loading. Its polling
waits are unchanged. `--require-hiscore-ready` requires initialized and captured
scores before both SAVEs. The checker compares the saved readiness bit with
each release and records the table's RAM bytes independently; changed initial
guard bytes are allowed after initialization. These profile scenarios are
prepared, not yet executed. The runner rejects a descriptor for the other set.

The preserved `bf28f0a` Rabio Lepus diagnostic is rejected: both restores agree
with one another, but differ from save continuation. The pending `LD A,E`
retirement was absent from the saved accumulator. The focused native regression
and IM0/1/2 suite pass with the corrected wrapper at `67bb84c`; its full-game
rerun removes the extra writes but still differs in transport timing. Native
transport/release normalization and connected private-return tests now pass;
the short silent Rabio Lepus continuation now passes both save generations.
Active-game/audio and full integration remain pending. See
[STATE_TRANSPORT_NORMALIZATION.md](STATE_TRANSPORT_NORMALIZATION.md).
Earlier fit receipts remain evidence for their pinned sources.

`scripts/run_state_sdram_alias_tests.py --label <new-label>` prepares a separate
native/export comparison of the SDRAM data path. Its VHDL fixture uses six
transparent wrappers and the unchanged real adapter, controller and chip model,
then writes512 bytes and reads all three ports. Native VHDL and external-clock
C++ record the same initialized command and valid-data events. The export audit
permits only the seven transparent associations and shared top wire to change.
It passes at `reference/state_sdram_alias_deep_v3_checks.json`. Only CRLF/LF
newlines and protocol-unused idle address/bank pins are excluded; all valid
data and DQM/select/command timing remain checked. Its result is separate from
whole-game event-monitor and continuation evidence.
