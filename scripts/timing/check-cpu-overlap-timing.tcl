# Measure CPU-source -> saved operand setup, including the failed overlap cone.
# No constraints, clock changes or exceptions are introduced.
if {$argc != 2} {error "Usage: check-cpu-overlap-timing.tcl report-prefix require-pass"}
set prefix [lindex $argv 0]
set require_pass [lindex $argv 1]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set sources [get_registers {*arm7tdmi_core:cpu|*}]
set targets [get_registers {*arm7tdmi_core:cpu|fetched_rm_value[*]}]
if {[get_collection_size $sources] < 100 || [get_collection_size $targets] != 32} {
    error "Missing CPU registers or 32 saved operand bits"
}
set minimum 1000.0
set corners 0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    report_timing -setup -from $sources -to $targets -npaths 5 -detail full_path -file "$prefix-$corners.rpt"
    set paths [get_timing_paths -setup -from $sources -to $targets -npaths 1]
    if {[get_collection_size $paths] == 0} {error "Untimed CPU saved-operand cone"}
    foreach_in_collection path $paths {
        set slack [get_path_info -slack $path]
        if {$slack < $minimum} {set minimum $slack}
    }
    incr corners
}
if {$corners != 4} {error "Expected four operating corners"}
set status [expr {$minimum >= 0 ? "PASS" : "FAILED"}]
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"%s","corners":%d,"operand_bits":32,"minimum_setup_ns":%.3f,"original_minimum_setup_ns":-0.385,"constraints_changed":false,"installed":false}} $status $corners $minimum]
close $receipt
delete_timing_netlist
project_close
if {$require_pass && $minimum < 0} {error "CPU saved operand setup still violates timing: $minimum ns"}
puts "COMPLETE: CPU saved-operand cone, four corners, minimum setup $minimum ns"
