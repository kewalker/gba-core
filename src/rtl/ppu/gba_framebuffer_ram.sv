module gba_framebuffer_ram (
    input  logic        write_clk,
    input  logic        write_en,
    input  logic [15:0] write_addr,
    input  logic [15:0] write_data,
    input  logic        read_clk,
    input  logic [15:0] read_addr,
    output logic [15:0] read_data,
    output logic [15:0] debug_pixel0
);
`ifdef GBK_SIM
    logic [15:0] mem [0:38399];
    assign debug_pixel0 = mem[0];
    always_ff @(posedge write_clk)
        if (write_en && write_addr < 16'd38400) mem[write_addr] <= write_data;
    always_ff @(posedge read_clk)
        if (read_addr < 16'd38400) read_data <= mem[read_addr];
`else
    wire [15:0] ram_q;
    assign read_data = ram_q;
    assign debug_pixel0 = 16'h0;
    altsyncram framebuffer_ram (
        .address_a(write_addr), .address_b(read_addr),
        .clock0(write_clk), .clock1(read_clk),
        .data_a(write_data), .data_b(16'h0),
        .wren_a(write_en), .wren_b(1'b0),
        .q_a(), .q_b(ram_q),
        .aclr0(1'b0), .aclr1(1'b0),
        .addressstall_a(1'b0), .addressstall_b(1'b0),
        .byteena_a(1'b1), .byteena_b(1'b1),
        .clocken0(1'b1), .clocken1(1'b1),
        .clocken2(1'b1), .clocken3(1'b1),
        .eccstatus(), .rden_a(1'b1), .rden_b(1'b1)
    );
    defparam framebuffer_ram.operation_mode = "BIDIR_DUAL_PORT";
    defparam framebuffer_ram.intended_device_family = "Cyclone V";
    defparam framebuffer_ram.lpm_type = "altsyncram";
    defparam framebuffer_ram.numwords_a = 38400;
    defparam framebuffer_ram.numwords_b = 38400;
    defparam framebuffer_ram.widthad_a = 16;
    defparam framebuffer_ram.widthad_b = 16;
    defparam framebuffer_ram.width_a = 16;
    defparam framebuffer_ram.width_b = 16;
    defparam framebuffer_ram.outdata_reg_b = "CLOCK1";
    defparam framebuffer_ram.address_reg_b = "CLOCK1";
`endif
endmodule
