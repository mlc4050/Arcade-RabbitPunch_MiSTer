# Fixed-latency RGB output alignment

rabbitpunch_video_output aligns external pixel-enable, active, sync, blanking
and coordinate metadata with the native RGB renderer. It generates no raster
or clocks, makes no assumption about physical totals/polarity, and adds no
pixel row/frame storage. The current native pipeline returns RGB four edges
after acceptance; the adapter captures RGB and matching metadata on edge five.
Every output pixel-enable, including blank slots, retains that fixed delay.
Output pins hold between enabled pixels.

A late/missing response, mismatched returned coordinate, renderer tag error or
rejected request produces black for that active slot and latches underflow until
reset. Physical pixel cadence never waits for rendering. Blank slots generate
no pixel request and output black. Reset flushes metadata and clears the fault.
This makes a timing shortfall visible instead of adding buffering or reusing
stale RGB. The adapter does not correct an unfinished line or choose when to
render the next line.

video_output_tb passes 420 slots covering sparse enables, independent sync and
blank transitions, all four failure paths, retained faults and reset flush
(reference/video_output_checks.json). A native-renderer capture comparison is
in progress; physical PLL/raster/pin timing and the MiSTer shell remain open.


The first adapter fit was rejected by its zero-RAM gate: Quartus inferred an
altshift_taps coordinate delay using 68 block RAM bits. That implementation
commit was reverted and corrected by resetting the coordinate delay registers
together with metadata. No pixel storage or additional latency is introduced.
The first complete Rabio Lepus gameplay replay matched all 62208 MAME pixels;
the corrected register-only implementation and six-scene replay are pending.
