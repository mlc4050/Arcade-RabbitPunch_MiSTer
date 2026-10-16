# First board interfaces and development MRAs

## Shared download contract

rtl/rabbitpunch_layout.vhd is the source for the six region offsets/sizes and joystick
slot numbers. scripts/build_mras.py reads these definitions rather than maintaining a
second copy. One selected set occupies index-0 download bytes 0..0x20ffff, total 0x210000.
Regions remain maincpu, audiocpu, tiles1, tiles2, sprites, upd, in that order.

The byte stream matches MAME region memory order, including ROM_LOAD16_BYTE interleave,
ROMREGION_ERASEFF, explicit fills and zero-filled tails. CPU and graphics consumers
must implement the appropriate word/pixel interpretation; do not swap the complete stream.

Generated files:

- releases/_dev/Rabio Lepus (Japan).mra
- releases/_dev/Rabbit Punch (US).mra

Both select RBF identity RabbitPunch. The US MRA accepts rpunch.zip with rabiolep.zip
as parent fallback; the Japanese MRA accepts rabiolep.zip. The generator currently
verifies using the user's merged parent archive. No mod byte is needed to select a
different board: these games share this hardware map and load different ROM content.

DIP defaults come from each game's input definitions, not from a common default:
Rabio Lepus is 00,00 and Rabbit Punch is 00,20. DIP bytes map low then high into the
board's 16-bit DSW value via the future index-254 loader. A multi-bit DIP uses a bit
range, not a comma-separated enumeration. Unspecified hardware encodings use '-'
entries as in the inspected Seta MRA generator. All labels fit the 28-column OSD.

Joystick slots are positional: Missile 4, Punch 5, Start 10, Coin 11, Pause 12,
Service 13, Test 14. MRA names are generated from the VHDL slot definitions. Physical
gamepad defaults/keyboard routing and the eventual input mapper are not implemented.

## Checks performed

For each game, the generator checks source CRCs/sizes against the installed executable's
-listxml output, then compares the assembled MRA stream with both address-based source
assembly and MAME's actual loaded memory regions, byte for byte. The MAME-loaded check
uses a Lua dump of all six regions, including unpopulated/fill bytes. Both complete
2162688-byte images match. Per-set hashes/results: reference/mra_checks.json.

validate_mra.py accepts both generated files (XML, rotation, DIP range/default/width,
version and control-name checks). mameversion is read from the executable and is 0289.
The mra.py interleave/slice self-test also passes.

## VHDL address decoder

rabbitpunch_decode.vhd decodes the low 20 CPU address bits, with upper-address mirrors,
read/write restrictions, active-low byte strobes, full-word-only scroll writes and
low-byte GGA/sound/sprite-control ports. Target codes are declared in the shared package.
Unmapped, inactive, no-strobe and unknown-address accesses select TARGET_NONE.

The independent test table checks 67 boundary, lane, access-direction and mirror cases.
This is selection logic only; it does not supply RAM, register contents, interrupt
behavior or default read data for unmapped accesses.

## VHDL bus request adapter

rabbitpunch_bus.vhd captures fx68k address/data/strobes into a single request pulse.
Request byte bit 1 is the upper byte and bit 0 the lower byte; request_write is active
high. Backend request fields are held until the next transaction. The backend returns
one response_valid pulse with response_data for each accepted request, including writes.
DTACK goes low only after the response and stays low until AS is released.

The backend must finish accepted requests across CPU reset. The adapter drains an old
reply before accepting a post-reset request, preventing a stale reply from completing
the new cycle. AS before its byte strobes does not create a request. Bus-error/timeout
policy, CPU phase generation and a complete memory backend remain to be integrated.

The test covers seven completed reads/writes with upper/lower/full-word lanes and
0/3/11-cycle backend delays, holding AS after acknowledgement, delayed byte strobes,
and a new request immediately after resetting a CPU with an outstanding transaction.

```
python scripts/run_board_tests.py
python scripts/build_mras.py
python scripts/validate_mra.py "releases/_dev/*.mra"
```

ModelSim logs are debug/baselines/board_decode/result.log and board_bus/result.log.
The interfaces have not been added to files.qip; the inherited demo remains connected.
These MRAs are development definitions, not a playable release. No RBF has been built.
