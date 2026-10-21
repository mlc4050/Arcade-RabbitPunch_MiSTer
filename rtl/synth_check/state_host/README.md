# State host protocol evaluation

This isolated profile connects the unchanged MiSTer `hps_io` to the VHDL state
controls. The enabled configuration exists only in this evaluation; the
production shell continues to advertise no savestates.

Run from a committed snapshot with the shared tool window available:

```powershell
.\scripts\d_drive.ps1 scripts/build_staged.py --synth-check state_host
.\scripts\d_drive.ps1 scripts/run_netlist_tests.py state_host
```

The functional netlist test reads the complete configuration through HPS,
checks all four slot increments and wraparound, reads the complete status
request payload, acknowledges it through the normal status command, and
checks failures, restores, held triggers and menu masks. Service completion
inputs are synthetic. This does not establish game continuation, ARM firmware
behavior, rendered OSD appearance or hardware timing.

The 48 MHz seed 3 fit passes with 0 block RAM bits, 423 ALMs and 469 registers;
minimum setup is +7.427 ns and hold +0.172 ns. The synthesized protocol test passes.
Receipts are `docs/reference/state_host_synth_checks.json` and
`docs/reference/state_host_netlist_checks.json`. This scope excludes ARM
firmware, rendered OSD and full-game/presentation integration.
