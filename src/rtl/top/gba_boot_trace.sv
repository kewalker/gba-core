// Passive PC history. IRQ excursions into BIOS do not count as a restart;
// only a transition to the BIOS reset vector does.
module gba_boot_trace (
    input logic clk, reset,
    input logic [31:0] pc,
    output logic [31:0] entry_counts, last_cart_pc, reset_from_pc
);
    logic [31:0] previous_pc;
    logic [15:0] reset_entries, cart_entries;
    logic boot_has_cart;
    wire in_cart = pc[31:24] >= 8'h08 && pc[31:24] <= 8'h0d;
    assign entry_counts = {reset_entries, cart_entries};
    always_ff @(posedge clk) begin
        if (reset) begin
            previous_pc <= 0;
            reset_entries <= 0;
            cart_entries <= 0;
            boot_has_cart <= 0;
            last_cart_pc <= 0;
            reset_from_pc <= 0;
        end else begin
            previous_pc <= pc;
            if (pc == 0 && previous_pc != 0) begin
                if (reset_entries != 16'hffff) reset_entries <= reset_entries + 1'b1;
                reset_from_pc <= previous_pc;
                boot_has_cart <= 0;
            end
            if (in_cart) begin
                last_cart_pc <= pc;
                if (!boot_has_cart) begin
                    if (cart_entries != 16'hffff) cart_entries <= cart_entries + 1'b1;
                    boot_has_cart <= 1;
                end
            end
        end
    end
endmodule
