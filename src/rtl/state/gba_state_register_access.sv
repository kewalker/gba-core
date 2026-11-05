// Guest-clock endpoint behind the single asynchronous command port. Flat image
// indices map to the existing shared register bus; no peripheral is duplicated.
// A read waits for native synchronous storage to settle. Writes commit on one
// valid edge, and the response remains held through cancellation/reset.
module gba_state_register_access #(
    parameter integer TIMEOUT_CYCLES=7425000
)(
    input wire clk,cancel,held,
    input wire request_valid,request_write,response_ready,
    input wire [31:0] request_addr,request_wdata,
    output wire request_ready,response_valid,
    output reg response_error=0,
    output reg [31:0] response_rdata=0,
    output reg [15:0] register_addr=0,
    output reg [31:0] register_wdata=0,
    output wire register_write,
    input wire register_valid,
    input wire [31:0] register_rdata
);
    localparam IDLE=0,ACCESS=1,RESPONSE=2;
    localparam WAIT_BITS=TIMEOUT_CYCLES>1 ? $clog2(TIMEOUT_CYCLES) : 1;
    reg [1:0] phase=IDLE;
    reg writing=0;
    reg [WAIT_BITS-1:0] elapsed=0;
    function automatic [15:0] address_of(input [7:0] index);
        reg [7:0] group_address,index_base;
        begin
            group_address=0;index_base=0;
            if(index<45)begin group_address=0;index_base=0;end
            else if(index<52)begin group_address=1;index_base=45;end
            else if(index<86)begin group_address=2;index_base=52;end
            else if(index<95)begin group_address=3;index_base=86;end
            else if(index<97)begin group_address=4;index_base=95;end
            else if(index<101)begin group_address=5;index_base=97;end
            else if(index<127)begin group_address=6;index_base=101;end
            else if(index<147)begin group_address=7;index_base=127;end
            else if(index<175)begin group_address=7;index_base=115;end
            else if(index<185)begin group_address=8;index_base=175;end
            else if(index==185)begin group_address=9;index_base=185;end
            else if(index<190)begin group_address=9;index_base=170;end
            else begin group_address=10;index_base=190;end
            // One narrow subtraction serves every group; do not infer a
            // separate 16-bit address adder for each mutually exclusive case.
            address_of=index<194 ? {group_address,8'(index-index_base)} : 16'h073f;
        end
    endfunction
    wire address_ok=request_addr<194 || (request_addr==255 && !request_write);
    assign request_ready=phase==IDLE;
    assign response_valid=phase==RESPONSE;
    assign register_write=phase==ACCESS && writing && held && !cancel && register_valid;
    initial if(TIMEOUT_CYCLES<1)$error("Invalid register access timeout");
    always @(posedge clk)case(phase)
        IDLE:if(request_valid && request_ready)begin
            register_addr<=address_of(request_addr[7:0]);register_wdata<=request_wdata;
            writing<=request_write;elapsed<=0;response_error<=0;response_rdata<=0;
            if(cancel || !held || !address_ok)begin response_error<=1;phase<=RESPONSE;end
            else phase<=ACCESS;
        end
        ACCESS:if(cancel || !held)begin response_error<=1;phase<=RESPONSE;end
            else if(register_valid)begin response_rdata<=register_rdata;phase<=RESPONSE;end
            else if(elapsed==TIMEOUT_CYCLES-1)begin response_error<=1;phase<=RESPONSE;end
            else elapsed<=elapsed+1'b1;
        RESPONSE:if(response_ready)phase<=IDLE;
        default:phase<=IDLE;
    endcase
endmodule
