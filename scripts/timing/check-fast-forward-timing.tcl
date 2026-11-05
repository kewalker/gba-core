# Audit request and speed-bit host -> execution synchronizers.
if {$argc != 1} {error "Usage: check-fast-forward-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set stages [get_registers {*gba_fast_forward:*fast_forward_control|request_sync[*]}]
if {[get_collection_size $stages] != 3} {error "Missing fast-forward request synchronizer stages"}
foreach chain {speed_low_sync speed_high_sync mute_sync} {
    if {[get_collection_size [get_registers "*gba_fast_forward:*fast_forward_control|$chain\[*\]"]] != 3} {
        error "Missing fast-forward speed synchronizer stages: $chain"
    }
}
foreach {pattern expected} {
    {*gba_obj_row_cache:*|matrix_capture[*]} 4
    {*gba_obj_row_cache:*|bank_capture[*]} 2
    {*gba_state_machine_validator:*|gba_state_image_validator:*|held_word[*]} 32
} {
    set count [get_collection_size [get_registers $pattern]]
    if {$count != $expected} {error "Missing fast-forward timing repair registers: $pattern count=$count expected=$expected"}
}
set tag_bits [get_collection_size [get_registers {*gba_obj_row_cache:*|response_tag[*]}]]
# The OBJ address has three fixed region bits; constant register removal may
# leave only the thirteen variable tag bits. The measured critical bits must
# always be private registers, irrespective of constant folding.
if {$tag_bits < 13 || $tag_bits > 16} {error "Missing private OBJ tag registers: $tag_bits"}
foreach bit {4 7} {
    if {[get_collection_size [get_registers "*gba_obj_row_cache:*|response_tag\[$bit\]"]] != 1} {
        error "Missing critical private OBJ tag bit $bit"
    }
}
set maximum 0.0
set corner 0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    foreach chain {request_sync speed_low_sync speed_high_sync mute_sync} {
    for {set index 0} {$index < 2} {incr index} {
        set next [expr {$index+1}]
        set source [get_registers "*gba_fast_forward:*fast_forward_control|$chain\[$index\]"]
        set target [get_registers "*gba_fast_forward:*fast_forward_control|$chain\[$next\]"]
        set path [report_path -from $source -to $target -npaths 1 -summary -file "$prefix-corner-$corner-$chain-stage-$index.rpt"]
        if {[lindex $path 0] != 1 || [lindex $path 1] >= 20.0} {error "Missing/slow fast-forward synchronizer path: $path"}
        if {[lindex $path 1] > $maximum} {set maximum [lindex $path 1]}
    }
    }
    incr corner
}
if {$corner != 4} {error "Expected four fast-forward timing corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"synchronizer_stages":3,"synchronizer_chains":4,"mute_synchronizer_bits":3,"speed_synchronizer_bits":6,"matrix_capture_bits":4,"bank_capture_bits":2,"private_tag_bits":%d,"reused_validator_word_bits":32,"maximum_stage_delay_ns":%.3f,"stage_bound_ns":20.0}} $tag_bits $maximum]
close $receipt
puts "PASS: fast-forward request synchronizer, four corners, maximum $maximum ns"
project_close
