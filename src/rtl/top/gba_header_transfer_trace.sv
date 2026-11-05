// Passive header provenance. RAM contents are meaningful only with valid set.
// The APF shadow is written while the CPU is held in reset; a synchronized
// completion flag qualifies its dual-clock read port after loading finishes.
module gba_header_transfer_trace (
    input wire clk, reset,
    input wire load_clk, load_reset, load_write,
    input wire [21:0] load_addr,
    input wire [31:0] load_data,
    input wire [31:0] last_read_addr, last_read_data,
    input wire [17:0] failure_address,
    output wire [95:0] words,
    output wire [2:0] valid
);
    (* ramstyle = "M10K" *) reg [31:0] loaded_header [0:63];
    (* ramstyle = "M10K" *) reg [31:0] rom_reads [0:63];
    (* ramstyle = "M10K" *) reg [31:0] iwram_reads [0:63];
    reg load_complete;
    reg complete_sync1, complete_sync2;
    reg [63:0] rom_valid, iwram_valid;
    wire [7:0] failure_offset = failure_address[17:16] == 2'd1
        ? failure_address[7:0] + 8'h74 // BIOS 3290 -> ROM 04
        : failure_address[7:0] - 8'h84; // IWRAM 88 -> ROM 04
    wire [5:0] index = failure_offset[7:2];
    wire [7:0] iwram_offset = last_read_addr[7:0] - 8'h84;
    reg [5:0] read_index;
    reg [31:0] loaded_q, rom_q, iwram_q;
    always @(posedge load_clk) begin
        if (load_reset) load_complete <= 0;
        else if (load_write && load_addr < 64) begin
            loaded_header[load_addr[5:0]] <= load_data;
            if (load_addr == 0) load_complete <= 0;
            if (load_addr == 63) load_complete <= 1;
        end
    end
    // No reset on RAM read ports: preserve block-RAM inference.
    always @(posedge clk) begin
        loaded_q <= loaded_header[index];
        rom_q <= rom_reads[index];
        iwram_q <= iwram_reads[index];
        read_index <= index;
        if (!reset && failure_address[17:16] == 0) begin
            if (last_read_addr >= 32'h08000004 && last_read_addr < 32'h080000e0)
                rom_reads[last_read_addr[7:2]] <= last_read_data;
            if (last_read_addr >= 32'h03000088 && last_read_addr < 32'h03000164)
                iwram_reads[iwram_offset[7:2]] <= last_read_data;
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            complete_sync1 <= 0; complete_sync2 <= 0;
            rom_valid <= 0; iwram_valid <= 0;
        end else begin
            complete_sync1 <= load_complete;
            complete_sync2 <= complete_sync1;
            if (failure_address[17:16] == 0) begin
                if (last_read_addr >= 32'h08000004 && last_read_addr < 32'h080000e0)
                    rom_valid[last_read_addr[7:2]] <= 1;
                if (last_read_addr >= 32'h03000088 && last_read_addr < 32'h03000164)
                    iwram_valid[iwram_offset[7:2]] <= 1;
            end
        end
    end
    wire selected = !reset && failure_address[17:16] != 0 && read_index == index;
    // Valid order is APF, CPU ROM, CPU IWRAM (bits 2,1,0).
    assign valid = selected ? {complete_sync2,rom_valid[index],iwram_valid[index]} : 3'b0;
    assign words = {iwram_q,rom_q,loaded_q};
endmodule
