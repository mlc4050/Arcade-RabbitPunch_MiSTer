# RabbitPunch state inventory

What a savestate or a state dump has to carry, kept current as RTL lands (the skill's
`savestates.md`). "Skip" needs a reason: a ROM table from the `.mra`, or something re-derived
every frame.

## RAMs

| Region | RTL | Width x depth | Bytes | Save? |
|---|---|---|---|---|
| Bitmap | rabbitpunch_board_memory / rabbitpunch_ram16 | 16 x 32768 | 65536 | Yes; read-only view port, restore through paused CPU request port |
| Sprites | rabbitpunch_board_memory / rabbitpunch_ram16 | 16 x 2048 | 4096 | Yes; same access paths |
| Tilemaps | rabbitpunch_board_memory / rabbitpunch_ram16 | 16 x 8192 | 16384 | Yes; same access paths |
| Palette | rabbitpunch_board_memory / rabbitpunch_ram16 | 16 x 1024 | 2048 | Yes; same access paths |
| Main work | rabbitpunch_board_memory / rabbitpunch_ram16 | 16 x 8192 | 16384 | Yes; same access paths |
| Sprite line banks | rabbitpunch_sprite_line / rabbitpunch_ram16 | 2 x 16 x 512 | 2048 | Derived pixels and occupancy/index/tag; finish/flush and re-render before resuming video, or capture both banks with scheduler phase |
| Packed tile line banks | rabbitpunch_tiles / rabbitpunch_ram16 | 2 x 16 x 512 | 2048 | Derived BG0/FG pixels; finish/flush and re-render, or capture banks and scheduler phase |

| Sound work RAM | rabbitpunch_sound_bus / rabbitpunch_ram8 | 8 x 2048 | 2048 | Yes; read-only view after drained sound CPU pause, restore writer not implemented |

## Registers and FSMs

| What | RTL | Bits | Save? | MAME `save_item` equivalent |
|---|---|---|---|---|
| Bus FSM: idle/waiting/complete/draining | rabbitpunch_bus.vhd | 2 logical | Future capture at drained/idle boundary | Transport, no direct MAME device counterpart |
| Latched request address/data/byte enables/write flag | rabbitpunch_bus.vhd | 43 | Future; can be discarded only at drained/idle boundary | Current 68000 bus access |
| CPU read-data holding register | rabbitpunch_bus.vhd | 16 | Future | Current 68000 bus access |
| Request pulse register | rabbitpunch_bus.vhd | 1 | Must be inactive at proposed capture boundary | Transport |
| CPU phase divider count and phase | rabbitpunch_maincpu.vhd | ceil(log2(PHASE_DIVIDER)) + 1 | Future, together with CPU | CPU clock phase |
| Memory backend FSM / target / write flag | rabbitpunch_memory.vhd | 2 logical + 5 + 1 | Capture at idle boundary | Transport |
| ROM request address and response holding data | rabbitpunch_memory.vhd | 18 + 16 | Capture at idle boundary | Transport |
| Inspection target, valid and per-bank read holding data | rabbitpunch_board_memory / rabbitpunch_ram16 | Derived pipeline state | Discard only when inspection idle | Debug/video port pipeline |
| Video flags / scroll registers / sprite count and priority | rabbitpunch_io.vhd | 16 + 36 + 12 | Read through explicit outputs; restore through CPU write path | m_videoflags, tilemap scroll, m_sprite_num, m_sprite_pri |
| GGA register file and selected index | rabbitpunch_io.vhd | 128 + 4 | Indexed GGA view; restore through select/data writes | GGA m_regs / m_address_latch |
| Sound command and pending flag | rabbitpunch_io.vhd | 8 + 1 | Capture with sound CPU stopped; future coordinated state loader | generic_latch_8 state |
| IRQ enabled / first-event state / frequency / pending | rabbitpunch_irq.vhd | 4 | Future explicit state loader | CRTC timer configuration and CPU HOLD_LINE |
| CPU previous interrupt-acknowledge cycle | rabbitpunch_maincpu.vhd | 1 | Capture outside acknowledge cycle | Bus protocol edge detection |
| Bitmap fetch FSM and X/Y/nibble/palette-bank metadata | rabbitpunch_bitmap.vhd | 2 logical + 9 + 8 + 2 + 4 | Future capture or drain before video restart | Pixel pipeline, no direct MAME saved state |
| Bitmap request address and pixel output registers | rabbitpunch_bitmap.vhd | 15 + 9 + 8 + 10 + opacity/valid strobes | Drain/flush before video restart | Pixel pipeline |
| Tile lookup FSM, queued descriptor, flags and RAM request | rabbitpunch_tile_lookup.vhd | 58 logical | Drain RAM and consume/drop queued row before capture | Derived tile pipeline; source VRAM and registers are saved separately |
| Tile row FSM, code/row/palette/X/Y metadata and planar ROM word | rabbitpunch_tile_row.vhd | Transport and row metadata | Drain ROM and finish/flush active row before capture | Derived tile pipeline |
| Sprite row FSM, latched code/row/position/palette/flips/priority, last ROM address and planar word | rabbitpunch_sprite_row.vhd | Transport and row metadata | Drain ROM and finish/flush active row before capture | Derived sprite pipeline; source RAM and registers are saved separately |
| Sprite scan FSM, line Y, current index, priority/palette bank and queued candidate metadata | rabbitpunch_sprite_scan.vhd | Transport and candidate metadata | Drain descriptor read and finish/flush queued candidate and drawer before capture | Derived line selection; no original-board list snapshot implemented |
| Sprite line FSM, clear cursor, active bank, bank validity/line tags, staged candidate, forwarding entry and view response | rabbitpunch_sprite_line.vhd | Derived line/pipeline state | Finish/flush and re-render before video restart; no complete save interface | Line buffering and hazard bypass, not game-visible source RAM |
| Sprite logical-line controller FSM, latched command, scan-finished flag and accepted draw index | rabbitpunch_sprites.vhd | Derived line-command state | Finish/flush whole renderer before capture and rebuild the line before output | Coordinates selector, row drawer and line storage; no PCB raster policy |
| Tile logical-line FSM, bank/window cursor, scroll/flags, issued/written counts, pending transport flags and view tags | rabbitpunch_tiles.vhd | Derived line state | Drain transport and rebuild both layer bytes before resuming output | Packed tile-line scheduling; no complete save interface |
| Video line FSM, command, completion flags and aligned pixel/tag registers | rabbitpunch_video.vhd | Derived line/pixel pipeline | Finish/flush and rebuild lines, suppress output until valid | Coordinates renderers and fixed-rate native bitmap read/mixing |
| Native bitmap/palette frontend metadata and valid stage | rabbitpunch_bitmap_pixel / rabbitpunch_palette_pixel | Derived coordinate/color stages | Flush on restore before accepting output | Fixed one-clock native RAM read contract; palette RGB wrapper passes six complete MAME scenes |

