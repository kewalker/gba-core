// Host-domain counters, settings and a separate per-game stats slot. The
// cartridge header identity is title[96] + game code[32], captured at load.
module gba_playtime_host #(parameter integer CLOCK_HZ=74250000, parameter RTC_PERSISTENCE=0)(
    input wire clk,video_clk,video_reset,running,in_menu,guest_stopped,
`ifdef GBK_SAVESTATE
    input wire state_rtc_lock,state_rtc_start,state_rtc_restore,state_rtc_word_write,
    input wire [1:0] state_rtc_word_index,
    input wire [31:0] state_rtc_word_data,
    output wire state_rtc_ready,state_rtc_busy,state_rtc_done,state_rtc_error,
    output wire [31:0] state_rtc_word_rdata,
`endif
    input wire bridge_wr,bridge_rd,endian_little,
    input wire [31:0] bridge_addr,bridge_wr_data,
    input wire host_toggle,host_valid,
    input wire [31:0] host_time_bcd,host_date_bcd,host_epoch,
    input wire rtc_acknowledge,
    input wire [97:0] rtc_reply,
    output wire rtc_request,
    output wire [1:0] rtc_operation,
    output wire [97:0] rtc_payload,
    output wire rtc_boot_ready,
    input wire request_read,allcomplete,
    input wire [15:0] request_id,
    output wire stats_ack,
    output wire [31:0] bridge_rdata,
    output wire [2:0] video_show,
    output wire [2:0] video_corner,
    output wire video_wall_valid,
    output wire [15:0] video_wall,
    output wire [27:0] video_session,video_total
);
    wire cart_write=bridge_wr && bridge_addr[31:25]==7'b0000100;
    wire new_game=cart_write && bridge_addr==32'h08000000;
    wire [31:0] load_data=endian_little ? bridge_wr_data :
        {bridge_wr_data[7:0],bridge_wr_data[15:8],bridge_wr_data[23:16],bridge_wr_data[31:24]};
    // Interact scalars use network word order, unlike little-endian file data.
    wire [31:0] setting_data=endian_little ?
        {bridge_wr_data[7:0],bridge_wr_data[15:8],bridge_wr_data[23:16],bridge_wr_data[31:24]} : bridge_wr_data;
    reg [127:0] game_id=0;
    reg [3:0] header_seen=0;
    reg [2:0] show=0;
    reg [2:0] corner=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] stopped_sync=0;
    always @(posedge clk)begin
        stopped_sync<={stopped_sync[1:0],guest_stopped};
        if(new_game)begin game_id<=0;header_seen<=0;end
        if(cart_write && bridge_addr[24:4]==21'h00000a)begin
            game_id[bridge_addr[3:2]*32+:32]<=load_data;
            header_seen[bridge_addr[3:2]]<=1;
        end
        if(bridge_wr)begin
            case(bridge_addr)
                32'h10000000:show[0]<=setting_data[0];
                32'h10000004:show[1]<=setting_data[0];
                32'h10000008:show[2]<=setting_data[0];
                32'h1000000c:corner<=(setting_data<=32'd5) ? setting_data[2:0] : 3'd0;
                default:begin end
            endcase
        end
    end
    wire playing=running && rtc_boot_ready && !in_menu && !stopped_sync[2] && &header_seen;
    wire [31:0] session_seconds,total_seconds,loaded_total,stats_rdata;
    wire load_total,export_locked,wall_valid;
    wire [23:0] wall_time_bcd;
    gba_playtime_clock #(.CLOCK_HZ(CLOCK_HZ)) clock_counter(.clk,.new_game,.playing,
        .host_toggle,.host_valid,.host_time_bcd,.load_total,.loaded_total,
        .wall_valid,.wall_time_bcd,.session_seconds,.total_seconds);
    wire stats_address=RTC_PERSISTENCE ? bridge_addr>=32'h10000100 && bridge_addr<32'h10000130 : bridge_addr[31:5]==27'h0800008;
    wire load_rtc,snapshot_ready,export_busy;
    wire [97:0] loaded_rtc,rtc_snapshot;
    wire [31:0] loaded_word;
    wire load_word_read;
    wire [1:0] load_word_index;
    generate if(RTC_PERSISTENCE)begin: persistence
        gba_rtc_persistence_link #(.CLOCK_HZ(CLOCK_HZ)) link(.clk,.new_game,.load_rtc,.running,.loaded_word,.load_word_read,.load_word_index,
`ifdef GBK_SAVESTATE
            .state_lock(state_rtc_lock),.state_start(state_rtc_start),.state_restore(state_rtc_restore),.state_word_write(state_rtc_word_write),
            .state_word_index(state_rtc_word_index),.state_word_data(state_rtc_word_data),.state_word_rdata(state_rtc_word_rdata),
            .state_ready(state_rtc_ready),.state_busy(state_rtc_busy),.state_done(state_rtc_done),.state_error(state_rtc_error),
`endif
            .host_valid,.host_date(host_date_bcd),.host_time(host_time_bcd),.host_epoch,
            .export_request(request_read && request_id==3 && !export_locked && !export_busy),.allcomplete,
            .acknowledge(rtc_acknowledge),.reply(rtc_reply),.request_toggle(rtc_request),
            .operation(rtc_operation),.payload(rtc_payload),.snapshot_ready,.snapshot(rtc_snapshot),.boot_ready(rtc_boot_ready));
    end else begin
