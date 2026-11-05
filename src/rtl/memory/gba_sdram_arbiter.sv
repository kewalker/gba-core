// Fair arbitration at complete-transaction boundaries. Ownership never follows
// a live request; the accepted owner's response is held until it is consumed.
module gba_sdram_arbiter(
 input wire clk,reset,
`ifdef GBK_SAVESTATE
 // This is a third owner of the SAME controller. The state coordinator may
 // Exclusive mode waits for a frozen guest. Background mode admits bounded
 // state-pool traffic between normal transactions, including host uploads and
 // RAM copying through the existing EWRAM client. No second memory controller.
 input wire state_enable,state_background,state_valid,state_write,
 input wire [24:0] state_addr,input wire [31:0] state_wdata,
 input wire [3:0] state_byteena,
 output wire state_ready,state_response,input wire state_response_ready,
`endif
 input wire rom_valid,output wire rom_ready,input wire rom_write,
 input wire [24:0] rom_addr,input wire [31:0] rom_wdata,input wire [3:0] rom_byteena,
 output wire rom_response,input wire rom_response_ready,
 input wire ram_valid,output wire ram_ready,input wire ram_write,
 input wire [24:0] ram_addr,input wire [31:0] ram_wdata,input wire [3:0] ram_byteena,
 output wire ram_response,input wire ram_response_ready,
 output wire memory_valid,input wire memory_ready,output wire memory_write,
 output wire [24:0] memory_addr,output wire [31:0] memory_wdata,
 output wire [3:0] memory_byteena,input wire response_valid,output wire response_ready
);
 reg busy,owner_ram,last_ram;
 wire choose_ram=ram_valid && (!rom_valid || !last_ram);
`ifdef GBK_SAVESTATE
 reg last_state;
 wire choose_state=state_enable===1'b1 &&
     (state_background!==1'b1 || (state_valid && (!last_state || !(ram_valid || rom_valid))));
 reg owner_state;
 wire [24:0] normal_addr=choose_ram ? ram_addr : rom_addr;
 wire [31:0] normal_wdata=choose_ram ? ram_wdata : rom_wdata;
 wire [3:0] normal_byteena=choose_ram ? ram_byteena : rom_byteena;
 assign memory_valid=!busy && (choose_state ? state_valid : (ram_valid || rom_valid));
 assign memory_write=choose_state ? state_write : (choose_ram ? ram_write : rom_write);
 assign memory_addr=choose_state ? state_addr : normal_addr;
 assign memory_wdata=choose_state ? state_wdata : normal_wdata;
 assign memory_byteena=choose_state ? state_byteena : normal_byteena;
 assign state_ready=!busy && choose_state && memory_ready;
 assign ram_ready=!busy && !choose_state && choose_ram && memory_ready;
 assign rom_ready=!busy && !choose_state && !choose_ram && memory_ready;
 assign state_response=busy && owner_state && response_valid;
 assign ram_response=busy && !owner_state && owner_ram && response_valid;
 assign rom_response=busy && !owner_state && !owner_ram && response_valid;
 assign response_ready=busy && (owner_state ? state_response_ready :
     (owner_ram ? ram_response_ready : rom_response_ready));
`else
 assign memory_valid=!busy && (ram_valid || rom_valid);
 assign memory_write=choose_ram ? ram_write : rom_write;
 assign memory_addr=choose_ram ? ram_addr : rom_addr;
 assign memory_wdata=choose_ram ? ram_wdata : rom_wdata;
 assign memory_byteena=choose_ram ? ram_byteena : rom_byteena;
 assign ram_ready=!busy && choose_ram && memory_ready;
 assign rom_ready=!busy && !choose_ram && memory_ready;
 assign ram_response=busy && owner_ram && response_valid;
 assign rom_response=busy && !owner_ram && response_valid;
 assign response_ready=busy && (owner_ram ? ram_response_ready : rom_response_ready);
`endif
 always @(posedge clk) begin
  if(reset) begin busy<=0;owner_ram<=0;last_ram<=0;end
  else begin
   if(memory_valid && memory_ready) begin
    busy<=1;owner_ram<=choose_ram;
`ifdef GBK_SAVESTATE
    if(!choose_state)last_ram<=choose_ram;
`else
    last_ram<=choose_ram;
`endif
   end
   if(busy && response_valid && response_ready) busy<=0;
  end
 end
`ifdef GBK_SAVESTATE
 always @(posedge clk)begin
  if(reset)begin owner_state<=0;last_state<=0;end
  else if(memory_valid && memory_ready)begin owner_state<=choose_state;last_state<=choose_state;end
 end
`endif
endmodule
