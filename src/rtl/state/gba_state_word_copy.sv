// One word buffer, reused for capture and restore. Both endpoints use the
// ready/response protocol of the existing guest RAM and staged SDRAM ports.
// Descriptor selection, image CRC/schema validation and CDC belong upstream.
module gba_state_word_copy #(
    parameter integer STAGING_BYTES=1048576,
    parameter integer TIMEOUT_CYCLES=7425000,
    parameter integer GUEST_ADDRESS_BITS=32
)(
    input wire clk,reset,start,restore,cancel,
    input wire held,staging_locked,image_validated,
    input wire [31:0] guest_base,staging_offset,word_count,
    output wire busy,
    output reg done,partial_restore,
    output reg [2:0] error_code,
    output wire guest_valid,guest_write,guest_response_ready,
    output wire [31:0] guest_addr,guest_wdata,
    input wire guest_ready,guest_response,guest_error,
    input wire [31:0] guest_rdata,
    output wire staging_valid,staging_write,staging_response_ready,
    output wire [31:0] staging_addr,staging_wdata,
    input wire staging_ready,staging_response,staging_error,
    input wire [31:0] staging_rdata
);
    localparam IDLE=0,READ_ISSUE=1,READ_WAIT=2,WRITE_ISSUE=3,WRITE_WAIT=4;
    localparam OFFSET_BITS=$clog2(STAGING_BYTES),COUNT_BITS=$clog2(STAGING_BYTES/4+1);
    localparam TIMEOUT_BITS=TIMEOUT_CYCLES>1 ? $clog2(TIMEOUT_CYCLES) : 1;
    reg [2:0] phase;
    reg direction,aborting;
    reg [GUEST_ADDRESS_BITS-1:0] guest_position;
    reg [31:0] word_buffer;
    reg [OFFSET_BITS-1:0] staging_position;
    reg [COUNT_BITS-1:0] remaining;
    reg [TIMEOUT_BITS-1:0] elapsed;
    wire [32:0] bytes_requested={1'b0,word_count}<<2;
    // Prove count before shifting so overflow cannot turn a large copy small.
    wire descriptor_ok=word_count>0 && word_count<=STAGING_BYTES/4 &&
        guest_base[1:0]==0 && staging_offset[1:0]==0 &&
        {1'b0,guest_base}+bytes_requested<=(33'd1<<GUEST_ADDRESS_BITS) &&
        {1'b0,staging_offset}+bytes_requested<=STAGING_BYTES;
    wire prerequisites=held && staging_locked && (!direction || image_validated);
    wire fault=cancel || !prerequisites || aborting;
    assign busy=phase!=IDLE;
    assign guest_addr=guest_position;
    assign staging_addr=staging_position;
    assign guest_wdata=word_buffer;
    assign staging_wdata=word_buffer;
    assign guest_write=direction;
    assign staging_write=!direction;
    assign guest_valid=!fault && ((!direction && phase==READ_ISSUE) || (direction && phase==WRITE_ISSUE));
    assign staging_valid=!fault && ((direction && phase==READ_ISSUE) || (!direction && phase==WRITE_ISSUE));
    assign guest_response_ready=(!direction && phase==READ_WAIT) || (direction && phase==WRITE_WAIT);
    assign staging_response_ready=(direction && phase==READ_WAIT) || (!direction && phase==WRITE_WAIT);
    wire source_ready=direction ? staging_ready : guest_ready;
    wire source_response=direction ? staging_response : guest_response;
    wire source_error=direction ? staging_error : guest_error;
    wire [31:0] source_data=direction ? staging_rdata : guest_rdata;
    wire sink_ready=direction ? guest_ready : staging_ready;
    wire sink_response=direction ? guest_response : staging_response;
    wire sink_error=direction ? guest_error : staging_error;
    // Delay only the watchdog's progress descriptor, not either transaction.
    // The old direct clear routed virtual address -> response selection into
    // every timer bit. Reload at one on the next clock: after that edge the
    // elapsed value is exactly the original value. Suppress the stale sample
    // on that one edge (except the original immediate one-cycle timeout).
    reg timer_progress;
    always @(posedge clk)begin
        if(reset || phase==IDLE)begin timer_progress<=0;elapsed<=0;end
        else begin
            timer_progress<=(phase==READ_ISSUE && source_ready) ||
                            (phase==READ_WAIT && source_response) ||
                            (phase==WRITE_ISSUE && sink_ready) ||
                            (phase==WRITE_WAIT && sink_response);
            if(timer_progress)elapsed<=TIMEOUT_CYCLES>1 ? 1 : 0;
            else if(elapsed!=TIMEOUT_CYCLES-1)elapsed<=elapsed+1'b1;
        end
    end
    task finish(input [2:0] code);
        begin phase<=IDLE;done<=1;error_code<=code;if(code==0)partial_restore<=0;end
    endtask
    initial if(STAGING_BYTES<4 || STAGING_BYTES%4!=0 || TIMEOUT_CYCLES<1 || GUEST_ADDRESS_BITS<1 || GUEST_ADDRESS_BITS>32)
        $error("Invalid state copy bounds");
    always @(posedge clk)begin
        done<=0;
        if(reset)begin
            phase<=IDLE;direction<=0;aborting<=0;error_code<=0;done<=0;partial_restore<=0;
            guest_position<=0;staging_position<=0;remaining<=0;word_buffer<=0;
        end else if(phase==IDLE)begin
            if(start)begin
                error_code<=0;partial_restore<=0;aborting<=0;
                direction<=restore;guest_position<=guest_base;staging_position<=staging_offset;remaining<=word_count;
                if(!descriptor_ok)finish(1);
                else if(!held || !staging_locked || (restore && !image_validated))finish(2);
                else phase<=READ_ISSUE;
            end
        end else begin
            if(cancel || !prerequisites)begin aborting<=1;if(error_code==0)error_code<=3;end
            if(elapsed==TIMEOUT_CYCLES-1 && (!timer_progress || TIMEOUT_CYCLES==1))begin
                aborting<=1;if(error_code==0)error_code<=4;
            end
            case(phase)
                READ_ISSUE:if(fault)finish(error_code==0 ? 3'd3 : error_code);
                    else if(source_ready)begin phase<=READ_WAIT;end
                READ_WAIT:if(source_response)begin
                    if(source_error)finish(5);
                    else if(fault)finish(error_code==0 ? 3'd3 : error_code);
                    else begin word_buffer<=source_data;phase<=WRITE_ISSUE;end
                end
                WRITE_ISSUE:if(fault)finish(error_code==0 ? 3'd3 : error_code);
                    else if(sink_ready)begin
                        phase<=WRITE_WAIT;
                        if(direction)partial_restore<=1;
                    end
                WRITE_WAIT:if(sink_response)begin
                    if(sink_error)finish(5);
                    else if(fault)finish(error_code==0 ? 3'd3 : error_code);
                    else if(remaining==1)finish(0);
                    else begin
                        guest_position<=guest_position+4;staging_position<=staging_position+4;
                        remaining<=remaining-1'b1;phase<=READ_ISSUE;
                    end
                end
                default:finish(5);
            endcase
            // A timed-out accepted transaction must still drain. Do not invent
            // an acknowledgement or resume a partially restored guest. busy
            // remains asserted until the real reply arrives (or explicit reset).
        end
    end
endmodule
