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
