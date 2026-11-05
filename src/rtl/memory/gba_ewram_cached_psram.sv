// Coherent write-through cache shared by CPU and DMA accesses.
// Stores acknowledge only after the physical backend completes.
module gba_ewram_cached_psram #(parameter CACHE_WORDS=64,parameter bit SLOW_CLOCK=0,
    parameter bit SDRAM_BACKEND=0,BURST_FILL=0)(
`ifdef GBK_SAVESTATE
    output wire state_idle,
`endif
    input wire clk,reset,req,write,
    input wire [31:0] addr,wdata,
    input wire [1:0] size,
    output wire [31:0] rdata,
    output wire ready,
    output wire [21:16] cram_a,
    inout wire [15:0] cram_dq,
    input wire cram_wait,
    output wire cram_clk,cram_adv_n,cram_cre,cram_ce0_n,cram_ce1_n,
    output wire cram_oe_n,cram_we_n,cram_ub_n,cram_lb_n,
    output wire memory_req,memory_write,output wire [31:0] memory_addr,memory_wdata,
    output wire [1:0] memory_size,input wire [31:0] memory_rdata,input wire memory_ready,
    input wire [63:0] memory_line_data
);
    localparam INDEX_BITS=$clog2(CACHE_WORDS), TAG_BITS=16-INDEX_BITS;
    // Only complete physical words are cached. Mirrors share the same tag.
    // Keep this small flow-through store out of the block-RAM budget.
    initial begin
        if(CACHE_WORDS < 2 || CACHE_WORDS > 65536 || (CACHE_WORDS & (CACHE_WORDS-1)) != 0)
            $error("EWRAM cache capacity must be a power of two from 2 to 65536");
    end
    localparam IDLE=0,WAIT_BACKEND=1,ACK=2;
    reg [1:0] state;
    reg [CACHE_WORDS-1:0] valid;

    (* ramstyle="MLAB, no_rw_check" *) reg [TAG_BITS-1:0] tags[0:CACHE_WORDS-1];
    wire [INDEX_BITS-1:0] index=addr[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0] tag=addr[17:INDEX_BITS+2];
    wire hit=valid[index] && tags[index]==tag;
    reg [31:0] held_addr,held_wdata;

    reg [1:0] held_size;
    reg held_write,held_hit;
    reg sibling_pending;
    // Neighbor admission is a locality hint, never an architectural response.
    // Writes leave the previous read in place for read/update object loops.
    reg [15:0] previous_read_word;
    reg previous_read_valid,held_stream_read;
    wire adjacent_read=previous_read_valid &&
        (addr[17:2]==previous_read_word+16'd1 || addr[17:2]==previous_read_word-16'd1);

