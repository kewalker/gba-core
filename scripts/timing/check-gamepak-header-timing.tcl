# Measure fitted FPGA paths against the reader's 8-clock guard at 74.25 MHz.
if {$argc != 1} {error "Usage: check-gamepak-header-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set capture [get_registers {*gba_gamepak_rom_reader:cart_trial_reader|response_data[*]}]
if {[get_collection_size $capture] != 32} {error "Expected 32 Game Pak capture registers"}
set outputs [get_ports {cart_tran_bank0[4] cart_tran_bank0[5] cart_tran_bank1_dir cart_tran_bank2_dir cart_tran_bank3_dir}]
if {[get_collection_size $outputs] != 5} {error "Missing Game Pak select, read or direction pins"}
set maximum 0.0
set corners 0
foreach_in_collection condition [get_available_operating_conditions] {
    set_operating_conditions $condition
    update_timing_netlist
    foreach group {input output} {
        set index 0
        if {$group eq "input"} {set endpoints $capture} else {set endpoints $outputs}
        foreach_in_collection endpoint $endpoints {
            if {$group eq "input"} {
                set from [get_ports {cart_tran_bank2[*] cart_tran_bank3[*]}]
                set to [get_registers [get_register_info -name $endpoint]]
            } else {
                set from [get_registers {*}]
                set to [get_ports [get_port_info -name $endpoint]]
            }
            set path [report_path -from $from -to $to -npaths 1 -summary \
                -file "$prefix-$group-$corners-$index.rpt"]
            if {[lindex $path 0] != 1 || [lindex $path 1] >= 40.0} {error "Game Pak $group path failed: $path"}
            if {[lindex $path 1] > $maximum} {set maximum [lindex $path 1]}
            incr index
        }
    }
    incr corners
}
if {$corners != 4} {error "Expected four Game Pak timing corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"maximum_fpga_path_ns":%.3f,"bound_ns":40.0}} $maximum]
close $receipt
project_close
puts "PASS: Game Pak read and direction paths, maximum $maximum ns"
