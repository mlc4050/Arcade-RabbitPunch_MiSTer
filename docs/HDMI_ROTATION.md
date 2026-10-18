# HDMI rotation bring-up boundary

Rotation is now connected in the experimental source shell; full-shell fit
and hardware qualification are pending. The native analog path
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


The descriptive adapter now serializes coincident source/destination buffer
advances in VHDL, with the imported file unchanged. Its 8238d77 fit passes all
standalone timing/coverage checks: 220 ALMs, 196 registers, no RAM/PLL and one
inherited donor DSP; minimum setup +8.085 ns and hold +0.164 ns. Initialized
between-edge tests check known read/write indices, active slot exclusion,
read-slot progress and every pixel in three complete frames per case. Five
compact FB_VBL phases (-2..+2 clocks), both low-latency request values, and
both full native directions pass. Low-latency requests deliberately retain
triple buffering: an initialized negative control exposes a legacy two-buffer
collision when FB_VBL leads source VS. See hdmi_rotation_buffers_checks.json
and hdmi_rotation_low_latency_probe.json. A separate early frozen-buffer
report was invalid startup stimulus; hdmi_rotation_liveness_rejected.json
retains that diagnosis and its corrected initialized recheck.

The new publication guard accepts pixels only after a clean source frame
boundary. It invalidates a slot on its first overwrite and advertises a slot
only after a complete same-slot pixel count and an empty output queue at the
frame boundary. Load, disable, not-ready and overflow immediately blank/flush
presentation; recovery waits for another complete frame. Short, long,
mixed-slot, queued, startup and post-load partial frames are rejected. Its
7b1b43b standalone fit is 40 ALMs, 35 registers, no RAM/DSP/PLL, with setup
+7.557 ns and hold +0.170 ns. The functional netlist repeats the behavioral
scenarios at the actual 62208-pixel size. See frame_publication_checks.json,
frame_publication_synth.json and frame_publication_netlist_checks.json.

The fitted rotator plus actual queue/publication RTL also passes both full
CW/CCW images under repeated 96/64-clock DDR busy bursts. Each direction
checks three complete 62208-pixel frames, every address/colour/byte mask, slot
safety/progress, queue drain and publication only after all advertised-slot
DDR pixel writes. Compact controls pass too. The first full-width publication
checker incorrectly treated X=256 as frame origin by omitting its high bit;
that exact failure is retained and the corrected checker passes. See
hdmi_rotation_publication_checks.json and hdmi_rotation_publication_rejected.json.

The combined transport now gives the loader immediate priority, discards old
queued presentation writes and keeps DDR responses continuously connected to
the loader. The caller must retain ownership through its last response and
output word. The actual load frontend/native copier test verifies that
contract under word backpressure, pending-queue takeover, DDR/direct byte
modes, metadata filtering, reset gating, rejected overlaps and recovery:
24 physical reads and all 129 expected output words remain exact, with no
presentation write while the loader owns DDR. See load_frontend_rotation_checks.json.
The separate mux/queue test also checks clean post-load image recovery.

Transport fit 385ef95 passes all standalone timing/coverage checks: 465 ALMs,
291 registers, six M10Ks/51712 bits, no DSP/PLL, setup +6.739 ns and hold
+0.172 ns. Its functional netlist passes the takeover/recovery scenario at
62208 pixels per frame. These are isolated resources, not new full-shell totals.
See rotation_transport_checks.json, rotation_transport_synth.json and
rotation_transport_netlist_checks.json.

Configured DDR reservations are disjoint: framework scaler 0x20000000..
0x217fffff, rotator 0x24000000..0x257fffff, and the current ROM image at
0x30000000..0x3020ffff. A rotated 216x288 image uses stride 864 and 248832
bytes, fitting an 8 MiB slot. The audit derives addresses from RTL/framework
sources and checks both QSFs and any MRA DDR address; it does not validate
arbitrary host-supplied external-framebuffer locations. See ddr_window_checks.json.

Next: latch HDMI mode changes safely, connect the native tap and framebuffer
metadata/blanking plus the qualified loader transport, verify rotated aspect
and control changes, then fit both complete MiSTer revisions. Actual CRT/HDMI
hardware, arbitrary source/output phase/frequency, full end-to-end latency and
physical DDR acceptance remain unverified. Native rendering keeps its existing
one-row pipeline; optional HDMI rotation is the only new framebuffer path.


