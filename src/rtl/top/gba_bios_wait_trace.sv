// Passive trace points for the standard GBA BIOS. These observe execution;
// they never alter CPU, memory, or interrupt behavior.
module gba_bios_wait_trace (
    input wire clk, reset,
    input wire [191:0] execution_state,
    input wire [351:0] restart_context,
    input wire [31:0] loaded_logo_word, cartridge_logo_word, irq_counts,
    output wire [351:0] snapshot
);
    wire [31:0] pc = execution_state[191:160];
    wire [31:0] last_read_addr = restart_context[319:288];
    wire [31:0] last_read_data = restart_context[351:320];
    wire [2:0] point = pc == 32'h330 ? 3'd1 : pc == 32'h364 ? 3'd2 :
        pc == 32'h350 ? 3'd3 : pc == 32'h1c62 ? 3'd4 : pc == 32'h1c70 ? 3'd5 :
        pc == 32'h70a ? 3'd6 : pc == 32'h71c ? 3'd7 : 3'd0;
    reg [2:0] previous_point;
    reg [15:0] wait_caller, wait_flags, requested_flags;
    reg [11:0] wait_entries, wait_returns;
    reg [7:0] animation_iterations, copied_logo_byte;
    reg validation_seen, validation_failed;
    reg failure_seen;
    reg [17:0] failure_address;
    reg [15:0] failure_values;
    wire [31:0] validation_result = validation_seen ? {31'b0,validation_failed} : 32'hffffffff;
    // Failure address: stage 1 = BIOS reference address of unequal logo byte;
    // stage 2 = IWRAM address of checksum byte. Values: expected/actual bytes.
    assign snapshot = {irq_counts, 16'b0, failure_values, 14'b0, failure_address,
        24'b0, copied_logo_byte, 16'b0, requested_flags, validation_result,
        24'b0, animation_iterations, 4'b0, wait_entries, 4'b0, wait_returns,
        16'b0, wait_flags, 16'b0, wait_caller, pc};
    always @(posedge clk) begin
        if (reset) begin
            previous_point <= 0; wait_caller <= 0; wait_flags <= 0;
            requested_flags <= 0; wait_entries <= 0; wait_returns <= 0;
            animation_iterations <= 0; validation_seen <= 0; validation_failed <= 0;
            copied_logo_byte <= 0;
            failure_seen <= 0; failure_address <= 0; failure_values <= 0;
        end else begin
            previous_point <= point;
            // The completed read tuple is retained until the next data read.
            if ((last_read_addr & 32'hff007ffc) == 32'h03000088)
                copied_logo_byte <= last_read_data[7:0];
            if (point != previous_point) case (point)
                3'd1: begin
                    wait_caller <= restart_context[271:256];
                    requested_flags <= execution_state[47:32];
                    if (wait_entries != 12'hfff) wait_entries <= wait_entries+1'b1;
                end
                3'd2: wait_flags <= execution_state[15:0];
                3'd3:
                    if (wait_returns != 12'hfff) wait_returns <= wait_returns+1'b1;
                3'd4:
                    if (animation_iterations != 8'hff)
                        animation_iterations <= animation_iterations+1'b1;
                // R0 is the return from the header validation at 06E8.
                3'd5: begin
                    validation_seen <= 1;
                    validation_failed <= execution_state[95:64] != 0;
                end
                3'd6: if (!failure_seen && !execution_state[126]) begin
                    failure_seen <= 1;
                    failure_address <= {2'd1,last_read_addr[15:0]};
                    failure_values <= {restart_context[199:192],execution_state[7:0]};
                end
                3'd7: if (!failure_seen && !execution_state[126]) begin
                    failure_seen <= 1;
                    failure_address <= {2'd2,last_read_addr[15:0]};
                    failure_values <= {8'b0,execution_state[95:88]};
                end
                default: begin end
            endcase
        end
    end
endmodule
