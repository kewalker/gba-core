// Exclusive state transactions reuse the ordinary CPU-side memory-map port.
// No shadow memory or extra physical RAM ports. The whole-machine coordinator
// must freeze all guest writers first; held is an acknowledgement, not a request.
module gba_state_memory_access(
    input wire clk,reset,held,
    input wire state_valid,state_write,
    input wire [31:0] state_addr,state_wdata,
    output wire state_ready,state_response,state_error,busy,
    output wire [31:0] state_rdata,
    input wire state_response_ready,
    input wire cpu_req,cpu_write,
    input wire [1:0] cpu_size,
    input wire [31:0] cpu_addr,cpu_wdata,
    output wire cpu_ready,
    output wire [31:0] cpu_rdata,
    output wire memory_req,memory_write,
    output wire [1:0] memory_size,
    output wire [31:0] memory_addr,memory_wdata,
    input wire memory_ready,
    input wire [31:0] memory_rdata
);
    localparam IDLE=0,ACCESS=1,REPLY=2;
    reg [1:0] phase;
    reg accepted_write,error;
    reg [31:0] accepted_addr,accepted_wdata,result;
    // Exact physical RAM spans only. Exclude mirrors, MMIO, ROM and battery
    // command interfaces; those require their own raw/protocol state endpoints.
    wire allowed=state_addr[1:0]==0 && (
        (state_addr>=32'h02000000 && state_addr<32'h02040000) ||
        (state_addr>=32'h03000000 && state_addr<32'h03008000) ||
        (state_addr>=32'h05000000 && state_addr<32'h05000400) ||
        (state_addr>=32'h06000000 && state_addr<32'h06018000) ||
        (state_addr>=32'h07000000 && state_addr<32'h07000400));
    assign busy=phase!=IDLE;
    // A state command cannot steal an already presented CPU request. An
    // invalid/not-held request is rejected without ever reaching the bus.
    assign state_ready=phase==IDLE && !cpu_req;
    assign state_response=phase==REPLY;
    assign state_error=state_response && error;
    assign state_rdata=state_response && !error ? result : 32'd0;
    assign memory_req=phase==ACCESS || (phase==IDLE && !held && cpu_req);
    assign memory_write=phase==ACCESS ? accepted_write : cpu_write;
    assign memory_addr=phase==ACCESS ? accepted_addr : cpu_addr;
    assign memory_wdata=phase==ACCESS ? accepted_wdata : cpu_wdata;
    assign memory_size=phase==ACCESS ? 2'd2 : cpu_size;
    assign cpu_ready=phase==IDLE && !held && memory_ready;
    assign cpu_rdata=memory_rdata;
    always @(posedge clk)begin
        if(reset)begin phase<=IDLE;accepted_write<=0;accepted_addr<=0;accepted_wdata<=0;result<=0;error<=0;end
        else case(phase)
            IDLE:if(state_valid && state_ready)begin
                error<=!held || !allowed;result<=0;
                if(!held || !allowed)phase<=REPLY;
                else begin
                    accepted_write<=state_write;accepted_addr<=state_addr;accepted_wdata<=state_wdata;phase<=ACCESS;
                end
            end
            ACCESS:if(memory_ready)begin result<=memory_rdata;phase<=REPLY;end
            REPLY:if(state_response_ready)phase<=IDLE;
            default:begin phase<=REPLY;error<=1;end
        endcase
    end
endmodule
