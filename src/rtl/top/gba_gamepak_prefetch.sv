// Native-cycle GamePak prefetch accounting. Data remains on the existing ROM
// path: this tracks the work already performed by the eight-halfword buffer.
// No host clocks or cache-hit signals contribute guest prefetch credit.
module gba_gamepak_prefetch(
 input wire clk,reset,hold,
 input wire restore_low,restore_high,input wire [31:0] restore_data,
 output wire [45:0] state_bits,
 input wire [15:0] waitcnt,
 input wire flush,code_access,data_access,
 input wire [31:0] address,
 input wire word_access,
 input wire [5:0] ordinary_charge,opportunity,
 output wire [5:0] charge
);
 // Fits the existing scheduler's two reserved fields (20 + 26 bits).
 // ROM addresses all have bit 27 set; [26:1] identifies the next halfword,
 // including the three WAITCNT windows. No physical alias loses its window.
 reg [45:0] image;
 wire [25:0] next_halfword=image[25:0];
 wire [6:0] credit=image[32:26];
 wire valid=image[33];
 wire [11:0] saved_waits=image[45:34];
 wire [11:0] waits={waitcnt[14],waitcnt[10:0]};
 wire rom=address[31:28]==0 && address[27:24]>=8 && address[27:24]<=13;
 wire cart_data=data_access && address[27:24]>=8;
 wire changed=saved_waits!=waits;
 function automatic [3:0] sequential_cost(input [2:0] window,input [15:0] control);
  if(window<2) sequential_cost=control[4] ? 2 : 3;
  else if(window<4) sequential_cost=control[7] ? 2 : 5;
  else sequential_cost=control[10] ? 2 : 9;
 endfunction
 wire [3:0] request_cost=sequential_cost(address[26:24],waitcnt);
 wire [3:0] stream_cost=sequential_cost(next_halfword[25:23],waitcnt);
 wire continuing=valid && rom && address[26:1]==next_halfword && address[16:0]!=0;
 wire usable=waitcnt[14] && !flush && !changed && continuing;
 wire [6:0] needed=word_access ? {2'd0,request_cost,1'b0} : {3'd0,request_cost};
 wire [7:0] capacity={1'b0,stream_cost,3'b000};
 wire [7:0] grown={1'b0,credit}+opportunity;
 wire [6:0] remainder=needed>credit ? needed-credit : 0;
 // A complete prefetched opcode takes one CPU cycle. A partial fetch waits
 // only for the unfinished halfword service. Keep a strictly positive charge.
 assign charge=code_access && usable ? (remainder==0 ? 6'd1 : remainder[5:0]) : ordinary_charge;
 wire [6:0] remaining_credit=credit>=needed ? credit-needed : 0;
 // On a buffered hit the cartridge bus is free during the one CPU delivery
 // cycle, allowing one cycle of work on the following halfword.
 wire [7:0] after_hit={1'b0,remaining_credit}+1'b1;
 wire [25:0] following=address[26:1]+(word_access ? 26'd2 : 26'd1);
 wire [6:0] new_credit=after_hit>capacity ? capacity[6:0] : after_hit[6:0];
 assign state_bits=image;
 always @(posedge clk) begin
  if(reset) image<=0;
  else if(hold) begin
   if(restore_low) image[19:0]<=restore_data[31:12];
   if(restore_high) image[45:20]<=restore_data[31:6];
  end else begin
   image[45:34]<=waits;
   if(!waitcnt[14] || cart_data || (flush && !code_access) || (changed && !code_access)) begin
    image[33:0]<=0;
   end else if(code_access) begin
    image[25:0]<=following;image[33]<=rom && following[25:23]<6;
    image[32:26]<=rom && following[25:23]<6 && usable && credit>=needed ? new_credit : 0;
   end else if(valid && opportunity!=0) begin
    image[32:26]<=grown>capacity ? capacity[6:0] : grown[6:0];
   end
  end
 end
endmodule
