# APF holds BCD metadata while a two-stage update toggle crosses to the guest
# RTC clock. Bound the complete data/validation path below one guest period.
if {$argc != 1} {error "Usage: check-rtc-bundle-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set source [get_registers {*core_bridge_cmd:icb|rtc_date_bcd* *core_bridge_cmd:icb|rtc_time_bcd*}]
set destinations [get_registers {*gba_cartridge_rtc:rtc|year* *gba_cartridge_rtc:rtc|month* *gba_cartridge_rtc:rtc|day* *gba_cartridge_rtc:rtc|weekday* *gba_cartridge_rtc:rtc|hour* *gba_cartridge_rtc:rtc|minute[*] *gba_cartridge_rtc:rtc|second[*]}]
set count [get_collection_size $destinations]
if {$count < 32 || $count > 56} {error "Missing RTC calendar endpoints: $count"}
set sync [get_registers {*gba_cartridge_rtc:rtc|host_sync[*]}]
if {[get_collection_size $sync] != 2} {error "Missing RTC event synchronizer stages"}
set maximum 0.0
set corner 0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    set bit 0
    foreach_in_collection endpoint $destinations {
        set name [get_register_info -name $endpoint]
        set path [report_path -from $source -to [get_registers $name] -npaths 1 -summary -file "$prefix-corner-$corner-bit-$bit.rpt"]
        if {[lindex $path 0] != 1 || [lindex $path 1] >= 20.0} {error "RTC bundle fails held-event settling: $name $path"}
        if {[lindex $path 1] > $maximum} {set maximum [lindex $path 1]}
        incr bit
    }
    incr corner
}
if {$corner != 4} {error "Expected four RTC operating corners"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"PASS","corners":4,"endpoints":%d,"maximum_delay_ns":%.3f,"settling_bound_ns":20.0,"event_sync_stages":2}} $count $maximum]
close $receipt
puts "PASS: RTC BCD descriptor, $count endpoints, four corners, maximum $maximum ns"
project_close