| RGB wrapper error-valid/coordinate delay | rabbitpunch_rgb_video.vhd | Derived pixel metadata | Flush on restore | Aligns invalid line tags with native palette latency |

| Held CPU write address/data/byte lanes | rabbitpunch_board_memory.vhd | 42 + shared target/FSM | Drain accepted write or capture pending fields | Preserved across video/CPU reset until a safe native RAM write slot |

## Chip state

| Chip | Module | Addressable? | Tier | Note |
|---|---|---|---|---|
| fx68k | rtl/cpu/fx68k, rabbitpunch_fx68k.vhd | No CPU register state port | CPU simulation integration | Adapter exposes descriptive bus pins; full CPU state capture remains open |
| T80 | rtl/cpu/t80, rabbitpunch_t80.vhd | No CPU register state port | Wrapper test | Descriptive unsigned interface tested; not connected to sound board |
| JTFRAME drawer | rtl/jtframe/jtframe_draw.v, rabbitpunch_tile_row.vhd | No state port | Tile-row simulation | Pixel shifter, counters and request state must finish/flush before restart |
| JTFRAME buffer evaluation copies | rtl/jtframe | Not integrated | Evaluation | Not part of the game state yet |

## Deliberately skipped

| What | Why it need not be saved |
|---|---|
| ROM image and layout constants | Recreated from the selected MRA; no writable ROM state |
| Address decoder | Combinational; derived from the CPU pins |
| Sprite entry arbitration and pixel mixer | Combinational; no stored state. Future line RAM must store occupancy/index/palette/foreground tag separately |

## Frame alignment

No save/restore interface exists yet. Proposed transport capture boundary is a paused
CPU with no outstanding request and an idle adapter; saving an in-flight transaction
would also require the backend's outstanding-response state. Video/frame alignment,
CPU register capture, RAM state arbitration and full savestates remain integration work.

