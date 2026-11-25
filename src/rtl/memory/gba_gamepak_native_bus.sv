// One CPU or DMA access to the native slot. ROM/GPIO/EEPROM use the
// multiplexed halfword bus. The save window uses a byte and /CS2.
// The physical cartridge interprets all command sequences and busy reads.
module gba_gamepak_native_bus #(
    parameter integer GUARD_CYCLES=8,
    parameter integer ACCESS_CYCLES=20
)(
    input wire clk,enable,write_allowed,
    input wire request,write,response_ready,
    input wire [26:0] address,
    input wire [1:0] size,
    input wire [31:0] wdata,
    output wire ready,response,
    output reg error=0,
    output reg [31:0] rdata=0,
    input wire [15:0] ad_in,
    input wire [7:0] high_in,
    output wire [23:0] pins,
    output wire ad_drive,high_drive,cs1_n,cs2_n,rd_n,wr_n
);
    localparam IDLE=0,ADDRESS=1,SELECT=2,DATA=3,STROBE=4,HOLD=5,RECOVER=6,REPLY=7;
    localparam WAIT_BITS=$clog2(1+(GUARD_CYCLES>ACCESS_CYCLES ? GUARD_CYCLES : ACCESS_CYCLES));
    reg [2:0] phase=IDLE;
    reg [WAIT_BITS-1:0] ticks;
    reg writing,byte_bus,two_halves,second_half;
    reg [15:0] upper_data;
    reg [15:0] ad_out;
    reg [7:0] high_out;
    reg [15:0] first_halfword;
    reg [14:0] word_address_low;
    reg drive_ad=0,drive_high=0,select_rom=0,select_save=0,read_strobe=0,write_strobe=0;
    wire request_byte_bus=&address[26:25];
    wire request_word=size[1] && !request_byte_bus;
    wire [23:0] halfword_address={address[24:2],address[1] && !request_word};
    wire [1:0] save_lane=size==0 ? 2'd0 : size==1 ? {1'b0,address[0]} : address[1:0];

    assign ready=enable && phase==IDLE;
    assign response=phase==REPLY;
    assign pins={high_out,ad_out};
    assign ad_drive=enable && drive_ad;
    assign high_drive=enable && drive_high;
    assign cs1_n=!enable || !select_rom;
    assign cs2_n=!enable || !select_save;
    assign rd_n=!enable || !read_strobe;
    assign wr_n=!enable || !write_strobe;

    initial if(GUARD_CYCLES<1 || ACCESS_CYCLES<1)$error("Invalid native Game Pak timing");

    always @(posedge clk) begin
        if(phase==REPLY)begin
            if(response_ready)phase<=IDLE;
        end else if(!enable)begin
            drive_ad<=0;drive_high<=0;select_rom<=0;select_save<=0;read_strobe<=0;write_strobe<=0;
            if(phase!=IDLE)begin error<=1;rdata<=0;phase<=REPLY;end
        end else if(phase==IDLE)begin
            if(request)begin
                error<=write && !write_allowed;rdata<=0;
                // Byte stores do not issue writes on the halfword bus.
                if(write && (!write_allowed || (!request_byte_bus && size==0)))phase<=REPLY;
                else begin
                    writing<=write;byte_bus<=request_byte_bus;two_halves<=request_word;second_half<=0;
                    // Until select latches the ROM address, keep the upper
                    // half of write data off the multiplexed AD pins.
                    {high_out,ad_out}<=request_byte_bus ?
                        {wdata[save_lane*8+:8],address[15:0]} : halfword_address;
                    first_halfword<=wdata[15:0];upper_data<=wdata[31:16];
                    word_address_low<=halfword_address[15:1];
                    drive_ad<=1;drive_high<=!request_byte_bus || write;
                    ticks<=WAIT_BITS'(GUARD_CYCLES-1);phase<=ADDRESS;
                end
            end
        end else if(ticks!=0)ticks<=ticks-1'b1;
        else begin
            ticks<=WAIT_BITS'(GUARD_CYCLES-1);
            case(phase)
                ADDRESS:begin
                    select_rom<=!byte_bus;select_save<=byte_bus;phase<=SELECT;
                end
                SELECT:begin
                    if(!byte_bus)begin
                        drive_ad<=writing;
                        if(writing)ad_out<=second_half ? upper_data : first_halfword;
                    end
                    phase<=DATA;
                end
                DATA:begin
                    read_strobe<=!writing;write_strobe<=writing;
                    ticks<=WAIT_BITS'(ACCESS_CYCLES-1);phase<=STROBE;
                end
                STROBE:begin
                    read_strobe<=0;write_strobe<=0;
                    if(!writing)begin
                        if(byte_bus)rdata<={4{high_in}};
                        else if(!two_halves)rdata<={2{ad_in}};
                        else if(second_half)rdata[31:16]<=ad_in;
                        else rdata[15:0]<=ad_in;
                    end
                    phase<=HOLD;
                end
                HOLD:begin
                    if(two_halves && !second_half && !writing)begin
                        second_half<=1;phase<=DATA;
                    end else begin
                        drive_ad<=0;drive_high<=0;select_rom<=0;select_save<=0;phase<=RECOVER;
                    end
                end
                RECOVER:begin
                    if(two_halves && !second_half && writing)begin
                        // Relatch the second halfword address, including for
                        // peripherals whose internal address ignores /WR.
                        ad_out<={word_address_low,1'b1};
                        drive_ad<=1;drive_high<=1;second_half<=1;phase<=ADDRESS;
                    end else phase<=REPLY;
                end
                default:phase<=IDLE;
            endcase
        end
    end
endmodule

// Retain one accepted descriptor across the CPU/slot clock boundary. Guest
// reset cancels delivery to the guest and lets an issued strobe run to hold.
module gba_gamepak_native_link #(
    parameter bit HOST_PORT=0,
    parameter bit BYTE_WRITES_ONLY=0,
    parameter bit COMPACT_MAILBOX=0
)(
    input wire guest_clk,guest_reset,guest_enable,guest_request,guest_write,
    input wire [26:0] guest_address,
    input wire [1:0] guest_size,
    input wire [31:0] guest_wdata,
    output wire guest_ready,guest_error,guest_busy,
    output wire [31:0] guest_rdata,
    input wire slot_clk,slot_enable,write_allowed,
    input wire host_mode,host_request,host_consume,
    input wire [26:0] host_address,
    input wire [1:0] host_size,
    output wire host_ready,host_response,host_error,
    output wire [31:0] host_data,
    input wire [15:0] ad_in,
    input wire [7:0] high_in,
    output wire [23:0] pins,
    output wire ad_drive,high_drive,cs1_n,cs2_n,rd_n,wr_n
);
    wire slot_request,slot_write,slot_ready,slot_response,slot_consume,slot_error;
    wire [26:0] slot_address;
    wire [1:0] slot_size;
    wire [31:0] slot_wdata,slot_rdata;
    localparam integer WRITE_BITS=BYTE_WRITES_ONLY ? 8 : 32;
    wire [WRITE_BITS-1:0] guest_write_payload,slot_write_payload;
    generate if(BYTE_WRITES_ONLY)begin: byte_payload
        // The admitted save aperture writes one lane. Select it before the
        // mailbox so the other lanes do not need crossing registers.
        wire [1:0] lane=guest_size==0 ? 2'd0 : guest_size==1 ? {1'b0,guest_address[0]} : guest_address[1:0];
        assign guest_write_payload=guest_wdata[lane*8+:8];
        assign slot_wdata={4{slot_write_payload}};
    end else begin: full_payload
        assign guest_write_payload=guest_wdata;
        assign slot_wdata=slot_write_payload;
    end endgenerate
    wire use_host=HOST_PORT && host_mode;
    wire bus_ready,bus_response;
    assign host_ready=use_host && bus_ready;
    assign host_response=use_host && bus_response;
    assign host_error=slot_error;
    assign host_data=slot_rdata;
    assign slot_ready=!use_host && bus_ready;
    assign slot_response=!use_host && bus_response;
    wire mailbox_ready,mailbox_response;
    reg canceled=0;
    always @(posedge guest_clk)begin
        if(guest_reset || !guest_enable)canceled<=1;
        else if(mailbox_ready && guest_request)canceled<=0;
    end
    assign guest_ready=mailbox_response && !canceled && !guest_reset && guest_enable;
    gba_state_async_port #(.ADDRESS_BITS(27),.TARGET_BITS(2),.WRITE_DATA_BITS(WRITE_BITS),
        .COMPACT_DATA(COMPACT_MAILBOX)) mailbox(
        .source_clk(guest_clk),.source_cancel(guest_reset || !guest_enable),
        .source_valid(guest_request),.source_write(guest_write),.source_response_ready(1'b1),
        .source_target(guest_size),.source_addr(guest_address),.source_wdata(guest_write_payload),
        .source_ready(mailbox_ready),.source_response(mailbox_response),.source_busy(guest_busy),
        .source_error(guest_error),.source_rdata(guest_rdata),
        .destination_clk(slot_clk),.destination_cancel(!slot_enable),
        .destination_valid(slot_request),.destination_write(slot_write),.destination_response_ready(slot_consume),
        .destination_target(slot_size),.destination_addr(slot_address),.destination_wdata(slot_write_payload),
        .destination_ready(slot_ready),.destination_response(slot_response),.destination_error(slot_error),
        .destination_rdata(slot_rdata));
    gba_gamepak_native_bus bus(.clk(slot_clk),.enable(slot_enable),
        .write_allowed(write_allowed && (!BYTE_WRITES_ONLY || (&slot_address[26:25]))),
        .request(use_host ? host_request : slot_request),.write(!use_host && slot_write),
        .response_ready(use_host ? host_consume : slot_consume),
        .address(use_host ? host_address : slot_address),
        .size(use_host ? host_size : slot_size),.wdata(slot_wdata),
        .ready(bus_ready),.response(bus_response),.error(slot_error),.rdata(slot_rdata),
        .ad_in,.high_in,.pins,.ad_drive,.high_drive,.cs1_n,.cs2_n,.rd_n,.wr_n);
endmodule
