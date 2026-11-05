// 240x160 active-area test pattern for the first Pocket bring-up.
module gba_video_test_pattern (
    input  logic       clk,
    input  logic       reset,

    output logic [8:0] r,
    output logic [8:0] g,
    output logic [8:0] b,
    output logic       de,
    output logic       hsync,
    output logic       vsync
);

    localparam int ACTIVE_W = 240;
    localparam int ACTIVE_H = 160;
    localparam int H_FRONT  = 16;
    localparam int H_SYNC   = 16;
    localparam int H_BACK   = 32;
    localparam int V_FRONT  = 8;
    localparam int V_SYNC   = 4;
    localparam int V_BACK   = 16;

    localparam int TOTAL_W = ACTIVE_W + H_FRONT + H_SYNC + H_BACK;
    localparam int TOTAL_H = ACTIVE_H + V_FRONT + V_SYNC + V_BACK;

    logic [$clog2(TOTAL_W)-1:0] x;
    logic [$clog2(TOTAL_H)-1:0] y;

    always_ff @(posedge clk) begin
        if (reset) begin
            x <= '0;
            y <= '0;
        end else if (x == TOTAL_W - 1) begin
            x <= '0;
            if (y == TOTAL_H - 1) begin
                y <= '0;
            end else begin
                y <= y + 1'b1;
            end
        end else begin
            x <= x + 1'b1;
        end
    end

    always_comb begin
        de = (x < ACTIVE_W) && (y < ACTIVE_H);
        hsync = (x >= ACTIVE_W + H_FRONT) && (x < ACTIVE_W + H_FRONT + H_SYNC);
        vsync = (y >= ACTIVE_H + V_FRONT) && (y < ACTIVE_H + V_FRONT + V_SYNC);

        r = 9'd0;
        g = 9'd0;
        b = 9'd0;

        if (de) begin
            r = {x[7:0], 1'b0};
            g = {y[7:0], 1'b0};
            b = {x[5:0] ^ y[5:0], 3'b000};

            if (x < 8 || x >= ACTIVE_W - 8 || y < 8 || y >= ACTIVE_H - 8) begin
                r = 9'h1ff;
                g = 9'h1ff;
                b = 9'h1ff;
            end
        end
    end

endmodule

