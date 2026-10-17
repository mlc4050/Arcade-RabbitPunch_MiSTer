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

`run_memory_powerup_tests.py` additionally reads all 52,224 words of the five
production banks through both CPU and inspection interfaces before the first
write (104,448 initial-content checks). Separate byte writes at the first,
middle and last word of every bank check both logical data and untouched nearby
words. The same component-based VHDL bench is available through
`run_netlist_tests.py memory` after the isolated memory fit, so synthesized
configuration contents can be checked independently of the RTL primitive model.

The combined logical-platform implementation at f6d5f7e passes every 48 MHz
timing and coverage gate with configuration initialization enabled: worst setup
+3.142 ns, hold +0.109 ns, and unchanged 929387 RAM bits. See
`reference/platform_synth.json`; private full reports are retained under
`debug/fit_archive/platform_f6d5f7e/`. This virtual-I/O fit does not establish
external SDRAM, PLL, pixel-clock or physical output timing.

The first isolated-memory rerun used its old raw virtual-I/O boundary and was
rejected for hold (worst -2.582 ns). A detailed slow-100C path report identifies
`iu24_request_address[4]` to the pending-address register: input data delay
2.203 ns versus destination clock arrival 4.499 ns, giving -2.296 ns at that
corner. This result is retained under
`debug/fit_archive/memory_c166ae1_rejected/`; it is not an accepted memory fit.

The isolated target now uses `memory_check.vhd`, with same-clock launch/capture
registers on every client port and an explicit falling-edge synthetic tester
contract in its SDC, matching the other evaluation blocks. Production
`rabbitpunch_memory` and RAM behavior are unchanged. The exhaustive bench checks
both direct and registered boundaries; netlist mode selects the registered
component and accounts for the two added test-only boundary stages. No timing
false paths or multicycle exceptions are used. Final board electrical timing
still requires the physical integration check.

The corrected isolated target at fa445a9 passes all timing and coverage checks:
835584 RAM bits, worst setup +6.462 ns and hold +0.186 ns. Reports are retained
under `debug/fit_archive/memory_fa445a9/` and summarized in
`reference/memory_synth.json`. The exhaustive synthesized-netlist simulation
is tracked separately from this implementation result.

An additional private negative control removes only the bitmap bank's FFFF
binding. The full mapped-memory bench fails at CPU bank 0, word 0, after
successful compilation/loading. This checks the production bank policy as well
as the primitive defaults; see reference/ram_bank_initialization_negative.json.

The initial synthesized-memory replay reached its 300-second real-time limit
without an assertion failure. ModelSim Starter reports exceeding its recommended
capacity; the partial log is retained under
`debug/baselines/gate_memory_timeout_300/`. The active replay uses an explicit
1200-second limit and progress markers. No netlist functional pass is claimed
until that replay completes.