RAM inspection is now implemented: choose a target code and local word address,
assert view enable, then sample data with view valid after the next rising edge.
Shorter banks use the low address bits. The port is read-only; restore must borrow
the CPU request port while paused/drained. No complete state transport/arbitration
exists yet. Simultaneous inspection of the exact byte being written has no promised
hardware value and must be avoided by future snapshot/video scheduling. CPU reset
does not clear any RAM or cancel an accepted ROM/memory request. Power-up RAM contents
are not assigned; comparisons must not rely on uninitialized bytes.

Board I/O initialization is separate from CPU reset. GGA registers can now be read
without borrowing the CPU bus; the boot bench pauses/drains before dumping all 24
video/GGA state fields. IRQ and sound state lack a complete save/restore protocol.
Input/DIP pins must be recorded with the future capture manifest.


## SDRAM transport adapter

rabbitpunch_sdram holds one accepted request per client, byte address, write
word/byte enables, toggle/ack phase, three captured response granules, and the
initialization wait state/counter. The imported controller owns open command,
refresh and burst-capture state. It remains independent of game reset. The
current capture boundary must drain all clients; no save/restore interface is
claimed. ROM contents remain recreated from the MRA rather than saved.


The read-only ROM requester also holds one pending/queued flag per client,
aligned burst addresses, byte-lane offsets and response registers. It has no
cache and no game-reset input; drain it together with the SDRAM adapter before
capturing state or restarting a transaction stream.


Optional last-burst ROM caches add three immutable eight-byte entries with full
aligned addresses, valid bits and per-client miss states/requested addresses.
A restore may invalidate these derived entries after draining transactions;
there is no need to save immutable ROM data. Never invalidate or change images
with pending cache/transport work. This state is independent of game reset.


The connected ROM subsystem adds previous-loading and loader-ownership flags.
A load transition requires drained mapper/cache/controller transactions, and
invalidates derived ROM cache entries. Game reset must not touch these flags;
HPS download integration will hold gameplay reset while this path keeps running.


The logical rabbitpunch_board integration adds wiring only. CPU, I/O, IRQ,
renderer and shared native RAM retain the state and inspection restrictions
listed above. Cold initialization and CPU/video reset remain separate inputs;
CPU pause alone does not make video-owned inspection ports available.


Download control owns an image-valid flag, loading/error flags, acknowledged byte
count, latched pending word/address and transfer/drain FSM. This is load-time
state independent of CPU/video reset. Do not capture/restore during an active
image transfer; complete or reject and drain the image first. HPS/DDR staging
state is not implemented yet.


rabbitpunch_system adds no storage beyond its constituent blocks. Download reset
also initializes board I/O for a new image, while native RAM remains preserved.
Soft reset reaches CPU/video only; ROM loading/caches/controller remain live.


The JT51 evaluation copy owns FM register/shift storage, operator/envelope/phase
state, timers, LFO/noise and accumulators. Its current native interface has no
complete state capture/restore port. The VHDL adapter adds no state. Register
programming can be traced; full sound savestate capture remains unavailable.


The descriptive T80 adapter adds no state. Its enable directly controls CPU
advancement; software pause must first drain/retain external bus transactions.
T80 register/interrupt/machine-cycle state remains inside the unchanged CPU.
A complete sound CPU capture/restore interface is not implemented.


Sound CPU transaction adapter: styp_state tracks idle/waiting/completed/draining;
latched request address/data/write and read reply persist while CPU enables
stall. Pause drains an accepted response; reset drains before CPU restart.
No runtime state-load interface is added. The T80 DIR input is used by simulator
setup only to normalize the MAME comparison's initial CPU registers; no production
savestate support is claimed. JT51's internal state remains vendor-owned.


Native sound RAM contains 2048 bytes, exposed through the read-only sound-board
inspection address/data port only after o_paused. It has no reset clear or
restore writer. The sound bus owns an outstanding ROM address, YM write
address/data and transaction state; it deliberately remains live during CPU
reset/pause to finish the request owed by soundcpu. The main board remains the
owner of command byte/pending state. ADPCM strobes are not chip state or audio.


JT7759 is now an unchanged isolated evaluation component behind an unsigned
VHDL standalone wrapper. It has no production state capture/restore interface.
The native 17-bit ROM address and 9-bit raw signed PCM are exposed; bank and
board-control state are not implemented yet. Native/wrapped synthetic tests
exercise playback and reset, not savestates or game audio.


