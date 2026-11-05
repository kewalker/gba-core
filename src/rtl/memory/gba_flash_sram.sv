// Candidate wrapper. Host reads are requested by a bridge strobe and complete
// later within the APF one-word response interval; they are not live RAM reads.
module gba_flash_sram (
    input wire clk, reset, req, write, save_sram, save_flash512,
`ifdef GBK_SAVESTATE
    input wire state_hold,state_write,
    input wire [31:0] state_wdata,
    output wire state_valid,
    output wire [31:0] state_rdata,
    output wire state_host_idle,state_host_done,
`endif
    input wire [1:0] size,
    input wire [31:0] addr, wdata,
    output wire [31:0] rdata,
    output wire ready,
    input wire load_clk, load_reset, load_write, load_read,
    input wire [14:0] load_addr,
    input wire [31:0] load_wdata,
    output wire [31:0] load_rdata,
    output wire load_valid, boot_ready, fault,
    input wire export_lock,
    output wire export_locked,
    output wire [16:0] sram_a,
    inout wire [15:0] sram_dq,
    output wire sram_oe_n, sram_we_n, sram_ub_n, sram_lb_n
);
    wire [14:0] ram_addr;
    wire [31:0] ram_q, ram_data;
    wire [3:0] ram_mask;
    wire ram_write, ram_request, ram_ready, ram_idle;
    gba_flash_commands #(.ASYNC_MEMORY(1)) commands (
`ifdef GBK_SAVESTATE
        .state_hold,.state_write,.state_wdata,.state_valid,.state_rdata,
`endif
        .clk,.reset,.req,.write,.save_sram,.save_flash512,.size,.addr,.wdata,.rdata,.ready,
        .export_lock,.export_locked,.ram_addr,.ram_q,.ram_data,.ram_mask,
        .ram_write,.ram_request,.ram_ready,.ram_idle
    );
    gba_save_sram_backend storage (
`ifdef GBK_SAVESTATE
        .state_host_idle,.state_host_done,
`endif
        .clk,.mem_clk(load_clk),.load_reset,.req(ram_request),.write(ram_write),
        .addr(ram_addr),.wdata(ram_data),.mask(ram_mask),.rdata(ram_q),
        .ready(ram_ready),.guest_idle(ram_idle),
        .host_write(load_write),.host_read(load_read),.host_addr(load_addr),
        .host_wdata(load_wdata),.host_rdata(load_rdata),.host_valid(load_valid),
        .boot_ready,.fault,.sram_a,.sram_dq,.sram_oe_n,.sram_we_n,.sram_ub_n,.sram_lb_n
    );
endmodule
