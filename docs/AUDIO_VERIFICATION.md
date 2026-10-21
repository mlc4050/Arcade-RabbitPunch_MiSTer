# October 20 release audio verification

The published savestate release passes four additional ordinary sound-playback
regressions. No production RTL changed during this audit, so the existing
Arcade-RabbitPunch_20261020.rbf remains the applicable build.

| Set | Passage | PCM samples | MAME non-timer register writes | Golden PCM/WAV/timed writes |
| --- | --- | ---: | ---: | --- |
| Rabio Lepus (Japan) | E4 effect, 3 seconds | 187,493 | 266/266 | Exact |
| Rabbit Punch (US) | E4 effect, 3 seconds | 187,493 | 266/266 | Exact |
| Rabio Lepus (Japan) | 99 music, 9 seconds | 562,493 | 1,293/1,293 | Exact |
| Rabbit Punch (US) | 99 music, 9 seconds | 562,493 | 1,545/1,545 | Exact |

The tested source is d269f2b; its tree is identical to published e20f02c.
All RTL also matches fitted source 6ac4a1b. The published RBF SHA-256 is
f7cc5bcd9f89ac3b9a4b976b7b7782bb6980dd88d7722e5df3b0b573f11f83e3.
The source audit checks 49 RTL snapshots, including the state-capable sound
adapters and generated chip models.

Each test uses the existing VHDL controlled-command fixture, original sound ROM,
production clock enables and mixer, with one-clock external ROM replies. State
capability is enabled and capture/restore controls are inactive. The comparison
includes every captured PCM sample, complete cycle-stamped register writes,
sample-marker timing and WAV padding. Output is byte-identical to the respective
qualified golden capture.

For the two music passages, exact WAV and timed-write equality links these runs
to the existing MAME music analyses. Both passages retain all 126 ordered note
events. Maximum note timing offsets are 0.156 ms for Japan and 0.218 ms for US;
the retained fitted drifts are -1.77 and -2.05 ppm across roughly 7.77 seconds.
The waveform analyses retain approximately -0.25/-0.28 dB RMS level differences
and the documented YM2151 timer-acknowledgement write differences. These are
bounded comparisons, not bit-exact MAME PCM, exhaustive music-track coverage or
an original-board analog measurement.

The corrected uPD7759 silence timing already included in this release remains
unchanged. Pause muting is also retained in rabbitpunch_system.vhd: its output
is zero while pause is asserted. This audit adds no new hardware pause test.
Active savestate continuation and complete-machine qualification remain covered
by their separate release evidence.

Evidence:

- [Release audio receipt](reference/release_audio_20261020_checks.json)
- [Release source audit](reference/release_audio_source_20261020_checks.json)
- [Japan MAME music metrics](reference/music_corpus_rabiolep_9s_cmd99_checks.json)
- [US MAME music metrics](reference/music_corpus_rpunch_9s_cmd99_checks.json)

With the retained local captures, recheck all receipt inputs without modifying
them:

~~~powershell
.\scripts\d_drive.ps1 scripts\check_release_audio_20261020.py --check-only
~~~

Raw captures, immutable manifests, source snapshots, export audits and driver
logs remain under debug/music_commands/ on D:. An early US reference-label
setup rejection and an unfinished retired build remain preserved separately;
neither is recorded as a passing simulation. The final US FM-only case explicitly
requires zero sample starts in both MAME and RTL before using its historical
music golden. The prior native CPU evidence anchors unchanged donor logic and
startup references; this report does not transfer native capture qualification
to the newer wrapper.
