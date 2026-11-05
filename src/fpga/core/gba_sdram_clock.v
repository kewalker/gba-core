// Separate, fixed-frequency forwarded clock. Commands/data launch on clk_74a;
// the SDRAM samples them on the +270-degree clock after FPGA output delay.
module gba_sdram_clock(input wire refclk,reset,output wire locked,output wire dram_clk);
 wire shifted;
 altera_pll #(.fractional_vco_multiplier("false"),.reference_clock_frequency("74.25 MHz"),
  .operation_mode("normal"),.number_of_clocks(1),.output_clock_frequency0("74.25 MHz"),
  .phase_shift0("10101 ps"),.duty_cycle0(50),.pll_type("General"),.pll_subtype("General")) forward_pll(
  .refclk(refclk),.rst(reset),.outclk(shifted),.locked(locked),.fbclk(1'b0),.fboutclk());
 altddio_out #(.width(1),.power_up_high("OFF"),.oe_reg("UNREGISTERED"),
  .intended_device_family("Cyclone V")) clock_pin(
  .datain_h(1'b1),.datain_l(1'b0),.outclock(shifted),.outclocken(1'b1),
  .aclr(reset || !locked),.aset(1'b0),.sclr(1'b0),.sset(1'b0),.oe(1'b1),.dataout(dram_clk));
endmodule
