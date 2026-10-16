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
policy and final top-level arbitration remain to be integrated.

The test covers seven completed reads/writes with upper/lower/full-word lanes and
0/3/11-cycle backend delays, holding AS after acknowledgement, delayed byte strobes,
and a new request immediately after resetting a CPU with an outstanding transaction.

```
./scripts/d_drive.ps1 scripts/run_board_tests.py
./scripts/d_drive.ps1 scripts/build_mras.py
./scripts/d_drive.ps1 scripts/validate_mra.py "releases/_dev/*.mra"
./scripts/d_drive.ps1 scripts/check_boot_writes.py
```

ModelSim logs are debug/baselines/board_decode/result.log and board_bus/result.log.
The interfaces have not been added to files.qip; the inherited demo remains connected.
These MRAs are development definitions, not a playable release. No RBF has been built.

## CPU adapter and diagnostic

`rabbitpunch_fx68k.vhd` is a naming-only adapter around unchanged vendor logic.
Its ports describe the bus signals; the vendor's pin names appear only in the
component declaration and translation map. `E` means the Motorola 6800 peripheral
clock, `VMA` qualifies a peripheral address, and `VPA` selects the peripheral cycle
or an interrupt autovector. The wrapper documents these signals even where unused.

`rabbitpunch_maincpu.vhd` connects that adapter to our request bus. At the evaluation
48 MHz clock it alternates phase enables every three clocks, giving an 8 MHz CPU.
Delayed replies add actual wait states. Pause stops phase advancement once the
current bus cycle finishes; the backend can still complete outstanding replies.
The system reset currently drives both external and power-up reset. Level-1 IRQ
and autovector acknowledge are connected and tested; bus error, DMA and general
6800 peripheral cycles remain unconnected. This is not a complete board model.

The diagnostic executes real 68000 opcodes: word writes, upper/lower byte writes,
readback through D0 and writes to distinct RAM addresses. It checks the resulting
1234/1234/1234/600d words, memory response latencies 0/17/65 clocks, pause with no
new requests, and reset/replay. Two runs complete with 14 writes and eight reset
vector reads. The test uses behavioral memory, so it does not validate FPGA BRAM
indexing or SDRAM transport. Log: debug/baselines/board_maincpu/result.log.

## Real-ROM comparison against MAME

`check_boot_writes.py` loads each game's main ROM from the previously verified
MAME region dumps (`build_mras.py` regenerates these), and captures 10000 MAME writes
after an explicit soft reset. The Lua script guards against repeated autoboot
execution on reset. The runner verifies the first four vector reads, including
their data, before accepting the trace. Later reads of low ROM addresses are not
miscounted as additional resets.

For both rabiolep and rpunch, the first 10000 RTL writes match MAME exactly in order,
address, byte mask and masked data. This includes stack writes, GGA initialization
and RAM/bitmap clearing. No trace alignment or skipped writes are used. The CLR.B
read preceding a write-only GGA register write returns unmapped ffff, as in MAME.

This is an early execution check, not a successful game boot: no raster events
or sound CPU are generated. RAM and board I/O are actual VHDL. The bench stops with
a failure if a command is pending when the CPU polls the missing sound CPU. Timings and
ROM prefetch streams are not compared. Evidence: reference/boot_checks.json;
raw traces: debug/boot_writes/<set>/mame_writes.txt and
debug/baselines/boot_<set>/rtl_writes.txt.

## VHDL conventions and local storage

Use numeric_std and unsigned for vectors, with iu16_/ou16_ for 16-bit ports,
iux_/oux_ for unconstrained ports, su16_ for internal signals and vu16_ for
variables. Single-bit ports use i_/o_, internal std_logic uses s_. Integer/natural
signals use sint_; integer/natural variables use vint_. Vendor pin names remain
inside their descriptive adapters. Unchanged third-party files retain their style.

Run Python tools through scripts/d_drive.ps1. It places TEMP/TMP/TMPDIR, Python
cache/user-base, pip cache and ModelSim configuration under this repository on D:.
Each simulation uses its own D-drive work library and logs. The shared JTAG guard
retains its machine-wide marker location so other repositories still coordinate;
these simulation runs need no JTAG marker creation.

`rabbitpunch_t80.vhd` provides the same descriptive boundary for the selected Z80
core. Public address/data ports are unsigned; required conversions to the vendor's
vector types occur only in its port map. The T80 wrapper regression runs the donor
LD/memory-write/OUT/HALT program and checks the complete I/O address (4200), data
(42), RAM write address (8000), and halt output. The wrapper is not connected to a
sound board yet. Imported TG68K evaluation files and MiSTer sys sources remain intact.
The mixed-language toolchain smoke-test VHDL also follows the same conventions.

## Main memory backend

