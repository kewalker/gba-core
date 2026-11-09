// Initial GBA memory map. This keeps the regions explicit so wait states,
// byte lanes, and cartridge/save devices can be added without changing the
// CPU-facing bus contract.
module gba_memory_map #(
`ifdef GBK_SAVESTATE
    parameter bit STATE_CPU_LOOKUP=0,
`endif
    parameter bit RTC_PERSISTENCE=0,
    parameter bit EEPROM=0,
    parameter bit EXTERNAL_SAVE=0,
    parameter logic EXTERNAL_EWRAM = 1'b0,
    parameter logic RENDER_SCHEDULER = 1'b0,
    parameter logic NATIVE_TIMING = 1'b0,
    parameter logic BLOCK_OAM = 1'b0,
    parameter integer IWRAM_CACHE_WORDS=64,
    parameter bit FAST_CPU=0,
    parameter bit EARLY_CART_RESPONSE=0,
    parameter bit EARLY_EWRAM_RESPONSE=0
) (
    input  logic clk,
    input  logic reset,
`ifdef GBK_SAVESTATE
    // One execution-domain serial state bus, shared by existing peripherals.
    input wire state_dma_request,state_hold,state_reg_write,
    input wire [31:0] state_cpu_lookup_addr,
    input wire state_cpu_lookup_idle,
    input wire [15:0] state_reg_addr,
    input wire [31:0] state_reg_wdata,
    output wire state_dma_quiescent,state_transactions_idle,
    output reg state_reg_valid,
    output reg [31:0] state_reg_rdata,
    input wire state_save_raw_access,state_save_raw_eeprom,
    output wire state_save_raw_idle,state_save_raw_done,
`endif
    input wire stopped,postflg,
    input wire cpu_bus_lock,
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
    output wire stop_wake,
    output wire [16:0] display_position,
    output wire signed [15:0] audio_left, audio_right,
    input wire gba_tick,dma_timing_allow,
    output wire dma_timing_active,dma_timing_access,dma_timing_write,
    output wire [31:0] dma_timing_addr,
    output wire [1:0] dma_timing_size,
    output reg [15:0] timing_waitcnt,
    input  logic render_clk,
    input  logic bios_load_clk, bios_load_reset,
    input  logic bios_load_write,
    input  logic [11:0] bios_load_addr,
    input  logic [31:0] bios_load_wdata,
    input  logic save_load_write,
    input wire save_sram, save_flash512,
    input wire save_eeprom, cart_large,
    output wire save_eeprom_large,
    input  logic [14:0] save_load_addr,
    input  logic [31:0] save_load_wdata,
    output wire [31:0] save_load_rdata,
    input wire save_export_lock,
    output wire save_export_locked,
    input wire save_load_read,
    output wire save_load_valid, save_boot_ready, save_fault,
    output wire [16:0] save_mem_a,
    inout wire [15:0] save_mem_dq,
    output wire save_mem_oe_n, save_mem_we_n, save_mem_ub_n, save_mem_lb_n,
    input  logic        req,
    input  logic        write,
    input  logic [1:0]  size,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,
    output logic        ready,
    output logic        cart_req,
    output logic [31:0] cart_addr,
    output logic        cart_streaming,
    input  logic [31:0] cart_rdata,
    input  logic        cart_ready,
    output logic        ppu_vram_write,
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
    output logic [15:0] ppu_mosaic,
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
    output logic [15:0] ppu_bg2pa, ppu_bg2pb, ppu_bg2pc, ppu_bg2pd,
    output logic [27:0] ppu_bg2x, ppu_bg2y,
    output logic [27:0] ppu_bg3x,
    output logic [27:0] ppu_bg3y,
    output logic [15:0] ppu_win0h,
    output logic [15:0] ppu_win1h,
    output logic [15:0] ppu_win0v,
    output logic [15:0] ppu_win1v,
    output logic [15:0] ppu_winin,
    output logic [15:0] ppu_winout,
    output logic [15:0] ppu_bldcnt, ppu_bldalpha, ppu_bldy,
    input wire [8:0] ppu_second_palette_read_addr,
    output wire [15:0] ppu_second_palette_rdata,
    input  logic        ewram_ready,
    input  logic [31:0] ewram_rdata,
    output logic        ewram_req,
    output logic        ewram_write,
    output logic [31:0] ewram_addr,
    output logic [31:0] ewram_wdata,
    output logic [1:0]  ewram_size,
    input  logic [9:0]  controller_keys,
    output logic [15:0] debug_sound_bias,
    output logic [31:0] debug_irq_vector_write_data,
    output logic [15:0] debug_irq_vector_write_status,
    output logic [95:0] debug_runtime_memory,
    output logic [31:0] debug_probe_pending_addr,
    output logic [12:0] debug_probe_iwram_index,
    output logic [31:0] debug_probe_iwram_rdata,
    output logic [4:0]  debug_probe_memory_state,
    output logic [31:0] debug_bios_word_12c,
    output logic        irq,
    output wire         halt_wake,
    output logic [31:0] debug_dma_source, debug_dma_destination, debug_dma_status
);

`ifdef GBK_SIM
    localparam integer EWRAM_WORDS = EXTERNAL_EWRAM ? 1 : 1024;
    localparam integer IWRAM_WORDS = 1024;
    localparam integer VRAM_WORDS  = 1024;
`else
    localparam integer EWRAM_WORDS = EXTERNAL_EWRAM ? 1 : 65536;
    localparam integer IWRAM_WORDS = 8192;
    localparam integer VRAM_WORDS  = 24576;
`endif
    logic [31:0] ewram [0:EWRAM_WORDS-1]; // 256 KiB
`ifndef GBK_POCKET
    (* ramstyle = "M20K, no_rw_check" *) logic [31:0] iwram [0:IWRAM_WORDS-1];  // 32 KiB
`endif
`ifndef GBK_POCKET
    logic [31:0] vram  [0:VRAM_WORDS-1];   // 96 KiB
`endif
`ifndef GBK_POCKET
    (* ramstyle = "M20K, no_rw_check" *) logic [31:0] pal   [0:255];
