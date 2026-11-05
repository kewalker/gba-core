`timescale 1ns/1ps
module gba_playtime_host_tb #(parameter ENDIAN_LITTLE=0);
 wire [31:0] host_date_bcd=0,host_epoch=0; wire rtc_acknowledge=0; wire rtc_request,rtc_boot_ready; wire [97:0] rtc_reply=0; wire [97:0] rtc_payload; wire [1:0] rtc_operation;
    reg clk=0,video_clk=0,video_reset=0,running=0,in_menu=0,guest_stopped=0;
    always #5 clk=~clk;
    always #30.7 video_clk=~video_clk;
    reg bridge_wr=0,bridge_rd=0;
    wire endian_little=ENDIAN_LITTLE;
    reg [31:0] bridge_addr=0,bridge_wr_data=0;
    reg host_toggle=0,host_valid=0;
    reg [31:0] host_time_bcd=32'h00123456;
    reg request_read=0,allcomplete=0;
    reg [15:0] request_id=0;
    wire stats_ack,video_wall_valid;
    wire [31:0] bridge_rdata;
    wire [2:0] video_show;
    wire [2:0] video_corner;
    wire [15:0] video_wall;
    wire [27:0] video_session,video_total;
    gba_playtime_host #(.CLOCK_HZ(1000)) dut(.*);
    function automatic [31:0] transport(input [31:0] data);
        transport=ENDIAN_LITTLE ? data : {data[7:0],data[15:8],data[23:16],data[31:24]};
    endfunction
    function automatic [31:0] scalar(input [31:0] data);
        scalar=ENDIAN_LITTLE ? {data[7:0],data[15:8],data[23:16],data[31:24]} : data;
    endfunction
    task tick;@(posedge clk);#1;@(negedge clk);endtask
    task write_word(input [31:0] addr,data);
        bridge_addr=addr;bridge_wr_data=data;bridge_wr=1;tick();bridge_wr=0;tick();
    endtask
    task read_word(input [31:0] addr,expected);
        bridge_addr=addr;bridge_rd=1;tick();bridge_rd=0;tick();
        if(bridge_rdata!==expected)$fatal(1,"Bridge %h read %h expected %h",addr,bridge_rdata,expected);
        // A new live address must not replace the previous buffered response.
        bridge_addr=32'h1000000c;tick();
        if(bridge_rdata!==expected)$fatal(1,"Unstrobed address replaced buffered response");
    endtask
    localparam [127:0] ID=128'h112233445566778899aabbccddeeff00;
    task load_game;
        running=0;write_word(32'h08000000,0);
        for(integer n=0;n<4;n=n+1)write_word(32'h080000a0+n*4,transport(ID[n*32+:32]));
    endtask
    reg [31:0] words[0:7];
    task load_record;
        words[0]=32'h54504247;words[1]=1;
        for(integer n=0;n<4;n=n+1)words[n+2]=ID[n*32+:32];
        words[6]=3661;words[7]=0;
        for(integer n=0;n<7;n=n+1)words[7]=words[7]^words[n];
        for(integer n=0;n<8;n=n+1)write_word(32'h10000100+n*4,transport(words[n]));
    endtask
    integer before_session,before_total;
    initial begin
        tick();repeat(1500)tick();
        if(video_show!==0)$fatal(1,"Overlay not off at powerup");
        read_word(32'h10000000,0);read_word(32'h10000004,0);read_word(32'h10000008,0);read_word(32'h1000000c,0);
        load_game();load_record();
        if(dut.total_seconds!=3661 || dut.session_seconds!=0)$fatal(1,"Sidecar import failed");
        host_valid=1;host_toggle=1;tick();
        write_word(32'h10000000,scalar(1));write_word(32'h10000004,scalar(1));write_word(32'h10000008,scalar(1));write_word(32'h1000000c,scalar(3));
        read_word(32'h10000000,scalar(1));read_word(32'h10000004,scalar(1));read_word(32'h10000008,scalar(1));read_word(32'h1000000c,scalar(3));
        repeat(1500)tick();
        if(video_show!==7 || video_corner!==3 || video_wall!==16'h1234 || video_total!==24'h000101 || !video_wall_valid)
            $fatal(1,"Bundled video CDC/format failed %h %h %h %h",video_show,video_corner,video_wall,video_total);
        running=1;repeat(2500)tick();
        if(dut.session_seconds!=2 || dut.total_seconds!=3663)$fatal(1,"Running playtime failed");
        in_menu=1;before_session=dut.session_seconds;before_total=dut.total_seconds;repeat(2500)tick();
        if(dut.session_seconds!=before_session || dut.total_seconds!=before_total)$fatal(1,"Menu counted playtime");
        in_menu=0;guest_stopped=1;repeat(10)tick();before_session=dut.session_seconds;repeat(2500)tick();
        if(dut.session_seconds!=before_session)$fatal(1,"STOP counted playtime");
        guest_stopped=0;repeat(1000)tick();
        running=0;video_reset=1;repeat(2500)tick();video_reset=0;
        if(dut.session_seconds!=before_session+1)$fatal(1,"Reset counted or cleared playtime");
        before_total=dut.total_seconds;
        // The late record must not roll a running session backwards.
        load_record();if(dut.total_seconds!=before_total)$fatal(1,"Late import rolled back total");
        request_id=3;request_read=1;
        if(stats_ack)$fatal(1,"Export acknowledged before snapshot");
        tick();if(!stats_ack)$fatal(1,"Snapshot never acknowledged");
        request_read=0;tick();
        words[6]=before_total;words[7]=0;
        for(integer n=0;n<7;n=n+1)words[7]=words[7]^words[n];
        running=1;repeat(2000)tick();
        for(integer n=0;n<8;n=n+1)read_word(32'h10000100+n*4,transport(words[n]));
        allcomplete=1;tick();allcomplete=0;tick();
        write_word(32'h0e000000,32'hbad0bad0);
        if(dut.total_seconds<before_total+2)$fatal(1,"Export stalled game clock");
        load_game();if(dut.session_seconds!=0 || dut.total_seconds!=0)$fatal(1,"New game failed counter reset");
        if(!dut.wall_valid || dut.wall_time_bcd[23:8]!=16'h1235)$fatal(1,"New game reset wall clock");
        load_record();if(dut.total_seconds!=3661)$fatal(1,"Relaunch lost saved total");
        // Preserve legacy values and exercise the extra position bit through
        // scalar byte order, readback and the complete asynchronous descriptor.
        for(integer pos=0;pos<6;pos=pos+1)begin
            write_word(32'h1000000c,scalar(pos));
            read_word(32'h1000000c,scalar(pos));
            repeat(1500)tick();
            if(video_corner!==3'(pos) || video_show!==7 || video_wall!==16'h1235 ||
                video_total!==24'h000101 || video_session!==0 || !video_wall_valid)
                $fatal(1,"Position %0d corrupted bundled descriptor",pos);
        end
        write_word(32'h1000000c,scalar(6));read_word(32'h1000000c,scalar(0));
        write_word(32'h1000000c,scalar(32'hffffffff));read_word(32'h1000000c,scalar(0));
        $display("PASS: host settings, header identity, endian=%0d, menu/STOP/reset accounting, frozen sidecar and CDC",ENDIAN_LITTLE);
        $finish;
    end
    initial begin #1000000;$fatal(1,"Host integration timeout");end
endmodule
