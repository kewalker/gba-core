// GBA PPU timing plus bitmap modes 3/4/5 and mode-0 regular text layers.
module gba_ppu #(
    parameter logic EXTERNAL_VRAM = 1'b0,
    parameter logic FAST_RENDER = 1'b0,
    parameter logic NATIVE_TIMING = 1'b0,
    parameter logic OBJ_ROWS = 1'b0,
    parameter logic BLOCK_OAM = 1'b0,
    parameter logic OBJ_WORD_READS = 1'b0,
    parameter logic OBJ_TAGGED_READS = 1'b0
) (
`ifdef GBK_SAVESTATE
    input wire state_render_invalidate,
`endif
    input  logic clk,
    input  logic reset,
    input  logic pixel_ce,
    input  logic render_clk,
    input  logic [15:0] dispcnt,
    input wire [15:0] mosaic,
    input  logic        vram_write,
    input  logic [15:0] vram_addr,
    input  logic [15:0] vram_wdata,
    output logic [15:0] vram_read_addr,
    input  logic [15:0] vram_read_data,
    input  logic [15:0] vram_debug0,
    output logic [15:0] bg_map_read_addr,
    input  logic [15:0] bg_map_read_data,
    output logic [15:0] bg_tile_read_addr,
    input  logic [15:0] bg_tile_read_data,
    output logic [15:0] bg1_map_read_addr,
    input  logic [15:0] bg1_map_read_data,
    output logic [15:0] bg1_tile_read_addr,
    input  logic [15:0] bg1_tile_read_data,
    output logic [15:0] bg2_map_read_addr,
    input  logic [15:0] bg2_map_read_data,
    output logic [15:0] bg2_tile_read_addr,
    input  logic [15:0] bg2_tile_read_data,
    output logic [15:0] bg3_map_read_addr,
    input  logic [15:0] bg3_map_read_data,
    output logic [15:0] bg3_tile_read_addr,
    input  logic [15:0] bg3_tile_read_data,
    output logic [16:0] obj_tile_read_addr,
    input  logic [15:0] obj_tile_read_data,
    input  wire [31:0] obj_tile_read_word,
    input  wire [15:0] obj_tile_read_word_addr,
    input  wire obj_tile_read_word_valid,
    output logic [50:0] obj_window_extra_read_addr,
    input logic [47:0] obj_window_extra_read_data,
    input  logic [8191:0] oam_data_flat,
    output wire [6:0] oam_read_addr,
    input wire [63:0] oam_read_data,
    input  logic [15:0] bg0cnt,
    input  logic [8:0]  bg0hofs,
    input  logic [8:0]  bg0vofs,
    input  logic [15:0] bg1cnt,
    input  logic [8:0]  bg1hofs,
    input  logic [8:0]  bg1vofs,
    input  logic [15:0] bg2cnt,
    input  logic [8:0]  bg2hofs,
    input  logic [8:0]  bg2vofs,
    input  logic [15:0] bg3cnt,
    input  logic [8:0]  bg3hofs,
    input  logic [8:0]  bg3vofs,
    input  logic [15:0] bg3pa,
    input  logic [15:0] bg3pb,
    input  logic [15:0] bg3pc,
    input  logic [15:0] bg3pd,
    input  logic [27:0] bg3refx,
    input  logic [27:0] bg3refy,
    input wire [15:0] bg2pa,bg2pb,bg2pc,bg2pd,
    input wire [27:0] bg2refx,bg2refy,
    input  logic [15:0] win0h,
    input  logic [15:0] win1h,
    input  logic [15:0] win0v,
    input  logic [15:0] win1v,
    input  logic [15:0] winin,
    input  logic [15:0] winout,
    input wire [15:0] bldcnt,bldalpha,bldy,
    output wire [8:0] second_palette_read_addr,
    input wire [15:0] second_palette_read_data,
    output logic [8:0]  palette_read_addr,
    input  logic [15:0] palette_read_data,
    output logic [8:0]  bg_palette_read_addr,
    input  logic [15:0] bg_palette_read_data,
    input  logic [15:0] backdrop_color,
    output logic [8:0]  obj_palette_read_addr,
    input  logic [15:0] obj_palette_read_data,
    output logic [8:0]  r,
    output logic [8:0]  g,
    output logic [8:0]  b,
    output logic        de,
    output logic        hsync,
    output logic        vsync,
    output wire         video_skip,
    output wire [16:0] raster_position,
    output logic [15:0] debug_pixel0,
    output logic [15:0] debug_mode2_status,
    output logic [31:0] debug_mode2_window
);

    localparam int ACTIVE_W = 240;
