// A native session may issue guest writes only after a complete cartridge
// backup was reopened and read back. Use the same physical bus for backup
// reads and gameplay, with a single APF-sized scratch buffer.
module gba_gamepak_native_backup #(
    parameter integer CHUNK_BYTES=256
)(
    input wire clk,enable,start,timeout_tick,profile_verified,
    input wire [2:0] save_kind,
    input wire [31:0] game_code,
    output wire write_allowed,busy,
    output reg failed=0,
    output wire bus_request,bus_consume,
    output wire [26:0] bus_address,
    input wire bus_ready,bus_response,bus_error,
    input wire [31:0] bus_data,
    input wire bridge_rd,bridge_wr,
    input wire [31:0] bridge_addr,bridge_wdata,
    input wire command_done,
    input wire [2:0] command_error,
    output wire archive_active,command_open,command_write,command_read,
    output wire [31:0] bridge_rdata,transfer_address,transfer_offset,transfer_length
);
    localparam integer BYTE_BITS=$clog2(CHUNK_BYTES);
    localparam IDLE=0,READ_BYTE=1,WAIT_BYTE=2,COMPLETE=3,IO_ERROR=4;
    reg pending=0,armed=0;
    reg [2:0] admitted_kind;
    reg [31:0] admitted_code;
    reg [2:0] phase=IDLE;
    reg [BYTE_BITS-1:0] cursor;
    reg [31:0] packed_word;
    reg [31:0] backup_data;
    (* ramstyle="M10K, no_rw_check" *) reg [31:0] scratch[0:CHUNK_BYTES/4-1];
    wire fill_chunk,backup_read,backup_ready,backup_error;
    wire [16:0] chunk_offset;
    wire [13:0] backup_word;
    wire admitted=profile_verified && (save_kind==2 || save_kind==3);
    wire same_profile=admitted && save_kind==admitted_kind && game_code==admitted_code;
    wire [31:0] captured_word={bus_data[7:0],packed_word[31:8]};
    wire capture=phase==WAIT_BYTE && bus_response && !bus_error;
    assign busy=enable && pending;
    assign write_allowed=enable && armed && same_profile;
    assign bus_request=busy && phase==READ_BYTE;
    assign bus_consume=phase==WAIT_BYTE || !busy;
    assign bus_address=27'h6000000 | {10'd0,chunk_offset} | 27'(cursor);

    gba_gamepak_save_backup #(.VARIABLE_PROFILE(1),.USE_TIMEOUT_TICK(1),
        .STREAMING(1),.CHUNK_BYTES(CHUNK_BYTES)) archive(
        .clk,.enable(enable && (!pending || same_profile)),.request(pending),.timeout_tick,.half_capacity(1'b0),
        .game_code(admitted_code),.stream_capacity(admitted_kind==2 ? 18'd32768 : 18'd65536),
        .fill_chunk,.chunk_offset,.chunk_filled(phase==COMPLETE),.chunk_error(phase==IO_ERROR),
        .ready(backup_ready),.error(backup_error),.active(archive_active),
        .bridge_rd,.bridge_wr,.bridge_addr,.bridge_wdata,.backup_rdata(backup_data),.backup_read,.backup_word,
        .command_open,.command_write,.command_read,.command_done,.command_error,
        .bridge_rdata,.transfer_address,.transfer_offset,.transfer_length);

    always @(posedge clk)begin
        if(backup_read)backup_data<=scratch[backup_word[BYTE_BITS-3:0]];
        if(capture && cursor[1:0]==3)scratch[cursor[BYTE_BITS-1:2]]<=captured_word;
        if(!enable)begin pending<=0;armed<=0;failed<=0;end
        else if((pending || armed) && !same_profile)begin pending<=0;armed<=0;failed<=1;end
        else if(pending)begin
            if(backup_ready || backup_error)begin
                pending<=0;armed<=backup_ready;failed<=backup_error;
            end
        end else if(start && !armed && !archive_active)begin
            pending<=admitted;failed<=!admitted;
            admitted_kind<=save_kind;admitted_code<=game_code;
        end

        if(!busy || !fill_chunk)phase<=IDLE;
        else case(phase)
            IDLE:begin cursor<=0;phase<=READ_BYTE;end
            READ_BYTE:if(bus_ready)phase<=WAIT_BYTE;
            WAIT_BYTE:if(bus_response)begin
                if(bus_error)phase<=IO_ERROR;
                else begin
                    packed_word<=captured_word;
                    cursor<=cursor+1'b1;
                    phase<=(&cursor) ? COMPLETE : READ_BYTE;
                end
            end
            default:begin end
        endcase
    end
    initial if(CHUNK_BYTES<8)$error("Native backup requires at least two words per chunk");
endmodule
