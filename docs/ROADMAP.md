# Rabbit Punch / Rabio Lepus MiSTer roadmap

Approved by the user in the originating chat. Local framework bootstrap and source
reference setup are complete. CPU/JTFRAME evaluation copies and initial baseline tests
are now checked in. The shared ROM/control layout, VHDL address decoder and bus
request adapter are implemented and tested. A descriptive fx68k adapter and CPU phase
generator pass diagnostic tests. Five VHDL RAM banks pass full-address tests, and
both real ROMs match MAME's first 10000 writes through that memory backend.
Board I/O, GGA storage, sound mailbox interface and level-1 autovector handling
pass directed tests; full raster and sound integration remain open.
The complete game is not integrated/running yet.
Hardware evidence and local source citations: [HARDWARE_NOTES.md](HARDWARE_NOTES.md).

## Goal and scope

Build one DE10-nano core supporting `rabiolep` and `rpunch`, producing an RBF and an MRA
for each game. New board logic, CPU bus adapters, graphics adapters, bitmap logic,
registers and board tests will be VHDL. Directly reuse applicable JTFRAME tile/sprite,
RAM and timing modules in their original HDL; the user explicitly approved this.
Reuse fx68k (SystemVerilog) for the main 68000 and T80 (VHDL) for the Z80. Initial
TG68K.C evaluation passed functional tests but missed 68000 instruction timing;
the directly compared fx68k baseline matches the tested loop (BASELINES.md).
Proposed framework, SDRAM transport, and sound reuse are mixed-language dependencies;
this proposal does not promise an entirely VHDL source tree. Retain MiSTer `sys/` unchanged.

Target the user's one Mister Addons 128 MB SDRAM module, with ROM addresses entirely below 32 MiB.
No second module and no game-data DDR3 access during gameplay are proposed.
MiSTer framework video rotation/scaling may independently use HPS DDR3.
Load-time DDR ROM staging is a later standard feature.

First reference set: `rabiolep` (MAME parent), followed by `rpunch`; bring-up order can
change based on available lawful local ROMs and executable behavior. Super Volleyball
is excluded from the first scope. No remote repository has been created or published.

## Research status and open decisions

- Local repository: `D:/git/Arcade-RabbitPunch_MiSTer`,
  branch `develop`. Both Quartus revisions exist; template demo remains connected.
- Pinned framework `9c8eadb40067c8ce3aef90899844f62d688ac73a`; comparison of sys
  against fetched source passes when ignoring checkout end-of-line differences.
- `scripts/reference_manifest.py` generated ROM metadata, including explicit fills;
  both games' DIP self-check passes. Capture regions are configured for this board.
- User's merged `rabiolep.zip` contains all 18 required files per set, verified by
  uncompressed length and CRC of actual data. No ROM bytes were copied into this repository.
- MAME checkout identifies as `mame0289-1577-g00ab4817bd7`; the three inspected board
  files have no working-tree changes. It is newer than release 0.289, so a release binary
  must use a separately pinned matching source before captures become trusted references.
- Quartus Lite 17.0.2/602, Cyclone V support, ModelSim Starter 10.5b and MAME 0.289
  are installed/configured. The mixed-language simulator check passes. Reference source
  is now pinned to matching mame0289; both sets pass MAME ROM verification and have
  first captures and coarse write sweeps. See TOOLCHAIN.md for evidence and remaining gates.

- Located board driver and GGA device; recorded local MAME HEAD and memory maps.
- Counted declared/file-loaded ROM storage from both sets: 2.0625 / 1.3125 MiB each.
- Pinned CPU/JTFRAME evaluation sources, ran unchanged donor CPU tests, and checked
  JTFRAME row/buffer interfaces. Selected fx68k after measured timing comparison;
  see BASELINES.md and reference/vendor_manifest.json. Sound modules remain candidates.
- Physical sync timing, per-field write timing, continuous-play coverage, game CPU/RTL
  validation and actual Quartus fit remain open. Installed tools are not a game build.
- Mixed-language sound and direct JTFRAME reuse are approved. New board-specific
  logic remains VHDL. Module selection and evidence are in FRAMEWORK_DECISION.md.
- Development MRAs for both games are generated under releases/_dev. Their complete
  0x210000-byte streams match independent source assembly and actual MAME-loaded ROM
  regions; XML/DIP/button/version checks pass. See BOARD_INTERFACE.md and reference/mra_checks.json.
- First clock-independent board interfaces pass: 67 decoder boundary/lane/mirror checks,
  and bus transactions with delayed responses, held strobes and CPU-reset reply draining.
  They are not connected to the MiSTer top-level or compiled into an RBF yet.
- CPU integration diagnostic passes word/byte readback, 0/17/65-clock response delays,
  pause and reset replay. Real-ROM early-boot comparisons match the first 10000 writes
  for both games exactly using the actual VHDL RAM backend. ROM transport and board
  inputs remain behavioral; board I/O is VHDL, and
  this prefix does not establish a full boot. See BOARD_INTERFACE.md and reference/boot_checks.json.
