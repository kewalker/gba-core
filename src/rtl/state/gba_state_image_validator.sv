// Validate a STAGED image before any live-state write is authorized.
// All signals use one clock. The backing store holds each requested word until
// read_valid; only one read is outstanding. A start pulse begins a new pass.
// This module neither freezes the guest nor writes guest/battery memory.
module gba_state_image_validator #(
    parameter integer SECTION_COUNT=2,
    parameter integer MAX_BYTES=1048576,
    parameter integer READ_TIMEOUT=7425000,
    parameter bit CHECK_PAYLOAD=0,
    parameter integer CRC_BITS=1,
    parameter bit LATCH_IDENTITY=1
)(
    input wire clk,reset,start,
    // Capture reuses this CRC accumulator for bounded staged-memory scans.
    // Unconnected legacy callers select normal validation.
    input wire scan_only,
    input wire [31:0] scan_begin,scan_bytes,
    output reg [31:0] scan_crc,
    input wire [31:0] rom_crc,rom_bytes,bios_crc,layout_crc,
    output wire [3:0] section_index,
    input wire [31:0] expected_section_id,expected_section_bytes,
    output wire read_req,
    output wire [31:0] read_addr,
    input wire read_valid,
    input wire [31:0] read_data,
    // Optional schema-specific precommit check. Default remains container-only.
    output wire payload_valid,
    output wire [31:0] payload_word_index,
`ifdef GBK_FAST_FORWARD
    output wire [31:0] payload_data,
`endif
    input wire payload_word_ok,
    output wire busy,
    output reg done,valid,
    output reg [3:0] error_code
);
    localparam IDLE=0,READ_WORD=1,CRC_BYTES=2,FINAL=3;
    localparam [31:0] HEADER_BYTES=64+16*SECTION_COUNT;
    localparam BAD_HEADER=1,BAD_IDENTITY=2,BAD_LENGTH=3,BAD_TABLE=4,
        BAD_CHECKSUM=5,TIMED_OUT=6,BAD_PAYLOAD=7;
    localparam INDEX_BITS=$clog2(MAX_BYTES/4+1),OFFSET_BITS=$clog2(MAX_BYTES+1);
    localparam WAIT_BITS=READ_TIMEOUT>1 ? $clog2(READ_TIMEOUT) : 1;
    localparam CHUNKS=32/CRC_BITS,CHUNK_BITS=$clog2(CHUNKS);
`ifdef GBK_FAST_FORWARD
    localparam VALIDATE_WORD=4;
    reg [2:0] state;
`else
    reg [1:0] state;
`endif
    reg [CHUNK_BITS-1:0] chunk_index;
    reg [INDEX_BITS-1:0] word_index,total_words;
    // Track the payload-relative position with the word counter. Subtracting
    // the header size combinationally put a carry chain before semantic index
    // decoding and the validator's accept/reject decision.
    reg [INDEX_BITS:0] payload_position;
    localparam [INDEX_BITS:0] PAYLOAD_INITIAL=-(HEADER_BYTES/4);
    reg [OFFSET_BITS-1:0] next_section_offset;
    reg [WAIT_BITS-1:0] wait_count;
    reg [31:0] held_word,rolling_crc,expected_body_crc;
    // Latch identity at start; a loader update cannot change comparison halfway
    // through a pass. Integration must cancel validation on a game/BIOS reload.
    reg [31:0] saved_rom_crc,saved_rom_bytes,saved_bios_crc,saved_layout_crc;
    // The machine job already owns stable identity registers for its entire
    // operation. Standalone validators retain the original latching contract.
    wire [31:0] held_rom_crc=LATCH_IDENTITY ? saved_rom_crc : rom_crc;
    wire [31:0] held_rom_bytes=LATCH_IDENTITY ? saved_rom_bytes : rom_bytes;
    wire [31:0] held_bios_crc=LATCH_IDENTITY ? saved_bios_crc : bios_crc;
    wire [31:0] held_layout_crc=LATCH_IDENTITY ? saved_layout_crc : layout_crc;
    reg held_scan;
    assign section_index=4'((word_index-16)>>2);
    assign busy=state!=IDLE;
    assign read_req=state==READ_WORD;
    assign read_addr=word_index<<2;
`ifdef GBK_FAST_FORWARD
    assign payload_valid=!held_scan && state==VALIDATE_WORD && word_index>=HEADER_BYTES/4;
    assign payload_data=held_word;
