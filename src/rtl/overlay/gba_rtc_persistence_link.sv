// Host-side command ownership. Boot waits only for initialization/import, never
// during ordinary gameplay. Missing host time gets a bounded 100 ms grace
// after the framework releases reset; ROM loading/Prerun can take seconds.
module gba_rtc_persistence_link #(parameter integer CLOCK_HZ=74250000)(
    input wire clk,new_game,load_rtc,running,
`ifdef GBK_SAVESTATE
    input wire state_lock,state_start,state_restore,state_word_write,
    input wire [1:0] state_word_index,
    input wire [31:0] state_word_data,
    output wire state_ready,state_busy,
    output reg state_done=0,
    output reg state_error=0,
    output wire [31:0] state_word_rdata,
`endif
    input wire [31:0] loaded_word,
    output reg load_word_read=0,
    output reg [1:0] load_word_index=0,
    input wire host_valid,
    input wire [31:0] host_date,host_time,host_epoch,
    input wire export_request,allcomplete,
    input wire acknowledge,
    input wire [97:0] reply,
    output reg request_toggle=0,
    output reg [1:0] operation=0,
    output reg [97:0] payload=0,
    output reg snapshot_ready=0,
    output wire [97:0] snapshot,
    output reg boot_ready=1
);
    localparam integer WAIT_CYCLES=CLOCK_HZ/10>0 ? CLOCK_HZ/10 : 1;
    localparam integer WAIT_BITS=$clog2(WAIT_CYCLES+1);
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] ack_sync=0;
    reg inflight=0,stale=0,clear_pending=0,load_pending=0;
    reg snapshot_pending=0,request_seen=0,discard_snapshot=0;
    reg [1:0] load_fetch=0;
    reg [WAIT_BITS-1:0] wait_count=0;
`ifdef GBK_SAVESTATE
    reg state_owned=0,state_inflight=0;
    reg [3:0] state_words=0;
    wire state_lock_active=state_lock===1'b1;
    assign state_ready=state_owned && !inflight && !clear_pending && !load_pending && !new_game && !load_rtc;
    assign state_busy=state_inflight;
    assign state_word_rdata=state_word_index==3 ? {30'd0,reply[97:96]} :
        state_word_index==2 ? reply[95:64] : state_word_index==1 ? reply[63:32] : reply[31:0];
`endif
    wire time_ready=host_valid===1'b1 || wait_count==WAIT_CYCLES;
    // Record read-data is the receiving register: reads follow the three-stage
    // acknowledgement. No further snapshot is issued while export is locked.
    assign snapshot=reply;
    always @(posedge clk)begin
        ack_sync<={ack_sync[1:0],acknowledge};
        request_seen<=export_request;
        load_word_read<=0;
`ifdef GBK_SAVESTATE
        state_done<=0;
        if(!state_owned && state_lock_active && boot_ready && !inflight && !clear_pending && !load_pending &&
            !snapshot_pending && !snapshot_ready && !new_game && !load_rtc && !export_request)begin
            state_owned<=1;state_words<=0;state_error<=0;
        end
        if(!state_lock_active && !state_inflight)state_owned<=0;
        if(state_word_write===1'b1)begin
            if(!state_ready || (state_word_index==3 && state_word_data[31:2]!=0))state_error<=1;
            else begin
                case(state_word_index)
                    0:payload[31:0]<=state_word_data;
                    1:payload[63:32]<=state_word_data;
                    2:payload[95:64]<=state_word_data;
                    3:payload[97:96]<=state_word_data[1:0];
                endcase
                state_words[state_word_index]<=1;
            end
        end
`endif
        if((clear_pending || load_pending) && running && !time_ready)wait_count<=wait_count+1'b1;
        if(inflight)begin
            if(ack_sync[2]==request_toggle)begin
                inflight<=0;
`ifdef GBK_SAVESTATE
                if(state_inflight)begin
                    state_inflight<=0;state_done<=1;state_error<=state_error || stale || new_game || load_rtc;
                end else
`endif
                if(!stale && !new_game)begin
                    if(operation==2)begin
                        if(!discard_snapshot && !allcomplete)snapshot_ready<=1;
                    end else if(!load_pending && !load_rtc)boot_ready<=1;
                end
            end
        end else if(!new_game)begin
            if(clear_pending && time_ready)begin
                payload<={host_valid===1'b1,host_valid===1'b1,host_epoch,8'h40,
                    host_time[7:0],host_time[15:8],host_time[23:16],5'd0,host_time[26:24],
                    host_date[7:0],host_date[15:8],host_date[23:16]};
                operation<=0;request_toggle<=~request_toggle;inflight<=1;stale<=0;clear_pending<=0;
            end else if(!clear_pending && load_pending && time_ready)begin
                case(load_fetch)
                    0:begin load_word_index<=0;load_word_read<=1;load_fetch<=1;end
                    1:load_fetch<=2;
                    default:begin
                        case(load_word_index)
                            0:payload[31:0]<=loaded_word;
                            1:payload[63:32]<=loaded_word;
                            2:payload[95:64]<=loaded_word;
                            3:payload[97:96]<=loaded_word[1:0];
                        endcase
                        if(load_word_index==3)begin
                            operation<=1;request_toggle<=~request_toggle;inflight<=1;stale<=0;load_pending<=0;load_fetch<=0;
                        end else begin load_word_index<=load_word_index+1'b1;load_word_read<=1;load_fetch<=1;end
                    end
                endcase
`ifdef GBK_SAVESTATE
            end else if(state_start===1'b1 && state_ready)begin
                state_words<=0;
                if(state_restore && state_words!=4'hf)begin state_done<=1;state_error<=1;end
                else begin
                    operation<=state_restore ? 2'd1 : 2'd2;request_toggle<=~request_toggle;
                    inflight<=1;stale<=0;state_inflight<=1;state_error<=0;
                end
`endif
            end else if(!clear_pending && !load_pending && snapshot_pending && boot_ready
`ifdef GBK_SAVESTATE
                && !state_owned
`endif
            )begin
                operation<=2;request_toggle<=~request_toggle;inflight<=1;stale<=0;
                snapshot_pending<=0;discard_snapshot<=0;
            end
        end
        if(export_request && !request_seen)begin snapshot_pending<=1;snapshot_ready<=0;end
        if(allcomplete)begin
            snapshot_pending<=0;snapshot_ready<=0;
            if(inflight && operation==2)discard_snapshot<=1;
        end
        if(load_rtc)begin load_pending<=1;boot_ready<=0;end
        if(new_game)begin
`ifdef GBK_SAVESTATE
            state_owned<=0;state_words<=0;
            if(state_owned || state_inflight)state_error<=1;
`endif
            clear_pending<=1;load_pending<=0;snapshot_pending<=0;
            snapshot_ready<=0;boot_ready<=0;wait_count<=0;stale<=1;
            load_fetch<=0;load_word_read<=0;
        end
    end
endmodule
