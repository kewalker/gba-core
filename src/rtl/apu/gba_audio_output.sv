// 48 kHz, 16-bit stereo in 32-bit I2S slots. All serialization runs on the
// Pocket's existing 12.288 MHz PLL clock; no fabric-generated internal clocks.
module gba_audio_output (
    input wire clk_audio, clk_source, reset,
    input wire [15:0] sample_left, sample_right,
    output wire mclk,
    output logic lrck, dac
);
    logic request_toggle, ack_toggle;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] request_sync,ack_sync;
    logic [31:0] mailbox;
    logic [31:0] frame;
    logic [1:0] divider;
    logic [5:0] bit_index;
    assign mclk=clk_audio;
    // Mailbox data is held until the next request (one audio frame later).
    // The acknowledged data has two synchronizer clocks plus a full frame
    // to settle before use; left/right are always captured together.
    always_ff @(posedge clk_source or posedge reset) begin
        if(reset) begin request_sync<=0;ack_toggle<=0;mailbox<=0;end
        else begin
            request_sync<={request_sync[0],request_toggle};
            if(request_sync[1]!=ack_toggle) begin
                mailbox<={sample_left,sample_right};ack_toggle<=request_sync[1];
            end
        end
    end
    always_ff @(posedge clk_audio or posedge reset) begin
        if(reset) begin
            ack_sync<=0;request_toggle<=0;frame<=0;divider<=0;
            bit_index<=0;lrck<=0;dac<=0;
        end else begin
            ack_sync<={ack_sync[0],ack_toggle};
            divider<=divider+1'b1;
            // Falling edge of the implicit MCLK/4 bit clock.
            if(divider==3) begin
                bit_index<=bit_index+1'b1;
                if(bit_index==31) lrck<=1;
                if(bit_index==63) begin
                    lrck<=0;
                    if(ack_sync[1]==request_toggle) begin
                        frame<=mailbox;
                        request_toggle<=~request_toggle;
                    end
                end
                if(bit_index<16) dac<=frame[31-bit_index];
                else if(bit_index>=32 && bit_index<48) dac<=frame[47-bit_index];
                else dac<=0;
            end
        end
    end
endmodule
