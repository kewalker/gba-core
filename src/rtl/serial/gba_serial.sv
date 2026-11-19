// GBA serial registers and normal 8/32-bit cable transport. GPIO SI edges
// remain live in STOP. Physical multiplayer/UART/Joybus engines are separate
// from this register/normal-transfer stage; do not claim their cable parity.
module gba_serial #(
    parameter bit FIXED_CABLE_CLOCK=0
)(
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
    // The physical cable has considerably more edge noise than the internal
    // GPIO path. Keep a separate synchronized/qualified copy for the
    // multiplayer engine so normal serial timing remains unchanged.
    reg [3:0] multi_filter_a,multi_filter_b,multi_filter_c,multi_pins_sync,multi_pins_previous;
    wire [3:0] multi_ones=multi_filter_a & multi_filter_b & multi_filter_c;
    wire [3:0] multi_zeros=~multi_filter_a & ~multi_filter_b & ~multi_filter_c;
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
    wire cable_tick;
    generate if(FIXED_CABLE_CLOCK)begin : physical_cable_clock
        // Generate the native 16.777216 MHz cadence from the Pocket's
        // 39.936 MHz execution clock independently of guest fast-forward.
        reg [12:0] phase;
        wire tick=phase>=13'd2827;
        always @(posedge clk)begin
            if(reset)phase<=0;
            else phase<=tick ? phase-13'd2827 : phase+13'd2048;
        end
        assign cable_tick=tick
`ifdef GBK_SAVESTATE
            && !state_frozen
`endif
            ;
    end else begin
        assign cable_tick=cycle_enable;
    end endgenerate
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
    wire multi_busy,multi_error,multi_done,multi_begin,multi_valid,multi_parent;
    wire multi_id_valid,multi_disconnected_raw;
    // Disconnected idle reads all-ones data and an error with no ID.
    wire multi_disconnected=multiplayer && multi_connected && multi_disconnected_raw;
    wire [1:0] multi_id,multi_slot;
    wire [15:0] multi_data;
    wire [3:0] multi_out,multi_dir;
    gba_serial_multiplayer #(.PHYSICAL_CABLE(FIXED_CABLE_CLOCK)) multi_engine(
        .clk,.reset(reset || !multi_selected || !multi_connected),.cycle_enable(cable_tick),.stopped,
        .start(multi_control_store && mask[7] && control_word[7] && control_word[13:12]==2),
        .baud(multi_control_store ? control_word[1:0] : siocnt[1:0]),
        .send_data(multi_control_store && |mask[31:16] ? control_word[31:16] : send_data),
        .pins(FIXED_CABLE_CLOCK ? multi_pins_sync : pins_sync),
        .previous(FIXED_CABLE_CLOCK ? multi_pins_previous : pins_previous),
        .pins_out(multi_out),.pins_dir(multi_dir),.busy(multi_busy),.error(multi_error),
        .parent_role(multi_parent),.id_valid(multi_id_valid),.disconnected(multi_disconnected_raw),
        .player_id(multi_id),.done(multi_done),.begin_transfer(multi_begin),
        .data_valid(multi_valid),.slot(multi_slot),.data(multi_data));
`endif
    wire [3:0] effective_pins=(pins_sync & ~pins_dir) | (pins_out & pins_dir);
    wire internal_edge=normal && busy && siocnt[0] && cable_tick && half_count==(siocnt[1] ? 5'd3 : 5'd31);
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
`ifdef GBK_LINK_MULTIPLAYER
            16'h0120:rdata=multi_disconnected ? 32'hffffffff : data32;
            16'h0124:rdata=multi_disconnected ? 32'hffffffff : multi23;
