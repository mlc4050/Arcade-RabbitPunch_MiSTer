# Full MiSTer state-engine evaluation

Generate this profile with `scripts/create_state_emu_check.py`, then commit its
inputs and run `scripts/build_staged.py --rev RabbitPunch_state_eval` through
`scripts/d_drive.ps1`.

`RabbitPunch_state_eval_stp` also enables the existing read-only debug probe.
The staged builder derives its VHDL debug enable and build ID from that
revision's `DEBUG_ISSP` setting and committed HEAD. Both evaluation profiles
keep the production menu unchanged.

The instrumented fit at `2a9c1e2` passes164 scoped timing checks with23,494
ALMs, minimum setup +0.457 ns and hold +0.088 ns; the probe and build identity
survive. Its snapshot precedes the ARM-loaded-slot reader correction. See
`docs/reference/state_emu_debug_synth_checks.json` for that exact scope.

The corrected ARM-loaded-slot reader also passes the instrumented fit at
`6dab351`:23,266 ALMs,2,303,968 block RAM bits,164 scoped timing checks,
minimum setup +0.507 ns and hold +0.111 ns. See
`docs/reference/state_emu_arm_loaded_synth_checks.json`. Physical DDR and
cold-game execution remain separate gates.

The fit at `bdac2b6` passes all 144 scoped timing checks with 22,934 ALMs and
2,303,968 block RAM bits. Minimum setup is +0.253 ns and hold +0.080 ns.
The game PLL runs at 46.666667 MHz with a 5.357 ns SDRAM phase. See
`docs/reference/state_emu_synth_checks.json` for source and report hashes.

It uses the unchanged framework and production physical constraints. The
evaluation boundary differs from the disabled experimental boundary only by
enabling the state engine for synthesis. Production `files.qip`, the release
revision and its menu remain unchanged. Do not deploy this evaluation revision.

The build requires the complete state/presentation hierarchy, all 1784608
logical-machine block RAM bits, the four 19×16 capture MLABs, both CPU ROM
geometries and at least 4016/189 FM/ADPCM registers. It also applies the existing
timing, framework coverage and physical PLL/SDRAM clock checks. Passing these
gates establish a fitted composition, not deterministic continuation,
physical DDR operation or hardware savestate behavior.
