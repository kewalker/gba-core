// External save storage: host port is synchronous to mem_clk (74.25 MHz).
// APF permits at most one host word per 88 clocks. A pending host word takes
// priority after at most one in-flight word. Guest requests use a held mailbox;
// its state deliberately survives emulated CPU reset, draining accepted writes.
module gba_save_sram_backend (
    input wire clk, mem_clk, load_reset,
`ifdef GBK_SAVESTATE
    output wire state_host_idle,
    output reg state_host_done=0,
`endif
    input wire req, write,
    input wire [14:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] mask,
    output reg [31:0] rdata=0,
    output reg ready=0,
    output wire guest_idle,
    input wire host_write, host_read,
    input wire [14:0] host_addr,
    input wire [31:0] host_wdata,
    output reg [31:0] host_rdata=0,
    output reg host_valid=0,
    output wire boot_ready,
    output reg fault=0,
    output wire [16:0] sram_a,
    inout wire [15:0] sram_dq,
    output wire sram_oe_n, sram_we_n, sram_ub_n, sram_lb_n
);
    reg request_toggle=0, pending=0;
    reg held_write=0;
    reg [14:0] held_addr=0;
    reg [31:0] held_data=0;
    reg [3:0] held_mask=0;
    reg response_toggle=0;
    reg [31:0] response_data=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] response_sync=0;
    reg [31:0] response_data_1=0, response_data_2=0;
    assign guest_idle=!pending;
    always @(posedge clk) begin
        response_sync<={response_sync[1:0],response_toggle};
        response_data_1<=response_data; response_data_2<=response_data_1;
        ready<=0;
        if(pending) begin
            if(response_sync[2]==request_toggle) begin
                rdata<=response_data_2; ready<=1; pending<=0;
            end
        end else if(req && !ready) begin
            held_write<=write; held_addr<=addr; held_data<=wdata; held_mask<=mask;
            request_toggle<=!request_toggle; pending<=1;
        end
    end
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] request_sync=0;
    reg write_1=0, write_2=0;
    reg [14:0] addr_1=0, addr_2=0;
    reg [31:0] data_1=0, data_2=0;
    reg [3:0] mask_1=0, mask_2=0;
    reg seen=0, initialized=0, inflight=0;
    reg [14:0] init_addr=0;
    reg host_pending=0, host_is_write=0, active_host_write=0;
    reg [14:0] host_address=0;
    reg [31:0] host_data=0;
    localparam INIT=0, HOST=1, GUEST=2;
    reg [1:0] owner=INIT;
    wire pin_ready, pin_done;
    wire [31:0] pin_data;
    // Qualify startup with the synchronized PLL reset, independently of the
    // guest reset (which cannot be released until this fill completes).
    reg [7:0] cold_count=0;
    reg [6:0] init_wait=0;
    wire cold_reset=!initialized && (load_reset || !cold_count[7]);
    // A word normally completes in 28 clocks. Restart the *whole* blank fill
    // if its sequencer recovers to IDLE without returning a completion.
    // Recovery is restricted to pre-import initialization: never erase a save
    // or hide a missing runtime completion after advertising readiness.
    // Count ALL lack of progress, including a pin FSM stuck before accepting
    // the first request. Counting only inflight leaves that case deadlocked.
    wire init_timeout=!initialized && init_wait==7'd64;
    wire pin_reset=cold_reset || init_timeout;
    wire launch=!pin_reset && pin_ready && !inflight && (!initialized || host_pending || request_sync[2]!=seen);
    wire select_host=initialized && host_pending;
    wire select_guest=initialized && !host_pending;
    wire pop_host=launch && select_host;
`ifdef GBK_SAVESTATE
    assign state_host_idle=initialized && !fault && !inflight && !host_pending && request_sync[2]==seen;
`endif
    assign boot_ready=initialized && !fault;
    pocket_sram pins (
        .clk(mem_clk),.reset(pin_reset),.req(launch),
        .write(!initialized || (select_host ? host_is_write : write_2)),
        .addr(!initialized ? init_addr : (select_host ? host_address : addr_2)),
        .wdata(!initialized ? 32'hffffffff : (select_host ? host_data : data_2)),
        .mask(!initialized || select_host ? 4'b1111 : mask_2),
        .ready(pin_ready),.done(pin_done),.rdata(pin_data),
        .sram_a,.sram_dq,.sram_oe_n,.sram_we_n,.sram_ub_n,.sram_lb_n
    );
    always @(posedge mem_clk) begin
        if(!initialized && load_reset) cold_count<=0;
        else if(!cold_count[7]) cold_count<=cold_count+1'b1;
        if(!initialized && !pin_reset && !(pin_done && inflight && owner==INIT)) init_wait<=init_wait+1'b1;
        else init_wait<=0;
        request_sync<={request_sync[1:0],request_toggle};
        write_1<=held_write; write_2<=write_1;
        addr_1<=held_addr; addr_2<=addr_1;
        data_1<=held_data; data_2<=data_1;
        mask_1<=held_mask; mask_2<=mask_1;
        host_valid<=0;
`ifdef GBK_SAVESTATE
        state_host_done<=0;
`endif
        if(launch) begin
            inflight<=1;
            owner<=!initialized ? INIT : (select_host ? HOST : GUEST);
            if(select_guest) seen<=request_sync[2];
            if(select_host) begin host_pending<=0; active_host_write<=host_is_write; end
        end
        if(pin_done && inflight) begin
            inflight<=0;
            case(owner)
                INIT: if(init_addr==15'h7fff) initialized<=1;
                    else init_addr<=init_addr+1'b1;
                HOST: begin host_rdata<=pin_data; host_valid<=!active_host_write;
`ifdef GBK_SAVESTATE
                    state_host_done<=1;
`endif
                end
                GUEST: begin response_data<=pin_data; response_toggle<=seen; end
            endcase
        end
        // The raw bridge may still be settling during cold initialization.
        // APF cannot grant a save transfer until boot/slot readiness is high;
        // these early strobes must not permanently poison that readiness.
        // After initialization, retain strict overflow/collision detection:
        // APF provides no per-word backpressure for an accepted transfer.
        if(initialized && (host_write || host_read)) begin
            if((host_pending && !pop_host) || (host_write && host_read)) fault<=1;
            else begin
                host_pending<=1; host_is_write<=host_write;
                host_address<=host_addr; host_data<=host_wdata;
            end
        end
        if(pin_reset) begin
            initialized<=0; init_addr<=0; inflight<=0; init_wait<=0;
            owner<=INIT; host_pending<=0; active_host_write<=0;
            fault<=0; host_valid<=0;
        end
    end
endmodule
