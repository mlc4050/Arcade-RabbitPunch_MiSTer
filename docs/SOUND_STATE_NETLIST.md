# Complete sound-state VHDL evaluation

The original imported JT51/JT7759 sources remain pristine. An isolated generated
VHDL implementation is being evaluated to expose every reachable state element
instead of adding incomplete hand-selected state ports to vendor Verilog. This
is not connected to production audio or the OSD.

The canonical optional ADPCM state model now uses the audio branch's corrected
silence controller and exports189 bits in six words. Its native/formal receipts,
source provenance and preserved prior model are documented in
[ADPCM_STATE_REGENERATION.md](ADPCM_STATE_REGENERATION.md). The192-bit inventory
and FPGA results below describe the earlier imported-controller model; they
do not qualify the corrected model's FPGA timing or complete game restoration.

## Inventory

`scripts/inventory_sound_state.py` verifies the production vendor hashes, reads
the normal synthesis configuration without `SIMULATION`, lowers processes,
flattens hierarchy and maps memories. Optional generic gate mapping supplies a
small JSON primitive vocabulary; no ABC, FPGA build or hardware access occurs.
The exact tool revision, source/log/netlist hashes and counts are recorded in
`reference/sound_state_inventory.json`.

| Original hierarchy | JT51 state bits before bit-level pruning |
|---|---:|
| Accumulator/output | 199 |
| Envelope generator | 548 |
| LFO | 97 |
| Register/parameter/control bank | 1731 |
| Noise | 36 |
| Operator and feedback pipelines | 616 |
| Phase generator | 779 |
| Timers | 26 |
| Total | 4032 |

Bit-level lowering removes sixteen unused bits, leaving **4016 state bits** in
the generated JT51 implementation. The total is not directly comparable with
the other donor's 2820-bit format: versions and optimization boundaries differ.

| Original hierarchy | JT7759 reachable state bits |
|---|---:|
| Decoder sample/step | 13 |
| Control/command/address/timing FSM | 86 |
| ROM/FIFO transport | 77 |
| Divider and registered enables | 16 |
| Total | 192 |

The JT7759 transport includes all four FIFO bytes, valid flags, pointers,
outstanding read controls, ROM address, response data/valid and DRQ history.
Constant ROM/signature tables are combinational data rather than writable game
state. Unused signals removed by lowering have no path to the chip's outputs.

## Generated VHDL boundary

`scripts/generate_sound_state_vhdl.py` accepts only AND, OR, XOR, NOT, mux and
positive-edge DFF primitives, including positive asynchronous reset variants.
Unknown cells, additional/derived clocks and duplicate state drivers are errors.
It emits descriptive VHDL ports, an exact primitive network and one scan bit for
each surviving DFF. A manifest pins every state bit, generator/input/tool hash
and generated file. Files are regenerated, never hand-edited.

`i_state_hold` freezes every sequential element, including ungated write/control
logic. Asynchronous resets are masked while held so a partially restored control
word cannot erase another restored word. Releasing hold restores the original
reset behavior. This reset/freeze boundary passes the isolated fits below;
whole-core integration still needs timing qualification. While held, a 16-bit
word address selects a 32-bit read/write
word; the final word's unused bits read zero. JT51 has 126 words; JT7759 has six.
The parent must preflight an image and keep hold asserted across the full load.
It must also manage external ROM transport and board-control state coherently.
Mask outward ROM-request side effects and mute PCM while scan words are changed:
partial register images can otherwise expose transient control/address values.
Hold does not make a partially loaded image safe for neighboring live clients.

Known explicit state initializers are retained; otherwise flip-flops use zero
power-up state as an explicit FPGA initialization contract. Temporary scalar
wires have no authored initializer. Processes group up to one scan word with
the same clock/reset, sharing its write decode without constructing a global
wide scan crossbar. State order is unchanged and remains pinned in the manifest.

