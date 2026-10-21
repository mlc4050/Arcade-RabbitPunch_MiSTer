# State-enabled JT51 evaluation donor

Copied byte-for-byte from `rtl/jt51/*.v` in
https://github.com/rmonic79/Arcade-BoogieWings_MiSTer at
`84085e3d19be7c0a9b3238579ce99962b0b462e5`. JT51 source headers specify
GPL-3.0-or-later and retain Jose Tejada
Gomez's authorship and the donor's savestate instrumentation attribution to
Umberto Parisi. Every imported file has a SHA-256 in `vendor_manifest.json`.
There are no local changes to these imported sources. The included GPLv3 text
comes from the existing production JT51 `LICENSE`; the donor repository's
root GPLv2 text is not used to override the explicit JT51 GPLv3-or-later headers.

The donor exports a 2820-bit persistent-state vector through `auto_ss_*` ports.
This is an evaluation candidate, not a replacement for production JT51 or a
claim of exact PCM continuation. In particular its operator and accumulator
instances have no state ports. It remains outside `files.qip`; a descriptive
VHDL wrapper and VHDL continuation audit establish the actual scope separately.

The native audit completed with `accepted: false`: the vector reloads exactly,
but all 32768 combined observable trace clocks differ after restoring a keyed
feedback tone, including after 4096 clocks. See
`docs/reference/fm_state_audit_checks.json` and `docs/SAVESTATES.md` for the
fixture qualification, missing-state findings and exact evidence. No imported
file was changed to make this test pass.
