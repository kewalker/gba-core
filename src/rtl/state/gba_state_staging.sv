// One outstanding word transaction into a bounded SDRAM staging pool.
// Lock acquisition/release drains the accepted owner's response. The host can
// never mutate bytes between validation and restore commit while lock is held.
// All signals use the SDRAM clock; APF buffering/CDC is a separate endpoint.
module gba_state_staging #(
    parameter [24:0] BASE_HALFWORD=25'h1200000,
    parameter integer POOL_BYTES=1048576
)(
    input wire clk,reset,lock_request,
    output reg locked,
    output wire idle,
    input wire host_valid,host_write,
    input wire [31:0] host_offset,host_wdata,
    output wire host_ready,host_response,
    input wire host_response_ready,
    output wire [31:0] host_rdata,
    output wire host_error,
    input wire core_valid,core_write,
    input wire [31:0] core_offset,core_wdata,
    output wire core_ready,core_response,
    input wire core_response_ready,
    output wire [31:0] core_rdata,
    output wire core_error,
    output wire memory_valid,memory_write,
    output wire [24:0] memory_addr,
    output wire [31:0] memory_wdata,
    output wire [3:0] memory_byteena,
    input wire memory_ready,memory_response,
    input wire [63:0] memory_rdata,
    output wire memory_response_ready
);
    localparam IDLE=0,ISSUE=1,WAIT_RESPONSE=2,REJECT=3,RESPONSE=4;
    reg [2:0] phase;
    reg owner_core,held_write;
    localparam OFFSET_BITS=$clog2(POOL_BYTES);
    reg [OFFSET_BITS-1:0] held_offset;
    reg [31:0] held_wdata,response_data;
    wire choose_core=locked && lock_request;
    wire selected_valid=choose_core ? core_valid : host_valid;
    wire [31:0] selected_offset=choose_core ? core_offset : host_offset;
    wire [31:0] selected_data=choose_core ? core_wdata : host_wdata;
    wire selected_write=choose_core ? core_write : host_write;
    wire aligned=selected_offset[1:0]==0 && selected_offset<POOL_BYTES;
    wire owner_ready=owner_core ? core_response_ready : host_response_ready;
    wire response=phase==RESPONSE || phase==REJECT;
    assign idle=phase==IDLE;
    assign host_ready=idle && !locked && !lock_request;
    assign core_ready=idle && locked && lock_request;
    assign host_response=response && !owner_core;
    assign core_response=response && owner_core;
    assign host_error=host_response && phase==REJECT;
    assign core_error=core_response && phase==REJECT;
    wire [31:0] selected_result=phase==REJECT ? 32'd0 : response_data;
    assign host_rdata=selected_result;
    assign core_rdata=selected_result;
    assign memory_valid=phase==ISSUE;
    assign memory_write=held_write;
    assign memory_addr=BASE_HALFWORD+25'(held_offset>>1);
    assign memory_wdata=held_wdata;
    assign memory_byteena=4'hf;
    assign memory_response_ready=phase==WAIT_RESPONSE;
    initial begin
        if(POOL_BYTES<4 || POOL_BYTES%8!=0 || BASE_HALFWORD[1:0]!=0 ||
           BASE_HALFWORD<25'h1020000 || {1'b0,BASE_HALFWORD}+POOL_BYTES/2>26'h2000000)
            $error("State staging pool overlaps ROM/EWRAM or exceeds SDRAM");
    end
    always @(posedge clk)begin
        if(reset)begin
            phase<=IDLE;locked<=0;owner_core<=0;
            held_offset<=0;held_wdata<=0;held_write<=0;response_data<=0;
        end else case(phase)
            IDLE:begin
                // No lock change may reassign an outstanding transaction.
                locked<=lock_request;
                if(selected_valid && (choose_core ? core_ready : host_ready))begin
                    owner_core<=choose_core;held_offset<=selected_offset;
                    held_wdata<=selected_data;held_write<=selected_write;
                    phase<=aligned ? ISSUE : REJECT;
                end
            end
            ISSUE:if(memory_ready)phase<=WAIT_RESPONSE;
            // Finish the physical response into one held reply word. Halfword
            // selection must not feed the validator's comparisons on the same
            // host edge. Ownership remains fixed until the caller consumes it.
            WAIT_RESPONSE:if(memory_response)begin
                response_data<=held_offset[2] ? memory_rdata[63:32] : memory_rdata[31:0];
                phase<=RESPONSE;
            end
            RESPONSE:if(owner_ready)phase<=IDLE;
            REJECT:if(owner_ready)phase<=IDLE;
            default:phase<=IDLE;
        endcase
    end
endmodule
