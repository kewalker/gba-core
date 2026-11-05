// The implementation runs faster than the GBA. Charge emulated bus/internal
// cycles, consume that debt at 16.777216 MHz, and bound execution lookahead.
// 16.777216 / 39.936 MHz = 2048/4875 exactly.
module gba_cycle_scheduler #(
    parameter integer TICK_NUMERATOR=2048,TICK_DENOMINATOR=4875,
    parameter integer LOOKAHEAD=4,
    parameter bit REGION_PROFILE=0
) (
    input wire clk,reset,
`ifdef GBK_FAST_FORWARD
    input wire fast_forward,
    input wire cpu_halted,
    input wire [1:0] fast_forward_speed,
`endif
`ifdef GBK_SAVESTATE
    // Assert only after CPU/DMA/memory drain. Host wall time is not guest time.
    input wire state_hold,state_write,
    input wire [3:0] state_addr,
    input wire [31:0] state_wdata,
    output wire state_valid,
    output reg [31:0] state_rdata,
`endif
    input wire cpu_req,cpu_ready,cpu_write,cpu_code,cpu_thumb,cpu_exec,cpu_irq,cpu_refill,
    input wire [31:0] cpu_addr,
    input wire [1:0] cpu_size,
    input wire [3:0] cpu_internal_cycles,
    input wire dma_active,dma_access,dma_write,
    input wire [31:0] dma_addr,
    input wire [1:0] dma_size,
    input wire [15:0] waitcnt,
    output wire gba_tick,cpu_allow,dma_allow,
    output wire [287:0] profile
);
    localparam PHASE_BITS=$clog2(TICK_DENOMINATOR);
    reg [PHASE_BITS-1:0] phase;
`ifdef GBK_FAST_FORWARD
    // Shared fractional phase, unchanged physical clocks and guest charges.
    // Max consumes one guest tick per physical clock (about 2.38x here).
    // Unknown/invalid preference defaults to the original 2x behavior.
    wire [PHASE_BITS-1:0] fast_increment=fast_forward_speed===2'd0 ? (3*TICK_NUMERATOR)/2 :
        fast_forward_speed===2'd2 ? (max_wait ? (TICK_DENOMINATOR+1)/2 : TICK_DENOMINATOR) : 2*TICK_NUMERATOR;
    wire [PHASE_BITS-1:0] tick_increment=fast_forward===1'b1 ? fast_increment : TICK_NUMERATOR;
    wire [PHASE_BITS-1:0] tick_threshold=TICK_DENOMINATOR-tick_increment;
`endif
`ifdef GBK_FAST_FORWARD
    // Private research only. Physical memory clocks continue; idle/HALT tick.
    wire max_wait=fast_forward===1'b1 && fast_forward_speed===2'd2 &&
        accounted_debt==0 && (cpu_halted===1'b0 || dma_active);
`endif
    reg [11:0] debt;
    reg [11:0] maximum_debt;
`ifdef GBK_SAVESTATE
    wire state_frozen=state_hold===1'b1;
    assign state_valid=!reset && state_frozen && state_addr<7;
`ifdef GBK_FAST_FORWARD
    assign gba_tick=!state_frozen && phase>=tick_threshold;
`else
    assign gba_tick=!state_frozen && phase>=TICK_DENOMINATOR-TICK_NUMERATOR;
`endif
`else
`ifdef GBK_FAST_FORWARD
    assign gba_tick=phase>=tick_threshold;
`else
    assign gba_tick=phase>=TICK_DENOMINATOR-TICK_NUMERATOR;
`endif
`endif
    reg [5:0] pending_cpu_charge,pending_dma_charge;
    wire [12:0] accounted_debt={1'b0,debt}+pending_cpu_charge+pending_dma_charge;
    // Include the accounting pipeline in the budget so retiming never
    // grants extra execution credit or drops a completed transfer's cost.
`ifdef GBK_SAVESTATE
    assign cpu_allow=!state_frozen && accounted_debt<LOOKAHEAD;
    assign dma_allow=!state_frozen && accounted_debt<LOOKAHEAD;
