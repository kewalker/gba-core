`timescale 1ns/1ps
module gba_audio_dma_tb;
    parameter bit FAST=0;
    parameter bit SECOND=0;
    parameter bit SOURCE_IWRAM=0;
    localparam [31:0] SOURCE_BASE=SOURCE_IWRAM ? 32'h03000000 : 32'h02000000;
    localparam integer CHANNEL=SECOND ? 2 : 1;
    localparam [31:0] FIFO_ADDR=SECOND ? 32'h040000a4 : 32'h040000a0;
    reg clk=0,reset=1,req=0,write=0,gba_tick=0;
    always #5 clk=~clk;
    always @(negedge clk)gba_tick<=~gba_tick;
    reg [31:0] addr=0,wdata=0;
    reg [1:0] size=2;
    wire [31:0] rdata;
    wire ready;
    wire signed [15:0] audio_left,audio_right;
    integer writes=0,pops=0;
    reg [2:0] throttle=0;
    always @(posedge clk) throttle<=throttle+1'b1;
    gba_memory_map #(.FAST_CPU(FAST)) dut(.clk,.reset,.gba_tick,.dma_timing_allow(!FAST || (SOURCE_IWRAM ? throttle<4 : throttle==0)),
        .render_clk(clk),.bios_load_clk(clk),.bios_load_write(1'b0),.bios_load_addr(12'd0),
        .bios_load_wdata(32'd0),.save_load_write(1'b0),.save_load_addr(15'd0),.save_load_wdata(32'd0),
        .req,.write,.addr,.wdata,.size,.rdata,.ready,.audio_left,.audio_right,
        .cart_rdata(32'd0),.cart_ready(1'b0),.ewram_ready(1'b0),.ewram_rdata(32'd0),
        .controller_keys(10'h3ff));
    task wr(input [31:0] a,d,input [1:0] s);
        @(negedge clk);req=1;write=1;addr=a;wdata=d;size=s;
        do @(posedge clk);while(!ready);
        @(negedge clk);req=0;write=0;
    endtask
    always @(posedge clk)if(!reset)begin
        if(dut.dma_req && dut.dma_write && dut.dma_ready_signal)begin
            if(dut.dma_size!==2 || dut.dma_addr!==FIFO_ADDR)$fatal(1,"Sound DMA size/destination");
            writes=writes+1;
        end
        if(dut.apu.channels[SECOND].pop)begin
            // Stream is 0,1,...,127 from EWRAM, refilled entirely by real DMA.
            #1;if(audio_left!==(SECOND ? 16'd0 : 16'((pops%128)*128)) ||
                audio_right!==(SECOND ? 16'((pops%128)*128) : 16'd0))
                $fatal(1,"DMA/timer PCM mismatch index=%0d got=%d/%d",pops,audio_left,audio_right);
            pops=pops+1;
        end
    end
    initial begin
        repeat(3)@(negedge clk);reset=0;
        for(integer i=0;i<32;i=i+1)wr(SOURCE_BASE+i*4,'h03020100+i*'h04040404,2);
        wr('h040000bc+(CHANNEL-1)*12,SOURCE_BASE,2);wr('h040000c0+(CHANNEL-1)*12,FIFO_ADDR,2);
        // Force count/type/destination stepping overrides: CNT=1, 16-bit,
        // increment destination. Sound mode must still copy four fixed words.
        wr('h040000c4+(CHANNEL-1)*12,'hb2000001,2);
        repeat(8)@(negedge clk);
        if(writes!=0)$fatal(1,"DMA launched before APU enabled");
        wr('h04000084,'h80,0);wr('h04000082,SECOND ? 'h1008 : 'h0204,1);
        repeat(200)@(negedge clk);
        if(writes!=8 || dut.apu.level[SECOND]!=32 || dut.dma.source[CHANNEL]!=SOURCE_BASE+32 ||
            dut.dma.count[CHANNEL]!=1 || !dut.dma.control[CHANNEL][15])
            $fatal(1,"DMA initial bursts writes=%0d level=%0d source=%h count=%h enabled=%b",writes,dut.apu.level[SECOND],dut.dma.source[CHANNEL],dut.dma.count[CHANNEL],dut.dma.control[CHANNEL][15]);
        // IRQ enable is clear: audio must use overflow, never timer IRQ.
        wr('h04000100,'h0080ffc0,2);
        wait(pops==96);
        wr('h04000102,0,1);
        repeat(200)@(negedge clk);
        // The game's VSync code stops and rearms DMA without rewriting SAD.
        // Leave queued tail samples in place: the next refill must wrap to
        // the programmed source, not run off into unrelated memory.
        wr('h040000c6+(CHANNEL-1)*12,'h0400,1);
        wr('h040000c6+(CHANNEL-1)*12,'hb200,1);
        wr('h04000102,'h0080,1);
        wait(pops==144);
        wr('h04000102,0,1);
        repeat(200)@(negedge clk);
        if(writes%4 || writes<24)$fatal(1,"Sound DMA burst/repeat");
        if(dut.timer_irq!=0)$fatal(1,"Unexpected timer IRQ");
        $display("PASS: %s -> DMA%0d -> FIFO -> native timer -> stereo PCM with source restart (FAST=%0d), writes=%0d samples=%0d",SOURCE_IWRAM ? "IWRAM" : "EWRAM",CHANNEL,FAST,writes,pops);
        $finish;
    end
    initial begin #300000;$fatal(1,"Audio DMA timeout");end
endmodule
