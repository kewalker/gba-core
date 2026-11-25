// Read-only fallback for standard mask ROMs. Give every power-of-two
// boundary the same four independent word reads and wrapped references.
// The ceiling is an observation limit, distinct from a detected boundary.
module gba_gamepak_rom_size_probe (
    input wire clk, enable, start,
    output wire reader_valid,
    output wire [22:0] reader_word,
    input wire reader_ready, reader_reply,
    input wire [31:0] reader_data,
    output wire reader_reply_ready,
    output reg done=0,
    output reg [23:0] words=0,
    output reg [1:0] evidence=0
);
    localparam IDLE=0, REQUEST=1, REPLY=2;
    localparam OPEN_BUS=1, MIRROR=2, CEILING=3;
    reg [1:0] phase=IDLE;
    reg [4:0] boundary;
    reg [1:0] sample_index;
    reg upper, repeated;
    reg all_open, all_mirrored, varied;
    reg [31:0] first_sample, reference_data, first_reference;
    reg [17:0] offset;
    always @* begin
        case(sample_index)
            0:offset=18'h0002b; // game code at AC as a mirror anchor
            1:offset=18'h15ca9;
            2:offset=18'h28631;
            3:offset=18'h3b985;
        endcase
    end
    assign reader_word={upper ? boundary : 5'd0,offset};
    assign reader_valid=enable && phase==REQUEST;
    assign reader_reply_ready=enable && phase==REPLY;
    wire [15:0] halfword_address={offset[14:0],1'b0};
    wire open_sample=reader_data[15:0]==halfword_address &&
        (reader_data[31:16]==halfword_address || reader_data[31:16]==(halfword_address|16'd1));
    wire mirrored_sample=reader_data==reference_data;

    always @(posedge clk) begin
        done<=0;
        if(!enable)begin
            phase<=IDLE;words<=0;evidence<=0;
        end else case(phase)
            IDLE:if(start)begin
                phase<=REQUEST;words<=0;evidence<=0;boundary<=1;sample_index<=0;
                upper<=0;repeated<=0;all_open<=1;all_mirrored<=1;varied<=0;
            end
            REQUEST:if(reader_ready)phase<=REPLY;
            REPLY:if(reader_reply)begin
                phase<=REQUEST;
                repeated<=!repeated;
                if(!repeated)first_sample<=reader_data;
                else if(reader_data!=first_sample)begin
                    done<=1;phase<=IDLE;
                end else if(!upper)begin
                    upper<=1;
                    reference_data<=reader_data;
                    if(sample_index==0)first_reference<=reader_data;
                    else if(reader_data!=first_reference)varied<=1;
                end else begin
                    upper<=0;
                    sample_index<=sample_index+1'b1;
                    all_open<=all_open && open_sample;
                    all_mirrored<=all_mirrored && mirrored_sample;
                    if(&sample_index)begin
                        if((all_open && open_sample) || (all_mirrored && mirrored_sample && varied))begin
                            words<={1'b0,boundary,18'd0};
                            evidence<=all_open && open_sample ? OPEN_BUS : MIRROR;
                            done<=1;phase<=IDLE;
                        end else if(boundary[4])begin
                            words<=24'h800000;evidence<=CEILING;
                            done<=1;phase<=IDLE;
                        end else begin
                            boundary<=boundary<<1;all_open<=1;all_mirrored<=1;varied<=0;
                        end
                    end
                end
            end
            default:phase<=IDLE;
        endcase
    end
endmodule
