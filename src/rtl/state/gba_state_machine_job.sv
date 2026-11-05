// Whole-machine capture/restore sequencer. One word copier and one CRC engine
// serve every section. Ports are host-clock ready/response interfaces; route
// targets 0/1 through the existing single CDC endpoint, 2 to raw save access,
// and 3 to the existing RTC persistence payload (not a second calendar).
// A failed restore after its first accepted write remains frozen until reset.
module gba_state_machine_job #(
    parameter integer CRC_BITS=1,
    parameter integer TIMEOUT_CYCLES=7425000
)(
    input wire clk,reset,start,restore,cancel,
    input wire [31:0] rom_crc,rom_bytes,bios_crc,
    output wire busy,staging_lock,rtc_lock,resume_prepare,failed_stopped,
    output reg done,
    output reg [3:0] error_code,
    input wire staging_locked,
    output reg freeze_start,freeze_finish,
    input wire frozen,freeze_done,freeze_needs_prepare,
    input wire [2:0] freeze_error,
    input wire resume_ready,
    output reg rtc_start,
    output wire rtc_restore,
    input wire rtc_ready,rtc_done,rtc_error,
    output wire guest_valid,guest_write,guest_response_ready,
    output reg [1:0] guest_target,
    output reg [31:0] guest_addr,
    output wire [31:0] guest_wdata,
    input wire guest_ready,guest_response,guest_error,
    input wire [31:0] guest_rdata,
    output wire staging_valid,staging_write,staging_response_ready,
    output wire [31:0] staging_addr,staging_wdata,
    input wire staging_ready,staging_response,staging_error,
    input wire [31:0] staging_rdata
);
    localparam IDLE=0,LOCK=1,VALIDATE_START=2,VALIDATE_WAIT=3,
        FREEZE_START=4,FREEZE_WAIT=5,RTC_START=6,RTC_WAIT=7,
        META_ISSUE=8,META_WAIT=9,COPY_START=10,COPY_WAIT=11,
        BODY_START=12,BODY_WAIT=13,HEADER_START=14,HEADER_WAIT=15,
        WARM_ISSUE=16,WARM_WAIT=17,PREPARE=18,RELEASE=19,FAULT=20;
    reg [4:0] phase;
    reg direction,aborting,mutated,freeze_started,capture_check,recovering;
    reg [5:0] meta_index;
    reg [1:0] meta_mode; // complete header/table, body CRC, header CRC
    reg [31:0] held_rom_crc,held_rom_bytes,held_bios_crc;
    wire copier_done,copier_busy,copy_partial;
    wire [2:0] copy_error;
    wire copy_guest_valid,copy_guest_write,copy_guest_response_ready;
    wire [31:0] copy_guest_addr,copy_guest_wdata;
    wire copy_stage_valid,copy_stage_write,copy_stage_response_ready;
    wire [31:0] copy_stage_addr,copy_stage_wdata;
    wire val_done,val_valid,val_busy,val_read;
    wire [31:0] val_addr,scan_crc;
    wire [3:0] val_error;
    reg val_pending,val_transport_error;
    wire validating=phase==VALIDATE_WAIT || phase==BODY_WAIT || phase==HEADER_WAIT;
    wire copying=phase==COPY_WAIT;
    wire warming=phase==WARM_ISSUE || phase==WARM_WAIT;
    assign busy=phase!=IDLE;
    assign staging_lock=busy;
    assign rtc_lock=busy;
    assign resume_prepare=phase==PREPARE || phase==RELEASE;
    assign failed_stopped=phase==FAULT;
    assign rtc_restore=direction;
    function automatic [31:0] section_size(input [3:0] section);
        case(section)
            0:section_size=776;1:section_size=262144;2:section_size=32768;
            3:section_size=98304;4,5:section_size=1024;
            6:section_size=131072;7:section_size=8192;8:section_size=16;
            default:section_size=0;
        endcase
    endfunction
    function automatic [31:0] section_offset(input [3:0] section);
        case(section)
            0:section_offset=208;1:section_offset=984;2:section_offset=263128;
            3:section_offset=295896;4:section_offset=394200;5:section_offset=395224;
            6:section_offset=396248;7:section_offset=527320;8:section_offset=535512;
            default:section_offset=0;
        endcase
    endfunction
    reg [31:0] metadata;
    wire [3:0] metadata_section=(meta_index-16)>>2;
    always @*begin
        metadata=0;
        case(meta_index)
            0:metadata=32'h534b4247;1:metadata=32'h00010000;
            2:metadata=208;3:metadata=535528;
            4:metadata=held_rom_crc;5:metadata=held_rom_bytes;
            6:metadata=held_bios_crc;
`ifdef GBK_GAMEPAK_PREFETCH
            7:metadata=32'h47465332;
`else
            7:metadata=32'h47465331;
