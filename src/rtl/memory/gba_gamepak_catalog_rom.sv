// A sealed catalog resident in block RAM. Sequential scans reuse one
// registered read port for size discovery and exact CRC validation.
module gba_gamepak_catalog_rom #(
    parameter integer ROWS=2880,
    parameter INIT_FILE="gamepak-catalog.hex"
)(
    input wire clk,reset,header_valid,validate,advance,
    input wire [31:0] header_code,rom_crc,
    output wire size_pending,
    output reg [31:0] game_code=0,
    output reg [23:0] rom_words=0,
    output reg result_valid=0,
    output reg matched=0,
    output reg [23:0] alternate_words=0,
    output reg [2:0] save_kind=0,
    output reg [5:0] hardware=0
);
    localparam IDLE=0,SCAN=1,FINISH=2,READY=3;
    localparam integer ADDRESS_BITS=$clog2(ROWS);
    reg [1:0] phase=IDLE;
    reg [ADDRESS_BITS:0] cursor;
    reg row_valid=0,row_last;
    reg [103:0] row;
    (* ramstyle="M10K" *) reg [103:0] catalog[0:ROWS-1];
    initial $readmemh(INIT_FILE,catalog);
    reg checking_crc,saw_current_size;
    reg [31:0] checked_crc;
    reg [23:0] best_words;
    wire reading=phase==SCAN && cursor<ROWS;
    wire [23:0] row_words=row[39:16];
    assign size_pending=phase==IDLE || ((phase==SCAN || phase==FINISH) && !checking_crc);

    always @(posedge clk)begin
        row_valid<=reading && !reset;
        if(reading)begin
            row<=catalog[cursor[ADDRESS_BITS-1:0]];
            row_last<=cursor==ROWS-1;
        end
    end

    task start_scan(input bit identity);
        begin
            cursor<=0;checking_crc<=identity;saw_current_size<=0;best_words<=0;phase<=SCAN;
        end
    endtask

    always @(posedge clk)begin
        if(reset)begin
            phase<=IDLE;game_code<=0;rom_words<=0;result_valid<=0;
            matched<=0;alternate_words<=0;save_kind<=0;hardware<=0;
        end else case(phase)
            IDLE:if(header_valid)begin game_code<=header_code;start_scan(0);end
            SCAN:begin
                if(reading)cursor<=cursor+1'b1;
                if(row_valid)begin
                    if(row[103:72]==game_code)begin
                        if(row_words==rom_words)begin
                            saw_current_size<=1;
                            if(checking_crc && row[71:40]==checked_crc)begin
                                matched<=1;save_kind<=row[2:0];hardware<=row[8:3];
                            end
                        end else if((!checking_crc || saw_current_size) && best_words==0)
                            best_words<=row_words;
                    end
                    if(row_last)phase<=FINISH;
                end
            end
            FINISH:begin
                if(checking_crc)begin result_valid<=1;alternate_words<=best_words;end
                else rom_words<=best_words;
                phase<=READY;
            end
            READY:if(header_valid && header_code!=game_code)rom_words<=0;
                else if(advance && result_valid && !matched && alternate_words!=0)begin
                    rom_words<=alternate_words;result_valid<=0;
                end else if(validate && !result_valid && rom_words!=0)begin
                    checked_crc<=rom_crc;start_scan(1);
                end
            default:phase<=IDLE;
        endcase
    end
endmodule
