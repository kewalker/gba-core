// Integrated CPU, GBA memory map, and mode-3 PPU.
module gba_system_top #(
    parameter bit RTC_PERSISTENCE=0,
    parameter bit EEPROM=0,
    parameter bit EXTERNAL_SAVE=0,
    parameter logic [31:0] RESET_PC = 32'h00000000,
    parameter logic        EXTERNAL_CARTRIDGE = 1'b0,
    parameter logic        EXTERNAL_EWRAM = 1'b0,
    parameter logic        RENDER_SCHEDULER = 1'b0,
    parameter logic        NATIVE_TIMING = 1'b0,
    parameter bit FAST_CPU=0,
    parameter bit REGION_PROFILE=0,
    parameter bit ROM_PROFILE=0,
    parameter integer EXECUTION_LOOKAHEAD=16,
    parameter integer ROM_READ_WAIT_CYCLES=3,
    parameter bit SDRAM_EWRAM=0,SDRAM_ROM=0,EWRAM_BURST_FILL=0,ROM_DIRECT_BURST=0,ROM_FILL_NEIGHBOR=0
) (
    input  logic clk,
`ifdef GBK_FAST_FORWARD
    input wire fast_forward,fast_forward_realign,
    input wire fast_forward_mute,
    input wire [1:0] fast_forward_speed,
`endif
`ifdef GBK_SAVESTATE
    // Execution-clock-domain state control and one shared 32-bit register bus.
    input wire state_cpu_request,state_dma_request,state_hold,state_reg_write,
    input wire [15:0] state_reg_addr,
    input wire [31:0] state_reg_wdata,
    output wire state_cpu_quiescent,state_dma_quiescent,state_held,state_reg_valid,
    output wire state_transactions_idle,state_resume_ready,state_resume_complete,
    input wire state_resume_prepare,
    output wire [31:0] state_reg_rdata,
    // Host-clock signals for exclusive raw save-port ownership; guest save
    // type and the ordinary mirrored pre-discovery import remain unchanged.
    input wire state_save_raw_access,state_save_raw_eeprom,
    output wire state_save_raw_idle,state_save_raw_done,
    input wire state_bulk_valid,state_bulk_write,state_bulk_response_ready,
    input wire [31:0] state_bulk_addr,state_bulk_wdata,
    output wire state_bulk_ready,state_bulk_response,state_bulk_error,state_bulk_busy,
    output wire [31:0] state_bulk_rdata,
    // Memory-clock-domain state client. No duplicate SDRAM controller/backend.
    // Exclusive mode requires a frozen guest. Background mode arbitrates only
    // bounded state-pool traffic alongside the existing ROM/EWRAM clients.
    input wire state_memory_enable,state_memory_background,state_memory_valid,state_memory_write,
    input wire [24:0] state_memory_addr,
    input wire [31:0] state_memory_wdata,
    input wire [3:0] state_memory_byteena,
    output wire state_memory_ready,state_memory_response,
    output wire [63:0] state_memory_rdata,
    input wire state_memory_response_ready,
`endif
    input wire cpu_clk,
    output wire [287:0] debug_cycle_profile,
    output wire [319:0] debug_rom_profile,
    output wire [319:0] debug_stall_profile,
    input  logic fast_clk,
    input  logic reset,
    input wire rtc_host_toggle,rtc_host_valid,
    input wire [31:0] rtc_host_date,rtc_host_time,
    input wire [31:0] rtc_host_epoch,
    input wire rtc_persistence_request,
    input wire [1:0] rtc_persistence_operation,
    input wire [97:0] rtc_persistence_payload,
    output wire rtc_persistence_acknowledge,
    output wire [97:0] rtc_persistence_reply,
    input wire [3:0] link_pins_in,
    output wire [3:0] link_pins_out,link_pins_dir,
    output wire guest_stopped,
    output wire signed [15:0] audio_left, audio_right,
    input  logic [31:0] controller_keys,
    input  logic        cart_load_clk,
    input  logic        cart_load_reset,
    input  logic        cart_load_write,
    input  logic [22:0] cart_load_addr,
    input  logic [31:0] cart_load_wdata,
    input  logic        bios_load_write,
    input  logic [11:0] bios_load_addr,
    input  logic [31:0] bios_load_wdata,
    input logic save_load_write,
    output wire save_sram,
    output wire save_eeprom,save_eeprom_large,
    input wire cart_large,
    input logic [14:0] save_load_addr,
    input logic [31:0] save_load_wdata,
    output wire [31:0] save_load_rdata,
    input wire save_export_lock,
    output wire save_export_locked,
    output logic        cart_req,
    output logic [31:0] cart_addr,
    output logic [31:0] cart_rdata,
    output logic        cart_ready,
    output logic [8:0]  video_r,
    output logic [8:0]  video_g,
    output logic [8:0]  video_b,
    output logic        video_de,
    output logic        video_hsync,
    output logic        video_vsync,
    output wire         video_skip,
    output logic [15:0] debug_ppu_dispcnt,
    output logic [15:0] debug_ppu_bg0cnt,
    output logic [15:0] debug_ppu_bg1cnt,
    output logic [15:0] debug_ppu_bg2cnt,
    output logic [15:0] debug_ppu_bg3cnt,
    output logic [31:0] debug_bg3_matrix,
    output logic [31:0] debug_bg3_reference,
    output logic [31:0] debug_dma_source, debug_dma_destination, debug_dma_status,
    output logic [31:0] debug_bg3_map,
    output logic [31:0] debug_bg3_tile,
    output logic [15:0] debug_bg3_tile_raw,
    output logic [15:0] debug_mode2_status,
    output logic [31:0] debug_mode2_window,
    output logic [31:0] debug_pc,
    output logic [31:0] debug_cpsr,
    output logic [31:0] debug_instr,
    output logic [31:0] debug_r1,
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
    output logic [21:16] cram_a,
    inout  wire  [15:0] cram_dq,
    input wire save_load_read,
    output wire save_load_valid, save_boot_ready, save_fault,
    output wire [16:0] save_mem_a,
    inout wire [15:0] save_mem_dq,
    output wire save_mem_oe_n, save_mem_we_n, save_mem_ub_n, save_mem_lb_n,
    input  wire         cram_wait,
    output logic        cram_clk,
    output logic        cram_adv_n,
    output logic        cram_cre,
    output logic        cram_ce0_n,
    output logic        cram_ce1_n,
    output logic        cram_oe_n,
    output logic        cram_we_n,
    output logic        cram_ub_n,
    output logic        cram_lb_n
    ,output logic [21:16] ewram_cram_a
    ,inout  wire  [15:0] ewram_cram_dq
    ,input  wire         ewram_cram_wait
    ,output logic        ewram_cram_clk
    ,output logic        ewram_cram_adv_n
    ,output logic        ewram_cram_cre
    ,output logic        ewram_cram_ce0_n
    ,output logic        ewram_cram_ce1_n
    ,output logic        ewram_cram_oe_n
    ,output logic        ewram_cram_we_n
    ,output logic        ewram_cram_ub_n
    ,output logic        ewram_cram_lb_n
    ,input wire sdram_reset
    ,output wire sdram_initialized
    ,output wire [12:0] dram_a
    ,output wire [1:0] dram_ba,dram_dqm
    ,inout wire [15:0] dram_dq
    ,output wire dram_cke,dram_ras_n,dram_cas_n,dram_we_n
);
    logic        ppu_vram_write;
    logic [15:0] ppu_vram_addr;
    logic [15:0] ppu_vram_wdata;
    logic [15:0] ppu_vram_read_addr;
    logic [15:0] ppu_vram_rdata;
    logic [15:0] ppu_vram_debug0;
    logic [15:0] ppu_bg_map_read_addr;
    logic [15:0] ppu_bg_map_rdata;
    logic [15:0] ppu_bg_tile_read_addr;
    logic [15:0] ppu_bg_tile_rdata;
    logic [15:0] ppu_bg1_map_read_addr;
    logic [15:0] ppu_bg1_map_rdata;
    logic [15:0] ppu_bg1_tile_read_addr;
    logic [15:0] ppu_bg1_tile_rdata;
    logic [15:0] ppu_bg2_map_read_addr;
    logic [15:0] ppu_bg2_map_rdata;
    logic [15:0] ppu_bg2_tile_read_addr;
    logic [15:0] ppu_bg2_tile_rdata;
    logic [15:0] ppu_bg3_map_read_addr;
    logic [15:0] ppu_bg3_map_rdata;
    logic [15:0] ppu_bg3_tile_read_addr;
    logic [15:0] ppu_bg3_tile_rdata;
    logic [16:0] ppu_obj_tile_read_addr;
    logic [15:0] ppu_obj_tile_rdata;
    wire [31:0] ppu_obj_tile_word;
    wire [15:0] ppu_obj_tile_word_addr;
    wire ppu_obj_tile_word_valid;
    wire [50:0] ppu_obj_window_extra_read_addr;
    wire [47:0] ppu_obj_window_extra_read_data;
    logic [8191:0] ppu_oam_data_flat;
    wire [6:0] ppu_oam_read_addr;
    wire [63:0] ppu_oam_read_data;
    logic [8:0]  ppu_palette_read_addr;
    logic [15:0] ppu_palette_rdata;
    logic [8:0]  ppu_bg_palette_read_addr;
    logic [15:0] ppu_bg_palette_rdata;
    logic [15:0] ppu_backdrop_color;
    logic [8:0]  ppu_obj_palette_read_addr;
    logic [15:0] ppu_obj_palette_rdata;
    logic [15:0] ppu_dispcnt;
    wire [15:0] ppu_mosaic;
    logic [15:0] ppu_bg0cnt;
    logic [8:0]  ppu_bg0hofs;
    logic [8:0]  ppu_bg0vofs;
    logic [15:0] ppu_bg1cnt;
    logic [8:0]  ppu_bg1hofs;
    logic [8:0]  ppu_bg1vofs;
    logic [15:0] ppu_bg2cnt;
    logic [8:0]  ppu_bg2hofs;
    logic [8:0]  ppu_bg2vofs;
    logic [15:0] ppu_bg3cnt;
    logic [15:0] ppu_bg3pa, ppu_bg3pb, ppu_bg3pc, ppu_bg3pd;
    logic [27:0] ppu_bg3x, ppu_bg3y;
    wire [15:0] ppu_bg2pa,ppu_bg2pb,ppu_bg2pc,ppu_bg2pd;
    wire [27:0] ppu_bg2x,ppu_bg2y;
    assign debug_ppu_dispcnt = ppu_dispcnt;
    assign debug_ppu_bg0cnt = ppu_bg0cnt;
    assign debug_ppu_bg1cnt = ppu_bg1cnt;
    assign debug_ppu_bg2cnt = ppu_bg2cnt;
    assign debug_ppu_bg3cnt = ppu_bg3cnt;
    assign debug_bg3_matrix = {ppu_bg3pa, ppu_bg3pd};
    assign debug_bg3_reference = {ppu_bg3x[15:0], ppu_bg3y[15:0]};
    assign debug_bg3_map = {ppu_bg3_map_read_addr, ppu_bg3_map_rdata};
    assign debug_bg3_tile = {ppu_bg3_tile_read_addr, ppu_bg3_tile_rdata};
    logic [8:0]  ppu_bg3hofs;
    logic [8:0]  ppu_bg3vofs;
    logic [15:0] ppu_win0h, ppu_win1h, ppu_win0v, ppu_win1v;
    logic [15:0] ppu_winin, ppu_winout;
    wire [15:0] ppu_bldcnt,ppu_bldalpha,ppu_bldy,ppu_second_palette_rdata;
    wire [8:0] ppu_second_palette_read_addr;
    logic        ewram_ready;
    logic [31:0] ewram_rdata;
    logic        ewram_req, ewram_write;
    logic [31:0] ewram_addr, ewram_wdata;
    logic [1:0]  ewram_size;

    logic ppu_pixel_ce;
    wire execution_clk=FAST_CPU ? cpu_clk : clk;
    wire raw_stopped,stop_resync_pause,stop_resync_blank;
    wire [16:0] guest_display_position,host_display_position;
