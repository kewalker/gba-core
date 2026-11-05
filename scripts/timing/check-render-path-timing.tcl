# Run from src/fpga after fitting:
# quartus_sta -t ../../scripts/check-render-path-timing.tcl ../../build/render-path
# The raster release gate tests this coordinate path with 30 ns propagation.
if {$argc > 1} {error "Usage: check-render-path-timing.tcl ?report-prefix?"}
if {$argc == 1} {set prefix [lindex $argv 0]} else {set prefix ../../build/render-path}
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set xy {*gba_ppu:ppu|x* *gba_ppu:ppu|y*}
set corner 0
set maximum 0.0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    set result [report_path -from $xy -to {*scheduler|ram_addr*} -npaths 12 -summary -file "$prefix-corner-$corner.rpt"]
    if {[lindex $result 0] != 12 || [lindex $result 1] >= 30.0} {
        error "Coordinate path exceeds tested delay bound or report is incomplete: $result"
    }
    if {[lindex $result 1] > $maximum} {set maximum [lindex $result 1]}
    incr corner
}
if {$corner != 4} {error "Expected four operating conditions, got $corner"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"corners":%d,"maximum_delay_ns":%.3f,"tested_bound_ns":30.0}} $corner $maximum]
close $receipt
puts "PASS: $corner crossing corners, maximum $maximum ns below 30 ns"
project_close
