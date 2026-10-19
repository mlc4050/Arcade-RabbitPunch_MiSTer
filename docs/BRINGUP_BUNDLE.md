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
