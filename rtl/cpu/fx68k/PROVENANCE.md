# fx68k timing evaluation

Copied without byte changes from Arcade-Seta_MiSTer, commit
208dc11035f3c9356c5c1005c0005aad14e51239. Selected source files were clean.
Upstream: https://github.com/ijor/fx68k. Donor ancestry and its inherited microcode
path modification are recorded in DONOR_NOTES.md. Licence: GPLv3; LICENSE, original
README and copyright headers retained. Per-file SHA256 values and donor paths are in
docs/reference/vendor_manifest.json.

Local RTL changes: none. The micro/nanorom .mem files are CPU control-store data,
not copyrighted game ROM dumps. The simulator runner stages these two unchanged
files under the expected relative paths in debug/baselines/fx68k_pace/.

Evaluate with the donor's unchanged fx68k pacing test before board integration;
see docs/BASELINES.md for measured behavior. No game bus or Quartus source list is
connected to this candidate merely by vendoring it.
