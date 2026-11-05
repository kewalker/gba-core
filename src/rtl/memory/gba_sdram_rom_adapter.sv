// Physical-halfword interface adapter retaining the last complete SDRAM burst.
// Reads return only after all four beats are stable. Writes invalidate the
// burst buffer and acknowledge only after controller recovery/precharge.
module gba_sdram_rom_adapter(
 input wire clk,reset,input wire [1:0] bank,input wire [21:0] addr,
 input wire write_en,read_en,input wire [15:0] write_data,
 input wire write_high,write_low,
 output wire busy,output reg read_valid,output reg [15:0] read_data,
 output wire [63:0] read_line_data,
 output wire memory_valid,input wire memory_ready,output wire memory_write,
 output wire [24:0] memory_addr,output wire [31:0] memory_wdata,
 output wire [3:0] memory_byteena,
 input wire response_valid,output wire response_ready,input wire [63:0] response_data,
 output wire physical_read,physical_active
);
 reg [1:0] state;
 reg [23:0] held_addr;
 reg [15:0] held_data;
 reg held_write,held_high,held_low;
 reg line_valid;
 reg [21:0] line_tag;
 reg [63:0] line_data;
 // Complete and stable on the same cycle as read_valid, on hits and misses.
 // The cartridge may consume the whole burst without issuing more halfwords.
 assign read_line_data=line_data;
 wire [23:0] address={bank,addr};
 wire line_hit=line_valid && line_tag==address[23:2];
 assign busy=state!=0;
 assign memory_valid=state==1;
 assign memory_write=held_write;
 // ROM occupies the lower 32 MiB. Writes update one half of an aligned word.
 assign memory_addr={1'b0,held_addr[23:1],1'b0};
 assign memory_wdata=held_addr[0] ? {held_data,16'd0} : {16'd0,held_data};
 assign memory_byteena=held_addr[0] ? {held_high,held_low,2'b00} : {2'b00,held_high,held_low};
 assign response_ready=state==2;
 assign physical_read=memory_valid && memory_ready && !held_write;
 assign physical_active=(state==1 || state==2) && !held_write;
 always @(posedge clk) begin
  read_valid<=0;
  if(reset) begin
   state<=0;held_addr<=0;held_data<=0;held_write<=0;held_high<=0;held_low<=0;
   line_valid<=0;line_tag<=0;line_data<=0;read_data<=0;
  end else case(state)
   0:if(write_en || read_en) begin
    held_addr<=address;held_data<=write_data;held_write<=write_en;
    held_high<=write_high;held_low<=write_low;
    if(write_en) begin line_valid<=0;state<=1;end
    else if(line_hit) begin read_data<=line_data[address[1:0]*16+:16];read_valid<=1;end
    else state<=1;
   end
   1:if(memory_ready) state<=2;
   2:if(response_valid) begin
    if(!held_write) begin
     line_data<=response_data;line_tag<=held_addr[23:2];line_valid<=1;
     read_data<=response_data[held_addr[1:0]*16+:16];read_valid<=1;
    end
    state<=0;
   end
   default:state<=0;
  endcase
 end
endmodule
