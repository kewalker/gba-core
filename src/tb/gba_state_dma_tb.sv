`timescale 1ns/1ps
module gba_state_dma_tb;
    reg clk=0,reset=1,state_request=0,state_hold=0,state_write=0;
    reg [5:0] state_addr=0;
    reg state_shift=0,state_restore=0;
    reg [31:0] state_wdata=0;
    wire state_quiescent,state_valid;
    wire [31:0] state_rdata;
    reg cfg_req=0,cfg_write=0,vblank_trigger=0;
    reg [31:0] cfg_addr=0,cfg_wdata=0;
    wire cfg_ready,active,dma_req,dma_write;
    wire [1:0] dma_size;
    wire [31:0] dma_addr,dma_wdata;
    wire [3:0] completion_irq;
    reg [2:0] latency=0;
    wire dma_ready=dma_req && latency==4;
    wire [31:0] dma_rdata=dma_addr^32'ha5a50000;
    integer reads=0,writes3=0,writes1=0,irq3=0,irq1=0;
    reg waiting=0,held_write=0;
    reg [31:0] held_addr=0;
    reg [31:0] saved[0:33],value;
    always #5 clk=~clk;
    gba_dma dut(.clk,.reset,.cpu_lock(1'b0),.vblank_trigger,.hblank_trigger(1'b0),.fifo_request(2'd0),
        .cfg_req,.cfg_write,.cfg_addr,.cfg_wdata,.cfg_size(2'd2),.cfg_ready,
        .active,.dma_req,.dma_write,.dma_size,.dma_addr,.dma_wdata,.dma_rdata,.dma_ready,.completion_irq,
`ifdef GBK_STATE_SERIAL
        .state_shift,.state_restore,
