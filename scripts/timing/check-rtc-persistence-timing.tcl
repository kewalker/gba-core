# Held command/reply banks cross only with a three-stage toggle handshake.
# Audit every surviving source bit, including the separate APF epoch bank.
if {$argc != 1} {error "Usage: check-rtc-persistence-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set command [get_registers {*gba_rtc_persistence_link:*link|payload[*] *gba_rtc_persistence_link:*link|operation[*]}]
set reply [get_registers {*gba_rtc_persistence_engine:*engine|reply[*]}]
set epoch [get_registers {*core_bridge_cmd:icb|rtc_epoch_seconds[*]}]
set guest [get_registers {*gba_rtc_persistence_engine:*engine|* *gba_cartridge_rtc:rtc|*}]
# Epoch also loads the host-domain held payload. Quartus may duplicate a bit
# solely for this consumer; that copy has no direct path to the guest engine.
# Bound both consumers, and separately require all32 logical bits to reach
# the guest bank through at least one physical copy at every corner.
set epoch_destinations [get_registers {*gba_rtc_persistence_engine:*engine|* *gba_cartridge_rtc:rtc|* *gba_rtc_persistence_link:*link|payload[*]}]
set host [get_keepers {*gba_playtime_record:stats|*export_words*}]
if {[get_collection_size $host] < 1} {error "Missing block-memory sidecar capture endpoints"}
foreach {pattern expected} {
    {*gba_rtc_persistence_engine:*engine|request_sync[*]} 3
    {*gba_rtc_persistence_link:*link|ack_sync[*]} 3
} {
    if {[get_collection_size [get_registers $pattern]] != $expected} {error "Missing persistence synchronizer: $pattern"}
}
set maximum 0.0
set corner 0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    set epoch_covered [dict create]
    foreach {label source destination minimum bound} [list command $command $guest 70 30.0 reply $reply $host 70 30.0 epoch $epoch $epoch_destinations 32 20.0] {
        set count [get_collection_size $source]
        if {$count < $minimum} {error "Missing $label persistence bank: $count"}
        set bit 0
        foreach_in_collection from $source {
            set name [get_register_info -name $from]
            set path [report_path -from [get_registers $name] -to $destination -npaths 1 -summary -file "$prefix-$label-corner-$corner-bit-$bit.rpt"]
            if {[lindex $path 0] != 1 || [lindex $path 1] >= $bound} {error "Persistence $label settling fails: $name $path"}
            if {[lindex $path 1] > $maximum} {set maximum [lindex $path 1]}
            if {$label eq "epoch"} {
                if {![regexp {rtc_epoch_seconds\[([0-9]+)\](~DUPLICATE.*)?$} $name unused logical]} {error "Unrecognized epoch register: $name"}
                set direct [report_path -from [get_registers $name] -to $guest -npaths 1 -summary -file "$prefix-epoch-guest-corner-$corner-bit-$bit.rpt"]
                if {[lindex $direct 0] == 1} {dict set epoch_covered $logical 1}
            }
            incr bit
        }
    }
    for {set bit 0} {$bit < 32} {incr bit} {
        if {![dict exists $epoch_covered $bit]} {error "Missing direct guest epoch bit $bit at corner $corner"}
    }
    incr corner
}
if {$corner != 4} {error "Expected four persistence corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"synchronizer_stages":3,"maximum_delay_ns":%.3f,"command_bits":%d,"reply_bits":%d,"epoch_bits":%d,"guest_epoch_bits":32,"epoch_bound_ns":20.0}} $maximum [get_collection_size $command] [get_collection_size $reply] [get_collection_size $epoch]]
close $receipt
puts "PASS: RTC persistence held banks at four corners, maximum $maximum ns"
project_close

