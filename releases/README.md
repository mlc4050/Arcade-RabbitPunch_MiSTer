# Rabbit Punch / Rabio Lepus prototype

Use `Arcade-RabbitPunch_20261018.rbf` with the primary MRAs in this folder.
Optional DDR-loading and synthetic diagnostic MRAs are under `_alternatives/`.
ROMs are not included. The diagnostic MRA requires the separately generated diagnostic ROM.

This candidate updates the OSD and keeps Save NVRAM open for host upload polling.
Immediate on-disk NVRAM saving still requires hardware confirmation. Full savestates
are not available, and music comparison against MAME remains in progress.

Build: original source `3dfbd332d078da18f1d762df7fcb34be8cb05a51`, fitter seed 3;
corresponding privacy-rewritten source `5704d95f32c325ac919f90afaeb55952bccaa878`.
All 144 scoped timing checks pass; minimum setup +0.419 ns, hold +0.079 ns.
Resources: 15,285 ALMs, 25,260 registers, 187 M10Ks, 35 DSPs, 3 PLLs.
See `../docs/reference/full_shell_final_osd_nvram_checks.json` for timing scope
and `../docs/reference/publication_identity_checks.json` for source identity.

RBF SHA-256: `2848c5750c1fbe4d8201a34c987d9dfd4761dba44c4c4367ec5ed5dd6c32a92b`.
