# Core clocks are derived from the FPGA 50 MHz reference by rabbitpunch_pll.
derive_pll_clocks

# Define the exported SDRAM clock at the FPGA package pin, preserving its
# actual PLL phase and output-clock insertion delay.
set game_clocks [get_clocks -nowarn {*|machine|pll|clock_generator*}]
set shifted_sources [list]
foreach_in_collection clock $game_clocks {
    set period [get_clock_info -period $clock]
    set edges [get_clock_info -waveform $clock]
    if {$period > 21.42 && $period < 21.44 && abs([lindex $edges 0] - 10.714286) < 0.03} {
        lappend shifted_sources [get_clock_info -targets $clock]
    }
}
if {[llength $shifted_sources] != 1} {
    error "Expected one half-period SDRAM PLL output; clock plan is unverified"
}
create_generated_clock -name sdram_pin -source [lindex $shifted_sources 0] \
    -divide_by 1 [get_ports SDRAM_CLK]

# CAS-2 prototype budget: tAC <=6 ns, tIS >=1.5 ns, tIH >=0.8 ns;
# allow 1 ns for unmeasured module/PCB delays and skew. Input minimum zero is
# conservative. This compatible-part budget must be confirmed on the actual
# module; see docs/SDRAM_PIN_TIMING.md. No SDRAM data path is false-pathed.
set_input_delay -clock sdram_pin -min 0.0 [get_ports {SDRAM_DQ[*]}]
set_input_delay -clock sdram_pin -max 7.0 [get_ports {SDRAM_DQ[*]}]
set sdram_outputs [get_ports {SDRAM_DQ[*] SDRAM_A[*] SDRAM_BA[*] SDRAM_DQML SDRAM_DQMH SDRAM_nCS SDRAM_nCAS SDRAM_nRAS SDRAM_nWE SDRAM_CKE}]
set_output_delay -clock sdram_pin -min -1.8 $sdram_outputs
set_output_delay -clock sdram_pin -max 2.5 $sdram_outputs

# The new VHDL PLL hierarchy differs from sys_top.sdc's template pll_inst path.
# Keep its two related outputs plus the exported clock in one group; the
# unchanged MiSTer framework crosses to its independent clocks through its CDCs.
set game_clocks [add_to_collection $game_clocks [get_clocks sdram_pin]]
set other_clocks [remove_from_collection [all_clocks] $game_clocks]
set_clock_groups -asynchronous -group $game_clocks -group $other_clocks

# Include the newly exported SDRAM clock in automatic uncertainty derivation.
derive_clock_uncertainty
