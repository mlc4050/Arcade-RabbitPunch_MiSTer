# High-score reference and persistence boundary

MAME 0.289's plugins/hiscore/hiscore.dat identifies these work-RAM byte blocks:

| Set | First byte | Length | First/last initialization bytes | Native work-RAM words |
|---|---:|---:|---:|---:|
| rabiolep | 0x0FFE01 | 0x77 (119) | 00 / 80 | 0x1F00 through 0x1F3B |
| rpunch | 0x0FFE01 | 0x73 (115) | 00 / 17 | 0x1F00 through 0x1F39 |

capture_hiscore_reference.py pins the data file SHA and driver/release version,
then checks these initialization sentinels in live MAME without loading the
hiscore plugin or writing memory. Both become ready on captured frame 8.
Initial block bytes remain private in debug; reference/hiscore_reference.json
records their hashes, readiness and byte geometry. These markers are MAME's
plugin loading convention, not an original-board nonvolatile storage feature.

The block begins on a lower-byte lane and has odd length, so persistence needs
byte strobes and must preserve the preceding upper byte in its first word.
Both final bytes also occupy lower lanes. A single generic byte engine must
use the selected set's length; treating the two score tables as identical
would copy unrelated US RAM bytes.

Existing work-RAM inspection can read the region while the main CPU is paused.
Production maintenance now provides acknowledged byte reads/writes through
the existing work-RAM CPU port. The HPS score service now requests pause, waits for CPU/bus drain, and uses masked RAM
writes without resetting memory, preserves neighboring bytes, and releases pause
only after accepted accesses complete. Score polling/load/save is scoped
per ROM generation and set. The host boundary and logical platform now connect uploads and restoration; physical MiSTer disk testing remains pending.
The reference capture itself does not establish persistence; HDL checks are listed below.


The standalone rabbitpunch_maintenance byte adapter now passes actual native
RAM tests for both geometries using captured MAME bytes with deterministic
interior changes to stand in for a saved file. It waits for both confirmed CPU
pause and an externally asserted drained bus before accepting work. Big-endian
byte masks preserve the preceding byte and following word; reads return the
correct lane. It holds pause through an accepted memory access even after the
client ends its session. Initialization discards a pending client result only
after draining its backend reply. Delays of 0..51 and 300 clocks are checked
(reference/maintenance_checks.json). It is now connected to the production
bus owner; HPS score upload/restore uses this path through the maintenance-client arbiter. No maintenance access
bypasses the existing RAM port or adds pixel buffering.

The inspected standard hiscore.v helpers use a configured pause-padding delay
rather than a transaction-ready handshake. That contract cannot directly drive
our delayed CPU-bus interface. Any future wrapper must preserve confirmed pause
and byte access acknowledgment; a fixed padding count is not an acknowledgment.

## Acknowledged atomic score store

`rabbitpunch_hiscore.vhd` is a single-clock VHDL client of the production
maintenance byte interface. Validated per-game metadata selects the two table
geometries above. The HPS configuration parser and logical platform composition are now connected;
the physical release shell remains pending.

A 256-byte native dual-port M10K contains two 128-byte banks. Downloads and
snapshots populate the inactive bank; a complete transaction switches the saved
bank atomically. Partial, reordered and oversized downloads preserve the previous
valid image. Gameplay reset abandons a partial snapshot and preserves the saved
image; a new ROM generation invalidates it. The maintenance adapter must receive
the same reset so it drains backend debt and suppresses canceled client replies.

Initialization checks the MAME first/last sentinels before restoring a valid
file. Those checks do not apply to saved bytes or later snapshots: legitimate
scores may change the sentinel positions. With no input file, the first ready
table is captured so the first run can still be saved. Startup and retry waits
are explicit clock-count inputs for the forthcoming metadata parser.

Opening the OSD captures the initialized table. Changed bytes mark it dirty;
autosave requests one native upload for the dirty snapshot while OSD is open.
Turning autosave off retains a manual-readable snapshot. Completed uploads clear
dirty state. Host data writes must honor `o_dump_wait`; announcing a transfer
while busy does not prevent outstanding maintenance responses from completing.
The saved bank remains stable throughout an upload.

`run_hiscore_tests.py` uses both pinned MAME initialization captures and native
score/work RAM. It checks restoration with modified first/last saved bytes,
byte lanes and neighbors, delayed pause/acknowledgment, unchanged snapshots,
autosave toggles, malformed downloads, canceled capture debt and first-run save
readiness. See `reference/hiscore_checks.json`. This is a unit-level score-store
proof, not an on-disk `.nvm` persistence claim.

The descriptive `rabbitpunch_host` wrapper now exposes native upload request,
index, read pulse, active flag and data. Its fitted functional-netlist test
reads 119 bytes from a synchronous data source across seven commands and checks
request polling/rearming. Existing native download/control platform tests also
pass. No `sys` source was modified.


