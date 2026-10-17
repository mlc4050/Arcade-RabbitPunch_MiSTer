# JT7759 evaluation copy

Copied unchanged from SNK68 at 566133699ecd2ec2aa6897de6f0995ebefb60624; selected rtl/jt7759 files are clean.
Upstream: https://github.com/jotego/jt7759, Jose Tejada Gomez, GPL-3.0-or-later.
The donor does not record its exact upstream revision. LICENSE/README/QIP are
preserved, as are the original top-level test.v/go.sh under sim/vendor/jt7759.
File hashes are in docs/reference/vendor_manifest.json. No chip edits are made.

The README table is not an interface declaration: the native ROM address is
17 bits and PCM is signed 9 bits. Existing vendor header spelling is preserved.
This is an evaluation candidate, not integrated sample audio. Original test.v
launches four sample commands and exits at the fourth launch; it has no waveform
scoreboard and its clock comments do not establish 640 kHz operation. A VHDL
baseline must verify the selected clock-enable and interface contracts separately.

The SystemC2 candidate was not selected: its controller's DONE state holds
forever until reset. This SNK68 version returns to IDLE at sample end; that
static distinction motivated selection; the independent VHDL two-command
retrigger baseline passes.


The original test's automatic start sees busyn high during chip reset, drives
start low before IDLE, and loses the trigger edge. Its first unassisted ModelSim
run launches no samples. An initial 50 us inactive-start guard lets the first
sample complete, but its automatic multi-sample fixture then stalls in READADR
at the second table address. That is a failed fixture result, not a passing
multi-sample baseline. Its transcript is preserved under debug/.

The retained original chip/test/ROM model is checked only for first-sample
completion using simulator-controlled start and an explicit idle assertion.
It does not claim the original automatic sequence works. The separate VHDL
baseline uses ROM-valid responses qualified by ROM request and independently
checks two different complete commands, 13-clock delayed ROM responses, 640 kHz
enables, nonzero PCM presence and reset mute. No decoded-value or game-audio
comparison is claimed. No vendor source is changed to make a test pass.