`ifdef GBK_SAVESTATE
    wire state_video_blank,state_video_invalidate,state_render_invalidate;
    wire state_bus_idle,state_rom_cpu_idle,state_rom_memory_idle,state_ewram_idle,state_ram_cdc_idle;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
        reg [2:0] state_rom_idle_sync;
    always @(posedge execution_clk)begin
        if(reset)state_rom_idle_sync<=0;
        else state_rom_idle_sync<={state_rom_idle_sync[1:0],state_rom_memory_idle};
    end
    // All terms are execution-clock signals. The physical ROM owner reports
    // its idle state from the loader clock through a dedicated synchronizer.
    // Once held, later EWRAM/map operations belong exclusively to the copier.
    assign state_transactions_idle=state_held || (state_bus_idle && state_rom_cpu_idle &&
        state_rom_idle_sync[2] && state_ewram_idle && state_ram_cdc_idle);
    gba_state_video state_video(.host_clk(cart_load_clk),.video_clk(clk),.render_clk(fast_clk),.reset,
        .state_hold(state_held),.prepare(state_resume_prepare),.guest_position(guest_display_position),
        .host_position(host_display_position),.ready(state_resume_ready),
        .release_done(state_resume_complete),
        .video_invalidate(state_video_invalidate),.render_invalidate(state_render_invalidate),.blank(state_video_blank));
`endif
    generate if(FAST_CPU && NATIVE_TIMING) begin : native_stop_alignment
        gba_stop_resync alignment(.cpu_clk(execution_clk),.video_clk(clk),
`ifdef GBK_SAVESTATE
            .reset(reset || (state_hold===1'b1)),
`else
            .reset,
`endif
`ifdef GBK_FAST_FORWARD
            .raw_stop(raw_stopped || fast_forward_realign===1'b1),.guest_position(guest_display_position),
`else
            .raw_stop(raw_stopped),.guest_position(guest_display_position),
`endif
            .host_position(host_display_position),.cpu_pause(stop_resync_pause),
            .video_blank(stop_resync_blank));
    end else begin : legacy_stop_alignment
        assign stop_resync_pause=1'b0;
        assign stop_resync_blank=1'b0;
    end endgenerate
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] stop_video_sync;
    always @(posedge fast_clk) begin
        if(reset) stop_video_sync<=0;
        else stop_video_sync<={stop_video_sync[0],guest_stopped};
    end
    wire [8:0] guest_video_r,guest_video_g,guest_video_b;
    // Keep host scanout cadence during STOP; only guest peripherals pause.
