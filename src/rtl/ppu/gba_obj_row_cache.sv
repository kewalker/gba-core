// Render the next scanline ahead of display. Transparent pixels do not claim
// a destination, and priority/OAM order are resolved per pixel, not per box.
module gba_obj_row_cache #(parameter EXTERNAL_OAM=0, WORD_READS=0, VIDEO_CDC=0, TAGGED_READS=0) (
    input wire clk,reset,
    input wire video_clk,
    input wire [8:0] x,
    input wire [7:0] y,
    input wire [15:0] dispcnt,
    input wire [7:0] mosaic,
    input wire [8191:0] oam,
    output reg [6:0] oam_addr,
    input wire [63:0] oam_data,
    output reg [16:0] tile_addr,
    input wire [15:0] tile_data,
    input wire [31:0] tile_word_data,
    input wire [15:0] tile_word_addr,
    input wire tile_word_valid,
    output reg [7:0] palette_index,
    output reg [1:0] pixel_priority,
    output reg semi_transparent,
    output reg window_opaque,
    output reg overrun
);
    localparam IDLE=0,CLEAR=1,ATTR=2,GEOMETRY=3,SAMPLE=4,
               WAIT_TILE=5,READ_PIXEL=6,WRITE_PIXEL=7,NEXT_OBJ=8,WAIT_OAM=9,WAIT_MATRIX=10,
               TILE_INDEX=11,TILE_ADDRESS=12,CHECK_TILE=13,AFFINE_MULT=14,AFFINE_SUM=15,AFFINE_CENTER=16,DECODE_SIZE=17;
    // A compact safe encoding avoids the wide one-hot validity reduction on
    // every next-state path. Illegal states still recover to IDLE.
    (* syn_encoding="safe, sequential" *) reg [4:0] state;
    reg [7:0] seen_y,target_y,clear_x;
    reg [6:0] object_index;
    reg [47:0] attributes;
    reg [6:0] width,height;
    reg [6:0] geometry_w,geometry_h;
    reg [7:0] local_x,field_width;
    reg [5:0] normal_source_y;
    reg [8:0] screen_x;
    reg [9:0] tile_number;
    reg [3:0] palette_bank;
    reg [1:0] object_priority;
    reg eight_bpp,hflip,mapping_1d,window_object,semi_object;
    reg affine;
    reg object_mosaic;
    reg signed [27:0] texture_u,texture_v;
    reg signed [27:0] mosaic_texture_u,mosaic_texture_v;
    reg [5:0] mosaic_source_x;
    reg mosaic_outside;
    reg signed [27:0] next_texture_u,next_texture_v;
    reg skip_sample;
    reg signed [15:0] step_u,step_v;
    reg signed [15:0] coefficient_a,coefficient_b,coefficient_c,coefficient_d;
    reg signed [8:0] initial_x,initial_y;
    reg signed [24:0] product_a,product_b,product_c,product_d;
    reg signed [25:0] affine_sum_u,affine_sum_v;
    reg [1:0] width_shift;
    reg [5:0] sample_x,sample_y;
    reg [9:0] sample_tile;
    reg [16:0] sample_addr;
    reg [3:0] wait_count;
    reg cached_valid;
    reg [16:0] cached_addr;
    reg [31:0] cached_data;
    reg [5:0] cached_source_y;
    reg cached_row_hit;
    reg [4:0] cached_source_word;
    reg [7:0] sampled_index,destination_x;
    reg [1:0] bank_valid;
    reg [63:0] matrix_cache;