`else
            16'h0120:rdata=data32;
            16'h0124:rdata=multi23;
`endif
            16'h0128:begin
                rdata={send_data,siocnt & 16'h7f8b};
                if(!mode[1])begin rdata[2]=pins_sync[2];rdata[7]=busy;end
                else if(mode==2)begin
`ifdef GBK_LINK_MULTIPLAYER
                    // During a transfer SI hands off a slot and SD carries data.
                    // SIOCNT still reports the selected role and bus readiness.
                    rdata[2]=!multi_parent;rdata[3]=!multi_busy && pins_sync[1];
                    rdata[6:4]=multi_connected ? {multi_error,
                        (FIXED_CABLE_CLOCK && !multi_id_valid) ? 2'b00 : multi_id} : {1'b1,siocnt[5:4]};
                    rdata[7]=multi_connected && multi_busy;
                    if(multi_disconnected)rdata[6:4]=3'b100;
`else
                    rdata[2]=pins_sync[2];rdata[3]=pins_sync[1];
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
            multi_filter_a<=4'hf;multi_filter_b<=4'hf;multi_filter_c<=4'hf;
            multi_pins_sync<=4'hf;multi_pins_previous<=4'hf;
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
            multi_filter_a<=pins_meta;
            multi_filter_b<=multi_filter_a;
            multi_filter_c<=multi_filter_b;
            multi_pins_previous<=multi_pins_sync;
            // Require three consecutive synchronized samples before an
            // input changes. This rejects cable ringing/crosstalk while
            // retaining the reference engine's native edge timing.
            multi_pins_sync<=(multi_pins_sync & ~multi_zeros) | multi_ones;
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
                    // On a physical cable a failed exchange completes
                    // silently, as in the reference core.
                    if(siocnt[14] && !(FIXED_CABLE_CLOCK && multi_error))irq<=1;
                end
            end
`endif
            if(normal_hold!=0)normal_hold<=normal_hold-1'b1;
            if(normal && busy && siocnt[0] && cable_tick && !stopped)begin
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
// hands each child its turn. The idle termination window is a model choice,
// pending measurement against real hardware.
// This module deliberately stays default-off until physical interoperability
// and full-core timing have been qualified.
module gba_serial_multiplayer #(
    parameter bit PHYSICAL_CABLE=0
)(
    input wire clk,reset,cycle_enable,stopped,start,
    input wire [1:0] baud,
    input wire [15:0] send_data,
    input wire [3:0] pins,previous,
    output reg [3:0] pins_out,pins_dir,
    output reg busy,error,done,begin_transfer,data_valid,
    output wire parent_role,
    // Physical-cable status as seen by a reference core known to trade with
    // a GBA SP: ID is reported only after a successful exchange, and an idle
    // unit with no established role reads as disconnected.
    output reg id_valid,
    output wire disconnected,
    output reg [1:0] player_id,slot,
    output reg [15:0] data
);
    reg parent,child_latched,sent,tx_active,rx_active,handed,reply_ready,child_granted;
    reg [10:0] period,tx_ticks,rx_ticks;
    localparam [4:0] REPLY_PERIODS=18;
    reg [4:0] silence;
    // Mincer Ray qualifies the idle parent signature for 255 native cable
    // ticks (~15 us).  A millisecond-scale qualification window lets games
    // time out their role probe before this unit ever reports itself ready.
    reg [7:0] role_samples;
    reg [1:0] rx_slot;
    reg [4:0] tx_bit,rx_bit;
    reg [15:0] tx_shift,rx_shift,payload;
    reg sd_out;
    // SC and the first SD start bit can fall together. Once SC admits a
    // child, accept the low first bit even if its SD edge has already passed.
    wire start_received=!pins[1] && (previous[1] || (!parent && rx_slot==0));
    wire clock_fall=previous[0] && !pins[0];
    // Physical: a parent may pull SC low before this unit selects
    // multi-player (Emerald enables RCNT only after the peer started). Until
    // the first transfer after a mode (re)selection, an already-low SC also
    // starts a child, as in the reference core. period keeps its reset value
    // (146, never a selected baud period) exactly until that first transfer,
    // so no additional register is needed.
    wire fresh_sc_low=PHYSICAL_CABLE && period==11'd146 && !pins[0];
    wire clock_rise=!previous[0] && pins[0];
    wire parent_signature=!child_latched && pins[2:0]==3'b011 && previous[2:0]==3'b011;
    wire idle_parent=parent_signature && (!PHYSICAL_CABLE || (&role_samples));
    wire tx_stop=tx_active && tx_bit==17;
    // Match the reference native-tick divisors exactly. The counter loads
    // period-1 below, so these are the full bit periods, not terminal counts.
    wire [10:0] selected_period=baud==0 ? 11'd1747 : baud==1 ? 11'd436 : baud==2 ? 11'd291 : 11'd145;
    assign parent_role=parent || (!busy && idle_parent);
    assign disconnected=PHYSICAL_CABLE && !busy && !parent && !child_latched && !parent_signature && pins[0];
    always @*begin
        pins_out=4'hf;pins_dir=4'b1000;
        pins_out[3]=!(handed || (!parent && tx_stop));
        if(parent)begin pins_dir[0]=1;pins_out[0]=!busy;end
        // A child can let the cable pull-up hold the tail of its stop bit.
        if(tx_active && (parent || !tx_stop || tx_ticks>=(period>>1)))begin
            pins_dir[1]=1;pins_out[1]=sd_out;
        end
    end
    always @(posedge clk)begin
        if(reset)begin
            busy<=0;error<=0;done<=0;begin_transfer<=0;data_valid<=0;
            player_id<=0;slot<=0;data<=0;parent<=0;child_latched<=0;sent<=0;
            tx_active<=0;rx_active<=0;handed<=0;period<=146;id_valid<=0;
            reply_ready<=0;child_granted<=0;role_samples<=0;
            tx_ticks<=0;rx_ticks<=0;silence<=0;rx_slot<=0;
            tx_bit<=0;rx_bit<=0;tx_shift<=0;rx_shift<=0;payload<=0;sd_out<=1;
        end else begin
            done<=0;begin_transfer<=0;data_valid<=0;
            if(!busy)begin
                handed<=0;
                // On a physical cable, SI can wobble after acquisition.
                // Retain SC ownership until multiplayer mode is reset.
                // The guest-clock model still supports idle role changes.
                if(idle_parent)parent<=1;
                if(parent ? (PHYSICAL_CABLE || !pins[2]) : !parent_signature)role_samples<=0;
                else if(cycle_enable && !(&role_samples))role_samples<=role_samples+1'b1;
                if(!PHYSICAL_CABLE && parent && pins[2] && (&role_samples))parent<=0;
                // Physical: a parent latched while the peer was off or not yet
                // in multi-player mode (its SO, our SI, idles low) must not
                // keep SC once the cable stops showing the parent signature.
                // A Start in that state is ignored and drops the role, so the
                // real parent can clock us as a child (reference behaviour).
                if(PHYSICAL_CABLE && parent && start && !stopped && !parent_signature)begin
                    parent<=0;role_samples<=0;
                end
                if(!stopped && ((parent_role && start && pins[1] && pins[0] &&
                    (!PHYSICAL_CABLE || parent_signature)) ||
                    (!parent_role && pins[2] && (clock_fall || fresh_sc_low))))begin
                    busy<=1;error<=0;begin_transfer<=1;sent<=0;handed<=0;
                    parent<=parent_role;child_latched<=!parent_role;period<=selected_period;payload<=send_data;
                    rx_slot<=0;silence<=0;rx_ticks<=selected_period-1'b1;
                    rx_active<=0;tx_active<=0;reply_ready<=0;child_granted<=0;role_samples<=0;
                end
            end else if(!stopped)begin
                // Children finish only on the parent's SC release. Losing a
                // chain predecessor leaves them without a turn and sets error.
                if(!parent && clock_rise)begin
                    busy<=0;done<=1;tx_active<=0;rx_active<=0;handed<=0;
                    if(!sent && !tx_stop)begin
                        error<=1;
                        // Physical: forget the child role after a missed
                        // turn so the cable is re-qualified from idle.
                        if(PHYSICAL_CABLE)begin child_latched<=0;id_valid<=0;end
                    end else begin
                        id_valid<=!error;
                        if(tx_stop)begin
                            // A real parent may release SC before the local
                            // stop-bit counter has finished. The word is out.
                            data_valid<=1;slot<=player_id;data<=payload;
                        end
                    end
                end else begin
                    // SI is a handoff token. Remember it through the SD stop
                    // cell so a brief return high cannot cancel our slot.
                    if(!parent && !pins[2])child_granted<=1;
                    if(!sent && !tx_active && !rx_active &&
                        (parent || (reply_ready && (child_granted || !pins[2]) && pins[1])))begin
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
                    if(!rx_active && start_received && silence!=REPLY_PERIODS)begin
                        rx_active<=1;rx_bit<=0;rx_ticks<=(period>>1)-1'b1;
                        rx_shift<=0;silence<=0;reply_ready<=0;
                    end else if(cycle_enable)begin
                        // Leave an extra quarter-bit after the nominal stop
                        // cell to account for differences in peer clocks.
                        // Leave an extra quarter-bit after the nominal stop
                        // cell to account for differences in peer clocks.
                        // (Replying exactly at the boundary, as the reference
                        // core does, contends with a slightly slower parent.)
                        if(!rx_active && rx_slot!=0 && rx_ticks==(period>>2))reply_ready<=1;
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
                                    else silence<=REPLY_PERIODS;
                                end
                            end else if(parent && !tx_active && sent)begin
                                if(silence>=REPLY_PERIODS-5'd1)begin
                                    busy<=0;done<=1;handed<=0;
                                    if(PHYSICAL_CABLE && rx_slot<2)begin
                                        // No child answered: report an error
                                        // (no IRQ) and re-acquire the role.
                                        error<=1;id_valid<=0;parent<=0;role_samples<=0;
                                    end else id_valid<=!error;
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
