// Timer-clocked Direct Sound A/B and native-clocked legacy PSG channels.
// Bus writes are single accepted transactions, with narrow data right justified.
module gba_apu #(parameter bit CYCLE_ENABLE=0) (
    input wire clk, reset,
`ifdef GBK_SAVESTATE
    input wire state_hold,state_write,
    input wire [5:0] state_addr,
    input wire [31:0] state_wdata,
    output reg state_valid,
    output reg [31:0] state_rdata,
`endif
    input wire cycle_enable,
    input wire [1:0] timer_overflow,
    input wire bus_write,
    input wire [31:0] addr, wdata,
    input wire [1:0] size,
    output logic [31:0] rdata,
    output wire [1:0] fifo_request,
    output logic signed [15:0] audio_left, audio_right
);
    logic [15:0] soundcnt_l, soundcnt_h;
    logic master_enable;
    logic [4:0] read_ptr[0:1], write_ptr[0:1];
    logic [5:0] level[0:1];
    logic signed [7:0] sample[0:1];
`ifdef GBK_SAVESTATE
    wire state_frozen=state_hold===1'b1;
    wire state_psg_valid;
    wire [31:0] state_psg_rdata;
    reg [31:0] state_fifo_data[0:1];
    reg [5:0] last_state_addr;
    reg fifo_state_ready;
    wire [1:0] fifo_warm;
    reg [1:0] resume_warm_count;
    always @(posedge clk)begin
        if(reset || !state_frozen)begin last_state_addr<=0;fifo_state_ready<=0;end
        else begin last_state_addr<=state_addr;fifo_state_ready<=!state_write && state_addr==last_state_addr;end
    end
    always @(posedge clk)begin
        if(reset || !state_frozen || state_addr!=63 || state_write)resume_warm_count<=0;
        else if(resume_warm_count!=3)resume_warm_count<=resume_warm_count+1'b1;
    end
    always @*begin
        state_valid=!reset && state_frozen && (state_addr<4 ||
            (state_addr<20 && fifo_state_ready && last_state_addr==state_addr));state_rdata=0;
        if(state_valid)case(state_addr)
            0:state_rdata={soundcnt_h,soundcnt_l};
            1:state_rdata={31'd0,master_enable};
            2:state_rdata={8'd0,sample[0],level[0],write_ptr[0],read_ptr[0]};
            3:state_rdata={8'd0,sample[1],level[1],write_ptr[1],read_ptr[1]};
            default:state_rdata=state_addr<12 ? state_fifo_data[0] : state_fifo_data[1];
        endcase
        else if(!reset && state_frozen && state_addr==63)begin
            state_valid=1;state_rdata={31'd0,(&fifo_warm) && resume_warm_count==3};
        end else if(state_frozen && state_addr>=32)begin state_valid=state_psg_valid;state_rdata=state_psg_rdata;end
    end
`endif
    wire [31:0] mask = size==0 ? 32'hff << (addr[1:0]*8) :
        size==1 ? 32'hffff << (addr[1]*16) : 32'hffffffff;
    wire [31:0] bits_in = size==2 ? wdata : wdata << (addr[1:0]*8);
    wire control_write = bus_write && addr[15:2]==14'h20
`ifdef GBK_SAVESTATE
        && !state_frozen
`endif
    ;
    wire [31:0] merged = ({soundcnt_h,soundcnt_l} & ~mask) | (bits_in & mask);
    wire disable_write = bus_write && addr[15:2]==14'h21 && mask[7] && !bits_in[7]
