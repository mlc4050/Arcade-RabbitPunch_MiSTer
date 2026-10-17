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

The host fit passes with zero RAM, 348 ALMs, 384 registers, worst setup +6.967 ns
and hold +0.156 ns, all reported corners and six timing coverage categories
passing (reference/host_synth.json). VHDL netlist tests read the complete config
text back and verify both joystick word orders, all eight status words, native
FIO command/index/download/data addresses and the wait pin. F2 and extended
arrow press/release flags and event toggles also pass
(reference/host_netlist_checks.json). This is not a physical ARM bridge or a
native-RTL ModelSim pass. File-trigger and whole-system tests are separately
scoped in DDR_LOADING.md.


The native host functional netlist is now connected to the logical platform in
platform_host_tb. Actual command strobes produce CPU-visible controls and DIPs,
byte/DDR downloads and pause/reset/retry behavior. See PLATFORM.md and
reference/platform_host_checks.json. The development configuration is shared with the platform; this is not final OSD or physical HPS bridge validation.


Development configuration now lives in rabbitpunch_config.vhd: reset (bit 0),
pause (bit 1), OSD pause (bit 2), and the exact padded MRA button names/slots.
Reset precedes J1. The configuration version is v0.1-dev. Video/scaler/audio
menu options wait for their physical shell connections. Full native host readback and connected platform command tests pass for this
configuration (reference/host_netlist_checks.json and
reference/platform_host_checks.json). This checks bytes and decoded controls,
not the physical ARM OSD renderer.


Upload request/index/data and native active/read flags are exposed through the
unsigned wrapper. The verified pre-menu upload fit/test checks a 119-byte transfer
from a synchronous read source, command boundaries and pending request rearming.
The configuration now adds `H3O3,Autosave high scores,Off,On;` at status bit 3;
the logical platform supplies menu-mask bit 3 until a valid profile exists. The refreshed native host fit and configuration/upload netlist test pass for
this menu generation (reference/host_synth.json and host_netlist_checks.json).


The composed native score-platform test now passes both sets. It verifies
standard configuration/NVRAM transfers, CPU-consumed restored bytes, UIO3C save
request polling, native score uploads, UIO2E profile-dependent menu visibility,
soft-reset restoration and ROM-generation isolation. The file master is a VHDL
protocol driver, not ARM Main software; no on-device filesystem claim follows.
See reference/platform_hiscore_host_checks.json.
