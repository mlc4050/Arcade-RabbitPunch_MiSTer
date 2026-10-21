# US manual DIP audit

Source: [Rabbit Punch manual](https://www.crazykong.com/manuals/RabbitPunch.man.pdf), OPTION SWITCH SETTINGS banks 1 and 2, supplied by the user. The PDF and screenshot hashes are recorded in `reference/manual_dip_reference.json`. Physical ON is a set bit; switch 1 is bit 0.

## Coinage additions

MAME 0.289 omits two encodings documented for both coin slots. The US development MRAs now offer both. Coin A uses bits 0–3; Coin B uses bits 4–7. The core already passes these bits through without translation.

| Coin nibble | Physical switches 1/2/3/4 (or 5/6/7/8) | Menu label | Manual meaning |
|---|---|---|---|
| 1 | ON / OFF / OFF / OFF | 1C/1C+2C/3C | First coin gives one credit; two accumulated coins give three credits. |
| E | OFF / ON / ON / ON | 4C/1C | Four coins give one credit. |

Existing MAME labels 6C/4C, 5C/6C and 4C/5C describe the end of cumulative bonus schedules in the manual. They retain their established labels. Nibbles 7 and F are unspecified and remain unavailable. The US manual is not evidence for other Japanese settings. The same coinage additions are independently confirmed in the Japanese ROM, as described below.

## Bank 2 and defaults

All eight US bank 2 settings match the current MAME-derived menu: difficulty, lives, laser mode, extended play, demo sound, continue buy-in and flip screen. Difficulty bits are packed in switch order, so normal/easy/hard/hardest correspond to values 0/2/1/3. Physical continue switch OFF permits continuing; menu Continues On is correct for that position.

The supplied manual, printed page12 (PDF page17), specifies all Bank2 switches OFF **except Lives and Demo Sound**. Its factory setting is therefore `00,24`: three lives and demo sound On. MAME and the current MRAs default to `00,20`: two lives and demo sound On. Set Lives to3 and use Reset to apply to reproduce the manual factory settings. The previous audit incorrectly described both banks as all OFF; that reading missed the Bank2 exception. Switch options and bit encodings already match; defaults are retained rather than changed by this audit. See `reference/manual_dip_current_checks.json` for the current PDF and descriptor checks.

These are menu additions only. ROM assembly, button slots, DIP bit positions and production HDL are unchanged. Physical coin accounting remains unverified on MiSTer.

## Actual ROM accounting check

The pinned US ROM in MAME now confirms both added encodings on both coin slots.
Six physical input-port coin pulses produce these credit totals, observed at
work RAM byte 0x0FC19F and matching byte 0x0FD987:

| Nibble | Credits after coins 1 / 2 / 3 / 4 / 5 / 6 |
|---|---|
| 0, default 1C/1C | 1 / 2 / 3 / 4 / 5 / 6 |
| 1, cumulative bonus | 1 / 3 / 4 / 6 / 7 / 9 |
| C, known 2C/1C control | 0 / 1 / 1 / 2 / 2 / 3 |
| E, manual 4C/1C | 0 / 0 / 0 / 1 / 1 / 1 |

The test applies raw DIPs through the power-on CFG, verifies DSW reads every
frame and observes six six-frame pulses from the actual MAME SERVICE port.

In the pinned MAME/US ROM, the input named Coin 1 uses the high Coin B nibble,
and Coin 2 uses the low Coin A nibble. Testing same-named A/1 and B/2 initially
left the other slot at 1C/1C; the known C control exposed that association.
The crossed inputs reproduce all manual histories. Preserve MAME's field names
and active-high core input mapping; this is not physical-board wiring evidence.

Report: reference/manual_coinage_checks.json. The private archive preserves all
CFGs, actual input traces, six RAM snapshots per case, final screenshots, source
hashes and both the exploratory pairing and confirmed cross-slot controls.
The new settings are therefore supported by the actual ROM as well as the
manual. MiSTer hardware accounting remains unverified.

## Japanese ROM confirmation

Rabio Lepus independently produces the same four credit histories above on both
slots, including the known C control, with raw DIPs applied at power-on and
actual input-port coin pulses checked. Its observed credit byte is also
0x0FC19F; matching display state uses 0x0FD973. See
reference/rabiolep_manual_coinage_checks.json and its exact private archive.

Both Japanese development MRAs now offer the two verified omitted encodings.
Japanese lives, laser, extended-play/demo-sound definitions and default 00,00
remain its own MAME settings. This extension follows actual Japanese ROM
behavior and does not infer other Japanese board settings from the US manual.
ROM images, DIP positions, controls and production RTL remain unchanged.
