// Identity of accepted loader bytes. The APF peripheral specifies at least 88
// host clocks per word. A shared 32-clock CRC engine finishes before the next
// write, avoiding a large combinational CRC on the 74.25 MHz host path.
// Unexpected overlap invalidates identity; it never stalls ordinary loading.
module gba_state_identity #(parameter integer BIOS_BYTES=16384)(
    input wire clk,reset,rom_begin,
    input wire [31:0] rom_size,
    input wire rom_write,bios_write,
    input wire [31:0] rom_offset,bios_offset,load_data,
`ifdef GBK_GAMEPAK_RETAIL_CATALOG
    input wire catalog_active,catalog_begin,catalog_write,
    output wire catalog_crc_idle,
    output wire [31:0] catalog_crc,
    output reg catalog_crc_error=0,
`endif
`ifdef GBK_GAMEPAK_NATIVE_PREFLIGHT
    output wire rom_stream_idle,
`endif
    output wire ready,
    output reg [31:0] rom_crc,rom_bytes,bios_crc
);
    localparam integer BIOS_NEXT_BITS=$clog2(BIOS_BYTES+1);
    reg rom_complete,bios_complete,rom_ordered,bios_ordered;
    reg [23:0] rom_next_word;
    reg [BIOS_NEXT_BITS-1:0] bios_next;
    reg busy,work_rom,work_last;
    reg [31:0] work_crc,work_data;
    reg [5:0] bits_left;
`ifdef GBK_GAMEPAK_RETAIL_CATALOG
    reg work_catalog;
    assign catalog_crc_idle=work_catalog && !busy;
    assign catalog_crc=~work_crc;
`endif
    wire [31:0] size=rom_begin ? rom_size : rom_bytes;
    wire size_valid=size!=0 && size<=32'h02000000;
    // ROM offsets fit in 23 word bits. Keep one more bit for the terminal
    // 32 MiB boundary, and reject out-of-range bridge addresses separately.
    wire [23:0] rom_word={1'b0,rom_offset[24:2]};
    wire [23:0] size_words=size[25:2];
    wire [23:0] next_rom_word=rom_word+1'b1;
    wire valid_word_address=rom_offset[31:25]==0 && rom_offset[1:0]==0;
    wire partial_rom_word=rom_word==size_words && size[1:0]!=0;
    wire [2:0] rom_count=partial_rom_word ?
        {1'b0,size[1:0]} : 3'd4;
    // Accepted offsets are aligned and below the image size. Reuse the
    // continuation increment for aligned ends. Partial ends are in this word.
    wire last_rom_word=partial_rom_word ||
        (size[1:0]==0 && next_rom_word==size_words);
    wire [31:0] next_crc=(work_crc>>1) ^
        ((work_crc[0]^work_data[0]) ? 32'hedb88320 : 32'd0);
    assign ready=rom_complete && bios_complete && !busy;
`ifdef GBK_GAMEPAK_NATIVE_PREFLIGHT
    assign rom_stream_idle=!busy && !catalog_active;
`endif
    always @(posedge clk)begin
        if(reset)begin
            rom_complete<=0;bios_complete<=0;rom_ordered<=0;bios_ordered<=0;
            rom_next_word<=0;bios_next<=0;rom_crc<=0;rom_bytes<=0;bios_crc<=0;
            busy<=0;work_rom<=0;work_last<=0;work_crc<=0;work_data<=0;bits_left<=0;
`ifdef GBK_GAMEPAK_RETAIL_CATALOG
            work_catalog<=0;catalog_crc_error<=0;
`endif
        end else begin
            if(busy)begin
                work_crc<=next_crc;work_data<=work_data>>1;bits_left<=bits_left-1'b1;
                if(bits_left==1)begin
                    busy<=0;
`ifdef GBK_GAMEPAK_RETAIL_CATALOG
                    if(!work_catalog)begin
`endif
                    if(work_rom)begin rom_crc<=~next_crc;if(work_last)rom_complete<=1;end
                    else begin bios_crc<=~next_crc;if(work_last)bios_complete<=1;end
`ifdef GBK_GAMEPAK_RETAIL_CATALOG
                    end
`endif
                end
            end
            if(rom_begin)begin
                rom_bytes<=rom_size;rom_complete<=0;rom_ordered<=0;rom_next_word<=0;
                if(busy && work_rom)busy<=0;
            end
`ifdef GBK_GAMEPAK_RETAIL_CATALOG
            // The catalog is read outside the ROM and BIOS load windows.
            // Keep its rolling CRC in the shared datapath, so the published
            // ROM and BIOS identities survive a post-copy catalog scan.
            if(catalog_begin)begin
                catalog_crc_error<=busy || rom_write || bios_write || rom_begin;
                work_catalog<=1;work_crc<=32'hffffffff;busy<=0;
            end else if(catalog_active && (rom_write || bios_write || rom_begin))begin
                catalog_crc_error<=1;
            end else if(catalog_write)begin
                if(!catalog_crc_idle)catalog_crc_error<=1;
                else begin work_data<=load_data;bits_left<=6'd32;busy<=1;end
            end else
`endif
            if(rom_write || bios_write)begin
                // Capture descriptors independently of range/order admission.
                // Invalid descriptors never set busy. Keeping validation out
                // of these wide register enables avoids a loader-size compare
                // followed by a high-fanout 32-bit capture enable.
                work_data<=load_data;work_rom<=rom_write;
`ifdef GBK_GAMEPAK_RETAIL_CATALOG
                work_catalog<=0;
`endif
                work_crc<=rom_write ? (rom_word==0 ? 32'hffffffff : ~rom_crc) :
                    (bios_offset==0 ? 32'hffffffff : ~bios_crc);
                bits_left<=rom_write ? {rom_count,3'b000} : 6'd32;
                work_last<=rom_write ? last_rom_word : bios_offset==BIOS_BYTES-4;
                if(rom_write)rom_complete<=0;
                if(bios_write)bios_complete<=0;
                if(busy || (rom_write && bios_write))begin
                    // A stale work item must never publish completion after
                    // an invalidating load or overwrite another descriptor.
                    busy<=0;
                    if(rom_write || (busy && work_rom))begin rom_complete<=0;rom_ordered<=0;end
                    if(bios_write || (busy && !work_rom))begin bios_complete<=0;bios_ordered<=0;end
                end else if(rom_write)begin
                    // A stream begins at zero and advances one word until
                    // its last word completes. No ordered stream can reach
                    // an offset past the image before that completion.
                    if(size_valid && valid_word_address &&
                       (rom_word==0 || (!rom_begin && rom_ordered && !rom_complete && rom_word==rom_next_word)))begin
                        busy<=1;
                        rom_next_word<=next_rom_word;rom_ordered<=1;
                    end else rom_ordered<=0;
                end else begin
                    if(bios_offset[1:0]==0 && bios_offset<BIOS_BYTES &&
                       (bios_offset==0 || (bios_ordered && bios_offset==bios_next)))begin
                        busy<=1;
                        // A range-checked word advances no further than
                        // BIOS_BYTES. Retain that terminal offset without a
                        // full bridge-width incrementer and register bank.
                        bios_next<=bios_offset[BIOS_NEXT_BITS-1:0]+BIOS_NEXT_BITS'(4);
                        bios_ordered<=1;
                    end else bios_ordered<=0;
                end
            end
        end
    end
endmodule
