// One outstanding request. Bundled descriptors remain held until response;
// responses remain held until consumed. Reset must be common to both domains.
module gba_sdram_cdc(
`ifdef GBK_SAVESTATE
 output wire state_client_idle,
`endif
 input wire client_clk,memory_clk,reset,client_reset,
 input wire client_req,client_write,input wire [24:0] client_addr,
 input wire [31:0] client_wdata,input wire [3:0] client_byteena,
 output reg client_ready,output reg [63:0] client_rdata,
 output wire memory_valid,input wire memory_ready,
 output wire memory_write,output wire [24:0] memory_addr,
 output wire [31:0] memory_wdata,output wire [3:0] memory_byteena,
 input wire response_valid,output wire response_ready,input wire [63:0] response_data
);
 reg request_toggle,response_toggle;
 reg [61:0] descriptor;
 reg [63:0] held_response;
 (* ASYNC_REG="TRUE" *) reg [2:0] request_sync,response_sync;
 reg request_seen,response_seen;
 reg [61:0] descriptor_sync1,descriptor_sync2;
 reg [63:0] data_sync1,data_sync2;
 reg [1:0] client_state;
 reg accepted;
 reg discard_response;
`ifdef GBK_SAVESTATE
 assign state_client_idle=client_state==0 && !client_req && !client_ready;
`endif
 assign {memory_write,memory_addr,memory_wdata,memory_byteena}=descriptor_sync2;
 assign memory_valid=request_sync[2]!=request_seen && !accepted;
 assign response_ready=accepted;
 always @(posedge client_clk) begin
  client_ready<=0;
  if(reset) begin
   request_toggle<=0;descriptor<=0;response_sync<=0;response_seen<=0;
   data_sync1<=0;data_sync2<=0;client_rdata<=0;client_state<=0;discard_response<=0;
  end else begin
   response_sync<={response_sync[1:0],response_toggle};
   data_sync1<=held_response;data_sync2<=data_sync1;
   if(client_reset && client_state==1) discard_response<=1;
   case(client_state)
    0:if(client_req && !client_reset) begin
     descriptor<={client_write,client_addr,client_wdata,client_byteena};
     request_toggle<=~request_toggle;client_state<=1;discard_response<=0;
    end
    1:if(response_sync[2]!=response_seen) begin
     client_rdata<=data_sync2;client_ready<=!discard_response && !client_reset;
     response_seen<=response_sync[2];client_state<=2;
    end
    2:client_state<=0;
    default:client_state<=0;
   endcase
  end
 end
 always @(posedge memory_clk) begin
  if(reset) begin
   request_sync<=0;request_seen<=0;descriptor_sync1<=0;descriptor_sync2<=0;
   held_response<=0;response_toggle<=0;accepted<=0;
  end else begin
   request_sync<={request_sync[1:0],request_toggle};
   descriptor_sync1<=descriptor;descriptor_sync2<=descriptor_sync1;
   if(memory_valid && memory_ready) accepted<=1;
   if(response_valid && response_ready) begin
    held_response<=response_data;response_toggle<=~response_toggle;
    request_seen<=request_sync[2];accepted<=0;
   end
  end
 end
endmodule
