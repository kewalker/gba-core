// APF VIDEO is a pixel stream with one-clock sync events, not raster sync
// regions. Register all data/control together before the APF DDR serializer.
module gba_apf_video_out (
    input  wire clk, reset,
    input  wire [23:0] rgb_in,
    input  wire de_in, skip_in, hs_region, vs_region,
    output reg [23:0] rgb,
    output reg de, skip, hs, vs
);
    reg hs_previous,vs_previous;
    wire hs_start=hs_region && !hs_previous;
    wire vs_start=vs_region && !vs_previous;
    always @(posedge clk) begin
        if(reset) begin
            rgb<=0;de<=0;skip<=0;hs<=0;vs<=0;
            hs_previous<=0;vs_previous<=0;
        end else begin
            rgb<=de_in ? rgb_in : 24'd0;
            de<=de_in;
            // SKIP only suppresses active pixels. Raster counters advance
            // on a dot-enable edge, so their sync region rises immediately
            // before a held/skipped dot. Forwarding that skip marked every
            // one-clock HS/VS event as skipped. Keep blanking and sync events
            // explicitly valid for receivers that qualify control by SKIP.
            skip<=de_in && skip_in && !hs_start && !vs_start;
            // Sync is independent of pixel acceptance. SKIP is meaningful
            // during DE; it must never suppress a line or frame event.
            hs<=hs_start;
            vs<=vs_start;
            hs_previous<=hs_region;
            vs_previous<=vs_region;
        end
    end
endmodule

// Apply mild desaturation before APF output and the playtime overlay.
module gba_soft_colors (
    input wire host_clk,video_clk,video_reset,
    input wire bridge_wr,bridge_rd,bridge_endian_little,
    input wire [31:0] bridge_addr,bridge_wr_data,
    output wire [31:0] bridge_rdata,
    input wire frame_start,
    input wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);
    localparam [31:0] SETTING_ADDRESS=32'h1000001c;
    reg enabled_host=0,readback=0;
    always @(posedge host_clk) begin
        if(bridge_wr && bridge_addr==SETTING_ADDRESS)
            enabled_host<=bridge_endian_little ? bridge_wr_data[24] : bridge_wr_data[0];
        if(bridge_rd && bridge_addr==SETTING_ADDRESS)
            readback<=enabled_host;
    end
    assign bridge_rdata=bridge_endian_little ? {7'd0,readback,24'd0} : {31'd0,readback};

    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [2:0] enabled_sync;
    reg enabled_frame;
    always @(posedge video_clk) begin
        if(video_reset) begin
            enabled_sync<=0;
            enabled_frame<=0;
        end else begin
            enabled_sync<={enabled_sync[1:0],enabled_host};
            if(frame_start) enabled_frame<=enabled_sync[2];
        end
    end

    wire [7:0] red=rgb_in[23:16],green=rgb_in[15:8],blue=rgb_in[7:0];
    // floor((R + 2G + B) / 16) is a quarter of the weighted gray level.
    wire [9:0] weighted_sum={2'b0,red}+{1'b0,green,1'b0}+{2'b0,blue};
    wire [7:0] gray_quarter={2'b0,weighted_sum[9:4]};
    wire [7:0] red_soft=red-{2'b0,red[7:2]}+gray_quarter;
    wire [7:0] green_soft=green-{2'b0,green[7:2]}+gray_quarter;
    wire [7:0] blue_soft=blue-{2'b0,blue[7:2]}+gray_quarter;
    assign rgb_out=enabled_frame ? {red_soft,green_soft,blue_soft} : rgb_in;
endmodule
