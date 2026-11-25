// Read and validate the Game Pak header, then stream aligned words to the
// existing ROM loader. The caller supplies the cartridge size and owns boot
// reset. Destination idle must include all queued and in-flight writes.
module gba_gamepak_rom_loader #(
    parameter [31:0] EXPECTED_GAME_CODE=0,
    parameter bit VERIFY_HEADER_CHECKSUM=1,
    parameter bit RESOLVE_PROFILE=0,
    parameter bit HEADER_ONLY=0,
    parameter bit PROBE_UNKNOWN_SIZE=0,
    // Copy the probed size instead of stopping. Inconsistent probe reads
    // copy the whole 32 MiB window, which costs time but never truncates.
    parameter bit DETECT_SIZE=0,
    parameter integer COPY_ADDRESS_BITS=23
) (
    input wire clk,reset,enable,start,
    input wire [23:0] image_words,
    input wire profile_pending,
    output wire [31:0] header_game_code,
    output wire header_code_valid,
    output wire copy_start,
    output wire [23:0] probed_words,
    output wire [23:0] detected_words,
    output wire [1:0] probe_evidence,
    output wire busy,
    output reg done,error,
    output wire reader_valid,
    output wire [22:0] reader_word,
    input wire reader_ready,reader_reply,
    input wire [31:0] reader_data,
    output wire reader_reply_ready,
    output wire load_valid,
    output wire [22:0] load_word,
    output wire [31:0] load_data,
    input wire load_ready,load_idle
);
    localparam IDLE=0,HEADER_REQUEST=1,HEADER_REPLY=2,
               COPY_REQUEST=3,COPY_REPLY=4,DRAIN=5,RESOLVE=6,PROBE_SIZE=7;
    localparam [23:0] MAX_WORDS=24'd1<<COPY_ADDRESS_BITS;
    reg [2:0] state=IDLE;
    reg [COPY_ADDRESS_BITS-1:0] word_index,last_word;
    reg [7:0] checksum;
    reg [1:0] header_byte_index;
    reg fixed_marker_valid;
    wire active=enable && !reset;
    localparam bit CHECK_HEADER=VERIFY_HEADER_CHECKSUM;
    wire header_last_byte=!CHECK_HEADER || (word_index==23'h2f ? header_byte_index==1 : &header_byte_index);
    assign busy=state!=IDLE;
    wire probing=PROBE_UNKNOWN_SIZE && state==PROBE_SIZE;
    wire probe_valid, probe_reply_ready, probe_done;
    wire [22:0] probe_word;
    assign reader_valid=active && (probing ? probe_valid : state==HEADER_REQUEST || state==COPY_REQUEST);
    assign reader_word=probing ? probe_word : 23'(word_index);
    assign reader_reply_ready=active && (probing ? probe_reply_ready :
        (state==HEADER_REPLY && header_last_byte) || (state==COPY_REPLY && load_ready));
    assign load_valid=active && state==COPY_REPLY && reader_reply;
    assign load_word=23'(word_index);
    assign load_data=reader_data;
    assign header_game_code=reader_data;
    assign header_code_valid=reader_reply_ready && state==HEADER_REPLY && reader_reply && word_index==23'h2b;
    wire [7:0] header_byte=reader_data[{header_byte_index,3'b000}+:8];
    wire [7:0] next_checksum=checksum+header_byte;
    wire [23:0] last_word_full=image_words-1'b1;
    // The probed size, or the whole window when the probe was inconsistent.
    // It stays valid after the copy for the caller's identity and ROM size.
    // The probe reports zero only when its reads were inconsistent.
    assign detected_words=probed_words!=0 ? probed_words : MAX_WORDS;
    wire valid_size=image_words>=48 && image_words<=MAX_WORDS;
    wire size_ready=profile_pending!==1'b1;
    assign copy_start=active && ((state==RESOLVE && valid_size && size_ready) ||
        (DETECT_SIZE && probing && probe_done));
    generate if(PROBE_UNKNOWN_SIZE) begin: probe
        gba_gamepak_rom_size_probe size_probe(.clk,.enable(active),
            .start(state==RESOLVE && !valid_size),.reader_valid(probe_valid),.reader_word(probe_word),
            .reader_ready(reader_ready && probing),.reader_reply(reader_reply && probing),.reader_data,
            .reader_reply_ready(probe_reply_ready),.done(probe_done),.words(probed_words),.evidence(probe_evidence));
    end else begin: no_probe
        assign {probe_valid,probe_reply_ready,probe_done,probe_word,probed_words,probe_evidence}=0;
    end endgenerate

    always @(posedge clk) begin
        done<=0;error<=0;
        if(!active)state<=IDLE;
        else case(state)
            IDLE:if(start)begin
                if(!HEADER_ONLY && !RESOLVE_PROFILE && !valid_size)error<=1;
                else begin
                    last_word<=last_word_full[COPY_ADDRESS_BITS-1:0];
                    // Header complement covers bytes A0..BC inclusive.
                    // Start with the fixed bias and include byte BD at the end.
                    word_index<=CHECK_HEADER ? 23'h28 : 23'h2b;
                    checksum<=8'h19;fixed_marker_valid<=0;
                    state<=HEADER_REQUEST;
                end
            end
            HEADER_REQUEST:if(reader_ready)begin header_byte_index<=0;state<=HEADER_REPLY;end
            HEADER_REPLY:if(reader_reply)begin
                if(!CHECK_HEADER)begin
                    // Known images are CRC-checked before boot, including
                    // the full header. Check the fixed byte before copying.
                    if(RESOLVE_PROFILE && word_index==23'h2b)begin
                        word_index<=23'h2c;state<=HEADER_REQUEST;
                    end else if(RESOLVE_PROFILE && reader_data[23:16]==8'h96)begin
                        word_index<=0;state<=RESOLVE;
                    end else if(!RESOLVE_PROFILE && reader_data==EXPECTED_GAME_CODE)begin
                        word_index<=0;state<=COPY_REQUEST;
                    end else begin error<=1;state<=IDLE;end
                end else if(word_index==23'h2f && header_last_byte)begin
                    if(fixed_marker_valid && next_checksum==0)begin
                        if(HEADER_ONLY)begin done<=1;state<=IDLE;end
                        else begin word_index<=0;state<=RESOLVE_PROFILE ? RESOLVE : COPY_REQUEST;end
                    end else begin
                        error<=1;state<=IDLE;
                    end
                end else if(header_last_byte && EXPECTED_GAME_CODE!=0 && word_index==23'h2b && reader_data!=EXPECTED_GAME_CODE)begin
                    error<=1;state<=IDLE;
                end else begin
                    if(word_index==23'h2c && header_byte_index==2)fixed_marker_valid<=header_byte==8'h96;
                    checksum<=next_checksum;
                    if(header_last_byte)begin word_index<=word_index+1'b1;state<=HEADER_REQUEST;end
                    else header_byte_index<=header_byte_index+1'b1;
                end
            end
            RESOLVE:if(size_ready)begin
                if(valid_size)begin
                    last_word<=last_word_full[COPY_ADDRESS_BITS-1:0];
                    state<=COPY_REQUEST;
                end else if(PROBE_UNKNOWN_SIZE)state<=PROBE_SIZE;
                else begin error<=1;state<=IDLE;end
            end
            // A size observation alone gives no reliable physical save type.
            // Detection mode takes the save type from the copied image instead.
            PROBE_SIZE:if(probe_done)begin
                if(DETECT_SIZE)begin
                    last_word<=COPY_ADDRESS_BITS'(detected_words-1'b1);
                    word_index<=0;state<=COPY_REQUEST;
                end else begin error<=1;state<=IDLE;end
            end
            COPY_REQUEST:if(reader_ready)state<=COPY_REPLY;
            COPY_REPLY:if(reader_reply && load_ready)begin
                if(word_index==last_word)state<=DRAIN;
                else begin word_index<=word_index+1'b1;state<=COPY_REQUEST;end
            end
            DRAIN:if(load_idle)begin done<=1;state<=IDLE;end
            default:state<=IDLE;
        endcase
    end
endmodule
