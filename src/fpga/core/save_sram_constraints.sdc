# The SRAM is asynchronous. These are pin datapath budgets, not a fictitious
# SRAM clock. The sequencer supplies 8 * 13.468 ns access time, plus a full
# clock of input hold before OE release. Reserve 2 ns board flight each way:
# out 8 + board 2 + tAA 55 + board 2 + input 8 + clock skew 5 = 80 ns.
# The input register samples after 7 access clocks (94.3 ns), then the word
# register consumes it on clock 8. Write pulse 107.7 ns - 8 ns pin skew exceeds
# tWP 45 ns; setup+access also
# exceeds tAW/tBW 50 ns. Fitted endpoint coverage is checked separately.
set save_inputs [get_registers -nowarn {*external_save.flash*storage*pins*|dq_sample[*]}]
if {[get_collection_size $save_inputs] != 0} {
    if {[get_collection_size $save_inputs] != 16} {error "Missing SRAM read registers"}
    set save_pins [get_ports {sram_a[*] sram_dq[*] sram_oe_n sram_we_n sram_ub_n sram_lb_n}]
    # TimeQuest includes clock insertion in register-to-port max_delay. Allow
    # 8 ns raw path plus 5 ns insertion here; the separate routed audit enforces
    # the stricter raw 8 ns bound on every endpoint at all four corners.
    set_max_delay 13.0 -from [get_registers {*external_save.flash*storage*pins*}] -to $save_pins
    set_max_delay 8.0 -from [get_ports {sram_dq[*]}] -to $save_inputs
    set_min_delay 0.0 -from [get_ports {sram_dq[*]}] -to $save_inputs
}