`ifdef GBK_FAST_FORWARD
    // WAIT_MATRIX's final wait clock is already idle. Decode the four write
    // enables there, keeping the state/wait/matrix mux off the 64-bit bank's
    // capture edge. The capture edge and externally visible cycles are fixed.
    reg [3:0] matrix_capture;
    reg [1:0] bank_capture;
    (* preserve, dont_merge *) reg [15:0] response_tag;
    always @(posedge clk)begin
        if(reset)begin matrix_capture<=0;response_tag<=0;bank_capture<=0;end
        else begin
            matrix_capture<=!begin_line && state==WAIT_MATRIX && wait_count==1 ? (4'b0001 << matrix_word) : 4'b0000;
            // Requests wait at least four clocks before accepting a tagged
            // word. A private mirror settles on the first wait clock and
            // removes the high-fanout output address from the return check.
            response_tag<=tile_addr[16:1];
            // Predict the final clear edge. Keep the existing target_y data
            // route and exact tag write edge, with only two private enables.
            bank_capture<=!begin_line && state==CLEAR && clear_x==238 ?
                (target_y[0] ? 2'b10 : 2'b01) : 2'b00;
        end
        if(reset)begin matrix_cache<=0;bank_y[0]<=0;bank_y[1]<=0;end
        else if(!begin_line)begin
            for(integer lane=0;lane<4;lane=lane+1)
                if(matrix_capture[lane])matrix_cache[lane*16+:16]<=oam_data[63:48];
            if(bank_capture[0])bank_y[0]<=target_y;
            if(bank_capture[1])bank_y[1]<=target_y;
        end
    end
`endif
    reg [1:0] matrix_word;
    reg [7:0] bank_y[0:1];

    // Port A is the renderer's read/modify/write port, B the display port.
    (* ramstyle="M10K, no_rw_check" *) reg [11:0] pixels[0:511];
    reg [11:0] display_pixel,previous_pixel;
    wire [8:0] engine_addr={target_y[0],state==CLEAR ? clear_x : destination_x};
    wire [8:0] display_addr={y[0],x[7:0]};
    wire [7:0] line_y;
    wire begin_line;
    generate if(VIDEO_CDC) begin : line_crossing
        // The binary raster can briefly look like a different row while its
        // bits propagate. Never let that transient invalidate a display bank.
        // Hold an entire row descriptor in the video domain, then transfer it
        // only after its event has crossed two synchronizer stages. The held
        // bus remains unchanged for a whole scanline (over 9700 render clocks).
        reg [7:0] held_y;
        reg event_toggle;
        (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] event_sync;
        reg event_seen;
        reg [7:0] received_y;
        reg received_line;
        always @(posedge video_clk) begin
            if(reset) begin held_y<=8'hff;event_toggle<=0;end
            else if(held_y!=y) begin held_y<=y;event_toggle<=!event_toggle;end
        end
        always @(posedge clk) begin
            if(reset) begin event_sync<=0;event_seen<=0;received_y<=8'hff;received_line<=0;end
            else begin
                event_sync<={event_sync[0],event_toggle};
                // Register the event alongside its descriptor. The renderer
                // consumes both on the following edge, exactly as it consumed
                // received_y!=seen_y. Keep that eight-bit comparison out of
                // the high-fanout abort/next-state path at 133 MHz.
                received_line<=event_sync[1]!=event_seen && held_y!=received_y;
                if(event_sync[1]!=event_seen) begin
                    received_y<=held_y;
                    event_seen<=event_sync[1];
                end
            end
        end
        assign line_y=received_y;
        assign begin_line=received_line;
    end else begin : same_clock_line
        assign line_y=y;
        assign begin_line=line_y!=seen_y;
    end endgenerate
    wire replace_pixel=sampled_index!=0 && !window_object &&
        (previous_pixel[7:0]==0 || object_priority<previous_pixel[9:8]);
    always @(posedge clk) begin
        // An aborted line never consumes these affine intermediates. Keep
        // the line-change comparison out of the DSP input clock enables;
        // the next accepted object captures fresh inputs at GEOMETRY.
        if(state==GEOMETRY)begin
            coefficient_a<=pa;coefficient_b<=pb;coefficient_c<=pc;coefficient_d<=pd;
            step_u<=pa;step_v<=pc;
            initial_x<=start_x;initial_y<=start_y;
        end
        // AFFINE_SUM consumes the result captured on the preceding
        // AFFINE_MULT edge. Other captures are unused, so no enable or
        // additional renderer state is needed on the DSP output registers.
        product_a<=coefficient_a*initial_x;product_b<=coefficient_b*initial_y;
        product_c<=coefficient_c*initial_x;product_d<=coefficient_d*initial_y;
    end

    always @(posedge clk) begin
        previous_pixel<=pixels[engine_addr];
        display_pixel<=pixels[display_addr];
        if(!reset && !begin_line) begin
            if(state==CLEAR) pixels[engine_addr]<=0;
            else if(state==WRITE_PIXEL && sampled_index!=0) begin
                if(window_object) pixels[engine_addr]<={previous_pixel[11],1'b1,previous_pixel[9:0]};
                else if(replace_pixel)
                    pixels[engine_addr]<={semi_object,previous_pixel[10],object_priority,sampled_index};
            end
        end
    end
    wire display_valid=bank_valid[y[0]] && bank_y[y[0]]==y && x<240;
    reg display_valid_stage;
    // Match the validity tag to the RAM read, then register the complete
    // tuple. Bank-tag comparisons must not reach the BG window/priority
    // compositor and its palette-address register in the same render clock.
    always @(posedge clk) begin
        if(reset) begin
            display_valid_stage<=0;palette_index<=0;pixel_priority<=3;window_opaque<=0;semi_transparent<=0;
        end else begin
            display_valid_stage<=display_valid;
            palette_index<=display_valid_stage ? display_pixel[7:0] : 8'd0;
            pixel_priority<=display_valid_stage ? display_pixel[9:8] : 2'd3;
            window_opaque<=display_valid_stage && display_pixel[10];
            semi_transparent<=display_valid_stage && display_pixel[11];
        end
    end

    reg [6:0] decoded_w,decoded_h;
    always @* begin
        case({attributes[15:14],attributes[31:30]})
            0: begin decoded_w=8;decoded_h=8;end
            1: begin decoded_w=16;decoded_h=16;end
            2: begin decoded_w=32;decoded_h=32;end
            3: begin decoded_w=64;decoded_h=64;end
            4: begin decoded_w=16;decoded_h=8;end
            5: begin decoded_w=32;decoded_h=8;end
            6: begin decoded_w=32;decoded_h=16;end
            7: begin decoded_w=64;decoded_h=32;end
            8: begin decoded_w=8;decoded_h=16;end
            9: begin decoded_w=8;decoded_h=32;end
            10: begin decoded_w=16;decoded_h=32;end
            11: begin decoded_w=32;decoded_h=64;end
            default: begin decoded_w=0;decoded_h=0;end
        endcase
    end
    wire [7:0] relative_y=target_y-attributes[7:0];
`ifdef GBK_SAVESTATE
    reg [7:0] geometry_relative_y;
`endif
    wire [9:0] snapped_target_y,snapped_screen_x;
    wire [3:0] mosaic_remainder_x,mosaic_remainder_y;
    wire mosaic_x_valid,mosaic_y_valid;
`ifdef GBK_SAVESTATE
    reg mosaic_y_coordinate_matches;
    wire mosaic_y_size_valid;
    // The lookup captures old target_y on this edge. Predict whether its tag
    // matches the new target_y at the two existing update sites, keeping the
    // coordinate comparator out of the GEOMETRY next-state path.
    always @(posedge clk)begin
        if(reset)mosaic_y_coordinate_matches<=target_y==0;
        else if(begin_line)mosaic_y_coordinate_matches<=target_y==(line_y==227 ? 8'd0 : line_y+8'd1);
        else mosaic_y_coordinate_matches<=1;
    end
    gba_mosaic_coordinate #(.COORD_BITS(8),.CHECK_COORDINATE(0)) mosaic_y(.clk,.coordinate({2'd0,target_y}),.size(mosaic[7:4]),.snapped(snapped_target_y),.valid(mosaic_y_size_valid),.remainder_value(mosaic_remainder_y));
    assign mosaic_y_valid=mosaic_y_coordinate_matches && mosaic_y_size_valid;
`ifdef GBK_SIM
    always @(negedge clk)if(!reset && (^target_y)!==1'bx && (^mosaic_y.coordinate_tag)!==1'bx &&
        mosaic_y_coordinate_matches !== (mosaic_y.coordinate_tag=={2'd0,target_y}))
        $fatal(1,"Mosaic Y coordinate validity predictor mismatch");
`endif
`else
    gba_mosaic_coordinate #(.COORD_BITS(8)) mosaic_y(.clk,.coordinate({2'd0,target_y}),.size(mosaic[7:4]),.snapped(snapped_target_y),.valid(mosaic_y_valid),.remainder_value(mosaic_remainder_y));
`endif
`ifdef GBK_SAVESTATE
    reg mosaic_coordinate_matches;
    wire mosaic_x_size_valid;
    // The lookup captures the old screen_x on each edge. Its coordinate tag
    // therefore matches the new screen_x exactly when that edge leaves X
    // unchanged. Track the three existing update sites instead of putting a
    // wide tag comparison ahead of every SAMPLE next-state decision.
    always @(posedge clk)begin
        if(reset || begin_line)mosaic_coordinate_matches<=1;
        else if(state==GEOMETRY)mosaic_coordinate_matches<=screen_x==attributes[24:16];
        else if(state==WRITE_PIXEL || (state==TILE_INDEX && skip_sample))mosaic_coordinate_matches<=0;
        else mosaic_coordinate_matches<=1;
    end
    gba_mosaic_coordinate #(.COORD_BITS(9),.CHECK_COORDINATE(0)) mosaic_x(.clk,.coordinate({1'b0,screen_x}),.size(mosaic[3:0]),.snapped(snapped_screen_x),.valid(mosaic_x_size_valid),.remainder_value(mosaic_remainder_x));
    assign mosaic_x_valid=mosaic_coordinate_matches && mosaic_x_size_valid;
`ifdef GBK_SIM
    always @(negedge clk)if(!reset && (^screen_x)!==1'bx && (^mosaic_x.coordinate_tag)!==1'bx &&
        mosaic_coordinate_matches !== (mosaic_x.coordinate_tag=={1'b0,screen_x}))
        $fatal(1,"Mosaic coordinate validity predictor mismatch");
`endif
`else
    gba_mosaic_coordinate #(.COORD_BITS(9)) mosaic_x(.clk,.coordinate({1'b0,screen_x}),.size(mosaic[3:0]),.snapped(snapped_screen_x),.valid(mosaic_x_valid),.remainder_value(mosaic_remainder_x));
`endif
    wire [7:0] vertical_delta=attributes[12] ? {4'd0,mosaic_remainder_y} : 8'd0;
    wire [7:0] sampled_relative_y_next=relative_y<vertical_delta ? 8'd0 : relative_y-vertical_delta;
    reg [7:0] sampled_relative_y;
    wire [7:0] decoded_field_w={1'b0,geometry_w} << (attributes[8] && attributes[9]);
    wire [7:0] decoded_field_h={1'b0,geometry_h} << (attributes[8] && attributes[9]);
    wire [63:0] matrix=EXTERNAL_OAM ? matrix_cache : oam[6144+attributes[29:25]*64+:64];
    wire signed [15:0] pa=matrix[15:0],pb=matrix[31:16],pc=matrix[47:32],pd=matrix[63:48];
    wire signed [8:0] start_x=-$signed({1'b0,decoded_field_w>>1});
    wire signed [8:0] start_y=$signed({1'b0,sampled_relative_y})-$signed({1'b0,decoded_field_h>>1});
    wire mosaic_group_start=!object_mosaic || local_x==0 || mosaic_remainder_x==0;
    wire [5:0] normal_x=hflip ? width-1-local_x : local_x;
    // Retain the group's first texture coordinate rather than recomputing
    // step*remainder for each pixel. The first partial group is clamped to
    // local X=0, matching normal/affine OBJ mosaic at a non-aligned origin.
    // This removes two combinational multipliers from the 133 MHz sample path
    // without adding a renderer state or changing its per-pixel cadence.
    wire signed [27:0] sampled_u=mosaic_group_start ? texture_u : mosaic_texture_u;
    wire signed [27:0] sampled_v=mosaic_group_start ? texture_v : mosaic_texture_v;
    wire [5:0] source_x=affine ? sampled_u[13:8] : mosaic_group_start ? normal_x : mosaic_source_x;
    wire [5:0] source_y=affine ? sampled_v[13:8] : normal_source_y;
    wire current_outside=texture_u<0 || texture_v<0 ||
        texture_u>=$signed({1'b0,width,8'd0}) || texture_v>=$signed({1'b0,height,8'd0});
    wire outside_texture=affine && (mosaic_group_start ? current_outside : mosaic_outside);
    // Compare before the late group selection, rather than routing a ROM bit
    // through a six-bit source mux and then a comparator in one fast cycle.
    wire current_row_hit=cached_source_y==texture_v[13:8];
    wire mosaic_row_hit=cached_source_y==mosaic_texture_v[13:8];
    wire sampled_row_hit=cached_valid && (affine ?
        (mosaic_group_start ? current_row_hit : mosaic_row_hit) : cached_source_y==normal_source_y);
    // Valid source coordinates keep tile X below the object's tile width.
    // The row and column fields therefore do not overlap. Build the linear
    // index from registered coordinates without a variable shift/add chain.
    // Out-of-texture samples are rejected before this address is consumed.
    reg [8:0] row_tile_1d;
    always @* case(width_shift)
        0: row_tile_1d={6'd0,sample_y[5:3]};
        1: row_tile_1d={5'd0,sample_y[5:3],sample_x[3]};
        2: row_tile_1d={4'd0,sample_y[5:3],sample_x[4:3]};
        3: row_tile_1d={3'd0,sample_y[5:3],sample_x[5:3]};
    endcase
    wire [9:0] row_tile=mapping_1d ?
        (eight_bpp ? {row_tile_1d,1'b0} : {1'b0,row_tile_1d}) :
        (eight_bpp ? {2'd0,sample_y[5:3],1'b0,sample_x[5:3],1'b0} :
                     {2'd0,sample_y[5:3],2'd0,sample_x[5:3]});
    wire [1:0] byte_offset=WORD_READS ? sample_x[1:0] : {1'b0,sample_x[0]};
    wire [2:0] nibble_offset=WORD_READS ? sample_x[2:0] : {1'b0,sample_x[1:0]};
    wire [7:0] sample_byte=cached_data[byte_offset*8+:8];
    wire [3:0] sample_nibble=cached_data[nibble_offset*4+:4];
    wire [7:0] response_byte=tile_word_data[byte_offset*8+:8];
    wire [3:0] response_nibble=tile_word_data[nibble_offset*4+:4];
    // In 8bpp the byte already represents transparent index zero. In 4bpp
    // only the palette prefix needs masking when the nibble is zero.
    // Decode transparency and palette bank in parallel before the pixel mux.
    // Kept lane outputs prevent zero detection from following sample_x selection.
    (* keep = "true" *) wire [63:0] sample_expanded,response_expanded;
    genvar lane;
    generate for(lane=0;lane<8;lane=lane+1) begin : palette_lane
        assign sample_expanded[lane*8+:8]={((|cached_data[lane*4+:4]) ? palette_bank : 4'd0),cached_data[lane*4+:4]};
        assign response_expanded[lane*8+:8]={((|tile_word_data[lane*4+:4]) ? palette_bank : 4'd0),tile_word_data[lane*4+:4]};
    end endgenerate
    wire [7:0] sample_palette_index=eight_bpp ? sample_byte : sample_expanded[nibble_offset*8+:8];
    // Decode both possible texels before selecting the capture state. This
    // avoids state decode -> 32-bit source mux -> nibble extraction -> zero
    // detection in a single render clock. No fetch or pixel state is added.
    wire [7:0] response_palette_index=eight_bpp ? response_byte : response_expanded[nibble_offset*8+:8];
    wire [4:0] source_word=WORD_READS ?
        (eight_bpp ? {1'b0,sample_x[5:2]} : {2'b0,sample_x[5:3]}) :
        (eight_bpp ? sample_x[5:1] : {1'b0,sample_x[5:2]});
    wire cached_address_hit=WORD_READS ? cached_addr[16:1]==sample_addr[16:1] : cached_addr==sample_addr;
    wire [16:0] next_sample_addr=eight_bpp ? {3'b010,sample_tile[9:1],sample_y[2:0],sample_x[2:1]} :
        {3'b010,sample_tile,sample_y[2:0],sample_x[2]};

    always @(posedge clk) begin
        if(reset) begin
            state<=IDLE;seen_y<=8'hff;target_y<=0;clear_x<=0;
            object_index<=0;attributes<=0;bank_valid<=0;
            geometry_w<=0;geometry_h<=0;
`ifndef GBK_FAST_FORWARD
            bank_y[0]<=0;bank_y[1]<=0;
`endif
            cached_valid<=0;cached_row_hit<=0;
            tile_addr<=0;overrun<=0;oam_addr<=0;
`ifndef GBK_FAST_FORWARD
            matrix_cache<=0;
`endif
            matrix_word<=0;
        end else if(begin_line) begin
            // Never continue writing the line that has just begun display.
            overrun<=state!=IDLE;
            seen_y<=line_y;target_y<=line_y==227 ? 8'd0 : line_y+8'd1;
            clear_x<=0;cached_valid<=0;cached_row_hit<=0;
            bank_valid[line_y==227 ? 1'b0 : !line_y[0]]<=0;
            state<=(line_y==227 || line_y<159) ? CLEAR : IDLE;
        end else case(state)
            CLEAR: if(clear_x==239) begin
                bank_valid[target_y[0]]<=1;
`ifndef GBK_FAST_FORWARD
                bank_y[target_y[0]]<=target_y;
`endif
                object_index<=0;state<=dispcnt[12] ? ATTR : IDLE;
            end else clear_x<=clear_x+1'b1;
            ATTR: begin
                if(EXTERNAL_OAM) begin oam_addr<=object_index;wait_count<=2;state<=WAIT_OAM;end
                else begin attributes<=oam[object_index*48+:48];state<=DECODE_SIZE;end
            end
            WAIT_OAM: begin
                state<=WAIT_OAM;
                if(wait_count!=0) wait_count<=wait_count-1'b1;
                else begin
                    attributes<=oam_data[47:0];
                    if(oam_data[8]) begin
                        oam_addr<={oam_data[29:25],2'd0};matrix_word<=0;
                        wait_count<=2;state<=WAIT_MATRIX;
                    end else state<=DECODE_SIZE;
                end
            end
            WAIT_MATRIX: begin
                state<=WAIT_MATRIX;
                if(wait_count!=0) wait_count<=wait_count-1'b1;
                else begin
`ifndef GBK_FAST_FORWARD
                    matrix_cache[matrix_word*16+:16]<=oam_data[63:48];
`endif
                    if(matrix_word==3) state<=DECODE_SIZE;
                    else begin matrix_word<=matrix_word+1'b1;oam_addr<=oam_addr+1'b1;wait_count<=2;end
                end
            end
            DECODE_SIZE: begin
                state<=DECODE_SIZE;
                if(!attributes[12] || mosaic_y_valid)begin
                // Separate shape/size decoding from affine field expansion
                // and centering; their combined fitted path exceeded 7.512 ns.
                geometry_w<=decoded_w;geometry_h<=decoded_h;
`ifdef GBK_SAVESTATE
                // Target line and latched attributes stay fixed for this
                // object. Use the existing decode edge, with no extra state,
                // to split subtraction from the GEOMETRY row-bound decision.
                geometry_relative_y<=relative_y;
`endif
                sampled_relative_y<=sampled_relative_y_next;state<=GEOMETRY;
            end
            end
            GEOMETRY: begin
                // DSP inputs are captured independently above; rejected
                // objects never consume their affine intermediates.
                // Rejected objects never consume texture coordinates. Avoid
                // routing the crop comparison into these 56 register enables.
                texture_u<=0;texture_v<=0;
                // Capture the remaining object fields on the same cycle,
                // including rejected objects. Only accepted objects reach
                // SAMPLE/AFFINE_MULT, so the row-bound comparison need only
                // select the next state, not drive this wide register enable.
                width<=geometry_w;height<=geometry_h;local_x<=0;field_width<=decoded_field_w;
                normal_source_y<=attributes[29] ? geometry_h-1-sampled_relative_y : sampled_relative_y;
                affine<=attributes[8];
                object_mosaic<=attributes[12];
                case(geometry_w)
                    8:width_shift<=0;16:width_shift<=1;32:width_shift<=2;default:width_shift<=3;
                endcase
                screen_x<=attributes[24:16];hflip<=attributes[28];
                eight_bpp<=attributes[13];mapping_1d<=dispcnt[6];
                window_object<=attributes[11];
                tile_number<={attributes[41:33],attributes[32] && !attributes[13]};
                palette_bank<=attributes[47:44];object_priority<=attributes[43:42];
                semi_object<=attributes[11:10]==1;
                if((!attributes[8] && attributes[9]) || attributes[11:10]==3 ||
`ifdef GBK_SAVESTATE
                    (attributes[11] && !dispcnt[15]) || geometry_w==0 || geometry_relative_y>=decoded_field_h)
`else
                    (attributes[11] && !dispcnt[15]) || geometry_w==0 || relative_y>=decoded_field_h)
`endif
                    state<=NEXT_OBJ;
                else begin
                    // The source-coordinate tag is local to this object's
                    // geometry, tile base, and colour depth.
                    cached_valid<=0;
                    state<=attributes[8] ? AFFINE_MULT : SAMPLE;
                end
            end
            AFFINE_MULT: begin
                state<=AFFINE_SUM;
            end
            AFFINE_SUM: begin
                affine_sum_u<=product_a+product_b;affine_sum_v<=product_c+product_d;
                state<=AFFINE_CENTER;
            end
            AFFINE_CENTER: begin
                texture_u<=($signed({1'b0,width})<<<7)+affine_sum_u;
                texture_v<=($signed({1'b0,height})<<<7)+affine_sum_v;
                state<=SAMPLE;
            end
            // Vertical geometry was captured before walking this object's
            // row. Its lookup need not gate every later pixel's registers.
            // Check it at DECODE_SIZE, where its data is actually consumed.
            SAMPLE: begin
                state<=SAMPLE;
                if(!object_mosaic || mosaic_x_valid)begin
                if(mosaic_group_start)begin
                    mosaic_texture_u<=texture_u;mosaic_texture_v<=texture_v;mosaic_source_x<=normal_x;
                    mosaic_outside<=current_outside;
                end
                // Calculate the next coordinates independently of bounds.
                // A wide crop comparison must not also control a wide
                // coordinate adder/mux before the next register edge.
                next_texture_u<=texture_u+step_u;next_texture_v<=texture_v+step_v;
                skip_sample<=screen_x>=240 || outside_texture || (dispcnt[2:0]>=3 && tile_number<512);
                sample_x<=source_x;sample_y<=source_y;destination_x<=screen_x[7:0];
                // Prepare the row offset in the existing sample cycle,
                // leaving only tile-base addition for TILE_INDEX.
                // Compare the row while sampling it, before the word-tag
                // and colour-selection stage. The cache cannot change
                // between SAMPLE and TILE_INDEX; a new line aborts both.
                cached_row_hit<=sampled_row_hit;
                state<=TILE_INDEX;
            end
            end
            TILE_INDEX: if(skip_sample) begin
                local_x<=local_x+1'b1;screen_x<=screen_x+1'b1;
                texture_u<=next_texture_u;texture_v<=next_texture_v;
                state<=local_x==field_width-1 ? NEXT_OBJ : SAMPLE;
            end else if(cached_row_hit && cached_source_word==source_word) begin
                // Adjacent pixels usually share a fetched halfword. The
                // destination RAM read has already settled since SAMPLE;
                // neither address generation nor another read stage is needed.
                sampled_index<=sample_palette_index;
                state<=WRITE_PIXEL;
            end else begin sample_tile<=tile_number+row_tile;state<=TILE_ADDRESS;end
            TILE_ADDRESS: begin
                // These fields do not overlap once 8bpp tile bit 0 is clear.
                sample_addr<=next_sample_addr;
                // TILE_INDEX already handled a retained source row/word hit.
                // A tagged word miss can issue now; no second address check
                // or fixed settling interval is needed before the request.
                if(TAGGED_READS && WORD_READS) begin
                    tile_addr<=next_sample_addr;wait_count<=4;state<=WAIT_TILE;
                end else state<=CHECK_TILE;
            end
            CHECK_TILE: if(!cached_valid || !cached_address_hit) begin
                tile_addr<=sample_addr;wait_count<=14;state<=WAIT_TILE;
            end else begin
                sampled_index<=sample_palette_index;
                state<=READ_PIXEL;
            end
            WAIT_TILE: begin
                state<=WAIT_TILE;
                if(TAGGED_READS && WORD_READS ?
`ifdef GBK_FAST_FORWARD
                    wait_count==0 && tile_word_valid && tile_word_addr==response_tag : wait_count==0) begin
`else
                    wait_count==0 && tile_word_valid && tile_word_addr==tile_addr[16:1] : wait_count==0) begin
`endif
                    cached_data<=WORD_READS ? tile_word_data : {16'd0,tile_data};cached_addr<=tile_addr;
                    cached_source_y<=sample_y;cached_source_word<=source_word;
                    cached_valid<=1;
                    if(TAGGED_READS && WORD_READS) begin
                        // Destination address has been held since SAMPLE,
                        // so the pixel RAM read is already settled. Capture
                        // this response's texel and proceed to its write.
                        sampled_index<=response_palette_index;state<=WRITE_PIXEL;
                    end else state<=CHECK_TILE;
                end
                // The request address changes on entry. Four clocks exclude
                // any response issued before that edge, including an old
                // same-address word from before a completed texture write.
                // After this minimum, wait for the exact tagged response.
                else if(wait_count!=0) wait_count<=wait_count-1'b1;
            end
            READ_PIXEL: state<=WRITE_PIXEL;
            WRITE_PIXEL: begin
                local_x<=local_x+1'b1;screen_x<=screen_x+1'b1;
                texture_u<=next_texture_u;texture_v<=next_texture_v;
                state<=local_x==field_width-1 ? NEXT_OBJ : SAMPLE;
            end
            NEXT_OBJ: if(object_index==127) state<=IDLE;
                else begin object_index<=object_index+1'b1;state<=ATTR;end
            default: state<=IDLE;
        endcase
    end
endmodule
