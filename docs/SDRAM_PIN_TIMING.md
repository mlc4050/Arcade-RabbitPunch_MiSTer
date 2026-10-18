# Prototype SDRAM pin timing

The first physical shell uses a 50 MHz reference, 46.6667 MHz system clock and
quarter-period-shifted external SDRAM clock. The controller uses CAS latency two.
`GINT_SDRAM_READ_CAPTURE_ADJUST=1` selects the earlier runtime capture; the adapter
keeps that input zero during controller initialization. Same-phase logical tests
retain zero. Changing clock phase requires rechecking the read-window selection.

The root SDC creates an exported clock at SDRAM_CLK from the actual shifted PLL
output. It times every SDRAM data/address/control input/output path against that
clock. No SDRAM path is false-pathed. The core PLL outputs remain related; the
unchanged MiSTer framework's independent clock domains are grouped separately.

The provisional compatible-part budget uses CAS-2 clock-to-data <=6 ns, input
setup >=1.5 ns and hold >=0.8 ns, plus 1 ns for unmeasured module/PCB delays and
skew. This gives data input min/max 0/7 ns and output min/max -1.8/2.5 ns. The
numbers come from the [Alliance AS4C32M16SB datasheet](https://www.alliancememory.com/wp-content/uploads/pdf/dram/512M%20SDRAM_%20B%20die_AS4C32M16SB-7TCN-7TIN-6TIN_Rev%201.0%20June%202016.pdf).
The actual chips on the user's Mister Addons 128 MB module have not been identified;
these constraints are an explicit prototype assumption, not a claim about that
module's marking, trace lengths or verified timing window.

Implementation must pass every reported setup/hold corner and expose no
unconstrained SDRAM paths. Check placement of the controller's unconditional
DQ input register in I/O cells, fitted PLL period/phase and SDRAM I/O standards.
Hardware pattern tests, phase-margin checks and actual ROM/video bring-up remain
necessary; a command model cannot establish electrical timing. The prototype is
not a verified release until these hardware checks pass.

The first full-shell fit (660a45a) fails at the SDRAM input boundary: all 16
DQ inputs have setup violations, worst -4.338 ns, despite confirmed I/O input
register packing. The forwarded clock pin has about 5.2 ns more insertion delay
than the system capture clock. Internal game paths pass (+4.823 ns worst at the
100 C slow corner); this failure is the external clock relationship. The initial
10714 ps phase is rejected for this physical shell.

The 5357 ps (quarter-period) candidate passes the instrumented full-shell fit
90e053c. All 164 reported checks pass: minimum setup +0.367 ns, hold +0.078 ns,
recovery +4.368 ns, removal +0.393 ns and minimum pulse width +1.122 ns. The
fitted game clock is exactly 140/3 MHz by PLL ratios; only the forwarded SDRAM
pin uses the shifted output. The production-phase attract comparison matches
all 62208 MAME RGB pixels with no underflow and a 2484/3024-clock worst row.
See reference/full_shell_90e053c_timing_checks.json and
reference/scanout_pll_5357ps_rpunch_attract_checks.json. These results qualify the
prototype budgets, not the actual module's electrical margin. The low-level PLL
default remains 10714 ps for historical tests; the production clocked-machine
wrapper explicitly selects 5357 ps.

The inherited MiSTer SDC leaves four peripheral input pins and fifty output pins
untimed (HDMI video/audio, I2C, LEDs and multiplexed SD/user ports). They are
classified separately in scripts/framework_timing_scope.json, locked to unchanged
sys_top.v/sys_top.sdc hashes, exact allowed port names and bounded path counts.
The full-build gate rejects new untimed pins, any illegal/unconstrained clock,
any increased path count and every reported negative slack. The independent
block gates still require zero in all six coverage categories. No broad false
paths were added to make this pass; HDMI/peripheral electrical margins remain
outside the full-build timing claim. The raw counts remain in the output report.

The instrumented fit adds Intel-generated dedicated TDI/TMS/TDO pins. Its six
untimed inputs/51 outputs include those reserved pins; input/output path counts
are 59/115. The instrumented-only scope permits exactly the reserved pin names,
requires DEBUG_ISSP and a source-locked debug wrapper, and bounds the additional
paths to 45 input/five output paths. Release builds receive no such allowance.
TCK and internal debug clocks/checks remain timed. External JTAG cable delays
are unverified. The original runner rejected the new pins; the completed fit was
then checked retrospectively with the updated gate, without changing constraints
or recompiling. Twenty-eight acceptance/negative controls include reserved pins
in the wrong revision, changed debug source and extra untimed SDRAM/path cases.

The independent non-debug full fit 81844b1 also passes: all 144 reported checks,
minimum setup +0.368 ns and hold +0.076 ns. It has only the four inherited input
and fifty output pin coverage gaps, with no instrumentation allowance. Fitted
game frequency/SDRAM phase checks pass. See
reference/full_shell_81844b1_release_checks.json for exact resources and hashes.
The production-phase Japanese play1000 scene now matches all 62208 MAME RGB
pixels as well; the renderer has no scanout underflow in that comparison.
