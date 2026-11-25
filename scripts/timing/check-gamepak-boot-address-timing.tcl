# The lowest halfword address bit is tied low for aligned word reads.
# The remaining address pins must settle within the reader's setup guard.
if {$argc < 1 || $argc > 2} {error "Usage: check-gamepak-boot-address-timing.tcl report-prefix ?changing-pins?"}
set prefix [lindex $argv 0]
set changing_pins 21
if {$argc == 2} {set changing_pins [lindex $argv 1]}
if {$changing_pins ni {21 22 23}} {error "Expected 21, 22, or 23 changing address pins"}
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist

set pins [list]
foreach {bank first last} [list 1 0 [expr {$changing_pins - 16}] 2 0 7 3 1 7] {
    for {set bit $first} {$bit <= $last} {incr bit} {
        lappend pins "cart_tran_bank${bank}\[$bit\]"
    }
}
set sources [get_registers {*gba_gamepak_rom_loader:cart_boot_loader|word_index[*]* *gba_gamepak_rom_reader:cart_trial_reader|word_address[*]* *gba_gamepak_rom_size_probe:size_probe|boundary[*]*}]
if {[get_collection_size $sources] < $changing_pins} {error "Missing Game Pak address registers"}
set corners 0
set maximum 0.0
foreach_in_collection condition [get_available_operating_conditions] {
    set_operating_conditions $condition
    update_timing_netlist
    set index 0
    foreach name $pins {
        set pin [get_ports $name]
        if {[get_collection_size $pin] != 1} {error "Missing Game Pak address pin $name"}
        set path [report_path -from $sources -to $pin -npaths 1 -summary \
            -file "$prefix-corner-$corners-pin-$index.rpt"]
        if {[lindex $path 0] != 1 || [lindex $path 1] >= 40.0} {error "Game Pak address path $name failed: $path"}
        if {[lindex $path 1] > $maximum} {set maximum [lindex $path 1]}
        incr index
    }
    incr corners
}
if {$corners != 4} {error "Expected four Game Pak timing corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"address_pins":%d,"maximum_fpga_path_ns":%.3f}} [llength $pins] $maximum]
close $receipt
puts "PASS: Game Pak boot address timing, maximum $maximum ns"
project_close