`endif
            8:metadata=9;
            default:if(meta_index>=16)case(meta_index[1:0])
                0:metadata={28'd0,metadata_section}+1;
                1:metadata=section_offset(metadata_section);
                2:metadata=section_size(metadata_section);
                default:metadata=0;
            endcase
        endcase
        if(meta_mode!=0)metadata=scan_crc;
    end
    // The copy descriptor is a virtual, contiguous payload. Translate the held
    // word address here; the copier retains it through the real response.
    reg [19:0] section_begin;
    reg [7:0] guest_region;
    reg [1:0] copy_target;
    wire [19:0] virtual_offset=copy_guest_addr[19:0];
    wire [19:0] section_offset_bytes=virtual_offset-section_begin;
    always @*begin
        copy_target=1;guest_region=0;section_begin=0;
        if(virtual_offset<776)copy_target=0;
        else if(virtual_offset<262920)begin guest_region=2;section_begin=776;end
        else if(virtual_offset<295688)begin guest_region=3;section_begin=262920;end
        else if(virtual_offset<393992)begin guest_region=6;section_begin=295688;end
        else if(virtual_offset<395016)begin guest_region=5;section_begin=393992;end
        else if(virtual_offset<396040)begin guest_region=7;section_begin=395016;end
        else if(virtual_offset<527112)begin copy_target=2;guest_region=14;section_begin=396040;end
        else if(virtual_offset<535304)begin copy_target=2;guest_region=13;section_begin=527112;end
        else begin copy_target=3;section_begin=535304;end
    end
    always @*begin
        guest_target=copy_target;
        // Register payload begins at virtual zero. RTC is exactly four words
        // at virtual 535304 (low nibble 8), so its two-bit index needs no
        // full section subtraction/range chain before the RTC write enable.
        guest_addr=copy_target==0 ? {12'd0,virtual_offset}>>2 :
            copy_target==3 ? {30'd0,virtual_offset[3]^1'b1,virtual_offset[2]} :
            {guest_region,4'd0,section_offset_bytes};
        if(warming)begin guest_target=0;guest_addr=255;end
    end
    assign guest_valid=copying ? copy_guest_valid : phase==WARM_ISSUE;
    assign guest_write=copying && copy_guest_write;
    assign guest_wdata=copy_guest_wdata;
    assign guest_response_ready=copying ? copy_guest_response_ready : phase==WARM_WAIT;
    assign staging_valid=copying ? copy_stage_valid :
        validating ? val_read && !val_pending : phase==META_ISSUE;
    assign staging_write=copying ? copy_stage_write : !validating;
    assign staging_addr=copying ? copy_stage_addr : validating ? val_addr : {24'd0,meta_index,2'b00};
    assign staging_wdata=copying ? copy_stage_wdata : metadata;
    assign staging_response_ready=copying ? copy_stage_response_ready :
        validating ? val_pending : phase==META_WAIT;
    gba_state_word_copy #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.GUEST_ADDRESS_BITS(20)) copier(
        .clk,.reset,.start(phase==COPY_START),.restore(direction),.cancel(cancel || aborting),
        .held(frozen),.staging_locked,.image_validated(direction),
        .guest_base(32'd0),.staging_offset(32'd208),.word_count(32'd133830),
        .busy(copier_busy),.done(copier_done),.partial_restore(copy_partial),.error_code(copy_error),
        .guest_valid(copy_guest_valid),.guest_write(copy_guest_write),.guest_response_ready(copy_guest_response_ready),
        .guest_addr(copy_guest_addr),.guest_wdata(copy_guest_wdata),
        .guest_ready(guest_ready && copying),.guest_response(guest_response && copying),.guest_error,.guest_rdata,
        .staging_valid(copy_stage_valid),.staging_write(copy_stage_write),.staging_response_ready(copy_stage_response_ready),
        .staging_addr(copy_stage_addr),.staging_wdata(copy_stage_wdata),
        .staging_ready(staging_ready && copying),.staging_response(staging_response && copying),.staging_error,.staging_rdata);
    gba_state_machine_validator #(.CRC_BITS(CRC_BITS),.READ_TIMEOUT(TIMEOUT_CYCLES),.LATCH_IDENTITY(0)) validator(
        .clk,.reset,.start(phase==VALIDATE_START || phase==BODY_START || phase==HEADER_START),
        .scan_only(phase==BODY_START || phase==HEADER_START),
        .scan_begin(phase==BODY_START ? 32'd64 : 32'd0),
        .scan_bytes(phase==BODY_START ? 32'd535464 : 32'd60),.scan_crc,
        .rom_crc(held_rom_crc),.rom_bytes(held_rom_bytes),.bios_crc(held_bios_crc),
        .read_req(val_read),.read_addr(val_addr),.read_valid(val_pending && staging_response),.read_data(staging_rdata),
        .busy(val_busy),.done(val_done),.valid(val_valid),.error_code(val_error));
    task fail(input [3:0] code);
        begin
            error_code<=code;
            if(mutated)phase<=FAULT;
            else if(freeze_started)begin recovering<=1;phase<=WARM_ISSUE;end
            else begin phase<=IDLE;done<=1;end
        end
    endtask
    always @(posedge clk)begin
        done<=0;freeze_start<=0;freeze_finish<=0;rtc_start<=0;
        if(reset)begin
            phase<=IDLE;direction<=0;aborting<=0;mutated<=0;freeze_started<=0;capture_check<=0;recovering<=0;
            meta_index<=0;meta_mode<=0;error_code<=0;done<=0;
            held_rom_crc<=0;held_rom_bytes<=0;held_bios_crc<=0;
            val_pending<=0;val_transport_error<=0;
        end else begin
            if(busy && cancel)aborting<=1;
            if(copying && guest_valid && guest_ready && guest_write)mutated<=1;
            if(validating)begin
                if(staging_valid && staging_ready)val_pending<=1;
                if(val_pending && staging_response)begin
                    val_pending<=0;
                    if(staging_error)val_transport_error<=1;
                end
            end
            case(phase)
                IDLE:if(start)begin
                    direction<=restore;aborting<=0;mutated<=0;freeze_started<=0;capture_check<=0;recovering<=0;
                    held_rom_crc<=rom_crc;held_rom_bytes<=rom_bytes;held_bios_crc<=bios_crc;
                    error_code<=0;phase<=LOCK;
                end
                LOCK:if(cancel || aborting)fail(8);
                    else if(staging_locked)phase<=direction ? VALIDATE_START : FREEZE_START;
                VALIDATE_START:begin val_transport_error<=0;phase<=VALIDATE_WAIT;end
                VALIDATE_WAIT:if(val_done)begin
                    if(!val_valid || val_transport_error)fail(val_transport_error ? 4'd9 : val_error);
                    else if(cancel || aborting)fail(8);
                    else phase<=capture_check ? WARM_ISSUE : FREEZE_START;
                end
                FREEZE_START:begin freeze_start<=1;freeze_started<=1;phase<=FREEZE_WAIT;end
                FREEZE_WAIT:if(freeze_done)begin
                        freeze_started<=0;error_code<=10;phase<=IDLE;done<=1;
                    end
                    else if(freeze_error!=0 && freeze_needs_prepare)begin
                        // No register/FIFO reads or restore writes have begun.
                        // A release fault still needs the real display barrier;
                        // waiting for freeze_done first deadlocks that barrier.
                        error_code<=10;recovering<=1;phase<=PREPARE;
                    end
                    else if(frozen)begin
                        if(cancel || aborting)fail(8);
                        else phase<=direction ? COPY_START : RTC_START;
                    end
                RTC_START:if(cancel || aborting)fail(8);
                    else if(rtc_ready)begin rtc_start<=1;phase<=RTC_WAIT;end
                RTC_WAIT:if(rtc_done)begin
                    if(rtc_error)fail(11);
                    else if(cancel || aborting)fail(8);
                    else if(direction)phase<=WARM_ISSUE;
                    else begin meta_index<=0;meta_mode<=0;phase<=META_ISSUE;end
                end
                META_ISSUE:if(cancel || aborting)fail(8);
                    else if(staging_ready)phase<=META_WAIT;
                META_WAIT:if(staging_response)begin
                    if(staging_error)fail(9);
                    else if(cancel || aborting)fail(8);
                    else if(meta_mode==1)phase<=HEADER_START;
                    else if(meta_mode==2)begin capture_check<=1;phase<=VALIDATE_START;end
                    else if(meta_index==51)phase<=COPY_START;
                    else begin meta_index<=meta_index+1'b1;phase<=META_ISSUE;end
                end
                COPY_START:phase<=COPY_WAIT;
                COPY_WAIT:if(copier_done)begin
                    if(copy_error!=0)fail(cancel || aborting ? 4'd8 : 4'd12);
                    else if(cancel || aborting)fail(8);
                    else phase<=direction ? RTC_START : BODY_START;
                end
                BODY_START:begin val_transport_error<=0;phase<=BODY_WAIT;end
                HEADER_START:begin val_transport_error<=0;phase<=HEADER_WAIT;end
                BODY_WAIT,HEADER_WAIT:if(val_done)begin
                    if(!val_valid || val_transport_error)fail(9);
                    else if(cancel || aborting)fail(8);
                    else begin
                        meta_index<=phase==BODY_WAIT ? 14 : 15;
                        meta_mode<=phase==BODY_WAIT ? 1 : 2;phase<=META_ISSUE;
                    end
                end
                WARM_ISSUE:if(guest_ready)phase<=WARM_WAIT;
                WARM_WAIT:if(guest_response)begin
                    if(guest_error)begin error_code<=13;phase<=FAULT;end
                    else if(!recovering && (cancel || aborting))fail(8);
                    else phase<=guest_rdata[0] ? PREPARE : WARM_ISSUE;
                end
                PREPARE:if(resume_ready)begin freeze_finish<=1;phase<=RELEASE;end
                RELEASE:if(freeze_done)begin
                    if(freeze_error!=0 && error_code==0)error_code<=10;
                    phase<=IDLE;done<=1;freeze_started<=0;
                end
                // Keep freeze and staging ownership on every failed partial
                // restore. Only an explicit machine reset may clear this state.
                FAULT:begin end
                default:fail(15);
            endcase
        end
    end
endmodule
