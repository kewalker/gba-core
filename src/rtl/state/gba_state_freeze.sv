// Pause coordinator for a future whole-machine serializer. This is not a clock
// gate: host commands, SDRAM refresh, RTC wall time and host scanout stay live.
// CPU remains held until every guest domain acknowledges release AND display/
// cache preparation completes. An in-flight freeze cannot be withdrawn before
// its acknowledgements: otherwise a late clock domain could freeze AFTER resume.
module gba_state_freeze #(
    parameter integer DOMAINS=2,
    parameter integer TIMEOUT_CYCLES=7425000
)(
    input wire clk,reset,start,finish,cancel,
    input wire cpu_quiescent,transactions_drained,resume_ready,
    input wire [DOMAINS-1:0] domain_frozen,
    output wire cpu_hold,drain_request,freeze_request,frozen,busy,
    output wire prepare_required,
    output reg done,
    output reg [2:0] error_code
);
    localparam IDLE=0,DRAIN=1,FREEZE=2,HELD=3,RELEASE=4;
    reg [2:0] phase;
    localparam TIMEOUT_BITS=TIMEOUT_CYCLES>1 ? $clog2(TIMEOUT_CYCLES) : 1;
    reg [TIMEOUT_BITS-1:0] elapsed;
    reg abort_freeze;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
        reg [DOMAINS-1:0] ack1,ack2,ack3;
    assign busy=phase!=IDLE;
    assign cpu_hold=busy;
    assign drain_request=busy;
    assign freeze_request=phase==FREEZE || phase==HELD;
    assign frozen=phase==HELD && (&ack3) && cpu_quiescent && transactions_drained;
    assign prepare_required=|ack3;
    initial if(DOMAINS<1 || TIMEOUT_CYCLES<1)$error("Invalid state freeze configuration");
    always @(posedge clk)begin
        if(reset)begin ack1<=0;ack2<=0;ack3<=0;end
        else begin ack1<=domain_frozen;ack2<=ack1;ack3<=ack2;end
    end
    always @(posedge clk)begin
        done<=0;
        if(reset)begin phase<=IDLE;elapsed<=0;error_code<=0;done<=0;abort_freeze<=0;end
        else case(phase)
            IDLE:if(start)begin phase<=DRAIN;elapsed<=0;error_code<=0;abort_freeze<=0;end
            DRAIN:begin
                if(cancel)begin error_code<=1;phase<=RELEASE;elapsed<=0;end
                else if(cpu_quiescent && transactions_drained && ack3==0)begin
                    phase<=FREEZE;elapsed<=0;
                end else if(elapsed==TIMEOUT_CYCLES-1)begin
                    error_code<=2;phase<=RELEASE;elapsed<=0;
                end else elapsed<=elapsed+1'b1;
            end
            FREEZE:begin
                if(cancel)begin error_code<=1;abort_freeze<=1;end
                if(!cpu_quiescent || !transactions_drained)begin error_code<=4;abort_freeze<=1;end
                if(&ack3)begin
                    if(abort_freeze || cancel || !cpu_quiescent || !transactions_drained)phase<=RELEASE;
                    else phase<=HELD;
                    elapsed<=0;
                end else if(elapsed==TIMEOUT_CYCLES-1)begin
                    if(error_code==0)error_code<=3;
                    abort_freeze<=1;
                end else elapsed<=elapsed+1'b1;
            end
            HELD:begin
                if(!cpu_quiescent || !transactions_drained || !(&ack3))begin
                    error_code<=4;phase<=RELEASE;elapsed<=0;
                end else if(finish || cancel)begin
                    error_code<=cancel ? 3'd1 : 3'd0;phase<=RELEASE;elapsed<=0;
                end
            end
            RELEASE:begin
                if(ack3==0 && resume_ready)begin phase<=IDLE;done<=1;elapsed<=0;end
                else if(elapsed==TIMEOUT_CYCLES-1)begin
                    // No unsafe forced resume. Remain held, keep commands live,
                    // and report the release fault until reset or a real ack.
                    if(error_code==0)error_code<=5;
                end else elapsed<=elapsed+1'b1;
            end
            default:begin error_code<=4;phase<=RELEASE;elapsed<=0;end
        endcase
    end
endmodule

// One instance per guest clock domain. frozen acknowledges the REQUEST protocol;
// execution_hold parks guest state until the coordinator grants resume. Clearing
// frozen alone must not advance peripherals while the CPU is still waiting for
// release acknowledgements/cache warm-up. CPU/DMA prepare uses prepare_hold;
// native peripherals use execution_hold, so they can drain during preparation.
module gba_state_freeze_domain(
    input wire clk,reset,request,idle,hold_request,
    output reg frozen,
    output wire execution_hold,prepare_hold
);
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] request_sync;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] hold_sync;
    reg parked;
    assign execution_hold=parked;
    assign prepare_hold=hold_sync[2] || parked;
    always @(posedge clk)begin
        if(reset)begin request_sync<=0;hold_sync<=0;frozen<=0;parked<=0;end
        else begin
            request_sync<={request_sync[1:0],request};
            hold_sync<={hold_sync[1:0],hold_request};
            if(!request_sync[2])frozen<=0;
            else if(idle)begin frozen<=1;parked<=1;end
            if(!request_sync[2] && !hold_sync[2])parked<=0;
        end
    end
endmodule