`ifdef GBK_SAVESTATE
        && !state_frozen
`endif
    ;
    wire [2:0] write_bytes = size==0 ? 3'd1 : size==1 ? 3'd2 : 3'd4;
    wire [31:0] psg_rdata;
    wire [3:0] psg_active;
    wire [19:0] psg_samples;
    gba_psg psg(.clk,.reset,.cycle_enable(!CYCLE_ENABLE || cycle_enable),
`ifdef GBK_SAVESTATE
        .state_hold,.state_write(state_write && state_addr>=32),.state_addr(state_addr[4:0]),.state_wdata,
        .state_valid(state_psg_valid),.state_rdata(state_psg_rdata),
`endif
        .master_enable,.power_off(disable_write),.bus_write,.addr,.bits_in,.mask,
        .rdata(psg_rdata),.active(psg_active),.channel_samples(psg_samples));
    genvar c,bank;
    generate for(c=0;c<2;c=c+1) begin : channels
        wire fifo_write = bus_write && addr[15:2]==(14'h28+c)
`ifdef GBK_SAVESTATE
            && !state_frozen
`endif
        ;
        wire clear_fifo = disable_write ||
            (control_write && mask[27+c*4] && bits_in[27+c*4]);
        wire pop = master_enable && timer_overflow[soundcnt_h[10+c*4]] && level[c]!=0
`ifdef GBK_SAVESTATE
            && !state_frozen
`endif
        ;
        // Exact hardware word-buffer under/overflow behaviour is a later audit.
        wire push = fifo_write && (level[c]+{3'b0,write_bytes} <= 6'd32);
        // Four byte banks each have one write port. A flat byte array with
        // four independently addressed writes synthesizes a costly crossbar.
        // Banking preserves arbitrary byte/halfword writes and pointer wrap.
        wire [31:0] heads;
`ifdef GBK_SAVESTATE
        wire state_fifo_access=state_frozen && state_addr>=4+c*8 && state_addr<12+c*8;
        wire state_fifo_write=state_fifo_access && state_write;
        // Read ahead to the pointer that will be live after this edge. This
        // preserves the original sample cycle with a synchronous RAM output.
        wire [4:0] prefetched_read_ptr=clear_fifo ? 5'd0 : read_ptr[c]+5'(pop);
        wire [2:0] fifo_read_slot=state_fifo_access ? 3'(state_addr-4) : prefetched_read_ptr[4:2];
        reg [2:0] captured_read_slot;
        always @(posedge clk)captured_read_slot<=fifo_read_slot;
        assign fifo_warm[c]=!state_fifo_access && captured_read_slot==read_ptr[c][4:2];
        wire [1:0] fifo_write_lane=state_fifo_write ? 2'd0 : write_ptr[c][1:0];
        wire [2:0] fifo_write_slot=state_fifo_write ? 3'(state_addr-4) : write_ptr[c][4:2];
        wire [31:0] fifo_write_data=state_fifo_write ? state_wdata : wdata;
        // Register raw state reads just like the existing sample consumer.
        // Exposing heads asynchronously prevents the FPGA from inferring
        // synchronous FIFO RAMs and expands the banks into hundreds of FFs.
        always @(posedge clk)state_fifo_data[c]<=heads;
`endif
        for(bank=0;bank<4;bank=bank+1) begin : banks
`ifdef GBK_SAVESTATE
            (* ramstyle="M10K, no_rw_check" *)
`endif
            logic [7:0] data[0:7];
`ifdef GBK_SAVESTATE
            wire [1:0] distance=2'(bank)-fifo_write_lane;
            wire [2:0] slot=fifo_write_slot+3'(bank<fifo_write_lane);
            wire bank_write=!reset && (state_fifo_write || (push && !clear_fifo && {1'b0,distance}<write_bytes));
            reg [7:0] read_data,forward_data;
            reg [2:0] forward_slot;
            reg forward_write;
            // A push into an empty FIFO may coincide with prefetching that
            // word. Forward the byte explicitly rather than depending on the
            // device's read-during-write mode. No added RAM port is needed.
            assign heads[bank*8+:8]=forward_write && forward_slot==captured_read_slot ? forward_data : read_data;
            always_ff @(posedge clk)begin
                read_data<=data[fifo_read_slot];
                forward_write<=bank_write;
                if(bank_write)begin
                    data[slot]<=fifo_write_data[distance*8+:8];
                    forward_data<=fifo_write_data[distance*8+:8];forward_slot<=slot;
                end
            end
`else
            wire [1:0] distance=2'(bank)-write_ptr[c][1:0];
            wire [2:0] slot=write_ptr[c][4:2]+3'(bank<write_ptr[c][1:0]);
            assign heads[bank*8+:8]=data[read_ptr[c][4:2]];
            always_ff @(posedge clk)
                if(push && !reset && !clear_fifo && {1'b0,distance}<write_bytes)
                    data[slot]<=wdata[distance*8+:8];
`endif
        end
        assign fifo_request[c] = master_enable && level[c]<=16;
        always_ff @(posedge clk) begin
            if(reset || clear_fifo) begin
                read_ptr[c]<=0;write_ptr[c]<=0;level[c]<=0;sample[c]<=0;
`ifdef GBK_SAVESTATE
            end else if(state_frozen)begin
                if(state_write && state_addr==2+c)begin
                    read_ptr[c]<=state_wdata[4:0];write_ptr[c]<=state_wdata[9:5];
                    level[c]<=state_wdata[15:10];sample[c]<=state_wdata[23:16];
                end
`endif
            end else begin
                if(push) begin
                    write_ptr[c]<=write_ptr[c]+write_bytes;
                end
                if(pop) begin
                    sample[c]<=heads[read_ptr[c][1:0]*8+:8];
                    read_ptr[c]<=read_ptr[c]+1'b1;
                end
                level[c]<=level[c]+(push ? {3'b0,write_bytes} : 6'd0)-(pop ? 6'd1 : 6'd0);
            end
        end
    end endgenerate
    always_ff @(posedge clk) begin
        if(reset) begin soundcnt_l<=0;soundcnt_h<=0;master_enable<=0;end
`ifdef GBK_SAVESTATE
        else if(state_frozen)begin
            if(state_write && state_addr==0)begin soundcnt_l<=state_wdata[15:0] & 16'hff77;soundcnt_h<=state_wdata[31:16] & 16'h770f;end
            if(state_write && state_addr==1)master_enable<=state_wdata[0];
        end
`endif
        else begin
            if(control_write) begin
                soundcnt_l<=master_enable ? merged[15:0] & 16'hff77 : 16'd0;
                soundcnt_h<=merged[31:16] & 16'h770f;
            end
            if(bus_write && addr[15:2]==14'h21 && mask[7]) master_enable<=bits_in[7];
            if(disable_write) soundcnt_l<=0;
        end
    end
    always_comb begin
        rdata=psg_rdata;
        case(addr[15:2])
            14'h20:rdata={soundcnt_h,soundcnt_l};
            14'h21:rdata={24'd0,master_enable,3'd0,psg_active};
            default:rdata=psg_rdata;
        endcase
    end
    // Full-volume PCM contributes +/-256 to the GBA's signed 10-bit mix.
    logic signed [10:0] pcm_a,pcm_b;
    logic signed [10:0] mix_l,mix_r;
    logic signed [9:0] psg_l,psg_r;
    logic signed [6:0] psg_sum_l,psg_sum_r;
    // Use the available hard multipliers instead of scarce general logic.
    (* multstyle="dsp" *) wire signed [11:0] psg_gain_l=
        psg_sum_l*$signed({1'b0,soundcnt_l[6:4]}+5'd1);
    (* multstyle="dsp" *) wire signed [11:0] psg_gain_r=
        psg_sum_r*$signed({1'b0,soundcnt_l[2:0]}+5'd1);
    integer channel;
    function automatic signed [15:0] pcm16(input signed [10:0] value);
        if(value>511) pcm16=16'sh7fc0;
        else if(value< -512) pcm16=16'sh8000;
        else pcm16={value[9:0],6'b0};
    endfunction
    always_comb begin
        psg_sum_l=0;psg_sum_r=0;
        for(channel=0;channel<4;channel=channel+1) begin
            if(soundcnt_l[12+channel]) psg_sum_l=psg_sum_l+$signed(psg_samples[channel*5+:5]);
            if(soundcnt_l[8+channel]) psg_sum_r=psg_sum_r+$signed(psg_samples[channel*5+:5]);
        end
    end
    always_comb begin
        pcm_a=$signed({{3{sample[0][7]}},sample[0]}) <<< 1;
        pcm_b=$signed({{3{sample[1][7]}},sample[1]}) <<< 1;
        if(!soundcnt_h[2]) pcm_a=pcm_a >>> 1;
        if(!soundcnt_h[3]) pcm_b=pcm_b >>> 1;
        psg_l=psg_gain_l[9:0];psg_r=psg_gain_r[9:0];
        case(soundcnt_h[1:0])
            0:begin psg_l=psg_l >>> 2;psg_r=psg_r >>> 2;end
            1:begin psg_l=psg_l >>> 1;psg_r=psg_r >>> 1;end
            default:begin end
        endcase
        // Six-channel worst case is -992..988, safely inside eleven bits.
        mix_l=(soundcnt_h[9] ? pcm_a : 11'sd0)+
            (soundcnt_h[13] ? pcm_b : 11'sd0)+psg_l;
        mix_r=(soundcnt_h[8] ? pcm_a : 11'sd0)+
            (soundcnt_h[12] ? pcm_b : 11'sd0)+psg_r;
        audio_left=master_enable ? pcm16(mix_l) : 16'd0;
        audio_right=master_enable ? pcm16(mix_r) : 16'd0;
    end
endmodule

