// GBA serial EEPROM (512 B / 8 KiB), with an independent APF host port.
// access is one ACCEPTED halfword bus cycle, not a level-held request.
// File bytes are in ascending address order; serial bytes are MSB first.
module gba_eeprom #(
    parameter integer PROGRAM_CYCLES=199680
) (
    input wire clk, reset, access, write, bit_in,
`ifdef GBK_SAVESTATE
    input wire state_hold,state_write,state_host_access,
    input wire [1:0] state_addr,
    input wire [31:0] state_wdata,
    output wire state_valid,
    output reg [31:0] state_rdata,
    output wire state_host_idle,
    output reg state_host_done=0,
`endif
    input wire [15:0] dma_count,
    output wire bit_out, ready,
    input wire load_clk, load_reset, load_write, load_read,
    input wire [14:0] load_addr,
    input wire [31:0] load_wdata,
    output wire [31:0] load_rdata,
    output reg load_valid=0,
    input wire export_lock,
    output reg export_locked=0,
    output wire capacity_large
);
    localparam IDLE=0,COMMAND=1,ADDRESS=2,DATA=3,STOP=4,OUTPUT=5;
    localparam BUSY_BITS=$clog2(PROGRAM_CYCLES+1);
    reg [2:0] state=IDLE;
    reg read_command=0;
    reg [3:0] address_remaining=0;
    reg [9:0] block_address=0;
    reg [6:0] count=0;
    reg [63:0] incoming=0;
    reg commit=0;
    reg [BUSY_BITS-1:0] busy=0;
    reg large_seen=0, host_large=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] lock_sync=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] host_large_sync=0;
`ifdef GBK_SAVESTATE
    wire state_frozen=state_hold===1'b1;
    reg capacity_request=0,capacity_payload=0,capacity_pending=0;
    reg capacity_seen=0,capacity_ack=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] capacity_request_sync=0,capacity_ack_sync=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] capacity_payload_sync=0;
    // Restore the host capacity latch itself. A permanent override would
    // suppress capacity detection on a later ordinary save-file import.
    // Bundled payload stays fixed until the round-trip acknowledgement.
    always @(posedge load_clk)begin
        capacity_request_sync<={capacity_request_sync[1:0],capacity_request};
        capacity_payload_sync<={capacity_payload_sync[0],capacity_payload};
        if(capacity_request_sync[2]!=capacity_seen)begin
            capacity_seen<=capacity_request_sync[2];
            capacity_ack<=capacity_request_sync[2];
        end
    end
    always @(posedge clk)begin
        capacity_ack_sync<={capacity_ack_sync[1:0],capacity_ack};
        if(capacity_pending && capacity_ack_sync[2]==capacity_request)capacity_pending<=0;
        if(state_write && state_valid && state_addr==0)begin
            capacity_payload<=state_wdata[26];capacity_request<=!capacity_request;capacity_pending<=1;
        end
    end
    assign state_valid=state_frozen && !reset && !commit && !capacity_pending;
    always @* begin
        state_rdata=0;
        if(state_valid)case(state_addr)
            0:state_rdata={5'd0,host_large_sync[1],large_seen,count,block_address,address_remaining,read_command,state};
            1:state_rdata=incoming[31:0];
            2:state_rdata=incoming[63:32];
            3:state_rdata=busy;
        endcase
    end
`endif
    always @(posedge load_clk) begin
        // Capacity, like the data, survives runtime PLL and CPU resets.
        // Configuration initial values start a fresh game/core instance.
        if(load_write && load_addr>=128 && load_addr<2048
`ifdef GBK_SAVESTATE
            && state_host_access!==1'b1
`endif
        ) host_large<=1;
