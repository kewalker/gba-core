// Byte-wide Game Pak save bus. AD holds the 16-bit byte address; the high
// address bank carries data. The ROM select stays inactive for every command.
//
// BANKED (128 KiB Flash): the top address bit selects one of two 64 KiB
// banks. Before an access to a large chip in a different bank, the engine
// issues the bank command (AA@5555, 55@2AAA, B0@5555, bank@0000). The bank is
// re-established at the start of every enabled pass. Small chips never see it.
module gba_gamepak_flash #(
    parameter integer GUARD_CYCLES=20,
    parameter integer ACCESS_CYCLES=20,
    parameter integer POLL_LIMIT=1048575,
    parameter bit LATCH_REQUEST=1,
    parameter bit LINEAR_SAVE=0,
    parameter bit BANKED=0,
    parameter integer ADDRESS_BITS=16
)(
    input wire clk,enable,request,
    input wire linear_save,
    input wire large_chip,
    input wire [1:0] operation,
    input wire [ADDRESS_BITS-1:0] address,
    input wire [7:0] write_data,data_in,
    output wire ready,
    output reg done=0,
    output reg error=0,
    output reg [7:0] read_data=0,
    output reg [15:0] chip_id=0,
    output reg [15:0] pin_address=0,
    output reg [7:0] pin_data=0,
    output wire address_drive,data_drive,cs2_n,rd_n,wr_n
);
    localparam READ=0, IDENTIFY=1, PROGRAM=2, ERASE=3;
    localparam IDLE=0, DECODE=1, SETUP=2, ACCESS=3, HOLD=4, RELEASE=5, RESULT=6;
    localparam integer MAX_WAIT=GUARD_CYCLES>ACCESS_CYCLES ? GUARD_CYCLES : ACCESS_CYCLES;
    reg [2:0] phase=IDLE;
    reg [$clog2(MAX_WAIT+1)-1:0] ticks;
    reg [$clog2(POLL_LIMIT+1)-1:0] polls;
    reg [1:0] job;
    reg [2:0] step;
    reg [ADDRESS_BITS-1:0] held_address;
    reg [7:0] held_data,sample;
    wire [ADDRESS_BITS-1:0] full_address=LATCH_REQUEST ? held_address : address;
    // Within a bank, the chip sees the low address bits only.
    wire [15:0] job_address=BANKED ? 16'(full_address[ADDRESS_BITS-2:0]) : 16'(full_address);
    wire target_bank=BANKED && full_address[ADDRESS_BITS-1];
    reg bank=0,bank_known=0,banking=0;
    wire [7:0] job_data=LATCH_REQUEST ? held_data : write_data;
    wire linear=LINEAR_SAVE && linear_save;
    reg writing=0,compare_poll;
    reg bus_active=0,read_strobe=0,write_strobe=0;
    reg previous_toggle;
    reg [7:0] manufacturer;
    assign ready=enable && phase==IDLE;
    assign address_drive=enable && bus_active;
    assign data_drive=address_drive && writing;
    assign cs2_n=!address_drive;
    assign rd_n=!enable || !read_strobe;
    assign wr_n=!enable || !write_strobe;

    always @(posedge clk)begin
        done<=0;
        if(!enable)begin
            phase<=IDLE;error<=0;bus_active<=0;read_strobe<=0;write_strobe<=0;
            bank_known<=0;banking<=0;
        end
        else case(phase)
            IDLE:if(request)begin
                job<=operation;held_address<=address;held_data<=write_data;
                step<=0;polls<=0;compare_poll<=0;error<=0;phase<=DECODE;
                banking<=BANKED && large_chip && (!bank_known || bank!=(BANKED && address[ADDRESS_BITS-1]));
            end
            DECODE:begin
                pin_address<=job_address;pin_data<=job_data;writing<=0;
                if(BANKED && banking)begin
                    writing<=1;
                    case(step)
                        0:begin pin_address<=16'h5555;pin_data<=8'haa;end
                        1:begin pin_address<=16'h2aaa;pin_data<=8'h55;end
                        2:begin pin_address<=16'h5555;pin_data<=8'hb0;end
                        default:begin pin_address<=16'h0000;pin_data<={7'd0,target_bank};end
                    endcase
                end
                else if(linear)writing<=job==PROGRAM && step==0;
                else if(job!=READ)case(step)
                    0:begin pin_address<=16'h5555;pin_data<=8'haa;writing<=1;end
                    1:begin pin_address<=16'h2aaa;pin_data<=8'h55;writing<=1;end
                    2:begin
                        pin_address<=16'h5555;writing<=1;
                        pin_data<=job==IDENTIFY ? 8'h90 : job==PROGRAM ? 8'ha0 : 8'h80;
                    end
                    3:case(job)
                        IDENTIFY:pin_address<=0;
                        PROGRAM:writing<=1;
                        default:begin pin_address<=16'h5555;pin_data<=8'haa;writing<=1;end
                    endcase
                    4:case(job)
                        IDENTIFY:pin_address<=1;
                        ERASE:begin pin_address<=16'h2aaa;pin_data<=8'h55;writing<=1;end
                        default:begin end
                    endcase
                    5:begin
                        writing<=1;
                        if(job==IDENTIFY)begin pin_address<=16'h5555;pin_data<=8'haa;end
                        else pin_data<=8'h30;
                    end
                    6:if(job==IDENTIFY)begin pin_address<=16'h2aaa;pin_data<=8'h55;writing<=1;end
                    7:begin pin_address<=16'h5555;pin_data<=8'hf0;writing<=1;end
                endcase
                bus_active<=1;ticks<=GUARD_CYCLES-1;phase<=SETUP;
            end
            SETUP:if(ticks!=0)ticks<=ticks-1'b1;
                else begin
                    read_strobe<=!writing;write_strobe<=writing;
                    ticks<=ACCESS_CYCLES-1;phase<=ACCESS;
                end
            ACCESS:if(ticks!=0)ticks<=ticks-1'b1;
                else begin
                    read_strobe<=0;write_strobe<=0;sample<=data_in;
                    ticks<=GUARD_CYCLES-1;phase<=HOLD;
                end
            HOLD:if(ticks!=0)ticks<=ticks-1'b1;
                else begin bus_active<=0;ticks<=GUARD_CYCLES-1;phase<=RELEASE;end
            RELEASE:if(ticks!=0)ticks<=ticks-1'b1;else phase<=RESULT;
            RESULT:begin
                phase<=DECODE;
                if(BANKED && banking)begin
                    if(step==3)begin step<=0;banking<=0;bank<=target_bank;bank_known<=1;end
                    else step<=step+1'b1;
                end
                else if(job==READ)begin read_data<=sample;phase<=IDLE;done<=1;end
                else if(linear)begin
                    if(job!=PROGRAM || !writing)begin
                        phase<=IDLE;done<=1;error<=job!=PROGRAM || sample!=job_data;
                    end else step<=1;
                end
                else if(job==IDENTIFY)begin
                    step<=step+1'b1;
                    if(step==3)manufacturer<=sample;
                    if(step==4)chip_id<={sample,manufacturer};
                    if(step==7)begin phase<=IDLE;done<=1;end
                end else if(writing)step<=step+1'b1;
                else if(compare_poll && previous_toggle==sample[6] &&
                    (job==ERASE ? sample==8'hff : sample==job_data))begin
                    phase<=IDLE;done<=1;
                end else if(polls==POLL_LIMIT)begin
                    phase<=IDLE;done<=1;error<=1;
                end else begin
                    polls<=polls+1'b1;previous_toggle<=sample[6];compare_poll<=1;
                end
            end
            default:phase<=IDLE;
        endcase
    end
endmodule
