# CPU and JTFRAME baseline results

## Main CPU selection

Select fx68k for Rabbit Punch's 8 MHz 68000. TG68K.C passes the functional checks
below, but its NOP/DBRA loop takes 4 enables per iteration, versus the expected
68000 count of 14 clocks. Over 10272 measured intervals this is 41088 enables
versus 143808 clocks: interpreting each enable as an 8 MHz CPU clock makes the
whole test loop 5.14 ms rather than 17.98 ms. This confirms the warning in the
TG68K donor's provenance; changing a global enable divisor would not establish
correct timing for other instructions.

The unchanged fx68k donor test executes the same delay loop in 14 clocks per
iteration, 143822 clocks over 10273 intervals, with at most 2 clocks under AS
(no bus wait states in its default HALF=6, LAT=4 configuration). The donor's
full-count check prints PASS. This validates this particular timing test, not all
instructions or Rabbit Punch's eventual SDRAM/interrupt interface.

The Seta working source currently uses fx68k; its older ROADMAP/CPU notes still
describe TG68K in places. Current production code and the test results take
precedence over those stale descriptions. Keep both evaluation copies for now,
but add only the selected CPU to the eventual game source list.

## Executed checks

| Case | Outcome | What it establishes |
|---|---|---|
| t80_donor | PASS | Unchanged Psikyo boot test: opcode/immediate fetch, memory store, I/O store, HALT |
| tg68k_donor | Completed, final result reached | Unchanged 68020-wrapper regression; final BFEXTU store observed; not the selected board CPU mode |
| tg68k_68000 | PASS | Unchanged Seta native-kernel test: reset vectors ordered, arithmetic/store correct, no unknown bus after reset |
| tg68k_ccr | PASS | Unchanged Seta carry set/clear and indirect jump test in 68000 mode |
| tg68k_pace | Measurement completed; timing differs | 4 enables per NOP/DBRA iteration, not 14 |
| fx68k_pace | PASS | Same timing loop matches 68000 counts in the tested memory configuration |
| jtframe_draw | PASS | 12 cases: 16 pixels each, both X/Y flips, palette and ROM address checks, 0/3/11-cycle response delays |
| jtframe_buffer | PASS | Transparent pen 15, overwrite/keep-old priority, bank swap, read/erase and write-address flip |

CPU donor test files are unchanged and SHA256-pinned. The JTFRAME subset did not
include standalone drawer/buffer tests, so those two are local interface tests.
The drawer is the donor's pristine upstream reference, not its GX-modified version.
The object-buffer test uses SIMULATION initialization of the line selector and
clears both line banks through their public read/erase interface.

## Warnings and limits

TG68K logs contain inherited time-zero unknown-arithmetic warnings; native smoke
and CCR tests explicitly check no unknown bus signals after reset. The T80 source
still emits its inherited 9-versus-4-bit operand warning at T80.vhd:685. No CPU RTL
was edited to hide warnings. fx68k uses the documented ModelSim 7061 suppression
for its always_ff constructs. Its unchanged pacing run emits 97683 warnings,
including 8315/8360 unique/priority-case diagnostics from the decoder/ALU. These
remain unsuppressed and recorded; passing this loop does not settle every decoder
state or instruction. Review warning classes alongside functional traces before
claiming game-level CPU equivalence.

Per-case logs: debug/baselines/<case>/result.log. Selected donor commits, clean-file
checks and exact file hashes: reference/vendor_manifest.json. Reproduce all cases:

```
python scripts/run_baselines.py
python scripts/run_baselines.py --only tg68k_68000 fx68k_pace
```

Run ModelSim outside the sandbox as documented in TOOLCHAIN.md; the runner checks
the machine-wide JTAG guard before each case. Tests run in separate local simulation
directories and do not alter donors or sys/. No board RTL, hardware run, Quartus
fit or playable RBF is established by these results.