`ifdef GBK_SAVESTATE
    assign video_r=(state_video_blank || stop_video_sync[1] || stop_resync_blank) ? 9'h1ff : guest_video_r;
    assign video_g=(state_video_blank || stop_video_sync[1] || stop_resync_blank) ? 9'h1ff : guest_video_g;
    assign video_b=(state_video_blank || stop_video_sync[1] || stop_resync_blank) ? 9'h1ff : guest_video_b;
`else
    assign video_r=(stop_video_sync[1] || stop_resync_blank) ? 9'h1ff : guest_video_r;
    assign video_g=(stop_video_sync[1] || stop_resync_blank) ? 9'h1ff : guest_video_g;
    assign video_b=(stop_video_sync[1] || stop_resync_blank) ? 9'h1ff : guest_video_b;
`endif
    logic [23:0] pixel_phase;
    always_ff @(posedge fast_clk) begin
        if (reset) begin
            pixel_phase <= 0;
            ppu_pixel_ce <= 1'b0;
        end else if (RENDER_SCHEDULER) begin
            if (pixel_phase >= 24'd13312000) begin
                pixel_phase <= pixel_phase - 24'd13312000 + 24'd1228800;
                ppu_pixel_ce <= 1'b1;
            end else begin
                pixel_phase <= pixel_phase + 24'd1228800;
                ppu_pixel_ce <= 1'b0;
            end
        end else begin
            pixel_phase <= 0;
            ppu_pixel_ce <= 1'b1;
        end
    end

    wire save_flash512;
`ifdef GBK_FAST_FORWARD
    wire signed [15:0] guest_audio_left,guest_audio_right;
    wire fast_audio_muted=(fast_forward===1'b1 && fast_forward_mute===1'b1) || stop_resync_pause;
    assign audio_left=fast_audio_muted ? 16'sd0 : guest_audio_left;
    assign audio_right=fast_audio_muted ? 16'sd0 : guest_audio_right;
