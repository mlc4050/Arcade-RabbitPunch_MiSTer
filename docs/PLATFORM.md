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
