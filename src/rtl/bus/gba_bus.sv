// CPU-to-memory integration point. Device arbitration (DMA, PPU, timers,
// and cartridge wait states) will be added here as the peripheral blocks grow.
module gba_bus #(
    parameter bit RTC_PERSISTENCE=0,
    parameter bit EEPROM=0,
    parameter bit EXTERNAL_SAVE=0,
    parameter logic [31:0] RESET_PC = 32'h00000000,
    parameter logic        EXTERNAL_EWRAM = 1'b0,
    parameter logic        RENDER_SCHEDULER = 1'b0,
    parameter logic        NATIVE_TIMING = 1'b0,
    parameter logic        BLOCK_OAM = 1'b0,
    parameter bit FAST_CPU=0,
    parameter bit REGION_PROFILE=0,
    parameter integer EXECUTION_LOOKAHEAD=4,
    parameter bit EARLY_CART_RESPONSE=0,
    parameter bit EARLY_EWRAM_RESPONSE=0
) (
    input  logic clk,
`ifdef GBK_FAST_FORWARD
    input wire fast_forward,
    input wire [1:0] fast_forward_speed,
`endif
    input  logic render_clk,
    input  logic reset,
`ifdef GBK_SAVESTATE
    input wire state_cpu_request,state_dma_request,state_hold,state_reg_write,
    input wire [15:0] state_reg_addr,
    input wire [31:0] state_reg_wdata,
    output wire state_cpu_quiescent,state_dma_quiescent,state_held,state_transactions_idle,
    output reg state_reg_valid,
    output reg [31:0] state_reg_rdata,
    input wire state_save_raw_access,state_save_raw_eeprom,
    output wire state_save_raw_idle,state_save_raw_done,
    input wire state_bulk_valid,state_bulk_write,state_bulk_response_ready,
    input wire [31:0] state_bulk_addr,state_bulk_wdata,
    output wire state_bulk_ready,state_bulk_response,state_bulk_error,state_bulk_busy,
    output wire [31:0] state_bulk_rdata,
`endif
    output wire guest_stopped,
    output wire raw_stopped,
    output wire [16:0] display_position,
    input wire stop_resync_pause,
    input wire cart_rtc,rtc_host_toggle,rtc_host_valid,
    input wire [31:0] rtc_host_date,rtc_host_time,
    input wire [31:0] rtc_host_epoch,
    input wire rtc_persistence_request,
    input wire [1:0] rtc_persistence_operation,
    input wire [97:0] rtc_persistence_payload,
    output wire rtc_persistence_acknowledge,
    output wire [97:0] rtc_persistence_reply,
    input wire [3:0] link_pins_in,
    output wire [3:0] link_pins_out,link_pins_dir,
    output wire signed [15:0] audio_left, audio_right,
    output wire [287:0] debug_cycle_profile,
    output wire [319:0] debug_stall_profile,
    input  logic bios_load_clk, bios_load_reset,
    input  logic bios_load_write,
    input  logic [11:0] bios_load_addr,
    input  logic [31:0] bios_load_wdata,
    input logic save_load_write,
    input wire save_sram, save_flash512,
    input wire save_eeprom, cart_large,
    output wire save_eeprom_large,
    input logic [14:0] save_load_addr,
    input logic [31:0] save_load_wdata,
    output wire [31:0] save_load_rdata,
    input wire save_export_lock,
    output wire save_export_locked,
    input wire save_load_read,
    output wire save_load_valid, save_boot_ready, save_fault,
    output wire [16:0] save_mem_a,
    inout wire [15:0] save_mem_dq,
    output wire save_mem_oe_n, save_mem_we_n, save_mem_ub_n, save_mem_lb_n,
    input  logic [31:0] cart_rdata,
    input  logic        cart_ready,
    output logic        cart_req,
    output logic [31:0] cart_addr,
    output wire         cart_streaming,
    output logic [31:0] debug_pc,
    output logic [31:0] debug_cpsr,
    output logic [31:0] debug_instr,
    output logic [31:0] debug_r1,
    output logic [31:0] debug_r2,
    output logic [31:0] debug_r12,
    output logic [159:0] debug_bios_sound_state,
    output logic [95:0] debug_runtime_memory,
    output logic [191:0] debug_execution_state,
    output logic [31:0] debug_irq_counts,
    output logic [351:0] debug_restart_context,
    output logic debug_restart_valid,
    output logic [31:0] debug_bias_pc,
    output logic [31:0] debug_bias_instr,
    output logic [31:0] debug_bias_r1,
    output logic [31:0] debug_bias_r2,
    output logic [31:0] debug_bias_r12,
    output logic [31:0] debug_bias_count,
    output logic [15:0] debug_sound_bias,
    output logic [31:0] debug_irq_vector_write_data,
    output logic [15:0] debug_irq_vector_write_status,
    output logic [31:0] debug_irq_vector_snapshot_data,
    output logic [15:0] debug_irq_vector_snapshot_status,
    output logic [31:0] debug_io_trace,
    output logic [31:0] debug_io_read_trace,
    output logic [31:0] debug_io_write_trace,
    output logic [31:0] debug_irq_handler_read_pc,
    output logic [31:0] debug_irq_handler_read_data,
    output logic [31:0] debug_irq_probe_r0,
    output logic [31:0] debug_irq_probe_bus_addr,
    output logic [31:0] debug_irq_probe_pending_addr,
    output logic [31:0] debug_irq_probe_port_state,
    output logic [31:0] debug_irq_probe_bus_data,
    output logic [31:0] debug_irq_probe_ram_data,
    output logic [31:0] debug_irq_probe_vector_write,
    output logic [15:0] debug_irq_stage_flags,
    output logic [31:0] debug_irq_12c_instr,
    output logic [31:0] debug_irq_130_r0,
    output logic [31:0] debug_irq_130_instr,
    output logic [31:0] debug_irq_134_fetch_r0,
    output logic [31:0] debug_bios_word_12c,
    output logic [31:0] debug_dma_source, debug_dma_destination, debug_dma_status,
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
    output logic [31:0] debug_thumb_return_pop_addr,
    output logic [31:0] debug_thumb_return_pop_data,
    output logic [31:0] debug_thumb_return_fetch_word,
    output logic [31:0] debug_thumb_return_pre_bx_instr,
    output logic [15:0] debug_thumb_return_flags,
    output logic [31:0] debug_indirect_call_r0,
    output logic [31:0] debug_indirect_call_fetch_word,
    output logic [31:0] debug_indirect_call_read_addr,
    output logic [31:0] debug_indirect_call_read_data,
    output logic [15:0] debug_indirect_call_flags,
    output logic [31:0] debug_irq_callback_read_pc,
    output logic [31:0] debug_irq_callback_read_data,
    output logic [31:0] debug_irq_bx_target,
    output logic [31:0] debug_irq_first_ewram_pc,
    output logic [31:0] debug_irq_ewram_source_pc,
    output logic [31:0] debug_irq_ewram_source_instr,
    output logic [15:0] debug_irq_pending_bits,
    output logic        debug_bus_valid,
    output logic        debug_bus_write,
    output logic [1:0]  debug_bus_size,
    output logic [31:0] debug_bus_addr,
    output logic [31:0] debug_bus_wdata,
    output logic [31:0] debug_bus_rdata,
    output logic        debug_bus_ready,
    output logic        ppu_vram_write,
    output wire [15:0] ppu_mosaic,
    output logic [15:0] ppu_vram_addr,
    output logic [15:0] ppu_vram_wdata,
    input  logic [15:0] ppu_vram_read_addr,
    output logic [15:0] ppu_vram_rdata,
    output logic [15:0] ppu_vram_debug0,
    input  logic [15:0] ppu_bg_map_read_addr,
    output logic [15:0] ppu_bg_map_rdata,
    input  logic [15:0] ppu_bg_tile_read_addr,
    output logic [15:0] ppu_bg_tile_rdata,
    input  logic [15:0] ppu_bg1_map_read_addr,
    output logic [15:0] ppu_bg1_map_rdata,
    input  logic [15:0] ppu_bg1_tile_read_addr,
    output logic [15:0] ppu_bg1_tile_rdata,
    input  logic [15:0] ppu_bg2_map_read_addr,
    output logic [15:0] ppu_bg2_map_rdata,
    input  logic [15:0] ppu_bg2_tile_read_addr,
    output logic [15:0] ppu_bg2_tile_rdata,
    input  logic [15:0] ppu_bg3_map_read_addr,
    output logic [15:0] ppu_bg3_map_rdata,
    input  logic [15:0] ppu_bg3_tile_read_addr,
    output logic [15:0] ppu_bg3_tile_rdata,
    output logic [15:0] debug_bg3_tile_raw,
    input  logic [16:0] ppu_obj_tile_read_addr,
    output logic [15:0] ppu_obj_tile_rdata,
    output wire [31:0] ppu_obj_tile_word,
    output wire [15:0] ppu_obj_tile_word_addr,
    output wire ppu_obj_tile_word_valid,
    input logic [50:0] ppu_obj_window_extra_read_addr,
    output logic [47:0] ppu_obj_window_extra_read_data,
    output logic [8191:0] ppu_oam_data_flat,
    input wire [6:0] ppu_oam_read_addr,
    output wire [63:0] ppu_oam_read_data,
    input  logic [8:0]  ppu_palette_read_addr,
    output logic [15:0] ppu_palette_rdata,
    input  logic [8:0]  ppu_bg_palette_read_addr,
    output logic [15:0] ppu_bg_palette_rdata,
    output logic [15:0] ppu_backdrop_color,
    input  logic [8:0]  ppu_obj_palette_read_addr,
    output logic [15:0] ppu_obj_palette_rdata,
    output logic [15:0] ppu_dispcnt,
    output logic [15:0] ppu_bg0cnt,
    output logic [8:0]  ppu_bg0hofs,
    output logic [8:0]  ppu_bg0vofs,
    output logic [15:0] ppu_bg1cnt,
    output logic [8:0]  ppu_bg1hofs,
    output logic [8:0]  ppu_bg1vofs,
    output logic [15:0] ppu_bg2cnt,
    output logic [8:0]  ppu_bg2hofs,
    output logic [8:0]  ppu_bg2vofs,
    output logic [15:0] ppu_bg3cnt,
    output logic [8:0]  ppu_bg3hofs,
    output logic [8:0]  ppu_bg3vofs,
    output logic [15:0] ppu_bg3pa,
    output logic [15:0] ppu_bg3pb,
    output logic [15:0] ppu_bg3pc,
    output logic [15:0] ppu_bg3pd,
    output wire [15:0] ppu_bg2pa, ppu_bg2pb, ppu_bg2pc, ppu_bg2pd,
    output wire [27:0] ppu_bg2x, ppu_bg2y,
    output logic [27:0] ppu_bg3x,
    output logic [27:0] ppu_bg3y,
    output logic [15:0] ppu_win0h,
    output logic [15:0] ppu_win1h,
    output logic [15:0] ppu_win0v,
    output logic [15:0] ppu_win1v,
    output logic [15:0] ppu_winin,
    output logic [15:0] ppu_winout,
    output wire [15:0] ppu_bldcnt,ppu_bldalpha,ppu_bldy,
    input wire [8:0] ppu_second_palette_read_addr,
    output wire [15:0] ppu_second_palette_rdata,
    input  logic        ewram_ready,
    input  logic [31:0] ewram_rdata,
    output logic        ewram_req,
    output logic        ewram_write,
    output logic [31:0] ewram_addr,
    output logic [31:0] ewram_wdata,
    output logic [1:0]  ewram_size,
    input  logic [9:0]  controller_keys
);

    logic        cpu_req, cpu_write, cpu_ready;
