// Core-owned APF export sizes. The host reads these entries on normal exit;
// metadata size_maximum alone does not determine the number of exported bytes.
module gba_save_datatable #(parameter RTC_PERSISTENCE=0)(
    input wire clk,running,host_access,
    input wire [31:0] save_size,
    output wire [9:0] address,
    output wire [31:0] data,
    output wire write_enable
);
    reg turn=0;
    always @(posedge clk)turn<=~turn;
    assign address=turn ? 10'd7 : 10'd3;
    assign data=turn ? (RTC_PERSISTENCE ? 32'd48 : 32'd32) : save_size;
    // The dual-port RAM leaves mixed-port read/write collisions undefined.
    // Hold the table stable throughout host table access, including its
    // registered address/read pipeline. Resume at the next bridge address.
    assign write_enable=running && !host_access;
endmodule
