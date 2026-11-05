// GBA cartridge image backed by one Pocket CRAM chip (both dies).
// The APF data-slot loader writes in the 74 MHz bridge clock domain. CPU
// requests are crossed from the emulator clock with a toggle handshake so a
// PSRAM wait state never becomes a fixed-latency CPU assumption.
module gba_cartridge_psram #(
    parameter bit ENABLE_WORD_CACHE=1'b1,
    parameter integer CACHE_WORDS=256,
    parameter bit BYPASS_STREAM_FILLS=1'b1,
    parameter bit PAIR_READS=1'b0,
    parameter bit PROFILE_ROM=1'b0,
    parameter bit FAST_READ_ISSUE=1'b0,
    parameter integer READ_WAIT_CYCLES=4,
    parameter bit SDRAM_BACKEND=0,
    parameter bit SDRAM_DIRECT_BURST=0,
    parameter bit SDRAM_FILL_NEIGHBOR=0
) (
`ifdef GBK_SAVESTATE
    output wire state_cpu_idle,state_memory_idle,
`endif
    input  logic        load_clk,
    input  logic        reset,
    input  logic        load_write,
    input  logic [22:0] load_addr,
    input  logic [31:0] load_wdata,
    input  logic        cpu_clk,
    input  logic        cpu_req,
    input  logic [31:0] cpu_addr,
    input  wire         cpu_streaming,
    input wire profile_reset,
    output wire [319:0] debug_profile,
    output logic [31:0] cpu_rdata,
    output wire cpu_ready,
    output logic [21:16] cram_a,
    inout  wire  [15:0] cram_dq,
    input  wire         cram_wait,
    output logic        cram_clk,
    output logic        cram_adv_n,
    output logic        cram_cre,
    output logic        cram_ce0_n,
    output logic        cram_ce1_n,
    output logic        cram_oe_n,
    output logic        cram_we_n,
    output logic        cram_ub_n,
    output logic        cram_lb_n,
    output wire memory_valid,input wire memory_ready,output wire memory_write,
    output wire [24:0] memory_addr,output wire [31:0] memory_wdata,
    output wire [3:0] memory_byteena,input wire response_valid,
    output wire response_ready,input wire [63:0] response_data
);
`ifdef GBK_FAST_FORWARD
    // Complete once on the acceptance edge; held requests cannot re-ACK.
    wire retained_fast_ready=!reset && accepted_request && retained_match;
    assign cpu_ready=cpu_ready_reg || retained_fast_ready;
`else
    assign cpu_ready=cpu_ready_reg;
