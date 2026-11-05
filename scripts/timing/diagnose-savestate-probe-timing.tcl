# Read-only fitted-path diagnosis. Negative slack is evidence, not success.
if {$argc != 1} {error "Usage: diagnose-savestate-probe-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set corner 0
set minimum 1000.0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    report_timing -setup -npaths 20 -detail full_path -file "$prefix-setup-$corner.rpt"
    # Overall worst paths can hide a second failing clock behind twenty host
    # paths. Keep each destination clock visible without changing constraints.
    set clock_index 0
    foreach_in_collection clock [get_clocks *] {
        report_timing -setup -to_clock $clock -npaths 5 -detail full_path -file "$prefix-clock-$clock_index-$corner.rpt"
        incr clock_index
    }
    foreach_in_collection path [get_timing_paths -setup -npaths 1] {
        set slack [get_path_info -slack $path]
        if {$slack<$minimum} {set minimum $slack}
    }
    incr corner
}
if {$corner!=4} {error "Expected four operating conditions"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"MEASURED","corners":%d,"minimum_setup_ns":%.3f,"timing_qualified":false,"installed":false}} $corner $minimum]
close $receipt
delete_timing_netlist
project_close
puts "COMPLETE: fitted save-state prototype setup-path diagnosis; worst slack $minimum ns"
