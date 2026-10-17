# Evaluation: actual PLL clock tree, registered logical test boundaries and
# direct SDRAM pins. Hypothetical external tester delays are not PCB timing.
create_clock -name reference_50 -period 20.000000 [get_ports i_reference_clk]
derive_pll_clocks
derive_clock_uncertainty
# Select the generated zero-phase system clock by fitted period/waveform;
# require exactly one match rather than silently falling back to a base clock.
set system_clocks [list]
foreach_in_collection clock [get_clocks *] {
    set period [get_clock_info -period $clock]
    set edges [get_clock_info -waveform $clock]
    if {$period > 21.42 && $period < 21.44 && abs([lindex $edges 0]) < 0.01} {
        lappend system_clocks [get_clock_info -name $clock]
    }
}
if {[llength $system_clocks] != 1} {
    error "Expected one fitted zero-phase 46.6667 MHz system clock: $system_clocks"
}
set clock_pattern [string map [list {[} {\[} {]} {\]}] [lindex $system_clocks 0]]
set system_clock [get_clocks $clock_pattern]
if {[get_collection_size $system_clock] != 1} {
    error "System-clock collection did not resolve uniquely"
}
set data_inputs [remove_from_collection [all_inputs] [get_ports i_reference_clk]]
set data_outputs [remove_from_collection [all_outputs] [get_ports o_sdram_clk]]
set_input_delay -clock $system_clock -min 10.714286 $data_inputs
set_input_delay -clock $system_clock -max 10.714286 $data_inputs
set_output_delay -clock $system_clock -min 0 $data_outputs
set_output_delay -clock $system_clock -max 0 $data_outputs
