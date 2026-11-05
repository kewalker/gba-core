// 74.25 MHz asynchronous AS6C2016-55 interface. One accepted request transfers
// two halfwords. reset is a cold-start reset, never the emulated CPU reset.
// Default pin intervals: setup 26.9 ns, access/write pulse 107.7 ns, hold and
// read-to-write turnaround 26.9 ns. Fitted I/O timing must be audited separately.
module pocket_sram #(
    parameter integer SETUP_CYCLES=2, ACCESS_CYCLES=8, HOLD_CYCLES=2
) (
    input wire clk, reset, req, write,
    input wire [14:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] mask,
    output wire ready,
    output reg done=0,
    output reg [31:0] rdata=0,
    output reg [16:0] sram_a=0,
    inout wire [15:0] sram_dq,
    output reg sram_oe_n=1,
    output reg sram_we_n=1,
    output reg sram_ub_n=1,
    output reg sram_lb_n=1
);
    localparam IDLE=0, SETUP=1, ACCESS=2, HOLD=3, READ_RELEASE=4;
    reg [2:0] state=IDLE;
    reg [7:0] ticks=0;
    reg half=0, writing=0, drive=0;
    reg [15:0] upper_data=0, dq_out=0;
    reg [15:0] dq_sample=0;
    reg [3:0] mask_hold=0;
    assign sram_dq=drive ? dq_out : 16'bz;
    assign ready=state==IDLE && !reset;
    // Dedicated input/output register candidates: no halfword mux at the pin.
    always @(posedge clk) dq_sample<=sram_dq;
    always @(posedge clk) begin
        done<=0;
        if(reset) begin
            state<=IDLE; drive<=0; sram_oe_n<=1; sram_we_n<=1;
            sram_ub_n<=1; sram_lb_n<=1;
        end else case(state)
            IDLE: if(req) begin
                sram_a<={1'b0,addr,1'b0}; upper_data<=wdata[31:16]; dq_out<=wdata[15:0]; mask_hold<=mask;
                writing<=write; half<=0; drive<=write;
                sram_lb_n<=write ? !mask[0] : 0;
                sram_ub_n<=write ? !mask[1] : 0;
                ticks<=SETUP_CYCLES-1; state<=SETUP;
            end
            SETUP: if(ticks!=0) ticks<=ticks-1'b1;
                else begin
                    sram_we_n<=!writing; sram_oe_n<=writing;
                    ticks<=ACCESS_CYCLES-1; state<=ACCESS;
                end
            ACCESS: if(ticks!=0) ticks<=ticks-1'b1;
                else begin
                    if(!writing) begin
                        if(half) rdata[31:16]<=dq_sample;
                        else rdata[15:0]<=dq_sample;
                    end
                    sram_we_n<=1;
                    ticks<=HOLD_CYCLES-1;
                    state<=writing ? HOLD : READ_RELEASE;
                end
            // Keep OE asserted for a whole clock after sampling. The chip's
            // output-disable maximum is not a guaranteed input hold time.
            READ_RELEASE: begin sram_oe_n<=1; state<=HOLD; end
            HOLD: if(ticks!=0) ticks<=ticks-1'b1;
                else if(!half) begin
                    half<=1; sram_a[0]<=1;
                    dq_out<=upper_data;
                    sram_lb_n<=writing ? !mask_hold[2] : 0;
                    sram_ub_n<=writing ? !mask_hold[3] : 0;
                    ticks<=SETUP_CYCLES-1; state<=SETUP;
                end else begin
                    drive<=0; sram_lb_n<=1; sram_ub_n<=1;
                    done<=1; state<=IDLE;
                end
            default: state<=IDLE;
        endcase
    end
endmodule