`endif
    gba_save_type save_type(.clk(cart_load_clk),.reset(cart_load_reset),
        .load_write(cart_load_write),.load_addr(cart_load_addr),
        .load_wdata(cart_load_wdata),.save_sram,.save_eeprom,.save_flash512);
    wire cart_rtc;
    gba_rtc_signature rtc_signature(.clk(cart_load_clk),.reset(cart_load_reset),
        .load_write(cart_load_write),.load_addr(cart_load_addr),.load_wdata(cart_load_wdata),.enabled(cart_rtc));

    // Only the external cartridge guarantees registered ready and data in
    // execution_clk. Keep the reference cartridge's legacy response staging.
    gba_bus #(.RTC_PERSISTENCE(RTC_PERSISTENCE),.EEPROM(EEPROM),.EXTERNAL_SAVE(EXTERNAL_SAVE),.EARLY_CART_RESPONSE(EXTERNAL_CARTRIDGE),.EARLY_EWRAM_RESPONSE(EXTERNAL_EWRAM),.RESET_PC(RESET_PC), .EXTERNAL_EWRAM(EXTERNAL_EWRAM),
              .RENDER_SCHEDULER(RENDER_SCHEDULER), .NATIVE_TIMING(NATIVE_TIMING),
              .BLOCK_OAM(RENDER_SCHEDULER && NATIVE_TIMING),.FAST_CPU(FAST_CPU),.REGION_PROFILE(REGION_PROFILE),
              .EXECUTION_LOOKAHEAD(EXECUTION_LOOKAHEAD)) bus (
`ifdef GBK_SAVESTATE
        .state_cpu_request,.state_dma_request,.state_hold,.state_reg_write,.state_reg_addr,.state_reg_wdata,
        .state_save_raw_access,.state_save_raw_eeprom,.state_save_raw_idle,.state_save_raw_done,
        .state_cpu_quiescent,.state_dma_quiescent,.state_held,.state_reg_valid,.state_reg_rdata,
        .state_transactions_idle(state_bus_idle),
        .state_bulk_valid,.state_bulk_write,.state_bulk_response_ready,.state_bulk_addr,.state_bulk_wdata,
        .state_bulk_ready,.state_bulk_response,.state_bulk_error,.state_bulk_busy,.state_bulk_rdata,
`endif
        .clk(execution_clk), .render_clk(fast_clk), .reset,.guest_stopped,
`ifdef GBK_FAST_FORWARD
        .fast_forward,
        .fast_forward_speed,
`endif
        .raw_stopped,.stop_resync_pause,.display_position(guest_display_position),.debug_cycle_profile,.debug_stall_profile,
        .cart_rtc,.rtc_host_toggle,.rtc_host_valid,.rtc_host_date,.rtc_host_time,
        .rtc_host_epoch,.rtc_persistence_request,.rtc_persistence_operation,
        .rtc_persistence_payload,.rtc_persistence_acknowledge,.rtc_persistence_reply,
        .link_pins_in,.link_pins_out,.link_pins_dir,
`ifdef GBK_FAST_FORWARD
        .audio_left(guest_audio_left),.audio_right(guest_audio_right),
