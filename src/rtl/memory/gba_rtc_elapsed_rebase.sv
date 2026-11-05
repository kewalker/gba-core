// One shared serial divider advances seconds, minutes and hours. Calendar
// fields stay in BCD throughout; no parallel decimal dividers or multipliers.
module gba_rtc_elapsed_rebase #(parameter IN_PLACE=0)(
    input wire clk,reset,start,
    input wire [55:0] saved_calendar,
    input wire [31:0] elapsed_seconds,
    input wire [55:0] live_calendar,
    output wire seed,adjust,advance_day,
    output wire [1:0] adjust_field,
    output wire [7:0] adjust_value,
    output reg busy=0,
    output reg done=0,
    output reg valid=0,
    output reg [55:0] calendar=0
);
    function automatic good_bcd(input [7:0] b,input [7:0] maximum);
        good_bcd=b[3:0]<10 && b[7:4]<10 && b<=maximum;
    endfunction
    function automatic [7:0] bcd_next(input [7:0] b);
        bcd_next=b[3:0]==9 ? b+8'd7 : b+1'b1;
    endfunction
    function automatic [7:0] last_day(input [7:0] yy,mm);
        case(mm)
            2:last_day=((yy[1:0]+{yy[4],1'b0}) & 2'b11)==0 ? 8'h29 : 8'h28;
            4,6,9,8'h11:last_day=8'h30;
            default:last_day=8'h31;
        endcase
    endfunction
    (* romstyle="M10K" *) reg [7:0] decimal_table[0:63];
    reg [7:0] decimal_value=0;
    initial for(integer n=0;n<64;n=n+1)decimal_table[n]=((n/10)<<4)+(n%10);
    wire acceptable=good_bcd(saved_calendar[7:0],8'h99) &&
        good_bcd(saved_calendar[15:8],8'h12) && saved_calendar[15:8]!=0 &&
        good_bcd(saved_calendar[23:16],last_day(saved_calendar[7:0],saved_calendar[15:8])) && saved_calendar[23:16]!=0 &&
        saved_calendar[31:24]<=6 && good_bcd(saved_calendar[39:32],8'h23) &&
        good_bcd(saved_calendar[47:40],8'h59) && good_bcd(saved_calendar[55:48],8'h59);
    reg [31:0] dividend=0;
    reg [5:0] remainder=0;
    reg [4:0] bit_index=0;
    reg [1:0] field=0,phase=0;
    wire [55:0] work_calendar=IN_PLACE ? live_calendar : calendar;
    assign seed=IN_PLACE && start && !busy && acceptable && !reset;
    assign adjust=IN_PLACE && busy && phase==3 && !reset;
    assign advance_day=IN_PLACE && busy && phase==2 && dividend[15:0]!=0 && !reset;
    assign adjust_field=field;
    assign adjust_value=decimal_value;
    wire [5:0] divisor=field==2 ? 6'd24 : 6'd60;
    wire [6:0] trial={remainder,dividend[31]};
    wire quotient_bit=trial>={1'b0,divisor};
    wire [7:0] saved_field=field==0 ? work_calendar[55:48] : field==1 ? work_calendar[47:40] : work_calendar[39:32];
    wire [5:0] binary_field={2'd0,saved_field[7:4]}*6'd10+{2'd0,saved_field[3:0]};
    wire [6:0] sum={1'b0,remainder}+{1'b0,binary_field};
    wire carry=sum>={1'b0,divisor};
    wire [5:0] reduced=carry ? sum-{1'b0,divisor} : sum;
    wire [31:0] carried_quotient=dividend+{31'd0,carry};
    always @(posedge clk)if(busy && phase==1)decimal_value<=decimal_table[reduced];
    always @(posedge clk)begin
        done<=0;
        if(reset)begin busy<=0;done<=0;valid<=0;end
        else if(start && !busy)begin
            valid<=0;
            if(!acceptable)done<=1;
            else begin
                if(!IN_PLACE)calendar<=saved_calendar;
                dividend<=elapsed_seconds;
                remainder<=0;bit_index<=0;field<=0;phase<=0;busy<=1;
            end
        end else if(busy)begin
            case(phase)
                0:begin
                    dividend<={dividend[30:0],quotient_bit};
                    remainder<=quotient_bit ? trial-{1'b0,divisor} : trial;
                    bit_index<=bit_index+1'b1;
                    if(bit_index==31)phase<=1;
                end
                1:phase<=3;
                3:begin
                    if(!IN_PLACE)case(field)
                        0:calendar[55:48]<=decimal_value;
                        1:calendar[47:40]<=decimal_value;
                        default:calendar[39:32]<=decimal_value;
                    endcase
                    dividend<=carried_quotient;remainder<=0;
                    if(field==2)phase<=2;
                    else begin field<=field+1'b1;phase<=0;end
                end
                default:if(dividend[15:0]!=0)begin
                    dividend[15:0]<=dividend[15:0]-1'b1;
                    if(!IN_PLACE)begin
                    calendar[26:24]<=calendar[26:24]==6 ? 3'd0 : calendar[26:24]+1'b1;
                    if(calendar[23:16]==last_day(calendar[7:0],calendar[15:8]))begin
                        calendar[23:16]<=1;
                        if(calendar[15:8]==8'h12)begin
                            calendar[15:8]<=1;
                            calendar[7:0]<=calendar[7:0]==8'h99 ? 8'd0 : bcd_next(calendar[7:0]);
                        end else calendar[15:8]<=bcd_next(calendar[15:8]);
                    end else calendar[23:16]<=bcd_next(calendar[23:16]);
                    end
                end else begin valid<=1;busy<=0;done<=1;end
            endcase
        end
    end
endmodule