ADPCM board-control adapter owns one bank bit, physical reset state, latched
8-bit command, reset-release readiness and idle/waiting/start FSM. Its bank is
part of every exposed 18-bit sample ROM address. A future frontend must reject
stale responses after address/bank changes; no frontend cache or queue is added
by this adapter. No restore interface is implemented yet.


rabbitpunch_audio adds no storage: it connects sound_board's ADPCM strobes/data
to the sample controller. Program/sample transport, main command ownership and
PCM mixing remain external. Pause drains the sound CPU while both chips keep
running; this is a logical CPU-pause contract, not complete-system savestates.


Prepared read arbiter owns three pending credits, three latched 27-bit aligned
addresses, selected/active owner, round-robin next index and three returned
64-bit data registers. Idle means no backend request remains outstanding;
parent clients must also consume visible replies before image invalidation.
There is no reset cancellation or new RAM. The production ROM subsystem now uses it on physical port 2 beside the
loader ownership mux.


Audio ROM frontend state: independent program/sample request FSMs, burst byte
offsets, pending sample address and one returned sample byte/tag. Existing
burst-cache instances retain 16 bytes across game reset. Invalidate after both
clients and shared-read queue drain, before changing images. The sample output
valid compares the complete current banked address, so a stale pending reply
cannot escape after a bank change. No production reset cancels an accepted read.


The complete logical system connects the existing main command latch/pending
bit directly to audio's command input/IRQ and returns its read acknowledgment.
No second mailbox is added. System pause reports complete only when both CPU
adapters have drained; chip clock enables continue independently of CPU pause.
Sound native RAM has its own paused inspection port. Sound/sample caches retain
ROM data through a game reset and invalidate on drained image replacement.
Separate raw FM and sample PCM outputs remain available before final mixing.


Mono output adds a 16-bit registered PCM word and two FM warmup flags. Reset
clears the flags; the second Yamaha sample marker qualifies its contribution
after one complete accumulator period. Stopped chip enables cannot release the
warmup mask. Mixing adds no RAM or video buffering. No restore interface is added.


The load-time DDR wrapper adds one pending 16-bit stream word/address and a
previous-active flag. Native rom_loader owns the 64-bit granule, word index,
byte offset and copy FSM; ddram_phy owns one outstanding external read. These
are load-time transport state and must drain before ownership changes; neither
is reset by a gameplay soft reset. No additional RAM or gameplay DDR use is added.


The HPS-signal frontend owns its load-mode FSM, previous ROM-download flag,
seen-write/error/mode bits, byte count, one held low byte and one pending word.
Copy and direct-stream paths share one downstream ready/valid contract. A
framework reset only gates starting a pending DDR transaction; it does not
clear loader state or rearm a completed image. Errors remain latched until a
fresh ROM transaction, with accepted word/read debt drained before release.


Input state adds the downloaded 16-bit DIP word; only cold initialization clears
it. Inherited per-key latches/toggle state retain held keyboard actions. Manual
pause owns one latch and previous-button bit, separate from OSD/debug/state
pause levels. Game reset clears manual pause while preserving DIP metadata.
No full savestate restore path is added by these controls.


The logical platform adds no state. It joins host status/reset and the existing
controls, download frontend and complete system. The frontend now defers a
fresh image until the previous downstream loader drains; no generation queue
or clock domain is introduced. Physical HPS/DDR ownership and raster remain
external.


The output adapter owns five stages of enable/active/sync/blanking/accepted
metadata and coordinates, output RGB/control registers, and one sticky
underflow flag. Reset flushes all stages. They are ordinary registers (zero
RAM in Quartus), no line/frame pixel storage or additional clock domain.


The standalone maintenance adapter owns a one-request FSM, byte-lane selector
and held bus payload. Initialization drains outstanding memory debt before
releasing pause and suppresses its stale client response. It adds no RAM; the integrated system uses it through the shared bus owner.


The standalone bus owner adds one held packet/pending bit per requester and
one active-owner FSM. Its all-idle output includes offered requests as well
as pending/active debt; image replacement must consume that output when the
owner is integrated. No reset cancels ownership or an accepted memory request.


Maintenance is now connected through board/system/platform. Its pause joins
the main and sound adapters, and ready waits for both to drain. ROM generation
handoff also waits for all board-owner packets, including currently offered
requests. The idle CPU path bypasses packet storage; selected backend payload
is held for the reply. Reset clears I/O effects but acknowledges accepted I/O
so no owner debt is stranded. HPS persistence/restore orchestration now connects through the high-score service described below.


