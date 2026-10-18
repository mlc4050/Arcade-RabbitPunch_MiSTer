# HDMI rotation bring-up boundary

Rotation is approved work but remains disconnected. The native analog path
and its common screen flip remain independent of the HDMI framebuffer tap.
Both games are horizontal, so Auto must leave rotation disabled; explicit
CW/CCW is an optional presentation mode. A rotated output advertises 3:4.

The inspected donor is `Arcade-Seta_MiSTer/rtl/video/screen_rotate_two.sv`,
clean at commit `208dc11035f3c9356c5c1005c0005aad14e51239`, SHA-256
`a704b114cc7d7c1684eb273ab98b436350a3ffb957b350fad975bb322ba11f9e`.
Its header grants GPL-2.0-or-later. It uses the single video clock and pixel
enable. No local upstream regression for this module was found in Seta's
sim/scripts trees; arrival tests must be authored in VHDL before integration.

The actual source declares DDRAM_BUSY but never reads it. Its ram_wr is a
one-cycle pulse derived from visible pixels. Therefore merely OR-ing loader
activity into BUSY does not backpressure this revision of the donor. A wrapper
must capture writes, drain accepted requests in order, and prevent overflow;
the imported file stays unchanged. The skill guide's general BUSY advice is
insufficient for this exact file. This is source inspection, not a measured
hardware failure in Seta or any other core.

Before connection:

- Verify CW/CCW pixel addresses, byte enables, channel order, measured width,
  height and stride against an independent coordinate model. Check every
  visible pixel, not flat fields alone. Preserve native scanout independently.
- Test the descriptive VHDL wrapper and its bounded write queue under DDR busy
  bursts, simultaneous enqueue/dequeue, loader requests with queued writes,
  reset/replacement and ownership changes. Record an overflow indication and
  prevent partial rotated frames from being advertised as complete frames.
- Hold the ROM reader busy until its grant, keep all outstanding loader reads
  owned until their responses drain, and isolate rotator requests throughout
  the loader transaction. Stop/restart presentation at a clean frame boundary;
  a stalled tap may need history rebuilt before enabling the framebuffer.
- Audit the donor's default three 8 MiB slots beginning at 0x24000000 against
  framework reservations and the ROM staging window at 0x30000000. Do not
  silently repurpose game SDRAM or add runtime ROM reads to DDR.
- Qualify the isolated fitted RAM/clock/timing budget, then connect MISTER_FB,
  loader arbitration and 3:4 metadata and run both full-shell revisions.

Rotation intentionally uses the framework framebuffer. It is not an added
framebuffer in the game renderer or native CRT output. Latency and low-lag
buffer selection need their own explicit validation; no eight-frame queue is
introduced or accepted by this plan. Crop controls must also be chosen for
this game's native 216 visible lines; copying a 216-of-240 crop menu would
advertise a no-op here.

Isolated arrival and queue evidence now passes. The unchanged donor's fc479ee
fit uses 218 ALMs, 193 registers, one DSP, no RAM/PLL, with setup/hold
+9.340/+0.134 ns. Both full 288x216 CW/CCW address/colour/byte-mask scoreboards
pass all 62208 pixels. The separate 512-write VHDL queue uses one 512x101 RAM
(51712 bits, six M10Ks), 243 ALMs, 252 registers, no DSP/PLL, with setup/hold
+8.956/+0.149 ns. RTL and fitted-netlist ordering tests check 4497 accepted
packets, including full capacity, overflow, pointer wraps and reset. Both full
rotated images also pass through repeated 96/64-clock DDR busy bursts with
no overflow. These modules remain disconnected; their resource usage is not
included in the accepted full-shell totals. See reference/hdmi_rotation_arrival_checks.json,
ddr_write_queue_synth.json, ddr_write_queue_netlist_checks.json and
hdmi_rotation_queue_checks.json.

A separate expected-failure netlist probe exposes another integration hazard:
when source VSYNC and FB_VBL rise together, the donor advances both buffer
selectors from their old values and advertises the same buffer it writes
(read=1, write=1 in the fixture). This is a simulated donor behaviour, not a
measured fault in another core. See reference/hdmi_rotation_collision_probe.json.
The native framework samples hdmi_vbl into fb_vbl on clk_vid; an adapter must
serialize the buffer-advance events and advertise only complete valid frames.
The pixel-address and queued-write proofs do not establish safe publication,
frame latency or loader handoff. Keep rotation disconnected until those pass.
