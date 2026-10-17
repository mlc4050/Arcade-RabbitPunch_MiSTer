# Native MiSTer host boundary

rabbitpunch_host wraps the unchanged sys/hps_io.sv with descriptive unsigned
ports. The 46 HPS_BUS bit positions are preserved. File I/O is explicitly byte
wide. Config text is packed to the native constant-vector parameter at compile
time; status, two joystick words, keyboard events and SDRAM configuration keep
their native widths. No disk, analog controller, upload or PS/2 serial feature
is enabled by this boundary. The prototype configuration is not the final core
OSD. Real sys/emu wiring remains unchanged while physical scanout is unresolved.

| Native HPS bus field | Meaning |
|---|---|
| 31:16 | host command/data word |
| 15:0 | FPGA response word |
| 33 | command/data strobe |
| 34 / 35 | UIO control / file-channel selection |
| 32 | wide-file flag, zero here |
| 36 / 37 | system clock / file backpressure |
| 45:38 | framework video telemetry, not game inputs |

ModelSim 10.5b cannot parse the current unmodified framework's forward local
symbols and some static declarations. Documented compatibility flags did not
resolve that. No sys source was edited or substituted. Instead the staged
host_check profile synthesizes the real host wrapper with Quartus 17 and emits
its functional netlist, which the VHDL host_tb drives in ModelSim. The profile
aliases both video telemetry clocks to its 48 MHz evaluation clock and leaves
pixel/raster activity zero. It establishes no real video or 100 MHz telemetry.

The host fit passes with zero RAM, 330 ALMs, 392 registers, worst setup +6.491 ns
and hold +0.167 ns, all reported corners and six timing coverage categories
passing (reference/host_synth.json). VHDL netlist tests read the complete config
text back and verify both joystick word orders, all eight status words, native
FIO command/index/download/data addresses and the wait pin. F2 and extended
arrow press/release flags and event toggles also pass
(reference/host_netlist_checks.json). This is not a physical ARM bridge or a
native-RTL ModelSim pass. File-trigger and whole-system tests are separately
scoped in DDR_LOADING.md.
