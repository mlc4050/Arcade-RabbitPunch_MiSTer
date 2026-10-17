# Configuration-time RAM contents

The active reference is MAME 0.289 at tag mame0289. Ordinary shared/main/sound
RAM starts at zero. In `rpunch_state::machine_start`, rpunch.cpp allocates a
512x256 pixmap and fills every pixel with colour 15. Its byte handlers pack two
pixels per byte; the core's packed 16-bit bitmap word therefore starts at FFFF.
This follows the emulator reference, not a claim that original SRAM powered up
with defined contents.

Both unsigned native-RAM wrappers now set altsyncram's
`power_up_uninitialized` to FALSE, specifying zero configuration contents.
`rabbitpunch_ram16` has a constant `POWER_UP_WORD` generic. Writes XOR the CPU word
with that value before storage, and both read ports XOR it back. Bitmap selects
FFFF; other production banks select 0000. Byte masks act on the encoded data,
so a byte write preserves the other logical byte. This adds no RAM bank, clock
domain, clocked read stage or runtime clear sweep. The zero constant optimizes
away for ordinary RAM.

Initialization happens when the FPGA configuration is loaded. CPU/game reset
and a logical ROM reload do not clear existing game RAM. That preserves the
existing warm-reset behavior. The game program remains responsible for any
software reinitialization after reset; high-score profile/image generation
tracking is separate.

Inspection through CPU/video/state ports returns logical CPU-format words.
A direct vendor-memory dump of the bitmap contains encoded bits and must XOR
FFFF to recover those words. State restore through the acknowledged CPU/byte
interface already performs the correct encoding; it needs no format change.

`run_ram_powerup_tests.py` checks every address of 256-word native instances on
both read ports, logical patterns 0000/FFFF/A55A, zeroed byte RAM, separate upper
and lower writes and clock-enable retention. No simulator memory deposits are
used. Private negative controls turn configuration initialization back off and
fail the expected startup-content assertions for both RAM widths.

`run_board_memory_video_tests.py` reads the first 64 words of each actual mapped
bank before any CPU write, then checks its existing parallel video/CPU traffic,
byte-mask collisions and inspection behavior. Bitmap reads FFFF; other banks
read zero. Real-ROM `check_system_boot.py` no longer deposits values into main,
bitmap or sound RAM. Its short two-game startup check passes with production
configuration initialization. Sound-CPU register normalization and direct SDRAM
ROM-model preload remain explicit and separate test setup.

The complete long startup comparison, six captured scenes, native score tests
and new implementation evidence are recorded as they finish. A physical FPGA
power-up measurement remains part of hardware bring-up.
