# T80 evaluation and sound CPU candidate

Copied without byte changes from Arcade-Psikyo_MiSTer, commit
e2f717e110f9c113e46d949072c81c4b5e966965. Selected files were clean.
Upstream: https://github.com/MiSTer-devel/T80,
830fd0315f0af5cdbcb0e703f1cea3ce4e91f538. Licence: BSD-style three-clause,
as stated in the source headers; copyright notices retained. DONOR_NOTES.md is an
unchanged copy of the donor's history. Per-file SHA256 values are in
docs/reference/vendor_manifest.json.

Local RTL changes: none. Only the T80se dependency closure is copied, rather than
the donor's unrelated wrappers or QIP. The unchanged donor boot/memory/I/O/HALT
test passes. The inherited operand-width warning in T80.vhd:685 remains recorded;
this test does not establish full CPU equivalence or the Rabbit Punch sound bus.
