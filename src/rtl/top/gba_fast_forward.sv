`ifdef GBK_FAST_FORWARD
// Host preference survives guest reset like the other Interact settings.
// Only a synchronized request enters the execution domain. Speed is a host
// control, not architectural state and does not change the save image layout.
module gba_fast_forward(
    input wire host_clk,cpu_clk,reset,in_menu,suspended,hold_button,
    input wire bridge_wr,bridge_rd,endian_little,
    input wire [31:0] bridge_addr,bridge_wdata,
    output wire [31:0] bridge_rdata,
    output wire active,realign,mute_audio,
    output wire [1:0] speed
);
    reg menu_enabled=0;
    reg menu_mute=0;
    reg [1:0] menu_speed=1;
    reg [31:0] read_data=0;
    wire [31:0] setting_data=endian_little ?
        {bridge_wdata[7:0],bridge_wdata[15:8],bridge_wdata[23:16],bridge_wdata[31:24]} : bridge_wdata;
    always @(posedge host_clk)begin
        if(bridge_wr && bridge_addr==32'h10000010)menu_enabled<=setting_data[0];
        if(bridge_wr && bridge_addr==32'h10000018)menu_mute<=setting_data[0];
        if(bridge_wr && bridge_addr==32'h10000014)
            menu_speed<=setting_data<=2 ? setting_data[1:0] : 2'd1;
        if(bridge_rd)begin
            case(bridge_addr)
                32'h10000010:read_data<={31'd0,menu_enabled};
                32'h10000014:read_data<={30'd0,menu_speed};
                32'h10000018:read_data<={31'd0,menu_mute};
                default:read_data<=0;
            endcase
        end
    end
    assign bridge_rdata=endian_little ?
        {read_data[7:0],read_data[15:8],read_data[23:16],read_data[31:24]} : read_data;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] request_sync;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] mute_sync;
    assign mute_audio=mute_sync[2];
    // Menu writes happen while acceleration is suspended. Each bit crosses
    // three stages like the request; all intermediate codes are bounded rates.
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] speed_low_sync,speed_high_sync;
    assign speed={speed_high_sync[2],speed_low_sync[2]};
    reg previous_active;
    assign active=request_sync[2];
    // A one-clock synthetic STOP uses the proven frozen-raster handshake to
    // reacquire normal scanout phase after any accelerated interval.
    assign realign=previous_active && !active;
    always @(posedge cpu_clk)begin
        if(reset)begin
            request_sync<=0;previous_active<=0;mute_sync<=0;
            speed_low_sync<=3'b111;speed_high_sync<=0;
        end
        else begin
            request_sync<={request_sync[1:0],(menu_enabled || hold_button) && !in_menu && !suspended};
            mute_sync<={mute_sync[1:0],menu_mute};
            speed_low_sync<={speed_low_sync[1:0],menu_speed[0]};
            speed_high_sync<={speed_high_sync[1:0],menu_speed[1]};
            previous_active<=active;
        end
    end
endmodule
`endif
