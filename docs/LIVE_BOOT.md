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

## Extended gameplay/PCM test prepared

The versioned VHDL fixture in sim/fast/gameplay_fast_fixture.vhd and runner
scripts/run_gameplay_tests.py extend the test to 1800 frames. Coin is asserted
at frame 900 and Start at 990, each for six frames. Shoot is held after Start,
Missile pulses once and vertical movement alternates. PCM is observed from raw
FM left/right, ADPCM and the actual mixed mono output; the VHDL sample strobe is
delayed four clocks after a rising YM sample marker to allow mixer settling.
The runner checks the 746/747 system-clock sample cadence and rejects a
completed all-zero mono capture. No independent waveform equality is claimed.

This test is prepared and running, not qualified by the 120-frame results.
The independent MAME 1800-frame references visibly reach stage 1 for both sets,
and their complete 62208-pixel images match independent rendering of the
captured MAME state. See reference/gameplay_mame_schedule_checks.json.

An initial two-frame Start pulse failed to start either game in MAME; the own
incomplete RTL experiments were stopped and privately archived. This is a
rejected stimulus schedule, not a production RTL failure. The short 1200-frame
Japanese capture also remains in a title transition; the final endpoint is
1800 as verified in MAME. Neither stopped run is counted as an accepted test.

A subsequent fixture audit caught Service Credit (SERVICE bit 0) being pulsed
instead of Coin 1 (bit 4). The production input adapter already uses bit 4.
Both incomplete long runs were stopped before their frame-900 injection and
privately archived; neither is accepted. The corrected case suffix is
_coin1, explicitly driving bit 4 and Start 1 bit 5. See
reference/gameplay_service_credit_stimulus_rejected.json.

Correction to the initial extended reference claim: the first pulse-length
generator omitted a Lua pulse_frames declaration and checked lua_error.txt but
missed ERROR.txt from capture callbacks. Those stage-1 images were attract mode,
not validated controlled gameplay. Their static software-renderer equality
still holds. The initial schedule report is explicitly rejected for input
validation. The corrected runner uses versioned gameplay_capture.lua, rejects
both error files and callback error markers, and verifies recorded Coin/Start/
Missile pulse counts from inputs.txt. Corrected output names end in _checked.

The final corrected schedule uses Coin at 900, Start at 990, and neutral
controls until frame 1290 before Shoot/motion and a Missile pulse at 1320.
With immediate held Shoot the games stayed in title/start-release handling;
the neutral interval permits progress. The earlier effect of pulse duration
was not isolated and is not claimed as a game requirement. The final MAME
runner checks actual SERVICE Coin 1/Start 1 and player Missile/Shoot bits,
rejects callback errors even when CORE_CAPTURE_OK was also printed, and passes
an actual injected-callback-error negative control. Both final 1800-frame
reference images match independent rendering of their MAME state. Reports:
reference/gameplay_mame_schedule_verified_checks.json and
reference/gameplay_reference_error_guard_checks.json. Earlier schedule reports
remain explicitly rejected.

The final live VHDL fixture drives the unchanged production pad adapter using
the layout's named button slots, rather than duplicating its board-bit map.
Current live output cases end in _pad. No long-run result is accepted yet.
