//
// User core top-level
//
// Instantiated by the real top-level: apf_top
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;      // reset or cs2, we let the hw control it by itself
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
assign cart_tran_pin31 = 1'bz;      // input
assign cart_tran_pin31_dir = 1'b0;  // input

wire [3:0] gba_link_out,gba_link_dir;
assign port_tran_so = gba_link_dir[3] ? gba_link_out[3] : 1'bz;
assign port_tran_so_dir = gba_link_dir[3];
assign port_tran_si = gba_link_dir[2] ? gba_link_out[2] : 1'bz;
assign port_tran_si_dir = gba_link_dir[2];
assign port_tran_sd = gba_link_dir[1] ? gba_link_out[1] : 1'bz;
assign port_tran_sd_dir = gba_link_dir[1];
assign port_tran_sck = gba_link_dir[0] ? gba_link_out[0] : 1'bz;
assign port_tran_sck_dir = gba_link_dir[0];

// tie off the rest of the pins we are not using
`ifdef GBK_SDRAM_EWRAM
localparam GBA_SDRAM_EWRAM=1;
`else
localparam GBA_SDRAM_EWRAM=0;
`endif
`ifdef GBK_SDRAM_ROM
localparam GBA_SDRAM_ROM=1;
`else
localparam GBA_SDRAM_ROM=0;
`endif
`ifdef GBK_EXTERNAL_SAVE
localparam GBA_EXTERNAL_SAVE=1;
`else
localparam GBA_EXTERNAL_SAVE=0;
`endif
`ifdef GBK_EEPROM
localparam GBA_EEPROM=1;
`else
localparam GBA_EEPROM=0;
`endif
wire gba_save_boot_ready,gba_save_fault,gba_save_load_valid;
`ifdef GBK_BOOT_DIAGNOSTIC
`ifdef GBK_BOOT_DIAGNOSTIC_LIVE_ONLY
localparam GBA_BOOT_DIAGNOSTIC=2;
`else
localparam GBA_BOOT_DIAGNOSTIC=1;
`endif
`else
localparam GBA_BOOT_DIAGNOSTIC=0;
`endif
`ifdef GBK_BOOT_DIAGNOSTIC_POLLS
localparam GBA_BOOT_DIAGNOSTIC_POLLS=`GBK_BOOT_DIAGNOSTIC_POLLS;
`else
localparam GBA_BOOT_DIAGNOSTIC_POLLS=0;
`endif
wire sdram_clock_locked,sdram_initialized,sdram_clock_locked_s;
wire startup_pll_reset,memory_startup_reset;
`ifdef GBK_EWRAM_BURST_FILL
localparam GBA_EWRAM_BURST_FILL=1;
`else
localparam GBA_EWRAM_BURST_FILL=0;
`endif
`ifdef GBK_ROM_DIRECT_BURST
localparam GBA_ROM_DIRECT_BURST=1;
`else
localparam GBA_ROM_DIRECT_BURST=0;
`endif
`ifdef GBK_ROM_FILL_NEIGHBOR
localparam GBA_ROM_FILL_NEIGHBOR=1;
`else
localparam GBA_ROM_FILL_NEIGHBOR=0;
`endif
generate if(GBA_SDRAM_EWRAM || GBA_SDRAM_ROM) begin : sdram_clocking
    gba_sdram_clock forward_clock(.refclk(clk_74a),.reset(~pll_core_locked_s),
        .locked(sdram_clock_locked),.dram_clk(dram_clk));
end else begin : no_sdram_clocking
    assign sdram_clock_locked=1'b1;
    assign dram_clk=1'b0;
end endgenerate



assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;


// for bridge write data, we just broadcast it to all bus devices
// for bridge read data, we have to mux it
// add your own devices here
always @(*) begin
    casex(bridge_addr)
    default: begin
        bridge_rd_data <= 0;
    end
    32'h0Exxxxxx: begin
        bridge_rd_data <= gba_save_bridge_rdata;
    end
    32'h10xxxxxx: begin
`ifdef GBK_FAST_FORWARD
        if(bridge_addr==32'h10000010 || bridge_addr==32'h10000014 || bridge_addr==32'h10000018) bridge_rd_data <= gba_fast_forward_rdata;
        else
`endif
`ifdef GBK_PLAYTIME
        bridge_rd_data <= gba_playtime_rdata;
`else
        bridge_rd_data <= 0;
`endif
    end
    32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
    end
`ifdef GBK_POCKET_STATE
    32'h12xxxxxx: bridge_rd_data <= pstate_bridge_rdata;
`endif
    endcase
end


//
// host/target command handler
//
    wire gba_log_valid, gba_log_ready;
wire [31:0] gba_log_data;
`ifndef GBK_DIAGNOSTIC
assign gba_log_valid = 1'b0;
assign gba_log_data = 0;
`endif
    wire            reset_n;                // driven by host commands, can be used as core-wide reset
    wire    [31:0]  cmd_bridge_rd_data;
    
// bridge host commands
// synchronous to clk_74a
    wire            memory_boot_ready = (!(GBA_SDRAM_EWRAM || GBA_SDRAM_ROM) || sdram_initialized) && gba_save_boot_ready;
    wire            status_boot_done = pll_core_locked_s && !memory_startup_reset && memory_boot_ready;
    wire            status_setup_done = status_boot_done; // rising edge triggers a target command
    wire            status_running = reset_n; // we are running as soon as reset_n goes high
    // Bits 4:0: save fault, save ready, SDRAM initialized, SDRAM PLL, core PLL.
    wire [4:0] boot_diagnostic_signals={gba_save_fault,gba_save_boot_ready,
        sdram_initialized,sdram_clock_locked_s,pll_core_locked_s};

    wire            dataslot_requestread;
    wire    [15:0]  dataslot_requestread_id;
    wire dataslot_requestread_ack;
    wire gba_save_requestread_ack;
`ifdef GBK_PLAYTIME
    wire gba_stats_ack;
    assign dataslot_requestread_ack=dataslot_requestread_id==16'd3 ? gba_stats_ack : gba_save_requestread_ack;
`else
    assign dataslot_requestread_ack=gba_save_requestread_ack;
`endif
    wire dataslot_requestread_ok = 1;
    wire [31:0] gba_save_rdata, gba_save_bridge_rdata;
    wire gba_save_locked, gba_save_export, gba_save_sram;
    wire gba_save_eeprom,gba_eeprom_large;
    wire gba_eeprom_large_s;
    synch_3 eeprom_size_sync(gba_eeprom_large,gba_eeprom_large_s,clk_74a);
    reg gba_cart_large=0;
    always @(posedge clk_74a) begin
        if(gba_cart_load_write) begin
            if(bridge_addr==32'h08000000) gba_cart_large<=0;
            else if(bridge_addr[24]) gba_cart_large<=1;
        end
    end
    gba_save_bridge #(.DEFER_READ(GBA_EXTERNAL_SAVE || GBA_EEPROM)) save_bridge (
        .save_rvalid(gba_save_load_valid),.clk(clk_74a), .bridge_rd(bridge_rd), .request_read(dataslot_requestread),
        .request_id(dataslot_requestread_id), .allcomplete(dataslot_allcomplete),
        .request_ack(gba_save_requestread_ack), .export_lock(gba_save_export),
        .export_locked(gba_save_locked), .bridge_addr(bridge_addr),
        .endian_little(bridge_endian_little), .save_rdata(gba_save_rdata),
        .bridge_rdata(gba_save_bridge_rdata)
    );

    wire            dataslot_requestwrite;
    wire    [15:0]  dataslot_requestwrite_id;
    wire    [31:0]  dataslot_requestwrite_size;
    wire            dataslot_requestwrite_ack = memory_boot_ready;
    wire            dataslot_requestwrite_ok = 1;

    wire            dataslot_update;
    wire    [15:0]  dataslot_update_id;
    wire    [31:0]  dataslot_update_size;
    
    wire            dataslot_allcomplete;
    wire gba_save_write_allowed,gba_save_read_allowed;
    gba_save_transfer_guard save_transfer_guard (
        .clk(clk_74a),.allcomplete(dataslot_allcomplete),
        .request_write(dataslot_requestwrite),.write_ack(dataslot_requestwrite_ack),
        .write_id(dataslot_requestwrite_id),
        .request_read(dataslot_requestread),.read_ack(dataslot_requestread_ack),
        .read_id(dataslot_requestread_id),
        .write_allowed(gba_save_write_allowed),.read_allowed(gba_save_read_allowed)
    );

    wire     [31:0] rtc_epoch_seconds;
    wire     [31:0] rtc_date_bcd;
    wire     [31:0] rtc_time_bcd;
    wire            rtc_valid;
    wire            rtc_update_toggle;

    wire            savestate_supported;
    wire    [31:0]  savestate_addr;
    wire    [31:0]  savestate_size;
    wire    [31:0]  savestate_maxloadsize;

    wire            savestate_start;
    wire            savestate_start_ack;
    wire            savestate_start_busy;
    wire            savestate_start_ok;
    wire            savestate_start_err;

    wire            savestate_load;
    wire            savestate_load_ack;
    wire            savestate_load_busy;
    wire            savestate_load_ok;
    wire            savestate_load_err;
`ifdef GBK_POCKET_STATE
    assign savestate_supported=1'b1;
    assign savestate_addr=32'h12000000;
    assign savestate_size=32'd535528;
    assign savestate_maxloadsize=32'd535528;
    wire pstate_reset_request,pstate_reset_ready;
    wire pstate_busy,pstate_done,pstate_stopped,pstate_start,pstate_restore,pstate_cancel;
    wire [3:0] pstate_error;
    wire pstate_identity_ready;
    wire [31:0] pstate_rom_crc,pstate_rom_bytes,pstate_bios_crc;
    wire pstate_transport_busy,pstate_transport_fault;
    wire [31:0] pstate_bridge_rdata,pstate_host_offset,pstate_host_wdata,pstate_host_rdata;
    wire pstate_host_valid,pstate_host_write,pstate_host_consume,pstate_host_ready,pstate_host_response,pstate_host_error;
    wire pstate_cpu_request,pstate_dma_request,pstate_hold,pstate_reg_write,pstate_cpu_idle,pstate_dma_idle,pstate_held,pstate_reg_valid;
    wire [15:0] pstate_reg_addr;
    wire [31:0] pstate_reg_wdata,pstate_reg_rdata;
    wire pstate_guest_idle,pstate_resume_prepare,pstate_resume_ready,pstate_resume_complete;
    wire pstate_bulk_valid,pstate_bulk_write,pstate_bulk_consume,pstate_bulk_ready,pstate_bulk_response,pstate_bulk_error;
    wire [31:0] pstate_bulk_addr,pstate_bulk_wdata,pstate_bulk_rdata;
    wire pstate_memory_valid,pstate_memory_write,pstate_memory_consume,pstate_memory_ready,pstate_memory_response;
    wire [24:0] pstate_memory_addr;
    wire [31:0] pstate_memory_wdata;
    wire [63:0] pstate_memory_rdata;
    wire [3:0] pstate_memory_byteena;
    wire pstate_save_access,pstate_save_eeprom,pstate_save_idle,pstate_save_done,pstate_save_write,pstate_save_read;
    wire [14:0] pstate_save_addr;
    wire [31:0] pstate_save_wdata;
    wire pstate_rtc_lock,pstate_rtc_start,pstate_rtc_restore,pstate_rtc_write,pstate_rtc_ready,pstate_rtc_done,pstate_rtc_error;
    wire [1:0] pstate_rtc_index;
    wire [31:0] pstate_rtc_wdata,pstate_rtc_rdata;
    wire pstate_transfer_allowed=!savestate_start_busy && !savestate_load_busy && !pstate_busy && !pstate_reset_request;
    reg pstate_running_previous=0;
    always @(posedge clk_74a)pstate_running_previous<=reset_n;
    wire pstate_host_reset=memory_startup_reset || (pstate_running_previous && !reset_n);
    // Register the loader descriptor before identity range/order admission.
    // APF completes the command before streaming bytes, leaving ample time
    // for this host-clock stage. Ordinary startup uses 0082, deferred uses 008A.
    reg pstate_rom_begin=0;
    reg [31:0] pstate_rom_size=0;
    always @(posedge clk_74a)begin
        if(memory_startup_reset)begin pstate_rom_begin<=0;pstate_rom_size<=0;end
        else begin
            pstate_rom_begin<=(dataslot_requestwrite && dataslot_requestwrite_id==0) ||
                              (dataslot_update && dataslot_update_id==0);
            pstate_rom_size<=dataslot_requestwrite ? dataslot_requestwrite_size : dataslot_update_size;
        end
    end
    gba_state_identity pstate_identity(.clk(clk_74a),.reset(memory_startup_reset),
        .rom_begin(pstate_rom_begin),.rom_size(pstate_rom_size),
        .rom_write(gba_cart_load_write),.bios_write(gba_bios_load_write),
        .rom_offset({7'd0,gba_cart_load_addr,2'b0}),.bios_offset({8'd0,bridge_addr[23:0]}),.load_data(gba_load_wdata),
        .ready(pstate_identity_ready),.rom_crc(pstate_rom_crc),.rom_bytes(pstate_rom_bytes),.bios_crc(pstate_bios_crc));
    gba_state_host pstate_host(.clk(clk_74a),.reset(pstate_host_reset),.enabled(1'b1),
        .identity_ready(pstate_identity_ready && reset_n),.owners_idle(dataslot_allcomplete && !gba_save_export),
        .capture_request(savestate_start),.load_request(savestate_load),
        .capture_ack(savestate_start_ack),.capture_busy(savestate_start_busy),.capture_ok(savestate_start_ok),.capture_error(savestate_start_err),
        .load_ack(savestate_load_ack),.load_busy(savestate_load_busy),.load_ok(savestate_load_ok),.load_error(savestate_load_err),
        .lifecycle_request(pstate_reset_request),.lifecycle_ready(pstate_reset_ready),
        .machine_start(pstate_start),.machine_restore(pstate_restore),.machine_cancel(pstate_cancel),
        .machine_busy(pstate_busy),.machine_done(pstate_done),.machine_failed_stopped(pstate_stopped),.machine_error(pstate_error),
        .machine_release_done(pstate_resume_complete),
        .endian_little(bridge_endian_little),.bridge_rd(bridge_rd),.bridge_wr(bridge_wr),.bridge_addr(bridge_addr),.bridge_wdata(bridge_wr_data),.bridge_rdata(pstate_bridge_rdata),
        .transport_busy(pstate_transport_busy),.transport_fault(pstate_transport_fault),
        .host_valid(pstate_host_valid),.host_write(pstate_host_write),.host_response_ready(pstate_host_consume),
        .host_offset(pstate_host_offset),.host_wdata(pstate_host_wdata),.host_ready(pstate_host_ready),
        .host_response(pstate_host_response),.host_error(pstate_host_error),.host_rdata(pstate_host_rdata));
    gba_state_machine pstate_machine(.host_clk(clk_74a),.guest_clk(clk_core_39936),.reset(!reset_n),
        .start(pstate_start),.restore(pstate_restore),.cancel(pstate_cancel),
        .rom_crc(pstate_rom_crc),.rom_bytes(pstate_rom_bytes),.bios_crc(pstate_bios_crc),
        .busy(pstate_busy),.done(pstate_done),.failed_stopped(pstate_stopped),.error_code(pstate_error),
        .guest_transactions_idle(pstate_guest_idle),.resume_prepare(pstate_resume_prepare),.resume_ready(pstate_resume_ready),
        .state_cpu_request(pstate_cpu_request),.state_dma_request(pstate_dma_request),.state_hold(pstate_hold),
        .state_cpu_quiescent(pstate_cpu_idle),.state_dma_quiescent(pstate_dma_idle),.state_held(pstate_held),
        .state_reg_write(pstate_reg_write),.state_reg_addr(pstate_reg_addr),.state_reg_wdata(pstate_reg_wdata),
        .state_reg_valid(pstate_reg_valid),.state_reg_rdata(pstate_reg_rdata),
        .state_bulk_valid(pstate_bulk_valid),.state_bulk_write(pstate_bulk_write),.state_bulk_response_ready(pstate_bulk_consume),
        .state_bulk_addr(pstate_bulk_addr),.state_bulk_wdata(pstate_bulk_wdata),.state_bulk_ready(pstate_bulk_ready),
        .state_bulk_response(pstate_bulk_response),.state_bulk_error(pstate_bulk_error),.state_bulk_rdata(pstate_bulk_rdata),
        .state_save_raw_access(pstate_save_access),.state_save_raw_eeprom(pstate_save_eeprom),
        .state_save_raw_idle(pstate_save_idle),.state_save_raw_done(pstate_save_done),
        .save_write(pstate_save_write),.save_read(pstate_save_read),.save_addr(pstate_save_addr),.save_wdata(pstate_save_wdata),
        .save_fault(gba_save_fault),.save_rdata(gba_save_rdata),
        .rtc_lock(pstate_rtc_lock),.rtc_start(pstate_rtc_start),.rtc_restore(pstate_rtc_restore),.rtc_word_write(pstate_rtc_write),
        .rtc_word_index(pstate_rtc_index),.rtc_word_data(pstate_rtc_wdata),.rtc_ready(pstate_rtc_ready),
        .rtc_done(pstate_rtc_done),.rtc_error(pstate_rtc_error),.rtc_word_rdata(pstate_rtc_rdata),
        .host_valid(pstate_host_valid),.host_write(pstate_host_write),.host_response_ready(pstate_host_consume),
        .host_offset(pstate_host_offset),.host_wdata(pstate_host_wdata),.host_ready(pstate_host_ready),
        .host_response(pstate_host_response),.host_error(pstate_host_error),.host_rdata(pstate_host_rdata),
        .memory_valid(pstate_memory_valid),.memory_write(pstate_memory_write),.memory_response_ready(pstate_memory_consume),
        .memory_addr(pstate_memory_addr),.memory_wdata(pstate_memory_wdata),.memory_byteena(pstate_memory_byteena),
        .memory_ready(pstate_memory_ready),.memory_response(pstate_memory_response),.memory_rdata(pstate_memory_rdata));
`else
    // Keep unsupported state commands deterministic until the complete
    // serializer and restore path have passed their release gates.
    assign savestate_supported=1'b0;
    assign savestate_addr=32'd0;
    assign savestate_size=32'd0;
    assign savestate_maxloadsize=32'd0;
    assign {savestate_start_ack,savestate_start_busy,savestate_start_ok,savestate_start_err}=4'd0;
    assign {savestate_load_ack,savestate_load_busy,savestate_load_ok,savestate_load_err}=4'd0;
`endif
    
    wire            osnotify_inmenu;

// bridge target commands
// synchronous to clk_74a

    reg             target_dataslot_read;       
    reg             target_dataslot_write;
    reg             target_dataslot_getfile;    // require additional param/resp structs to be mapped
    reg             target_dataslot_openfile;   // require additional param/resp structs to be mapped
    
    wire            target_dataslot_ack;        
    wire            target_dataslot_done;
    wire    [2:0]   target_dataslot_err;

    reg     [15:0]  target_dataslot_id;
    reg     [31:0]  target_dataslot_slotoffset;
    reg     [31:0]  target_dataslot_bridgeaddr;
    reg     [31:0]  target_dataslot_length;

// Load the Game Pak data slot into the cartridge window exposed to the GBA
// system. The APF host performs the actual transfer after this request and
// presents the words back as bridge writes at 0x08000000.
always @(posedge clk_74a or negedge reset_n) begin
    if (!reset_n) begin
        target_dataslot_read <= 1'b0;
        target_dataslot_id <= 16'd0;
        target_dataslot_slotoffset <= 32'd0;
        target_dataslot_bridgeaddr <= 32'h08000000;
        target_dataslot_length <= 32'd0;
    end else begin
        target_dataslot_read <= 1'b0;
        if (dataslot_update && dataslot_update_id == 16'd0) begin
            target_dataslot_read <= 1'b1;
            target_dataslot_id <= 16'd0;
            target_dataslot_slotoffset <= 32'd0;
            target_dataslot_bridgeaddr <= 32'h08000000;
            target_dataslot_length <= dataslot_update_size;
        end
    end
end
    
    wire    [31:0]  target_buffer_param_struct; // to be mapped/implemented when using some Target commands
    wire    [31:0]  target_buffer_resp_struct;  // to be mapped/implemented when using some Target commands
    
// bridge data slot access
// synchronous to clk_74a

    // Slot index 1, word 1: export the complete two-bank Flash array,
    // including when no save existed at startup or a shorter file was loaded.
    // Standard SRAM libraries select 32 KiB; Flash retains the 128 KiB image.
`ifdef GBK_PLAYTIME
    wire [9:0] datatable_addr;
    wire [31:0] datatable_data;
    wire datatable_wren;
    gba_save_datatable #(.RTC_PERSISTENCE(GBA_RTC_PERSISTENCE)) save_datatable(
        .clk(clk_74a),.running(reset_n),
        .host_access(bridge_addr[31:24]==8'hf8 && bridge_addr[15:12]==4'h2),
        .save_size(gba_save_export_size),
        .address(datatable_addr),.data(datatable_data),.write_enable(datatable_wren));
`else
    wire [9:0] datatable_addr=10'd3;
    wire datatable_wren=reset_n;
`endif
    wire [31:0] gba_save_export_size=GBA_EEPROM && gba_save_eeprom ?
        (gba_eeprom_large_s ? 32'd8192 : 32'd512) : gba_save_sram ? 32'd32768 : 32'd131072;
`ifndef GBK_PLAYTIME
    wire [31:0] datatable_data=gba_save_export_size;
`endif
    wire    [31:0]  datatable_q;

// Bound a BOOTING status request to 10 ms on the direct 74.25 MHz clock.
// Normal cold SRAM fill takes about 11.5 ms. Host polling must not depend on
// debug-log I/O providing that delay; readiness and slot grants stay guarded.
core_bridge_cmd #(.BOOT_DIAGNOSTIC(GBA_BOOT_DIAGNOSTIC),.BOOT_DIAGNOSTIC_POLLS(GBA_BOOT_DIAGNOSTIC_POLLS),
`ifdef GBK_POCKET_STATE
    .STATE_LIFECYCLE(1),
`endif
    .BOOT_STATUS_WAIT_CYCLES(742500)) icb (

    .clk                ( clk_74a ),
    .reset_n            ( reset_n ),
`ifdef GBK_POCKET_STATE
    .state_reset_request(pstate_reset_request),.state_reset_ready(pstate_reset_ready),.state_transfer_allowed(pstate_transfer_allowed),
`endif

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),
    
    .status_boot_done       ( status_boot_done ),
    .boot_diagnostic_signals( boot_diagnostic_signals ),
    .debug_event_valid(gba_log_valid),
    .debug_event_data(gba_log_data),
    .debug_event_ready(gba_log_ready),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),
    
    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),
    .rtc_update_toggle      ( rtc_update_toggle ),
    
    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),
    
    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_getfile    ( target_dataslot_getfile ),
    .target_dataslot_openfile   ( target_dataslot_openfile ),
    
    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .target_buffer_param_struct ( target_buffer_param_struct ),
    .target_buffer_resp_struct  ( target_buffer_resp_struct ),
    
    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )

);



////////////////////////////////////////////////////////////////////////////////////////



// video generation
// ~12,288,000 hz pixel clock
//
// Keep the established 12.288 MHz transport clock and its 90-degree phase.
// The PPU derives native GBA dots with a fractional enable. The registered
// APF output stage aligns pixel acceptance with RGB and emits sync events.


assign video_rgb_clock = clk_core_12288;
assign video_rgb_clock_90 = clk_core_12288_90deg;
wire [23:0] gba_video_rgb_raw;
wire [351:0] gba_restart_context;
wire gba_restart_valid;
`ifdef GBK_DIAGNOSTIC
`ifdef GBK_DEEP_DIAGNOSTIC
reg [31:0] gba_diag_pc_frame;
reg [31:0] gba_diag_bias_count_frame;
reg [31:0] gba_diag_bias_r12_frame;
reg [31:0] gba_diag_r2_frame;
reg [31:0] gba_diag_add_instr_frame;
reg [31:0] gba_diag_add_result_frame;
reg [31:0] gba_diag_add_result_display;
reg [15:0] gba_diag_sound_bias_frame;
reg [15:0] gba_diag_sound_count_frame;
reg [15:0] gba_diag_status_capture;
reg [31:0] gba_diag_window_capture;
reg [15:0] gba_diag_logo_reads;
reg [31:0] gba_diag_logo_word;
reg [31:0] gba_diag_logo_last_word;
reg [31:0] gba_diag_logo_load_word;
reg [31:0] gba_diag_logo_load_sync1, gba_diag_logo_load_sync2;
reg [31:0] gba_diag_io_read_trace_frame;
reg [31:0] gba_diag_io_write_trace_frame;
reg        gba_diag_bg3_map_seen;
reg        gba_diag_bg3_tile_seen;
reg        gba_diag_window_seen;
reg        gba_diag_vs_d;
reg        gba_diag_frozen;
wire       gba_diag_capture = gba_video_vs && !gba_diag_vs_d && !gba_diag_frozen;

reg [31:0] gba_log_previous_boot_counts;
reg gba_restart_valid_previous;
always @(posedge clk_core_39936) begin
    if (!reset_n) begin gba_log_previous_boot_counts <= 0; gba_restart_valid_previous <= 0; end
    else begin gba_log_previous_boot_counts <= gba_boot_counts; gba_restart_valid_previous <= gba_restart_valid; end
end
wire [351:0] gba_bios_wait_snapshot;
gba_bios_wait_trace bios_wait_trace (
    .clk(clk_core_39936), .reset(~reset_n),
    .execution_state(gba_debug_execution_state), .restart_context(gba_restart_context),
    .loaded_logo_word(gba_diag_logo_load_sync2),
    .irq_counts(gba_debug_irq_counts),
    .cartridge_logo_word(gba_diag_logo_last_word), .snapshot(gba_bios_wait_snapshot)
);
wire [351:0] gba_game_video_snapshot;
// The fade now completes on hardware. Capture the DMA owner and addresses
// at the later intro stall, without issuing any diagnostic memory accesses.
assign gba_game_video_snapshot = {
    gba_debug_execution_state[95:64],
    gba_restart_context[351:288],
    gba_debug_irq_counts,
    gba_debug_runtime_memory[63:0],
    gba_debug_dma_status, gba_debug_dma_destination, gba_debug_dma_source,
    gba_debug_ppu_bg0cnt, gba_debug_ppu_dispcnt,
    gba_debug_execution_state[191:160]
};
gba_runtime_log #(.PERIOD_CYCLES(39936000),.DIAGNOSTIC_SAMPLES(1),.DIAGNOSTIC_KIND(16'h4750),.MAX_SNAPSHOTS(48), .SNAPSHOT_KIND(16'h474d)) runtime_log (
    .sample_clk(clk_core_39936), .bridge_clk(clk_74a),
    .reset(!pll_core_locked_s), .core_running(reset_n),
    .capture_now(gba_boot_counts != gba_log_previous_boot_counts),
    .capture_restart(gba_restart_valid && !gba_restart_valid_previous),
    .restart_snapshot(gba_restart_context),
    .diagnostic_snapshot({gba_cycle_profile,gba_debug_pc,32'd39936000}), .snapshot(gba_game_video_snapshot),
    .event_valid(gba_log_valid), .event_data(gba_log_data),
    .event_ready(gba_log_ready)
);
wire [31:0] gba_boot_counts, gba_boot_last_cart_pc, gba_boot_reset_from_pc;
gba_boot_trace boot_trace (
    .clk(clk_core_39936), .reset(~reset_n), .pc(gba_debug_pc),
    .entry_counts(gba_boot_counts), .last_cart_pc(gba_boot_last_cart_pc),
    .reset_from_pc(gba_boot_reset_from_pc)
);
reg [8:0]  gba_diag_x;
reg [9:0]  gba_diag_y;

function [34:0] gba_diag_hex_glyph;
    input [3:0] digit;
    begin
        case (digit)
            4'h0: gba_diag_hex_glyph = {5'b11111,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b11111};
            4'h1: gba_diag_hex_glyph = {5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
            4'h2: gba_diag_hex_glyph = {5'b11110,5'b00001,5'b00001,5'b11110,5'b10000,5'b10000,5'b11111};
            4'h3: gba_diag_hex_glyph = {5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
            4'h4: gba_diag_hex_glyph = {5'b10010,5'b10010,5'b10010,5'b11111,5'b00010,5'b00010,5'b00010};
            4'h5: gba_diag_hex_glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
            4'h6: gba_diag_hex_glyph = {5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
            4'h7: gba_diag_hex_glyph = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
            4'h8: gba_diag_hex_glyph = {5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
            4'h9: gba_diag_hex_glyph = {5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
            4'hA: gba_diag_hex_glyph = {5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
            4'hB: gba_diag_hex_glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
            4'hC: gba_diag_hex_glyph = {5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
            4'hD: gba_diag_hex_glyph = {5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
            4'hE: gba_diag_hex_glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
            default: gba_diag_hex_glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
        endcase
    end
endfunction

// Record APF's incoming header even while the emulated CPU is in reset.
always @(posedge clk_74a) begin
    if (!pll_core_locked_s)
        gba_diag_logo_load_word <= 32'b0;
    else if (gba_cart_load_write && gba_cart_load_addr == 22'd1)
        gba_diag_logo_load_word <= gba_load_wdata;
end

always @(posedge clk_core_12288) begin
    if (!reset_n) begin
        gba_diag_pc_frame <= 32'b0;
        gba_diag_bias_count_frame <= 32'b0;
        gba_diag_bias_r12_frame <= 32'b0;
        gba_diag_r2_frame <= 32'b0;
        gba_diag_add_instr_frame <= 32'b0;
        gba_diag_add_result_frame <= 32'b0;
        gba_diag_add_result_display <= 32'b0;
        gba_diag_sound_bias_frame <= 16'b0;
        gba_diag_sound_count_frame <= 16'b0;
        gba_diag_status_capture <= 16'b0;
        gba_diag_window_capture <= 32'b0;
        gba_diag_logo_reads <= 16'b0;
        gba_diag_logo_word <= 32'b0;
        gba_diag_logo_last_word <= 32'b0;
        gba_diag_logo_load_sync1 <= 32'b0;
        gba_diag_logo_load_sync2 <= 32'b0;
        gba_diag_io_read_trace_frame <= 32'b0;
        gba_diag_io_write_trace_frame <= 32'b0;
        gba_diag_bg3_map_seen <= 1'b0;
        gba_diag_bg3_tile_seen <= 1'b0;
        gba_diag_window_seen <= 1'b0;
        gba_diag_vs_d <= 1'b0;
        gba_diag_frozen <= 1'b0;
        gba_diag_x <= 9'd0;
        gba_diag_y <= 10'd0;
    end else begin
        gba_diag_logo_load_sync1 <= gba_diag_logo_load_word;
        gba_diag_logo_load_sync2 <= gba_diag_logo_load_sync1;
        gba_diag_vs_d <= gba_video_vs;
        if (!cont1_key[14]) gba_diag_frozen <= 1'b0;
        else if (gba_diag_capture) gba_diag_frozen <= 1'b1;
        if (gba_diag_capture)
            // Latest executed instruction, frozen together with its operands
            // on the first video boundary while Select is held.
            gba_diag_pc_frame <= gba_debug_execution_state[191:160];
        // The first Nintendo logo header word is identical in licensed GBA
        // ROMs. Capture the CPU-visible cartridge response at offset 4 so
        // rows 5 and 6 can distinguish a bad Game Pak read from rendering.
        if (gba_cart_ready && gba_cart_addr[23:2] == 22'd1) begin
            gba_diag_logo_last_word <= gba_cart_rdata;
            if (gba_diag_logo_reads == 16'd0)
                gba_diag_logo_word <= gba_cart_rdata;
            if (gba_diag_logo_reads != 16'hffff)
                gba_diag_logo_reads <= gba_diag_logo_reads + 16'd1;
        end
        if (gba_diag_capture) begin
            // Rows 3/4/5/7/8: CPSR low half, R0, instruction, R1, R2.
            // All operands were sampled at that instruction's execution.
            gba_diag_bias_r12_frame <= gba_debug_execution_state[159:128];
            gba_diag_sound_count_frame <= {gba_debug_execution_state[127:124],
                                           gba_debug_execution_state[107:96]};
            // Row 6: reset-vector transitions / cartridge boot entries.
            gba_diag_r2_frame <= gba_boot_counts;
        end
        if (gba_diag_capture) begin
            // Last executed instruction's R1/R2 operands.
            gba_diag_add_instr_frame <= gba_debug_execution_state[63:32];
            // Frame-latch values so hexadecimal glyphs cannot tear.
            gba_diag_add_result_display <= gba_debug_execution_state[31:0];
            gba_diag_add_result_frame <= 32'b0;
            gba_diag_bg3_map_seen <= 1'b0;
            gba_diag_bg3_tile_seen <= 1'b0;
            gba_diag_window_seen <= 1'b0;
            gba_diag_sound_bias_frame[7:0] <=
                gba_diag_sound_bias_frame[7:0] | gba_diag_status_capture[7:0];
            if (gba_diag_sound_bias_frame[15:8] == 8'b0 &&
                gba_diag_status_capture[15:8] != 8'b0)
                gba_diag_sound_bias_frame[15:8] <= gba_diag_status_capture[15:8];
            gba_diag_status_capture <= 16'b0;
            gba_diag_io_write_trace_frame <= gba_debug_execution_state[95:64];
            gba_diag_window_capture <= 32'b0;
        end else if (gba_video_de) begin
            gba_diag_status_capture[7:0] <=
                gba_diag_status_capture[7:0] | gba_debug_mode2_status[7:0];
            if (gba_diag_status_capture[15:8] == 8'b0 &&
                gba_debug_mode2_status[15:8] != 8'b0)
                gba_diag_status_capture[15:8] <= gba_debug_mode2_status[15:8];
            if (!gba_diag_window_seen && gba_debug_mode2_status[0]) begin
                gba_diag_window_capture <= gba_debug_mode2_window;
                if (gba_debug_mode2_window[15:0] != 16'b0)
                    gba_diag_window_seen <= 1'b1;
            end
            if (!gba_diag_bg3_tile_seen && gba_debug_bg3_tile[31:16] != 16'b0) begin
                gba_diag_add_result_frame <= gba_debug_bg3_tile;
                if (gba_debug_bg3_tile[15:0] != 16'b0)
                    gba_diag_bg3_tile_seen <= 1'b1;
            end
        end
        if (gba_diag_capture)
            gba_diag_bias_count_frame <= {16'b0, gba_debug_ppu_dispcnt};
        if (gba_video_vs && !gba_diag_vs_d) begin
            gba_diag_io_read_trace_frame <= gba_debug_io_read_trace;
        end
        if (!cont1_key[14])
            gba_diag_sound_bias_frame <= 16'b0;
        if (gba_diag_x == 9'd319) begin
            gba_diag_x <= 9'd0;
            if (gba_diag_y == 10'd639)
                gba_diag_y <= 10'd0;
            else
                gba_diag_y <= gba_diag_y + 1'b1;
        end else begin
            gba_diag_x <= gba_diag_x + 1'b1;
        end
    end
end
wire [7:0] gba_diag_region = gba_diag_pc_frame[31:24];
wire [3:0] gba_diag_bios_page = gba_diag_pc_frame[11:8];
// BIOS pages are deliberately distinct so a solid color identifies the
// failing control-flow window instead of collapsing the entire BIOS to red.
wire [23:0] gba_diag_bios_rgb =
    (gba_diag_bios_page == 4'h0) ? 24'hff2020 : // 000-0ff
    (gba_diag_bios_page == 4'h1) ? 24'hff8020 : // 100-1ff
    (gba_diag_bios_page == 4'h2) ? 24'hffff20 : // 200-2ff
    (gba_diag_bios_page == 4'h3) ? 24'h80ff20 : // 300-3ff
    (gba_diag_bios_page == 4'h4) ? 24'h20ff20 : // 400-4ff
    (gba_diag_bios_page == 4'h5) ? 24'h20ffff : // 500-5ff
    (gba_diag_bios_page == 4'h6) ? 24'h2080ff : // 600-6ff
    (gba_diag_bios_page == 4'h7) ? 24'h2020ff : // 700-7ff
    (gba_diag_bios_page == 4'h8) ? 24'h8020ff : // 800-8ff
    (gba_diag_bios_page == 4'h9) ? 24'hff20ff : // 900-9ff
    (gba_diag_bios_page == 4'ha) ? 24'hff2080 : // a00-aff
    (gba_diag_bios_page == 4'hb) ? 24'hff2040 : // b00-bff
    (gba_diag_bios_page == 4'hc) ? 24'hffffff : // c00-cff
    (gba_diag_bios_page == 4'hd) ? 24'hb0b0b0 : // d00-dff
    (gba_diag_bios_page == 4'he) ? 24'h20c0c0 : // e00-eff
    24'h101010;                                // f00-fff
wire [23:0] gba_diag_rgb =
    (gba_diag_region == 8'h00) ? gba_diag_bios_rgb :
    ((gba_diag_region >= 8'h08) && (gba_diag_region <= 8'h0d)) ? 24'h20ffff : // cartridge ROM
    (gba_diag_region == 8'h02) ? 24'h2080ff : // EWRAM
    (gba_diag_region == 8'h03) ? 24'h20ff40 : // IWRAM
    (gba_diag_region == 8'h04) ? 24'hffff20 : // IO
    (gba_diag_region == 8'h06) ? 24'hff20c0 : // VRAM
    24'hffffff;
wire gba_diag_text_active = gba_video_de &&
                            (gba_diag_x >= 9'd48) && (gba_diag_x < 9'd192) &&
                            (gba_diag_y >= 10'd2) && (gba_diag_y < 10'd18);
wire [8:0] gba_diag_text_x = gba_diag_x - 9'd48;
wire [3:0] gba_diag_char = gba_diag_text_x / 18;
wire [3:0] gba_diag_col = (gba_diag_text_x % 18) / 3;
wire [2:0] gba_diag_row = (gba_diag_y - 10'd2) / 2;
wire [3:0] gba_diag_digit =
    (gba_diag_char == 4'd0) ? gba_diag_pc_frame[31:28] :
    (gba_diag_char == 4'd1) ? gba_diag_pc_frame[27:24] :
    (gba_diag_char == 4'd2) ? gba_diag_pc_frame[23:20] :
    (gba_diag_char == 4'd3) ? gba_diag_pc_frame[19:16] :
    (gba_diag_char == 4'd4) ? gba_diag_pc_frame[15:12] :
    (gba_diag_char == 4'd5) ? gba_diag_pc_frame[11:8] :
    (gba_diag_char == 4'd6) ? gba_diag_pc_frame[7:4] :
                               gba_diag_pc_frame[3:0];
wire [34:0] gba_diag_glyph = gba_diag_hex_glyph(gba_diag_digit);
wire gba_diag_text_pixel = gba_diag_text_active &&
                           (gba_diag_col < 5) &&
                           gba_diag_glyph[34 - ((gba_diag_row * 5) + gba_diag_col)];
wire gba_diag_bias_active = gba_video_de &&
                            (gba_diag_x >= 9'd48) && (gba_diag_x < 9'd192) &&
                            (gba_diag_y >= 10'd20) && (gba_diag_y < 10'd36);
wire [8:0] gba_diag_bias_x = gba_diag_x - 9'd48;
wire [3:0] gba_diag_bias_char = gba_diag_bias_x / 18;
wire [3:0] gba_diag_bias_col = (gba_diag_bias_x % 18) / 3;
wire [2:0] gba_diag_bias_row = (gba_diag_y - 10'd20) / 2;
wire [3:0] gba_diag_bias_digit =
    (gba_diag_bias_char == 4'd0) ? gba_diag_bias_count_frame[31:28] :
    (gba_diag_bias_char == 4'd1) ? gba_diag_bias_count_frame[27:24] :
    (gba_diag_bias_char == 4'd2) ? gba_diag_bias_count_frame[23:20] :
    (gba_diag_bias_char == 4'd3) ? gba_diag_bias_count_frame[19:16] :
    (gba_diag_bias_char == 4'd4) ? gba_diag_bias_count_frame[15:12] :
    (gba_diag_bias_char == 4'd5) ? gba_diag_bias_count_frame[11:8] :
    (gba_diag_bias_char == 4'd6) ? gba_diag_bias_count_frame[7:4] :
                                   gba_diag_bias_count_frame[3:0];
wire [34:0] gba_diag_bias_glyph = gba_diag_hex_glyph(gba_diag_bias_digit);
wire gba_diag_bias_pixel = gba_diag_bias_active &&
                           (gba_diag_bias_col < 5) &&
                           gba_diag_bias_glyph[34 - ((gba_diag_bias_row * 5) + gba_diag_bias_col)];

// Four visible hex digits for the actual SOUNDBIAS register.  This is
// separate from the write counter so a BIOS ramp can be distinguished from
// a CPU that is merely repeating the same store.
wire gba_diag_sound_active = gba_video_de &&
                             (gba_diag_x >= 9'd84) && (gba_diag_x < 9'd156) &&
                             (gba_diag_y >= 10'd38) && (gba_diag_y < 10'd54);
wire [8:0] gba_diag_sound_x = gba_diag_x - 9'd84;
wire [3:0] gba_diag_sound_char = gba_diag_sound_x / 18;
wire [3:0] gba_diag_sound_col = (gba_diag_sound_x % 18) / 3;
wire [2:0] gba_diag_sound_row = (gba_diag_y - 10'd38) / 2;
wire [3:0] gba_diag_sound_digit =
    (gba_diag_sound_char == 4'd0) ? gba_diag_sound_count_frame[15:12] :
    (gba_diag_sound_char == 4'd1) ? gba_diag_sound_count_frame[11:8] :
    (gba_diag_sound_char == 4'd2) ? gba_diag_sound_count_frame[7:4] :
                                    gba_diag_sound_count_frame[3:0];
wire [34:0] gba_diag_sound_glyph = gba_diag_hex_glyph(gba_diag_sound_digit);
wire gba_diag_sound_pixel = gba_diag_sound_active &&
                            (gba_diag_sound_col < 5) &&
                            gba_diag_sound_glyph[34 - ((gba_diag_sound_row * 5) + gba_diag_sound_col)];
wire gba_diag_io_active = gba_video_de &&
                          (gba_diag_x >= 9'd48) && (gba_diag_x < 9'd192) &&
                          (gba_diag_y >= 10'd56) && (gba_diag_y < 10'd72);
wire [8:0] gba_diag_io_x = gba_diag_x - 9'd48;
wire [3:0] gba_diag_io_char = gba_diag_io_x / 18;
wire [3:0] gba_diag_io_col = (gba_diag_io_x % 18) / 3;
wire [2:0] gba_diag_io_row = (gba_diag_y - 10'd56) / 2;
wire [31:0] gba_diag_io_frame = gba_diag_io_write_trace_frame;
wire [3:0] gba_diag_io_digit =
    (gba_diag_io_char == 4'd0) ? gba_diag_io_frame[31:28] :
    (gba_diag_io_char == 4'd1) ? gba_diag_io_frame[27:24] :
    (gba_diag_io_char == 4'd2) ? gba_diag_io_frame[23:20] :
    (gba_diag_io_char == 4'd3) ? gba_diag_io_frame[19:16] :
    (gba_diag_io_char == 4'd4) ? gba_diag_io_frame[15:12] :
    (gba_diag_io_char == 4'd5) ? gba_diag_io_frame[11:8] :
    (gba_diag_io_char == 4'd6) ? gba_diag_io_frame[7:4] :
                                gba_diag_io_frame[3:0];
wire [34:0] gba_diag_io_glyph = gba_diag_hex_glyph(gba_diag_io_digit);
wire gba_diag_io_pixel = gba_diag_io_active &&
                          (gba_diag_io_col < 5) &&
                          gba_diag_io_glyph[34 - ((gba_diag_io_row * 5) + gba_diag_io_col)];
wire gba_diag_instr_active = gba_video_de &&
                             (gba_diag_x >= 9'd48) && (gba_diag_x < 9'd192) &&
                             (gba_diag_y >= 10'd74) && (gba_diag_y < 10'd90);
wire [8:0] gba_diag_instr_x = gba_diag_x - 9'd48;
wire [3:0] gba_diag_instr_char = gba_diag_instr_x / 18;
wire [3:0] gba_diag_instr_col = (gba_diag_instr_x % 18) / 3;
wire [2:0] gba_diag_instr_row = (gba_diag_y - 10'd74) / 2;
wire [3:0] gba_diag_instr_digit =
    (gba_diag_instr_char == 4'd0) ? gba_diag_bias_r12_frame[31:28] :
    (gba_diag_instr_char == 4'd1) ? gba_diag_bias_r12_frame[27:24] :
    (gba_diag_instr_char == 4'd2) ? gba_diag_bias_r12_frame[23:20] :
    (gba_diag_instr_char == 4'd3) ? gba_diag_bias_r12_frame[19:16] :
    (gba_diag_instr_char == 4'd4) ? gba_diag_bias_r12_frame[15:12] :
    (gba_diag_instr_char == 4'd5) ? gba_diag_bias_r12_frame[11:8] :
    (gba_diag_instr_char == 4'd6) ? gba_diag_bias_r12_frame[7:4] :
                                    gba_diag_bias_r12_frame[3:0];
wire [34:0] gba_diag_instr_glyph = gba_diag_hex_glyph(gba_diag_instr_digit);
wire gba_diag_instr_pixel = gba_diag_instr_active &&
                            (gba_diag_instr_col < 5) &&
                            gba_diag_instr_glyph[34 - ((gba_diag_instr_row * 5) + gba_diag_instr_col)];
wire gba_diag_r1_active = gba_video_de &&
                          (gba_diag_x >= 9'd48) && (gba_diag_x < 9'd192) &&
                          (gba_diag_y >= 10'd92) && (gba_diag_y < 10'd108);
wire [8:0] gba_diag_r1_x = gba_diag_x - 9'd48;
wire [3:0] gba_diag_r1_char = gba_diag_r1_x / 18;
wire [3:0] gba_diag_r1_col = (gba_diag_r1_x % 18) / 3;
wire [2:0] gba_diag_r1_row = (gba_diag_y - 10'd92) / 2;
wire [3:0] gba_diag_r1_digit =
    (gba_diag_r1_char == 4'd0) ? gba_diag_r2_frame[31:28] :
    (gba_diag_r1_char == 4'd1) ? gba_diag_r2_frame[27:24] :
    (gba_diag_r1_char == 4'd2) ? gba_diag_r2_frame[23:20] :
    (gba_diag_r1_char == 4'd3) ? gba_diag_r2_frame[19:16] :
    (gba_diag_r1_char == 4'd4) ? gba_diag_r2_frame[15:12] :
    (gba_diag_r1_char == 4'd5) ? gba_diag_r2_frame[11:8] :
    (gba_diag_r1_char == 4'd6) ? gba_diag_r2_frame[7:4] :
                                 gba_diag_r2_frame[3:0];
wire [34:0] gba_diag_r1_glyph = gba_diag_hex_glyph(gba_diag_r1_digit);
wire gba_diag_r1_pixel = gba_diag_r1_active &&
                         (gba_diag_r1_col < 5) &&
                         gba_diag_r1_glyph[34 - ((gba_diag_r1_row * 5) + gba_diag_r1_col)];
wire gba_diag_add_instr_active = gba_video_de &&
                                 (gba_diag_x >= 9'd48) && (gba_diag_x < 9'd192) &&
                                 (gba_diag_y >= 10'd110) && (gba_diag_y < 10'd126);
wire [8:0] gba_diag_add_instr_x = gba_diag_x - 9'd48;
wire [3:0] gba_diag_add_instr_char = gba_diag_add_instr_x / 18;
wire [3:0] gba_diag_add_instr_col = (gba_diag_add_instr_x % 18) / 3;
wire [2:0] gba_diag_add_instr_row = (gba_diag_y - 10'd110) / 2;
wire [3:0] gba_diag_add_instr_digit =
    (gba_diag_add_instr_char == 4'd0) ? gba_diag_add_instr_frame[31:28] :
    (gba_diag_add_instr_char == 4'd1) ? gba_diag_add_instr_frame[27:24] :
    (gba_diag_add_instr_char == 4'd2) ? gba_diag_add_instr_frame[23:20] :
    (gba_diag_add_instr_char == 4'd3) ? gba_diag_add_instr_frame[19:16] :
    (gba_diag_add_instr_char == 4'd4) ? gba_diag_add_instr_frame[15:12] :
    (gba_diag_add_instr_char == 4'd5) ? gba_diag_add_instr_frame[11:8] :
    (gba_diag_add_instr_char == 4'd6) ? gba_diag_add_instr_frame[7:4] :
                                        gba_diag_add_instr_frame[3:0];
wire [34:0] gba_diag_add_instr_glyph = gba_diag_hex_glyph(gba_diag_add_instr_digit);
wire gba_diag_add_instr_pixel = gba_diag_add_instr_active &&
                                 (gba_diag_add_instr_col < 5) &&
                                 gba_diag_add_instr_glyph[34 - ((gba_diag_add_instr_row * 5) + gba_diag_add_instr_col)];
wire gba_diag_add_result_active = gba_video_de &&
                                  (gba_diag_x >= 9'd48) && (gba_diag_x < 9'd192) &&
                                  (gba_diag_y >= 10'd128) && (gba_diag_y < 10'd144);
wire [8:0] gba_diag_add_result_x = gba_diag_x - 9'd48;
wire [3:0] gba_diag_add_result_char = gba_diag_add_result_x / 18;
wire [3:0] gba_diag_add_result_col = (gba_diag_add_result_x % 18) / 3;
wire [2:0] gba_diag_add_result_row = (gba_diag_y - 10'd128) / 2;
wire [3:0] gba_diag_add_result_digit =
    (gba_diag_add_result_char == 4'd0) ? gba_diag_add_result_display[31:28] :
    (gba_diag_add_result_char == 4'd1) ? gba_diag_add_result_display[27:24] :
    (gba_diag_add_result_char == 4'd2) ? gba_diag_add_result_display[23:20] :
    (gba_diag_add_result_char == 4'd3) ? gba_diag_add_result_display[19:16] :
    (gba_diag_add_result_char == 4'd4) ? gba_diag_add_result_display[15:12] :
    (gba_diag_add_result_char == 4'd5) ? gba_diag_add_result_display[11:8] :
    (gba_diag_add_result_char == 4'd6) ? gba_diag_add_result_display[7:4] :
                                         gba_diag_add_result_display[3:0];
wire [34:0] gba_diag_add_result_glyph = gba_diag_hex_glyph(gba_diag_add_result_digit);
wire gba_diag_add_result_pixel = gba_diag_add_result_active &&
                                  (gba_diag_add_result_col < 5) &&
                                  gba_diag_add_result_glyph[34 - ((gba_diag_add_result_row * 5) + gba_diag_add_result_col)];
wire [23:0] gba_diag_text_rgb = 24'hffffff;
// The legacy screen overlay retains many CPU probes in addition to its glyph
// logic. Keep it opt-in so the gameplay renderer can use that FPGA capacity;
// the passive runtime-event logger above remains enabled independently.
`ifdef GBK_DIAGNOSTIC_OVERLAY
assign gba_video_rgb_raw = cont1_key[14] && gba_video_de ? ((gba_diag_text_pixel || gba_diag_bias_pixel || gba_diag_sound_pixel || gba_diag_io_pixel ||
                                    gba_diag_instr_pixel || gba_diag_r1_pixel || gba_diag_add_instr_pixel ||
                                    gba_diag_add_result_pixel) ? gba_diag_text_rgb : 24'h000000) :
                                    {gba_video_r[8:1], gba_video_g[8:1], gba_video_b[8:1]};
`else
assign gba_video_rgb_raw = {gba_video_r[8:1], gba_video_g[8:1], gba_video_b[8:1]};
`endif
`else
// Rotate regional/ROM/stall profiles at 125 ms, eight minutes of bounded
// capture. Each kind is sampled every 375 ms. Disconnect forensic
// consumers so synthesis can remove their upstream retained probes.
gba_runtime_log #(.PERIOD_CYCLES(4992000), .MAX_SNAPSHOTS(3840),
    .CAPTURE_EVENTS(0), .SNAPSHOT_KIND(16'h4751),
    .DIAGNOSTIC_SAMPLES(1), .DIAGNOSTIC_KIND(16'h4752),.EXTRA_SAMPLES(1)) runtime_log (
    .sample_clk(clk_core_39936), .bridge_clk(clk_74a),
    .reset(!pll_core_locked_s), .core_running(reset_n),
    .capture_now(1'b0), .capture_restart(1'b0), .restart_snapshot(352'b0),
    .diagnostic_snapshot({gba_rom_profile,gba_cycle_profile[287:256]}),
    .extra_snapshot({gba_stall_profile,gba_cycle_profile[287:256]}),
    .snapshot({gba_cycle_profile,gba_debug_pc,32'd39936000}),
    .event_valid(gba_log_valid), .event_data(gba_log_data),
    .event_ready(gba_log_ready)
);
assign gba_video_rgb_raw = {gba_video_r[8:1], gba_video_g[8:1], gba_video_b[8:1]};
`endif
`else
assign gba_video_rgb_raw = {gba_video_r[8:1], gba_video_g[8:1], gba_video_b[8:1]};
`endif
wire [23:0] gba_apf_rgb;
wire gba_apf_de,gba_apf_skip,gba_apf_hs,gba_apf_vs;
gba_apf_video_out video_output (
    .clk(clk_core_12288), .reset(~reset_n),
    .rgb_in(gba_video_rgb_raw),
    .de_in(gba_video_de), .skip_in(gba_video_skip),
    .hs_region(gba_video_hs), .vs_region(gba_video_vs),
    .rgb(gba_apf_rgb), .de(gba_apf_de), .skip(gba_apf_skip), .hs(gba_apf_hs), .vs(gba_apf_vs)
);
wire gba_guest_stopped;
`ifdef GBK_RTC_PERSISTENCE
localparam GBA_RTC_PERSISTENCE=1;
`else
localparam GBA_RTC_PERSISTENCE=0;
`endif
wire gba_rtc_request,gba_rtc_acknowledge,gba_rtc_boot_ready;
wire [1:0] gba_rtc_operation;
wire [97:0] gba_rtc_payload,gba_rtc_reply;
`ifndef GBK_PLAYTIME
assign gba_rtc_request=0;assign gba_rtc_operation=0;assign gba_rtc_payload=0;assign gba_rtc_boot_ready=1;
`endif
`ifdef GBK_PLAYTIME
wire [31:0] gba_playtime_rdata;
wire [2:0] gba_overlay_show;
wire [2:0] gba_overlay_corner;
wire gba_overlay_wall_valid;
wire [15:0] gba_overlay_wall;
wire [27:0] gba_overlay_session,gba_overlay_total;
gba_playtime_host #(.RTC_PERSISTENCE(GBA_RTC_PERSISTENCE)) playtime_host(.clk(clk_74a),.video_clk(clk_core_12288),.video_reset(~reset_n),
`ifdef GBK_SAVESTATE
`ifdef GBK_POCKET_STATE
    .state_rtc_lock(pstate_rtc_lock),.state_rtc_start(pstate_rtc_start),.state_rtc_restore(pstate_rtc_restore),.state_rtc_word_write(pstate_rtc_write),
    .state_rtc_word_index(pstate_rtc_index),.state_rtc_word_data(pstate_rtc_wdata),.state_rtc_word_rdata(pstate_rtc_rdata),
    .state_rtc_ready(pstate_rtc_ready),.state_rtc_busy(),.state_rtc_done(pstate_rtc_done),.state_rtc_error(pstate_rtc_error),
`else
    .state_rtc_lock(1'b0),.state_rtc_start(1'b0),.state_rtc_restore(1'b0),.state_rtc_word_write(1'b0),
    .state_rtc_word_index(2'd0),.state_rtc_word_data(32'd0),.state_rtc_word_rdata(),
    .state_rtc_ready(),.state_rtc_busy(),.state_rtc_done(),.state_rtc_error(),
`endif
`endif
    .running(reset_n),.in_menu(osnotify_inmenu),.guest_stopped(gba_guest_stopped),
    .bridge_wr(bridge_wr),.bridge_rd(bridge_rd),.endian_little(bridge_endian_little),
    .bridge_addr(bridge_addr),.bridge_wr_data(bridge_wr_data),
    .host_toggle(rtc_update_toggle),.host_valid(rtc_valid),.host_time_bcd(rtc_time_bcd),
    .host_date_bcd(rtc_date_bcd),.host_epoch(rtc_epoch_seconds),
    .rtc_request(gba_rtc_request),.rtc_operation(gba_rtc_operation),.rtc_payload(gba_rtc_payload),
    .rtc_acknowledge(gba_rtc_acknowledge),.rtc_reply(gba_rtc_reply),.rtc_boot_ready(gba_rtc_boot_ready),
    .request_read(dataslot_requestread),.request_id(dataslot_requestread_id),
    .allcomplete(dataslot_allcomplete),.stats_ack(gba_stats_ack),.bridge_rdata(gba_playtime_rdata),
    .video_show(gba_overlay_show),.video_corner(gba_overlay_corner),
    .video_wall_valid(gba_overlay_wall_valid),.video_wall(gba_overlay_wall),
    .video_session(gba_overlay_session),.video_total(gba_overlay_total));
gba_playtime_overlay playtime_overlay(.clk(clk_core_12288),.reset(~reset_n),
    .rgb_in(gba_apf_rgb),.de_in(gba_apf_de),.skip_in(gba_apf_skip),.hs_in(gba_apf_hs),.vs_in(gba_apf_vs),
    .show(gba_overlay_show),.corner(gba_overlay_corner),.wall_valid(gba_overlay_wall_valid),
    .wall_hhmm(gba_overlay_wall),.session_hhmm(gba_overlay_session),.total_hhmm(gba_overlay_total),
    .rgb(video_rgb),.de(video_de),.skip(video_skip),.hs(video_hs),.vs(video_vs));
`else
assign video_rgb=gba_apf_rgb;
assign video_de=gba_apf_de;
assign video_skip=gba_apf_skip;
assign video_hs=gba_apf_hs;
assign video_vs=gba_apf_vs;
`endif

wire [8:0] gba_video_r, gba_video_g, gba_video_b;
wire       gba_video_de, gba_video_hs, gba_video_vs, gba_video_skip;
wire [15:0] gba_debug_ppu_dispcnt;
wire [15:0] gba_debug_ppu_bg0cnt, gba_debug_ppu_bg1cnt;
wire [15:0] gba_debug_ppu_bg2cnt, gba_debug_ppu_bg3cnt;
wire [31:0] gba_debug_bg3_matrix, gba_debug_bg3_reference;
wire [31:0] gba_debug_dma_source, gba_debug_dma_destination, gba_debug_dma_status;
wire [31:0] gba_debug_bg3_map, gba_debug_bg3_tile;
wire [15:0] gba_debug_bg3_tile_raw;
wire [15:0] gba_debug_mode2_status;
wire [31:0] gba_debug_mode2_window;
wire [31:0] gba_debug_pc;
wire [31:0] gba_debug_cpsr;
wire [31:0] gba_debug_instr;
wire [31:0] gba_debug_r1;
wire [159:0] gba_debug_bios_sound_state;
wire [31:0] gba_debug_irq_counts;
wire [95:0] gba_debug_runtime_memory;
wire [191:0] gba_debug_execution_state;
wire [31:0] gba_debug_bias_pc;
wire [31:0] gba_debug_bias_instr;
wire [31:0] gba_debug_bias_r1;
wire [31:0] gba_debug_bias_r2;
wire [31:0] gba_debug_bias_r12;
wire [31:0] gba_debug_bias_count;
wire [15:0] gba_debug_sound_bias;
wire [31:0] gba_debug_irq_vector_write_data;
wire [15:0] gba_debug_irq_vector_write_status;
wire [31:0] gba_debug_irq_vector_snapshot_data;
wire [15:0] gba_debug_irq_vector_snapshot_status;
wire [31:0] gba_debug_io_trace;
wire [31:0] gba_debug_io_read_trace;
wire [31:0] gba_debug_io_write_trace;
wire [31:0] gba_debug_irq_handler_read_pc;
wire [31:0] gba_debug_irq_handler_read_data;
wire [31:0] gba_debug_irq_probe_r0;
wire [31:0] gba_debug_irq_probe_bus_addr;
wire [31:0] gba_debug_irq_probe_pending_addr;
wire [31:0] gba_debug_irq_probe_port_state;
wire [31:0] gba_debug_irq_probe_bus_data;
wire [31:0] gba_debug_irq_probe_ram_data;
wire [31:0] gba_debug_irq_probe_vector_write;
wire [15:0] gba_debug_irq_stage_flags;
wire [31:0] gba_debug_irq_12c_instr;
wire [31:0] gba_debug_irq_130_r0;
wire [31:0] gba_debug_irq_130_instr;
wire [31:0] gba_debug_irq_134_fetch_r0;
wire [31:0] gba_debug_bios_word_12c;
wire [31:0] gba_debug_first_irq_entry_lr;
wire [31:0] gba_debug_first_irq_return_lr;
wire [31:0] gba_debug_first_irq_push_lr_addr;
wire [31:0] gba_debug_first_irq_push_lr_data;
wire [31:0] gba_debug_second_irq_push_lr_addr;
wire [31:0] gba_debug_second_irq_push_lr_data;
wire [31:0] gba_debug_first_irq_pop_lr_addr;
wire [31:0] gba_debug_first_irq_pop_lr_data;
wire [31:0] gba_debug_first_irq_vector_lr;
wire [31:0] gba_debug_first_irq_prologue_lr;
wire [15:0] gba_debug_first_irq_stack_passes;
wire [31:0] gba_debug_first_irq_progress;
wire [31:0] gba_debug_first_irq_last_pc;
wire [31:0] gba_debug_first_irq_134_instr;
wire [15:0] gba_debug_first_irq_load_state;
wire [31:0] gba_debug_first_irq_load_data;
wire [15:0] gba_debug_first_irq_load_target;
wire [31:0] gba_debug_bad_source_pc;
wire [31:0] gba_debug_bad_source_instr;
wire [31:0] gba_debug_bad_target_pc;
wire [31:0] gba_debug_bad_source_lr;
wire [15:0] gba_debug_bad_source_cpsr;
wire [31:0] gba_debug_thumb_return_pop_addr;
wire [31:0] gba_debug_thumb_return_pop_data;
wire [31:0] gba_debug_thumb_return_fetch_word;
wire [31:0] gba_debug_thumb_return_pre_bx_instr;
wire [15:0] gba_debug_thumb_return_flags;
wire [31:0] gba_debug_indirect_call_r0;
wire [31:0] gba_debug_indirect_call_fetch_word;
wire [31:0] gba_debug_indirect_call_read_addr;
wire [31:0] gba_debug_indirect_call_read_data;
wire [15:0] gba_debug_indirect_call_flags;
wire [31:0] gba_debug_irq_callback_read_pc;
wire [31:0] gba_debug_irq_callback_read_data;
wire [31:0] gba_debug_irq_bx_target;
wire [31:0] gba_debug_irq_first_ewram_pc;
wire [31:0] gba_debug_irq_ewram_source_pc;
wire [31:0] gba_debug_irq_ewram_source_instr;
wire [15:0] gba_debug_irq_pending_bits;
wire       gba_cart_req;
wire [31:0] gba_cart_addr;
wire [31:0] gba_cart_rdata;
wire        gba_cart_ready;
wire [31:0] gba_load_wdata = bridge_endian_little ? bridge_wr_data : {
    bridge_wr_data[7:0], bridge_wr_data[15:8],
    bridge_wr_data[23:16], bridge_wr_data[31:24]
};
wire        gba_bios_load_write = bridge_wr && (bridge_addr[31:24] == 8'h00);
wire [11:0] gba_bios_load_addr = bridge_addr[13:2];
wire gba_cart_load_write;
wire [22:0] gba_cart_load_addr;
gba_rom_load_decode rom_load_decode(.bridge_write(bridge_wr),.bridge_addr(bridge_addr),
    .load_write(gba_cart_load_write),.load_addr(gba_cart_load_addr));
// Ignore optional RTC trailers beyond the 128 KiB Flash array.
wire gba_save_load_write = gba_save_write_allowed && bridge_wr && bridge_addr[31:24] == 8'h0e &&
                          bridge_addr[23:17] == 0;
wire [9:0] gba_controller_keys = {
    ~cont1_key[8],  // L
    ~cont1_key[9],  // R
    ~cont1_key[1],  // Down
    ~cont1_key[0],  // Up
    ~cont1_key[2],  // Left
    ~cont1_key[3],  // Right
    ~cont1_key[15], // Start
    ~cont1_key[14], // Select
    ~cont1_key[5],  // B
    ~cont1_key[4]   // A
};

`ifdef GBK_FAST_FORWARD
wire gba_fast_forward_active,gba_fast_forward_realign;
wire gba_fast_forward_mute;
wire [1:0] gba_fast_forward_speed;
wire [31:0] gba_fast_forward_rdata;
gba_fast_forward fast_forward_control(.host_clk(clk_74a),.cpu_clk(clk_core_39936),.reset(~reset_n),
    .in_menu(osnotify_inmenu),
`ifdef GBK_POCKET_STATE
    .suspended(pstate_busy),
`else
    .suspended(1'b0),
`endif
    .hold_button(cont1_key[6]),.bridge_wr(bridge_wr),.bridge_rd(bridge_rd),
    .endian_little(bridge_endian_little),.bridge_addr(bridge_addr),.bridge_wdata(bridge_wr_data),
    .bridge_rdata(gba_fast_forward_rdata),.active(gba_fast_forward_active),.realign(gba_fast_forward_realign),
    .speed(gba_fast_forward_speed),.mute_audio(gba_fast_forward_mute));
`endif

`ifdef GBK_DIAGNOSTIC
`ifdef GBK_DEEP_DIAGNOSTIC
localparam GBA_REGION_PROFILE=0;
`else
localparam GBA_REGION_PROFILE=1;
`endif
`else
localparam GBA_REGION_PROFILE=0;
`endif
gba_system_top #(.RTC_PERSISTENCE(GBA_RTC_PERSISTENCE),.EEPROM(GBA_EEPROM),.EXTERNAL_SAVE(GBA_EXTERNAL_SAVE),.RESET_PC(32'h00000000), .EXTERNAL_CARTRIDGE(1'b1),
                  .EXTERNAL_EWRAM(1'b1), .RENDER_SCHEDULER(1'b1), .NATIVE_TIMING(1'b1),.FAST_CPU(1),
                  .REGION_PROFILE(GBA_REGION_PROFILE),.ROM_PROFILE(GBA_REGION_PROFILE),
                  .SDRAM_EWRAM(GBA_SDRAM_EWRAM),.SDRAM_ROM(GBA_SDRAM_ROM),.EWRAM_BURST_FILL(GBA_EWRAM_BURST_FILL),
                  .ROM_DIRECT_BURST(GBA_ROM_DIRECT_BURST),.ROM_FILL_NEIGHBOR(GBA_ROM_FILL_NEIGHBOR)) gba_emulator (
`ifdef GBK_FAST_FORWARD
    .fast_forward(gba_fast_forward_active),.fast_forward_realign(gba_fast_forward_realign),
    .fast_forward_speed(gba_fast_forward_speed),
    .fast_forward_mute(gba_fast_forward_mute),
`endif
`ifdef GBK_SAVESTATE
`ifdef GBK_POCKET_STATE
    .state_cpu_request(pstate_cpu_request),.state_dma_request(pstate_dma_request),.state_hold(pstate_hold),
    .state_reg_write(pstate_reg_write),.state_reg_addr(pstate_reg_addr),.state_reg_wdata(pstate_reg_wdata),
    .state_save_raw_access(pstate_save_access),.state_save_raw_eeprom(pstate_save_eeprom),
    .state_save_raw_idle(pstate_save_idle),.state_save_raw_done(pstate_save_done),
    .state_cpu_quiescent(pstate_cpu_idle),.state_dma_quiescent(pstate_dma_idle),.state_held(pstate_held),
    .state_reg_valid(pstate_reg_valid),.state_reg_rdata(pstate_reg_rdata),
    .state_transactions_idle(pstate_guest_idle),.state_resume_prepare(pstate_resume_prepare),.state_resume_ready(pstate_resume_ready),
    .state_resume_complete(pstate_resume_complete),
    .state_bulk_valid(pstate_bulk_valid),.state_bulk_write(pstate_bulk_write),.state_bulk_response_ready(pstate_bulk_consume),
    .state_bulk_addr(pstate_bulk_addr),.state_bulk_wdata(pstate_bulk_wdata),
    .state_bulk_ready(pstate_bulk_ready),.state_bulk_response(pstate_bulk_response),.state_bulk_error(pstate_bulk_error),
    .state_bulk_busy(),.state_bulk_rdata(pstate_bulk_rdata),
    .state_memory_enable(1'b1),.state_memory_background(1'b1),.state_memory_valid(pstate_memory_valid),.state_memory_write(pstate_memory_write),
    .state_memory_addr(pstate_memory_addr),.state_memory_wdata(pstate_memory_wdata),.state_memory_byteena(pstate_memory_byteena),
    .state_memory_ready(pstate_memory_ready),.state_memory_response(pstate_memory_response),
    .state_memory_rdata(pstate_memory_rdata),.state_memory_response_ready(pstate_memory_consume),
`else
    // Keep incomplete state transport explicitly inactive. Do not gate normal
    // boot/readiness on state-buffer initialization or leave hold inputs open.
    .state_cpu_request(1'b0),.state_dma_request(1'b0),.state_hold(1'b0),.state_reg_write(1'b0),
    .state_reg_addr(16'd0),.state_reg_wdata(32'd0),
    .state_save_raw_access(1'b0),.state_save_raw_eeprom(1'b0),.state_save_raw_idle(),.state_save_raw_done(),
    .state_cpu_quiescent(),.state_dma_quiescent(),.state_held(),.state_reg_valid(),.state_reg_rdata(),
    .state_bulk_valid(1'b0),.state_bulk_write(1'b0),.state_bulk_response_ready(1'b0),
    .state_bulk_addr(32'd0),.state_bulk_wdata(32'd0),
    .state_bulk_ready(),.state_bulk_response(),.state_bulk_error(),.state_bulk_busy(),.state_bulk_rdata(),
    .state_memory_enable(1'b0),.state_memory_valid(1'b0),.state_memory_write(1'b0),
    .state_memory_background(1'b0),
    .state_memory_addr(25'd0),.state_memory_wdata(32'd0),.state_memory_byteena(4'd0),
    .state_memory_ready(),.state_memory_response(),.state_memory_rdata(),.state_memory_response_ready(1'b0),
`endif
`endif
    .sdram_reset(memory_startup_reset),.sdram_initialized(sdram_initialized),
    .dram_a(dram_a),.dram_ba(dram_ba),.dram_dq(dram_dq),.dram_dqm(dram_dqm),
    .dram_cke(dram_cke),.dram_ras_n(dram_ras_n),.dram_cas_n(dram_cas_n),.dram_we_n(dram_we_n),
    .video_skip(gba_video_skip),
    .guest_stopped(gba_guest_stopped),
    .audio_left(gba_audio_left),.audio_right(gba_audio_right),
    .clk(clk_core_12288),.cpu_clk(clk_core_39936),.debug_cycle_profile(gba_cycle_profile),.debug_rom_profile(gba_rom_profile),.debug_stall_profile(gba_stall_profile),
    .fast_clk(clk_core_133),
    .reset(~reset_n || !gba_rtc_boot_ready),
    .rtc_host_epoch(rtc_epoch_seconds),.rtc_persistence_request(gba_rtc_request),
    .rtc_persistence_operation(gba_rtc_operation),.rtc_persistence_payload(gba_rtc_payload),
    .rtc_persistence_acknowledge(gba_rtc_acknowledge),.rtc_persistence_reply(gba_rtc_reply),
    .rtc_host_toggle(rtc_update_toggle),.rtc_host_valid(rtc_valid),
    .rtc_host_date(rtc_date_bcd),.rtc_host_time(rtc_time_bcd),
    .link_pins_in({port_tran_so,port_tran_si,port_tran_sd,port_tran_sck}),
    .link_pins_out(gba_link_out),.link_pins_dir(gba_link_dir),
    .controller_keys(gba_controller_keys),
    .cart_load_clk(clk_74a),
    .cart_load_reset(memory_startup_reset),
    .cart_load_write(gba_cart_load_write),
    .cart_load_addr(gba_cart_load_addr),
    .cart_load_wdata(gba_load_wdata),
`ifdef GBK_POCKET_STATE
    .save_load_read(pstate_save_access ? pstate_save_read : (gba_save_read_allowed && bridge_rd && bridge_addr[31:24]==8'h0e && bridge_addr[23:17]==0)),
`else
    .save_load_read(gba_save_read_allowed && bridge_rd && bridge_addr[31:24]==8'h0e && bridge_addr[23:17]==0),
`endif
    .save_load_valid(gba_save_load_valid),.save_boot_ready(gba_save_boot_ready),.save_fault(gba_save_fault),
    .save_mem_a(sram_a),.save_mem_dq(sram_dq),.save_mem_oe_n(sram_oe_n),
    .save_mem_we_n(sram_we_n),.save_mem_ub_n(sram_ub_n),.save_mem_lb_n(sram_lb_n),
    .save_sram(gba_save_sram),
    .save_eeprom(gba_save_eeprom),.save_eeprom_large(gba_eeprom_large),.cart_large(gba_cart_large),
`ifdef GBK_POCKET_STATE
    .save_load_write(pstate_save_access ? pstate_save_write : gba_save_load_write),
    .save_load_addr(pstate_save_access ? pstate_save_addr : bridge_addr[16:2]),
    .save_load_wdata(pstate_save_access ? pstate_save_wdata : gba_load_wdata),
`else
    .save_load_write(gba_save_load_write),
    .save_load_addr(bridge_addr[16:2]),
    .save_load_wdata(gba_load_wdata),
`endif
    .save_load_rdata(gba_save_rdata),
    .save_export_lock(gba_save_export), .save_export_locked(gba_save_locked),
    .debug_restart_context(gba_restart_context),
    .debug_restart_valid(gba_restart_valid),
    .bios_load_write(gba_bios_load_write),
    .bios_load_addr(gba_bios_load_addr),
    .bios_load_wdata(gba_load_wdata),
    .cart_req(gba_cart_req),
    .cart_addr(gba_cart_addr),
    .cart_rdata(gba_cart_rdata),
    .cart_ready(gba_cart_ready),
    .cram_a(cram0_a),
    .cram_dq(cram0_dq),
    .cram_wait(cram0_wait),
    .cram_clk(cram0_clk),
    .cram_adv_n(cram0_adv_n),
    .cram_cre(cram0_cre),
    .cram_ce0_n(cram0_ce0_n),
    .cram_ce1_n(cram0_ce1_n),
    .cram_oe_n(cram0_oe_n),
    .cram_we_n(cram0_we_n),
    .cram_ub_n(cram0_ub_n),
    .cram_lb_n(cram0_lb_n),
    .ewram_cram_a(cram1_a),
    .ewram_cram_dq(cram1_dq),
    .ewram_cram_wait(cram1_wait),
    .ewram_cram_clk(cram1_clk),
    .ewram_cram_adv_n(cram1_adv_n),
    .ewram_cram_cre(cram1_cre),
    .ewram_cram_ce0_n(cram1_ce0_n),
    .ewram_cram_ce1_n(cram1_ce1_n),
    .ewram_cram_oe_n(cram1_oe_n),
    .ewram_cram_we_n(cram1_we_n),
    .ewram_cram_ub_n(cram1_ub_n),
    .ewram_cram_lb_n(cram1_lb_n),
    .video_r(gba_video_r),
    .video_g(gba_video_g),
    .video_b(gba_video_b),
    .video_de(gba_video_de),
    .video_hsync(gba_video_hs),
    .video_vsync(gba_video_vs),
    .debug_ppu_dispcnt(gba_debug_ppu_dispcnt),
    .debug_ppu_bg0cnt(gba_debug_ppu_bg0cnt),
    .debug_ppu_bg1cnt(gba_debug_ppu_bg1cnt),
    .debug_ppu_bg2cnt(gba_debug_ppu_bg2cnt),
    .debug_ppu_bg3cnt(gba_debug_ppu_bg3cnt),
    .debug_bg3_matrix(gba_debug_bg3_matrix),
    .debug_bg3_reference(gba_debug_bg3_reference),
    .debug_dma_source(gba_debug_dma_source),
    .debug_dma_destination(gba_debug_dma_destination),
    .debug_dma_status(gba_debug_dma_status),
    .debug_bg3_map(gba_debug_bg3_map),
    .debug_bg3_tile(gba_debug_bg3_tile),
    .debug_bg3_tile_raw(gba_debug_bg3_tile_raw),
    .debug_mode2_status(gba_debug_mode2_status),
    .debug_mode2_window(gba_debug_mode2_window),
    .debug_pc(gba_debug_pc),
    .debug_cpsr(gba_debug_cpsr),
    .debug_instr(gba_debug_instr),
    .debug_r1(gba_debug_r1),
    .debug_bios_sound_state(gba_debug_bios_sound_state),
    .debug_execution_state(gba_debug_execution_state),
    .debug_irq_counts(gba_debug_irq_counts),
    .debug_runtime_memory(gba_debug_runtime_memory),
    .debug_bias_pc(gba_debug_bias_pc),
    .debug_bias_instr(gba_debug_bias_instr),
    .debug_bias_r1(gba_debug_bias_r1),
    .debug_bias_r2(gba_debug_bias_r2),
    .debug_bias_r12(gba_debug_bias_r12),
    .debug_bias_count(gba_debug_bias_count),
    .debug_sound_bias(gba_debug_sound_bias),
    .debug_irq_vector_write_data(gba_debug_irq_vector_write_data),
    .debug_irq_vector_write_status(gba_debug_irq_vector_write_status),
    .debug_irq_vector_snapshot_data(gba_debug_irq_vector_snapshot_data),
    .debug_irq_vector_snapshot_status(gba_debug_irq_vector_snapshot_status),
    .debug_io_trace(gba_debug_io_trace),
    .debug_io_read_trace(gba_debug_io_read_trace),
    .debug_io_write_trace(gba_debug_io_write_trace),
    .debug_irq_handler_read_pc(gba_debug_irq_handler_read_pc),
    .debug_irq_handler_read_data(gba_debug_irq_handler_read_data),
    .debug_irq_probe_r0(gba_debug_irq_probe_r0),
    .debug_irq_probe_bus_addr(gba_debug_irq_probe_bus_addr),
    .debug_irq_probe_pending_addr(gba_debug_irq_probe_pending_addr),
    .debug_irq_probe_port_state(gba_debug_irq_probe_port_state),
    .debug_irq_probe_bus_data(gba_debug_irq_probe_bus_data),
    .debug_irq_probe_ram_data(gba_debug_irq_probe_ram_data),
    .debug_irq_probe_vector_write(gba_debug_irq_probe_vector_write),
    .debug_irq_stage_flags(gba_debug_irq_stage_flags),
    .debug_irq_12c_instr(gba_debug_irq_12c_instr),
    .debug_irq_130_r0(gba_debug_irq_130_r0),
    .debug_irq_130_instr(gba_debug_irq_130_instr),
    .debug_irq_134_fetch_r0(gba_debug_irq_134_fetch_r0),
    .debug_bios_word_12c(gba_debug_bios_word_12c),
    .debug_first_irq_entry_lr(gba_debug_first_irq_entry_lr),
    .debug_first_irq_return_lr(gba_debug_first_irq_return_lr),
    .debug_first_irq_push_lr_addr(gba_debug_first_irq_push_lr_addr),
    .debug_first_irq_push_lr_data(gba_debug_first_irq_push_lr_data),
    .debug_second_irq_push_lr_addr(gba_debug_second_irq_push_lr_addr),
    .debug_second_irq_push_lr_data(gba_debug_second_irq_push_lr_data),
    .debug_first_irq_pop_lr_addr(gba_debug_first_irq_pop_lr_addr),
    .debug_first_irq_pop_lr_data(gba_debug_first_irq_pop_lr_data),
    .debug_first_irq_vector_lr(gba_debug_first_irq_vector_lr),
    .debug_first_irq_prologue_lr(gba_debug_first_irq_prologue_lr),
    .debug_first_irq_stack_passes(gba_debug_first_irq_stack_passes),
    .debug_first_irq_progress(gba_debug_first_irq_progress),
    .debug_first_irq_last_pc(gba_debug_first_irq_last_pc),
    .debug_first_irq_134_instr(gba_debug_first_irq_134_instr),
    .debug_first_irq_load_state(gba_debug_first_irq_load_state),
    .debug_first_irq_load_data(gba_debug_first_irq_load_data),
    .debug_first_irq_load_target(gba_debug_first_irq_load_target),
    .debug_bad_source_pc(gba_debug_bad_source_pc),
    .debug_bad_source_instr(gba_debug_bad_source_instr),
    .debug_bad_target_pc(gba_debug_bad_target_pc),
    .debug_bad_source_lr(gba_debug_bad_source_lr),
    .debug_bad_source_cpsr(gba_debug_bad_source_cpsr),
    .debug_thumb_return_pop_addr(gba_debug_thumb_return_pop_addr),
    .debug_thumb_return_pop_data(gba_debug_thumb_return_pop_data),
    .debug_thumb_return_fetch_word(gba_debug_thumb_return_fetch_word),
    .debug_thumb_return_pre_bx_instr(gba_debug_thumb_return_pre_bx_instr),
    .debug_thumb_return_flags(gba_debug_thumb_return_flags),
    .debug_indirect_call_r0(gba_debug_indirect_call_r0),
    .debug_indirect_call_fetch_word(gba_debug_indirect_call_fetch_word),
    .debug_indirect_call_read_addr(gba_debug_indirect_call_read_addr),
    .debug_indirect_call_read_data(gba_debug_indirect_call_read_data),
    .debug_indirect_call_flags(gba_debug_indirect_call_flags),
    .debug_irq_callback_read_pc(gba_debug_irq_callback_read_pc),
    .debug_irq_callback_read_data(gba_debug_irq_callback_read_data),
    .debug_irq_bx_target(gba_debug_irq_bx_target),
    .debug_irq_first_ewram_pc(gba_debug_irq_first_ewram_pc),
    .debug_irq_ewram_source_pc(gba_debug_irq_ewram_source_pc),
    .debug_irq_ewram_source_instr(gba_debug_irq_ewram_source_instr),
    .debug_irq_pending_bits(gba_debug_irq_pending_bits)
);

`ifdef GBK_LEGACY_CUBE
    localparam  VID_V_BPORCH = 'd10;
    localparam  VID_V_ACTIVE = 'd240;
    localparam  VID_V_TOTAL = 'd512;
    localparam  VID_H_BPORCH = 'd10;
    localparam  VID_H_ACTIVE = 'd320;
    localparam  VID_H_TOTAL = 'd400;

    reg [15:0]  frame_count;
    
    reg [9:0]   x_count;
    reg [9:0]   y_count;
    
    wire [9:0]  visible_x = x_count - VID_H_BPORCH;
    wire [9:0]  visible_y = y_count - VID_V_BPORCH;
    // True 3D wireframe cube: 32 preprojected yaw/pitch poses.
    function signed [9:0] cube_v0_x; input [4:0] phase; begin case (phase)
        5'd0: cube_v0_x=10'sd101;
        5'd1: cube_v0_x=10'sd97;
        5'd2: cube_v0_x=10'sd96;
        5'd3: cube_v0_x=10'sd98;
        5'd4: cube_v0_x=10'sd103;
        5'd5: cube_v0_x=10'sd108;
        5'd6: cube_v0_x=10'sd115;
        5'd7: cube_v0_x=10'sd122;
        5'd8: cube_v0_x=10'sd129;
        5'd9: cube_v0_x=10'sd137;
        5'd10: cube_v0_x=10'sd144;
        5'd11: cube_v0_x=10'sd152;
        5'd12: cube_v0_x=10'sd160;
        5'd13: cube_v0_x=10'sd168;
        5'd14: cube_v0_x=10'sd176;
        5'd15: cube_v0_x=10'sd183;
        5'd16: cube_v0_x=10'sd191;
        5'd17: cube_v0_x=10'sd198;
        5'd18: cube_v0_x=10'sd205;
        5'd19: cube_v0_x=10'sd212;
        5'd20: cube_v0_x=10'sd217;
        5'd21: cube_v0_x=10'sd222;
        5'd22: cube_v0_x=10'sd224;
        5'd23: cube_v0_x=10'sd223;
        5'd24: cube_v0_x=10'sd219;
        5'd25: cube_v0_x=10'sd210;
        5'd26: cube_v0_x=10'sd197;
        5'd27: cube_v0_x=10'sd180;
        5'd28: cube_v0_x=10'sd160;
        5'd29: cube_v0_x=10'sd140;
        5'd30: cube_v0_x=10'sd123;
        5'd31: cube_v0_x=10'sd110;
    endcase end endfunction
    function signed [9:0] cube_v0_y; input [4:0] phase; begin case (phase)
        5'd0: cube_v0_y=10'sd61;
        5'd1: cube_v0_y=10'sd71;
        5'd2: cube_v0_y=10'sd77;
        5'd3: cube_v0_y=10'sd81;
        5'd4: cube_v0_y=10'sd82;
        5'd5: cube_v0_y=10'sd82;
        5'd6: cube_v0_y=10'sd81;
        5'd7: cube_v0_y=10'sd79;
        5'd8: cube_v0_y=10'sd76;
        5'd9: cube_v0_y=10'sd74;
        5'd10: cube_v0_y=10'sd73;
        5'd11: cube_v0_y=10'sd72;
        5'd12: cube_v0_y=10'sd72;
        5'd13: cube_v0_y=10'sd74;
        5'd14: cube_v0_y=10'sd77;
        5'd15: cube_v0_y=10'sd82;
        5'd16: cube_v0_y=10'sd89;
        5'd17: cube_v0_y=10'sd85;
        5'd18: cube_v0_y=10'sd82;
        5'd19: cube_v0_y=10'sd81;
        5'd20: cube_v0_y=10'sd82;
        5'd21: cube_v0_y=10'sd87;
        5'd22: cube_v0_y=10'sd94;
        5'd23: cube_v0_y=10'sd105;
        5'd24: cube_v0_y=10'sd120;
        5'd25: cube_v0_y=10'sd138;
        5'd26: cube_v0_y=10'sd156;
        5'd27: cube_v0_y=10'sd174;
        5'd28: cube_v0_y=10'sd187;
        5'd29: cube_v0_y=10'sd194;
        5'd30: cube_v0_y=10'sd195;
        5'd31: cube_v0_y=10'sd189;
    endcase end endfunction
    function signed [9:0] cube_v1_x; input [4:0] phase; begin case (phase)
        5'd0: cube_v1_x=10'sd101;
        5'd1: cube_v1_x=10'sd97;
        5'd2: cube_v1_x=10'sd96;
        5'd3: cube_v1_x=10'sd98;
        5'd4: cube_v1_x=10'sd103;
        5'd5: cube_v1_x=10'sd108;
        5'd6: cube_v1_x=10'sd115;
        5'd7: cube_v1_x=10'sd122;
        5'd8: cube_v1_x=10'sd129;
        5'd9: cube_v1_x=10'sd137;
        5'd10: cube_v1_x=10'sd144;
        5'd11: cube_v1_x=10'sd152;
        5'd12: cube_v1_x=10'sd160;
        5'd13: cube_v1_x=10'sd168;
        5'd14: cube_v1_x=10'sd176;
        5'd15: cube_v1_x=10'sd183;
        5'd16: cube_v1_x=10'sd191;
        5'd17: cube_v1_x=10'sd198;
        5'd18: cube_v1_x=10'sd205;
        5'd19: cube_v1_x=10'sd212;
        5'd20: cube_v1_x=10'sd217;
        5'd21: cube_v1_x=10'sd222;
        5'd22: cube_v1_x=10'sd224;
        5'd23: cube_v1_x=10'sd223;
        5'd24: cube_v1_x=10'sd219;
        5'd25: cube_v1_x=10'sd210;
        5'd26: cube_v1_x=10'sd197;
        5'd27: cube_v1_x=10'sd180;
        5'd28: cube_v1_x=10'sd160;
        5'd29: cube_v1_x=10'sd140;
        5'd30: cube_v1_x=10'sd123;
        5'd31: cube_v1_x=10'sd110;
    endcase end endfunction
    function signed [9:0] cube_v1_y; input [4:0] phase; begin case (phase)
        5'd0: cube_v1_y=10'sd179;
        5'd1: cube_v1_y=10'sd178;
        5'd2: cube_v1_y=10'sd173;
        5'd3: cube_v1_y=10'sd166;
        5'd4: cube_v1_y=10'sd158;
        5'd5: cube_v1_y=10'sd148;
        5'd6: cube_v1_y=10'sd138;
        5'd7: cube_v1_y=10'sd129;
        5'd8: cube_v1_y=10'sd120;
        5'd9: cube_v1_y=10'sd112;
        5'd10: cube_v1_y=10'sd105;
        5'd11: cube_v1_y=10'sd99;
        5'd12: cube_v1_y=10'sd94;
        5'd13: cube_v1_y=10'sd91;
        5'd14: cube_v1_y=10'sd89;
        5'd15: cube_v1_y=10'sd88;
        5'd16: cube_v1_y=10'sd151;
        5'd17: cube_v1_y=10'sd150;
        5'd18: cube_v1_y=10'sd150;
        5'd19: cube_v1_y=10'sd153;
        5'd20: cube_v1_y=10'sd158;
        5'd21: cube_v1_y=10'sd165;
        5'd22: cube_v1_y=10'sd175;
        5'd23: cube_v1_y=10'sd188;
        5'd24: cube_v1_y=10'sd204;
        5'd25: cube_v1_y=10'sd219;
        5'd26: cube_v1_y=10'sd233;
        5'd27: cube_v1_y=10'sd242;
        5'd28: cube_v1_y=10'sd243;
        5'd29: cube_v1_y=10'sd236;
        5'd30: cube_v1_y=10'sd221;
        5'd31: cube_v1_y=10'sd201;
    endcase end endfunction
    function signed [9:0] cube_v2_x; input [4:0] phase; begin case (phase)
        5'd0: cube_v2_x=10'sd219;
        5'd1: cube_v2_x=10'sd210;
        5'd2: cube_v2_x=10'sd197;
        5'd3: cube_v2_x=10'sd180;
        5'd4: cube_v2_x=10'sd160;
        5'd5: cube_v2_x=10'sd140;
        5'd6: cube_v2_x=10'sd123;
        5'd7: cube_v2_x=10'sd110;
        5'd8: cube_v2_x=10'sd101;
        5'd9: cube_v2_x=10'sd97;
        5'd10: cube_v2_x=10'sd96;
        5'd11: cube_v2_x=10'sd98;
        5'd12: cube_v2_x=10'sd103;
        5'd13: cube_v2_x=10'sd108;
        5'd14: cube_v2_x=10'sd115;
        5'd15: cube_v2_x=10'sd122;
        5'd16: cube_v2_x=10'sd129;
        5'd17: cube_v2_x=10'sd137;
        5'd18: cube_v2_x=10'sd144;
        5'd19: cube_v2_x=10'sd152;
        5'd20: cube_v2_x=10'sd160;
        5'd21: cube_v2_x=10'sd168;
        5'd22: cube_v2_x=10'sd176;
        5'd23: cube_v2_x=10'sd183;
        5'd24: cube_v2_x=10'sd191;
        5'd25: cube_v2_x=10'sd198;
        5'd26: cube_v2_x=10'sd205;
        5'd27: cube_v2_x=10'sd212;
        5'd28: cube_v2_x=10'sd217;
        5'd29: cube_v2_x=10'sd222;
        5'd30: cube_v2_x=10'sd224;
        5'd31: cube_v2_x=10'sd223;
    endcase end endfunction
    function signed [9:0] cube_v2_y; input [4:0] phase; begin case (phase)
        5'd0: cube_v2_y=10'sd61;
        5'd1: cube_v2_y=10'sd63;
        5'd2: cube_v2_y=10'sd70;
        5'd3: cube_v2_y=10'sd80;
        5'd4: cube_v2_y=10'sd92;
        5'd5: cube_v2_y=10'sd104;
        5'd6: cube_v2_y=10'sd113;
        5'd7: cube_v2_y=10'sd118;
        5'd8: cube_v2_y=10'sd120;
        5'd9: cube_v2_y=10'sd119;
        5'd10: cube_v2_y=10'sd115;
        5'd11: cube_v2_y=10'sd110;
        5'd12: cube_v2_y=10'sd104;
        5'd13: cube_v2_y=10'sd99;
        5'd14: cube_v2_y=10'sd95;
        5'd15: cube_v2_y=10'sd91;
        5'd16: cube_v2_y=10'sd89;
        5'd17: cube_v2_y=10'sd87;
        5'd18: cube_v2_y=10'sd84;
        5'd19: cube_v2_y=10'sd81;
        5'd20: cube_v2_y=10'sd79;
        5'd21: cube_v2_y=10'sd76;
        5'd22: cube_v2_y=10'sd75;
        5'd23: cube_v2_y=10'sd75;
        5'd24: cube_v2_y=10'sd76;
        5'd25: cube_v2_y=10'sd79;
        5'd26: cube_v2_y=10'sd85;
        5'd27: cube_v2_y=10'sd93;
        5'd28: cube_v2_y=10'sd104;
        5'd29: cube_v2_y=10'sd119;
        5'd30: cube_v2_y=10'sd136;
        5'd31: cube_v2_y=10'sd157;
    endcase end endfunction
    function signed [9:0] cube_v3_x; input [4:0] phase; begin case (phase)
        5'd0: cube_v3_x=10'sd219;
        5'd1: cube_v3_x=10'sd210;
        5'd2: cube_v3_x=10'sd197;
        5'd3: cube_v3_x=10'sd180;
        5'd4: cube_v3_x=10'sd160;
        5'd5: cube_v3_x=10'sd140;
        5'd6: cube_v3_x=10'sd123;
        5'd7: cube_v3_x=10'sd110;
        5'd8: cube_v3_x=10'sd101;
        5'd9: cube_v3_x=10'sd97;
        5'd10: cube_v3_x=10'sd96;
        5'd11: cube_v3_x=10'sd98;
        5'd12: cube_v3_x=10'sd103;
        5'd13: cube_v3_x=10'sd108;
        5'd14: cube_v3_x=10'sd115;
        5'd15: cube_v3_x=10'sd122;
        5'd16: cube_v3_x=10'sd129;
        5'd17: cube_v3_x=10'sd137;
        5'd18: cube_v3_x=10'sd144;
        5'd19: cube_v3_x=10'sd152;
        5'd20: cube_v3_x=10'sd160;
        5'd21: cube_v3_x=10'sd168;
        5'd22: cube_v3_x=10'sd176;
        5'd23: cube_v3_x=10'sd183;
        5'd24: cube_v3_x=10'sd191;
        5'd25: cube_v3_x=10'sd198;
        5'd26: cube_v3_x=10'sd205;
        5'd27: cube_v3_x=10'sd212;
        5'd28: cube_v3_x=10'sd217;
        5'd29: cube_v3_x=10'sd222;
        5'd30: cube_v3_x=10'sd224;
        5'd31: cube_v3_x=10'sd223;
    endcase end endfunction
    function signed [9:0] cube_v3_y; input [4:0] phase; begin case (phase)
        5'd0: cube_v3_y=10'sd179;
        5'd1: cube_v3_y=10'sd191;
        5'd2: cube_v3_y=10'sd205;
        5'd3: cube_v3_y=10'sd217;
        5'd4: cube_v3_y=10'sd227;
        5'd5: cube_v3_y=10'sd230;
        5'd6: cube_v3_y=10'sd227;
        5'd7: cube_v3_y=10'sd218;
        5'd8: cube_v3_y=10'sd204;
        5'd9: cube_v3_y=10'sd187;
        5'd10: cube_v3_y=10'sd169;
        5'd11: cube_v3_y=10'sd152;
        5'd12: cube_v3_y=10'sd136;
        5'd13: cube_v3_y=10'sd121;
        5'd14: cube_v3_y=10'sd108;
        5'd15: cube_v3_y=10'sd98;
        5'd16: cube_v3_y=10'sd151;
        5'd17: cube_v3_y=10'sd146;
        5'd18: cube_v3_y=10'sd141;
        5'd19: cube_v3_y=10'sd136;
        5'd20: cube_v3_y=10'sd131;
        5'd21: cube_v3_y=10'sd126;
        5'd22: cube_v3_y=10'sd123;
        5'd23: cube_v3_y=10'sd121;
        5'd24: cube_v3_y=10'sd120;
        5'd25: cube_v3_y=10'sd121;
        5'd26: cube_v3_y=10'sd124;
        5'd27: cube_v3_y=10'sd129;
        5'd28: cube_v3_y=10'sd136;
        5'd29: cube_v3_y=10'sd145;
        5'd30: cube_v3_y=10'sd155;
        5'd31: cube_v3_y=10'sd167;
    endcase end endfunction
    function signed [9:0] cube_v4_x; input [4:0] phase; begin case (phase)
        5'd0: cube_v4_x=10'sd129;
        5'd1: cube_v4_x=10'sd137;
        5'd2: cube_v4_x=10'sd144;
        5'd3: cube_v4_x=10'sd152;
        5'd4: cube_v4_x=10'sd160;
        5'd5: cube_v4_x=10'sd168;
        5'd6: cube_v4_x=10'sd176;
        5'd7: cube_v4_x=10'sd183;
        5'd8: cube_v4_x=10'sd191;
        5'd9: cube_v4_x=10'sd198;
        5'd10: cube_v4_x=10'sd205;
        5'd11: cube_v4_x=10'sd212;
        5'd12: cube_v4_x=10'sd217;
        5'd13: cube_v4_x=10'sd222;
        5'd14: cube_v4_x=10'sd224;
        5'd15: cube_v4_x=10'sd223;
        5'd16: cube_v4_x=10'sd219;
        5'd17: cube_v4_x=10'sd210;
        5'd18: cube_v4_x=10'sd197;
        5'd19: cube_v4_x=10'sd180;
        5'd20: cube_v4_x=10'sd160;
        5'd21: cube_v4_x=10'sd140;
        5'd22: cube_v4_x=10'sd123;
        5'd23: cube_v4_x=10'sd110;
        5'd24: cube_v4_x=10'sd101;
        5'd25: cube_v4_x=10'sd97;
        5'd26: cube_v4_x=10'sd96;
        5'd27: cube_v4_x=10'sd98;
        5'd28: cube_v4_x=10'sd103;
        5'd29: cube_v4_x=10'sd108;
        5'd30: cube_v4_x=10'sd115;
        5'd31: cube_v4_x=10'sd122;
    endcase end endfunction
    function signed [9:0] cube_v4_y; input [4:0] phase; begin case (phase)
        5'd0: cube_v4_y=10'sd89;
        5'd1: cube_v4_y=10'sd87;
        5'd2: cube_v4_y=10'sd84;
        5'd3: cube_v4_y=10'sd81;
        5'd4: cube_v4_y=10'sd79;
        5'd5: cube_v4_y=10'sd76;
        5'd6: cube_v4_y=10'sd75;
        5'd7: cube_v4_y=10'sd75;
        5'd8: cube_v4_y=10'sd76;
        5'd9: cube_v4_y=10'sd79;
        5'd10: cube_v4_y=10'sd85;
        5'd11: cube_v4_y=10'sd93;
        5'd12: cube_v4_y=10'sd104;
        5'd13: cube_v4_y=10'sd119;
        5'd14: cube_v4_y=10'sd136;
        5'd15: cube_v4_y=10'sd157;
        5'd16: cube_v4_y=10'sd61;
        5'd17: cube_v4_y=10'sd63;
        5'd18: cube_v4_y=10'sd70;
        5'd19: cube_v4_y=10'sd80;
        5'd20: cube_v4_y=10'sd92;
        5'd21: cube_v4_y=10'sd104;
        5'd22: cube_v4_y=10'sd113;
        5'd23: cube_v4_y=10'sd118;
        5'd24: cube_v4_y=10'sd120;
        5'd25: cube_v4_y=10'sd119;
        5'd26: cube_v4_y=10'sd115;
        5'd27: cube_v4_y=10'sd110;
        5'd28: cube_v4_y=10'sd104;
        5'd29: cube_v4_y=10'sd99;
        5'd30: cube_v4_y=10'sd95;
        5'd31: cube_v4_y=10'sd91;
    endcase end endfunction
    function signed [9:0] cube_v5_x; input [4:0] phase; begin case (phase)
        5'd0: cube_v5_x=10'sd129;
        5'd1: cube_v5_x=10'sd137;
        5'd2: cube_v5_x=10'sd144;
        5'd3: cube_v5_x=10'sd152;
        5'd4: cube_v5_x=10'sd160;
        5'd5: cube_v5_x=10'sd168;
        5'd6: cube_v5_x=10'sd176;
        5'd7: cube_v5_x=10'sd183;
        5'd8: cube_v5_x=10'sd191;
        5'd9: cube_v5_x=10'sd198;
        5'd10: cube_v5_x=10'sd205;
        5'd11: cube_v5_x=10'sd212;
        5'd12: cube_v5_x=10'sd217;
        5'd13: cube_v5_x=10'sd222;
        5'd14: cube_v5_x=10'sd224;
        5'd15: cube_v5_x=10'sd223;
        5'd16: cube_v5_x=10'sd219;
        5'd17: cube_v5_x=10'sd210;
        5'd18: cube_v5_x=10'sd197;
        5'd19: cube_v5_x=10'sd180;
        5'd20: cube_v5_x=10'sd160;
        5'd21: cube_v5_x=10'sd140;
        5'd22: cube_v5_x=10'sd123;
        5'd23: cube_v5_x=10'sd110;
        5'd24: cube_v5_x=10'sd101;
        5'd25: cube_v5_x=10'sd97;
        5'd26: cube_v5_x=10'sd96;
        5'd27: cube_v5_x=10'sd98;
        5'd28: cube_v5_x=10'sd103;
        5'd29: cube_v5_x=10'sd108;
        5'd30: cube_v5_x=10'sd115;
        5'd31: cube_v5_x=10'sd122;
    endcase end endfunction
    function signed [9:0] cube_v5_y; input [4:0] phase; begin case (phase)
        5'd0: cube_v5_y=10'sd151;
        5'd1: cube_v5_y=10'sd146;
        5'd2: cube_v5_y=10'sd141;
        5'd3: cube_v5_y=10'sd136;
        5'd4: cube_v5_y=10'sd131;
        5'd5: cube_v5_y=10'sd126;
        5'd6: cube_v5_y=10'sd123;
        5'd7: cube_v5_y=10'sd121;
        5'd8: cube_v5_y=10'sd120;
        5'd9: cube_v5_y=10'sd121;
        5'd10: cube_v5_y=10'sd124;
        5'd11: cube_v5_y=10'sd129;
        5'd12: cube_v5_y=10'sd136;
        5'd13: cube_v5_y=10'sd145;
        5'd14: cube_v5_y=10'sd155;
        5'd15: cube_v5_y=10'sd167;
        5'd16: cube_v5_y=10'sd179;
        5'd17: cube_v5_y=10'sd191;
        5'd18: cube_v5_y=10'sd205;
        5'd19: cube_v5_y=10'sd217;
        5'd20: cube_v5_y=10'sd227;
        5'd21: cube_v5_y=10'sd230;
        5'd22: cube_v5_y=10'sd227;
        5'd23: cube_v5_y=10'sd218;
        5'd24: cube_v5_y=10'sd204;
        5'd25: cube_v5_y=10'sd187;
        5'd26: cube_v5_y=10'sd169;
        5'd27: cube_v5_y=10'sd152;
        5'd28: cube_v5_y=10'sd136;
        5'd29: cube_v5_y=10'sd121;
        5'd30: cube_v5_y=10'sd108;
        5'd31: cube_v5_y=10'sd98;
    endcase end endfunction
    function signed [9:0] cube_v6_x; input [4:0] phase; begin case (phase)
        5'd0: cube_v6_x=10'sd191;
        5'd1: cube_v6_x=10'sd198;
        5'd2: cube_v6_x=10'sd205;
        5'd3: cube_v6_x=10'sd212;
        5'd4: cube_v6_x=10'sd217;
        5'd5: cube_v6_x=10'sd222;
        5'd6: cube_v6_x=10'sd224;
        5'd7: cube_v6_x=10'sd223;
        5'd8: cube_v6_x=10'sd219;
        5'd9: cube_v6_x=10'sd210;
        5'd10: cube_v6_x=10'sd197;
        5'd11: cube_v6_x=10'sd180;
        5'd12: cube_v6_x=10'sd160;
        5'd13: cube_v6_x=10'sd140;
        5'd14: cube_v6_x=10'sd123;
        5'd15: cube_v6_x=10'sd110;
        5'd16: cube_v6_x=10'sd101;
        5'd17: cube_v6_x=10'sd97;
        5'd18: cube_v6_x=10'sd96;
        5'd19: cube_v6_x=10'sd98;
        5'd20: cube_v6_x=10'sd103;
        5'd21: cube_v6_x=10'sd108;
        5'd22: cube_v6_x=10'sd115;
        5'd23: cube_v6_x=10'sd122;
        5'd24: cube_v6_x=10'sd129;
        5'd25: cube_v6_x=10'sd137;
        5'd26: cube_v6_x=10'sd144;
        5'd27: cube_v6_x=10'sd152;
        5'd28: cube_v6_x=10'sd160;
        5'd29: cube_v6_x=10'sd168;
        5'd30: cube_v6_x=10'sd176;
        5'd31: cube_v6_x=10'sd183;
    endcase end endfunction
    function signed [9:0] cube_v6_y; input [4:0] phase; begin case (phase)
        5'd0: cube_v6_y=10'sd89;
        5'd1: cube_v6_y=10'sd85;
        5'd2: cube_v6_y=10'sd82;
        5'd3: cube_v6_y=10'sd81;
        5'd4: cube_v6_y=10'sd82;
        5'd5: cube_v6_y=10'sd87;
        5'd6: cube_v6_y=10'sd94;
        5'd7: cube_v6_y=10'sd105;
        5'd8: cube_v6_y=10'sd120;
        5'd9: cube_v6_y=10'sd138;
        5'd10: cube_v6_y=10'sd156;
        5'd11: cube_v6_y=10'sd174;
        5'd12: cube_v6_y=10'sd187;
        5'd13: cube_v6_y=10'sd194;
        5'd14: cube_v6_y=10'sd195;
        5'd15: cube_v6_y=10'sd189;
        5'd16: cube_v6_y=10'sd61;
        5'd17: cube_v6_y=10'sd71;
        5'd18: cube_v6_y=10'sd77;
        5'd19: cube_v6_y=10'sd81;
        5'd20: cube_v6_y=10'sd82;
        5'd21: cube_v6_y=10'sd82;
        5'd22: cube_v6_y=10'sd81;
        5'd23: cube_v6_y=10'sd79;
        5'd24: cube_v6_y=10'sd76;
        5'd25: cube_v6_y=10'sd74;
        5'd26: cube_v6_y=10'sd73;
        5'd27: cube_v6_y=10'sd72;
        5'd28: cube_v6_y=10'sd72;
        5'd29: cube_v6_y=10'sd74;
        5'd30: cube_v6_y=10'sd77;
        5'd31: cube_v6_y=10'sd82;
    endcase end endfunction
    function signed [9:0] cube_v7_x; input [4:0] phase; begin case (phase)
        5'd0: cube_v7_x=10'sd191;
        5'd1: cube_v7_x=10'sd198;
        5'd2: cube_v7_x=10'sd205;
        5'd3: cube_v7_x=10'sd212;
        5'd4: cube_v7_x=10'sd217;
        5'd5: cube_v7_x=10'sd222;
        5'd6: cube_v7_x=10'sd224;
        5'd7: cube_v7_x=10'sd223;
        5'd8: cube_v7_x=10'sd219;
        5'd9: cube_v7_x=10'sd210;
        5'd10: cube_v7_x=10'sd197;
        5'd11: cube_v7_x=10'sd180;
        5'd12: cube_v7_x=10'sd160;
        5'd13: cube_v7_x=10'sd140;
        5'd14: cube_v7_x=10'sd123;
        5'd15: cube_v7_x=10'sd110;
        5'd16: cube_v7_x=10'sd101;
        5'd17: cube_v7_x=10'sd97;
        5'd18: cube_v7_x=10'sd96;
        5'd19: cube_v7_x=10'sd98;
        5'd20: cube_v7_x=10'sd103;
        5'd21: cube_v7_x=10'sd108;
        5'd22: cube_v7_x=10'sd115;
        5'd23: cube_v7_x=10'sd122;
        5'd24: cube_v7_x=10'sd129;
        5'd25: cube_v7_x=10'sd137;
        5'd26: cube_v7_x=10'sd144;
        5'd27: cube_v7_x=10'sd152;
        5'd28: cube_v7_x=10'sd160;
        5'd29: cube_v7_x=10'sd168;
        5'd30: cube_v7_x=10'sd176;
        5'd31: cube_v7_x=10'sd183;
    endcase end endfunction
    function signed [9:0] cube_v7_y; input [4:0] phase; begin case (phase)
        5'd0: cube_v7_y=10'sd151;
        5'd1: cube_v7_y=10'sd150;
        5'd2: cube_v7_y=10'sd150;
        5'd3: cube_v7_y=10'sd153;
        5'd4: cube_v7_y=10'sd158;
        5'd5: cube_v7_y=10'sd165;
        5'd6: cube_v7_y=10'sd175;
        5'd7: cube_v7_y=10'sd188;
        5'd8: cube_v7_y=10'sd204;
        5'd9: cube_v7_y=10'sd219;
        5'd10: cube_v7_y=10'sd233;
        5'd11: cube_v7_y=10'sd242;
        5'd12: cube_v7_y=10'sd243;
        5'd13: cube_v7_y=10'sd236;
        5'd14: cube_v7_y=10'sd221;
        5'd15: cube_v7_y=10'sd201;
        5'd16: cube_v7_y=10'sd179;
        5'd17: cube_v7_y=10'sd178;
        5'd18: cube_v7_y=10'sd173;
        5'd19: cube_v7_y=10'sd166;
        5'd20: cube_v7_y=10'sd158;
        5'd21: cube_v7_y=10'sd148;
        5'd22: cube_v7_y=10'sd138;
        5'd23: cube_v7_y=10'sd129;
        5'd24: cube_v7_y=10'sd120;
        5'd25: cube_v7_y=10'sd112;
        5'd26: cube_v7_y=10'sd105;
        5'd27: cube_v7_y=10'sd99;
        5'd28: cube_v7_y=10'sd94;
        5'd29: cube_v7_y=10'sd91;
        5'd30: cube_v7_y=10'sd89;
        5'd31: cube_v7_y=10'sd88;
    endcase end endfunction

    function cube_line;
        input signed [9:0] px, py, x0, y0, x1, y1;
        reg signed [10:0] sx0, sy0, sx1, sy1;
        reg signed [10:0] dx, dy, rx, ry, adx, ady, span, tol;
        reg signed [23:0] cross;
        begin
            // Reduce the precomputed perspective poses so the whole cube fits.
            sx0=10'sd160+((x0-10'sd160)>>>1);
            sy0=10'sd120+((y0-10'sd120)>>>1);
            sx1=10'sd160+((x1-10'sd160)>>>1);
            sy1=10'sd120+((y1-10'sd120)>>>1);
            dx=sx1-sx0; dy=sy1-sy0; rx=px-sx0; ry=py-sy0;
            cross=rx*dy-ry*dx;
            adx=(dx<0)?-dx:dx; ady=(dy<0)?-dy:dy;
            span=(adx>ady)?adx:ady;
            tol=span+1;
            cube_line=(cross<=tol)&&(cross>=-tol)&&
                (px>=((sx0<sx1)?sx0-1:sx1-1))&&(px<=((sx0<sx1)?sx1+1:sx0+1))&&
                (py>=((sy0<sy1)?sy0-1:sy1-1))&&(py<=((sy0<sy1)?sy1+1:sy0+1));
        end
    endfunction    wire [4:0] cube_phase = frame_count[8:4];
    wire signed [9:0] cube_px=visible_x, cube_py=visible_y;
    wire cube_edge_0 = cube_line(cube_px,cube_py,cube_v0_x(cube_phase),cube_v0_y(cube_phase),cube_v2_x(cube_phase),cube_v2_y(cube_phase));
    wire cube_edge_1 = cube_line(cube_px,cube_py,cube_v2_x(cube_phase),cube_v2_y(cube_phase),cube_v3_x(cube_phase),cube_v3_y(cube_phase));
    wire cube_edge_2 = cube_line(cube_px,cube_py,cube_v3_x(cube_phase),cube_v3_y(cube_phase),cube_v1_x(cube_phase),cube_v1_y(cube_phase));
    wire cube_edge_3 = cube_line(cube_px,cube_py,cube_v1_x(cube_phase),cube_v1_y(cube_phase),cube_v0_x(cube_phase),cube_v0_y(cube_phase));
    wire cube_edge_4 = cube_line(cube_px,cube_py,cube_v4_x(cube_phase),cube_v4_y(cube_phase),cube_v6_x(cube_phase),cube_v6_y(cube_phase));
    wire cube_edge_5 = cube_line(cube_px,cube_py,cube_v6_x(cube_phase),cube_v6_y(cube_phase),cube_v7_x(cube_phase),cube_v7_y(cube_phase));
    wire cube_edge_6 = cube_line(cube_px,cube_py,cube_v7_x(cube_phase),cube_v7_y(cube_phase),cube_v5_x(cube_phase),cube_v5_y(cube_phase));
    wire cube_edge_7 = cube_line(cube_px,cube_py,cube_v5_x(cube_phase),cube_v5_y(cube_phase),cube_v4_x(cube_phase),cube_v4_y(cube_phase));
    wire cube_edge_8 = cube_line(cube_px,cube_py,cube_v0_x(cube_phase),cube_v0_y(cube_phase),cube_v4_x(cube_phase),cube_v4_y(cube_phase));
    wire cube_edge_9 = cube_line(cube_px,cube_py,cube_v2_x(cube_phase),cube_v2_y(cube_phase),cube_v6_x(cube_phase),cube_v6_y(cube_phase));
    wire cube_edge_10 = cube_line(cube_px,cube_py,cube_v1_x(cube_phase),cube_v1_y(cube_phase),cube_v5_x(cube_phase),cube_v5_y(cube_phase));
    wire cube_edge_11 = cube_line(cube_px,cube_py,cube_v3_x(cube_phase),cube_v3_y(cube_phase),cube_v7_x(cube_phase),cube_v7_y(cube_phase));
    wire cube_edge_front = cube_edge_0|cube_edge_1|cube_edge_2|cube_edge_3;
    wire cube_edge_back = cube_edge_4|cube_edge_5|cube_edge_6|cube_edge_7;
    wire cube_edge_axis = cube_edge_8|cube_edge_9|cube_edge_10|cube_edge_11;
    wire cube_edge_any = cube_edge_front|cube_edge_back|cube_edge_axis;

    reg [23:0]  vidout_rgb;
    reg         vidout_de, vidout_de_1;
    reg         vidout_skip;
    reg         vidout_vs;
    reg         vidout_hs, vidout_hs_1;
    
    reg [9:0]   square_x = 'd135;
    reg [9:0]   square_y = 'd95;

always @(posedge clk_core_12288 or negedge reset_n) begin

    if(~reset_n) begin
    
        x_count <= 0;
        y_count <= 0;
        frame_count <= 0;
        
    end else begin
        vidout_de <= 0;
        vidout_skip <= 0;
        vidout_vs <= 0;
        vidout_hs <= 0;
        
        vidout_hs_1 <= vidout_hs;
        vidout_de_1 <= vidout_de;
        
        // x and y counters
        x_count <= x_count + 1'b1;
        if(x_count == VID_H_TOTAL-1) begin
            x_count <= 0;
            
            y_count <= y_count + 1'b1;
            if(y_count == VID_V_TOTAL-1) begin
                y_count <= 0;
            end
        end
        
        // generate sync 
        if(x_count == 0 && y_count == 0) begin
            // sync signal in back porch
            // new frame
            vidout_vs <= 1;
            frame_count <= frame_count + 1'b1;
        end
        
        // we want HS to occur a bit after VS, not on the same cycle
        if(x_count == 3) begin
            // sync signal in back porch
            // new line
            vidout_hs <= 1;
        end

        // inactive screen areas are black
        vidout_rgb <= 24'h0;
        // generate active video
        if(x_count >= VID_H_BPORCH && x_count < VID_H_ACTIVE+VID_H_BPORCH) begin

            if(y_count >= VID_V_BPORCH && y_count < VID_V_ACTIVE+VID_V_BPORCH) begin
                // data enable. this is the active region of the line
                vidout_de <= 1;
                // True projected 3D wireframe cube.
                vidout_rgb <= 24'h081020;
                if (cube_edge_back) vidout_rgb <= 24'hb04cff;
                if (cube_edge_axis) vidout_rgb <= 24'hffe060;
                if (cube_edge_front) vidout_rgb <= 24'h00e0ff;
                
            end 
        end
    end
end
`endif



//
// Timer-driven GBA Direct Sound, sampled coherently into Pocket I2S.
wire [15:0] gba_audio_left,gba_audio_right;
gba_audio_output audio_output (
    .clk_audio(clk_core_12288),.clk_source(clk_core_39936),
    .reset(~reset_n || ~pll_core_locked_s),
    .sample_left(gba_audio_left),.sample_right(gba_audio_right),
    .mclk(audio_mclk),.lrck(audio_lrck),.dac(audio_dac)
);
///////////////////////////////////////////////


    wire    clk_core_12288;
    wire    clk_core_12288_90deg;
    wire    clk_core_133;
    wire    clk_core_39936;
    wire [287:0] gba_cycle_profile;
    wire [319:0] gba_rom_profile;
    wire [319:0] gba_stall_profile;
    
    wire    pll_core_locked;
    wire    pll_core_locked_s;
gba_startup_reset startup_reset (
    .clk(clk_74a),.core_locked_async(pll_core_locked),
    .memory_locked_async(sdram_clock_locked),.memory_ready(memory_boot_ready),
    .pll_reset(startup_pll_reset),.core_locked(pll_core_locked_s),
    .memory_locked(sdram_clock_locked_s),.memory_reset(memory_startup_reset),
    .startup_complete()
);

mf_pllbase mp1 (
    .refclk         ( clk_74a ),
    .rst            ( startup_pll_reset ),
    
    .outclk_0       ( clk_core_12288 ),
    .outclk_1       ( clk_core_12288_90deg ),
    .outclk_2       ( clk_core_133 ),
    .outclk_3       ( clk_core_39936 ),
    
    .locked         ( pll_core_locked )
);


    
endmodule
