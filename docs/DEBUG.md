# Read-only bring-up probes

The instrumented RabbitPunch_stp revision includes rabbitpunch_debug; the release
revision omits its instance. This is VHDL instrumentation with one system-clock
process and no signals that control the game. Its counter/packet bench passes;
the Tcl field decoder and one-line Python reader pass valid and deliberately malformed input tests without
opening JTAG. Fitted probe presence and actual hardware reads remain unverified.

Use scripts/read_issp.py RPUN through scripts/d_drive.ps1 when all compilation and
simulation jobs have ended. The helper takes the shared JTAG lock. Do not invoke
quartus_stp directly. Do not use clear/set/pulse; this instance is read-only.

The packet contains the RPUN core tag (0x5250554E), a 32-bit source commit prefix,
and layout version 1. Staged builds inject the commit prefix into their QSF;
a manual build without that macro reports zero, meaning unknown. The reader also
prefixes output with the device/deploy-log core, build and set identity. A matching
packet tag does not establish which game is loaded; keep the device set prefix.
The decoder refuses unknown tags/layouts, nonbinary/incorrect-width packets,
missing named instances and source actions.

Counters record enabled negative VSYNC edges, main CPU request pulses, main CPU
write pulses, sound CPU request pulses, visible pixel enables, PCM sample markers
and rising underflow edges. All counters saturate at 0xFFFFFFFF, start at FPGA
configuration, and survive gameplay reset. Once saturated they cannot supply a
rate; reload configuration for a fresh window. Visible pixel counting follows
physical data enable even during black loading screens. A zero underflow count
is meaningful only alongside advancing frame/pixel totals. The main request and
write counters distinguish CPU reads from writes; full addresses/data/byte masks
are retained, including upper address bits.

The beam/status fields are sampled and the packet is registered. The packet has
one edge of latency relative to counter updates. JTAG samples a live changing
bus; this is activity telemetry, not an atomic game-state dump or a cycle trace.
Repeat readings before inferring a stuck address. The fields do not measure
maximum row render cycles, interrupt latency, SDRAM electrical margins or audio
correctness.

Status bits are PLL lock, ready, loading, downloading, error, sticky underflow,
scanout armed, paused, host download, ADPCM busy and framework reset in bits
0 through 10. Other status bits are zero. The canonical bit map is in
rtl/rabbitpunch_debug.vhd and the corresponding named Tcl fields. The test-only
counter width generic exercises saturation quickly; hardware retains 32 bits.

Evidence: reference/debug_checks.json (VHDL behavior) and
reference/debug_decode_checks.json (mocked Tcl transport). No hardware results
are claimed by either report.

Quartus 17's altsource_probe supports at most 511 probe bits. The initial
512-bit instrumented build was rejected at elaboration, before fitting; it is
archived under debug/fit_archive/full_shell_1693628_probe_width_rejected/.
The unused top bit was removed. Layout version occupies bits 480..510; all
other field positions remain unchanged. VHDL and decoder tests are rerun for
the exact hardware width, and malformed-width packets remain rejected.