High-score persistence adds a 256-byte native dual-port RAM split into two
128-byte banks, the saved-bank selector/valid/dirty/notified flags, initialized
flag, pending OSD capture, byte index, download count/error, prior host flags,
startup/retry counter and acknowledged-access FSM. Only complete snapshots switch
banks. A game reset cancels partial work and keeps the last saved bank; a new ROM
or metadata generation invalidates it. The profile parser owns a 192-bit packet,
count/error/previous-active state and decoded profile/wait fields. Full savestate
support must preserve the selected set/generation alongside those flags, or drain
and rebuild persistence without mixing files from another game.

The maintenance-client arbiter owns a session FSM (idle/external/score) and one
accepted-byte pending bit. Client payload is held by the selected caller until
acceptance; no extra memory transaction queue is introduced. Drain the shared
helper/backend before taking a stable state. A canceled score client initializes
only its helper session; backend bus ownership still drains independently.


Native RAM configuration now uses zeroed physical M10K storage. Bitmap uses
constant FFFF XOR encoding to expose MAME's transparent-15 startup pixels;
other production word banks and byte RAM use zero. State view/maintenance APIs
return logical values and need no format change. A raw vendor-memory dump of
the bitmap must be decoded with FFFF. CPU/game reset does not clear these banks.
See RAM_POWERUP.md for startup scope and tests.


The provisional clock-enable generator adds a /7 pixel phase, modulo-35 main
and sound accumulators, a sound half-rate phase bit and modulo-875 ADPCM
accumulator. These advance on the system clock and are separate from user pause
and game reset. The raster adds two nine-bit beam counters; it has no pixel RAM.
The PLL/reset boundary adds three cold-initialization release registers. Its
asynchronous assertion covers PLL clock loss; game reset does not reset the PLL.

The scanline scheduler adds a t_state/styp_state request/render FSM, one held
render bank/Y, two ready-bank bits and eight-bit row tags, display bank/valid,
armed and sticky-underflow flags. It starts row zero during vertical blank and
prepares each following visible row in the spare bank. A handoff consumes the
ready tag before the next physical row. Late completion cannot switch banks
mid-line. Initialization must also reset/drain the connected renderer before
new requests; no extra line/frame pixel storage or full savestate interface is
added. These blocks are connected by the production continuous machine.

The continuous scanout wiring now connects the scheduler, beam and output adapter
with the platform in rabbitpunch_machine. It adds no pixel storage. Game readiness
loss clears scheduler ownership and sticky output diagnostics while beam counters,
sync and clock-enable phases continue. The main CPU's optional external-phase mode
stores its alternating phase only when enabled and not frozen; pause leaves the
shared fractional enable generator running. The legacy internal divider remains
available by default for independent logical tests. Full savestate capture must
include both the shared enable phases and the CPU adapter phase, or cold-restart
that timing boundary rather than independently restoring only one of them.

The instrumented revision adds read-only rabbitpunch_debug telemetry, separate
from emulated game state: seven saturating 32-bit counters, last main request,
last main write/data/byte mask, last sound request/data, sampled beam/status and
a registered 511-bit packet with core/build/layout identity. Counters have only
configuration-time initialization and survive gameplay/PLL reset. This telemetry
is not a savestate and is omitted from the release revision. See DEBUG.md.

Optional video presentation adds only unchanged framework line-buffer/filter
state after native scanout. It is not emulated board RAM. Native bypass has no
added pixel storage; optional modes rebuild their line history from the running
raster after reset/restore. Frame/pixel debug counters remain tied to native
scanout. No full-frame render buffer or game-clock domain is introduced.

HDMI sizing metadata adds two bits counting observed vertical-sync edges and
a previous-sync bit, plus unchanged framework arithmetic/geometry state. It
holds normal ratio metadata while geometry is first measured; no pixels or
emulated game state pass through it. It has no game-reset/pause dependence,
and uses the existing system clock with pixel enables.


The common viewport flip adapter adds three single-bit presentation registers:
applied orientation, outstanding render and outstanding pixel transaction.
Initialization clears them; game-not-ready clears transaction ownership and
selects the requested orientation while output is blanked. Once ready,
orientation changes only at a safe frame-prepare boundary, before the next
row-zero request. Requests accepted on the same edge as a previous completion
retain ownership. Restore must drain or reset this boundary together with the
renderer/scanout. No RGB, line or frame storage is added.
