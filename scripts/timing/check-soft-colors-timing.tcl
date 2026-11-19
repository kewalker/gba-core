# Check the fitted pixel-clock stages that receive the host menu setting.
if {$argc != 1} {error "Usage: check-soft-colors-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set stages [list]
for {set index 0} {$index < 3} {incr index} {
    set register [get_registers "*gba_soft_colors:soft_colors|enabled_sync\[$index\]"]
    if {[get_collection_size $register] != 1} {error "Missing Soft Colors synchronizer stage $index"}
    lappend stages $register
}
set frame [get_registers {*gba_soft_colors:soft_colors|enabled_frame}]
if {[get_collection_size $frame] != 1} {error "Missing frame-boundary setting latch"}
lappend stages $frame
set corners 0
set maximum 0.0
foreach_in_collection condition [get_available_operating_conditions] {
    set_operating_conditions $condition
    update_timing_netlist
    for {set index 0} {$index < 3} {incr index} {
        set from [lindex $stages $index]
        set to [lindex $stages [expr {$index+1}]]
        set path [report_path -from $from -to $to -npaths 1 -summary \
            -file "$prefix-corner-$corners-stage-$index.rpt"]
        if {[lindex $path 0] != 1 || [lindex $path 1] >= 20.0} {error "Missing or slow Soft Colors path: $path"}
        if {[lindex $path 1] > $maximum} {set maximum [lindex $path 1]}
    }
    incr corners
}
if {$corners != 4} {error "Expected four Soft Colors timing corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"synchronizer_stages":3,"maximum_stage_delay_ns":%.3f}} $maximum]
close $receipt
puts "PASS: Soft Colors synchronizer and frame latch, maximum $maximum ns"
project_close
