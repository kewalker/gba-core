# Qualified clock: 74.25 MHz, forwarded +270 degrees through a DDR output.
# External budgets: chip setup/hold 2/1 ns, CL2 tAC <=6 ns, tOH >=2.5 ns;
# reserve 1 ns board flight/skew for output setup/hold and read setup.
set sdram_inputs [get_registers -nowarn {*sdram_memory.controller*dq_sample*}]
if {[get_collection_size $sdram_inputs] != 0} {
    if {[get_collection_size $sdram_inputs] != 16} {error "Missing SDRAM input registers"}
    set forwarded [get_clocks -nowarn {*sdram_clocking.forward_clock*PLL_OUTPUT_COUNTER*divclk}]
    if {[get_collection_size $forwarded] != 1} {error "Missing unique SDRAM forwarded PLL clock"}
    create_generated_clock -name sdram_pin_clock -source [get_clock_info -targets $forwarded] -divide_by 1 [get_ports dram_clk]
    set outputs [get_ports {dram_a[*] dram_ba[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n dram_cke dram_dq[*]}]
    set_output_delay -clock sdram_pin_clock -max 3.0 $outputs
    set_output_delay -clock sdram_pin_clock -min -2.0 $outputs
    set_input_delay -clock sdram_pin_clock -max 7.0 [get_ports {dram_dq[*]}]
    set_input_delay -clock sdram_pin_clock -min 2.5 [get_ports {dram_dq[*]}]
    # Continuous read data reaches the next-but-one controller edge. The
    # default hold relation must remain: do NOT pair with a -hold exception.
    # Check setup/hold path clock relationships in the separate fitted audit.
    set_multicycle_path -setup 2 -from [get_ports {dram_dq[*]}] -to $sdram_inputs
}
