# Hacks, approximations and workarounds in this core

Everything in this core's own RTL, scripts or `.mra` layout that is known not to be what the
hardware does: a stand-in, a shortcut, a value chosen to make something work, a workaround for a
tool. Each entry is added in the commit that introduces the hack and removed in the commit that
removes it.

This is not `MAME_KLUDGES.md`. That file lists MAME's own guesses that the core reproduces on
purpose because MAME is the reference. This file lists what is ours.

Rules:

- An entry cites `file:line` (or a module and signal name if the line moves often), and the
  evidence column says what was measured, or "unverified".
- "What would make it correct" names the work, not "fix later".
- A hack whose entry is missing is a bug. A hack whose entry is stale is worse: update it in the
  same commit as the code.
- Severity is what a player or a verifier would see: **visible** (wrong pixels, wrong sound, wrong
  timing a game can hit), **latent** (wrong only for input no in-scope set produces), **tooling**
  (affects the build or the bench, not the bitstream).

| What | Where | Why it is a hack | What would make it correct | Evidence | Severity |
|---|---|---|---|---|---|
| Provisional SDRAM clock phase | `rabbitpunch_clocked_machine.vhd`, GSTR_SDRAM_PHASE_SHIFT | Production quarter-period shifted output passes prototype constraints; actual module/PCB sampling margin is not measured | Check fitted PLL parameters, pin constraints and physical SDRAM transactions; tune phase/read capture if evidence requires | Production-phase command-model/frame tests and instrumented full fit pass; physical margin pending | visible |
| Provisional output timing and fixed sync polarity | `rabbitpunch_raster.vhd`, `rabbitpunch_clock_enables.vhd` | User-authorized 432x256/60.2816 Hz candidate from schematic crystal and inferred GGA fields; MAME declares 60 Hz without raw timing | Compare MAME-visible behavior and validate output during MiSTer bring-up; replace constants if better evidence appears | Ratio/raster and production-PLL continuous MAME-image checks pass; physical output pending; PROVISIONAL_RASTER.md | visible |
| Raster events not generated in real-ROM boot bench | `boot_writes_tb.sv`, interrupts instance | GGA IRQ state and CPU acknowledge work, but vblank/half-frame events are tied low | Supply verified raster events and compare IRQ execution against MAME | Directed scheduler and CPU STOP/handler/RTE tests pass; early boot is not a full timing comparison | tooling |
| System reset also drives CPU power-up reset | `rabbitpunch_maincpu.vhd`, i_powerup_reset | No separate cold/warm reset policy yet | Wire and verify distinct reset behavior during board integration | Diagnostic reset replay passes; game warm reset unverified | latent |
| Boot ROM transport and external inputs remain behavioral | `sim/board/boot_writes_tb.sv` | ROM array supplies the external handshake; DIP defaults come from MRA, controls are inactive | Integrate SDRAM transport, input mapper and sound CPU | VHDL RAM, board I/O and mailbox now used; a poll of a pending command stops for the missing sound CPU | tooling |

| Same-word video/inspection reads take priority over a CPU write | `rabbitpunch_board_memory.vhd`, STATE_WAIT_WRITE_SLOT | Deterministic FPGA policy avoids undefined native mixed-port collisions; original PCB bus ownership timing is not yet established | Verify against schematics/measurements and prove CPU wait bounds with the physical raster | Directed collision tests pass; original arbitration unverified | visible |

<!-- Examples of the shape, from sibling cores:
| Sound mailbox is a stub that answers the power-on test | `rtl/gx_snd_stub.sv` | No sound CPU yet; the stub returns the reply the test expects and a heartbeat | Phase 3: the real sound board | The game's RAM check passes with it; nothing else is exercised | visible |
| Sound-command spin of 800 CPU clocks after a latch write | `rtl/cpu/…_bus.sv:NNN` | Copies MAME's 40 us wait; the real board's mechanism is unknown | A measurement of the latch on hardware | Without it the second byte overwrote the first (commit) | latent |
| Sound CPU reset held 1,024 clocks | `rtl/….sv:NNN` | MAME's pulse is zero-length; the T80 needs to see it | The measured reset length | A PCB measurement says about one second | latent |
| Screen timing from one game used for every game | `rtl/video/…crtc.sv` | MAME declares 60 Hz with no comment; the one PCB-verified rate is used for all | Per-game timing from PCB measurement | 0.043% from the verified rate | visible |
-->

## Removed

Entries move here when the hack is gone, with the commit that removed it, so a later reader can
tell "never had it" from "had it and fixed it". Delete a row once nothing else refers to it.

| What | Removed by | Replaced with |
|---|---|---|


## Sound startup comparison initial state