`else
    assign cpu_allow=accounted_debt<LOOKAHEAD;
    assign dma_allow=accounted_debt<LOOKAHEAD;
`endif
    wire cpu_access=cpu_req && cpu_ready;
    wire [1:0] access_size=cpu_code ? (cpu_thumb ? 2'd1 : 2'd2) : cpu_size;
    reg cpu_history_valid,dma_read_valid,dma_write_valid,dma_previous;
    reg [31:0] cpu_next,dma_read_next,dma_write_next;
    reg cpu_previous_write;
    reg refill_pending;
    wire cpu_sequential=cpu_history_valid && cpu_addr==cpu_next &&
        cpu_addr[16:0]!=0 && cpu_write==cpu_previous_write;
    wire dma_sequential=dma_addr[16:0]!=0 &&
        (dma_write ? dma_write_valid && dma_addr==dma_write_next : dma_read_valid && dma_addr==dma_read_next);

    function automatic [4:0] nonseq_wait(input [1:0] setting);
        case(setting)
            0:nonseq_wait=4;1:nonseq_wait=3;2:nonseq_wait=2;3:nonseq_wait=8;
        endcase
    endfunction
    function automatic [5:0] bus_cycles(input [31:0] address,input [1:0] size,input sequential,input [15:0] waits);
        reg [4:0] first,following;
        begin
            first=1;following=1;
            case(address[27:24])
                2:begin first=3;following=3;end
                5,6:begin first=1;following=1;end
                // WAITCNT encodes waitstates in addition to the base
                // transfer cycle; EWRAM's three cycles already include it.
                8,9:begin first=nonseq_wait(waits[3:2])+1'b1;following=waits[4] ? 2 : 3;end
                10,11:begin first=nonseq_wait(waits[6:5])+1'b1;following=waits[7] ? 2 : 5;end
                12,13:begin first=nonseq_wait(waits[9:8])+1'b1;following=waits[10] ? 2 : 9;end
                14,15:first=nonseq_wait(waits[1:0])+1'b1;
                default:begin end
            endcase
            if(address[27:24]>=8 && address[27:24]<=13 && sequential) first=following;
            bus_cycles={1'b0,first};
            if(size==2 && (address[27:24]==2 || address[27:24]==5 || address[27:24]==6 ||
               (address[27:24]>=8 && address[27:24]<=13))) bus_cycles={1'b0,first}+following;
        end
    endfunction
    // A pipeline refill costs two extra sequential instruction fetches at
    // the destination. Charge its actual memory width/waits, not two fixed
    // FPGA or internal clocks. The next target address is available here.
    wire [5:0] refill_fetch_cycles=bus_cycles(cpu_addr,access_size,1'b1,waitcnt);
`ifdef GBK_GAMEPAK_PREFETCH
    wire [5:0] ordinary_cpu_bus_charge=cpu_access ? bus_cycles(cpu_addr,access_size,cpu_sequential && !(cpu_code && refill_pending),waitcnt)+
        (cpu_code && refill_pending ? refill_fetch_cycles*2 : 6'd0) : 6'd0;
    wire [45:0] prefetch_state;
    wire [5:0] cpu_bus_charge;
    wire prefetch_flush=refill_pending || (cpu_exec && cpu_refill) || cpu_irq || dma_active;
    wire [5:0] prefetch_opportunity=(cpu_access && !cpu_code && cpu_addr[27:24]<8 ? ordinary_cpu_bus_charge : 6'd0)+
        (cpu_exec && !cpu_refill ? {2'd0,cpu_internal_cycles} : 6'd0);
    gba_gamepak_prefetch prefetch(.clk,.reset,
`ifdef GBK_SAVESTATE
        .hold(state_frozen),.restore_low(state_write && state_valid && state_addr==2),
        .restore_high(state_write && state_valid && state_addr==3),.restore_data(state_wdata),
`else
        .hold(1'b0),.restore_low(1'b0),.restore_high(1'b0),.restore_data(32'd0),
`endif
        .state_bits(prefetch_state),.waitcnt,.flush(prefetch_flush),
        .code_access(cpu_access && cpu_code),.data_access(cpu_access && !cpu_code),.address(cpu_addr),
        .word_access(access_size==2),.ordinary_charge(ordinary_cpu_bus_charge),
        .opportunity(prefetch_opportunity),.charge(cpu_bus_charge));
`else
    wire [5:0] cpu_bus_charge=cpu_access ? bus_cycles(cpu_addr,access_size,cpu_sequential && !(cpu_code && refill_pending),waitcnt)+
        (cpu_code && refill_pending ? refill_fetch_cycles*2 : 6'd0) : 6'd0;
`endif
    wire [5:0] cpu_charge=cpu_bus_charge+(cpu_exec ? {2'd0,cpu_internal_cycles}-(cpu_refill ? 6'd2 : 6'd0) : 6'd0);
    wire [5:0] dma_charge=(dma_access ? bus_cycles(dma_addr,dma_size,dma_sequential,waitcnt) : 6'd0)+
        (dma_active && !dma_previous ? 6'd2 : 6'd0);
    wire [12:0] next_debt=accounted_debt-(gba_tick && accounted_debt!=0 ? 13'd1 : 13'd0);
    reg [31:0] native_cycles,cpu_cycles,dma_cycles,missing_cycles,instructions;
    reg [31:0] cpu_wait_clocks,throttle_clocks,dma_wait_clocks;
    reg [31:0] missing_bios,missing_ewram,missing_iwram,missing_cart;
    reg [31:0] missing_video,missing_io,missing_dma,missing_other;
    assign profile=REGION_PROFILE ?
        {native_cycles,missing_bios,missing_ewram,missing_iwram,missing_cart,
         missing_video,missing_io,missing_dma,missing_other} :
        {native_cycles,cpu_cycles,dma_cycles,missing_cycles,instructions,
         cpu_wait_clocks,throttle_clocks,dma_wait_clocks,20'd0,maximum_debt};
`ifdef GBK_SAVESTATE
    // Scheduler v1: seven words. Diagnostic lifetime counters stay monotonic;
    // native phase, accounting pipeline and sequential/refill history rewind.
    always @* begin
        state_rdata=0;
        if(state_valid)case(state_addr)
            4'd0:state_rdata=32'(phase);
            4'd1:state_rdata={20'd0,debt};
`ifdef GBK_GAMEPAK_PREFETCH
            4'd2:state_rdata={prefetch_state[19:0],pending_dma_charge,pending_cpu_charge};
            4'd3:state_rdata={prefetch_state[45:20],refill_pending,cpu_previous_write,dma_previous,dma_write_valid,dma_read_valid,cpu_history_valid};
`else
            4'd2:state_rdata={20'd0,pending_dma_charge,pending_cpu_charge};
            4'd3:state_rdata={26'd0,refill_pending,cpu_previous_write,dma_previous,dma_write_valid,dma_read_valid,cpu_history_valid};
`endif
            4'd4:state_rdata=cpu_next;
            4'd5:state_rdata=dma_read_next;
            4'd6:state_rdata=dma_write_next;
            default:state_rdata=0;
        endcase
    end
`endif
    // Partition the existing missing-cycle predicate, rather than counting
    // raw waits that can overlap native-cycle throttling. DMA has priority
    // because it owns the bus while a CPU request remains held behind it.
    wire missing_tick=gba_tick && accounted_debt==0 && (cpu_req || dma_active) && cpu_charge==0 && dma_charge==0;
    always @(posedge clk) begin
        if(reset) begin
            missing_bios<=0;missing_ewram<=0;missing_iwram<=0;missing_cart<=0;
            missing_video<=0;missing_io<=0;missing_dma<=0;missing_other<=0;
        end else if(missing_tick) begin
            if(dma_active) missing_dma<=missing_dma+1'b1;
            else case(cpu_addr[31:24])
                8'h00:missing_bios<=missing_bios+1'b1;
                8'h02:missing_ewram<=missing_ewram+1'b1;
                8'h03:missing_iwram<=missing_iwram+1'b1;
                8'h04:missing_io<=missing_io+1'b1;
                8'h05,8'h06,8'h07:missing_video<=missing_video+1'b1;
                8'h08,8'h09,8'h0a,8'h0b,8'h0c,8'h0d:missing_cart<=missing_cart+1'b1;
                default:missing_other<=missing_other+1'b1;
            endcase
        end
    end
    always @(posedge clk) begin
        if(reset) begin
            phase<=0;debt<=0;maximum_debt<=0;
            pending_cpu_charge<=0;pending_dma_charge<=0;
            cpu_history_valid<=0;dma_read_valid<=0;dma_write_valid<=0;dma_previous<=0;
            cpu_next<=0;dma_read_next<=0;dma_write_next<=0;cpu_previous_write<=0;
            refill_pending<=0;
            native_cycles<=0;cpu_cycles<=0;dma_cycles<=0;missing_cycles<=0;instructions<=0;
            cpu_wait_clocks<=0;throttle_clocks<=0;dma_wait_clocks<=0;
`ifdef GBK_SAVESTATE
        end else if(state_frozen)begin
            if(state_write && state_valid)case(state_addr)
                4'd0:phase<=PHASE_BITS'(state_wdata);
                4'd1:debt<=state_wdata[11:0];
                4'd2:begin pending_cpu_charge<=state_wdata[5:0];pending_dma_charge<=state_wdata[11:6];end
                4'd3:begin
                    cpu_history_valid<=state_wdata[0];dma_read_valid<=state_wdata[1];
                    dma_write_valid<=state_wdata[2];dma_previous<=state_wdata[3];
                    cpu_previous_write<=state_wdata[4];refill_pending<=state_wdata[5];
                end
                4'd4:cpu_next<=state_wdata;
                4'd5:dma_read_next<=state_wdata;
                4'd6:dma_write_next<=state_wdata;
                default:begin end
            endcase
`endif
        end else begin
            pending_cpu_charge<=cpu_charge;pending_dma_charge<=dma_charge;
`ifdef GBK_FAST_FORWARD
            phase<=gba_tick ? phase-tick_threshold : phase+tick_increment;
`else
            phase<=gba_tick ? phase-(TICK_DENOMINATOR-TICK_NUMERATOR) : phase+TICK_NUMERATOR;
`endif
            debt<=next_debt>4095 ? 12'hfff : next_debt[11:0];
            if(next_debt>maximum_debt) maximum_debt<=next_debt>4095 ? 12'hfff : next_debt[11:0];
            dma_previous<=dma_active;
            if(cpu_access && cpu_code) refill_pending<=0;
            if((cpu_exec && cpu_refill) || cpu_irq) refill_pending<=1;
            if(cpu_access) begin
                cpu_history_valid<=1;cpu_next<=cpu_addr+(access_size==2 ? 4 : access_size==1 ? 2 : 1);
                cpu_previous_write<=cpu_write;
            end
            if(dma_active) cpu_history_valid<=0;
            if(!dma_active) begin dma_read_valid<=0;dma_write_valid<=0;end
            else if(dma_access) begin
                if(dma_write) begin dma_write_valid<=1;dma_write_next<=dma_addr+(dma_size==2 ? 4 : 2);end
                else begin dma_read_valid<=1;dma_read_next<=dma_addr+(dma_size==2 ? 4 : 2);end
            end
            if(gba_tick) native_cycles<=native_cycles+1'b1;
            if(pending_cpu_charge!=0) cpu_cycles<=cpu_cycles+pending_cpu_charge;
            if(pending_dma_charge!=0) dma_cycles<=dma_cycles+pending_dma_charge;
            if(cpu_exec) instructions<=instructions+1'b1;
            if(cpu_req && !cpu_ready && !dma_active) cpu_wait_clocks<=cpu_wait_clocks+1'b1;
            if(!cpu_allow && !dma_active) throttle_clocks<=throttle_clocks+1'b1;
            if(dma_active && !dma_access && dma_allow) dma_wait_clocks<=dma_wait_clocks+1'b1;
            if(missing_tick)
                missing_cycles<=missing_cycles+1'b1;
        end
    end
endmodule
