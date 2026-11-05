# The row descriptor is sampled two render periods after the earliest event
# synchronizer capture. Bound its data path below 12 ns (< 2 * 7.512 ns).
# Run from src/fpga after a successful full fit.
if {$argc != 1} {error "Usage: check-scanline-crossing-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set corner 0
set maximum 0.0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    set bypass [report_path -from {*gba_ppu:ppu|y*} -to {*object_rows*bank_valid* *object_rows*target_y* *object_rows*seen_y*} -npaths 1 -summary -file "$prefix-bypass-$corner.rpt"]
    if {[lindex $bypass 0] != 0} {error "Unsynchronized raster-to-bank control path remains: $bypass"}
    set result [report_path -from {*object_rows*line_crossing*held_y*} -to {*object_rows*line_crossing*received_y*} -npaths 8 -summary -file "$prefix-corner-$corner.rpt"]
    if {[lindex $result 0] != 8 || [lindex $result 1] >= 12.0} {
        error "Scanline descriptor exceeds transfer bound or paths missing: $result"
    }
    if {[lindex $result 1] > $maximum} {set maximum [lindex $result 1]}
    incr corner
}
if {$corner != 4} {error "Expected four operating conditions, got $corner"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"corners":%d,"maximum_delay_ns":%.3f,"transfer_bound_ns":12.0}} $corner $maximum]
close $receipt
puts "PASS: $corner scanline descriptor corners, maximum $maximum ns below 12 ns"
project_close
