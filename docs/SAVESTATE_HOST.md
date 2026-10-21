# Savestate host and DDR interface

The four-slot service, OSD actions and controller shortcut are connected in the
production VHDL composition. Both ROM sets pass continuation diagnostics, and
the host controls pass native protocol tests. Manual savestate save and restore
work on MiSTer hardware; broader persistence and display-mode checks have their
own scope. See [SAVESTATES.md](SAVESTATES.md) for current evidence.
The interface audit below retains its original design rationale and intermediate
qualification limits. No `sys/` changes are required.

## Address reservations

Use four 256 KiB slots, compatible with the local NMK16 implementation:

| Slot | DDR byte range | DDR 64-bit word range |
|---|---|---|
| 1 | 0x3E000000..0x3E03FFFF | 0x07C00000..0x07C07FFF |
| 2 | 0x3E040000..0x3E07FFFF | 0x07C08000..0x07C0FFFF |
| 3 | 0x3E080000..0x3E0BFFFF | 0x07C10000..0x07C17FFF |
| 4 | 0x3E0C0000..0x3E0FFFFF | 0x07C18000..0x07C1FFFF |

Current configured reservations are scaler 0x20000000..0x217FFFFF, rotation
0x24000000..0x257FFFFF and ROM staging 0x30000000..0x3020FFFF. The proposed slots
are pairwise disjoint, below 0x40000000 and within MiSTer's conventional HPS
extra-RAM window. Integration must assert these bounds against current RTL.
Arbitrary externally supplied framebuffer addresses are outside this audit.

The first eight bytes of each slot belong to Main's standard control word:
bits 31..0 are a change counter, bits 63..32 are payload length in 32-bit words.
Payload starts at slot+8 and is bounded by 262136 bytes / 65534 words. Its own
versioned board format must include ROM identity, section sizes and integrity
checks. An empty slot has zero payload length. The 106496-byte writable RAM
image leaves ample room for the bounded CPU/chip/register payload, but the
final section layout still needs implementation and validation.

The isolated `rabbitpunch_state_preflight` implements a 64-byte board header
after the standard host control word. Its words are magic (`RPS1`), packed
header-size/version, ABI signature, ROM CRC, body byte length, body CRC,
configuration identity, total payload byte length, six exact section byte
lengths, header CRC and reserved zero. All words are little endian. Header CRC
covers its first 56 bytes; body CRC covers all body bytes, independently of ROM
identity. Main's mutable change counter is excluded from these checks.

Preflight consumes valid/ready bytes and final completion before publishing a
valid result. It checks live ROM/config identity again at completion. The
21-case isolated test includes independent body-CRC data, backpressure gaps,
simultaneous final byte/completion, compatibility/CRC/size failures, overflowing
section values, early end, excess data, abort/late bytes and valid retry. Exact
hashes are in `reference/state_preflight_checks.json`.

This is not a complete restore validator: CPU/beam/cadence field legality must
also pass before application, and the source slot must stay immutable between
preflight and load. No write port exists in this checker. The final six-section
body layout and ABI signature still need to be connected to the machine service;
the current OSD does not expose this provisional format.

## Publication and restore

The functional configuration prefix will be `RabbitPunch;SS3E000000:40000;`.
Read the current change counter before save, and publish a different counter
only with a complete payload. Main initializes counters to FFFFFFFF when it
prepares slots for a ROM launch, so a private counter initialized to zero is
insufficient. Write the size/counter control word last. A failed save must not
publish a new counter. Restore must validate nonzero/bounded length, format,
ROM compatibility, section bounds and checksum before changing game state.

Current upstream Main polls this interface approximately once per second and
persists changed nonempty slots. There is no SD-card write-success response to
the FPGA: save completion means a committed DDR image, not synchronous file
durability. The host API also supplies no copy lock or acknowledgement for a
rapid rewrite of the same slot while Main copies it. Header-last publication
alone does not prove concurrent host-copy safety; retain integrity validation
and do not claim atomic disk persistence from a DDR completion pulse.

