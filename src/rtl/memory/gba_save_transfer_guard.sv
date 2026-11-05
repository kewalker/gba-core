// A raw save-address strobe is not permission to access nonvolatile storage.
// Retain the APF grant after its request command ends, through the data phase.
module gba_save_transfer_guard (
    input wire clk, allcomplete,
    input wire request_write, write_ack,
    input wire [15:0] write_id,
    input wire request_read, read_ack,
    input wire [15:0] read_id,
    output wire write_allowed, read_allowed
);
    reg write_open=0, read_open=0;
    assign write_allowed=write_open;
    assign read_allowed=read_open;
    always @(posedge clk)begin
        if(allcomplete)begin write_open<=0;read_open<=0;end
        else if(request_write)begin
            write_open<=write_ack && write_id==16'd1;read_open<=0;
        end else if(request_read)begin
            read_open<=read_ack && read_id==16'd1;write_open<=0;
        end
    end
endmodule
