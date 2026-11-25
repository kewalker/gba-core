# Measure the physical EEPROM pins against the serial reader's 20-clock guard.
if {$argc != 1} {error "Usage: check-gamepak-eeprom-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist

set captures [get_registers {*gba_gamepak_save_import:gamepak_import|serial_byte[0]* *gba_gamepak_save_import:gamepak_import|word[0]* *shared_cart_import.value[0]* *gba_gamepak_eeprom_import:gamepak_eeprom_import|*serial_word[0]* *gba_gamepak_eeprom_import:gamepak_eeprom_import|sample_word[0]*}]
set drivers [get_registers {*gba_gamepak_save_import:gamepak_import|* *gba_gamepak_eeprom_import:gamepak_eeprom_import|* *shared_cart_import.value[31]*}]
if {![get_collection_size $captures] || ![get_collection_size $drivers]} {error "Missing EEPROM pin endpoints"}
set pins {cart_tran_bank0[4] cart_tran_bank0[5] cart_tran_bank0[6] cart_tran_bank3[0] cart_tran_bank3[7] cart_tran_bank2_dir cart_tran_bank3_dir cart_tran_bank1_dir}
set corners 0
set maximum 0.0
proc measure {from to file} {
    global maximum
    if {[get_collection_size $from] == 0 || [get_collection_size $to] == 0} {error "Missing EEPROM endpoint: $file"}
    set path [report_path -from $from -to $to -npaths 1 -summary -file "$file.rpt"]
    if {[lindex $path 0] != 1 || [lindex $path 1] >= 65.0} {error "EEPROM pin path failed: $file $path"}
    if {[lindex $path 1] > $maximum} {set maximum [lindex $path 1]}
}
foreach_in_collection condition [get_available_operating_conditions] {
    set_operating_conditions $condition
    update_timing_netlist
    measure [get_ports {cart_tran_bank3[0]}] $captures "$prefix-input-$corners"
    set index 0
    foreach pin $pins {
        measure $drivers [get_ports $pin] "$prefix-output-$corners-$index"
        incr index
    }
    incr corners
}
if {$corners != 4} {error "Expected four EEPROM timing corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"maximum_fpga_path_ns":%.3f}} $maximum]
close $receipt
puts "PASS: Game Pak EEPROM I/O timing, maximum $maximum ns"
project_close