`else
        .audio_left,.audio_right,
`endif
        .save_load_read,.save_load_valid,.save_boot_ready,.save_fault,
        .save_mem_a,.save_mem_dq,.save_mem_oe_n,.save_mem_we_n,.save_mem_ub_n,.save_mem_lb_n,
        .bios_load_clk(cart_load_clk), .bios_load_reset(cart_load_reset), .bios_load_write, .bios_load_addr, .bios_load_wdata,
        .debug_restart_context, .debug_restart_valid,
        .cart_rdata, .cart_ready, .cart_req, .cart_addr, .cart_streaming,
        .debug_dma_source, .debug_dma_destination, .debug_dma_status,
        .debug_pc, .debug_cpsr, .debug_instr, .debug_r1, .debug_bios_sound_state, .debug_execution_state, .debug_runtime_memory, .debug_irq_counts,
        .debug_bias_pc, .debug_bias_instr, .debug_bias_r1, .debug_bias_r2,
        .debug_bias_r12,
        .debug_bias_count,
        .debug_sound_bias, .debug_irq_vector_write_data,
        .debug_irq_vector_write_status,
        .debug_irq_vector_snapshot_data, .debug_irq_vector_snapshot_status,
        .debug_io_trace,
        .debug_io_read_trace, .debug_io_write_trace,
        .debug_irq_handler_read_pc, .debug_irq_handler_read_data,
        .debug_irq_probe_r0, .debug_irq_probe_bus_addr,
        .debug_irq_probe_pending_addr, .debug_irq_probe_port_state,
        .debug_irq_probe_bus_data, .debug_irq_probe_ram_data,
        .debug_irq_probe_vector_write,
        .debug_irq_stage_flags, .debug_irq_12c_instr,
        .debug_irq_130_r0, .debug_irq_130_instr,
        .debug_irq_134_fetch_r0,
        .debug_bios_word_12c,
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
        .debug_thumb_return_pop_addr, .debug_thumb_return_pop_data,
        .debug_thumb_return_fetch_word, .debug_thumb_return_pre_bx_instr,
        .debug_thumb_return_flags,
        .debug_indirect_call_r0, .debug_indirect_call_fetch_word,
        .debug_indirect_call_read_addr, .debug_indirect_call_read_data,
        .debug_indirect_call_flags,
        .debug_irq_callback_read_pc, .debug_irq_callback_read_data,
        .debug_irq_bx_target, .debug_irq_first_ewram_pc,
        .debug_irq_ewram_source_pc, .debug_irq_ewram_source_instr,
        .debug_irq_pending_bits,
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
        .ewram_addr, .ewram_wdata, .ewram_size, .controller_keys(controller_keys[9:0]),
        .save_sram, .save_flash512, .save_eeprom, .cart_large, .save_eeprom_large, .save_load_write, .save_load_addr, .save_load_wdata,
        .save_load_rdata, .save_export_lock, .save_export_locked
    );

    wire cart_streaming;
    wire rom_memory_valid,rom_memory_ready,rom_memory_write,rom_response,rom_response_ready;
    wire [24:0] rom_memory_addr;
    wire [31:0] rom_memory_wdata;
    wire [3:0] rom_memory_byteena;
    wire ram_cache_req,ram_cache_write,ram_cache_ready;
    wire [31:0] ram_cache_addr,ram_cache_wdata;
    wire [1:0] ram_cache_size;
    wire [63:0] ram_cache_rdata,memory_rdata;
