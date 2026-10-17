# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
# Read the fitted clock tree; the Python gate checks its frequency, phase and users.
load_package project
load_package sta
project_open clocked_machine_check
create_timing_netlist
read_sdc
update_timing_netlist
set output [open output_files/clock_tree.tsv w]
puts $output "name\tperiod_ns\trise_ns\tfall_ns\tpositive_registers\tnegative_registers"
foreach_in_collection clock [get_clocks *] {
    set edges [get_clock_info -waveform $clock]
    puts $output "[get_clock_info -name $clock]\t[get_clock_info -period $clock]\t[lindex $edges 0]\t[lindex $edges 1]\t[get_clock_info -nreg_pos $clock]\t[get_clock_info -nreg_neg $clock]"
}
close $output
delete_timing_netlist
project_close
