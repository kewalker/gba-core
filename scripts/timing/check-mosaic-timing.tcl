# Raster-clock mosaic lookups must settle within the same 30 ns address
# budget used by the held-dot rendering regression and raw raster audit.
if {$argc != 1} {error "Usage: check-mosaic-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set sources {*gba_mosaic_coordinate:mosaic_horizontal* *gba_mosaic_coordinate:mosaic_vertical*}
set maximum 0.0
set corner 0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    set result [report_path -from $sources -to {*scheduler|ram_addr*} -npaths 12 -summary -file "$prefix-corner-$corner.rpt"]
    if {[lindex $result 0] != 12 || [lindex $result 1] >= 30.0} {
        error "Mosaic address path exceeds held-dot bound or paths missing: $result"
    }
    if {[lindex $result 1] > $maximum} {set maximum [lindex $result 1]}
    incr corner
}
if {$corner != 4} {error "Expected four operating corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"corners":%d,"maximum_delay_ns":%.3f,"tested_bound_ns":30.0}} $corner $maximum]
close $receipt
puts "PASS: mosaic crossing paths, $corner corners, maximum $maximum ns"
project_close
