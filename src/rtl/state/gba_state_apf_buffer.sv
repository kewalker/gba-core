// APF returns the previous read's buffered word. A read strobe starts work
// AFTER that frame captures its response, leaving a complete SPI frame for
// SDRAM service. Host and staging share clk_74a; core-side CDC is upstream.
// Permissions belong to the state job controller, never startup readiness.
module gba_state_apf_buffer #(
    parameter [7:0] ADDRESS_PREFIX=8'h12,
    parameter integer POOL_BYTES=1048576,TIMEOUT_CYCLES=7425000
)(
    input wire clk,reset,clear_fault,allow_read,allow_write,endian_little,
    input wire bridge_rd,bridge_wr,
    input wire [31:0] bridge_addr,bridge_wdata,
    output reg [31:0] bridge_rdata,
    output wire busy,
    output reg fault,
    output wire host_valid,host_write,host_response_ready,
    output wire [31:0] host_offset,host_wdata,
    input wire host_ready,host_response,host_error,
    input wire [31:0] host_rdata
);
    localparam IDLE=0,ISSUE=1,WAIT_REPLY=2;
    localparam OFFSET_BITS=$clog2(POOL_BYTES),WAIT_BITS=TIMEOUT_CYCLES>1 ? $clog2(TIMEOUT_CYCLES) : 1;
    reg [1:0] phase;
    reg pending_write,pending_little;
    reg [OFFSET_BITS-1:0] pending_offset;
    reg [31:0] pending_data;
    reg [WAIT_BITS-1:0] elapsed;
    wire hit=bridge_addr[31:24]==ADDRESS_PREFIX;
    wire command=hit && (bridge_rd || bridge_wr);
    wire command_allowed=bridge_wr ? allow_write : allow_read;
    wire address_ok=bridge_addr[1:0]==0 && {8'd0,bridge_addr[23:0]}<POOL_BYTES;
    wire final_dummy=bridge_rd && !bridge_wr && bridge_addr[1:0]==0 &&
        {8'd0,bridge_addr[23:0]}==POOL_BYTES;
    function automatic [31:0] swap_bytes(input [31:0] data);
        swap_bytes={data[7:0],data[15:8],data[23:16],data[31:24]};
    endfunction
    assign busy=phase!=IDLE;
    // Permissions admit new APF frames. Once captured, a descriptor owns its
    // place in the drain, including while staging has not accepted it yet.
    assign host_valid=phase==ISSUE;
    assign host_write=pending_write;
    assign host_offset=pending_offset;
    assign host_wdata=pending_data;
    assign host_response_ready=phase==WAIT_REPLY;
    initial if(POOL_BYTES<4 || POOL_BYTES>16777216 || POOL_BYTES%4!=0 || TIMEOUT_CYCLES<1)
        $error("Invalid APF state buffer bounds");
    always @(posedge clk)begin
        if(reset)begin
            phase<=IDLE;pending_write<=0;pending_little<=0;pending_offset<=0;
            pending_data<=0;elapsed<=0;bridge_rdata<=0;fault<=0;
        end else begin
            if(clear_fault && phase==IDLE)begin fault<=0;bridge_rdata<=0;end
            // There is no APF ready pin. An overrun must fail the job, never
            // overwrite the descriptor of an already accepted transaction.
            if(command && phase!=IDLE)fault<=1;
            case(phase)
                IDLE:if(command)begin
                    // The last SPI frame retrieves the preceding word. At
                    // an exact-size pool boundary it may address one past end.
                    if(final_dummy && allow_read)bridge_rdata<=0;
                    else if(!address_ok || !command_allowed || (bridge_rd && bridge_wr))begin
                        fault<=1;if(bridge_rd)bridge_rdata<=0;
                    end else begin
                        pending_write<=bridge_wr;pending_little<=endian_little;
                        pending_offset<=bridge_addr[23:0];
                        pending_data<=endian_little ? bridge_wdata : swap_bytes(bridge_wdata);
                        elapsed<=0;phase<=ISSUE;
                    end
                end
                ISSUE:begin
                    if(host_ready)begin phase<=WAIT_REPLY;elapsed<=0;end
                    else if(elapsed==TIMEOUT_CYCLES-1)begin fault<=1;phase<=IDLE;end
                    else elapsed<=elapsed+1'b1;
                end
                WAIT_REPLY:begin
                    if(host_response)begin
                        if(host_error)fault<=1;
                        if(!pending_write)bridge_rdata<=host_error ? 32'd0 :
                            pending_little ? host_rdata : swap_bytes(host_rdata);
                        phase<=IDLE;elapsed<=0;
                    end else if(elapsed==TIMEOUT_CYCLES-1)begin
                        // Accepted operations still drain on a timeout. Busy
                        // stays set, preventing ownership changes or commit.
                        fault<=1;
                    end else elapsed<=elapsed+1'b1;
                end
                default:begin fault<=1;phase<=WAIT_REPLY;end
            endcase
        end
    end
endmodule
