// Attach a ROM-specific nonvolatile slot after the ROM has been identified.
// APF owns the file and can flush this slot through its normal unload path.
module gba_gamepak_stats_file #(
    parameter integer TIMEOUT_BITS=6,
    parameter bit PRESELECTED_PROFILE=0
)(
    input wire clk,enable,restart,start,timeout_tick,
    input wire [31:0] game_code,rom_crc,
    output wire profile_path_read,
    output wire [3:0] profile_path_index,
    input wire [31:0] profile_path_word,
    input wire bridge_rd,
    input wire [31:0] bridge_addr,
    input wire command_done,
    input wire [2:0] command_error,
    output wire command_open,command_read,active,accept_data,
    output reg done=0,
    output reg attached=0,
    output reg [3:0] result=0,
    output wire [31:0] bridge_rdata
);
    localparam IDLE=0, NAME=1, PROBE=2, CREATE=3, LOAD=4, SETTLE=5, FINISHED=6;
    reg [2:0] phase=IDLE;
    reg submitted=0,saw_clear=0;
    reg [TIMEOUT_BITS-1:0] elapsed=0;
    reg [2:0] settle=0;
    localparam [31:0] PARAM_BASE=32'h15000000;
    wire filename_request=bridge_rd && bridge_addr[31:9]==PARAM_BASE[31:9];
    wire [6:0] word_index=bridge_addr[8:2];
    reg [3:0] char_index;
    reg [23:0] prefix_bytes;
    reg [7:0] next_char;
    reg [31:0] path_output;
    reg path_selected=0,create_flag=0;
    wire [3:0] name_address=phase==NAME ? 4'd5+{2'd0,char_index[3:2]} : word_index[3:0];
    (* ramstyle="M10K, no_rw_check" *) reg [31:0] path_words[0:15];
    initial begin
        path_words[0]=32'h2f536176;
        path_words[1]=32'h65732f67;
        path_words[2]=32'h62612f42;
        path_words[3]=32'h69744269;
        path_words[4]=32'h72642e47;
        path_words[5]=0;path_words[6]=0;path_words[7]=0;path_words[8]=0;
        path_words[9]=32'h2e67626b; // ".gbk": sidecars keep the .gbkstat name
        path_words[10]=32'h73746174;
        path_words[11]=0;path_words[12]=0;path_words[13]=0;path_words[14]=0;path_words[15]=0;
    end

    function automatic [7:0] hex_digit(input [3:0] digit);
        hex_digit=digit<10 ? {4'h3,digit} : {4'h6,4'(digit-9)};
    endfunction
    function automatic [7:0] path_char(input [7:0] letter);
        path_char=(letter>=8'h30 && letter<=8'h39) ||
                  (letter>=8'h41 && letter<=8'h5a) ? letter : 8'h5f;
    endfunction

    assign profile_path_read=PRESELECTED_PROFILE && filename_request;
    assign profile_path_index=word_index[3:0];
    assign active=phase!=IDLE && phase!=FINISHED;
    assign command_open=enable && !submitted && (phase==PROBE || phase==CREATE);
    assign command_read=enable && !submitted && phase==LOAD;
    assign accept_data=phase==LOAD && submitted;
    // Only the path is a byte array. APF reads the create flag as a scalar.
    assign bridge_rdata=path_selected ? (PRESELECTED_PROFILE ? profile_path_word : path_output) :
                                           {31'd0,create_flag};

    wire [7:0] code_letter=game_code[{2'(char_index-3),3'b000}+:8];
    wire [3:0] crc_digit=rom_crc[{~char_index[2:0],2'b00}+:4];
    always @*begin
        case(char_index)
            0:next_char=8'h42;
            1:next_char=8'h41;
            2:next_char=8'h2f;
            3,4,5,6:next_char=path_char(code_letter);
            7:next_char=8'h2d;
            default:next_char=hex_digit(crc_digit);
        endcase
    end

    always @(posedge clk)begin
        if(!PRESELECTED_PROFILE && phase==NAME)begin
            // Prepare four path words before handing them to APF when the
            // caller provides uncompressed code and CRC inputs.
            prefix_bytes<={prefix_bytes[15:0],next_char};
            if(&char_index[1:0])path_words[name_address]<={prefix_bytes,next_char};
        end else if(!PRESELECTED_PROFILE && filename_request)path_output<=path_words[name_address];
        if(filename_request)begin
            path_selected<=word_index[6:4]==0;
            create_flag<=word_index==64 && phase==CREATE;
        end
        if(!enable || restart)begin phase<=IDLE;done<=0;attached<=0;submitted<=0;result<=0;end
        else case(phase)
            IDLE:if(start)begin char_index<=0;phase<=PRESELECTED_PROFILE ? PROBE : NAME;end
            NAME:begin
                char_index<=char_index+1'b1;
                if(&char_index)phase<=PROBE;
            end
            PROBE,CREATE,LOAD:if(!submitted)begin
                submitted<=1;saw_clear<=0;elapsed<=0;
            end else begin
                if(timeout_tick)elapsed<=elapsed+1'b1;
                if(!command_done)saw_clear<=1;
                // A timeout releases startup but keeps the command pending.
                // During sleep/wake APF answers only after its state load, so
                // the file still attaches (and loads) once that reply arrives.
                if(&elapsed && !done)begin done<=1;result<=4'hf;end
                if(command_done && saw_clear)begin
                    submitted<=0;
                    case(phase)
                        PROBE:if(command_error==0)phase<=LOAD;
                            else if(command_error==3)phase<=CREATE;
                            else begin phase<=FINISHED;done<=1;result<={1'b0,command_error};end
                        CREATE:begin
                            // An existing file can appear between probe and
                            // create. Open without truncation and read it.
                            if(command_error==0)phase<=LOAD;
                            else begin
                                attached<=command_error==1;phase<=FINISHED;done<=1;
                                result<={1'b0,command_error};
                            end
                        end
                        LOAD:begin
                            attached<=command_error==0;
                            result<={1'b0,command_error};
                            settle<=0;phase<=SETTLE;
                        end
                        default:phase<=FINISHED;
                    endcase
                end
            end
            SETTLE:begin
                // Let record validation and the RTC arbiter observe the last
                // returned word before allowing the guest to start.
                settle<=settle+1'b1;
                if(&settle)begin phase<=FINISHED;done<=1;end
            end
            default:begin end
        endcase
    end
endmodule
