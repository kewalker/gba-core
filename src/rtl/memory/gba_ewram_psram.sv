// 256 KiB GBA EWRAM backed by Pocket CRAM1.
// The GBA bus is 32-bit while CRAM is 16-bit, so every operation is two
// halfword transactions for a word; narrow stores use one transaction.
// A retained aligned word avoids redundant reads after reads or writes.
module gba_ewram_psram #(parameter bit SLOW_CLOCK=0) (
    input  logic        clk,
    input  logic        reset,
    input  logic        req,
        input  logic        write,
        input  logic [31:0] addr,
        input  logic [31:0] wdata,
        input  logic [1:0]  size,
    output logic [31:0] rdata,
    output logic        ready,
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
    localparam [3:0] IDLE = 0, WRITE_LOW = 1, WRITE_LOW_WAIT = 2,
                     WRITE_HIGH = 3, WRITE_HIGH_WAIT = 4,
                     READ_LOW = 5, READ_LOW_WAIT = 6,
                     READ_HIGH = 7, READ_HIGH_WAIT = 8, ACK = 9;
    logic [3:0] state;
    logic [21:0] half_addr;
    logic [31:0] write_data;
    logic [1:0] write_size;
    logic [1:0] write_byte_addr;
    logic [15:0] read_low;
    logic ps_write, ps_read, ps_busy, ps_valid;
    logic [21:0] ps_addr;
    logic [15:0] ps_wdata, ps_rdata;
    logic ps_seen_busy;
    logic ps_write_high, ps_write_low;
    logic cached_word_valid;

    // Only enable at <=40 MHz. At 39.936 MHz the reduced waits retain
    // >=100 ns ADV-to-write-end and >=125 ns ADV-to-read-capture.
    // The ROM/loader's 74.25 MHz physical instance keeps its defaults.
    pocket_psram #(.READ_WAIT_CYCLES(SLOW_CLOCK ? 2 : 4),
                  .WRITE_WAIT_CYCLES(SLOW_CLOCK ? 2 : 4)) psram (
        .clk, .reset, .bank(1'b0), .addr(ps_addr),
        .write_en(ps_write), .write_data(ps_wdata),
        .write_high(ps_write_high), .write_low(ps_write_low),
        .read_en(ps_read), .busy(ps_busy),
        .read_valid(ps_valid), .read_data(ps_rdata),
        .cram_a, .cram_dq, .cram_wait,
        .cram_clk, .cram_adv_n, .cram_cre,
        .cram_ce0_n, .cram_ce1_n, .cram_oe_n, .cram_we_n,
        .cram_ub_n, .cram_lb_n
    );

    always_ff @(posedge clk) begin
        ps_write <= 1'b0;
        ps_read <= 1'b0;
        ps_write_high <= 1'b0;
        ps_write_low <= 1'b0;
        ready <= 1'b0;
        if (reset) begin
            state <= IDLE;
            half_addr <= 0;
            write_data <= 0;
            write_size <= 2'b10;
            write_byte_addr <= 0;
            read_low <= 0;
            rdata <= 0;
            ps_addr <= 0;
            ps_wdata <= 0;
            ps_seen_busy <= 1'b0;
            cached_word_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: if (req) begin
                    half_addr <= {addr[17:2], 1'b0};
                    write_data <= wdata;
                    write_size <= size;
                    write_byte_addr <= addr[1:0];
                    if(write) begin
                        // All writers (CPU and DMA) share this port. Keep a
                        // complete store, or merge a narrow store into the
                        // retained word. No reader can observe it until the
                        // physical write has completed and ACK has retired.
                        if(size==2'b10) begin
                            rdata<=wdata;
                            cached_word_valid<=1;
                        end else if(cached_word_valid && half_addr[16:1]==addr[17:2]) begin
                            if(size==2'b01) begin
                                if(addr[1]) rdata[31:16]<=wdata[15:0];
                                else rdata[15:0]<=wdata[15:0];
                            end else begin
                                case(addr[1:0])
                                    0:rdata[7:0]<=wdata[7:0];
                                    1:rdata[15:8]<=wdata[7:0];
                                    2:rdata[23:16]<=wdata[7:0];
                                    3:rdata[31:24]<=wdata[7:0];
                                endcase
                            end
                        end else cached_word_valid<=0;
                        // Narrow upper-half stores need no lower-half cycle.
                        state <= size!=2'b10 && addr[1] ? WRITE_HIGH : WRITE_LOW;
                    end else if(cached_word_valid && half_addr[16:1]==addr[17:2]) begin
                        // rdata already holds this complete aligned word.
                        ready<=1;
                        state<=ACK;
                    end else begin
                        cached_word_valid<=0;
                        state<=READ_LOW;
                    end
                end
                WRITE_LOW: if (!ps_busy) begin
                    ps_addr <= half_addr;
                    ps_wdata <= (write_size == 2'b00 && write_byte_addr[0])
                        ? {write_data[7:0], 8'b0} : write_data[15:0];
                    if (write_size == 2'b10 ||
                        (write_size == 2'b01 && !write_byte_addr[1])) begin
                        ps_write_high <= 1'b1;
                        ps_write_low <= 1'b1;
                    end else if (write_size == 2'b00 && !write_byte_addr[1]) begin
                        ps_write_high <= write_byte_addr[0];
                        ps_write_low <= !write_byte_addr[0];
                    end
                    ps_write <= 1'b1;
                    ps_seen_busy <= 1'b0;
                    state <= WRITE_LOW_WAIT;
                end
                WRITE_LOW_WAIT: begin
                    if (ps_busy) ps_seen_busy <= 1'b1;
                    else if (ps_seen_busy) begin
                        if(write_size==2'b10) state<=WRITE_HIGH;
                        else begin ready<=1;state<=ACK;end
                    end
                end
                WRITE_HIGH: if (!ps_busy) begin
                    ps_addr <= half_addr + 1'b1;
                    ps_wdata <= (write_size == 2'b00 && write_byte_addr[0])
                        ? {write_data[7:0], 8'b0} :
                        // Narrow stores are right-justified on the CPU bus.
                        // Byte offset 2 uses the low input byte, just like 0.
                        (write_size != 2'b10 ? write_data[15:0] : write_data[31:16]);
                    if (write_size == 2'b10 ||
                        (write_size == 2'b01 && write_byte_addr[1])) begin
                        ps_write_high <= 1'b1;
                        ps_write_low <= 1'b1;
                    end else if (write_size == 2'b00 && write_byte_addr[1]) begin
                        ps_write_high <= write_byte_addr[0];
                        ps_write_low <= !write_byte_addr[0];
                    end
                    ps_write <= 1'b1;
                    ps_seen_busy <= 1'b0;
                    state <= WRITE_HIGH_WAIT;
                end
                WRITE_HIGH_WAIT: begin
                    if (ps_busy) ps_seen_busy <= 1'b1;
                    else if (ps_seen_busy) begin
                        ready <= 1'b1;
                        state <= ACK;
                    end
                end
                READ_LOW: if (!ps_busy) begin
                    ps_addr <= half_addr;
                    ps_read <= 1'b1;
                    state <= READ_LOW_WAIT;
                end
                READ_LOW_WAIT: if (ps_valid) begin
                    read_low <= ps_rdata;
                    state <= READ_HIGH;
                end
                READ_HIGH: if (!ps_busy) begin
                    ps_addr <= half_addr + 1'b1;
                    ps_read <= 1'b1;
                    state <= READ_HIGH_WAIT;
                end
                READ_HIGH_WAIT: if (ps_valid) begin
                    rdata <= {ps_rdata, read_low};
                    cached_word_valid <= 1'b1;
                    ready <= 1'b1;
                    state <= ACK;
                end
                // ready is consumed on this edge. Do not accept the still
                // asserted old request as a second memory transaction.
                ACK: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
