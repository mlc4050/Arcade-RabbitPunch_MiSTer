# CPU and video BRAM integration

`rabbitpunch_board_memory.vhd` owns the same five native RAM banks previously
inside rabbitpunch_memory. The old entity is now a CPU-only compatibility adapter;
it instantiates this backend with video reads disabled. `rabbitpunch_board_video.vhd`
connects the backend directly to rabbitpunch_rgb_video, sharing physical source RAM
between CPU transactions and video. All logic and both ports of every RAM use i_clk.
No RAM has been duplicated for the renderers.

## Port contract

Each bank retains its CPU read/write port. Bitmap and palette have independent
fixed one-clock native video reads. Sprite and tile descriptor request pulses
return data with a one-clock registered valid signal; there is no outstanding
external descriptor transport in this wrapper. Graphics and CPU program ROM
requests still go to external responders. There is no physical raster or SDRAM
controller here.

CPU requests remain pulses with one outstanding transaction and one response.
Reads, and writes to another word, retain the original RAM response latency.
Same-address CPU reads and video reads can run together. A same-word write is
held internally until that bank's read port stops reading that word; video can
continue reading another word in the same bank. The backend retains the original
address, data, byte lanes and target while waiting, then acknowledges only after
committing the write. This avoids undefined mixed-port read/write behavior,
including partial byte writes and globally mirrored CPU addresses.

Video/inspection reads win collisions. This is a conservative FPGA scheduling
policy, not a measured claim about the original PCB's RAM ownership timing.
A continuously conflicting reader can delay a CPU write indefinitely; the final
raster schedule must provide safe slots and verify worst-case waits. No CPU reset
input clears RAM or discards an accepted request. Video reset only flushes derived
renderer state; board RAM and accepted CPU work survive.

Inspection borrows a bank's video port after that consumer has paused and drained.
It may run alongside other banks. A clocked assertion rejects simultaneous
inspection/video requests to the same bank. Inspection returns raw stored values,
without future CPU cheat-read overrides. CPU writes colliding with inspection
are held by the same arbitration.

## Verification status

The VHDL board_memory_video_tb checks all four video banks reading in parallel,
concurrent CPU work-RAM reads/writes, same-address CPU/video reads, held writes
for all three active byte-lane combinations and mirrored addresses. Inputs are
changed after each request pulse to verify pending request retention. It checks
that moving a video read to a different word releases a write without disabling
the bank, and tests raw inspection with a colliding CPU write. There are 849
checks and 324 intentionally held cycles; no simulator errors or warnings.
Results and source hashes: reference/board_memory_video_checks.json.

Existing board diagnostics also pass through the compatibility adapter, including
all 52224 RAM words, bank isolation, byte lanes, mirrors, inspection, delayed ROM,
CPU pause/reset and IRQ/autovector handling. The real-ROM 10000-write boot replays
for both games are rerunning at this checkpoint.

The scene bench now preloads actual shared board RAM through CPU transactions,
then issues continuous work-RAM writes while rendering and scanning out. It also
contains a directed live update: CPU writes force bitmap pen 1 at X=8/Y=0 and
set its palette entry green; the next requested pixel must be 00FF00. Its original
62208 screenshot pixels are recorded before this modification. Reset is tested
with an external graphics ROM response pending and a pixel in flight. The initial
shared-RAM title replay passes; the complete six-scene/live-update regression
and combined board/video implementation/timing check are in progress.

The isolated board_video target requires 868352 RAM bits: the five source banks
plus four line banks, with no duplicate source memory. This is still a virtual-I/O
block, not a full MiSTer core. CPU transaction stimulus in the scene bench is not
an executing fx68k; the boot replay separately exercises the real CPU adapter.