`ifdef GBK_SAVESTATE
        if(capacity_request_sync[2]!=capacity_seen)host_large<=capacity_payload_sync[1];
`endif
    end
    always @(posedge clk) begin
        lock_sync<={lock_sync[1:0],export_lock===1'b1};
        host_large_sync<={host_large_sync[0],host_large};
`ifdef GBK_SAVESTATE
        if(state_write && state_valid && state_addr==0)large_seen<=state_wdata[25];
        else if(!state_frozen)
`endif
        if(access && write && (state==IDLE || state==OUTPUT) && bit_in && (dma_count==17 || dma_count==81)) large_seen<=1;
        // A completed 64-bit write drains even if guest reset follows STOP.
        export_locked<=lock_sync[2] && !commit;
    end
    assign capacity_large=large_seen || host_large_sync[1];
    assign ready=!lock_sync[2] && !reset
`ifdef GBK_SAVESTATE
        && !state_frozen
`endif
    ;
    wire [63:0] stored;
    wire [63:0] commit_data;
    genvar lane;
    generate for(lane=0;lane<8;lane=lane+1) begin : byte_order
        assign commit_data[lane*8+:8]=incoming[63-lane*8-:8];
    end endgenerate
    wire [6:0] output_bit=count-7'd4;
    assign bit_out=busy!=0 ? 1'b0 :
        state==OUTPUT ? (count<4 ? 1'b0 : stored[{output_bit[5:3],~output_bit[2:0]}]) : 1'b1;
    always @(posedge clk) begin
        commit<=0;
        if(busy!=0
`ifdef GBK_SAVESTATE
            && !state_frozen
`endif
        ) busy<=busy-1'b1;
        if(reset) begin
            state<=IDLE; count<=0; address_remaining<=0;
`ifdef GBK_SAVESTATE
        end else if(state_frozen)begin
            if(state_write && state_valid)case(state_addr)
                0:begin state<=state_wdata[2:0];read_command<=state_wdata[3];
                    address_remaining<=state_wdata[7:4];block_address<=state_wdata[17:8];count<=state_wdata[24:18];end
                1:incoming[31:0]<=state_wdata;
                2:incoming[63:32]<=state_wdata;
                3:busy<=state_wdata[BUSY_BITS-1:0];
            endcase
`endif
        end else if(access && ready) begin
            if(write) begin
                if(busy==0) case(state)
                    IDLE,OUTPUT: if(bit_in) begin
                        state<=COMMAND; block_address<=0;
                        address_remaining<=(dma_count==17 || dma_count==81) ? 14 :
                            (dma_count==9 || dma_count==73) ? 6 : (capacity_large ? 14 : 6);
                    end
                    COMMAND: begin read_command<=bit_in;state<=ADDRESS;end
                    ADDRESS: begin
                        block_address<={block_address[8:0],bit_in};
                        address_remaining<=address_remaining-1'b1;
                        if(address_remaining==1) begin
                            count<=0;state<=read_command ? STOP : DATA;
                        end
                    end
                    DATA: begin
                        incoming<={incoming[62:0],bit_in};count<=count+1'b1;
                        if(count==63) state<=STOP;
                    end
                    STOP: begin
                        // Read framing consumes the trailing cycle regardless
                        // of its data. EEPROM_V124 leaves this halfword of its
                        // stack buffer uninitialized (e.g. Minish Cap).
                        if(read_command) begin state<=OUTPUT;count<=0;end
                        // Invalid write stops never commit a partial record.
                        else if(bit_in) state<=IDLE;
                        else begin commit<=1;busy<=PROGRAM_CYCLES;state<=IDLE;end
                    end
                    default:state<=IDLE;
                endcase
            end else if(busy==0) begin
                if(state==OUTPUT) begin
                    if(count==67) state<=IDLE;
                    else count<=count+1'b1;
                end else if(state!=IDLE) state<=IDLE; // abort incomplete input
            end
        end
    end
    // Host memory is sampled before its delayed valid pulse. Reads beyond
    // 8 KiB return FF and writes are excluded, never wrapped into progress.
    reg [1:0] read_pipe=0;
    reg [1:0] range_pipe=0;
`ifdef GBK_SAVESTATE
    reg state_last_write=0;
    assign state_host_idle=!state_last_write && read_pipe==0 && !load_valid;
    always @(posedge load_clk)begin
        state_last_write<=load_write;
        state_host_done<=state_last_write || load_valid;
    end
`endif
    wire [31:0] host_q;
    always @(posedge load_clk) begin
        read_pipe<={read_pipe[0],load_read};
        range_pipe<={range_pipe[0],load_addr<2048};
        load_valid<=read_pipe[1];
    end
    assign load_rdata=range_pipe[1] ? host_q : 32'hffffffff;
`ifdef GBK_SIM
    reg [63:0] mem[0:1023];
    reg [9:0] guest_address;
    reg [10:0] host_address;
    reg [31:0] host_data;
    initial for(integer i=0;i<1024;i=i+1) mem[i]=64'hffffffffffffffff;
    assign stored=mem[guest_address];
    assign host_q=host_data;
    always @(posedge clk) begin
        guest_address<=block_address;
        if(commit) mem[block_address]<=commit_data;
    end
    always @(posedge load_clk) begin
        host_address<=load_addr[10:0];
        host_data<=host_address[0] ? mem[host_address[10:1]][63:32] : mem[host_address[10:1]][31:0];
        if(load_write && load_addr<2048)
            if(load_addr[0]) mem[load_addr[10:1]][63:32]<=load_wdata;
            else mem[load_addr[10:1]][31:0]<=load_wdata;
    end
`else
    altsyncram storage (
        .clock0(load_clk),.clock1(clk),.address_a(load_addr[10:0]),.address_b(block_address),
        .data_a(load_wdata),.data_b(commit_data),.wren_a(load_write && load_addr<2048),.wren_b(commit),
        .q_a(host_q),.q_b(stored),.byteena_a(1'b1),.byteena_b(1'b1),
        .aclr0(1'b0),.aclr1(1'b0),.addressstall_a(1'b0),.addressstall_b(1'b0),
        .clocken0(1'b1),.clocken1(1'b1),.clocken2(1'b1),.clocken3(1'b1),
        .rden_a(1'b1),.rden_b(1'b1),.eccstatus()
    );
    defparam storage.operation_mode="BIDIR_DUAL_PORT";
    defparam storage.intended_device_family="Cyclone V",storage.lpm_type="altsyncram";
    defparam storage.width_a=32,storage.widthad_a=11,storage.numwords_a=2048;
    defparam storage.width_b=64,storage.widthad_b=10,storage.numwords_b=1024;
    defparam storage.width_byteena_a=1,storage.width_byteena_b=1;
    defparam storage.outdata_reg_a="CLOCK0",storage.address_reg_b="CLOCK1",storage.outdata_reg_b="UNREGISTERED";
    defparam storage.init_file="../rtl/memory/gba_eeprom_blank.mif";
`endif
endmodule