`ifdef GBK_SAVESTATE
    // Reuse the existing CPU/scheduler/peripheral instances. No shadow machine.
    wire state_access=(state_hold===1'b1) && state_cpu_quiescent && state_dma_quiescent;
    assign state_held=state_access;
    wire state_cpu_valid,state_scheduler_valid,state_memory_valid;
    wire [31:0] state_cpu_rdata,state_scheduler_rdata,state_memory_rdata;
    wire state_power_valid;
    wire [2:0] state_power_rdata;
    wire state_bus_write=state_reg_write && state_access;
    wire state_map_idle;
    // Once parked, accesses through the shared map belong to the state copier.
    assign state_transactions_idle=state_access || (state_map_idle && !state_bulk_busy);
    always @*begin
        state_reg_valid=0;state_reg_rdata=0;
        if(state_access)case(state_reg_addr[15:8])
            0:if(state_reg_addr[7:0]<45)begin state_reg_valid=state_cpu_valid;state_reg_rdata=state_cpu_rdata;end
            1:if(state_reg_addr[7:0]<7)begin state_reg_valid=state_scheduler_valid;state_reg_rdata=state_scheduler_rdata;end
            5:if(state_reg_addr[7:0]==0)begin state_reg_valid=state_power_valid;state_reg_rdata={29'd0,state_power_rdata};end
                else begin state_reg_valid=state_memory_valid;state_reg_rdata=state_memory_rdata;end
            default:begin state_reg_valid=state_memory_valid;state_reg_rdata=state_memory_rdata;end
        endcase
    end
`endif
    logic [1:0]  cpu_size;
    logic [31:0] cpu_addr, cpu_wdata, cpu_rdata;
    logic [31:0] debug_add_input, debug_add_instr, debug_add_result;
    logic [31:0] debug_data_instr;
    logic        debug_add_event;
    logic [31:0] mem_rdata;
    logic        mem_ready;
    logic        peripheral_irq;
    wire cpu_halted,halt_wake,cpu_stopped,stop_wake,cpu_postflg;
    wire cpu_bus_lock;
    assign raw_stopped=cpu_stopped;
    assign guest_stopped=cpu_stopped || (stop_resync_pause===1'b1);
    wire execution_halted=cpu_halted || (stop_resync_pause===1'b1);
    gba_cpu_halt halt_control(.clk,.reset,.accepted(cpu_req && cpu_ready),
`ifdef GBK_SAVESTATE
        .state_hold(state_access),.state_write(state_bus_write && state_reg_addr==16'h0500),
        .state_wdata(state_reg_wdata[2:0]),.state_valid(state_power_valid),.state_rdata(state_power_rdata),
`endif
        .write(cpu_write),.size(cpu_size),.addr(cpu_addr),.wdata(cpu_wdata),
        .pc(debug_pc),.wake(halt_wake),.stop_wake,.halted(cpu_halted),.stopped(cpu_stopped),.postflg(cpu_postflg));
    logic        irq_vector_snapshot_seen;
    logic [31:0] cpu_debug_r0;
    logic [31:0] memory_probe_pending_addr;
    logic [12:0] memory_probe_iwram_index;
    logic [31:0] memory_probe_iwram_rdata;
    logic [4:0]  memory_probe_state;

    wire [31:0] research_fetch_pc;
    wire cpu_allow,dma_allow,gba_tick;
    wire timing_code,timing_thumb,timing_exec,timing_irq,timing_refill;
    wire [3:0] timing_internal_cycles;
    wire dma_timing_active,dma_timing_access,dma_timing_write;
    wire [31:0] dma_timing_addr;
    wire [1:0] dma_timing_size;
    wire [15:0] timing_waitcnt;
    gba_stall_profiler #(.ENABLED(REGION_PROFILE)) stall_profiler(
        .clk,.reset,.gba_tick,.halted(execution_halted),.cpu_req,.cpu_ready,
        .dma_active(dma_timing_active),.ewram_req,.ewram_ready,.ewram_write,
        .profile(debug_stall_profile));
    generate if(FAST_CPU) begin : native_execution
        gba_cycle_scheduler #(.REGION_PROFILE(REGION_PROFILE),.LOOKAHEAD(EXECUTION_LOOKAHEAD)) scheduler(.clk,.reset,.cpu_req,.cpu_ready,.cpu_write,
`ifdef GBK_FAST_FORWARD
            .fast_forward,
            .cpu_halted(execution_halted),
            .fast_forward_speed,
`endif
`ifdef GBK_SAVESTATE
            .state_hold(state_access),.state_write(state_bus_write && state_reg_addr[15:8]==1 && state_reg_addr[7:0]<7),
            .state_addr(state_reg_addr[3:0]),.state_wdata(state_reg_wdata),
            .state_valid(state_scheduler_valid),.state_rdata(state_scheduler_rdata),
`endif
            .cpu_code(timing_code),.cpu_thumb(timing_thumb),.cpu_exec(timing_exec),.cpu_irq(timing_irq),
            .cpu_refill(timing_refill),
            .cpu_addr(timing_code ? research_fetch_pc : cpu_addr),.cpu_size,.cpu_internal_cycles(timing_internal_cycles),
            .dma_active(dma_timing_active),.dma_access(dma_timing_access),.dma_write(dma_timing_write),
            .dma_addr(dma_timing_addr),.dma_size(dma_timing_size),.waitcnt(timing_waitcnt),
            .gba_tick,.cpu_allow,.dma_allow,.profile(debug_cycle_profile));
    end else begin : legacy_execution
