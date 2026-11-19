# Reset clock-domain crossing audit. With the asynchronous clock groups
# removed, every register path from a reset source is timed, so a crossing
# shows up as a path between different clocks. Raw resets (reset_n, the RTC
# boot gate and the memory startup reset) may reach another clock only through
# a gba_reset_sync stage; each synchronizer output must stay in its own clock.
# Ordinary signals entering an existing synchronizer's first stage are allowed.
# Run from src/fpga after fitting: quartus_sta -t check-reset-crossing-timing.tcl prefix
if {$argc != 1} {error "Usage: check-reset-crossing-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
remove_clock_groups -all
update_timing_netlist
set raw [get_registers -nowarn {*core_bridge_cmd:icb|reset_n *persistence.link|boot_ready *gba_startup_reset:startup_reset|memory_reset}]
set synced [get_registers -nowarn {*reset_sync|stages[2]}]
if {[get_collection_size $raw] < 2 || [get_collection_size $synced] < 10} {
    error "Missing reset sources: raw [get_collection_size $raw], synchronizers [get_collection_size $synced]"
}
proc crossings {sources} {
    set count 0
    set example ""
    foreach kind {setup recovery} {
        foreach_in_collection p [get_timing_paths -$kind -from $sources -npaths 50000 -nworst 1] {
            set fc [get_clock_info -name [get_path_info -from_clock $p]]
            set tc [get_clock_info -name [get_path_info -to_clock $p]]
            if {$fc eq $tc} continue
            set to [get_node_info -name [get_path_info -to $p]]
            if {[string match "*reset_sync*stages*" $to] || [regexp {_sync\[0\]$|sync1(\[[0-9]+\])?$} $to]} continue
            incr count
            if {$example eq ""} {set example "$kind $fc -> $tc $to"}
        }
    }
    return [list $count $example]
}
set corner 0
set total 0
set first ""
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    foreach group [list $raw $synced] {
        lassign [crossings $group] count example
        incr total $count
        if {$first eq "" && $example ne ""} {set first $example}
    }
    incr corner
}
if {$corner != 4} {error "Expected four operating conditions, got $corner"}
set status [expr {$total == 0 ? "PASS" : "FAIL"}]
set receipt [open "$prefix.json" w]
puts $receipt [format {{"status":"%s","corners":%d,"raw_sources":%d,"synchronizer_outputs":%d,"crossing_endpoints":%d}} \
    $status $corner [get_collection_size $raw] [get_collection_size $synced] $total]
close $receipt
if {$total != 0} {error "Reset crossings found: $total, e.g. $first"}
puts "PASS: no reset crosses a clock domain outside a synchronizer in $corner corners"
project_close
