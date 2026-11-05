// Complete staged container validation before ANY live-state mutation. Reuses
// the register scanner and container CRC engine; no second image/RAM buffer.
// Layout GFS1: registers, seven fixed mutable arrays, existing RTC payload.
module gba_state_machine_validator #(
    parameter integer READ_TIMEOUT=7425000,
    parameter integer CRC_BITS=1,
    parameter bit LATCH_IDENTITY=1
)(
    input wire clk,reset,start,
    input wire scan_only,
    input wire [31:0] scan_begin,scan_bytes,
    output wire [31:0] scan_crc,
    input wire [31:0] rom_crc,rom_bytes,bios_crc,
    output wire read_req,
    output wire [31:0] read_addr,
    input wire read_valid,
    input wire [31:0] read_data,
    output wire busy,done,valid,
    output wire [3:0] error_code
);
    wire [3:0] section_index;
`ifdef GBK_FAST_FORWARD
    wire [31:0] validated_word;
`define GBK_MACHINE_VALIDATOR_WORD validated_word
`else
`define GBK_MACHINE_VALIDATOR_WORD read_data
`endif
    reg [31:0] section_bytes;
    always @*case(section_index)
        0:section_bytes=776;1:section_bytes=262144;2:section_bytes=32768;
        3:section_bytes=98304;4,5:section_bytes=1024;
        6:section_bytes=131072;7:section_bytes=8192;8:section_bytes=16;
        default:section_bytes=0;
    endcase
    wire payload_valid,register_ok;
    wire [31:0] payload_word;
    reg payload_ok;
    gba_state_register_validator registers(.clk,.reset,.start,
        .word_valid(payload_valid && payload_word<194),.word_index(payload_word),.word_data(`GBK_MACHINE_VALIDATOR_WORD),.word_ok(register_ok));
    function automatic bcd(input [7:0] value,low,high);
        bcd=value[3:0]<10 && value[7:4]<10 && value>=low && value<=high;
    endfunction
    always @*begin
        payload_ok=payload_word<194 ? register_ok : 1'b1;
        case(payload_word)
            // Calendar and control use the EXISTING 98-bit persistence layout.
            133826:payload_ok=bcd(`GBK_MACHINE_VALIDATOR_WORD[7:0],8'h00,8'h99) && bcd(`GBK_MACHINE_VALIDATOR_WORD[15:8],8'h01,8'h12) &&
                bcd(`GBK_MACHINE_VALIDATOR_WORD[23:16],8'h01,8'h31) && `GBK_MACHINE_VALIDATOR_WORD[31:24]<=6;
            133827:payload_ok=bcd(`GBK_MACHINE_VALIDATOR_WORD[7:0],8'h00,8'h23) && bcd(`GBK_MACHINE_VALIDATOR_WORD[15:8],8'h00,8'h59) &&
                bcd(`GBK_MACHINE_VALIDATOR_WORD[23:16],8'h00,8'h59) && (`GBK_MACHINE_VALIDATOR_WORD[31:24] & ~8'h6a)==0;
            133829:payload_ok=`GBK_MACHINE_VALIDATOR_WORD[31:2]==0;
            default:begin end
        endcase
    end
    gba_state_image_validator #(.SECTION_COUNT(9),.CHECK_PAYLOAD(1),.READ_TIMEOUT(READ_TIMEOUT),.CRC_BITS(CRC_BITS),.LATCH_IDENTITY(LATCH_IDENTITY)) container(
        .clk,.reset,.start,.scan_only,.scan_begin,.scan_bytes,.scan_crc,
        .rom_crc,.rom_bytes,.bios_crc,
`ifdef GBK_GAMEPAK_PREFETCH
        .layout_crc(32'h47465332),
`else
        .layout_crc(32'h47465331),
`endif
        .section_index,.expected_section_id({28'd0,section_index}+1),.expected_section_bytes(section_bytes),
`ifdef GBK_FAST_FORWARD
        .payload_data(validated_word),
`endif
        .read_req,.read_addr,.read_valid,.read_data,.payload_valid,.payload_word_index(payload_word),.payload_word_ok(payload_ok),
        .busy,.done,.valid,.error_code);
`undef GBK_MACHINE_VALIDATOR_WORD
endmodule
