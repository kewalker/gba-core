// Explicit Pocket IWRAM block.
//
// The simulation/reference memory map uses a SystemVerilog array, but the
// Pocket build must not ask Quartus to infer a multi-read-port RAM from that
// array.  This is the single shared CPU/DMA port used by the GBA bus.
module gba_pocket_iwram #(
    parameter integer WORDS = 8192
) (
    input  logic        clk,
    input  logic        write,
    input  logic [$clog2(WORDS)-1:0] addr,
    input  logic [31:0] wdata,
    input  logic [3:0]  byteena,
    output logic [31:0] rdata
);
`ifdef GBK_SIM
    logic [31:0] mem [0:WORDS-1];
    logic [$clog2(WORDS)-1:0] read_addr_reg;
    always_ff @(posedge clk) begin
        if (write && addr < WORDS) begin
            if (byteena[0]) mem[addr][7:0] <= wdata[7:0];
            if (byteena[1]) mem[addr][15:8] <= wdata[15:8];
            if (byteena[2]) mem[addr][23:16] <= wdata[23:16];
            if (byteena[3]) mem[addr][31:24] <= wdata[31:24];
        end
        // Match the hardware address and output registers on port B.
        read_addr_reg <= addr;
        if (read_addr_reg < WORDS)
            rdata <= mem[read_addr_reg];
    end
`else
    wire [31:0] ram_q;
    assign rdata = ram_q;
    altsyncram iwram_ram (
        .address_a(addr), .address_b(addr),
        .clock0(clk), .clock1(clk),
        .data_a(wdata), .data_b(32'b0),
        .wren_a(write), .wren_b(1'b0),
        .q_a(), .q_b(ram_q),
        .aclr0(1'b0), .aclr1(1'b0),
        .addressstall_a(1'b0), .addressstall_b(1'b0),
        .byteena_a(byteena), .byteena_b(4'b1111),
        .clocken0(1'b1), .clocken1(1'b1),
        .clocken2(1'b1), .clocken3(1'b1),
        .eccstatus(), .rden_a(1'b1), .rden_b(1'b1)
    );
    defparam iwram_ram.operation_mode = "BIDIR_DUAL_PORT";
    defparam iwram_ram.intended_device_family = "Cyclone V";
    defparam iwram_ram.lpm_type = "altsyncram";
    defparam iwram_ram.numwords_a = WORDS;
    defparam iwram_ram.numwords_b = WORDS;
    defparam iwram_ram.widthad_a = $clog2(WORDS);
    defparam iwram_ram.widthad_b = $clog2(WORDS);
    defparam iwram_ram.width_a = 32;
    defparam iwram_ram.width_b = 32;
    defparam iwram_ram.width_byteena_a = 4;
    defparam iwram_ram.width_byteena_b = 4;
    defparam iwram_ram.outdata_reg_b = "CLOCK1";
    defparam iwram_ram.address_reg_b = "CLOCK1";
`endif
endmodule
