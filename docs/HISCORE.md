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
There is no production maintenance write port or HPS score upload/restore path
yet. Future restore must request pause, wait for CPU/bus drain, use masked RAM
writes without resetting memory, preserve neighboring bytes, and release pause
only after accepted accesses complete. Score polling/load/save must be scoped
per ROM generation and set; the existing host prototype disables uploads.
This reference does not claim persistence is implemented or verified in HDL.
