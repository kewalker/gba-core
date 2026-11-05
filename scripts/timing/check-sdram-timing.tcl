# Run from the fitted candidate's src/fpga directory.
if {$argc!=1} {error "Usage: check-sdram-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set inputs [get_registers {*sdram_memory.controller*dq_sample*}]
if {[get_collection_size $inputs]!=16} {error "Expected sixteen SDRAM input capture registers"}
set clock [get_clocks sdram_pin_clock]
set period [get_clock_info -period $clock]
set waveform [get_clock_info -waveform $clock]
if {abs($period-13.468)>0.001 || abs([lindex $waveform 0]-10.101)>0.002} {error "Unexpected SDRAM pin clock: $period $waveform"}
set output_names {dram_ras_n dram_cas_n dram_we_n dram_cke}
for {set bit 0} {$bit<16} {incr bit} {lappend output_names [format {dram_dq[%d]} $bit]}
for {set bit 0} {$bit<13} {incr bit} {lappend output_names [format {dram_a[%d]} $bit]}
for {set bit 0} {$bit<2} {incr bit} {lappend output_names [format {dram_ba[%d]} $bit];lappend output_names [format {dram_dqm[%d]} $bit]}
set map_file [open output_files/ap_core.map.rpt r]
set map_text [read $map_file]
close $map_file
set config [open ap_core.qsf r]
set configuration [read $config]
close $config
set full_rom [regexp {VERILOG_MACRO "?GBK_SDRAM_ROM} $configuration]
set has_ewram [regexp {VERILOG_MACRO "?GBK_SDRAM_EWRAM} $configuration]
set constant_outputs {dram_cke VCC}
set constant_json {"dram_cke"}
set timed_outputs 36
if {!$full_rom} {
 lappend constant_outputs {dram_a[11]} GND
 append constant_json {,"dram_a[11]"}
 set timed_outputs 35
}
# A32MiB ROM actively uses row11. Only proven constant outputs are exempt.
foreach {port value} $constant_outputs {
 if {[string first "Pin \"$port\" is stuck at $value" $map_text]<0 ||
     [get_collection_size [get_fanins [get_ports $port]]]!=0} {error "Unproven constant SDRAM output: $port"}
}
set minimum_setup 1000.0
set minimum_hold 1000.0
set request_max 0.0
set response_max 0.0
set corner 0
foreach_in_collection op [get_available_operating_conditions] {
 set_operating_conditions $op
 update_timing_netlist
 foreach kind {setup hold} {
  set index 0
  foreach_in_collection endpoint $inputs {
   set name [get_register_info -name $endpoint]
   if {![regexp {\[([0-9]+)\]$} $name whole bit]} {error "Unrecognized SDRAM bit: $name"}
   set from [get_ports [format {dram_dq[%d]} $bit]]
   set to [get_registers $name]
   report_timing -$kind -from $from -to $to -npaths 1 -detail full_path -file "$prefix-input-$kind-$corner-$bit.rpt"
   set found 0
   foreach_in_collection path [get_timing_paths -$kind -from $from -to $to -npaths 1] {
    set found 1
    set slack [get_path_info -slack $path]
    if {$slack<0} {error "SDRAM input $kind fails: $name $slack ns"}
    set variable minimum_$kind
    if {$slack<[set $variable]} {set $variable $slack}
   }
   if {!$found} {error "Missing SDRAM input $kind: $name"}
   incr index
  }
  if {$index!=16} {error "Incomplete SDRAM input endpoints"}
  set index 0
  foreach name $output_names {
   if {[dict exists $constant_outputs $name]} {continue}
   set to [get_ports $name]
   report_timing -$kind -to $to -npaths 1 -detail full_path -file "$prefix-output-$kind-$corner-$index.rpt"
   set found 0
   foreach_in_collection path [get_timing_paths -$kind -to $to -npaths 1] {
    set found 1
    set slack [get_path_info -slack $path]
    if {$slack<0} {error "SDRAM output $kind fails: $name $slack ns"}
    set variable minimum_$kind
    if {$slack<[set $variable]} {set $variable $slack}
   }
   if {!$found} {error "Missing SDRAM output $kind: $name"}
   incr index
  }
 }
 # The asynchronous cuts do not excuse unbounded bundled-data propagation.
 foreach bundle {request response} {
  if {!$has_ewram} {continue}
  if {$bundle eq "request"} {
   set from [get_registers {*sdram_ewram_bridge.bridge*|descriptor[*]}]
   set to [get_registers {*sdram_ewram_bridge.bridge*|descriptor_sync1*}]
   set bound 10.0
  } else {
   set from [get_registers {*sdram_ewram_bridge.bridge*|held_response*}]
   set to [get_registers {*sdram_ewram_bridge.bridge*|data_sync1*}]
   set bound 20.0
  }
  set count [get_collection_size $to]
  if {$count<32 || ($bundle eq "response" && $count!=64)} {error "Missing SDRAM $bundle CDC bits: $count"}
  set index 0
  foreach_in_collection endpoint $to {
   set name [get_register_info -name $endpoint]
   set result [report_path -from $from -to [get_registers $name] -npaths 1 -summary -file "$prefix-$bundle-$corner-$index.rpt"]
   if {[lindex $result 0]!=1 || [lindex $result 1]>=$bound} {error "SDRAM $bundle CDC settling fails: $name $result"}
   set variable ${bundle}_max
   if {[lindex $result 1]>[set $variable]} {set $variable [lindex $result 1]}
   incr index
  }
 }
 incr corner
}
if {$corner!=4} {error "Expected four SDRAM timing corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"input_bits":16,"output_ports":%d,"timed_output_ports":%d,"constant_outputs":[%s],"period_ns":%.3f,"phase_ns":%.3f,"minimum_setup_slack_ns":%.3f,"minimum_hold_slack_ns":%.3f,"request_bundle_delay_ns":%.3f,"response_bundle_delay_ns":%.3f}} [llength $output_names] $timed_outputs $constant_json $period [lindex $waveform 0] $minimum_setup $minimum_hold $request_max $response_max]
close $receipt
delete_timing_netlist
project_close
