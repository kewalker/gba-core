// GBA serial registers and normal 8/32-bit cable transport. GPIO SI edges
// remain live in STOP. Physical multiplayer/UART/Joybus engines are separate
// from this register/normal-transfer stage; do not claim their cable parity.
module gba_serial(
    input wire clk,reset,cycle_enable,stopped,
`ifdef GBK_SAVESTATE
    input wire state_prepare,state_hold,state_write,
    input wire [3:0] state_addr,
    input wire [31:0] state_wdata,
    output wire state_valid,
    output reg [31:0] state_rdata,
`endif
    input wire access,write,
    input wire [31:0] addr,wdata,
    input wire [1:0] size,
    input wire [3:0] pins_in, // {SO,SI,SD,SC}, pull-ups when unconnected
    output reg [3:0] pins_out,pins_dir,
    output reg [31:0] rdata,
    output reg irq
);
    reg [15:0] siocnt,rcnt,send_data,joycnt;
    reg [31:0] data32,multi23,joy_recv,joy_trans;
    reg [5:0] joystat;
    reg busy,clock_level,so_bit;
    reg [2:0] normal_hold;
    reg [5:0] remaining;
    reg [4:0] half_count;
    reg [31:0] transmit,receive;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [3:0] pins_meta,pins_sync;
    reg [3:0] pins_previous;
`ifdef GBK_SAVESTATE
    wire state_frozen=state_hold===1'b1;
    reg state_disconnected;
    // A physical peer cannot rewind with this console. A state operation
    // disconnects the cable until guest reset, while preserving guest protocol
    // progress as it would stand after unplugging. Normal play is unchanged.
    always @(posedge clk)begin
        if(reset)state_disconnected<=0;
        else if(state_prepare===1'b1 && state_frozen)state_disconnected<=1;
    end
    assign state_valid=!reset && state_frozen && state_disconnected && state_addr<10;
    always @*begin
        state_rdata=0;
        if(state_valid)case(state_addr)
            0:state_rdata={send_data,siocnt};1:state_rdata={joycnt,rcnt};
            2:state_rdata=data32;3:state_rdata=multi23;4:state_rdata=joy_recv;5:state_rdata=joy_trans;
            6:state_rdata={8'd0,irq,joystat,half_count,remaining,normal_hold,so_bit,clock_level,busy};
            7:state_rdata=transmit;8:state_rdata=receive;
            9:state_rdata={20'd0,pins_previous,pins_sync,pins_meta};
            default:state_rdata=0;
        endcase
    end
`endif
    wire [1:0] mode=siocnt[13:12];
    wire normal=!rcnt[15] && !mode[1];
    wire gpio=rcnt[15:14]==2'b10;
    wire joybus=rcnt[15:14]==2'b11;
    wire [31:0] mask=size==0 ? 32'hff << (addr[1:0]*8) : size==1 ? 32'hffff << (addr[1]*16) : 32'hffffffff;
    wire [31:0] aligned=size==2 ? wdata : wdata << (addr[1:0]*8);
    wire [31:0] control_word=({send_data,siocnt}&~mask)|(aligned&mask);
    wire [15:0] rcnt_next=((rcnt&~mask[15:0]) | aligned[15:0]&mask[15:0]) & 16'hc1ff;
    wire hit=addr[31:16]==16'h0400;
    wire store=access && write && hit;
`ifdef GBK_LINK_MULTIPLAYER
    wire multi_control_store=store && addr[15:2]==14'h4a;
    wire multiplayer=!rcnt[15] && mode==2;
    wire multi_selected=!rcnt[15] && (multi_control_store ? control_word[13:12]==2 : mode==2);
    wire multi_connected=
`ifdef GBK_SAVESTATE
        !state_disconnected;
`else
        1'b1;
`endif
    wire multi_busy,multi_error,multi_done,multi_begin,multi_valid;
    wire [1:0] multi_id,multi_slot;
    wire [15:0] multi_data;
    wire [3:0] multi_out,multi_dir;
    gba_serial_multiplayer multi_engine(
        .clk,.reset(reset || !multi_selected || !multi_connected),.cycle_enable,.stopped,
        .start(multi_control_store && mask[7] && control_word[7] && control_word[13:12]==2),
        .baud(multi_control_store ? control_word[1:0] : siocnt[1:0]),
        .send_data(multi_control_store && |mask[31:16] ? control_word[31:16] : send_data),
        .pins(pins_sync),.previous(pins_previous),
        .pins_out(multi_out),.pins_dir(multi_dir),.busy(multi_busy),.error(multi_error),
        .player_id(multi_id),.done(multi_done),.begin_transfer(multi_begin),
        .data_valid(multi_valid),.slot(multi_slot),.data(multi_data));
