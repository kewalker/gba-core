# Mailbox and acknowledgement launch together in the execution domain.
# Two acknowledgement synchronizers precede frame capture at 12.288 MHz.
# Keep all nonconstant stereo data paths below one audio period (80 ns),
# leaving at least another period before the earliest acknowledged capture.
if {$argc != 1} {error "Usage: check-audio-crossing-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set source {*gba_audio_output:audio_output|mailbox*}
set destination {*gba_audio_output:audio_output|frame*}
set expected [get_collection_size [get_registers $destination]]
if {$expected == 0} {error "Missing stereo frame registers"}
set corner 0
set maximum 0.0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    set result [report_path -from $source -to $destination -npaths 64 -summary -file "$prefix-corner-$corner.rpt"]
    if {[lindex $result 0] != $expected || [lindex $result 1] >= 80.0} {
        error "Audio mailbox data path missing or beyond settling bound: $result, expected $expected"
    }
    if {[lindex $result 1] > $maximum} {set maximum [lindex $result 1]}
    incr corner
}
if {$corner != 4} {error "Expected four operating conditions, got $corner"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"corners":%d,"data_registers":%d,"maximum_delay_ns":%.3f,"settling_bound_ns":80.0}} $corner $expected $maximum]
close $receipt
delete_timing_netlist
project_close
