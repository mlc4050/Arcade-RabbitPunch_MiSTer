# TG68K.C evaluation copy

Copied without byte changes from Arcade-Seta_MiSTer, commit
208dc11035f3c9356c5c1005c0005aad14e51239. The selected source paths were clean.
Upstream: https://github.com/TobiFlex/TG68K.C,
ade33e396a1e647c2de9daf71ff9d5b3979639b2, with inherited modifications described
in DONOR_NOTES.md. Licence: LGPL-3.0-or-later, as stated in the source headers.
All selected files and SHA256 values are recorded in docs/reference/vendor_manifest.json.

Local RTL changes: none. TG68K.vhd is retained for the unchanged donor wrapper test;
it is not selected for board integration. Native-kernel 68000 functional tests pass,
but a NOP/DBRA loop takes 4 enables per iteration against a 68000's 14 clocks.
This is not a cycle-accurate main CPU. See docs/BASELINES.md for the selection result.
