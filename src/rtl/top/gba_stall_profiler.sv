// Passive, CPU-domain counters. Latency maxima saturate at 65535 clocks and
// persist until guest reset. No signal feeds ready, arbitration or execution.
module gba_stall_profiler #(parameter bit ENABLED=0)(
 input wire clk,reset,gba_tick,halted,cpu_req,cpu_ready,dma_active,
 input wire ewram_req,ewram_ready,ewram_write,
 output wire [319:0] profile
);
 generate if(ENABLED) begin : enabled
  reg [31:0] idle_ticks,halt_entries,reads,writes,active_clocks,slow_requests;
  reg was_halted,tracking,held_write;
  reg [15:0] latency,read_max,write_max,dma_length,dma_max,cpu_length,cpu_max;
  wire [15:0] elapsed=latency==16'hffff ? latency : latency+1'b1;
  wire [15:0] dma_elapsed=dma_length==16'hffff ? dma_length : dma_length+1'b1;
  wire [15:0] cpu_elapsed=cpu_length==16'hffff ? cpu_length : cpu_length+1'b1;
  assign profile={idle_ticks,halt_entries,reads,writes,active_clocks,
    16'd0,read_max,16'd0,write_max,16'd0,dma_max,16'd0,cpu_max,slow_requests};
  always @(posedge clk) begin
   if(reset) begin
    idle_ticks<=0;halt_entries<=0;reads<=0;writes<=0;active_clocks<=0;slow_requests<=0;
    was_halted<=0;tracking<=0;held_write<=0;latency<=0;read_max<=0;write_max<=0;
    dma_length<=0;dma_max<=0;cpu_length<=0;cpu_max<=0;
   end else begin
    was_halted<=halted;
    if(halted && gba_tick) idle_ticks<=idle_ticks+1'b1;
    if(halted && !was_halted) halt_entries<=halt_entries+1'b1;
    if(!tracking && ewram_req) begin tracking<=1;held_write<=ewram_write;latency<=0;end
    if(tracking) begin
     latency<=elapsed;active_clocks<=active_clocks+1'b1;
     if(held_write) begin if(elapsed>write_max)write_max<=elapsed;end
     else if(elapsed>read_max)read_max<=elapsed;
     if(ewram_ready) begin
      tracking<=0;
      if(held_write)writes<=writes+1'b1;else reads<=reads+1'b1;
      if(elapsed>=64)slow_requests<=slow_requests+1'b1;
     end
    end
    if(dma_active) begin dma_length<=dma_elapsed;if(dma_elapsed>dma_max)dma_max<=dma_elapsed;end
    else dma_length<=0;
    if(cpu_req && !cpu_ready) begin cpu_length<=cpu_elapsed;if(cpu_elapsed>cpu_max)cpu_max<=cpu_elapsed;end
    else cpu_length<=0;
   end
  end
 end else begin : disabled
  assign profile=0;
 end endgenerate
endmodule
