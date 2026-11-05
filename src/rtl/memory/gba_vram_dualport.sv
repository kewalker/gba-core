// Shared GBA VRAM storage.
//
// The CPU/DMA side and the display side use independent clocks.  Keeping the
// storage in a true dual-port RAM is important on the Pocket: the old memory
// map exposed one asynchronous array read for every PPU layer, which caused
// Quartus to replicate the entire 96 KiB VRAM until analysis exhausted host
// memory.
module gba_vram_dualport #(
    parameter integer WORDS = 24576
) (
    input  logic        cpu_clk,
    input  logic        cpu_write,
    input  logic [$clog2(WORDS)-1:0] cpu_addr,
    input  logic [31:0] cpu_wdata,
    input  logic [3:0]  cpu_byteena,
    output logic [31:0] cpu_rdata,
    input  logic        ppu_clk,
    input  logic [$clog2(WORDS)-1:0] ppu_addr,
    output logic [31:0] ppu_rdata
);

`ifdef GBK_SIM
    logic [31:0] mem [0:WORDS-1];
    logic [$clog2(WORDS)-1:0] cpu_addr_reg, ppu_addr_reg;

    always_ff @(posedge cpu_clk) begin
        cpu_addr_reg <= cpu_addr;
        if (cpu_write && cpu_addr < WORDS) begin
            if (cpu_byteena[0]) mem[cpu_addr][7:0] <= cpu_wdata[7:0];
            if (cpu_byteena[1]) mem[cpu_addr][15:8] <= cpu_wdata[15:8];
            if (cpu_byteena[2]) mem[cpu_addr][23:16] <= cpu_wdata[23:16];
            if (cpu_byteena[3]) mem[cpu_addr][31:24] <= cpu_wdata[31:24];
        end
        if (cpu_addr_reg < WORDS)
            cpu_rdata <= mem[cpu_addr_reg];
    end

    always_ff @(posedge ppu_clk) begin
        ppu_addr_reg <= ppu_addr;
        if (ppu_addr_reg < WORDS)
            ppu_rdata <= mem[ppu_addr_reg];
    end
`else
    wire [31:0] cpu_q;
    wire [31:0] ppu_q;
    assign cpu_rdata = cpu_q;
    assign ppu_rdata = ppu_q;

    altsyncram vram_ram (
        .address_a(cpu_addr), .address_b(ppu_addr),
        .clock0(cpu_clk), .clock1(ppu_clk),
        .data_a(cpu_wdata), .data_b(32'b0),
        .wren_a(cpu_write), .wren_b(1'b0),
        .q_a(cpu_q), .q_b(ppu_q),
        .aclr0(1'b0), .aclr1(1'b0),
        .addressstall_a(1'b0), .addressstall_b(1'b0),
        .byteena_a(cpu_byteena), .byteena_b(4'b1111),
        .clocken0(1'b1), .clocken1(1'b1),
        .clocken2(1'b1), .clocken3(1'b1),
        .eccstatus(), .rden_a(1'b1), .rden_b(1'b1)
    );
    defparam vram_ram.operation_mode = "BIDIR_DUAL_PORT";
    defparam vram_ram.intended_device_family = "Cyclone V";
    defparam vram_ram.lpm_type = "altsyncram";
    defparam vram_ram.numwords_a = WORDS;
    defparam vram_ram.numwords_b = WORDS;
    defparam vram_ram.widthad_a = $clog2(WORDS);
    defparam vram_ram.widthad_b = $clog2(WORDS);
    defparam vram_ram.width_a = 32;
    defparam vram_ram.width_b = 32;
    defparam vram_ram.width_byteena_a = 4;
    defparam vram_ram.width_byteena_b = 4;
    defparam vram_ram.outdata_reg_a = "CLOCK0";
    defparam vram_ram.outdata_reg_b = "CLOCK1";
    // Port A's address is always clocked; altsyncram has no address_reg_a
    // parameter. Port B's address and both outputs are explicitly clocked.
    defparam vram_ram.address_reg_b = "CLOCK1";
`endif
endmodule
