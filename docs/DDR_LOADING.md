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
timing or a game boot. Standalone full-size copy implementation is pending.