`ifdef GBK_SAVESTATE
    wire state_cache_reset=reset || state_render_invalidate===1'b1;
`endif
    localparam int ACTIVE_H = 160;
    // Native timing matches the reference GBA raster: 308 dots x 228 lines.
    // Keep the legacy raster available for existing isolated renderer tests.
    localparam int H_FRONT = NATIVE_TIMING ? 10 : 16;
    localparam int H_SYNC = NATIVE_TIMING ? 20 : 16;
    localparam int H_BACK = NATIVE_TIMING ? 38 : 48;
    localparam int V_FRONT = NATIVE_TIMING ? 5 : 8;
    localparam int V_SYNC = NATIVE_TIMING ? 5 : 4;
    localparam int V_BACK = NATIVE_TIMING ? 58 : 468;
    localparam int TOTAL_W = ACTIVE_W + H_FRONT + H_SYNC + H_BACK;
    localparam int TOTAL_H = ACTIVE_H + V_FRONT + V_SYNC + V_BACK;

    // 128/375 * 12.288 MHz is exactly the 4.194304 MHz GBA dot rate.
    // APF ignores held pixels via video_skip; RGB and sync share one enable.
    logic [8:0] video_phase;
    wire video_advance = !NATIVE_TIMING || video_phase >= 9'd247;
    assign video_skip = NATIVE_TIMING && !video_advance;
    always_ff @(posedge clk) begin
        if (reset) video_phase <= 0;
        else if (NATIVE_TIMING)
            video_phase <= video_advance ? video_phase - 9'd247 : video_phase + 9'd128;
    end

    logic [$clog2(TOTAL_W)-1:0] x;
    logic [$clog2(TOTAL_H)-1:0] y;
    assign raster_position={8'(y),9'(x)};
    wire [9:0] mosaic_x,mosaic_y;
    wire [3:0] mosaic_line_remainder;
    // Register the lookup alongside the raster, using the same next coordinate.
    // A render-clock lookup would launch a complete affine address calculation
    // every 7.5 ns although its inputs only change at the held video dot rate.
    wire raster_step=video_advance && (!FAST_RENDER || pixel_ce);
    wire [9:0] next_mosaic_x=reset ? 10'd0 : raster_step ?
        (x==TOTAL_W-1 ? 10'd0 : 10'(x)+1'b1) : 10'(x);
    wire [9:0] next_mosaic_y=reset ? 10'd0 : raster_step && x==TOTAL_W-1 ?
        (y==TOTAL_H-1 ? 10'd0 : 10'(y)+1'b1) : 10'(y);
    gba_mosaic_coordinate #(.COORD_BITS($clog2(TOTAL_W))) mosaic_horizontal(.clk(clk),.coordinate(next_mosaic_x),.size(mosaic[3:0]),.snapped(mosaic_x));
    gba_mosaic_coordinate #(.COORD_BITS($clog2(TOTAL_H))) mosaic_vertical(.clk(clk),.coordinate(next_mosaic_y),.size(mosaic[7:4]),.snapped(mosaic_y),.remainder_value(mosaic_line_remainder));
    wire [15:0] affine2_map_addr,affine2_tile_addr;
    wire [7:0] affine2_palette;
    wire [9:0] affine2_screen_x=bg2cnt[6] ? mosaic_x : {1'b0,x};
    // The registered lookup already supplies y - snapped_y, bounded 0..15.
    // Keep that narrow value instead of subtracting two raster coordinates
    // before the affine correction multipliers on the video/render crossing.
    wire [3:0] affine2_line_offset=bg2cnt[6] ? mosaic_line_remainder : 4'd0;
    wire signed [27:0] affine2_refx=$signed(bg2refx)-$signed(bg2pb)*$signed({1'b0,affine2_line_offset});
    wire signed [27:0] affine2_refy=$signed(bg2refy)-$signed(bg2pd)*$signed({1'b0,affine2_line_offset});
    gba_affine_background affine2(.screen_x(affine2_screen_x),.refx(affine2_refx),.refy(affine2_refy),
        .pa(bg2pa),.pc(bg2pc),.cnt(bg2cnt),.map_data(bg2_map_read_data),.tile_data(bg2_tile_read_data),
        .map_addr(affine2_map_addr),.tile_addr(affine2_tile_addr),.palette(affine2_palette));
    wire [9:0] cache_y=y;
    logic [15:0] pixel;
    logic [15:0] pixel_index;
    logic [15:0] pixel_reg;
    logic [15:0] framebuffer_pixel;
    logic [31:0] bitmap_index;
    logic [2:0]  mode;
    logic        bitmap_visible;
    logic [7:0]  mode4_index_pixel;
    logic [15:0] bg_map_addr_calc;
    logic [15:0] bg_tile_addr_calc;
    logic [15:0] bg_tile_pixel;
    logic [7:0]  bg_palette_index;
    logic        bg_visible;
    logic [9:0]  bg_x;
    logic [9:0]  bg_y;
    logic [5:0]  bg_tile_x;
    logic [5:0]  bg_tile_y;
    logic [2:0]  bg_pixel_x;
    logic [2:0]  bg_pixel_y;
    logic [2:0]  bg_sample_x;
    logic [2:0]  bg_sample_y;
    logic [9:0]  bg_tile_number;
    logic [3:0]  bg_palette_bank;
    logic [15:0] bg1_tile_addr_calc;
    logic [15:0] bg1_tile_pixel;
    logic [7:0]  bg1_palette_index;
    logic [9:0]  bg1_x, bg1_y;
    logic [5:0]  bg1_tile_x, bg1_tile_y;
    logic [2:0]  bg1_pixel_x, bg1_pixel_y;
    logic [2:0]  bg1_sample_x, bg1_sample_y;
    logic [9:0]  bg1_tile_number;
    logic [3:0]  bg1_palette_bank;
    logic [15:0] bg2_tile_addr_calc, bg2_tile_pixel;
    logic [7:0]  bg2_palette_index;
    logic [9:0]  bg2_x, bg2_y;
    logic [5:0]  bg2_tile_x, bg2_tile_y;
    logic [2:0]  bg2_pixel_x, bg2_pixel_y;
    logic [2:0]  bg2_sample_x, bg2_sample_y;
    logic [9:0]  bg2_tile_number;
    logic [3:0]  bg2_palette_bank;
    logic [15:0] bg3_tile_addr_calc, bg3_tile_pixel;
    logic [7:0]  bg3_palette_index;
    logic [9:0]  bg3_x, bg3_y;
    logic [5:0]  bg3_tile_x, bg3_tile_y;
    logic [2:0]  bg3_pixel_x, bg3_pixel_y;
    logic [2:0]  bg3_sample_x, bg3_sample_y;
    logic [9:0]  bg3_tile_number;
    logic [3:0]  bg3_palette_bank;
    logic signed [27:0] bg3_affine_x_raw, bg3_affine_y_raw;
    logic signed [19:0] bg3_affine_x_int, bg3_affine_y_int;
    logic [9:0] bg3_affine_x, bg3_affine_y;

    logic [9:0] bg3_affine_mask;
    logic [13:0] bg3_affine_map_index;
    logic [15:0] bg3_affine_map_byte_addr, bg3_affine_tile_byte_addr;
    logic [7:0] bg3_affine_tile_number;
    logic bg3_affine_outside;
    logic        bg0_active, bg1_active, bg2_active, bg3_active, bg3_fetch_active;
    logic        win0_inside, win1_inside, window_active;
    logic [4:0]  window_bg_allowed;
    logic        window_obj_allowed;
    logic window_effects_allowed;
    logic        obj_window_found, obj_window_opaque;
    logic [16:0] obj_window_tile_addr;
    logic [15:0] obj_window_tile_pixel;
    logic [7:0]  obj_window_pixel_index;
    logic        obj_window_8bpp;
    logic [5:0]  obj_window_sample_x, obj_window_sample_y;
    logic [6:0]  obj_window_width, obj_window_height;
    logic [6:0]  obj_window_rel_x, obj_window_rel_y;
    logic [8:0]  obj_window_rel_x_wrapped;
    logic [7:0]  obj_window_rel_y_wrapped;
    logic [3:0]  obj_window_tiles_per_row;
    logic [1:0]  obj_window_shape, obj_window_size;
    logic [9:0]  obj_window_tile_number;
    logic [10:0] obj_window_tile_offset;
    logic        obj_window_hflip, obj_window_vflip;
    integer obj_window_i;
    logic [7:0]  bg_selected_palette_index;
    logic        obj_active, obj_selected, obj_found;
    logic [7:0]  obj_palette_index;
    logic [1:0]  obj_priority;
    logic [16:0] obj_tile_addr_calc;
    logic [15:0] obj_tile_pixel;
    logic [1:0]  bg_selected_priority;
    logic [3:0]  bg_opaque;
    logic [3:0]  bg_wins;
    logic        obj_8bpp;
    logic [5:0]  obj_sample_x, obj_sample_y;
    logic [6:0]  obj_width, obj_height, obj_rel_x, obj_rel_y;
    logic [8:0] obj_rel_x_wrapped;
    logic [7:0] obj_rel_y_wrapped;
    logic [3:0]  obj_tiles_per_row;
    logic [1:0]  obj_shape, obj_size;
    logic [9:0]  obj_tile_number;
    logic [10:0] obj_tile_offset;
    logic        obj_hflip, obj_vflip;
    logic obj_semi;
    logic [3:0]  obj_palette_bank;
    integer sprite_i;
    wire [7:0] row_obj_palette;
    wire [1:0] row_obj_priority;
    wire [16:0] row_obj_addr;
    wire row_obj_window;
    wire row_obj_semi;
    wire effective_obj_window=OBJ_ROWS ? row_obj_window && dispcnt[12] : obj_window_opaque;
    generate if(OBJ_ROWS) begin : object_rows
        gba_obj_row_cache #(.EXTERNAL_OAM(BLOCK_OAM),.WORD_READS(OBJ_WORD_READS),.VIDEO_CDC(!FAST_RENDER),.TAGGED_READS(OBJ_TAGGED_READS)) rows(.clk(render_clk),.video_clk(clk),
`ifdef GBK_SAVESTATE
            .reset(state_cache_reset),
`else
            .reset,
`endif
            .x,.y(y[7:0]),.dispcnt,.mosaic(mosaic[15:8]),
            .oam_addr(oam_read_addr),.oam_data(oam_read_data),
            .oam(oam_data_flat),.tile_addr(row_obj_addr),.tile_data(obj_tile_read_data),
            .tile_word_data(obj_tile_read_word),
            .tile_word_addr(obj_tile_read_word_addr),.tile_word_valid(obj_tile_read_word_valid),
            .palette_index(row_obj_palette),.pixel_priority(row_obj_priority),
            .semi_transparent(row_obj_semi),
            .window_opaque(row_obj_window),.overrun());
    end else begin : legacy_objects
        assign row_obj_palette=0;assign row_obj_priority=3;
        assign row_obj_addr=0;assign row_obj_window=0;
        assign row_obj_semi=0;
        assign oam_read_addr=0;
    end endgenerate

    wire [15:0] legacy_text_map0,legacy_text_tile0,legacy_text_map1,legacy_text_tile1,legacy_text_map2,legacy_text_tile2;
`ifdef GBK_POCKET
    wire [7:0] cached_palette0,cached_palette1,cached_palette2,cached_palette3;
    wire [15:0] cached_map3,cached_tile3,cached_map2,cached_tile2;
    wire [15:0] affine_map3,affine_tile3;
    wire [7:0] affine_palette3;
    generate if(EXTERNAL_VRAM && !FAST_RENDER) begin : text_rows
        wire [19:0] control_coordinates;
        wire [9:0] mosaic_control_x,mosaic_control_y;
        gba_mosaic_coordinate #(.COORD_BITS(NATIVE_TIMING ? 8 : $clog2(TOTAL_W))) control_horizontal(.clk(render_clk),.coordinate({1'b0,control_coordinates[8:0]}),.size(mosaic[3:0]),.snapped(mosaic_control_x));
        gba_mosaic_coordinate #(.COORD_BITS($clog2(TOTAL_H))) control_vertical(.clk(render_clk),.coordinate(control_coordinates[18:9]),.size(mosaic[7:4]),.snapped(mosaic_control_y));
        if(NATIVE_TIMING) begin : protected_requests
            gba_render_coordinate_transfer #(.FRAME_LINES(TOTAL_H)) coordinate_transfer(.video_clk(clk),.render_clk,
`ifdef GBK_SAVESTATE
                .reset(state_cache_reset),
`else
                .reset,
`endif
                .video_coordinates({cache_y,x}),.render_coordinates(control_coordinates));
        end else begin : legacy_requests
            assign control_coordinates={1'b0,cache_y,x};
        end
        gba_text_row_cache #(.FRAME_LINES(TOTAL_H),.COHERENT_CONTROL(NATIVE_TIMING)) bg0(.clk(render_clk),
`ifdef GBK_SAVESTATE
            .reset(state_cache_reset),
`else
            .reset,
`endif
            .enabled(mode<=1 && dispcnt[8]),.x(bg0cnt[6] ? mosaic_x[8:0] : x),.y(bg0cnt[6] ? mosaic_y : cache_y),
            .control_x(bg0cnt[6] ? mosaic_control_x[8:0] : control_coordinates[8:0]),.control_y(bg0cnt[6] ? mosaic_control_y : control_coordinates[18:9]),
            .control_blank(control_coordinates[19]),
            .cnt(bg0cnt),.hofs(bg0hofs),.vofs(bg0vofs),.map_addr(bg_map_read_addr),.tile_addr(bg_tile_read_addr),
            .map_data(bg_map_read_data),.tile_data(bg_tile_read_data),.palette_index(cached_palette0));
        gba_text_row_cache #(.FRAME_LINES(TOTAL_H),.COHERENT_CONTROL(NATIVE_TIMING)) bg1(.clk(render_clk),
`ifdef GBK_SAVESTATE
            .reset(state_cache_reset),
`else
            .reset,
`endif
            .enabled(mode<=1 && dispcnt[9]),.x(bg1cnt[6] ? mosaic_x[8:0] : x),.y(bg1cnt[6] ? mosaic_y : cache_y),
            .control_x(bg1cnt[6] ? mosaic_control_x[8:0] : control_coordinates[8:0]),.control_y(bg1cnt[6] ? mosaic_control_y : control_coordinates[18:9]),
            .control_blank(control_coordinates[19]),
            .cnt(bg1cnt),.hofs(bg1hofs),.vofs(bg1vofs),.map_addr(bg1_map_read_addr),.tile_addr(bg1_tile_read_addr),
            .map_data(bg1_map_read_data),.tile_data(bg1_tile_read_data),.palette_index(cached_palette1));
        gba_text_row_cache #(.FRAME_LINES(TOTAL_H),.COHERENT_CONTROL(NATIVE_TIMING)) bg2(.clk(render_clk),
`ifdef GBK_SAVESTATE
            .reset(state_cache_reset),
`else
            .reset,
`endif
            .enabled(mode==0 && dispcnt[10]),.x(bg2cnt[6] ? mosaic_x[8:0] : x),.y(bg2cnt[6] ? mosaic_y : cache_y),
            .control_x(bg2cnt[6] ? mosaic_control_x[8:0] : control_coordinates[8:0]),.control_y(bg2cnt[6] ? mosaic_control_y : control_coordinates[18:9]),
            .control_blank(control_coordinates[19]),
            .cnt(bg2cnt),.hofs(bg2hofs),.vofs(bg2vofs),.map_addr(cached_map2),.tile_addr(cached_tile2),
            .map_data(bg2_map_read_data),.tile_data(bg2_tile_read_data),.palette_index(cached_palette2));
        gba_text_row_cache #(.FRAME_LINES(TOTAL_H),.COHERENT_CONTROL(NATIVE_TIMING)) bg3(.clk(render_clk),
`ifdef GBK_SAVESTATE
            .reset(state_cache_reset),
`else
            .reset,
`endif
            .enabled(mode==0 && dispcnt[11]),.x(bg3cnt[6] ? mosaic_x[8:0] : x),.y(bg3cnt[6] ? mosaic_y : cache_y),
            .control_x(bg3cnt[6] ? mosaic_control_x[8:0] : control_coordinates[8:0]),.control_y(bg3cnt[6] ? mosaic_control_y : control_coordinates[18:9]),
            .control_blank(control_coordinates[19]),
            .cnt(bg3cnt),.hofs(bg3hofs),.vofs(bg3vofs),.map_addr(cached_map3),.tile_addr(cached_tile3),
            .map_data(bg3_map_read_data),.tile_data(bg3_tile_read_data),.palette_index(cached_palette3));
        assign affine_map3=(mode==1 ? de && dispcnt[10] : bg3_fetch_active) ? bg3_affine_map_byte_addr>>1 : 16'd0;
        assign bg2_map_read_addr=mode==2 ? affine2_map_addr : cached_map2;
        assign bg2_tile_read_addr=mode==2 ? affine2_tile_addr : cached_tile2;
        assign affine_tile3=(mode==1 ? de && dispcnt[10] : bg3_fetch_active) ? bg3_affine_tile_byte_addr>>1 : 16'd0;
        assign affine_palette3=bg3_affine_outside ? 8'd0 :
            (bg3_affine_tile_byte_addr[0] ? bg3_tile_read_data[15:8] : bg3_tile_read_data[7:0]);
    end else begin : direct_text
        assign bg_map_read_addr=legacy_text_map0;assign bg_tile_read_addr=legacy_text_tile0;
        assign bg1_map_read_addr=legacy_text_map1;assign bg1_tile_read_addr=legacy_text_tile1;
        assign bg2_map_read_addr=mode==2 ? affine2_map_addr : legacy_text_map2;assign bg2_tile_read_addr=mode==2 ? affine2_tile_addr : legacy_text_tile2;
        assign cached_map2=0;assign cached_tile2=0;
        assign cached_map3=0;assign cached_tile3=0;assign cached_palette3=0;
        assign affine_map3=bg3_fetch_active ? bg3_affine_map_byte_addr>>1 : 16'd0;
        assign affine_tile3=bg3_fetch_active ? bg3_affine_tile_byte_addr>>1 : 16'd0;
        assign affine_palette3=bg3_affine_outside ? 8'd0 :
            (bg3_affine_tile_byte_addr[0] ? bg3_tile_read_data[15:8] : bg3_tile_read_data[7:0]);
        assign cached_palette0=bg_palette_index;assign cached_palette1=bg1_palette_index;assign cached_palette2=bg2_palette_index;
    end endgenerate
`else
    assign bg_map_read_addr=legacy_text_map0;assign bg_tile_read_addr=legacy_text_tile0;
    assign bg1_map_read_addr=legacy_text_map1;assign bg1_tile_read_addr=legacy_text_tile1;
    assign bg2_map_read_addr=mode==2 ? affine2_map_addr : legacy_text_map2;assign bg2_tile_read_addr=mode==2 ? affine2_tile_addr : legacy_text_tile2;
`endif
    assign mode = dispcnt[2:0];
    assign de = (x < ACTIVE_W) && (y < ACTIVE_H);
    assign hsync = (x >= ACTIVE_W + H_FRONT) &&
                   (x < ACTIVE_W + H_FRONT + H_SYNC);
    assign vsync = (y >= ACTIVE_H + V_FRONT) &&
                   (y < ACTIVE_H + V_FRONT + V_SYNC);

    // Mode 2 has no bitmap framebuffer fetch. Reuse that already-scheduled
    // VRAM slot for the BIOS's OBJ-window mask, leaving the normal OBJ slot
    // available for visible sprites in the same pixel.
    assign vram_read_addr = (mode == 2 && dispcnt[15]) ? obj_window_tile_addr[15:0] :
        bitmap_visible ?
        (mode == 3) ? bitmap_index[15:0] :
        (mode == 4) ? bitmap_index[16:1] : bitmap_index[15:0] : 16'd0;
    assign mode4_index_pixel = bitmap_index[0] ? framebuffer_pixel[15:8] : framebuffer_pixel[7:0];
    assign palette_read_addr = (bitmap_visible && mode == 4) ? {1'b0, mode4_index_pixel} :
                               9'd0;
    always_comb begin
        // GBA window coordinates are inclusive start / exclusive end.  A
        // wrapped interval is treated as the union of the two edge ranges.
        win0_inside = (((x[7:0] >= win0h[15:8]) && (x[7:0] < win0h[7:0])) ||
                       ((win0h[15:8] > win0h[7:0]) &&
                        ((x[7:0] >= win0h[15:8]) || (x[7:0] < win0h[7:0])))) &&
                      (((y[7:0] >= win0v[15:8]) && (y[7:0] < win0v[7:0])) ||
                       ((win0v[15:8] > win0v[7:0]) &&
                        ((y[7:0] >= win0v[15:8]) || (y[7:0] < win0v[7:0]))));
        win1_inside = (((x[7:0] >= win1h[15:8]) && (x[7:0] < win1h[7:0])) ||
                       ((win1h[15:8] > win1h[7:0]) &&
                        ((x[7:0] >= win1h[15:8]) || (x[7:0] < win1h[7:0])))) &&
                      (((y[7:0] >= win1v[15:8]) && (y[7:0] < win1v[7:0])) ||
                       ((win1v[15:8] > win1v[7:0]) &&
                        ((y[7:0] >= win1v[15:8]) || (y[7:0] < win1v[7:0]))));
        window_active = de && (dispcnt[13] || dispcnt[14] ||
                               ((OBJ_ROWS || mode == 2) && dispcnt[15]));
        window_bg_allowed = 5'b11111;
        window_obj_allowed = 1'b1;
        window_effects_allowed = 1'b1;
        if (window_active) begin
            if (dispcnt[13] && win0_inside) begin
                window_bg_allowed = winin[4:0];
                window_obj_allowed = winin[4];
                window_effects_allowed = winin[5];
            end else if (dispcnt[14] && win1_inside) begin
                window_bg_allowed = winin[12:8];
                window_obj_allowed = winin[12];
                window_effects_allowed = winin[13];
            end else if ((OBJ_ROWS || mode == 2) && dispcnt[15] && effective_obj_window) begin
                window_bg_allowed = winout[12:8];
                window_obj_allowed = winout[12];
                window_effects_allowed = winout[13];
            end else begin
                window_bg_allowed = winout[4:0];
                window_obj_allowed = winout[4];
                window_effects_allowed = winout[5];
            end
        end
    end
`ifdef GBK_POCKET
    // Text mode uses WIN0/WIN1. Keep its mask independent of the affine
    // OBJ-window reads so those reads cannot enter the text priority path.
    wire [3:0] text_window_allowed = !(dispcnt[13] || dispcnt[14] || (OBJ_ROWS && dispcnt[15])) ? 4'hf :
        dispcnt[13] && win0_inside ? winin[3:0] :
        dispcnt[14] && win1_inside ? winin[11:8] :
        OBJ_ROWS && dispcnt[15] && row_obj_window ? winout[11:8] : winout[3:0];
    assign bg0_active = (mode <= 1) && de && dispcnt[8] && text_window_allowed[0];
    assign bg1_active = (mode <= 1) && de && dispcnt[9] && text_window_allowed[1];
    assign bg2_active = (mode <= 2) && de && dispcnt[10] && (mode==2 ? window_bg_allowed[2] : text_window_allowed[2]);
    assign bg3_fetch_active = ((mode == 0) || (mode == 2)) && de && dispcnt[11];
    assign bg3_active = bg3_fetch_active &&
        (mode == 0 ? text_window_allowed[3] : window_bg_allowed[3]);
`else
    assign bg0_active = (mode == 0) && de && dispcnt[8] && window_bg_allowed[0];
    assign bg1_active = (mode == 0) && de && dispcnt[9] && window_bg_allowed[1];
    assign bg2_active = (mode <= 2) && de && dispcnt[10] && window_bg_allowed[2];
    assign bg3_fetch_active = ((mode == 0) || (mode == 2)) && de && dispcnt[11];
    assign bg3_active = bg3_fetch_active && window_bg_allowed[3];
`endif
    assign bg_visible = bg0_active || bg1_active || bg2_active || bg3_active;
    // Resolve the opaque layer with pairwise comparisons. Equal priorities
    // go to the lower BG number, matching the original ordered selection.
`ifdef GBK_POCKET
    // Decode text tile pixels before the priority/palette address stage.
    // There are eleven render clocks per output pixel; this register breaks
    // the measured scheduler -> nibble decode -> priority -> palette path.
    logic [7:0] text_palette0, text_palette1, text_palette2, text_palette3;
    // Production PPU timing runs at the video clock; decode staging must
    // use the fast RAM-render clock, not delay text by a whole video pixel.
    wire text_decode_clk = FAST_RENDER ? clk : render_clk;
    always_ff @(posedge text_decode_clk) begin
        if (reset) begin
            text_palette0 <= 0;
            text_palette1 <= 0;
            text_palette2 <= 0;
            text_palette3 <= 0;
        end else begin
            text_palette0 <= cached_palette0;
            text_palette1 <= cached_palette1;
            text_palette2 <= mode==1 ? affine_palette3 : mode==2 ? affine2_palette : cached_palette2;
            text_palette3 <= mode==2 ? affine_palette3 : cached_palette3;
        end
    end
    assign bg_opaque = {bg3_active && text_palette3 != 0,
                        bg2_active && text_palette2 != 0,
                        bg1_active && text_palette1 != 0,
                        bg0_active && text_palette0 != 0};
`else
    assign bg_opaque = {bg3_active && bg3_palette_index != 0,
                        bg2_active && bg2_palette_index != 0,
                        bg1_active && bg1_palette_index != 0,
                        bg0_active && bg_palette_index != 0};
`endif
    function automatic [3:0] background_winners(input [3:0] opaque,input [7:0] priority_bits);
        integer i,j;
        begin
            background_winners=opaque;
            for(i=0;i<4;i=i+1)
                for(j=0;j<4;j=j+1)
                    if(j!=i && opaque[j] &&
                       ((priority_bits[j*2+:2]<priority_bits[i*2+:2]) ||
                        (j<i && priority_bits[j*2+:2]==priority_bits[i*2+:2])))
                        background_winners[i]=0;
        end
    endfunction
    wire [7:0] background_priorities={bg3cnt[1:0],bg2cnt[1:0],bg1cnt[1:0],bg0cnt[1:0]};
`ifdef GBK_POCKET
    generate if(OBJ_ROWS) begin : parallel_window_priority
        // Rank both possible OBJ-window masks before the late row-window
        // flag arrives. Select the already-ranked result without adding a
        // pixel stage or serializing window selection with BG comparisons.
        wire [3:0] raw_opaque={
            bg3_fetch_active && text_palette3!=0,
            (mode<=2) && de && dispcnt[10] && text_palette2!=0,
            (mode<=1) && de && dispcnt[9] && text_palette1!=0,
            (mode<=1) && de && dispcnt[8] && text_palette0!=0};
        wire no_windows=!(dispcnt[13] || dispcnt[14] || dispcnt[15]);
        wire [3:0] outside_mask=no_windows ? 4'hf :
            dispcnt[13] && win0_inside ? winin[3:0] :
            dispcnt[14] && win1_inside ? winin[11:8] : winout[3:0];
        wire [3:0] object_mask=no_windows ? 4'hf :
            dispcnt[13] && win0_inside ? winin[3:0] :
            dispcnt[14] && win1_inside ? winin[11:8] :
            dispcnt[15] ? winout[11:8] : winout[3:0];
        (* keep *) wire [3:0] outside_winners=background_winners(raw_opaque & outside_mask,background_priorities);
        (* keep *) wire [3:0] object_winners=background_winners(raw_opaque & object_mask,background_priorities);
        assign bg_wins=(row_obj_window && (mode!=2 || dispcnt[12])) ? object_winners : outside_winners;
    end else begin : ordinary_window_priority
        assign bg_wins=background_winners(bg_opaque,background_priorities);
    end endgenerate
`else
    assign bg_wins=background_winners(bg_opaque,background_priorities);
`endif
`ifdef GBK_POCKET
    wire [3:0] composed_wins;
    wire [31:0] composed_palettes;
    wire [7:0] composed_priorities;
    wire [3:0] composed_opaque;
    generate if(OBJ_ROWS) begin : text_composite_pipe
        reg [3:0] winners;
        reg [31:0] palettes;
        reg [7:0] priorities;
        reg [3:0] opaque;
        always_ff @(posedge text_decode_clk) begin
            if(reset) begin winners<=0;palettes<=0;priorities<=8'hff;opaque<=0;end
            else begin
                winners<=bg_wins;
                opaque<=bg_opaque;
                palettes<={text_palette3,text_palette2,text_palette1,text_palette0};
                priorities<={bg3cnt[1:0],bg2cnt[1:0],bg1cnt[1:0],bg0cnt[1:0]};
            end
        end
        assign composed_wins=winners;
        assign composed_palettes=palettes;
        assign composed_priorities=priorities;
        assign composed_opaque=opaque;
    end else begin : direct_text_composite
        assign composed_wins=bg_wins;
        assign composed_opaque=bg_opaque;
        assign composed_palettes={text_palette3,text_palette2,text_palette1,text_palette0};
        assign composed_priorities={bg3cnt[1:0],bg2cnt[1:0],bg1cnt[1:0],bg0cnt[1:0]};
    end endgenerate
    assign bg_selected_palette_index =
        ({8{composed_wins[0]}} & composed_palettes[0+:8]) |
        ({8{composed_wins[1]}} & composed_palettes[8+:8]) |
        ({8{composed_wins[2]}} & composed_palettes[16+:8]) |
        ({8{composed_wins[3]}} & composed_palettes[24+:8]);
    assign bg_selected_priority=(|composed_wins) ?
        (({2{composed_wins[0]}} & composed_priorities[0+:2]) |
         ({2{composed_wins[1]}} & composed_priorities[2+:2]) |
         ({2{composed_wins[2]}} & composed_priorities[4+:2]) |
         ({2{composed_wins[3]}} & composed_priorities[6+:2])) : 2'b11;
`else
    assign bg_selected_palette_index =
        ({8{bg_wins[0]}} & bg_palette_index) |
        ({8{bg_wins[1]}} & bg1_palette_index) |
        ({8{bg_wins[2]}} & bg2_palette_index) |
        ({8{bg_wins[3]}} & bg3_palette_index);
    assign bg_selected_priority =
        (|bg_wins) ?
        (({2{bg_wins[0]}} & bg0cnt[1:0]) |
         ({2{bg_wins[1]}} & bg1cnt[1:0]) |
         ({2{bg_wins[2]}} & bg2cnt[1:0]) |
         ({2{bg_wins[3]}} & bg3cnt[1:0])) : 2'b11;
`endif
`ifdef GBK_POCKET
    assign bg_palette_read_addr = {bg_selected_palette_index, 1'b0};
    wire [7:0] bg_composite_index = bg_selected_palette_index;
`else
    assign bg_palette_read_addr = bg_visible ? {bg_selected_palette_index, 1'b0} : 9'd0;
    wire [7:0] bg_composite_index = bg_selected_palette_index;
`endif
    assign obj_tile_pixel = obj_tile_read_data;
    assign obj_palette_index = OBJ_ROWS ? row_obj_palette : obj_8bpp
        ? (obj_sample_x[0] ? obj_tile_pixel[15:8] : obj_tile_pixel[7:0])
        : ((obj_sample_x[0]
            ? (obj_sample_x[1] ? obj_tile_pixel[15:12] : obj_tile_pixel[7:4])
            : (obj_sample_x[1] ? obj_tile_pixel[11:8] : obj_tile_pixel[3:0])) == 0
            ? 8'd0
            : (obj_sample_x[0]
                ? (obj_sample_x[1] ? obj_tile_pixel[15:12] : obj_tile_pixel[7:4])
                : (obj_sample_x[1] ? obj_tile_pixel[11:8] : obj_tile_pixel[3:0])) +
              (obj_palette_bank << 4));
    assign obj_palette_read_addr = obj_active ? {obj_palette_index, 1'b0} : 9'd0;
    assign obj_active = (OBJ_ROWS ? dispcnt[12] && row_obj_palette!=0 : obj_found) && window_obj_allowed;
    assign obj_selected = obj_active && (obj_palette_index != 0) &&
        (!bg_visible || bg_composite_index == 0 ||
         (OBJ_ROWS ? row_obj_priority : obj_priority) <= bg_selected_priority);
    // Fetches must not depend on the mask they help render. Gating this
    // address by window_obj_allowed creates a scheduler-data -> window-mask
    // -> OBJ geometry -> scheduler-address path too long for 133 MHz.
    assign obj_tile_read_addr = OBJ_ROWS ? row_obj_addr : obj_found ? obj_tile_addr_calc : 17'd0;

    // A non-affine OBJ-window sprite supplies coverage, not a visible OBJ
    // colour. The real BIOS uses nine such sprites to reveal its mode-2 BG3.
    // Union coverage from two overlapping windows (the captured BIOS
    // layout needs at most two). Mode 2 frees a text-BG scheduler slot
    // for the additional mask tile read.
    logic [3:0] window_valid, window_bpp;
    logic [1:0] window_sample [0:3];
    logic [16:0] window_address [0:3];
    integer window_lane, previous_window, selected_window;
    always_comb begin
        previous_window = -1;
        window_valid = 0;
        window_bpp = 0;
        for (integer n=0; n<4; n=n+1) begin
            window_sample[n] = 0;
            window_address[n] = 0;
        end
        for(window_lane=0;window_lane<2;window_lane=window_lane+1) begin
            selected_window = OBJ_SCAN_ENTRIES;
        obj_window_found = 1'b0;
        obj_window_width = 8;
        obj_window_height = 8;
        obj_window_rel_x = 0;
        obj_window_rel_y = 0;
        obj_window_rel_x_wrapped = 0;
        obj_window_rel_y_wrapped = 0;
        obj_window_shape = 0;
        obj_window_size = 0;
        obj_window_8bpp = 1'b0;
        obj_window_tile_number = 0;
        obj_window_hflip = 1'b0;
        obj_window_vflip = 1'b0;
        obj_window_i = 0;
        if (!OBJ_ROWS && mode == 2 && de && dispcnt[15] && dispcnt[12]) begin
        for (obj_window_i = 0; obj_window_i < OBJ_SCAN_ENTRIES; obj_window_i = obj_window_i + 1) begin
            if (!obj_window_found && obj_window_i > previous_window &&
                // Attr0[10:11] selects OBJ-window mode. Attr0[8:9]
                // instead controls affine/disable for a regular OBJ.
                oam_data_flat[(obj_window_i*48) + 10 +: 2] == 2'b10 &&
                oam_data_flat[(obj_window_i*48) + 8 +: 2] == 2'b00) begin
                obj_window_shape = oam_data_flat[(obj_window_i*48) + 14 +: 2];
                obj_window_size = oam_data_flat[(obj_window_i*48) + 30 +: 2];
                case ({obj_window_shape, obj_window_size})
                    4'b0000: begin obj_window_width=8;  obj_window_height=8;  end
                    4'b0001: begin obj_window_width=16; obj_window_height=16; end
                    4'b0010: begin obj_window_width=32; obj_window_height=32; end
                    4'b0011: begin obj_window_width=64; obj_window_height=64; end
                    4'b0100: begin obj_window_width=16; obj_window_height=8;  end
                    4'b0101: begin obj_window_width=32; obj_window_height=8;  end
                    4'b0110: begin obj_window_width=32; obj_window_height=16; end
                    4'b0111: begin obj_window_width=64; obj_window_height=32; end
                    4'b1000: begin obj_window_width=8; obj_window_height=16; end
                    4'b1001: begin obj_window_width=8; obj_window_height=32; end
                    4'b1010: begin obj_window_width=16; obj_window_height=32; end
                    4'b1011: begin obj_window_width=32; obj_window_height=64; end
                    default: begin obj_window_width=8; obj_window_height=8; end
                endcase
                // OBJ coordinates wrap in 9-bit X / 8-bit Y space. In the
                // BIOS animation some window sprites enter across Y=255.
                obj_window_rel_x_wrapped = x - oam_data_flat[(obj_window_i*48) + 16 +: 9];
                obj_window_rel_y_wrapped = y[7:0] - oam_data_flat[(obj_window_i*48) +: 8];
                if (obj_window_rel_x_wrapped < obj_window_width &&
                    obj_window_rel_y_wrapped < obj_window_height) begin
                    obj_window_found = 1'b1;
                    selected_window = obj_window_i;
                    obj_window_rel_x = obj_window_rel_x_wrapped[6:0];
                    obj_window_rel_y = obj_window_rel_y_wrapped[6:0];
                    obj_window_8bpp = oam_data_flat[(obj_window_i*48) + 13];
                    obj_window_tile_number = oam_data_flat[(obj_window_i*48) + 32 +: 10];
                    obj_window_hflip = oam_data_flat[(obj_window_i*48) + 28];
                    obj_window_vflip = oam_data_flat[(obj_window_i*48) + 29];
                end
            end
        end
        end
        obj_window_sample_x = obj_window_hflip ?
            (obj_window_width - 1 - obj_window_rel_x) : obj_window_rel_x;
        obj_window_sample_y = obj_window_vflip ?
            (obj_window_height - 1 - obj_window_rel_y) : obj_window_rel_y;
        obj_window_tiles_per_row = obj_window_width >> 3;
        obj_window_tile_offset = obj_window_tile_number +
            (dispcnt[6]
                ? (((obj_window_sample_y >> 3) * obj_window_tiles_per_row +
                    (obj_window_sample_x >> 3)) << obj_window_8bpp)
                : (((obj_window_sample_y >> 3) << 5) +
                    ((obj_window_sample_x >> 3) << obj_window_8bpp)));
        obj_window_tile_addr = 17'h08000 + (obj_window_tile_offset << 4) +
            (obj_window_sample_y[2:0] * (obj_window_8bpp ? 4 : 2)) +
            (obj_window_8bpp ? {1'b0, obj_window_sample_x[2:1]} :
                                {1'b0, 1'b0, obj_window_sample_x[2]});

            window_valid[window_lane] = obj_window_found;
            window_bpp[window_lane] = obj_window_8bpp;
            window_sample[window_lane] = obj_window_sample_x[1:0];
            window_address[window_lane] = obj_window_tile_addr;
            previous_window = selected_window;
        end
        obj_window_found = window_valid[0];
        obj_window_8bpp = window_bpp[0];
        obj_window_sample_x = {4'b0,window_sample[0]};
        obj_window_tile_addr = window_address[0];
        for(integer n=0;n<3;n=n+1)
            obj_window_extra_read_addr[n*17+:17] = window_address[n+1];
    end
    assign obj_window_tile_pixel = vram_read_data;
    assign obj_window_pixel_index = obj_window_8bpp
        ? (obj_window_sample_x[0] ? obj_window_tile_pixel[15:8] : obj_window_tile_pixel[7:0])
        : (obj_window_sample_x[0]
            ? (obj_window_sample_x[1] ? obj_window_tile_pixel[15:12] : obj_window_tile_pixel[7:4])
            : (obj_window_sample_x[1] ? obj_window_tile_pixel[11:8] : obj_window_tile_pixel[3:0]));
    always_comb begin
        obj_window_opaque = obj_window_found && (obj_window_pixel_index != 0);
        for(integer n=1;n<4;n=n+1) begin
            if(window_valid[n]) begin
                if(window_bpp[n])
                    obj_window_opaque = obj_window_opaque ||
                        ((obj_window_extra_read_data[(n-1)*16+:16] >> (8*window_sample[n][0])) & 16'hff) != 0;
                else
                    obj_window_opaque = obj_window_opaque ||
                        ((obj_window_extra_read_data[(n-1)*16+:16] >> (4*window_sample[n])) & 16'hf) != 0;
            end
        end
    end
    // Keep diagnostic taps off the mode-0 BG priority/palette-address path.
    // That path has less than one render-clock cycle of timing margin.
    // Bits 0..7: window found/opaque, BG3 active/nonzero pixel,
    // BG3 fetch enabled, window permits BG3, nonzero palette data, OBJ active.
    assign debug_mode2_status = {bg3_palette_index,
        obj_active, (bg3_active && bg_palette_read_data != 0),
        window_bg_allowed[3], bg3_fetch_active,
        (bg3_palette_index != 0), bg3_active,
        obj_window_opaque, obj_window_found};
    assign debug_mode2_window = {vram_read_addr, vram_read_data};

    assign bg_x = (bg0cnt[6] ? mosaic_x : {1'b0,x}) + bg0hofs;
    assign bg_y = (bg0cnt[6] ? mosaic_y : 10'(y)) + bg0vofs;
    assign bg_tile_x = bg_x[8:3];
    assign bg_tile_y = bg_y[8:3];
    assign bg_pixel_x = bg_x[2:0];
    assign bg_pixel_y = bg_y[2:0];
    assign bg_sample_x = bg_map_read_data[10] ? (3'd7 - bg_pixel_x) : bg_pixel_x;
    assign bg_sample_y = bg_map_read_data[11] ? (3'd7 - bg_pixel_y) : bg_pixel_y;
    // VRAM read ports use halfword addresses; text calculations previously
    // supplied bytes, doubling both screen-map and character fetch offsets.
    // Colour depth and mosaic do not disable screen-map addressing.
    assign legacy_text_map0 =
        (bg0cnt[12:8] * 16'h0400) + (bg_tile_y[4:0] * 32 + bg_tile_x[4:0]);
    assign bg_tile_number = bg_map_read_data[9:0];
    assign bg_palette_bank = bg_map_read_data[15:12];
    assign bg_tile_addr_calc = {bg0cnt[3:2], 14'b0} +
        (bg0cnt[7]
            ? {bg_tile_number, bg_sample_y, bg_sample_x[2:1], 1'b0}
            : {1'b0, bg_tile_number, bg_sample_y, bg_sample_x[2], 1'b0});
    assign legacy_text_tile0 = bg0_active ? (bg_tile_addr_calc >> 1) : 16'd0;
    assign bg_tile_pixel = bg_tile_read_data;
    assign bg_palette_index = bg0cnt[7]
        ? (bg_sample_x[0] ? bg_tile_pixel[15:8] : bg_tile_pixel[7:0])
        : (bg_sample_x[0]
            ? (bg_sample_x[1] ? bg_tile_pixel[15:12] : bg_tile_pixel[7:4])
            : (bg_sample_x[1] ? bg_tile_pixel[11:8] : bg_tile_pixel[3:0])) +
            (bg_palette_bank << 4);

    assign bg1_x = (bg1cnt[6] ? mosaic_x : {1'b0,x}) + bg1hofs;
    assign bg1_y = (bg1cnt[6] ? mosaic_y : 10'(y)) + bg1vofs;
    assign bg1_tile_x = bg1_x[8:3];
    assign bg1_tile_y = bg1_y[8:3];
    assign bg1_pixel_x = bg1_x[2:0];
    assign bg1_pixel_y = bg1_y[2:0];
    assign bg1_sample_x = bg1_map_read_data[10] ? (3'd7 - bg1_pixel_x) : bg1_pixel_x;
    assign bg1_sample_y = bg1_map_read_data[11] ? (3'd7 - bg1_pixel_y) : bg1_pixel_y;
    assign legacy_text_map1 =
        (bg1cnt[12:8] * 16'h0400) + (bg1_tile_y[4:0] * 32 + bg1_tile_x[4:0]);
    assign bg1_tile_number = bg1_map_read_data[9:0];
    assign bg1_palette_bank = bg1_map_read_data[15:12];
    assign bg1_tile_addr_calc = {bg1cnt[3:2], 14'b0} +
        (bg1cnt[7]
            ? {bg1_tile_number, bg1_sample_y, bg1_sample_x[2:1], 1'b0}
            : {1'b0, bg1_tile_number, bg1_sample_y, bg1_sample_x[2], 1'b0});
    assign legacy_text_tile1 = bg1_active ? (bg1_tile_addr_calc >> 1) : 16'd0;
    assign bg1_tile_pixel = bg1_tile_read_data;
    assign bg1_palette_index = bg1cnt[7]
        ? (bg1_sample_x[0] ? bg1_tile_pixel[15:8] : bg1_tile_pixel[7:0])
        : (bg1_sample_x[0]
            ? (bg1_sample_x[1] ? bg1_tile_pixel[15:12] : bg1_tile_pixel[7:4])
            : (bg1_sample_x[1] ? bg1_tile_pixel[11:8] : bg1_tile_pixel[3:0])) +
            (bg1_palette_bank << 4);

    assign bg2_x = (bg2cnt[6] ? mosaic_x : {1'b0,x}) + bg2hofs;
    assign bg2_y = (bg2cnt[6] ? mosaic_y : 10'(y)) + bg2vofs;
    assign bg2_tile_x = bg2_x[8:3];
    assign bg2_tile_y = bg2_y[8:3];
    assign bg2_pixel_x = bg2_x[2:0];
    assign bg2_pixel_y = bg2_y[2:0];
    assign bg2_sample_x = bg2_map_read_data[10] ? (3'd7 - bg2_pixel_x) : bg2_pixel_x;
    assign bg2_sample_y = bg2_map_read_data[11] ? (3'd7 - bg2_pixel_y) : bg2_pixel_y;
    assign legacy_text_map2 =
        (bg2cnt[12:8] * 16'h0400) + (bg2_tile_y[4:0] * 32 + bg2_tile_x[4:0]);
    assign bg2_tile_number = bg2_map_read_data[9:0];
    assign bg2_palette_bank = bg2_map_read_data[15:12];
    assign bg2_tile_addr_calc = {bg2cnt[3:2], 14'b0} +
        (bg2cnt[7]
            ? {bg2_tile_number, bg2_sample_y, bg2_sample_x[2:1], 1'b0}
            : {1'b0, bg2_tile_number, bg2_sample_y, bg2_sample_x[2], 1'b0});
    assign legacy_text_tile2 = bg2_active ? (bg2_tile_addr_calc >> 1) : 16'd0;
    assign bg2_tile_pixel = bg2_tile_read_data;
    assign bg2_palette_index = mode==2 ? affine2_palette : bg2cnt[7]
        ? (bg2_sample_x[0] ? bg2_tile_pixel[15:8] : bg2_tile_pixel[7:0])
        : (bg2_sample_x[0]
            ? (bg2_sample_x[1] ? bg2_tile_pixel[15:12] : bg2_tile_pixel[7:4])
            : (bg2_sample_x[1] ? bg2_tile_pixel[11:8] : bg2_tile_pixel[3:0])) +
            (bg2_palette_bank << 4);

    // BG3's mode-2 map contains one byte per tile, and its tiles are always
    // 8bpp.  Reference coordinates and matrix elements have eight fractional
    // bits.  Wrapping uses the size-dependent low coordinate bits; otherwise
    // an out-of-bounds sample is transparent.
    // Mode 1 has one affine layer, BG2. Reuse the affine fetch pair that
    // serves BG3 in mode 2, keeping BG0/BG1 text slots independent.
    wire [15:0] affine_cnt=mode==1 ? bg2cnt : bg3cnt;
    wire [15:0] affine_pa=mode==1 ? bg2pa : bg3pa, affine_pb=mode==1 ? bg2pb : bg3pb;
    wire [15:0] affine_pc=mode==1 ? bg2pc : bg3pc, affine_pd=mode==1 ? bg2pd : bg3pd;
    wire [27:0] affine_refx=mode==1 ? bg2refx : bg3refx, affine_refy=mode==1 ? bg2refy : bg3refy;
    wire [9:0] affine_screen_x=affine_cnt[6] ? mosaic_x : {1'b0,x};
    // Move the mode-1 sign to the stable matrix coefficient. Negating the
    // changing ROM remainder put a carry chain before its unregistered DSP.
    // Seventeen coefficient bits preserve negation of -32768 exactly.
    wire signed [10:0] affine_line_coordinate=mode==1 ?
        (affine_cnt[6] ? $signed({7'd0,mosaic_line_remainder}) : 11'sd0) :
        (affine_cnt[6] ? $signed({1'b0,mosaic_y}) : $signed(11'(y)));
    wire signed [16:0] affine_vertical_pb=mode==1 ?
        -$signed({affine_pb[15],affine_pb}) : $signed({affine_pb[15],affine_pb});
    wire signed [16:0] affine_vertical_pd=mode==1 ?
        -$signed({affine_pd[15],affine_pd}) : $signed({affine_pd[15],affine_pd});
    // Preserve parallel multiplier outputs. Cascaded multiply-add inference
    // sent a held raster coordinate through two unregistered DSP blocks.
    (* keep = "true" *) wire signed [26:0] affine_x_horizontal =
        $signed(affine_pa) * $signed({1'b0,affine_screen_x});
    (* keep = "true" *) wire signed [26:0] affine_y_horizontal =
        $signed(affine_pc) * $signed({1'b0,affine_screen_x});
    (* keep = "true" *) wire signed [26:0] affine_x_vertical =
        affine_vertical_pb * affine_line_coordinate;
    (* keep = "true" *) wire signed [26:0] affine_y_vertical =
        affine_vertical_pd * affine_line_coordinate;
    // Three-input carry-save reduction keeps both DSP products parallel.
    // All operations are modulo 2^28, matching the original assignment.
    function automatic signed [27:0] affine_sum3(input [27:0] a,b,c);
        reg [27:0] carry_bits;
        begin
            carry_bits=(a&b)|(a&c)|(b&c);
            affine_sum3=(a^b^c)+(carry_bits<<1);
        end
    endfunction
    assign bg3_affine_x_raw = affine_sum3(affine_refx, {affine_x_vertical[26],affine_x_vertical}, {affine_x_horizontal[26],affine_x_horizontal});
    assign bg3_affine_y_raw = affine_sum3(affine_refy, {affine_y_vertical[26],affine_y_vertical}, {affine_y_horizontal[26],affine_y_horizontal});
    assign bg3_affine_x_int = bg3_affine_x_raw >>> 8;
    assign bg3_affine_y_int = bg3_affine_y_raw >>> 8;
    assign bg3_affine_mask = (11'd128 << affine_cnt[15:14]) - 11'd1;
    assign bg3_affine_outside = !affine_cnt[13] &&
        ((bg3_affine_x_int < 0) || (bg3_affine_y_int < 0) ||
         (bg3_affine_x_int >= (20'sd128 <<< affine_cnt[15:14])) ||
         (bg3_affine_y_int >= (20'sd128 <<< affine_cnt[15:14])));
    assign bg3_affine_x = bg3_affine_x_int[9:0] & bg3_affine_mask;
    assign bg3_affine_y = bg3_affine_y_int[9:0] & bg3_affine_mask;
    // Wrapped tile coordinates occupy disjoint fields at each map size.
    // A variable shift followed by an addition obscures that fact in timing.
    always_comb case(affine_cnt[15:14])
        0:bg3_affine_map_index={6'd0,bg3_affine_y[6:3],bg3_affine_x[6:3]};
        1:bg3_affine_map_index={4'd0,bg3_affine_y[7:3],bg3_affine_x[7:3]};
        2:bg3_affine_map_index={2'd0,bg3_affine_y[8:3],bg3_affine_x[8:3]};
        3:bg3_affine_map_index={bg3_affine_y[9:3],bg3_affine_x[9:3]};
    endcase
    assign bg3_affine_map_byte_addr = {affine_cnt[12:8], 11'b0} + bg3_affine_map_index;
    assign bg3_affine_tile_number = bg3_affine_map_byte_addr[0]
        ? bg3_map_read_data[15:8] : bg3_map_read_data[7:0];
    assign bg3_affine_tile_byte_addr = {affine_cnt[3:2], 14'b0} +
        {bg3_affine_tile_number, bg3_affine_y[2:0], bg3_affine_x[2:0]};

`ifndef GBK_POCKET
    assign bg3_x = (bg3cnt[6] ? mosaic_x : {1'b0,x}) + bg3hofs;
    assign bg3_y = (bg3cnt[6] ? mosaic_y : 10'(y)) + bg3vofs;
    assign bg3_tile_x = bg3_x[8:3];
    assign bg3_tile_y = bg3_y[8:3];
    assign bg3_pixel_x = bg3_x[2:0];
    assign bg3_pixel_y = bg3_y[2:0];
    assign bg3_sample_x = bg3_map_read_data[10] ? (3'd7 - bg3_pixel_x) : bg3_pixel_x;
    assign bg3_sample_y = bg3_map_read_data[11] ? (3'd7 - bg3_pixel_y) : bg3_pixel_y;
    assign bg3_map_read_addr = (mode == 2) ? (bg3_affine_map_byte_addr >> 1) :
        (bg3cnt[12:8] * 16'h0400) + (bg3_tile_y[4:0] * 32 + bg3_tile_x[4:0]);
    assign bg3_tile_number = bg3_map_read_data[9:0];
    assign bg3_palette_bank = bg3_map_read_data[15:12];
    assign bg3_tile_addr_calc = {bg3cnt[3:2], 14'b0} +
        (bg3cnt[7]
            ? {bg3_tile_number, bg3_sample_y, bg3_sample_x[2:1], 1'b0}
            : {1'b0, bg3_tile_number, bg3_sample_y, bg3_sample_x[2], 1'b0});
    assign bg3_tile_read_addr = bg3_active ?
        ((mode == 2) ? (bg3_affine_tile_byte_addr >> 1) : (bg3_tile_addr_calc >> 1)) : 16'd0;
    assign bg3_tile_pixel = bg3_tile_read_data;
    assign bg3_palette_index = (mode == 2) ?
        (bg3_affine_outside ? 8'd0 :
         (bg3_affine_tile_byte_addr[0] ? bg3_tile_pixel[15:8] : bg3_tile_pixel[7:0])) :
        bg3cnt[7]
        ? (bg3_sample_x[0] ? bg3_tile_pixel[15:8] : bg3_tile_pixel[7:0])
        : (bg3_sample_x[0]
            ? (bg3_sample_x[1] ? bg3_tile_pixel[15:12] : bg3_tile_pixel[7:4])
            : (bg3_sample_x[1] ? bg3_tile_pixel[11:8] : bg3_tile_pixel[3:0])) +
            (bg3_palette_bank << 4);

`else
    assign bg3_map_read_addr = mode==0 ? cached_map3 : affine_map3;
    assign bg3_tile_read_addr = mode==0 ? cached_tile3 : affine_tile3;
    assign bg3_palette_index = mode==0 ? text_palette3 : affine_palette3;
`endif

    // Regular OBJ subset: non-affine sprites with the hardware size table.
`ifdef GBK_POCKET
    // Provisional hardware budget: scan the first 32 entries combinationally.
    // A future line-cached scanner must cover all 128 without unrolling them.
    localparam integer OBJ_SCAN_ENTRIES = 32;
`else
    localparam integer OBJ_SCAN_ENTRIES = 128;
`endif
    // The scan chooses the first visible OAM entry, then priority arbitration
    // decides whether it covers the selected background pixel.
    always_comb begin
        sprite_i = 0;
        obj_found = 1'b0;
        obj_tile_addr_calc = 17'd0;
        obj_8bpp = 1'b0;
        obj_sample_x = 0;
        obj_sample_y = 0;
        obj_width = 8;
        obj_height = 8;
        obj_rel_x = 0;
        obj_rel_y = 0;
        obj_rel_x_wrapped = 0;
        obj_rel_y_wrapped = 0;
        obj_tiles_per_row = 1;
        obj_shape = 0;
        obj_size = 0;
        obj_tile_number = 0;
        obj_tile_offset = 0;
        obj_hflip = 0;
        obj_vflip = 0;
        obj_palette_bank = 0;
        obj_priority = 2'b11;
        obj_semi = 0;
        if (!OBJ_ROWS && (mode <= 5) && de && dispcnt[12]) begin
            for (sprite_i = 0; sprite_i < OBJ_SCAN_ENTRIES; sprite_i = sprite_i + 1) begin
                if (!obj_found &&
                oam_data_flat[(sprite_i*48) + 9 -: 2] == 2'b00 &&
                !oam_data_flat[(sprite_i*48) + 11]) begin
                obj_shape = oam_data_flat[(sprite_i*48) + 14 +: 2];
                obj_size = oam_data_flat[(sprite_i*48) + 30 +: 2];
                case ({obj_shape, obj_size})
                    4'b0000: begin obj_width=8;  obj_height=8;  end
                    4'b0001: begin obj_width=16; obj_height=16; end
                    4'b0010: begin obj_width=32; obj_height=32; end
                    4'b0011: begin obj_width=64; obj_height=64; end
                    4'b0100: begin obj_width=16; obj_height=8;  end
                    4'b0101: begin obj_width=32; obj_height=8;  end
                    4'b0110: begin obj_width=32; obj_height=16; end
                    4'b0111: begin obj_width=64; obj_height=32; end
                    4'b1000: begin obj_width=8;  obj_height=16; end
                    4'b1001: begin obj_width=8;  obj_height=32; end
                    4'b1010: begin obj_width=16; obj_height=32; end
                    4'b1011: begin obj_width=32; obj_height=64; end
                    default: begin obj_width=8; obj_height=8; end
                endcase
                obj_tiles_per_row = obj_width >> 3;
                // OAM stores negative positions modulo 512/256. Match the
                // window-object path so sprites entering at the left/top
                // edges retain the visible part of their tile.
                obj_rel_x_wrapped = x - oam_data_flat[(sprite_i*48) + 16 +: 9];
                obj_rel_y_wrapped = y[7:0] - oam_data_flat[(sprite_i*48) +: 8];
                if (obj_rel_x_wrapped < obj_width &&
                    obj_rel_y_wrapped < obj_height) begin
                    obj_found = 1'b1;
                    obj_semi = oam_data_flat[(sprite_i*48) + 10];
                    obj_8bpp = oam_data_flat[(sprite_i*48) + 13];
                    obj_priority = oam_data_flat[(sprite_i*48) + 42 +: 2];
                    obj_palette_bank = oam_data_flat[(sprite_i*48) + 44 +: 4];
                    // Keep the scan to bounding-box selection. Tile
                    // arithmetic belongs after it so synthesis needs one
                    // address unit instead of one per candidate sprite.
                    obj_rel_x = obj_rel_x_wrapped[6:0];
                    obj_rel_y = obj_rel_y_wrapped[6:0];
                    obj_tile_number = oam_data_flat[(sprite_i*48) + 32 +: 10];
                    obj_hflip = oam_data_flat[(sprite_i*48) + 28];
                    obj_vflip = oam_data_flat[(sprite_i*48) + 29];
                end
                end
            end
        end
        if (obj_found) begin
            obj_sample_x = obj_hflip ? (obj_width - 1 - obj_rel_x) : obj_rel_x;
            obj_sample_y = obj_vflip ? (obj_height - 1 - obj_rel_y) : obj_rel_y;
            // The VRAM scheduler addresses halfwords. OBJ VRAM begins at
            // byte offset 0x10000, hence halfword offset 0x8000.
            // Tile numbers are always 32-byte units, including 8bpp OBJ.
            obj_tile_offset = obj_tile_number +
                (dispcnt[6]
                    ? (((obj_sample_y >> 3) * obj_tiles_per_row +
                        (obj_sample_x >> 3)) << obj_8bpp)
                    : (((obj_sample_y >> 3) << 5) +
                        ((obj_sample_x >> 3) << obj_8bpp)));
            obj_tile_addr_calc = 17'h08000 +
                (obj_tile_offset << 4) +
                ((obj_sample_y[2:0]) * (obj_8bpp ? 4 : 2)) +
                (obj_8bpp ? {1'b0, obj_sample_x[2:1]} : {1'b0, 1'b0, obj_sample_x[2]});
        end
    end

    generate
        if (!EXTERNAL_VRAM) begin : standalone_framebuffer
            gba_framebuffer_ram framebuffer_ram (
                .write_clk(clk), .write_en(vram_write),
                .write_addr(vram_addr), .write_data(vram_wdata),
                .read_clk(clk), .read_addr(vram_read_addr),
                .read_data(framebuffer_pixel), .debug_pixel0(debug_pixel0)
            );
        end else begin : shared_vram
            assign framebuffer_pixel = vram_read_data;
            assign debug_pixel0 = vram_debug0;
        end
    endgenerate

    // Keep the runner-up BG even when it is not selected as a blend target:
    // an intervening opaque layer must block blending with deeper layers.
`ifdef GBK_POCKET
    wire [3:0] effect_wins=composed_wins;
    wire [3:0] effect_opaque=composed_opaque;
    wire [31:0] effect_palettes=composed_palettes;
    wire [7:0] effect_priorities=composed_priorities;
`else
    wire [3:0] effect_wins=bg_wins;
    wire [3:0] effect_opaque=bg_opaque;
    wire [31:0] effect_palettes={bg3_palette_index,bg2_palette_index,bg1_palette_index,bg_palette_index};
    wire [7:0] effect_priorities={bg3cnt[1:0],bg2cnt[1:0],bg1cnt[1:0],bg0cnt[1:0]};
`endif
    reg [2:0] top_bg_layer,lower_bg_layer;
    reg [1:0] lower_bg_priority;
    reg [7:0] lower_bg_index;
    reg lower_bg_valid;
    wire [3:0] lower_bg_wins=background_winners(effect_opaque & ~effect_wins,effect_priorities);
    integer layer;
    always @* begin
        top_bg_layer=5;
        lower_bg_valid=|lower_bg_wins;
        lower_bg_layer=lower_bg_valid ?
            (({3{lower_bg_wins[1]}} & 3'd1) | ({3{lower_bg_wins[2]}} & 3'd2) | ({3{lower_bg_wins[3]}} & 3'd3)) : 3'd5;
        lower_bg_priority=lower_bg_valid ?
            (({2{lower_bg_wins[0]}} & effect_priorities[0+:2]) |
             ({2{lower_bg_wins[1]}} & effect_priorities[2+:2]) |
             ({2{lower_bg_wins[2]}} & effect_priorities[4+:2]) |
             ({2{lower_bg_wins[3]}} & effect_priorities[6+:2])) : 2'd3;
        lower_bg_index=({8{lower_bg_wins[0]}} & effect_palettes[0+:8]) |
            ({8{lower_bg_wins[1]}} & effect_palettes[8+:8]) |
            ({8{lower_bg_wins[2]}} & effect_palettes[16+:8]) |
            ({8{lower_bg_wins[3]}} & effect_palettes[24+:8]);
        for(integer n=3;n>=0;n=n-1) begin
            if(effect_wins[n]) top_bg_layer=n;
        end
    end
    assign second_palette_read_addr={lower_bg_index,1'b0};
    wire bitmap_layer = bitmap_visible && window_bg_allowed[2] &&
        (mode!=4 || mode4_index_pixel!=0);
    wire top_bg_valid=bitmap_visible ? bitmap_layer : top_bg_layer!=5;
    wire [2:0] bg_layer_id=bitmap_visible ? 3'd2 : top_bg_layer;
    wire [1:0] bg_priority=bitmap_visible ? bg2cnt[1:0] : bg_selected_priority;
    wire visible_obj=obj_active && obj_palette_index!=0;
    wire [1:0] visible_obj_priority=OBJ_ROWS ? row_obj_priority : obj_priority;
    wire obj_on_top=visible_obj && (!top_bg_valid || visible_obj_priority<=bg_priority);
    reg [15:0] first_color,second_color;
    reg [2:0] first_layer,second_layer;
    wire [14:0] effected_color;
    always @* begin
        first_color=backdrop_color;second_color=backdrop_color;
        first_layer=5;second_layer=5;
        if(top_bg_valid) begin
            first_layer=bg_layer_id;
            first_color=bitmap_visible ? (mode==4 ? palette_read_data : framebuffer_pixel) : bg_palette_read_data;
        end
        if(obj_on_top) begin
            second_color=first_color;second_layer=first_layer;
            first_color=obj_palette_read_data;first_layer=4;
        end else if(top_bg_valid) begin
            if(lower_bg_valid && !bitmap_visible) begin
                second_color=second_palette_read_data;second_layer=lower_bg_layer;
            end
            if(visible_obj && (!lower_bg_valid || bitmap_visible || visible_obj_priority<=lower_bg_priority)) begin
                second_color=obj_palette_read_data;second_layer=4;
            end
        end
    end
    gba_color_effects effects(.first_color(first_color[14:0]),.second_color(second_color[14:0]),
        .second_valid(first_layer!=5),
        .first_layer,.second_layer,.semi_transparent(obj_on_top && (OBJ_ROWS ? row_obj_semi : obj_semi)),
        .enabled(window_effects_allowed),.bldcnt,.bldalpha,.bldy,.color(effected_color));
    always @* begin
        pixel_index = ((bg2cnt[6] ? mosaic_y : 10'(y)) * ACTIVE_W) + (bg2cnt[6] ? mosaic_x : {1'b0,x});
        bitmap_index = (mode == 5) ? (((bg2cnt[6] ? mosaic_y : 10'(y)) * 160) + (bg2cnt[6] ? mosaic_x : {1'b0,x})) : pixel_index;
        bitmap_visible = (mode == 3 || mode == 4) || (mode == 5 && x < 160 && y < 128);
        pixel = {1'b0,effected_color};
        if(dispcnt[7]) pixel=16'h7fff;
        r=de ? {pixel[4:0],4'b0} : 9'd0;
        g=de ? {pixel[9:5],4'b0} : 9'd0;
        b=de ? {pixel[14:10],4'b0} : 9'd0;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            x <= 0;
            y <= 0;
            pixel_reg <= 0;
        end else if (video_advance && (!FAST_RENDER || pixel_ce)) begin
            if (x < ACTIVE_W && y < ACTIVE_H && bitmap_visible)
                pixel_reg <= framebuffer_pixel;
            if (x == TOTAL_W-1) begin
                x <= 0;
                if (y == TOTAL_H-1)
                    y <= 0;
                else
                    y <= y + 1'b1;
            end else begin
                x <= x + 1'b1;
            end
        end
    end
endmodule

// A bundled coordinate descriptor for cache requests. Native dots are held
// for at least two video clocks, much longer than the three render-clock
// event transfer; the descriptor cannot change before it has been consumed.
module gba_render_coordinate_transfer #(parameter integer FRAME_LINES=228) (
    input wire video_clk,render_clk,reset,
    input wire [18:0] video_coordinates,
    output reg [19:0] render_coordinates
);
    reg [19:0] held_coordinates;
    reg event_toggle,event_seen;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] event_sync;
    wire [8:0] video_x=video_coordinates[8:0];
    wire [9:0] video_y=video_coordinates[18:9];
    wire blank=video_x>=240;
    // Normalize the next-line lookahead in the video domain. Its increment
    // and blanking mux need not consume a 7.512 ns render-clock period.
    wire [19:0] normalized_coordinates={blank,
        (blank ? (video_y==FRAME_LINES-1 ? 10'd0 : video_y+10'd1) : video_y),
        (blank ? 9'd0 : video_x)};
    always @(posedge video_clk) begin
        if(reset) begin held_coordinates<=20'hfffff;event_toggle<=0;end
        else if(held_coordinates!=normalized_coordinates) begin
            held_coordinates<=normalized_coordinates;event_toggle<=!event_toggle;
        end
    end
    always @(posedge render_clk) begin
        if(reset) begin render_coordinates<=0;event_sync<=0;event_seen<=0;end
        else begin
            event_sync<={event_sync[0],event_toggle};
            if(event_sync[1]!=event_seen) begin
                render_coordinates<=held_coordinates;event_seen<=event_sync[1];
            end
        end
    end
endmodule

// Two tile rows per layer: retain the displayed row while fetching its neighbour.
// Tile parity selects the bank; word storage has one write and one read port.
module gba_text_row_cache #(parameter integer FRAME_LINES=640,parameter COHERENT_CONTROL=0) (
    input logic clk, reset, enabled,
    input logic [8:0] x,
    input logic [9:0] y,
    input wire [8:0] control_x,
    input wire [9:0] control_y,
    input wire control_blank,
    input logic [15:0] cnt,
    input logic [8:0] hofs, vofs,
    output logic [15:0] map_addr, tile_addr,
    input logic [15:0] map_data, tile_data,
    output logic [7:0] palette_index
);
    localparam integer SETTLE = 14; // ten scheduler slots plus registered return
    logic [1:0] state;
    logic [3:0] wait_count;
    logic [9:0] config_seen;
    logic [8:0] cached_sy;
    logic [1:0] valid;
    logic [4:0] tags[0:1];
    // A row being written is invalid, so a same-address read is never used.
    // Eight halfwords do not justify a dedicated M10K per background.
    // Keep the existing clocked read; flow-through MLAB storage feeds it.
    (* ramstyle = "MLAB, no_rw_check" *) logic [15:0] row_words[0:7];
    logic [4:0] attrs[0:1]; // horizontal flip and palette bank
    logic slot;
    logic [1:0] half_index;
    logic [15:0] tile_base;
    logic blank_seen;
    // Priority and unused/mosaic/affine-only bits do not change cached data.
    wire [9:0] row_config={cnt[15:14],cnt[12:7],cnt[3:2]};
    wire [8:0] screen_x = COHERENT_CONTROL ? control_x : (x < 240 ? x : 9'd0);
    wire [9:0] screen_y = COHERENT_CONTROL ? control_y : (x < 240 ? y : (y == FRAME_LINES-1 ? 10'd0 : y + 10'd1));
    reg [8:0] request_x,request_y;
    reg descriptor_blank;
    // Separate mosaic normalization from scroll addition. Both stages fit
    // within the held-dot descriptor window; no CPU/PPU dot is delayed.
    always_ff @(posedge clk)begin
        if(reset)begin request_x<=0;request_y<=0;descriptor_blank<=0;end
        else begin request_x<=screen_x;request_y<=screen_y[8:0];descriptor_blank<=control_blank;end
    end
    wire [8:0] sx_raw = (COHERENT_CONTROL ? request_x : screen_x) + hofs;
    wire [8:0] sy_raw = (COHERENT_CONTROL ? request_y : screen_y[8:0]) + vofs;
    reg [8:0] staged_sx,staged_sy;
    reg staged_blank;
`ifdef GBK_SAVESTATE
    reg [5:0] staged_next_tx;
    wire [5:0] descriptor_next_tx=({sx_raw[8] & cnt[14],sx_raw[7:3]}+6'd1) &
        (cnt[14] ? 6'd63 : 6'd31);
`endif
    // Register per-layer scroll offsets before request/tag selection. The
    // normalized descriptor already includes blanking and next-line lookahead.
    always_ff @(posedge clk) begin
        if(reset) begin
            staged_sx<=0;staged_sy<=0;staged_blank<=0;
`ifdef GBK_SAVESTATE
            staged_next_tx<=1;
`endif
        end else begin
            staged_sx<={sx_raw[8] & cnt[14],sx_raw[7:0]};
            staged_sy<={sy_raw[8] & cnt[15],sy_raw[7:0]};
            staged_blank<=descriptor_blank;
`ifdef GBK_SAVESTATE
            // Capture the neighbour index with its matching descriptor;
            // leave only tag comparison on the idle-to-fetch state path.
            staged_next_tx<=descriptor_next_tx;
`endif
        end
    end
    wire [8:0] sx = COHERENT_CONTROL ? staged_sx : {sx_raw[8] & cnt[14], sx_raw[7:0]};
    wire [8:0] sy = COHERENT_CONTROL ? staged_sy : {sy_raw[8] & cnt[15], sy_raw[7:0]};
    wire request_blank=COHERENT_CONTROL ? staged_blank : x>=240;
    wire current_slot=sx[3];
`ifdef GBK_SAVESTATE
    wire [5:0] next_tx = COHERENT_CONTROL ? staged_next_tx :
        (sx[8:3]+6'd1) & (cnt[14] ? 6'd63 : 6'd31);
`else
    wire [5:0] next_tx = (sx[8:3]+6'd1) & (cnt[14] ? 6'd63 : 6'd31);
`endif
    wire current_hit=valid[current_slot] && tags[current_slot]==sx[8:4];
    wire next_hit=valid[!current_slot] && tags[!current_slot]==next_tx[5:1];
    wire [5:0] requested_tx = current_hit ? next_tx : sx[8:3];
    // Decode screen banks before cache-hit/next-tile selection. Adding the
    // selected bank afterward put tag comparison and two carry chains on
    // the same map-address path. These parallel constants keep that choice
    // to a final mux, with identical launch state and fetch latency.
    wire [5:0] map_bank0={1'b0,cnt[12:8]};
    wire vertical_bank=cnt[15] && sy[8];
    wire [1:0] left_delta={vertical_bank && cnt[14],vertical_bank && !cnt[14]};
`ifdef GBK_SAVESTATE
    // Compute the constant screen-bank alternatives before selecting by the
    // late descriptor Y bit. This removes Y -> carry -> bank mux -> map_addr.
    (* keep = 1 *) wire [5:0] map_bank_step1=map_bank0+6'd1;
    (* keep = 1 *) wire [5:0] map_bank_step2=map_bank0+6'd2;
    (* keep = 1 *) wire [5:0] map_bank_step3=map_bank0+6'd3;
    wire [5:0] map_bank_left=vertical_bank ?
        (cnt[14] ? map_bank_step2 : map_bank_step1) : map_bank0;
`else
    (* keep *) wire [5:0] map_bank_left=map_bank0+{4'd0,left_delta};
`endif
    // The right bank is consumed only by 64-tile-wide maps: its offset is
    // one on the upper screen row or three on the lower screen row.
`ifdef GBK_SAVESTATE
    wire [5:0] map_bank_right=vertical_bank ? map_bank_step3 : map_bank_step1;
`else
    (* keep *) wire [5:0] map_bank_right=map_bank0+{4'd0,vertical_bank,1'b1};
`endif
    wire [15:0] current_map_address={
        (cnt[14] && sx[8] ? map_bank_right : map_bank_left),sy[7:3],sx[7:3]};
    wire [15:0] next_map_address={
        (cnt[14] && next_tx[5] ? map_bank_right : map_bank_left),sy[7:3],next_tx[4:0]};
    wire [15:0] launch_map_address=current_hit ? next_map_address : current_map_address;
    // Display reads settle during the held native dot. Only cache mutation
    // needs the transferred coordinates; delaying colour lookup would spend
    // the compositor's pixel deadline on the crossing itself.
    wire [8:0] display_sx_raw=(x<240 ? x : 9'd0)+hofs;
    wire [8:0] display_sx={display_sx_raw[8] & cnt[14],display_sx_raw[7:0]};
    wire display_slot=display_sx[3];
    wire display_hit=valid[display_slot] && tags[display_slot]==display_sx[8:4];
    wire [4:0] attr=attrs[display_slot];
    wire [2:0] sample_x = attr[4] ? ~display_sx[2:0] : display_sx[2:0];
    wire [1:0] pixel_word = cnt[7] ? sample_x[2:1] : {1'b0,sample_x[2]};
    logic [15:0] word_pixel;
    always_ff @(posedge clk)
        word_pixel<=row_words[{display_slot,pixel_word}];
    wire [7:0] colour = cnt[7] ? (sample_x[0] ? word_pixel[15:8] : word_pixel[7:0]) :
                               {4'd0,word_pixel[sample_x[1:0]*4+:4]};
    wire [2:0] fetched_y=map_data[11] ? ~cached_sy[2:0] : cached_sy[2:0];
    wire [14:0] fetched_offset=cnt[7] ? {map_data[9:0],fetched_y,2'b0} :
                                      {1'b0,map_data[9:0],fetched_y,1'b0};
    assign tile_addr=tile_base | {14'd0,half_index};
`ifdef GBK_SAVESTATE
    // Select transparency in parallel with pixel data. A variable nibble mux
    // followed by a zero comparison put flip -> colour -> bank transparency
    // on the measured text-palette path. Each nibble's opacity is independent
    // of flip/selection, so the selected bank needs no late colour comparison.
    wire [3:0] nibble_select={sample_x[1:0]==3,sample_x[1:0]==2,
                              sample_x[1:0]==1,sample_x[1:0]==0};
    // Resolve each lane's bank/transparency before selecting a pixel. The low
    // colour bits then have no selected-opacity signal in their clear cone.
    function automatic [7:0] decode_nibble(input [3:0] pixel,input [3:0] bank);
        begin decode_nibble=0;if(pixel!=0)decode_nibble={bank,pixel};end
    endfunction
    function automatic [7:0] decode_byte(input [7:0] pixel);
        begin decode_byte=0;if(pixel!=0)decode_byte=pixel;end
    endfunction
    (* keep = 1 *) wire [7:0] decoded_nibble0=decode_nibble(word_pixel[3:0],attr[3:0]);
    (* keep = 1 *) wire [7:0] decoded_nibble1=decode_nibble(word_pixel[7:4],attr[3:0]);
    (* keep = 1 *) wire [7:0] decoded_nibble2=decode_nibble(word_pixel[11:8],attr[3:0]);
    (* keep = 1 *) wire [7:0] decoded_nibble3=decode_nibble(word_pixel[15:12],attr[3:0]);
    (* keep = 1 *) wire [7:0] decoded_byte0=decode_byte(word_pixel[7:0]);
    (* keep = 1 *) wire [7:0] decoded_byte1=decode_byte(word_pixel[15:8]);
    wire [7:0] nibble_palette=({8{nibble_select[0]}} & decoded_nibble0) |
                             ({8{nibble_select[1]}} & decoded_nibble1) |
                             ({8{nibble_select[2]}} & decoded_nibble2) |
                             ({8{nibble_select[3]}} & decoded_nibble3);
    wire [7:0] byte_palette=sample_x[0] ? decoded_byte1 : decoded_byte0;
    always_comb begin
        palette_index=0;
        if(enabled && display_hit)
            palette_index=cnt[7] ? byte_palette : nibble_palette;
    end
`else
    always_comb begin
        palette_index=0;
        if(enabled && display_hit && colour!=0)
            palette_index=cnt[7] ? colour : {attr[3:0],colour[3:0]};
    end
`endif
    // No reset on the row data: valid bits hide it until all words arrive.
    // A narrow write port avoids a second staging row and wide bank muxes.
    always_ff @(posedge clk) begin
        if(!reset && state==2 && wait_count==0)
            row_words[{slot,half_index}]<=tile_data;
    end
    // Idle addresses may change even on a cache hit or invalidation. Only
    // state 1 consumes map data, after SETTLE clocks from the launch edge.
    // Keep tag comparisons out of this wide register's clock-enable cone.
    always_ff @(posedge clk) begin
        if(reset) map_addr<=0;
        else if(state==0) map_addr<=launch_map_address;
    end
`ifdef GBK_SAVESTATE
    // On every non-invalidating edge these values already equal their inputs.
    // Rewriting them removes the wide invalidation condition from their enables
    // without changing any observed metadata, state transition or fetch cycle.
    always_ff @(posedge clk)begin
        if(reset)begin config_seen<=0;cached_sy<=0;end
        else begin config_seen<=row_config;cached_sy<=sy;end
    end
    // The settling counter is irrelevant in idle or on an invalidated row.
    // Reload at each launch/word boundary without gating its register enable
    // through the wide configuration/row comparison. State/valid still abort
    // on the original edge; memory launch and consumption cycles are unchanged.
    always_ff @(posedge clk) begin
        if(reset)wait_count<=0;
        else if(state==0 || ((state==1 || state==2) && wait_count==0))wait_count<=SETTLE;
        else if(wait_count!=0)wait_count<=wait_count-1'b1;
    end
`endif
    always_ff @(posedge clk) begin
        if(reset) begin
            blank_seen<=0;
            state<=0;valid<=0;
`ifndef GBK_SAVESTATE
            config_seen<=0;cached_sy<=0;wait_count<=0;
`endif
            slot<=0;half_index<=0;tile_base<=0;
            tags[0]<=0;tags[1]<=0;
        end else if(!enabled || config_seen!=row_config || cached_sy!=sy ||
                    (request_blank && !blank_seen)) begin
            blank_seen<=request_blank;
            state<=0;valid<=0;
`ifndef GBK_SAVESTATE
            config_seen<=row_config;cached_sy<=sy;
`endif
        end else begin
            blank_seen<=request_blank;
            case(state)
                0: if(!current_hit || !next_hit) begin
                    slot<=requested_tx[0];
                    valid[requested_tx[0]]<=0;
`ifdef GBK_SAVESTATE
                    // Each bank's data depends on tile parity, independently
                    // of the late hit decision. On a current hit its tag is
                    // already sx[8:4], so rewriting that same value is safe.
                    // Avoid hit -> requested_tx mux -> bank-index/data mux.
                    if(!current_slot || current_hit)
                        tags[0]<=current_slot ? next_tx[5:1] : sx[8:4];
                    if(current_slot || current_hit)
                        tags[1]<=current_slot ? sx[8:4] : next_tx[5:1];
`else
                    tags[requested_tx[0]]<=requested_tx[5:1];
`endif
`ifndef GBK_SAVESTATE
                    wait_count<=SETTLE;
`endif
                    state<=1;
                end
`ifdef GBK_SAVESTATE
                1: if(wait_count!=0) begin end
`else
                1: if(wait_count!=0) wait_count<=wait_count-1'b1;
`endif
                   else begin
                       attrs[slot]<={map_data[10],map_data[15:12]};
                       tile_base<={1'b0,cnt[3:2],13'b0}+{1'b0,fetched_offset};
                       half_index<=0;
`ifndef GBK_SAVESTATE
                       wait_count<=SETTLE;
`endif
                       state<=2;
                   end
`ifdef GBK_SAVESTATE
                2: if(wait_count!=0) begin end
`else
                2: if(wait_count!=0) wait_count<=wait_count-1'b1;
`endif
                   else if(half_index==(cnt[7] ? 2'd3 : 2'd1)) begin
                       valid[slot]<=1;state<=0;
                   end else begin
                       half_index<=half_index+1'b1;
`ifndef GBK_SAVESTATE
                       wait_count<=SETTLE;
`endif
                   end
                default: begin state<=0;valid<=0;end
            endcase
        end
    end
endmodule



// GBA effects operate on 5-bit channels, with coefficients clamped to 16.
module gba_color_effects(
    input wire [14:0] first_color,second_color,
    input wire [2:0] first_layer,second_layer,
    input wire semi_transparent,enabled,second_valid,
    input wire [15:0] bldcnt,bldalpha,bldy,
    output reg [14:0] color
);
    wire [4:0] eva=bldalpha[4:0]>16 ? 5'd16 : bldalpha[4:0];
    wire [4:0] evb=bldalpha[12:8]>16 ? 5'd16 : bldalpha[12:8];
    wire [4:0] evy=bldy[4:0]>16 ? 5'd16 : bldy[4:0];
    integer channel;
    reg [10:0] sum;
    reg [9:0] delta;
    always @* begin
        color=first_color;sum=0;delta=0;
        for(channel=0;channel<3;channel=channel+1) begin
            if(enabled) begin
                if(second_valid && (semi_transparent || (bldcnt[7:6]==1 && bldcnt[first_layer])) && bldcnt[8+second_layer]) begin
                    sum=first_color[channel*5+:5]*eva+second_color[channel*5+:5]*evb;
                    color[channel*5+:5]=sum[10:4]>31 ? 5'd31 : sum[8:4];
                end else if(bldcnt[first_layer]) begin
                    case(bldcnt[7:6])
                        2: begin
                            delta=(5'd31-first_color[channel*5+:5])*evy;
                            color[channel*5+:5]=first_color[channel*5+:5]+delta[8:4];
                        end
                        3: begin
                            delta=first_color[channel*5+:5]*evy;
                            color[channel*5+:5]=first_color[channel*5+:5]-delta[8:4];
                        end
                        default: begin end
                    endcase
                end
            end
        end
    end
endmodule

