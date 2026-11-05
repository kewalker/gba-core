`timescale 1ns/1ps
module gba_playtime_decode_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg [23:0] session_binary=0,total_binary=0;
    wire [27:0] session_bcd,total_bcd;
    gba_playtime_decode dut(.*);
    function automatic [27:0] reference_value(input integer d,h,m);
        reference_value={4'(d/100),4'((d/10)%10),4'(d%10),4'(h/10),4'(h%10),4'(m/10),4'(m%10)};
    endfunction
    integer count=0;
    initial begin
        for(integer d=0;d<512;d=d+1)
            for(integer h=0;h<24;h=h+1)
                for(integer m=0;m<60;m=m+1)begin
                    @(negedge clk);
                    session_binary={4'd0,9'(d),5'(h),6'(m)};
                    total_binary={4'd0,9'(511-d),5'(23-h),6'(59-m)};
                    @(posedge clk);#1;
                    if(session_bcd!==reference_value(d,h,m) || total_bcd!==reference_value(511-d,23-h,59-m))
                        $fatal(1,"Decimal ROM data/channel/latency mismatch d=%0d h=%0d m=%0d",d,h,m);
                    count=count+1;
                end
        $display("PASS: %0d paired duration ROM conversions, every day/hour/minute, exact one-clock latency",count);$finish;
    end
endmodule