ADPCM native comparison uses compiler `+initreg=r+0` and `+initmem=r+0` as its
scoped FPGA-zero contract. FM native comparison uses the pristine four-state
model without global initialization overrides: live-enable reset, all-register
software initialization and actual timer loads establish the exercised state.
There are no simulator forces/deposits. Neither case proves general four-state
power-up identity.

The baseline runner now accepts optional `verilog_defines` and `vlog_options`
arguments for these tests. Existing callers still receive the unchanged
`SIMULATION` default. These evaluation tests deliberately omit that define so
JT7759's simulation-only bad-divider seed does not change the comparison.

## Qualification and remaining gates

The canonical generated JT7759 passes
`scripts/d_drive.ps1 scripts/run_adpcm_netlist_state_tests.py`. It matches the
pristine native chip for 1213 clocks through nonzero synthetic standalone
playback with throttled ROM replies, freezes/reloads all 192 bits, and restores
the same image three times with **12288 exact immediate continuation clocks**.
Busy, DRQ, ROM address/request and PCM are compared from the first resumed clock.
The canonical generated JT51 also passes native comparison for 16256 clocks
through a nonzero feedback tone with both running timers and a pending IRQ.
All 4016 state bits pass complement/write/read and exact restoration, followed
by three **4096-clock immediate continuations** across status, IRQ, sample
marker and all four PCM outputs. The trace has 4096 nonzero tone clocks.
See `reference/adpcm_netlist_state_checks.json` and
`reference/fm_netlist_state_checks.json` for exact source/log hashes. Their
original `*_word_groups_checks.json` receipts retain executed model paths.
`promote_sound_state.py` verifies matching native/formal hashes and copies
byte-identical models into the canonical directory; earlier models and reports
are preserved without deleting ignored artifacts.

Both generated implementations pass normal-mode formal correspondence:
`reference/jt7759_state_normal_proof.json` and
`reference/jt51_state_normal_proof.json`. The checker synthesizes the generated
VHDL through GHDL, pairs every flop with its pristine JSON counterpart, cuts
those flops and gives both models identical arbitrary current-state/input bits.
It proves every original output, every next-state D function and asynchronous
reset condition/value. Clock polarity and the absence of extra/merged state
are checked separately. The final JT51 checker closes all 12124 equivalence
points, with zero unproven points, using independent output-cone proofs.
Optional structural merging and earlier bounded frontend/monolithic timeouts
are preserved and unscored. Corresponding-net lookup is indexed rather than
quadratic in the number of state bits and wires.

These are two-state, normal-mode proofs under trusted synthesis frontends and
primitive mapping. The inactive scan-write protocol assertion is omitted with
GHDL `--no-formal`; it is inactive because scan controls are tied off. Power-up
identity, scan-mode behavior, analog timing and Quartus fitness are separate
gates. An earlier JT51 fixture failed before capture at 122960 ns;
`reference/fm_netlist_native_mismatch.json` preserves that negative result and
the exact model/bench/log are archived on D:. That initialization-override run
is not a restore pass and remains a negative receipt. A subsequent scalar
full-software-init run reached its 1200-second wall limit without a pass/failure
marker (`reference/fm_scalar_software_init_timeout.json`). The final word-grouped
model/fixture described above passes without those FM initialization overrides;
neither its success nor the two-state proof erases the earlier scoped results.

Both isolated state-enabled Quartus projects pass with registered virtual
I/O at 48 MHz, seed 3 and two compiler threads, built from `a272220`. They use
`build_staged.py --synth-check jt51_state` or `--synth-check jt7759_state`, after
committing and coordinating ownership. Exact model/report hashes and all-corner
timing results are in `reference/jt51_state_synth_checks.json` and
`reference/jt7759_state_synth_checks.json`.

| Isolated block | ALMs including test boundary | Core registers | Worst setup slack | Block RAM |
|---|---:|---:|---:|---:|
| JT51 state | 4946 | 4541 | +4.918 ns | 0 |
| JT7759 state | 464 | 247 | +10.439 ns | 0 |

