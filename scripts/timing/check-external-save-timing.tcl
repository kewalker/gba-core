# Audit real routed datapaths, including bundled CDC paths cut by clock groups.
if {$argc!=1} {error "Usage: check-external-save-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set base {*external_save.flash*storage*}
set pins [get_registers "${base}pins*"]
set read_regs [get_registers "${base}pins*|dq_sample\[*\]"]
if {[get_collection_size $read_regs]!=16} {error "Expected 16 SRAM input endpoints"}
set corner 0
array set maxima {input 0.0 output 0.0 request 0.0 response 0.0}
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    set i 0
    foreach_in_collection endpoint $read_regs {
        set name [get_register_info -name $endpoint]
        set path [report_path -from [get_ports {sram_dq[*]}] -to [get_registers $name] -npaths 1 -summary -file "$prefix-input-$corner-$i.rpt"]
        if {[lindex $path 0]!=1 || [lindex $path 1]>8.0} {error "SRAM input budget fails: $name $path"}
        if {[lindex $path 1]>$maxima(input)} {set maxima(input) [lindex $path 1]}
        incr i
    }
    set output_count 0
    foreach_in_collection endpoint [get_ports {sram_a[*] sram_dq[*] sram_oe_n sram_we_n sram_ub_n sram_lb_n}] {
        set name [get_port_info -name $endpoint]
        # Only the lower 128 KiB is used; address bit 16 is constant zero.
        if {$name eq {sram_a[16]}} {continue}
        set path [report_path -from $pins -to [get_ports $name] -npaths 1 -summary -file "$prefix-output-$corner-$output_count.rpt"]
        if {[lindex $path 0]!=1 || [lindex $path 1]>8.0} {error "SRAM output budget fails: $name $path"}
        if {[lindex $path 1]>$maxima(output)} {set maxima(output) [lindex $path 1]}
        incr output_count
    }
    if {$output_count!=36} {error "Missing SRAM output paths: $output_count"}
    foreach bundle {address data mask write response} {
        if {$bundle eq "response"} {
            set source [get_registers "${base}|response_data\[*\]"]
            set dest [get_registers "${base}|response_data_1\[*\]"]
            set expected 32
            set bound 20.0
            set kind response
        } else {
            set field [dict get {address addr data data mask mask write write} $bundle]
            set source [get_registers "${base}|held_${field}*"]
            set dest [get_registers "${base}|${field}_1*"]
            set expected [dict get {address 15 data 8 mask 4 write 1} $bundle]
            set bound 10.0
            set kind request
        }
        set count [get_collection_size $dest]
        # Guest write bytes are replicated: synthesis can merge 32 data bits
        # down to eight. Audit every remaining endpoint, whichever are kept.
        if {$count<$expected || ($bundle ne "data" && $count!=$expected)} {error "Missing save $bundle endpoints: $count"}
        set i 0
        foreach_in_collection endpoint $dest {
            set name [get_register_info -name $endpoint]
            set path [report_path -from $source -to [get_registers $name] -npaths 1 -summary -file "$prefix-$bundle-$corner-$i.rpt"]
            if {[lindex $path 0]!=1 || [lindex $path 1]>=$bound} {error "Save mailbox budget fails: $name $path"}
            if {[lindex $path 1]>$maxima($kind)} {set maxima($kind) [lindex $path 1]}
            incr i
        }
    }
    incr corner
}
if {$corner!=4} {error "Expected four SRAM timing corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"input_endpoints":16,"output_endpoints":36,"input_ns":%.3f,"output_ns":%.3f,"request_ns":%.3f,"response_ns":%.3f,"installed":false,"hardware_accepted":false}} $maxima(input) $maxima(output) $maxima(request) $maxima(response)]
close $receipt
delete_timing_netlist
project_close
