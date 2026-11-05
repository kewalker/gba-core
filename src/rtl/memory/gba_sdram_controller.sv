// AS4C32M16MSA at <=74.25 MHz: CL2, sequential burst-4, single-location writes.
// All banks are closed between requests. Response remains valid until consumed;
// acceptance is explicit and refresh always takes priority at the next boundary.
// Commands launch on clk; the board forwards a +270-degree clock. DQ is sampled
// in I/O registers on clk, then consumed one edge later (see READ_PIPELINE).
module gba_sdram_controller #(
 parameter integer STARTUP_CYCLES=16000, REFRESH_CYCLES=520,
 parameter integer TRCD=2,TRP=2,TRFC=6,TWR=3,TMRD=2,
 parameter integer READ_PIPELINE=3
)(
 input wire clk,reset,
 input wire req_valid,output wire req_ready,
 input wire req_write,input wire [24:0] req_addr,
 input wire [31:0] req_wdata,input wire [3:0] req_byteena,
 output reg rsp_valid,input wire rsp_ready,output reg [63:0] rsp_data,
 output reg initialized,output reg refresh_pulse,
 output reg [12:0] dram_a,output reg [1:0] dram_ba,
 inout wire [15:0] dram_dq,output reg [1:0] dram_dqm,
 output wire dram_cke,output wire dram_ras_n,dram_cas_n,dram_we_n
);
 localparam [2:0] NOP=3'b111,ACT=3'b011,RD=3'b101,WR=3'b100,
  PRE=3'b010,REF=3'b001,MRS=3'b000;
 localparam [3:0] POWERUP=0,INIT_PRE=1,INIT_REF1=2,INIT_REF2=3,
  INIT_MODE=4,INIT_EXT=5,IDLE=6,RCD=7,READ=8,WRITE_HIGH=9,
  WRITE_RECOVERY=10,PRE_WAIT=11,REF_WAIT=12,RESPONSE=13;
 reg [3:0] state;
 reg [2:0] command;
 reg [15:0] startup;
 reg [9:0] refresh_age;
 reg [3:0] delay_count;
 reg [24:0] held_addr;
 reg [31:0] held_wdata;
 reg [3:0] held_byteena;
 reg held_write;
 reg [1:0] beat;
 reg [15:0] dq_out;
 reg dq_drive;
 reg [15:0] dq_sample;
 always @(posedge clk) dq_sample<=dram_dq;
 assign dram_dq=dq_drive ? dq_out : 16'hzzzz;
 assign {dram_ras_n,dram_cas_n,dram_we_n}=command;
 assign dram_cke=1'b1;
 assign req_ready=initialized && state==IDLE && !rsp_valid && refresh_age<REFRESH_CYCLES;
 initial begin
  if(STARTUP_CYCLES<14850 || STARTUP_CYCLES>65535 || REFRESH_CYCLES>540 || REFRESH_CYCLES<32)
   $error("SDRAM timing parameters outside the qualified 74.25 MHz profile");
 end
 always @(posedge clk) begin
  command<=NOP;dq_drive<=0;dram_dqm<=0;refresh_pulse<=0;
  if(reset) begin
   state<=POWERUP;startup<=0;refresh_age<=0;delay_count<=0;
   rsp_valid<=0;rsp_data<=0;initialized<=0;command<=NOP;
   held_addr<=0;held_wdata<=0;held_byteena<=0;held_write<=0;beat<=0;
   dram_a<=0;dram_ba<=0;dq_out<=0;dq_drive<=0;
  end else begin
   if(initialized && refresh_age!=1023) refresh_age<=refresh_age+1'b1;
   case(state)
    POWERUP: if(startup==STARTUP_CYCLES-1) begin
     command<=PRE;dram_a<=13'h400;delay_count<=TRP-1;state<=INIT_PRE;
    end else startup<=startup+1'b1;
    INIT_PRE: if(delay_count!=0) delay_count<=delay_count-1'b1;
     else begin command<=REF;delay_count<=TRFC-1;state<=INIT_REF1;end
    INIT_REF1: if(delay_count!=0) delay_count<=delay_count-1'b1;
     else begin command<=REF;delay_count<=TRFC-1;state<=INIT_REF2;end
    INIT_REF2: if(delay_count!=0) delay_count<=delay_count-1'b1;
     else begin command<=MRS;dram_ba<=0;dram_a<=13'h222;delay_count<=TMRD-1;state<=INIT_MODE;end
    INIT_MODE: if(delay_count!=0) delay_count<=delay_count-1'b1;
     else begin command<=MRS;dram_ba<=2;dram_a<=0;delay_count<=TMRD-1;state<=INIT_EXT;end
    INIT_EXT: if(delay_count!=0) delay_count<=delay_count-1'b1;
     else begin initialized<=1;refresh_age<=0;state<=IDLE;end
    IDLE: if(refresh_age>=REFRESH_CYCLES) begin
     command<=REF;refresh_age<=0;refresh_pulse<=1;delay_count<=TRFC-1;state<=REF_WAIT;
    end else if(req_valid && req_ready) begin
     held_addr<=req_addr;held_wdata<=req_wdata;held_byteena<=req_byteena;held_write<=req_write;
     command<=ACT;dram_a<=req_addr[24:12];dram_ba<=req_addr[11:10];
     delay_count<=TRCD-1;state<=RCD;
    end
    RCD: if(delay_count!=0) delay_count<=delay_count-1'b1;
     else if(held_write) begin
      command<=WR;dram_a<={3'b000,held_addr[9:0]};
      dq_out<=held_wdata[15:0];dq_drive<=1;dram_dqm<=~held_byteena[1:0];state<=WRITE_HIGH;
     end else begin
      command<=RD;dram_a<={3'b000,held_addr[9:2],2'b00};
      delay_count<=READ_PIPELINE;beat<=0;state<=READ;
     end
    READ: if(delay_count!=0) delay_count<=delay_count-1'b1;
     else begin
      rsp_data[beat*16+:16]<=dq_sample;
      if(beat==3) begin command<=PRE;dram_a<=13'h400;delay_count<=TRP-1;state<=PRE_WAIT;end
      else beat<=beat+1'b1;
     end
    WRITE_HIGH: begin
     command<=WR;dram_a<={3'b000,held_addr[9:1],1'b1};
     dq_out<=held_wdata[31:16];dq_drive<=1;dram_dqm<=~held_byteena[3:2];
     delay_count<=TWR-1;state<=WRITE_RECOVERY;
    end
    WRITE_RECOVERY: if(delay_count!=0) delay_count<=delay_count-1'b1;
     else begin command<=PRE;dram_a<=13'h400;delay_count<=TRP-1;state<=PRE_WAIT;end
    PRE_WAIT: if(delay_count!=0) delay_count<=delay_count-1'b1;
     else begin rsp_valid<=1;state<=RESPONSE;end
    REF_WAIT: if(delay_count!=0) delay_count<=delay_count-1'b1;
     else state<=rsp_valid ? RESPONSE : IDLE;
    RESPONSE: begin
     // A client may stall indefinitely: responses do not prevent refresh.
     if(rsp_valid && rsp_ready) begin rsp_valid<=0;state<=IDLE;end
     else if(refresh_age>=REFRESH_CYCLES) begin
      command<=REF;refresh_age<=0;refresh_pulse<=1;delay_count<=TRFC-1;state<=REF_WAIT;
     end
    end
    default:state<=POWERUP;
   endcase
  end
 end
endmodule
