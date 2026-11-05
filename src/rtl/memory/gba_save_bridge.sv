// APF nonvolatile export. Keep the Flash image locked through all-complete,
// including Reset Enter during shutdown. No game state is reset by this lock.
module gba_save_bridge #(parameter bit DEFER_READ=0) (
    input wire clk, request_read, allcomplete, bridge_rd,
    input wire [15:0] request_id,
    output wire request_ack,
    output reg export_lock = 0,
    input wire export_locked,
    input wire [31:0] bridge_addr, save_rdata,
    input wire endian_little,
    input wire save_rvalid,
    output wire [31:0] bridge_rdata
);
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] locked_sync = 0;
    always @(posedge clk) begin
        locked_sync <= {locked_sync[1:0],export_locked};
        if(allcomplete) export_lock <= 0;
        // Complete the return-to-zero handshake before another export. A
        // delayed acknowledgement from the previous transfer cannot authorize
        // reading a new image after the CPU has briefly resumed writing.
        if(request_read && request_id == 16'd1 &&
           (export_lock || !locked_sync[2])) export_lock <= 1;
    end
    // APF assigns request_id and asserts request_read on the same edge.
    // Gate ACK with the request so a stale previous slot ID cannot let the
    // command handler complete before the Flash lock has even been requested.
    assign request_ack = request_read && (request_id != 16'd1 ||
                         (export_lock && locked_sync[2]));
    wire [31:0] current_data = bridge_addr[23:17] != 0 ? 32'hffffffff :
        (endian_little ? save_rdata :
         {save_rdata[7:0],save_rdata[15:8],save_rdata[23:16],save_rdata[31:24]});
    // APF reads are buffered by one word: the next SPI transaction returns
    // the result of this read strobe. Holding a live RAM/address response here
    // lets the next address replace it before the framework samples the word,
    // shifting every exported save four bytes to the left on each shutdown.
    reg [31:0] read_data = 0;
    reg read_pending=0, pending_little=0;
    always @(posedge clk) begin
        if(bridge_rd && bridge_addr[31:24] == 8'h0e) begin
            if(!DEFER_READ || bridge_addr[23:17]!=0) read_data<=current_data;
            else begin read_pending<=1; pending_little<=endian_little; end
        end
        if(DEFER_READ && read_pending && save_rvalid) begin
            read_data<=pending_little ? save_rdata :
                {save_rdata[7:0],save_rdata[15:8],save_rdata[23:16],save_rdata[31:24]};
            read_pending<=0;
        end
    end
    assign bridge_rdata = read_data;
endmodule
