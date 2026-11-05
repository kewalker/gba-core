// Startup runs entirely from the board reference clock. Reset the PLL after
// configuration, synchronize both lock indications, and qualify memory reset
// release. A bounded pre-boot retry covers failure to acquire lock or finish
// memory initialization. Once readiness has been advertised, retries stop:
// imported saves and loaded ROM must never be cleared by this watchdog.
module gba_startup_reset #(
    parameter integer RETRY_BITS=22
) (
    input wire clk, core_locked_async, memory_locked_async, memory_ready,
    output wire pll_reset, core_locked, memory_locked, memory_reset,
    output reg startup_complete=0
);
    reg [7:0] reset_count=0;
    reg [7:0] settle_count=0;
    reg [RETRY_BITS-1:0] wait_count=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] core_sync=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] memory_sync=0;
    assign pll_reset=!reset_count[7];
    assign core_locked=core_sync[2] && !pll_reset;
    assign memory_locked=memory_sync[2] && core_locked;
    assign memory_reset=!core_locked || !memory_locked || !settle_count[7];
    always @(posedge clk) begin
        if(!reset_count[7]) reset_count<=reset_count+1'b1;
        if(pll_reset) core_sync<=0;
        else core_sync<={core_sync[1:0],core_locked_async};
        if(!core_locked) memory_sync<=0;
        else memory_sync<={memory_sync[1:0],memory_locked_async};
        if(!memory_locked) settle_count<=0;
        else if(!settle_count[7]) settle_count<=settle_count+1'b1;
        // Explicit reset is essential: a power-up-only sticky enable can be
        // replaced with VCC by Quartus's constant-data register optimization.
        if(pll_reset) startup_complete<=0;
        else if(!memory_reset && memory_ready) startup_complete<=1;
        if(startup_complete || pll_reset || (!memory_reset && memory_ready)) wait_count<=0;
        else if(&wait_count) begin
            reset_count<=0;
            wait_count<=0;
        end else wait_count<=wait_count+1'b1;
    end
endmodule
