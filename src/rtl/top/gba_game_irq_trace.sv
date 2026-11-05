// Passive landmarks for the user's Emerald BPEE ROM. Counts wrap at 65536.
// Retained executed-PC observations are counted once per landmark visit.
module gba_game_irq_trace (
    input wire clk, reset,
    input wire [31:0] pc, cpu_r0, validation_result, irq_counts,
    input wire [15:0] dispcnt, bg0cnt,
    input wire [31:0] interrupt_ie_if, last_read_addr, last_read_data,
    output wire [351:0] snapshot
);
    wire [2:0] point = pc==32'h08000738 ? 3'd1 :
        pc==32'h080007d6 ? 3'd2 : pc==32'h08000844 ? 3'd3 :
        pc==32'h080008d0 ? 3'd4 : pc==32'h0816ceac ? 3'd5 :
        pc==32'h03002878 ? 3'd6 : 3'd0;
    reg [2:0] previous_point;
    reg [15:0] vblank_entries, vblank_exits, vcount_entries, wait_returns;
    reg [15:0] copyright_calls, vblank_progress;
    reg [31:0] dispatch_target;
    always @(posedge clk) begin
        if(reset) begin
            previous_point<=0; vblank_entries<=0; vblank_exits<=0;
            vcount_entries<=0; wait_returns<=0; copyright_calls<=0;
            vblank_progress<=16'hffff; dispatch_target<=32'hffffffff;
        end else begin
            previous_point<=point;
            if(pc[31:8]==24'h080007 && pc[7:0]>=8'h38 && pc[7:0]<=8'hd6)
                vblank_progress<=pc[15:0];
            if(point!=previous_point) case(point)
                1: vblank_entries<=vblank_entries+1'b1;
                2: vblank_exits<=vblank_exits+1'b1;
                3: vcount_entries<=vcount_entries+1'b1;
                4: wait_returns<=wait_returns+1'b1;
                5: copyright_calls<=copyright_calls+1'b1;
                6: dispatch_target<=cpu_r0;
                default: begin end
            endcase
        end
    end
    assign snapshot={irq_counts,copyright_calls,vblank_progress,interrupt_ie_if,
        last_read_data,last_read_addr,validation_result,vcount_entries,wait_returns,
        dispatch_target,vblank_entries,vblank_exits,bg0cnt,dispcnt,pc};
endmodule
