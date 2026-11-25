// ROM dimensions are selected provisionally by game code. CRC validation of
// the complete image authorizes the physical save profile after the copy.
module gba_gamepak_profile #(
    parameter bit INCLUDE_STATS_PATH=0
) (
    input wire clk, start, header_code_valid,
    input wire [31:0] header_game_code, rom_crc,
    output reg [23:0] rom_words,
    output reg [31:0] game_code, profile_crc,
    output wire save_profile_valid,
    output wire save_sram_32k, save_eeprom,
    output reg [17:0] save_bytes,
    input wire stats_path_read,
    input wire [3:0] stats_path_index,
    output wire [31:0] stats_path_word
);
    localparam UNKNOWN=0, GOLDEN_SUN=1, WARIO_LAND=2, MINISH_US=3, MINISH_EU=4;
    localparam [31:0] AGSE=32'h45534741, AWAE=32'h45415741, BZME=32'h454d5a42, BZMP=32'h504d5a42;
    localparam NO_PROFILE=0, FLASH=1, LINEAR=2, EEPROM=3;
    reg [2:0] profile=UNKNOWN;
    reg [1:0] protocol;
    typedef struct packed {
        logic [31:0] code, crc;
        logic [23:0] words;
        logic [1:0] save_protocol;
        logic [17:0] bytes;
    } cartridge_profile;
    function automatic cartridge_profile catalog(input [2:0] index);
        case(index)
            GOLDEN_SUN:catalog={AGSE,32'he1fb68e8,24'h200000,2'(FLASH),18'd65536};
            WARIO_LAND:catalog={AWAE,32'hd6141609,24'h200000,2'(LINEAR),18'd32768};
            MINISH_US:catalog={BZME,32'habcebbb1,24'h400000,2'(EEPROM),18'd8192};
            MINISH_EU:catalog={BZMP,32'he8637292,24'h400000,2'(EEPROM),18'd8192};
            default:catalog='0;
        endcase
    endfunction
    always @(posedge clk) begin
        if(start)profile<=UNKNOWN;
        else if(header_code_valid)case(header_game_code)
            AGSE:profile<=GOLDEN_SUN;
            AWAE:profile<=WARIO_LAND;
            BZME:profile<=MINISH_US;
            BZMP:profile<=MINISH_EU;
            default:profile<=UNKNOWN;
        endcase
    end
    // Record format is independent of the selected bus protocol.
    always @* {game_code,profile_crc,rom_words,protocol,save_bytes}=catalog(profile);
    assign save_sram_32k=protocol==LINEAR;
    assign save_eeprom=protocol==EEPROM;
    // With no confirmed profile, leave the physical save bus idle.
    assign save_profile_valid=protocol!=NO_PROFILE && rom_crc==profile_crc;

    function automatic [31:0] hex_word(input [15:0] value);
        for(integer lane=0;lane<4;lane=lane+1)begin
            hex_word[lane*8+:8]=value[lane*4+:4]<10
                ? 8'h30+{4'd0,value[lane*4+:4]} : 8'h57+{4'd0,value[lane*4+:4]};
        end
    endfunction
    function automatic [31:0] path_word(input cartridge_profile entry,input [3:0] index);
        case(index)
            0:path_word=32'h2f536176;
            1:path_word=32'h65732f67;
            2:path_word=32'h62612f42;
            3:path_word=32'h69744269;
            4:path_word=32'h72642e47;
            5:path_word={24'h42412f,entry.code[7:0]};
            6:path_word={entry.code[15:8],entry.code[23:16],entry.code[31:24],8'h2d};
            7:path_word=hex_word(entry.crc[31:16]);
            8:path_word=hex_word(entry.crc[15:0]);
            9:path_word=32'h2e67626b;
            10:path_word=32'h73746174;
            default:path_word=0;
        endcase
    endfunction
    generate if(INCLUDE_STATS_PATH)begin : stats_path
        // Entries share the same constants used for identity validation.
        // Preformat the path in ROM to avoid a runtime ASCII formatter.
        (* ramstyle="M10K" *) reg [31:0] words[0:127];
        reg [31:0] response;
        initial for(integer index=0;index<128;index=index+1)
            words[index]=path_word(catalog(3'(index/16)),4'(index));
        always @(posedge clk)if(stats_path_read)
            response<=words[{profile,stats_path_index}];
        assign stats_path_word=response;
    end else begin : no_stats_path
        assign stats_path_word=0;
    end endgenerate
endmodule
