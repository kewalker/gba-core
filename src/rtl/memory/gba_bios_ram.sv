// Dual-clock BIOS storage. The Pocket bridge writes the image at 74 MHz;
// the ARM7 reads it from the emulator clock.
module gba_bios_ram #(
    parameter integer WORDS = 4096
) (
    input  logic load_clk,
    input  logic load_write,
    input  logic [$clog2(WORDS)-1:0] load_addr,
    input  logic [31:0] load_wdata,
    input  logic cpu_clk,
    input  logic [$clog2(WORDS)-1:0] cpu_addr,
    output logic [31:0] cpu_rdata,
    output logic [31:0] debug_word_12c
);
    wire [$clog2(WORDS)-1:0] load_port_addr =
        load_write ? load_addr : 12'h04b;
`ifdef GBK_SIM
    logic [31:0] mem [0:WORDS-1];
    logic [$clog2(WORDS)-1:0] load_addr_reg;
`ifdef GBK_POCKET
    logic [$clog2(WORDS)-1:0] cpu_addr_reg;
`endif
    always_ff @(posedge load_clk) begin
        load_addr_reg <= load_port_addr;
        if (load_write && load_addr < WORDS) mem[load_addr] <= load_wdata;
    end
    always_comb debug_word_12c =
        (load_addr_reg < WORDS) ? mem[load_addr_reg] : 32'd0;
`ifdef GBK_POCKET
    // Match the Pocket altsyncram configuration: the CPU-side address is
    // clocked, while the data output is unregistered.
    always_ff @(posedge cpu_clk)
        cpu_addr_reg <= cpu_addr;
    always_comb cpu_rdata = (cpu_addr_reg < WORDS) ? mem[cpu_addr_reg] : 32'd0;
`else
    always_comb cpu_rdata = (cpu_addr < WORDS) ? mem[cpu_addr] : 32'd0;
`endif
`else
    wire [31:0] load_q;
    wire [31:0] cpu_q;
    assign cpu_rdata = cpu_q;
    assign debug_word_12c = load_q;
    altsyncram bios_ram (
        .address_a(load_port_addr), .address_b(cpu_addr),
        .clock0(load_clk), .clock1(cpu_clk),
        .data_a(load_wdata), .data_b(32'b0),
        .wren_a(load_write), .wren_b(1'b0),
        .q_a(load_q), .q_b(cpu_q),
        .aclr0(1'b0), .aclr1(1'b0),
        .addressstall_a(1'b0), .addressstall_b(1'b0),
        .byteena_a(4'b1111), .byteena_b(4'b1111),
        .clocken0(1'b1), .clocken1(1'b1),
        .clocken2(1'b1), .clocken3(1'b1),
        .eccstatus(), .rden_a(1'b1), .rden_b(1'b1)
    );
    defparam bios_ram.operation_mode = "BIDIR_DUAL_PORT";
    defparam bios_ram.intended_device_family = "Cyclone V";
    defparam bios_ram.lpm_type = "altsyncram";
    defparam bios_ram.numwords_a = WORDS;
    defparam bios_ram.numwords_b = WORDS;
    defparam bios_ram.widthad_a = $clog2(WORDS);
    defparam bios_ram.widthad_b = $clog2(WORDS);
    defparam bios_ram.width_a = 32;
    defparam bios_ram.width_b = 32;
    defparam bios_ram.width_byteena_a = 4;
    defparam bios_ram.width_byteena_b = 4;
    defparam bios_ram.outdata_reg_a = "UNREGISTERED";
    defparam bios_ram.outdata_reg_b = "UNREGISTERED";
    // The A address is always clocked; altsyncram has no address_reg_a.
    defparam bios_ram.address_reg_b = "CLOCK1";
`endif
endmodule
