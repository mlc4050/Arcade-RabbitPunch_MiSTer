# Unchanged donor CPU tests

Source files are byte-for-byte copies, with source paths, donor revisions and SHA256
values in docs/reference/vendor_manifest.json. The original comments and limitations
are retained. Local changes to these test files: none.

- Psikyo: tg68k/tb_tg68k_boot.vhd and t80/tb_t80_boot.vhd.
- Seta: tg68k/tb_tg68k_smoke.sv, tb_tg68k_ccr.sv, tb_tg68k_pace.sv,
  and fx68k/tb_fx68k_pace.sv.

The 68020 wrapper test reaches its final result landmark. The native kernel smoke/CCR
tests exercise 68000 mode. The pacing tests compare the same NOP/DBRA loop.
Existing donor source licences and notices apply; see each CPU's provenance.
scripts/run_baselines.py enforces assertions, transcript failure markers and required
completion markers without editing the donor tests.
