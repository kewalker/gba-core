// S-3511A-style cartridge GPIO/RTC. The calendar runs from the FPGA execution
// clock, independently of guest HALT, STOP and reset. Host time is a bundled
// event: the bridge holds its BCD words while a toggle crosses two flops.
module gba_cartridge_rtc #(parameter integer CLOCK_HZ=39936000, parameter RTC_PERSISTENCE=0)(
    input wire clk,reset,
`ifdef GBK_SAVESTATE
    input wire state_hold,state_write,
    input wire [1:0] state_addr,
    input wire [31:0] state_wdata,
    output wire state_valid,
    output reg [31:0] state_rdata,
`endif
    input wire host_toggle,host_valid,
    input wire [31:0] host_date_bcd,host_time_bcd,
    input wire [31:0] host_epoch,
    input wire persistence_request,
    input wire [1:0] persistence_operation,
    input wire [97:0] persistence_payload,
    output wire persistence_acknowledge,
    output wire [97:0] persistence_reply,
    input wire bus_write,
    input wire [31:0] addr,wdata,
    input wire [1:0] size,
    output wire [31:0] rdata,
    output reg read_enable=0,
    output reg irq=0
);
    localparam integer COUNTER_BITS=$clog2(CLOCK_HZ);
    reg [COUNTER_BITS-1:0] subsecond=0;
    reg [7:0] year=0,month=1,day=1,hour=0,minute=0,second=0;
    reg [2:0] weekday=6;
    reg clock_valid=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] host_sync=0;
    reg host_seen=0;
    reg host_event=0;
    reg calendar_write=0,calendar_date_write=0;
    reg [55:0] calendar_payload=0;
    function automatic [7:0] bcd_next(input [7:0] value);
        bcd_next=value[3:0]==9 ? value+7 : value+1'b1;
    endfunction
    function automatic [7:0] to_bcd(input integer value);
        to_bcd=((value/10)<<4)+(value%10);
    endfunction
    function automatic integer from_bcd(input [7:0] value);
        from_bcd=value[7:4]*10+value[3:0];
    endfunction
    function automatic valid_bcd(input [7:0] value,input integer low,high);
        valid_bcd=value[3:0]<10 && value[7:4]<10 && value>=to_bcd(low) && value<=to_bcd(high);
    endfunction
    function automatic [7:0] hour_to_12(input [7:0] value);
        hour_to_12=value<8'h12 ? value :
            (value[3:0]<2 ? value-8'h18 : value-8'h12) | 8'h80;
    endfunction
    function automatic [7:0] hour_to_24(input [7:0] value);
        reg [7:0] base;
        begin
            base=value & 8'h7f;
            if(base==8'h12)base=0;
            hour_to_24=!value[7] ? base : (base[3:0]>=8 ? base+8'h18 : base+8'h12);
        end
    endfunction
    wire leap=(((year[1:0]+{year[4],1'b0}) & 2'b11)==0);
    reg [7:0] last_day;
    always @* begin
        case(month)
            8'h02:last_day=leap ? 8'h29 : 8'h28;
            8'h04,8'h06,8'h09,8'h11:last_day=8'h30;
            default:last_day=8'h31;
        endcase
    end
    wire host_time_ok=valid_bcd(host_date_bcd[23:16],0,99) && valid_bcd(host_date_bcd[15:8],1,12) &&
        valid_bcd(host_date_bcd[7:0],1,31) && host_time_bcd[27:24]<=6 &&
        valid_bcd(host_time_bcd[23:16],0,23) && valid_bcd(host_time_bcd[15:8],0,59) && valid_bcd(host_time_bcd[7:0],0,59);
    reg [7:0] control=8'h40;
    reg minute_level_previous=0;
    wire minute_level=clock_valid && control[3] && second<8'h30;
    wire [7:0] payload_hour=calendar_date_write ? calendar_payload[39:32] : calendar_payload[7:0];
    wire [7:0] payload_minute=calendar_date_write ? calendar_payload[47:40] : calendar_payload[15:8];
    wire [7:0] payload_second=calendar_date_write ? calendar_payload[55:48] : calendar_payload[23:16];
    wire [7:0] normalized_hour=control[6] ? payload_hour : hour_to_24(payload_hour);
    wire payload_ok=valid_bcd(normalized_hour,0,23) && valid_bcd(payload_minute,0,59) && valid_bcd(payload_second & 8'h7f,0,59) &&
        (!calendar_date_write || (valid_bcd(calendar_payload[7:0],0,99) && valid_bcd(calendar_payload[15:8],1,12) &&
            valid_bcd(calendar_payload[23:16],1,31) && calendar_payload[31:24]<=6));
    wire restore;
    wire [55:0] restored_calendar;
    wire [7:0] restored_control;
    wire restored_valid;
    wire persistence_seed,persistence_adjust,persistence_day,persistence_busy;
    wire [1:0] persistence_field;
    wire [7:0] persistence_value;
    generate if(RTC_PERSISTENCE)begin: persistence
        gba_rtc_persistence_engine #(.CLOCK_HZ(CLOCK_HZ)) engine(.clk,.host_event,.host_epoch,
            .live_calendar({second,minute,hour,5'd0,weekday,day,month,year}),
            .live_control(control),.live_valid(clock_valid),.request_toggle(persistence_request),
            .operation(persistence_operation),.payload(persistence_payload),
            .acknowledge(persistence_acknowledge),.reply(persistence_reply),.apply(restore),
            .restored_calendar,.restored_control,.restored_valid,
            .seed(persistence_seed),.adjust(persistence_adjust),.advance_day(persistence_day),.busy(persistence_busy),
            .adjust_field(persistence_field),.adjust_value(persistence_value));
    end else begin
        assign restore=0;assign restored_calendar=0;assign restored_control=0;assign restored_valid=0;
        assign persistence_acknowledge=0;assign persistence_reply=0;
        assign persistence_seed=0;assign persistence_adjust=0;assign persistence_day=0;assign persistence_busy=0;
        assign persistence_field=0;assign persistence_value=0;
    end endgenerate
    always @(posedge clk)begin
        host_sync<={host_sync[0],host_toggle===1'b1};
        host_event<=0;
        if(host_sync[1]!=host_seen) begin
            host_seen<=host_sync[1];
            if(host_valid===1'b1 && host_time_ok)host_event<=1;
        end
    end
    always @(posedge clk) begin
        if(persistence_seed)begin
            {second,minute,hour,weekday,day,month,year}<=
                {persistence_payload[55:32],persistence_payload[26:24],persistence_payload[23:0]};
            subsecond<=0;clock_valid<=0;
        end else if(restore)begin
            {second,minute,hour,weekday,day,month,year}<=
                {restored_calendar[55:32],restored_calendar[26:24],restored_calendar[23:0]};
            subsecond<=0;clock_valid<=restored_valid;
        end else if(persistence_adjust)begin
            case(persistence_field)
                0:second<=persistence_value;
                1:minute<=persistence_value;
                default:hour<=persistence_value;
            endcase
        end else if(host_event && (!RTC_PERSISTENCE || (!clock_valid && !persistence_busy)))begin
                year<=host_date_bcd[23:16];month<=host_date_bcd[15:8];day<=host_date_bcd[7:0];
                weekday<=host_time_bcd[26:24];hour<=host_time_bcd[23:16];minute<=host_time_bcd[15:8];second<=host_time_bcd[7:0];
                subsecond<=0;clock_valid<=1;
        end else if(calendar_write && payload_ok)begin
            hour<=normalized_hour;minute<=payload_minute;second<=payload_second & 8'h7f;subsecond<=0;clock_valid<=1;
            if(calendar_date_write)begin
                year<=calendar_payload[7:0];month<=calendar_payload[15:8];day<=calendar_payload[23:16];weekday<=calendar_payload[26:24];
            end
        end else begin
            if(clock_valid && subsecond==CLOCK_HZ-1)begin
                subsecond<=0;
                if(second!=8'h59)second<=bcd_next(second);
                else begin
                    second<=0;
                    if(minute!=8'h59)minute<=bcd_next(minute);
                    else begin
                        minute<=0;
                        if(hour!=8'h23)hour<=bcd_next(hour);
                        else begin
                            hour<=0;
                        end
                    end
                end
            end else if(clock_valid)subsecond<=subsecond+1'b1;
            // The ordinary midnight increment also serves offline whole days.
            // Restore runs before guest execution and holds clock_valid low.
            if(persistence_day || (clock_valid && subsecond==CLOCK_HZ-1 && second==8'h59 && minute==8'h59 && hour==8'h23))begin
                weekday<=weekday==6 ? 3'd0 : weekday+1'b1;
                if(day!=last_day)day<=bcd_next(day);
                else begin
                    day<=1;
                    if(month!=8'h12)month<=bcd_next(month);
                    else begin month<=1;year<=year==8'h99 ? 8'd0 : bcd_next(year);end
                end
            end
        end
    end
    reg [3:0] data_latch=0,direction=0;
    reg [7:0] command_shift=0,command=0;
    reg [6:0] bits=0;
    reg command_active=0,sio_out=1;
    reg [55:0] shift_data=0;
`ifdef GBK_SAVESTATE
    wire state_frozen=state_hold===1'b1;
    reg state_pending_minute=0;
    // Wall time continues through a guest checkpoint. Preserve a live alarm
    // edge until the interrupt owner resumes; restoring parser bits must not
    // rewind the live minute-edge history or erase an alarm received asleep.
    always @(posedge clk)begin
        if(reset)state_pending_minute<=0;
        else if(state_frozen)begin
            if(minute_level && !minute_level_previous)state_pending_minute<=1;
        end else state_pending_minute<=0;
    end
    assign state_valid=state_frozen && !reset && !calendar_write && !persistence_busy && !restore;
    always @*begin
        state_rdata=0;
        if(state_valid)case(state_addr)
            0:state_rdata={13'd0,irq,bits,sio_out,command_active,read_enable,direction,data_latch};
            1:state_rdata={16'd0,command,command_shift};
            2:state_rdata=shift_data[31:0];
            3:state_rdata={8'd0,shift_data[55:32]};
        endcase
    end
`endif
    wire [31:0] mask=size==0 ? 32'hff << (addr[1:0]*8) : size==1 ? 32'hffff << (addr[1]*16) : 32'hffffffff;
    wire [31:0] aligned=size==2 ? wdata : wdata << (addr[1:0]*8);
    wire [31:0] merged=({12'd0,direction,12'd0,data_latch}&~mask)|(aligned&mask);
    wire pins_write=bus_write && addr[24:2]==23'h31;
    wire [3:0] pins=(data_latch&direction)|{2'd0,sio_out && !direction[1],1'b0};
    wire [3:0] next_pins=(merged[3:0]&merged[19:16])|{2'd0,sio_out && !merged[17],1'b0};
    // Bits are deposited in their architectural positions, LSB first.
    wire [7:0] command_byte=(command_shift & ~(8'b1 << bits[2:0])) | ({7'd0,next_pins[1]} << bits[2:0]);
    wire [7:0] reversed_command={command_byte[0],command_byte[1],command_byte[2],command_byte[3],command_byte[4],command_byte[5],command_byte[6],command_byte[7]};
    wire [7:0] normalized_command=command_byte[7:4]==6 ? command_byte : reversed_command;
    wire [6:0] data_length=command[3:1]==2 ? 7'd56 : command[3:1]==3 ? 7'd24 : 7'd8;
    // Serial input enters at the top, LSB first. Select the completed byte
    // group once at commit instead of decoding a 56-way write bit position.
    wire [55:0] payload_with_bit={next_pins[1],shift_data[55:1]};
    wire [7:0] visible_hour=control[6] ? hour : hour_to_12(hour);
    wire [55:0] datetime={second,minute,visible_hour,5'd0,weekday,day,month,year};
    assign rdata=addr[24:2]==23'h31 ? {12'd0,direction,12'd0,pins} : {31'd0,read_enable};
    always @(posedge clk)begin
        calendar_write<=0;
`ifdef GBK_SAVESTATE
        if(!state_frozen)irq<=(minute_level && !minute_level_previous) || state_pending_minute;
`else
        irq<=minute_level && !minute_level_previous;
`endif
        minute_level_previous<=minute_level;
        if(reset)begin
            data_latch<=0;direction<=0;read_enable<=0;command_shift<=0;command<=0;bits<=0;
            command_active<=0;sio_out<=1;shift_data<=0;
            if(!RTC_PERSISTENCE)control<=8'h40;
`ifdef GBK_SAVESTATE
        end else if(state_frozen)begin
            if(state_write && state_valid)case(state_addr)
                0:begin data_latch<=state_wdata[3:0];direction<=state_wdata[7:4];read_enable<=state_wdata[8];
                    command_active<=state_wdata[9];sio_out<=state_wdata[10];bits<=state_wdata[17:11];irq<=state_wdata[18];end
                1:begin command_shift<=state_wdata[7:0];command<=state_wdata[15:8];end
                2:shift_data[31:0]<=state_wdata;
                3:shift_data[55:32]<=state_wdata[23:0];
            endcase
`endif
        end else begin
            if(bus_write && addr[24:2]==23'h32 && mask[0])read_enable<=aligned[0];
            if(pins_write)begin
                data_latch<=merged[3:0];direction<=merged[19:16];
                if(!next_pins[2] || !pins[2])begin bits<=0;command_active<=0;sio_out<=1;end
                else if(!pins[0] && next_pins[0])begin
                    if(!command_active)begin
                        command_shift<=command_byte;
                        if(bits==7)begin
                            bits<=0;command<=normalized_command;command_active<=normalized_command[7:4]==6;
                            case(normalized_command[3:1])
                                0:begin
                                    control<=0;calendar_payload<=56'h00000000010100;
                                    calendar_date_write<=1;calendar_write<=1;
                                end
                                2:shift_data<=datetime;
                                6:irq<=1;
                                1:shift_data<={48'd0,control};
                                3:shift_data<={32'd0,second,minute,visible_hour};
                                default:shift_data<=56'hffffffffffffff;
                            endcase
                        end else bits<=bits+1'b1;
                    end else if(!command[0])begin
                        shift_data<=payload_with_bit;
                        if(bits==data_length-1)begin
                            bits<=0;
                            if(command[3:1]==1)control<=payload_with_bit[55:48] & 8'h6a;
                            else if(command[3:1]==2 || command[3:1]==3)begin
                                calendar_payload<=command[3:1]==2 ? payload_with_bit : {32'd0,payload_with_bit[55:32]};
                                calendar_date_write<=command[3:1]==2;calendar_write<=1;
                            end
                        end else bits<=bits+1'b1;
                    end
                end else if(pins[0] && !next_pins[0] && command_active && command[0])begin
                    sio_out<=shift_data[0];bits<=bits==data_length-1 ? 7'd0 : bits+1'b1;
                    case(command[3:1])
                        2:shift_data<={shift_data[0],shift_data[55:1]};
                        3:shift_data[23:0]<={shift_data[0],shift_data[23:1]};
                        default:shift_data[7:0]<={shift_data[0],shift_data[7:1]};
                    endcase
                end
            end
        end
        if(restore)control<=restored_control;
    end
endmodule

module gba_rtc_signature(input wire clk,reset,load_write,input wire [22:0] load_addr,
    input wire [31:0] load_wdata,output reg enabled=0);
    reg [6:0] matched=0;
    reg [22:0] next_addr=0;
    reg history=0;
    function automatic [7:0] advance(input [6:0] previous,input [7:0] value);
        begin
            advance[0]=value=="S";advance[1]=previous[0] && value=="I";
            advance[2]=previous[1] && value=="I";advance[3]=previous[2] && value=="R";
            advance[4]=previous[3] && value=="T";advance[5]=previous[4] && value=="C";
            advance[6]=previous[5] && value=="_";advance[7]=previous[6] && value=="V";
        end
    endfunction
    wire [7:0] s0=advance(history && load_addr==next_addr && load_addr!=0 ? matched : 7'd0,load_wdata[7:0]);
    wire [7:0] s1=advance(s0[6:0],load_wdata[15:8]),s2=advance(s1[6:0],load_wdata[23:16]),s3=advance(s2[6:0],load_wdata[31:24]);
    always @(posedge clk)begin
        if(reset)begin matched<=0;history<=0;next_addr<=0;end
        else if(load_write)begin
            matched<=s3[6:0];next_addr<=load_addr+1'b1;history<=1;
            if(load_addr==0)enabled<=0;
            else if(s0[7] || s1[7] || s2[7] || s3[7])enabled<=1;
        end
    end
endmodule