`rabbitpunch_hiscore_config` accepts the standard 16-byte header plus one
8-byte record with two-byte length. Address, length and guard bytes must match
one of the two pinned MAME definitions. The supported descriptor has CHECK_HOLD
and WRITE_HOLD = 2, WRITE_REPEATCOUNT = 1, WRITE_REPEATWAIT = 0,
ACCESS_PAUSEPAD = 0 and CHANGEMASK = 0. Acknowledged memory replaces fixed pause
padding; repeated writes and masks are not supported. Full-width START_WAIT and
CHECK_WAIT remain programmable clock counts. Invalid metadata disables the
profile and sets a diagnostic error. No unsupported field is silently ignored.

`rabbitpunch_hiscore_service` composes the parser with the store at standard
indices 3 and 4; ROM index 0 invalidates both profile and saved image. Its memory
initialize output must also reach the production maintenance helper so canceled
client state never strands real backend debt. The composed service passes the
same native-memory tests through real index-3 configuration transfers, including
first-run readiness, soft reset restore, concurrent upload bank stability and a
download announced while RAM work is outstanding. See
reference/hiscore_service_checks.json and hiscore_config_checks.json. Production logical platform composition and development MRA metadata are connected;
physical MiSTer/disk testing remains pending.


## Logical platform composition

The platform connects the score service and an exclusive maintenance-client
arbiter to the existing byte helper. External state/debug sessions have idle
priority. An ended session retains ownership through its accepted byte reply;
neither client can steal an active session. Score reconfiguration cancels only
score-owned helper work and preserves backend draining. ROM/game reset retains
the existing full-system cancellation/drain rules.

The standard service uses host indices 3/4 and status bit 3 for autosave.
`ou16_host_menu_mask(3)` hides the option until a valid profile exists. No
original-board battery RAM is inferred: MiSTer software persists the snapshot.

The development MRAs load ROM0, then the 24-byte score configuration, then
`nvram index=4` with decimal size 119 or 115. The generated metadata uses a
48,000,000-clock startup wait (one second at the evaluation clock), 65535-clock
retry wait, acknowledged hold descriptors of two, one write pass and no change
mask/padding. These are software loading-policy waits, not measurements of board
clock timing. Subsequent sentinel checks still gate restoration.

Main_MiSTer's [MRA loader](https://github.com/MiSTer-devel/Main_MiSTer/blob/master/support/arcade/mra_loader.cpp)
processes sections in document order, loads an existing `config/nvram/<MRA>.nvm`
at the nvram node, and uploads exactly its declared size when saving. It derives
the separate DIP filename `<MRA>.dip` and sends selected DIP bytes at index 254.
The FPGA never opens either file. No input `.nvm` means no index-4 download;
first-run capture in the score service covers that case.

`run_platform_hiscore_tests.py` uses actual generated MRA metadata (only startup
and retry waits accelerated to 30/19 clocks), both captured MAME table geometries,
the full platform, executing fx68k, shared SDRAM/chip model and native work RAM.
It checks CPU-consumed restored bytes, external maintenance arbitration, changed
OSD snapshots, uploads, soft-reset restore, ROM-generation isolation and preserved
DIP state. Native HPS strobe-to-file behavior and the physical `.nvm` disk round
trip are separate evidence boundaries.


Native HPS composition now passes `run_platform_hiscore_tests.py --host-netlist`
for both sets (reference/platform_hiscore_host_checks.json). It sends actual
FIO55/FIO53/FIO54 command strobes through the checked Quartus hps_io netlist,
loads ROM0/DIPs/config3/dump4, verifies the executing CPU's restored word, polls
UIO3C for the autosave request and reads all score bytes through native uploads.
UIO2E verifies menu masking before/after a valid profile. Configuration readback,
standalone 119-byte upload and prior connected controls/download tests pass too.
HPS bus responses are sampled while their channel is selected; test-master
strobes span an accepting clock edge even when called after a registered event.

Main_MiSTer's [menu implementation](https://github.com/MiSTer-devel/Main_MiSTer/blob/master/menu.cpp)
checks pending arcade uploads in MENU_SAVE_CHECK on entry to the normal core or
core-selection menu; Save settings also calls arcade_nvm_save. The native request
is a latch in unchanged hps_io, consumed by a UIO3C poll. Generation clearing in
the score service prevents retained score bytes crossing games. Physical menu
behavior, unusually early exit before initialization, and disk-file persistence
still require the final MiSTer shell/hardware test; the simulation does not run
the ARM menu software.


Gameplay reset does not reject host score files. File downloads, atomic bank
commit, upload readback and upload-completion bookkeeping continue while the
CPU is held reset; game-RAM restoration remains blocked until reset releases
and initialization sentinels match. Unit/service tests check reset-held loading
and upload completion, and direct/native full-platform tests hold status reset
through config3/dump4 before checking the CPU's restored word. The preceding
controller fails the new unit test at the expected reset-held-load assertion
(private debug/baselines/hiscore_reset_unfixed/negative_control.json). All final
positive report source/log hashes were checked before this commit.
