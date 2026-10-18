# Load-time DDR image copying

The normal game ROM path remains external SDRAM. Onboard DDR3 is only a staging
source at the HPS extra-RAM window 0x30000000. No gameplay ROM client is moved
to DDR3. Physical HPS download/reset triggers and DDR ownership sharing are not
wired into the MiSTer top yet.

## Reused transport and copy engine

Unchanged Psikyo ddram_phy and rom_loader sources are pinned at
e2f717e110f9c113e46d949072c81c4b5e966965. Their original licence/README and
original PHY test/model are retained; hashes and provenance record all copies.
The donor's optional ADPCM-A bit swap is disabled: the MRA image is already in
Rabbit Punch layout. Native 25-bit destination addresses bound copies to 32 MiB;
the in-scope 0x210000-byte image fits. Length must be a multiple of eight.

The original donor PHY test passes byte-lane writes, granule reads, consecutive
transactions and immediate reuse at behavioral read latencies six and thirteen
(reference/ddram_donor_checks.json). No native word-loader test was identified;
the new VHDL copy test covers its use here without changing either vendor file.

rabbitpunch_ddr_copy exposes descriptive unsigned ports and a registered
one-word credit. Native dl_req is held until dl_busy acknowledges capture; that
credit remains occupied until our ready/valid stream accepts its word. External
word backpressure is not itself a native dl_busy acknowledgment. Both native
PHY busy and external DDRAM_BUSY inhibit the copier's next read, avoiding a
request lost while the PHY is idle but the DDR port is externally busy. The
caller owns the DDR port for the entire copy and must drain other clients before
starting. Initialization is cold transport reset, not game reset.

The copier reads one eight-byte granule at a time and emits its four ascending
16-bit words, with low byte at the even byte address. o_done means all words
have entered the downstream download controller; it does not mean that the
last physical SDRAM write has completed. Keep gameplay reset controlled by the
system's image validity/drain logic. A soft game reset must not start a copy.

## Directed and connected tests

ddr_copy_tb passes two distinct 64-byte images through independent DDR busy,
variable read delay, deliberately spoiled inactive data pins, word-ready stalls,
stable held output and warm restart (reference/ddr_copy_checks.json).

system_ddr_tb connects the copier to rabbitpunch_system's real sequential
loader, cached SDRAM controller/chip model and executing fx68k. Two 64-byte
program images write CAFE then BEEF into native main RAM. Inspection while
paused, warm image replacement and soft reset without any DDR recopy pass.
There are sixteen modeled DDR reads and sixty-four accepted stream words
(reference/system_ddr_checks.json). Audio enables and logical video are idle.
This is not an HPS trigger, a full-image bandwidth measurement, DDR electrical
timing or a game boot. Standalone full-size copy implementation passes all reported 48 MHz corners
with zero RAM, worst setup +8.269 ns and hold +0.143 ns
(reference/ddr_copy_synth.json).


## Automatic HPS-signal frontend

rabbitpunch_load_frontend accepts the clock-domain signals that hps_io exports.
Only index 0 arms a ROM transaction. The download-active output remains asserted
through host transfer, reset-release waiting, and copying/draining. A transfer
with byte-write pulses uses a one-word byte-pair buffer; low byte belongs to the
even address. Addresses must be sequential and the final byte count exact.
A first byte on the same edge as download rises is supported. Host wait includes
the write pulse and occupied word credit; metadata indices are left unstalled.

With no byte writes, the frontend waits until framework reset is released, then
starts one DDR copy. Later soft-reset edges cannot recopy that image. Do not
connect framework/game reset to the cold initialization input: byte streaming
and copying must continue while gameplay is held reset. The receiving system
uses frontend error OR framework reset as its game-reset input, in addition to
its existing image-valid/download reset. A rejected/short transaction cannot
release gameplay just because an old image once existed. Copy completion is
still distinct from the downstream final write acknowledgment.

An overlapping ROM transaction latches error and drains the old copy instead
of canceling an owned DDR read. A fresh transaction after idle clears error and
can recover. The frontend does not queue simultaneous image generations.
The caller must arbitrate/own the DDR port for the entire copy; actual rotator
sharing and hps_io wiring remain future platform work. Existing development
MRAs have not been switched to DDR-address mode before that wiring exists.

load_frontend_tb passes metadata filtering, reset-release gating, no reset-only
copy, no soft-reset recopy, direct pairing/stalls, same-edge first byte, odd and
nonsequential rejection, overlap drain and fresh recovery
(reference/load_frontend_checks.json). system_frontend_tb connects the frontend
to the native DDR copier, real production SDRAM download/cache/chip model and
fx68k. Three 64-byte DDR images and one direct byte image execute checked
CAFE/BEEF writes; a partial byte image holds reset and recovers into DDR loading.
There are 129 accepted word transfers and 24 DDR reads. Audio/video are idle;
this models HPS signals rather than instantiating real hps_io. Full-size frontend
implementation passes all reported 48 MHz corners: 294 ALMs, zero RAM,
setup +5.860 ns / hold +0.136 ns (reference/load_frontend_synth.json) (reference/system_frontend_checks.json).


Integrated retry protection: i_start_ready defaults high for standalone callers,
but rabbitpunch_platform connects it to downstream not-loading. Host wait also
asserts during frontend error drain. The master waits before a new transaction,
including DDR mode with no byte strobes; otherwise an early retry can overlap
the previous image's final SDRAM write. platform_tb covers immediate partial-
image recovery with this backpressure. The older standalone frontend fit above
records its exact earlier commit; the combined platform fit covers this update.


An isolated presentation transport now shares the physical DDR port with the
actual frontend/native copier in simulation. Concurrent presentation traffic
and pending-queue takeover preserve all 24 expected DDR reads and 129 output
words across the existing scenarios, including overlap drain. No presentation
write occurs during frontend ownership; queued pixels are discarded and a
fresh complete frame is required afterward. See HDMI_ROTATION.md and
reference/load_frontend_rotation_checks.json. This is not yet the connected
production shell or a physical HPS/DDR test.


The experimental source shell now connects the qualified presentation transport.
Its ownership signal is downloading OR system-loading, keeping presentation
blank/flushed through the downstream final SDRAM acknowledgment. MISTER_FB
and the complete controller hierarchy are mandatory full-build gates; the new
connected full-shell implementation and physical HPS/DDR tests remain pending.
