//
// bridge host/target command handler
// 2022 Analogue
//

// mapped to 0xF8xxxxxx on bridge
// the spec is loose enough to allow implementation with either
// block rams and a soft CPU, or simply hard logic with some case statements.
//
// the implementation spec is documented, and depending on your application you
// may want to completely replace this module. this is only one of many 
// possible ways to accomplish the host/target command system and data table.
//
// this module should always be clocked by a direct clock input and never a PLL, 
// because it should report PLL lock status
//

module core_bridge_cmd #(parameter BOOT_DIAGNOSTIC=0, parameter BOOT_DIAGNOSTIC_POLLS=0,
    parameter integer BOOT_STATUS_WAIT_CYCLES=0,
    parameter STATE_LIFECYCLE=0) (

input   wire            clk,
output  reg             reset_n,
// Enabled only by the state-integrated top. The bridge stays live while an
// accepted operation drains; reset and its host acknowledgement follow together.
output  wire            state_reset_request,
input   wire            state_reset_ready,
input   wire            state_transfer_allowed,

input   wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

// all these signals should be synchronous to clk
// add synchronizers if these need to be used in other clock domains
input   wire            status_boot_done,           // assert when PLLs lock and logic is ready
input   wire [4:0]      boot_diagnostic_signals,     // live core PLL, SDRAM PLL/init, save ready/fault
input   wire            debug_event_valid,
input   wire [31:0]     debug_event_data,
output  wire            debug_event_ready,
input   wire            status_setup_done,          // assert when core is happy with what's been loaded into it
input   wire            status_running,             // assert when pocket's taken core out of reset and is running

output  reg             dataslot_requestread,
output  reg     [15:0]  dataslot_requestread_id,
input   wire            dataslot_requestread_ack,
input   wire            dataslot_requestread_ok,

output  reg             dataslot_requestwrite,
output  reg     [15:0]  dataslot_requestwrite_id,
output  reg     [31:0]  dataslot_requestwrite_size,
input   wire            dataslot_requestwrite_ack,
input   wire            dataslot_requestwrite_ok,

output  reg             dataslot_update,
output  reg     [15:0]  dataslot_update_id,
output  reg     [31:0]  dataslot_update_size,

output  reg             dataslot_allcomplete,

output  reg     [31:0]  rtc_epoch_seconds,
output  reg     [31:0]  rtc_date_bcd,
output  reg     [31:0]  rtc_time_bcd,
output  reg             rtc_valid,
output  reg             rtc_update_toggle,

input   wire            savestate_supported,
input   wire    [31:0]  savestate_addr,
input   wire    [31:0]  savestate_size,
input   wire    [31:0]  savestate_maxloadsize,

output  reg             osnotify_inmenu,

output  reg             savestate_start,        // core should detect rising edge on this,
input   wire            savestate_start_ack,    // and then assert ack for at least 1 cycle
input   wire            savestate_start_busy,   // assert constantly while in progress after ack
input   wire            savestate_start_ok,     // assert continuously when done, and clear when new process is started
input   wire            savestate_start_err,    // assert continuously on error, and clear when new process is started

output  reg             savestate_load,
input   wire            savestate_load_ack,
input   wire            savestate_load_busy,
input   wire            savestate_load_ok,
input   wire            savestate_load_err,

input   wire            target_dataslot_read,       // rising edge triggered
input   wire            target_dataslot_write,
input   wire            target_dataslot_getfile,
input   wire            target_dataslot_openfile,

output  reg             target_dataslot_ack,        // asserted upon command start until completion
output  reg             target_dataslot_done,       // asserted upon command finish until next command is issued    
output  reg     [2:0]   target_dataslot_err,        // contains result of command execution. zero is OK

input   wire    [15:0]  target_dataslot_id,         // parameters for each of the read/reload/write commands
input   wire    [31:0]  target_dataslot_slotoffset,
input   wire    [31:0]  target_dataslot_bridgeaddr,
input   wire    [31:0]  target_dataslot_length,

input   wire    [31:0]  target_buffer_param_struct, // bus address of the memory region APF will fetch additional parameter struct from
input   wire    [31:0]  target_buffer_resp_struct,  // bus address of the memory region APF will write its response struct to
                                                    // this should be mapped by the developer, the buffer is not implemented in this file

input   wire    [9:0]   datatable_addr,
input   wire            datatable_wren,
input   wire    [31:0]  datatable_data,
output  wire    [31:0]  datatable_q

);

