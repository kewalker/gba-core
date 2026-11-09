`timescale 1ns/1ps
// A CPU store may remain asserted while DMA owns the physical VRAM port.
module gba_vram_dma_ownership_tb;
    reg clk=0,render_clk=0,reset=1,req=0,write=0;
    reg [31:0] addr=0,wdata=0;
    wire [31:0] rdata;
    wire ready;
    always #40 clk=~clk;
    always #3.75 render_clk=~render_clk;
    gba_memory_map #(.RENDER_SCHEDULER(1)) dut (
        .clk,.render_clk,.reset,.req,.write,.addr,.wdata,.size(2'd2),.rdata,.ready,
        .bios_load_clk(clk),.bios_load_write(1'b0),.bios_load_addr(12'd0),.bios_load_wdata(32'd0),
        .cart_ready(1'b0),.cart_rdata(32'd0),.ewram_ready(1'b0),.ewram_rdata(32'd0),
        .controller_keys(10'h3ff));
    task store(input [31:0] a,d);
        @(negedge clk);addr=a;wdata=d;write=1;req=1;
        do @(posedge clk);while(!ready);
        @(negedge clk);req=0;write=0;
    endtask
    task load(input [31:0] a,d);
        @(negedge clk);addr=a;req=1;write=0;
        do @(posedge clk);while(!ready);
        if(rdata!==d) $fatal(1,"VRAM ownership: read %h got %h expected %h",a,rdata,d);
        @(negedge clk);req=0;
    endtask
    task copy(input [31:0] source,destination,control);
        store(32'h040000d4,source);store(32'h040000d8,destination);
        store(32'h040000dc,control);
        do @(negedge clk);while(dut.dma_active);
    endtask
    task check_palette_readback;
        // Cross the boundary between the BG and OBJ palettes.
        store(32'h050001fc,32'h12345678);
        store(32'h05000200,32'h7c00001f);
        store(32'h05000204,32'h03e07fff);
        copy(32'h050001fc,32'h03000000,32'h84000003);
        load(32'h03000000,32'h12345678);
        load(32'h03000004,32'h7c00001f);
        load(32'h03000008,32'h03e07fff);
        copy(32'h050001fe,32'h03000010,32'h80000004);
        load(32'h03000010,32'h001f1234);
        load(32'h03000014,32'h7fff7c00);
        $display("PASS: palette DMA preserves BG/OBJ colors for 32-bit and 16-bit transfers");
    endtask
    initial begin : run_tests
        repeat(3) @(negedge clk);reset=0;
        if ($test$plusargs("palette_readback")) begin
            check_palette_readback();
            $finish;
            disable run_tests;
        end
        store(32'h06000000,32'h12345678);
        store(32'h06000004,32'habcdef01);
        store(32'h06000008,32'h76543210);
        store(32'h06000100,32'h55667788);
        if($test$plusargs("word_only")) begin
            copy(32'h06000000,32'h03000000,32'h84000003);
            load(32'h03000000,32'h12345678);
            load(32'h03000004,32'habcdef01);
            load(32'h03000008,32'h76543210);
            $display("PASS: consecutive VRAM DMA words wait for registered RAM data");
            $finish;
        end
        if($test$plusargs("halfword_only")) begin
            copy(32'h06000002,32'h03000000,32'h80000004);
            load(32'h03000000,32'hef011234);
            load(32'h03000004,32'h3210abcd);
            $display("PASS: VRAM DMA halfword source selects both physical lanes");
            $finish;
        end
        // Real DMA3 reads two VRAM words into IWRAM. Queue a CPU VRAM
        // write while it runs; READY must stay low until DMA releases it.
        store(32'h040000d4,32'h06000000);
        store(32'h040000d8,32'h03000000);
        store(32'h040000dc,32'h84000002);
        @(negedge clk);addr=32'h06000100;wdata=32'hdeadbeef;req=1;write=1;
        while(dut.dma_active) begin
            @(posedge clk);
            if(dut.dma_active && ready) $fatal(1,"CPU acknowledged during DMA");
            @(negedge clk);
        end
        do @(posedge clk);while(!ready);
        @(negedge clk);req=0;write=0;
        load(32'h06000000,32'h12345678);
        load(32'h06000004,32'habcdef01);
        load(32'h03000000,32'h12345678);
        load(32'h03000004,32'habcdef01);
        load(32'h06000100,32'hdeadbeef);
        // Consecutive reads must restart the RAM wait even when both
        // halfwords use the same physical word. Start at the upper lane.
        copy(32'h06000002,32'h03000010,32'h80000004);
        load(32'h03000010,32'hef011234);
        load(32'h03000014,32'h3210abcd);
        store(32'h06000200,32'h55555555);
        store(32'h06000208,32'h77777777);
        copy(32'h06000002,32'h06000202,32'h80000004);
        load(32'h06000200,32'h12345555);
        load(32'h06000204,32'habcdef01);
        load(32'h06000208,32'h77773210);
        copy(32'h06000000,32'h06000300,32'h84000003);
        load(32'h06000300,32'h12345678);
        load(32'h06000304,32'habcdef01);
        load(32'h06000308,32'h76543210);
        $display("PASS: held CPU VRAM store cannot corrupt DMA source, DMA result, or port ownership");
        $display("PASS: VRAM word/halfword DMA copies preserve changing source addresses and both lanes");
        check_palette_readback();
        // Wario's disabled HBlank callback still programs an immediate
        // 256-halfword DMA with a null source and an IWRAM destination.
        store(32'h0300322c,32'h12345678);
        store(32'h03003428,32'habcdef01);
        store(32'h0300342c,32'h76543210);
        copy(32'h00000000,32'h0300322c,32'h80000100);
        load(32'h0300322c,32'h00000000);
        load(32'h03003428,32'h00000000);
        load(32'h0300342c,32'h76543210);
        $display("PASS: Wario null-source DMA releases the CPU after 256 halfwords");
        $finish;
    end
    initial begin #100000;$fatal(1,"VRAM ownership timeout");end
endmodule
