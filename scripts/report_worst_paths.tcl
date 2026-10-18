# Dump the worst setup-timing paths for the clk_sys domain from the
# already-compiled database, without a recompile. Run from the directory that
# holds the database (the repo root for build.sh, build/ for build_staged.py):
#   quartus_sta -t scripts/report_worst_paths.tcl <revision>
# The revision is the trailing argument; it defaults to the one below.
set rev ""
if {[llength $quartus(args)] > 0} { set rev [lindex $quartus(args) 0] }
if {$rev eq ""} {
    set qsfs [glob -nocomplain *.qsf]
    if {[llength $qsfs] != 1} { puts "give the revision: quartus_sta -t report_worst_paths.tcl <rev>"; exit 1 }
    set rev [file rootname [lindex $qsfs 0]]
}
project_open $rev
create_timing_netlist
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
set clk [lindex $game_clock 0]


report_timing -setup -npaths 15 -detail full_path -to_clock $clk \
    -panel_name "Worst 15 setup paths to game clock (including SDRAM inputs)" -file "output_files/worst_paths_$rev.rpt"

delete_timing_netlist
# -dont_export_assignments: project_close otherwise RE-SAVES the .qsf,
# reordering it and reverting hand edits (a VERILOG_MACRO has been lost that way).
project_close -dont_export_assignments
