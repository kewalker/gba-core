// GBA legacy sound. All dividers advance on native 16.78 MHz cycles, never
// on CPU instruction/transfer completion. MMIO remains in the bus clock domain.
module gba_psg (
    input wire clk, reset, cycle_enable, master_enable, power_off,
`ifdef GBK_SAVESTATE
    input wire state_hold,state_write,
    input wire [4:0] state_addr,
    input wire [31:0] state_wdata,
    output wire state_valid,
    output reg [31:0] state_rdata,
`endif
    input wire bus_write,
    input wire [31:0] addr, bits_in, mask,
    output logic [31:0] rdata,
    output wire [3:0] active,
    output wire [19:0] channel_samples
);
    logic [31:0] regs [0:7];
    logic [1:0] divider;
    logic [12:0] frame_count;
    logic [2:0] frame_step;
`ifdef GBK_SAVESTATE
    wire state_frozen=state_hold===1'b1;
    wire state_config_write=state_frozen && state_write && state_addr<8;
    wire [31:0] config_mask=state_config_write ? 32'hffffffff : mask;
    wire [31:0] config_data=state_config_write ? state_wdata : bits_in;
`endif
    wire tick = cycle_enable && divider==3
`ifdef GBK_SAVESTATE
        && !state_frozen
`endif
    ;
    wire frame_tick = tick && frame_count==8191;
    wire length_tick = frame_tick && !frame_step[0];
    wire sweep_tick = frame_tick && frame_step[1:0]==2;
    wire envelope_tick = frame_tick && frame_step==7;
`ifdef GBK_SAVESTATE
    wire [2:0] reg_index=state_config_write ? state_addr[2:0] : addr[4:2];
    wire reg_write=state_config_write || (!state_frozen && bus_write && addr[15:5]==11'h003 && master_enable);
    wire [31:0] shared_register_read=regs[state_frozen && state_addr<8 ? state_addr[2:0] : reg_index];
`else
    wire [2:0] reg_index=addr[4:2];
    wire reg_write=bus_write && addr[15:5]==11'h003 && master_enable;
`endif
    // Merge each register locally, avoiding a wide readback mux in every
    // write/trigger path on this nearly full FPGA.
    wire [31:0] updated [0:7];
    genvar word_index;
    generate for(word_index=0;word_index<8;word_index=word_index+1) begin : register_merge
`ifdef GBK_SAVESTATE
        assign updated[word_index]=(regs[word_index] & ~config_mask) | (config_data & config_mask);
`else
        assign updated[word_index]=(regs[word_index] & ~mask) | (bits_in & mask);
`endif
    end endgenerate
    logic [5:0] wave_position;
    wire wave_bank=regs[4][6] ^ (regs[4][5] && wave_position[5]);
`ifdef GBK_SAVESTATE
    wire state_wave_access=state_frozen && state_addr>=20 && state_addr<28;
    wire state_wave_write=state_wave_access && state_write;
    wire [2:0] cpu_wave_index=state_wave_access ? 3'(state_addr-20) : {!wave_bank,addr[3:2]};
    wire wave_write=(state_wave_write || (!state_frozen && bus_write && addr[15:4]==12'h009)) && !reset;
    wire [31:0] wave_write_data=state_wave_write ? state_wdata : bits_in;
    wire [3:0] wave_byteena=state_wave_write ? 4'hf : {mask[24],mask[16],mask[8],mask[0]};
    reg [4:0] last_state_addr;
    reg wave_state_ready;
    always @(posedge clk)begin
        if(reset || !state_frozen)begin last_state_addr<=0;wave_state_ready<=0;end
        else begin last_state_addr<=state_addr;wave_state_ready<=state_addr==last_state_addr;end
    end
    assign state_valid=!reset && state_frozen && (state_addr<20 ||
        (state_wave_access && wave_state_ready && last_state_addr==state_addr));
    wire [31:0] channel_state[0:3];
    wire [22:0] period_state[0:3];
    wire [22:0] noise_reload_state;
    wire [14:0] noise_lfsr_state;
    wire [21:0] sweep_state;
    always @*begin
        state_rdata=0;
        if(state_valid)begin
            if(state_addr<8)state_rdata=shared_register_read;
            else if(state_addr==8)state_rdata={8'd0,wave_position,frame_step,frame_count,divider};
            else if(state_addr<17)state_rdata=state_addr[0] ? channel_state[(state_addr-9)>>1] : {9'd0,period_state[(state_addr-9)>>1]};
            else case(state_addr)
                17:state_rdata={9'd0,noise_reload_state};18:state_rdata={17'd0,noise_lfsr_state};
                19:state_rdata={10'd0,sweep_state};default:state_rdata=cpu_wave_word;
            endcase
        end
    end
`else
    wire [2:0] cpu_wave_index={!wave_bank,addr[3:2]};
