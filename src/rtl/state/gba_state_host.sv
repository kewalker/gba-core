// Production APF command/transfer ownership, clocked by the direct host clock.
// The machine owns capture/validation/restore; this module admits one command,
// drains captured APF frames before starting it, and latches host-visible results.
module gba_state_host #(
    parameter integer IMAGE_BYTES=535528,
    parameter integer TIMEOUT_CYCLES=7425000
)(
    input wire clk,reset,enabled,identity_ready,owners_idle,
    input wire capture_request,load_request,
    output reg capture_ack,load_ack,
    output wire capture_busy,load_busy,
    output reg capture_ok,capture_error,load_ok,load_error,
    input wire lifecycle_request,
    output wire lifecycle_ready,
    output wire machine_start,machine_restore,machine_cancel,
    input wire machine_busy,machine_done,machine_failed_stopped,machine_release_done,
    input wire [3:0] machine_error,
    input wire endian_little,bridge_rd,bridge_wr,
    input wire [31:0] bridge_addr,bridge_wdata,
    output wire [31:0] bridge_rdata,
    output wire transport_busy,transport_fault,
    output wire host_valid,host_write,host_response_ready,
    output wire [31:0] host_offset,host_wdata,
    input wire host_ready,host_response,host_error,
    input wire [31:0] host_rdata
);
    localparam IDLE=0,DRAIN=1,START=2,ACTIVE=3,STOPPED=4,COMPLETE=5;
    reg [2:0] phase;
    reg direction,capture_seen,load_seen;
    reg clear_fault;
    reg completed_error;
    wire new_capture=capture_request && !capture_seen;
    wire new_load=load_request && !load_seen;
    wire new_request=new_capture || new_load;
    wire admit=enabled && phase==IDLE && !lifecycle_request;
    // A command and an APF frame may arrive on the same edge. The frame is
    // captured under the old admission grant; DRAIN observes its registered busy
    // before starting the job. Never lock staging on that command edge.
    gba_state_apf_buffer #(.POOL_BYTES(IMAGE_BYTES),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) buffer(
        .clk,.reset,.clear_fault,.allow_read(admit),.allow_write(admit),.endian_little,
        .bridge_rd,.bridge_wr,.bridge_addr,.bridge_wdata,.bridge_rdata,
        .busy(transport_busy),.fault(transport_fault),
        .host_valid,.host_write,.host_response_ready,.host_offset,.host_wdata,
        .host_ready,.host_response,.host_error,.host_rdata);
    assign capture_busy=(phase!=IDLE && !direction);
    assign load_busy=(phase!=IDLE && direction);
    assign machine_start=phase==START && !lifecycle_request;
    assign machine_restore=direction;
    assign machine_cancel=lifecycle_request && machine_busy && !machine_failed_stopped;
    // A failed-stopped job has already drained accepted work. Reset is the only
    // recovery allowed; it must never be mistaken for successful completion.
    assign lifecycle_ready=!transport_busy &&
        ((phase==IDLE && !machine_busy) || (phase==STOPPED && machine_failed_stopped));
    task fail_result;
        begin
            if(direction)begin load_ok<=0;load_error<=1;end
            else begin capture_ok<=0;capture_error<=1;end
        end
    endtask
    always @(posedge clk)begin
        if(reset)begin
            phase<=IDLE;direction<=0;capture_seen<=0;load_seen<=0;
            capture_ack<=0;load_ack<=0;capture_ok<=0;capture_error<=0;
            load_ok<=0;load_error<=0;clear_fault<=0;completed_error<=0;
        end else begin
            capture_ack<=0;load_ack<=0;clear_fault<=0;
            if(!capture_request)capture_seen<=0;
            if(!load_request)load_seen<=0;
            if(new_capture)begin capture_ack<=1;capture_seen<=1;end
            if(new_load)begin load_ack<=1;load_seen<=1;end
            if(phase!=IDLE)begin
                if(new_capture && direction)begin capture_ok<=0;capture_error<=1;end
                if(new_load && !direction)begin load_ok<=0;load_error<=1;end
            end
            // A conflicting request is acknowledged with the active busy result;
            // it cannot replace its descriptor or clear its eventual result.
            if(new_request && phase==IDLE)begin
                if(!enabled || !identity_ready || lifecycle_request || (new_capture && new_load))begin
                    if(new_capture)begin capture_ok<=0;capture_error<=1;end
                    if(new_load)begin load_ok<=0;load_error<=1;end
                end else begin
                    direction<=new_load;phase<=DRAIN;
                    if(new_load)begin load_ok<=0;load_error<=0;end
                    else begin capture_ok<=0;capture_error<=0;end
                end
            end
            case(phase)
                IDLE:;
                DRAIN:if(!transport_busy && (owners_idle || lifecycle_request))begin
                    if(lifecycle_request || transport_fault)begin
                        fail_result();phase<=IDLE;clear_fault<=1;
                    end else phase<=START;
                end
                START:begin
                    if(lifecycle_request)begin fail_result();phase<=IDLE;end
                    else phase<=ACTIVE;
                end
                ACTIVE:begin
                    if(machine_failed_stopped)begin fail_result();phase<=STOPPED;end
                    else if(!machine_busy && machine_done)begin
                        completed_error<=machine_error!=0 || lifecycle_request || transport_fault;
                        phase<=COMPLETE;
                    end
                end
                // The machine drains and releases architectural state first.
                // Do not report completion until scanout has removed blanking
                // and its release acknowledgement has crossed to this clock.
                COMPLETE:if(machine_release_done)begin
                    if(completed_error || lifecycle_request || transport_fault)fail_result();
                    else if(direction)load_ok<=1;
                    else capture_ok<=1;
                    phase<=IDLE;clear_fault<=1;
                end
                STOPPED:;
                default:begin fail_result();phase<=STOPPED;end
            endcase
        end
    end
endmodule
