// Minimal GBA timer block. Timer registers are exposed at 04000100-0400010F.
module gba_timers #(parameter bit CYCLE_ENABLE=0) (
    input  logic clk,
    input logic reset,
`ifdef GBK_SAVESTATE
    input wire state_hold,state_write,
    input wire [3:0] state_addr,
    input wire [31:0] state_wdata,
    output wire state_valid,
    output reg [31:0] state_rdata,
`endif
    input wire cycle_enable,
    input logic        req,
    input logic        write,
    input logic [31:0] addr,
    input logic [31:0] wdata,
    input logic [1:0] size,
    output logic [31:0] rdata,
    output logic        ready,
    output logic [3:0]  irq,
    output wire [3:0] overflow_pulse
);
    logic [15:0] reload [0:3];
    logic [15:0] count  [0:3];
    logic [15:0] control[0:3];
    logic [15:0] prescale_count [0:3];
    integer i;
`ifdef GBK_SAVESTATE
    wire state_frozen=state_hold===1'b1;
    assign state_valid=!reset && state_frozen && state_addr<9;
    always @*begin
        state_rdata=0;
        if(state_valid)begin
            if(state_addr<8)state_rdata=state_addr[0] ?
                {control[state_addr[2:1]],prescale_count[state_addr[2:1]]} :
                {reload[state_addr[2:1]],count[state_addr[2:1]]};
            else state_rdata={28'd0,irq};
        end
    end
`endif

    wire hit = (addr[31:24] == 8'h04) && (addr[15:0] >= 16'h0100) &&
               (addr[15:0] <= 16'h010F);
    wire [1:0] timer_index = addr[3:2];
    wire [1:0] reg_half = addr[1:0];
    wire [31:0] register_word = {control[timer_index], reload[timer_index]};
    wire [31:0] write_mask = size == 2'b00 ? (32'hff << (addr[1:0]*8)) :
                           size == 2'b10 ? 32'hffffffff :
                           (32'hffff << (addr[1]*16));
    wire [31:0] updated_word = (register_word & ~write_mask) |
        ((size == 2'b10 ? wdata : wdata << (addr[1:0]*8)) & write_mask);
    wire [3:0] tick, overflow;
    assign overflow_pulse = overflow;
    genvar t;
    generate for(t=0;t<4;t=t+1) begin : timer_ticks
        wire prescale_tick = prescale_count[t] == ((control[t][1:0] == 0) ? 16'd0 :
            (control[t][1:0] == 1) ? 16'd63 : (control[t][1:0] == 2) ? 16'd255 : 16'd1023);
        if(t==0) assign tick[t] = control[t][7] && (!CYCLE_ENABLE || cycle_enable) && prescale_tick;
        else assign tick[t] = control[t][7] && (!CYCLE_ENABLE || cycle_enable) && (control[t][2] ? overflow[t-1] : prescale_tick);
        assign overflow[t] = tick[t] && count[t] == 16'hffff
`ifdef GBK_SAVESTATE
            && !state_frozen
`endif
        ;
    end endgenerate

    assign ready = !req || !hit || write || hit;
    assign rdata = {control[timer_index], count[timer_index]};

    always_ff @(posedge clk) begin
        if (reset) begin
            irq <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                reload[i] <= 16'b0;
                count[i] <= 16'b0;
                control[i] <= 16'b0;
                prescale_count[i] <= 16'b0;
            end
`ifdef GBK_SAVESTATE
        end else if(state_frozen)begin
            if(state_write && state_valid)begin
                if(state_addr<8)begin
                    if(state_addr[0])begin control[state_addr[2:1]]<=state_wdata[31:16];prescale_count[state_addr[2:1]]<=state_wdata[15:0];end
                    else begin reload[state_addr[2:1]]<=state_wdata[31:16];count[state_addr[2:1]]<=state_wdata[15:0];end
                end else irq<=state_wdata[3:0];
            end
`endif
        end else begin
            irq <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                if (control[i][7] && (!CYCLE_ENABLE || cycle_enable)) begin
                    if (tick[i]) begin
                        prescale_count[i] <= 16'b0;
                        if (count[i] == 16'hffff) begin
                            count[i] <= reload[i];
                            if (control[i][6]) irq[i] <= 1'b1;
                        end else begin
                            count[i] <= count[i] + 1'b1;
                        end
                    end else if(i==0 || !control[i][2]) begin
                        prescale_count[i] <= prescale_count[i] + 1'b1;
                    end
                end
            end

            if (req && write && hit) begin
                if(|write_mask[15:0]) reload[timer_index] <= updated_word[15:0];
                if(|write_mask[31:16]) begin
                    control[timer_index] <= updated_word[31:16];
                    if(!control[timer_index][7] && updated_word[23]) begin
                        count[timer_index] <= updated_word[15:0];
                        prescale_count[timer_index] <= 0;
                    end
                end
            end
        end
    end

endmodule
