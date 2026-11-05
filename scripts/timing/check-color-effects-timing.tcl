# Palette outputs cross to the video sampler after combinational effects.
# The native-pixel integration regression adds this entire 40 ns bound to
# palette data, including changing halfword lanes on the shortest dots.
if {$argc != 1} {error "Usage: check-color-effects-timing.tcl report-prefix"}
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
    set result [report_path -from {*palette_storage* *ppu_palette_rdata* *ppu_backdrop_color*} -to {*gba_apf_video_out:video_output|rgb*} -npaths 12 -summary -file "$prefix-corner-$corner.rpt"]
    if {[lindex $result 0] != 12 || [lindex $result 1] >= 40.0} {
        error "Color-effect path exceeds tested delay bound or paths missing: $result"
    }
    if {[lindex $result 1] > $maximum} {set maximum [lindex $result 1]}
    incr corner
}
if {$corner != 4} {error "Expected four operating conditions, got $corner"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"corners":%d,"maximum_delay_ns":%.3f,"tested_bound_ns":40.0}} $corner $maximum]
close $receipt
delete_timing_netlist
project_close
