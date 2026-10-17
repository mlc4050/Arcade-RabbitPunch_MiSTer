# Logical system integration

rabbitpunch_system joins the CPU/I/O/video board, ROM requester/cache/SDRAM
subsystem and sequential image download controller on one i_clk. It adds wiring
only. A configured FPGA starts without a valid image and holds CPU/video reset.
ROM initialization and loading continue while gameplay is held in reset.

The caller supplies raw 16-bit image words through valid/ready, with low byte
at the even byte address, plus external logical line/pixel/raster-event inputs.
HPS ioctl/DDR staging, PLL, SDRAM pin-clock phase, physical scanout, sound and
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
physical integration task. The completed implementation uses 3275 ALMs,
4510 registers and 112 M10K blocks (907936 RAM bits); worst setup is +4.035 ns
and hold +0.107 ns across all reported corners. Six clock/coverage categories
have zero violations. Exact scope and fitted commit: reference/system_synth.json.