// handle endianness
    reg     [31:0]  bridge_wr_data_in;
    reg     [31:0]  bridge_rd_data_out;
    
    wire endian_little_s;
synch_3 s01(.i(bridge_endian_little), .o(endian_little_s), .clk(clk), .rise(), .fall());

always @(*) begin
    bridge_rd_data <= endian_little_s ? {
        bridge_rd_data_out[7:0], 
        bridge_rd_data_out[15:8], 
        bridge_rd_data_out[23:16], 
        bridge_rd_data_out[31:24]
    } : bridge_rd_data_out;

    bridge_wr_data_in <= endian_little_s ? {
        bridge_wr_data[7:0], 
        bridge_wr_data[15:8], 
        bridge_wr_data[23:16], 
        bridge_wr_data[31:24]
    } : bridge_wr_data;
end                             

    
// minimalistic approach here - 
// keep the commonly used registers in logic, but data table in BRAM.
// implementation could be changed quite a bit for a more advanced use case

// host

    reg     [31:0]  host_0;
    reg     [31:0]  host_4 = 'h20; // host cmd parameter data at 0x20 
    reg     [31:0]  host_8 = 'h40; // host cmd response data at 0x40 
    
    reg     [31:0]  host_20; // parameter data
    reg     [31:0]  host_24;
    reg     [31:0]  host_28;
    reg     [31:0]  host_2C;
    
    reg     [31:0]  host_40; // response data
    reg     [31:0]  host_44;
    wire [15:0] boot_diagnostic_code;
    reg [3:0] boot_diagnostic_polls=0;
    generate if(BOOT_DIAGNOSTIC==2) begin : live_boot_attribution
        // Minimal probe for nearly-full images: current readiness flags on
        // every poll, without sticky observation registers or poll counters.
        assign boot_diagnostic_code=16'hc000 | {11'b0,boot_diagnostic_signals};
    end else if(BOOT_DIAGNOSTIC) begin : boot_attribution
        reg [4:0] seen=0;
        always @(posedge clk) seen<=seen | boot_diagnostic_signals;
        assign boot_diagnostic_code=BOOT_DIAGNOSTIC_POLLS==0 ?
            (16'ha000 | {6'b0,seen,boot_diagnostic_signals}) :
            (16'hb000 | {4'b0,status_setup_done,status_boot_done,seen,boot_diagnostic_signals});
    end else begin : no_boot_attribution
        assign boot_diagnostic_code=0;
    end endgenerate
    reg     [31:0]  host_48;
    reg     [31:0]  host_4C;    
    
    reg             host_cmd_start;
    reg     [15:0]  host_cmd_startval;
    reg     [15:0]  host_cmd;
    reg     [15:0]  host_resultcode;
    
localparam  [3:0]   ST_IDLE         = 'd0;
localparam  [3:0]   ST_PARSE        = 'd1;
localparam  [3:0]   ST_WORK         = 'd2;
localparam  [3:0]   ST_DONE_OK      = 'd13;
localparam  [3:0]   ST_DONE_CODE    = 'd14;
localparam  [3:0]   ST_DONE_ERR     = 'd15;
    reg     [3:0]   hstate;
assign state_reset_request = STATE_LIFECYCLE && hstate==ST_PARSE && host_cmd==16'h0010;
    localparam BOOT_WAIT_BITS=BOOT_STATUS_WAIT_CYCLES>1 ? $clog2(BOOT_STATUS_WAIT_CYCLES) : 1;
    reg [BOOT_WAIT_BITS-1:0] boot_status_wait=0;
    
// target
    
    reg     [31:0]  target_0;
    reg     [31:0]  target_4 = 'h20; // target cmd parameter data at 0x20 
    reg     [31:0]  target_8 = 'h40; // target cmd response data at 0x40 
    
    reg     [31:0]  target_20; // parameter data
    reg     [31:0]  target_24;
    reg     [31:0]  target_28;
    reg     [31:0]  target_2C;
    
    reg     [31:0]  target_40; // response data
    reg     [31:0]  target_44;
    reg     [31:0]  target_48;
    reg     [31:0]  target_4C;  
    
