// Guest-clock endpoint behind the single asynchronous command port. Flat image
// indices map to the existing shared register bus; no peripheral is duplicated.
// A read waits for native synchronous storage to settle. Writes commit on one
// valid edge, and the response remains held through cancellation/reset.
//
// GBK_STATE_SERIAL: words with a nonzero serial width are flop rings inside
// their peripheral. After the word reports valid, the ring shifts exactly
// `width` times (LSB first) within a fixed 32-clock window: a read rotates it
// home while sampling register_rdata[0]; a write shifts register_wdata[0] in.
// The image word is bit-identical to the parallel layout. Once a ring starts
// moving it always completes, so cancellation cannot leave it half-rotated.
module gba_state_register_access #(
    parameter integer TIMEOUT_CYCLES=7425000
)(
    input wire clk,cancel,held,
    input wire request_valid,request_write,response_ready,
    input wire [31:0] request_addr,request_wdata,
    output wire request_ready,response_valid,
    output reg response_error=0,
    output reg [31:0] response_rdata=0,
    output reg [15:0] register_addr=0,
    output reg [31:0] register_wdata=0,
    output wire register_write,
`ifdef GBK_STATE_SERIAL
    output wire [1:0] register_shift, // {restore, shift}
`endif
    input wire register_valid,
    input wire [31:0] register_rdata
);
    localparam IDLE=0,ACCESS=1,RESPONSE=2,SHIFT=3;
    localparam WAIT_BITS=TIMEOUT_CYCLES>1 ? $clog2(TIMEOUT_CYCLES) : 1;
    reg [1:0] phase=IDLE;
    reg writing=0;
    reg [WAIT_BITS-1:0] elapsed=0;
    function automatic [15:0] address_of(input [7:0] index);
        reg [7:0] group_address,index_base;
        begin
            group_address=0;index_base=0;
            if(index<45)begin group_address=0;index_base=0;end
            else if(index<52)begin group_address=1;index_base=45;end
            else if(index<86)begin group_address=2;index_base=52;end
            else if(index<95)begin group_address=3;index_base=86;end
            else if(index<97)begin group_address=4;index_base=95;end
            else if(index<101)begin group_address=5;index_base=97;end
            else if(index<127)begin group_address=6;index_base=101;end
            else if(index<147)begin group_address=7;index_base=127;end
            else if(index<175)begin group_address=7;index_base=115;end
            else if(index<185)begin group_address=8;index_base=175;end
            else if(index==185)begin group_address=9;index_base=185;end
            else if(index<190)begin group_address=9;index_base=170;end
            else begin group_address=10;index_base=190;end
            // One narrow subtraction serves every group; do not infer a
            // separate 16-bit address adder for each mutually exclusive case.
            address_of=index<194 ? {group_address,8'(index-index_base)} : 16'h073f;
        end
    endfunction
    // Serial ring width of each bus address; 0 keeps the parallel access.
    // This is the single definition: peripherals implement exactly these
    // rings and testbenches call this function hierarchically.
    function automatic [5:0] serial_width(input [15:0] address);
        reg [7:0] offset;
        begin
            serial_width=0;offset=address[7:0];
`ifdef GBK_STATE_SERIAL
            case(address[15:8])
                // CPU: banked SP/LR of SVC, IRQ, UND, FIQ and ABT plus User.
                // PC, CPSR and SPSRs keep the parallel path (execution
                // timing; SPSRs read through current_spsr).
                0:case(offset)
                    18,19,20,21,23,24,26,27,29,30,32,33:serial_width=32;
                    default:serial_width=0;
                endcase
                // Scheduler: debt and the three next-event timestamps.
                // Phase is parameter-width; words 2/3 carry prefetch state.
                1:case(offset)
                    1:serial_width=12;
                    4,5,6:serial_width=32;
                    default:serial_width=0;
                endcase
                // DMA: per channel source, dest, SAD, DAD latches,
                // control:count, reload count, two zero words; then the
                // pending/FIFO word and the active channel.
                2:if(offset<32)case(offset[2:0])
                    0,1,4:serial_width=32;
                    2,3:serial_width=28;
                    5:serial_width=16;
                    default:serial_width=0;
                endcase
                else if(offset==32)serial_width=10;
                else if(offset==33)serial_width=2;
                // Timers: reload:count and control:prescale per timer, IRQs.
                3:if(offset<8)serial_width=32;
                    else if(offset==8)serial_width=4;
                // Sound: SOUNDCNT, master enable and the two FIFO pointer
                // words; PSG frame/wave position, per-channel state and
                // period, noise reload, LFSR and sweep (PSG words 8-19 at
                // 40-51). PSG registers, wave RAM and FIFO data stay parallel.
                7:case(offset)
                    0:serial_width=32;
                    1:serial_width=1;
                    2,3,40:serial_width=24;
                    41:serial_width=27;
                    42,44:serial_width=14;
                    43,47:serial_width=21;
                    45:serial_width=10;
                    46:serial_width=13;
                    48,49:serial_width=23;
                    50:serial_width=15;
                    51:serial_width=22;
                    default:serial_width=0;
                endcase
                // Serial port: data words and the packed transfer state.
                // SIOCNT/RCNT restore through masks; pin synchronizers
                // keep sampling, so both stay parallel.
                8:case(offset)
                    2,3,4,5,7,8:serial_width=32;
                    6:serial_width=24;
                    default:serial_width=0;
                endcase
                default:serial_width=0;
            endcase
`endif
        end
    endfunction
    function automatic [5:0] width_of(input [7:0] index);
        width_of=index<194 ? serial_width(address_of(index)) : 6'd0;
    endfunction
    // Materialize the fixed layout in one block ROM. Its registered output
    // doubles as the address latch for the synchronous peripheral bus.
`ifdef GBK_STATE_SERIAL
    (* ramstyle="M10K" *) reg [21:0] addresses[0:255];
    initial for(integer index=0;index<256;index=index+1)
        addresses[index]={width_of(8'(index)),address_of(8'(index))};
    reg [5:0] width=0;
    reg [4:0] count=0;
    wire shifting=phase==SHIFT && {1'b0,count}<width;
    assign register_shift={writing,shifting};
`else
    (* ramstyle="M10K" *) reg [15:0] addresses[0:255];
    initial for(integer index=0;index<256;index=index+1)
        addresses[index]=address_of(8'(index));
`endif

    wire address_ok=request_addr<194 || (request_addr==255 && !request_write);
    assign request_ready=phase==IDLE;
    assign response_valid=phase==RESPONSE;
`ifdef GBK_STATE_SERIAL
    assign register_write=phase==ACCESS && writing && width==0 && held && !cancel && register_valid;
`else
    assign register_write=phase==ACCESS && writing && held && !cancel && register_valid;
`endif
    initial if(TIMEOUT_CYCLES<1)$error("Invalid register access timeout");
    always @(posedge clk)case(phase)
        IDLE:if(request_valid && request_ready)begin
`ifdef GBK_STATE_SERIAL
            {width,register_addr}<=addresses[request_addr[7:0]];
`else
            register_addr<=addresses[request_addr[7:0]];
`endif
            register_wdata<=request_wdata;
            writing<=request_write;elapsed<=0;response_error<=0;response_rdata<=0;
            if(cancel || !held || !address_ok)begin response_error<=1;phase<=RESPONSE;end
            else phase<=ACCESS;
        end
        ACCESS:if(cancel || !held)begin response_error<=1;phase<=RESPONSE;end
`ifdef GBK_STATE_SERIAL
            else if(register_valid && width!=0)begin count<=0;phase<=SHIFT;end
`endif
            else if(register_valid)begin response_rdata<=register_rdata;phase<=RESPONSE;end
            else if(elapsed==TIMEOUT_CYCLES-1)begin response_error<=1;phase<=RESPONSE;end
            else elapsed<=elapsed+1'b1;
`ifdef GBK_STATE_SERIAL
        SHIFT:begin
            response_rdata<={shifting && register_rdata[0],response_rdata[31:1]};
            register_wdata<={1'b0,register_wdata[31:1]};
            count<=count+1'b1;
            if(count==31)begin
                if(cancel || !held)response_error<=1;
                phase<=RESPONSE;
            end
        end
`endif
        RESPONSE:if(response_ready)phase<=IDLE;
        default:phase<=IDLE;
    endcase
endmodule
