# Board controls and pause

Pinned MAME rpunch.cpp uses ACTIVE HIGH P1, P2 and SERVICE fields. Both games
share that layout. rabbitpunch_inputs ORs pad and keyboard actions and reorders
UP/DOWN/LEFT/RIGHT without inversion. Player unused bits 6/7 and SERVICE unused
bits 2/7 stay zero. In particular the original unused freeze input is not Pause.

| MiSTer pad bit | Board meaning |
|---|---|
| 0 / 1 / 2 / 3 | right / left / down / up -> player bits 3 / 2 / 1 / 0 |
| 4 / 5 | Fire/Punch / Missile -> player bits 4 / 5 |
| 6:9 | padded action slots, ignored |
| 10 | controller 1/2 Start -> SERVICE bits 5/6 |
| 11 | controller 1/2 Coin -> SERVICE bits 4/3 |
| 12 | common pause button, outside original SERVICE ports |
| 13 / 14 | Service coin / Test switch -> SERVICE bits 0/1 |

The inherited mame_keys.sv remains unchanged behind rabbitpunch_keys. Its two
button slots and Start/Coin/Pause positions match the development MRAs. Its F2
SERVICE parameter maps to Test slot 14, distinct from keyboard 9's service-coin
input. The board has no service-coin 2 input, so keyboard 0 is ignored.

| Keyboard | Action |
|---|---|
| arrows / R F D G | player 1 / player 2 movement |
| left Ctrl, left Alt / A, S | Fire/Punch, Missile for player 1 / player 2 |
| 1 / 2 | Start 1 / Start 2 |
| 5 / 6 | Coin 1 / Coin 2 |
| 9 / F2 | Service coin / Test switch; F2 can be held at boot |
| P | pause toggle |

Live MAME 0.289 captures provide 35 independent port vectors per set: individual
controls, legal combinations, padding/service exclusions and pause not affecting
original ports. Both sets' port vectors agree. The FPGA mapper passes all 35
pad vectors and 30 equivalent keyboard vectors, plus per-key state/event-toggle
and simultaneous pad/key checks (reference/input_vectors.json and
reference/inputs_checks.json). No physical controller or game-play test is claimed.

Index 254 bytes 0/1 latch the DIP low/high byte. Japan defaults are 0000; US
2000 enables demo sounds. The MRA supplies the per-set defaults before framework
reset release. The standalone cold fallback defaults to Japan and can be
parameterized. Every value of both byte lanes, full metadata address/index
filtering and no-strobe holding pass. Game reset does not clear downloaded DIPs.

rabbitpunch_pause toggles once per rising button/key level. OSD pause is optional;
debug/state inspection can independently retain pause. Reset clears manual pause
without treating an already-held key as a new press. It requests CPU clock-enable
pause through the existing board adapters; it adds no clock gate, video buffer
or chip-enable gating. The connected controls test checks pad/keyboard pause,
OSD/state ownership and DIP preservation across game reset
(reference/pause_checks.json and reference/controls_checks.json). Controls pass a full Quartus fit at 48 MHz with zero block RAM and all
reported timing/coverage checks passing (reference/controls_synth.json). The
separate system CPU-drain/pause tests retain their own scope.


The first hardware user reports that the action labelled Shoot launches
missiles. The corrected displayed order is **Fire/Punch, Missile**, mapping
unchanged pad slots/player bits 4 and 5 respectively. The generic MAME input
field numbers are unchanged. This supersedes the old labels inferred from the
driver memory-map comment, which assigns those roles the other way around.
Re-define controller buttons after replacing the MRA if a saved assignment
reflects the earlier labels. Confirmation of the corrected physical labels
remains a hardware follow-up. Both players use the same board wiring.

The completed 1800-frame runs used the old semantic names (held slot 5 and
pulsed slot 4). Their archived exact stimulus remains unchanged and their
CPU/render/audio results stand, but the held action must be interpreted as
Missile and the pulse as Fire/Punch under the hardware-reported roles. Future
fixtures/reference captures use the corrected semantic constants/fields.