MAME's defined Z80 reset registers differ from the unchanged T80 reset state.
The strict 4096-write sound startup comparison explicitly seeds T80 through its
existing simulation state-load input from captured MAME reset registers. This
normalizes the test starting condition only. No production reset circuitry is
changed; the separate native-reset comparison now passes both games with all 4096
write addresses/masks and 215 peripheral writes exact, while explicitly
reporting four audited bootstrap stack-save bytes. Sound memory replies in that test
are behavioral, periodically delayed by 53 clocks; this is not original-board
cycle timing or shared SDRAM bandwidth proof. See SOUND_BRINGUP.md.


Resolved RAM startup policy: native word/byte RAM now has explicit
configuration-time contents, with transparent-15 packed bitmap words and zero
ordinary RAM matching MAME. No game-reset clear sweep is introduced.
RAM_POWERUP.md and reference/ram_powerup_checks.json record the contract;
physical board startup verification remains open.

## First physical-shell prototype

The framework boundary is being connected for first hardware bring-up. It exposes
the native 288x216 raster and signed mono audio. Forced scandoubling, HQ2x and
CRT scanline levels are connected through a tested VHDL wrapper; the new shell
fits pass, while physical output remains pending. Corrected HDMI rotation passes
release/debug full-shell timing and its documented functional comparisons. Audio
mix is connected and passes synthesized-host/connected protocol regressions; its
release/debug full-shell implementations now pass all timing and coverage gates. Crop remains unconnected. HDMI aspect/integer
metadata and common screen flip pass their full-shell gates;
this is not the final standard-feature set. The framework HDMI scaler remains
available. The optional rotator now shares DDR through a loader-priority queue/publication
boundary verified with the real frontend and fitted complete-controller
comparisons; physical contention checks remain pending. No game
ROM fetch uses DDR during play. Physical output and audible game audio are untested.


Common screen flip uses a visible-viewport coordinate mirror at the existing
random-access line-buffer boundary, including bitmap requests and inverse RGB
tags. It adds no composite framebuffer. This is a presentation implementation,
not recovered C7-01 GGA circuitry; MAME's ignored global-flip bit is documented
in MAME_KLUDGES.md. The coordinate/transaction unit test and both complete 62208-pixel rotated
MAME comparisons pass, along with a clocked-machine fit requiring unchanged
RAM usage. Full-shell flip timing and coverage also pass; physical CRT/HDMI operation remains open;
see VIDEO_FLIP.md for the exact scope.


The connected optional CRT Adjust wrapper corrects the donor's vertical-blank
alignment at its wrapper for our HSync-after-visible raster. It carries the
completed bank's VBlank tag through the two read-enable stages, disables the
donor's extra vertical RGB gate and leaves the imported file unchanged.
The first-row correction passes full-height RTL and synthesized-netlist checks,
exact native sync geometry and all 62208 pixels of a real renderer/MAME scene.
Standalone and both full-shell revisions pass routed timing. The combined
CRT/HQ2x one-row colour assertion was an invalid flat-field expectation at the
black blanking border. Compact and production-width captures now match every
pixel of an independent native framework reference; no production HDL changed.
Native, forced-doubled and direct combined cases also pass. Patterned combined
HQ2x now matches all 1024 pixels against an independent native-framework fixture.
Live vertical-shift changes, extreme clipping and physical monitor
checks remain open; see CRT_ADJUST.md. Native Off bypass is direct.


## Supplemental fast T80 model

Production T80 sources remain unchanged. The GHDL-only exported copy replaces an
unequal-width legacy block-I/O mask to permit compilation, and explicitly traps
the entire affected flag path; it provides no silent replacement behavior for
those instructions. Native ModelSim/MAME startup comparisons and an executing
INI rejection qualify only the documented workload. Logical RAM and two-state
initialization retain their separately documented limits. See TOOLCHAIN.md and
reference/fast_sound_boot_archive.json. General instruction equivalence would
require independent opcode qualification or a faithfully supported toolchain;
these startup tests do not supply it.

## Savestate evaluation limits

The isolated GX 68000 capture donor keeps register stores and most exception
frame writes off game RAM, but its first PC-low word reaches SSP-2 before the
interrupt acknowledge identifies the capture. Repeated deterministic CPU tests
and STOP/IRQ wake pass; original stack transparency does not. The earlier NMK16
CPU monitors use more of the game's stack. Neither is a complete production
savestate implementation. The tested RAM and board/timing state ports remain
separate integration surfaces; exact hidden sound-chip state and full-machine
restore are unavailable. OSD actions are withheld. See SAVESTATES.md.

The isolated BoogieWings JT51 state donor is rejected for exact restoration:
its 2820-bit vector round-trips, while all 32768 checked observable trace clocks
differ after restore. Missing operator/feedback/accumulator state ports remain
unpatched. The first fixture's uninitialized stopped timer counters are archived
separately; the final negative result explicitly initializes both timers through
normal writes. Production sound is unchanged. See
`reference/fm_state_audit_checks.json` for source/log hashes and test scope.
