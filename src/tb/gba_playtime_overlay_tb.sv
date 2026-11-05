`timescale 1ns/1ps
module gba_playtime_overlay_tb;
    reg clk=0,reset=1;
    always #5 clk=~clk;
    reg [23:0] rgb_in=24'h28486c;
    reg de_in=0,skip_in=0,hs_in=0,vs_in=0;
    reg [2:0] show=0,corner=0;
    reg wall_valid=1;
    reg [15:0] wall_hhmm=16'h1234;
    reg [27:0] session_hhmm=28'h0000102,total_hhmm=28'h1230345;
    wire [23:0] rgb;
    wire de,skip,hs,vs;
    gba_playtime_overlay overlay(.*);
    reg [23:0] expected=24'h28486c;
    integer frame_count=0;
    integer preview_file=0;
    string preview_path;
    function automatic [27:0] total_value(input integer pos);
        case(pos)
            0:total_value=28'h0020345;
            1:total_value=28'h0120345;
            2:total_value=28'h1230345;
            3:total_value=28'h4000000;
            4:total_value=28'h4161559;
            default:total_value=28'h0000000;
        endcase
    endfunction
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
            14:glyph=15'b001_001_111_101_111;
            15:glyph=15'b100_100_111_101_101;
            16:glyph=15'b000_000_111_111_101;
            17:glyph=0;
            default:glyph=15'b000_000_111_000_000; // unavailable clock
        endcase
    endfunction
    // Independent pixel oracle: enumerate enabled sources and draw glyphs
    // directly; no compact-row lookup or mask ROM from the implementation.
    function automatic [23:0] pixel(input integer x,y,pos,flags,valid);
        integer count,slot,ox,oy,lx,ly,c,px,py,symbol,width;
        string text_line;
        reg [23:0] duration;
        reg [14:0] bitmap;
        reg ink,edge_pixel;
        begin
            pixel=rgb_in;count=0;slot=0;ink=0;edge_pixel=0;
            for(integer n=0;n<3;n=n+1)if(flags & (1<<n))count=count+1;
            oy=(pos==2 || pos==3 || pos==5) ? 158-count*8 : 2;
            for(integer n=0;n<3;n=n+1)begin
                if(flags & (1<<n))begin
                    text_line=n==0 ? (valid ? "12:34" : "--:--") : n==1 ? "C01h 02m" : "T123d 03h 45m";
                    if(n==2)case(pos)
                        0:text_line="T2d 03h 45m";
                        1:text_line="T12d 03h 45m";
                        2:text_line="T123d 03h 45m";
                        3:text_line="T400d 00h 00m";
                        4:text_line="T416d 15h 59m";
                        5:text_line="T00h 00m";
                    endcase
                    width=text_line.len()*5;
                    ox=(pos>=4) ? (240-width)/2 : ((pos&1) ? 238-width : 2);
                    lx=x-ox;ly=y-oy-slot*8;
                    if(lx>=0 && lx<width && ly>=0 && ly<7)begin
                        c=lx/5;px=lx%5;py=ly;symbol=13;
                        case(text_line[c])
                            "C":symbol=11;"T":symbol=12;":":symbol=10;
                            "d":symbol=14;"h":symbol=15;"m":symbol=16;
                            " ":symbol=17;"-":symbol=13;
                            default:symbol=text_line[c]-48;
                        endcase
                        bitmap=glyph(5'(symbol));
                        for(integer gy=0;gy<5;gy=gy+1)begin
                            for(integer gx=0;gx<3;gx=gx+1)begin
                                if(bitmap[14-gy*3-gx])begin
                                    if(px==gx+1 && py==gy+1)ink=1;
                                    if(px>=gx && px<=gx+2 && py>=gy && py<=gy+2)edge_pixel=1;
                                end
                            end
                        end
                    end
                    slot=slot+1;
                end
            end
            if(ink)pixel=24'hffffff;else if(edge_pixel)pixel=0;
        end
    endfunction
    task tick;
        @(posedge clk);#1;
        if(reset)begin
            if({rgb,de,skip,hs,vs}!==0)$fatal(1,"Reset output mismatch");
        end else begin
            if({de,skip,hs,vs}!=={de_in,skip_in,hs_in,vs_in})
                $fatal(1,"Changed APF control latency");
            if(rgb!==expected)$fatal(1,"Pixel mismatch frame=%0d x=%0d y=%0d got=%h expected=%h",
                frame_count,overlay.x,overlay.y,rgb,expected);
        end
        @(negedge clk);
    endtask
    task frame(input integer pos,flags,valid);
        corner=3'(pos);show=3'(flags);wall_valid=1'(valid);
        wall_hhmm=16'h1234;session_hhmm=28'h0000102;total_hhmm=total_value(pos);
        expected=rgb_in;vs_in=1;tick();vs_in=0;tick();
        if(pos==0 && flags==7 && valid && $value$plusargs("overlay_ppm=%s",preview_path))begin
            preview_file=$fopen(preview_path,"wb");
            if(!preview_file)$fatal(1,"Cannot create renderer preview");
            $fwrite(preview_file,"P6\n240 160\n255\n");
        end
        for(integer yy=0;yy<160;yy=yy+1)begin
            expected=rgb_in;hs_in=1;tick();hs_in=0;tick();
            for(integer xx=0;xx<240;xx=xx+1)begin
                de_in=1;expected=pixel(xx,yy,pos,flags,valid);
                if((xx+yy)%7==0)begin skip_in=1;tick();tick();skip_in=0;end
                tick();
                if(preview_file)$fwrite(preview_file,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
                // Every setting and displayed value must stay frozen until VS.
                if(xx==120 && yy==80)begin
                    show=~3'(flags);corner=3'((pos+1)%6);wall_valid=!valid;
                    wall_hhmm=16'h2359;session_hhmm=24'h999959;total_hhmm=0;
                end
            end
            expected=rgb_in;de_in=0;tick();tick();
        end
        if(preview_file)begin $fclose(preview_file);preview_file=0;end
        frame_count=frame_count+1;
    endtask
    initial begin
        repeat(2)tick();reset=0;tick();
        for(integer valid=0;valid<2;valid=valid+1)
            for(integer pos=0;pos<6;pos=pos+1)
                for(integer flags=0;flags<8;flags=flags+1)frame(pos,flags,valid);
        reset=1;tick();reset=0;tick();frame(5,4,1);
        $display("PASS: %0d exact pixel frames, all 48 enable/position combinations, unavailable clock, held dots, VS snapshots and reset",frame_count);
        $finish;
    end
    initial begin #100000000;$fatal(1,"Overlay timeout");end
endmodule
