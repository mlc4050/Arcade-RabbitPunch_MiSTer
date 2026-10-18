# Every failing setup endpoint on the main core clock, summary form, from the
# existing post-fit netlist. Run from the directory holding the database:
#   quartus_sta -t scripts/sta_all_fail.tcl <revision>
set rev ""
if {[llength $quartus(args)] > 0} { set rev [lindex $quartus(args) 0] }
if {$rev eq ""} {
    set qsfs [glob -nocomplain *.qsf]
    if {[llength $qsfs] != 1} { puts "give the revision: quartus_sta -t sta_all_fail.tcl <rev>"; exit 1 }
    set rev [file rootname [lindex $qsfs 0]]
}
project_open $rev
create_timing_netlist
set_operating_conditions 7_slow_1100mv_100c
read_sdc
update_timing_netlist
# Resolve the current VHDL game PLL uniquely; never emit an empty timing report.
set game_clock [list]
foreach_in_collection clock [get_clocks -nowarn {*|machine|pll|clock_generator*}] {
    set period [get_clock_info -period $clock]
    set edges [get_clock_info -waveform $clock]
    if {$period > 21.42 && $period < 21.44 && abs([lindex $edges 0]) < 0.03} {
        lappend game_clock $clock
    }
}
if {[llength $game_clock] != 1} { error "Expected one zero-phase game clock" }
set ck [lindex $game_clock 0]

report_timing -setup -npaths 600 -detail summary -to_clock $ck -file sta_all_fail.rpt
project_close -dont_export_assignments