`endif
        .state_request,.state_hold,.state_write,.state_addr,.state_wdata,.state_quiescent,.state_valid,.state_rdata);
    always @(posedge clk)begin
        if(reset || !dma_req || dma_ready)latency<=0;else latency<=latency+1'b1;
        if(reset)waiting<=0;
        else begin
            if(waiting && (!dma_req || dma_addr!==held_addr || dma_write!==held_write))
                $fatal(1,"DMA state request withdrew an outstanding descriptor");
            waiting<=dma_req && !dma_ready;held_addr<=dma_addr;held_write<=dma_write;
            if(dma_req && dma_ready)begin
                if(!dma_write)reads<=reads+1;
                else if(dma_addr>=32'h03000200 && dma_addr<32'h03000210)begin
                    if(dma_size!=2 || dma_wdata!==((32'h02000100+writes3*4)^32'ha5a50000))$fatal(1,"Draining DMA3 data mismatch");
                    writes3<=writes3+1;
                end else if(dma_addr>=32'h03000500 && dma_addr<32'h03000508)begin
                    if(dma_wdata!==((32'h02000400+writes1*4)^32'ha5a50000))$fatal(1,"Restored pending DMA1 data mismatch");
                    writes1<=writes1+1;
                end else $fatal(1,"DMA wrote unexpected destination %h",dma_addr);
            end
            if(completion_irq[3])irq3<=irq3+1;
            if(completion_irq[1])irq1<=irq1+1;
            if(state_quiescent && (dma_req || active || |completion_irq))$fatal(1,"DMA acknowledged before drain/IRQ retirement");
        end
    end
    task cfg(input [31:0] address,input [31:0] data);
        @(negedge clk);cfg_req=1;cfg_write=1;cfg_addr=address;cfg_wdata=data;
        do @(posedge clk);while(!cfg_ready);
        @(negedge clk);cfg_req=0;cfg_write=0;
    endtask
`ifdef GBK_STATE_SERIAL
    // Mirror gba_state_register_access: shift each ring exactly its width.
    function automatic integer width_of(input integer address);
        if(address<32)case(address%8)
            0,1,4:width_of=32;
            2,3:width_of=28;
            5:width_of=16;
            default:width_of=0;
        endcase
        else width_of=address==32 ? 10 : 2;
    endfunction
    task read_state(input integer address,output [31:0] data);
        @(negedge clk);state_addr=address;#1;
        if(!state_valid)$fatal(1,"DMA state read outside frozen boundary");
        data=0;
        for(integer bit_index=0;bit_index<width_of(address);bit_index=bit_index+1)begin
            data[bit_index]=state_rdata[0];
            if(state_rdata[31:1]!==0)$fatal(1,"DMA serial word drove more than bit 0");
            state_shift=1;state_restore=0;
            @(negedge clk);state_shift=0;#1;
        end
    endtask
    task write_state(input integer address,input [31:0] data);
        @(negedge clk);state_addr=address;
        for(integer bit_index=0;bit_index<width_of(address);bit_index=bit_index+1)begin
            state_wdata={31'd0,data[bit_index]};state_shift=1;state_restore=1;
            @(negedge clk);
        end
        state_shift=0;state_restore=0;
    endtask
`else
    task read_state(input integer address,output [31:0] data);
        @(negedge clk);state_addr=address;#1;
        if(!state_valid)$fatal(1,"DMA state read outside frozen boundary");
        data=state_rdata;
    endtask
    task write_state(input integer address,input [31:0] data);
        @(negedge clk);state_addr=address;state_wdata=data;state_write=1;
        @(negedge clk);state_write=0;
    endtask
`endif
    initial begin
        repeat(4)@(negedge clk);reset=0;
        cfg(32'h040000bc,32'h02000400);cfg(32'h040000c0,32'h03000500);cfg(32'h040000c4,32'hd4000002);
        cfg(32'h040000d4,32'h02000100);cfg(32'h040000d8,32'h03000200);cfg(32'h040000dc,32'hc4000004);
        wait(dma_req && !dma_write && latency==2);
        @(negedge clk);state_request=1;vblank_trigger=1;
        @(negedge clk);vblank_trigger=0;
        wait(state_quiescent);@(negedge clk);state_hold=1;
        if(writes3!=4 || writes1!=0 || irq3!=1)$fatal(1,"DMA drain truncated block or launched queued channel");
        for(integer i=0;i<34;i=i+1)read_state(i,saved[i]);
        if(saved[24]!==32'h02000110 || saved[25]!==32'h03000210 ||
            saved[28]!==32'h44000000 || saved[12]!==32'hd4000002 || saved[32]!==32'h42)
            $fatal(1,"DMA serialized state incorrectly src=%h dst=%h done=%h queued=%h pending/fifo=%h",saved[24],saved[25],saved[28],saved[12],saved[32]);
        // A capture read must leave every word exactly as it was.
        for(integer i=0;i<34;i=i+1)begin
            read_state(i,value);if(value!==saved[i])$fatal(1,"DMA state read was destructive word=%0d",i);
        end
        repeat(20)@(negedge clk);
        if(active || writes1!=0)$fatal(1,"Pending DMA progressed while frozen");
        for(integer i=0;i<34;i=i+1)write_state(i,0);
        for(integer i=0;i<34;i=i+1)write_state(i,saved[i]);
        for(integer i=0;i<34;i=i+1)begin
            read_state(i,value);if(value!==saved[i])$fatal(1,"DMA state restore mismatch word=%0d",i);
        end
        @(negedge clk);state_hold=0;state_request=0;
        wait(irq1==1);repeat(3)@(negedge clk);
        if(writes3!=4 || writes1!=2 || reads!=6 || active || irq3!=1)$fatal(1,"DMA restore/replay did not preserve exact transfers and IRQs");
        $display("PASS: DMA state drains active block, retains pending trigger, restores live/programmed/FIFO state and resumes exact transfers");$finish;
    end
    initial begin #1000000;$fatal(1,"DMA state timeout");end
endmodule
