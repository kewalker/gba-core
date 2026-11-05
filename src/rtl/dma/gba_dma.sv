// Minimal GBA DMA controller. Four channels expose the standard register
// layout at 040000B0-040000DF and can copy internal memory in 16/32-bit units.
module gba_dma (
    input  logic        clk,
    input  logic        reset,
`ifdef GBK_SAVESTATE
    input wire state_request,state_hold,state_write,
    input wire [5:0] state_addr,
    input wire [31:0] state_wdata,
    output wire state_quiescent,state_valid,
    output reg [31:0] state_rdata,
`endif
    input wire cpu_lock,
    input  logic        vblank_trigger, hblank_trigger,
    input wire [1:0] fifo_request,
    input  logic        cfg_req,
    input  logic        cfg_write,
    input  logic [31:0] cfg_addr,
    input  logic [31:0] cfg_wdata,
    input  logic [1:0]  cfg_size,
    output logic [31:0] cfg_rdata,
    output logic        cfg_ready,
    output logic        active,
    output logic        dma_req,
    output logic        dma_write,
    output logic [1:0]  dma_size,
    output logic [31:0] dma_addr,
    output logic [31:0] dma_wdata,
    input  logic [31:0] dma_rdata,
    input  logic        dma_ready,
    output logic [3:0]  completion_irq,
    output logic [31:0] debug_source, debug_destination, debug_status
);
    logic [31:0] source[0:3], dest[0:3];
    // SAD is a programming latch, separate from the advancing transfer
    // address. Sound drivers stop/re-enable DMA to restart their ring buffer
    // without rewriting SAD. Repeat triggers keep the current address.
    logic [27:0] programmed_source[0:3], programmed_dest[0:3];
    logic [15:0] count[0:3], control[0:3];
    logic [1:0]  channel;
    logic [1:0]  state;
    logic [31:0] transfer_data;
    logic [15:0] reload_count[0:3];
    // Pending includes the running block and suspended blocks. Repeated
    // blanking triggers coalesce while a block is already pending/running.
    logic [3:0] pending, trigger_requests;
    logic [2:0] fifo_remaining[0:1];
    wire sound_transfer = (channel==1 || channel==2) && control[channel][13:12]==2'b11;
    wire [2:0] sound_remaining = fifo_remaining[channel[1]];
    wire [3:0] enabled = {control[3][15],control[2][15],control[1][15],control[0][15]};
    wire [3:0] eligible = (pending | trigger_requests) & enabled;
    integer triggered_channel;
    integer following_channel;
    integer i;

    localparam ST_IDLE = 2'd0, ST_READ = 2'd1, ST_WRITE = 2'd2;
