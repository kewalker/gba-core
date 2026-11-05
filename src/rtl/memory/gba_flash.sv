// Shared 128 KiB Flash / 32 KiB SRAM backing. APF import writes while the CPU
// is held in reset. Runtime command reset preserves the imported/save data.
// Host port A exports a coherent image after the current operation finishes.
module gba_flash (
    input logic clk, reset, req, write,
`ifdef GBK_SAVESTATE
    input wire state_hold,state_write,state_host_read,
    input wire [31:0] state_wdata,
    output wire state_valid,
    output wire [31:0] state_rdata,
    output wire state_host_idle,
    output reg state_host_done=0,
`endif
    input wire save_sram, save_flash512,
    input wire [1:0] size,
    input logic [31:0] addr, wdata,
    output logic [31:0] rdata,
    output wire ready,
    input logic load_clk, load_write,
    input logic [14:0] load_addr,
    input logic [31:0] load_wdata,
    output wire [31:0] load_rdata,
    input wire export_lock,
    output wire export_locked
);
    wire [14:0] ram_addr;
    logic [31:0] ram_q;
    wire [31:0] ram_data;
    wire [3:0] ram_mask;
    wire ram_write;
    // Both backends use the same command engine and byte/bank semantics.
    gba_flash_commands commands (
`ifdef GBK_SAVESTATE
        .state_hold,.state_write,.state_wdata,.state_valid,.state_rdata,
`endif
        .clk,.reset,.req,.write,.save_sram,.save_flash512,.size,.addr,.wdata,.rdata,.ready,
        .export_lock,.export_locked,.ram_addr,.ram_q,.ram_data,.ram_mask,.ram_write,
        .ram_request(),.ram_ready(1'b1),.ram_idle(1'b1)
    );
