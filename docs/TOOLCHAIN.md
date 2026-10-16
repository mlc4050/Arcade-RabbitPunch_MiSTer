# Verified local toolchain and reference baseline

## Installed tools

| Tool | Executable | Verified result |
|---|---|---|
| Quartus Prime Lite | D:/quartus/quartus/bin64/quartus_sh.exe | 17.0.2 Build 602 |
| Cyclone V device files | D:/quartus/quartus/common/devinfo/cyclonev | Present; device elaboration/fitting not yet run |
| ModelSim Altera Starter | D:/quartus/modelsim_ase/win32aloem/vsim.exe | 10.5b, 2016.10 |
| MAME | .local/tools/mame0289/mame.exe, relative to core root | 0.289 (mame0289) |

Paths are configured in the local gitignored mister.env. No machine-wide PATH changes
were made. The supplied self-extracting MAME package was extracted into the workspace,
not installed into the user's source checkout or Downloads directory.

Legacy ModelSim executables fail to launch inside the sandbox with Windows error 623
(illegal DLL relocation); the same tools launch and run successfully outside it. Use
the approved outside-sandbox invocation for simulation, with the existing JTAG guard.
No DLL replacement or Windows security/compatibility setting change was needed.

## Mixed-language check

`python scripts/check_simulator.py` passed after vcom compiled a VHDL register and
vlog compiled the SystemVerilog testbench; vsim elaborated both and simulated reset,
enabled writes and disabled hold. It reached TOOLCHAIN_SMOKE_PASS at 46 ns.
Evidence: debug/toolchain/result.log. This validates the tool installation and language
boundary only, not game hardware. No FPGA compilation, fitting or RBF generation occurred.

## Matching MAME reference

Executable: official Windows x64 0.289. Reference source snapshot: tag mame0289,
commit f34f02505e32c1993c6a782b6814232cbfc74e36 (annotated tag object
d0b7160e54874fa58f553614db373d73100d5ecb), exported from the user's local
MAME git objects to .local/reference/mame0289. Includes rpunch.cpp, vsystem_gga.cpp/.h,
ymopm.cpp/.h and upd7759.cpp/.h. The original MAME checkout remains unchanged.
The active driver/device hashes are in reference/rom_manifest.json.

The standalone core repository is D:/git/Arcade-RabbitPunch_MiSTer. The MAME executable
and pinned reference source moved with it into gitignored .local/; the original
D:/git/mame source checkout and downloaded installer remain in place.

MAME -verifyroms reports rabiolep and rpunch [rabiolep] good: 2 sets checked, 2 OK.
The DIP source parser now also recognizes the release driver's Continues and 4C_5C
shared labels; its self-check passes for both sets.

## First captures and timing sweeps

Both sets have an attract frame 1200 capture with 10 RAM/register dumps and a 288x216
reference PNG under debug/<set>-attract/. The Rabio Lepus capture shows the title screen.
These files are local reference fixtures, not committed ROM data or FPGA screenshots.

Initial coarse write sweeps cover 1800 counted frames per game in attract mode
(skip 600) and coin/start mode (coin 600, skip 1500). Results are preserved in
write_timing_mame.txt; raw histograms and end snapshots are under debug/wtiming/.
The coin/start snapshots were inspected: Rabio Lepus is in stage 1 play, Rabbit Punch
is at a stage 1 game-over/continue prompt. The Rabbit Punch run includes gameplay,
but is not evidence of 1800 continuously active-play frames.

Sprite and bitmap writes extend through active display in MAME's synthetic 224-line
frame; palette writes concentrate in its 8-line vblank. These are emulation timings,
not a measured PCB raster. Before any buffering decision, subdivide sprite writes by
descriptor field and register writes by function, and extend active-play coverage
using continuing/restarted input or scripted scenes. No snapshot/latch policy is chosen yet.
