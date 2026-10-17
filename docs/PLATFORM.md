# Logical platform integration

rabbitpunch_platform connects host status, joystick/keyboard and index-254 DIP
metadata to the existing controls/pause block, byte/DDR frontend and complete
main/video/audio/SDRAM system. Native hps_io remains an independently verified
external boundary. Reset status bit 0 and host button 1 reset gameplay; status
bit 1 requests pause and bit 2 enables OSD pause. Cold initialization remains
separate from gameplay reset and ROM replacement.

The frontend receives downstream start readiness from the system's loading
flag. A rejected partial image can report its frontend error before the last
SDRAM write completes. Host wait stays high through frontend error drain and
while the downstream loader remains busy, so a new ROM cannot merge with the
old generation. The host must obey wait before starting/ending a transaction
as well as before sending bytes. No accepted write/read is canceled.

The VHDL platform test downloads two 64-byte DDR diagnostics and one byte-stream
diagnostic, rejects a partial byte image, and recovers. The actual fx68k reads
player/service registers at C0018/C001A and DIP at C001C, writing checked 1219,
1226 and A55A words to native work RAM beside the CAFE/BEEF image marker. Paused
inspection checks all four RAM words. Pad pause, keyboard resume, held P across
reload, independent OSD pause and soft-reset DIP/image preservation are checked.
See reference/platform_checks.json; these are synthetic programs with modeled
host/DDR signals and the production SDRAM controller/chip model. Audio enables
and logical video requests are idle in this test.

The platform exposes a DDR ownership request, not a completed shared-port mux.
Physical PLL, raster/scanout, actual HPS bridge/rotator ownership and external
memory electrical timing remain outside this module. The inherited demo top is
not changed into a playable core by this logical integration. Development MRAs
remain byte-stream mode until physical DDR wiring is complete.


Full-size production logical-platform implementation, including paused
maintenance and the transparent idle CPU owner, passes all reported 48 MHz
timing corners and all six coverage gates (reference/platform_synth.json,
commit 8e608a3): 6431 ALMs, 7832 registers, 123 RAM blocks and
927339 RAM bits. Worst reported setup is +2.885 ns and hold +0.082 ns;
all other reported checks are nonnegative. The eight expected sound RAM
geometries and required CPU/video/loader/maintenance hierarchy survive
synthesis. Registered logical test boundaries and direct SDRAM pins use
hypothetical half-period external input timing; final PLL/raster and PCB
memory timing remain unproven.

Native host integration also passes (reference/platform_host_checks.json).
platform_host_tb drives actual UIO/FIO command strobes into the verified
Quartus functional netlist of unchanged hps_io/rabbitpunch_host/host_check, then
connects its decoded outputs to the RTL platform. It repeats the CPU-visible
input/DIP/RAM, DDR/byte load, pause/reload/reset and partial-image recovery
checks. HPS wait is obeyed before command strobes. This avoids ModelSim 10.5b's
native hps_io parser limitation without replacing the host with a behavioral
parser. The runner verifies the archived netlist hash and matching committed
host sources. There is no SDF or physical ARM bridge in this test.


The logical platform now includes standard high-score config3/dump4 service,
atomic score banks and a session arbiter sharing the acknowledged maintenance
byte port with external state/debug access. Host upload request/data/active and
profile-dependent menu mask are explicit ports; status bit 3 enables autosave.
See HISCORE.md and reference/platform_hiscore_checks.json for the executing-CPU
proof. This adds 2048 logical RAM bits (one M10K) to the platform; a refreshed
combined fit is required before treating the new composition as timing-closed.
