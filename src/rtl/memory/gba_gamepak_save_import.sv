// Startup reader for byte-wide saves and serial EEPROM. Both protocols use
// the same bus timer, working-save cursor, word shifter and store handshake.
//
// EEPROM capacity is measured, not looked up. Every request uses 14 address
// bits. A 512-byte chip answers a 14-bit request using its first six address
// bits, so wide blocks 0-63 all return its block 0, while an 8 KiB chip
// returns 64 different blocks. The first 512 bytes are read in the wide
// layout; if every block matches block 0 and is not blank, the chip is
// narrow and blocks 1-63 are re-read as wide block n<<8. A blank or uniform
// first 512 bytes reads all 8 KiB, which is exact for a blank chip.
// small_capacity selects 32 KiB for byte-wide saves only.
//
// EEPROM_WRITEBACK adds automatic writeback on the same pin sequencer.
// A commit first streams the cartridge's pre-write image to the SD backup
// (once per session), then visits every block: the working block is loaded
// into the 64-bit comparator, the cartridge block is read and compared bit by
// bit, a differing block is written with the measured address width (6 bits
// for 512 bytes, 14 for 8 KiB), the chip is polled until it reports ready,
// and the block is read back and compared again. The caller only starts a
// commit when the game's own address width matches the measured one.
//
// Writeback is only allowed when the import is trustworthy (writeback_allowed):
// after the import, the whole chip is read again and compared with the stored
// copy, and at least one data bit must have read as 0. A marginal contact
// fails the comparison, and a dead data line reads as an all-FF chip; both
// keep the cartridge read-only for the session, because the game would
// otherwise overwrite a real save it could not see. A program is accepted
// only after the chip has reported busy and then ready, and an I/O or verify
// error disables writeback for the rest of the session.
//
// FALLBACK_SAVE: Play Cartridge has no SD save slot, so a session the cart
// cannot take is written to CODE-unsaved.sav instead (backup_fallback). A
// commit goes straight to that file, never touching the cart, when the import
// was not trusted, a write failed earlier, or the game's address width differs
// from the chip's (write_permitted low). A program, poll or verify failure
// after the pre-write backup also continues into it.
module gba_gamepak_save_import #(
    parameter integer WAIT_CYCLES=20,
    // Builds whose writeback controller imports byte-wide saves use this
    // reader for EEPROM only; the parallel path is then not built.
    parameter bit EEPROM_ONLY=0,
    parameter bit EEPROM_WRITEBACK=0,
    // Polls allowed for one block program (about 0.8 us each at 20 waits).
    parameter integer POLL_LIMIT=65535,
    parameter integer BACKUP_CHUNK_BYTES=256,
    parameter bit FALLBACK_SAVE=0
) (
    input wire clk, enable, start, eeprom, small_capacity,
    input wire [7:0] parallel_in,
    input wire serial_in,
    output wire [23:0] pin_address_data,
    output wire high_drive, ad_drive, cs1_n, cs2_n, rd_n, wr_n,
    output wire busy,
    output reg done=0,
    output reg ok=0,
    output reg eeprom_narrow=0,
    output wire raw_write,
    output reg [13:0] raw_address=0,
    output wire [31:0] raw_wdata,
    input wire raw_idle, raw_done, raw_error,
    // EEPROM_WRITEBACK only; tie off otherwise.
    input wire commit_start, locked,
    input wire [31:0] raw_rdata,
    output wire raw_read,
    output wire write_lock, reset_block,
    output reg [2:0] result=0,
    input wire backup_ready, backup_error, backup_fill,
    input wire [16:0] backup_offset,
    output wire backup_request, backup_filled, backup_chunk_error,
    input wire backup_read,
    input wire [13:0] backup_word,
    output reg [31:0] backup_rdata=0,
    output wire writeback_allowed,
    input wire write_permitted,
    output wire backup_fallback
);
    wire eeprom_mode=EEPROM_ONLY || eeprom;
    localparam IDLE=0, ADDRESS_SETUP=1, ADDRESS_LATCH=2, BIT_SETUP=3,
               STROBE=4, HOLD=5, RELEASE=6, STORE=7, DRAIN=8,
               LOCK=9, BACKUP=10, BACKUP_CHUNK=11, LOAD=12, LOAD_WAIT=13, DECIDE=14, FALLBACK_WAIT=15;
    // Passes. IMPORT is the original startup read.
    localparam [2:0] IMPORT=0, SNAPSHOT=1, COMPARE=2, PROGRAM=3, POLL=4, VERIFY=5, FALLBACK=6;
    localparam [2:0] SUCCESS=1, UNSUPPORTED=2, IO_ERROR=3, VERIFY_ERROR=4, BACKUP_ERROR=5;
    localparam TICK_BITS=$clog2(WAIT_CYCLES+1);
    localparam [TICK_BITS-1:0] GUARD=TICK_BITS'(WAIT_CYCLES-1);
    localparam POLL_BITS=$clog2(POLL_LIMIT+1);
    localparam integer CHUNK_WORDS=BACKUP_CHUNK_BYTES/4;
    localparam integer CHUNK_BITS=$clog2(CHUNK_WORDS);
    reg [3:0] phase=IDLE;
    reg [2:0] pass=IMPORT;
    reg [TICK_BITS-1:0] ticks;
    reg [6:0] remaining;
    reg sending;
    reg [6:0] serial_byte;
    reg [31:0] word;
    reg select_n=1, read_n=1, write_n=1, drive_ad=0, drive_address=0;

    wire [13:0] next_address=raw_address+1'b1;
    reg eeprom_sized=0,blocks_differ=0,first_blank=1;
    // Block 0's bits, compared serially with each later block by rotation.
    // During writeback the same register holds the working block, in
    // transmission order, and rotates once per compared or written bit.
    reg [63:0] first_bits;
    wire first_half=raw_address[10:0]==11'h07f;
    wire finished=raw_address==(eeprom_mode
        ? (eeprom_narrow ? 14'h007f : 14'h07ff)
        : (small_capacity ? 14'h1fff : 14'h3fff));
    wire first_word=phase==IDLE && start;
    wire next_word=phase==DRAIN && raw_done && !finished;
    wire timed=busy && phase<=RELEASE && phase!=IDLE;

    // The cursor supplies the block address and the counter selects one
    // command bit. Reads are 11, block address, 0. A write is 10, the block
    // address at the chip's own width, 64 data bits, 0.
    wire [15:0] command_address=eeprom_narrow ? {raw_address[6:1],10'd0} : {4'd0,raw_address[10:1],2'd0};
    wire writing=EEPROM_WRITEBACK && pass==PROGRAM;
    wire [15:0] write_header=eeprom_narrow ? {2'b10,raw_address[6:1],8'd0} : {2'b10,4'd0,raw_address[10:1]};
    // Write framing, counted down from 73 or 81: the header ends at 66,
    // data occupies 65..2 and the stop bit is sent at 1.
    wire [3:0] header_bit=eeprom_narrow ? 4'(remaining-7'd58) : 4'(remaining-7'd66);
    wire write_bit=remaining>=66 ? write_header[header_bit] : remaining>=2 ? first_bits[63] : 1'b0;
    wire command_prefix=remaining>=16;
    wire command_bit=writing ? write_bit : command_prefix || command_address[remaining[3:0]];
    // The top address window also selects EEPROM on 32 MiB Game Paks.
    assign pin_address_data=eeprom_mode
        ? {8'hff,{9{drive_address}},6'd0,!drive_address && command_bit}
        : {8'hff,raw_address,~remaining[1:0]};
    assign busy=phase!=IDLE;
    assign high_drive=enable && eeprom_mode && busy;
    assign ad_drive=enable && drive_ad;
    assign cs1_n=!enable || !eeprom_mode || select_n;
    assign cs2_n=!enable || eeprom_mode || select_n;
    assign rd_n=!enable || read_n;
    assign wr_n=!enable || !eeprom_mode || write_n;
    assign raw_write=enable && phase==STORE && pass==IMPORT && raw_idle && !raw_error;
    assign raw_wdata={word[7:0],word[15:8],word[23:16],word[31:24]};
    assign raw_read=EEPROM_WRITEBACK && enable && phase==LOAD && raw_idle && !raw_error;
    assign write_lock=EEPROM_WRITEBACK && busy && pass!=IMPORT && !confirming;
    assign reset_block=EEPROM_WRITEBACK && busy && pass>=COMPARE && !confirming;
    wire in_fallback=FALLBACK_SAVE && EEPROM_WRITEBACK && pass==FALLBACK;
    reg [2:0] fallback_code=0;
    // The fallback drops its request until the writer has left the previous
    // run's ready/error state.
    assign backup_request=EEPROM_WRITEBACK && busy && (pass==SNAPSHOT || in_fallback) &&
        phase!=LOCK && phase!=FALLBACK_WAIT;
    assign backup_fallback=in_fallback;
    assign backup_filled=EEPROM_WRITEBACK && phase==BACKUP_CHUNK;
    assign backup_chunk_error=1'b0;

    wire receive=enable && !raw_error && phase==STROBE && ticks==0;
    wire receive_serial=receive && eeprom_mode && !sending && remaining<=64;
    wire ready_byte=receive_serial && remaining[2:0]==1;
    wire [7:0] data_byte=eeprom_mode ? {serial_byte,serial_in} : parallel_in;
    wire sizing_bit=receive_serial && !eeprom_sized;
    wire compare_bit=EEPROM_WRITEBACK && receive_serial && (pass==COMPARE || pass==VERIFY);
    wire sent_data_bit=writing && phase==HOLD && ticks==0 && remaining<=65 && remaining>=2;
    reg poll_busy=0;
    wire poll_ready=EEPROM_WRITEBACK && pass==POLL && receive && serial_in && poll_busy;
    reg [POLL_BITS-1:0] polls=0;
    reg block_differs=0,backup_verified=0;
    // Import trust: confirming re-reads the chip after the import.
    reg confirming=0,data_zero=0,trusted=0,write_failed=0;
    assign writeback_allowed=EEPROM_WRITEBACK && ok && trusted && !write_failed;
    (* ramstyle="M10K, no_rw_check" *) reg [31:0] archive_chunk[0:CHUNK_WORDS-1];
    always @(posedge clk)begin
        if(receive_serial)serial_byte<={serial_byte[5:0],serial_in};
        if(sizing_bit)begin
            if(raw_address[10:1]==0)begin
                first_bits<={first_bits[62:0],serial_in};
                first_blank<=first_blank && serial_in;
            end else begin
                first_bits<={first_bits[62:0],first_bits[63]};
                if(serial_in!=first_bits[63])blocks_differ<=1;
            end
        end else if(compare_bit || sent_data_bit)begin
            first_bits<={first_bits[62:0],first_bits[63]};
        end else if(EEPROM_WRITEBACK && phase==LOAD_WAIT && raw_done)begin
            if(!raw_address[0])first_bits[63:32]<={raw_rdata[7:0],raw_rdata[15:8],raw_rdata[23:16],raw_rdata[31:24]};
            else first_bits[31:0]<={raw_rdata[7:0],raw_rdata[15:8],raw_rdata[23:16],raw_rdata[31:24]};
        end
        if(phase==IDLE && start)begin blocks_differ<=0;first_blank<=1;end
        if((receive && !eeprom_mode) || ready_byte)word<={word[23:0],data_byte};
        if(EEPROM_WRITEBACK)begin
            if(backup_read)backup_rdata<=archive_chunk[backup_word[CHUNK_BITS-1:0]];
            if(phase==STORE && pass==SNAPSHOT)archive_chunk[raw_address[CHUNK_BITS-1:0]]<=raw_wdata;
            else if(in_fallback && phase==LOAD_WAIT && raw_done)archive_chunk[raw_address[CHUNK_BITS-1:0]]<=raw_rdata;
        end
    end

    task begin_word;
        begin
            if(eeprom_mode)remaining<=7'd17;
            else remaining<=7'd3;
            sending<=eeprom_mode;
            select_n<=eeprom_mode;
            drive_ad<=1;
            drive_address<=eeprom_mode;
            phase<=ADDRESS_SETUP;
        end
    endtask

    task begin_block(input [2:0] mode);
        begin
            pass<=mode;block_differs<=0;
            if(mode==PROGRAM)begin
                remaining<=eeprom_narrow ? 7'd73 : 7'd81;
                sending<=1;select_n<=1;drive_ad<=1;drive_address<=1;phase<=ADDRESS_SETUP;
            end else begin_word();
        end
    endtask

    task release_pins;
        begin
            phase<=IDLE;
            select_n<=1;read_n<=1;write_n<=1;drive_ad<=0;drive_address<=0;
        end
    endtask

    task finish(input [2:0] code);
        begin
            release_pins();
            result<=code;pass<=IMPORT;
            if(code==IO_ERROR || code==VERIFY_ERROR)write_failed<=1;
        end
    endtask

    // After the pre-write backup, a failed write saves the session to SD.
    task fail(input [2:0] code);
        begin
            if(FALLBACK_SAVE && pass!=IMPORT && pass!=SNAPSHOT && pass!=FALLBACK && !confirming)begin
                select_n<=1;read_n<=1;write_n<=1;drive_ad<=0;drive_address<=0;
                fallback_code<=code;pass<=FALLBACK;phase<=FALLBACK_WAIT;
            end else finish(code);
        end
    endtask

    // End of the import, after the confirmation pass when there is one.
    task import_complete(input bit success,input bit trust);
        begin
            release_pins();pass<=IMPORT;confirming<=0;
            done<=1;ok<=success;trusted<=trust;
        end
    endtask

    // Load the working copy of the block at the cursor (two save words).
    task load_block(input [13:0] block_word);
        begin
            select_n<=1;read_n<=1;write_n<=1;drive_ad<=0;drive_address<=0;
            raw_address<=block_word;pass<=COMPARE;phase<=LOAD;
        end
    endtask

    always @(posedge clk)begin
        if(first_word || next_word || (timed && ticks==0))ticks<=GUARD;
        else if(timed)ticks<=ticks-1'b1;
        // Block starts below clear this; a compared bit can only set it.
        if(compare_bit && serial_in!=first_bits[63])block_differs<=1;
        if(EEPROM_WRITEBACK && receive_serial && pass==IMPORT && !serial_in)data_zero<=1;
        if(EEPROM_WRITEBACK && pass==POLL && receive && !serial_in)poll_busy<=1;

        if(!enable)begin
            release_pins();
            done<=0;ok<=0;result<=0;backup_verified<=0;pass<=IMPORT;
            confirming<=0;data_zero<=0;trusted<=0;write_failed<=0;
        end else if(busy && raw_error && pass!=SNAPSHOT)begin
            if(pass==IMPORT || confirming)import_complete(0,0);
            else fail(IO_ERROR);
        end else case(phase)
            IDLE:if(start)begin
                raw_address<=0;done<=0;ok<=0;pass<=IMPORT;
                eeprom_narrow<=0;eeprom_sized<=0;
                confirming<=0;data_zero<=0;trusted<=0;
                begin_word();
            end else if(EEPROM_WRITEBACK && commit_start && writeback_allowed && write_permitted)begin
                result<=0;pass<=SNAPSHOT;phase<=LOCK;
            end else if(FALLBACK_SAVE && EEPROM_WRITEBACK && commit_start && done)begin
                // The cart may not be written: keep the session on SD.
                result<=0;fallback_code<=UNSUPPORTED;pass<=FALLBACK;phase<=LOCK;
            end
            STORE:if(pass==SNAPSHOT)begin
                // One chunk word per block half; the chunk ends on an odd word.
                if(&raw_address[CHUNK_BITS-1:0])begin
                    select_n<=1;read_n<=1;write_n<=1;drive_ad<=0;drive_address<=0;
                    phase<=BACKUP_CHUNK;
                end else begin
                    raw_address<=next_address;
                    if(remaining!=0)phase<=BIT_SETUP;
                    else begin_word();
                end
            end else if(raw_write)phase<=DRAIN;
            DRAIN:if(raw_done)begin
                if(eeprom_mode && !eeprom_sized && first_half)begin
                    eeprom_sized<=1;
                    if(!blocks_differ && !first_blank)begin
                        // Narrow chip: block 0 is correct; re-read blocks 1-63.
                        eeprom_narrow<=1;raw_address<=14'd2;begin_word();
                    end else begin
                        raw_address<=next_address;begin_word();
                    end
                end else if(finished)begin
                    // EEPROM writeback builds read the whole chip again.
                    if(EEPROM_WRITEBACK && eeprom_mode)begin
                        confirming<=1;load_block(14'd0);
                    end else begin
                        release_pins();
                        done<=1;ok<=1;
                    end
                end else begin
                    raw_address<=next_address;
                    if(eeprom_mode && remaining!=0)phase<=BIT_SETUP;
                    else begin_word();
                end
            end
            LOCK:if(locked)begin
                if(in_fallback || !backup_verified)phase<=BACKUP;
                else load_block(14'd0);
            end
            FALLBACK_WAIT:if(!backup_ready && !backup_error)phase<=BACKUP;
            BACKUP:if(backup_error)finish(in_fallback ? fallback_code : BACKUP_ERROR);
                else if(backup_ready)begin
                    if(in_fallback)finish(fallback_code);
                    else begin backup_verified<=1;load_block(14'd0);end
                end else if(backup_fill)begin
                    raw_address<=backup_offset[15:2];
                    if(in_fallback)phase<=LOAD;else begin_word();
                end
            BACKUP_CHUNK:if(!backup_fill)phase<=BACKUP;
            LOAD:if(raw_read)phase<=LOAD_WAIT;
            LOAD_WAIT:if(raw_done)begin
                if(in_fallback)begin
                    // The working copy streams into the chunk word by word.
                    if(&raw_address[CHUNK_BITS-1:0])phase<=BACKUP_CHUNK;
                    else begin raw_address<=next_address;phase<=LOAD;end
                end else if(!raw_address[0])begin raw_address<=next_address;phase<=LOAD;end
                else begin_block(COMPARE);
            end
            // A block has been compared (COMPARE/VERIFY) or programmed.
            DECIDE:case(pass)
                COMPARE:if(confirming)begin
                        // A second read that differs means unreliable contacts.
                        if(block_differs)import_complete(1,0);
                        else if(finished)import_complete(1,data_zero);
                        else load_block(next_address);
                    end else if(block_differs)begin_block(PROGRAM);
                    else if(finished)finish(SUCCESS);
                    else load_block(next_address);
                VERIFY:if(block_differs)fail(VERIFY_ERROR);
                    else if(finished)finish(SUCCESS);
                    else load_block(next_address);
                default:fail(IO_ERROR);
            endcase
            default:if(ticks==0)case(phase)
                ADDRESS_SETUP:if(eeprom_mode)begin
                    select_n<=0;phase<=ADDRESS_LATCH;
                end else begin
                    read_n<=0;phase<=STROBE;
                end
                ADDRESS_LATCH:begin
                    drive_address<=0;drive_ad<=sending;phase<=BIT_SETUP;
                end
                BIT_SETUP:begin
                    read_n<=sending;write_n<=!sending;phase<=STROBE;
                end
                STROBE:begin
                    read_n<=1;write_n<=1;phase<=HOLD;
                    if(poll_ready)begin
                        // Programming finished: read the block back.
                        select_n<=1;drive_ad<=1;drive_address<=1;
                        pass<=VERIFY;block_differs<=0;remaining<=7'd17;sending<=1;
                        phase<=RELEASE;
                    end
                end
                HOLD:if(!eeprom_mode)begin
                    select_n<=1;drive_ad<=0;phase<=RELEASE;
                end else if(EEPROM_WRITEBACK && pass==POLL)begin
                    if(polls==POLL_BITS'(POLL_LIMIT))fail(IO_ERROR);
                    else begin polls<=polls+1'b1;phase<=BIT_SETUP;end
                end else begin
                    remaining<=remaining-1'b1;
                    phase<=BIT_SETUP;
                    if(sending && remaining==1)begin
                        select_n<=1;drive_ad<=0;phase<=RELEASE;
                        sending<=0;remaining<=68;
                        if(writing)begin pass<=POLL;polls<=0;poll_busy<=0;end
                    end else if(!sending && (remaining==33 || remaining==1))begin
                        if(EEPROM_WRITEBACK && (pass==COMPARE || pass==VERIFY))begin
                            // Comparison passes keep reading; nothing is stored.
                            if(remaining==1)begin
                                select_n<=1;drive_ad<=0;phase<=DECIDE;
                            end
                        end else phase<=STORE;
                    end
                end
                RELEASE:if(eeprom_mode || remaining!=0)begin
                    if(!eeprom_mode)remaining<=remaining-1'b1;
                    select_n<=eeprom_mode;drive_ad<=1;drive_address<=eeprom_mode;
                    phase<=ADDRESS_SETUP;
                end else phase<=STORE;
                default:release_pins();
            endcase
        endcase
    end
    initial if(EEPROM_WRITEBACK && (!EEPROM_ONLY || BACKUP_CHUNK_BYTES<8 ||
        (BACKUP_CHUNK_BYTES & (BACKUP_CHUNK_BYTES-1))!=0))$error("Invalid EEPROM writeback configuration");
endmodule