`ifdef GBK_SAVESTATE
    reg state_host_pending=0;
    assign state_host_idle=!state_host_pending;
    always @(posedge load_clk)begin
        state_host_done<=state_host_pending;
        state_host_pending<=load_write || state_host_read;
    end
`endif
`ifdef GBK_SIM
    logic [31:0] mem[0:32767];
    logic [14:0] read_addr;
    initial for(integer i=0;i<32768;i=i+1) mem[i]=32'hffffffff;
    reg [31:0] host_q;
    assign load_rdata = host_q;
    always @(posedge load_clk) begin
        host_q <= mem[load_addr];
        if(load_write === 1'b1) mem[load_addr]<=load_wdata;
    end
    always @(posedge clk) begin
        read_addr<=ram_addr;
        ram_q<=mem[read_addr];
        if(ram_write) for(integer n=0;n<4;n=n+1)
            if(ram_mask[n]) mem[ram_addr][n*8+:8]<=ram_data[n*8+:8];
    end
`else
    altsyncram storage (
        .clock0(load_clk), .clock1(clk), .address_a(load_addr), .address_b(ram_addr),
        .data_a(load_wdata), .data_b(ram_data), .wren_a(load_write), .wren_b(ram_write),
        .byteena_a(4'b1111), .byteena_b(ram_mask), .q_a(load_rdata), .q_b(ram_q),
        .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0), .addressstall_b(1'b0),
        .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
        .rden_a(1'b1), .rden_b(1'b1), .eccstatus()
    );
    defparam storage.operation_mode="BIDIR_DUAL_PORT";
    defparam storage.intended_device_family="Cyclone V";
    defparam storage.lpm_type="altsyncram";
    defparam storage.width_a=32, storage.width_b=32;
    defparam storage.widthad_a=15, storage.widthad_b=15;
    defparam storage.numwords_a=32768, storage.numwords_b=32768;
    defparam storage.width_byteena_a=4, storage.width_byteena_b=4;
    defparam storage.outdata_reg_a="UNREGISTERED";
    defparam storage.address_reg_b="CLOCK1", storage.outdata_reg_b="CLOCK1";
    defparam storage.indata_reg_b="CLOCK1", storage.wrcontrol_wraddress_reg_b="CLOCK1";
    defparam storage.byteena_reg_b="CLOCK1";
    defparam storage.init_file="../rtl/memory/gba_flash_blank.mif";
`endif
endmodule

// Save command engine. The internal RAM retains its original fixed latency;
// external storage supplies one completion per read/write. CPU reset cancels
// command parsing, while the external backend drains already accepted writes.
module gba_flash_commands #(parameter bit ASYNC_MEMORY=0) (
    input wire clk, reset, req, write, save_sram, save_flash512,
`ifdef GBK_SAVESTATE
    input wire state_hold,state_write,
    input wire [31:0] state_wdata,
    output wire state_valid,
    output wire [31:0] state_rdata,
`endif
    input wire [1:0] size,
    input wire [31:0] addr, wdata,
    output logic [31:0] rdata,
    output wire ready,
    input wire export_lock,
    output reg export_locked=0,
    output logic [14:0] ram_addr,
    input wire [31:0] ram_q,
    output wire [31:0] ram_data,
    output wire [3:0] ram_mask,
    output wire ram_write, ram_request,
    input wire ram_ready, ram_idle
);
    localparam IDLE=0, READ_WAIT=1, READ_VALUE=2, PROGRAM_WAIT=3,
               PROGRAM_VALUE=4, PROGRAM_WRITE=5, ERASE=6, ACK=7;
    // Save type is held in the loader domain until the next ROM load. It is
    // independent of CPU Reset Enter/Exit and settles before game execution.
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] sram_sync = 0;
    always @(posedge clk) sram_sync <= {sram_sync[0], save_sram === 1'b1};
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] flash512_sync=0;
    always @(posedge clk) flash512_sync <= {flash512_sync[0],save_flash512 === 1'b1};
    wire [1:0] store_lane = size==2'b00 ? 2'd0 :
        size==2'b01 ? {1'b0,addr[0]} : addr[1:0];
    wire [7:0] sram_byte = wdata[store_lane*8+:8];
    logic [2:0] state;
    logic [1:0] settle;
    logic [2:0] command_state;
    logic id_mode, bank;
`ifdef GBK_SAVESTATE
    wire state_frozen=state_hold===1'b1;
    assign state_valid=!reset && state_frozen && state==IDLE && ram_idle && !req;
    assign state_rdata=state_valid ? {27'd0,bank,id_mode,command_state} : 32'd0;
`endif
    wire selected_bank=bank && !flash512_sync[1];
    logic [14:0] erase_end;
    logic [1:0] byte_lane;
    logic [7:0] program_byte;
    logic [31:0] program_data;
    assign ram_write = !reset && (state == ERASE || state == PROGRAM_WRITE);
    assign ram_mask = state == ERASE ? 4'b1111 : (4'b0001 << byte_lane);
    assign ram_data = state == ERASE ? 32'hffffffff : program_data;
    assign ready = state == ACK;
    assign ram_request = !reset && (state==READ_WAIT || state==PROGRAM_WAIT || ram_write);
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] lock_sync;
    always @(posedge clk) begin
        lock_sync <= {lock_sync[1:0], export_lock === 1'b1};
        // Register the state decode before crossing clocks. A combinational
        // decode could glitch when several state bits change during program.
        // This extra edge also drains the final registered RAM write.
        export_locked <= lock_sync[2] && (reset || state == IDLE || state == ACK) && ram_idle;
    end
    always_ff @(posedge clk) begin
        if(reset) begin
            state<=IDLE;settle<=0;command_state<=0;id_mode<=0;bank<=0;
            ram_addr<=0;erase_end<=0;byte_lane<=0;program_byte<=0;program_data<=0;rdata<=0;
`ifdef GBK_SAVESTATE
        end else if(state_frozen && state==IDLE)begin
            // CPU/DMA have drained their accepted bus operation. Preserve the
            // unlock/program/bank parser between transactions; backing bytes
            // are copied through the existing raw host port, never commands.
            if(state_write && state_valid)begin
                command_state<=state_wdata[2:0];id_mode<=state_wdata[3];bank<=state_wdata[4];
            end
`endif
        end else case(state)
            IDLE: if(req && !lock_sync[2] && (!ASYNC_MEMORY || (ram_idle && !ram_ready))) begin
                ram_addr<=sram_sync[1] ? {2'b0,addr[14:2]} : {selected_bank,addr[15:2]};byte_lane<=addr[1:0];settle<=2;
                if(!write) begin
                    if(id_mode && !sram_sync[1]) begin
                        // The 8-bit save bus repeats the selected byte on all lanes.
                        case(addr[15:0])
                            0:rdata<=flash512_sync[1] ? 32'hc2c2c2c2 : 32'h62626262;
                            1:rdata<=flash512_sync[1] ? 32'h1c1c1c1c : 32'h13131313;
                            default:rdata<=32'hffffffff;
                        endcase
                        state<=ACK;
                    end else state<=READ_WAIT;
                end else begin
                    state<=ACK;
                    // Program consumes arbitrary data, including F0/AA.
                    if(sram_sync[1]) begin
                        // SRAM overwrites one byte, with no unlock/program/erase
                        // commands. The shared byte-enable RAM needs no extra
                        // storage and preserves neighbouring lanes.
                        program_data<={4{sram_byte}};state<=PROGRAM_WRITE;
                    end else if(command_state==3) begin
                        program_byte<=wdata[7:0];command_state<=0;state<=PROGRAM_WAIT;
                    end else if(wdata[7:0]==8'hf0) begin
                        id_mode<=0;command_state<=0;
                    end else case(command_state)
                        0: if(addr[15:0]==16'h5555 && wdata[7:0]==8'haa) command_state<=1;
                        1: command_state<=(addr[15:0]==16'h2aaa && wdata[7:0]==8'h55) ? 2 : 0;
                        2: begin
                            command_state<=0;
                            if(addr[15:0]==16'h5555) case(wdata[7:0])
                                8'h90:id_mode<=1;
                                8'ha0:begin id_mode<=0;command_state<=3;end
                                8'hb0:command_state<=4;
                                8'h80:begin id_mode<=0;command_state<=5;end
                                default:begin end
                            endcase
                        end
                        4: begin
                            if(addr[15:0]==0) bank<=wdata[0] && !flash512_sync[1];
                            command_state<=0;
                        end
                        5: command_state<=(addr[15:0]==16'h5555 && wdata[7:0]==8'haa) ? 6 : 0;
                        6: command_state<=(addr[15:0]==16'h2aaa && wdata[7:0]==8'h55) ? 7 : 0;
                        7: begin
                            command_state<=0;
                            if(wdata[7:0]==8'h30) begin
                                ram_addr<={selected_bank,addr[15:12],10'b0};
                                erase_end<={selected_bank,addr[15:12],10'h3ff};state<=ERASE;
                            end else if(addr[15:0]==16'h5555 && wdata[7:0]==8'h10) begin
                                ram_addr<=0;erase_end<=flash512_sync[1] ? 15'h3fff : 15'h7fff;state<=ERASE;
                            end
                        end
                        default:command_state<=0;
                    endcase
                end
            end
            READ_WAIT,PROGRAM_WAIT:
                if(ASYNC_MEMORY) begin
                    if(ram_ready) state<=state==READ_WAIT ? READ_VALUE : PROGRAM_VALUE;
                end else if(settle!=0) settle<=settle-1'b1;
                else state<=state==READ_WAIT ? READ_VALUE : PROGRAM_VALUE;
            READ_VALUE: begin rdata<={4{ram_q[byte_lane*8+:8]}};state<=ACK;end
            PROGRAM_VALUE: begin
                program_data<={4{ram_q[byte_lane*8+:8] & program_byte}};state<=PROGRAM_WRITE;
            end
            PROGRAM_WRITE: if(!ASYNC_MEMORY || ram_ready) state<=ACK;
            ERASE: if(!ASYNC_MEMORY || ram_ready) begin
                if(ram_addr==erase_end) state<=ACK;else ram_addr<=ram_addr+1'b1;
            end
            // DMA can suspend the CPU after Flash has finished. Hold the
            // completion until the bus presents the owner's request again;
            // replaying an AA/55 command would corrupt the unlock sequence.
            ACK: if(req) state<=IDLE;
            default:state<=IDLE;
        endcase
    end
endmodule

// Nintendo save-library signature detection during ROM loading. Inspect every
// byte alignment, including signatures spanning loader words. Unmarked games
// retain the established Flash default. CPU reset does not clear the selection.
module gba_save_type (
    input wire clk, reset, load_write,
    input wire [22:0] load_addr,
    input wire [31:0] load_wdata,
    output reg save_sram = 0,
    output reg save_eeprom = 0,
    output reg save_flash512 = 0
);
    reg [6:0] matched = 0;
    reg [22:0] next_addr = 0;
    reg history_valid = 0;
    wire consecutive = history_valid && load_addr==next_addr && load_addr!=0;
    // Carry only the seven possible partial matches, not a wide byte history.
    // Advance all four incoming bytes combinationally, so no loader bandwidth
    // or alignment assumption is introduced. Shared prefixes also cover FRAM.
    function automatic [7:0] advance(input [6:0] previous,input [7:0] value);
        begin
            advance[0]=value==8'h53;                         // S
            advance[1]=previous[0] && value==8'h52;          // R
            advance[2]=previous[1] && value==8'h41;          // A
            advance[3]=previous[2] && value==8'h4d;          // M
            advance[4]=previous[3] && value==8'h5f;          // _
            advance[5]=previous[4] && value==8'h46;          // F
            advance[6]=previous[5] && value==8'h5f;          // _
            advance[7]=(previous[4] || previous[6]) && value==8'h56; // V
        end
    endfunction
    wire [7:0] step0=advance(consecutive ? matched : 7'd0,load_wdata[7:0]);
    wire [7:0] step1=advance(step0[6:0],load_wdata[15:8]);
    wire [7:0] step2=advance(step1[6:0],load_wdata[23:16]);
    wire [7:0] step3=advance(step2[6:0],load_wdata[31:24]);
    wire found=step0[7] || step1[7] || step2[7] || step3[7];
    reg [8:0] flash_matched=0;
    function automatic [9:0] advance_flash(input [8:0] previous,input [7:0] value);
        begin
            advance_flash[0]=value==8'h46; // F
            advance_flash[1]=previous[0] && value==8'h4c;
            advance_flash[2]=previous[1] && value==8'h41;
            advance_flash[3]=previous[2] && value==8'h53;
            advance_flash[4]=previous[3] && value==8'h48;
            advance_flash[5]=previous[4] && value==8'h35;
            advance_flash[6]=previous[5] && value==8'h31;
            advance_flash[7]=previous[6] && value==8'h32;
            advance_flash[8]=(previous[4] || previous[7]) && value==8'h5f;
            advance_flash[9]=previous[8] && value==8'h56;
        end
    endfunction
    wire [9:0] fl0=advance_flash(consecutive ? flash_matched : 9'd0,load_wdata[7:0]);
    wire [9:0] fl1=advance_flash(fl0[8:0],load_wdata[15:8]);
    wire [9:0] fl2=advance_flash(fl1[8:0],load_wdata[23:16]);
    wire [9:0] fl3=advance_flash(fl2[8:0],load_wdata[31:24]);
    always @(posedge clk) begin
        if(reset) flash_matched<=0;
        else if(load_write) begin
            flash_matched<=fl3[8:0];
            if(load_addr==0) save_flash512<=0;
            else if(fl0[9] || fl1[9] || fl2[9] || fl3[9]) save_flash512<=1;
        end
    end
    reg [6:0] eeprom_matched=0;
    function automatic [7:0] advance_eeprom(input [6:0] previous,input [7:0] value);
        begin
            advance_eeprom[0]=value==8'h45;
            advance_eeprom[1]=previous[0] && value==8'h45;
            advance_eeprom[2]=previous[1] && value==8'h50;
            advance_eeprom[3]=previous[2] && value==8'h52;
            advance_eeprom[4]=previous[3] && value==8'h4f;
            advance_eeprom[5]=previous[4] && value==8'h4d;
            advance_eeprom[6]=previous[5] && value==8'h5f;
            advance_eeprom[7]=previous[6] && value==8'h56;
        end
    endfunction
    wire [7:0] ee0=advance_eeprom(consecutive ? eeprom_matched : 7'd0,load_wdata[7:0]);
    wire [7:0] ee1=advance_eeprom(ee0[6:0],load_wdata[15:8]);
    wire [7:0] ee2=advance_eeprom(ee1[6:0],load_wdata[23:16]);
    wire [7:0] ee3=advance_eeprom(ee2[6:0],load_wdata[31:24]);
    always @(posedge clk) begin
        // A PLL reset must not switch the host port back to the independent
        // Flash array. Only configuration or an actual new ROM clears type.
        if(reset) begin eeprom_matched<=0;end
        else if(load_write) begin
            eeprom_matched<=ee3[6:0];
            if(load_addr==0) save_eeprom<=0;
            else if(ee0[7] || ee1[7] || ee2[7] || ee3[7]) save_eeprom<=1;
        end
    end
    always @(posedge clk) begin
        if(reset) begin save_sram<=0;matched<=0;history_valid<=0;next_addr<=0;end
        else if(load_write) begin
            matched<=step3[6:0];history_valid<=1;next_addr<=load_addr+1'b1;
            if(load_addr==0) save_sram<=0;
            else if(found) save_sram<=1;
        end
    end
endmodule