localparam  [3:0]   TARG_ST_IDLE        = 'd0;
localparam  [3:0]   TARG_ST_READYTORUN  = 'd1;
localparam  [3:0]   TARG_ST_DATASLOTOP  = 'd2;
localparam  [3:0]   TARG_ST_WAITRESULT_RTR  = 'd14;
localparam  [3:0]   TARG_ST_WAITRESULT_DSO  = 'd15;
    reg     [3:0]   tstate;
localparam [3:0] TARG_ST_DEBUG_START = 3, TARG_ST_DEBUG_WAIT = 13;
assign debug_event_ready = tstate == TARG_ST_IDLE &&
    !status_setup_done_queue && !target_dataslot_read_queue &&
    !target_dataslot_write_queue && !target_dataslot_getfile_queue &&
    !target_dataslot_openfile_queue;
    
    reg             status_setup_done_1, status_setup_done_queue;
    reg             target_dataslot_read_1, target_dataslot_read_queue;
    reg             target_dataslot_write_1, target_dataslot_write_queue;
    reg             target_dataslot_getfile_1, target_dataslot_getfile_queue;
    reg             target_dataslot_openfile_1, target_dataslot_openfile_queue;
    
    
initial begin
    hstate = ST_IDLE;
    tstate = TARG_ST_IDLE;
    target_0 = 0;
    reset_n <= 0;
    dataslot_requestread <= 0;
    dataslot_requestwrite <= 0;
    dataslot_update <= 0;
    dataslot_allcomplete <= 0;
    rtc_valid <= 0;
    rtc_update_toggle <= 0;
    savestate_start <= 0;
    savestate_load <= 0;
    osnotify_inmenu <= 0;
    
    status_setup_done_queue <= 0;
    target_dataslot_read_queue <= 0;
    target_dataslot_write_queue <= 0;
    target_dataslot_getfile_queue <= 0;
    target_dataslot_openfile_queue <= 0;
    target_dataslot_ack <= 0;
    target_dataslot_done <= 0;
    target_dataslot_err <= 0;
end
    