`endif
    wire [3:0] effective_pins=(pins_sync & ~pins_dir) | (pins_out & pins_dir);
    wire internal_edge=normal && busy && siocnt[0] && cycle_enable && half_count==(siocnt[1] ? 5'd3 : 5'd31);
    wire sample_edge=normal && busy && !stopped && (siocnt[0] ? internal_edge && !clock_level :
        !pins_previous[0] && pins_sync[0]);
    wire [31:0] next_receive={receive[30:0],pins_sync[2]};
    always @* begin
        pins_out=4'hf;pins_dir=0;
`ifdef GBK_SAVESTATE
        if(!state_disconnected)begin
`endif
        if(gpio)begin pins_out=rcnt[3:0];pins_dir=rcnt[7:4];end
`ifdef GBK_LINK_MULTIPLAYER
        else if(multiplayer)begin pins_out=multi_out;pins_dir=multi_dir;end
`endif
        else if(normal)begin
            pins_out[3]=(busy || normal_hold!=0) ? so_bit : siocnt[3];pins_dir[3]=1;
            pins_out[0]=clock_level;pins_dir[0]=siocnt[0];
        end
`ifdef GBK_SAVESTATE
        end
`endif
        rdata=0;
        case({addr[15:2],2'b00})
            16'h0120:rdata=data32;
            16'h0124:rdata=multi23;
            16'h0128:begin
                rdata={send_data,siocnt & 16'h7f8b};
                if(!mode[1])begin rdata[2]=pins_sync[2];rdata[7]=busy;end
                else if(mode==2)begin
                    rdata[2]=pins_sync[2];rdata[3]=pins_sync[1];
`ifdef GBK_LINK_MULTIPLAYER
                    rdata[6:4]=multi_connected ? {multi_error,multi_id} : {1'b1,siocnt[5:4]};
                    rdata[7]=multi_connected && multi_busy;
`else
                    rdata[6:4]=0;rdata[7]=0;
`endif
                end else begin rdata[6:4]=3'b010;end
            end
            16'h0134:rdata={16'd0,rcnt[15:4],effective_pins};
            16'h0140:rdata={16'd0,joycnt};
            16'h0150:rdata=joy_recv;
            16'h0154:rdata=joy_trans;
            16'h0158:rdata={26'd0,joystat};
            default:rdata=0;
        endcase
    end
    always @(posedge clk)begin
        if(reset)begin
            siocnt<=0;rcnt<=16'h8000;send_data<=0;data32<=0;multi23<=0;
            joycnt<=0;joy_recv<=0;joy_trans<=0;joystat<=0;
            busy<=0;clock_level<=1;so_bit<=1;normal_hold<=0;remaining<=0;half_count<=0;transmit<=0;receive<=0;irq<=0;
            pins_meta<=4'hf;pins_sync<=4'hf;pins_previous<=4'hf;
`ifdef GBK_SAVESTATE
        end else if(state_frozen)begin
            if(state_write && state_valid)case(state_addr)
                0:begin
`ifdef GBK_LINK_MULTIPLAYER
                    siocnt<=state_wdata[15:0]&16'h7ffb;
`else
                    siocnt<=state_wdata[15:0]&16'h7f8b;
`endif
                    send_data<=state_wdata[31:16];
                end
                1:begin rcnt<=state_wdata[15:0]&16'hc1ff;joycnt<=state_wdata[31:16]&16'h0047;end
                2:data32<=state_wdata;3:multi23<=state_wdata;4:joy_recv<=state_wdata;5:joy_trans<=state_wdata;
                6:begin busy<=state_wdata[0];clock_level<=state_wdata[1];so_bit<=state_wdata[2];
                    normal_hold<=state_wdata[5:3];remaining<=state_wdata[11:6];half_count<=state_wdata[16:12];
                    joystat<=state_wdata[22:17];irq<=state_wdata[23];end
                7:transmit<=state_wdata;8:receive<=state_wdata;
                9:begin pins_meta<=state_wdata[3:0];pins_sync<=state_wdata[7:4];pins_previous<=state_wdata[11:8];end
                default:begin end
            endcase
`endif
        end else begin
            for(integer pin=0;pin<4;pin=pin+1)pins_meta[pin]<=
`ifdef GBK_SAVESTATE
                state_disconnected ? 1'b1 :