`endif
    localparam integer OAM_WORDS = 256;
    (* ramstyle = "M20K, no_rw_check" *) logic [31:0] oam [0:OAM_WORDS-1];
    wire [31:0] oam_cpu_rdata;
    // DMA destination strobes are qualified by the same completion signal
    // that advances the controller. Keep this declaration ahead of the
    // physical RAM/I/O port decodes below.
    logic dma_ready_signal;
    wire oam_dma_access=dma_active && dma_req && dma_ready_signal && dma_addr[31:24]==8'h07;
    wire [7:0] oam_cpu_addr=oam_dma_access ? dma_addr[9:2] :
        read_state!=0 && pending_addr[31:24]==8'h07 ? pending_addr[9:2] : addr[9:2];
    wire oam_cpu_write=oam_dma_access ? dma_write : req && write && hit_oam && !dma_active;
    wire [31:0] oam_cpu_wdata=oam_dma_access ? align_store_data(dma_wdata,dma_size,dma_addr[1:0]) : align_store_data(wdata,size,addr[1:0]);
    wire [3:0] oam_cpu_byteena=oam_dma_access ?
        (dma_size==0 ? 4'b0001<<dma_addr[1:0] : dma_size==1 ? 4'b0011<<{dma_addr[1],1'b0} : 4'b1111) :
        (size==0 ? 4'b0001<<addr[1:0] : size==1 ? 4'b0011<<{addr[1],1'b0} : 4'b1111);
    generate if(BLOCK_OAM) begin : block_oam
        gba_oam_ram storage(.cpu_clk(clk),.cpu_write(oam_cpu_write),.cpu_addr(oam_cpu_addr),
            .cpu_wdata(oam_cpu_wdata),.cpu_byteena(oam_cpu_byteena),.cpu_rdata(oam_cpu_rdata),
            .render_clk,.render_addr(ppu_oam_read_addr),.render_data(ppu_oam_read_data));
    end else begin : flat_oam
        assign oam_cpu_rdata=0;assign ppu_oam_read_data=0;
    end endgenerate
    logic [31:0] bios_rdata;
    logic [27:0] bg2_programmed_x,bg2_programmed_y;
    // Internal affine references advance by PB/PD each visible scanline.
    // A register write reloads the current reference, even for the same value.
    always_ff @(posedge clk) begin
        if(reset) begin ppu_bg2x<=0;ppu_bg2y<=0;end
`ifdef GBK_SAVESTATE
        else if(state_frozen)begin
            if(state_reg_write && state_reg_addr==16'h0618)ppu_bg2x<=state_reg_wdata[27:0];
            if(state_reg_write && state_reg_addr==16'h0619)ppu_bg2y<=state_reg_wdata[27:0];
        end
`endif
        else begin
            if(display_line_end) begin
                if(vcount==227) begin ppu_bg2x<=bg2_programmed_x;ppu_bg2y<=bg2_programmed_y;end
            end
            // Increment before HBlank DMA writes the reference for the next
            // line. Advancing at line end would add PB/PD a second time to
            // a reference explicitly supplied by a per-line DMA transfer.
            if(display_hblank_edge && vcount<160 && ppu_dispcnt[2:0]!=0 && ppu_dispcnt[10]) begin
                ppu_bg2x<=ppu_bg2x+{{12{ppu_bg2pb[15]}},ppu_bg2pb};
                ppu_bg2y<=ppu_bg2y+{{12{ppu_bg2pd[15]}},ppu_bg2pd};
            end
            if(display_io_write && display_io_addr[15:2]==14'h000a)
                ppu_bg2x<=merge_store({4'd0,bg2_programmed_x},display_io_data,display_io_size,display_io_addr[1:0]);
            if(display_io_write && display_io_addr[15:2]==14'h000b)
                ppu_bg2y<=merge_store({4'd0,bg2_programmed_y},display_io_data,display_io_size,display_io_addr[1:0]);
        end
    end
    logic [31:0] response_rdata;
    // Cartridge ready/data are already settled in this clock domain. Complete
    // a CPU-owned read directly, without copying through two response stages.
    // A retained response still handles a read delayed by arbitration.
    wire cart_cpu_fast_ready=EARLY_CART_RESPONSE && read_state==4'd2 &&
        (cart_cpu_response_valid || (cart_port_busy && !cart_owner_dma && cart_ready));
    wire [31:0] cart_cpu_fast_data=cart_cpu_response_valid ? cart_response_data : cart_rdata;
    // EWRAM also returns registered data. Only the CPU-owned read may use
    // this completion; DMA responses and stores keep their existing path.
    wire ewram_cpu_fast_ready=EARLY_EWRAM_RESPONSE && EXTERNAL_EWRAM &&
        read_state==4'd4 && (ewram_cpu_response_valid ||
        (ewram_port_busy && !ewram_owner_dma && !ewram_write && ewram_ready));
    wire [31:0] ewram_cpu_fast_data=ewram_cpu_response_valid ? ewram_response_data : ewram_rdata;
`ifdef GBK_POCKET
    wire local_read_ready=req && !write && !dma_active && read_state==6;
    wire [31:0] local_read_data=pending_addr[31:24]==0 ? bios_rdata :
        pending_addr[31:24]==3 ? iwram_ram_rdata :
        BLOCK_OAM && pending_addr[31:24]==7 ? oam_cpu_rdata : render_cpu_rdata;
    assign rdata=local_read_ready ? local_read_data : iwram_cache_hit ? iwram_cache_data[iwram_cache_index] :
        eeprom_cpu_read ? eeprom_word :
        cart_cpu_fast_ready ? cart_cpu_fast_data :
        ewram_cpu_fast_ready ? ewram_cpu_fast_data : response_rdata;
`else
    assign rdata=eeprom_cpu_read ? eeprom_word : cart_cpu_fast_ready ? cart_cpu_fast_data :
        ewram_cpu_fast_ready ? ewram_cpu_fast_data : response_rdata;
`endif
    logic [3:0]  read_state;
    logic [31:0] pending_addr;
    // Present a new CPU fetch to the registered BIOS address port on the
    // request edge, then hold that address for the entire pending read.
    wire [11:0] bios_ram_addr = (read_state == 4'd0)
        ? addr[13:2] : pending_addr[13:2];
    assign debug_probe_pending_addr = pending_addr;
    assign debug_probe_memory_state = {dma_active, read_state};
    logic [31:0] timer_rdata;
    logic        timer_ready;
    logic [31:0] interrupt_rdata;
    logic        interrupt_ready;
    logic        vblank_irq;
    logic hblank_irq, vcount_irq;
    wire vblank_trigger = display_line_end && vcount == 8'd159;
    logic vcount_match_previous;
    logic [3:0]  timer_irq;
    wire [3:0] dma_completion_irq;
    wire [3:0] timer_overflow;
    wire [1:0] audio_fifo_request;
    wire [31:0] apu_rdata;
    logic [31:0] dma_cfg_rdata;
    logic [31:0] dma_mem_rdata;
    logic        dma_cfg_ready;
    logic        dma_active;
    logic        dma_req;
    wire dma_engine_req;
    assign dma_req=dma_engine_req && (!FAST_CPU || dma_timing_allow);
    assign dma_timing_active=dma_active;
    assign dma_timing_access=dma_req && dma_ready_signal;
    assign dma_timing_write=dma_write;
    assign dma_timing_addr=dma_addr;
    assign dma_timing_size=dma_size;
    logic        dma_write;
    logic [1:0]  dma_size;
    logic [31:0] dma_addr;
    logic [31:0] dma_wdata;
    logic ewram_port_busy, ewram_owner_dma;
    // Retain physically completed CPU stores while DMA uses the port. The
    // held CPU request must acknowledge that completion rather than replay.
    logic ewram_cpu_write_complete;
    logic ewram_cpu_response_valid, ewram_dma_response_valid;
    logic [31:0] ewram_response_data;
    logic cart_port_busy, cart_owner_dma;
    logic cart_cpu_response_valid, cart_dma_response_valid;
`ifdef GBK_SAVESTATE
    assign state_transactions_idle=read_state==0 && !cart_port_busy && !ewram_port_busy &&
        !cart_cpu_response_valid && !cart_dma_response_valid &&
        !ewram_cpu_response_valid && !ewram_dma_response_valid && !dma_active;
`endif
    logic [31:0] cart_response_data;
    logic [15:0] legacy_bg_map_rdata, legacy_bg_tile_rdata;
    logic [15:0] legacy_bg1_map_rdata, legacy_bg1_tile_rdata;
    logic [15:0] legacy_bg2_map_rdata, legacy_bg2_tile_rdata;
    logic [15:0] legacy_bg3_map_rdata, legacy_bg3_tile_rdata;
    logic [15:0] legacy_obj_tile_rdata;
    logic [15:0] ppu_vram_rdata_legacy;
    logic [169:0] render_addr_flat;
    logic [159:0] render_data_flat;
    logic [169:0] scheduled_addr_flat;
    logic [159:0] scheduled_data_flat;
    logic [14:0] render_cpu_addr;
    logic [31:0] render_cpu_wdata;
    logic [31:0] render_cpu_rdata;
    logic [1:0] dma_vram_wait;
    wire [31:0] dma_controller_status;
    assign debug_dma_status = dma_controller_status | {30'b0,cart_req,cart_ready};
    logic [3:0] render_cpu_byteena;
    logic render_cpu_write;
    // BIOS SWI 0x19 ramps this register between 0 and 0x0200.  Keeping it
    // live before the full APU exists prevents the BIOS from polling zero
    // forever after its first sound-bias write.
    logic [15:0] sound_bias;
    // GBA display timing is visible to software through DISPSTAT/VCOUNT.
    // Keep a GBA-rate 228-line counter beside the Pocket's 640-line output
    // timing so BIOS code and games see the conventional 0..227 scanlines.
    logic [10:0] display_dot;
    // Native GBA cycles / Pocket clock = 16.777216 / 12.288 = 512/375.
    // Advance one or two cycles without changing CPU/memory handshake clocks.
    logic [8:0] display_phase;
    wire guest_stopped=stopped===1'b1;
`ifdef GBK_SAVESTATE
    wire state_frozen=state_hold===1'b1;
`endif
    wire peripheral_tick=!guest_stopped && (!FAST_CPU || gba_tick)
`ifdef GBK_SAVESTATE
        && !state_frozen
`endif
    ;
    logic [15:0] keycnt;
    wire [9:0] selected_pressed=(~controller_keys) & keycnt[9:0];
    wire keypad_match=keycnt[15] ? selected_pressed==keycnt[9:0] : |selected_pressed;
    reg keypad_and_matched;
    reg [9:0] keypad_previous;
    wire keypad_irq=keycnt[14] && keypad_match &&
        (!keycnt[15] || !keypad_and_matched || keypad_previous!=controller_keys);
    always_ff @(posedge clk) begin
        if(reset) begin keypad_and_matched<=0;keypad_previous<=10'h3ff;end
`ifdef GBK_SAVESTATE
        else if(state_frozen)begin
            if(state_reg_write && state_reg_addr==16'h0502)begin
                keypad_previous<=state_reg_wdata[9:0];keypad_and_matched<=state_reg_wdata[10];
            end
        end
`endif
        else begin
            keypad_previous<=controller_keys;
            keypad_and_matched<=keycnt[14] && keycnt[15] && keypad_match;
        end
    end
    always_ff @(posedge clk) begin
        if(reset) keycnt<=0;
`ifdef GBK_SAVESTATE
        else if(state_frozen)begin
            if(state_reg_write && state_reg_addr==16'h0501)keycnt<=state_reg_wdata[15:0];
        end
`endif
        else if(display_io_write && display_io_addr[31:2]==(32'h04000130>>2))
            keycnt<=merge_io16(keycnt,io_aligned[31:16],io_byteena[3:2]) & 16'hc3ff;
    end
    wire [1:0] display_step =
`ifdef GBK_SAVESTATE
        state_frozen ? 2'd0 :
`endif
        guest_stopped ? 2'd0 : FAST_CPU ? {1'b0,gba_tick} : NATIVE_TIMING && display_phase >= 9'd238 ? 2'd2 : 2'd1;
    wire [11:0] display_next = {1'b0,display_dot} + display_step;
    localparam integer DISPLAY_LINE_CYCLES = NATIVE_TIMING ? 1232 : 898;
    // Match the reference core's 1008 visible + 224 blank cycle split.
    localparam integer DISPLAY_HBLANK_START = NATIVE_TIMING ? 1008 : 674;
    wire display_line_end = display_next >= DISPLAY_LINE_CYCLES;
    wire display_hblank_edge = display_dot < DISPLAY_HBLANK_START && display_next >= DISPLAY_HBLANK_START;
    logic [7:0] vcount;
    assign display_position={vcount,display_dot[10:2]};
    logic [15:0] dispstat_control;
    wire display_hblank = (display_dot >= DISPLAY_HBLANK_START);
    wire display_vblank = (vcount >= 8'd160);
    wire display_vcount_match = (vcount == dispstat_control[15:8]);
    wire [15:0] dispstat_value = {dispstat_control[15:3],
                                   display_vcount_match, display_hblank,
                                   display_vblank};
    assign debug_sound_bias = sound_bias;

    always_ff @(posedge clk) begin
        if (reset) begin
            display_dot <= 10'd0;
            display_phase <= 0;
            vcount <= 8'd0;
            dispstat_control <= 16'd0;
            vblank_irq <= 1'b0; hblank_irq <= 0; vcount_irq <= 0; vcount_match_previous <= 1;
`ifdef GBK_SAVESTATE
        end else if(state_frozen)begin
            if(state_reg_write)case(state_reg_addr)
                16'h0601:dispstat_control<=state_reg_wdata[15:0];
                16'h0616:begin display_dot<=state_reg_wdata[10:0];display_phase<=state_reg_wdata[19:11];vcount<=state_reg_wdata[27:20];end
                16'h0617:begin vblank_irq<=state_reg_wdata[0];hblank_irq<=state_reg_wdata[1];vcount_irq<=state_reg_wdata[2];vcount_match_previous<=state_reg_wdata[3];end
                default:begin end
            endcase
`endif
        end else begin
            vblank_irq <= vblank_trigger && dispstat_control[3];
            hblank_irq <= display_hblank_edge && dispstat_control[4];
            vcount_irq <= display_vcount_match && !vcount_match_previous && dispstat_control[5];
            vcount_match_previous <= display_vcount_match;
            if (NATIVE_TIMING && !FAST_CPU && !guest_stopped)
                display_phase <= display_phase >= 9'd238 ? display_phase - 9'd238 : display_phase + 9'd137;
            if (display_line_end) begin
                display_dot <= display_next - DISPLAY_LINE_CYCLES;
                // Hardware raises VBlank only on the 159 -> 160 edge.  IF
                // remains latched in the interrupt controller after this
                // one-clock event, matching the BIOS IntrWait contract.
                if (vcount == 8'd227)
                    vcount <= 8'd0;
                else
                    vcount <= vcount + 1'b1;
            end else begin
                display_dot <= display_next[10:0];
            end
            if (req && write && addr[31:24] == 8'h04 && addr[15:1] == (16'h0004 >> 1)) begin
                case (size)
                    2'b00: if (addr[0]) dispstat_control[15:8] <= wdata[7:0];
                           else         dispstat_control[7:0]  <= wdata[7:0];
                    default: dispstat_control <= wdata[15:0];
                endcase
            end
        end
    end

    gba_bios_ram bios_storage (
        .load_clk(bios_load_clk), .load_write(bios_load_write),
        .load_addr(bios_load_addr), .load_wdata(bios_load_wdata),
        .cpu_clk(clk), .cpu_addr(bios_ram_addr),
        .cpu_rdata(bios_rdata),
        .debug_word_12c(debug_bios_word_12c)
    );
`ifdef GBK_POCKET
    logic [12:0] iwram_ram_addr;
    logic [31:0] iwram_ram_wdata;
    logic [3:0]  iwram_ram_byteena;
    logic        iwram_ram_write;
    logic [31:0] iwram_ram_rdata;
    reg [IWRAM_CACHE_WORDS-1:0] iwram_cache_valid;
    localparam IWRAM_CACHE_INDEX_BITS=$clog2(IWRAM_CACHE_WORDS);
    // The index already identifies the low physical word-address bits.
    reg [12-IWRAM_CACHE_INDEX_BITS:0] iwram_cache_tag[0:IWRAM_CACHE_WORDS-1];
    // MLAB supports a flow-through read, preserving the one-clock hit path.
    // Fills occur in state 6, when no cache hit can consume read/write data.
    (* ramstyle="MLAB, no_rw_check" *) reg [31:0] iwram_cache_data[0:IWRAM_CACHE_WORDS-1];
`ifdef GBK_SAVESTATE
    // Normal CPU hits do not need the state copier's address overlay. State
    // reads use the existing physical RAM path while frozen; writes keep the
    // same invalidation/fill machinery. No guest cycle or memory port is added.
    wire [31:0] iwram_lookup_addr=STATE_CPU_LOOKUP ? state_cpu_lookup_addr : addr;
    wire iwram_lookup_enabled=!STATE_CPU_LOOKUP || (!state_frozen && state_cpu_lookup_idle);
    wire [5:0] iwram_cache_index=iwram_lookup_addr[7:2] & (IWRAM_CACHE_WORDS-1);
`else
    wire [5:0] iwram_cache_index=addr[7:2] & (IWRAM_CACHE_WORDS-1);
`endif
    wire [5:0] iwram_fill_index=pending_addr[7:2] & (IWRAM_CACHE_WORDS-1);
    wire [31:0] iwram_write_addr=dma_active ? dma_addr : addr;
    wire [5:0] iwram_write_index=iwram_write_addr[7:2] & (IWRAM_CACHE_WORDS-1);
    wire iwram_cache_hit=!reset && !dma_active && req && !write &&
`ifdef GBK_SAVESTATE
        iwram_lookup_enabled && iwram_lookup_addr[31:24]==8'h03 && read_state==0 && iwram_cache_valid[iwram_cache_index] &&
        iwram_cache_tag[iwram_cache_index]==iwram_lookup_addr[14:2+IWRAM_CACHE_INDEX_BITS];
`else
        addr[31:24]==8'h03 && read_state==0 && iwram_cache_valid[iwram_cache_index] &&
        iwram_cache_tag[iwram_cache_index]==addr[14:2+IWRAM_CACHE_INDEX_BITS];
`endif
    // Physical tags handle every mirror. A store only invalidates a matching
    // word; unrelated data at the same index must not evict cached code.
    // DMA ownership suppresses all CPU hits, including a back-to-back hit.
    always_ff @(posedge clk) begin
        if(reset) iwram_cache_valid<=0;
        else if((dma_active && dma_req && dma_write && dma_ready_signal && dma_addr[31:24]==8'h03) ||
                (!dma_active && req && write && addr[31:24]==8'h03))
            begin
                if(iwram_cache_tag[iwram_write_index]==iwram_write_addr[14:2+IWRAM_CACHE_INDEX_BITS])
                    iwram_cache_valid[iwram_write_index]<=0;
            end
        else if(!dma_active && read_state==6 && pending_addr[31:24]==8'h03) begin
            iwram_cache_valid[iwram_fill_index]<=1;
            iwram_cache_tag[iwram_fill_index]<=pending_addr[14:2+IWRAM_CACHE_INDEX_BITS];
            iwram_cache_data[iwram_fill_index]<=iwram_ram_rdata;
        end
    end
    logic [1:0] dma_local_read_wait;
    wire dma_read_registered_ram = !dma_write &&
        (dma_addr[31:24] == 8'h03 || dma_addr[31:24] == 8'h05 ||
         (BLOCK_OAM && dma_addr[31:24] == 8'h07));
    logic [7:0]  pal_ram_addr;
    logic [31:0] pal_ram_wdata;
    logic [31:0] pal_ram_rdata;
    logic [3:0]  pal_ram_byteena;
    logic        pal_ram_write;
    logic [31:0] pal_ppu_rdata;
    logic [31:0] pal_obj_ppu_rdata;
    logic [8:0] pal_bg_render_addr;
`endif

    wire hit_bios  = (addr[31:24] == 8'h00);
    wire hit_ewram = (addr[31:24] == 8'h02);
    wire hit_iwram = (addr[31:24] == 8'h03);
    wire hit_io    = (addr[31:24] == 8'h04);
    wire hit_timer = hit_io && (addr[15:0] >= 16'h0100) && (addr[15:0] <= 16'h010F);
    wire hit_interrupt = hit_io && ((addr[15:2] == (16'h0200 >> 2)) ||
                                    (addr[15:2] == (16'h0208 >> 2)));
    wire hit_dma = hit_io && (addr[15:0] >= 16'h00B0) && (addr[15:0] <= 16'h00DF);
    wire hit_pal   = (addr[31:24] == 8'h05);
    wire hit_vram  = (addr[31:24] == 8'h06);
    wire hit_oam   = (addr[31:24] == 8'h07);
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] eeprom_sync=0,large_rom_sync=0;
    always @(posedge clk) begin
        eeprom_sync<={eeprom_sync[0],save_eeprom===1'b1};
        large_rom_sync<={large_rom_sync[0],cart_large===1'b1};
    end
    wire eeprom_selected=EEPROM && eeprom_sync[1];
    function automatic eeprom_address(input [31:0] a);
        eeprom_address=a[31:24]==8'h0d && (!large_rom_sync[1] || a[23:8]==16'hffff);
    endfunction
    wire hit_eeprom=eeprom_selected && eeprom_address(addr);
    wire dma_hit_eeprom=eeprom_selected && eeprom_address(dma_addr);
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] rtc_enable_sync=0;
    always @(posedge clk)rtc_enable_sync<={rtc_enable_sync[0],cart_rtc===1'b1};
    wire gpio_read_enable,cartridge_irq;
    wire [31:0] gpio_rdata;
    wire hit_gpio=rtc_enable_sync[1] && addr[31:25]>=7'h04 && addr[31:25]<=7'h06 &&
        (addr[24:2]==23'h31 || addr[24:2]==23'h32) && (write || gpio_read_enable);
    gba_cartridge_rtc #(.RTC_PERSISTENCE(RTC_PERSISTENCE),.CLOCK_HZ(FAST_CPU ? 39936000 : 12288000)) rtc(
`ifdef GBK_SAVESTATE
        .state_hold,.state_write(state_reg_write && state_reg_addr>=16'h0a00 && state_reg_addr<=16'h0a03),
        .state_addr(state_reg_addr[1:0]),.state_wdata(state_reg_wdata),.state_valid(state_rtc_valid),.state_rdata(state_rtc_rdata),
`endif
        .clk,.reset,.host_toggle(rtc_host_toggle),.host_valid(rtc_host_valid),
        .host_date_bcd(rtc_host_date),.host_time_bcd(rtc_host_time),
        .host_epoch(rtc_host_epoch),.persistence_request(rtc_persistence_request),
        .persistence_operation(rtc_persistence_operation),.persistence_payload(rtc_persistence_payload),
        .persistence_acknowledge(rtc_persistence_acknowledge),.persistence_reply(rtc_persistence_reply),
        .bus_write(req && write && hit_gpio && !dma_active),.addr(read_state==14 ? pending_addr : addr),
        .wdata,.size,.rdata(gpio_rdata),.read_enable(gpio_read_enable),.irq(cartridge_irq));
    wire hit_cart  = (addr[31:24] >= 8'h08) && (addr[31:24] <= 8'h0D) && !hit_eeprom && !hit_gpio;
    wire hit_flash = (addr[31:24] == 8'h0e) || (addr[31:24] == 8'h0f);
    wire [31:0] flash_rdata;
    wire flash_ready;
    wire [31:0] flash_load_rdata,eeprom_load_rdata;
`ifdef GBK_SAVESTATE
    wire state_raw_active=state_save_raw_access===1'b1;
    wire state_host_eeprom=state_raw_active ? state_save_raw_eeprom===1'b1 : EEPROM && save_eeprom===1'b1;
    wire state_flash_valid,state_eeprom_valid,state_flash_host_idle,state_flash_host_done,state_eeprom_host_idle,state_eeprom_host_done;
    wire [31:0] state_flash_rdata,state_eeprom_rdata;
    wire state_rtc_valid;
    wire [31:0] state_rtc_rdata;
    assign state_save_raw_idle=state_host_eeprom ? state_eeprom_host_idle : state_flash_host_idle;
    assign state_save_raw_done=state_host_eeprom ? state_eeprom_host_done : state_flash_host_done;
`endif
    wire flash_load_valid,flash_export_locked,eeprom_export_locked,eeprom_load_valid;
    wire eeprom_ready,eeprom_bit;
    wire eeprom_cpu_read=EEPROM && read_state==4'd13;
    wire [31:0] eeprom_word={15'd0,eeprom_bit,15'd0,eeprom_bit};
    wire eeprom_access=eeprom_selected && eeprom_ready &&
        (dma_active ? (dma_req && dma_hit_eeprom && dma_size==1) :
            (req && hit_eeprom && size==1 && (write || eeprom_cpu_read)));
`ifdef GBK_SAVESTATE
    assign save_load_rdata=state_host_eeprom ? eeprom_load_rdata : flash_load_rdata;
    assign save_load_valid=state_host_eeprom ? eeprom_load_valid : flash_load_valid;
`else
    assign save_load_rdata=(EEPROM && save_eeprom===1'b1) ? eeprom_load_rdata : flash_load_rdata;
    assign save_load_valid=(EEPROM && save_eeprom===1'b1) ? eeprom_load_valid : flash_load_valid;
`endif
    assign save_export_locked=(EEPROM && save_eeprom===1'b1) ? eeprom_export_locked : flash_export_locked;
    generate if(EEPROM) begin : serial_save
        gba_eeprom #(.PROGRAM_CYCLES(FAST_CPU ? 199680 : 61440)) device (
`ifdef GBK_SAVESTATE
            .state_hold,.state_write(state_reg_write && state_reg_addr>=16'h0910 && state_reg_addr<=16'h0913),
            .state_addr(state_reg_addr[1:0]),.state_wdata(state_reg_wdata),.state_valid(state_eeprom_valid),.state_rdata(state_eeprom_rdata),
            .state_host_access(state_raw_active),.state_host_idle(state_eeprom_host_idle),.state_host_done(state_eeprom_host_done),
`endif
            .clk,.reset,.access(eeprom_access),.write(dma_active ? dma_write : write),
            .bit_in(dma_active ? dma_wdata[0] : wdata[0]),
            .dma_count(dma_active && dma_controller_status[7:6]==3 ? dma_controller_status[23:8] : 16'd0),
            .bit_out(eeprom_bit),.ready(eeprom_ready),
            .load_clk(bios_load_clk),.load_reset(bios_load_reset),
            // Import precedes type discovery on some asset orders. Mirror
            // host writes into both stores; only the selected one exports.
`ifdef GBK_SAVESTATE
            .load_write(save_load_write && (!state_raw_active || state_host_eeprom)),.load_read(save_load_read && state_host_eeprom),
`else
            .load_write(save_load_write),.load_read(save_load_read && save_eeprom===1'b1),
`endif
            .load_addr(save_load_addr),.load_wdata(save_load_wdata),.load_rdata(eeprom_load_rdata),.load_valid(eeprom_load_valid),
            .export_lock(save_export_lock),.export_locked(eeprom_export_locked),.capacity_large(save_eeprom_large)
        );
    end else begin : no_serial_save
`ifdef GBK_SAVESTATE
        assign state_eeprom_valid=state_frozen && !reset;assign state_eeprom_rdata=0;
        assign state_eeprom_host_idle=0;assign state_eeprom_host_done=0;
`endif
        assign eeprom_bit=1;assign eeprom_ready=1;
        assign eeprom_load_rdata=32'hffffffff;assign eeprom_load_valid=0;
        assign eeprom_export_locked=0;assign save_eeprom_large=0;
    end endgenerate
    generate if(EXTERNAL_SAVE) begin : external_save
    gba_flash_sram flash (
`ifdef GBK_SAVESTATE
        .state_hold,.state_write(state_reg_write && state_reg_addr==16'h0900),
        .state_wdata(state_reg_wdata),.state_valid(state_flash_valid),.state_rdata(state_flash_rdata),
        .state_host_idle(state_flash_host_idle),.state_host_done(state_flash_host_done),
`endif
        .clk, .reset, .req(req && hit_flash && !dma_active && read_state != 4'd3),
        .write, .size, .save_sram, .save_flash512, .addr, .wdata, .rdata(flash_rdata), .ready(flash_ready),
`ifdef GBK_SAVESTATE
        .load_read(save_load_read && !state_host_eeprom),
`else
        .load_read(save_load_read && !(EEPROM && save_eeprom===1'b1)),
`endif
        .load_valid(flash_load_valid),.boot_ready(save_boot_ready),.fault(save_fault),
        .sram_a(save_mem_a),.sram_dq(save_mem_dq),.sram_oe_n(save_mem_oe_n),
        .sram_we_n(save_mem_we_n),.sram_ub_n(save_mem_ub_n),.sram_lb_n(save_mem_lb_n),
        .load_clk(bios_load_clk), .load_reset(bios_load_reset), .load_write(save_load_write === 1'b1
`ifdef GBK_SAVESTATE
            && (!state_raw_active || !state_host_eeprom)
`endif
        ),
        .load_addr(save_load_addr), .load_wdata(save_load_wdata),
        .load_rdata(flash_load_rdata), .export_lock(save_export_lock), .export_locked(flash_export_locked)
    );
    end else begin : internal_save
        assign save_boot_ready=1'b1;
        assign save_fault=1'b0;
        assign flash_load_valid=1'b0;
        assign save_mem_a=17'd0;
        assign save_mem_dq=16'bz;
        assign save_mem_oe_n=1'b1;
        assign save_mem_we_n=1'b1;
        assign save_mem_ub_n=1'b1;
        assign save_mem_lb_n=1'b1;
    gba_flash flash (
`ifdef GBK_SAVESTATE
        .state_hold,.state_write(state_reg_write && state_reg_addr==16'h0900),
        .state_wdata(state_reg_wdata),.state_valid(state_flash_valid),.state_rdata(state_flash_rdata),
        .state_host_read(save_load_read && !state_host_eeprom),.state_host_idle(state_flash_host_idle),.state_host_done(state_flash_host_done),
`endif
        .clk, .reset, .req(req && hit_flash && !dma_active && read_state != 4'd3),
        .write, .size, .save_sram, .save_flash512, .addr, .wdata, .rdata(flash_rdata), .ready(flash_ready),
        .load_clk(bios_load_clk), .load_write(save_load_write === 1'b1
`ifdef GBK_SAVESTATE
            && (!state_raw_active || !state_host_eeprom)
`endif
        ),
        .load_addr(save_load_addr), .load_wdata(save_load_wdata),
        .load_rdata(flash_load_rdata), .export_lock(save_export_lock), .export_locked(flash_export_locked)
    );
    end endgenerate


    // CPU and DMA display-register writes share byte-lane decoding. Games
    // use repeating HBlank DMA for per-scanline scroll/affine effects.
    always_ff @(posedge clk) begin
        if(reset) begin
            ppu_dispcnt <= 0;
            ppu_mosaic<=0;
            ppu_bg0cnt <= 0;
            ppu_bg0hofs <= 0;
            ppu_bg0vofs <= 0;
            ppu_bg1cnt <= 0;
            ppu_bg1hofs <= 0;
            ppu_bg1vofs <= 0;
            ppu_bg2cnt <= 0;
            ppu_bg2hofs <= 0;
            ppu_bg2vofs <= 0;
            ppu_bg3cnt <= 0;
            ppu_bg3hofs <= 0;
            ppu_bg3vofs <= 0;
            ppu_bg3pa <= 0;
            ppu_bg2pa<=0;ppu_bg2pb<=0;ppu_bg2pc<=0;ppu_bg2pd<=0;
            bg2_programmed_x<=0;bg2_programmed_y<=0;
            ppu_bg3pb <= 0;
            ppu_bg3pc <= 0;
            ppu_bg3pd <= 0;
            ppu_bg3x <= 0;
            ppu_bg3y <= 0;
            ppu_win0h <= 0;
            ppu_win1h <= 0;
            ppu_win0v <= 0;
            ppu_win1v <= 0;
            ppu_winin <= 0;
            ppu_winout <= 0;
            ppu_bldcnt <= 0;ppu_bldalpha <= 0;ppu_bldy <= 0;
            timing_waitcnt<=0;
            sound_bias <= 16'b0;
`ifdef GBK_SAVESTATE
        end else if(state_frozen && !state_ppu_config_write)begin
            if(state_reg_write && state_reg_addr==16'h0503)timing_waitcnt<=state_reg_wdata[15:0];
`endif
        end else if(display_io_write) begin
                case ({display_io_addr[15:2],2'b00})
                    16'h0000: begin
                        ppu_dispcnt <= merge_io16(ppu_dispcnt,io_aligned[15:0],io_byteena[1:0]);
                    end
                    16'h0008: begin
                        ppu_bg0cnt <= merge_io16(ppu_bg0cnt,io_aligned[15:0],io_byteena[1:0]);
                        ppu_bg1cnt <= merge_io16(ppu_bg1cnt,io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h000c: begin
                        ppu_bg2cnt <= merge_io16(ppu_bg2cnt,io_aligned[15:0],io_byteena[1:0]);
                        ppu_bg3cnt <= merge_io16(ppu_bg3cnt,io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h0010: begin
                        ppu_bg0hofs <= merge_io16({7'b0,ppu_bg0hofs},io_aligned[15:0],io_byteena[1:0]);
                        ppu_bg0vofs <= merge_io16({7'b0,ppu_bg0vofs},io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h0014: begin
                        ppu_bg1hofs <= merge_io16({7'b0,ppu_bg1hofs},io_aligned[15:0],io_byteena[1:0]);
                        ppu_bg1vofs <= merge_io16({7'b0,ppu_bg1vofs},io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h0018: begin
                        ppu_bg2hofs <= merge_io16({7'b0,ppu_bg2hofs},io_aligned[15:0],io_byteena[1:0]);
                        ppu_bg2vofs <= merge_io16({7'b0,ppu_bg2vofs},io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h001c: begin
                        ppu_bg3hofs <= merge_io16({7'b0,ppu_bg3hofs},io_aligned[15:0],io_byteena[1:0]);
                        ppu_bg3vofs <= merge_io16({7'b0,ppu_bg3vofs},io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h0020: begin
                        ppu_bg2pa <= merge_io16(ppu_bg2pa,io_aligned[15:0],io_byteena[1:0]);
                        ppu_bg2pb <= merge_io16(ppu_bg2pb,io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h0024: begin
                        ppu_bg2pc <= merge_io16(ppu_bg2pc,io_aligned[15:0],io_byteena[1:0]);
                        ppu_bg2pd <= merge_io16(ppu_bg2pd,io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h0028: begin
                        bg2_programmed_x[15:0] <= merge_io16(bg2_programmed_x[15:0],io_aligned[15:0],io_byteena[1:0]);
                        bg2_programmed_x[27:16] <= merge_io16({4'b0,bg2_programmed_x[27:16]},io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h002c: begin
                        bg2_programmed_y[15:0] <= merge_io16(bg2_programmed_y[15:0],io_aligned[15:0],io_byteena[1:0]);
                        bg2_programmed_y[27:16] <= merge_io16({4'b0,bg2_programmed_y[27:16]},io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h0030: begin
                        ppu_bg3pa <= merge_io16(ppu_bg3pa,io_aligned[15:0],io_byteena[1:0]);
                        ppu_bg3pb <= merge_io16(ppu_bg3pb,io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h0034: begin
                        ppu_bg3pc <= merge_io16(ppu_bg3pc,io_aligned[15:0],io_byteena[1:0]);
                        ppu_bg3pd <= merge_io16(ppu_bg3pd,io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h0038: begin
                        ppu_bg3x[15:0] <= merge_io16(ppu_bg3x[15:0],io_aligned[15:0],io_byteena[1:0]);
                        ppu_bg3x[27:16] <= merge_io16({4'b0,ppu_bg3x[27:16]},io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h003c: begin
                        ppu_bg3y[15:0] <= merge_io16(ppu_bg3y[15:0],io_aligned[15:0],io_byteena[1:0]);
                        ppu_bg3y[27:16] <= merge_io16({4'b0,ppu_bg3y[27:16]},io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h0040: begin
                        ppu_win0h <= merge_io16(ppu_win0h,io_aligned[15:0],io_byteena[1:0]);
                        ppu_win1h <= merge_io16(ppu_win1h,io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h0044: begin
                        ppu_win0v <= merge_io16(ppu_win0v,io_aligned[15:0],io_byteena[1:0]);
                        ppu_win1v <= merge_io16(ppu_win1v,io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h0048: begin
                        ppu_winin <= merge_io16(ppu_winin,io_aligned[15:0],io_byteena[1:0]);
                        ppu_winout <= merge_io16(ppu_winout,io_aligned[31:16],io_byteena[3:2]);
                    end
                    16'h004c: ppu_mosaic<=merge_io16(ppu_mosaic,io_aligned[15:0],io_byteena[1:0]);
                    16'h0050: begin
                        ppu_bldcnt <= merge_io16(ppu_bldcnt,io_aligned[15:0],io_byteena[1:0]) & 16'h3fff;
                        ppu_bldalpha <= merge_io16(ppu_bldalpha,io_aligned[31:16],io_byteena[3:2]) & 16'h1f1f;
                    end
                    16'h0054: ppu_bldy <= merge_io16(ppu_bldy,io_aligned[15:0],io_byteena[1:0]) & 16'h001f;
                    16'h0204: timing_waitcnt<=merge_io16(timing_waitcnt,io_aligned[15:0],io_byteena[1:0]) & 16'h5fff;
                    16'h0088: begin
                        sound_bias <= merge_io16(sound_bias,io_aligned[15:0],io_byteena[1:0]);
                    end
                    default: begin end
                endcase
        end
    end

    // Return the containing aligned word. The CPU selects byte/halfword lanes.
    function automatic [31:0] io_word(input [31:0] a);
        begin
            case ({a[15:2],2'b00})
                16'h0000: io_word={16'b0,ppu_dispcnt};
                16'h0004: io_word={8'b0,vcount,dispstat_value};
                16'h0008: io_word={ppu_bg1cnt,ppu_bg0cnt};
                16'h000c: io_word={ppu_bg3cnt,ppu_bg2cnt};
                16'h0010: io_word={7'b0,ppu_bg0vofs,7'b0,ppu_bg0hofs};
                16'h0014: io_word={7'b0,ppu_bg1vofs,7'b0,ppu_bg1hofs};
                16'h0018: io_word={7'b0,ppu_bg2vofs,7'b0,ppu_bg2hofs};
                16'h001c: io_word={7'b0,ppu_bg3vofs,7'b0,ppu_bg3hofs};
                16'h0020: io_word={ppu_bg2pb,ppu_bg2pa};
                16'h0024: io_word={ppu_bg2pd,ppu_bg2pc};
                16'h0028: io_word={4'b0,bg2_programmed_x};
                16'h002c: io_word={4'b0,bg2_programmed_y};
                16'h0030: io_word={ppu_bg3pb,ppu_bg3pa};
                16'h0034: io_word={ppu_bg3pd,ppu_bg3pc};
                16'h0038: io_word={4'b0,ppu_bg3x};
                16'h003c: io_word={4'b0,ppu_bg3y};
                16'h0040: io_word={ppu_win1h,ppu_win0h};
                16'h0044: io_word={ppu_win1v,ppu_win0v};
                16'h0048: io_word={ppu_winout,ppu_winin};
                16'h004c: io_word=0; // MOSAIC is write-only.
                16'h0050: io_word={ppu_bldalpha,ppu_bldcnt};
                16'h0204: io_word={16'd0,timing_waitcnt};
                16'h0060,16'h0064,16'h0068,16'h006c,
                16'h0070,16'h0074,16'h0078,16'h007c,
                16'h0080,16'h0084,16'h0090,16'h0094,16'h0098,16'h009c: io_word=apu_rdata;
                16'h0088: io_word={16'b0,sound_bias};
                16'h0130: io_word={keycnt,6'd0,controller_keys};
                16'h0120,16'h0124,16'h0128,16'h0134,16'h0140,16'h0150,16'h0154,16'h0158:io_word=serial_rdata;
                16'h0300: io_word={31'd0,postflg===1'b1};
                16'h0200,16'h0208: io_word=interrupt_rdata;
                default: if(a[15:0]>=16'h0100 && a[15:0]<=16'h010f) io_word=timer_rdata;
                         else if(a[15:0]>=16'h00b0 && a[15:0]<=16'h00df) io_word=dma_cfg_rdata;
                         else io_word=0;
            endcase
        end
    endfunction
    // Merge each register locally. Feeding a shared readback mux into every
    // write port wastes logic and routing on the nearly full Pocket FPGA.
`ifdef GBK_SAVESTATE
    wire state_ppu_access=state_frozen && state_reg_addr[15:8]==6 && state_reg_addr[7:0]<26;
    wire state_ppu_config_write=state_ppu_access && state_reg_write && state_reg_addr[7:0]<22 && state_reg_addr[7:0]!=1;
    wire [31:0] state_ppu_io_addr={16'h0400,6'd0,state_reg_addr[7:0],2'd0};
    // Reuse the ordinary I/O read mux and write merge/decode. Only hidden
    // timing/reference state needs dedicated access, not a second PPU bank.
`ifdef GBK_LINK_MULTIPLAYER
    // always_comb includes globals read inside io_word in its sensitivity.
    // A continuous function call can stay stale in event-driven simulation
    // when only a peripheral changes (e.g. polling Busy or clearing IF).
    logic [31:0] shared_io_word;
    always_comb shared_io_word=io_word(state_ppu_access ? state_ppu_io_addr : pending_addr);
`else
    wire [31:0] shared_io_word=io_word(state_ppu_access ? state_ppu_io_addr : pending_addr);
`endif
    wire [31:0] display_io_addr=state_ppu_config_write ? state_ppu_io_addr : dma_active ? dma_addr : addr;
    wire [31:0] display_io_data=state_ppu_config_write ? state_reg_wdata : dma_active ? dma_wdata : wdata;
    wire [1:0] display_io_size=state_ppu_config_write ? 2'd2 : dma_active ? dma_size : size;
    wire display_io_write=state_ppu_config_write || (dma_active ? dma_req && dma_write && dma_ready_signal && dma_addr[31:24]==8'h04 : req && write && hit_io);
`else
    wire [31:0] display_io_addr=dma_active ? dma_addr : addr;
    wire [31:0] display_io_data=dma_active ? dma_wdata : wdata;
    wire [1:0] display_io_size=dma_active ? dma_size : size;
    wire display_io_write=dma_active ? dma_req && dma_write && dma_ready_signal && dma_addr[31:24]==8'h04 : req && write && hit_io;
`endif
    wire [31:0] io_aligned = align_store_data(display_io_data,display_io_size,display_io_addr[1:0]);
    wire [3:0] io_byteena = display_io_size==0 ? (4'b0001 << display_io_addr[1:0]) :
        display_io_size==1 ? (display_io_addr[1] ? 4'b1100 : 4'b0011) : 4'b1111;
    wire [31:0] serial_rdata;
    wire serial_irq;
    gba_serial serial(.clk,.reset,.cycle_enable(peripheral_tick),.stopped(guest_stopped),
`ifdef GBK_SAVESTATE
        .state_prepare(state_dma_request),.state_hold(state_hold),
        .state_write(state_reg_write && state_reg_addr[15:8]==8 && state_reg_addr[7:0]<10),
        .state_addr(state_reg_addr[3:0]),.state_wdata(state_reg_wdata),.state_valid(state_serial_valid),.state_rdata(state_serial_rdata),
`endif
        .access(display_io_write || (read_state==1 && pending_addr[31:16]==16'h0400)),
        .write(display_io_write),.addr(display_io_write ? display_io_addr : pending_addr),
        .wdata(display_io_data),.size(display_io_size),.rdata(serial_rdata),.irq(serial_irq),
        .pins_in(link_pins_in),.pins_out(link_pins_out),.pins_dir(link_pins_dir));
    wire signed [15:0] guest_audio_left,guest_audio_right;
    assign audio_left=guest_stopped ? 16'sd0 : guest_audio_left;
    assign audio_right=guest_stopped ? 16'sd0 : guest_audio_right;
    gba_apu #(.CYCLE_ENABLE(1)) apu(.clk,.reset,.cycle_enable(peripheral_tick),.timer_overflow(timer_overflow[1:0]),
`ifdef GBK_SAVESTATE
        .state_hold,.state_write(state_reg_write && state_reg_addr[15:8]==7 && state_reg_addr[7:0]<64),
        .state_addr(state_reg_addr[5:0]),.state_wdata(state_reg_wdata),.state_valid(state_apu_valid),.state_rdata(state_apu_rdata),
`endif
        .bus_write(display_io_write),.addr(display_io_addr),.wdata(display_io_data),
        .size(display_io_size),.rdata(apu_rdata),.fifo_request(audio_fifo_request),
        .audio_left(guest_audio_left),.audio_right(guest_audio_right));
    function automatic [15:0] merge_io16(input [15:0] old_value,new_value,input [1:0] lanes);
        merge_io16 = {lanes[1] ? new_value[15:8] : old_value[15:8],
                      lanes[0] ? new_value[7:0] : old_value[7:0]};
    endfunction

    // CPU stores arrive as a 32-bit value plus a transfer size.  Keep the
    // untouched lanes intact for byte and halfword accesses; this matters for
    // packed palette entries, VRAM pixels, and Thumb STRB/STRH instructions.
    function automatic [31:0] merge_store(
        input [31:0] old_word,
        input [31:0] new_word,
        input [1:0]  store_size,
        input [1:0]  byte_addr
    );
        begin
            case (store_size)
                2'b00: begin
                    case (byte_addr)
                        2'b00: merge_store = {old_word[31:8], new_word[7:0]};
                        2'b01: merge_store = {old_word[31:16], new_word[7:0], old_word[7:0]};
                        2'b10: merge_store = {old_word[31:24], new_word[7:0], old_word[15:0]};
                        default: merge_store = {new_word[7:0], old_word[23:0]};
                    endcase
                end
                2'b01: begin
                    merge_store = byte_addr[1]
                        ? {new_word[15:0], old_word[15:0]}
                        : {old_word[31:16], new_word[15:0]};
                end
                default: merge_store = new_word;
            endcase
        end
    endfunction

    // The CPU and DMA present narrow stores right-justified. Physical
    // byte-enable RAMs instead consume data in the selected byte lanes.
    function automatic [31:0] align_store_data(
        input [31:0] source,
        input [1:0] store_size,
        input [1:0] byte_addr
    );
        begin
            case (store_size)
                2'b00: align_store_data = {24'b0, source[7:0]} << (byte_addr * 8);
                2'b01: align_store_data = {16'b0, source[15:0]} << (byte_addr[1] * 16);
                default: align_store_data = source;
            endcase
        end
    endfunction

    // 0=idle, 1=internal RAM read, 2=cartridge read, 3=data ready,
    // 4=external EWRAM read, 5/6=registered internal RAM read.
    assign ready = !dma_active && (
                   cart_cpu_fast_ready || ewram_cpu_fast_ready ||
`ifdef GBK_POCKET
                   local_read_ready ||
`endif
`ifdef GBK_POCKET
                   iwram_cache_hit ||
`endif
                   (read_state == 3'd3) ||
                   (eeprom_cpu_read && eeprom_ready) ||
                   (req && write && hit_eeprom && eeprom_ready) ||
                   (req && write && !hit_flash && !hit_eeprom && !(EXTERNAL_EWRAM && hit_ewram)) ||
                   (req && write && hit_flash && flash_ready) ||
                   (EXTERNAL_EWRAM && req && write && hit_ewram && ewram_cpu_write_complete));
    // A delayed cartridge response belongs to the latched request, even
    // when a blanking-triggered DMA starts before that response arrives.
    assign cart_req = cart_port_busy && !cart_cpu_response_valid && !cart_dma_response_valid;
    always_ff @(posedge clk) begin
        if (reset) begin
            cart_port_busy <= 0;
            cart_owner_dma <= 0;
            cart_cpu_response_valid <= 0;
            cart_dma_response_valid <= 0;
            cart_response_data <= 0;
            cart_addr <= 0;
            cart_streaming <= 0;
        end else begin
            if (dma_active || (cart_cpu_response_valid && read_state == 4'd2))
                cart_cpu_response_valid <= 0;
            if (cart_dma_response_valid && dma_req)
                cart_dma_response_valid <= 0;
            if (cart_port_busy && cart_ready) begin
                cart_port_busy <= 0;
                cart_response_data <= cart_rdata;
                if (cart_owner_dma) cart_dma_response_valid <= 1;
                else if (!dma_active && !cart_cpu_fast_ready) cart_cpu_response_valid <= 1;
            end else if (!cart_port_busy && !cart_cpu_response_valid && !cart_dma_response_valid) begin
                if (dma_active && dma_req && !dma_write &&
                    dma_addr[31:24] >= 8'h08 && dma_addr[31:24] <= 8'h0d && !dma_hit_eeprom) begin
                    cart_port_busy <= 1;
                    cart_owner_dma <= 1;
                    cart_addr <= dma_addr - 32'h08000000;
                    // Graphics DMA streams should not displace CPU ROM code.
                    // Latch the hint with the address until this owner retires.
                    cart_streaming <= debug_dma_destination[31:24] == 8'h06;
                end else if (!dma_active && req && !write && hit_cart && read_state != 4'd3) begin
                    cart_port_busy <= 1;
                    cart_owner_dma <= 0;
                    cart_addr <= addr - 32'h08000000;
                    cart_streaming <= 0;
                end
            end
        end
    end
    assign ppu_vram_write = req && write && hit_vram && !dma_active;
    assign ppu_vram_addr = {addr[16:2], addr[1]};
    assign ppu_vram_wdata = addr[1] ? wdata[31:16] : wdata[15:0];
    assign render_cpu_write = RENDER_SCHEDULER &&
        ((!dma_active && req && write && hit_vram) ||
         (dma_active && dma_req && dma_write && dma_ready_signal && dma_addr[31:24] == 8'h06));
    // A stalled CPU request can remain asserted throughout DMA. It must
    // never write the address selected for a DMA read (or a pending read).
    assign render_cpu_addr = (dma_active && dma_req && dma_addr[31:24] == 8'h06)
        ? dma_addr[16:2] :
        ((RENDER_SCHEDULER && (read_state == 3'd5 || read_state == 3'd6) &&
          pending_addr[31:24] == 8'h06) ? pending_addr[16:2] : addr[16:2]);
    assign render_cpu_wdata = (dma_active && dma_req && dma_write && dma_addr[31:24] == 8'h06)
        ? align_store_data(dma_wdata, dma_size, dma_addr[1:0])
        : align_store_data(wdata, size, addr[1:0]);
    assign render_cpu_byteena = (dma_active && dma_req && dma_write && dma_addr[31:24] == 8'h06)
        ? ((dma_size == 2'b00) ? (4'b0001 << dma_addr[1:0]) :
           (dma_size == 2'b01) ? (dma_addr[1] ? 4'b1100 : 4'b0011) : 4'b1111)
        : ((size == 2'b00) ? (4'b0001 << addr[1:0]) :
           (size == 2'b01) ? (addr[1] ? 4'b1100 : 4'b0011) : 4'b1111);
`ifdef GBK_POCKET
    assign iwram_ram_addr = (dma_req && dma_addr[31:24] == 8'h03)
        ? dma_addr[14:2]
        : ((read_state == 3'd5 || read_state == 3'd6 || read_state == 4'd9 ||
            read_state == 4'd10 || read_state == 4'd11) &&
           pending_addr[31:24] == 8'h03)
          ? pending_addr[14:2] : addr[14:2];
    assign iwram_ram_wdata = (dma_req && dma_addr[31:24] == 8'h03)
        ? align_store_data(dma_wdata, dma_size, dma_addr[1:0])
        : align_store_data(wdata, size, addr[1:0]);
    assign iwram_ram_byteena = (dma_req && dma_addr[31:24] == 8'h03)
        ? ((dma_size == 2'b00) ? (4'b0001 << dma_addr[1:0]) :
           (dma_size == 2'b01) ? (dma_addr[1] ? 4'b1100 : 4'b0011) : 4'b1111)
        : ((size == 2'b00) ? (4'b0001 << addr[1:0]) :
           (size == 2'b01) ? (addr[1] ? 4'b1100 : 4'b0011) : 4'b1111);
    assign iwram_ram_write = (req && write && hit_iwram && !dma_active) ||
                             (dma_req && dma_write && dma_ready_signal && dma_addr[31:24] == 8'h03);
    gba_pocket_iwram iwram_storage (
        .clk, .write(iwram_ram_write), .addr(iwram_ram_addr),
        .wdata(iwram_ram_wdata), .byteena(iwram_ram_byteena),
        .rdata(iwram_ram_rdata)
    );
    assign debug_probe_iwram_index = iwram_ram_addr;
    assign debug_probe_iwram_rdata = iwram_ram_rdata;
    // Trace the physical IWRAM write port, including DMA and byte lanes.
    // The BIOS IRQ vector lives in the final word at 03FFFFFC.
    always_ff @(posedge clk) begin
        if (reset) begin
            debug_irq_vector_write_data <= 32'b0;
            debug_irq_vector_write_status <= 16'b0;
        end else if (iwram_ram_write && iwram_ram_addr == 13'h1FFF) begin
            debug_irq_vector_write_data <= iwram_ram_wdata;
            debug_irq_vector_write_status <= {
                debug_irq_vector_write_status[15:5] + 11'd1,
                dma_req && dma_addr[31:24] == 8'h03,
                iwram_ram_byteena
            };
        end
    end
    assign pal_ram_addr = dma_active && dma_req && dma_addr[31:24] == 8'h05
        ? dma_addr[9:2]
        : (read_state == 4'd7 || read_state == 4'd8) ? pending_addr[9:2] : addr[9:2];
    assign pal_ram_wdata = dma_active
        ? align_store_data(dma_wdata, dma_size, dma_addr[1:0])
        : align_store_data(wdata, size, addr[1:0]);
    assign pal_ram_byteena = dma_active
        ? ((dma_size == 2'b00) ? (4'b0001 << dma_addr[1:0]) :
           (dma_size == 2'b01) ? (dma_addr[1] ? 4'b1100 : 4'b0011) : 4'b1111)
        : ((size == 2'b00) ? (4'b0001 << addr[1:0]) :
           (size == 2'b01) ? (addr[1] ? 4'b1100 : 4'b0011) : 4'b1111);
    assign pal_ram_write = dma_active
        ? (dma_req && dma_write && dma_ready_signal && dma_addr[31:24] == 8'h05)
        : (req && write && hit_pal);
    // Mirror palette entry zero for the final mode-2 window mux. Both
    // CPU and DMA byte enables follow the physical palette write port.
    always_ff @(posedge clk) begin
        if (reset) ppu_backdrop_color <= 0;
        else if (pal_ram_write && pal_ram_addr == 0) begin
            if (pal_ram_byteena[0]) ppu_backdrop_color[7:0] <= pal_ram_wdata[7:0];
            if (pal_ram_byteena[1]) ppu_backdrop_color[15:8] <= pal_ram_wdata[15:8];
        end
    end
    assign pal_bg_render_addr = (ppu_dispcnt[2:0] == 3'd4)
        // Bitmap lookup is an entry index; the physical palette port uses
        // a byte offset, like the text BG lookup. Preserve index bit zero
        // as the halfword lane rather than dropping it into the byte lane.
        ? {ppu_palette_read_addr[7:0],1'b0} : ppu_bg_palette_read_addr;
    // VRAM scheduler data can change on every render clock. Register its
    // resolved palette address before the RAM's synchronous read port so the
    // BG/window priority chain does not have to reach a hard RAM in one
    // 133 MHz cycle. The next 12.288 MHz video pixel is over ten render
    // clocks away, leaving time for this stage and the RAM read.
    logic [8:0] pal_bg_render_addr_stage;
    logic [1:0] pal_bg_half_pipeline, pal_obj_half_pipeline;
    logic [6:0] pal_bg_word_stage0,pal_bg_word_stage1;
    logic [1:0] pal_bg_word_valid;
    // Mode 2 can change lanes immediately when the returned RAM word already
    // matches its request. Qualifying by the returned word tag preserves the
    // BIOS pixel deadline without combining a new lane with another word.
    wire pal_bg_half_select = ppu_dispcnt[2:0]==3'd2 && pal_bg_word_valid[1] &&
        pal_bg_word_stage1==pal_bg_render_addr[8:2]
        ? pal_bg_render_addr[1] : pal_bg_half_pipeline[1];
    always_ff @(posedge render_clk) begin
        if (reset) begin
            pal_bg_render_addr_stage <= 9'd0;
            pal_bg_half_pipeline <= 0;
            pal_obj_half_pipeline <= 0;
            pal_bg_word_stage0 <= 0;pal_bg_word_stage1 <= 0;pal_bg_word_valid <= 0;
        end else begin
            pal_bg_render_addr_stage <= pal_bg_render_addr;
            // Keep the halfword lane with the address through the RAM's
            // registered address and output. A live lane selects the wrong
            // colour whenever the next request changes bit 1.
            pal_bg_half_pipeline <= {pal_bg_half_pipeline[0],pal_bg_render_addr_stage[1]};
            pal_obj_half_pipeline <= {pal_obj_half_pipeline[0],ppu_obj_palette_read_addr[1]};
            pal_bg_word_stage0 <= pal_bg_render_addr_stage[8:2];
            pal_bg_word_stage1 <= pal_bg_word_stage0;
            pal_bg_word_valid <= {pal_bg_word_valid[0],1'b1};
        end
    end
    gba_pocket_palette palette_storage (
        .cpu_clk(clk), .cpu_write(pal_ram_write), .cpu_addr(pal_ram_addr),
        .cpu_wdata(pal_ram_wdata), .cpu_byteena(pal_ram_byteena),
        .cpu_rdata(pal_ram_rdata), .ppu_clk(render_clk),
        .ppu_addr({1'b0, pal_bg_render_addr_stage[8:2]}), .ppu_rdata(pal_ppu_rdata)
    );
    // Independent runner-up BG lookup for color blending. Every CPU/DMA
    // palette write reaches this copy too.
    wire [31:0] second_palette_word;
    reg [8:0] second_palette_addr;
    reg [1:0] second_palette_half;
    always @(posedge render_clk) begin
        if(reset) begin second_palette_addr<=0;second_palette_half<=0;end
        else begin
            second_palette_addr<=ppu_second_palette_read_addr;
            second_palette_half<={second_palette_half[0],second_palette_addr[1]};
        end
    end
    gba_pocket_palette second_palette_storage(
        .cpu_clk(clk),.cpu_write(pal_ram_write),.cpu_addr(pal_ram_addr),
        .cpu_wdata(pal_ram_wdata),.cpu_byteena(pal_ram_byteena),.cpu_rdata(),
        .ppu_clk(render_clk),.ppu_addr({1'b0,second_palette_addr[8:2]}),.ppu_rdata(second_palette_word));
    assign ppu_second_palette_rdata=second_palette_half[1] ? second_palette_word[31:16] : second_palette_word[15:0];
    // A second copy supplies the OBJ palette without stealing the BG read
    // port. Both copies receive every CPU and DMA palette write.
    gba_pocket_palette obj_palette_storage (
        .cpu_clk(clk), .cpu_write(pal_ram_write), .cpu_addr(pal_ram_addr),
        .cpu_wdata(pal_ram_wdata), .cpu_byteena(pal_ram_byteena),
        .cpu_rdata(), .ppu_clk(render_clk),
        .ppu_addr({1'b1, ppu_obj_palette_read_addr[8:2]}),
        .ppu_rdata(pal_obj_ppu_rdata)
    );
`else
    assign debug_irq_vector_write_data = 32'b0;
    assign ppu_backdrop_color = pal[0][15:0];
    assign debug_irq_vector_write_status = 16'b0;
    assign debug_probe_iwram_index = 13'b0;
    assign debug_probe_iwram_rdata = 32'b0;
`endif
    always_ff @(posedge clk) begin
        if (reset) begin
            dma_vram_wait <= 2'b00;
`ifdef GBK_POCKET
            dma_local_read_wait <= 2'b00;
`endif
        end else begin
            // VRAM registers both its address and output. A single wait
            // bit acknowledges the preceding address's output. Restart the
            // two-clock delay for every read, including consecutive words.
            if (!RENDER_SCHEDULER || !dma_req || dma_write || dma_addr[31:24] != 8'h06)
                dma_vram_wait <= 2'b00;
            else
                dma_vram_wait <= {dma_vram_wait[0],1'b1};
`ifdef GBK_POCKET
            // Each DMA read needs a fresh address/output-register delay.
            // Shifting a zero through the old delay lets its high bit survive
            // the one-cycle write phase and acknowledge the next read early.
            if (!dma_req || !dma_read_registered_ram)
                dma_local_read_wait <= 2'b00;
            else
                dma_local_read_wait <= {dma_local_read_wait[0],1'b1};
`endif
        end
    end
`ifdef GBK_POCKET
`ifdef GBK_DMA_WORD_REUSE
    // DMA still performs every logical read and receives its normal guest
    // timing charge. Reuse only the physical, registered local-RAM word.
    // CPU writes cannot run while DMA owns the bus; matching DMA writes
    // invalidate even for partial lanes and mirrored addresses.
    reg dma_word_valid;
    reg [15:0] dma_word_tag;
    reg [31:0] dma_word_data;
    wire dma_word_eligible = dma_addr[31:24]==8'h03 ||
        (RENDER_SCHEDULER && dma_addr[31:24]==8'h06);
    wire [15:0] dma_word_address = dma_addr[31:24]==8'h03 ?
        {3'b000,dma_addr[14:2]} : {1'b1,dma_addr[16:2]};
    wire dma_word_hit = !reset && dma_active && dma_word_valid &&
        dma_req && !dma_write && dma_word_eligible && dma_word_address==dma_word_tag;
    always_ff @(posedge clk) begin
        // Quiescent state capture/restore happens after DMA releases the bus,
        // so this transient word is discarded before architectural capture.
        if(reset || !dma_active) dma_word_valid <= 1'b0;
        else if(dma_req && dma_write && dma_ready_signal && dma_word_eligible && dma_word_address==dma_word_tag)
            dma_word_valid <= 1'b0;
        else if(dma_req && !dma_write && dma_ready_signal && dma_word_eligible && !dma_word_hit) begin
            dma_word_valid <= 1'b1;
            dma_word_tag <= dma_word_address;
            // Preserve both lanes, including after an upper-halfword read.
            dma_word_data <= dma_addr[31:24]==8'h03 ? iwram_ram_rdata : render_cpu_rdata;
        end
    end
`endif
`endif
    always_comb begin
        dma_ready_signal = dma_req &&
            ((dma_addr[31:24] == 8'h02) || (dma_addr[31:24] == 8'h03) ||
             (dma_addr[31:24] == 8'h05) || (dma_addr[31:24] == 8'h06) ||
             (dma_addr[31:24] == 8'h07));
        // BIOS is read-only, but DMA writes must still finish. Aria's Soul
        // Set initializer zero-fills 0x00003200/0x00003300 with DMA3; waiting
        // for a BIOS write response here would hold the CPU indefinitely.
        // No BIOS write port is enabled by this acknowledgement.
        // The BIOS enables DMA1 for the Direct Sound FIFO during boot.  The
        // FIFO and display I/O writes complete in one accepted DMA cycle.
        // Share the BIOS/I/O decode (regions 00 and 04) to keep this path
        // small. The DMA controller separately gates ready with dma_req.
        if (dma_write && (dma_addr[31:24] & 8'hfb) == 8'h00)
            dma_ready_signal = 1'b1;
        // DMA cannot read BIOS or the unmapped region before EWRAM.
        // These reads still finish. Wario programs a null source while
        // installing a disabled HBlank callback during room setup.
        if (!dma_write && dma_addr[31:25] == 7'd0)
            dma_ready_signal = dma_req;
        if (!dma_write && dma_addr[31:24] >= 8'h08 && dma_addr[31:24] <= 8'h0d)
            dma_ready_signal = dma_req && cart_dma_response_valid;
        if(dma_hit_eeprom) dma_ready_signal=dma_req && eeprom_ready;
        if (EXTERNAL_EWRAM && dma_addr[31:24] == 8'h02)
            dma_ready_signal = dma_req && ewram_dma_response_valid;
        if (RENDER_SCHEDULER && dma_addr[31:24] == 8'h06 && !dma_write)
            dma_ready_signal = dma_req && dma_vram_wait[1];
`ifdef GBK_POCKET
        if (dma_read_registered_ram)
            dma_ready_signal = dma_local_read_wait[1];
`ifdef GBK_DMA_WORD_REUSE
        if(dma_word_hit) dma_ready_signal = dma_req;
`endif
`endif
    end
`ifdef GBK_POCKET
    assign ppu_vram_debug0 = 16'd0;
`else
    assign ppu_vram_debug0 = vram[0][15:0];
`endif
    // Hold the physical transaction and its owner until completion. DMA can
    // preempt a CPU read, but cannot consume that read's delayed response.
    assign ewram_req = EXTERNAL_EWRAM && ewram_port_busy && !ewram_ready;
    always_ff @(posedge clk) begin
        if (reset) begin
            ewram_port_busy <= 0;
            ewram_owner_dma <= 0;
            ewram_cpu_response_valid <= 0;
            ewram_dma_response_valid <= 0;
            ewram_response_data <= 0;
            ewram_cpu_write_complete <= 0;
            ewram_addr <= 0;
            ewram_wdata <= 0;
            ewram_write <= 0;
            ewram_size <= 0;
        end else if (EXTERNAL_EWRAM) begin
            if (ewram_cpu_write_complete && !dma_active && req && write && hit_ewram)
                ewram_cpu_write_complete <= 0;
            if (dma_active || (ewram_cpu_response_valid &&
                ((req && write && hit_ewram) || read_state == 4'd4)))
                ewram_cpu_response_valid <= 0;
            if (ewram_dma_response_valid && dma_req)
                ewram_dma_response_valid <= 0;
            if (ewram_port_busy && ewram_ready) begin
                ewram_port_busy <= 0;
                ewram_response_data <= ewram_rdata;
                if (ewram_owner_dma) ewram_dma_response_valid <= 1;
                else if (ewram_write) ewram_cpu_write_complete <= 1;
                else if (!dma_active && !ewram_cpu_fast_ready) ewram_cpu_response_valid <= 1;
            end else if (!ewram_port_busy && !ewram_cpu_response_valid &&
                         !ewram_dma_response_valid && !ewram_ready) begin
                if (dma_active && dma_req && dma_addr[31:24] == 8'h02) begin
                    ewram_port_busy <= 1;
                    ewram_owner_dma <= 1;
                    ewram_addr <= dma_addr;
                    ewram_wdata <= dma_wdata;
                    ewram_write <= dma_write;
                    ewram_size <= dma_size;
                end else if (!dma_active && req && hit_ewram && read_state != 4'd3 &&
                             !ewram_cpu_write_complete) begin
                    ewram_port_busy <= 1;
                    ewram_owner_dma <= 0;
                    ewram_addr <= addr;
                    ewram_wdata <= wdata;
                    ewram_write <= write;
                    ewram_size <= size;
                end
            end
        end
    end

    gba_timers #(.CYCLE_ENABLE(1)) timers (
`ifdef GBK_SAVESTATE
        .state_hold,.state_write(state_reg_write && state_reg_addr[15:8]==3 && state_reg_addr[7:0]<9),
        .state_addr(state_reg_addr[3:0]),.state_wdata(state_reg_wdata),
        .state_valid(state_timer_valid),.state_rdata(state_timer_rdata),
`endif
        .clk, .reset,
        .cycle_enable(peripheral_tick),
        .req(req && hit_timer && !dma_active), .write, .addr,
        .wdata, .size, .rdata(timer_rdata), .ready(timer_ready), .irq(timer_irq),
        .overflow_pulse(timer_overflow)
    );

    logic [31:0] runtime_ie_if;
    logic runtime_ime;
    logic [31:0] runtime_bios_flags_seen;
    assign debug_runtime_memory = {runtime_bios_flags_seen,
        16'b0, vcount[7:0], 1'b0, dma_active, read_state, irq, runtime_ime,
        runtime_ie_if};
    // Record only flag values actually returned to the CPU, not speculative
    // RAM port values while DMA owns the port.
    always_ff @(posedge clk) begin
        if (reset) runtime_bios_flags_seen <= 0;
        else if (req && !write && ready && addr[31:24] == 8'h03 &&
                 addr[14:2] == 13'h1ffe)
            runtime_bios_flags_seen <= runtime_bios_flags_seen | rdata;
    end
    gba_interrupts interrupts (
`ifdef GBK_SAVESTATE
        .state_hold,.state_write(state_reg_write && state_reg_addr[15:8]==4 && state_reg_addr[7:0]<2),
        .state_addr(state_reg_addr[0]),.state_wdata(state_reg_wdata),
        .state_valid(state_irq_valid),.state_rdata(state_irq_rdata),
`endif
        .clk, .reset,
        .req(req && hit_interrupt && !dma_active), .write, .addr, .wdata, .size,
        .debug_ie_if(runtime_ie_if), .debug_ime(runtime_ime),
        .vblank_irq, .hblank_irq, .vcount_irq, .timer_irq, .dma_irq(dma_completion_irq),
        .keypad_irq,.serial_irq,.gamepak_irq(cartridge_irq && rtc_enable_sync[1]),.stop_wake,
        .rdata(interrupt_rdata), .ready(interrupt_ready), .irq(irq), .halt_wake(halt_wake)
    );

    gba_dma dma (
`ifdef GBK_SAVESTATE
        .state_request(state_dma_request),.state_hold,
        .state_write(state_reg_write && state_reg_addr[15:8]==2 && state_reg_addr[7:0]<34),
        .state_addr(state_reg_addr[5:0]),.state_wdata(state_reg_wdata),.state_quiescent(state_dma_quiescent),
        .state_valid(state_dma_valid),.state_rdata(state_dma_rdata),
`endif
        .cpu_lock((cpu_bus_lock===1'b1) || guest_stopped),
        .fifo_request(guest_stopped ? 2'b0 : audio_fifo_request),
        .vblank_trigger(vblank_trigger),
        .hblank_trigger((NATIVE_TIMING ? display_hblank_edge : display_dot == 11'd674) && vcount < 160),
        .clk, .reset,
        .cfg_req(req && hit_dma), .cfg_write(write), .cfg_addr(addr),
        .cfg_wdata(wdata), .cfg_size(size), .cfg_rdata(dma_cfg_rdata), .cfg_ready(dma_cfg_ready),
        .active(dma_active), .dma_req(dma_engine_req), .dma_write, .dma_size, .dma_addr,
        // A ready peripheral cannot acknowledge a cycle suppressed by the
        // native timing budget. Otherwise DMA skips writes while req is low.
        .dma_wdata, .dma_rdata(dma_mem_rdata), .dma_ready(dma_ready_signal && dma_req),
        .completion_irq(dma_completion_irq),
        .debug_source(debug_dma_source), .debug_destination(debug_dma_destination),
        .debug_status(dma_controller_status)
    );
`ifdef GBK_SAVESTATE
    wire state_timer_valid,state_irq_valid,state_dma_valid,state_apu_valid,state_serial_valid;
    wire [31:0] state_timer_rdata,state_irq_rdata,state_dma_rdata,state_apu_rdata,state_serial_rdata;
    always @*begin
        state_reg_valid=0;state_reg_rdata=0;
        case(state_reg_addr[15:8])
            2:if(state_reg_addr[7:0]<34)begin state_reg_valid=state_dma_valid;state_reg_rdata=state_dma_rdata;end
            3:if(state_reg_addr[7:0]<9)begin state_reg_valid=state_timer_valid;state_reg_rdata=state_timer_rdata;end
            4:if(state_reg_addr[7:0]<2)begin state_reg_valid=state_irq_valid;state_reg_rdata=state_irq_rdata;end
            5:if(state_frozen && state_reg_addr[7:0]>=1 && state_reg_addr[7:0]<=3)begin
                state_reg_valid=!reset;
                case(state_reg_addr[1:0])
                    1:state_reg_rdata={16'd0,keycnt};
                    2:state_reg_rdata={21'd0,keypad_and_matched,keypad_previous};
                    3:state_reg_rdata={16'd0,timing_waitcnt};
                endcase
            end
            6:if(state_ppu_access)begin
                state_reg_valid=!reset;
                case(state_reg_addr[7:0])
                    1:state_reg_rdata={8'd0,vcount,dispstat_control};
                    19:state_reg_rdata={16'd0,ppu_mosaic};
                    21:state_reg_rdata={16'd0,ppu_bldy};
                    22:state_reg_rdata={4'd0,vcount,display_phase,display_dot};
                    23:state_reg_rdata={28'd0,vcount_match_previous,vcount_irq,hblank_irq,vblank_irq};
                    24:state_reg_rdata={4'd0,ppu_bg2x};
                    25:state_reg_rdata={4'd0,ppu_bg2y};
                    default:state_reg_rdata=shared_io_word;
                endcase
            end
            7:if(state_reg_addr[7:0]<64)begin state_reg_valid=state_apu_valid;state_reg_rdata=state_apu_rdata;end
            8:if(state_reg_addr[7:0]<10)begin state_reg_valid=state_serial_valid;state_reg_rdata=state_serial_rdata;end
            9:if(state_reg_addr[7:0]==0)begin state_reg_valid=state_flash_valid;state_reg_rdata=state_flash_rdata;end
                else if(state_reg_addr[7:0]>=16 && state_reg_addr[7:0]<20)begin state_reg_valid=state_eeprom_valid;state_reg_rdata=state_eeprom_rdata;end
            10:if(state_reg_addr[7:0]<4)begin state_reg_valid=state_rtc_valid;state_reg_rdata=state_rtc_rdata;end
            default:begin end
        endcase
    end
`endif

    always_comb begin
        dma_mem_rdata = 32'b0;
        if (dma_addr[31:24] >= 8'h08 && dma_addr[31:24] <= 8'h0d)
            dma_mem_rdata = dma_size == 2'b01 ?
                (dma_addr[1] ? {16'b0,cart_response_data[31:16]} : {16'b0,cart_response_data[15:0]}) : cart_response_data;
        if (dma_addr[31:24] == 8'h02) begin
            if (EXTERNAL_EWRAM)
                dma_mem_rdata = dma_size == 2'b01 ?
                    (dma_addr[1] ? {16'b0, ewram_response_data[31:16]} :
                                   {16'b0, ewram_response_data[15:0]}) : ewram_response_data;
            else
                dma_mem_rdata = dma_size == 2'b01 ? (dma_addr[1] ? {16'b0, ewram[dma_addr[17:2]][31:16]} : {16'b0, ewram[dma_addr[17:2]][15:0]}) : ewram[dma_addr[17:2]];
        end
        else if (dma_addr[31:24] == 8'h03) begin
`ifdef GBK_POCKET
            dma_mem_rdata = dma_size == 2'b01 ?
                (dma_addr[1] ? {16'b0,iwram_ram_rdata[31:16]} :
                               {16'b0,iwram_ram_rdata[15:0]}) : iwram_ram_rdata;
`else
            dma_mem_rdata = dma_size == 2'b01 ? (dma_addr[1] ? {16'b0, iwram[dma_addr[14:2]][31:16]} : {16'b0, iwram[dma_addr[14:2]][15:0]}) : iwram[dma_addr[14:2]];
`endif
        end
        else if (dma_addr[31:24] == 8'h05) begin
`ifdef GBK_POCKET
            dma_mem_rdata = dma_size == 2'b01 ?
                (dma_addr[1] ? {16'b0,pal_ram_rdata[31:16]} :
                               {16'b0,pal_ram_rdata[15:0]}) : pal_ram_rdata;
`else
            dma_mem_rdata = dma_size == 2'b01 ? (dma_addr[1] ? {16'b0, pal[dma_addr[9:2]][31:16]} : {16'b0, pal[dma_addr[9:2]][15:0]}) : pal[dma_addr[9:2]];
`endif
        end
        else if (dma_addr[31:24] == 8'h06) begin
`ifdef GBK_POCKET
            dma_mem_rdata = dma_size == 2'b01 ?
                (dma_addr[1] ? {16'b0,render_cpu_rdata[31:16]} :
                               {16'b0,render_cpu_rdata[15:0]}) : render_cpu_rdata;
`else
            dma_mem_rdata = dma_size == 2'b01 ? (dma_addr[1] ? {16'b0, vram[dma_addr[16:2]][31:16]} : {16'b0, vram[dma_addr[16:2]][15:0]}) : vram[dma_addr[16:2]];
`endif
        end
        else if (dma_addr[31:24] == 8'h07 && dma_addr[9:2] < OAM_WORDS)
            dma_mem_rdata = BLOCK_OAM ? (dma_size==1 ? (dma_addr[1] ? {16'd0,oam_cpu_rdata[31:16]} : {16'd0,oam_cpu_rdata[15:0]}) : oam_cpu_rdata) :
                dma_size == 2'b01 ? (dma_addr[1] ? {16'b0, oam[dma_addr[9:2]][31:16]} : {16'b0, oam[dma_addr[9:2]][15:0]}) : oam[dma_addr[9:2]];
        if(dma_hit_eeprom) dma_mem_rdata={31'd0,eeprom_bit};
`ifdef GBK_POCKET
`ifdef GBK_DMA_WORD_REUSE
        if(dma_word_hit) dma_mem_rdata = dma_size==2'b01 ?
            (dma_addr[1] ? {16'd0,dma_word_data[31:16]} : {16'd0,dma_word_data[15:0]}) : dma_word_data;
`endif
`endif
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            read_state <= 3'd0;
            pending_addr <= 0;
            response_rdata <= 0;
            ppu_vram_rdata_legacy <= 0;
            ppu_palette_rdata <= 0;
        end else if (dma_active) begin
            // DMA owns the shared RAM port while active.  Abandon any CPU
            // read in flight; req remains asserted and will retry after DMA.
            // In particular, never publish a stale IWRAM word sampled from
            // the DMA address as the CPU's completed read.
            read_state <= 3'd0;
            if (dma_req && dma_write && dma_ready_signal) begin
                if (dma_addr[31:24] == 8'h02 && !EXTERNAL_EWRAM) begin
                    if (dma_size == 2'b01) begin
                        if (dma_addr[1]) ewram[dma_addr[17:2]][31:16] <= dma_wdata[15:0];
                        else ewram[dma_addr[17:2]][15:0] <= dma_wdata[15:0];
                    end else ewram[dma_addr[17:2]] <= dma_wdata;
                end else if (dma_addr[31:24] == 8'h03) begin
`ifndef GBK_POCKET
                    if (dma_size == 2'b01) begin
                        if (dma_addr[1]) iwram[dma_addr[14:2]][31:16] <= dma_wdata[15:0];
                        else iwram[dma_addr[14:2]][15:0] <= dma_wdata[15:0];
                    end else iwram[dma_addr[14:2]] <= dma_wdata;
`endif
                end else if (dma_addr[31:24] == 8'h05) begin
`ifndef GBK_POCKET
                    if (dma_size == 2'b01) begin
                        if (dma_addr[1]) pal[dma_addr[9:2]][31:16] <= dma_wdata[15:0];
                        else pal[dma_addr[9:2]][15:0] <= dma_wdata[15:0];
                    end else pal[dma_addr[9:2]] <= dma_wdata;
`endif
                end else if (dma_addr[31:24] == 8'h06) begin
`ifndef GBK_POCKET
                    if (dma_size == 2'b01) begin
                        if (dma_addr[1]) vram[dma_addr[16:2]][31:16] <= dma_wdata[15:0];
                        else vram[dma_addr[16:2]][15:0] <= dma_wdata[15:0];
                    end else vram[dma_addr[16:2]] <= dma_wdata;
`endif
                end else if (!BLOCK_OAM && dma_addr[31:24] == 8'h07 && dma_addr[9:2] < OAM_WORDS) begin
                    if (dma_size == 2'b01) begin
                        if (dma_addr[1]) oam[dma_addr[9:2]][31:16] <= dma_wdata[15:0];
                        else oam[dma_addr[9:2]][15:0] <= dma_wdata[15:0];
                    end else oam[dma_addr[9:2]] <= dma_wdata;
                end
            end
        end else if(read_state==4'd14)begin
            response_rdata<=gpio_rdata;read_state<=3;
        end else if (read_state == 4'd13) begin
            if(eeprom_ready) read_state<=0;
        end else if (read_state == 3'd1) begin
            if (pending_addr[31:24] == 8'h00)       response_rdata <= bios_rdata;
            else if (pending_addr[31:24] == 8'h02)  response_rdata <= ewram[pending_addr[17:2]];
            else if (pending_addr[31:24] == 8'h03) begin
`ifdef GBK_POCKET
                response_rdata <= iwram_ram_rdata;
`else
                response_rdata <= iwram[pending_addr[14:2]];
`endif
            end
`ifdef GBK_SAVESTATE
            else if (pending_addr[31:24] == 8'h04) response_rdata <= shared_io_word;
`else
            else if (pending_addr[31:24] == 8'h04) response_rdata <= io_word(pending_addr);
`endif
            else if (pending_addr[31:24] == 8'h05) begin
`ifdef GBK_POCKET
                response_rdata <= pal_ram_rdata;
`else
                response_rdata <= pal[pending_addr[9:2]];
`endif
            end
            else if (pending_addr[31:24] == 8'h06) begin
`ifdef GBK_POCKET
                response_rdata <= render_cpu_rdata;
`else
                response_rdata <= vram[pending_addr[16:2]];
`endif
            end
            else if (pending_addr[31:24] == 8'h07)
                response_rdata <= (pending_addr[9:2] < OAM_WORDS)
                    ? oam[pending_addr[9:2]] : 32'b0;
            else response_rdata <= 32'h0;
            read_state <= 3'd3;
        end else if (read_state == 4'd12) begin
            if (flash_ready) begin response_rdata <= flash_rdata; read_state <= 3'd3; end
        end else if (read_state == 3'd2) begin
            if (cart_cpu_fast_ready || cart_cpu_response_valid) begin
                response_rdata <= cart_cpu_fast_ready ? cart_cpu_fast_data : cart_response_data;
                read_state <= EARLY_CART_RESPONSE ? 4'd0 : 4'd3;
            end
        end else if (read_state == 3'd4) begin
            if (ewram_cpu_fast_ready || ewram_cpu_response_valid) begin
                response_rdata <= ewram_cpu_fast_ready ? ewram_cpu_fast_data : ewram_response_data;
                read_state <= EARLY_EWRAM_RESPONSE ? 4'd0 : 4'd3;
            end
        end else if (read_state == 3'd5) begin
            read_state <= 3'd6;
        end else if (read_state == 3'd6) begin
`ifdef GBK_POCKET
            // The state-6 acknowledgement returns local_read_data directly.
            // Copying it into response_rdata cannot serve a later state-3
            // acknowledgement because this path returns straight to idle.
            read_state <= 3'd0;
`else
            read_state <= 3'd3;
`endif
        end else if (read_state == 4'd9) begin
`ifdef GBK_POCKET
            if (pending_addr[31:24] == 8'h03 ||
                pending_addr[31:24] == 8'h00)
                read_state <= 4'd10;
            else read_state <= 3'd3;
`else
            response_rdata <= bios_rdata;
            read_state <= 3'd3;
`endif
        end else if (read_state == 4'd10) begin
            read_state <= 4'd11;
        end else if (read_state == 4'd11) begin
`ifdef GBK_POCKET
            response_rdata <= (pending_addr[31:24] == 8'h00)
                ? bios_rdata : iwram_ram_rdata;
`endif
            read_state <= 3'd3;
        end else if (read_state == 4'd7) begin
`ifdef GBK_POCKET
            read_state <= 4'd8;
`else
            read_state <= 3'd3;
`endif
        end else if (read_state == 4'd8) begin
`ifdef GBK_POCKET
            response_rdata <= pal_ram_rdata;
`endif
            read_state <= 4'd3;
        end else if (read_state == 3'd3) begin
            read_state <= 3'd0;
        end else if (req && write) begin
            if (hit_ewram && !EXTERNAL_EWRAM) ewram[addr[17:2]] <= merge_store(ewram[addr[17:2]], wdata, size, addr[1:0]);
            else if (hit_iwram) begin
`ifndef GBK_POCKET
                iwram[addr[14:2]] <= merge_store(iwram[addr[14:2]], wdata, size, addr[1:0]);
`endif
            end
`ifndef GBK_POCKET
            else if (hit_pal)   pal[addr[9:2]] <= merge_store(pal[addr[9:2]], wdata, size, addr[1:0]);
`endif
            else if (hit_vram) begin
`ifndef GBK_POCKET
                vram[addr[16:2]] <= merge_store(vram[addr[16:2]], wdata, size, addr[1:0]);
`endif
            end
            else if (!BLOCK_OAM && hit_oam && addr[9:2] < OAM_WORDS)
                oam[addr[9:2]] <= merge_store(oam[addr[9:2]], wdata, size, addr[1:0]);
        end else if (req) begin
            pending_addr <= addr;
            if(hit_gpio)read_state<=4'd14;
            else if (hit_eeprom) read_state <= 4'd13;
            else if (hit_cart) read_state <= 3'd2;
            else if (hit_flash) read_state <= 4'd12;
            else if (hit_ewram && EXTERNAL_EWRAM) read_state <= 3'd4;
`ifdef GBK_POCKET
            else if (hit_bios) read_state <= 3'd5;
`else
            else if (hit_bios) read_state <= 3'd1;
`endif
            else if (RENDER_SCHEDULER && hit_vram) read_state <= 3'd5;
`ifdef GBK_POCKET
            else if (hit_iwram) begin
                // A cache hit completes on this edge. Stay idle so block
                // transfers may present a different address immediately.
                if(!iwram_cache_hit) read_state<=3'd5;
            end
            else if (BLOCK_OAM && hit_oam) read_state <= 3'd5;
            else if (hit_pal) read_state <= 4'd7;
`endif
            else read_state <= 3'd1;
        end

        // The display engine gets a second, synchronous read port into the
        // same VRAM used by the CPU.  This avoids a second 240x160 framebuffer
        // copy in the Pocket FPGA fabric.
`ifndef GBK_POCKET
        if (!RENDER_SCHEDULER && ppu_vram_read_addr[15:1] < VRAM_WORDS)
            ppu_vram_rdata_legacy <= ppu_vram_read_addr[0]
                ? vram[ppu_vram_read_addr[15:1]][31:16]
                : vram[ppu_vram_read_addr[15:1]][15:0];
`endif
`ifndef GBK_POCKET
        if (ppu_palette_read_addr[8:1] < 256)
            ppu_palette_rdata <= ppu_palette_read_addr[0]
                ? pal[ppu_palette_read_addr[8:1]][31:16]
                : pal[ppu_palette_read_addr[8:1]][15:0];
`else
        ppu_palette_rdata <= pal_bg_half_select
            ? pal_ppu_rdata[31:16] : pal_ppu_rdata[15:0];
`endif
    end

`ifndef GBK_POCKET
    // Legacy asynchronous PPU taps are retained for the unit-test/reference
    // path only.  The Pocket path must not elaborate these reads: Quartus can
    // otherwise preserve the old array fanout even when the scheduler drives
    // the outputs.
    generate if (!RENDER_SCHEDULER) begin : legacy_ppu_array_reads
    always_comb begin
        legacy_bg_map_rdata = 16'd0;
        legacy_bg_tile_rdata = 16'd0;
        legacy_bg1_map_rdata = 16'd0;
        legacy_bg1_tile_rdata = 16'd0;
        legacy_bg2_map_rdata = 16'd0;
        legacy_bg2_tile_rdata = 16'd0;
        legacy_bg3_map_rdata = 16'd0;
        legacy_bg3_tile_rdata = 16'd0;
        legacy_obj_tile_rdata = 16'd0;
        if (ppu_bg_map_read_addr[15:1] < VRAM_WORDS)
            legacy_bg_map_rdata = ppu_bg_map_read_addr[0]
                ? vram[ppu_bg_map_read_addr[15:1]][31:16]
                : vram[ppu_bg_map_read_addr[15:1]][15:0];
        if (ppu_bg_tile_read_addr[15:1] < VRAM_WORDS)
            legacy_bg_tile_rdata = ppu_bg_tile_read_addr[0]
                ? vram[ppu_bg_tile_read_addr[15:1]][31:16]
                : vram[ppu_bg_tile_read_addr[15:1]][15:0];
        if (ppu_bg1_map_read_addr[15:1] < VRAM_WORDS)
            legacy_bg1_map_rdata = ppu_bg1_map_read_addr[0]
                ? vram[ppu_bg1_map_read_addr[15:1]][31:16]
                : vram[ppu_bg1_map_read_addr[15:1]][15:0];
        if (ppu_bg1_tile_read_addr[15:1] < VRAM_WORDS)
            legacy_bg1_tile_rdata = ppu_bg1_tile_read_addr[0]
                ? vram[ppu_bg1_tile_read_addr[15:1]][31:16]
                : vram[ppu_bg1_tile_read_addr[15:1]][15:0];
        if (ppu_bg2_map_read_addr[15:1] < VRAM_WORDS)
            legacy_bg2_map_rdata = ppu_bg2_map_read_addr[0]
                ? vram[ppu_bg2_map_read_addr[15:1]][31:16]
                : vram[ppu_bg2_map_read_addr[15:1]][15:0];
        if (ppu_bg2_tile_read_addr[15:1] < VRAM_WORDS)
            legacy_bg2_tile_rdata = ppu_bg2_tile_read_addr[0]
                ? vram[ppu_bg2_tile_read_addr[15:1]][31:16]
                : vram[ppu_bg2_tile_read_addr[15:1]][15:0];
        if (ppu_bg3_map_read_addr[15:1] < VRAM_WORDS)
            legacy_bg3_map_rdata = ppu_bg3_map_read_addr[0]
                ? vram[ppu_bg3_map_read_addr[15:1]][31:16]
                : vram[ppu_bg3_map_read_addr[15:1]][15:0];
        if (ppu_bg3_tile_read_addr[15:1] < VRAM_WORDS)
            legacy_bg3_tile_rdata = ppu_bg3_tile_read_addr[0]
                ? vram[ppu_bg3_tile_read_addr[15:1]][31:16]
                : vram[ppu_bg3_tile_read_addr[15:1]][15:0];
        if (ppu_obj_tile_read_addr[16:1] < VRAM_WORDS)
            legacy_obj_tile_rdata = ppu_obj_tile_read_addr[0]
                ? vram[ppu_obj_tile_read_addr[16:1]][31:16]
                : vram[ppu_obj_tile_read_addr[16:1]][15:0];
    end
    end endgenerate
`endif

    always_comb begin
        ppu_bg_palette_rdata = 16'd0;
        ppu_obj_palette_rdata = 16'd0;
        ppu_oam_data_flat = 8192'd0;
`ifdef GBK_POCKET
        ppu_bg_palette_rdata = pal_bg_half_select
            ? pal_ppu_rdata[31:16] : pal_ppu_rdata[15:0];
        ppu_obj_palette_rdata = pal_obj_half_pipeline[1]
            ? pal_obj_ppu_rdata[31:16] : pal_obj_ppu_rdata[15:0];
`else
        if (ppu_bg_palette_read_addr[8:1] < 256)
            ppu_bg_palette_rdata = ppu_bg_palette_read_addr[0]
                ? pal[ppu_bg_palette_read_addr[8:1]][31:16]
                : pal[ppu_bg_palette_read_addr[8:1]][15:0];
        if (ppu_obj_palette_read_addr[8:1] < 256)
            ppu_obj_palette_rdata = ppu_obj_palette_read_addr[0]
                ? pal[ppu_obj_palette_read_addr[8:1]][31:16]
                : pal[ppu_obj_palette_read_addr[8:1]][15:0];
`endif
        for (integer oi = 0; oi < (BLOCK_OAM ? 0 : OAM_WORDS/2); oi = oi + 1) begin
            ppu_oam_data_flat[(oi*48) +: 16] = oam[oi*2][15:0];
            ppu_oam_data_flat[(oi*48) + 16 +: 16] = oam[oi*2][31:16];
            ppu_oam_data_flat[(oi*48) + 32 +: 16] = oam[oi*2+1][15:0];
            // Keep existing packed attributes first; matrix coefficients
            // are the fourth OAM halfwords, four entries per affine matrix.
            ppu_oam_data_flat[6144+oi*16+:16] = oam[oi*2+1][31:16];
        end
    end

`ifndef GBK_POCKET
    assign ppu_second_palette_rdata=ppu_second_palette_read_addr[1] ?
        pal[ppu_second_palette_read_addr[8:2]][31:16] : pal[ppu_second_palette_read_addr[8:2]][15:0];
`endif
    assign render_addr_flat[0*17 +: 17] = {1'b0, ppu_bg_map_read_addr};
    assign render_addr_flat[1*17 +: 17] = {1'b0, ppu_bg_tile_read_addr};
    assign render_addr_flat[2*17 +: 17] = {1'b0, ppu_bg1_map_read_addr};
    assign render_addr_flat[3*17 +: 17] = {1'b0, ppu_bg1_tile_read_addr};
    assign render_addr_flat[4*17 +: 17] = {1'b0, ppu_bg2_map_read_addr};
    assign render_addr_flat[5*17 +: 17] = {1'b0, ppu_bg2_tile_read_addr};
    assign render_addr_flat[6*17 +: 17] = {1'b0, ppu_bg3_map_read_addr};
    assign render_addr_flat[7*17 +: 17] = {1'b0, ppu_bg3_tile_read_addr};
    assign render_addr_flat[8*17 +: 17] = ppu_obj_tile_read_addr;
    assign render_addr_flat[9*17 +: 17] = {1'b0, ppu_vram_read_addr};
    // Mode 1: affine map/tile pairs at 0/4 and 5/9; BG0 at 1/2,
    // BG1 at 3/6, OBJ at 7. The scheduler restores the logical port tags.
    // The legacy mode-2 path retains its map at 0 and dependent tile at 5.
    wire [169:0] legacy_scheduled_addr_flat;
    assign scheduled_addr_flat = mode2_row_affine ? {render_addr_flat[7*17+:17],render_addr_flat[6*17+:17],render_addr_flat[8*17+:17],render_addr_flat[7*17+:17],render_addr_flat[5*17+:17],render_addr_flat[7*17+:17],render_addr_flat[4*17+:17],render_addr_flat[6*17+:17],render_addr_flat[4*17+:17],render_addr_flat[6*17+:17]} : legacy_scheduled_addr_flat;
    wire mode1_affine = ppu_dispcnt[2:0]==1;
    assign legacy_scheduled_addr_flat[0*17 +: 17] = (mode1_affine || ppu_dispcnt[2:0] == 3'd2)
        ? render_addr_flat[6*17 +: 17] : render_addr_flat[0*17 +: 17];
    // With native OAM rows, windows already come from the row RAM. Reuse
    // their spare slot and the redundant tile probe for a second affine
    // map/tile pair, leaving the legacy window-fetch path available.
    wire mode2_row_affine = BLOCK_OAM && NATIVE_TIMING && ppu_dispcnt[2:0]==2;
    assign legacy_scheduled_addr_flat[1*17 +: 17] = mode1_affine ? render_addr_flat[0*17+:17] : mode2_row_affine ? render_addr_flat[7*17+:17] :
        ppu_dispcnt[2:0] == 2 ? ppu_obj_window_extra_read_addr[0+:17] : render_addr_flat[1*17 +: 17];
    assign legacy_scheduled_addr_flat[2*17 +: 17] = mode1_affine ? render_addr_flat[1*17+:17] : ppu_dispcnt[2:0] == 3'd2
        ? render_addr_flat[9*17 +: 17] : render_addr_flat[2*17 +: 17];
    assign legacy_scheduled_addr_flat[3*17 +: 17] = mode1_affine ? render_addr_flat[2*17+:17] : ppu_dispcnt[2:0] == 3'd2
        ? ppu_obj_window_extra_read_addr[0+:17] : render_addr_flat[3*17 +: 17];
    assign legacy_scheduled_addr_flat[4*17 +: 17] = mode1_affine ? render_addr_flat[7*17+:17] : mode2_row_affine ? render_addr_flat[6*17+:17] : (ppu_dispcnt[2:0] == 3'd2)
        ? render_addr_flat[7*17 +: 17] : render_addr_flat[4*17 +: 17];
    // Native mode 2 uses map/tile pairs 0/5 and 4/1 (next round),
    // since OAM-row windows do not need the legacy per-pixel mask slots.
    // Legacy mode 2 keeps its independent earlier tile probe at slot 4.
    assign legacy_scheduled_addr_flat[5*17 +: 17] = mode1_affine ? render_addr_flat[6*17+:17] : (ppu_dispcnt[2:0] == 3'd2)
        ? render_addr_flat[7*17 +: 17] : render_addr_flat[5*17 +: 17];
    // Bitmap modes (including the BIOS boot logo) use the framebuffer read
    // port rather than a tile-layer read. Keep it on the same single-port
    // VRAM scheduler as the BG reads.
    assign legacy_scheduled_addr_flat[6*17 +: 17] = mode1_affine ? render_addr_flat[3*17+:17] : render_addr_flat[9*17 +: 17];
    assign legacy_scheduled_addr_flat[7*17 +: 17] = render_addr_flat[8*17 +: 17];
    assign legacy_scheduled_addr_flat[8*17 +: 17] = mode1_affine ? render_addr_flat[9*17+:17] : render_addr_flat[6*17 +: 17];
    assign legacy_scheduled_addr_flat[9*17 +: 17] = render_addr_flat[7*17 +: 17];

    generate
        if (RENDER_SCHEDULER) begin : scheduled_render_reads
            gba_vram_render_scheduler #(.PORTS(10), .WINDOW_SLOT_ALIASES(1'b1)) scheduler (
                .mode2_window_reads(ppu_dispcnt[2:0] == 3'd2),
                .mode1_affine_reads(ppu_dispcnt[2:0] == 3'd1),
                .mode2_affine_reads(mode2_row_affine),
                .cpu_clk(clk), .reset,
                .cpu_write(render_cpu_write), .cpu_addr(render_cpu_addr),
                .cpu_wdata(render_cpu_wdata), .cpu_byteena(render_cpu_byteena), .render_clk,
                .render_addr_flat(scheduled_addr_flat), .render_data_flat(scheduled_data_flat), .cpu_rdata(render_cpu_rdata),
                .obj_word_data(ppu_obj_tile_word),
                .obj_word_addr(ppu_obj_tile_word_addr),.obj_word_valid(ppu_obj_tile_word_valid)
            );
            assign ppu_bg_map_rdata = scheduled_data_flat[0*16 +: 16];
            assign ppu_bg_tile_rdata = scheduled_data_flat[1*16 +: 16];
            assign ppu_bg1_map_rdata = scheduled_data_flat[2*16 +: 16];
            assign ppu_bg1_tile_rdata = scheduled_data_flat[3*16 +: 16];
            assign ppu_bg2_map_rdata = scheduled_data_flat[4*16 +: 16];
            assign ppu_bg2_tile_rdata = mode2_row_affine ? scheduled_data_flat[3*16+:16] : scheduled_data_flat[5*16 +: 16];
            assign ppu_bg3_map_rdata = ppu_dispcnt[2:0]==1 ? scheduled_data_flat[4*16+:16] : ppu_dispcnt[2:0]==2 ? scheduled_data_flat[0*16 +: 16] : scheduled_data_flat[8*16 +: 16];
            assign ppu_bg3_tile_rdata = ppu_dispcnt[2:0]==2 ? scheduled_data_flat[5*16 +: 16] : scheduled_data_flat[9*16 +: 16];
            assign debug_bg3_tile_raw = scheduled_data_flat[4*16 +: 16];
            assign ppu_obj_tile_rdata = scheduled_data_flat[7*16 +: 16];
            assign ppu_vram_rdata = scheduled_data_flat[6*16 +: 16];
            assign ppu_obj_window_extra_read_data = scheduled_data_flat[1*16+:48];
        end else begin : legacy_render_reads
            assign ppu_bg_map_rdata = legacy_bg_map_rdata;
            assign ppu_bg_tile_rdata = legacy_bg_tile_rdata;
            assign ppu_bg1_map_rdata = legacy_bg1_map_rdata;
            assign ppu_bg1_tile_rdata = legacy_bg1_tile_rdata;
            assign ppu_bg2_map_rdata = legacy_bg2_map_rdata;
            assign ppu_bg2_tile_rdata = legacy_bg2_tile_rdata;
            assign ppu_bg3_map_rdata = legacy_bg3_map_rdata;
            assign ppu_bg3_tile_rdata = legacy_bg3_tile_rdata;
            assign debug_bg3_tile_raw = legacy_bg3_tile_rdata;
            assign ppu_obj_tile_rdata = legacy_obj_tile_rdata;
            assign ppu_obj_tile_word = 32'd0;
            assign ppu_obj_tile_word_addr = 16'd0;
            assign ppu_obj_tile_word_valid = 1'b0;
`ifdef GBK_POCKET
            assign ppu_obj_window_extra_read_data = 0;
`else
            for(genvar n=0;n<3;n=n+1) begin : window_legacy
                wire [16:0] a = ppu_obj_window_extra_read_addr[n*17+:17];
                assign ppu_obj_window_extra_read_data[n*16+:16] = a[16:1]<VRAM_WORDS ?
                    (a[0] ? vram[a[16:1]][31:16] : vram[a[16:1]][15:0]) : 16'b0;
            end
`endif
            assign ppu_vram_rdata = ppu_vram_rdata_legacy;
        end
    endgenerate

endmodule
