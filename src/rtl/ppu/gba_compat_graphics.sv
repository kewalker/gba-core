// Decode snapped coordinates and remainders together in spare block RAM.
// Keeping subtraction in the table removes a carry chain from the held-dot
// affine address path, with the same one-clock lookup latency and valid tag.
module gba_mosaic_coordinate #(parameter integer COORD_BITS=10
`ifdef GBK_SAVESTATE
    ,parameter bit CHECK_COORDINATE=1
`endif
)(input wire clk,input wire [9:0] coordinate,input wire [3:0] size,
    output wire [9:0] snapped,output wire valid,output wire [3:0] remainder_value);
    localparam integer COORDINATES=1<<COORD_BITS;
    (* ramstyle="M10K" *) reg [COORD_BITS+3:0] lookup[0:16*COORDINATES-1];
    initial for(integer divisor_index=0;divisor_index<16;divisor_index=divisor_index+1)
        for(integer coordinate_index=0;coordinate_index<COORDINATES;coordinate_index=coordinate_index+1)
            lookup[divisor_index*COORDINATES+coordinate_index]=
                ((coordinate_index-coordinate_index % (divisor_index+1))<<4) |
                (coordinate_index % (divisor_index+1));
    reg [COORD_BITS+3:0] decoded;
    reg [3:0] size_tag;
    reg [9:0] coordinate_tag;
    always @(posedge clk)begin
        decoded<=lookup[{size,coordinate[COORD_BITS-1:0]}];
        coordinate_tag<=coordinate;size_tag<=size;
    end
    assign snapped={{(10-COORD_BITS){1'b0}},decoded[COORD_BITS+3:4]};
`ifdef GBK_SAVESTATE
    // A client that owns every coordinate update can provide the equivalent
    // registered coordinate match, while retaining this live size-tag check.
    assign valid=(!CHECK_COORDINATE || coordinate_tag==coordinate) && size_tag==size;
`else
    assign valid=coordinate_tag==coordinate && size_tag==size;
`endif
    assign remainder_value=decoded[3:0];
`ifdef GBK_SIM
    always @(posedge clk)if((coordinate>>COORD_BITS)!=0)$fatal(1,"Mosaic coordinate exceeds allocated ROM range");
`endif
endmodule

// Independent mode-2 BG2 fetch path. References supplied by the memory map
// already include the current scanline's PB/PD advance.
module gba_affine_background(
    input wire [9:0] screen_x,
    input wire [27:0] refx,refy,
    input wire [15:0] pa,pc,cnt,map_data,tile_data,
    output wire [15:0] map_addr,tile_addr,
    output wire [7:0] palette
);
    wire signed [27:0] raw_x=$signed(refx)+$signed(pa)*$signed({1'b0,screen_x});
    wire signed [27:0] raw_y=$signed(refy)+$signed(pc)*$signed({1'b0,screen_x});
    wire signed [19:0] ix=raw_x>>>8,iy=raw_y>>>8;
    wire [10:0] dimension=11'd128<<cnt[15:14];
    wire [9:0] mask=dimension-1'b1;
    wire outside=!cnt[13] && (ix<0 || iy<0 || ix>=$signed({1'b0,dimension}) || iy>=$signed({1'b0,dimension}));
    wire [9:0] sx=ix[9:0]&mask,sy=iy[9:0]&mask;
    reg [13:0] map_index;
    always @* case(cnt[15:14])
        0:map_index={6'd0,sy[6:3],sx[6:3]};
        1:map_index={4'd0,sy[7:3],sx[7:3]};
        2:map_index={2'd0,sy[8:3],sx[8:3]};
        3:map_index={sy[9:3],sx[9:3]};
    endcase
    wire [15:0] map_byte={cnt[12:8],11'd0}+map_index;
    wire [7:0] tile_number=map_byte[0] ? map_data[15:8] : map_data[7:0];
    wire [15:0] tile_byte={cnt[3:2],14'd0}+{tile_number,sy[2:0],sx[2:0]};
    assign map_addr=map_byte>>1;
    assign tile_addr=tile_byte>>1;
    assign palette=outside ? 8'd0 : tile_byte[0] ? tile_data[15:8] : tile_data[7:0];
endmodule
