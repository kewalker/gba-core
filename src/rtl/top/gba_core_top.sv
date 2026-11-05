// Project-local top-level for early simulation and bring-up.
// The Pocket APF shell will eventually wrap this module and connect these
// video signals to Analogue's host-facing framework.
module gba_core_top (
    input  logic       clk,
    input  logic       reset_n,

    output logic [8:0] video_r,
    output logic [8:0] video_g,
    output logic [8:0] video_b,
    output logic       video_de,
    output logic       video_hsync,
    output logic       video_vsync
);

    logic reset;

    assign reset = ~reset_n;

    gba_video_test_pattern video_test_pattern (
        .clk(clk),
        .reset(reset),
        .r(video_r),
        .g(video_g),
        .b(video_b),
        .de(video_de),
        .hsync(video_hsync),
        .vsync(video_vsync)
    );

endmodule
