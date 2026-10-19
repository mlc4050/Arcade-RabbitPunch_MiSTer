# Private bring-up bundle

prepare_bringup_bundle.py creates a local _Arcade tree from an already accepted
full-shell RBF and the tested development MRAs. It does not build, deploy,
publish, launch or touch JTAG. No game ROM ZIP is included. The ROM-free diagnostic
MRA is included beside both default game MRAs and their DDR-load alternatives.

The tool checks every retained fit-artifact hash, positive reported timing,
unchanged production sources versus the fitted commit, MRA target/version and
byte-identical copied files. A fresh output directory retains the exact package
with manifest.json and practical diagnostic/game bring-up instructions.

The current artifact is identified by reference/bringup_bundle_checks.json.
Its RBF is source 86c437a, release revision RabbitPunch, seed 3, 144 timing checks,
setup +0.139 ns and hold +0.084 ns. This is a timed local candidate with documented
provisional SDRAM/raster and inherited peripheral coverage limits. Hardware
execution, visible outputs, audio and persistence are still unverified.

Regenerate after changing MRAs; an earlier package retains its earlier menu and
hashes. Use --archive-root to select the worktree holding the accepted artifact
archive and --output-dir for a new package directory. Nothing is placed under
published releases or copied to a MiSTer automatically.

## Instrumented candidate

--revision RabbitPunch_stp selects the already accepted source 896da70,
seed 2 debug RBF: all 164 required checks pass, setup +0.306 ns and hold
+0.078 ns. It uses the same production-source match and complete fit-artifact
hash gates as the default release candidate. No new Quartus compile is needed.

The debug candidate has its own Arcade-RabbitPunch_stp dated filename. Its five
MRAs live under _Arcade/_Debug, with [Debug] in the display name. Only name and
RBF target differ from the verified development definitions: XML structure,
ROM bytes/layout, DIP bits/defaults, buttons and score transfers are preserved.
The normal bundle continues copying source MRAs byte-for-byte. Both candidates
can coexist without replacing each other's game menu entries or RBF files.

reference/bringup_bundle_debug_checks.json identifies the debug package and
all exact file hashes. Its fitted SLD is kept outside _Arcade in debug_metadata
on the PC. RPUN is a read-only activity packet; see DEBUG.md for fields,
limitations and the shared build/simulation/JTAG lock. Neither packaging path
accesses the MiSTer, launches a game, reads JTAG or publishes a release.
