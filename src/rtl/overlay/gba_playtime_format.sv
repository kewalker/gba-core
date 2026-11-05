// Serial seconds-to-duration conversion. The display retains its original
// 9999-hour limit; output packs {4'd0, days[8:0], hours[4:0], minutes[5:0]}.
module gba_playtime_format(
    input wire clk,start,
    input wire [31:0] seconds,
    output reg busy=0,
    output reg done=0,
    output reg [23:0] duration_binary=0
);
    reg [31:0] dividend=0;
    reg [6:0] remainder=0;
    reg [5:0] bit_index=0;
    reg [1:0] phase=0;
    reg [5:0] minutes=0;
    wire [7:0] divisor=phase==2 ? 8'd24 : 8'd60;
    wire [7:0] trial={remainder,dividend[31]};
    wire [7:0] residue=trial>=divisor ? trial-divisor : trial;
    wire [31:0] quotient={dividend[30:0],trial>=divisor};
    always @(posedge clk)begin
        done<=0;
        if(start && !busy)begin
            busy<=1;phase<=0;bit_index<=0;dividend<=seconds;remainder<=0;
        end else if(busy)begin
            dividend<=quotient;remainder<=residue[6:0];bit_index<=bit_index+1'b1;
            if(bit_index==31)begin
                bit_index<=0;remainder<=0;phase<=phase+1'b1;
                if(phase==1)begin
                    minutes<=residue[5:0];
                    if(quotient>9999)begin
                        duration_binary<={4'd0,9'd416,5'd15,6'd59};busy<=0;done<=1;
                    end
                end
                if(phase==2)begin
                    duration_binary<={4'd0,quotient[8:0],residue[4:0],minutes};busy<=0;done<=1;
                end
            end
        end
    end
endmodule

// Use spare block RAM for decimal digits, keeping conversion out of logic
// cells. All fields and both channels have the same one-video-clock latency.
module gba_playtime_decode(
    input wire clk,
    input wire [23:0] session_binary,total_binary,
    output reg [27:0] session_bcd=0,
    output reg [27:0] total_bcd=0
);
    (* ramstyle="M10K" *) reg [11:0] days[0:511];
    (* ramstyle="M10K" *) reg [7:0] hours[0:31];
    (* ramstyle="M10K" *) reg [7:0] minutes[0:63];
    initial begin
        for(integer n=0;n<512;n=n+1)days[n]={4'(n/100),4'((n/10)%10),4'(n%10)};
        for(integer n=0;n<32;n=n+1)hours[n]={4'(n/10),4'(n%10)};
        for(integer n=0;n<64;n=n+1)minutes[n]={4'(n/10),4'(n%10)};
    end
    always @(posedge clk)begin
        session_bcd<={days[session_binary[19:11]],hours[session_binary[10:6]],minutes[session_binary[5:0]]};
        total_bcd<={days[total_binary[19:11]],hours[total_binary[10:6]],minutes[total_binary[5:0]]};
    end
endmodule

// A compact optional clock/playtime overlay. All APF data/control gets the same
// single register stage; held/skipped pixels never advance the coordinates.
// Settings and formatted values must be held in this clock domain. Snapshot
// them at VS so changing counters/settings cannot tear a displayed frame.
module gba_playtime_overlay(
    input wire clk,reset,
    input wire [23:0] rgb_in,
    input wire de_in,skip_in,hs_in,vs_in,
    input wire [2:0] show, // wall / session / total, all off by default upstream
    input wire [2:0] corner, // 0..3: legacy corners; 4: top centre; 5: bottom centre
    input wire wall_valid,
    input wire [15:0] wall_hhmm,
    input wire [27:0] session_hhmm,total_hhmm,
    output wire [23:0] rgb,
    output reg de=0,
    output reg skip=0,
    output reg hs=0,
    output reg vs=0
);
    reg [8:0] x=0,y=0;
    reg previous_de=0;
    reg [1:0] line_count=0,first_line=0,second_line=0;
    reg [2:0] position=0;
    reg clock_valid=0;
    reg [15:0] wall=0;
    reg [27:0] session=0,total=0;
    function automatic [14:0] glyph(input [4:0] ch);
        case(ch)
            0:glyph=15'b111_101_101_101_111;
            1:glyph=15'b010_110_010_010_111;
            2:glyph=15'b111_001_111_100_111;
            3:glyph=15'b111_001_111_001_111;
            4:glyph=15'b101_101_111_001_001;
            5:glyph=15'b111_100_111_001_111;
            6:glyph=15'b111_100_111_101_111;
            7:glyph=15'b111_001_010_010_010;
            8:glyph=15'b111_101_111_101_111;
            9:glyph=15'b111_101_111_001_111;
            10:glyph=15'b000_010_000_010_000;
            11:glyph=15'b111_100_100_100_111; // C (current session)
            12:glyph=15'b111_010_010_010_010; // T
            14:glyph=15'b001_001_111_101_111; // d
            15:glyph=15'b100_100_111_101_101; // h
            16:glyph=15'b000_000_111_111_101; // m
            17:glyph=0; // blank
            default:glyph=15'b000_000_111_000_000; // unavailable clock
        endcase
    endfunction
    function automatic [1:0] raster_mask(input [4:0] symbol,input [2:0] px,py);
        reg [14:0] bitmap;
        begin
            bitmap=glyph(symbol);raster_mask=0;
            for(integer gy=0;gy<5;gy=gy+1)begin
                for(integer gx=0;gx<3;gx=gx+1)begin
                    if(bitmap[14-gy*3-gx])begin
                        if(px==gx+1 && py==gy+1)raster_mask[1]=1;
                        if(px>=gx && px<=gx+2 && py>=gy && py<=gy+2)raster_mask[0]=1;
                    end
                end
            end
        end
    endfunction
    (* romstyle="M10K" *) reg [1:0] font_masks[0:2047];
    initial for(integer n=0;n<2048;n=n+1)font_masks[n]=raster_mask(n[10:6],n[5:3],n[2:0]);
    reg [1:0] pixel_mask=0;
    reg mask_enabled=0;
    reg [23:0] base_rgb=0;
    // ROM and base pixel capture on the same edge. The output mux retains
    // the existing one-clock RGB/control latency without a second stage.
    always @(posedge clk)pixel_mask<=font_masks[{ch,column,row}];
    assign rgb=mask_enabled ? (pixel_mask[1] ? 24'hffffff : pixel_mask[0] ? 24'd0 : base_rgb) : base_rgb;
    wire centred=position==4 || position==5;
    wire bottom=position==2 || position==3 || position==5;
    wire has_days=duration[27:16]!=0;
    reg [2:0] day_digits;
    always @*begin
        if(duration[27:24]!=0)day_digits=3;
        else if(duration[23:20]!=0)day_digits=2;
        else day_digits=1;
    end
    wire [4:0] text_chars=source_line==0 ? 5 : has_days ? 10+day_digits : 8;
    wire [8:0] text_width={4'd0,text_chars}*9'd5;
    wire [8:0] origin_x=centred ? (9'd240-text_width)/2 : position[0] ? 9'd238-text_width : 9'd2;
    wire [8:0] origin_y=bottom ? 9'd158-{4'd0,line_count,3'd0} : 9'd2;
    wire in_area=x>=origin_x && x<origin_x+text_width && y>=origin_y && y<origin_y+9'd24;
    wire [4:0] local_y=5'(y-origin_y);
    wire [1:0] line_number=local_y[4:3];
    wire [1:0] source_line=line_number==0 ? first_line : line_number==1 ? second_line : 2'd2;
    wire [6:0] local_x=7'(x-origin_x);
    wire [2:0] column=local_x%7'd5,row=local_y[2:0];
    wire [4:0] character=local_x/7'd5;
    reg [4:0] ch;
    reg line_enabled;
    reg [27:0] duration;
    wire [4:0] duration_start=has_days ? {2'd0,day_digits}+5'd3 : 5'd1;
    always @*begin
        ch=13;duration=source_line==1 ? session : total;
        line_enabled=line_number<line_count;
        if(source_line==0)begin
            case(character)
                0:ch=clock_valid ? wall[15:12] : 4'd13;
                1:ch=clock_valid ? wall[11:8] : 4'd13;
                2:ch=10;
                3:ch=clock_valid ? wall[7:4] : 4'd13;
                4:ch=clock_valid ? wall[3:0] : 4'd13;
                default:ch=15;
            endcase
        end else begin
            ch=17;
            if(character==0)ch=source_line==1 ? 11 : 12;
            else if(has_days && character<=day_digits)begin
                // Bound the digit mux explicitly; avoid a wide variable shift.
                case(day_digits-character[2:0])
                    0:ch={1'b0,duration[19:16]};
                    1:ch={1'b0,duration[23:20]};
                    2:ch={1'b0,duration[27:24]};
                    default:ch=17;
                endcase
            end else if(has_days && character=={2'd0,day_digits}+5'd1)ch=14;
            else begin
                if(character==duration_start)ch={1'b0,duration[15:12]};
                else if(character==duration_start+5'd1)ch={1'b0,duration[11:8]};
                else if(character==duration_start+5'd2)ch=15;
                else if(character==duration_start+5'd4)ch={1'b0,duration[7:4]};
                else if(character==duration_start+5'd5)ch={1'b0,duration[3:0]};
                else if(character==duration_start+5'd6)ch=16;
            end
        end
    end
    always @(posedge clk)begin
        if(reset)begin
            x<=0;y<=0;previous_de<=0;line_count<=0;
            base_rgb<=0;mask_enabled<=0;de<=0;skip<=0;hs<=0;vs<=0;
        end else begin
            de<=de_in;skip<=skip_in;hs<=hs_in;vs<=vs_in;
            base_rgb<=rgb_in;
            mask_enabled<=de_in && in_area && row<7 && line_enabled && (source_line!=0 || character<5);
            previous_de<=de_in;
            if(previous_de && !de_in)y<=y+1'b1;
            if(de_in && !skip_in)x<=x+1'b1;
            if(hs_in)x<=0;
            if(vs_in)begin
                x<=0;y<=0;position<=corner;
                // Pack enabled sources once per frame, off the pixel path.
                line_count<={1'b0,show[0]}+{1'b0,show[1]}+{1'b0,show[2]};
                first_line<=show[0] ? 2'd0 : show[1] ? 2'd1 : 2'd2;
                second_line<=show[0] && show[1] ? 2'd1 : 2'd2;
                clock_valid<=wall_valid;wall<=wall_hhmm;session<=session_hhmm;total<=total_hhmm;
            end
        end
    end
endmodule