All reported setup, hold, recovery, removal and minimum-pulse checks are
nonnegative; unconstrained-path gates pass. Core-register counts exceed their
4016/192 mapped state sizes, with dynamic scan read/write still observable.
This is a preservation sanity check, not post-fit equivalence or a full-shell fit.

The audio comparison session also qualified the combined optional CPU/FM/ADPCM
parent at commit `c108e8fd794ca3dacf31a017ddc5ce5c4178959e` with capture inactive.
Both ROM sets reproduce the original RTL's complete PCM, WAV and timestamped
chip-write traces for nine seconds of command99 music (562493 PCM samples per
set). The passage exercises active FM with ADPCM idle; it does not qualify
active sample playback or restoration. The copied receipts retain their exact
candidate source hashes in `reference/state_sound_music_*_cmd99_checks.json`.
These receipts precede the response-owner/reset and mixer-state changes.

Commit `fd3434b7dcfacb2b4e1f2d70106b4e6846d3ef85`, including those later
response-owner/reset and registered-mixer changes, now also reproduces the
complete original RTL PCM, WAV and timed peripheral trace for a three-second
active ADPCM sample24 commandE4 in both ROM sets. See the copied
`reference/state_sound_sample_*_checks.json` receipts. All capture controls
remain inactive in this comparison; it is not a combined-audio restore test.

This equivalence retains the original JT7759's approximately17.21ms early PCM
onset relative to MAME. Sample24 begins with silence header0B: the legacy chip
waits1409 control enables, while pinned MAME waits12288. The independent audio
investigation and exact reference hashes are retained in
`reference/adpcm_silence_timing_diagnosis.json`. A separate VHDL correction is
under evaluation by the audio session and has not changed these pinned state
models or their provisional ABI. Any adopted correction must include complete
state coverage and renewed normal-mode/continuation qualification.
These normal-mode audio fixtures retain the original continuous cadence and
scripted ROM-reply harness; whole-machine clock freeze/load is a separate gate.

For this comparison, the private GHDL-to-Verilog export needed 404 guarded
one-bit unknown-condition ternary simplifications. An expression with an X
arm and Z condition merges to X for all four possible values of the other
one-bit arm. The audio tool applied only that identity, retaining raw exports,
delta audits and hashes; canonical generated VHDL remained unchanged. This
was not a conversion of unknowns to zero. Native/four-state and formal evidence
above remains attached to the original canonical sources.

Before production integration:

1. Broaden initialization/four-state and scan-mode checks around
   the proved normal-mode functions. Audit reset assertion/deassertion, init,
   mux unknown semantics and imported table contents. The normal proof is not
   a proof of scan protocol or analogue behavior.
2. Broaden immediate continuation tests across arbitrary phases, active writes,
   IRQ flags, FM feedback/noise/LFO/envelope states, sample commands, every ADPCM
   header path, reset/control changes and ROM wait phases. JT7759 slave mode is
   outside the current production configuration and is not qualified by this test.
3. Recheck resource use and timing in the complete integrated core. The isolated
   Quartus 17.0.2 fits above close block fitness only; surrounding arbitration,
   state fanout and physical presentation remain outside their timing boundary.
4. Integrate the surrounding sound-board/bus/ROM frontend, mixer and command state
   with a whole-machine freeze/load boundary. These chip ports alone do not make
   complete game savestates.

Physical HSync/VSync and pixel cadence must continue during state transfers.
The isolated cadence/raster hold ports must not simply freeze native scanout.
Choose a documented blanking/phase alignment for capture/release, maintain
physical presentation timing while the game is held, and rebuild invalidated
line/rotation history before publishing pixels. Emulated game phase and physical
display phase need an explicit policy rather than independently loading them.

All generated files, caches and reports stay on D:. Coordinate native simulation
and FPGA tools with the audio session and observe `hwlock.py`; no JTAG/deploy or
production audio replacement is part of this evaluation.