`endif
    logic cpu_ready_reg;
    localparam integer ROM_WORD_BITS=SDRAM_BACKEND ? 23 : 22;
    logic psram_write, psram_read, psram_busy, psram_valid;
    logic [1:0] psram_bank;
    logic [21:0] psram_addr;
    logic [15:0] psram_wdata, psram_rdata;
    wire physical_busy,physical_valid;
    wire [15:0] physical_rdata;
    wire sdram_busy,sdram_valid,sdram_physical_read,sdram_physical_active;
    wire [15:0] sdram_rdata;
    wire [63:0] sdram_line_data;
    assign psram_busy=SDRAM_BACKEND ? sdram_busy : physical_busy;
    assign psram_valid=SDRAM_BACKEND ? sdram_valid : physical_valid;
    assign psram_rdata=SDRAM_BACKEND ? sdram_rdata : physical_rdata;
    // APF bridge writes are much slower than the PSRAM clock on average, but
    // can arrive in short consecutive bursts.  Queue them instead of only
    // accepting a word while the two-halfword PSRAM writer is idle.
    localparam integer LOAD_FIFO_DEPTH = 64;
    // Shallow loader queues fit flow-through MLABs; reserve M10Ks for ROM.
    (* ramstyle="MLAB, no_rw_check" *) logic [22:0] load_fifo_addr [0:LOAD_FIFO_DEPTH-1];
    (* ramstyle="MLAB, no_rw_check" *) logic [31:0] load_fifo_data [0:LOAD_FIFO_DEPTH-1];
    logic [5:0]  load_fifo_write_ptr, load_fifo_read_ptr;
    logic [6:0]  load_fifo_count;
    wire         load_fifo_full = (load_fifo_count == LOAD_FIFO_DEPTH);
    logic load_inflight, load_half, load_issued, load_busy_seen;
    logic [22:0] load_word_addr;
    logic [31:0] load_word_data;
    logic read_inflight, read_issued;
    logic [1:0] pair_half;
    logic [1:0] pair_last;
    logic [ROM_WORD_BITS:0] read_half_addr;

    logic req_toggle;
    logic [ROM_WORD_BITS+1:2] req_addr_hold;
    logic req_pair_hold,req_pair_sync1,req_pair_sync2;
    logic request_history_valid;
    logic [2:0] sequential_run;
    logic req_seen_cpu;
    logic resp_toggle_mem;
    logic [15:0] resp_low_mem, resp_high_mem;
    logic [15:0] resp_pair_low_mem,resp_pair_high_mem;
    logic resp_sync1, resp_sync2, resp_sync3, resp_seen_cpu;
    logic [15:0] resp_low_sync1, resp_low_sync2;
    logic [15:0] resp_high_sync1, resp_high_sync2;
    logic [15:0] resp_pair_low_sync1,resp_pair_low_sync2;
    logic [15:0] resp_pair_high_sync1,resp_pair_high_sync2;
    logic req_sync1, req_sync2, req_sync3, req_seen_mem;
    logic [ROM_WORD_BITS+1:2] req_addr_sync1, req_addr_sync2;
    logic cpu_waiting;
    logic allocate_request;
    logic image_epoch,epoch_sync1,epoch_sync2,epoch_seen,accepted_epoch;
    logic cached_word_valid;
    // Retain hot ROM code across branches and data reads. Synchronous lookup
    // allows the tag/data arrays to use block RAM rather than a large mux.
    localparam CACHE_BITS = CACHE_WORDS > 1 ? $clog2(CACHE_WORDS) : 1;
    localparam PAIR_MODE=PAIR_READS && CACHE_WORDS>1;
    localparam LINE_WORDS=PAIR_MODE ? 2 : 1;
    // Store only the tag bits above the index. At 2048 words this keeps
    // 8 KiB of data plus tags within nine M10Ks.
    localparam VALID_GROUPS=(CACHE_WORDS+31)/32;
    localparam VALID_GROUP_BITS=VALID_GROUPS>1 ? $clog2(VALID_GROUPS) : 1;
    // Pack validity into flow-through RAM words instead of a large resettable
    // register bank and decoder. Clear serially while reads bypass the cache.
    (* ramstyle="MLAB, no_rw_check" *) reg [31:0] cache_valid_words[0:VALID_GROUPS-1];
    reg cache_clearing;
    reg [VALID_GROUP_BITS-1:0] clear_group;
    reg [31:0] cache_lookup_valid_word,accepted_valid_word;
    reg accepted_cache_ready;
    wire [31:0] lookup_valid_bits=cache_valid_words[lookup_index >> 5];
    // Retain an independent tag per word: unrelated words in adjacent
    // indices must coexist exactly as in the single-word cache.
    localparam ENTRY_BITS=32+ROM_WORD_BITS-CACHE_BITS;
    (* ramstyle="M10K, no_rw_check" *) reg [ENTRY_BITS*LINE_WORDS-1:0] cache_words[0:CACHE_WORDS/LINE_WORDS-1];
    reg [ENTRY_BITS*LINE_WORDS-1:0] cache_lookup,accepted_line_data;
    wire [ENTRY_BITS-33:0] lookup_tag;
    wire [31:0] lookup_data;
    generate if(PAIR_MODE) begin : paired_cache
        assign lookup_tag=req_addr_hold[2] ? cache_lookup[ENTRY_BITS+32+:ENTRY_BITS-32] : cache_lookup[32+:ENTRY_BITS-32];
        assign lookup_data=req_addr_hold[2] ? cache_lookup[ENTRY_BITS+:32] : cache_lookup[31:0];
        always_ff @(posedge cpu_clk)
            if(resp_sync3!=resp_seen_cpu && allocate_request)
                cache_words[fill_index >> 1]<={
                    (req_pair_hold || req_addr_hold[2] ? {req_addr_hold[ROM_WORD_BITS+1:2+CACHE_BITS],resp_pair_high_sync2,resp_pair_low_sync2} : accepted_line_data[ENTRY_BITS+:ENTRY_BITS]),
                    (req_pair_hold || !req_addr_hold[2] ? {req_addr_hold[ROM_WORD_BITS+1:2+CACHE_BITS],resp_high_sync2,resp_low_sync2} : accepted_line_data[0+:ENTRY_BITS])};
    end else begin : single_cache
        assign lookup_tag=cache_lookup[32+:ENTRY_BITS-32];
        assign lookup_data=cache_lookup[31:0];
        always_ff @(posedge cpu_clk)
            if(resp_sync3!=resp_seen_cpu && allocate_request)
                cache_words[fill_index]<={req_addr_hold[ROM_WORD_BITS+1:2+CACHE_BITS],resp_high_sync2,resp_low_sync2};
    end endgenerate
    reg cache_lookup_valid,cache_pending;
`ifdef GBK_SAVESTATE
    assign state_cpu_idle=!cpu_waiting && !cache_pending && !cpu_req && !cache_clearing &&
        resp_sync3==resp_seen_cpu;
    assign state_memory_idle=load_fifo_count==0 && !load_write && !load_inflight &&
        !read_inflight && !psram_busy && !psram_write && !psram_read && req_sync3==req_seen_mem;
