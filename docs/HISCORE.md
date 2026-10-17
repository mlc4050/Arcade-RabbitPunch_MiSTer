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
the existing work-RAM CPU port. The HPS score upload/restore path is still open. Future restore must request pause, wait for CPU/bus drain, use masked RAM
writes without resetting memory, preserve neighboring bytes, and release pause
only after accepted accesses complete. Score polling/load/save must be scoped
per ROM generation and set. The host boundary exposes uploads; platform persistence composition is still pending.
This reference does not claim persistence is implemented or verified in HDL.


The standalone rabbitpunch_maintenance byte adapter now passes actual native
RAM tests for both geometries using captured MAME bytes with deterministic
interior changes to stand in for a saved file. It waits for both confirmed CPU
pause and an externally asserted drained bus before accepting work. Big-endian
byte masks preserve the preceding byte and following word; reads return the
correct lane. It holds pause through an accepted memory access even after the
client ends its session. Initialization discards a pending client result only
after draining its backend reply. Delays of 0..51 and 300 clocks are checked
(reference/maintenance_checks.json). It is now connected to the production
bus owner; HPS score upload/restore remains separate (MAINTENANCE.md). No maintenance access
bypasses the existing RAM port or adds pixel buffering.

The inspected standard hiscore.v helpers use a configured pause-padding delay
rather than a transaction-ready handshake. That contract cannot directly drive
our delayed CPU-bus interface. Any future wrapper must preserve confirmed pause
and byte access acknowledgment; a fixed padding count is not an acknowledgment.

## Acknowledged atomic score store

`rabbitpunch_hiscore.vhd` is a single-clock VHDL client of the production
maintenance byte interface. Validated per-game metadata selects the two table
geometries above. The HPS configuration parser and platform composition remain
pending; this module is not connected to the release shell yet.

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
