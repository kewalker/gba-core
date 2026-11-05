// One CPU/DMA word port and one independent 64-bit sprite-entry read port.
module gba_oam_ram(
    input wire cpu_clk,cpu_write,
    input wire [7:0] cpu_addr,
    input wire [31:0] cpu_wdata,
    input wire [3:0] cpu_byteena,
    output wire [31:0] cpu_rdata,
    input wire render_clk,
    input wire [6:0] render_addr,
    output wire [63:0] render_data
);
`ifdef GBK_SIM
    reg [31:0] mem[0:255];
    reg [7:0] cpu_addr_reg;
    reg [6:0] render_addr_reg;
    reg [31:0] cpu_q;
    reg [63:0] render_q;
    assign cpu_rdata=cpu_q;assign render_data=render_q;
    always @(posedge cpu_clk) begin
        if(cpu_write) for(integer n=0;n<4;n=n+1)
            if(cpu_byteena[n]) mem[cpu_addr][n*8+:8]<=cpu_wdata[n*8+:8];
        cpu_addr_reg<=cpu_addr;cpu_q<=mem[cpu_addr_reg];
    end
    always @(posedge render_clk) begin
        render_addr_reg<=render_addr;
        render_q<={mem[{render_addr_reg,1'b1}],mem[{render_addr_reg,1'b0}]};
    end
`else
    altsyncram storage(.clock0(cpu_clk),.clock1(render_clk),
        .address_a(cpu_addr),.address_b(render_addr),.data_a(cpu_wdata),.data_b(64'd0),
        .wren_a(cpu_write),.wren_b(1'b0),.byteena_a(cpu_byteena),.byteena_b(8'hff),
        .q_a(cpu_rdata),.q_b(render_data),.aclr0(1'b0),.aclr1(1'b0),
        .addressstall_a(1'b0),.addressstall_b(1'b0),.clocken0(1'b1),.clocken1(1'b1),
        .clocken2(1'b1),.clocken3(1'b1),.rden_a(1'b1),.rden_b(1'b1),.eccstatus());
    defparam storage.operation_mode="BIDIR_DUAL_PORT";
    defparam storage.intended_device_family="Cyclone V";
    defparam storage.lpm_type="altsyncram";
    defparam storage.numwords_a=256,storage.widthad_a=8,storage.width_a=32;
    defparam storage.numwords_b=128,storage.widthad_b=7,storage.width_b=64;
    defparam storage.width_byteena_a=4,storage.width_byteena_b=8;
    defparam storage.outdata_reg_a="CLOCK0",storage.outdata_reg_b="CLOCK1";
    defparam storage.address_reg_b="CLOCK1";
`endif
endmodule