`ifdef GBK_SAVESTATE
        assign state_scheduler_valid=0;assign state_scheduler_rdata=0;
`endif
        assign cpu_allow=1;assign dma_allow=1;assign gba_tick=0;assign debug_cycle_profile=0;
    end endgenerate

    arm7tdmi_core #(.RESET_PC(RESET_PC),.TIMED_EXECUTION(FAST_CPU)) cpu (
`ifdef GBK_SAVESTATE
        .state_request(state_cpu_request),.state_write(state_bus_write && state_reg_addr[15:8]==0 && state_reg_addr[7:0]<45),
        .state_addr(state_reg_addr[5:0]),.state_wdata(state_reg_wdata),
        .state_quiescent(state_cpu_quiescent),.state_valid(state_cpu_valid),.state_rdata(state_cpu_rdata),
`endif
        .clk, .reset, .halt(execution_halted),
        .research_fetch_pc(research_fetch_pc),.execution_enable(cpu_allow),.timing_code,.timing_thumb,.timing_exec,.timing_irq,.timing_internal_cycles,.timing_refill,
        .bus_valid(cpu_req), .bus_write(cpu_write), .bus_size(cpu_size),.bus_lock(cpu_bus_lock),
        .bus_addr(cpu_addr), .bus_wdata(cpu_wdata), .bus_rdata(cpu_rdata),
        .bus_ready(cpu_ready), .irq(peripheral_irq), .debug_pc,
        .debug_restart_context, .debug_restart_valid,
        .debug_r0(cpu_debug_r0), .debug_cpsr,
        .debug_instr, .debug_r1, .debug_r2, .debug_r12, .debug_bios_sound_state, .debug_execution_state, .debug_irq_counts,
        .debug_add_input, .debug_add_instr, .debug_add_result,
        .debug_add_event, .debug_data_instr,
        .debug_first_irq_entry_lr, .debug_first_irq_return_lr,
        .debug_first_irq_push_lr_addr, .debug_first_irq_push_lr_data,
        .debug_second_irq_push_lr_addr, .debug_second_irq_push_lr_data,
        .debug_first_irq_pop_lr_addr, .debug_first_irq_pop_lr_data,
        .debug_first_irq_vector_lr, .debug_first_irq_prologue_lr,
        .debug_first_irq_stack_passes,
        .debug_first_irq_progress, .debug_first_irq_last_pc,
        .debug_first_irq_134_instr, .debug_first_irq_load_state,
        .debug_first_irq_load_data, .debug_first_irq_load_target,
        .debug_bad_source_pc, .debug_bad_source_instr,
        .debug_bad_target_pc, .debug_bad_source_lr, .debug_bad_source_cpsr,
        .debug_irq_callback_read_pc, .debug_irq_callback_read_data,
        .debug_irq_bx_target, .debug_irq_first_ewram_pc,
        .debug_irq_ewram_source_pc, .debug_irq_ewram_source_instr,
        .debug_irq_pending_bits
    );

