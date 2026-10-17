# SDRAM donor

Copied without modification from Arcade-Vamphalf_MiSTer at `8f9d15b879952371ec46cb2b0f5e960bfee25d22`:
`rtl/memory/sdram.sv`. Copyright Sorgelig, GPL-3.0-or-later, as retained
in the source header. Chain: Sorgelig -> Psikyo burst-4 -> Fuuki wider
addresses -> KonamiGX two-chip support -> Vamphalf configurable refresh.
Exact SHA256 and source path are in docs/reference/vendor_manifest.json.

This donor's RFS_INTERVAL parameter permits correct clock-specific refresh
without editing imported HDL. Rabbit Punch disables double reads and extra
write beats; it needs only the lowest 0x210000 bytes of one 128 MB module.
Address port indices [26:1] must be retained in the VHDL component boundary.
Three ports have fixed priority and shared read-data registers; the VHDL
adapter captures responses on acknowledgment. Chip-clock phase and external
pin timing remain top-level integration work, not proven by a functional sim.

The unchanged command-decoding model from the same commit is vendored as
sim/vendor/sdram/sdram_chip_model_wide.sv; it models both chips, mode/CAS,
bursts and per-beat byte masks. It does not model analog timing or charge
retention. A VHDL testbench separately monitors refresh command intervals.
