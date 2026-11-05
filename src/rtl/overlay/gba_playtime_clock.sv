// Wall time is independent of cartridge RTC writes and guest execution.
// Session/total time counts enabled host clocks, including ordinary HALT idle,
// but excluding the Pocket menu, guest STOP and time outside the running game.
module gba_playtime_clock #(parameter integer CLOCK_HZ=74250000)(
    input wire clk,new_game,playing,
    input wire host_toggle,host_valid,
    input wire [31:0] host_time_bcd,
    input wire load_total,
    input wire [31:0] loaded_total,
    output reg wall_valid=0,
    output reg [23:0] wall_time_bcd=0,
    output reg [31:0] session_seconds=0,
    output reg [31:0] total_seconds=0
);
    localparam integer COUNTER_BITS=$clog2(CLOCK_HZ);
    reg [COUNTER_BITS-1:0] wall_phase=0,play_phase=0;
    reg host_seen=0;
    function automatic [7:0] bcd_next(input [7:0] value);
        bcd_next=value[3:0]==9 ? value+7 : value+1'b1;
    endfunction
    wire host_ok=host_time_bcd[23:16]<=8'h23 && host_time_bcd[19:16]<10 &&
        host_time_bcd[15:8]<=8'h59 && host_time_bcd[11:8]<10 &&
        host_time_bcd[7:0]<=8'h59 && host_time_bcd[3:0]<10;
    always @(posedge clk)begin
        if(host_toggle!=host_seen)begin
            host_seen<=host_toggle;
            if(host_valid && host_ok)begin wall_time_bcd<=host_time_bcd[23:0];wall_phase<=0;wall_valid<=1;end
        end else if(wall_valid)begin
            if(wall_phase==CLOCK_HZ-1)begin
                wall_phase<=0;
                if(wall_time_bcd[7:0]!=8'h59)wall_time_bcd[7:0]<=bcd_next(wall_time_bcd[7:0]);
                else begin
                    wall_time_bcd[7:0]<=0;
                    if(wall_time_bcd[15:8]!=8'h59)wall_time_bcd[15:8]<=bcd_next(wall_time_bcd[15:8]);
                    else begin
                        wall_time_bcd[15:8]<=0;
                        wall_time_bcd[23:16]<=wall_time_bcd[23:16]==8'h23 ? 8'd0 : bcd_next(wall_time_bcd[23:16]);
                    end
                end
            end else wall_phase<=wall_phase+1'b1;
        end
        if(new_game)begin session_seconds<=0;total_seconds<=0;play_phase<=0;end
        else begin
            if(load_total)total_seconds<=loaded_total;
            if(playing)begin
                if(play_phase==CLOCK_HZ-1)begin
                    play_phase<=0;
                    if(session_seconds!=32'hffffffff)session_seconds<=session_seconds+1'b1;
                    if(!load_total && total_seconds!=32'hffffffff)total_seconds<=total_seconds+1'b1;
                end else play_phase<=play_phase+1'b1;
            end
        end
    end
endmodule

// Per-game sidecar. Version 1 is 32 bytes; version 2 adds a normalized
// calendar, control register and host epoch anchor (48 bytes total).
module gba_playtime_record #(parameter RTC_PERSISTENCE=0)(
    input wire clk,new_game,playing,
    input wire [127:0] game_id,
    input wire [31:0] total_seconds,
    input wire load_write,
    input wire [(RTC_PERSISTENCE?4:3)-1:0] load_index,
    input wire [31:0] load_data,
    input wire export_request,allcomplete,read_strobe,
    input wire [(RTC_PERSISTENCE?4:3)-1:0] read_index,
    input wire endian_little,
    input wire snapshot_ready,
    input wire [97:0] rtc_snapshot,
    input wire identity_write,identity_ready,
    input wire [1:0] identity_index,
    input wire [31:0] identity_data,
    input wire load_word_read,
    input wire [1:0] load_word_index,
    output wire [31:0] loaded_word,
    output reg load_rtc=0,
    output wire [97:0] loaded_rtc,
    output wire export_busy,
    output reg export_locked=0,
    output reg load_total=0,
    output reg [31:0] loaded_total=0,
    output reg [31:0] read_data=0,
    output reg import_valid=0
);
    localparam [31:0] MAGIC=32'h54504247,VERSION=RTC_PERSISTENCE?2:1;
    reg import_closed=0,import_ok=0,import_v2=0;
    reg [3:0] expected_index=0;
    reg [31:0] import_xor=0;
    reg calendar_ok=0,calendar_present=0;
    reg identity_compare=0;
    reg [31:0] identity_expected=0,bank_read=0;
    // The guest reply bank is held until the next snapshot command. The host
    // link forbids a new snapshot while this export is locked, so a duplicate
    // 98-bit receiving bank is unnecessary. Read strobes follow ack settling.
    wire [97:0] frozen_rtc=rtc_snapshot;
    assign loaded_rtc=0;
    assign loaded_word=bank_read;
    reg [127:0] frozen_id=0;
    reg [31:0] frozen_total=0;
    reg capture_busy=0;
    reg [3:0] capture_index=0;
    reg [31:0] capture_total=0;
    // Import and export are mutually exclusive, so their checksum accumulator
    // has one owner at a time and does not need two 32-bit register banks.
    wire [31:0] capture_xor=import_xor;
    // Separate 1W/1R banks give Quartus an explicit block-memory shape.
    // Metadata 0..3 holds imported RTC; 4..7 holds the current ROM identity.
    (* ramstyle="M10K" *) reg [31:0] export_words[0:15];
    (* ramstyle="M10K" *) reg [31:0] metadata_words[0:7];
    assign export_busy=RTC_PERSISTENCE && capture_busy;
    wire [3:0] word_index=RTC_PERSISTENCE ? capture_index : {1'b0,read_index};
    wire import_write=load_write && !playing && !import_closed && !import_valid &&
        (!RTC_PERSISTENCE || (!capture_busy && !export_locked));
    wire metadata_write=identity_write || (import_write && import_v2 && load_index>=7 && load_index<=10);
    wire [2:0] metadata_write_index=identity_write ? {1'b1,identity_index} : 3'(load_index-7);
    wire [31:0] metadata_write_data=identity_write ? identity_data : load_data;
    wire capture_identity=capture_busy && capture_index>=1 && capture_index<=4;
    wire compare_identity=import_write && load_index>=2 && load_index<=5;
    wire metadata_read=load_word_read || capture_identity || compare_identity;
    wire [2:0] metadata_read_index=load_word_read ? {1'b0,load_word_index} :
        capture_identity ? 3'(capture_index+3) : 3'(load_index+2);
    wire [31:0] checksum=MAGIC^VERSION^frozen_id[31:0]^frozen_id[63:32]^frozen_id[95:64]^frozen_id[127:96]^frozen_total^
        (RTC_PERSISTENCE ? frozen_rtc[31:0]^frozen_rtc[63:32]^frozen_rtc[95:64]^{30'd0,frozen_rtc[97:96]} : 32'd0);
    function automatic good_bcd(input [7:0] b,input [7:0] maximum);
        good_bcd=b[3:0]<10 && b[7:4]<10 && b<=maximum;
    endfunction
    wire [7:0] yy=load_data[7:0],mm=load_data[15:8],dd=load_data[23:16];
    wire leap=((yy[1:0]+{yy[4],1'b0}) & 2'b11)==0;
    wire [7:0] last_day=mm==2 ? (leap?8'h29:8'h28) :
        (mm==4 || mm==6 || mm==9 || mm==8'h11) ? 8'h30 : 8'h31;
    wire date_ok=good_bcd(yy,8'h99) && good_bcd(mm,8'h12) && mm!=0 &&
        good_bcd(dd,last_day) && dd!=0 && load_data[31:24]<=6;
    wire time_ok=good_bcd(load_data[7:0],8'h23) && good_bcd(load_data[15:8],8'h59) && good_bcd(load_data[23:16],8'h59);
    reg [31:0] word_data;
    wire [31:0] next_checksum=import_xor^(RTC_PERSISTENCE && capture_busy ? word_data : load_data);
    always @*begin
        case(word_index)
            0:word_data=MAGIC;1:word_data=VERSION;
            2:word_data=RTC_PERSISTENCE ? bank_read : frozen_id[31:0];
            3:word_data=RTC_PERSISTENCE ? bank_read : frozen_id[63:32];
            4:word_data=RTC_PERSISTENCE ? bank_read : frozen_id[95:64];
            5:word_data=RTC_PERSISTENCE ? bank_read : frozen_id[127:96];
            6:word_data=RTC_PERSISTENCE ? capture_total : frozen_total;
            7:word_data=RTC_PERSISTENCE ? frozen_rtc[31:0] : checksum;
            8:word_data=frozen_rtc[63:32];9:word_data=frozen_rtc[95:64];
            10:word_data={30'd0,frozen_rtc[97:96]};default:word_data=RTC_PERSISTENCE ? capture_xor : checksum;
        endcase
    end
    always @(posedge clk)begin
        load_total<=0;load_rtc<=0;identity_compare<=0;
        if(!RTC_PERSISTENCE)begin
        if(allcomplete || new_game)export_locked<=0;
        else if(export_request && !export_locked)begin
            frozen_id<=game_id;frozen_total<=total_seconds;export_locked<=1;
        end
        if(read_strobe)read_data<=endian_little ? word_data : {word_data[7:0],word_data[15:8],word_data[23:16],word_data[31:24]};
        end else begin
            if(allcomplete || new_game)begin export_locked<=0;capture_busy<=0;end
            else if(capture_busy)begin
                import_xor<=next_checksum;capture_index<=capture_index+1'b1;
                if(capture_index==11)begin capture_busy<=0;export_locked<=1;end
            end else if(export_request && !export_locked && snapshot_ready)begin
                capture_total<=total_seconds;import_xor<=0;capture_index<=0;capture_busy<=1;
            end
        end
        if(new_game)begin
            import_closed<=0;import_valid<=0;expected_index<=0;import_ok<=0;import_xor<=0;loaded_total<=0;import_v2<=0;
            calendar_ok<=0;calendar_present<=0;
        end else begin
            if(playing)import_closed<=1;
            if(import_write)begin
                if(load_index==0)begin expected_index<=1;import_ok<=load_data==MAGIC && (!RTC_PERSISTENCE || identity_ready);import_xor<=load_data;end
                else if(load_index==expected_index)begin
                    expected_index<=expected_index+1'b1;import_xor<=next_checksum;
                    case(load_index)
                        1:begin import_ok<=import_ok && (load_data==1 || (RTC_PERSISTENCE && load_data==2));import_v2<=load_data==2;end
                        2,3,4,5:if(!RTC_PERSISTENCE)import_ok<=import_ok && load_data==game_id[(load_index-2)*32+:32];
                            else begin identity_compare<=1;identity_expected<=load_data;end
                        6:loaded_total<=load_data;
                        7:if(!import_v2)begin
                            if(import_ok && load_data==import_xor)begin
                                load_total<=1;import_valid<=1;
                            end
                        end else calendar_ok<=date_ok;
                        8:begin calendar_ok<=calendar_ok && time_ok;import_ok<=import_ok && (load_data[31:24]&8'h95)==0;end
                        10:begin calendar_present<=load_data[0];import_ok<=import_ok && load_data[31:2]==0 && (!load_data[0] || calendar_ok);end
                        11:if(import_v2 && import_ok && load_data==import_xor)begin
                            load_total<=1;import_valid<=1;load_rtc<=calendar_present;
                        end
                        default:begin end
                    endcase
                end else begin import_ok<=0;expected_index<=0;end
            end
            if(RTC_PERSISTENCE && identity_compare && bank_read!==identity_expected && !(import_write && load_index==0))import_ok<=0;
        end
    end
    // A single synchronous block-memory bank freezes the complete v2 file.
    // Populate one word per clock, then acknowledge; APF reads retain the
    // same one-strobe response latency as the legacy endpoint.
    generate if(RTC_PERSISTENCE)begin: file_bank
        always @(posedge clk)begin
            if(capture_busy)export_words[capture_index]<=endian_little ? word_data :
                {word_data[7:0],word_data[15:8],word_data[23:16],word_data[31:24]};
            if(read_strobe)read_data<=export_words[read_index];
            if(metadata_write)metadata_words[metadata_write_index]<=metadata_write_data;
            if(metadata_read)bank_read<=metadata_words[metadata_read_index];
        end
    end endgenerate
endmodule