`ifdef GBK_SAVESTATE
    wire state_map_req,state_map_write,state_map_ready;
    wire [1:0] state_map_size;
    wire [31:0] state_map_addr,state_map_wdata,state_map_rdata;
    gba_state_memory_access state_ram_access(.clk,.reset,.held(state_access),
        .state_valid(state_bulk_valid),.state_write(state_bulk_write),.state_addr(state_bulk_addr),.state_wdata(state_bulk_wdata),
        .state_ready(state_bulk_ready),.state_response(state_bulk_response),.state_error(state_bulk_error),
        .busy(state_bulk_busy),.state_rdata(state_bulk_rdata),.state_response_ready(state_bulk_response_ready),
        .cpu_req,.cpu_write,.cpu_size,.cpu_addr,.cpu_wdata,.cpu_ready(mem_ready),.cpu_rdata(mem_rdata),
        .memory_req(state_map_req),.memory_write(state_map_write),.memory_size(state_map_size),
        .memory_addr(state_map_addr),.memory_wdata(state_map_wdata),.memory_ready(state_map_ready),.memory_rdata(state_map_rdata));
`endif
    gba_memory_map #(.RTC_PERSISTENCE(RTC_PERSISTENCE),.EEPROM(EEPROM),.EXTERNAL_SAVE(EXTERNAL_SAVE),.EARLY_CART_RESPONSE(EARLY_CART_RESPONSE),.EARLY_EWRAM_RESPONSE(EARLY_EWRAM_RESPONSE),.EXTERNAL_EWRAM(EXTERNAL_EWRAM), .RENDER_SCHEDULER(RENDER_SCHEDULER),
