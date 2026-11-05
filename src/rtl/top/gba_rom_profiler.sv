// Passive counters. A held-data mailbox transfers memory-clock counters;
// nothing from this module feeds request, ready, reset or clock enables.
module gba_rom_profiler #(parameter integer PHYSICAL_READ_UNITS=1)(
    input wire cpu_clk,memory_clk,reset,
    input wire request_event,retained_event,cache_hit_event,miss_event,
    input wire stream_miss_event,pair_event,lookup_wait,miss_wait,
    input wire physical_read,physical_active,
    output wire [319:0] profile
);
    reg [31:0] requests,retained_hits,cache_hits,misses,stream_misses,pairs;
    reg [31:0] lookup_clocks,miss_clocks;
    reg [31:0] memory_reads,memory_active;
    reg [63:0] held_memory;
    reg request_toggle,ack_toggle;
    (* ASYNC_REG="TRUE" *) reg [1:0] request_sync;
    reg request_seen;
    (* ASYNC_REG="TRUE" *) reg [2:0] ack_sync;
    reg ack_seen;
    reg [63:0] data_sync1,data_sync2,memory_snapshot;
    reg [9:0] refresh_timer;
    assign profile={requests,retained_hits,cache_hits,misses,stream_misses,pairs,
                    lookup_clocks,miss_clocks,memory_snapshot};
    always @(posedge memory_clk) begin
        if(reset) begin
            memory_reads<=0;memory_active<=0;held_memory<=0;
            request_sync<=0;request_seen<=0;ack_toggle<=0;
        end else begin
            if(physical_read) memory_reads<=memory_reads+PHYSICAL_READ_UNITS;
            if(physical_active) memory_active<=memory_active+1'b1;
            request_sync<={request_sync[0],request_toggle};
            if(request_sync[1]!=request_seen) begin
                held_memory<={memory_reads,memory_active};
                request_seen<=request_sync[1];ack_toggle<=request_sync[1];
            end
        end
    end
    always @(posedge cpu_clk) begin
        if(reset) begin
            requests<=0;retained_hits<=0;cache_hits<=0;misses<=0;
            stream_misses<=0;pairs<=0;lookup_clocks<=0;miss_clocks<=0;
            request_toggle<=0;ack_sync<=0;ack_seen<=0;
            data_sync1<=0;data_sync2<=0;memory_snapshot<=0;refresh_timer<=0;
        end else begin
            if(request_event) requests<=requests+1'b1;
            if(retained_event) retained_hits<=retained_hits+1'b1;
            if(cache_hit_event) cache_hits<=cache_hits+1'b1;
            if(miss_event) misses<=misses+1'b1;
            if(stream_miss_event) stream_misses<=stream_misses+1'b1;
            if(pair_event) pairs<=pairs+1'b1;
            if(lookup_wait) lookup_clocks<=lookup_clocks+1'b1;
            if(miss_wait) miss_clocks<=miss_clocks+1'b1;
            ack_sync<={ack_sync[1:0],ack_toggle};
            data_sync1<=held_memory;data_sync2<=data_sync1;
            if(ack_sync[2]!=ack_seen) begin
                memory_snapshot<=data_sync2;ack_seen<=ack_sync[2];
            end
            refresh_timer<=refresh_timer+1'b1;
            // One refresh per 1024 CPU clocks (~25.64 us). The memory
            // snapshot is held until the next request, far beyond settling.
            if(refresh_timer==0 && request_toggle==ack_sync[2])
                request_toggle<=~request_toggle;
        end
    end
endmodule
