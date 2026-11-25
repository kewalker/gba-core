// Import a byte-wide save into the normal save SRAM, then sync on request.
// The caller locks guest writes and owns the raw SRAM port during writeback.
// The pre-write image is fetched from the cart for SD backup.
//
// LARGE_SAVE: ADDRESS_BITS covers 128 KiB Flash; large_save selects the full
// range, otherwise Flash uses half and a linear (SRAM) save a quarter. The
// Flash engine below switches banks; the chip ID must match the capacity.
//
// FALLBACK_SAVE: when a commit is refused or fails after its pre-write backup
// (unsupported chip, I/O or verify error), the working save is written to SD
// through the same backup writer (backup_fallback names it CODE-unsaved.sav),
// because Play Cartridge has no SD save slot of its own.
module gba_gamepak_save #(
    parameter integer ADDRESS_BITS=16,
    parameter integer SECTOR_BITS=12,
    parameter bit LINEAR_SAVE=0,
    parameter bit REUSE_BACKUP=0,
    parameter bit LARGE_SAVE=0,
    parameter integer BACKUP_CHUNK_BYTES=256,
    parameter bit FALLBACK_SAVE=0
)(
    input wire clk,enable,import_start,commit_start,locked,
    input wire linear_save,
    input wire large_save,
    input wire backup_ready,backup_error,
    input wire backup_fill,
    input wire [ADDRESS_BITS-1:0] backup_offset,
    output wire backup_filled,backup_chunk_error,
    output wire backup_request,write_lock,reset_block,
    output wire backup_fallback,
    output reg busy=0,
    output reg import_done=0,
    output reg import_ok=0,
    output reg [2:0] result=0,
    output wire flash_request,
    output reg [1:0] flash_operation,
    output wire [ADDRESS_BITS-1:0] flash_address,
    output wire [7:0] flash_wdata,
    input wire flash_ready,flash_done,flash_error,
    input wire [7:0] flash_rdata,
    input wire [15:0] flash_id,
    output wire raw_read,raw_write,
    output wire [ADDRESS_BITS-3:0] raw_address,
    output wire [31:0] raw_wdata,
    input wire raw_idle,raw_done,raw_error,
    input wire [31:0] raw_rdata,
    input wire backup_read,
    input wire [ADDRESS_BITS-3:0] backup_word,
    output reg [31:0] backup_rdata
);
    localparam READ=0, IDENTIFY=1, PROGRAM=2, ERASE=3;
    localparam IDLE=0, LOCK=1, REQUEST=2, FLASH_WAIT=3, SRAM_WRITE=4,
               SRAM_READ=5, SRAM_WAIT=6, COMPARE=7, BACKUP=8, PROGRAM_BYTE=9,
               BACKUP_CHUNK=10, BACKUP_IO_ERROR=11, FALLBACK_STORE=12, FALLBACK_WAIT=13;
    localparam IMPORT=0, SNAPSHOT=1, SCAN=2, REWRITE=3, VERIFY=4, CHECK_ID=5, FALLBACK=6;
    localparam [2:0] SUCCESS=1, UNSUPPORTED=2, IO_ERROR=3, VERIFY_ERROR=4, BACKUP_ERROR=5;
    wire linear=LINEAR_SAVE && linear_save;
    reg [3:0] phase=IDLE;
    reg [2:0] pass;
    reg [ADDRESS_BITS-1:0] cursor;
    reg [31:0] word_data;
    reg changed;
    reg backup_verified=0;
    reg [2:0] fallback_code=0;
    wire in_fallback=FALLBACK_SAVE && pass==FALLBACK;
    wire [7:0] desired=word_data[7:0];
    wire [ADDRESS_BITS-SECTOR_BITS-1:0] sector=cursor[ADDRESS_BITS-1:SECTOR_BITS];
    wire sector_last=&cursor[SECTOR_BITS-1:0];
    // Capacity is the full range shifted down by 0, 1 or 2 address bits.
    wire large_mode=LARGE_SAVE && large_save;
    wire [1:0] shrink=LARGE_SAVE ? (large_mode ? 2'd0 : linear ? 2'd2 : 2'd1) : {1'b0,linear};
    wire last_byte=cursor==({ADDRESS_BITS{1'b1}} >> shrink);
    wire last_sector=sector==({(ADDRESS_BITS-SECTOR_BITS){1'b1}} >> shrink);
    // 64 KiB: Macronix MX29L512, SST 39VF512, Panasonic MN63F805.
    // 128 KiB: Macronix MX29L010, Sanyo LE26FV10N1TS (banked).
    wire identify_ok=large_mode ? (flash_id==16'h09c2 || flash_id==16'h1362) :
        (flash_id==16'h1cc2 || flash_id==16'hd4bf || (LARGE_SAVE && flash_id==16'h1b32));
    wire [31:0] imported_word={flash_rdata,word_data[31:8]};
    localparam integer CHUNK_BITS=$clog2(BACKUP_CHUNK_BYTES);
    (* ramstyle="M10K, no_rw_check" *) reg [31:0] archive_chunk[0:BACKUP_CHUNK_BYTES/4-1];
    always @(posedge clk)begin
        if(backup_read)backup_rdata<=archive_chunk[backup_word[CHUNK_BITS-3:0]];
        if(phase==FLASH_WAIT && flash_done && pass==SNAPSHOT && flash_operation==READ &&
            cursor[1:0]==3)archive_chunk[cursor[CHUNK_BITS-1:2]]<=imported_word;
        else if(FALLBACK_SAVE && phase==FALLBACK_STORE)archive_chunk[cursor[CHUNK_BITS-1:2]]<=word_data;
    end
    // The fallback first drops its request until the writer has left the
    // pre-write run's ready/error state, so that result is never reused.
    assign backup_request=busy && (pass==SNAPSHOT || in_fallback) && phase!=LOCK && phase!=FALLBACK_WAIT;
    assign backup_fallback=in_fallback;
    assign backup_filled=phase==BACKUP_CHUNK;
    assign backup_chunk_error=phase==BACKUP_IO_ERROR;
    assign write_lock=busy && pass!=IMPORT;
    assign reset_block=busy && (pass==CHECK_ID || pass==SCAN || pass==REWRITE || pass==VERIFY || in_fallback);
    assign flash_request=enable && phase==REQUEST;
    assign flash_address=cursor;
    assign flash_wdata=desired;
    assign raw_read=enable && phase==SRAM_READ && raw_idle;
    assign raw_write=enable && phase==SRAM_WRITE && raw_idle;
    assign raw_address=cursor[ADDRESS_BITS-1:2];
    assign raw_wdata=word_data;

    task finish(input [2:0] code);
        begin
            result<=code;busy<=0;phase<=IDLE;
            if(pass==IMPORT)begin import_done<=1;import_ok<=code==SUCCESS;end
        end
    endtask
    // After a verified pre-write backup, a refused or failed commit saves the
    // working copy to SD instead of ending with the session unsaved.
    task fail(input [2:0] code);
        begin
            if(FALLBACK_SAVE && pass!=IMPORT && pass!=SNAPSHOT && pass!=FALLBACK)begin
                fallback_code<=code;pass<=FALLBACK;phase<=FALLBACK_WAIT;
            end else finish(code);
        end
    endtask
    task access_flash(input [1:0] op);
        begin flash_operation<=op;phase<=REQUEST;end
    endtask
    task start_sector(input [2:0] mode,input [ADDRESS_BITS-SECTOR_BITS-1:0] number);
        begin
            pass<=mode;cursor<={number,{SECTOR_BITS{1'b0}}};
            changed<=0;phase<=SRAM_READ;
        end
    endtask
    task next_sector;
        begin
            if(last_sector)finish(SUCCESS);
            else start_sector(SCAN,sector+1'b1);
        end
    endtask
    task advance_byte;
        begin
            cursor<=cursor+1'b1;
            word_data<={8'd0,word_data[31:8]};
            if(cursor[1:0]==3)phase<=SRAM_READ;
            else if(pass==REWRITE)phase<=PROGRAM_BYTE;
            else access_flash(READ);
        end
    endtask

    always @(posedge clk)begin
        if(!enable)begin
            phase<=IDLE;busy<=0;import_done<=0;import_ok<=0;result<=0;backup_verified<=0;
        end
        else if(busy && pass!=SNAPSHOT && raw_error)fail(IO_ERROR);
        else case(phase)
            IDLE:if(import_start || (commit_start && import_ok))begin
                result<=0;busy<=1;cursor<=0;
                if(import_start)begin pass<=IMPORT;access_flash(READ);end
                else begin pass<=SNAPSHOT;phase<=LOCK;end
            end
            LOCK:if(locked)begin
                if(REUSE_BACKUP && backup_verified)begin
                    if(linear)start_sector(SCAN,0);
                    else begin pass<=CHECK_ID;access_flash(IDENTIFY);end
                end else phase<=BACKUP;
            end
            REQUEST:if(flash_ready)phase<=FLASH_WAIT;
            FLASH_WAIT:if(flash_done)begin
                if(flash_error)begin
                    if(pass==SNAPSHOT)phase<=BACKUP_IO_ERROR;
                    else if(pass==IMPORT)finish(IO_ERROR);
                    else fail(IO_ERROR);
                end
                else case(flash_operation)
                    IDENTIFY:if(identify_ok)start_sector(SCAN,0);else fail(UNSUPPORTED);
                    ERASE:begin pass<=REWRITE;phase<=SRAM_READ;end
                    PROGRAM:if(sector_last)start_sector(VERIFY,sector);else advance_byte();
                    default:case(pass)
                        IMPORT,SNAPSHOT:begin
                            word_data<=imported_word;
                            if(cursor[1:0]==3 && pass==IMPORT)phase<=SRAM_WRITE;
                            else if(pass==SNAPSHOT && (&cursor[CHUNK_BITS-1:0]))phase<=BACKUP_CHUNK;
                            else begin cursor<=cursor+1'b1;access_flash(READ);end
                        end
                        default:phase<=COMPARE;
                    endcase
                endcase
            end
            SRAM_WRITE:if(raw_write)phase<=SRAM_WAIT;
            SRAM_READ:if(raw_read)phase<=SRAM_WAIT;
            SRAM_WAIT:if(raw_done)begin
                if(pass==IMPORT)begin
                    if(last_byte)finish(SUCCESS);
                    else begin cursor<=cursor+1'b1;access_flash(READ);end
                end else begin
                    word_data<=raw_rdata;
                    if(in_fallback)phase<=FALLBACK_STORE;
                    else if(pass==REWRITE)phase<=PROGRAM_BYTE;
                    else access_flash(READ);
                end
            end
            COMPARE:if(pass==VERIFY && flash_rdata!=desired)fail(VERIFY_ERROR);
                else if(pass==SCAN && linear && flash_rdata!=desired)begin
                    changed<=1;access_flash(PROGRAM);
                end
                else if(!sector_last)begin
                    changed<=changed || flash_rdata!=desired;
                    advance_byte();
                end else if(pass==VERIFY || !(changed || flash_rdata!=desired))next_sector();
                else if(linear)start_sector(VERIFY,sector);
                else begin
                    cursor<={sector,{SECTOR_BITS{1'b0}}};
                    access_flash(ERASE);
                end
            PROGRAM_BYTE:if(desired==8'hff)begin
                if(sector_last)start_sector(VERIFY,sector);else advance_byte();
            end else access_flash(PROGRAM);
            BACKUP:if(backup_error)finish(in_fallback ? fallback_code : BACKUP_ERROR);
                else if(backup_ready)begin
                    if(in_fallback)finish(fallback_code);
                    else begin
                        backup_verified<=1;
                        if(linear)start_sector(SCAN,0);
                        else begin pass<=CHECK_ID;access_flash(IDENTIFY);end
                    end
                end
                else if(backup_fill)begin
                    cursor<=backup_offset;
                    if(in_fallback)phase<=SRAM_READ;else access_flash(READ);
                end
            FALLBACK_WAIT:if(!backup_ready && !backup_error)phase<=BACKUP;
            FALLBACK_STORE:if(&cursor[CHUNK_BITS-1:2])phase<=BACKUP_CHUNK;
                else begin cursor<=cursor+3'd4;phase<=SRAM_READ;end
            BACKUP_CHUNK:if(!backup_fill)phase<=BACKUP;
            BACKUP_IO_ERROR:if(backup_error)finish(IO_ERROR);
            default:phase<=IDLE;
        endcase
    end
    initial if(BACKUP_CHUNK_BYTES<8 || BACKUP_CHUNK_BYTES>(1<<ADDRESS_BITS) ||
        (BACKUP_CHUNK_BYTES & (BACKUP_CHUNK_BYTES-1))!=0)$error("Invalid save backup chunk size");
endmodule

// Write the working save back to the cartridge without user action.
// Game writes are committed after a quiet interval, and any unsaved change
// is committed before a quit or reset is allowed to proceed.
// A Memory restore replaces the working save without touching the cartridge.
// Automatic writes pause from the first restored word until the restore
// completes successfully, then resume with the next game write. A partial
// or failed restore therefore never reaches the cartridge.
// A failed write keeps the change unsaved. It is retried after the next
// game write, and once more before a quit or reset, so a persistently
// failing cartridge cannot hold the Pocket's quit indefinitely.
module gba_gamepak_save_scheduler #(
    parameter integer QUIET_TICKS=8
)(
    input wire clk,enable,ready,tick,guest_write,restore_write,restore_done,
    input wire reset_pending,busy,
    input wire [2:0] result,
    output wire start,pending,reset_block,
    output reg restored=0,
    output wire [3:0] status
);
    localparam integer TICK_BITS=$clog2(QUIET_TICKS+1);
    localparam [3:0] READY=0, SAVING=6, WORKING_COPY=7, UNAVAILABLE=8, QUEUED=10;
    localparam [2:0] SUCCESS=1;
    reg [TICK_BITS-1:0] quiet=0;
    reg dirty=0,active=0,finished=0,failed=0,reset_tried=0;
    wire unsaved=!restored && (dirty || guest_write);
    wire settled=!failed && !guest_write && quiet==QUIET_TICKS;
    wire flush=reset_pending && !reset_tried;
    wire eligible=enable && ready && !restore_write && unsaved;
    assign start=eligible && !busy && !active && (settled || flush);
    assign pending=enable && (active || unsaved);
    assign reset_block=enable && (active || (flush && eligible));
    // Report a cartridge commit result only once the commit has finished.
    assign status=!enable ? UNAVAILABLE : active ? SAVING : restored ? WORKING_COPY :
        failed ? {1'b0,result} : unsaved ? QUEUED : finished ? {1'b0,result} : READY;

    always @(posedge clk)begin
        if(!enable)begin
            dirty<=0;active<=0;restored<=0;finished<=0;failed<=0;quiet<=0;
        end else if(restore_write)begin
            restored<=1;dirty<=0;finished<=0;failed<=0;quiet<=0;
        end else if(restored)begin
            if(restore_done)restored<=0;
        end else if(start)begin
            // The controller includes any guest write that drains before it
            // acquires its lock, and keeps the lock through verification.
            active<=1;dirty<=1;finished<=0;quiet<=0;
            if(reset_pending)reset_tried<=1;
        end else if(active)begin
            if(!busy)begin
                active<=0;finished<=1;
                if(result==SUCCESS)begin dirty<=0;failed<=0;end
                else failed<=1;
            end
        end else if(guest_write)begin
            dirty<=1;failed<=0;quiet<=0;
        end else if(dirty && tick && quiet!=QUIET_TICKS)quiet<=quiet+1'b1;
        if(!reset_pending)reset_tried<=0;
    end
endmodule
