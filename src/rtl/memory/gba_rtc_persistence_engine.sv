// Guest-clock owner of persistence operations. Command data stays frozen until
// acknowledgement; reply data stays frozen until the next snapshot command.
module gba_rtc_persistence_engine #(parameter integer CLOCK_HZ=39936000)(
    input wire clk,host_event,
    input wire [31:0] host_epoch,
    input wire [55:0] live_calendar,
    input wire [7:0] live_control,
    input wire live_valid,
    input wire request_toggle,
    input wire [1:0] operation,
    input wire [97:0] payload,
    output reg acknowledge=0,
    output reg [97:0] reply=0,
    output reg apply=0,
    output wire [55:0] restored_calendar,
    output wire [7:0] restored_control,
    output wire restored_valid,
    output wire seed,adjust,advance_day,busy,
    output wire [1:0] adjust_field,
    output wire [7:0] adjust_value
);
    localparam integer FRACTION_BITS=$clog2(CLOCK_HZ);
    reg [31:0] epoch=0;
    reg [FRACTION_BITS-1:0] fraction=0;
    reg epoch_valid=0;
    always @(posedge clk)begin
        if(host_event)begin epoch<=host_epoch;fraction<=0;epoch_valid<=1;end
        else if(epoch_valid)begin
            if(fraction==CLOCK_HZ-1)begin
                fraction<=0;if(epoch!=32'hffffffff)epoch<=epoch+1'b1;
            end else fraction<=fraction+1'b1;
        end
    end
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] request_sync=0;
    reg seen=0;
    reg [1:0] state=0;
    reg rebase_start=0;
    reg [31:0] elapsed=0;
    // The extra subtraction bit also gives the unsigned borrow. Share this
    // carry chain with the elapsed result instead of a separate comparator.
    (* keep="true" *) wire [32:0] epoch_difference={1'b0,epoch}-{1'b0,payload[95:64]};
    wire rebase_busy,rebase_done,rebase_valid;
    wire [55:0] rebased_calendar;
    assign busy=state!=0;
    gba_rtc_elapsed_rebase #(.IN_PLACE(1)) rebase(.clk,.reset(1'b0),.start(rebase_start),
        .saved_calendar(payload[55:0]),.elapsed_seconds(elapsed),
        .live_calendar,.seed,.adjust,.advance_day,.adjust_field,.adjust_value,
        .busy(rebase_busy),.done(rebase_done),.valid(rebase_valid),.calendar(rebased_calendar));
    assign restored_calendar=payload[96] ? live_calendar : 56'h00000000010100;
    assign restored_control=payload[63:56] & 8'h6a;
    assign restored_valid=payload[96] && rebase_valid;
    always @(posedge clk)begin
        request_sync<={request_sync[1:0],request_toggle===1'b1};
        rebase_start<=0;apply<=0;
        case(state)
            0:if(request_sync[2]!=seen)begin
                seen<=request_sync[2];
                if(operation==2)begin
                    reply<={epoch_valid,live_valid,epoch,live_control,live_calendar};
                    acknowledge<=request_sync[2];
                end else if(payload[96])begin
                    elapsed<=payload[97] && epoch_valid && !epoch_difference[32] ? epoch_difference[31:0] : 32'd0;
                    rebase_start<=1;state<=1;
                end else begin apply<=1;state<=2;end
            end
            1:if(rebase_done)begin apply<=1;state<=2;end
            // Calendar/control owners consume apply on this edge. Only then
            // release the host, including when the rebase rejected the date.
            2:begin acknowledge<=seen;state<=0;end
            default:state<=0;
        endcase
    end
endmodule
