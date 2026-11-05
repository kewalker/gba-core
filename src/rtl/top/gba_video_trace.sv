// Passive game display diagnostics, sampled on the Pocket video clock.
module gba_video_trace (
    input wire clk,reset,
    input wire [31:0] pc,validation_result,irq_counts,
    input wire [15:0] dispcnt,bg0cnt,bg1cnt,bg2cnt,bg3cnt,
    input wire [31:0] interrupt_ie_if,
    input wire [31:0] last_read_addr,last_read_data,
    input wire video_de,video_vs,
    input wire [8:0] video_r,video_g,video_b,
    output wire [351:0] snapshot
);
    reg vs_previous;
    reg [15:0] active_pixels,nonwhite_pixels;
    reg [31:0] frame_pixels,main_callback;
    reg [14:0] last_pixel;
    always @(posedge clk) begin
        if(reset) begin
            vs_previous<=0;active_pixels<=0;nonwhite_pixels<=0;
            frame_pixels<=0;last_pixel<=0;main_callback<=32'hffffffff;
        end else begin
            vs_previous<=video_vs;
            if(video_vs && !vs_previous) begin
                frame_pixels<={nonwhite_pixels,active_pixels};
                active_pixels<=0;nonwhite_pixels<=0;
            end else if(video_de) begin
                active_pixels<=active_pixels+1'b1;
                if({video_b[8:4],video_g[8:4],video_r[8:4]} != 15'h7fff)
                    nonwhite_pixels<=nonwhite_pixels+1'b1;
                last_pixel<={video_b[8:4],video_g[8:4],video_r[8:4]};
            end
            // Emerald BPEE gMain.callback2: retained completed CPU data read.
            if(last_read_addr==32'h030022c4) main_callback<=last_read_data;
        end
    end
    assign snapshot={irq_counts,main_callback,interrupt_ie_if,last_read_data,last_read_addr,
        validation_result,frame_pixels,bg3cnt,1'b0,last_pixel,
        bg2cnt,bg1cnt,bg0cnt,dispcnt,pc};
endmodule
