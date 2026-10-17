# Prototype SDRAM pin timing

The first physical shell uses a 50 MHz reference, 46.6667 MHz system clock and
half-period-shifted external SDRAM clock. The controller uses CAS latency two.
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
