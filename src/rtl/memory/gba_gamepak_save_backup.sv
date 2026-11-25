// Preserve each pre-write image in an APF file. APF returns one word
// behind the bridge read strobe. The backup RAM therefore has a registered
// read output, like the other bulk bridge endpoints.
// RING_SLOTS=0 picks the first unused CODE-xx.sav. A power-of-two RING_SLOTS
// overwrites CODE-0..N-1 in turn. APF cannot delete files, so the next slot
// lives in the 4-byte CODE-bk.idx, advanced only after the backup verifies.
// fallback writes the working save to CODE-unsaved.sav instead: no probe and
// no index, overwritten each time, read back like any backup.
module gba_gamepak_save_backup #(
    parameter bit VARIABLE_PROFILE=0,
    parameter bit USE_TIMEOUT_TICK=0,
    parameter bit STREAMING=0,
    parameter integer CHUNK_BYTES=256,
    parameter integer RING_SLOTS=0
)(
    input wire clk,enable,request,
    input wire fallback,
    input wire timeout_tick,
    input wire half_capacity,
    input wire [31:0] game_code,
    input wire [17:0] stream_capacity,
    output wire fill_chunk,
    output wire [16:0] chunk_offset,
    input wire chunk_filled,chunk_error,
    output wire ready,error,active,
    input wire bridge_rd,bridge_wr,
    input wire [31:0] bridge_addr,bridge_wdata,backup_rdata,
    output wire backup_read,
    output wire [13:0] backup_word,
    output wire command_open,command_write,command_read,
    input wire command_done,
    input wire [2:0] command_error,
    output wire [31:0] bridge_rdata,
    output wire [31:0] transfer_address,transfer_offset,transfer_length
);
    localparam [31:0] PARAM_BASE=32'h13000000, DATA_BASE=32'h14000000;
    localparam IDLE=0, PROBE=1, CREATE=2, WRITE_FILE=3, REOPEN=4, VERIFY_FILE=5, OK=6, FAILED=7,
               FILL_CHUNK=8, IDX_OPEN=9, IDX_READ=10, IDX_REOPEN=11, IDX_WRITE=12;
    localparam bit RING=RING_SLOTS>0;
    localparam [7:0] SLOT_MASK=RING ? 8'(RING_SLOTS-1) : 8'hff;
    localparam integer VERIFIED_BITS=STREAMING ? $clog2(CHUNK_BYTES/4+1) : 15;
    localparam integer PHASE_BITS=STREAMING || RING ? 4 : 3;
    reg [PHASE_BITS-1:0] phase=IDLE;
    reg [16:0] file_offset=0;
    reg verifying=0;
    reg [7:0] serial=0;
    reg submitted=0,saw_clear=0;
    // The shared 20-bit host divider gives the same timeout in 8 bits.
    reg [(USE_TIMEOUT_TICK ? 8 : 28)-1:0] elapsed=0;
    reg [VERIFIED_BITS-1:0] verified_words=0;
    reg verify_bad=0,verify_pending=0;
    reg [31:0] expected;
    reg [31:0] parameter_word=0;
    reg parameter_selected=0;
    wire [5:0] word_index=bridge_addr[7:2];
    wire read_parameters=bridge_addr[31:24]==PARAM_BASE[31:24];
    wire read_data=bridge_addr[31:16]==DATA_BASE[31:16];
    wire verify_word=phase==VERIFY_FILE && submitted && read_data && bridge_wr;
    wire index_phase=RING && (phase==IDX_OPEN || phase==IDX_READ || phase==IDX_REOPEN || phase==IDX_WRITE);
    wire [7:0] next_slot=(serial+1'b1) & SLOT_MASK;
    wire [14:0] word_count=VARIABLE_PROFILE && half_capacity ? 15'd8192 : 15'd16384;
    wire [17:0] archive_bytes=STREAMING ? stream_capacity : {1'b0,word_count,2'b00};
    wire valid_stream_capacity=stream_capacity==512 || stream_capacity==8192 || stream_capacity==32768 ||
        stream_capacity==65536 || stream_capacity==131072;
    wire [17:0] chunk_end={1'b0,file_offset}+18'(CHUNK_BYTES);
    wire last_chunk=chunk_end==archive_bytes;
    wire [VERIFIED_BITS-1:0] verify_count=STREAMING ? VERIFIED_BITS'(CHUNK_BYTES/4) : VERIFIED_BITS'(word_count);
    wire [31:0] save_name=VARIABLE_PROFILE ? swapped(game_code) : 32'h41475345;
    // Serialize byte-array payloads in the bridge's byte order.
    function automatic [31:0] swapped(input [31:0] value);
        swapped={value[7:0],value[15:8],value[23:16],value[31:24]};
    endfunction
    function automatic [7:0] hex_digit(input [3:0] nibble);
        hex_digit=nibble<10 ? 8'd48+{4'd0,nibble} : 8'd87+{4'd0,nibble};
    endfunction
    assign ready=phase==OK;
    assign error=phase==FAILED;
    assign active=phase!=IDLE;
    assign command_open=enable && !submitted && (phase==PROBE || phase==CREATE || phase==REOPEN ||
        (RING && (phase==IDX_OPEN || phase==IDX_REOPEN)));
    assign command_write=enable && !submitted && (phase==WRITE_FILE || (RING && phase==IDX_WRITE));
    assign command_read=enable && !submitted && (phase==VERIFY_FILE || (RING && phase==IDX_READ));
    assign transfer_address=DATA_BASE;
    assign transfer_offset=STREAMING && !index_phase ? {15'd0,file_offset} : 32'd0;
    assign transfer_length=index_phase ? 32'd4 : STREAMING ? 32'(CHUNK_BYTES) : {14'd0,archive_bytes};
    assign fill_chunk=STREAMING && enable && phase==FILL_CHUNK;
    assign chunk_offset=STREAMING ? file_offset : 17'd0;
    assign backup_read=read_data && ((bridge_rd && phase==WRITE_FILE) || verify_word);
    assign backup_word=bridge_addr[15:2];
    // The index file's first byte is the next slot; bridge byte 0 is [31:24].
    assign bridge_rdata=parameter_selected ? parameter_word :
        index_phase ? {next_slot,24'd0} : swapped(backup_rdata);
    always @(posedge clk)begin
        if(bridge_rd && (read_parameters || read_data))parameter_selected<=read_parameters;
        if(bridge_rd && read_parameters)begin
            // /Saves/gba/BitBird.GBA/CODE-xx.sav (or CODE-bk.idx), zero-
            // terminated. Only CREATE and IDX_OPEN ask APF to create a file.
            case({bridge_addr[8],word_index})
                7'd0:parameter_word<=32'h2f536176;
                7'd1:parameter_word<=32'h65732f67;
                7'd2:parameter_word<=32'h62612f42;
                7'd3:parameter_word<=32'h69744269;
                7'd4:parameter_word<=32'h72642e47;
                7'd5:parameter_word<={24'h42412f,save_name[31:24]};
                7'd6:parameter_word<={save_name[23:0],8'h2d};
                7'd7:parameter_word<=index_phase ? 32'h626b2e69 : fallback ? 32'h756e7361 :
                    {hex_digit(serial[7:4]),hex_digit(serial[3:0]),16'h2e73};
                7'd8:parameter_word<=index_phase ? 32'h64780000 : fallback ? 32'h7665642e : 32'h61760000;
                7'd9:parameter_word<=fallback ? 32'h73617600 : 32'd0;
                // APF reads the operation flags and size as scalar words.
                7'd64:parameter_word<=phase==CREATE || (RING && phase==IDX_OPEN) ? 32'd3 : 32'd0;
                7'd65:parameter_word<=phase==CREATE ? {14'd0,archive_bytes} :
                    RING && phase==IDX_OPEN ? 32'd4 : 32'd0;
                default:parameter_word<=0;
            endcase
        end
        verify_pending<=verify_word;
        if(verify_word)begin
            expected<=swapped(bridge_wdata);
            verified_words<=verified_words+1'b1;
            if(verified_words>=verify_count || backup_word!=14'(verified_words) || bridge_addr[1:0]!=0)verify_bad<=1;
        end
        if(verify_pending && expected!=backup_rdata)verify_bad<=1;
        if(RING && phase==IDX_READ && submitted && read_data && bridge_wr && bridge_addr[15:2]==0)
            serial<=bridge_wdata[31:24] & SLOT_MASK;
        if(!enable)begin phase<=IDLE;serial<=0;submitted<=0;end
        else if(phase==IDLE)begin
            if(request)begin
                serial<=0;file_offset<=0;verifying<=0;
                phase<=STREAMING && !valid_stream_capacity ? FAILED : fallback ? CREATE : RING ? IDX_OPEN : PROBE;
            end
        end else if(ready || error)begin
            if(!request)phase<=IDLE;
        end else if(fill_chunk)begin
            if(chunk_error)phase<=FAILED;
            else if(chunk_filled)phase<=verifying ? VERIFY_FILE : WRITE_FILE;
        end else if(!submitted)begin
            submitted<=1;saw_clear<=0;elapsed<=0;
            verified_words<=0;verify_bad<=0;
        end else begin
            if(!USE_TIMEOUT_TICK || timeout_tick)elapsed<=elapsed+1'b1;
            if(!command_done)saw_clear<=1;
            if(&elapsed)begin phase<=FAILED;submitted<=0;end
            else if(command_done && saw_clear && !(phase==VERIFY_FILE && (verify_pending || verify_word)))begin
                submitted<=0;
                case(phase)
                    PROBE:if(command_error==3)phase<=CREATE;
                        else if(command_error==0 && serial!=8'hff)begin serial<=serial+1'b1;phase<=PROBE;end
                        else phase<=FAILED;
                    // A ring slot may already exist (0) or be new (1).
                    CREATE:phase<=command_error==1 || ((RING || fallback) && command_error==0) ?
                        (STREAMING ? FILL_CHUNK : WRITE_FILE) : FAILED;
                    IDX_OPEN:phase<=command_error<=1 ? IDX_READ : FAILED;
                    IDX_READ:phase<=command_error==0 ? CREATE : FAILED;
                    // The backup is verified: a failed index update only
                    // means the next session reuses this slot.
                    IDX_REOPEN:phase<=command_error==0 ? IDX_WRITE : OK;
                    IDX_WRITE:phase<=OK;
                    WRITE_FILE:if(command_error!=0)phase<=FAILED;
                        else if(!STREAMING || last_chunk)phase<=REOPEN;
                        else begin file_offset<=chunk_end[16:0];phase<=FILL_CHUNK;end
                    // Reopen the completed file without create or resize flags.
                    // Pocket firmware can leave the explicit flush unacknowledged.
                    REOPEN:if(command_error!=0)phase<=FAILED;
                        else if(STREAMING)begin file_offset<=0;verifying<=1;phase<=FILL_CHUNK;end
                        else phase<=VERIFY_FILE;
                    VERIFY_FILE:if(command_error!=0 || verified_words!=verify_count || verify_bad)phase<=FAILED;
                        else if(!STREAMING || last_chunk)phase<=RING && !fallback ? IDX_REOPEN : OK;
                        else begin file_offset<=chunk_end[16:0];phase<=FILL_CHUNK;end
                    default:phase<=FAILED;
                endcase
            end
        end
    end
    initial if(RING && (RING_SLOTS>16 || (RING_SLOTS & (RING_SLOTS-1))!=0))
        $error("RING_SLOTS must be a power of two up to 16");
    initial if(STREAMING && (CHUNK_BYTES<4 || CHUNK_BYTES>512 || (CHUNK_BYTES & (CHUNK_BYTES-1))!=0))
        $error("Invalid streaming backup chunk size");
endmodule
