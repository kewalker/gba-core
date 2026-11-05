# Bound the cartridge's original held request and complete response mailboxes
# independently of asynchronous timing cuts. No settling stage is removed.
if {$argc!=1} {error "Usage: check-rom-bundle-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set corner 0
set config [open ap_core.qsf r]
set address_bits [expr {[regexp {VERILOG_MACRO "?GBK_SDRAM_ROM} [read $config]] ? 23 : 22}]
close $config
array set maxima {address 0.0 pair 0.0 response 0.0}
foreach_in_collection op [get_available_operating_conditions] {
 set_operating_conditions $op
 update_timing_netlist
 foreach bundle {address pair response} {
  if {$bundle eq "address"} {
   set source [get_registers {*external_cartridge.cartridge*|req_addr_hold[*]}]
   set destination [get_registers {*external_cartridge.cartridge*|req_addr_sync1[*]}]
   set expected $address_bits
   set bound 10.0
  } elseif {$bundle eq "pair"} {
   set source [get_registers {*external_cartridge.cartridge*|req_pair_hold}]
   set destination [get_registers {*external_cartridge.cartridge*|req_pair_sync1}]
   set expected 1
   set bound 10.0
  } else {
   set source [get_registers {*external_cartridge.cartridge*|resp_low_mem[*] *external_cartridge.cartridge*|resp_high_mem[*] *external_cartridge.cartridge*|resp_pair_low_mem[*] *external_cartridge.cartridge*|resp_pair_high_mem[*]}]
   set destination [get_registers {*external_cartridge.cartridge*|resp_low_sync1[*] *external_cartridge.cartridge*|resp_high_sync1[*] *external_cartridge.cartridge*|resp_pair_low_sync1[*] *external_cartridge.cartridge*|resp_pair_high_sync1[*]}]
   set expected 64
   set bound 20.0
  }
  if {[get_collection_size $destination]!=$expected} {error "Missing ROM $bundle endpoints: [get_collection_size $destination], expected $expected"}
  set index 0
  foreach_in_collection endpoint $destination {
   set name [get_register_info -name $endpoint]
   set path [report_path -from $source -to [get_registers $name] -npaths 1 -summary -file "$prefix-$bundle-$corner-$index.rpt"]
   if {[lindex $path 0]!=1 || [lindex $path 1]>=$bound} {error "ROM $bundle settling fails: $name $path"}
   if {[lindex $path 1]>$maxima($bundle)} {set maxima($bundle) [lindex $path 1]}
   incr index
  }
 }
 incr corner
}
if {$corner!=4} {error "Expected four ROM bundle timing corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"address_bits":%d,"pair_bits":1,"response_bits":64,"address_delay_ns":%.3f,"pair_delay_ns":%.3f,"response_delay_ns":%.3f}} $address_bits $maxima(address) $maxima(pair) $maxima(response)]
close $receipt
delete_timing_netlist
project_close