`ifdef GBK_SAVESTATE
        assign state_rtc_ready=0;assign state_rtc_busy=0;assign state_rtc_done=0;assign state_rtc_error=0;assign state_rtc_word_rdata=0;
`endif
        assign rtc_request=0;assign rtc_operation=0;assign rtc_payload=0;assign rtc_boot_ready=1;
        assign snapshot_ready=1;assign rtc_snapshot=0;
        assign load_word_read=0;assign load_word_index=0;
    end endgenerate
    gba_playtime_record #(.RTC_PERSISTENCE(RTC_PERSISTENCE)) stats(.clk,.new_game,.playing,.game_id,.total_seconds,
        .load_write(bridge_wr && stats_address),.load_index(bridge_addr[(RTC_PERSISTENCE?5:4):2]),.load_data,
        .export_request(request_read && request_id==3),.allcomplete,
        .read_strobe(bridge_rd && stats_address),.read_index(bridge_addr[(RTC_PERSISTENCE?5:4):2]),
        .snapshot_ready,.rtc_snapshot,.load_rtc,.loaded_rtc,.export_busy,
        .identity_write(cart_write && bridge_addr[24:4]==21'h00000a),.identity_ready(&header_seen),
        .identity_index(bridge_addr[3:2]),.identity_data(load_data),.load_word_read,.load_word_index,.loaded_word,
        .endian_little,.export_locked,.load_total,.loaded_total,.read_data(stats_rdata),.import_valid());
    assign stats_ack=request_read && request_id==3 && export_locked;
    reg [31:0] settings_rdata=0;
    always @(posedge clk)begin
        if(bridge_rd)begin
            case(bridge_addr)
                32'h10000000:settings_rdata<={31'd0,show[0]};
                32'h10000004:settings_rdata<={31'd0,show[1]};
                32'h10000008:settings_rdata<={31'd0,show[2]};
                32'h1000000c:settings_rdata<={29'd0,corner};
                default:settings_rdata<=0;
            endcase
        end
    end
    // Address mux remains stable until the following APF transaction, while
    // each selected endpoint retains the response from its read strobe.
    reg stats_selected=0;
    always @(posedge clk)if(bridge_rd)stats_selected<=stats_address;
    assign bridge_rdata=stats_selected ? stats_rdata : endian_little ?
        {settings_rdata[7:0],settings_rdata[15:8],settings_rdata[23:16],settings_rdata[31:24]} : settings_rdata;

    reg format_start=0;
    wire format_busy,format_done;
    reg [31:0] format_seconds=0;
    wire [23:0] formatted;
    gba_playtime_format formatter(.clk,.start(format_start),.seconds(format_seconds),
        .busy(format_busy),.done(format_done),.duration_binary(formatted));
    reg [2:0] format_state=0;
    reg [23:0] session_formatted=0;
    reg [70:0] held_bundle=0;
    reg publish_toggle=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] ack_sync=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] event_sync=0;
    reg video_ack=0;
    reg [70:0] received_bundle=0;
    reg [22:0] decoded_control=0;
    assign {video_show,video_corner,video_wall_valid,video_wall}=decoded_control;
    gba_playtime_decode digits(.clk(video_clk),.session_binary(received_bundle[47:24]),
        .total_binary(received_bundle[23:0]),.session_bcd(video_session),.total_bcd(video_total));
    // Align control/wall time with the synchronous decimal ROMs. VS then
    // snapshots one coherent descriptor; RGB/control pixel latency is unchanged.
    always @(posedge video_clk)decoded_control<=received_bundle[70:48];
    always @(posedge clk)begin
        ack_sync<={ack_sync[1:0],video_ack};
        format_start<=0;
        case(format_state)
            0:if(ack_sync[2]==publish_toggle && !format_busy)begin
                format_seconds<=session_seconds;format_start<=1;format_state<=1;
            end
            1:if(format_done)begin
                session_formatted<=formatted;format_seconds<=total_seconds;
                format_start<=1;format_state<=2;
            end
            2:if(format_done)begin
                held_bundle<={show,corner,wall_valid,wall_time_bcd[23:8],session_formatted,formatted};
                publish_toggle<=~publish_toggle;format_state<=0;
            end
            default:format_state<=0;
        endcase
    end
    always @(posedge video_clk)begin
        event_sync<={event_sync[1:0],publish_toggle};
        if(event_sync[2]!=video_ack)begin received_bundle<=held_bundle;video_ack<=event_sync[2];end
        // Do not reset the handshake on guest reset. Source ownership must
        // survive menu/reset events; the renderer itself resets separately.
    end
endmodule