`endif
                pins_in[pin]!==1'b0;
            pins_sync<=pins_meta;pins_previous<=pins_sync;
            irq<=gpio && rcnt[8] && pins_previous[2] && !pins_sync[2];
`ifdef GBK_LINK_MULTIPLAYER
            // Physical peers cannot rewind. State operations disconnect and
            // cancel multiplayer until guest reset; receive banks remain saved
            // in the existing ten-word schema. No live cable FSM is restored.
            if(multiplayer && multi_connected)begin
                if(multi_begin)begin data32<=32'hffffffff;multi23<=32'hffffffff;end
                if(multi_valid)case(multi_slot)
                    0:data32[15:0]<=multi_data;
                    1:data32[31:16]<=multi_data;
                    2:multi23[15:0]<=multi_data;
                    3:multi23[31:16]<=multi_data;
                endcase
                if(multi_done)begin
                    siocnt[6:4]<={multi_error,multi_id};
                    if(siocnt[14])irq<=1;
                end
            end
`endif
            if(normal_hold!=0)normal_hold<=normal_hold-1'b1;
            if(normal && busy && siocnt[0] && cycle_enable && !stopped)begin
                if(internal_edge)begin half_count<=0;clock_level<=!clock_level;end
                else half_count<=half_count+1'b1;
            end
            if(normal && busy && !stopped && (siocnt[0] ? internal_edge && clock_level :
                pins_previous[0] && !pins_sync[0]))so_bit<=transmit[31];
            if(sample_edge)begin
                receive<=next_receive;transmit<={transmit[30:0],1'b1};remaining<=remaining-1'b1;
                if(remaining==1)begin
                    busy<=0;clock_level<=1;siocnt[7]<=0;normal_hold<=5;
                    if(mode==1)data32<=next_receive;else send_data<={8'd0,next_receive[7:0]};
                    if(siocnt[14])irq<=1;
                end
            end
            if(access && !write && hit && joybus && addr[15:2]==14'h54)joystat[3]<=0;
            if(store)case({addr[15:2],2'b00})
                16'h0120:data32<=(data32&~mask)|(aligned&mask);
                16'h0124:multi23<=(multi23&~mask)|(aligned&mask);
                16'h0128:begin
                    if(|mask[31:16])send_data<=mode==2 ? control_word[31:16] : {8'd0,control_word[23:16]};
                    if(|mask[15:0])begin
`ifdef GBK_LINK_MULTIPLAYER
                        siocnt<=(control_word[15:0] & 16'h7f8b) | (siocnt & 16'h0070);