- Main RAM/ROM backend: five banks totaling 52224 words, byte strobes, synchronous
  CPU and read-only inspection ports, serialized external ROM handshake. Every RAM
  word and independent banks are checked (104486 assertions/checks). No CPU-reset
  RAM clear or request cancellation. Quartus inference/packing/timing remain open.
- Board register/mailbox/GGA and IRQ scheduler tests pass. A real fx68k program
  verifies STOP -> level-1 autovector -> stack -> handler -> RTE via VHDL RAM.
  Boot comparison checks 24 I/O fields reconstructed from MAME writes. Physical
  raster events are not generated in that bounded test yet.

## Component reuse candidates

The expanded local survey and MRA deliverables are in [REUSE_SURVEY.md](REUSE_SURVEY.md).
It distinguishes reused chip cores, adapted video pipeline designs, and new VHDL board glue.

These are inspected local candidates, not vendored or validated for Rabbit Punch yet.
Exact donor commits, dirty-tree checks, copied file hashes, full dependency lists, and
unaltered baseline tests must be captured before accepting them.

| Block | Candidate | Evidence / licence |
|---|---|---|
| 68000 | `rtl/cpu/fx68k/`, from Seta | GPLv3; unchanged donor loop test matches 14 clocks; TG68K evaluation retained for comparison only |
| Z80 | `D:/git/Arcade-Psikyo_MiSTer/rtl/cpu/t80/` | PROVENANCE.md; MiSTer T80 830fd0315f0af5cdbcb0e703f1cea3ce4e91f538; BSD-style; VHDL |
| YM2151 | `D:/git/Arcade-JalecoMS1BCD_MiSTer/rtl/third_party/jt51/hdl/jt51.v` | Header GPLv3+; Verilog; exact donor version pending |
| uPD7759 | `D:/git/Arcade-SystemC2_MiSTer/rtl/jt7759/hdl/jt7759.v` | Header GPLv3+; Verilog; standalone mode, bank/reset/start adaptation required |
| SDRAM | `D:/git/Arcade-Seta_MiSTer/rtl/memory/sdram/` | PROVENANCE.md; GPLv3+ inherited transport; verify supported geometry and read-data fixes |
| Framework | MiSTer-devel/Template_MiSTer | Fetch and pin at bootstrap; wrapper uses framework HDL; no sys edits |
| Tile/sprite primitives | Direct JTFRAME module reuse with VHDL board adapters | See FRAMEWORK_DECISION.md for candidate versions and test gates |
| Board bitmap/mixer/GGA/bus | New VHDL | MAME behavioral reference; no certified board video RTL has been identified |

For sprites, directly integrate suitable JTFRAME object engines through board-specific
VHDL scheduling and graphics-address adapters. Verify licence obligations for reused logic.
Provisional overall distribution licence: GPL-3.0-or-later, subject to full dependency audit.

### Additional examples from the user's meatsauce checkout

`D:/git/meatsauce/README.md` identifies this as the source collection for Meatcores.
Initial inspection found these useful architectural references; they are different boards,
not Rabbit Punch hardware descriptions:

- `cores/ikki/rtl/ikki_video.sv`: 16 x 32 sprites, M10K line buffers, and an interface
  tracking sprite-RAM writes for snapshot collision handling. Inspect the full schedule
  before adapting ideas to VHDL; Rabbit Punch's actual latch point still needs its own sweep.
- `cores/MCR-68K/rtl/mcr68_addr_decode.sv` and `mcr68_main_board.sv`: 68000 address decode
  and main-board integration examples. They use fx68k, so they are bus-contract references
  rather than a direct TG68K wrapper donor.
- `cores/escapekids/rtl/vendor/jtcores/modules/jt51/hdl/`: another local JT51 candidate;
  compare provenance, version, and integration tests with the current donor before choosing.
- `cores/Suna8bit/rtl/suna8_sprite_render.sv`: inspected header describes full-frame
  rendering and a simplified priority model. Do not copy that rendering architecture:
  Rabbit Punch's separate bitmap RAM does not justify frame-buffering all composited layers.

Most inspected board glue here is SystemVerilog. Use these examples to check interface,
memory, and verification choices while keeping the new Rabbit Punch board modules VHDL.

## Clocks and memory

Start evaluation near 48 MHz for system/video and SDRAM. No final PLL or pixel divider
can be selected from this driver: its 6.6665 MHz GGA input is not a proven pixel clock,
and 304 x 224 is not a measured physical raster. Obtain schematics/raw timing evidence
or explicitly approve a documented provisional output timing before video RTL.
Require an exact integer pixel-enable divider >= 4, system clock >= board clocks,
and prefer SDRAM at system rate. Any increase needs bandwidth measurements.

If 48 MHz survives the timing investigation, logical 8 MHz, 4 MHz, and 640 kHz enables
have ratios 1/6, 1/12, and 1/75. These are conditional examples, not a committed clock
plan; TG68K and Yamaha modules may require additional internal enable phases.
CPU effective execution/bus timing must be measured, not inferred from enable labels.

