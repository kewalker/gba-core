# A frozen bundled descriptor is held until a three-stage video event is
# acknowledged back. It must settle well before that event reaches stage 3.
if {$argc != 1} {error "Usage: check-playtime-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set endpoints [get_registers {*gba_playtime_host:playtime_host|received_bundle*}]
set endpoint_count [get_collection_size $endpoints]
# Synthesis drops constant upper bits of BCD digits. Audit every surviving
# destination, rather than assuming all seventy-one source bits are registers.
if {$endpoint_count < 40 || $endpoint_count > 71} {error "Missing playtime descriptor endpoints: $endpoint_count"}
set maximum 0.0
set corner 0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    set index 0
    foreach_in_collection endpoint $endpoints {
        set name [get_register_info -name $endpoint]
        set result [report_path -from {*gba_playtime_host:playtime_host|held_bundle*} -to [get_registers $name] -npaths 1 -summary -file "$prefix-corner-$corner-bit-$index.rpt"]
        if {[lindex $result 0] != 1 || [lindex $result 1] >= 20.0} {error "Playtime bundle exceeds 20 ns transfer bound: $result"}
        if {[lindex $result 1] > $maximum} {set maximum [lindex $result 1]}
        incr index
    }
    incr corner
}
if {$corner != 4} {error "Expected four operating corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"corners":%d,"endpoints":%d,"maximum_delay_ns":%.3f,"transfer_bound_ns":20.0}} $corner $endpoint_count $maximum]
close $receipt
puts "PASS: playtime descriptor $endpoint_count endpoints, $corner corners, maximum $maximum ns"
project_close
