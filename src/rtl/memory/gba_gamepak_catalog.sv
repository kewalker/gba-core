// Stream the packaged catalog through a deferred APF slot. The same scan
// selects the smallest available ROM size and resolves its final identity.
// The core retains only the match and the next size it can try.
module gba_gamepak_catalog #(
    parameter integer ASSET_BYTES=16,
    parameter [31:0] ASSET_CRC=0
)(
    input wire clk,reset,header_valid,validate,advance,timeout_tick,
    input wire [31:0] header_code,rom_crc,
    input wire bridge_wr,
    input wire [31:0] bridge_addr,bridge_data,
    input wire command_done,
    input wire [2:0] command_error,
    input wire crc_idle,crc_error,
    input wire [31:0] stream_crc,
    output wire crc_write,
    output wire command_read,active,size_pending,
    output reg [31:0] game_code=0,
    output reg [23:0] rom_words=0,
    output reg result_valid=0,
    output reg matched=0,
    output reg [23:0] alternate_words=0,
    output reg [2:0] save_kind=0,
    output reg [5:0] hardware=0,
    output reg failed=0
);
    localparam IDLE=0,TRANSFER=1,READY=2;
    localparam integer ASSET_WORDS=ASSET_BYTES/4;
    localparam integer POSITION_BITS=$clog2(ASSET_WORDS+1);
    reg [1:0] phase=IDLE;
    reg submitted,saw_clear,damaged,checking_crc;
    reg record_code_matches,record_crc_matches,record_identity_matches,scan_match,saw_current_size;
    reg [5:0] elapsed;
    reg [POSITION_BITS-1:0] position;
    reg [31:0] checked_crc;
    reg [23:0] best_words;
    reg [8:0] scan_flags;
    wire [23:0] incoming_words=bridge_data[23:0];
    wire same_size=incoming_words==rom_words;
    wire incoming=active && bridge_wr && bridge_addr[31:16]==16'h1600;
    wire expected_word=position<ASSET_WORDS && bridge_addr[15:0]==16'(position*4);
    wire accept=incoming && submitted && expected_word && crc_idle;
    assign crc_write=accept;
    assign active=phase==TRANSFER;
    assign command_read=active && !submitted;
    assign size_pending=phase==IDLE || (active && !checking_crc);

    initial if(ASSET_BYTES<16 || ASSET_BYTES%16!=0 || ASSET_BYTES>65536)
        $error("Invalid Game Pak catalog dimensions");

    task start_scan(input bit identity);
        begin
            checking_crc<=identity;position<=0;submitted<=0;best_words<=0;saw_current_size<=0;
            damaged<=0;scan_match<=0;phase<=TRANSFER;
        end
    endtask

    task fail_scan;
        begin
            failed<=1;phase<=READY;result_valid<=checking_crc;
            alternate_words<=0;matched<=0;
        end
    endtask

    always @(posedge clk) begin
        if(reset)begin
            phase<=IDLE;game_code<=0;rom_words<=0;result_valid<=0;matched<=0;
            alternate_words<=0;save_kind<=0;hardware<=0;failed<=0;
        end else case(phase)
            IDLE:if(header_valid)begin
                game_code<=header_code;start_scan(0);
            end
            TRANSFER:begin
                if(!submitted)begin submitted<=1;saw_clear<=0;elapsed<=0;end
                else begin
                    if(!command_done)saw_clear<=1;
                    if(timeout_tick)elapsed<=elapsed+1'b1;
                    if(&elapsed)fail_scan();
                    else if(command_done && saw_clear && !incoming && crc_idle)begin
                        if(command_error!=0 || damaged || crc_error || position!=ASSET_WORDS || stream_crc!=ASSET_CRC)begin
                            fail_scan();
                        end else begin
                            phase<=READY;
                            if(checking_crc)begin
                                result_valid<=1;matched<=scan_match;alternate_words<=best_words;
                                if(scan_match)begin save_kind<=scan_flags[2:0];hardware<=scan_flags[8:3];end
                            end else rom_words<=best_words;
                        end
                    end
                end
                if(incoming && !accept)damaged<=1;
                if(accept)begin
                    position<=position+1'b1;
                    case(position[1:0])
                        0:record_code_matches<=bridge_data==game_code;
                        1:record_crc_matches<=checking_crc && bridge_data==checked_crc;
                        2:begin
                            record_identity_matches<=record_code_matches && record_crc_matches && same_size;
                            if(record_code_matches)begin
                                // The checked asset groups each code in ascending
                                // size order. Keep its first size, or the first
                                // size after the just-copied group on a retry.
                                if(same_size)saw_current_size<=1;
                                else if((!checking_crc || saw_current_size) && best_words==0)best_words<=incoming_words;
                            end
                        end
                        3:if(record_identity_matches)begin
                            scan_match<=1;scan_flags<=bridge_data[8:0];
                        end
                    endcase
                end
            end
            READY:if(header_valid && header_code!=game_code)begin
                failed<=1;rom_words<=0;
            end else if(advance && result_valid && !matched && alternate_words!=0)begin
                rom_words<=alternate_words;result_valid<=0;
            end else if(validate && !failed && !result_valid && rom_words!=0)begin
                checked_crc<=rom_crc;start_scan(1);
            end
            default:phase<=IDLE;
        endcase
    end
endmodule