Proposed selected-set SDRAM byte layout, to become generated constants after approval:

| Start | End inclusive | Region |
|---|---|---|
| 000000 | 03ffff | maincpu |
| 040000 | 04ffff | audiocpu |
| 050000 | 0cffff | tiles1 |
| 0d0000 | 14ffff | tiles2 |
| 150000 | 1cffff | sprites |
| 1d0000 | 20ffff | upd |

The runtime layout above totals 0x210000 and preserves all declared regions. Validate
the table against generated RTL constants and MRA output, including all fill semantics.

Keep work RAM, tilemaps, palette, sprite RAM, and bitmap RAM in M10K where feasible.
Known game RAM is 104 KiB (64 bitmap + 16 tilemap + 16 main work + 4 sprite + 2 palette
+ 2 audio work). Raw bits alone suggest at least 84 M10Ks; actual width/depth packing,
ports, sprite snapshot, line buffers, caches, framework, and CPU/sound tables add overhead.
Measure each block and the framework baseline; do not treat this as a fit report.

Per-line ROM payload upper-bound sketch: at most 37 tile rows per layer for a scrolled
288-pixel window, 4 bytes each = 296 bytes; at most 63 active 16-pixel sprite rows,
8 bytes each = 504 bytes. That is 800 bytes before alignment, burst waste, map accesses,
CPU/sound demand, refresh, and turnaround. Bitmap reads come from BRAM. This is payload
arithmetic only: close the actual cycle budget once line period and controller cost are known.

## Implementation phases and exit criteria

1. **Bootstrap and reference tooling.** Create a separate local `Arcade-RabbitPunch_MiSTer`
   repository from Template, establish `develop`, pin framework and donors, and carry these
   docs across. Locate Quartus 17.0.2, mixed VHDL/Verilog simulator, matching MAME and ROMs.
   Record source hashes/version, validate ROM sets, build regions.json, and capture boot,
   video state, inputs, sound commands, and write sweeps in attract/play for both sets.
   Exit: reproducible reference artifacts and resolved clock/memory budget.
2. **CPU and bus.** Vendor CPUs with provenance and baseline tests; write VHDL decode,
   byte enables, ROM/RAM path, GGA register latch/IRQ model, sound latch, DIP/input ports,
   reset and pause. Use fx68k with a controlled VHDL bus adapter and phase enables.
   Exit: boot execution/state and peripheral accesses agree with MAME, with instruction
   and bus-cycle differences explained; standalone CPU synthesis closes timing.
3. **Video.** Build a software renderer checked against MAME snapshots, then VHDL tile
   adapters around reused JTFRAME tile/sprite primitives, a board sprite scheduler,
   bitmap reader and palette/priority mixer.
   Bitmap image RAM is part of this board; do not add a full-frame compositing buffer.
   Select sprite/register snapshots only from measured write timing. Provide accessible
   state ports and document STATE.md from the first RAM.
   Exit: decoded layouts and each layer/composite match reference scenes from both sets;
   measured worst-case line deadlines hold with CPU and sound clients active.
4. **MiSTer integration and silent hardware.** Integrate ROM loading, selected-set MRA
   generation, controls (Missile/Punch per driver and verified manual), DIP defaults,
   aspect 4:3, video output, debug identity/probes and pause. Create release and `_stp`
   revisions. Exit: simulation passes, staged Quartus build has nonnegative required
   slack, and both games boot/play on the user's board with recorded evidence.
5. **Sound.** Integrate Z80, YM2151, uPD7759, bank/reset/start and latch IRQ behavior.
   Exit: command/register traces and sample-bank tests pass, playback is verified on
   hardware and captured for comparison; no sample underruns or sound-induced video stalls.
6. **Features and release.** Add/test CRT Adjust, hiscore, fast load staging, HDMI scale/
   crop/rotation, common flip path, audio options, OSD visibility and both-player controls.
   Log inherited MAME assumptions in MAME_KLUDGES.md and own approximations in HACKS.md.
   Generate version-tagged MRAs, verify layouts against ROM_START, document provenance,
   contribution requirements, AI-code disclosure and floorplan. Release only after
   hardware verification; publishing and downstream database updates require user direction.

Full savestates and cheats are optional follow-up scope; debug state capture is designed early.
Each completed implementation phase is committed on develop; do not push develop.

## Verification rules

Follow MAME, including its acknowledged guesses, and log them. Preserve trusted chip RTL
when it disagrees until evidence identifies the correct behavior. Every subsystem gets
a meaningful testbench before hardware. Use mixed-language simulation for VHDL board
logic plus reused Verilog; Verilator alone cannot directly execute VHDL.
No module is considered proven here merely because a donor provenance file calls it proven.
No hardware result is reported without a capture/log/probe; staged builds gate on timing.

## Approval boundary

The user approved this roadmap and the mixed-language reuse approach. That approval
authorizes the local bootstrap and staged work above; it does not turn unresolved physical
timing guesses into measurements. Close those decisions with evidence before the dependent RTL.
