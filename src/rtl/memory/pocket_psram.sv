// Compact Cellular RAM controller for the Analogue Pocket CRAM interface.
// One request is accepted at a time.  The controller deliberately uses the
// asynchronous PSRAM protocol: address is presented on dq[15:0] and
// cram_a[21:16], latched with ADV#, then data is transferred with WE#/OE#.
module pocket_psram #(
    parameter integer READ_WAIT_CYCLES=4,
    parameter integer WRITE_WAIT_CYCLES=4,
    parameter bit FAST_READ_PINS=0
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        bank,
    input  logic [21:0] addr,
    input  logic        write_en,
    input  logic [15:0] write_data,
    input  logic        write_high,
    input  logic        write_low,
    input  logic        read_en,
    output logic        busy,
    output logic        read_valid,
    output logic [15:0] read_data,
    output logic [21:16] cram_a,
    inout  wire  [15:0] cram_dq,
    input  wire         cram_wait,
    output logic        cram_clk,
    output logic        cram_adv_n,
    output logic        cram_cre,
    output logic        cram_ce0_n,
    output logic        cram_ce1_n,
    output logic        cram_oe_n,
    output logic        cram_we_n,
    output logic        cram_ub_n,
    output logic        cram_lb_n
);
    localparam [3:0] IDLE = 0, WRITE_LATCH = 1, WRITE_DATA = 2,
                     READ_LATCH = 3, READ_ENABLE = 4, READ_CAPTURE = 5,
                     READ_HOLD = 6, WRITE_FINISH = 7, READ_RELEASE = 8;
    logic [3:0] state;
    logic [3:0] wait_count;
    logic [15:0] dq_out;
    logic dq_oe;
    logic [15:0] pending_write;
    logic [15:0] held_read_data;
    logic held_adv_n, registered_adv_n;
    logic held_read_valid;

    // ROM may place a free-running input register and the ADV output register
    // in the I/O cells. read_data is qualified only by read_valid in this mode;
    // Capture on the falling edge before the consumer's rising edge. The
    // release state preserves OE through that capture without delaying the
    // consumer or the next registered cartridge request.
    generate if (FAST_READ_PINS) begin : fast_read_pins
        always_ff @(negedge clk) begin
            read_data <= cram_dq;
            read_valid <= !reset && state==READ_RELEASE;
        end
        always_ff @(posedge clk) begin
            registered_adv_n <= reset ||
                !((state==IDLE && (write_en || read_en)) ||
                  (state==WRITE_LATCH && wait_count==0));
        end
        assign cram_adv_n = registered_adv_n;
    end else begin : held_read_pins
        assign read_data = held_read_data;
        assign read_valid = held_read_valid;
        assign cram_adv_n = held_adv_n;
    end endgenerate

    assign cram_dq = dq_oe ? dq_out : 16'hzzzz;
    assign busy = (state != IDLE);

    always_ff @(posedge clk) begin
        held_read_valid <= 1'b0;
        if (reset) begin
            state <= IDLE;
            cram_a <= 0;
            cram_clk <= 1'b0;
            held_adv_n <= 1'b1;
            cram_cre <= 1'b0;
            cram_ce0_n <= 1'b1;
            cram_ce1_n <= 1'b1;
            cram_oe_n <= 1'b1;
            cram_we_n <= 1'b1;
            cram_ub_n <= 1'b1;
            cram_lb_n <= 1'b1;
            dq_out <= 0;
            dq_oe <= 1'b0;
            held_read_data <= 0;
            pending_write <= 0;
            wait_count <= 0;
        end else begin
            case (state)
                IDLE: begin
                    held_adv_n <= 1'b1;
                    cram_ce0_n <= 1'b1;
                    cram_ce1_n <= 1'b1;
                    cram_oe_n <= 1'b1;
                    cram_we_n <= 1'b1;
                    cram_ub_n <= 1'b1;
                    cram_lb_n <= 1'b1;
                    dq_oe <= 1'b0;
                    if (write_en) begin
                        cram_a <= addr[21:16];
                        dq_out <= addr[15:0];
                        dq_oe <= 1'b1;
                        pending_write <= write_data;
                        // tBW is 70 ns from byte select to write end, not
                        // merely the 20 ns data-setup requirement. Select
                        // lanes with CE#/WE#/ADV#, then hold through data.
                        cram_ub_n <= ~write_high;
                        cram_lb_n <= ~write_low;
                        held_adv_n <= 1'b0;
                        cram_we_n <= 1'b0;
                        if (bank) cram_ce1_n <= 1'b0;
                        else     cram_ce0_n <= 1'b0;
                        wait_count <= 0;
                        state <= WRITE_LATCH;
                    end else if (read_en) begin
                        cram_a <= addr[21:16];
                        dq_out <= addr[15:0];
                        dq_oe <= 1'b1;
                        held_adv_n <= 1'b0;
                        cram_ub_n <= 1'b0;
                        cram_lb_n <= 1'b0;
                        if (bank) cram_ce1_n <= 1'b0;
                        else     cram_ce0_n <= 1'b0;
                        wait_count <= 0;
                        state <= READ_LATCH;
                    end
                end
                WRITE_LATCH: begin
                    // The address and ADV# pulse need a real setup interval.
                    // Keep WE# asserted while ADV# is released.
                    if (wait_count == 0) begin
                        wait_count <= 1;
                    end else begin
                        held_adv_n <= 1'b1;
                        wait_count <= 0;
                        state <= WRITE_DATA;
                    end
                end
                WRITE_DATA: begin
                    // Defaults preserve the 74.25 MHz interface. A caller
                    // using a slower clock may select a separately validated
                    // profile; address latch and write-end hold are unchanged.
                    dq_out <= pending_write;
                    if (wait_count < WRITE_WAIT_CYCLES) begin
                        wait_count <= wait_count + 1'b1;
                    end else begin
                        state <= WRITE_FINISH;
                    end
                end
                WRITE_FINISH: begin
                    // End the write before releasing DQ. Independent output
                    // delays can otherwise remove data before CE#/WE# rises.
                    // IDLE retains the data for one complete clock of hold.
                    cram_we_n <= 1'b1;
                    cram_ce0_n <= 1'b1;
                    cram_ce1_n <= 1'b1;
                    cram_ub_n <= 1'b1;
                    cram_lb_n <= 1'b1;
                    state <= IDLE;
                end
                READ_LATCH: begin
                    held_adv_n <= 1'b1;
                    // Keep the multiplexed address driven for a full clock
                    // after ADV# rises (CellularRAM tAVH is at least 2 ns).
                    state <= READ_HOLD;
                end
                READ_HOLD: begin
                    dq_oe <= 1'b0;
                    wait_count <= 0;
                    state <= READ_ENABLE;
                end
                READ_ENABLE: begin
                    cram_oe_n <= 1'b0;
                    // Wait for the PSRAM's access time after ADV# rises.
                    if (wait_count < READ_WAIT_CYCLES) begin
                        wait_count <= wait_count + 1'b1;
                    end else begin
                        state <= READ_CAPTURE;
                    end
                end
                READ_CAPTURE: begin
                    held_read_data <= cram_dq;
                    held_read_valid <= 1'b1;
                    if (FAST_READ_PINS) state <= READ_RELEASE;
                    else begin
                        cram_oe_n <= 1'b1;
                        state <= IDLE;
                    end
                end
                READ_RELEASE: begin
                    cram_oe_n <= 1'b1;
                    cram_ce0_n <= 1'b1;
                    cram_ce1_n <= 1'b1;
                    cram_ub_n <= 1'b1;
                    cram_lb_n <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
