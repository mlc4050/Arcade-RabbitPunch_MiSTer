# US manual DIP audit

Source: [Rabbit Punch manual](https://www.crazykong.com/manuals/RabbitPunch.man.pdf), OPTION SWITCH SETTINGS banks 1 and 2, supplied by the user. The PDF and screenshot hashes are recorded in `reference/manual_dip_reference.json`. Physical ON is a set bit; switch 1 is bit 0.

## Coinage additions

MAME 0.289 omits two encodings documented for both coin slots. The US development MRAs now offer both. Coin A uses bits 0–3; Coin B uses bits 4–7. The core already passes these bits through without translation.

| Coin nibble | Physical switches 1/2/3/4 (or 5/6/7/8) | Menu label | Manual meaning |
|---|---|---|---|
| 1 | ON / OFF / OFF / OFF | 1C/1C+2C/3C | First coin gives one credit; two accumulated coins give three credits. |
| E | OFF / ON / ON / ON | 4C/1C | Four coins give one credit. |

Existing MAME labels 6C/4C, 5C/6C and 4C/5C describe the end of cumulative bonus schedules in the manual. They retain their established labels. Nibbles 7 and F are unspecified and remain unavailable. No manual overrides are applied to Rabio Lepus: this is the US manual.

## Bank 2 and defaults

All eight US bank 2 settings match the current MAME-derived menu: difficulty, lives, laser mode, extended play, demo sound, continue buy-in and flip screen. Difficulty bits are packed in switch order, so normal/easy/hard/hardest correspond to values 0/2/1/3. Physical continue switch OFF permits continuing; menu Continues On is correct for that position.

The manual specifies factory switches all OFF (`00,00`). MAME defaults are `00,20`, which enables demo sound. We retain the MAME default; Demo Sounds Off already selects the manual factory state. This difference is explicit rather than silently changing the existing default.

These are menu additions only. ROM assembly, button slots, DIP bit positions and production HDL are unchanged. Physical coin accounting remains unverified on MiSTer.