`ifdef GBK_SAVESTATE
                     .STATE_CPU_LOOKUP(1),
`endif
                     .NATIVE_TIMING(NATIVE_TIMING),.BLOCK_OAM(BLOCK_OAM),.FAST_CPU(FAST_CPU)) memory (
`ifdef GBK_SAVESTATE
        .state_dma_request,.state_hold(state_access),.state_reg_write(state_bus_write),.state_reg_addr,.state_reg_wdata,
        .state_cpu_lookup_addr(cpu_addr),
        .state_cpu_lookup_idle(!state_bulk_busy),
        .state_transactions_idle(state_map_idle),
        .state_dma_quiescent,.state_reg_valid(state_memory_valid),.state_reg_rdata(state_memory_rdata),
        .state_save_raw_access,.state_save_raw_eeprom,.state_save_raw_idle,.state_save_raw_done,
`endif
        .clk, .reset, .render_clk,.stopped(guest_stopped),.display_position,.postflg(cpu_postflg),.stop_wake,.cpu_bus_lock,
        .cart_rtc,.rtc_host_toggle,.rtc_host_valid,.rtc_host_date,.rtc_host_time,
        .rtc_host_epoch,.rtc_persistence_request,.rtc_persistence_operation,
        .rtc_persistence_payload,.rtc_persistence_acknowledge,.rtc_persistence_reply,
        .link_pins_in,.link_pins_out,.link_pins_dir,
        .gba_tick,.dma_timing_allow(dma_allow),.dma_timing_active,.dma_timing_access,.dma_timing_write,
        .dma_timing_addr,.dma_timing_size,.timing_waitcnt,
        .save_load_read,.save_load_valid,.save_boot_ready,.save_fault,
        .save_mem_a,.save_mem_dq,.save_mem_oe_n,.save_mem_we_n,.save_mem_ub_n,.save_mem_lb_n,
        .bios_load_clk, .bios_load_reset, .bios_load_write, .bios_load_addr, .bios_load_wdata,
`ifdef GBK_SAVESTATE
        .req(state_map_req),.write(state_map_write),.size(state_map_size),.addr(state_map_addr),
        .wdata(state_map_wdata),.rdata(state_map_rdata),.ready(state_map_ready),
`else
        .req(cpu_req), .write(cpu_write), .size(cpu_size), .addr(cpu_addr),
        .wdata(cpu_wdata), .rdata(mem_rdata), .ready(mem_ready),
`endif
        .cart_req, .cart_addr, .cart_streaming, .cart_rdata, .cart_ready,
        .ppu_vram_write, .ppu_vram_addr, .ppu_vram_wdata,.ppu_mosaic,
        .ppu_vram_read_addr, .ppu_vram_rdata, .ppu_vram_debug0,
        .ppu_bg_map_read_addr, .ppu_bg_map_rdata,
        .ppu_bg_tile_read_addr, .ppu_bg_tile_rdata,
        .ppu_bg1_map_read_addr, .ppu_bg1_map_rdata,
        .ppu_bg1_tile_read_addr, .ppu_bg1_tile_rdata,
        .ppu_bg2_map_read_addr, .ppu_bg2_map_rdata,
        .ppu_bg2_tile_read_addr, .ppu_bg2_tile_rdata,
        .ppu_bg3_map_read_addr, .ppu_bg3_map_rdata,
        .ppu_bg3_tile_read_addr, .ppu_bg3_tile_rdata, .debug_bg3_tile_raw,
        .ppu_obj_tile_read_addr, .ppu_obj_tile_rdata, .ppu_obj_tile_word, .ppu_obj_tile_word_addr,.ppu_obj_tile_word_valid,
        .ppu_oam_data_flat,.ppu_oam_read_addr,.ppu_oam_read_data,
        .ppu_obj_window_extra_read_addr, .ppu_obj_window_extra_read_data,
        .ppu_palette_read_addr, .ppu_palette_rdata,
        .ppu_bg_palette_read_addr, .ppu_bg_palette_rdata,
        .ppu_backdrop_color,
        .ppu_obj_palette_read_addr, .ppu_obj_palette_rdata,
        .ppu_dispcnt, .ppu_bg0cnt, .ppu_bg0hofs, .ppu_bg0vofs,
        .ppu_bg1cnt, .ppu_bg1hofs, .ppu_bg1vofs,
        .ppu_bg2cnt, .ppu_bg2hofs, .ppu_bg2vofs,
        .ppu_bg3cnt, .ppu_bg3hofs, .ppu_bg3vofs,
        .ppu_bg3pa, .ppu_bg3pb, .ppu_bg3pc, .ppu_bg3pd, .ppu_bg3x, .ppu_bg3y,
        .ppu_bg2pa, .ppu_bg2pb, .ppu_bg2pc, .ppu_bg2pd, .ppu_bg2x, .ppu_bg2y,
        .ppu_win0h, .ppu_win1h, .ppu_win0v, .ppu_win1v,
        .ppu_winin, .ppu_winout,
        .ppu_bldcnt,.ppu_bldalpha,.ppu_bldy,.ppu_second_palette_read_addr,.ppu_second_palette_rdata,
        .ewram_ready, .ewram_rdata, .ewram_req, .ewram_write,
        .ewram_addr, .ewram_wdata, .ewram_size, .controller_keys,
        .save_sram, .save_flash512, .save_eeprom, .cart_large, .save_eeprom_large, .save_load_write, .save_load_addr, .save_load_wdata,
        .save_load_rdata, .save_export_lock, .save_export_locked,
        .audio_left,.audio_right,
        .debug_sound_bias, .debug_irq_vector_write_data,
        .debug_irq_vector_write_status,
        .debug_probe_pending_addr(memory_probe_pending_addr),
        .debug_probe_iwram_index(memory_probe_iwram_index),
        .debug_probe_iwram_rdata(memory_probe_iwram_rdata),
        .debug_probe_memory_state(memory_probe_state),
        .debug_bios_word_12c,
        .debug_dma_source, .debug_dma_destination, .debug_dma_status,
        .debug_runtime_memory, .irq(peripheral_irq), .halt_wake(halt_wake)
    );

    assign cpu_rdata = mem_rdata;
    assign cpu_ready = mem_ready;

    // Simulation-only observability is intentionally exposed at the bus
    // boundary.  These signals are not required by the Pocket wrapper, but
    // make a CPU/BIOS trace reproducible without changing core behavior.
    assign debug_bus_valid = cpu_req;
    assign debug_bus_write = cpu_write;
    assign debug_bus_size  = cpu_size;
    assign debug_bus_addr  = cpu_addr;
    assign debug_bus_wdata = cpu_wdata;
    assign debug_bus_rdata = cpu_rdata;
    assign debug_bus_ready = cpu_ready;

    // BIOS 2100h returns via POP {r3}; BX r3. Capture the fetch, the
    // instruction actually executed before BX, and any data read issued
    // while PC is 2100h. Do not assume that SP points into IWRAM.
    always_ff @(posedge clk) begin
        if (reset) begin
            debug_thumb_return_pop_addr <= 32'b0;
            debug_thumb_return_pop_data <= 32'b0;
            debug_thumb_return_fetch_word <= 32'b0;
            debug_thumb_return_pre_bx_instr <= 32'b0;
            debug_thumb_return_flags <= 16'b0;
        end else begin
            if (cpu_req && !cpu_write && cpu_ready &&
                debug_pc == 32'h00002100 && cpu_addr == 32'h00002100) begin
                debug_thumb_return_flags[0] <= 1'b1;
                debug_thumb_return_fetch_word <= cpu_rdata;
            end
            if (cpu_req && !cpu_write && debug_pc == 32'h00002100 &&
                cpu_addr != 32'h00002100) begin
                debug_thumb_return_flags[1] <= 1'b1;
                debug_thumb_return_pop_addr <= cpu_addr;
                if (cpu_ready) begin
                    debug_thumb_return_flags[2] <= 1'b1;
                    debug_thumb_return_pop_data <= cpu_rdata;
                end
            end
            if (cpu_req && !cpu_write && cpu_ready &&
                debug_pc == 32'h00002102 && cpu_addr == 32'h00002100) begin
                debug_thumb_return_flags[3] <= 1'b1;
                debug_thumb_return_pre_bx_instr <= debug_instr;
            end
        end
    end

    // BIOS 1DF2h loads r3 from [r0,#28h], then BLs to the BX r3
    // trampoline at 2102h. Capture both the instruction word and the
    // completed callback-pointer read without assuming a memory region.
    always_ff @(posedge clk) begin
        if (reset) begin
            debug_indirect_call_r0 <= 32'b0;
            debug_indirect_call_fetch_word <= 32'b0;
            debug_indirect_call_read_addr <= 32'b0;
            debug_indirect_call_read_data <= 32'b0;
            debug_indirect_call_flags <= 16'b0;
        end else begin
            if (cpu_req && !cpu_write && cpu_ready &&
                debug_pc == 32'h00001df2 && cpu_addr == 32'h00001df0) begin
                debug_indirect_call_flags[0] <= 1'b1;
                debug_indirect_call_fetch_word <= cpu_rdata;
            end
            if (cpu_req && !cpu_write && debug_pc == 32'h00001df2 &&
                cpu_addr != 32'h00001df0) begin
                debug_indirect_call_flags[1] <= 1'b1;
                debug_indirect_call_r0 <= cpu_debug_r0;
                debug_indirect_call_read_addr <= cpu_addr;
                if (cpu_ready) begin
                    debug_indirect_call_flags[2] <= 1'b1;
                    debug_indirect_call_read_data <= cpu_rdata;
                end
            end
        end
    end

    // Keep the most recent I/O transaction visible to the Pocket diagnostic
    // overlay.  The top nibble identifies a read (2) or write (1), followed
    // by the low 12 bits of write data and the low 16 bits of the address.
    always_ff @(posedge clk) begin
        if (reset)
            begin
                debug_io_trace <= 32'b0;
                debug_io_read_trace <= 32'b0;
                debug_io_write_trace <= 32'b0;
                debug_bias_pc <= 32'b0;
                debug_bias_instr <= 32'b0;
                debug_bias_r1 <= 32'b0;
                debug_bias_r2 <= 32'b0;
                debug_bias_r12 <= 32'b0;
                debug_bias_count <= 32'b0;
                debug_irq_handler_read_pc <= 32'b0;
                debug_irq_handler_read_data <= 32'b0;
                debug_irq_vector_snapshot_data <= 32'b0;
                debug_irq_vector_snapshot_status <= 16'b0;
                debug_irq_probe_r0 <= 32'b0;
                debug_irq_probe_bus_addr <= 32'b0;
                debug_irq_probe_pending_addr <= 32'b0;
                debug_irq_probe_port_state <= 32'b0;
                debug_irq_probe_bus_data <= 32'b0;
                debug_irq_probe_ram_data <= 32'b0;
                debug_irq_probe_vector_write <= 32'b0;
                debug_irq_stage_flags <= 16'b0;
                debug_irq_12c_instr <= 32'b0;
                debug_irq_130_r0 <= 32'b0;
                debug_irq_130_instr <= 32'b0;
                debug_irq_134_fetch_r0 <= 32'b0;
                irq_vector_snapshot_seen <= 1'b0;
            end
        else begin
        // Track the instruction fetches of the current BIOS IRQ pass.  A
        // successful read at 134h is not enough: the required MOV at 12Ch
        // must have executed and changed R0 before the handler load.
        if (cpu_req && !cpu_write && cpu_ready &&
            cpu_addr == debug_pc && debug_bad_target_pc == 32'b0) begin
            if (debug_pc == 32'h00000128) begin
                debug_irq_stage_flags <= 16'h0001;
                debug_irq_12c_instr <= 32'b0;
                debug_irq_130_r0 <= 32'b0;
                debug_irq_130_instr <= 32'b0;
                debug_irq_134_fetch_r0 <= 32'b0;
            end else if (debug_pc == 32'h0000012c) begin
                debug_irq_stage_flags[1] <= 1'b1;
                debug_irq_12c_instr <= cpu_rdata;
            end else if (debug_pc == 32'h00000130) begin
                debug_irq_stage_flags[2] <= 1'b1;
                debug_irq_130_r0 <= cpu_debug_r0;
                debug_irq_130_instr <= cpu_rdata;
            end else if (debug_pc == 32'h00000134) begin
                debug_irq_stage_flags[3] <= 1'b1;
                debug_irq_134_fetch_r0 <= cpu_debug_r0;
            end
        end
        // Capture every completed BIOS IRQ handler load until the first
        // invalid jump. This includes the failing transaction even when its
        // address is wrong, unlike the exact-address vector trace below.
        if (cpu_req && !cpu_write && cpu_ready &&
            debug_pc == 32'h00000134 && debug_bad_target_pc == 32'b0) begin
            debug_irq_probe_r0 <= cpu_debug_r0;
            debug_irq_probe_bus_addr <= cpu_addr;
            debug_irq_probe_pending_addr <= memory_probe_pending_addr;
            // Low 16 bits: valid, DMA owner, physical word index, and
            // whether the vector word has ever been written.
            debug_irq_probe_port_state <= {16'b0, 1'b1,
                                           memory_probe_state[4],
                                           memory_probe_iwram_index,
                                           (|debug_irq_vector_write_status)};
            debug_irq_probe_bus_data <= cpu_rdata;
            debug_irq_probe_ram_data <= memory_probe_iwram_rdata;
            debug_irq_probe_vector_write <= debug_irq_vector_write_data;
            debug_irq_stage_flags[4] <= 1'b1;
        end
        // The BIOS IRQ vector at 00000134 loads PC from 03FFFFFC.  Keep the
        // completed read visible after execution has jumped elsewhere.
        if (cpu_req && !cpu_write && cpu_ready && cpu_addr == 32'h03FFFFFC) begin
            debug_irq_handler_read_pc <= debug_pc;
            debug_irq_handler_read_data <= cpu_rdata;
            if (!irq_vector_snapshot_seen && debug_pc == 32'h00000134) begin
                debug_irq_vector_snapshot_data <= debug_irq_vector_write_data;
                debug_irq_vector_snapshot_status <= debug_irq_vector_write_status;
                irq_vector_snapshot_seen <= 1'b1;
            end
        end
        if (cpu_req && cpu_addr[31:24] == 8'h04) begin
            if (cpu_write) begin
                debug_io_trace <= {4'h1, cpu_wdata[11:0], cpu_addr[15:0]};
                debug_io_write_trace <= {4'h1, cpu_wdata[11:0], cpu_addr[15:0]};
                if (cpu_addr == 32'h04000088) begin
                    // Snapshot the state at the BIOS SOUNDBIAS write so the
                    // diagnostic overlay does not chase every CPU cycle.
                    debug_bias_r2 <= debug_r2;
                    debug_bias_count <= debug_bias_count + 1'b1;
                end
            end else if (cpu_ready) begin
                // On reads, cpu_wdata is unrelated/stale.  Capture the
                // returned bus value only when the memory cycle completes.
                debug_io_trace <= {4'h2, cpu_rdata[11:0], cpu_addr[15:0]};
                debug_io_read_trace <= {4'h2, cpu_rdata[11:0], cpu_addr[15:0]};
                if (cpu_addr == 32'h04000088)
                    // Row 5 shows the instruction latched when the CPU
                    // launched the read, not a response-time debug value.
                    debug_bias_r12 <= debug_data_instr;
            end
        end
        if (debug_add_event) begin
            // Keep only the targeted BIOS ADDS r2,#2 operands/results.  The
            // delay loop also uses Thumb add/sub instructions and must not
            // overwrite this diagnostic between the add and the store.
            debug_bias_pc <= debug_add_input;
            debug_bias_instr <= debug_add_instr;
            debug_bias_r1 <= debug_add_result;
        end
        end
    end
endmodule
