# The CPU freezes a display-position descriptor before asserting the request.
# Three video-clock stages precede use; audit its complete comparison path.
if {$argc != 1} {error "Usage: check-stop-resync-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set source [get_registers {*gba_stop_resync:*alignment|frozen_position[*]}]
set destination [get_registers {*gba_stop_resync:*alignment|video_blank}]
if {[get_collection_size $source] != 17 || [get_collection_size $destination] != 1} {error "Missing STOP position descriptor"}
foreach name {request_sync ack_sync} {
    set stages [get_registers "*gba_stop_resync:*alignment|$name\[*\]"]
    if {[get_collection_size $stages] != 3} {error "Missing STOP synchronizer: $name"}
}
set maximum 0.0
set corner 0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    set index 0
    foreach_in_collection bit $source {
        set name [get_register_info -name $bit]
        set path [report_path -from [get_registers $name] -to $destination -npaths 1 -summary -file "$prefix-corner-$corner-bit-$index.rpt"]
        if {[lindex $path 0] != 1 || [lindex $path 1] >= 20.0} {error "STOP descriptor bit $name missing or exceeds 20 ns: $path"}
        if {[lindex $path 1] > $maximum} {set maximum [lindex $path 1]}
        incr index
    }
    incr corner
}
if {$corner != 4} {error "Expected four STOP timing corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"descriptor_bits":17,"synchronizer_stages":3,"maximum_delay_ns":%.3f,"settling_bound_ns":20.0}} $maximum]
close $receipt
puts "PASS: STOP wake descriptor, four corners, maximum $maximum ns"
project_close
