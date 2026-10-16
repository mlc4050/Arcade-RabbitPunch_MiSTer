# Block evaluation only, not the final board PLL or pixel-clock choice.
create_clock -name clk_sys -period 20.833333 [get_ports i_clk]
derive_clock_uncertainty
set_input_delay -clock clk_sys 0 [remove_from_collection [all_inputs] [get_ports i_clk]]
set_output_delay -clock clk_sys 0 [all_outputs]
