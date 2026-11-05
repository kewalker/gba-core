// Host-clock adapter for the EXISTING raw save port. Upstream owns the freeze
// barrier and host-port arbitration. One descriptor and one response, no RAM,
// command-engine writes or second storage controller. Accepted work always
// drains its real completion, even after hold is withdrawn or reset requested.
module gba_state_save_access(
    input wire clk,reset,held,
    input wire request_valid,request_write,response_ready,
    input wire [31:0] request_addr,request_wdata,
    output wire request_ready,response_valid,busy,
    output reg response_error,
    output reg [31:0] response_rdata,
    output wire raw_access,raw_eeprom,raw_write,raw_read,
    output wire [14:0] raw_addr,
    output wire [31:0] raw_wdata,
    input wire flash_idle,flash_done,eeprom_idle,eeprom_done,backend_fault,
    input wire [31:0] raw_rdata
);
    localparam IDLE=0,SELECT=1,ISSUE=2,WAIT=3,RESPONSE=4;
    reg [2:0] phase=IDLE;
    reg selected_eeprom=0,selected_write=0,aborting=0,owns_port=0;
    reg [14:0] selected_addr=0;
    reg [31:0] selected_data=0;
    wire is_eeprom=request_addr>=32'h0d000000 && request_addr<32'h0d002000;
    wire is_flash=request_addr>=32'h0e000000 && request_addr<32'h0e020000;
    wire address_ok=request_addr[1:0]==0 && (is_eeprom || is_flash);
    wire selected_idle=selected_eeprom ? eeprom_idle : flash_idle;
    wire selected_done=selected_eeprom ? eeprom_done : flash_done;
    wire completion=selected_eeprom ? eeprom_done : flash_done;
    // Select the port from a registered descriptor BEFORE acknowledging it.
    // This breaks virtual-address translation -> raw-port selection -> backend
    // idle -> copier ready without accepting a transaction that cannot drain.
    assign request_ready=phase==SELECT && !reset &&
        (!held || !owns_port || backend_fault || (selected_idle && !selected_done));
    assign busy=phase!=IDLE;
    assign response_valid=phase==RESPONSE;
    // A SELECT request is not accepted yet: withdrawal releases it without a
    // reply or strobe. Accepted work retains ownership through its response.
    // One selected idle/done pair may be wired to both backend status inputs.
    // Selection is held from the registered descriptor until SELECT observes
    // withdrawal at an edge. It never emits a strobe before acceptance. Using
    // live request_valid here recreated the copier-target -> selected-status
    // -> ready feedback path that descriptor registration was meant to break.
    assign raw_access=owns_port && ((phase==SELECT && held && !reset && !backend_fault) ||
        phase==ISSUE || phase==WAIT || phase==RESPONSE);
    assign raw_eeprom=selected_eeprom;
    assign raw_write=phase==ISSUE && selected_write && held && !reset && !backend_fault;
    assign raw_read=phase==ISSUE && !selected_write && held && !reset && !backend_fault;
    assign raw_addr=selected_addr;
    assign raw_wdata=selected_data;
    always @(posedge clk)begin
        if(phase==IDLE)begin
            if(reset)begin response_error<=0;response_rdata<=0;aborting<=0;end
            else if(request_valid)begin
                selected_eeprom<=is_eeprom;selected_write<=request_write;
                selected_addr<=request_addr[16:2];selected_data<=request_wdata;
                response_rdata<=0;response_error<=0;aborting<=0;
                owns_port<=held && address_ok && !backend_fault;
                phase<=SELECT;
            end
        end else begin
            if(reset || !held || backend_fault)aborting<=1;
            case(phase)
                SELECT:begin
                    if(reset || !request_valid)phase<=IDLE;
                    else if(request_ready)begin
                        if(!held || !owns_port || backend_fault)begin response_error<=1;phase<=RESPONSE;end
                        else phase<=ISSUE;
                    end
                end
                ISSUE:begin
                    // Port arbitration/freeze remains upstream until this
                    // accepted descriptor completes. Never invent an ACK.
                    if(reset || !held || backend_fault)begin response_error<=1;phase<=RESPONSE;end
                    else phase<=WAIT;
                end
                WAIT:if(completion)begin
                    response_rdata<=raw_rdata;
                    response_error<=aborting || reset || !held || backend_fault;
                    phase<=RESPONSE;
                end
                RESPONSE:if(response_ready)phase<=IDLE;
                default:phase<=IDLE;
            endcase
        end
    end
endmodule