`ifdef GBK_SAVESTATE
    assign state_memory_rdata=memory_rdata;
`endif
    wire ram_memory_valid,ram_memory_ready,ram_memory_write,ram_response,ram_response_ready;
    wire [24:0] ram_memory_addr;
    wire [31:0] ram_memory_wdata;
    wire [3:0] ram_memory_byteena;
    wire memory_valid,memory_ready,memory_write,memory_response,memory_response_ready;
    wire [24:0] memory_addr;
    wire [31:0] memory_wdata;
    wire [3:0] memory_byteena;
    reg [31:0] aligned_ram_wdata;
    reg [3:0] aligned_ram_byteena;
    always_comb begin
        aligned_ram_wdata=ram_cache_wdata;aligned_ram_byteena=4'b1111;
        if(ram_cache_size==1) begin
            aligned_ram_wdata=ram_cache_wdata<<(ram_cache_addr[1]*16);
            aligned_ram_byteena=ram_cache_addr[1] ? 4'b1100 : 4'b0011;
        end else if(ram_cache_size==0) begin
            aligned_ram_wdata=ram_cache_wdata<<(ram_cache_addr[1:0]*8);
            aligned_ram_byteena=4'b0001<<ram_cache_addr[1:0];
        end
    end
    initial if((SDRAM_EWRAM && !EXTERNAL_EWRAM) || (SDRAM_ROM && !EXTERNAL_CARTRIDGE))
        $error("SDRAM backend requires the external-memory bus contract");
    generate if(SDRAM_EWRAM) begin : sdram_ewram_bridge
        gba_sdram_cdc bridge(.client_clk(execution_clk),.memory_clk(cart_load_clk),.reset(sdram_reset),.client_reset(reset),
`ifdef GBK_SAVESTATE
            .state_client_idle(state_ram_cdc_idle),
`endif
            .client_req(ram_cache_req),.client_write(ram_cache_write),
            .client_addr({1'b1,7'd0,ram_cache_addr[17:2],1'b0}),
            .client_wdata(aligned_ram_wdata),.client_byteena(aligned_ram_byteena),
            .client_ready(ram_cache_ready),.client_rdata(ram_cache_rdata),
            .memory_valid(ram_memory_valid),.memory_ready(ram_memory_ready),.memory_write(ram_memory_write),
            .memory_addr(ram_memory_addr),.memory_wdata(ram_memory_wdata),.memory_byteena(ram_memory_byteena),
            .response_valid(ram_response),.response_ready(ram_response_ready),.response_data(memory_rdata));
    end else begin : no_sdram_ewram_bridge
`ifdef GBK_SAVESTATE
        assign state_ram_cdc_idle=1'b1;
`endif
        assign ram_memory_valid=0;assign ram_memory_write=0;assign ram_memory_addr=0;
        assign ram_memory_wdata=0;assign ram_memory_byteena=0;assign ram_response_ready=0;
        assign ram_cache_ready=0;assign ram_cache_rdata=0;
    end endgenerate
    generate if(SDRAM_EWRAM || SDRAM_ROM) begin : sdram_memory
        gba_sdram_arbiter arbiter(.clk(cart_load_clk),.reset(sdram_reset),
`ifdef GBK_SAVESTATE
            .state_enable(state_memory_enable),.state_valid(state_memory_valid),.state_write(state_memory_write),
            .state_background(state_memory_background),
            .state_addr(state_memory_addr),.state_wdata(state_memory_wdata),.state_byteena(state_memory_byteena),
            .state_ready(state_memory_ready),.state_response(state_memory_response),.state_response_ready(state_memory_response_ready),
`endif
            .rom_valid(rom_memory_valid),.rom_ready(rom_memory_ready),.rom_write(rom_memory_write),
            .rom_addr(rom_memory_addr),.rom_wdata(rom_memory_wdata),.rom_byteena(rom_memory_byteena),
            .rom_response,.rom_response_ready,
            .ram_valid(ram_memory_valid),.ram_ready(ram_memory_ready),.ram_write(ram_memory_write),
            .ram_addr(ram_memory_addr),.ram_wdata(ram_memory_wdata),.ram_byteena(ram_memory_byteena),
            .ram_response,.ram_response_ready,
            .memory_valid,.memory_ready,.memory_write,.memory_addr,.memory_wdata,.memory_byteena,
            .response_valid(memory_response),.response_ready(memory_response_ready));
        gba_sdram_controller controller(.clk(cart_load_clk),.reset(sdram_reset),
            .req_valid(memory_valid),.req_ready(memory_ready),.req_write(memory_write),.req_addr(memory_addr),
            .req_wdata(memory_wdata),.req_byteena(memory_byteena),.rsp_valid(memory_response),
            .rsp_ready(memory_response_ready),.rsp_data(memory_rdata),.initialized(sdram_initialized),.refresh_pulse(),
            .dram_a,.dram_ba,.dram_dqm,.dram_dq,.dram_cke,.dram_ras_n,.dram_cas_n,.dram_we_n);
    end else begin : no_sdram_memory
`ifdef GBK_SAVESTATE
        assign state_memory_ready=0;assign state_memory_response=0;
`endif
        assign sdram_initialized=1;assign memory_ready=0;assign memory_response=0;assign memory_rdata=0;
        assign {rom_memory_ready,ram_memory_ready,rom_response,ram_response}=0;
        assign dram_a=0;assign dram_ba=0;assign dram_dqm=0;assign dram_dq=16'hzzzz;
        assign dram_cke=0;assign {dram_ras_n,dram_cas_n,dram_we_n}=3'b111;
    end endgenerate
    generate
        if (EXTERNAL_CARTRIDGE) begin : external_cartridge
            // 8 KiB ROM cache; native timing and physical read latency stay unchanged.
            gba_cartridge_psram #(.CACHE_WORDS(4096),.PAIR_READS(1),.PROFILE_ROM(ROM_PROFILE),.FAST_READ_ISSUE(1),
                .READ_WAIT_CYCLES(ROM_READ_WAIT_CYCLES),.SDRAM_BACKEND(SDRAM_ROM),
                .SDRAM_DIRECT_BURST(ROM_DIRECT_BURST),.SDRAM_FILL_NEIGHBOR(ROM_FILL_NEIGHBOR)) cartridge (
                // APF loads the cartridge while the emulated CPU is held
                // in reset. Only FPGA/loader reset may clear its scheduler.
                .load_clk(cart_load_clk), .reset(cart_load_reset || (SDRAM_ROM && sdram_reset)),
`ifdef GBK_SAVESTATE
                .state_cpu_idle(state_rom_cpu_idle),.state_memory_idle(state_rom_memory_idle),
`endif
                .load_write(cart_load_write), .load_addr(cart_load_addr),
                .load_wdata(cart_load_wdata),
                .cpu_clk(execution_clk), .cpu_req(cart_req), .cpu_addr(cart_addr),
                .cpu_streaming(cart_streaming),
                .profile_reset(reset),.debug_profile(debug_rom_profile),
                .cpu_rdata(cart_rdata), .cpu_ready(cart_ready),
                .cram_a, .cram_dq, .cram_wait,
                .cram_clk, .cram_adv_n, .cram_cre,
                .cram_ce0_n, .cram_ce1_n, .cram_oe_n, .cram_we_n,
                .cram_ub_n, .cram_lb_n,
                .memory_valid(rom_memory_valid),.memory_ready(rom_memory_ready),.memory_write(rom_memory_write),
                .memory_addr(rom_memory_addr),.memory_wdata(rom_memory_wdata),.memory_byteena(rom_memory_byteena),
                .response_valid(rom_response),.response_ready(rom_response_ready),.response_data(memory_rdata)
            );
        end else begin : internal_cartridge
`ifdef GBK_SAVESTATE
            assign state_rom_cpu_idle=!cart_req;assign state_rom_memory_idle=1'b1;
`endif
            assign rom_memory_valid=0;assign rom_memory_write=0;assign rom_memory_addr=0;
            assign rom_memory_wdata=0;assign rom_memory_byteena=0;assign rom_response_ready=0;
            assign debug_rom_profile=0;
            gba_cartridge cartridge (
                .load_clk(cart_load_clk), .load_write(cart_load_write),
                .load_addr(cart_load_addr[17:0]), .load_wdata(cart_load_wdata),
                .cpu_clk(execution_clk), .cpu_req(cart_req), .cpu_addr(cart_addr),
                .cpu_rdata(cart_rdata), .cpu_ready(cart_ready)
            );
            assign cram_a = 0;
            assign cram_dq = 16'hzzzz;
            assign cram_clk = 0;
            assign cram_adv_n = 1;
            assign cram_cre = 0;
            assign cram_ce0_n = 1;
            assign cram_ce1_n = 1;
            assign cram_oe_n = 1;
            assign cram_we_n = 1;
            assign cram_ub_n = 1;
            assign cram_lb_n = 1;
        end
    endgenerate

    generate
        if (EXTERNAL_EWRAM) begin : external_ewram
            // execution_clk is 39.936 MHz (fast CPU) or 12.288 MHz (legacy).
            gba_ewram_cached_psram #(.CACHE_WORDS(64),.SLOW_CLOCK(1),.SDRAM_BACKEND(SDRAM_EWRAM),.BURST_FILL(EWRAM_BURST_FILL)) ewram (
                .clk(execution_clk), .reset, .req(ewram_req), .write(ewram_write),
`ifdef GBK_SAVESTATE
                .state_idle(state_ewram_idle),
`endif
                .addr(ewram_addr), .wdata(ewram_wdata), .size(ewram_size),
                .rdata(ewram_rdata), .ready(ewram_ready),
                .cram_a(ewram_cram_a), .cram_dq(ewram_cram_dq),
                .cram_wait(ewram_cram_wait), .cram_clk(ewram_cram_clk),
                .cram_adv_n(ewram_cram_adv_n), .cram_cre(ewram_cram_cre),
                .cram_ce0_n(ewram_cram_ce0_n), .cram_ce1_n(ewram_cram_ce1_n),
                .cram_oe_n(ewram_cram_oe_n), .cram_we_n(ewram_cram_we_n),
                .cram_ub_n(ewram_cram_ub_n), .cram_lb_n(ewram_cram_lb_n),
                .memory_req(ram_cache_req),.memory_write(ram_cache_write),.memory_addr(ram_cache_addr),
                .memory_wdata(ram_cache_wdata),.memory_size(ram_cache_size),
                .memory_ready(ram_cache_ready),.memory_rdata(ram_cache_addr[2] ? ram_cache_rdata[63:32] : ram_cache_rdata[31:0]),.memory_line_data(ram_cache_rdata)
            );
        end else begin : internal_ewram
