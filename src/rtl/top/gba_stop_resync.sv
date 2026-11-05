// Native STOP wake alignment: keep host scanout running while guest clocks pause.
// The guest position must remain frozen while cpu_pause is asserted. The
// source holds its captured descriptor until the full request/ack roundtrip.
module gba_stop_resync (
    input wire cpu_clk,video_clk,reset,raw_stop,
    input wire [16:0] guest_position,host_position,
    output wire cpu_pause,
    output reg video_blank
);
    localparam IDLE=0,WAIT_PAUSED=1,WAIT_WAKE=2,WAIT_RUNNING=3;
    reg [1:0] state;
    reg request;
    reg [16:0] frozen_position;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] ack_sync,request_sync;
    assign cpu_pause=raw_stop || state!=IDLE;
    always @(posedge cpu_clk) begin
        if(reset) begin state<=IDLE;request<=0;frozen_position<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[1:0],video_blank};
            case(state)
                IDLE: if(raw_stop) begin
                    frozen_position<=guest_position;request<=1;state<=WAIT_PAUSED;
                end
                WAIT_PAUSED: if(ack_sync[2]) begin
                    if(raw_stop) state<=WAIT_WAKE;
                    else begin request<=0;state<=WAIT_RUNNING;end
                end
                WAIT_WAKE: if(!raw_stop) begin request<=0;state<=WAIT_RUNNING;end
                WAIT_RUNNING: if(!ack_sync[2]) state<=IDLE;
            endcase
        end
    end
    always @(posedge video_clk) begin
        if(reset) begin request_sync<=0;video_blank<=0;end
        else begin
            request_sync<={request_sync[1:0],request};
            if(request_sync[2]) video_blank<=1;
            else if(video_blank && host_position==frozen_position) video_blank<=0;
        end
    end
endmodule

