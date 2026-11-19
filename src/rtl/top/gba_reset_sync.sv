// Reset bridge for one clock domain. Assertion reaches the output at once;
// release passes through STAGES flops of the destination clock, so every
// register in that domain leaves reset on the same edge. The source may be
// combinational logic in another clock domain.
module gba_reset_sync #(parameter integer STAGES=3)(
    input wire clk,
    input wire reset_in,
    output wire reset_out
);
    (* preserve, dont_merge, altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [STAGES-1:0] stages={STAGES{1'b1}};
    always @(posedge clk or posedge reset_in) begin
        if(reset_in) stages<={STAGES{1'b1}};
        else stages<={stages[STAGES-2:0],1'b0};
    end
    assign reset_out=stages[STAGES-1];
endmodule