always @(posedge clk) begin

    // detect a rising edge on the input signal
    // and flag a queue that will be cleared later
    status_setup_done_1 <= status_setup_done;
    target_dataslot_read_1 <= target_dataslot_read;
    target_dataslot_write_1 <= target_dataslot_write;
    target_dataslot_getfile_1 <= target_dataslot_getfile;
    target_dataslot_openfile_1 <= target_dataslot_openfile;
    
    if(status_setup_done & ~status_setup_done_1) begin
        status_setup_done_queue <= 1;
    end
    if(target_dataslot_read & ~target_dataslot_read_1) begin
        target_dataslot_read_queue <= 1;
    end
    if(target_dataslot_write & ~target_dataslot_write_1) begin
        target_dataslot_write_queue <= 1;
    end
    if(target_dataslot_getfile & ~target_dataslot_getfile_1) begin
        target_dataslot_getfile_queue <= 1;
    end
    if(target_dataslot_openfile & ~target_dataslot_openfile_1) begin
        target_dataslot_openfile_queue <= 1;
    end
    
    
    b_datatable_wren <= 0;
    b_datatable_addr <= bridge_addr >> 2;
        
    if(bridge_wr) begin
        casex(bridge_addr)
        32'hF8xx00xx: begin
            case(bridge_addr[7:0])
            8'h0: begin
                host_0 <= bridge_wr_data_in; // command/status
                // check for command 
                if(bridge_wr_data_in[31:16] == 16'h434D) begin
                    // host wants us to do a command
                    host_cmd_startval <= bridge_wr_data_in[15:0];
                    host_cmd_start <= 1;
                end
            end
            8'h20: host_20 <= bridge_wr_data_in; // parameter data regs
            8'h24: host_24 <= bridge_wr_data_in;
            8'h28: host_28 <= bridge_wr_data_in;
            8'h2C: host_2C <= bridge_wr_data_in;
            endcase
        end
        32'hF8xx10xx: begin
            case(bridge_addr[7:0])
            8'h0: target_0 <= bridge_wr_data_in; // command/status
            8'h4: target_4 <= bridge_wr_data_in; // parameter data pointer
            8'h8: target_8 <= bridge_wr_data_in; // response data pointer
            8'h40: target_40 <= bridge_wr_data_in; // response data regs
            8'h44: target_44 <= bridge_wr_data_in;
            8'h48: target_48 <= bridge_wr_data_in;
            8'h4C: target_4C <= bridge_wr_data_in;
            endcase
        end
        32'hF8xx2xxx: begin
            b_datatable_wren <= 1;
        end
        endcase
    end 
    if(bridge_rd) begin
        casex(bridge_addr)
        32'hF8xx00xx: begin
            case(bridge_addr[7:0])
            8'h0: bridge_rd_data_out <= host_0; // command/status
            8'h4: bridge_rd_data_out <= host_4; // parameter data pointer
            8'h8: bridge_rd_data_out <= host_8; // response data pointer
            8'h40: bridge_rd_data_out <= host_40; // response data regs
            8'h44: bridge_rd_data_out <= host_44;
            8'h48: bridge_rd_data_out <= host_48;
            8'h4C: bridge_rd_data_out <= host_4C;
            endcase
        end
        32'hF8xx10xx: begin
            case(bridge_addr[7:0])
            8'h0: bridge_rd_data_out <= target_0;
            8'h4: bridge_rd_data_out <= target_4;
            8'h8: bridge_rd_data_out <= target_8;
            8'h20: bridge_rd_data_out <= target_20; // parameter data regs
            8'h24: bridge_rd_data_out <= target_24;
            8'h28: bridge_rd_data_out <= target_28;
            8'h2C: bridge_rd_data_out <= target_2C;
            endcase
        end
        32'hF8xx2xxx: begin
            bridge_rd_data_out <= b_datatable_q;
        
        end
        endcase
    end


    
    
    
    // host > target command executer
    case(hstate)
    ST_IDLE: begin
        boot_status_wait <= 0;
    
        dataslot_requestread <= 0;
        dataslot_requestwrite <= 0;
        dataslot_update <= 0;
        savestate_start <= 0;
        savestate_load <= 0;
        
        // there is no queueing. pocket will always make sure any outstanding host
        // commands are finished before starting another
        if(host_cmd_start) begin
            host_cmd_start <= 0;
            // save the command in case it gets clobbered later
            host_cmd <= host_cmd_startval;
            hstate <= ST_PARSE;
        end
    
    end
    ST_PARSE: begin
        // overwrite command semaphore with busy flag
        host_0 <= {16'h4255, host_cmd};
        
        case(host_cmd)
        16'h0000: begin
            // Request Status
            host_resultcode <= 1; // default: booting
            if(BOOT_DIAGNOSTIC && (BOOT_DIAGNOSTIC_POLLS==0 || boot_diagnostic_polls<BOOT_DIAGNOSTIC_POLLS)) begin
                // Deliberately nonstandard result for a dedicated diagnostic
                // image. Pocket records this even when normal boot is stuck.
                // Keep Reset Exit and all datapaths intact: tying reset low
                // would let synthesis remove the design being investigated.
                host_resultcode <= boot_diagnostic_code;
                if(BOOT_DIAGNOSTIC_POLLS!=0) boot_diagnostic_polls<=boot_diagnostic_polls+1'b1;
            end else if(status_boot_done) begin
                host_resultcode <= 2; // setup
                if(status_setup_done) begin
                    host_resultcode <= 3; // idle
                end else if(status_running) begin
                    host_resultcode <= 4; // running
                end 
            end
            // An unlogged host can exhaust its status-poll count before
            // cold memory initialization completes. Keep the documented BU
            // semaphore while waiting, but bound each request: a genuinely
            // stuck readiness gate must still report BOOTING, never IDLE.
            if(status_boot_done || BOOT_DIAGNOSTIC || BOOT_STATUS_WAIT_CYCLES==0 ||
               boot_status_wait==BOOT_STATUS_WAIT_CYCLES-1)
                hstate <= ST_DONE_CODE;
            else boot_status_wait <= boot_status_wait+1'b1;
        end
        16'h0010: begin
            // Reset Enter
            if(!STATE_LIFECYCLE || state_reset_ready)begin
                reset_n <= 0;
                hstate <= ST_DONE_OK;
            end
        end
        16'h0011: begin
            // Reset Exit
            reset_n <= 1;
            hstate <= ST_DONE_OK;
        end
        16'h0080: begin
            // Data slot request read
            if(STATE_LIFECYCLE && !state_transfer_allowed)begin
                host_resultcode<=2;hstate<=ST_DONE_CODE;
            end else begin
            dataslot_allcomplete <= 0;
            dataslot_requestread <= 1;
            dataslot_requestread_id <= host_20[15:0];
            if(dataslot_requestread_ack) begin
                host_resultcode <= 0;
                if(!dataslot_requestread_ok) host_resultcode <= 2;
                hstate <= ST_DONE_CODE;
            end
            end
        end
        16'h0082: begin
            // Data slot request write
            if(STATE_LIFECYCLE && !state_transfer_allowed)begin
                host_resultcode<=2;hstate<=ST_DONE_CODE;
            end else begin
            dataslot_allcomplete <= 0;
            dataslot_requestwrite <= 1;
            dataslot_requestwrite_id <= host_20[15:0];
            dataslot_requestwrite_size <= host_24;
            if(dataslot_requestwrite_ack) begin
                host_resultcode <= 0;
                if(!dataslot_requestwrite_ok) host_resultcode <= 2;
                hstate <= ST_DONE_CODE;
            end
            end
        end
        16'h008A: begin
            // Data slot update (sent on deferload marked slots only)
            if(STATE_LIFECYCLE && !state_transfer_allowed)begin
                host_resultcode<=2;hstate<=ST_DONE_CODE;
            end else begin
            dataslot_update <= 1;
            dataslot_update_id <= host_20[15:0];
            dataslot_update_size <= host_24;
            hstate <= ST_DONE_OK;
            end
        end
        16'h008F: begin
            // Data slot access all complete
            dataslot_allcomplete <= 1;
            hstate <= ST_DONE_OK;
        end
        16'h0090: begin
            // Real-time Clock Data
            // user logic should detect rising edge, it is not continuously updated
            rtc_valid <= 1;
            rtc_update_toggle <= ~rtc_update_toggle;
            rtc_epoch_seconds <= host_20;
            rtc_date_bcd <= host_24;
            rtc_time_bcd <= host_28;
            hstate <= ST_DONE_OK;
        end
        16'h00A0: begin
            // Savestate: Start/Query
            host_40 <= savestate_supported; 
            host_44 <= savestate_addr;
            host_48 <= savestate_size;
            
            host_resultcode <= 0;
            if(savestate_start_busy) host_resultcode <= 1;
            if(savestate_start_ok) host_resultcode <= 2;
            if(savestate_start_err) host_resultcode <= 3;
            
            if(host_20[0]) begin
                // Request Start!
                savestate_start <= 1;
                // stay in this state until ack'd
                if(savestate_start_ack) begin
                    hstate <= ST_DONE_CODE;
                end
            end else begin
                hstate <= ST_DONE_CODE;
            end
        end
        16'h00A4: begin
            // Savestate: Load/Query
            host_40 <= savestate_supported; 
            host_44 <= savestate_addr;
            host_48 <= savestate_maxloadsize;
            
            host_resultcode <= 0;
            if(savestate_load_busy) host_resultcode <= 1;
            if(savestate_load_ok) host_resultcode <= 2;
            if(savestate_load_err) host_resultcode <= 3;
            
            if(host_20[0]) begin
                // Request Load!
                savestate_load <= 1;
                // stay in this state until ack'd
                if(savestate_load_ack) begin
                    hstate <= ST_DONE_CODE;
                end
            end else begin
                hstate <= ST_DONE_CODE;
            end
        end
        16'h00B0: begin
            // OS Notify: Menu State
            osnotify_inmenu <= host_20[0];
            hstate <= ST_DONE_OK;
        end
        default: begin
            hstate <= ST_DONE_ERR;
        end
        endcase
    end
    ST_WORK: begin
        hstate <= ST_IDLE;
    end
    ST_DONE_OK: begin
        host_0 <= 32'h4F4B0000; // result code 0
        hstate <= ST_IDLE;
    end
    ST_DONE_CODE: begin
        host_0 <= {16'h4F4B, host_resultcode};
        hstate <= ST_IDLE;
    end
    ST_DONE_ERR: begin
        host_0 <= 32'h4F4BFFFF; // result code FFFF = unknown command
        hstate <= ST_IDLE;
    end
    endcase
    
    
    // target > host command executer
    case(tstate)
    TARG_ST_IDLE: begin
    
        target_dataslot_ack <= 0;
    
        if(status_setup_done_queue) begin
            status_setup_done_queue <= 0;
            tstate <= TARG_ST_READYTORUN;
            
        end else if(target_dataslot_read_queue) begin
            target_dataslot_read_queue <= 0;
            target_0[15:0] <= 16'h0180;
            
            target_20 <= target_dataslot_id;
            target_24 <= target_dataslot_slotoffset;
            target_28 <= target_dataslot_bridgeaddr;
            target_2C <= target_dataslot_length;
            
            tstate <= TARG_ST_DATASLOTOP;
            
        end else if(target_dataslot_write_queue) begin
            target_dataslot_write_queue <= 0;
            target_0[15:0] <= 16'h0184;
            
            target_20 <= target_dataslot_id;
            target_24 <= target_dataslot_slotoffset;
            target_28 <= target_dataslot_bridgeaddr;
            target_2C <= target_dataslot_length;
            
            tstate <= TARG_ST_DATASLOTOP;
            
        end else if(target_dataslot_getfile_queue) begin
            target_dataslot_getfile_queue <= 0;
            target_0[15:0] <= 16'h0190;
            
            target_20 <= target_dataslot_id;
            target_24 <= target_buffer_resp_struct; // pointer to the bram that will hold the response struct
                                                    // which will contain the requested filename before command completion
            tstate <= TARG_ST_DATASLOTOP;
            
        end else if(target_dataslot_openfile_queue) begin
            target_dataslot_openfile_queue <= 0;
            target_0[15:0] <= 16'h0192;
            
            target_20 <= target_dataslot_id;
            target_24 <= target_buffer_param_struct; // pointer to the bram that will hold the parameter struct
                                                    // which must contain the desired filename and flag/size before command execution
            tstate <= TARG_ST_DATASLOTOP;
        end else if(debug_event_valid) begin
            target_0[15:0] <= 16'h0152;
            target_20 <= debug_event_data;
            tstate <= TARG_ST_DEBUG_START;
        end
    end
    TARG_ST_DEBUG_START: begin
        target_0[31:16] <= 16'h636D;
        tstate <= TARG_ST_DEBUG_WAIT;
    end
    TARG_ST_DEBUG_WAIT: begin
        if(target_0[31:16] == 16'h6F6B) tstate <= TARG_ST_IDLE;
    end
    TARG_ST_READYTORUN: begin
        target_0 <= 32'h636D_0140;
        tstate <= TARG_ST_WAITRESULT_RTR;
    end
    TARG_ST_DATASLOTOP: begin
        target_0[31:16] <= 16'h636D;
        
        target_dataslot_done <= 0;
        target_dataslot_err <= 0;
        tstate <= TARG_ST_WAITRESULT_DSO;
    end
    TARG_ST_WAITRESULT_DSO: begin
        if(target_0[31:16] == 16'h6275) begin
            target_dataslot_ack <= 1;
        end
        if(target_0[31:16] == 16'h6F6B) begin
            // done
            // save result code
            target_dataslot_err <= target_0[2:0];
            // assert done
            target_dataslot_done <= 1;
            tstate <= TARG_ST_IDLE;
        end
    end
    TARG_ST_WAITRESULT_RTR: begin
        if(target_0[31:16] == 16'h6F6B) begin
            // done
            tstate <= TARG_ST_IDLE;
        end
    
    end
    endcase
    

end

    wire    [31:0]  b_datatable_q;
    reg     [9:0]   b_datatable_addr;
    reg             b_datatable_wren;

mf_datatable idt (
    .address_a      ( datatable_addr ),
    .address_b      ( b_datatable_addr ),
    .clock_a        ( clk ),
    .clock_b        ( clk ),
    .data_a         ( datatable_data ),
    .data_b         ( bridge_wr_data_in ),
    .wren_a         ( datatable_wren ),
    .wren_b         ( b_datatable_wren ),
    .q_a            ( datatable_q ),
    .q_b            ( b_datatable_q )
);


endmodule
