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


## Optional fast VHDL simulation backend

Portable GHDL 6.0.0 (mcode), Verilator 5.053 devel from OSS CAD Suite 20261018,
and w64devkit 2.10.1 / GCC 16.2.0 are extracted under this core's
.local/tools/ on D:. All three archive bytes match their official release
asset SHA256 digests; see reference/portable_tool_archive_checks.json.
No machine-wide PATH or registry setting was changed. The recorded tool version
strings include the official binaries' `dirty`/`mod` build labels rather than
silently relabeling them as clean builds.

Sources: [GHDL 6.0.0](https://github.com/ghdl/ghdl/releases/tag/v6.0.0),
[OSS CAD Suite 20261018](https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2026-10-18),
[w64devkit 2.10.1](https://github.com/skeeto/w64devkit/releases/tag/v2.10.1).
GHDL's [synthesis/export interface](https://ghdl.github.io/ghdl/using/Synthesis.html)
is experimental; our conversion boundaries are verified per fixture.

The existing VHDL clock-enable bench passes 175065 checks under GHDL and its
clock-enable RTL exports to Verilog. For the video test, VHDL retains stimulus,
raster generation and assertions. A generated C++ bridge advances the clock,
captures RGB and exits cleanly on an HDL assertion. It contains no video oracle.
run_crt_hq_fast_tests.py bootstraps against both pinned 1024-pixel compact
ModelSim/Quartus captures and requires a wrong-width VHDL assertion control
before the full-raster mode can run. Tool executable hashes, source hashes,
generated files, version strings and measured run times accompany each report.

The tool-only VHDL export specializes unused gamma support output bit 21 for
GAMMA=0. The simulation copy of video_mixer hoists the selected RGB declarations
to module scope to reproduce Quartus lookup; the original sys source is unchanged.
The initial unnormalized model produced 1024 wrong pixels in each path and is
explicitly rejected in reference/fast_hq_initial_scope_rejected.json. The known
legacy procedural-wire diagnostic is allowed only in this tool invocation;
HDL assertions remain enabled. This two-state RTL path complements four-state
ModelSim and Quartus implementation; it does not replace either.

Run through scripts/d_drive.ps1. Tool paths may be overridden with GHDL_EXE,
OSS_CAD_ROOT and CXX_BIN in mister.env. --reference-root selects the worktree
holding the already-qualified compact captures. --negative-width must pass as
an expected rejection; --full-raster checks the exact runner's qualification
hashes before starting. Every generated file and compiler cache stays on D:.


## Fast logical RAM contract

sim/fast/rabbitpunch_ram16_model.vhd and rabbitpunch_ram8_model.vhd deliberately
implement only the tested enabled-read/write RAM contract. Their entities use the
production names inside an isolated fast library; source lists select one
implementation. They never enter files.qip. Native comparison uses generated
renamed entities to instantiate each model beside the real Intel primitive.

run_fast_ram_tests.py passes that simultaneous 256-address native comparison,
including three initial word patterns, both byte lanes, both read ports and
output-enable retention. The unchanged all-bank VHDL contract also passes all
52224 configured words through CPU/inspection, totaling 104553 checks. Exact
inputs, generated comparison fixture and logs are in
reference/fast_ram_contract_checks.json and fast_ram_contract_archive.json.
Same-word mixed-port writes are rejected; X/unknown behavior and native
read-during-write collisions remain outside the abstraction.

The unchanged installed Intel Verilog RAM simulation library cannot be directly
used by this fast backend: its event-based write eligibility logic includes a
self-referential wire rejected by Verilator. The native ModelSim tests continue
to use Intel's actual simulation model. A fast diagnostic using these logical
RAMs must identify that boundary and cannot be called a native M10K proof.


Full-image loader tests reuse the qualified RAM abstraction, but first require
its exact current source/runner byte hashes. A fresh worktree with different
checkout line endings therefore reruns run_fast_ram_tests.py rather than assuming
an old byte-hashed report still applies. The loader worktree's exact contract is
retained separately as reference/fast_ram_loader_contract_checks.json and in the
full_image_loader_archive manifest; the original qualification report/archive
remains unchanged. Generated test-source alternatives are isolated from files.qip.


## Fast sound startup boundary

run_fast_sound_boot_tests.py and sim/fast/sound_fast_fixture.vhd qualify the
T80/sound bus/JT51 startup against both pinned native ModelSim and MAME traces.
Both games pass all 4096 ordered addresses/masks and 215 peripheral values in
958385 synthetic system cycles. Against the native trace, the only differing
value is the previously audited uninitialized B stack save (native XX, two-state
00). Against MAME, three values differ within the same four audited bootstrap
positions. Every other compared RAM value is exact. Neither CPU state nor RAM
is deposited. The original complete sound/physical checks remain authoritative.

GHDL rejects a legacy T80 expression with a nine-bit operand and four-bit mask.
The generated copy uses an explicit nine-bit mask to permit export, and makes
the entire affected block-I/O flag path fatal. This does not claim that the
instruction is implemented correctly by the fast copy. --negative-block-io runs
an original INI program which reaches that fatal assertion after reset (13.209 us),
proving the guard is active. Production/vendor source bytes remain unchanged.
--latches preserves the existing vendor latch behavior during export; explicit
HDL assertions remain enabled, independent of vendor reset unique-case checks.

The first clocked guard exported an artificial assertion register which started
false before the first asynchronous reset edge in two-state evaluation. Its
time-zero rejection is retained in reference/fast_sound_reset_assert_rejected.json.
The qualified copy instead uses a concurrent reset/enable-gated guard, then passes
both startup comparisons and the executing negative control. The rejected model
is not a production sound failure or a passing CPU test.

Exact binaries, source bytes, generated models, private ROM fixtures, independent
traces and logs are pinned by reference/fast_sound_boot_archive.json. The separate
worktree RAM contract is reference/fast_ram_sound_contract_checks.json. These are
supplemental startup proofs, excluding game commands, uPD samples, shared SDRAM,
audible output, general CPU equivalence and hardware. --reference-root selects
private ROM/MAME fixtures; --native-reference-root selects existing native traces.


## Offline music comparison

`scripts/compare_music_captures.py` uses NumPy to compare private immutable
MAME/RTL captures under `debug/audio_reference/`. Install NumPy in the local
D-drive package directory and set `PYTHONPATH` to that directory when invoking
through `scripts/d_drive.ps1`. The script verifies the original qualification
hashes and writes `docs/reference/music_comparison_checks.json`. Audio captures
and ROM data stay gitignored.
