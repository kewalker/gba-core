# Confirm both observed failure-source banks and the new schema-control state.
if {$argc != 1} {error "Usage: check-container-stage-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set words [get_registers {*gba_state_image_validator:container|held_word[*]}]
set indices [get_registers {*gba_state_image_validator:container|word_index[*]}]
set targets [get_registers {*gba_state_image_validator:container|state*}]
set stage [get_registers {*gba_state_image_validator:container|state.VALIDATE_WORD}]
if {[get_collection_size $words]!=32 || [get_collection_size $indices]==0 || [get_collection_size $targets]==0 || [get_collection_size $stage]!=1} {
 error "Missing schema-control stage or original failure-source registers"
}
set minimum_setup 1000.0
set minimum_hold 1000.0
set corners 0
foreach_in_collection op [get_available_operating_conditions] {
 set_operating_conditions $op
 update_timing_netlist
 foreach label {words indices} {
 set sources [set $label]
 foreach kind {setup hold} {
  set paths [get_timing_paths -$kind -from $sources -to $targets -npaths 1]
  if {[get_collection_size $paths]==0} {error "Untimed schema-control $kind path"}
  foreach_in_collection path $paths {
   set slack [get_path_info -slack $path]
   if {$kind eq "setup" && $slack<$minimum_setup} {set minimum_setup $slack}
   if {$kind eq "hold" && $slack<$minimum_hold} {set minimum_hold $slack}
   if {$slack<0} {error "Schema-control $kind violation: $slack ns"}
  }
  report_timing -$kind -from $sources -to $targets -npaths 5 -detail full_path -file "$prefix-$label-$kind-$corners.rpt"
 }
 }
 incr corners
}
if {$corners!=4} {error "Expected four schema-control timing corners"}
set out [open "$prefix.json" w]
puts $out [format {{"status":"PASS","corners":4,"held_word_bits":32,"word_index_bits":%d,"control_bits":%d,"minimum_setup_ns":%.3f,"minimum_hold_ns":%.3f,"constraints_changed":false}} [get_collection_size $indices] [get_collection_size $targets] $minimum_setup $minimum_hold]
close $out
delete_timing_netlist
project_close
puts "PASS: staged validator control clears setup and hold in four corners"
