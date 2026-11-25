// Read one aligned ROM word through the 16-bit multiplexed Game Pak bus.
// The caller must qualify a powered, native GBA cartridge before enabling.
// Wait counts are conservative starting values for the 74.25 MHz host clock.
module gba_gamepak_rom_reader #(
    parameter integer GUARD_CYCLES=8,
    parameter integer READ_CYCLES=20,
    parameter bit LATCH_WORD_ADDRESS=1
) (
    input wire clk,reset,enable,
    input wire request_valid,
    input wire [22:0] request_word,
    output wire request_ready,
    output wire response_valid,
    input wire response_ready,
    output reg [31:0] response_data,
    output wire [23:0] cart_halfword_address,
    output wire cart_address_drive,cart_ad_drive,
    input wire [15:0] cart_ad_in,
    output wire cart_cs_n,cart_rd_n,cart_wr_n,cart_cs2_n
);
    localparam IDLE=0,SETUP=1,LATCH=2,TURNAROUND=3,READ=4,
               NEXT_HALF=5,RECOVER=6,REPLY=7;
    localparam MAX_WAIT=GUARD_CYCLES>READ_CYCLES ? GUARD_CYCLES : READ_CYCLES;
    localparam WAIT_BITS=MAX_WAIT>1 ? $clog2(MAX_WAIT) : 1;
    reg [2:0] state=IDLE;
    reg [WAIT_BITS-1:0] wait_count;
    reg [22:0] word_address;
    reg high_half;
    reg address_drive=0,ad_drive=0,cs_n=1,rd_n=1;
    wire active=enable && !reset;
    assign request_ready=active && state==IDLE;
    assign response_valid=active && state==REPLY;
    // The boot loader holds the index through response acceptance, which is
    // after the reader has released the address pins. Other callers latch it.
    assign cart_halfword_address={LATCH_WORD_ADDRESS ? word_address : request_word,1'b0};
    assign cart_address_drive=active && address_drive;
    assign cart_ad_drive=active && ad_drive;
    assign cart_cs_n=!active || cs_n;
    assign cart_rd_n=!active || rd_n;
    assign cart_wr_n=1'b1;
    assign cart_cs2_n=1'b1;
    initial if(GUARD_CYCLES<1 || READ_CYCLES<1)$error("Invalid Game Pak wait count");

    always @(posedge clk) begin
        if(!active)begin
            state<=IDLE;
            address_drive<=0;ad_drive<=0;cs_n<=1;rd_n<=1;
        end else if(state==IDLE)begin
            if(request_valid)begin
                word_address<=request_word;
                address_drive<=1;ad_drive<=1;high_half<=0;
                wait_count<=0;state<=SETUP;
            end
        end else if(state==REPLY)begin
            if(response_ready)state<=IDLE;
        end else if(wait_count==(state==READ ? READ_CYCLES-1 : GUARD_CYCLES-1))begin
            wait_count<=0;
            case(state)
                SETUP:begin cs_n<=0;state<=LATCH;end
                LATCH:begin ad_drive<=0;state<=TURNAROUND;end
                TURNAROUND,NEXT_HALF:begin rd_n<=0;state<=READ;end
                READ:begin
                    rd_n<=1;
                    if(high_half)begin
                        response_data[31:16]<=cart_ad_in;
                        state<=RECOVER;
                    end else begin
                        response_data[15:0]<=cart_ad_in;
                        high_half<=1;
                        state<=NEXT_HALF;
                    end
                end
                RECOVER:begin cs_n<=1;address_drive<=0;state<=REPLY;end
                default:begin
                    state<=IDLE;
                    address_drive<=0;ad_drive<=0;cs_n<=1;rd_n<=1;
                end
            endcase
        end else wait_count<=wait_count+1'b1;
    end
endmodule
