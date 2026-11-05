// Bounded snapshots transferred by a held-data toggle mailbox. Logging never
// feeds back into CPU ready, clock enables, or reset. Host core resets restart
// the sampling budget without tearing down an in-flight command packet.
module gba_runtime_log #(
    parameter integer PERIOD_CYCLES = 12288000,
    parameter integer MAX_SNAPSHOTS = 24,
    parameter integer MAX_TRIGGERED = 8,
    parameter integer CAPTURE_EVENTS = 1,
    parameter integer DIAGNOSTIC_SAMPLES = 0,
    parameter bit EXTRA_SAMPLES=0,
    parameter [15:0] EXTRA_KIND=16'h4753,
    parameter [15:0] DIAGNOSTIC_KIND=16'h4745,
    parameter [15:0] SNAPSHOT_KIND = 16'h4742
) (
    input wire sample_clk, bridge_clk, reset, core_running,
    input wire capture_now,
    input wire capture_restart,
    input wire [351:0] restart_snapshot,
    input wire [351:0] snapshot,
    input wire [351:0] diagnostic_snapshot,
    input wire [351:0] extra_snapshot,
    output wire event_valid,
    output wire [31:0] event_data,
    input wire event_ready
);
    reg [351:0] held;
    reg [351:0] pending_snapshot;
    reg pending_capture, held_triggered;
    reg [15:0] held_kind, pending_kind;
    reg [15:0] triggered_count;
    reg request_toggle, ack_toggle;
    (* ASYNC_REG = "TRUE" *) reg ack_sync1, ack_sync2;
    (* ASYNC_REG = "TRUE" *) reg request_sync1, request_sync2;
    reg [31:0] timer;
    reg [15:0] count, sequence_id, held_sequence;
    reg [1:0] sample_phase;
    wire [383:0] held_packet={held,held_kind,held_sequence};
    reg [3:0] word_index;
    reg active;
    assign event_valid = active;
    // Mailbox contents remain held until the final word is acknowledged.
    // Select the current word instead of keeping a second 384-bit copy.
    assign event_data = held_packet[word_index*32 +:32];
    always @(posedge sample_clk or posedge reset) begin
        if (reset) begin
            held <= 0; request_toggle <= 0; ack_sync1 <= 0; ack_sync2 <= 0;
            timer <= PERIOD_CYCLES-1; count <= 0; sequence_id <= 0; held_sequence <= 0;sample_phase<=0;
            pending_snapshot <= 0; pending_capture <= 0; held_triggered <= 0;
            triggered_count <= 0;
            held_kind <= SNAPSHOT_KIND; pending_kind <= SNAPSHOT_KIND;
        end else begin
            ack_sync1 <= ack_toggle; ack_sync2 <= ack_sync1;
            if (!core_running) begin
                timer <= PERIOD_CYCLES-1; count <= 0;sample_phase<=0;
                pending_capture <= 0; triggered_count <= 0;
            end else begin
                if (count < MAX_SNAPSHOTS && timer != 0) timer <= timer-1'b1;
                // Save the transition's state immediately, even if the host
                // is busy with a preceding packet. A later transition replaces
                // an unsent pending one; the most recent reset is retained.
                if (CAPTURE_EVENTS && capture_restart === 1'b1) begin
                    if(request_toggle == ack_sync2) begin
                        held <= restart_snapshot; held_kind <= 16'h4744;
                        held_sequence <= sequence_id; sequence_id <= sequence_id+1'b1;
                        request_toggle <= ~request_toggle; pending_capture <= 0;
                    end else begin
                        pending_snapshot <= restart_snapshot; pending_kind <= 16'h4744; pending_capture <= 1;
                    end
                end else if (CAPTURE_EVENTS && capture_now && triggered_count < MAX_TRIGGERED &&
                             !(pending_capture && pending_kind == 16'h4744)) begin
                    triggered_count <= triggered_count+1'b1;
                    if (request_toggle == ack_sync2) begin
                        held <= snapshot; held_triggered <= 1;
                        held_kind <= SNAPSHOT_KIND == 16'h4742 ? 16'h4743 : SNAPSHOT_KIND;
                        held_sequence <= sequence_id; sequence_id <= sequence_id+1'b1;
                        request_toggle <= ~request_toggle; pending_capture <= 0;
                    end else begin
                        pending_snapshot <= snapshot; pending_capture <= 1;
                        pending_kind <= SNAPSHOT_KIND == 16'h4742 ? 16'h4743 : SNAPSHOT_KIND;
                    end
                end else if (pending_capture && request_toggle == ack_sync2) begin
                    held <= pending_snapshot; held_triggered <= 1;
                    held_kind <= pending_kind;
                    held_sequence <= sequence_id; sequence_id <= sequence_id+1'b1;
                    request_toggle <= ~request_toggle; pending_capture <= 0;
                end else if (!pending_capture && count < MAX_SNAPSHOTS && timer == 0 &&
                             request_toggle == ack_sync2) begin
                    held <= EXTRA_SAMPLES && sample_phase==2 ? extra_snapshot :
                        DIAGNOSTIC_SAMPLES && (EXTRA_SAMPLES ? sample_phase==1 : count[0]) ? diagnostic_snapshot : snapshot;
                    held_sequence <= sequence_id;
                    held_triggered <= 0;
                    held_kind <= EXTRA_SAMPLES && sample_phase==2 ? EXTRA_KIND :
                        DIAGNOSTIC_SAMPLES && (EXTRA_SAMPLES ? sample_phase==1 : count[0]) ? DIAGNOSTIC_KIND : SNAPSHOT_KIND;
                    sample_phase<=sample_phase==2 ? 0 : sample_phase+1'b1;
                    sequence_id <= sequence_id+1'b1;
                    request_toggle <= ~request_toggle;
                    count <= count+1'b1; timer <= PERIOD_CYCLES-1;
                end
            end
        end
    end
    always @(posedge bridge_clk or posedge reset) begin
        if (reset) begin
            request_sync1 <= 0; request_sync2 <= 0; ack_toggle <= 0;
            active <= 0; word_index <= 0;
        end else begin
            request_sync1 <= request_toggle; request_sync2 <= request_sync1;
            if (!active && request_sync2 != ack_toggle) begin
                word_index <= 0; active <= 1;
            end else if (active && event_ready) begin
                if (word_index == 11) begin
                    active <= 0; ack_toggle <= request_sync2;
                end else word_index <= word_index+1'b1;
            end
        end
    end
endmodule
