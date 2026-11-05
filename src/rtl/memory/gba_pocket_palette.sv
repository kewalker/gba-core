module gba_pocket_palette (
    input logic cpu_clk, input logic cpu_write, input logic [7:0] cpu_addr,
    input logic [31:0] cpu_wdata, input logic [3:0] cpu_byteena,
    output logic [31:0] cpu_rdata, input logic ppu_clk, input logic [7:0] ppu_addr,
    output logic [31:0] ppu_rdata
);
`ifdef GBK_SIM
    logic [31:0] mem [0:255];
    logic [7:0] ppu_addr_stage;
    always_ff @(posedge cpu_clk) begin
        if (cpu_write) begin
            if (cpu_byteena[0]) mem[cpu_addr][7:0] <= cpu_wdata[7:0];
            if (cpu_byteena[1]) mem[cpu_addr][15:8] <= cpu_wdata[15:8];
            if (cpu_byteena[2]) mem[cpu_addr][23:16] <= cpu_wdata[23:16];
            if (cpu_byteena[3]) mem[cpu_addr][31:24] <= cpu_wdata[31:24];
        end
        cpu_rdata <= mem[cpu_addr];
    end
    // Match the FPGA RAM's clocked address and clocked output ports.
    always_ff @(posedge ppu_clk) begin
        ppu_addr_stage <= ppu_addr;
        ppu_rdata <= mem[ppu_addr_stage];
    end
`else
    wire [31:0] cpu_q, ppu_q;
    assign cpu_rdata = cpu_q;
    assign ppu_rdata = ppu_q;
    altsyncram pal_ram (
        .address_a(cpu_addr), .address_b(ppu_addr), .clock0(cpu_clk), .clock1(ppu_clk),
        .data_a(cpu_wdata), .data_b(32'b0), .wren_a(cpu_write), .wren_b(1'b0),
        .q_a(cpu_q), .q_b(ppu_q), .aclr0(1'b0), .aclr1(1'b0),
        .addressstall_a(1'b0), .addressstall_b(1'b0), .byteena_a(cpu_byteena),
        .byteena_b(4'b1111), .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1),
        .clocken3(1'b1), .eccstatus(), .rden_a(1'b1), .rden_b(1'b1)
    );
    defparam pal_ram.operation_mode = "BIDIR_DUAL_PORT";
    defparam pal_ram.intended_device_family = "Cyclone V";
    defparam pal_ram.lpm_type = "altsyncram";
    defparam pal_ram.numwords_a = 256;
    defparam pal_ram.numwords_b = 256;
    defparam pal_ram.widthad_a = 8;
    defparam pal_ram.widthad_b = 8;
    defparam pal_ram.width_a = 32;
    defparam pal_ram.width_b = 32;
    defparam pal_ram.width_byteena_a = 4;
    defparam pal_ram.width_byteena_b = 4;
    defparam pal_ram.outdata_reg_a = "CLOCK0";
    defparam pal_ram.outdata_reg_b = "CLOCK1";
    // Port A's address is always clocked; altsyncram has no address_reg_a.
    defparam pal_ram.address_reg_b = "CLOCK1";
`endif
endmodule
