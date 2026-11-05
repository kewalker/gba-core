# Native cache request metadata must arrive before its synchronized event.
# Run from src/fpga after fitting. Display reads intentionally retain raw X.
if {$argc != 1} {error "Usage: check-text-coordinate-timing.tcl report-prefix"}
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
    set bypass [report_path -from {*gba_ppu:ppu|x* *gba_ppu:ppu|y*} -to {*text_rows*|valid* *text_rows*|tags* *text_rows*|cached_sy* *text_rows*|map_addr* *text_rows*|slot* *text_rows*|blank_seen*} -npaths 1 -summary -file "$prefix-bypass-$corner.rpt"]
    if {[lindex $bypass 0] != 0} {error "Raw raster still changes background cache state: $bypass"}
    set result [report_path -from {*text_rows*coordinate_transfer*held_coordinates*} -to {*text_rows*coordinate_transfer*render_coordinates*} -npaths 17 -summary -file "$prefix-corner-$corner.rpt"]
    if {[lindex $result 0] != 17 || [lindex $result 1] >= 12.0} {
        error "Coordinate descriptor exceeds transfer bound or paths missing: $result"
    }
    if {[lindex $result 1] > $maximum} {set maximum [lindex $result 1]}
    incr corner
}
if {$corner != 4} {error "Expected four operating conditions, got $corner"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"corners":%d,"maximum_delay_ns":%.3f,"transfer_bound_ns":12.0}} $corner $maximum]
close $receipt
puts "PASS: $corner text descriptor corners, maximum $maximum ns below 12 ns"
project_close
