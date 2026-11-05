`timescale 1ns/1ps
module gba_playtime_format_tb;
    reg clk=0,start=0;
    reg [31:0] seconds=0;
    wire busy,done;
    wire [23:0] duration_binary;
    always #5 clk=~clk;
    gba_playtime_format dut(.*);
    function automatic [23:0] reference_value(input [31:0] value);
        integer days,hours,minutes;
        begin
            hours=value/3600;minutes=(value/60)%60;
            if(hours>9999)begin hours=9999;minutes=59;end
            days=hours/24;hours=hours%24;
            reference_value={4'd0,9'(days),5'(hours),6'(minutes)};
        end
    endfunction
    task tick;@(posedge clk);#1;@(negedge clk);endtask
    integer count=0,clocks=0;
    reg [31:0] random_value=32'h19932026;
    reg [23:0] expected;
    task check(input [31:0] value);
        seconds=value;expected=reference_value(value);start=1;tick();start=0;clocks=0;
        while(!done && clocks<100)begin
            if(clocks==4)begin seconds=~value;start=1;end
            if(clocks==5)start=0;
            tick();clocks=clocks+1;
        end
        if(!done || busy || duration_binary!==expected || clocks>96)
            $fatal(1,"Format %0d got %h expected %h clocks=%0d",value,duration_binary,expected,clocks);
        tick();if(done)$fatal(1,"Formatter completion was not a pulse");
        count=count+1;
    endtask
    initial begin
        tick();check(0);check(59);check(60);check(3599);check(3600);check(86399);check(86400);check(86460);check(172800);check(35999999);check(36000000);check(32'hffffffff);
        for(integer n=0;n<2048;n=n+1)begin
            random_value=random_value^(random_value<<13);random_value=random_value^(random_value>>17);random_value=random_value^(random_value<<5);
            check(n[0] ? random_value : random_value%36000000);
        end
        $display("PASS: %0d independent playtime formatting vectors, minute/hour/day boundaries, original saturation limit, busy ownership and bounded latency",count);$finish;
    end
    initial begin #100000000;$fatal(1,"Formatter timeout");end
endmodule