Upstream stores arcade files under `savestates/Arcade/<MRA basename>_<1..4>.ss`,
with a legacy unsuffixed slot-1 fallback. The installed Main binary was not
queried during this audit. References: [MiSTer savestate interface](https://mister-devel.github.io/MkDocs_MiSTer/developer/savestates/),
[Main user_io.cpp](https://github.com/MiSTer-devel/Main_MiSTer/blob/master/user_io.cpp),
[Main file_io.cpp](https://github.com/MiSTer-devel/Main_MiSTer/blob/master/file_io.cpp).

Local pinned references are `D:/git/Arcade-NMK16_MiSTer` at
`4c9b923a87dcefee27574a8a06361e47e8e9b963` (`rtl/savestate/savestate.sv`,
`savestate_ui.sv`, `NMK16_Gunnail.sv`) and `D:/git/Arcade-KonamiGX_MiSTer` at
`89124d4f29e1d3f95557e5e5265efcbe9d0d7cb4` (`rtl/gx_ss_ddr.sv`). Keep imports
unchanged; new transport/control logic is VHDL.

## Shared transport

Loader ownership remains exclusive until its last DDR response and downstream
SDRAM write drain. State operations defer/reject while loading or not ready.
During play, queued rotation writes precede single-beat state commands. Keep
the existing rotation queue; its raw producer cannot be stalled.

`rabbitpunch_state_ddr_arbiter` implements this boundary in isolation. It
qualifies command strobes with physical readiness, tracks accepted read beats
and tags responses to their original reader. New reads serialize; rotation
writes may use gaps during pending state read debt. Initialization and caller
cancellation do not clear accepted debt. Loader takeover waits for late state
responses, and late loader responses never become state data. Clients must
consume/discard their own cancellation responses and obey BUSY. Writes are
single beat; loader reads may contain 1..255 beats. Current ROM staging uses
one beat.

`reference/state_ddr_arbiter_checks.json` pins the isolated test: cancellation,
initialization during debt, three/255-beat bursts, priority, masks and stalls.
This is not a production rotation/loader or physical DDR qualification. The
current production rotation transport still assumes the loader is the sole
reader and must be replaced by this explicit ownership boundary on integration.
State acquisition must also serialize NVRAM/hiscore RAM borrowing and upload.

## Ordered slot writer

The isolated `rabbitpunch_state_slot_writer` reads the existing host control
word, invalidates its length while preserving the old counter, streams an
immutable payload to the latched slot, then publishes its
length and changed counter in the final DDR write. The counter skips the host's
`FFFFFFFF` startup sentinel, including at wraparound. Cancellation/reset keeps
accepted read debt owned until its response arrives; no new save starts during
that drain. The parent must connect full-byte enables and one-beat bursts through
the shared arbiter and supply a validated board header followed by its body.

Tests cover all four slot addresses, five successful saves, stalled source/DDR,
counter wrap, ten partial-stream cancellations, cancellation on the commit edge,
and cancellation/reset with a pending or simultaneous read response. See
[state_slot_writer_checks.json](reference/state_slot_writer_checks.json).
Success means ordered DDR command acceptance. It does not acknowledge an SD
write or provide a lock against a concurrent host file copy. A canceled save
leaves the slot empty once invalidation has been accepted, including cancellation
after the final payload byte. A save canceled before invalidation preserves the
old image. The reader rejects zero length with a nonzero preserved counter.
Whole-machine integration is still pending.

## Restore staging reader

`rabbitpunch_state_slot_reader` reads the outer control word, checks nonempty
and exact payload length, then copies payload bytes into private staging with
backpressure. It rereads the control word after the last payload byte and
rejects a changed counter or length. Cancellation/reset drains accepted DDR
reads before releasing ownership. No output directly writes game state.

The integrated native test connects the reader to the actual private image RAM
and preflight validator. It passes valid receipt, stalls, empty/length rejection,
changed control word, canceled read debt, corrupted-body rejection and a later
valid retry. See [state_slot_reader_checks.json](reference/state_slot_reader_checks.json).
The parent seals only after successful receipt, validates that immutable copy,
then checks CPU/board field legality before application. The outer-word recheck
does not supply a general host lock; CRC validation remains required.

## OSD and feedback

Re-audit free status fields before wiring. The proposed fields on this branch
are slot 6..5, autoincrement 7, save action 8 and restore action 9. Existing
Save NVRAM remains T4. The four controls belong after Save NVRAM, separated by
blank lines, with Reset last. Actions remain hidden until the full service is
functional.

Expose defaulted typed `status_in`, `status_set`, `info` and `info_req` ports
through `rabbitpunch_host`; unchanged `hps_io` already supports them. Pulse each
strobe with a low gap. Edge-detect actions, latch operation and slot at acceptance,
and reject busy/loading requests. Increment only after successful save. Preserve
all unrelated status bits and clear action bits in feedback to avoid retriggers.
Completion messages refer to the latched operation slot, not the incremented
selection. Track actual host slot changes so a stale status echo does not undo
autoincrement. Distinguish empty, incompatible, checksum and transport failures.

The NMK16 message convention uses saved-slot codes 6..9, restored-slot codes
10..13, failure 14 and empty 15, with corresponding CONF_STR I strings. No
keyboard controls are required by the current request. F2 is already TEST;
optional future shortcuts must avoid that binding.
