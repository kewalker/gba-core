// Dispatcher for the machine copier's single outstanding descriptor. Register
// and RAM commands share ONE clock crossing; raw saves and RTC reuse their
// existing host-clock ports. The caller holds target/address through response.
module gba_state_machine_access #(
    parameter integer TIMEOUT_CYCLES=7425000
)(
    input wire host_clk,guest_clk,reset,host_held,guest_held,
    input wire request_valid,request_write,response_ready,
    input wire [1:0] request_target,
    input wire [31:0] request_addr,request_wdata,
    output wire request_ready,response_valid,response_error,
    output wire [31:0] response_rdata,
    output wire register_write,
    output wire [15:0] register_addr,
    output wire [31:0] register_wdata,
    input wire register_valid,
    input wire [31:0] register_rdata,
    output wire ram_valid,ram_write,ram_response_ready,
    output wire [31:0] ram_addr,ram_wdata,
    input wire ram_ready,ram_response,ram_error,
    input wire [31:0] ram_rdata,
    output wire raw_access,raw_eeprom,raw_write,raw_read,
    output wire [14:0] raw_addr,
    output wire [31:0] raw_wdata,
    input wire raw_idle,raw_done,raw_fault,
    input wire [31:0] raw_rdata,
    input wire rtc_ready,
    output wire rtc_word_write,
    output wire [1:0] rtc_word_index,
    output wire [31:0] rtc_word_data,
    input wire [31:0] rtc_word_rdata
);
    // Hold the complete descriptor before routing it. Virtual section address
    // translation must not also drive the save/RTC response and payload enables
    // in the same host cycle. One outstanding request keeps cancellation and
    // response ownership explicit across the extra admission clock.
    reg active=0,issued=0,discarding=0;
    reg held_write=0;
    reg [1:0] held_target=0;
    reg [31:0] held_addr=0,held_wdata=0;
    wire routed_ready,routed_response,routed_error;
    wire [31:0] routed_rdata;
    wire routed_valid=active && !issued && !reset && !discarding;
    wire routed_response_ready=active && issued && (response_ready || discarding || reset);
    assign request_ready=!active && !reset;
    assign response_valid=active && issued && routed_response && !discarding && !reset;
    assign response_error=routed_error;
    assign response_rdata=routed_rdata;
    always @(posedge host_clk)begin
        if(reset)begin
            // Shared CDC cancellation drains its accepted epoch. Local save
            // and RTC endpoints reset synchronously with this dispatcher.
            if(active && issued && held_target<2)discarding<=1;
            else begin active<=0;issued<=0;discarding<=0;end
        end
        else begin
            if(request_valid && request_ready)begin
                active<=1;issued<=0;discarding<=0;held_write<=request_write;
                held_target<=request_target;held_addr<=request_addr;held_wdata<=request_wdata;
            end
            if(routed_valid && routed_ready)issued<=1;
        end
        if(active && issued && routed_response && routed_response_ready)begin
            active<=0;issued<=0;discarding<=0;
        end
    end
    wire crossing_ready,crossing_response,crossing_error;
    wire [31:0] crossing_data;
    wire destination_valid,destination_write,destination_reply_ready,destination_target;
    wire [31:0] destination_addr,destination_data;
    wire register_ready,register_response,register_error;
    wire [31:0] register_result;
    gba_state_async_port crossing(.source_clk(host_clk),.source_cancel(reset),
        .source_valid(routed_valid && held_target<2),.source_write(held_write),
        .source_response_ready(routed_response_ready && held_target<2),.source_target(held_target[0]),
        .source_addr(held_addr),.source_wdata(held_wdata),.source_ready(crossing_ready),
        .source_response(crossing_response),.source_busy(),.source_error(crossing_error),.source_rdata(crossing_data),
        .destination_clk(guest_clk),.destination_cancel(reset || !guest_held),
        .destination_valid,.destination_write,.destination_response_ready(destination_reply_ready),
        .destination_target,.destination_addr,.destination_wdata(destination_data),
        .destination_ready(destination_target ? ram_ready : register_ready),
        .destination_response(destination_target ? ram_response : register_response),
        .destination_error(destination_target ? ram_error : register_error),
        .destination_rdata(destination_target ? ram_rdata : register_result));
    gba_state_register_access #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) registers(
        .clk(guest_clk),.cancel(reset),.held(guest_held),
        .request_valid(destination_valid && !destination_target),.request_write(destination_write),
        .response_ready(destination_reply_ready && !destination_target),
        .request_addr(destination_addr),.request_wdata(destination_data),.request_ready(register_ready),
        .response_valid(register_response),.response_error(register_error),.response_rdata(register_result),
        .register_addr,.register_wdata,.register_write,.register_valid,.register_rdata);
    assign ram_valid=destination_valid && destination_target;
    assign ram_write=destination_write;
    assign ram_response_ready=destination_reply_ready && destination_target;
    assign ram_addr=destination_addr;
    assign ram_wdata=destination_data;
    wire save_ready,save_response,save_error;
    wire [31:0] save_data;
    gba_state_save_access saves(.clk(host_clk),.reset,.held(host_held),
        .request_valid(routed_valid && held_target==2),.request_write(held_write),
        .response_ready(routed_response_ready && held_target==2),.request_addr(held_addr),.request_wdata(held_wdata),
        .request_ready(save_ready),.response_valid(save_response),.response_error(save_error),.response_rdata(save_data),.busy(),
        .raw_access,.raw_eeprom,.raw_write,.raw_read,.raw_addr,.raw_wdata,.raw_rdata,
        .flash_idle(raw_idle),.flash_done(raw_done),.eeprom_idle(raw_idle),.eeprom_done(raw_done),.backend_fault(raw_fault));
    reg rtc_response=0,rtc_error=0;
    reg [31:0] rtc_result=0;
    wire rtc_accept=routed_valid && held_target==3 && !rtc_response && !reset;
    assign rtc_word_index=held_addr[1:0];
    assign rtc_word_data=held_wdata;
    assign rtc_word_write=rtc_accept && held_write && host_held && !reset && rtc_ready && held_addr<4;
    always @(posedge host_clk)begin
        if(reset)rtc_response<=0;
        else if(rtc_response && routed_response_ready && held_target==3)rtc_response<=0;
        if(rtc_accept)begin
            rtc_response<=1;rtc_error<=reset || !host_held || !rtc_ready || held_addr>=4;
            rtc_result<=rtc_word_rdata;
        end
    end
    assign routed_ready=held_target<2 ? crossing_ready : held_target==2 ? save_ready : !rtc_response;
    assign routed_response=held_target<2 ? crossing_response : held_target==2 ? save_response : rtc_response;
    assign routed_error=held_target<2 ? crossing_error : held_target==2 ? save_error : rtc_error;
    assign routed_rdata=held_target<2 ? crossing_data : held_target==2 ? save_data : rtc_result;
endmodule
