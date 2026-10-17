# Sound bring-up

The sound board is not integrated or audible yet. The main board's command
mailbox is implemented, and the T80 CPU donor has its earlier baseline. This
checkpoint adds an unchanged JT51/YM2151 evaluation copy, descriptive unsigned
VHDL wrapper and an isolated chip baseline. uPD7759 and Z80 board/ROM scheduling
remain open.

## YM2151 donor and baseline

Selected chip RTL: Arcade-JalecoMS1BCD_MiSTer commit
f16ec2b84c14409b5ae7b8ade761fffd7ec34b8e, clean selected JT51 files.
Upstream is jotego/jt51, GPL-3.0-or-later. Its exact upstream JT51 revision is
not recorded by that donor. Dependency hashes and source paths are in
reference/vendor_manifest.json and rtl/sound/jt51/PROVENANCE.md. No donor RTL
is modified. Two SIMULATION-only diagnostic helpers come from the complete
local upstream JT51 checkout at 00dd3f935c8d73bbebe7a16c4af1c6f32ac742ed.
They are not synthesis dependencies or a mixed version of the sound chip.

The selected donor has no original regression suite. The older complete JT51
checkout has a top-level test using DAC ports absent from this selected copy;
its tests and chip interfaces must not be silently mixed. The new VHDL native
baseline runs before wrapper testing and states its limits explicitly.

run_ym2151_tests.py verifies native and wrapped interfaces using a 48 MHz
evaluation clock, 4 MHz chip enable and 2 MHz half-enable. Both enable inputs
advance the same clock domain. Measured sample-marker edges are 768 system
clocks apart (chip clock/64). Explicit channel mute/key-off programming produces
zero PCM. Do not assume FM parameter storage is initialized by reset alone.
Timer A/B status, IRQ assertion/clearing and a complete timer B period pass.
The first B overflow includes free-running prescaler phase, so its full period
is measured between consecutive overflows while load remains asserted.
Results: reference/ym2151_checks.json.

This is not a keyed-tone waveform, game-register trace, analog-level or by-ear
comparison. The sound CPU and MAME command traces must drive further verification
before game sound is claimed. The wrapper has descriptive chip select/write,
register/data selection, status and active-high interrupt ports. PCM outputs
use unsigned buses containing raw two's-complement bits, including separate
chip-quantized and full-resolution pairs; mixing must preserve that encoding.
The sample marker is forwarded unchanged and consumed synchronously, not as a
new clock. Peripheral CT pins are unused by the board adapter.

## uPD7759 candidate

Arcade-SystemC2_MiSTer commit acb146209bcbb58a7f2687c4b162b2ee9a3ff88c has
a clean selected JT7759 directory, not copied or validated here yet. Its current
README port table differs from the actual entry point: native ROM address is
17 bits and PCM output is signed 9 bits. Bind the HDL declaration, not that
stale table. Rabbit Punch's extra sample-ROM bank is outside the 128 KiB native
address window and needs board-specific VHDL handling. Reset/start polarity,
standalone mode, ROM latency and command timing must be checked against the
MAME driver/device and the actual donor before connection.

The sound ROM clients still need a verified path into shared SDRAM, with measured
impact on line deadlines. Do not add a frame buffer or silently increase clocks
to accommodate them.
