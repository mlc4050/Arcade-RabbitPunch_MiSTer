# Cheats

The main OSD has a **Cheats >** submenu, separated from DIP switches by a
blank line. Both Rabbit Punch and Rabio Lepus offer independently selectable
P1/P2 Infinite Missiles, Infinite Lives and Infinite Energy/Shield. Use the
matching development MRA: an older MRA does not contain these menu entries.

The standard MiSTer cheat menu sends enabled codes through download index 255.
The VHDL engine accepts up to eight 16-byte codes and overrides 68000 work-RAM
read responses. All six supplied codes are byte replacements. It also supports
compared replacements and byte/word/long OR/AND operations. Invalid, incomplete
or oversized lists fail closed. Two zero bytes clear the enabled list.

| Field | P1 address | P2 address | Returned byte |
|---|---|---|---|
| Missiles | FC269 | FC2A9 | 90 hex |
| Lives | FC3D9 | FC3F9 | 03 hex |
| Energy/shield damage counter | FC3D8 | FC3F8 | 00 hex |

Address comparison follows the board's 20-bit decode, including sign-extended
68000 work-RAM aliases. No additional CPU response cycle is inserted. Cheats
remain selected across warm resets; cold initialization/new ROM loading clears
the engine, after which Main must supply the selected list again.

The engine never writes RAM directly. The running game can write values derived
from overridden reads, so disabling a cheat does not undo its prior effects.
State/debug masters read and write raw RAM. Cheat selection is external policy,
outside the game savestate ABI: restored games use the currently selected codes.

## Verification

* Engine tests cover decoding, maximum capacity, overlap, comparisons, operations,
  mirrored addresses, malformed downloads, clearing and ordinary-read bypass.
* MAME 0.289 ran each original set for 6600 frames, including two-player combat,
  with cheats disabled, enabled and disabled again. Test-only RAM perturbations
  at frame 3000 exercise both players' lives and damage counters. All six fields
  have natural CPU reads whose consumed values change under the overrides.
* The native VHDL engine replays every captured complete read-response word from
  both MAME runs using the actual development MRA code bytes, with exact results.
* A native production-board simulation runs the state-capable 68000 against real
  board RAM/ownership logic. It checks both players, mirrored CPU reads, raw
  state-master reads/writes, warm reset retention and disabling the list.
* The existing state-board continuation test passes with cheats disabled.
* The actual state-enabled configuration retains the separated Cheats submenu;
  the production ROM frontend ignores cheat-index 255 downloads.

Receipts: reference/cheats_engine_mirrored_v2_checks.json,
reference/cheats_trace_rpunch_v1_checks.json,
reference/cheats_trace_rabiolep_v1_checks.json,
reference/cheats_board_v1_checks.json and
reference/state_board_cheats_disabled_v2_checks.json.
MAME capture metadata is retained in reference/cheat_game_*_checks.json;
ignored debug/cheats directories hold raw captures and earlier diagnostic runs.
These tests establish response behavior and integration, not whole-machine
cycle equivalence or MiSTer hardware qualification. Source 9747aee, release seed3 passes all144 fitted timing checks: minimum
setup +0.604ns, hold +0.074ns. Required hierarchy, fitted clocks and state
resources pass under the existing scoped framework timing policy.
reference/cheats_release_seed3_checks.json identifies the private RBF, matching
MRAs and verified ZIP. Physical cheat testing remains pending.

## Descriptors and provenance

Run scripts/build_cheat_mras.py once in a fresh feature checkout to create
releases/_dev/cheats, including the DDR alternatives. It adds only the cheat
block to published descriptors and checks the assembled ROM image hashes.
Published descriptors and the previously qualified RBF remain unchanged.
Use this generator for cheat candidates; the historical build_mras.py does not
add this development feature.

Address/value definitions derive from the historical Pugsy cheat collection
preserved in [libretro's MAME2003-Plus metadata](https://github.com/libretro/mame2003-plus-libretro/blob/master/metadata/cheat.dat),
then independently exercised against the current pinned MAME reference above.
Thanks to [Pugsy and contributors](https://www.mamecheat.co.uk/).
Source hash and the six extracted definitions are in
reference/cheat_code_provenance.json. No ROM data is included.

The private candidate is debug/bringup/RabbitPunch_Cheats_20261021.zip. Replace
both MRAs and the dated RBF together. The ZIP contains only those five files
inside _Arcade, including the two DDR alternatives; it contains no ROMs.
The original published assets remain unchanged.

The Cheats label explicitly includes MiSTer glyph 16 hex, matching the
right-aligned DIP submenu arrow. The standard C menu action is preserved.
The native state-enabled configuration assertion checks the glyph and spacing.
