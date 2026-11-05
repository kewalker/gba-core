// Identity of accepted loader bytes. The APF peripheral specifies at least 88
// host clocks per word. A shared 32-clock CRC engine finishes before the next
// write, avoiding a large combinational CRC on the 74.25 MHz host path.
// Unexpected overlap invalidates identity; it never stalls ordinary loading.
module gba_state_identity #(parameter integer BIOS_BYTES=16384)(
    input wire clk,reset,rom_begin,
    input wire [31:0] rom_size,
    input wire rom_write,bios_write,
    input wire [31:0] rom_offset,bios_offset,load_data,
    output wire ready,
    output reg [31:0] rom_crc,rom_bytes,bios_crc
);
    reg rom_complete,bios_complete,rom_ordered,bios_ordered;
    reg [31:0] rom_next,bios_next;
    reg busy,work_rom,work_last;
    reg [31:0] work_crc,work_data;
    reg [5:0] bits_left;
    wire [31:0] size=rom_begin ? rom_size : rom_bytes;
    wire size_valid=size!=0 && size<=32'h02000000;
    wire [2:0] rom_count=(rom_offset[31:2]==size[31:2] && size[1:0]!=0) ?
        {1'b0,size[1:0]} : 3'd4;
    wire [31:0] next_crc=(work_crc>>1) ^
        ((work_crc[0]^work_data[0]) ? 32'hedb88320 : 32'd0);
    assign ready=rom_complete && bios_complete && !busy;
    always @(posedge clk)begin
        if(reset)begin
            rom_complete<=0;bios_complete<=0;rom_ordered<=0;bios_ordered<=0;
            rom_next<=0;bios_next<=0;rom_crc<=0;rom_bytes<=0;bios_crc<=0;
            busy<=0;work_rom<=0;work_last<=0;work_crc<=0;work_data<=0;bits_left<=0;
        end else begin
            if(busy)begin
                work_crc<=next_crc;work_data<=work_data>>1;bits_left<=bits_left-1'b1;
                if(bits_left==1)begin
                    busy<=0;
                    if(work_rom)begin rom_crc<=~next_crc;if(work_last)rom_complete<=1;end
                    else begin bios_crc<=~next_crc;if(work_last)bios_complete<=1;end
                end
            end
            if(rom_begin)begin
                rom_bytes<=rom_size;rom_complete<=0;rom_ordered<=0;rom_next<=0;
                if(busy && work_rom)busy<=0;
            end
            if(rom_write || bios_write)begin
                // Capture descriptors independently of range/order admission.
                // Invalid descriptors never set busy. Keeping validation out
                // of these wide register enables avoids a loader-size compare
                // followed by a high-fanout 32-bit capture enable.
                work_data<=load_data;work_rom<=rom_write;
                work_crc<=rom_write ? (rom_offset==0 ? 32'hffffffff : ~rom_crc) :
                    (bios_offset==0 ? 32'hffffffff : ~bios_crc);
                bits_left<=rom_write ? {rom_count,3'b000} : 6'd32;
                work_last<=rom_write ? size-rom_offset<=4 : bios_offset==BIOS_BYTES-4;
                if(rom_write)rom_complete<=0;
                if(bios_write)bios_complete<=0;
                if(busy || (rom_write && bios_write))begin
                    // A stale work item must never publish completion after
                    // an invalidating load or overwrite another descriptor.
                    busy<=0;
                    if(rom_write || (busy && work_rom))begin rom_complete<=0;rom_ordered<=0;end
                    if(bios_write || (busy && !work_rom))begin bios_complete<=0;bios_ordered<=0;end
                end else if(rom_write)begin
                    if(size_valid && rom_offset[1:0]==0 && rom_offset<size &&
                       (rom_offset==0 || (!rom_begin && rom_ordered && rom_offset==rom_next)))begin
                        busy<=1;
                        rom_next<=rom_offset+4;rom_ordered<=1;
                    end else rom_ordered<=0;
                end else begin
                    if(bios_offset[1:0]==0 && bios_offset<BIOS_BYTES &&
                       (bios_offset==0 || (bios_ordered && bios_offset==bios_next)))begin
                        busy<=1;
                        bios_next<=bios_offset+4;bios_ordered<=1;
                    end else bios_ordered<=0;
                end
            end
        end
    end
endmodule
