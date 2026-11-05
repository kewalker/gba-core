// Restore preparation without stopping or resetting Pocket scanout. Guest
// position is a bundled descriptor: state_hold parks it before prepare rises,
// and it remains parked until ready has crossed back to the host coordinator.
module gba_state_video(
    input wire host_clk,video_clk,render_clk,reset,
    input wire state_hold,prepare,
    input wire [16:0] guest_position,host_position,
    output wire ready,release_done,
    output wire video_invalidate,render_invalidate,
    output reg blank
);
    localparam IDLE=0,HELD=1,WARM=2,ALIGN=3,GRANT=4,RELEASED=5;
    reg [2:0] phase;
    reg [16:0] target;
    reg origin_seen,at_origin;
    reg grant;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
        reg [2:0] hold_sync,prepare_sync,render_sync,invalidated_sync,ready_sync,parked_sync,released_sync;
    assign video_invalidate=phase==HELD;
    assign render_invalidate=render_sync[2];
    // A freeze that times out before any guest domain parks needs no display
    // preparation. Once parked, or as soon as prepare is requested, only the
    // acknowledged preparation grant can release it.
    assign ready=ready_sync[2] || (!prepare && !parked_sync[2]);
    assign release_done=released_sync[2];
    always @(posedge render_clk)begin
        if(reset)render_sync<=0;
        else render_sync<={render_sync[1:0],video_invalidate};
    end
    always @(posedge host_clk)begin
        if(reset)begin ready_sync<=0;parked_sync<=0;released_sync<=0;end
        else begin
            ready_sync<={ready_sync[1:0],grant};parked_sync<={parked_sync[1:0],state_hold};
            released_sync<={released_sync[1:0],!blank};
        end
    end
    always @(posedge video_clk)begin
        if(reset)begin
            hold_sync<=0;prepare_sync<=0;invalidated_sync<=0;
            phase<=IDLE;target<=0;origin_seen<=0;at_origin<=0;grant<=0;blank<=0;
        end else begin
            hold_sync<={hold_sync[1:0],state_hold};
            prepare_sync<={prepare_sync[1:0],prepare};
            invalidated_sync<={invalidated_sync[1:0],render_invalidate};
            at_origin<=host_position==0;
            case(phase)
                IDLE:if(hold_sync[2])begin phase<=HELD;blank<=1;grant<=0;end
                HELD:if(prepare_sync[2] && invalidated_sync[2])begin
                    target<=guest_position;origin_seen<=0;phase<=WARM;
                end
                WARM:if(!invalidated_sync[2] && host_position==0 && !at_origin)begin
                    if(origin_seen)phase<=ALIGN;
                    else origin_seen<=1;
                end
                ALIGN:if(host_position==target)begin grant<=1;phase<=GRANT;end
                GRANT:if(!hold_sync[2])begin blank<=0;phase<=RELEASED;end
                RELEASED:if(!prepare_sync[2])begin grant<=0;phase<=IDLE;end
                default:begin grant<=0;blank<=1;phase<=HELD;end
            endcase
        end
    end
endmodule
