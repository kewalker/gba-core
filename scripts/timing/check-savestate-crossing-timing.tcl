# Physical settling audit for the shared state command/reply mailbox. Clock
# groups cut these paths from ordinary setup analysis; simulation is insufficient.
# This audit adds no timing exceptions and does not qualify the production top.
if {$argc != 1} {error "Usage: check-savestate-crossing-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set base {*gba_state_async_port:crossing|}
foreach field {request_sync ack_sync} {
    set pattern [format {%s%s[*]} $base $field]
    if {[get_collection_size [get_registers $pattern]] != 3} {
        error "Missing three-stage state handshake: $field"
    }
}
set maximum_request 0.0
set maximum_response 0.0
set corner 0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    foreach {label source_field destination_field minimum bound} {
        request held_request request_data1 32 20.0
        response held_response response_data1 32 10.0
    } {
        set source [get_registers [format {%s%s[*]} $base $source_field]]
        set destination [get_registers [format {%s%s[*]} $base $destination_field]]
        set count [get_collection_size $destination]
        # Constant address bits may disappear. Require the data bank and audit
        # every remaining physical endpoint, including any duplicated bits.
        if {[get_collection_size $source] < $minimum || $count < $minimum} {
            error "Missing state $label payload bank"
        }
        set bit 0
        foreach_in_collection endpoint $destination {
            set name [get_register_info -name $endpoint]
            set path [report_path -from $source -to [get_registers $name] -npaths 1 -summary -file "$prefix-$label-$corner-$bit.rpt"]
            if {[lindex $path 0] != 1 || [lindex $path 1] >= $bound} {
                error "State $label settling fails: $name $path (bound $bound ns)"
            }
            set variable maximum_$label
            if {[lindex $path 1] > [set $variable]} {set $variable [lindex $path 1]}
            incr bit
        }
        set ${label}_endpoints $count
    }
    incr corner
}
if {$corner != 4} {error "Expected four state mailbox corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","scope":"Shared state mailbox settling only; production integration excluded","corners":4,"synchronizer_stages":3,"request_endpoints":%d,"response_endpoints":%d,"maximum_request_ns":%.3f,"maximum_response_ns":%.3f,"request_bound_ns":20.0,"response_bound_ns":10.0,"timing_qualified":false,"installed":false}} $request_endpoints $response_endpoints $maximum_request $maximum_response]
close $receipt
delete_timing_netlist
project_close
puts "PASS: state mailbox four-corner settling; request $maximum_request ns, response $maximum_response ns"
