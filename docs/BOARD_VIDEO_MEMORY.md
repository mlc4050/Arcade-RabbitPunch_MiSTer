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
for both games pass again, including 24 reconstructed board I/O fields each.

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

## Foreign-port synthesis audit

A review of constant-ROM-address warnings exposed a pre-existing tile/sprite
adapter problem. The unchanged JTFRAME port is declared [CW+6:2] in Verilog.
The old VHDL components declared the same width but indexed it CW+4 downto 0.
RTL simulation mapped those ports positionally; Quartus synthesis retained a
shifted/truncated connection. A Quartus-exported tile netlist fails the existing
ROM-address assertion at 115 ns even though the RTL test passes. The adapter
now preserves the vendor port indices exactly, including its internal wire,
and translates to the descriptive zero-based external address explicitly.

RTL tile and sprite regressions pass after the change. Synthesized-netlist
checks reuse the existing VHDL testbenches through component binding, compiling
only the exported netlist plus test support. The corrected tile netlist passes all 8256 queued rows and 66048 pixels. The
corrected sprite netlist passes 30724 rows including reset recovery, with 491589
checked pixel events. Both pass implementation and timing without constant
graphics-address warnings. Full shared-RAM RGB replays remain in progress. Earlier RTL pixel
comparisons remain valid simulation evidence; passing timing alone did not
establish graphics-address functional equivalence in synthesis.

The corrected combined board/video seed-2 implementation was rejected for
-0.045 ns hold slack from the virtual i_reset input to sprite-line view-valid
state at the slow 1100 mV/-40 C corner. Setup passes. The evaluation project
now pins seed 3 for a fresh placement, with the same RTL and constraints.
The timing gates remain strict; a successful fit must pass every corner.

## Replay diagnostics

The first parallel shared-RAM run exceeded its 600-second wall-clock guard in
Rabbit Punch play1000. The focused serial rerun completes in about 263 seconds,
with all 62208 RGB pixels identical and 83832 competing work-RAM writes; its
live bitmap/palette update and reset checks pass. Remaining scenes now run
serially. The simulator's Starter capacity warning is expected for this design;
progress.txt records simulated time, completed lines/pixels and CPU writes. A
20000-clock no-progress guard detects a pipeline stall separately from slow wall
time. Timeout paths retain the partial transcript. The known numeric_std warnings
at time zero occur while the inactive backend's combinational target settles;
they are not valid-data comparison failures. Tests do not suppress warnings.

Seed 3 also failed hold (-0.113 ns worst). The fitted settings report already
shows Optimize Hold Timing = All Paths and Multi-Corner Timing = On, so adding
those assignments would be ineffective. The evaluation project retains seed 3
and requests maximum router timing optimization plus timing ECO optimization.
RTL, clock period, I/O constraints and strict timing gates are unchanged.


## Registered implementation evaluation

The direct virtual-input project exposed input-to-register hold failures. At
seed 3 with maximum router effort and timing ECO enabled, the worst reported
hold is -1.254 ns from a virtual CPU byte-enable input; the internal
register-to-register hold at the inspected slow/-40 C corner is +0.212 ns.
The previous 0 ns input-delay model launched from the external clock pin while
the register clock arrived roughly 4.65 ns later. These reports do not establish
a clock-domain crossing or a long combinational setup path.

The isolated project now uses board_video_check.vhd, an evaluation-only wrapper
with same-clock launch and capture registers on every non-clock interface.
Synthetic virtual inputs change half a period after the external rising edge;
virtual output delays are zero. All boundary-register-to-DUT and DUT-to-boundary
paths, along with every internal path, retain the normal single-cycle setup
and same-edge hold checks. No false paths or multicycle exceptions are added.
This explicit tester contract is not a claim about final external pins; the
wrapper is absent from production RTL and adds no game latency. Final MiSTer
integration, PLL and SDRAM timing still require their own implementation.
Maximum router/ECO experiments are removed; seed 3 remains fixed. The new fit
must pass the existing all-corner timing, coverage and RAM-count gates.