`else
                        siocnt<=control_word[15:0] & 16'h7f8b;
`endif
                        if(control_word[13:12]!=mode || !control_word[7])begin busy<=0;clock_level<=1;end
                        else if(!busy && normal && !control_word[13])begin
                            busy<=1;remaining<=control_word[12] ? 32 : 8;half_count<=0;clock_level<=1;
                            transmit<=control_word[12] ? data32 : {control_word[23:16],24'd0};receive<=0;
                        end
                    end
                end
                16'h0134:begin
                    rcnt<=rcnt_next;
                    if(rcnt_next[15:14]!=rcnt[15:14])begin busy<=0;clock_level<=1;end
                end
                16'h0140:joycnt<=((joycnt&~(aligned[15:0]&mask[15:0]&16'h0007))&16'h0007) |
                    (((joycnt&~mask[15:0])|(aligned[15:0]&mask[15:0]))&16'h0040);
                16'h0150:joy_recv<=(joy_recv&~mask)|(aligned&mask);
                16'h0154:begin joy_trans<=(joy_trans&~mask)|(aligned&mask);joystat[1]<=1;end
                16'h0158:joystat[5:4]<=((joystat&~mask[5:0])|(aligned[5:0]&mask[5:0]))>>4;
                default:begin end
            endcase
        end
    end
endmodule

`ifdef GBK_LINK_MULTIPLAYER
// Experimental wire-level multiplayer transport. SD carries asynchronous,
// LSB-first start/data/stop frames; SC brackets the whole exchange and SO/SI
// hands each child its turn. Baud divisors and the three-bit idle termination
// window are initial model choices, pending measurement against real hardware.
// This module deliberately stays default-off until physical interoperability
// and full-core timing have been qualified.
module gba_serial_multiplayer(
    input wire clk,reset,cycle_enable,stopped,start,
    input wire [1:0] baud,
    input wire [15:0] send_data,
    input wire [3:0] pins,previous,
    output reg [3:0] pins_out,pins_dir,
    output reg busy,error,done,begin_transfer,data_valid,
    output reg [1:0] player_id,slot,
    output reg [15:0] data
);
    reg parent,sent,tx_active,rx_active,handed;
    reg [10:0] period,tx_ticks,rx_ticks;
    reg [1:0] silence,rx_slot;
    reg [4:0] tx_bit,rx_bit;
    reg [15:0] tx_shift,rx_shift,payload;
    reg sd_out;
    wire start_edge=previous[1] && !pins[1];
    wire clock_fall=previous[0] && !pins[0];
    wire clock_rise=!previous[0] && pins[0];
    wire [10:0] selected_period=baud==0 ? 11'd1748 : baud==1 ? 11'd437 : baud==2 ? 11'd291 : 11'd146;
    always @*begin
        pins_out=4'hf;pins_dir=4'b1000;
        pins_out[3]=!handed;
        if(parent && busy)begin pins_dir[0]=1;pins_out[0]=0;end
        if(tx_active)begin pins_dir[1]=1;pins_out[1]=sd_out;end
    end
    always @(posedge clk)begin
        if(reset)begin
            busy<=0;error<=0;done<=0;begin_transfer<=0;data_valid<=0;
            player_id<=0;slot<=0;data<=0;parent<=0;sent<=0;
            tx_active<=0;rx_active<=0;handed<=0;period<=146;
            tx_ticks<=0;rx_ticks<=0;silence<=0;rx_slot<=0;
            tx_bit<=0;rx_bit<=0;tx_shift<=0;rx_shift<=0;payload<=0;sd_out<=1;
        end else begin
            done<=0;begin_transfer<=0;data_valid<=0;
            if(!busy)begin
                parent<=!pins[2];handed<=0;
                if(!stopped && ((!pins[2] && start && pins[1]) || (pins[2] && clock_fall)))begin
                    busy<=1;error<=0;begin_transfer<=1;sent<=0;handed<=0;
                    parent<=!pins[2];period<=selected_period;payload<=send_data;
                    rx_slot<=0;silence<=0;rx_ticks<=selected_period-1'b1;
                    rx_active<=0;tx_active<=0;
                end
            end else if(!stopped)begin
                // Children finish only on the parent's SC release. Losing a
                // chain predecessor leaves them without a turn and sets error.
                if(!parent && clock_rise)begin
                    busy<=0;done<=1;tx_active<=0;rx_active<=0;handed<=0;
                    if(!sent)error<=1;
                end else begin
                    if(!sent && !tx_active && !rx_active && (parent || !pins[2]))begin
                        tx_active<=1;sd_out<=0;tx_bit<=0;
                        tx_ticks<=period-1'b1;tx_shift<=payload;player_id<=rx_slot;
                    end
                    if(tx_active && cycle_enable)begin
                        if(tx_ticks!=0)tx_ticks<=tx_ticks-1'b1;
                        else begin
                            tx_ticks<=period-1'b1;tx_bit<=tx_bit+1'b1;
                            if(tx_bit<16)begin sd_out<=tx_shift[0];tx_shift<={1'b1,tx_shift[15:1]};end
                            else if(tx_bit==16)sd_out<=1;
                            else begin tx_active<=0;sent<=1;handed<=1;end
                        end
                    end
                    if(!rx_active && start_edge && silence!=3)begin
                        rx_active<=1;rx_bit<=0;rx_ticks<=(period>>1)-1'b1;
                        rx_shift<=0;silence<=0;
                    end else if(cycle_enable)begin
                        if(rx_ticks!=0)rx_ticks<=rx_ticks-1'b1;
                        else begin
                            rx_ticks<=period-1'b1;
                            if(rx_active)begin
                                rx_bit<=rx_bit+1'b1;
                                if(rx_bit==0)begin
                                    if(pins[1])begin rx_active<=0;error<=1;end
                                end else if(rx_bit<=16)rx_shift<={pins[1],rx_shift[15:1]};
                                else begin
                                    rx_active<=0;data_valid<=1;slot<=rx_slot;data<=rx_shift;
                                    if(!pins[1])error<=1;
                                    if(rx_slot!=3)rx_slot<=rx_slot+1'b1;
                                    else silence<=3;
                                end
                            end else if(parent && !tx_active && sent)begin
                                if(silence>=2)begin
                                    busy<=0;done<=1;handed<=0;
                                end else silence<=silence+1'b1;
                            end
                        end
                    end
                end
            end
        end
    end
endmodule
`endif
