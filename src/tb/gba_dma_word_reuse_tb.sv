`timescale 1ns/1ps
// Real DMA register programming, registered RAM and independent data oracle.
module gba_dma_word_reuse_tb;
    reg clk=0,render_clk=0,reset=1,req=0,write=0,hblank=0;
    reg state_request=0,state_hold=0;
    reg [31:0] addr=0,wdata=0;
    wire [31:0] rdata;
    wire ready,quiescent;
    always #12.5 clk=~clk;
    always #3.75 render_clk=~render_clk;
    gba_memory_map #(.RENDER_SCHEDULER(1)) dut(
        .clk,.render_clk,.reset,.req,.write,.addr,.wdata,.size(2'd2),.rdata,.ready,
        .state_dma_request(state_request),.state_hold,.state_reg_write(1'b0),
        .state_reg_addr(16'd0),.state_reg_wdata(32'd0),.state_dma_quiescent(quiescent),
        .bios_load_clk(clk),.bios_load_write(1'b0),.bios_load_addr(12'd0),.bios_load_wdata(32'd0),
        .cart_ready(1'b0),.cart_rdata(32'd0),.ewram_ready(1'b0),.ewram_rdata(32'd0),
        .controller_keys(10'h3ff));
    initial begin
        force dut.dma.hblank_trigger=hblank;
        force dut.dma.vblank_trigger=1'b0;
        force dut.dma.fifo_request=2'b0;
    end
    task store(input [31:0] a,d);
        @(negedge clk);addr=a;wdata=d;write=1;req=1;
        do @(posedge clk);while(!ready);
        @(negedge clk);req=0;write=0;
    endtask
    task load(input [31:0] a,d);
        @(negedge clk);addr=a;req=1;write=0;
        do @(posedge clk);while(!ready);
        if(rdata!==d)$fatal(1,"DMA reuse output oracle: %h got %h expected %h",a,rdata,d);
        @(negedge clk);req=0;
    endtask
    task arm(input integer ch,input [31:0] source,destination,control);
        store(32'h040000b0+ch*12,source);
        store(32'h040000b4+ch*12,destination);
        store(32'h040000b8+ch*12,control);
    endtask
    integer reads=0,writes=0,hits=0,changed=0;
    reg checking=0;
    reg [31:0] expected[0:15];
    always @(posedge clk)begin
        if(!reset && checking && dut.dma_req && dut.dma_ready_signal)begin
            if(dut.dma.channel==0 && dut.dma_write)changed=1;
            if(dut.dma.channel==3)begin
                if(!dut.dma_write)begin
                    if(dut.dma_mem_rdata!==(changed ? 32'h24682468 : 32'h13572468))
                        $fatal(1,"DMA reuse preemption oracle: stale or wrong-width read %h changed=%0d",dut.dma_mem_rdata,changed);
                    expected[reads]=changed ? 32'h24682468 : 32'h13572468;
                    reads=reads+1;
                end else writes=writes+1;
            end
        end
`ifdef GBK_DMA_WORD_REUSE
        if(!reset && dut.dma_word_hit)hits=hits+1;
`endif
    end
    task preempt(input [31:0] source,mirror,destination);
        store(source,32'h13572468);
        // Read the retained word's lower half, then overwrite its upper half
        // through a mirror. This keeps the tag live across the channel switch.
        arm(0,source,mirror+2,32'he0000001); // HBlank, IRQ, halfword
        reads=0;writes=0;changed=0;checking=1;
        arm(3,source,destination,32'hc5000010); // IRQ, fixed word source
        wait(reads==2);
        @(negedge clk);hblank=1;
        @(negedge clk);hblank=0;
        wait(!dut.dma_active);
        @(negedge clk);checking=0;
        if(reads!=16 || writes!=16 || changed!=1)$fatal(1,"DMA reuse lost preemption or transfer");
        for(integer n=0;n<16;n=n+1)load(destination+n*4,expected[n]);
        load(source,32'h24682468);
        load(32'h04000200,32'h09000000); // IF includes DMA0 and DMA3
        store(32'h04000200,32'hffff0000);
        $display("PASS: DMA reuse mirrored partial-write preemption source=%h",source);
    endtask
    initial begin
        repeat(3)@(negedge clk);reset=0;
        preempt(32'h03001000,32'h03009000,32'h06001000);
        preempt(32'h06001000,32'h06021000,32'h03003000);
        // CPU mutation between DMA bursts must not reuse the preceding word.
        store(32'h03001000,32'h98765432);
        arm(3,32'h03001000,32'h06002000,32'h85000004);
        wait(!dut.dma_active);load(32'h0600200c,32'h98765432);
        store(32'h03001000,32'habcdef01);
        arm(3,32'h03001000,32'h06002000,32'h85000004);
        wait(!dut.dma_active);load(32'h0600200c,32'habcdef01);
        // Capture requests drain an active burst; transient data must be gone
        // when state quiescence is advertised (including cancellation/resume).
        arm(3,32'h03001000,32'h06002000,32'h85000010);
        wait(dut.dma_req && !dut.dma_write);
        @(negedge clk);state_request=1;
        wait(quiescent);@(negedge clk);state_hold=1;
        repeat(2)@(negedge clk);
`ifdef GBK_DMA_WORD_REUSE
        if(dut.dma_word_valid)$fatal(1,"DMA reuse retained across state quiescence");
`endif
        state_hold=0;state_request=0;
        load(32'h0600203c,32'habcdef01);
        // Reset during an active reused read, then mutate and run a new burst.
        arm(3,32'h03001000,32'h06002000,32'h85000010);
        wait(dut.dma_req && !dut.dma_write);
        repeat(5)@(negedge clk);reset=1;
        repeat(3)@(negedge clk);reset=0;
        store(32'h03001000,32'h76543210);
        arm(3,32'h03001000,32'h06002000,32'h85000004);
        wait(!dut.dma_active);load(32'h0600200c,32'h76543210);
`ifdef GBK_DMA_WORD_REUSE
        if(hits<16)$fatal(1,"DMA reuse feature never exercised");
`endif
        $display("PASS: DMA reuse ownership, width, preemption, IRQ, CPU mutation, reset and state drain");
        $finish;
    end
    initial begin #1000000;$fatal(1,"DMA reuse regression timeout");end
endmodule