`endif
    wire advance_wave;
    wire wave_trigger=reg_write && reg_index==5 && mask[15] && bits_in[15];
    wire [5:0] next_wave_position=
`ifdef GBK_SAVESTATE
        state_frozen ? wave_position :
`endif
        (reset || !master_enable || power_off || wave_trigger) ? 6'd0 :
        advance_wave ? (wave_position[4:0]==31 && !regs[4][5] ? 6'd0 : wave_position+6'd1) : wave_position;
    wire [31:0] next_wave_control=reg_write && reg_index==4 ? updated[4] : regs[4];
    wire next_wave_bank=next_wave_control[6] ^ (next_wave_control[5] && next_wave_position[5]);
    // Both reads are synchronous, allowing a true dual-port M10K. The CPU
    // already samples I/O on the following bus clock. Prefetch the playback
    // word for the next oscillator position so digit timing stays unchanged.
    logic [31:0] wave_word, cpu_wave_word;
`ifdef GBK_SIM
    logic [31:0] wave_ram [0:7];
    integer wave_byte;
    always_ff @(posedge clk) begin
`ifdef GBK_SAVESTATE
        if(wave_write)
            for(wave_byte=0;wave_byte<4;wave_byte=wave_byte+1)
                if(wave_byteena[wave_byte])wave_ram[cpu_wave_index][wave_byte*8+:8]<=wave_write_data[wave_byte*8+:8];
`else
        if(bus_write && addr[15:4]==12'h009 && !reset)
            for(wave_byte=0;wave_byte<4;wave_byte=wave_byte+1)
                if(mask[wave_byte*8])
                    wave_ram[cpu_wave_index][wave_byte*8+:8]<=bits_in[wave_byte*8+:8];
`endif
        cpu_wave_word<=wave_ram[cpu_wave_index];
    end
    always_ff @(posedge clk)
        wave_word<=wave_ram[{next_wave_bank,next_wave_position[4:3]}];
`else
    // Explicit primitive: inference otherwise leaves this tiny dual-read
    // array in registers, even with a RAM-style attribute.
    altsyncram wave_storage (
        .address_a(cpu_wave_index), .address_b({next_wave_bank,next_wave_position[4:3]}),
`ifdef GBK_SAVESTATE
        .clock0(clk),.clock1(clk),.data_a(wave_write_data),.data_b(32'd0),
        .wren_a(wave_write),.wren_b(1'b0),.q_a(cpu_wave_word),.q_b(wave_word),.byteena_a(wave_byteena),
`else
        .clock0(clk), .clock1(clk), .data_a(bits_in), .data_b(32'd0),
        .wren_a(bus_write && addr[15:4]==12'h009 && !reset), .wren_b(1'b0),
        .q_a(cpu_wave_word), .q_b(wave_word), .byteena_a({mask[24],mask[16],mask[8],mask[0]}),
`endif
        .byteena_b(4'b1111), .rden_a(1'b1), .rden_b(1'b1),
        .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
        .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0), .addressstall_b(1'b0), .eccstatus()
    );
    defparam wave_storage.operation_mode="BIDIR_DUAL_PORT";
    defparam wave_storage.intended_device_family="Cyclone V";
    defparam wave_storage.ram_block_type="M10K";
    defparam wave_storage.lpm_type="altsyncram";
    defparam wave_storage.width_a=32, wave_storage.width_b=32;
    defparam wave_storage.widthad_a=3, wave_storage.widthad_b=3;
    defparam wave_storage.numwords_a=8, wave_storage.numwords_b=8;
    defparam wave_storage.width_byteena_a=4, wave_storage.width_byteena_b=4;
    defparam wave_storage.address_reg_b="CLOCK1";
    defparam wave_storage.outdata_reg_a="UNREGISTERED", wave_storage.outdata_reg_b="UNREGISTERED";
    defparam wave_storage.read_during_write_mode_mixed_ports="DONT_CARE";
`endif
    wire [4:0] nibble_shift={wave_position[2:1],3'b0}+
        (wave_position[0] ? 5'd0 : 5'd4);
    wire [3:0] wave_digit=4'(wave_word >> nibble_shift);
    integer i;
    always_ff @(posedge clk) begin
        // Wave RAM survives master disable; it has no reset port.
        if(reset ||
`ifdef GBK_SAVESTATE
            (!state_frozen && (!master_enable || power_off))
`else
            !master_enable || power_off
`endif
        ) begin
            for(i=0;i<8;i=i+1) regs[i]<=0;
            divider<=0; frame_count<=0; frame_step<=0;
        end else begin
`ifdef GBK_SAVESTATE
            if(state_frozen)begin
                if(state_write && state_addr==8)begin divider<=state_wdata[1:0];frame_count<=state_wdata[14:2];frame_step<=state_wdata[17:15];end
            end else begin
`endif
            if(cycle_enable) divider<=divider+1'b1;
            if(tick) begin
                frame_count<=frame_count+1'b1;
                if(frame_tick) frame_step<=frame_step+1'b1;
            end
`ifdef GBK_SAVESTATE
            end
`endif
            if(reg_write) begin
                case(reg_index)
                    0:regs[0]<=updated[0] & 32'hffff007f;
                    1:regs[1]<=updated[1] & 32'h000047ff;
                    2:regs[2]<=updated[2] & 32'h0000ffff;
                    3:regs[3]<=updated[3] & 32'h000047ff;
                    4:regs[4]<=updated[4] & 32'he0ff00e0;
                    5:regs[5]<=updated[5] & 32'h000047ff;
                    6:regs[6]<=updated[6] & 32'h0000ff3f;
                    7:regs[7]<=updated[7] & 32'h000040ff;
                endcase
            end
        end
    end
    always_comb begin
        rdata=0;
`ifdef GBK_SAVESTATE
        if(addr[15:5]==11'h003)begin
            case(reg_index)
                0:rdata=shared_register_read & 32'hffc0007f;
                1,3,5:rdata=shared_register_read & 32'h00004000;
                2:rdata=shared_register_read & 32'h0000ffc0;
                4:rdata=shared_register_read & 32'he00000e0;
                6:rdata=shared_register_read & 32'h0000ff00;
                7:rdata=shared_register_read & 32'h000040ff;
            endcase
        end else if(addr[15:4]==12'h009)rdata=cpu_wave_word;
`else
        if(addr[15:5]==11'h003) begin
            case(reg_index)
                0:rdata=regs[0] & 32'hffc0007f;
                1,3,5:rdata=regs[reg_index] & 32'h00004000;
                2:rdata=regs[2] & 32'h0000ffc0;
                4:rdata=regs[4] & 32'he00000e0;
                6:rdata=regs[6] & 32'h0000ff00;
                7:rdata=regs[7] & 32'h000040ff;
            endcase
        end else if(addr[15:4]==12'h009) rdata=cpu_wave_word;
`endif
    end
    genvar c;
    generate for(c=0;c<4;c=c+1) begin : channels
        localparam integer ENV_INDEX = c==0 ? 0 : c==1 ? 2 : c==2 ? 4 : 6;
        localparam integer ENV_SHIFT = (c==0 || c==2) ? 16 : 0;
        localparam integer FREQ_INDEX = c*2+1;
        wire [15:0] env_reg=16'(regs[ENV_INDEX] >> ENV_SHIFT);
        wire [15:0] freq_reg=regs[FREQ_INDEX][15:0];
        wire env_write=reg_write && reg_index==ENV_INDEX;
        wire freq_write=reg_write && reg_index==FREQ_INDEX;
        wire [15:0] new_env=16'(updated[ENV_INDEX] >> ENV_SHIFT);
        wire [15:0] new_frequency=updated[FREQ_INDEX][15:0];
        wire trigger=freq_write && mask[15] && bits_in[15];
        wire dac_on=c==2 ? regs[4][7] : |env_reg[15:11];
        logic enabled;
        logic [8:0] length_count;
        logic [3:0] volume, envelope_count;
        logic [2:0] phase;
        localparam integer COUNTER_BITS=c==3 ? 23 : c==2 ? 13 : 14;
        logic [COUNTER_BITS-1:0] period_count;
        logic [22:0] noise_reload;
        logic [14:0] lfsr;
        logic [10:0] sweep_frequency, sweep_shadow;
        logic [3:0] sweep_count;
        logic sweep_enabled, sweep_negated;
`ifdef GBK_SAVESTATE
        assign channel_state[c]={5'd0,(c==0 ? sweep_negated : 1'b0),(c==0 ? sweep_enabled : 1'b0),
            (c==0 ? sweep_count : 4'd0),(c==2 ? 3'd0 : phase),(c==2 ? 4'd0 : envelope_count),
            (c==2 ? 4'd0 : volume),length_count,enabled};
        assign period_state[c]=23'(period_count);
        if(c==0)assign sweep_state={sweep_shadow,sweep_frequency};
        if(c==3)begin assign noise_reload_state=noise_reload;assign noise_lfsr_state=lfsr;end
`endif
        wire [6:0] sweep=regs[0][6:0];
        wire [10:0] frequency=c==0 ? sweep_frequency : freq_reg[10:0];
        wire [11:0] sweep_delta={1'b0,sweep_shadow} >> sweep[2:0];
        wire [11:0] sweep_result=sweep[3] ? {1'b0,sweep_shadow}-sweep_delta :
            {1'b0,sweep_shadow}+sweep_delta;
        wire [11:0] next_delta=sweep_result >> sweep[2:0];
        wire [12:0] next_sweep={1'b0,sweep_result}+{1'b0,next_delta};
        wire [22:0] period = c==3 ? noise_reload :
            ((23'd2048-{12'd0,frequency}) << (c==2 ? 1 : 2));
        wire [22:0] trigger_period = c==3 ?
            ((new_frequency[2:0]==0 ? 23'd8 : {20'd0,new_frequency[2:0]} << 4) << new_frequency[7:4]) :
            ((23'd2048-{12'd0,new_frequency[10:0]}) << (c==2 ? 1 : 2));
        wire length_write=env_write && (c==2 ? |mask[23:16] : |(mask >> ENV_SHIFT & 32'h3f));
        // Hardware clocks length immediately if enabled between length steps.
        wire extra_length=freq_write && !freq_reg[14] && new_frequency[14] && frame_step[0];
        wire clock_length=(length_tick && freq_reg[14] || extra_length) && length_count!=0;
        wire [8:0] initial_length=c==2 ? 9'd256-{1'b0,new_env[7:0]} :
            9'd64-{3'd0,new_env[5:0]};
        assign active[c]=enabled && master_enable;
        if(c==2) assign advance_wave=tick && enabled && period_count<=1;
        always_ff @(posedge clk) begin
            if(reset ||
`ifdef GBK_SAVESTATE
                (!state_frozen && (!master_enable || power_off))
`else
                !master_enable || power_off
`endif
            ) begin
                enabled<=0; length_count<=0; volume<=0; envelope_count<=0;
                phase<=0; period_count<=0; lfsr<=15'h7fff;
                noise_reload<=8;
                sweep_frequency<=0; sweep_shadow<=0; sweep_count<=0; sweep_enabled<=0; sweep_negated<=0;
                if(c==2) wave_position<=0;
`ifdef GBK_SAVESTATE
            end else if(state_frozen)begin
                if(state_write)begin
                    if(state_addr==9+c*2)begin
                        enabled<=state_wdata[0];length_count<=state_wdata[9:1];
                        if(c!=2)begin volume<=state_wdata[13:10];envelope_count<=state_wdata[17:14];phase<=state_wdata[20:18];end
                        if(c==0)begin sweep_count<=state_wdata[24:21];sweep_enabled<=state_wdata[25];sweep_negated<=state_wdata[26];end
                    end
                    if(state_addr==10+c*2)period_count<=COUNTER_BITS'(state_wdata);
                    if(c==2 && state_addr==8)wave_position<=state_wdata[23:18];
                    if(c==3 && state_addr==17)noise_reload<=state_wdata[22:0];
                    if(c==3 && state_addr==18)lfsr<=state_wdata[14:0];
                    if(c==0 && state_addr==19)begin sweep_frequency<=state_wdata[10:0];sweep_shadow<=state_wdata[21:11];end
                end
`endif
            end else begin
                if(!dac_on) enabled<=0;
                if(c==3 && freq_write) noise_reload<=trigger_period;
                if(tick && enabled) begin
                    if(period_count<=1) begin
                        period_count<=period;
                        phase<=phase+1'b1;
                        if(c==2) begin
                            if(wave_position[4:0]==31 && !regs[4][5]) wave_position<=0;
                            else wave_position<=wave_position+1'b1;
                        end
                        if(c==3 && freq_reg[7:4]<14) begin
                            lfsr<={lfsr[0]^lfsr[1],lfsr[14:1]};
                            if(freq_reg[3]) lfsr[6]<=lfsr[0]^lfsr[1];
                        end
                    end else period_count<=period_count-1'b1;
                end
                if(clock_length) begin
                    length_count<=length_count-1'b1;
                    if(length_count==1) enabled<=0;
                end
                if(c!=2 && envelope_tick && env_reg[10:8]!=0) begin
                    if(envelope_count>1) envelope_count<=envelope_count-1'b1;
                    else begin
                        envelope_count<={1'b0,env_reg[10:8]};
                        if(env_reg[11] && volume<15) volume<=volume+1'b1;
                        if(!env_reg[11] && volume>0) volume<=volume-1'b1;
                    end
                end
                if(c==0) begin
                    if(sweep_tick) begin
                        if(sweep_count>1) sweep_count<=sweep_count-1'b1;
                        else begin
                            sweep_count<=sweep[6:4]==0 ? 4'd8 : {1'b0,sweep[6:4]};
                            if(sweep_enabled && sweep[6:4]!=0 && sweep[2:0]!=0) begin
                                if(sweep_result[11]) enabled<=0;
                                else begin
                                    sweep_frequency<=sweep_result[10:0];
                                    sweep_shadow<=sweep_result[10:0];
                                    if(sweep[3]) sweep_negated<=1;
                                    else if(next_sweep>2047) enabled<=0;
                                end
                            end
                        end
                    end
                    if(reg_write && reg_index==0 && mask[3] && !bits_in[3] && sweep_negated)
                        enabled<=0;
                    if(freq_write) sweep_frequency<=new_frequency[10:0];
                end
                if(length_write) length_count<=initial_length;
                if(env_write && (c==2 ? mask[7] && !bits_in[7] :
                    !(|new_env[15:11]))) enabled<=0;
                if(trigger) begin
                    enabled<=dac_on;
                    period_count<=trigger_period;
                    if(length_count==0 || (clock_length && length_count==1)) length_count<=
                        (c==2 ? 9'd256 : 9'd64)-(new_frequency[14] && frame_step[0] ? 9'd1 : 9'd0);
                    if(c!=2) begin
                        volume<=env_reg[15:12];
                        envelope_count<=env_reg[10:8]==0 ? 4'd8 : {1'b0,env_reg[10:8]};
                    end
                    if(c==2) wave_position<=0;
                    if(c==3) lfsr<=15'h7fff;
                    if(c==0) begin
                        sweep_shadow<=new_frequency[10:0];
                        sweep_count<=sweep[6:4]==0 ? 4'd8 : {1'b0,sweep[6:4]};
                        sweep_enabled<=|sweep[6:4] || |sweep[2:0];
                        sweep_negated<=sweep[3] && |sweep[2:0];
                        if(sweep[2:0]!=0 && !sweep[3] &&
                            ({1'b0,new_frequency[10:0]}+({1'b0,new_frequency[10:0]} >> sweep[2:0]))>2047)
                            enabled<=0;
                    end
                end
            end
        end
        logic high_phase;
        logic signed [6:0] wave_level;
        // Every channel spans -15..15; carry no redundant upper bits into
        // the stereo summer and gain multipliers.
        logic signed [4:0] channel_sample;
        assign channel_samples[c*5+:5]=channel_sample;
        always_comb begin
            case(env_reg[7:6])
                0:high_phase=phase==7;
                1:high_phase=phase>=6;
                2:high_phase=phase>=4;
                3:high_phase=phase<6;
            endcase
            wave_level=$signed({2'b0,wave_digit,1'b0})-7'sd15;
            if(env_reg[15]) wave_level=(wave_level*7'sd3) >>> 2;
            else case(env_reg[14:13])
                0:wave_level=0;
                1:wave_level=wave_level;
                2:wave_level=wave_level >>> 1;
                3:wave_level=wave_level >>> 2;
            endcase
            channel_sample=0;
            if(enabled && dac_on && master_enable) begin
                if(c==2) channel_sample=wave_level;
                else if(c==3) channel_sample=lfsr[0] ? -$signed({3'b0,volume}) : $signed({3'b0,volume});
                else channel_sample=high_phase ? $signed({3'b0,volume}) : -$signed({3'b0,volume});
            end
        end
    end endgenerate
endmodule
