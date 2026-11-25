// Evaluate the inserted cartridge instead of looking it up in a list.
// Presents the same results as the retail catalog: the copied size, a usable
// profile and a save kind, so boot, save import and writeback stay unchanged.
//
// The loader has already checked the header and probed the ROM size from the
// cartridge. The save kind comes from the save-library string found while the
// image was copied, with the emulator's precedence (EEPROM, SRAM, Flash).
// A cartridge with no library string boots without physical save access.
// EEPROM capacity is measured later by the import; kind 6 stands for both.
module gba_gamepak_detect (
    input wire clk,reset,header_valid,validate,
    input wire [31:0] header_code,
    input wire [23:0] detected_words,
    // Signature flags from the copy clock; stable before validate.
    input wire signature_sram,signature_eeprom,signature_flash512,signature_flash1m,
    output wire size_pending,
    output reg [31:0] game_code=0,
    output wire [23:0] rom_words,
    output reg result_valid=0,
    output reg matched=0,
    output wire [23:0] alternate_words,
    output reg [2:0] save_kind=0,
    output wire [5:0] hardware
);
    localparam [2:0] NONE=0, SRAM_32K=2, FLASH_64K=3, FLASH_128K=4, EEPROM=6;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [3:0] signature_meta=0;
    reg [3:0] signature=0;
    assign size_pending=1'b0;
    assign rom_words=detected_words;
    assign alternate_words=0;
    assign hardware=0;
    always @(posedge clk)begin
        signature_meta<={signature_flash1m,signature_flash512,signature_sram,signature_eeprom};
        signature<=signature_meta;
        if(reset)begin
            game_code<=0;result_valid<=0;matched<=0;save_kind<=NONE;
        end else begin
            if(header_valid)game_code<=header_code;
            if(validate && !result_valid)begin
                result_valid<=1;matched<=1;
                save_kind<=signature[0] ? EEPROM : signature[1] ? SRAM_32K :
                    signature[2] ? FLASH_64K : signature[3] ? FLASH_128K : NONE;
            end
        end
    end
endmodule