`ifdef GBK_SAVESTATE
            assign state_ewram_idle=!ewram_req;
`endif
            assign ewram_ready = 1'b0;
            assign ewram_rdata = 32'd0;
            assign ewram_cram_a = 0;
            assign ewram_cram_dq = 16'hzzzz;
            assign ewram_cram_clk = 0;
            assign ewram_cram_adv_n = 1;
            assign ewram_cram_cre = 0;
            assign ewram_cram_ce0_n = 1;
            assign ewram_cram_ce1_n = 1;
            assign ewram_cram_oe_n = 1;
            assign ewram_cram_we_n = 1;
            assign ewram_cram_ub_n = 1;
            assign ewram_cram_lb_n = 1;
        end
    endgenerate

    // The PPU's timing and RGB/sync outputs are the Pocket video stream, so
    // they must remain synchronous to the declared video clock.  Keep the
    // faster clock on the VRAM scheduler, but run the PPU itself at the
    // 12.288 MHz pixel clock.
    gba_ppu #(.EXTERNAL_VRAM(1'b1), .FAST_RENDER(1'b0), .NATIVE_TIMING(NATIVE_TIMING),
              .OBJ_ROWS(RENDER_SCHEDULER && NATIVE_TIMING),.BLOCK_OAM(RENDER_SCHEDULER && NATIVE_TIMING),
              .OBJ_WORD_READS(RENDER_SCHEDULER && NATIVE_TIMING),
              .OBJ_TAGGED_READS(RENDER_SCHEDULER && NATIVE_TIMING)) ppu (
`ifdef GBK_SAVESTATE
        .state_render_invalidate(state_render_invalidate),
`endif
        .video_skip,.raster_position(host_display_position),
        .clk(clk), .reset,
        .render_clk(RENDER_SCHEDULER ? fast_clk : clk),
        .pixel_ce(ppu_pixel_ce),
        .vram_write(ppu_vram_write),
        .vram_addr(ppu_vram_addr),
        .vram_wdata(ppu_vram_wdata),
        .vram_read_addr(ppu_vram_read_addr),
        .vram_read_data(ppu_vram_rdata),
        .vram_debug0(ppu_vram_debug0),
        .bg_map_read_addr(ppu_bg_map_read_addr),
        .bg_map_read_data(ppu_bg_map_rdata),
        .bg_tile_read_addr(ppu_bg_tile_read_addr),
        .bg_tile_read_data(ppu_bg_tile_rdata),
        .bg0cnt(ppu_bg0cnt), .bg0hofs(ppu_bg0hofs), .bg0vofs(ppu_bg0vofs),
        .bg1_map_read_addr(ppu_bg1_map_read_addr),
        .bg1_map_read_data(ppu_bg1_map_rdata),
        .bg1_tile_read_addr(ppu_bg1_tile_read_addr),
        .bg1_tile_read_data(ppu_bg1_tile_rdata),
        .bg2_map_read_addr(ppu_bg2_map_read_addr),
        .bg2_map_read_data(ppu_bg2_map_rdata),
        .bg2_tile_read_addr(ppu_bg2_tile_read_addr),
        .bg2_tile_read_data(ppu_bg2_tile_rdata),
        .bg3_map_read_addr(ppu_bg3_map_read_addr),
        .bg3_map_read_data(ppu_bg3_map_rdata),
        .bg3_tile_read_addr(ppu_bg3_tile_read_addr),
        .bg3_tile_read_data(ppu_bg3_tile_rdata),
        .bg1cnt(ppu_bg1cnt), .bg1hofs(ppu_bg1hofs), .bg1vofs(ppu_bg1vofs),
        .bg2cnt(ppu_bg2cnt), .bg2hofs(ppu_bg2hofs), .bg2vofs(ppu_bg2vofs),
        .bg3cnt(ppu_bg3cnt), .bg3hofs(ppu_bg3hofs), .bg3vofs(ppu_bg3vofs),
        .bg3pa(ppu_bg3pa), .bg3pb(ppu_bg3pb), .bg3pc(ppu_bg3pc),
        .bg3pd(ppu_bg3pd), .bg3refx(ppu_bg3x), .bg3refy(ppu_bg3y),
        .bg2pa(ppu_bg2pa),.bg2pb(ppu_bg2pb),.bg2pc(ppu_bg2pc),.bg2pd(ppu_bg2pd),
        .bg2refx(ppu_bg2x),.bg2refy(ppu_bg2y),
        .win0h(ppu_win0h), .win1h(ppu_win1h),
        .win0v(ppu_win0v), .win1v(ppu_win1v),
        .winin(ppu_winin), .winout(ppu_winout),
        .bldcnt(ppu_bldcnt),.bldalpha(ppu_bldalpha),.bldy(ppu_bldy),
        .second_palette_read_addr(ppu_second_palette_read_addr),.second_palette_read_data(ppu_second_palette_rdata),
        .obj_tile_read_addr(ppu_obj_tile_read_addr),
        .obj_tile_read_data(ppu_obj_tile_rdata),
        .obj_tile_read_word(ppu_obj_tile_word),
        .obj_tile_read_word_addr(ppu_obj_tile_word_addr),.obj_tile_read_word_valid(ppu_obj_tile_word_valid),
        .obj_window_extra_read_addr(ppu_obj_window_extra_read_addr),
        .obj_window_extra_read_data(ppu_obj_window_extra_read_data),
        .oam_data_flat(ppu_oam_data_flat),
        .oam_read_addr(ppu_oam_read_addr),.oam_read_data(ppu_oam_read_data),
        .dispcnt(ppu_dispcnt),.mosaic(ppu_mosaic),
        .palette_read_addr(ppu_palette_read_addr),
        .palette_read_data(ppu_palette_rdata),
        .bg_palette_read_addr(ppu_bg_palette_read_addr),
        .bg_palette_read_data(ppu_bg_palette_rdata),
        .backdrop_color(ppu_backdrop_color),
        .obj_palette_read_addr(ppu_obj_palette_read_addr),
        .obj_palette_read_data(ppu_obj_palette_rdata),
        .r(guest_video_r), .g(guest_video_g), .b(guest_video_b),
        .de(video_de), .hsync(video_hsync), .vsync(video_vsync),
        .debug_mode2_status, .debug_mode2_window
    );
endmodule
