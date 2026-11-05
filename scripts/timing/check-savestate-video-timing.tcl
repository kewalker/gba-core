# The guest raster is parked before prepare crosses three video-clock stages.
# Audit the bundled restored position and the synchronizers that keep the guest
# held through cache reset, rebuild and the returning preparation grant.
if {$argc != 1} {error "Usage: check-savestate-video-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set base {*gba_state_video:state_video|}
foreach field {hold_sync prepare_sync render_sync invalidated_sync ready_sync parked_sync released_sync} {
    set bank [get_registers [format {%s%s[*]} $base $field]]
    if {[get_collection_size $bank] != 3} {error "Missing state video synchronizer: $field"}
}
set source [get_registers {*gba_memory_map:memory|vcount[*]}]
set dots [get_registers {*gba_memory_map:memory|display_dot[*]}]
set destination [get_registers [format {%starget[*]} $base]]
if {[get_collection_size $source] < 8 || [get_collection_size $dots] < 9 ||
    [get_collection_size $destination] != 17} {error "Missing restored video position descriptor"}
set maximum 0.0
set corner 0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    set bit 0
    foreach_in_collection endpoint $destination {
        set name [get_register_info -name $endpoint]
        set path [report_path -from $source -to [get_registers $name] -npaths 1 -summary -file "$prefix-line-$corner-$bit.rpt"]
        set dotpath [report_path -from $dots -to [get_registers $name] -npaths 1 -summary -file "$prefix-dot-$corner-$bit.rpt"]
        if {[lindex $path 0] == 0} {set path $dotpath}
        if {[lindex $path 0] != 1 || [lindex $path 1] >= 20.0} {
            error "State video position bit missing or exceeds 20 ns: $name $path"
        }
        if {[lindex $path 1] > $maximum} {set maximum [lindex $path 1]}
        incr bit
    }
    incr corner
}
if {$corner != 4} {error "Expected four state video timing corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"descriptor_bits":17,"synchronizer_banks":7,"stages":3,"maximum_delay_ns":%.3f,"settling_bound_ns":20.0,"installed":false,"timing_qualified":false}} $maximum]
close $receipt
delete_timing_netlist
project_close
puts "PASS: restored video position and preparation synchronizers, four corners, maximum $maximum ns"
