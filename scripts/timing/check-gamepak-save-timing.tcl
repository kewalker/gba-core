# Check the fitted physical Flash path across all corners. The bus controller
# allows twenty host clocks per setup, strobe, hold and release interval.
if {$argc < 1 || $argc > 2} {error "Usage: check-gamepak-save-timing.tcl report-prefix ?import?"}
set prefix [lindex $argv 0]
set import_only [expr {$argc == 2 && [lindex $argv 1] eq "import"}]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist

set address_pins [list]
set data_pins [list]
for {set bit 0} {$bit < 8} {incr bit} {
    lappend address_pins "cart_tran_bank2\[$bit\]" "cart_tran_bank3\[$bit\]"
    lappend data_pins "cart_tran_bank1\[$bit\]"
}
set control_pins {cart_tran_pin30 cart_tran_bank0[5] cart_tran_bank0[6] cart_tran_bank1_dir cart_tran_bank2_dir cart_tran_bank3_dir}
set outputs [concat $address_pins $data_pins $control_pins]
if {$import_only} {
    set outputs [concat $address_pins {cart_tran_pin30 cart_tran_bank0[5] cart_tran_bank2_dir cart_tran_bank3_dir}]
}
set maximum 0.0
proc check_pin {from to name} {
    global prefix maximum
    set path [report_path -from $from -to $to -npaths 1 -summary -file "$prefix-$name.rpt"]
    if {[lindex $path 0] != 1 || [lindex $path 1] >= 65.0} {
        post_message -type error "Game Pak Flash pin path $name failed: $path"
        qexit -error
    }
    if {[lindex $path 1] > $maximum} {set maximum [lindex $path 1]}
}

set pin_sources [get_registers {*gba_gamepak_flash:gamepak_flash|pin_address* *gba_gamepak_flash:gamepak_flash|pin_data* *gba_gamepak_flash:gamepak_flash|bus_active* *gba_gamepak_flash:gamepak_flash|read_strobe* *gba_gamepak_flash:gamepak_flash|write_strobe* *gba_gamepak_flash:gamepak_flash|writing*}]
set samples [get_registers {*gba_gamepak_flash:gamepak_flash|sample*}]
if {$import_only} {
    set pin_sources [get_registers {*gba_gamepak_save_import:gamepak_import|*}]
    set samples [get_registers {*gba_gamepak_save_import:gamepak_import|word[*]* *gba_gamepak_save_import:gamepak_import|*raw_wdata* *gba_gamepak_save_import:gamepak_import|local_shift.value[*]* *shared_cart_import.value[*]*}]
}
if {[get_collection_size $samples] < 8 || [get_collection_size $pin_sources] < 18} {
    post_message -type error "Missing Game Pak Flash pin registers"
    qexit -error
}
set corners 0
foreach_in_collection condition [get_available_operating_conditions] {
    set_operating_conditions $condition
    update_timing_netlist
    set index 0
    foreach name $outputs {
        if {[get_collection_size [get_ports $name]] != 1} {error "Missing Flash output $name"}
        check_pin $pin_sources [get_ports $name] "out-$corners-$index"
        incr index
    }
    set index 0
    foreach name $data_pins {
        check_pin [get_ports $name] $samples "in-$corners-$index"
        incr index
    }
    incr corners
}
if {$corners != 4} {error "Expected four Game Pak Flash timing corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"maximum_fpga_path_ns":%.3f}} $maximum]
close $receipt
puts "PASS: Game Pak Flash I/O timing, maximum $maximum ns"
project_close
