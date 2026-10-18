# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
# Standalone video-path check with synthetic inputs halfway between clock edges.
# Not final MiSTer video/pin timing. All paths remain single-cycle timed.
create_clock -name clk_sys -period 20.833333 [get_ports i_clk]
derive_clock_uncertainty
set_input_delay -clock clk_sys -min 10.416666 [remove_from_collection [all_inputs] [get_ports i_clk]]
set_input_delay -clock clk_sys -max 10.416666 [remove_from_collection [all_inputs] [get_ports i_clk]]
set_output_delay -clock clk_sys -min 0 [all_outputs]
set_output_delay -clock clk_sys -max 0 [all_outputs]
