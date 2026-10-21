# STOP-aware 68000 state evaluation donor

Copied byte for byte from local Arcade-KonamiGX_MiSTer commit
89124d4f29e1d3f95557e5e5265efcbe9d0d7cb4. Its fx68k provenance is retained
under fx68k/PROVENANCE.md, including the packed structs and stop_out change.
The upstream CPU is https://github.com/ijor/fx68k (GPLv3); the capture helper
carries GPL-3.0-or-later and its original copyright notice.
Each source and SHA-256 is recorded in vendor_manifest.json.

This is an isolated savestate evaluation. It is outside files.qip, does not
replace the production CPU, and must pass native continuation/STOP tests and
production startup/timing qualification before integration. The new VHDL
wrappers retain descriptive unsigned interfaces around unchanged imports.
