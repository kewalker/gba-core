// Minimal, bus-facing ARM7TDMI execution core.
// First milestone: ARM-state data processing, branches, BX, and word loads.
// Candidate register-read sharing. Compile-time aliases preserve the exact
// disabled-feature checkpoint, while the candidate uses four shared read ports
// for mutually exclusive ARM/Thumb/transfer phases. No execution cycle is added.
`ifdef GBK_SAVESTATE
`define GBK_RF_RAW_RM shared_raw_rm
`define GBK_RF_RAW_RN shared_raw_rn
`define GBK_RF_RAW_RS shared_raw_rs
`define GBK_RF_RAW_RD shared_raw_rd
`define GBK_RF_THUMB_RS arm_rn_value
`define GBK_RF_THUMB_RD arm_rm_value
`define GBK_RF_THUMB_RO shared_raw_rs
`define GBK_RF_THUMB_IMM arm_rm_value
`define GBK_RF_THUMB_HRD arm_rm_value
`define GBK_RF_THUMB_HRS arm_rn_value
`define GBK_RF_BLOCK shared_raw_rd
`define GBK_RF_STORE shared_raw_rd
`define GBK_RF_POSTBASE shared_raw_rn
`else
`define GBK_RF_RAW_RM r[instr[3:0]]
`define GBK_RF_RAW_RN r[instr[19:16]]
`define GBK_RF_RAW_RS r[instr[11:8]]
`define GBK_RF_RAW_RD r[instr[15:12]]
`define GBK_RF_THUMB_RS r[thumb_instr[5:3]]
`define GBK_RF_THUMB_RD r[thumb_instr[2:0]]
`define GBK_RF_THUMB_RO r[thumb_instr[8:6]]
`define GBK_RF_THUMB_IMM r[thumb_instr[10:8]]
`define GBK_RF_THUMB_HRD r[thumb_rd_idx]
`define GBK_RF_THUMB_HRS r[thumb_rs_idx]
`define GBK_RF_BLOCK r[block_reg_index]
`define GBK_RF_STORE r[load_rd]
`define GBK_RF_POSTBASE r[data_base_reg]
`endif
module arm7tdmi_core #(
    parameter logic [31:0] RESET_PC = 32'h00000000,
    parameter bit TIMED_EXECUTION=0
) (
    input  logic        clk,
    input  logic        reset,
    input wire halt,
`ifdef GBK_SAVESTATE
    // Experimental state port, execution-clock domain. Hold the request until
    // serialization/restore is complete. Reads/writes are valid only after ack.
    input wire state_request,state_write,
    input wire [5:0] state_addr,
    input wire [31:0] state_wdata,
    output wire state_quiescent,state_valid,
    output reg [31:0] state_rdata,
