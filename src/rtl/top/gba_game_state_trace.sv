// Passive completed-read observations for the user's Emerald BPEE ROM.
// These are retained CPU read values, not a debugger issuing memory reads.
module gba_game_state_trace (
    input wire clk,reset,
    input wire [31:0] pc,irq_counts,last_read_addr,last_read_data,
    input wire [15:0] dispcnt,bg0cnt,
    output wire [351:0] snapshot
);
    reg [15:0] main_state;
    reg [31:0] fade4,fade8,pending,multiboot,callback;
    reg [5:0] valid;
    reg [9:0] wait_completions;
    reg previous_wait;
    wire at_wait = pc==32'h080008d0;
    always @(posedge clk) begin
        if(reset) begin
            main_state<=0;fade4<=0;fade8<=0;pending<=0;multiboot<=0;callback<=0;
            valid<=0;wait_completions<=0;previous_wait<=0;
        end else begin
            previous_wait<=at_wait;
            if(at_wait && !previous_wait) wait_completions<=wait_completions+1'b1;
            case({last_read_addr[31:2],2'b00})
                32'h030026f8: begin main_state<=last_read_data[15:0];valid[0]<=1;end
                32'h02037fd8: begin fade4<=last_read_data;valid[1]<=1;end
                32'h02037fdc: begin fade8<=last_read_data;valid[2]<=1;end
                32'h02037fe4: begin pending<=last_read_data;valid[3]<=1;end
                32'h030062b0: begin multiboot<=last_read_data;valid[4]<=1;end
                32'h030022c4: begin callback<=last_read_data;valid[5]<=1;end
                default: begin end
            endcase
        end
    end
    assign snapshot={irq_counts,last_read_data,last_read_addr,callback,multiboot,
        pending,fade8,fade4,valid,wait_completions,main_state,bg0cnt,dispcnt,pc};
endmodule