The complete VHDL HDMI controller now latches None/CW/CCW requests at native
vertical sync while the loader is idle. A direction change registers a flush
pulse and requires a fresh complete image. Direct video immediately disables
framebuffer output/blanking and preserves native metadata. The native RGB tap
has no analog output port. All existing native aspect/integer cases, four
rotated integer modes against an independent transposed qualified framework
reference, 3:4 aspect, custom selector encoding, midframe requests, direction
flush, loader mode hold and reserved settings pass. Both full native directions
also pass three complete image frames through this complete RTL controller.
See hdmi_presentation_control_checks.json and hdmi_presentation_checks.json.

The complete-controller 47a3eff standalone fit passes with one exact 512x80
queue RAM (40960 bits, four M10Ks). The general queue's 101-bit packet has 21
fixed-zero columns here: five from the donor address base and sixteen from
the two 32-bit RGB words' zero high bytes. The audited gate derives those
columns from the unchanged donor and requires exactly one 512x80 memory;
capacity and every remaining packet field are retained. The original 51712-bit
estimate was rejected and archived, not accepted by widening a cap. See
hdmi_presentation_synth.json and hdmi_presentation_ram_rejected.json. Complete
fitted-controller functional control/image checks remain in progress.

Prototype shell wiring now enables MISTER_FB in both revisions and connects
status 114:113 to the HDMI-only controller (None=0, CW=1, CCW=2; 3 disables).
H5 hides the menu under direct video. Native analog RGB/sync stay on the
existing video-options path; the tap is before CRT/effects. The loader owns
DDR throughout downloading OR final system-loading drain. The complete
controller and framebuffer macro are required by the full-build gates.
No accepted full-shell rotation fit or physical result is claimed yet.

The 10c7995 host fit and synthesized HPS protocol bench pass with the new
HDMI None/CW/CCW configuration string checked byte for byte and all 128 status
bits transported. The standalone host uses 479 ALMs, 403 registers and no RAM;
minimum setup is +7.133 ns and hold +0.167 ns at its 48 MHz evaluation clock.
See reference/host_hdmi_menu_synth.json and reference/host_netlist_checks.json.
This does not establish physical ARM menu behavior or a complete shell fit.

A doubled-presentation regression found that integer rotation metadata measured
the analog HQ2x geometry even though the rotator captures native pixels. In the
32x20 native / 64x40 presented fixture at a 1900x1080 destination, the old V-integer
output was 640x1080 instead of the native reference's 660x1080. The failing source,
fixture and transcript are preserved under debug/fit_archive/hdmi_presented_geometry_34441d0_rejected/.
The controller now selects native CE/VS/DE while rotated, retaining the presented
geometry when rotation is off. Both directions and all four integer modes pass
the independent native-aspect comparison; the complete existing mode/loader/direct
control regression also passes. See reference/hdmi_presented_geometry_checks.json
and hdmi_presented_geometry_rejected_checks.json. Earlier fitted-controller and
full-shell jobs predate this metadata correction; fresh synthesis/timing is required.

The corrected native-geometry controller c7ecb10 passes standalone 48 MHz
implementation: 795 ALMs, 877 registers, four M10Ks (one 512x80 queue), one DSP,
no PLL. Minimum setup is +5.375 ns and hold +0.118 ns, with all six timing
coverage categories clean. See reference/hdmi_presentation_native_geometry_synth.json.
The full-controller functional netlist and corrected full-shell timing checks
remain pending; earlier fit snapshots do not include this correction.

The corrected c7ecb10 complete functional netlist passes the existing control
regression: native and rotated integer modes, custom/full selectors, mode latch,
direction flush, loader hold, direct-video override and reserved encodings.
It retains the production 62208-pixel validity counter; the bounded control
fixture is partial and cannot establish positive image publication.
See reference/hdmi_presentation_netlist_checks.json.

The corrected controller RTL also passes both native 288x216 directions with
three scored production-raster frames each: 373248 pixels total across those
two cases, exact addresses/colours/byte masks and complete publication under
the original /7 enable and 96/64-cycle DDR stalls. Compact controls also pass.
The separate compressed 304x224 raster /1 fixture passes both directions with
four-cycle busy bursts and all 62208 pixels per case; its synthetic cadence
is explicitly separate from the production proof. See hdmi_presentation_checks.json
and hdmi_presentation_dense_rtl_checks.json. Dense complete-netlist images and
the doubled-presentation netlist seam remain in progress.