`ifdef GBK_SAVESTATE
    wire state_draining=state_request===1'b1;
    wire state_frozen=state_hold===1'b1;
    // Finish the current block/burst, then stop launching queued channels.
    // Give the interrupt controller a clock to latch a completion pulse.
    assign state_quiescent=!reset && state_draining && state==ST_IDLE && completion_irq==0;
    assign state_valid=state_quiescent && state_frozen && state_addr<34;
    wire [1:0] state_channel=state_addr[4:3];
    always @*begin
        state_rdata=0;
        if(state_valid)begin
            if(state_addr<32)case(state_addr[2:0])
                0:state_rdata=source[state_channel];
                1:state_rdata=dest[state_channel];
                2:state_rdata={4'd0,programmed_source[state_channel]};
                3:state_rdata={4'd0,programmed_dest[state_channel]};
                4:state_rdata={control[state_channel],count[state_channel]};
                5:state_rdata={16'd0,reload_count[state_channel]};
                default:state_rdata=0;
            endcase
            else if(state_addr==32)state_rdata={22'd0,fifo_remaining[1],fifo_remaining[0],pending};
            else state_rdata={30'd0,channel};
        end
    end
`endif
    wire hit = (cfg_addr[31:8] == 24'h040000) &&
               (cfg_addr[15:0] >= 16'h00B0) && (cfg_addr[15:0] <= 16'h00DF);
    wire [7:0] cfg_byte_offset = cfg_addr[7:0] - 8'hB0;
    // Each channel spans three aligned words. Decode those ranges instead
    // of synthesizing byte-address division and remainder by twelve.
    wire [3:0] cfg_word_index = cfg_byte_offset[5:2];
    wire [1:0] cfg_channel = cfg_word_index >= 9 ? 2'd3 :
                            cfg_word_index >= 6 ? 2'd2 :
                            cfg_word_index >= 3 ? 2'd1 : 2'd0;
    // Subtracting 3*channel modulo four is adding channel modulo four.
    wire [1:0] cfg_local_word = cfg_byte_offset[3:2] + cfg_channel;
    wire [3:0] cfg_offset = {cfg_local_word,cfg_byte_offset[1:0]};
    wire [31:0] unit_bytes = (sound_transfer || control[channel][10]) ? 32'd4 : 32'd2;

    function automatic [15:0] merge_cfg16(
        input logic [15:0] old_value,
        input logic [31:0] write_value,
        input logic [1:0] write_size,
        input logic        high_byte
    );
        begin
            case (write_size)
                2'b00: merge_cfg16 = high_byte
                    ? {write_value[7:0], old_value[7:0]}
                    : {old_value[15:8], write_value[7:0]};
                default: merge_cfg16 = write_value[15:0];
            endcase
        end
    endfunction

    function automatic [31:0] merge_cfg32(
        input logic [31:0] old_value,write_value,
        input logic [1:0] write_size,offset
    );
        logic [31:0] mask;
        begin
            mask=write_size==0 ? (32'hff << (offset*8)) :
                 write_size==1 ? (32'hffff << (offset[1]*16)) : 32'hffffffff;
            merge_cfg32=(old_value & ~mask) |
                ((write_size==2 ? write_value : write_value << (write_size==0 ? offset*8 : offset[1]*16)) & mask);
        end
    endfunction
    wire [15:0] control_mask = cfg_channel==3 ? 16'hffe0 : 16'hf7e0;
    wire [15:0] cfg_control_value = (cfg_offset[1] ?
        merge_cfg16(control[cfg_channel],cfg_wdata,cfg_size,cfg_addr[0]) : cfg_wdata[31:16]) & control_mask;
    wire cfg_control_write = cfg_offset[1] || cfg_size==2;
    wire cfg_enable_rise = cfg_control_value[15] && !control[cfg_channel][15];
    wire cfg_word_transfer = cfg_control_value[10] ||
        ((cfg_channel==1 || cfg_channel==2) && cfg_control_value[13:12]==3);
    wire [31:0] cfg_alignment = cfg_word_transfer ? 32'hfffffffc : 32'hfffffffe;
    wire [31:0] cfg_source_mask = cfg_channel==0 ? 32'h07fffffe : 32'h0ffffffe;
    wire [31:0] cfg_dest_mask = cfg_channel==3 ? 32'h0ffffffe : 32'h07fffffe;
    wire [31:0] cfg_source_value = merge_cfg32({4'd0,programmed_source[cfg_channel]},cfg_wdata,cfg_size,cfg_offset[1:0]) & cfg_source_mask;
    wire [31:0] cfg_dest_value = merge_cfg32({4'd0,programmed_dest[cfg_channel]},cfg_wdata,cfg_size,cfg_offset[1:0]) & cfg_dest_mask;
    // DMA0..2 have 14-bit lengths; DMA3 has a 16-bit length. Zero is
    // the maximum length, represented by modular decrement rather than
    // another counter bit. Completion occurs only when the old value is 1.
    wire [15:0] count_mask = cfg_channel == 2'd3 ? 16'hffff : 16'h3fff;
    wire [15:0] cfg_count_value = merge_cfg16(reload_count[cfg_channel],
        cfg_wdata, cfg_size, cfg_addr[0]) & count_mask;

    assign active = state != ST_IDLE;
    assign cfg_ready = !cfg_req || !hit || state==ST_IDLE;
    assign dma_req = (state == ST_READ) || (state == ST_WRITE);
    assign dma_write = state == ST_WRITE;
    assign dma_size = (sound_transfer || control[channel][10]) ? 2'b10 : 2'b01;
    assign dma_addr = ((state == ST_READ) ? source[channel] : dest[channel]) &
        ((sound_transfer || control[channel][10]) ? 32'hfffffffc : 32'hfffffffe);
    assign dma_wdata = transfer_data;
    assign debug_source = source[channel];
    assign debug_destination = dest[channel];
    assign debug_status = {8'b0,count[channel],channel,state,dma_req,dma_write,2'b0};

    always_comb begin
        trigger_requests = 0;
        for (integer n=3;n>=0;n=n-1)
            if (control[n][15] &&
                ((control[n][13:12] == 2'b01 && vblank_trigger) ||
                 (control[n][13:12] == 2'b10 && hblank_trigger) ||
                 ((n==1 || n==2) && control[n][13:12]==2'b11 &&
                   ((dest[n]==32'h040000a0 && fifo_request[0] === 1'b1) ||
                    (dest[n]==32'h040000a4 && fifo_request[1] === 1'b1)))))
                trigger_requests[n] = 1'b1;
    end
    always_comb begin
        triggered_channel = -1;
        following_channel = -1;
        for (integer n=3;n>=0;n=n-1)
            if (eligible[n]) begin
                triggered_channel = n;
                if (n!=channel) following_channel = n;
            end
        // FIFO requests remain levels, sampled again after each four-word
        // burst. Do not queue a stale extra burst while that burst is busy.
    end

    always_comb begin
        cfg_rdata = 32'b0;
        if (hit) begin
            case ({cfg_offset[3:2],2'b00})
                // SAD/DAD are write-only; use the core's unmapped-read
                // fallback instead of exposing internal advancing pointers.
                // CNT_L reads zero, even while a transfer is counting down.
                4'h8: cfg_rdata = {control[cfg_channel], 16'd0};
                default: cfg_rdata = 32'b0;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            channel <= 0;
            transfer_data <= 0;
            completion_irq <= 0;
            pending<=0;
            fifo_remaining[0]<=0;fifo_remaining[1]<=0;
            for (i = 0; i < 4; i = i + 1) begin
                source[i] <= 0;
                programmed_source[i] <= 0;
                programmed_dest[i] <= 0;
                dest[i] <= 0;
                count[i] <= 0;
                control[i] <= 0;
                reload_count[i] <= 0;
            end
`ifdef GBK_SAVESTATE
        end else if(state_frozen && state_quiescent)begin
            if(state_write && state_valid)begin
                if(state_addr<32)case(state_addr[2:0])
                    0:source[state_channel]<=state_wdata;
                    1:dest[state_channel]<=state_wdata;
                    2:programmed_source[state_channel]<=state_wdata[27:0];
                    3:programmed_dest[state_channel]<=state_wdata[27:0];
                    4:begin control[state_channel]<=state_wdata[31:16];count[state_channel]<=state_wdata[15:0];end
                    5:reload_count[state_channel]<=state_wdata[15:0];
                    default:begin end
                endcase
                else if(state_addr==32)begin
                    pending<=state_wdata[3:0];fifo_remaining[0]<=state_wdata[6:4];fifo_remaining[1]<=state_wdata[9:7];
                end else channel<=state_wdata[1:0];
            end
`endif
        end else begin
            completion_irq <= 0;
            pending <= (pending | trigger_requests) & enabled;
            for (integer n=1;n<=2;n=n+1)
                if (trigger_requests[n] && !pending[n]) fifo_remaining[n-1]<=4;
            if (cfg_req && cfg_write && hit && state == ST_IDLE) begin
                // Programming latches are separate from live addresses and
                // count. Capture all three only on the Enable 0->1 edge.
                if (cfg_offset < 4) begin
                    programmed_source[cfg_channel] <= cfg_source_value[27:0];
                end else if (cfg_offset < 8) begin
                    programmed_dest[cfg_channel] <= cfg_dest_value[27:0];
                end else begin
                    if(!cfg_offset[1]) reload_count[cfg_channel] <= cfg_count_value;
                    if(cfg_control_write) begin
                        control[cfg_channel] <= cfg_control_value;
                        if(!cfg_control_value[15]) pending[cfg_channel]<=0;
                        if(cfg_enable_rise) begin
                            source[cfg_channel] <= {4'd0,programmed_source[cfg_channel]} & cfg_alignment;
                            dest[cfg_channel] <= {4'd0,programmed_dest[cfg_channel]} & cfg_alignment;
                            count[cfg_channel] <= cfg_offset[1] ? reload_count[cfg_channel] : cfg_count_value;
                            if(cfg_control_value[13:12]==0) begin
                                channel <= triggered_channel>=0 && triggered_channel<cfg_channel ? triggered_channel[1:0] : cfg_channel;
                                pending[cfg_channel]<=1;
`ifdef GBK_SAVESTATE
                                if(!state_draining)
`endif
                                state <= ST_READ;
                            end
                        end
                    end
                end
            end else if (state == ST_READ && dma_ready) begin
                pending[channel] <= 1;
                transfer_data <= dma_size == 2'b01 ? (dma_rdata & 32'h0000ffff) : dma_rdata;
                state <= ST_WRITE;
            end else if (state == ST_WRITE && dma_ready) begin
                // CNT_H[8:7] controls source stepping. In particular, BIOS
                // boot uses 8500h (32-bit, fixed source) to fill VRAM from
                // one word; incrementing here turns the fill into stray reads.
                case (control[channel][8:7])
                    2'b01: source[channel] <= source[channel] - unit_bytes;
                    2'b10: source[channel] <= source[channel];
                    default: source[channel] <= source[channel] + unit_bytes;
                endcase
                // CNT_H[6:5] controls destination stepping. Mode 3 increments
                // during a transfer; reload applies only to repeated DMA.
                if(!sound_transfer) case (control[channel][6:5])
                    2'b01: dest[channel] <= dest[channel] - unit_bytes;
                    2'b10: dest[channel] <= dest[channel];
                    default: dest[channel] <= dest[channel] + unit_bytes;
                endcase
                if(sound_transfer) begin
                    if(sound_remaining==1) begin
                        completion_irq[channel] <= control[channel][14];
                        if(!control[channel][9]) control[channel][15]<=0;
                        pending[channel]<=0;
                        fifo_remaining[channel[1]]<=0;
                        if(following_channel>=0
`ifdef GBK_SAVESTATE
                            && !state_draining
`endif
                        ) begin
                            channel<=following_channel[1:0];state<=ST_READ;
                        end else state<=ST_IDLE;
                    end else begin
                        fifo_remaining[channel[1]]<=sound_remaining-1'b1;
                        if(triggered_channel>=0 && triggered_channel<channel
`ifdef GBK_SAVESTATE
                            && !state_draining
`endif
                        ) channel<=triggered_channel[1:0];
                        state<=ST_READ;
                    end
                end else if (count[channel] == 16'd1) begin
                    completion_irq[channel] <= control[channel][14];
                    count[channel] <= 0;
                    if (control[channel][9] && control[channel][13:12] != 0) begin
                        count[channel] <= reload_count[channel];
                        if (control[channel][6:5] == 2'b11)
                            dest[channel] <= {4'd0,programmed_dest[channel]} &
                                (control[channel][10] ? 32'hfffffffc : 32'hfffffffe);
                    end else control[channel][15] <= 1'b0;
                    pending[channel]<=0;
                    if(following_channel>=0
`ifdef GBK_SAVESTATE
                        && !state_draining
`endif
                    ) begin
                        channel<=following_channel[1:0];state<=ST_READ;
                    end else state<=ST_IDLE;
                end else begin
                    count[channel] <= (count[channel] - 16'd1) &
                        (channel == 2'd3 ? 16'hffff : 16'h3fff);
                    // Preempt only after the destination accepted this unit.
                    // A completed write retires the old memory transaction,
                    // just as it does before the next unit of the same DMA.
                    // Keep the bus owned without adding an arbitration bubble.
                    if(triggered_channel>=0 && triggered_channel<channel
`ifdef GBK_SAVESTATE
                        && !state_draining
`endif
                    ) channel<=triggered_channel[1:0];
                    state <= ST_READ;
                end
            end else if (state == ST_IDLE) begin
                if (triggered_channel >= 0 && cpu_lock!==1'b1
`ifdef GBK_SAVESTATE
                    && !state_draining
`endif
                ) begin
                    channel <= triggered_channel[1:0];
                    state <= ST_READ;
                end else state<=ST_IDLE;
            end
        end
    end
endmodule
