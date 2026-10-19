# Executing game boot with continuous video

The qualified fast backend has run both original game images through 120 frames with the actual 68000, T80, shared external SDRAM arbitration and continuous native raster rendering. No CPU or on-chip RAM state was deposited. External ROM storage was preloaded and the real 32-byte loader header was sent; full-image loading is separately qualified.

| Set | Simulated system clocks | Main writes | Sound writes | Visible nonblack pixels | Direct MAME frame 120 differences | Independent renderer differences |
|---|---:|---:|---:|---:|---:|---:|
| Rabio Lepus | 93,549,462 | 93,386 | 336,258 | 5,106 | 0 / 62,208 | 0 / 62,208 |
| Rabbit Punch | 93,549,462 | 131,850 | 334,288 | 17 | 34 / 62,208 | 0 / 62,208 |

Both main CPU startup sequences match the first 10,000 MAME writes; sound startup uses the separately audited 4,096-write comparison. No row deadline, coordinate or underflow assertion failed. Japan reaches its visible notice screen. The US image contains early stars; MAME has the same nonblack pixel count but different positions/colors. The cause of that temporal state difference is unresolved. Equal frame numbers do not establish matching instruction, interrupt or raster phase.

`compare_live_boot_frames.py` replays each complete requested-write trace into the documented RAM startup contents and feeds the resulting state to the independently MAME-validated software renderer. Both images match that reconstructed state exactly. This is separate evidence from direct MAME equality, not a replacement for the US discrepancy. Requested-write replay is not a direct RAM dump and may include a final undrained request or writes after earlier captured rows.

## Scope and next gates

Logical on-chip RAM models are qualified separately against native Intel wrappers. The system clock in this fast model is synthetic, with the retained 5,357 ps SDRAM clock phase. Native PLL/Intel simulations remain a separate gate. The T80 block-I/O export guard remains enabled; unsupported affected instructions fail explicitly.

Sound writes are observed, but PCM outputs are unobserved and may be optimized away. These runs do not prove audible playback, FM/ADPCM output or complete live audio integration. Coin/start gameplay, longer attract/play captures, actual PCM sampling and physical hardware remain open. No production RTL changed for this test.

The exact tested prototype runner retains inherited diagnostic naming and supports only the asserted default load mode. A cleaner versioned VHDL fixture is a private unqualified draft, not part of these results. Future runs should extend stimulus and PCM coverage rather than repeat startup solely for cosmetic cleanup.

## Evidence

Reports are `reference/fast_game_{rabiolep,rpunch}_120_checks.json`, `reference/live_boot_{rabiolep,rpunch}_120_image_checks.json` and `reference/live_boot_120_archive.json`. The latter records immutable private archive `debug/fit_archive/live_boot_120_19a6d19dd5/` in the video-options worktree, with exact tested sources, generated models, binaries, ROM-derived inputs, CPU traces, raw images and MAME captures. ROM-derived files stay private and ignored.

## Pending extended pad/PCM run

The versioned VHDL fixture sim/fast/gameplay_fast_fixture.vhd drives the same
production pad adapter as the complete MiSTer shell. It uses named layout slots
for Coin, Start, Shoot and Missile, with alternating vertical movement. Current
cases are rabiolep_1800_pad and rpunch_1800_pad: Coin at frame 900, Start at 990,
six-frame pulses, neutral controls until frame 1290, then Shoot/motion and a
Missile pulse at 1320. Both long runs remain pending. Applied stimulus alone
does not prove that a game has entered playable action.

Actual raw FM stereo, ADPCM and mixed mono PCM are observed, preventing unused
sound-output pruning. VHDL delays its capture strobe four clocks after the YM
sample-marker edge for mixer settling. The runner checks the 746/747 system-
clock sample cadence, rejects a completed all-zero mono capture and produces
a private 62500 Hz WAV. There is no independent game-waveform or physical
audible comparison yet. The separate keyed-FM cross-tool proof is recorded
in SOUND_BRINGUP.md.

## Reference controls and rejected fixtures

The final MAME reference runner uses versioned gameplay_capture.lua. It checks
actual SERVICE Coin 1/Start 1 and player Missile/Shoot port values, rejects both
Lua error files and callback error markers, and passes an actual injected-error
negative control even when capture completion was also printed. Both final
1800-frame images match independent rendering of their MAME state. This proves
the reference inputs and renderer comparison; it does not prove live RTL
gameplay or instruction/raster alignment.

Reports are reference/gameplay_mame_schedule_verified_checks.json and
reference/gameplay_reference_error_guard_checks.json. Earlier reports remain
explicitly rejected for their input-schedule claims:

- The first two-frame/immediate-held-Shoot schedule did not reach play. The
  effect of pulse duration was not isolated; a neutral interval after Start
  also matters. Own incomplete runs were preserved and stopped.
- A raw-board fixture initially selected Service Credit instead of Coin 1.
  Production controls were already correct. Both incomplete runs stopped before
  injection; the current fixture uses the real pad adapter.
- The first MAME pulse-length generator omitted a Lua variable and failed to
  check ERROR.txt. Its stage-1 images were attract mode. Their static rendering
  comparisons remain valid; their controlled-gameplay claims were withdrawn.

No rejected or incomplete run is included in an accepted live gameplay result.
