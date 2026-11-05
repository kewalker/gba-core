if {$argc != 1} {error "Usage: check-fast-clock-timing.tcl report-prefix"}
set prefix [lindex $argv 0]
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
set cpu_clock ""
set video_clock ""
foreach_in_collection clock [get_clocks *] {
    set name [get_clock_info -name $clock]
    # The SDRAM forwarding PLL also has a general[0] output. Select the
    # established core PLL explicitly rather than depending on clock order.
    if {[string first {ic|mp1|mf_pllbase_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk} $name] >= 0} {
        if {$cpu_clock ne ""} {error "Ambiguous CPU clock"}
        set cpu_clock $name
    }
    if {[string first {ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk} $name] >= 0} {
        if {$video_clock ne ""} {error "Ambiguous video clock"}
        set video_clock $name
    }
}
if {$cpu_clock eq "" || $video_clock eq ""} {error "Missing independent CPU or video clock"}
set cpu_period [get_clock_info -period [get_clocks $cpu_clock]]
set video_period [get_clock_info -period [get_clocks $video_clock]]
# TimeQuest reports periods rounded to 1 ps. Allow their accumulated
# rounding across the 13:4 ratio while checking the expected frequency.
if {abs($cpu_period*13.0-$video_period*4.0)>0.02 || abs($cpu_period-25.040064)>0.01} {
    error "Unexpected CPU/video frequencies or ratio: CPU=$cpu_period video=$video_period"
}
set corner 0
set minimum 1000.0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    report_timing -setup -from_clock [get_clocks $cpu_clock] -to_clock [get_clocks $cpu_clock] -npaths 12 -detail full_path -file "$prefix-cpu-$corner.rpt"
    set paths [get_timing_paths -setup -from_clock [get_clocks $cpu_clock] -to_clock [get_clocks $cpu_clock] -npaths 1]
    set found 0
    foreach_in_collection path $paths {
        set found 1
        set slack [get_path_info -slack $path]
        if {$slack<0} {error "CPU clock fails setup: $slack ns"}
        if {$slack<$minimum} {set minimum $slack}
    }
    if {!$found} {error "Missing CPU timing paths"}
    incr corner
}
if {$corner!=4} {error "Expected four operating conditions"}
set receipt [open "$prefix.json" w]
puts $receipt [format {{"corners":%d,"cpu_period_ns":%.6f,"video_period_ns":%.6f,"minimum_cpu_setup_slack_ns":%.3f}} $corner $cpu_period $video_period $minimum]
close $receipt
delete_timing_netlist
project_close
