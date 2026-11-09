`timescale 1ns/1ps
module gba_hblank_display_dma_tb;
    reg clk=0,reset=1,req=0,write=0;
    reg [31:0] addr=0,wdata=0;
    wire ready;
    wire [8:0] scroll_x,scroll_y;
    always #5 clk=~clk;
    gba_memory_map #(.NATIVE_TIMING(1)) dut(.clk,.reset,.render_clk(clk),.bios_load_clk(clk),
        .req,.write,.addr,.wdata,.size(2'b10),.ready,.ppu_bg1hofs(scroll_x),.ppu_bg1vofs(scroll_y),
        .bios_load_write(1'b0),.bios_load_addr(12'd0),.bios_load_wdata(32'd0),
        .cart_ready(1'b0),.cart_rdata(32'd0),.ewram_ready(1'b0),.ewram_rdata(32'd0),.controller_keys(10'h3ff));
    task store(input [31:0] a,d);
        @(negedge clk);addr=a;wdata=d;write=1;req=1;
        do @(posedge clk);while(!ready);
        @(negedge clk);req=0;write=0;
    endtask
    initial begin
        repeat(3) @(negedge clk);reset=0;
        store(32'h03000200,32'h01230045);
        store(32'h03000204,32'h00670089);
        store(32'h040000b0,32'h03000200);
        store(32'h040000b4,32'h04000014);
        store(32'h040000b8,32'ha6400001); // word, repeat, HBlank, fixed destination
        wait(dut.dma_active);wait(!dut.dma_active);@(negedge clk);
        if(scroll_x!==9'h045 || scroll_y!==9'h123) $fatal(1,"First HBlank DMA display write lost: %h %h",scroll_x,scroll_y);
        wait(dut.dma_active);wait(!dut.dma_active);@(negedge clk);
        if(scroll_x!==9'h089 || scroll_y!==9'h067) $fatal(1,"Repeated HBlank DMA display write lost: %h %h",scroll_x,scroll_y);
        store(32'h040000b8,0);
        store(32'h040000b0,32'h03000200);
        store(32'h040000b4,32'h04000016);
        store(32'h040000b8,32'ha2400001); // halfword, upper register lane
        wait(dut.dma_active);wait(!dut.dma_active);@(negedge clk);
        if(scroll_x!==9'h089 || scroll_y!==9'h045) $fatal(1,"Halfword DMA damaged adjacent scroll register");
        store(32'h040000b8,0);
        store(32'h04000000,32'h0401);
        store(32'h04000020,32'h01000100);
        store(32'h04000024,32'hff800000);
        store(32'h04000028,32'h00000300);
        store(32'h0400002c,32'h0ffffe00);
        if(dut.ppu_bg2x!==28'h300 || dut.ppu_bg2y!==28'hffffe00) $fatal(1,"Affine reference write not reloaded");
        do @(posedge clk);while(!dut.display_hblank_edge);
        @(negedge clk);
        if(dut.ppu_bg2x!==28'h400 || dut.ppu_bg2y!==28'hffffd80) $fatal(1,"Affine scanline accumulation incorrect: %h %h",dut.ppu_bg2x,dut.ppu_bg2y);
        store(32'h04000028,32'h00000300); // same programmed value must reload
        if(dut.ppu_bg2x!==28'h300) $fatal(1,"Repeated same-value affine write failed to reload");
        do @(posedge clk);while(!dut.display_line_end);
        @(negedge clk);
        if(dut.ppu_bg2x!==28'h300) $fatal(1,"HBlank reference write was incremented again at line end");
        force dut.vcount=227;force dut.display_dot=1231;force dut.display_phase=0;
        @(posedge clk);#1;release dut.vcount;release dut.display_dot;release dut.display_phase;
        if(dut.ppu_bg2y!==28'hffffe00) $fatal(1,"Frame start failed to reload programmed affine reference");
        $display("PASS: actual repeating HBlank DMA updates both BG1 scroll halfwords on successive scanlines");$finish;
    end
    initial begin #50000;$fatal(1,"HBlank display DMA timeout");end
endmodule
