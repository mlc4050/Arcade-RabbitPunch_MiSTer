# Savestate implementation plan

Requested controls: Savestate slot (1..4), Autoincrement slot, Save state and
Restore state on the main OSD. Full save/restore is not implemented yet; these
actions are withheld until they can complete and report errors correctly.
NVRAM is the separate persistent high-score block, not a running-game snapshot.

## Local references inspected

- NMK16 commit 4c9b923a87dcefee27574a8a06361e47e8e9b963:
  rtl/savestate/ss_m68k_park.sv and ss_z80_park.sv use instruction-boundary
  interrupt/monitor overlays for the same fx68k and T80 families. The M68K helper
  uses level 7 and a register-dump stub; Z80 uses NMI and tracks interrupt mode.
  Its savestate.sv streams a flat state bus to four DDR slots; savestate_ui.sv
  connects slot selection, actions and completion/error notifications.
- KonamiGX commit 89124d4f29e1d3f95557e5e5265efcbe9d0d7cb4:
  rtl/cpu/gx_ss_m68k.sv redirects a forced exception and capture bank through
  the bus. docs/SAVESTATES.md documents fx68k entry ordering, STOP handling,
  stack side effects and raster-phase alignment. Its state sequencer/DDR
  client are examples of a sectioned format and consistent simulation files.

These are design references, not a claim that either drop-in works on this
board. Imported RTL must retain provenance and unchanged upstream interfaces
behind descriptive VHDL wrappers; new control/transport/test logic is VHDL.

## Scope and implementation gates

1. Review STATE.md against current RTL. Writable board RAM totals 106496 bytes
   including sound RAM. Exclude read-only ROM; rebuild derived line/cache and
   optional HDMI framebuffer state. Include CPU architectural state, IRQ/GGA,
   sound command/pending, FM and ADPCM state or an explicitly documented audio
   restoration tier. No full composed-game framebuffer is required.
2. Prove both CPUs park/resume from normal execution, interrupt and stopped/halted
   paths. Account for exception/NMI stack writes and protect original stack RAM.
   No phase advance or accepted memory response may be discarded.
3. Generalize the acknowledged maintenance bus to all RAM banks and sound RAM
   restore, while draining shared SDRAM/renderer transactions. Snapshot latches
   and raster/clock-enable phase at a documented consistent boundary.
4. Define a versioned format with ROM/set identity, section sizes and integrity
   checks. Reject truncated, incompatible, empty or wrong-set states before
   mutating game RAM. Reserve four nonoverlapping DDR slots only after checking
   existing ROM-staging and rotation windows; add a real shared-DDR arbiter.
5. Add the OSD slot/actions and status feedback. Autoincrement advances only on
   successful save; failed saves and restores preserve the selected slot.
6. Test save/restore/save round trips, deterministic continuation, both ROM sets,
   partial/invalid files, timeout release, active audio and rotated/unrotated
   output. Full implementation and timing precede hardware mid-game testing.

Exact sound continuation remains an open design choice: the JT51 pipeline and
JT7759 state need examination before promising it. Register replay may audibly
reattack notes and must be identified as such if used.

## Initial CPU qualification

The isolated native fx68k/NMK16 helper test passes a register and 64 KiB RAM
round trip with 400 exact ordered continuation writes and separately checked
USP (m68k_state_checks.json). It uses an interrupt-enabled supervisor program.
The initial fully masked SR=2700 program did not enter the park monitor even
with the external level-7 request visible. That case is unresolved and prevents
claiming general CPU capture support. STOP/normal pending IRQ and original
stack preservation still require dedicated tests. The helpers/wrapper are
quarantined outside files.qip and do not change the timed game core.