`endif
    input wire execution_enable,
    output wire [31:0] research_fetch_pc,
    output wire timing_code,timing_thumb,timing_exec,timing_irq,
    output reg [3:0] timing_internal_cycles,
    output reg timing_refill,
    output logic        bus_valid,
    output logic        bus_write,
    output wire         bus_lock,
    output logic [1:0]  bus_size,
    output logic [31:0] bus_addr,
    output logic [31:0] bus_wdata,
    input  logic [31:0] bus_rdata,
    input  logic        bus_ready,
    input  logic        irq,
    output logic [31:0] debug_pc,
    output logic [31:0] debug_r0,
    output logic [31:0] debug_cpsr,
    output logic [31:0] debug_instr,
    output logic [31:0] debug_r1,
    output logic [31:0] debug_r2,
    output logic [31:0] debug_r12,
    output logic [159:0] debug_bios_sound_state,
    output logic [191:0] debug_execution_state,
    output logic [31:0] debug_irq_counts,
    output logic [351:0] debug_restart_context,
    output logic debug_restart_valid,
    output logic [31:0] debug_add_input,
    output logic [31:0] debug_add_instr,
    output logic [31:0] debug_add_result,
    output logic        debug_add_event,
    output logic [31:0] debug_data_instr,
    output logic [31:0] debug_first_irq_entry_lr,
    output logic [31:0] debug_first_irq_return_lr,
    output logic [31:0] debug_first_irq_push_lr_addr,
    output logic [31:0] debug_first_irq_push_lr_data,
    output logic [31:0] debug_second_irq_push_lr_addr,
    output logic [31:0] debug_second_irq_push_lr_data,
    output logic [31:0] debug_first_irq_pop_lr_addr,
    output logic [31:0] debug_first_irq_pop_lr_data,
    output logic [31:0] debug_first_irq_vector_lr,
    output logic [31:0] debug_first_irq_prologue_lr,
    output logic [15:0] debug_first_irq_stack_passes,
    output logic [31:0] debug_first_irq_progress,
    output logic [31:0] debug_first_irq_last_pc,
    output logic [31:0] debug_first_irq_134_instr,
    output logic [15:0] debug_first_irq_load_state,
    output logic [31:0] debug_first_irq_load_data,
    output logic [15:0] debug_first_irq_load_target,
    output logic [31:0] debug_bad_source_pc,
    output logic [31:0] debug_bad_source_instr,
    output logic [31:0] debug_bad_target_pc,
    output logic [31:0] debug_bad_source_lr,
    output logic [15:0] debug_bad_source_cpsr,
    output logic [31:0] debug_irq_callback_read_pc,
    output logic [31:0] debug_irq_callback_read_data,
    output logic [31:0] debug_irq_bx_target,
    output logic [31:0] debug_irq_first_ewram_pc,
    output logic [31:0] debug_irq_ewram_source_pc,
    output logic [31:0] debug_irq_ewram_source_instr,
    output logic [15:0] debug_irq_pending_bits
);
    // The memory bus returns the containing aligned word. ARM7 single-word
    // LDR rotates it by the byte offset; LDM and instruction fetch do not.
    // Emerald's BlendPalette deliberately loads words at palette+2.
    logic [31:0] load_word_data;
    wire [31:0] load_bus_data=swap_active && swap_write_phase ? swap_result : bus_rdata;
    always_comb begin
        case(bus_addr[1:0])
            2'd0: load_word_data=load_bus_data;
            2'd1: load_word_data={load_bus_data[7:0],load_bus_data[31:8]};
            2'd2: load_word_data={load_bus_data[15:0],load_bus_data[31:16]};
            2'd3: load_word_data={load_bus_data[23:0],load_bus_data[31:24]};
        endcase
    end

    logic [31:0] r[0:15];
    // One shared destination mux for ordinary register writes, plus the
    // second write needed by long multiply and transfer writeback. PC writes
    // stay at their original statement positions to retain branch precedence.
    reg main_write_enable,aux_write_enable;
    reg [3:0] main_write_index,aux_write_index;
    reg [31:0] main_write_data,aux_write_data;
    task automatic write_main(input [3:0] index,input [31:0] value);
        begin
            if(index==15)r[15]<=value;
            else begin main_write_enable=1;main_write_index=index;main_write_data=value;end
        end
    endtask
    task automatic write_aux(input [3:0] index,input [31:0] value);
        begin
            if(index==15)r[15]<=value;
            else begin aux_write_enable=1;aux_write_index=index;aux_write_data=value;end
        end
    endtask
    logic [31:0] cpsr;
    logic        thumb;
    logic        data_cycle;
    logic        exec_pending;
    logic [31:0] instr_reg;
    logic [31:0] debug_instr_reg;
    logic [3:0]  load_rd;
    logic [31:0] instr, op2, alu_result;
    // Immediate MSR has no register-shift operand. Keep its bank-selection
    // control independent of the general shifter's register-data path.
    wire [31:0] msr_literal={24'd0,instr[7:0]};
    wire [4:0] msr_rotate={instr[11:8],1'b0};
    wire [31:0] msr_immediate=(msr_literal>>msr_rotate) |
        (msr_literal<<(6'd32-{1'b0,msr_rotate}));
    logic [15:0] thumb_instr;
    logic [5:0]  rotate_amount;
    logic [7:0]  arm_register_shift;
    logic [31:0] arm_shift_value;
    logic [3:0]  rd;
    logic        data_load;
    logic        data_byte;
    logic        data_half;
    logic        data_signed;
    logic        data_thumb;
    logic        data_pre;
    logic        data_writeback;
    logic [3:0]  data_base_reg;
    logic        block_cycle;
    logic        block_load;
    logic        block_writeback;
    logic        block_thumb;
    logic block_user_transfer,block_restore_psr;
    logic [3:0] block_first_reg;
    logic [15:0] block_remaining;
    logic [4:0]  block_count;
    logic [3:0]  block_reg_index;
    logic [31:0] block_addr;
    logic [31:0] block_base;
    logic [31:0] block_final_base;
    logic [3:0]  block_base_reg;
    logic [31:0] user_sp_bank, user_lr_bank;
    logic [31:0] irq_sp_bank, irq_lr_bank, irq_spsr;
    logic first_irq_entry_seen, first_irq_return_seen;
    logic first_irq_vector_seen, first_irq_prologue_seen;
    logic first_irq_push_seen, first_irq_pop_seen;
    logic second_irq_push_seen;
    logic last_exec_seen, bad_jump_seen;
    logic first_irq_ewram_seen;
    logic [31:0] last_exec_pc, last_exec_instr, last_exec_lr, last_exec_cpsr;
    logic restart_cart_seen;
    logic [31:0] restart_read_addr, restart_read_data;
    // The event mailbox freezes this tuple on the valid rising edge. Avoid a
    // duplicate 352-bit bank here; the last execution tuple remains stable
    // through the first fetch at PC zero, including an immediately ready bus.
    assign debug_restart_context = {restart_read_data,restart_read_addr,last_exec_lr,
        r[13],r[3],debug_execution_state[31:0],debug_execution_state[63:32],
        debug_execution_state[95:64],last_exec_cpsr,last_exec_instr,last_exec_pc};
    logic [31:0] svc_sp_bank, svc_lr_bank, svc_spsr;
    logic [31:0] und_sp_bank,und_lr_bank,und_spsr;
    logic [31:0] fiq_sp_bank,fiq_lr_bank,fiq_spsr,abt_sp_bank,abt_lr_bank,abt_spsr;
`ifdef GBK_SAVESTATE
    // R8..R12 already hold the active bank. Only the opposite bank needs
    // storage; a mode transition swaps the window with these five words.
    logic [31:0] inactive_high_bank[0:4];
    reg [3:0] shared_rn_index,shared_rm_index,shared_rs_index,shared_rd_index;
    reg [31:0] shared_raw_rn,shared_raw_rm,shared_raw_rs,shared_raw_rd;
    reg [11:0] fetched_read_indices;
    // Capture Rm on the existing fetch edge, splitting register selection
    // from the execute-stage shifter and address/writeback adder.
    reg [31:0] fetched_rm_value;
    reg fetched_rm_pc;
    // Decode on the existing fetch-completion edge, alongside instr_reg.
    // This removes PC halfword selection and Thumb opcode classification
    // from the register-read -> shifter -> ALU execution path. No new cycle.
    function automatic [11:0] decode_read_indices(input [31:0] word_value,input thumb_value,halfword);
        reg [15:0] t;
        reg [3:0] rn_value,rm_value,rs_value;
        begin
            t=halfword ? word_value[31:16] : word_value[15:0];
            rn_value=thumb_value ? {(t[15:10]==6'b010001 && t[6]),t[5:3]} : word_value[19:16];
            rm_value=thumb_value ? {(t[15:10]==6'b010001 && t[7]),t[2:0]} : word_value[3:0];
            if(thumb_value && (t[15:13]==3'b001 || t[15:12]==4'b1100))rm_value={1'b0,t[10:8]};
            rs_value=thumb_value ? {1'b0,t[8:6]} : word_value[11:8];
            decode_read_indices={rn_value,rm_value,rs_value};
        end
    endfunction
    function automatic [3:0] decode_rm_index(input [31:0] word_value,input thumb_value,halfword);
        reg [11:0] indices;
        begin
            indices=decode_read_indices(word_value,thumb_value,halfword);
            decode_rm_index=indices[7:4];
        end
    endfunction
    // ARM data-processing immediate shifts and register-offset transfers
    // are mutually exclusive; use one immediate barrel shifter for both.
    logic [32:0] arm_immediate_result;
    function automatic [32:0] shift_immediate(input [31:0] value,input [4:0] amount,input [1:0] kind,input carry_in);
        reg [31:0] shifted;
        reg carry_out;
        begin
            carry_out=carry_in;
            case(kind)
                0:begin shifted=value<<amount;if(amount!=0)carry_out=value[32-amount];end
                1:begin shifted=amount==0 ? 32'd0 : value>>amount;carry_out=amount==0 ? value[31] : value[amount-1];end
                2:begin shifted=$signed(value) >>> (amount==0 ? 5'd31 : amount);carry_out=amount==0 ? value[31] : value[amount-1];end
                default:begin
                    shifted=amount==0 ? {carry_in,value[31:1]} : rotate_right(value,amount);
                    carry_out=amount==0 ? value[0] : value[amount-1];
                end
            endcase
            shift_immediate={carry_out,shifted};
        end
    endfunction
    function automatic [31:0] read_rm_with_pc(input [31:0] pc_value);
        read_rm_with_pc=fetched_rm_pc ? pc_value : fetched_rm_value;
    endfunction
    wire [2:0] inactive_read_index=state_quiescent && state_addr>=35 && state_addr<45 ?
        (state_addr<40 ? 3'(state_addr-35) : 3'(state_addr-40)) : 3'(block_reg_index-8);
    wire [31:0] inactive_read_value=inactive_high_bank[inactive_read_index];
    wire [31:0] user_high_bank[0:4],fiq_high_bank[0:4];
    genvar high_alias;
    generate for(high_alias=0;high_alias<5;high_alias=high_alias+1)begin: inactive_high_alias
        assign user_high_bank[high_alias]=inactive_high_bank[high_alias];
        assign fiq_high_bank[high_alias]=inactive_high_bank[high_alias];
    end endgenerate
`else
    logic [31:0] user_high_bank[0:4],fiq_high_bank[0:4];
`endif
    reg high_switch_enable,high_switch_fiq,bank_save_enable,bank_restore_enable,bank_restore_lr;
    reg [4:0] high_new_mode,bank_restore_mode;
    reg [31:0] bank_save_sp,bank_save_lr,bank_same_sp,bank_same_lr;
    reg high_shadow_enable,high_shadow_fiq;
    reg [2:0] high_shadow_index;
    reg [31:0] high_shadow_data;
    task automatic switch_high_regs(input [4:0] new_mode);
        begin high_switch_enable=1;high_switch_fiq=new_mode==5'h11;high_new_mode=new_mode;end
    endtask
    task automatic save_bank(input [31:0] sp_value,lr_value);
        begin bank_save_enable=1;bank_save_sp=sp_value;bank_save_lr=lr_value;end
    endtask
    task automatic restore_bank(input [4:0] mode,input [31:0] same_sp,same_lr,input restore_lr);
        begin
            bank_restore_enable=1;bank_restore_mode=mode;bank_restore_lr=restore_lr;
            bank_same_sp=same_sp;bank_same_lr=same_lr;
        end
    endtask
    task automatic write_high_shadow(input fiq_bank,input [2:0] index,input [31:0] value);
        begin high_shadow_enable=1;high_shadow_fiq=fiq_bank;high_shadow_index=index;high_shadow_data=value;end
    endtask
`ifdef GBK_SAVESTATE
    // Exception return and state capture share the existing SPSR read mux.
    // CPSR is stable before the clock edge; no sequential temporary is used.
    reg [4:0] spsr_read_mode;
    always @*begin
        spsr_read_mode=cpsr[4:0];
        if(state_quiescent)case(state_addr)
            22:spsr_read_mode=5'h13;25:spsr_read_mode=5'h12;
            28:spsr_read_mode=5'h1b;31:spsr_read_mode=5'h11;34:spsr_read_mode=5'h17;
            default:begin end
        endcase
    end
    wire [31:0] current_spsr=spsr_read_mode==5'h12 ? irq_spsr : spsr_read_mode==5'h13 ? svc_spsr :
        spsr_read_mode==5'h1b ? und_spsr : spsr_read_mode==5'h11 ? fiq_spsr : spsr_read_mode==5'h17 ? abt_spsr : cpsr;
`else
    wire [31:0] current_spsr=cpsr[4:0]==5'h12 ? irq_spsr : cpsr[4:0]==5'h13 ? svc_spsr :
        cpsr[4:0]==5'h1b ? und_spsr : cpsr[4:0]==5'h11 ? fiq_spsr : cpsr[4:0]==5'h17 ? abt_spsr : cpsr;
`endif
    wire [31:0] spsr_mask={{8{instr[19]}},{8{instr[18]}},{8{instr[17]}},{8{instr[16]}}};
    wire [31:0] updated_spsr=(current_spsr & ~spsr_mask) |
        ((instr[25] ? msr_immediate : `GBK_RF_RAW_RM) & spsr_mask);
    task automatic return_exception(input [31:0] target,saved_sp,saved_lr);
        begin
            save_bank(saved_sp,saved_lr);
            restore_bank(current_spsr[4:0],saved_sp,saved_lr,1'b1);
            switch_high_regs(current_spsr[4:0]);
            cpsr<=current_spsr;thumb<=current_spsr[5];
            r[15]<=current_spsr[5] ? {target[31:1],1'b0} : {target[31:2],2'b0};
            if(cpsr[4:0]==5'h12)begin
                if(debug_irq_counts[15:0]!=16'hffff)debug_irq_counts[15:0]<=debug_irq_counts[15:0]+1'b1;
                if(!first_irq_return_seen)begin first_irq_return_seen<=1;debug_first_irq_return_lr<=r[14];end
            end
        end
    endtask
    wire privileged_bank=cpsr[4:0]!=5'h10 && cpsr[4:0]!=5'h1f;
    task automatic write_user_register(input [3:0] index,input [31:0] value);
        begin
            if(privileged_bank && index==13)user_sp_bank<=value;
            else if(privileged_bank && index==14)user_lr_bank<=value;
            else if(cpsr[4:0]==5'h11 && index>=8 && index<=12)write_high_shadow(1'b0,3'(index-8),value);
            else write_main(index,value);
        end
    endtask
    wire arm_undefined=(instr[27:25]==3'b011 && instr[4]) ||
        instr[27:25]==3'b110 || (instr[27:24]==4'b1110) ||
        (instr[27:25]==0 && instr[7] && instr[4] && instr[6] && !instr[20]);
    wire thumb_undefined=thumb_instr[15:8]==8'hde || thumb_instr[15:8]==8'hbe ||
        thumb_instr[15:11]==5'b11101 ||
        (thumb_instr[15:12]==4'hb && thumb_instr[11:8]!=0 && thumb_instr[11:9]!=2 && thumb_instr[11:9]!=6);
    task automatic take_undefined;
        begin
            und_spsr<=cpsr;
            save_bank(r[13],r[14]);
            restore_bank(5'h1b,r[13],r[14],1'b0);
            switch_high_regs(5'h1b); und_lr_bank<=r[15]+(thumb ? 2 : 4);r[14]<=r[15]+(thumb ? 2 : 4);
            r[15]<=4;cpsr[4:0]<=5'h1b;cpsr[5]<=0;cpsr[7]<=1;thumb<=0;
            exec_pending<=0;data_cycle<=0;block_cycle<=0;
        end
    endtask
    // A fetch can already be in flight when an interrupt source becomes
    // visible.  Remember that fact so IRQ entry never reinterprets the old
    // instruction response as the word at vector 00000018.
    logic        irq_pending;
    logic        instr_fetch_pending;
    logic        alu_carry, alu_overflow, shift_carry;
    logic [32:0] add_ext;
    logic [31:0] thumb_alu_result;
    logic [31:0] thumb_shift_result;
    logic        thumb_alu_carry;
    logic        thumb_alu_overflow;
    logic [3:0]  thumb_rd_idx, thumb_rs_idx;
    logic [31:0] thumb_high_rd_value, thumb_high_rs_value;
    logic [31:0] multiply_result;
    logic [63:0] long_multiply_result;
`ifdef GBK_SAVESTATE
    logic long_multiply_zero;
`endif
    logic [31:0] multiply_a,multiply_b;
    logic signed [32:0] multiply_a_extended,multiply_b_extended;
    logic signed [65:0] multiply_product;
    (* keep = "true" *) logic [32:0] multiply_low_sum;
    (* keep = "true" *) logic [31:0] multiply_high_sum0,multiply_high_sum1;
    logic [15:0] thumb_block_list;
    logic [31:0] data_offset;
    logic [31:0] arm_rn_value, arm_rm_value;
    // Freeze a single-transfer address at issue. Recomputing its shifter
    // and ALU while waiting for memory creates an ALU -> cache-hit -> CPU
    // write-enable path and needlessly couples memory timing to execution.
    logic [31:0] transfer_addr,transfer_writeback;
    logic swap_active,swap_write_phase;
    logic [31:0] swap_store,swap_result;
    assign bus_lock=swap_active;
    // Unconnected halt inputs in standalone CPU fixtures retain legacy use.
    wire halted=halt===1'b1;
`ifdef GBK_SAVESTATE
    wire state_hold=state_request===1'b1;
    // Stop only NEW fetches/IRQ entry. A fetch already pending must retain
    // valid until completion; data, block and both locked SWP phases drain.
    wire state_drained=!reset && state_hold && !data_cycle &&
        !block_cycle && !exec_pending && !instr_fetch_pending && !swap_active;
    // Qualify read-port ownership once after drain, outside the execution
    // datapath. A combinational busy decode here lengthens every Rn read,
    // including the multiplier path, even during ordinary guest execution.
    reg state_register_access=0;
    always @(posedge clk)begin
        if(reset)state_register_access<=0;
        else state_register_access<=state_drained;
    end
    assign state_quiescent=state_drained && state_register_access;
    assign state_valid=state_quiescent && state_addr<45;
    wire fetch_enabled=(!TIMED_EXECUTION || execution_enable) && !state_hold;
`else
    wire fetch_enabled=!TIMED_EXECUTION || execution_enable;
`endif
    assign timing_code=!data_cycle && !block_cycle;
    assign timing_thumb=thumb;
    assign timing_exec=exec_pending && !halted;
    assign timing_irq=!halted && irq_pending && !data_cycle && !block_cycle &&
        !exec_pending && !instr_fetch_pending && fetch_enabled;

`ifdef GBK_SAVESTATE
    // CPU section v1: 45 little-endian words; see savestate implementation plan.
    // Transient execution state is drained, diagnostic history is not guest state.
    always @* begin
        state_rdata=0;
        // Borrow the ordinary Rn read selector while execution is quiescent.
        // PC is read directly because the execution port adds its pipeline bias.
        if(state_valid && state_addr<15)state_rdata=shared_raw_rd;
        else if(state_valid) case(state_addr)
            6'd15:state_rdata=r[15];
            6'd16:state_rdata=cpsr;
            6'd17:state_rdata={30'd0,irq_pending,thumb};
            6'd18:state_rdata=user_sp_bank;
            6'd19:state_rdata=user_lr_bank;
            6'd20:state_rdata=svc_sp_bank;
            6'd21:state_rdata=svc_lr_bank;
            6'd22:state_rdata=current_spsr;
            6'd23:state_rdata=irq_sp_bank;
            6'd24:state_rdata=irq_lr_bank;
            6'd25:state_rdata=current_spsr;
            6'd26:state_rdata=und_sp_bank;
            6'd27:state_rdata=und_lr_bank;
            6'd28:state_rdata=current_spsr;
            6'd29:state_rdata=fiq_sp_bank;
            6'd30:state_rdata=fiq_lr_bank;
            6'd31:state_rdata=current_spsr;
            6'd32:state_rdata=abt_sp_bank;
            6'd33:state_rdata=abt_lr_bank;
            6'd34:state_rdata=current_spsr;
            6'd35,6'd36,6'd37,6'd38,6'd39:state_rdata=cpsr[4:0]==5'h11 ? inactive_read_value : 32'd0;
            6'd40,6'd41,6'd42,6'd43,6'd44:state_rdata=cpsr[4:0]!=5'h11 ? inactive_read_value : 32'd0;
            default:state_rdata=0;
        endcase
    end
`endif

    function automatic [2:0] multiply_cycles(input [31:0] value,input signed_termination);
        if(value[31:8]==0 || (signed_termination && value[31:8]==24'hffffff)) multiply_cycles=1;
        else if(value[31:16]==0 || (signed_termination && value[31:16]==16'hffff)) multiply_cycles=2;
        else if(value[31:24]==0 || (signed_termination && value[31:24]==8'hff)) multiply_cycles=3;
        else multiply_cycles=4;
    endfunction
    // Seed carry through an appended low bit, so ADC/SBC need one carry
    // chain rather than an addition/subtraction followed by another one.
    function automatic [32:0] add_with_carry(input [31:0] a,b,input carry);
        reg [33:0] sum;
        begin
            sum={1'b0,a,1'b1}+{1'b0,b,carry};
            add_with_carry=sum[33:1];
        end
    endfunction
`ifdef GBK_SAVESTATE
    // One five-level rotate network. Two opposite variable shifts plus a
    // 32-count subtraction put Rs -> shifter -> ALU over the fitted period.
    function automatic [31:0] rotate_right(input [31:0] value,input [4:0] amount);
        rotate_right=({value,value} >> amount);
    endfunction
`endif
    // Bus cycles are charged by the shared scheduler. These are only the
    // instruction's internal cycles and pipeline refill, never FPGA steps.
    always @* begin
        timing_internal_cycles=0;timing_refill=0;
        if(exec_pending) begin
            if(thumb) begin
                if(thumb_undefined) begin timing_internal_cycles=2;timing_refill=1;end
                else if(thumb_instr[15:11]==5'b11001 ||
                   (thumb_instr[15:12]==4'hb && thumb_instr[11:9]==3'b110))
                    begin
                        timing_refill=thumb_instr[15:12]==4'hb ?
                            (thumb_instr[8] || thumb_instr[7:0]==0) : thumb_instr[7:0]==0;
                        timing_internal_cycles=timing_refill ? 3 : 1;
                    end
                else if(thumb_instr[15:12]==5 || thumb_instr[15:13]==3'b011 ||
                        thumb_instr[15:12]==8 || thumb_instr[15:12]==9 || thumb_instr[15:11]==5'b01001) begin
                    if(thumb_instr[15:12]==5 ? thumb_instr[11:9]>=3 :
                       thumb_instr[15:11]==5'b01001 || thumb_instr[11]) timing_internal_cycles=1;
                end else if(thumb_instr[15:10]==6'b010000) begin
                    if(thumb_instr[9:6]==13) timing_internal_cycles=multiply_cycles(`GBK_RF_THUMB_RS,1'b1);
                    else if(thumb_instr[9:6]==2 || thumb_instr[9:6]==3 ||
                            thumb_instr[9:6]==4 || thumb_instr[9:6]==7) timing_internal_cycles=1;
                end else if(thumb_instr[15:10]==6'b010001) begin
                    if(thumb_instr[9:8]==3 ||
                       ((thumb_instr[9:8]==0 || thumb_instr[9:8]==2) && thumb_rd_idx==15)) begin timing_internal_cycles=2;timing_refill=1;end
                end else if(thumb_instr[15:8]==8'hdf || thumb_instr[15:11]==5'b11100 ||
                            thumb_instr[15:11]==5'b11111 ||
                            (thumb_instr[15:12]==13 && condition_pass(thumb_instr[11:8],cpsr))) begin timing_internal_cycles=2;timing_refill=1;end
            end else if(condition_pass(instr[31:28],cpsr)) begin
                if(instr[27:24]==15 || instr[27:25]==3'b101 || instr[27:4]==24'h12fff1)
                    begin timing_internal_cycles=2;timing_refill=1;end
                else if(arm_undefined) begin timing_internal_cycles=2;timing_refill=1;end
                else if((instr & 32'h0fb00ff0)==32'h01000090)
                    timing_internal_cycles=1;
                else if(instr[27:25]==3'b100)
                    begin timing_internal_cycles=instr[20] ? ((instr[15] || instr[15:0]==0) ? 3 : 1) : 0;timing_refill=instr[20] && (instr[15] || instr[15:0]==0);end
                else if(instr[27:23]==5'b00001 && instr[7:4]==9)
                    timing_internal_cycles=multiply_cycles(`GBK_RF_RAW_RS,instr[22])+1+instr[21];
                else if(instr[27:22]==0 && instr[7:4]==9)
                    timing_internal_cycles=multiply_cycles(`GBK_RF_RAW_RS,1'b1)+instr[21];
                else if(instr[27:26]==1 || (instr[27:25]==0 &&
                        (instr[7:4]==11 || instr[7:4]==13 || instr[7:4]==15)))
                    begin timing_internal_cycles=instr[20] ? (instr[15:12]==15 ? 3 : 1) : 0;timing_refill=instr[20] && instr[15:12]==15;end
                else if(instr[27:26]==0) begin
                    if(!instr[25] && instr[4]) timing_internal_cycles=1;
                    if(instr[15:12]==15 && (instr[24:21]<8 || instr[24:21]>11))
                        begin timing_internal_cycles=timing_internal_cycles+2;timing_refill=1;end
                end
            end
        end
    end

    function automatic [4:0] count_regs(input logic [15:0] list);
        integer i;
        begin
            count_regs = list==0 ? 5'd16 : 5'd0;
            for (i = 0; i < 16; i = i + 1)
                count_regs = count_regs + list[i];
        end
    endfunction

    function automatic [3:0] first_reg(input logic [15:0] list);
        integer i;
        begin
            first_reg = 0;
            for (i = 15; i >= 0; i = i - 1)
                if (list[i]) first_reg = i[3:0];
        end
    endfunction

    function automatic [31:0] block_start(
        input logic [31:0] base,
        input logic [15:0] list,
        input logic        pre_index,
        input logic        up
    );
        logic [6:0] bytes;
        begin
            bytes = count_regs(list) * 4;
            if (up)
                block_start = base + (pre_index ? 4 : 0);
            else
                block_start = base - (pre_index ? bytes : (bytes - 4));
        end
    endfunction

    function automatic logic condition_pass(input logic [3:0] cond, input logic [31:0] flags);
        logic n, z, c, v;
        begin
            n = flags[31]; z = flags[30]; c = flags[29]; v = flags[28];
            case (cond)
                4'h0: condition_pass = z;             // EQ
                4'h1: condition_pass = !z;            // NE
                4'h2: condition_pass = c;             // CS/HS
                4'h3: condition_pass = !c;            // CC/LO
                4'h4: condition_pass = n;             // MI
                4'h5: condition_pass = !n;            // PL
                4'h6: condition_pass = v;             // VS
                4'h7: condition_pass = !v;            // VC
                4'h8: condition_pass = c && !z;       // HI
                4'h9: condition_pass = !c || z;       // LS
                4'hA: condition_pass = n == v;         // GE
                4'hB: condition_pass = n != v;         // LT
                4'hC: condition_pass = !z && (n == v); // GT
                4'hD: condition_pass = z || (n != v);  // LE
                4'hE: condition_pass = 1'b1;           // AL
                default: condition_pass = 1'b0;
            endcase
        end
    endfunction

    assign debug_pc   = r[15];
    assign debug_r0   = r[0];
    assign debug_cpsr = cpsr;
    assign debug_instr = debug_instr_reg;
    assign debug_r1 = r[1];
    assign debug_r2 = r[2];
    assign debug_r12 = r[12];
    // A pending IRQ prevents a new fetch, but must not withdraw one already
    // waiting for memory. DMA can discard that memory-side read and require
    // a retry. Dropping valid would then leave both IRQ entry and the fetch
    // waiting forever, even after DMA releases the bus.
    // PRIVATE RESEARCH: no speculative memory outside IWRAM; only instructions
    // guaranteed to advance PC without starting a transfer or switching banks.
    wire [31:0] overlap_pc=r[15]+(thumb ? 32'd2 : 32'd4);
    wire arm_overlap_safe=!arm_undefined && instr[27:26]==0 && rd!=15 &&
        (instr[25] || !instr[4]) &&
        ((instr[24:21]<8 || instr[24:21]>11) || instr[20]);
    wire thumb_overlap_safe=!thumb_undefined &&
        (thumb_instr[15:13]==0 || thumb_instr[15:13]==1 ||
         (thumb_instr[15:10]==6'b010000 && thumb_instr[9:6]!=2 &&
          thumb_instr[9:6]!=3 && thumb_instr[9:6]!=4 &&
          thumb_instr[9:6]!=7 && thumb_instr[9:6]!=13) ||
         (thumb_instr[15:10]==6'b010001 && thumb_instr[9:8]!=3 &&
          thumb_rd_idx!=15 && thumb_rs_idx!=15));
    wire overlap_issue=TIMED_EXECUTION && !reset && !halted && exec_pending &&
        !data_cycle && !block_cycle && !swap_active && !instr_fetch_pending &&
        fetch_enabled && !irq_pending && !(irq && !cpsr[7]) &&
        r[15][31:24]==3 && overlap_pc[31:24]==3 &&
        (thumb ? thumb_overlap_safe : arm_overlap_safe);
    assign research_fetch_pc=overlap_issue ? overlap_pc : r[15];
    // Address may change while no request is issued. Keep opcode eligibility
    // out of the address -> cache tag -> read data -> operand capture path.
    wire [31:0] overlap_address_pc=exec_pending ? overlap_pc : r[15];
    assign bus_valid  = !reset && !halted && (data_cycle || block_cycle ||
                                  (overlap_issue || (!exec_pending && (fetch_enabled || instr_fetch_pending) && (!irq_pending || instr_fetch_pending))));
    assign bus_write  = swap_active ? swap_write_phase : block_cycle ? !block_load : (data_cycle && !data_load);
    assign bus_size   = block_cycle ? 2'b10 : (data_byte ? 2'b00 : (data_half ? 2'b01 : 2'b10));
`ifdef GBK_SAVESTATE
    // Timed SWP already owns data_cycle and its registered transfer address.
    // Avoid a redundant swap-mode mux before the memory cache-hit/ready path.
    generate if(TIMED_EXECUTION)begin: timed_bus_address
        assign bus_addr=block_cycle ? block_addr : data_cycle ? transfer_addr :
            (thumb ? {overlap_address_pc[31:2],2'b00} : overlap_address_pc);
    end else begin: legacy_bus_address
        assign bus_addr=swap_active ? transfer_addr : block_cycle ? block_addr :
            (data_cycle ? (data_thumb || data_pre ? alu_result : `GBK_RF_POSTBASE) :
            (thumb ? {r[15][31:2],2'b00} : r[15]));
    end endgenerate
`ifdef GBK_SIM
    always @(posedge clk)if(!reset)begin
        if(swap_active && (!data_cycle || block_cycle))$fatal(1,"SWP address ownership invariant");
        if(data_cycle && block_cycle)$fatal(1,"CPU data/block address ownership overlap");
    end
`endif
`else
    assign bus_addr   = swap_active ? transfer_addr : block_cycle ? block_addr :
                        (data_cycle ? (TIMED_EXECUTION ? transfer_addr : (data_thumb || data_pre ? alu_result : `GBK_RF_POSTBASE)) :
                        (thumb ? {r[15][31:2], 2'b00} : r[15]));
`endif
    wire [31:0] block_user_value=privileged_bank && block_reg_index==13 ? user_sp_bank :
        privileged_bank && block_reg_index==14 ? user_lr_bank :
`ifdef GBK_SAVESTATE
        cpsr[4:0]==5'h11 && block_reg_index>=8 && block_reg_index<=12 ? inactive_read_value : `GBK_RF_BLOCK;
`else
        cpsr[4:0]==5'h11 && block_reg_index>=8 && block_reg_index<=12 ? user_high_bank[block_reg_index-8] : `GBK_RF_BLOCK;
`endif
    wire [31:0] block_store_value=block_writeback && block_reg_index==block_base_reg && block_first_reg!=block_base_reg ?
        block_final_base : block_user_transfer ? block_user_value : `GBK_RF_BLOCK;
    assign bus_wdata  = swap_active ? swap_store : block_cycle ?
        (block_reg_index==15 ? r[15]+(block_thumb ? 4 : 12) : block_store_value) : (data_thumb ? (data_byte ? {24'b0, `GBK_RF_STORE[7:0]} :
                                      (data_half ? {16'b0, `GBK_RF_STORE[15:0]} : `GBK_RF_STORE)) :
                                    (data_byte ? {24'b0, `GBK_RF_RAW_RD[7:0]} :
                                     (data_half ? {16'b0, `GBK_RF_RAW_RD[15:0]} : `GBK_RF_RAW_RD)));

    // Select the architectural PC value in the register mux itself. A raw
    // sixteen-register read followed by a second PC-selection mux lengthens
    // the measured register -> shifter -> adder -> destination path.
    function automatic [31:0] read_with_pc(input [3:0] index,input [31:0] pc_value);
        case(index)
            0:read_with_pc=r[0];1:read_with_pc=r[1];2:read_with_pc=r[2];3:read_with_pc=r[3];
            4:read_with_pc=r[4];5:read_with_pc=r[5];6:read_with_pc=r[6];7:read_with_pc=r[7];
            8:read_with_pc=r[8];9:read_with_pc=r[9];10:read_with_pc=r[10];11:read_with_pc=r[11];
            12:read_with_pc=r[12];13:read_with_pc=r[13];14:read_with_pc=r[14];
            default:read_with_pc=pc_value;
        endcase
    endfunction
    always_comb begin
        instr = instr_reg;
`ifdef GBK_SAVESTATE
        thumb_instr = r[15][1] ? instr_reg[31:16] : instr_reg[15:0];
        // ARM Rn / Thumb Rs, ARM Rm / Thumb Rd, ARM Rs / Thumb Ro,
        // and accumulation/store/block data share four physical selections.
        shared_rn_index=fetched_read_indices[11:8];
        shared_rm_index=fetched_read_indices[7:4];
        shared_rs_index=fetched_read_indices[3:0];
        shared_rd_index=block_cycle ? block_reg_index :
            (data_cycle && data_thumb ? load_rd : instr[15:12]);
        // Reuse the store/accumulator-data port for quiescent inspection.
        // Putting state address selection on Rn fed it into Thumb multiply
        // and the execution ALU. This preserves four physical read selections.
        if(state_register_access && state_addr<15)shared_rd_index=state_addr[3:0];
        arm_rn_value=read_with_pc(shared_rn_index,r[15]+(thumb ? 32'd4 : 32'd8));
        arm_rm_value=read_rm_with_pc(r[15]+(thumb ? 32'd4 :
            (!instr[25] && instr[4] ? 32'd12 : 32'd8)));
        shared_raw_rn=shared_rn_index==15 ? r[15] : arm_rn_value;
        shared_raw_rm=read_rm_with_pc(r[15]);
        shared_raw_rs=read_with_pc(shared_rs_index,r[15]);
        shared_raw_rd=read_with_pc(shared_rd_index,r[15]);
`else
        arm_rn_value = read_with_pc(instr[19:16],r[15]+32'd8);
        arm_rm_value = read_with_pc(instr[3:0],r[15]+32'd8);
        thumb_instr = r[15][1] ? instr_reg[31:16] : instr_reg[15:0];
`endif
        rd = instr[15:12];
        shift_carry = cpsr[29];
        alu_carry = cpsr[29];
        alu_overflow = cpsr[28];
        add_ext = 33'b0;
        data_offset = 32'b0;
`ifdef GBK_SAVESTATE
        arm_register_shift=instr[11:8]==15 ? 8'(r[15]+32'd8) : shared_raw_rs[7:0];
        arm_shift_value=arm_rm_value;
        arm_immediate_result=shift_immediate(instr[27:26]==2'b01 ? shared_raw_rm : arm_rm_value,
            instr[11:7],instr[6:5],cpsr[29]);
`else
        arm_register_shift = 8'(read_with_pc(instr[11:8],r[15]+32'd8));
        // Rm reads PC+12 for register-controlled data-processing shifts.
        arm_shift_value = read_with_pc(instr[3:0],r[15]+32'd12);
`endif
        thumb_block_list = 16'b0;
        if (thumb_instr[15:12] == 4'b1011 &&
            (thumb_instr[11:9] == 3'b010 || thumb_instr[11:9] == 3'b110)) begin
            thumb_block_list[7:0] = thumb_instr[7:0];
            if (thumb_instr[8])
                thumb_block_list[thumb_instr[11] ? 15 : 14] = 1'b1;
        end
        // Share ARM signed/unsigned multiplication. Keep Thumb's low-word
        // multiplier separate so a mode mux does not precede this long path.
        multiply_a = `GBK_RF_RAW_RM;
        multiply_b = `GBK_RF_RAW_RS;
        multiply_a_extended = {(instr[22] && multiply_a[31]),multiply_a};
        multiply_b_extended = {(instr[22] && multiply_b[31]),multiply_b};
        multiply_product = multiply_a_extended * multiply_b_extended;
        // Compute upper carry alternatives in parallel with the low word.
        // A full 64-bit accumulation chain exceeded the execution period.
        multiply_low_sum = {1'b0,multiply_product[31:0]} + {1'b0,`GBK_RF_RAW_RD};
        multiply_high_sum0 = multiply_product[63:32] + `GBK_RF_RAW_RN;
        // Seed the carry in the adder's low bit. An explicit trailing +1
        // synthesized as a second carry chain after the high-word sum.
        multiply_high_sum1 = add_with_carry(multiply_product[63:32],`GBK_RF_RAW_RN,1'b1);
        long_multiply_result = multiply_product[63:0];
        if (instr[21])
            long_multiply_result = {multiply_low_sum[32] ? multiply_high_sum1 : multiply_high_sum0,
                                    multiply_low_sum[31:0]};
`ifdef GBK_SAVESTATE
        // Reduce the parallel carry alternatives before selecting the flag.
        // Reducing the selected 64-bit result put the high-word mux and a
        // second reduction after the multiplier/accumulator path.
        long_multiply_zero = instr[21] ?
            ((multiply_low_sum[31:0]==0) && (multiply_low_sum[32] ?
                multiply_high_sum1==0 : multiply_high_sum0==0)) :
            multiply_product[63:0]==0;
`endif
        // MUL/MLA use the identical low-word product/accumulation.
        multiply_result = long_multiply_result[31:0];
        if (instr[25]) begin
            op2 = {24'b0, instr[7:0]};
            rotate_amount = {instr[11:8], 1'b0};
            if (rotate_amount != 0) begin
`ifdef GBK_SAVESTATE
                op2 = rotate_right(op2,rotate_amount[4:0]);
`else
                op2 = (op2 >> rotate_amount) | (op2 << (32-rotate_amount));
`endif
                shift_carry = op2[31];
            end
        end else begin
            op2 = arm_rm_value;
            rotate_amount = 0;
            if (!instr[4]) begin
`ifdef GBK_SAVESTATE
                op2=arm_immediate_result[31:0];shift_carry=arm_immediate_result[32];
`else
                case (instr[6:5])
                    2'b00: begin
                        op2 = arm_rm_value << instr[11:7];
                        if (instr[11:7] != 0) shift_carry = arm_rm_value[32-instr[11:7]];
                    end
                    2'b01: begin
                        op2 = instr[11:7] == 0 ? 32'b0 : arm_rm_value >> instr[11:7];
                        shift_carry = instr[11:7] == 0 ? arm_rm_value[31] : arm_rm_value[instr[11:7]-1];
                    end
                    2'b10: begin
                        op2 = $signed(arm_rm_value) >>> (instr[11:7] == 0 ? 5'd31 : instr[11:7]);
                        // An encoded zero means ASR #32, including sign-bit carry.
                        shift_carry = instr[11:7] == 0 ? arm_rm_value[31] : arm_rm_value[instr[11:7]-1];
                    end
                    default: begin
`ifdef GBK_SAVESTATE
                        op2 = instr[11:7] == 0 ? ((arm_rm_value >> 1) | (cpsr[29] ? 32'h80000000 : 0)) :
                              rotate_right(arm_rm_value,instr[11:7]);
`else
                        op2 = instr[11:7] == 0 ? ((arm_rm_value >> 1) | (cpsr[29] ? 32'h80000000 : 0)) :
                              ((arm_rm_value >> instr[11:7]) | (arm_rm_value << (32-instr[11:7])));
`endif
                        if (instr[11:7] != 0) shift_carry = arm_rm_value[instr[11:7]-1];
                        else shift_carry = `GBK_RF_RAW_RM[0];
                    end
                endcase
`endif
            end else begin
                // Register shifts use all eight low bits of Rs. Zero keeps
                // the operand and carry; counts >=32 have distinct rules.
                op2 = arm_shift_value;
                if (arm_register_shift != 0) begin
                    case (instr[6:5])
                        2'b00: begin
                            op2 = arm_register_shift < 32 ? arm_shift_value << arm_register_shift : 32'b0;
                            shift_carry = arm_register_shift <= 32 ? arm_shift_value[32-arm_register_shift] : 1'b0;
                        end
                        2'b01: begin
                            op2 = arm_register_shift < 32 ? arm_shift_value >> arm_register_shift : 32'b0;
                            shift_carry = arm_register_shift <= 32 ? arm_shift_value[arm_register_shift-1] : 1'b0;
                        end
                        2'b10: begin
                            op2 = $signed(arm_shift_value) >>> (arm_register_shift < 32 ? arm_register_shift : 8'd31);
                            shift_carry = arm_register_shift < 32 ? arm_shift_value[arm_register_shift-1] : arm_shift_value[31];
                        end
                        default: begin
`ifdef GBK_SAVESTATE
                            op2 = rotate_right(arm_shift_value,arm_register_shift[4:0]);
`else
                            op2 = (arm_shift_value >> arm_register_shift[4:0]) |
                                  (arm_shift_value << (32-arm_register_shift[4:0]));
`endif
                            shift_carry = op2[31];
                        end
                    endcase
                end
            end
        end
        if (instr[27:26] == 2'b01) begin
            data_offset = {20'b0, instr[11:0]};
            if (instr[25]) begin
`ifdef GBK_SAVESTATE
                data_offset=arm_immediate_result[31:0];
`else
                data_offset = `GBK_RF_RAW_RM;
                case (instr[6:5])
                    2'b00: data_offset = `GBK_RF_RAW_RM << instr[11:7];
                    2'b01: data_offset = instr[11:7] == 0 ? 32'b0 : `GBK_RF_RAW_RM >> instr[11:7];
                    2'b10: data_offset = $signed(`GBK_RF_RAW_RM) >>>
                        (instr[11:7] == 0 ? 5'd31 : instr[11:7]);
`ifdef GBK_SAVESTATE
                    default: data_offset = instr[11:7] == 0 ?
                        ((`GBK_RF_RAW_RM >> 1) | (cpsr[29] ? 32'h80000000 : 0)) :
                        rotate_right(`GBK_RF_RAW_RM,instr[11:7]);
`else
                    default: data_offset = instr[11:7] == 0 ?
                        ((`GBK_RF_RAW_RM >> 1) | (cpsr[29] ? 32'h80000000 : 0)) :
                        ((`GBK_RF_RAW_RM >> instr[11:7]) |
                         (`GBK_RF_RAW_RM << (32-instr[11:7])));
`endif
                endcase
`endif
            end
            alu_result = instr[23] ? arm_rn_value + data_offset
                                   : arm_rn_value - data_offset;
        end else begin
            alu_carry = shift_carry;
            case (instr[24:21])
                // ARM data-processing opcodes.  The BIOS uses the test and
                // borrow forms during its early reset/stack setup, so keep
                // the full sixteen-opcode family here rather than treating
                // the less common forms as no-ops.
                4'b0000: alu_result = arm_rn_value & op2; // AND
                4'b0001: alu_result = arm_rn_value ^ op2;
                4'b0010: begin alu_result = arm_rn_value - op2; alu_carry = arm_rn_value >= op2; end // SUB
                4'b0011: begin alu_result = op2 - arm_rn_value; alu_carry = op2 >= arm_rn_value; end // RSB
                4'b0100: begin add_ext = {1'b0, arm_rn_value} + {1'b0, op2}; alu_result = add_ext[31:0]; alu_carry = add_ext[32]; end
                4'b0101: begin add_ext = add_with_carry(arm_rn_value,op2,cpsr[29]); alu_result = add_ext[31:0]; alu_carry = add_ext[32]; end
                4'b0110: begin add_ext = add_with_carry(arm_rn_value,~op2,cpsr[29]); alu_result = add_ext[31:0]; alu_carry = add_ext[32]; end // SBC
                4'b0111: begin add_ext = add_with_carry(op2,~arm_rn_value,cpsr[29]); alu_result = add_ext[31:0]; alu_carry = add_ext[32]; end // RSC
                4'b1000: alu_result = arm_rn_value & op2; // TST
                4'b1001: alu_result = arm_rn_value ^ op2; // TEQ
                4'b1100: alu_result = arm_rn_value | op2;
                4'b1110: alu_result = arm_rn_value & ~op2;
                4'b1101: alu_result = op2;
                4'b1010: begin alu_result = arm_rn_value - op2; alu_carry = arm_rn_value >= op2; end
                4'b1011: begin add_ext = {1'b0, arm_rn_value} + {1'b0, op2}; alu_result = add_ext[31:0]; alu_carry = add_ext[32]; end // CMN
                4'b1111: alu_result = ~op2; // MVN
                default: alu_result = arm_rn_value;
            endcase
            case (instr[24:21])
                4'b0010, 4'b1010: alu_overflow =
                    (arm_rn_value[31] != op2[31]) &&
                    (alu_result[31] != arm_rn_value[31]); // SUB/CMP
                4'b0011: alu_overflow =
                    (op2[31] != arm_rn_value[31]) &&
                    (alu_result[31] != op2[31]); // RSB
                4'b0100, 4'b0101, 4'b1011: alu_overflow =
                    (arm_rn_value[31] == op2[31]) &&
                    (alu_result[31] != arm_rn_value[31]); // ADD/ADC/CMN
                4'b0110: alu_overflow =
                    (arm_rn_value[31] != op2[31]) &&
                    (alu_result[31] != arm_rn_value[31]); // SBC
                4'b0111: alu_overflow =
                    (op2[31] != arm_rn_value[31]) &&
                    (alu_result[31] != op2[31]); // RSC
                default: alu_overflow = cpsr[28];
            endcase
        end

        // ARM halfword transfer addressing (LDRH/STRH).  The ARM encoding
        // uses the otherwise-unallocated 000 space with H=1 and S=0; the
        // offset is either Rm or the split immediate in bits 11:8 and 3:0.
        if (!thumb && instr[27:25] == 3'b000 &&
            (instr[7:4] == 4'b1011 || instr[7:4] == 4'b1101 || instr[7:4] == 4'b1111)) begin
            if (instr[22])
                op2 = {24'b0, instr[11:8], instr[3:0]};
            else
                op2 = `GBK_RF_RAW_RM;
            alu_result = instr[23] ? arm_rn_value + op2 : arm_rn_value - op2;
        end

        if (thumb) begin
            // Thumb load/store address and attributes are decoded when the
            // instruction is executed; these values are only used for the
            // bus outputs while data_cycle is active.
            if (thumb_instr[15:12] == 4'b0101) begin
                alu_result = `GBK_RF_THUMB_RS + `GBK_RF_THUMB_RO;
            end else if (thumb_instr[15:13] == 3'b011) begin
                alu_result = `GBK_RF_THUMB_RS +
                             (thumb_instr[10:6] << (thumb_instr[12] ? 0 : 2));
            end else if (thumb_instr[15:12] == 4'b1000) begin
                alu_result = `GBK_RF_THUMB_RS +
                             {26'b0, thumb_instr[10:6], 1'b0};
            end else if (thumb_instr[15:12] == 4'b1001) begin
                alu_result = r[13] + {22'b0, thumb_instr[7:0], 2'b00};
            end else if (thumb_instr[15:11] == 5'b01001) begin
                // Thumb PC-relative literals use the address of the current
                // instruction plus four, then word-align the base.
                alu_result = {((r[15] + 32'd4) >> 2), 2'b00} +
                             {22'b0, thumb_instr[7:0], 2'b00};
            end
        end

        case (thumb_instr[12:11])
            2'b00: thumb_shift_result = `GBK_RF_THUMB_RS << thumb_instr[10:6];
            2'b01: thumb_shift_result = thumb_instr[10:6] == 0 ? 32'b0 :
                `GBK_RF_THUMB_RS >> thumb_instr[10:6];
            default: thumb_shift_result = $signed(`GBK_RF_THUMB_RS) >>>
                (thumb_instr[10:6] == 0 ? 5'd31 : thumb_instr[10:6]);
        endcase
        thumb_rd_idx = {1'b0, thumb_instr[2:0]};
        thumb_rs_idx = {1'b0, thumb_instr[5:3]};
        if (thumb_instr[15:10] == 6'b010001) begin
            thumb_rd_idx = {thumb_instr[7], thumb_instr[2:0]};
            thumb_rs_idx = {thumb_instr[6], thumb_instr[5:3]};
        end
        // In Thumb high-register operations, reading r15 returns the
        // instruction address plus four.  In particular, the BIOS uses
        // "MOV r3,PC; BX r3" to transition from Thumb code at 0xBC0 into
        // ARM code at 0xBC4.
        thumb_high_rd_value = (thumb_rd_idx == 4'hF) ? (r[15] + 32'd4) : `GBK_RF_THUMB_HRD;
        thumb_high_rs_value = (thumb_rs_idx == 4'hF) ? (r[15] + 32'd4) : `GBK_RF_THUMB_HRS;
        thumb_alu_result = `GBK_RF_THUMB_HRD;
        thumb_alu_carry = cpsr[29];
        thumb_alu_overflow = cpsr[28];
        if (thumb_instr[15:10] == 6'b010000) begin
            case (thumb_instr[9:6])
                4'b0000: thumb_alu_result = `GBK_RF_THUMB_RD & `GBK_RF_THUMB_RS;
                4'b0001: thumb_alu_result = `GBK_RF_THUMB_RD ^ `GBK_RF_THUMB_RS;
                4'b0010: begin
                    // Register counts use Rs[7:0], not Rs[4:0]. Zero
                    // preserves C; exactly 32 and greater counts differ.
                    if (`GBK_RF_THUMB_RS[7:0] != 0) begin
                        thumb_alu_result = `GBK_RF_THUMB_RS[7:0] < 32 ?
                            `GBK_RF_THUMB_RD << `GBK_RF_THUMB_RS[7:0] : 32'd0;
                        thumb_alu_carry = `GBK_RF_THUMB_RS[7:0] <= 32 ?
                            `GBK_RF_THUMB_RD[32-`GBK_RF_THUMB_RS[7:0]] : 1'b0;
                    end
                end
                4'b0011: begin
                    if (`GBK_RF_THUMB_RS[7:0] != 0) begin
                        thumb_alu_result = `GBK_RF_THUMB_RS[7:0] < 32 ?
                            `GBK_RF_THUMB_RD >> `GBK_RF_THUMB_RS[7:0] : 32'd0;
                        thumb_alu_carry = `GBK_RF_THUMB_RS[7:0] <= 32 ?
                            `GBK_RF_THUMB_RD[`GBK_RF_THUMB_RS[7:0]-1] : 1'b0;
                    end
                end
                4'b0100: begin
                    if (`GBK_RF_THUMB_RS[7:0] != 0) begin
                        thumb_alu_result = $signed(`GBK_RF_THUMB_RD) >>>
                            (`GBK_RF_THUMB_RS[7:0] < 32 ? `GBK_RF_THUMB_RS[7:0] : 8'd31);
                        thumb_alu_carry = `GBK_RF_THUMB_RS[7:0] < 32 ?
                            `GBK_RF_THUMB_RD[`GBK_RF_THUMB_RS[7:0]-1] : `GBK_RF_THUMB_RD[31];
                    end
                end
                4'b0101: begin
                    add_ext = add_with_carry(`GBK_RF_THUMB_RD,`GBK_RF_THUMB_RS,cpsr[29]);
                    thumb_alu_result = add_ext[31:0]; thumb_alu_carry = add_ext[32];
                    thumb_alu_overflow = (`GBK_RF_THUMB_RD[31] == `GBK_RF_THUMB_RS[31]) &&
                                         (thumb_alu_result[31] != `GBK_RF_THUMB_RD[31]);
                end
                4'b0110: begin
                    add_ext = add_with_carry(`GBK_RF_THUMB_RD,~`GBK_RF_THUMB_RS,cpsr[29]);
                    thumb_alu_result = add_ext[31:0];thumb_alu_carry = add_ext[32];
                    thumb_alu_overflow = (`GBK_RF_THUMB_RD[31] != `GBK_RF_THUMB_RS[31]) &&
                                         (thumb_alu_result[31] != `GBK_RF_THUMB_RD[31]);
                end
                4'b0111: begin
                    if (`GBK_RF_THUMB_RS[7:0] != 0) begin
                        thumb_alu_result = (`GBK_RF_THUMB_RD >> `GBK_RF_THUMB_RS[4:0]) |
                                           (`GBK_RF_THUMB_RD << (32-`GBK_RF_THUMB_RS[4:0]));
                        // Nonzero multiples of 32 retain the value but
                        // set C to bit 31, unlike an actual zero count.
                        thumb_alu_carry = thumb_alu_result[31];
                    end
                end
                4'b1000: thumb_alu_result = `GBK_RF_THUMB_RD & `GBK_RF_THUMB_RS; // TST
                4'b1001: begin // NEG
                    thumb_alu_result = 32'b0 - `GBK_RF_THUMB_RS;
                    thumb_alu_carry = (`GBK_RF_THUMB_RS == 0);
                    thumb_alu_overflow = (`GBK_RF_THUMB_RS == 32'h80000000);
                end
                4'b1010: begin // CMP
                    thumb_alu_result = `GBK_RF_THUMB_RD - `GBK_RF_THUMB_RS;
                    thumb_alu_carry = `GBK_RF_THUMB_RD >= `GBK_RF_THUMB_RS;
                    thumb_alu_overflow = (`GBK_RF_THUMB_RD[31] != `GBK_RF_THUMB_RS[31]) &&
                                         (thumb_alu_result[31] != `GBK_RF_THUMB_RD[31]);
                end
                4'b1011: begin // CMN
                    add_ext = {1'b0, `GBK_RF_THUMB_RD} + {1'b0, `GBK_RF_THUMB_RS};
                    thumb_alu_result = add_ext[31:0];
                    thumb_alu_carry = add_ext[32];
                    thumb_alu_overflow = (`GBK_RF_THUMB_RD[31] == `GBK_RF_THUMB_RS[31]) &&
                                         (thumb_alu_result[31] != `GBK_RF_THUMB_RD[31]);
                end
                4'b1100: thumb_alu_result = `GBK_RF_THUMB_RD | `GBK_RF_THUMB_RS; // ORR
                4'b1101: thumb_alu_result = `GBK_RF_THUMB_RD * `GBK_RF_THUMB_RS; // MUL
                4'b1110: thumb_alu_result = `GBK_RF_THUMB_RD & ~`GBK_RF_THUMB_RS; // BIC
                4'b1111: thumb_alu_result = ~`GBK_RF_THUMB_RS; // MVN
            endcase
        end
    end

    always_ff @(posedge clk) begin
        high_switch_enable=0;high_switch_fiq=0;high_new_mode=0;
        bank_save_enable=0;bank_save_sp=0;bank_save_lr=0;
        bank_restore_enable=0;bank_restore_mode=0;bank_restore_lr=0;bank_same_sp=0;bank_same_lr=0;
        high_shadow_enable=0;high_shadow_fiq=0;high_shadow_index=0;high_shadow_data=0;
        main_write_enable=0;aux_write_enable=0;
`ifdef GBK_SAVESTATE
        // Disabled write ports have no destination or payload. Do not force
        // either to zero through the late bus-ready/commit condition before
        // decoding the real destination. The enables alone qualify writes.
        main_write_index=4'bx;aux_write_index=4'bx;
        main_write_data=32'bx;aux_write_data=32'bx;
`else
        main_write_index=0;aux_write_index=0;main_write_data=0;aux_write_data=0;
`endif
        if (reset) begin
            transfer_addr <= 0;
            swap_active<=0;swap_write_phase<=0;swap_store<=0;swap_result<=0;
            transfer_writeback <= 0;
            r[0] <= 0; r[1] <= 0; r[2] <= 0; r[3] <= 0;
            r[4] <= 0; r[5] <= 0; r[6] <= 0; r[7] <= 0;
            r[8] <= 0; r[9] <= 0; r[10] <= 0; r[11] <= 0;
            r[12] <= 0; r[13] <= 0; r[14] <= 0; r[15] <= RESET_PC;
            cpsr <= 32'h000000D3;
            thumb <= 1'b0;
            data_cycle <= 1'b0;
            exec_pending <= 1'b0;
            instr_reg <= 32'b0;
`ifdef GBK_SAVESTATE
            fetched_read_indices<=0;
            fetched_rm_value<=0;fetched_rm_pc<=0;
`endif
            debug_instr_reg <= 32'b0;
            debug_add_instr <= 32'b0;
            debug_add_input <= 32'b0;
            debug_add_result <= 32'b0;
            debug_add_event <= 1'b0;
            debug_data_instr <= 32'b0;
            load_rd <= 0;
            data_load <= 1'b0;
            data_byte <= 1'b0;
            data_half <= 1'b0;
            data_signed <= 1'b0;
            data_thumb <= 1'b0;
            data_pre <= 1'b1;
            data_writeback <= 1'b0;
            data_base_reg <= 4'b0;
            block_cycle <= 1'b0;
            block_load <= 1'b0;
            block_writeback <= 1'b0;
            block_thumb <= 1'b0;
            block_user_transfer<=0;block_restore_psr<=0;block_first_reg<=0;
            block_remaining <= 16'b0;
            block_count <= 0;
            block_reg_index <= 0;
            block_addr <= 0;
            block_base <= 0;
            block_final_base <= 0;
            block_base_reg <= 0;
            user_sp_bank <= 32'b0;
            user_lr_bank <= 32'b0;
            irq_sp_bank <= 32'b0;
            irq_lr_bank <= 32'b0;
            irq_spsr <= 32'b0;
            first_irq_entry_seen <= 1'b0;
            first_irq_return_seen <= 1'b0;
            debug_first_irq_entry_lr <= 32'b0;
            debug_first_irq_return_lr <= 32'b0;
            debug_first_irq_push_lr_addr <= 32'b0;
            debug_first_irq_push_lr_data <= 32'b0;
            debug_second_irq_push_lr_addr <= 32'b0;
            debug_second_irq_push_lr_data <= 32'b0;
            debug_first_irq_pop_lr_addr <= 32'b0;
            debug_first_irq_pop_lr_data <= 32'b0;
            debug_first_irq_vector_lr <= 32'b0;
            debug_first_irq_prologue_lr <= 32'b0;
            debug_first_irq_stack_passes <= 16'b0;
            first_irq_vector_seen <= 1'b0;
            first_irq_prologue_seen <= 1'b0;
            first_irq_push_seen <= 1'b0;
            first_irq_pop_seen <= 1'b0;
            second_irq_push_seen <= 1'b0;
            debug_first_irq_progress <= 32'b0;
            debug_first_irq_last_pc <= 32'b0;
            debug_first_irq_134_instr <= 32'b0;
            debug_first_irq_load_state <= 16'b0;
            debug_first_irq_load_data <= 32'b0;
            debug_first_irq_load_target <= 16'b0;
            debug_bios_sound_state <= 0;
            debug_execution_state <= 0;
            debug_irq_counts <= 0;
            last_exec_seen <= 1'b0;
            bad_jump_seen <= 1'b0;
            last_exec_pc <= 32'b0;
            last_exec_instr <= 32'b0;
            last_exec_lr <= 32'b0;
            last_exec_cpsr <= 32'b0;
            restart_cart_seen <= 0; debug_restart_valid <= 0;
            restart_read_addr <= 0; restart_read_data <= 0;
            debug_bad_source_pc <= 32'b0;
            debug_bad_source_instr <= 32'b0;
            debug_bad_target_pc <= 32'b0;
            debug_bad_source_lr <= 32'b0;
            debug_bad_source_cpsr <= 16'b0;
            debug_irq_callback_read_pc <= 32'b0;
            debug_irq_callback_read_data <= 32'b0;
            debug_irq_bx_target <= 32'b0;
            debug_irq_first_ewram_pc <= 32'b0;
            debug_irq_ewram_source_pc <= 32'b0;
            debug_irq_ewram_source_instr <= 32'b0;
            debug_irq_pending_bits <= 16'b0;
            first_irq_ewram_seen <= 1'b0;
            svc_sp_bank <= 32'b0;
            svc_lr_bank <= 32'b0;
            svc_spsr <= 32'b0;
            und_sp_bank<=0;und_lr_bank<=0;und_spsr<=0;
            fiq_sp_bank<=0;fiq_lr_bank<=0;fiq_spsr<=0;abt_sp_bank<=0;abt_lr_bank<=0;abt_spsr<=0;
`ifdef GBK_SAVESTATE
            for(integer n=0;n<5;n=n+1)inactive_high_bank[n]<=0;
`else
            for(integer n=0;n<5;n=n+1)begin user_high_bank[n]<=0;fiq_high_bank[n]<=0;end
`endif
            irq_pending <= 1'b0;
            instr_fetch_pending <= 1'b0;
`ifdef GBK_SAVESTATE
        end else if(state_quiescent) begin
            // This path is unreachable while running or while a transaction
            // is outstanding. The image validator must authorize restore first.
            // Feed restores through the existing destination mux/write enables.
            // A second general-register write network wastes logic and routing.
            if(state_write && state_valid && state_addr<15)write_main(state_addr[3:0],state_wdata);
            else if(state_write && state_valid) case(state_addr)
                6'd15:r[15]<=state_wdata;
                6'd16:cpsr<=state_wdata;
                6'd17:begin thumb<=state_wdata[0];irq_pending<=state_wdata[1];end
                6'd18:user_sp_bank<=state_wdata;
                6'd19:user_lr_bank<=state_wdata;
                6'd20:svc_sp_bank<=state_wdata;
                6'd21:svc_lr_bank<=state_wdata;
                6'd22:svc_spsr<=state_wdata;
                6'd23:irq_sp_bank<=state_wdata;
                6'd24:irq_lr_bank<=state_wdata;
                6'd25:irq_spsr<=state_wdata;
                6'd26:und_sp_bank<=state_wdata;
                6'd27:und_lr_bank<=state_wdata;
                6'd28:und_spsr<=state_wdata;
                6'd29:fiq_sp_bank<=state_wdata;
                6'd30:fiq_lr_bank<=state_wdata;
                6'd31:fiq_spsr<=state_wdata;
                6'd32:abt_sp_bank<=state_wdata;
                6'd33:abt_lr_bank<=state_wdata;
                6'd34:abt_spsr<=state_wdata;
                // Reuse the existing bank-shadow write selector/data bus.
                // Describing ten independent writes creates another wide mux.
                6'd35,6'd36,6'd37,6'd38,6'd39:write_high_shadow(1'b0,3'(state_addr-35),state_wdata);
                6'd40,6'd41,6'd42,6'd43,6'd44:write_high_shadow(1'b1,3'(state_addr-40),state_wdata);
                default:begin end
            endcase
`endif
        end else if(!halted) begin
            if(exec_pending) begin
                transfer_addr <= thumb || instr[24] ? alu_result : `GBK_RF_RAW_RN;
                transfer_writeback <= alu_result;
            end
            // One-cycle pulse used by the bus diagnostics.  The sticky
            // operand/result registers remain useful after the pulse.
            debug_add_event <= 1'b0;
            // Sample the loop operands at the instruction that clears the
            // second PCM buffer, rather than at an unrelated video boundary.
            if (exec_pending && thumb && r[15] == 32'h00001e9c)
                debug_bios_sound_state <= {
                    debug_bios_sound_state[159:128] + 32'd1,
                    r[13], r[8], r[6], r[1]};
            if (exec_pending) begin
                debug_execution_state <= {r[15],
                    thumb ? {16'b0, thumb_instr} : instr_reg,
                    cpsr, r[0], r[1], r[2]};
                last_exec_seen <= 1'b1;
                last_exec_pc <= r[15];
                last_exec_instr <= thumb ? {16'b0, thumb_instr} : instr_reg;
                last_exec_lr <= r[14];
                last_exec_cpsr <= cpsr;
                if(r[15][31:24]>=8'h08 && r[15][31:24]<=8'h0d) restart_cart_seen <= 1;
            end
            if(bus_valid && bus_ready && !bus_write && (data_cycle || block_cycle)) begin
                restart_read_addr <= bus_addr; restart_read_data <= bus_rdata;
            end
            if(restart_cart_seen && r[15]==0 && !debug_restart_valid) begin
                debug_restart_valid <= 1;
            end
            // Retain the first invalid control-flow transition.  The BIOS
            // occupies only 00000000-00003FFF.  These BIOS spans are Thumb
            // routines used by the IRQ dispatcher; ARM-state execution in
            // them is already wrong even before the PC leaves the BIOS.
            if (!bad_jump_seen && last_exec_seen &&
                ((cpsr[4:0] == 5'h12 && !thumb &&
                  ((r[15] >= 32'h000009c2 && r[15] < 32'h00000aac) ||
                   (r[15] >= 32'h0000210c && r[15] < 32'h00002140) ||
                   (r[15] >= 32'h00002d70 && r[15] < 32'h00002d90))) ||
                 !(r[15] < 32'h00004000 || r[15][31:24] == 8'h02 ||
                   r[15][31:24] == 8'h03 ||
                   (r[15][31:24] >= 8'h08 && r[15][31:24] <= 8'h0d)))) begin
                bad_jump_seen <= 1'b1;
                debug_bad_source_pc <= last_exec_pc;
                debug_bad_source_instr <= last_exec_instr;
                debug_bad_target_pc <= r[15];
                debug_bad_source_lr <= last_exec_lr;
                debug_bad_source_cpsr <= last_exec_cpsr[15:0];
            end
            if (first_irq_entry_seen && !first_irq_return_seen &&
                data_cycle && bus_ready && cpsr[4:0] == 5'h12 &&
                (r[15] == 32'h00000310 || r[15] == 32'h00000318)) begin
                debug_irq_callback_read_pc <= r[15];
                debug_irq_callback_read_data <= bus_rdata;
            end
            if (first_irq_entry_seen && !first_irq_return_seen &&
                exec_pending && r[15] == 32'h00000324 && cpsr[4:0] == 5'h12) begin
                debug_irq_bx_target <= r[0];
                debug_irq_pending_bits <= r[2][15:0];
            end
            if (first_irq_entry_seen && !first_irq_return_seen &&
                !first_irq_ewram_seen && cpsr[4:0] == 5'h12 &&
                r[15][31:24] == 8'h02) begin
                first_irq_ewram_seen <= 1'b1;
                debug_irq_first_ewram_pc <= r[15];
                debug_irq_ewram_source_pc <= last_exec_pc;
                debug_irq_ewram_source_instr <= last_exec_instr;
            end
            if (first_irq_entry_seen && !first_irq_return_seen &&
                block_cycle && bus_ready && block_reg_index == 4'd14) begin
                if (r[15] == 32'h00000128 && !block_load) begin
                    debug_first_irq_stack_passes[7:0] <=
                        debug_first_irq_stack_passes[7:0] + 8'd1;
                    if (!first_irq_push_seen) begin
                        first_irq_push_seen <= 1'b1;
                        debug_first_irq_push_lr_addr <= bus_addr;
                        debug_first_irq_push_lr_data <= bus_wdata;
                    end else if (!second_irq_push_seen) begin
                        second_irq_push_seen <= 1'b1;
                        debug_second_irq_push_lr_addr <= bus_addr;
                        debug_second_irq_push_lr_data <= bus_wdata;
                    end
                end
                if (r[15] == 32'h00000138 && block_load) begin
                    debug_first_irq_stack_passes[15:8] <=
                        debug_first_irq_stack_passes[15:8] + 8'd1;
                    if (!first_irq_pop_seen) begin
                        first_irq_pop_seen <= 1'b1;
                        debug_first_irq_pop_lr_addr <= bus_addr;
                        debug_first_irq_pop_lr_data <= bus_rdata;
                    end
                end
            end
            // Sticky checkpoints from the IRQ vector through the BIOS
            // dispatcher and its Thumb callback.  These remain visible even
            // if execution later runs into an unmapped address.
            if (first_irq_entry_seen && !first_irq_return_seen && exec_pending) begin
                if (r[15] == 32'h00000018) begin
                    debug_first_irq_progress[0] <= 1'b1;
                    if (!first_irq_vector_seen) begin
                        first_irq_vector_seen <= 1'b1;
                        debug_first_irq_vector_lr <= r[14];
                    end
                end
                if (r[15] == 32'h00000128) begin
                    debug_first_irq_progress[1] <= 1'b1;
                    if (!first_irq_prologue_seen) begin
                        first_irq_prologue_seen <= 1'b1;
                        debug_first_irq_prologue_lr <= r[14];
                    end
                end
                if (r[15] == 32'h00000134) begin
                    debug_first_irq_progress[2] <= 1'b1;
                    debug_first_irq_134_instr <= instr_reg;
                end
                if (r[15] == 32'h00000300) begin
                    debug_first_irq_progress[3] <= 1'b1;
                    if (instr_reg == 32'hE3A03301)
                        debug_first_irq_progress[8] <= 1'b1;
                end
                if (r[15] == 32'h00000324) begin
                    debug_first_irq_progress[4] <= 1'b1;
                    if (instr_reg == 32'hE12FFF10)
                        debug_first_irq_progress[9] <= 1'b1;
                end
                if (r[15] == 32'h0000210C) begin
                    debug_first_irq_progress[5] <= 1'b1;
                    if (thumb)
                        debug_first_irq_progress[10] <= 1'b1;
                end
                if (r[15] == 32'h00000138) begin
                    debug_first_irq_progress[6] <= 1'b1;
                    if (!thumb)
                        debug_first_irq_progress[11] <= 1'b1;
                end
                if (r[15] == 32'h0000013C) begin
                    debug_first_irq_progress[7] <= 1'b1;
                    if (!thumb)
                        debug_first_irq_progress[12] <= 1'b1;
                end
                if (r[15][31:14] == 18'b0)
                    debug_first_irq_last_pc <= r[15];
            end
            if (first_irq_entry_seen && !first_irq_return_seen &&
                data_cycle && bus_ready && r[15] == 32'h00000134) begin
                debug_first_irq_progress[13] <= 1'b1;
                if (data_load && load_rd == 4'hF)
                    debug_first_irq_progress[14] <= 1'b1;
                if (bus_rdata == 32'h00000300)
                    debug_first_irq_progress[15] <= 1'b1;
                debug_first_irq_load_state <= {7'b0, instr_fetch_pending,
                                               irq_pending, thumb, block_cycle,
                                               load_rd, data_load};
                debug_first_irq_load_data <= bus_rdata;
                debug_first_irq_load_target <= {bus_rdata[15:2], 2'b00};
            end
            if (first_irq_entry_seen && !first_irq_return_seen &&
                !data_cycle && !block_cycle && !exec_pending &&
                r[15] == 32'h00000300 && bus_valid && !bus_write) begin
                debug_first_irq_progress[16] <= 1'b1;
                if (bus_ready)
                    debug_first_irq_progress[17] <= 1'b1;
            end
            // Latch rather than immediately vectoring.  If a fetch began on
            // the same edge as the IRQ, the bus must finish that transaction
            // before its response can be safely discarded.
            if (irq && !cpsr[7])
                irq_pending <= 1'b1;
            if (!data_cycle && !block_cycle && !exec_pending &&
                !irq_pending && bus_valid && !bus_ready)
                instr_fetch_pending <= 1'b1;

            if (timing_irq) begin
            // ARM7 IRQ entry: save CPSR, switch to IRQ mode/ARM state, and
            // vector through 00000018. The banked SP/LR state is enough for
            // the normal BIOS-style IRQ prologue and return sequence.
            if (debug_irq_counts[31:16] != 16'hffff)
                debug_irq_counts[31:16] <= debug_irq_counts[31:16] + 1'b1;
            irq_spsr <= cpsr;
            save_bank(r[13],r[14]);
            restore_bank(5'h12,r[13],r[14],1'b0);
            // SUBS PC,LR,#4 must resume at the interrupted next instruction
            // in either state.  r[15] already names that next instruction.
            switch_high_regs(5'h12); irq_lr_bank <= r[15] + 4;
            r[14] <= r[15] + 4;
            if (!first_irq_entry_seen) begin
                first_irq_entry_seen <= 1'b1;
                debug_first_irq_entry_lr <= r[15] + 4;
            end
            r[15] <= 32'h00000018;
            cpsr[4:0] <= 5'h12;
            cpsr[5] <= 1'b0;
            cpsr[7] <= 1'b1;
            thumb <= 1'b0;
            instr_reg <= 32'b0;
`ifdef GBK_SAVESTATE
            fetched_read_indices<=0;
            fetched_rm_value<=0;fetched_rm_pc<=0;
`endif
            data_cycle <= 1'b0;
            exec_pending <= 1'b0;
            irq_pending <= 1'b0;
        end else if (bus_ready && block_cycle) begin
            if (block_load)
                if (block_reg_index == 4'hF)begin
                    if(!block_restore_psr)r[15] <= block_thumb ? {bus_rdata[31:1],1'b0} : {bus_rdata[31:2],2'b0};
                end else if(block_user_transfer)write_user_register(block_reg_index,bus_rdata);
                else write_main(block_reg_index,bus_rdata);
            if (block_remaining == (16'b1 << block_reg_index)) begin
                block_cycle <= 1'b0;
                if(block_restore_psr)begin
                    return_exception(bus_rdata,block_writeback && block_base_reg==13 ? block_final_base : r[13],
                        block_writeback && block_base_reg==14 ? block_final_base : r[14]);
                    if(block_writeback && block_base_reg<13)begin
                        if(block_base_reg>=8 && ((cpsr[4:0]==5'h11)!=(current_spsr[4:0]==5'h11)))begin
                            if(cpsr[4:0]==5'h11)write_high_shadow(1'b1,3'(block_base_reg-8),block_final_base);
                            else write_high_shadow(1'b0,3'(block_base_reg-8),block_final_base);
                        end else write_aux(block_base_reg,block_final_base);
                    end
                end else begin
                    if (block_writeback)write_aux(block_base_reg,block_final_base);
                    if (!(block_load && block_reg_index == 4'hF))r[15] <= r[15] + (block_thumb ? 2 : 4);
                    if (block_load && block_reg_index == 4'hF)thumb <= block_thumb;
                end
            end else begin
                block_remaining <= block_remaining & ~(16'b1 << block_reg_index);
                block_reg_index <= first_reg(block_remaining & ~(16'b1 << block_reg_index));
                block_addr <= block_addr + 4;
            end
        end else if (bus_ready && data_cycle && swap_active && !swap_write_phase) begin
            swap_result<=bus_rdata;swap_write_phase<=1;
        end else if (bus_ready && data_cycle) begin
            if (data_load) begin
                if (data_byte && load_rd != 4'hF)
                    write_main(load_rd,data_signed
                        ? {{24{load_bus_data[(bus_addr[1:0] * 8) + 7]}}, load_bus_data[(bus_addr[1:0] * 8) +: 8]}
                        : (load_bus_data >> (bus_addr[1:0] * 8)) & 32'h000000ff);
                else if (data_half && load_rd != 4'hF)
                    write_main(load_rd,data_signed
                        ? (bus_addr[1] ? {{16{load_bus_data[31]}}, load_bus_data[31:16]} :
                                         {{16{load_bus_data[15]}}, load_bus_data[15:0]})
                        : (load_bus_data >> (bus_addr[1] * 16)) & 32'h0000ffff);
                else if (load_rd != 4'hF)
                    write_main(load_rd,load_word_data);
            end
            if (data_load && load_rd == 4'hF)
                r[15] <= {load_word_data[31:2], 2'b00};
            else
                r[15] <= r[15] + (data_thumb ? 2 : 4);
                if (data_writeback)
                    write_aux(data_base_reg,TIMED_EXECUTION ? transfer_writeback : alu_result);
            data_cycle <= 1'b0;
            if(swap_active)begin swap_active<=0;swap_write_phase<=0;data_byte<=0;end
            data_load <= 1'b0;
            data_signed <= 1'b0;
        end else if (bus_ready && bus_valid && !exec_pending) begin
            if (irq_pending && instr_fetch_pending) begin
                // This is the response belonging to the fetch that was
                // issued before IRQ became pending.  It is not the vector
                // word and must not be executed with PC=00000018.
                instr_fetch_pending <= 1'b0;
            end else begin
                instr_reg <= bus_rdata;
`ifdef GBK_SAVESTATE
                fetched_read_indices<=decode_read_indices(bus_rdata,thumb,r[15][1]);
                fetched_rm_value<=read_with_pc(decode_rm_index(bus_rdata,thumb,r[15][1]),32'd0);
                fetched_rm_pc<=decode_rm_index(bus_rdata,thumb,r[15][1])==15;
`endif
                exec_pending <= 1'b1;
                instr_fetch_pending <= 1'b0;
            end
            end else if (exec_pending && thumb && thumb_undefined) begin
                take_undefined();
            end else if (exec_pending && thumb) begin
            exec_pending <= 1'b0;
            debug_instr_reg <= {16'b0, thumb_instr};
            if (thumb_instr[15:11] == 5'b11000 || thumb_instr[15:11] == 5'b11001) begin
                block_cycle <= 1'b1;
                block_load <= thumb_instr[11];
                block_writeback <= !thumb_instr[11] || !thumb_instr[{1'b0,thumb_instr[10:8]}];
                block_thumb <= 1'b1;
                block_user_transfer<=0;block_restore_psr<=0;
                block_remaining <= thumb_instr[7:0]==0 ? 16'h8000 : {8'b0, thumb_instr[7:0]};
                block_first_reg<=first_reg(thumb_instr[7:0]==0 ? 16'h8000 : {8'b0,thumb_instr[7:0]});
                block_count <= count_regs({8'b0, thumb_instr[7:0]});
                block_reg_index <= first_reg(thumb_instr[7:0]==0 ? 16'h8000 : {8'b0, thumb_instr[7:0]});
                block_base <= `GBK_RF_THUMB_IMM;
                block_base_reg <= {1'b0, thumb_instr[10:8]};
                block_final_base <= `GBK_RF_THUMB_IMM +
                                    (count_regs({8'b0, thumb_instr[7:0]}) * 4);
                block_addr <= `GBK_RF_THUMB_IMM;
            end else if (thumb_instr[15:12] == 4'b1011 &&
                (thumb_instr[11:9] == 3'b010 || thumb_instr[11:9] == 3'b110)) begin
                block_cycle <= 1'b1;
                block_load <= thumb_instr[11];
                block_writeback <= 1'b1;
                block_thumb <= 1'b1;
                block_user_transfer<=0;block_restore_psr<=0;
                block_remaining <= thumb_block_list==0 ? 16'h8000 : thumb_block_list;
                block_first_reg<=first_reg(thumb_block_list==0 ? 16'h8000 : thumb_block_list);
                block_count <= count_regs(thumb_block_list);
                block_reg_index <= first_reg(thumb_block_list==0 ? 16'h8000 : thumb_block_list);
                block_base <= r[13];
                block_base_reg <= 4'd13;
                block_final_base <= thumb_instr[11]
                    ? r[13] + (count_regs(thumb_block_list) * 4)
                    : r[13] - (count_regs(thumb_block_list) * 4);
                block_addr <= thumb_instr[11]
                    ? r[13]
                    : r[13] - (count_regs(thumb_block_list) * 4);
            end else if (thumb_instr[15:12] == 4'b0101 ||
                thumb_instr[15:13] == 3'b011 ||
                thumb_instr[15:12] == 4'b1000 ||
                thumb_instr[15:12] == 4'b1001 ||
                thumb_instr[15:11] == 5'b01001) begin
                // Latch the instruction when the data cycle is launched;
                // the memory response may arrive several clocks later.
                debug_data_instr <= {16'b0, thumb_instr};
                data_cycle <= 1'b1;
                data_load <= (thumb_instr[15:12] == 4'b0101) ?
                             (thumb_instr[11:9] >= 3'b011) :
                             (thumb_instr[15:13] == 3'b011) ? thumb_instr[11] :
                             (thumb_instr[15:12] == 4'b1000) ? thumb_instr[11] :
                             (thumb_instr[15:12] == 4'b1001) ? thumb_instr[11] : 1'b1;
                data_byte <= (thumb_instr[15:12] == 4'b0101) ?
                             (thumb_instr[11:9] == 3'b010 ||
                              thumb_instr[11:9] == 3'b011 ||
                              thumb_instr[11:9] == 3'b110) :
                             (thumb_instr[15:13] == 3'b011) ? thumb_instr[12] : 1'b0;
                data_half <= (thumb_instr[15:12] == 4'b0101) ?
                             (thumb_instr[11:9] == 3'b001 ||
                              thumb_instr[11:9] == 3'b101 ||
                              thumb_instr[11:9] == 3'b111) :
                             (thumb_instr[15:12] == 4'b1000);
                data_signed <= (thumb_instr[15:12] == 4'b0101) ?
                               (thumb_instr[11:9] == 3'b011 ||
                                thumb_instr[11:9] == 3'b111) : 1'b0;
                data_thumb <= 1'b1;
                data_pre <= 1'b1;
                data_writeback <= 1'b0;
                data_base_reg <= (thumb_instr[15:12] == 4'b1001) ? 4'd13 :
                                 (thumb_instr[15:11] == 5'b01001) ? 4'd15 :
                                 (thumb_instr[15:12] == 4'b0101) ? {1'b0, thumb_instr[5:3]} :
                                 {1'b0, thumb_instr[5:3]};
                // PC-relative LDR and SP-relative LDR/STR encode Rd in
                // bits 10:8; bits 2:0 belong to the immediate offset.
                // The latter is used for both the load destination and the
                // store source via bus_wdata.
                load_rd <= (thumb_instr[15:11] == 5'b01001 ||
                            thumb_instr[15:12] == 4'b1001) ?
                           {1'b0, thumb_instr[10:8]} : thumb_instr[2:0];
            end else begin
                r[15] <= r[15] + 2;
            end
            if (thumb_instr[15:13] == 3'b000 && thumb_instr[12:11] != 2'b11) begin
                // Thumb format 1: LSL/LSR/ASR Rd,Rs,#imm5.
                write_main(thumb_instr[2:0],thumb_shift_result);
                case (thumb_instr[12:11])
                    2'b00: begin
                        cpsr[29] <= (thumb_instr[10:6] == 0) ? cpsr[29] :
                            `GBK_RF_THUMB_RS[32-thumb_instr[10:6]];
                    end
                    2'b01: begin
                        cpsr[29] <= (thumb_instr[10:6] == 0) ?
                            `GBK_RF_THUMB_RS[31] : `GBK_RF_THUMB_RS[thumb_instr[10:6]-1];
                    end
                    default: begin
                        cpsr[29] <= (thumb_instr[10:6] == 0) ?
                            `GBK_RF_THUMB_RS[31] : `GBK_RF_THUMB_RS[thumb_instr[10:6]-1];
                    end
                endcase
                cpsr[31] <= thumb_shift_result[31];
                cpsr[30] <= (thumb_shift_result == 0);
            end else if (thumb_instr[15:13] == 3'b000 && thumb_instr[12:11] == 2'b11) begin
                // Thumb format 2: ADD/SUB register or small immediate.
                debug_add_instr <= {16'b0, thumb_instr};
                debug_add_input <= `GBK_RF_THUMB_RS;
                debug_add_event <= (thumb_instr == 16'h1C92);
                if (thumb_instr[9]) begin
                    if (thumb_instr[10]) begin
                        write_main(thumb_instr[2:0],`GBK_RF_THUMB_RS -
                                                {29'b0, thumb_instr[8:6]});
                        debug_add_result <= `GBK_RF_THUMB_RS -
                                            {29'b0, thumb_instr[8:6]};
                        cpsr[31] <= ((`GBK_RF_THUMB_RS -
                                      {29'b0, thumb_instr[8:6]}) & 32'h80000000) != 0;
                        cpsr[30] <= (`GBK_RF_THUMB_RS -
                                     {29'b0, thumb_instr[8:6]}) == 0;
                        cpsr[29] <= `GBK_RF_THUMB_RS >= {29'b0, thumb_instr[8:6]};
                        cpsr[28] <= (`GBK_RF_THUMB_RS[31] != 1'b0) &&
                                    ((((`GBK_RF_THUMB_RS -
                                        {29'b0, thumb_instr[8:6]}) & 32'h80000000) != 0) !=
                                     `GBK_RF_THUMB_RS[31]);
                    end else begin
                        write_main(thumb_instr[2:0],`GBK_RF_THUMB_RS -
                                                `GBK_RF_THUMB_RO);
                        debug_add_result <= `GBK_RF_THUMB_RS - `GBK_RF_THUMB_RO;
                        cpsr[31] <= ((`GBK_RF_THUMB_RS -
                                      `GBK_RF_THUMB_RO) & 32'h80000000) != 0;
                        cpsr[30] <= (`GBK_RF_THUMB_RS - `GBK_RF_THUMB_RO) == 0;
                        cpsr[29] <= `GBK_RF_THUMB_RS >= `GBK_RF_THUMB_RO;
                        cpsr[28] <= (`GBK_RF_THUMB_RS[31] != `GBK_RF_THUMB_RO[31]) &&
                                    ((((`GBK_RF_THUMB_RS - `GBK_RF_THUMB_RO) &
                                       32'h80000000) != 0) != `GBK_RF_THUMB_RS[31]);
                    end
                end else begin
                    if (thumb_instr[10]) begin
                        write_main(thumb_instr[2:0],`GBK_RF_THUMB_RS +
                                                {29'b0, thumb_instr[8:6]});
                        debug_add_result <= `GBK_RF_THUMB_RS +
                                            {29'b0, thumb_instr[8:6]};
                        cpsr[31] <= ((`GBK_RF_THUMB_RS +
                                      {29'b0, thumb_instr[8:6]}) & 32'h80000000) != 0;
                        cpsr[30] <= (`GBK_RF_THUMB_RS +
                                     {29'b0, thumb_instr[8:6]}) == 0;
                        cpsr[29] <= ({1'b0, `GBK_RF_THUMB_RS} +
                                     {1'b0, {29'b0, thumb_instr[8:6]}}) >= 33'h100000000;
                        cpsr[28] <= (`GBK_RF_THUMB_RS[31] == 1'b0) &&
                                    ((((`GBK_RF_THUMB_RS +
                                        {29'b0, thumb_instr[8:6]}) & 32'h80000000) != 0) !=
                                     `GBK_RF_THUMB_RS[31]);
                    end else begin
                        write_main(thumb_instr[2:0],`GBK_RF_THUMB_RS +
                                                `GBK_RF_THUMB_RO);
                        debug_add_result <= `GBK_RF_THUMB_RS + `GBK_RF_THUMB_RO;
                        cpsr[31] <= ((`GBK_RF_THUMB_RS +
                                      `GBK_RF_THUMB_RO) & 32'h80000000) != 0;
                        cpsr[30] <= (`GBK_RF_THUMB_RS + `GBK_RF_THUMB_RO) == 0;
                        cpsr[29] <= ({1'b0, `GBK_RF_THUMB_RS} +
                                     {1'b0, `GBK_RF_THUMB_RO}) >= 33'h100000000;
                        cpsr[28] <= (`GBK_RF_THUMB_RS[31] == `GBK_RF_THUMB_RO[31]) &&
                                    ((((`GBK_RF_THUMB_RS + `GBK_RF_THUMB_RO) &
                                       32'h80000000) != 0) != `GBK_RF_THUMB_RS[31]);
                    end
                end
            end else if (thumb_instr[15:11] == 5'b00100) begin
                // MOVS Rd,#imm8
                write_main(thumb_instr[10:8],{24'b0, thumb_instr[7:0]});
                cpsr[31] <= (thumb_instr[7:0] == 0) ? 1'b0 : 1'b0;
                cpsr[30] <= (thumb_instr[7:0] == 0);
            end else if (thumb_instr[15:10] == 6'b010000) begin
                if (thumb_instr[9:6] != 4'b1000 &&
                    thumb_instr[9:6] != 4'b1010 &&
                    thumb_instr[9:6] != 4'b1011)
                    write_main(thumb_instr[2:0],thumb_alu_result);
                cpsr[31] <= thumb_alu_result[31];
                cpsr[30] <= (thumb_alu_result == 0);
                if (thumb_instr[9:6] == 4'b0010 || thumb_instr[9:6] == 4'b0011 ||
                    thumb_instr[9:6] == 4'b0100 || thumb_instr[9:6] == 4'b0101 ||
                    thumb_instr[9:6] == 4'b0110 || thumb_instr[9:6] == 4'b0111 ||
                    thumb_instr[9:6] == 4'b1001 || thumb_instr[9:6] == 4'b1010 ||
                    thumb_instr[9:6] == 4'b1011)
                    cpsr[29] <= thumb_alu_carry;
                if (thumb_instr[9:6] == 4'b0101 || thumb_instr[9:6] == 4'b0110 ||
                    thumb_instr[9:6] == 4'b1001 || thumb_instr[9:6] == 4'b1010 ||
                    thumb_instr[9:6] == 4'b1011)
                    cpsr[28] <= thumb_alu_overflow;
            end else if (thumb_instr[15:10] == 6'b010001 && thumb_instr[9:8] == 2'b10) begin
                write_main(thumb_rd_idx,thumb_high_rs_value);
                if (thumb_rd_idx == 4'hF) begin
                    // MOV PC,Rm is a Thumb-state branch, not BX.  An even
                    // target must not clear CPSR.T (the BIOS uses this).
                    r[15] <= {thumb_high_rs_value[31:1], 1'b0};
                end else
                    r[15] <= r[15] + 2;
            end else if (thumb_instr[15:10] == 6'b010001 && thumb_instr[9:8] == 2'b01) begin
                cpsr[31] <= ((thumb_high_rd_value - thumb_high_rs_value) & 32'h80000000) != 0;
                cpsr[30] <= (thumb_high_rd_value == thumb_high_rs_value);
                cpsr[29] <= thumb_high_rd_value >= thumb_high_rs_value;
                cpsr[28] <= (thumb_high_rd_value[31] != thumb_high_rs_value[31]) &&
                            ((((thumb_high_rd_value - thumb_high_rs_value) & 32'h80000000) != 0) != thumb_high_rd_value[31]);
                r[15] <= r[15] + 2;
            end else if (thumb_instr[15:10] == 6'b010001 && thumb_instr[9:8] == 2'b00) begin
                if (thumb_rd_idx == 4'hF) begin
                    r[15] <= (thumb_high_rd_value + thumb_high_rs_value) & 32'hfffffffe;
                    // Like MOV PC,Rm, ADD PC,Rm does not exchange state.
                end else begin
                    write_main(thumb_rd_idx,thumb_high_rd_value + thumb_high_rs_value);
                    r[15] <= r[15] + 2;
                end
            end else if (thumb_instr[15:10] == 6'b010001 && thumb_instr[9:8] == 2'b11) begin
                thumb <= thumb_high_rs_value[0];
                cpsr[5] <= thumb_high_rs_value[0];
                r[15] <= {thumb_high_rs_value[31:1], 1'b0};
            end else if (thumb_instr[15:11] == 5'b00110) begin
                // ADDS Rd,#imm8
                write_main(thumb_instr[10:8],`GBK_RF_THUMB_IMM + {24'b0, thumb_instr[7:0]});
                cpsr[31] <= ((`GBK_RF_THUMB_IMM + {24'b0, thumb_instr[7:0]}) & 32'h80000000) != 0;
                cpsr[30] <= (`GBK_RF_THUMB_IMM + {24'b0, thumb_instr[7:0]}) == 0;
                cpsr[29] <= ({1'b0, `GBK_RF_THUMB_IMM} + {25'b0, thumb_instr[7:0]}) >= 33'h100000000;
                cpsr[28] <= (`GBK_RF_THUMB_IMM[31] == 1'b0) &&
                            (((`GBK_RF_THUMB_IMM + {24'b0, thumb_instr[7:0]}) & 32'h80000000) != 0);
            end else if (thumb_instr[15:11] == 5'b00111) begin
                // SUBS Rd,#imm8
                write_main(thumb_instr[10:8],`GBK_RF_THUMB_IMM - {24'b0, thumb_instr[7:0]});
                cpsr[31] <= ((`GBK_RF_THUMB_IMM - {24'b0, thumb_instr[7:0]}) & 32'h80000000) != 0;
                cpsr[30] <= (`GBK_RF_THUMB_IMM - {24'b0, thumb_instr[7:0]}) == 0;
                cpsr[29] <= `GBK_RF_THUMB_IMM >= {24'b0, thumb_instr[7:0]};
                cpsr[28] <= (`GBK_RF_THUMB_IMM[31] != 1'b0) &&
                            (((`GBK_RF_THUMB_IMM - {24'b0, thumb_instr[7:0]}) & 32'h80000000) == 0);
            end else if (thumb_instr[15:11] == 5'b00101) begin
                // CMP Rd,#imm8
                cpsr[31] <= ((`GBK_RF_THUMB_IMM - {24'b0, thumb_instr[7:0]}) & 32'h80000000) != 0;
                cpsr[30] <= (`GBK_RF_THUMB_IMM - {24'b0, thumb_instr[7:0]}) == 0;
                cpsr[29] <= `GBK_RF_THUMB_IMM >= {24'b0, thumb_instr[7:0]};
                cpsr[28] <= (`GBK_RF_THUMB_IMM[31] != 1'b0) &&
                            (((`GBK_RF_THUMB_IMM - {24'b0, thumb_instr[7:0]}) & 32'h80000000) == 0);
            end else if (thumb_instr[15:11] == 5'b10100) begin
                // ADD Rd,PC,#imm8*4 (ADR). Thumb PC reads as current+4,
                // aligned to a word boundary.
                write_main(thumb_instr[10:8],{((r[15] + 32'd4) >> 2), 2'b00} +
                    {22'b0, thumb_instr[7:0], 2'b00});
            end else if (thumb_instr[15:11] == 5'b10101) begin
                // ADD Rd,SP,#imm8*4.
                write_main(thumb_instr[10:8],r[13] +
                    {22'b0, thumb_instr[7:0], 2'b00});
            end else if (thumb_instr[15:7] == 9'b101100000) begin
                // ADD SP,#imm7*4.
                r[13] <= r[13] + {23'b0, thumb_instr[6:0], 2'b00};
            end else if (thumb_instr[15:7] == 9'b101100001) begin
                // SUB SP,#imm7*4.
                r[13] <= r[13] - {23'b0, thumb_instr[6:0], 2'b00};
            end else if (thumb_instr[15:8] == 8'hDF) begin
                // Thumb SWI enters the ARM SVC vector at 00000008.
                svc_spsr <= cpsr;
                save_bank(r[13],r[14]);
                restore_bank(5'h13,r[13],r[14],1'b0);
                switch_high_regs(5'h13); svc_lr_bank <= r[15] + 2;
                r[14] <= r[15] + 2;
                r[15] <= 32'h00000008;
                cpsr[4:0] <= 5'h13;
                cpsr[5] <= 1'b0;
                cpsr[7] <= 1'b1;
                thumb <= 1'b0;
            end else if (thumb_instr[15:11] == 5'b11100) begin
                // Unconditional B with signed 11-bit halfword offset.
                r[15] <= r[15] + 4 + {{20{thumb_instr[10]}}, thumb_instr[10:0], 1'b0};
            end else if (thumb_instr[15:11] == 5'b11110) begin
                // BL's first half writes the architectural LR. IRQ entry
                // banks it, so a callback's BL cannot destroy this target.
                r[14] <= r[15] + 4 + {{9{thumb_instr[10]}}, thumb_instr[10:0], 12'b0};
                r[15] <= r[15] + 2;
            end else if (thumb_instr[15:11] == 5'b11111) begin
                // Second half completes the target and writes the return LR.
                r[14] <= (r[15] + 2) | 32'b1;
                r[15] <= r[14] + {thumb_instr[10:0], 1'b0};
            end else if (thumb_instr[15:12] == 4'b1101 && thumb_instr[11:8] != 4'hF) begin
                if (condition_pass(thumb_instr[11:8], cpsr))
                    r[15] <= r[15] + 4 + {{23{thumb_instr[7]}}, thumb_instr[7:0], 1'b0};
            end
        end else if (exec_pending && !thumb) begin
            exec_pending <= 1'b0;
            debug_instr_reg <= instr;
            if (condition_pass(instr[31:28], cpsr)) begin
                if(arm_undefined) begin
                    take_undefined();
                end else if(privileged_bank && instr[27:26]==0 && instr[20] && rd==15 &&
                    (instr[25] || !instr[4] || !instr[7]) && (instr[24:21]<8 || instr[24:21]>11))begin
                    return_exception(alu_result,r[13],r[14]);
                end else if (instr[27:24] == 4'b1111) begin
                    // ARM SWI enters SVC mode and vectors through 00000008.
                    svc_spsr <= cpsr;
                    save_bank(r[13],r[14]);
                    restore_bank(5'h13,r[13],r[14],1'b0);
                    switch_high_regs(5'h13); svc_lr_bank <= r[15] + 4;
                    r[14] <= r[15] + 4;
                    r[15] <= 32'h00000008;
                    cpsr[4:0] <= 5'h13;
                    cpsr[5] <= 1'b0;
                    cpsr[7] <= 1'b1;
                    thumb <= 1'b0;
                end else if (instr[27:23] == 5'b00010 && instr[21:20] == 2'b00 &&
                    instr[19:16] == 4'hF && instr[11:0] == 12'b0) begin
                    // Bit 22 selects the saved status for the current exception.
                    write_main(rd,instr[22] ? current_spsr : cpsr);
                    r[15] <= r[15] + 4;
                end else if (instr[27:23] == 5'b00010 && instr[21:20] == 2'b10 &&
                             instr[15:12] == 4'hF && instr[11:4] == 8'b0) begin
                    // MSR CPSR_<fieldmask>,Rm.  The field mask is in
                    // bits 19:16; Rd is fixed to 1111 in bits 15:12.
                    if(instr[22])begin
                        case(cpsr[4:0])
                            5'h12:irq_spsr<=updated_spsr;
                            5'h13:svc_spsr<=updated_spsr;
                            5'h1b:und_spsr<=updated_spsr;
                            5'h11:fiq_spsr<=updated_spsr;
                            5'h17:abt_spsr<=updated_spsr;
                            default:begin end
                        endcase
                    end else begin
                    if (instr[19])
                        cpsr[31:28] <= `GBK_RF_RAW_RM[31:28];
                    if (instr[16] && cpsr[4:0]!=5'h10) begin
                        if (`GBK_RF_RAW_RM[4:0] != cpsr[4:0]) begin
                            save_bank(r[13],r[14]);
                            restore_bank(`GBK_RF_RAW_RM[4:0],r[13],r[14],1'b1);
                    switch_high_regs(`GBK_RF_RAW_RM[4:0]);
                        end
                        cpsr[7:0] <= `GBK_RF_RAW_RM[7:0];
                        thumb <= `GBK_RF_RAW_RM[5];
                    end
                    end
                    r[15] <= r[15] + 4;
                end else if (instr[27:25] == 3'b001 &&
                             {instr[24:23],instr[21:20]} == 4'b1010 &&
                             instr[15:12] == 4'hF) begin
                    // MSR CPSR_<fieldmask>,#rotated_imm.
                    if(instr[22])begin
                        case(cpsr[4:0])
                            5'h12:irq_spsr<=updated_spsr;
                            5'h13:svc_spsr<=updated_spsr;
                            5'h1b:und_spsr<=updated_spsr;
                            5'h11:fiq_spsr<=updated_spsr;
                            5'h17:abt_spsr<=updated_spsr;
                            default:begin end
                        endcase
                    end else begin
                    if (instr[19])
                        cpsr[31:28] <= msr_immediate[31:28];
                    if (instr[16] && cpsr[4:0]!=5'h10) begin
                        if (msr_immediate[4:0] != cpsr[4:0]) begin
                            save_bank(r[13],r[14]);
                            restore_bank(msr_immediate[4:0],r[13],r[14],1'b1);
                    switch_high_regs(msr_immediate[4:0]);
                        end
                        cpsr[7:0] <= msr_immediate[7:0];
                        thumb <= msr_immediate[5];
                    end
                    end
                    r[15] <= r[15] + 4;
                end else if (instr[27:4] == 24'h12FFF1) begin
                    thumb <= `GBK_RF_RAW_RM[0];
                    cpsr[5] <= `GBK_RF_RAW_RM[0];
                    r[15] <= {`GBK_RF_RAW_RM[31:1], 1'b0};
                end else if ((instr & 32'h0fb00ff0)==32'h01000090) begin
                    swap_active<=1;swap_write_phase<=0;data_cycle<=1;data_load<=1;
                    data_byte<=instr[22];data_half<=0;data_signed<=0;
                    data_thumb<=0;data_writeback<=0;load_rd<=rd;
                    transfer_addr<=`GBK_RF_RAW_RN;
                    swap_store<=instr[22] ? {24'd0,`GBK_RF_RAW_RM[7:0]} : `GBK_RF_RAW_RM;
                end else if (instr[27:25] == 3'b100) begin
                    block_cycle <= 1'b1;
                    block_load <= instr[20];
                    block_writeback <= instr[21] && !(instr[20] && instr[instr[19:16]]);
                    block_thumb <= 1'b0;
                    block_user_transfer<=instr[22] && !(instr[20] && (instr[15] || instr[15:0]==0));
                    block_restore_psr<=instr[22] && instr[20] && (instr[15] || instr[15:0]==0) && privileged_bank;
                    block_remaining <= instr[15:0]==0 ? 16'h8000 : instr[15:0];
                    block_first_reg<=first_reg(instr[15:0]==0 ? 16'h8000 : instr[15:0]);
                    block_count <= count_regs(instr[15:0]);
                    block_reg_index <= first_reg(instr[15:0]==0 ? 16'h8000 : instr[15:0]);
                    block_base <= `GBK_RF_RAW_RN;
                    block_base_reg <= instr[19:16];
                    block_final_base <= instr[23]
                        ? `GBK_RF_RAW_RN + (count_regs(instr[15:0]) * 4)
                        : `GBK_RF_RAW_RN - (count_regs(instr[15:0]) * 4);
                    block_addr <= block_start(`GBK_RF_RAW_RN, instr[15:0], instr[24], instr[23]);
                end else if (instr[27:23] == 5'b00001 && instr[7:4] == 4'b1001) begin
                    // ARM long multiply family.  RdLo is bits 15:12 and
                    // RdHi is bits 19:16; A selects accumulate and U selects
                    // signed operands.
                    write_main(instr[15:12],long_multiply_result[31:0]);
                    write_aux(instr[19:16],long_multiply_result[63:32]);
                    if (instr[20]) begin
                        cpsr[31] <= long_multiply_result[63];
`ifdef GBK_SAVESTATE
                        cpsr[30] <= long_multiply_zero;
`else
                        cpsr[30] <= (long_multiply_result == 0);
`endif
                    end
                    r[15] <= r[15] + 4;
                end else if (instr[27:22] == 6'b000000 && instr[7:4] == 4'b1001) begin
                    // MUL/MLA use Rd in bits 19:16 and Rn in bits 15:12.
                    write_main(instr[19:16],multiply_result);
                    if (instr[20]) begin
                        cpsr[31] <= multiply_result[31];
                        cpsr[30] <= (multiply_result == 0);
                    end
                    r[15] <= r[15] + 4;
                end else if (instr[27:25] == 3'b000 &&
                             (instr[7:4] == 4'b1011 || instr[7:4] == 4'b1101 ||
                              instr[7:4] == 4'b1111)) begin
                    debug_data_instr <= instr;
                    data_cycle <= 1'b1;
                    load_rd <= rd;
                    data_load <= instr[20];
                    data_byte <= instr[7:4] == 4'b1101;
                    data_half <= (instr[7:4] == 4'b1011) || (instr[7:4] == 4'b1111);
                    data_signed <= (instr[7:4] == 4'b1101) || (instr[7:4] == 4'b1111);
                    data_thumb <= 1'b0;
                    data_pre <= instr[24];
                    data_writeback <= !instr[24] || instr[21];
                    data_base_reg <= instr[19:16];
                end else if (instr[27:26] == 2'b00) begin
                    if (instr[24:21] != 4'b1010 && instr[24:21] != 4'b1000 &&
                        instr[24:21] != 4'b1001 && instr[24:21] != 4'b1011 &&
                        instr[15:12] != 4'hF)
                        write_main(rd,alu_result);
                    if (instr[20] || instr[24:21] == 4'b1010 ||
                        instr[24:21] == 4'b1000 || instr[24:21] == 4'b1001 ||
                        instr[24:21] == 4'b1011) begin
                        cpsr[31] <= alu_result[31];
                        cpsr[30] <= (alu_result == 0);
                        cpsr[29] <= alu_carry;
                        if (instr[24:21] == 4'b0010 || instr[24:21] == 4'b0011 ||
                            instr[24:21] == 4'b0100 || instr[24:21] == 4'b0101 ||
                            instr[24:21] == 4'b0110 || instr[24:21] == 4'b0111 ||
                            instr[24:21] == 4'b1010 || instr[24:21] == 4'b1011)
                            cpsr[28] <= alu_overflow;
                    end
                    r[15] <= r[15] + 4;
                end else if (instr[27:26] == 2'b01) begin
                    debug_data_instr <= instr;
                    data_cycle <= 1'b1;
                    load_rd <= rd;
                    data_load <= instr[20];
                    data_byte <= instr[22];
                    data_half <= 1'b0;
                    data_signed <= 1'b0;
                    data_thumb <= 1'b0;
                    data_pre <= instr[24];
                    data_writeback <= !instr[24] || instr[21];
                    data_base_reg <= instr[19:16];
                end else if (instr[27:25] == 3'b101) begin
                    if (instr[24]) r[14] <= r[15] + 4;
                    r[15] <= r[15] + 8 + {{6{instr[23]}}, instr[23:0], 2'b00};
                end else begin
                    r[15] <= r[15] + 4;
                end
            end
            if (!condition_pass(instr[31:28], cpsr))
                r[15] <= r[15] + 4;
        end
        end
        // Existing execution above must retire before the next opcode replaces
        // instr_reg. Forward its ordinary destination to the saved Rm operand.
        // Rn/Rs read the updated live register file on the following clock.
        if(overlap_issue)begin
            if(bus_ready)begin
                instr_reg<=bus_rdata;
                fetched_read_indices<=decode_read_indices(bus_rdata,thumb,overlap_pc[1]);
                fetched_rm_value<=main_write_enable &&
                    main_write_index==decode_rm_index(bus_rdata,thumb,overlap_pc[1]) ?
                    main_write_data : read_with_pc(decode_rm_index(bus_rdata,thumb,overlap_pc[1]),32'd0);
                fetched_rm_pc<=decode_rm_index(bus_rdata,thumb,overlap_pc[1])==15;
                exec_pending<=1;
                instr_fetch_pending<=0;
            end else instr_fetch_pending<=1;
        end
        if(bank_save_enable)case(cpsr[4:0])
            5'h11:begin fiq_sp_bank<=bank_save_sp;fiq_lr_bank<=bank_save_lr;end
            5'h12:begin irq_sp_bank<=bank_save_sp;irq_lr_bank<=bank_save_lr;end
            5'h13:begin svc_sp_bank<=bank_save_sp;svc_lr_bank<=bank_save_lr;end
            5'h17:begin abt_sp_bank<=bank_save_sp;abt_lr_bank<=bank_save_lr;end
            5'h1b:begin und_sp_bank<=bank_save_sp;und_lr_bank<=bank_save_lr;end
            default:begin user_sp_bank<=bank_save_sp;user_lr_bank<=bank_save_lr;end
        endcase
        if(bank_restore_enable)begin
            if(bank_restore_mode==cpsr[4:0])begin
                r[13]<=bank_same_sp;if(bank_restore_lr)r[14]<=bank_same_lr;
            end else case(bank_restore_mode)
                5'h11:begin r[13]<=fiq_sp_bank;if(bank_restore_lr)r[14]<=fiq_lr_bank;end
                5'h12:begin r[13]<=irq_sp_bank;if(bank_restore_lr)r[14]<=irq_lr_bank;end
                5'h13:begin r[13]<=svc_sp_bank;if(bank_restore_lr)r[14]<=svc_lr_bank;end
                5'h17:begin r[13]<=abt_sp_bank;if(bank_restore_lr)r[14]<=abt_lr_bank;end
                5'h1b:begin r[13]<=und_sp_bank;if(bank_restore_lr)r[14]<=und_lr_bank;end
                default:begin r[13]<=user_sp_bank;if(bank_restore_lr)r[14]<=user_lr_bank;end
            endcase
        end
        // On exception entry the new link supersedes saving the outgoing
        // same-mode LR. Retain exactly the original entry link expressions.
        if(high_switch_enable && !bank_restore_lr)case(high_new_mode)
            5'h12:irq_lr_bank<=r[15]+4;
            5'h13:svc_lr_bank<=r[15]+(thumb ? 2 : 4);
            5'h1b:und_lr_bank<=r[15]+(thumb ? 2 : 4);
            default:begin end
        endcase
        for(integer bank_index=0;bank_index<5;bank_index=bank_index+1)begin
`ifdef GBK_SAVESTATE
            if(high_switch_enable && ((cpsr[4:0]==5'h11)!=high_switch_fiq))begin
                inactive_high_bank[bank_index]<=r[8+bank_index];
                r[8+bank_index]<=inactive_high_bank[bank_index];
            end
            if(high_shadow_enable && high_shadow_index==bank_index)begin
                // Exception-return writeback belongs to the outgoing bank.
                // Once swapped, that bank is the inactive shadow. Ordinary
                // user-bank transfers in FIQ also target the inactive bank.
                // A shadow for the resulting active bank is redundant. Its
                // live values are written through write_main/write_aux, and
                // replace that shadow before any future mode switch uses it.
                if(high_shadow_fiq!=(high_switch_enable ? high_switch_fiq : (cpsr[4:0]==5'h11)))
                    inactive_high_bank[bank_index]<=high_shadow_data;
            end
`else
            if(high_switch_enable)begin
                if(cpsr[4:0]==5'h11 && !high_switch_fiq)begin
                    fiq_high_bank[bank_index]<=r[8+bank_index];r[8+bank_index]<=user_high_bank[bank_index];
                end else if(cpsr[4:0]!=5'h11 && high_switch_fiq)begin
                    user_high_bank[bank_index]<=r[8+bank_index];r[8+bank_index]<=fiq_high_bank[bank_index];
                end
            end
            if(high_shadow_enable && high_shadow_index==bank_index)begin
                if(high_shadow_fiq)fiq_high_bank[bank_index]<=high_shadow_data;
                else user_high_bank[bank_index]<=high_shadow_data;
            end
`endif
        end
        for(integer write_index=0;write_index<15;write_index=write_index+1)begin
            if(main_write_enable && main_write_index==write_index)r[write_index]<=main_write_data;
            if(aux_write_enable && aux_write_index==write_index)r[write_index]<=aux_write_data;
        end
    end
endmodule

`undef GBK_RF_RAW_RM
`undef GBK_RF_RAW_RN
`undef GBK_RF_RAW_RS
`undef GBK_RF_RAW_RD
`undef GBK_RF_THUMB_RS
`undef GBK_RF_THUMB_RD
`undef GBK_RF_THUMB_RO
`undef GBK_RF_THUMB_IMM
`undef GBK_RF_THUMB_HRD
`undef GBK_RF_THUMB_HRS
`undef GBK_RF_BLOCK
`undef GBK_RF_STORE
`undef GBK_RF_POSTBASE