`endif
`ifdef GBK_ROM_CACHE_HASH
    // Fold the physical tag into the index without changing bit zero: paired
    // burst neighbours must remain adjacent. With a known tag the XOR mapping
    // is invertible, so the existing full tag comparison still identifies a
    // unique physical word. Capacity, response edges and CDC are unchanged.
    function automatic [CACHE_BITS-1:0] cache_index(input [ROM_WORD_BITS+1:0] address);
        integer bit_index;
        begin
            cache_index=CACHE_WORDS>1 ? address[2+:CACHE_BITS] : 0;
            if(CACHE_BITS>1) begin
                for(bit_index=CACHE_BITS+2;bit_index<ROM_WORD_BITS+2;bit_index=bit_index+1)
                    cache_index[CACHE_BITS-1-((bit_index-CACHE_BITS-2)%(CACHE_BITS-1))]=
                        cache_index[CACHE_BITS-1-((bit_index-CACHE_BITS-2)%(CACHE_BITS-1))]^address[bit_index];
            end
        end
    endfunction
    wire [CACHE_BITS-1:0] lookup_index=cache_index(cpu_addr[ROM_WORD_BITS+1:0]);
    wire [CACHE_BITS-1:0] fill_index=cache_index({req_addr_hold,2'b00});
`else
    wire [CACHE_BITS-1:0] lookup_index = CACHE_WORDS > 1 ? cpu_addr[2+:CACHE_BITS] : 0;
    wire [CACHE_BITS-1:0] fill_index = CACHE_WORDS > 1 ? req_addr_hold[2+:CACHE_BITS] : 0;
`endif
    wire accepted_request=cpu_req && (!req_seen_cpu || cpu_addr[ROM_WORD_BITS+1:2]!=req_addr_hold) && !cpu_waiting;
    wire retained_match=ENABLE_WORD_CACHE && cached_word_valid && cpu_addr[ROM_WORD_BITS+1:2]==req_addr_hold && epoch_sync2==epoch_seen;
    wire cache_match=ENABLE_WORD_CACHE && cache_lookup_valid && lookup_tag==req_addr_hold[ROM_WORD_BITS+1:2+CACHE_BITS] &&
        accepted_cache_ready && !cache_clearing && accepted_epoch==epoch_seen && epoch_sync2==epoch_seen;
    wire profile_miss=(cache_pending && !cache_match) ||
        (accepted_request && !retained_match && !(ENABLE_WORD_CACHE && CACHE_WORDS>1));
    generate if(PROFILE_ROM) begin : rom_profiling
        reg streaming_request;
        always @(posedge cpu_clk)
            if(reset || profile_reset) streaming_request<=0;
            else if(accepted_request) streaming_request<=cpu_streaming;
        gba_rom_profiler #(.PHYSICAL_READ_UNITS(SDRAM_BACKEND ? 4 : 1)) monitor(.cpu_clk,.memory_clk(load_clk),.reset(reset || profile_reset),
            .request_event(accepted_request),.retained_event(accepted_request && retained_match),
            .cache_hit_event(cache_pending && cache_match),.miss_event(profile_miss),
            .stream_miss_event(profile_miss && (cache_pending ? streaming_request : cpu_streaming)),
            .pair_event(profile_miss && req_pair_hold && !(cache_pending && cache_lookup_valid_word[(fill_index & 31)^1])),
            .lookup_wait(cache_pending),.miss_wait(cpu_waiting && !cache_pending),
            .physical_read(SDRAM_BACKEND ? sdram_physical_read : psram_read),
            .physical_active(SDRAM_BACKEND ? sdram_physical_active : read_inflight),.profile(debug_profile));
    end else begin : no_rom_profiling
        assign debug_profile=0;
    end endgenerate
    always_ff @(posedge cpu_clk) begin
        cache_lookup <= cache_words[lookup_index >> PAIR_MODE];
        cache_lookup_valid_word <= lookup_valid_bits;
        cache_lookup_valid <= !cache_clearing && lookup_valid_bits[lookup_index & 31];
    end
    always_ff @(posedge cpu_clk) begin
        if(reset || epoch_sync2!=epoch_seen) begin
            cache_clearing<=1;
            clear_group<=0;
        end else if(cache_clearing) begin
            cache_valid_words[clear_group]<=0;
            if(clear_group==VALID_GROUPS-1) cache_clearing<=0;
            else clear_group<=clear_group+1'b1;
        end else if(ENABLE_WORD_CACHE && CACHE_WORDS>1 && resp_sync3!=resp_seen_cpu && allocate_request &&
                    accepted_cache_ready && accepted_epoch==epoch_seen) begin
            // Only one miss can be outstanding. The lookup's whole validity
            // word stays current until this fill; preserve its other entries.
            cache_valid_words[fill_index >> 5]<=accepted_valid_word |
                ((req_pair_hold ? 32'd3 : 32'd1) << (req_pair_hold ? (fill_index & 30) : (fill_index & 31)));
        end
    end
    // A new image begins at loader word zero. Cross that event separately
    // from the read mailbox, so a retained ROM word cannot survive a reload.
    always_ff @(posedge load_clk) begin
        if(reset) image_epoch<=0;
        else if(load_write && load_addr==0) image_epoch<=~image_epoch;
    end

    // Select ROM read timing independently; loader writes retain defaults.
    pocket_psram #(.READ_WAIT_CYCLES(READ_WAIT_CYCLES),.FAST_READ_PINS(1)) psram (
        .clk(load_clk), .reset(reset),
        .bank(psram_bank[0]), .addr(psram_addr),
        .write_en(SDRAM_BACKEND ? 1'b0 : psram_write), .write_data(psram_wdata),
        .write_high(1'b1), .write_low(1'b1),
        .read_en(SDRAM_BACKEND ? 1'b0 : psram_read), .busy(physical_busy),
        .read_valid(physical_valid), .read_data(physical_rdata),
        .cram_a, .cram_dq, .cram_wait,
        .cram_clk, .cram_adv_n, .cram_cre,
        .cram_ce0_n, .cram_ce1_n, .cram_oe_n, .cram_we_n,
        .cram_ub_n, .cram_lb_n
    );

    generate if(SDRAM_BACKEND) begin : sdram_service
        gba_sdram_rom_adapter adapter(.clk(load_clk),.reset,.bank(psram_bank),.addr(psram_addr),
            .write_en(psram_write),.read_en(psram_read),.write_data(psram_wdata),
            .write_high(1'b1),.write_low(1'b1),.busy(sdram_busy),.read_valid(sdram_valid),.read_data(sdram_rdata),
            .read_line_data(sdram_line_data),
            .memory_valid,.memory_ready,.memory_write,.memory_addr,.memory_wdata,.memory_byteena,
            .response_valid,.response_ready,.response_data,
            .physical_read(sdram_physical_read),.physical_active(sdram_physical_active));
    end else begin : no_sdram_service
        assign {memory_valid,memory_write,response_ready,sdram_busy,sdram_valid,sdram_physical_read,sdram_physical_active}=0;
        assign memory_addr=0;assign memory_wdata=0;assign memory_byteena=0;assign sdram_rdata=0;
        assign sdram_line_data=0;
    end endgenerate

`ifdef GBK_SIM
    logic [31:0] sim_rom [0:65535];
`endif

    // Bridge-domain loader and PSRAM request scheduler.
    always_ff @(posedge load_clk) begin
        if (reset) begin
            psram_write <= 1'b0;
            psram_read <= 1'b0;
            psram_bank <= 1'b0;
            load_fifo_write_ptr <= 0;
            load_fifo_read_ptr <= 0;
            load_fifo_count <= 0;
            load_inflight <= 1'b0;
            load_half <= 1'b0;
            load_issued <= 1'b0;
            load_busy_seen <= 1'b0;
            load_word_addr <= 0;
            load_word_data <= 0;
            read_inflight <= 1'b0;
            pair_half<=0;
            pair_last<=0;req_pair_sync1<=0;req_pair_sync2<=0;
            read_issued <= 1'b0;
            read_half_addr <= 0;
            req_sync1 <= 1'b0;
            req_sync2 <= 1'b0;
            req_sync3 <= 1'b0;
            req_addr_sync1 <= 0;
            req_addr_sync2 <= 0;
            req_seen_mem <= 1'b0;
            resp_toggle_mem <= 1'b0;
            resp_low_mem <= 0;
            resp_high_mem <= 0;
            resp_pair_low_mem<=0;resp_pair_high_mem<=0;
        end else begin
        psram_write <= 1'b0;
        psram_read <= 1'b0;
        req_sync1 <= req_toggle;
        req_sync2 <= req_sync1;
        // Bundled address has two stages too. Allow it a settling clock if
        // its first stage resolves one cycle later than the request toggle.
        req_sync3 <= req_sync2;
        req_addr_sync1 <= req_addr_hold;
        req_addr_sync2 <= req_addr_sync1;
        req_pair_sync1<=req_pair_hold;req_pair_sync2<=req_pair_sync1;

        if (load_write && !load_fifo_full) begin
            load_fifo_addr[load_fifo_write_ptr] <= load_addr;
            load_fifo_data[load_fifo_write_ptr] <= load_wdata;
            load_fifo_write_ptr <= load_fifo_write_ptr + 1'b1;
        end

        if (!load_inflight && !read_inflight && (load_fifo_count != 0)) begin
            load_word_addr <= load_fifo_addr[load_fifo_read_ptr];
            load_word_data <= load_fifo_data[load_fifo_read_ptr];
            load_fifo_read_ptr <= load_fifo_read_ptr + 1'b1;
            load_half <= 1'b0;
            load_inflight <= 1'b1;
            load_issued <= 1'b0;
            load_busy_seen <= 1'b0;
        end

        case ({load_write && !load_fifo_full,
               !load_inflight && !read_inflight && (load_fifo_count != 0)})
            2'b10: load_fifo_count <= load_fifo_count + 1'b1;
            2'b01: load_fifo_count <= load_fifo_count - 1'b1;
            default: load_fifo_count <= load_fifo_count;
        endcase

        if (load_inflight && !load_issued && !psram_busy) begin
            psram_bank <= load_word_addr[22:21];
            psram_addr <= {load_word_addr[20:0], load_half};
            psram_wdata <= load_half ? load_word_data[31:16] : load_word_data[15:0];
            psram_write <= 1'b1;
            load_issued <= 1'b1;
        end else if (load_inflight && load_issued && psram_busy) begin
            load_busy_seen <= 1'b1;
        end else if (load_inflight && load_issued && load_busy_seen && !psram_busy) begin
`ifdef GBK_SIM
            // Commit only after the physical controller completes the write.
            if (load_half)
                sim_rom[load_word_addr[15:0]][31:16] <= load_word_data[31:16];
            else
                sim_rom[load_word_addr[15:0]][15:0] <= load_word_data[15:0];
`endif
            if (load_half)
                load_inflight <= 1'b0;
            else
                load_half <= 1'b1;
            load_issued <= 1'b0;
            load_busy_seen <= 1'b0;
        end else if (req_sync3 != req_seen_mem && !psram_busy && !load_inflight &&
                     (load_fifo_count == 0)) begin
            req_seen_mem <= req_sync3;
            read_half_addr <= req_pair_sync2 ? {req_addr_sync2[ROM_WORD_BITS+1:3], 2'b00} : {req_addr_sync2,1'b0};
            pair_half<=PAIR_MODE && !req_pair_sync2 ? {req_addr_sync2[2],1'b0} : 2'd0;
            pair_last<=req_pair_sync2 ? 2'd3 : PAIR_MODE ? {req_addr_sync2[2],1'b1} : 2'd1;
            read_inflight <= 1'b1;
            // The request/address mailbox has already settled and the
            // physical controller is idle. Issue directly instead of
            // spending another scheduler clock rediscovering that state.
            read_issued <= FAST_READ_ISSUE;
            if(FAST_READ_ISSUE) begin
                psram_bank <= req_addr_sync2 >> 21;
                psram_addr <= req_pair_sync2 ? {req_addr_sync2[22:3],2'b00} : {req_addr_sync2[22:2],1'b0};
                psram_read <= 1'b1;
            end
        end

        if (read_inflight && !read_issued && !psram_busy) begin
            psram_bank <= read_half_addr >> 22;
            psram_addr <= read_half_addr[21:0];
            psram_read <= 1'b1;
            read_issued <= 1'b1;
        end

        if (psram_valid) begin
            read_issued <= 1'b0;
            if(SDRAM_BACKEND && SDRAM_DIRECT_BURST) begin
                // The adapter already owns a complete aligned 64-bit burst.
                // Reuse the existing held response mailbox and its settling
                // stages. Allocation/prefetch policy remains CPU-side and
                // unchanged; a scalar miss still fills only its demanded word.
                if(PAIR_MODE) begin
                    {resp_pair_high_mem,resp_pair_low_mem,resp_high_mem,resp_low_mem} <= sdram_line_data;
                end else begin
                    {resp_high_mem,resp_low_mem} <= read_half_addr[1] ? sdram_line_data[63:32] : sdram_line_data[31:0];
                end
                resp_toggle_mem <= ~resp_toggle_mem;
                read_inflight <= 1'b0;
            end else begin
            case(pair_half)
                0:resp_low_mem<=psram_rdata;
                1:resp_high_mem<=psram_rdata;
                2:resp_pair_low_mem<=psram_rdata;
                3:resp_pair_high_mem<=psram_rdata;
            endcase
            if(pair_half==pair_last) begin
                resp_toggle_mem <= ~resp_toggle_mem;
                read_inflight <= 1'b0;
            end else begin
                pair_half<=pair_half+1'b1;
                read_half_addr<=read_half_addr+1'b1;
                // read_valid is registered after READ_CAPTURE, so the
                // physical engine is idle here. Prepare the next halfword
                // immediately; its address latch and pin timing are intact.
                if(FAST_READ_ISSUE) begin
                    {psram_bank,psram_addr} <= read_half_addr+1'b1;
                    psram_read <= 1'b1;
                    read_issued <= 1'b1;
                end
            end
            end
        end
        end
    end

    // CPU-domain request/response handshake.
    always_ff @(posedge cpu_clk) begin
        if (reset) begin
            cpu_ready_reg <= 1'b0;
            cpu_rdata <= 0;
            req_toggle <= 1'b0;
            req_addr_hold <= 0;
            req_pair_hold<=0;accepted_line_data<=0;
            request_history_valid<=0;sequential_run<=0;
            req_seen_cpu <= 1'b0;
            resp_sync1 <= 1'b0;
            resp_sync2 <= 1'b0;
            resp_sync3 <= 1'b0;
            resp_seen_cpu <= 1'b0;
            resp_low_sync1 <= 0;
            resp_low_sync2 <= 0;
            resp_high_sync1 <= 0;
            resp_high_sync2 <= 0;
            resp_pair_low_sync1<=0;resp_pair_low_sync2<=0;
            resp_pair_high_sync1<=0;resp_pair_high_sync2<=0;
            cpu_waiting <= 1'b0;
            allocate_request <= 1'b1;
            cached_word_valid<=0;
            cache_pending<=0;accepted_cache_ready<=0;accepted_valid_word<=0;
            epoch_sync1<=0;epoch_sync2<=0;epoch_seen<=0;accepted_epoch<=0;
        end else begin
        cpu_ready_reg <= 1'b0;
        resp_sync1 <= resp_toggle_mem;
        resp_sync2 <= resp_sync1;
        // Qualify the two-stage data bus only after its settling interval.
        resp_sync3 <= resp_sync2;
        resp_low_sync1 <= resp_low_mem;
        resp_low_sync2 <= resp_low_sync1;
        resp_high_sync1 <= resp_high_mem;
        resp_high_sync2 <= resp_high_sync1;
        resp_pair_low_sync1<=resp_pair_low_mem;resp_pair_low_sync2<=resp_pair_low_sync1;
        resp_pair_high_sync1<=resp_pair_high_mem;resp_pair_high_sync2<=resp_pair_high_sync1;
        epoch_sync1<=image_epoch;epoch_sync2<=epoch_sync1;
        if(epoch_sync2!=epoch_seen) begin
            epoch_seen<=epoch_sync2;
            cached_word_valid<=0;
            request_history_valid<=0;sequential_run<=0;
        end

`ifdef GBK_SIM
        if (cpu_req) begin
            cpu_rdata <= sim_rom[cpu_addr[17:2]];
            cpu_ready_reg <= 1'b1;
        end
`else
        if (!cpu_req) req_seen_cpu <= 1'b0;
        // A ROM data read can be followed immediately by the next fetch,
        // and block transfers also keep req asserted as addresses advance.
        // Suppress repeats of the current word, but accept a changed word
        // address without requiring a low pulse between transactions.
        if (cpu_req && (!req_seen_cpu || cpu_addr[ROM_WORD_BITS+1:2] != req_addr_hold) &&
            !cpu_waiting) begin
            req_seen_cpu <= 1'b1;
            // Pair only after a run of eight distinct consecutive words.
            // Repeated halves of a Thumb word preserve that history. Cold
            // branches/random data and streaming misses keep scalar service.
            // Direct SDRAM service can optionally retain an empty sibling
            // from either demanded word, with no additional physical work.
            req_pair_hold<=PAIR_MODE && ENABLE_WORD_CACHE && !cpu_streaming && epoch_sync2==epoch_seen &&
                ((SDRAM_BACKEND && SDRAM_DIRECT_BURST && SDRAM_FILL_NEIGHBOR) ||
                 (request_history_valid && sequential_run==7 &&
                  !cpu_addr[2] && cpu_addr[ROM_WORD_BITS+1:2]==req_addr_hold+1'b1));
            request_history_valid<=epoch_sync2==epoch_seen;
            if(cpu_streaming || !request_history_valid || epoch_sync2!=epoch_seen)
                sequential_run<=0;
            else if(cpu_addr[ROM_WORD_BITS+1:2]==req_addr_hold+1'b1) begin
                if(sequential_run!=7) sequential_run<=sequential_run+1'b1;
            end else if(cpu_addr[ROM_WORD_BITS+1:2]!=req_addr_hold) sequential_run<=0;
            req_addr_hold <= cpu_addr[ROM_WORD_BITS+1:2];
            // Streaming graphics reads may hit existing entries or fill an
            // unused slot, but must not replace hot code with animation tiles.
            allocate_request <= !BYPASS_STREAM_FILLS || !cpu_streaming;
            accepted_cache_ready<=!cache_clearing && epoch_sync2==epoch_seen;
            if(ENABLE_WORD_CACHE && cached_word_valid &&
               cpu_addr[ROM_WORD_BITS+1:2]==req_addr_hold && epoch_sync2==epoch_seen) begin
                // Consecutive Thumb instructions share this 32-bit word.
                // Reuse the settled CPU-domain response, without another CDC
                // round trip and two physical halfword reads.
`ifdef GBK_FAST_FORWARD
                // The combinational acceptance already completed this read.
                cpu_ready_reg<=0;
`else
                cpu_ready_reg<=1;
`endif
            end else begin
                // A request accepted on the invalidation edge must not use
                // the old synchronous lookup, whose valid bit was sampled
                // before the bitmap cleared.
                accepted_epoch<=epoch_seen;
                if(ENABLE_WORD_CACHE && CACHE_WORDS>1) cache_pending<=1;
                else begin cached_word_valid<=0;req_toggle<=~req_toggle;end
                cpu_waiting <= 1'b1;
            end
        end
        if(cache_pending) begin
            cache_pending<=0;
            accepted_valid_word<=cache_lookup_valid_word;
            accepted_line_data<=cache_lookup;
            if(ENABLE_WORD_CACHE && cache_lookup_valid &&
               lookup_tag==req_addr_hold[ROM_WORD_BITS+1:2+CACHE_BITS] &&
               accepted_cache_ready && !cache_clearing &&
               accepted_epoch==epoch_seen && epoch_sync2==epoch_seen) begin
                cpu_rdata<=lookup_data;cpu_ready_reg<=1;
                cpu_waiting<=0;cached_word_valid<=1;
            end else begin
                cached_word_valid<=0;
                // Speculation may use an empty neighbour but must not evict
                // an occupied word or reread an already cached neighbour.
                if(PAIR_MODE && cache_lookup_valid_word[(fill_index & 31) ^ 1]) req_pair_hold<=0;
                // Empty slots remain useful for repeatedly copied graphics.
                // A streaming miss only bypasses an occupied cache slot.
                if(!cache_lookup_valid) allocate_request<=1;
                req_toggle<=~req_toggle;
            end
        end
        if (resp_sync3 != resp_seen_cpu) begin
            resp_seen_cpu <= resp_sync3;
            cpu_rdata <= PAIR_MODE && req_addr_hold[2] ? {resp_pair_high_sync2,resp_pair_low_sync2} : {resp_high_sync2,resp_low_sync2};
            cpu_ready_reg <= 1'b1;
            cpu_waiting <= 1'b0;
            cached_word_valid<=ENABLE_WORD_CACHE && cpu_req &&
                cpu_addr[ROM_WORD_BITS+1:2]==req_addr_hold && accepted_epoch==epoch_seen && epoch_sync2==epoch_seen;
        end
`endif
        end
    end
endmodule