`else
    assign payload_valid=!held_scan && read_req && read_valid && word_index>=HEADER_BYTES/4;
`endif
    assign payload_word_index={{(31-INDEX_BITS){payload_position[INDEX_BITS]}},payload_position};
    function automatic [31:0] crc_chunk(input [31:0] previous,input [CRC_BITS-1:0] value);
        reg [31:0] work;
        begin
            work=previous^{{(32-CRC_BITS){1'b0}},value};
            for(integer bit_index=0;bit_index<CRC_BITS;bit_index=bit_index+1)
                work=work[0] ? (work>>1)^32'hedb88320 : work>>1;
            crc_chunk=work;
        end
    endfunction
    // One accumulator and update network serve both disjoint checksums. The
    // header result is consumed before the accumulator starts the body CRC.
    // Bit-serial by default: state validation trades latency for scarce ALMs;
    // this datapath is outside normal guest execution.
    wire [31:0] crc_update=crc_chunk(rolling_crc,held_word[CRC_BITS-1:0]);
    task fail(input [3:0] reason);
        begin state<=IDLE;valid<=0;done<=1;error_code<=reason;end
    endtask
    initial begin
        if(SECTION_COUNT<1 || SECTION_COUNT>16 || MAX_BYTES<HEADER_BYTES ||
           MAX_BYTES%4!=0 || READ_TIMEOUT<1 || !(CRC_BITS==1 || CRC_BITS==2 || CRC_BITS==4 || CRC_BITS==8))
            $error("Invalid staged state validator configuration");
    end
    always @(posedge clk) begin
        done<=0;
        if(reset)begin
            state<=IDLE;valid<=0;done<=0;error_code<=0;chunk_index<=0;
            word_index<=0;held_word<=0;total_words<=0;next_section_offset<=HEADER_BYTES;
            payload_position<=PAYLOAD_INITIAL;
            rolling_crc<=32'hffffffff;expected_body_crc<=0;wait_count<=0;
            saved_rom_crc<=0;saved_rom_bytes<=0;saved_bios_crc<=0;saved_layout_crc<=0;
            held_scan<=0;scan_crc<=0;
        end else case(state)
            IDLE:if(start)begin
                valid<=0;error_code<=0;word_index<=0;total_words<=0;
                payload_position<=PAYLOAD_INITIAL;
                next_section_offset<=HEADER_BYTES;rolling_crc<=32'hffffffff;
                expected_body_crc<=0;wait_count<=0;
                saved_rom_crc<=rom_crc;saved_rom_bytes<=rom_bytes;
                saved_bios_crc<=bios_crc;saved_layout_crc<=layout_crc;
                state<=READ_WORD;
                held_scan<=scan_only===1'b1;
                if(scan_only===1'b1)begin
                    word_index<=scan_begin>>2;
                    payload_position<=(scan_begin>>2)-HEADER_BYTES/4;
                    total_words<=({1'b0,scan_begin}+{1'b0,scan_bytes})>>2;
                    if(scan_bytes==0 || scan_begin[1:0]!=0 || scan_bytes[1:0]!=0 ||
                       {1'b0,scan_begin}+{1'b0,scan_bytes}>MAX_BYTES)fail(BAD_LENGTH);
                end
            end
            READ_WORD:if(read_valid)begin
                held_word<=read_data;chunk_index<=0;wait_count<=0;
`ifdef GBK_FAST_FORWARD
                state<=held_scan ? CRC_BYTES : VALIDATE_WORD;
`else
                state<=CRC_BYTES;
`endif
`ifndef GBK_FAST_FORWARD
                if(!held_scan)case(word_index)
                    0:if(read_data!=32'h534b4247)fail(BAD_HEADER); // "GBKS"
                    1:if(read_data!=32'h00010000)fail(BAD_HEADER);
                    2:if(read_data!=HEADER_BYTES)fail(BAD_LENGTH);
                    3:begin
                        if(read_data<HEADER_BYTES || read_data>MAX_BYTES || read_data[1:0]!=0)
                            fail(BAD_LENGTH);
                        total_words<=read_data>>2;
                    end
                    4:if(read_data!=held_rom_crc)fail(BAD_IDENTITY);
                    5:if(read_data!=held_rom_bytes)fail(BAD_IDENTITY);
                    6:if(read_data!=held_bios_crc)fail(BAD_IDENTITY);
                    7:if(read_data!=held_layout_crc)fail(BAD_IDENTITY);
                    8:if(read_data!=SECTION_COUNT)fail(BAD_TABLE);
                    9,10,11,12,13:if(read_data!=0)fail(BAD_HEADER);
                    14:expected_body_crc<=read_data;
                    15:begin
                        if(read_data!=~rolling_crc)fail(BAD_CHECKSUM);
                        rolling_crc<=32'hffffffff;
                    end
                    default:if(CHECK_PAYLOAD && word_index>=HEADER_BYTES/4 && !payload_word_ok)fail(BAD_PAYLOAD);
                    else if(word_index<16+4*SECTION_COUNT)begin
                        case(word_index[1:0])
                            0:if(read_data!=expected_section_id)fail(BAD_TABLE);
                            1:if(read_data!=next_section_offset)fail(BAD_TABLE);
                            2:begin
                                // Subtraction after proving offset in range
                                // avoids a wraparound accepting an oversized span.
                                if(read_data==0 || read_data[1:0]!=0 ||
                                   read_data!=expected_section_bytes ||
                                   next_section_offset>(total_words<<2) ||
                                   read_data>(total_words<<2)-next_section_offset)
                                    fail(BAD_TABLE);
                                next_section_offset<=next_section_offset+read_data;
                            end
                            3:if(read_data!=0 ||
                                (section_index==SECTION_COUNT-1 && next_section_offset!=(total_words<<2)))
                                    fail(BAD_TABLE);
                        endcase
                    end
                endcase
`endif
            end else if(wait_count==READ_TIMEOUT-1)fail(TIMED_OUT);
            else wait_count<=wait_count+1'b1;
`ifdef GBK_FAST_FORWARD
            // Validate the intact staged word before CRC shifting. The schema
            // reject cone no longer shares the CRC's next-word/final control.
            VALIDATE_WORD:begin
                state<=CRC_BYTES;
                if(!held_scan)case(word_index)
                    0:if(held_word!=32'h534b4247)fail(BAD_HEADER); // "GBKS"
                    1:if(held_word!=32'h00010000)fail(BAD_HEADER);
                    2:if(held_word!=HEADER_BYTES)fail(BAD_LENGTH);
                    3:begin
                        if(held_word<HEADER_BYTES || held_word>MAX_BYTES || held_word[1:0]!=0)
                            fail(BAD_LENGTH);
                        total_words<=held_word>>2;
                    end
                    4:if(held_word!=held_rom_crc)fail(BAD_IDENTITY);
                    5:if(held_word!=held_rom_bytes)fail(BAD_IDENTITY);
                    6:if(held_word!=held_bios_crc)fail(BAD_IDENTITY);
                    7:if(held_word!=held_layout_crc)fail(BAD_IDENTITY);
                    8:if(held_word!=SECTION_COUNT)fail(BAD_TABLE);
                    9,10,11,12,13:if(held_word!=0)fail(BAD_HEADER);
                    14:expected_body_crc<=held_word;
                    15:begin
                        if(held_word!=~rolling_crc)fail(BAD_CHECKSUM);
                        rolling_crc<=32'hffffffff;
                    end
                    default:if(CHECK_PAYLOAD && word_index>=HEADER_BYTES/4 && !payload_word_ok)fail(BAD_PAYLOAD);
                    else if(word_index<16+4*SECTION_COUNT)begin
                        case(word_index[1:0])
                            0:if(held_word!=expected_section_id)fail(BAD_TABLE);
                            1:if(held_word!=next_section_offset)fail(BAD_TABLE);
                            2:begin
                                // Subtraction after proving offset in range
                                // avoids a wraparound accepting an oversized span.
                                if(held_word==0 || held_word[1:0]!=0 ||
                                   held_word!=expected_section_bytes ||
                                   next_section_offset>(total_words<<2) ||
                                   held_word>(total_words<<2)-next_section_offset)
                                    fail(BAD_TABLE);
                                next_section_offset<=next_section_offset+held_word;
                            end
                            3:if(held_word!=0 ||
                                (section_index==SECTION_COUNT-1 && next_section_offset!=(total_words<<2)))
                                    fail(BAD_TABLE);
                        endcase
                    end
                endcase
            end
`endif
            CRC_BYTES:begin
                if(held_scan || word_index!=15)rolling_crc<=crc_update;
                held_word<=held_word>>CRC_BITS;
                if(chunk_index==CHUNKS-1)begin
                    if(word_index+1==total_words)state<=FINAL;
                    else begin
                        word_index<=word_index+1'b1;payload_position<=payload_position+1'b1;state<=READ_WORD;
                    end
                end else chunk_index<=chunk_index+1'b1;

            end
            FINAL:begin
                if(held_scan)begin
                    scan_crc<=~rolling_crc;state<=IDLE;done<=1;valid<=1;error_code<=0;
                end else if(rolling_crc!=~expected_body_crc)fail(BAD_CHECKSUM);
                else begin state<=IDLE;done<=1;valid<=1;error_code<=0;end
            end
            default:fail(BAD_HEADER);
        endcase
    end
endmodule
