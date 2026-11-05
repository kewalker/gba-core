// Integration boundary for the existing guest bus, host RTC link and shared
// SDRAM controller. Normal gameplay has no requests through this datapath.
// The shared arbiter must use background mode: state EWRAM copies still travel
// through its existing RAM client while staging uses its bounded state client.
// Runtime reload/reset must first cancel and drain this job while guest and
// memory clocks/endpoints remain live. Assert reset only when idle or after
// failed_stopped (which guarantees accepted state transactions have drained).
// In particular, do not independently reset the guest CDC handshake epoch.
module gba_state_machine #(
    parameter integer CRC_BITS=1,
    parameter integer TIMEOUT_CYCLES=7425000
)(
    input wire host_clk,guest_clk,reset,start,restore,cancel,
    input wire [31:0] rom_crc,rom_bytes,bios_crc,
    output wire busy,done,failed_stopped,
    output wire [3:0] error_code,
    input wire guest_transactions_idle,resume_ready,
    output wire resume_prepare,state_cpu_request,state_dma_request,state_hold,
    input wire state_cpu_quiescent,state_dma_quiescent,state_held,
    output wire state_reg_write,
    output wire [15:0] state_reg_addr,
    output wire [31:0] state_reg_wdata,
    input wire state_reg_valid,
    input wire [31:0] state_reg_rdata,
    output wire state_bulk_valid,state_bulk_write,state_bulk_response_ready,
    output wire [31:0] state_bulk_addr,state_bulk_wdata,
    input wire state_bulk_ready,state_bulk_response,state_bulk_error,
    input wire [31:0] state_bulk_rdata,
    output wire state_save_raw_access,state_save_raw_eeprom,save_write,save_read,
    output wire [14:0] save_addr,
    output wire [31:0] save_wdata,
    input wire state_save_raw_idle,state_save_raw_done,save_fault,
    input wire [31:0] save_rdata,
    output wire rtc_lock,rtc_start,rtc_restore,rtc_word_write,
    output wire [1:0] rtc_word_index,
    output wire [31:0] rtc_word_data,
    input wire rtc_ready,rtc_done,rtc_error,
    input wire [31:0] rtc_word_rdata,
    input wire host_valid,host_write,host_response_ready,
    input wire [31:0] host_offset,host_wdata,
    output wire host_ready,host_response,host_error,
    output wire [31:0] host_rdata,
    output wire memory_valid,memory_write,memory_response_ready,
    output wire [24:0] memory_addr,
    output wire [31:0] memory_wdata,
    output wire [3:0] memory_byteena,
    input wire memory_ready,memory_response,
    input wire [63:0] memory_rdata
);
    wire freeze_start,freeze_finish,frozen,freeze_done,freeze_request,cpu_hold,domain_frozen;
    wire [2:0] freeze_error;
    wire prepare_hold,freeze_needs_prepare;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
        reg [2:0] quiescent_sync=0;
    always @(posedge host_clk)begin
        if(reset)quiescent_sync<=0;
        else quiescent_sync<={quiescent_sync[1:0],state_cpu_quiescent && state_dma_quiescent && guest_transactions_idle};
    end
    gba_state_freeze #(.DOMAINS(1),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) freeze(
        .clk(host_clk),.reset,.start(freeze_start),.finish(freeze_finish),.cancel(1'b0),
        .cpu_quiescent(quiescent_sync[2]),.transactions_drained(quiescent_sync[2]),.resume_ready,
        .domain_frozen,.cpu_hold,.drain_request(),.freeze_request,.frozen,.busy(),.prepare_required(freeze_needs_prepare),.done(freeze_done),.error_code(freeze_error));
    gba_state_freeze_domain domain(.clk(guest_clk),.reset,.request(freeze_request),
        .idle(state_cpu_quiescent && state_dma_quiescent && guest_transactions_idle),
        .hold_request(cpu_hold),.frozen(domain_frozen),.execution_hold(state_hold),.prepare_hold);
    assign state_cpu_request=prepare_hold;
    assign state_dma_request=prepare_hold;
    wire guest_valid,guest_write,guest_response_ready,guest_ready,guest_response,guest_error;
    wire [1:0] guest_target;
    wire [31:0] guest_addr,guest_wdata,guest_rdata;
    wire stage_valid,stage_write,stage_response_ready,stage_ready,stage_response,stage_error,stage_lock,stage_locked;
    wire [31:0] stage_addr,stage_wdata,stage_rdata;
    gba_state_machine_job #(.CRC_BITS(CRC_BITS),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) job(
        .clk(host_clk),.reset,.start,.restore,.cancel,.rom_crc,.rom_bytes,.bios_crc,
        .busy,.done,.error_code,.failed_stopped,.staging_lock(stage_lock),.staging_locked(stage_locked),
        .rtc_lock,.resume_prepare,.freeze_start,.freeze_finish,.frozen,.freeze_done,.freeze_needs_prepare,.freeze_error,.resume_ready,
        .rtc_start,.rtc_restore,.rtc_ready,.rtc_done,.rtc_error,
        .guest_valid,.guest_write,.guest_response_ready,.guest_target,.guest_addr,.guest_wdata,
        .guest_ready,.guest_response,.guest_error,.guest_rdata,
        .staging_valid(stage_valid),.staging_write(stage_write),.staging_response_ready(stage_response_ready),
        .staging_addr(stage_addr),.staging_wdata(stage_wdata),.staging_ready(stage_ready),
        .staging_response(stage_response),.staging_error(stage_error),.staging_rdata(stage_rdata));
    gba_state_machine_access #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) access(
        .host_clk,.guest_clk,.reset,.host_held(frozen),.guest_held(state_held),
        .request_valid(guest_valid),.request_write(guest_write),.response_ready(guest_response_ready),
        .request_target(guest_target),.request_addr(guest_addr),.request_wdata(guest_wdata),
        .request_ready(guest_ready),.response_valid(guest_response),.response_error(guest_error),.response_rdata(guest_rdata),
        .register_write(state_reg_write),.register_addr(state_reg_addr),.register_wdata(state_reg_wdata),
        .register_valid(state_reg_valid),.register_rdata(state_reg_rdata),
        .ram_valid(state_bulk_valid),.ram_write(state_bulk_write),.ram_response_ready(state_bulk_response_ready),
        .ram_addr(state_bulk_addr),.ram_wdata(state_bulk_wdata),.ram_ready(state_bulk_ready),
        .ram_response(state_bulk_response),.ram_error(state_bulk_error),.ram_rdata(state_bulk_rdata),
        .raw_access(state_save_raw_access),.raw_eeprom(state_save_raw_eeprom),.raw_write(save_write),.raw_read(save_read),
        .raw_addr(save_addr),.raw_wdata(save_wdata),.raw_idle(state_save_raw_idle),.raw_done(state_save_raw_done),
        .raw_fault(save_fault),.raw_rdata(save_rdata),
        .rtc_ready,.rtc_word_write,.rtc_word_index,.rtc_word_data,.rtc_word_rdata);
    gba_state_staging staging(.clk(host_clk),.reset,.lock_request(stage_lock),.locked(stage_locked),.idle(),
        .host_valid,.host_write,.host_offset,.host_wdata,.host_ready,.host_response,.host_response_ready,.host_rdata,.host_error,
        .core_valid(stage_valid),.core_write(stage_write),.core_offset(stage_addr),.core_wdata(stage_wdata),
        .core_ready(stage_ready),.core_response(stage_response),.core_response_ready(stage_response_ready),.core_rdata(stage_rdata),.core_error(stage_error),
        .memory_valid,.memory_write,.memory_addr,.memory_wdata,.memory_byteena,.memory_ready,.memory_response,.memory_rdata,.memory_response_ready);
endmodule
