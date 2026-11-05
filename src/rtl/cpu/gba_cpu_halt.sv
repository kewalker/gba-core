// HALTCNT is a BIOS-only byte at 04000301. Wake on IE & IF independently
// of IME/CPSR.I; IRQ entry remains the CPU's separate responsibility.
module gba_cpu_halt(
 input wire clk,reset,accepted,write,wake,stop_wake,
`ifdef GBK_SAVESTATE
 input wire state_hold,state_write,
 input wire [2:0] state_wdata,
 output wire state_valid,
 output wire [2:0] state_rdata,
`endif
 input wire [1:0] size,input wire [31:0] addr,wdata,pc,
 output reg halted,
 output reg stopped,postflg
);
`ifdef GBK_SAVESTATE
 wire state_frozen=state_hold===1'b1;
 assign state_valid=!reset && state_frozen;
 assign state_rdata=state_valid ? {postflg,stopped,halted} : 3'd0;
`endif
 wire halt_lane=size==0 ? addr[1:0]==1 : size==2 || (size==1 && !addr[1]);
 wire [7:0] halt_byte=size==0 ? wdata[7:0] : wdata[15:8];
 wire power_write=accepted && write && pc[31:14]==0 &&
     addr[31:2]==(32'h04000300>>2) && halt_lane;
 wire post_write=accepted && write && pc[31:14]==0 &&
     addr[31:2]==(32'h04000300>>2) && (size!=0 || addr[1:0]==0) && !addr[1];
 always @(posedge clk) begin
  if(reset) begin halted<=0;stopped<=0;postflg<=0;end
`ifdef GBK_SAVESTATE
  else if(state_frozen)begin
   if(state_write)begin halted<=state_wdata[0];stopped<=state_wdata[1];postflg<=state_wdata[2];end
  end
`endif
  else begin
   if(post_write) postflg<=postflg | wdata[0];
   if(stopped) begin
    if(stop_wake===1'b1) begin stopped<=0;halted<=0;end
   end else if(power_write && halt_byte[7]) begin
    if(stop_wake!==1'b1) begin stopped<=1;halted<=1;end
   end else if(wake) halted<=0;
   else if(power_write) halted<=1;
  end
 end
endmodule
