# Require real timed paths from retained-response ownership into CPU/bus state.
if {$argc ni {1 2} || ($argc==2 && [lindex $argv 1] ne "registered")} {
 error "Usage: check-retained-rom-timing.tcl report-prefix ?registered?"
}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set ownership [get_registers {*external_cartridge.cartridge*|cached_word_valid *external_cartridge.cartridge*|req_seen_cpu *external_cartridge.cartridge*|req_addr_hold[*]}]
set ready [get_registers {*external_cartridge.cartridge*|cpu_ready *external_cartridge.cartridge*|cpu_ready_reg}]
set sinks [get_registers {*arm7tdmi_core:cpu|* *gba_memory_map:memory|*}]
if {[get_collection_size $ownership]<25 || [get_collection_size $ready]==0 || [get_collection_size $sinks]<100} {error "Missing retained-response ownership, ready or CPU/bus endpoints"}
if {$argc==2} {
 # The registered interface must time both sides of the response register.
 set legs [list [list ownership-to-ready $ownership $ready] [list ready-to-bus $ready $sinks]]
} else {
 set sources [add_to_collection $ownership $ready]
 set legs [list [list direct $sources $sinks]]
}
set setup 1000.0
set hold 1000.0
set corners 0
foreach_in_collection op [get_available_operating_conditions] {
 set_operating_conditions $op
 update_timing_netlist
 foreach leg $legs {
  lassign $leg name sources destinations
  foreach kind {setup hold} {
   report_timing -$kind -from $sources -to $destinations -npaths 5 -detail full_path -file "$prefix-$name-$kind-$corners.rpt"
   set paths [get_timing_paths -$kind -from $sources -to $destinations -npaths 1]
   if {[get_collection_size $paths]==0} {error "Untimed retained-response $name $kind cone"}
   foreach_in_collection path $paths {
    set slack [get_path_info -slack $path]
    if {$kind eq "setup" && $slack<$setup} {set setup $slack}
    if {$kind eq "hold" && $slack<$hold} {set hold $slack}
   }
  }
 }
 incr corners
}
if {$corners!=4 || $setup<0 || $hold<0} {error "Retained-response timing failed: $corners corners, setup $setup, hold $hold"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"source_bits":%d,"minimum_setup_ns":%.3f,"minimum_hold_ns":%.3f,"constraints_changed":false,"installed":false}} [get_collection_size $ownership] $setup $hold]
close $receipt
delete_timing_netlist
project_close
puts "COMPLETE: retained-ROM ownership cone, four corners, setup $setup ns, hold $hold ns"
