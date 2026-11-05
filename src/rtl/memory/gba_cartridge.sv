// Dual-clock cartridge image store.
// The load port represents APF bridge/data-slot writes; the CPU port is read
// only and is intentionally separate so the two clock domains do not share
// combinational logic.
module gba_cartridge #(
    parameter integer ADDR_BITS = 18 // 1 MiB image model; grow for PSRAM
) (
    input  logic                  load_clk,
    input  logic                  load_write,
    input  logic [ADDR_BITS-1:0]  load_addr,
    input  logic [31:0]           load_wdata,
    input  logic                  cpu_clk,
    input  logic                  cpu_req,
    input  logic [31:0]           cpu_addr,
    output logic [31:0]           cpu_rdata,
    output logic                  cpu_ready
);
    localparam integer WORDS = 1 << ADDR_BITS;
    logic [31:0] rom [0:WORDS-1];

    assign cpu_ready = cpu_req;

    always_ff @(posedge load_clk) begin
        if (load_write)
            rom[load_addr] <= load_wdata;
    end

    always_ff @(posedge cpu_clk) begin
        if (cpu_req)
            cpu_rdata <= rom[cpu_addr[ADDR_BITS+1:2]];
    end
endmodule
