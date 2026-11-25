// Read the eight words at A0..BF twice. Compare each pair and check the
// GBA fixed byte and header complement, which covers A0..BC.
module gba_gamepak_header_probe #(
    parameter integer POWER_SETTLE_CYCLES=1048576
) (
    input wire clk,enable,
    output wire request_valid,
    output wire [22:0] request_word,
    input wire request_ready,response_valid,
    input wire [31:0] response_data,
    output wire response_ready,
    output reg passed=0,
    output reg failed=0
);
    localparam SETTLE=0,REQUEST=1,REPLY=2,SUM=3,DONE=4;
    localparam WAIT_BITS=POWER_SETTLE_CYCLES>1 ? $clog2(POWER_SETTLE_CYCLES) : 1;
    reg [2:0] state=SETTLE;
    reg [WAIT_BITS-1:0] power_wait=0;
    reg [2:0] index=0;
    reg repeat_word=0;
    reg [7:0] checksum=8'h19;
    reg [31:0] first_word;
    reg [1:0] byte_index;
    wire [7:0] header_byte=first_word[{byte_index,3'b000}+:8];
    wire [7:0] next_checksum=checksum+header_byte;
    assign request_valid=enable && state==REQUEST;
    assign request_word={17'd0,3'b101,index};
    assign response_ready=enable && state==REPLY;
    always @(posedge clk) begin
        if(!enable)begin
            state<=SETTLE;power_wait<=0;index<=0;
            passed<=0;failed<=0;repeat_word<=0;checksum<=8'h19;
        end else case(state)
            SETTLE:if(power_wait==POWER_SETTLE_CYCLES-1)state<=REQUEST;
                   else power_wait<=power_wait+1'b1;
            REQUEST:if(request_ready)state<=REPLY;
            REPLY:if(response_valid)begin
                if(!repeat_word)begin
                    first_word<=response_data;repeat_word<=1;state<=REQUEST;
                end else if(first_word!=response_data)begin
                    failed<=1;state<=DONE;
                end else begin
                    repeat_word<=0;byte_index<=0;state<=SUM;
                end
            end
            SUM:begin
                checksum<=next_checksum;
                if(index==4 && byte_index==2 && header_byte!=8'h96)begin
                    failed<=1;state<=DONE;
                end else if(index==7 && byte_index==1)begin
                    passed<=next_checksum==0;
                    failed<=next_checksum!=0;
                    state<=DONE;
                end else if(byte_index==3)begin
                    index<=index+1'b1;state<=REQUEST;
                end else byte_index<=byte_index+1'b1;
            end
            DONE:begin end
            default:state<=SETTLE;
        endcase
    end
endmodule
