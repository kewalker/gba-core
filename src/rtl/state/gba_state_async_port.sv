// One shared host -> guest command port. Bundled descriptor/response data stay
// fixed through a three-flop toggle handshake; data use two settling stages.
// cancel does not reset handshake epochs or drop accepted writes: source work
// drains to a response, and the caller retains freeze/ownership until then.
// Configuration initial values initialise both domains. Guest/loader resets
// are cancellation inputs, never independent resets of handshake toggles.
module gba_state_async_port #(
    parameter integer ADDRESS_BITS=32,
    parameter integer TARGET_BITS=1
)(
    input wire source_clk,source_cancel,
    input wire source_valid,source_write,source_response_ready,
    input wire [TARGET_BITS-1:0] source_target,
    input wire [ADDRESS_BITS-1:0] source_addr,
    input wire [31:0] source_wdata,
    output wire source_ready,source_response,source_busy,
    output reg source_error=0,
    output reg [31:0] source_rdata=0,
    input wire destination_clk,destination_cancel,
    output wire destination_valid,destination_write,destination_response_ready,
    output wire [TARGET_BITS-1:0] destination_target,
    output wire [ADDRESS_BITS-1:0] destination_addr,
    output wire [31:0] destination_wdata,
    input wire destination_ready,destination_response,destination_error,
    input wire [31:0] destination_rdata
);
    localparam PAYLOAD_BITS=TARGET_BITS+ADDRESS_BITS+33;
    localparam IDLE=0,WAIT_REPLY=1,REPLY=2;
    reg [1:0] source_phase=IDLE,destination_phase=IDLE;
    reg request_toggle=0,acknowledge=0,seen=0;
    reg source_aborting=0,destination_aborting=0;
    reg [PAYLOAD_BITS-1:0] held_request=0,active_request=0;
    reg [32:0] held_response=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] request_sync=0,ack_sync=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [PAYLOAD_BITS-1:0] request_data1=0,request_data2=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [32:0] response_data1=0,response_data2=0;
    assign source_ready=source_phase==IDLE && !source_cancel;
    assign source_busy=source_phase!=IDLE;
    assign source_response=source_phase==REPLY;
    assign {destination_target,destination_write,destination_addr,destination_wdata}=active_request;
    assign destination_valid=destination_phase==REPLY && !destination_cancel;
    assign destination_response_ready=destination_phase==WAIT_REPLY;
    always @(posedge source_clk)begin
        ack_sync<={ack_sync[1:0],acknowledge};
        response_data1<=held_response;response_data2<=response_data1;
        case(source_phase)
            IDLE:if(source_valid && source_ready)begin
                held_request<={source_target,source_write,source_addr,source_wdata};
                request_toggle<=!request_toggle;source_aborting<=0;source_phase<=WAIT_REPLY;
            end
            WAIT_REPLY:begin
                if(source_cancel)source_aborting<=1;
                if(ack_sync[2]==request_toggle)begin
                    source_rdata<=response_data2[31:0];
                    source_error<=response_data2[32] || source_aborting || source_cancel;
                    source_phase<=REPLY;
                end
            end
            REPLY:if(source_response_ready)source_phase<=IDLE;
            default:source_phase<=IDLE;
        endcase
    end
    always @(posedge destination_clk)begin
        request_sync<={request_sync[1:0],request_toggle};
        request_data1<=held_request;request_data2<=request_data1;
        case(destination_phase)
            IDLE:if(request_sync[2]!=seen)begin
                seen<=request_sync[2];active_request<=request_data2;destination_aborting<=0;
                if(destination_cancel)begin held_response<={1'b1,32'd0};acknowledge<=request_sync[2];end
                else destination_phase<=REPLY; // Issue one request, retain it until accepted.
            end
            REPLY:if(destination_cancel)begin
                held_response<={1'b1,32'd0};acknowledge<=seen;destination_phase<=IDLE;
            end else if(destination_ready)destination_phase<=WAIT_REPLY;
            WAIT_REPLY:begin
                if(destination_cancel)destination_aborting<=1;
                if(destination_response)begin
                    held_response<={destination_error || destination_aborting || destination_cancel,destination_rdata};
                    acknowledge<=seen;destination_phase<=IDLE;
                end
            end
            default:destination_phase<=IDLE;
        endcase
    end
endmodule