`ifdef GBK_SAVESTATE
    assign state_idle=state==IDLE && !req && !sibling_pending;
`endif
    reg [31:0] sibling_data;
    wire [INDEX_BITS-1:0] held_index=held_addr[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0] held_tag=held_addr[17:INDEX_BITS+2];
    wire backend_req=(state==IDLE && req && (write || !hit)) || state==WAIT_BACKEND;
    wire [31:0] psram_rdata;
    wire psram_ready;
    wire [31:0] backend_rdata=SDRAM_BACKEND ? memory_rdata : psram_rdata;
    wire backend_ready=SDRAM_BACKEND ? memory_ready : psram_ready;
    assign memory_req=SDRAM_BACKEND && backend_req;
    assign memory_write=state==IDLE ? write : held_write;
    assign memory_addr=state==IDLE ? addr : held_addr;
    assign memory_wdata=state==IDLE ? wdata : held_wdata;
    assign memory_size=state==IDLE ? size : held_size;
    reg hit_ready;

    // Physical completion is already registered. Forward it on the same
    // consuming edge as the original backend; do not add a cache wrapper
    // cycle to misses or write-through stores.
    assign ready=hit_ready || (state==WAIT_BACKEND && backend_ready);
    assign rdata=state==WAIT_BACKEND ? backend_rdata : cache_read_data;
    // Preserve pin-traffic observation points used by the shared fixtures.
    // synthesis translate_off
    wire ps_read=backend.ps_read, ps_write=backend.ps_write;
    // synthesis translate_on
    gba_ewram_psram #(.SLOW_CLOCK(SLOW_CLOCK)) backend(
        .clk,.reset,.req(SDRAM_BACKEND ? 1'b0 : backend_req),.write(state==IDLE ? write : held_write),
        .addr(state==IDLE ? addr : held_addr),.wdata(state==IDLE ? wdata : held_wdata),
        .size(state==IDLE ? size : held_size),.rdata(psram_rdata),.ready(psram_ready),
        .cram_a,.cram_dq,.cram_wait,.cram_clk,.cram_adv_n,.cram_cre,.cram_ce0_n,.cram_ce1_n,
        .cram_oe_n,.cram_we_n,.cram_ub_n,.cram_lb_n);
    // The synchronous read samples the request on the existing hit-accept
    // edge. hit_ready and RAM data become valid together; no cycle is added.
    wire [INDEX_BITS-1:0] cache_read_index=state==IDLE ? index : held_index;
    wire backend_complete=state==WAIT_BACKEND && backend_ready;
    wire neighbor_write=state==ACK && sibling_pending;
    wire data_write=!reset && (neighbor_write ||
        (backend_complete && (!held_write || held_size==2 || held_hit)));
    wire [INDEX_BITS-1:0] data_write_index=neighbor_write ?
        held_index ^ {{(INDEX_BITS-1){1'b0}},1'b1} : held_index;
    reg [31:0] partial_write_data;
    always @* begin
        if(held_size==1)
            partial_write_data=held_addr[1] ? {held_wdata[15:0],cache_read_data[15:0]} :
                {cache_read_data[31:16],held_wdata[15:0]};
        else case(held_addr[1:0])
            0:partial_write_data={cache_read_data[31:8],held_wdata[7:0]};
            1:partial_write_data={cache_read_data[31:16],held_wdata[7:0],cache_read_data[7:0]};
            2:partial_write_data={cache_read_data[31:24],held_wdata[7:0],cache_read_data[15:0]};
            3:partial_write_data={held_wdata[7:0],cache_read_data[23:0]};
        endcase
    end
    wire [31:0] data_write_word=neighbor_write ? sibling_data : !held_write ? backend_rdata :
        held_size==2 ? held_wdata : partial_write_data;
    wire [31:0] cache_read_data;
`ifdef GBK_SIM
`ifndef GBK_REAL_EWRAM_CACHE_RAM
`define GBK_EWRAM_CACHE_ARRAY_MODEL
`endif
`endif
`ifdef GBK_EWRAM_CACHE_ARRAY_MODEL
    reg [31:0] block_data[0:CACHE_WORDS-1];
    reg [31:0] block_q;
    assign cache_read_data=block_q;
    always @(posedge clk) begin
        if(data_write)block_data[data_write_index]<=data_write_word;
        block_q<=block_data[cache_read_index];
    end
`undef GBK_EWRAM_CACHE_ARRAY_MODEL
`else
    altsyncram cache_data_ram(
        .clock0(clk),.clock1(1'b1),.address_a(data_write_index),.address_b(cache_read_index),
        .data_a(data_write_word),.data_b(32'd0),.wren_a(data_write),.wren_b(1'b0),
        .q_a(),.q_b(cache_read_data),.aclr0(1'b0),.aclr1(1'b0),
        .addressstall_a(1'b0),.addressstall_b(1'b0),.byteena_a(1'b1),.byteena_b(1'b1),
        .clocken0(1'b1),.clocken1(1'b1),.clocken2(1'b1),.clocken3(1'b1),
        .rden_a(1'b1),.rden_b(1'b1),.eccstatus());
    defparam cache_data_ram.operation_mode="DUAL_PORT";
    defparam cache_data_ram.lpm_type="altsyncram";
    defparam cache_data_ram.intended_device_family="Cyclone V";
    defparam cache_data_ram.ram_block_type="M10K";
    defparam cache_data_ram.numwords_a=CACHE_WORDS,cache_data_ram.numwords_b=CACHE_WORDS;
    defparam cache_data_ram.widthad_a=INDEX_BITS,cache_data_ram.widthad_b=INDEX_BITS;
    defparam cache_data_ram.width_a=32,cache_data_ram.width_b=32;
    defparam cache_data_ram.width_byteena_a=1,cache_data_ram.width_byteena_b=1;
    defparam cache_data_ram.address_reg_b="CLOCK0",cache_data_ram.outdata_reg_b="UNREGISTERED";
    defparam cache_data_ram.read_during_write_mode_mixed_ports="DONT_CARE";
`endif
    always @(posedge clk) begin
        hit_ready<=0;
        if(reset) begin
            valid<=0;state<=IDLE;
            held_addr<=0;held_wdata<=0;held_size<=0;held_write<=0;held_hit<=0;
            sibling_pending<=0;sibling_data<=0;
            previous_read_word<=0;previous_read_valid<=0;held_stream_read<=0;
        end else case(state)
            IDLE: if(req) begin
                if(BURST_FILL && !write)begin previous_read_word<=addr[17:2];previous_read_valid<=1;end
                if(!write && hit) begin hit_ready<=1;state<=ACK;end
                else begin
                    held_addr<=addr;held_wdata<=wdata;held_size<=size;

                    held_stream_read<=adjacent_read;
                    held_write<=write;held_hit<=hit;state<=WAIT_BACKEND;
                end
            end
            WAIT_BACKEND: if(backend_ready) begin
                sibling_pending<=SDRAM_BACKEND && BURST_FILL && !held_write && held_stream_read;
                sibling_data<=held_addr[2] ? memory_line_data[31:0] : memory_line_data[63:32];

                if(!held_write || held_size==2) begin
                    tags[held_index]<=held_tag;valid[held_index]<=1;
                end
                state<=ACK;
            end
            ACK: begin
                // Reuse the existing acknowledgement bubble for the second
                // cache write. No new request can be accepted before IDLE;
                // CPU and DMA therefore observe both fills in bus order.
                if(sibling_pending) begin

                    tags[held_index ^ {{(INDEX_BITS-1){1'b0}},1'b1}]<=held_tag;
                    valid[held_index ^ {{(INDEX_BITS-1){1'b0}},1'b1}]<=1;
                end
                sibling_pending<=0;state<=IDLE;
            end
            default: state<=IDLE;
        endcase
    end
endmodule

