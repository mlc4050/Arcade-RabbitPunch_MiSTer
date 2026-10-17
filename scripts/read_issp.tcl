# Read the core's debug probes over JTAG (In-System Sources and Probes).
#
#   python scripts/read_issp.py RPUN
#
# SignalTap acquisition is GUI-only in Quartus Prime Lite 17.0 -- there are no
# *signaltap* Tcl commands -- so ISSP is what a headless workflow can drive.
#
# The probe bus layout is defined where the bus is BUILT (the issp instance in
# rtl/rabbitpunch_debug.vhd), not here. Keep the field tables in step with it: a
# silently shifted field decodes as plausible nonsense rather than as an error.
#
# Counters saturate at 32 bits and survive gameplay resets. Read twice for
# activity deltas; configuration reload is the only reset. No source actions.

# --- core-specific: edit for this core -------------------------------------
# One table per ISSP instance id, {name lo hi format}; format is dec, sdec
# (signed 16), hex or bit. Bit numbers index the probe bus as the RTL
# concatenates it. Add an entry to the `switch` further down for each table.
# This core exposes no source actions.
# RPUN layout version 1: registered read-only packet, no counter-clear source.
set fields_RPUN {
    {core_tag              0  31 hex}
    {build_id             32  63 hex}
    {frames               64  95 dec}
    {cpu_requests         96 127 dec}
    {cpu_writes          128 159 dec}
    {sound_requests      160 191 dec}
    {visible_pixels      192 223 dec}
    {last_write_address  224 247 hex}
    {last_write_bytes    248 249 hex}
    {last_write_data     256 271 hex}
    {last_sound_address  288 303 hex}
    {last_sound_data     304 311 hex}
    {last_sound_write    312 312 bit}
    {last_cpu_address    320 343 hex}
    {last_cpu_write      344 344 bit}
    {beam_x              352 360 dec}
    {beam_y              361 369 dec}
    {pll_locked          384 384 bit}
    {ready               385 385 bit}
    {loading             386 386 bit}
    {downloading         387 387 bit}
    {error               388 388 bit}
    {underflow           389 389 bit}
    {armed               390 390 bit}
    {paused              391 391 bit}
    {host_download       392 392 bit}
    {adpcm_busy          393 393 bit}
    {framework_reset     394 394 bit}
    {audio_samples       416 447 dec}
    {underflow_events    448 479 dec}
    {layout_version      480 510 dec}
}
# ---------------------------------------------------------------------------

proc bits_to_int {s lo hi} {
    # read_probe_data returns the bus MSB-first, so index from the right.
    set n [string length $s]
    set v 0
    for {set i $hi} {$i >= $lo} {incr i -1} {
        set c [string index $s [expr {$n - 1 - $i}]]
        set v [expr {$v * 2 + ($c eq "1" ? 1 : 0)}]
    }
    return $v
}

set do_clear [expr {[lsearch -exact $argv "clear"] >= 0}]
# `set N`   : write source byte N (decimal) and leave it
# `pulse N` : write N, then 0 -- for the edge-triggered controls
set set_val -1; set pulse_val -1
set i [lsearch -exact $argv "set"];   if {$i >= 0} { set set_val   [lindex $argv [expr {$i+1}]] }
set i [lsearch -exact $argv "pulse"]; if {$i >= 0} { set pulse_val [lindex $argv [expr {$i+1}]] }

set hw ""
foreach h [get_hardware_names] { if {$hw eq ""} { set hw $h } }
if {$hw eq ""} { puts "NO JTAG HARDWARE FOUND"; exit 1 }
puts "hardware: $hw"

set dev ""
foreach d [get_device_names -hardware_name $hw] {
    if {[string match "*5CSEBA6*" $d] || [string match "*5CSE*" $d] || $dev eq ""} {
        set dev $d
    }
}
if {$dev eq ""} { puts "NO DEVICE FOUND"; exit 1 }
puts "device:   $dev"

# Query instance info BEFORE opening a session: with a session already active
# this fails with "There is already an active In-System Sources and Probes
# session started."
set insts [get_insystem_source_probe_instance_info -hardware_name $hw -device_name $dev]
if {[llength $insts] == 0} {
    puts "NO ISSP INSTANCES -- is this an instrumented build?"
    exit 1
}
foreach i $insts { puts "instance: $i" }

# Take the first instance unless one is named on the command line (a single
# argument that is not a keyword or a keyword's value).
set want ""
set skip 0
foreach a $argv {
    if {$skip} { set skip 0; continue }
    if {$a eq "set" || $a eq "pulse"} { set skip 1; continue }
    if {$a ne "clear"} { set want $a }
}
set idx [lindex [lindex $insts 0] 0]
set inst_id [lindex [lindex $insts 0] 3]
if {$want ne ""} {
    set found 0
    foreach i $insts {
        if {[lindex $i 3] eq $want} { set idx [lindex $i 0]; set inst_id $want; set found 1 }
    }
}

if {$want ne "" && !$found} { puts "Requested instance '$want' was not found"; exit 1 }
if {$do_clear || $set_val >= 0 || $pulse_val >= 0} {
    puts "RPUN probes are read-only; source writes and counter clearing are unsupported"
    exit 1
}

# The field table belongs to the INSTANCE. An unrecognised id stops rather
# than guesses.
switch -- $inst_id {
    RPUN    { set fields $fields_RPUN }
    default {
        puts "instance id '$inst_id' has no field table -- add one before reading it"
        exit 1
    }
}
puts "decoding instance $inst_id"

start_insystem_source_probe -device_name $dev -hardware_name $hw
set raw [read_probe_data -instance_index $idx]
if {![regexp {^[01]+$} $raw] || [string length $raw] != 511 || [bits_to_int $raw 0 31] != 0x5250554E || [bits_to_int $raw 480 510] != 1} {
    end_insystem_source_probe
    puts "Probe identity, width or layout mismatch; refusing to decode"
    exit 1
}
puts "raw ([string length $raw] bits): $raw"
puts ""

foreach f $fields {
    lassign $f name lo hi fmt
    set v [bits_to_int $raw $lo $hi]
    switch $fmt {
        sdec { if {$v >= 32768} { set v [expr {$v - 65536}] }; puts [format "  %-16s %d" $name $v] }
        hex  { puts [format "  %-16s 0x%08X" $name $v] }
        bit  { puts [format "  %-16s %s"     $name [expr {$v ? "yes" : "no"}]] }
        default { puts [format "  %-16s %d"  $name $v] }
    }
}

end_insystem_source_probe
