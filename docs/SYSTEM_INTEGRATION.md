# Logical system integration

rabbitpunch_system joins the CPU/I/O/video board, ROM requester/cache/SDRAM
subsystem and sequential image download controller on one i_clk. It adds wiring
plus registered mono mixing and its startup-validity flags. A configured FPGA starts without a valid image and holds CPU/video reset.
ROM initialization and loading continue while gameplay is held in reset.

The caller supplies raw 16-bit image words through valid/ready, with low byte
at the even byte address, plus external logical line/pixel/raster-event inputs.
HPS ioctl/DDR staging, PLL, SDRAM pin-clock phase, physical scanout and
MiSTer framework integration remain open. This is not a playable core top.

IO cold initialization is held during download reset, so a replacement image
starts with cleared board registers. Native RAM is preserved. CPU/video reset
combines external game reset, download reset, cold initialization and ROM-not-
ready; the ROM transport does not receive that composite gameplay reset.
i_initialize is the cold SDRAM initialization input: do not assert it while
transactions are pending. Soft resets use i_game_reset and do not recopy ROMs.

The full default image size is ROM_IMAGE_SIZE. A size generic permits bounded
synthetic diagnostic images in simulation; it does not change the ROM layout or
an MRA. No real-game ROM bytes are contained in the diagnostic.

run_system_download_tests.py downloads three 32-byte 68000 programs through real
SDRAM commands. Each repeatedly executes MOVE.W #value,$000fc000 then branches
back. The first writes CAFE and the replacement writes BEEF, detecting stale
cached program words. The test checks CPU write addresses/data/byte masks and
pauses the CPU to read back native RAM. It also verifies that soft reset reruns
the second program without another download. A subsequent partial image holds
the CPU in reset and reports an error; a final full image recovers and executes.
Logical video remains idle in this
reset/download-focused test; concurrent video and captured graphics have their
separate regressions. reference/system_download_checks.json pins this proof.

The system implementation target fits the full-size logical system with
same-clock logical test boundaries and direct SDRAM pin wiring. Its external
SDRAM timing assumptions are hypothetical, as in SDRAM_TRANSPORT.md. No extra
clock pin or PLL is introduced; final shifted SDRAM clock wiring remains a
physical integration task. The earlier main/video-only implementation used 3275 ALMs,
4510 registers and 112 M10K blocks (907936 RAM bits); worst setup is +4.035 ns
and hold +0.107 ns across all reported corners. Six clock/coverage categories
have zero violations. Exact scope and fitted commit: reference/system_synth.json.


## Connected audio

The wrapper now includes rabbitpunch_audio and connects the existing main sound
latch/pending state to its command IRQ, returning the sound CPU read acknowledgment.
Program/sample ROM clients share controller port 2 with main cache misses; tile
and sprite reads retain the higher-priority physical ports. External enables
control sound CPU, YM, YM half-rate and ADPCM cadence on the same system clock.
Defaults disable these enables for the legacy download-only test. System pause
completes only after both CPUs drain, while chip enables can continue playback.
Raw FM left/right and sample PCM remain available as unsigned buses carrying
signed bit patterns, alongside a registered saturated mono output. A sound-RAM inspection port requires the sound CPU paused.

run_system_audio_tests.py executes four downloaded 32-byte 68000 programs which
write commands 42/43 to $0c000e and stop. The real T80 interrupt handler reads and
acknowledges the internal latch, stores each command at F800, selects its sample
bank and starts synthetic playback. Both runs produce nonzero PCM, both CPUs
pause, sound RAM reads back the command and playback plus YM cadence continue.
Replacement downloads exercise reset and hot ROM-cache invalidation. One starts
during nonzero PCM, checking abort/mute, ownership drain and playback recovery.
Evidence: reference/system_audio_checks.json. Sound/sample fixture regions are
directly preloaded; this is not a full-image download or real-game audio proof.
The existing three-image/partial-download/soft-reset test passes with audio
instantiated and its enables disabled. Expanded system implementation passes all reported 48 MHz corners with 5952
ALMs, 7141 registers and 927339 RAM bits. The eight sound-memory geometries are
checked alongside the total RAM budget; six coverage categories have zero
violations (reference/system_synth.json). The offered-request versus idle race found during active playback is fixed and
its directed ROM/download/playback regressions pass. The final mono revision
also passes implementation: 6000 ALMs, 7176 registers, 927339 RAM bits, worst
setup +2.775 ns and hold +0.089 ns across all reported corners. Its fitted
commit and precise scope are in reference/system_synth.json.


Mono arithmetic uses the pinned MAME routing gains and sums before halving.
JT51 PCM is masked until one complete sample period follows reset; stopped
chip enables keep the mask asserted. Disabled-clock download/reset tests require
mono output zero, and playback tests require defined output bits with no mixer
arithmetic warnings. Final fixture/RTL hashes are in the corresponding reports.
The 2000/256 real-ROM proof predates mono output; its exact sources are pinned in
reference/system_boot_checks.json, independently of the synthetic playback tests.


Final-wiring startup smoke checks for both games pass 32 main and eight sound
writes after the loader-idle and mono/startup changes. These supplement the
larger pre-mixer comparison (reference/system_boot_32_8_checks.json).


The extended final-system Rabio Lepus comparison passes all 10000 main-CPU
and 4096 sound-CPU ordered writes against MAME through shared SDRAM
(reference/system_boot_rabiolep_10000_4096_checks.json). Explicit MAME RAM and
sound-register seeds, direct preloaded ROM plus 32-byte real header download,
and idle logical video/raster retain the bounded scope of the earlier test.
Rabbit Punch's equivalent run is still in progress; this is not full game boot.


Production maintenance now uses the ordinary work-RAM CPU port after both CPU
adapters confirm pause and the main bus drains. The CPU path bypasses the owner
when idle, retaining its request/reply edges. Full synthetic CPU tests consume
restored bytes, preserve user pause, drain reset debt and replace images on
queued I/O/ROM boundaries. Audio tests verify maintenance write/read during
continued sample playback. Platform and native HPS command tests also pass.
See MAINTENANCE.md and reference/system_maintenance_checks.json. Physical timing
and HPS persistence remain separate; the new owner needs its own implementation
and real-ROM prefix verification before those are claimed for this revision.