`rabbitpunch_memory.vhd` uses the tested address decoder and five instances of
`rabbitpunch_ram16.vhd`. Sizes are bitmap 32768, sprites 2048, tilemaps 8192, palette
1024 and work RAM 8192 words: 52224 words / 102 KiB total, excluding sound RAM.
The CPU port reads or writes one word, with independent upper/lower byte enables.
There is no RAM clear loop or CPU-reset input. Accepted requests complete across
CPU reset as required by the bus adapter. Writes acknowledge with zero data;
read data is registered, then acknowledged on the following clock.
The RAM wrapper instantiates Quartus's `altsyncram` in `BIDIR_DUAL_PORT` mode:
CPU read/write uses port A, and inspection/video reads use port B. Both use
the same clock. Its public interface remains unsigned; vendor conversions are
confined to this wrapper. ModelSim uses the installed `altera_mf` library.

ROM requests expose a held, aligned 18-bit byte address and one request pulse.
The external transport returns one valid/data response. No 68000 byte swapping is
done here: the transport must return the big-endian word in normal CPU bit order.
Requests to board I/O or unmapped space are not acknowledged by this module;
`o_request_supported` identifies accesses that a separate I/O responder must handle.
The caller must serialize requests until the response; this is not a queued bus.

The read-only second RAM port can serve future video/state inspection. It uses a
target code and local word address, with one-cycle valid/data. Shorter banks use
the low word-address bits. Read-during-write collisions at the same address have
no guaranteed hardware result. The future video/snapshot policy must define that
scheduling; this interface does not choose a latch point or add a frame buffer.
State restoration can borrow the CPU request path while the CPU is paused/drained.

`memory_tb.sv` initializes every location to a bank/address-specific pattern before
reading it, then verifies every word across all banks. It also checks byte merges,
upper-address mirrors, inspection reads, and ROM delays 0/20/40 clocks. It reports
104486 checks. Six numeric_std metavalue warnings occur during initial combinational
decode settling at time zero; no test reads uninitialized RAM. All test assertions
pass. The standalone memory fit at commit ea6e0fd uses 102 M10K blocks (18%),
835584 memory bits (15%), 226 ALMs and 58 registers on 5CSEBA6U23I7.
At the 48 MHz evaluation constraint, worst setup slack is +7.947 ns and worst
hold slack is +0.209 ns; pulse-width checks pass and no paths are unconstrained.
Evidence is in reference/memory_synth.json. This is a virtual-I/O block test,
not a full MiSTer fit, final clock plan, or hardware verification.

The real-ROM boot bench now instantiates this VHDL backend rather than a behavioral
RAM array. ROM transport and external input pins remain testbench models; inactive
controls are zero (active-high hardware) and DSW defaults come directly from each
generated MRA. A poll of a pending sound command fails rather than fabricating a reply. The
comparison length is selected with `check_boot_writes.py --writes <count>`.

## Board I/O and level-1 interrupts

`rabbitpunch_io.vhd` implements video-flag byte merging, four nine-bit scroll
registers (full-word writes only), six-bit sprite count/priority, GGA select/data
storage, player/service/DIP reads and the sound-command mailbox. Each player read
combines the common service byte above that player's control byte. Unmapped reads,
including write-only ports, return ffff. Cold initialization is separate from CPU
reset. Sound commands remain pending until read by the future sound CPU; a new
write wins over simultaneous consume. No delayed fake acknowledgement is generated.

The GGA selector masks to four bits; all sixteen byte registers have an indexed
state read port. Data writes expose an address/data pulse. Register 0b rearms the
IRQ scheduler: c0 selects two interrupts per frame, other values select one, as in
the pinned MAME model. See MAME_KLUDGES.md for this incomplete chip model.

`rabbitpunch_irq.vhd` accepts external vblank-start and half-frame events. The first
event after configuration must be vblank. Level 1 holds until acknowledged.
Reconfiguration preserves an existing pending IRQ; an event simultaneous with ack
sets it again. No pixel clock, frame rate or raw raster is assumed here.

The CPU adapter maps level 1 to active-low IPL=110. A function-code-111 address-strobe
cycle asserts VPA for autovectoring and is excluded from normal memory requests.
One acknowledge pulse is emitted per such cycle. The directed CPU test verifies
STOP waits, vector 25 at address 64 is fetched, three exception words are stacked
through VHDL work RAM, the handler executes and RTE resumes after STOP. Interrupt
acknowledge addresses never reach memory.

I/O tests cover all GGA registers, byte lanes, scroll masks, inputs, sprite limits
and mailbox behavior. IRQ tests cover arming, one/two events per frame, holding,
rearm and coincident events. The real-ROM bench pauses/drains before recording 24
video/GGA fields, then compares them to an independent reconstruction from MAME
writes. Its raster event inputs remain low; this is not a comparison of the games'
interrupt timing or evidence of a full game boot.
