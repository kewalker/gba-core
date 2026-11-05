// Minimal GBA interrupt controller: IE, IF, and IME.
// VBlank is IF bit 0; each timer keeps its own overflow source in bits 3..6.
module gba_interrupts (
    input  logic        clk,
    input  logic        reset,
`ifdef GBK_SAVESTATE
    input wire state_hold,state_write,state_addr,
    input wire [31:0] state_wdata,
    output wire state_valid,
    output wire [31:0] state_rdata,
`endif
    input  logic        req,
    input  logic        write,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input logic [1:0] size,
    input  logic        vblank_irq,
    input logic hblank_irq, vcount_irq,
    input  logic [3:0]  timer_irq,
    input  logic [3:0]  dma_irq,
    input wire keypad_irq,serial_irq,gamepak_irq,
    output logic [31:0] rdata,
    output logic        ready,
    output logic [31:0] debug_ie_if,
    output logic        debug_ime,
    output logic        irq,
    output wire         halt_wake,stop_wake
);
    logic [15:0] ie_reg;
    logic [15:0] if_reg;
    logic        ime_reg;
`ifdef GBK_SAVESTATE
    wire state_frozen=state_hold===1'b1;
    assign state_valid=!reset && state_frozen;
    assign state_rdata=state_valid ? (state_addr ? {31'd0,ime_reg} : {if_reg,ie_reg}) : 32'd0;
`endif
    wire [15:0] irq_sources = {2'b0,gamepak_irq===1'b1, keypad_irq===1'b1, dma_irq, serial_irq===1'b1, timer_irq,
        vcount_irq === 1'b1, hblank_irq === 1'b1, vblank_irq};
    wire [31:0] write_mask = size == 2'b00 ? (32'hff << (addr[1:0]*8)) :
        size == 2'b10 ? 32'hffffffff : (32'hffff << (addr[1]*16));
    wire [31:0] write_bits = (size == 2'b10 ? wdata : wdata << (addr[1:0]*8)) & write_mask;

    wire hit = (addr[31:24] == 8'h04) &&
               ((addr[15:2] == (16'h0200 >> 2)) ||
                (addr[15:2] == (16'h0208 >> 2)));

    assign ready = !req || !hit || write || hit;
    assign debug_ie_if = {if_reg, ie_reg};
    assign debug_ime = ime_reg;
    assign halt_wake = |(ie_reg & if_reg);
    assign stop_wake = |(ie_reg & if_reg & 16'h3080);
    assign irq = ime_reg && halt_wake;
    always_comb begin
        case ({addr[15:2],2'b00})
            // IE and IF occupy one naturally aligned 32-bit word.  Besides
            // halfword reads, the BIOS IRQ dispatcher uses LDR [04000200]
            // and intersects the low (IE) and high (IF) halves.  Returning
            // an individually packed register here makes that read appear
            // to have no pending source, leaving IF uncleared and causing
            // an IRQ-entry loop.
            16'h0200,
            16'h0202: rdata = {if_reg, ie_reg};
            16'h0208: rdata = {31'b0, ime_reg};
            default:  rdata = 32'b0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            ie_reg <= 16'b0;
            if_reg <= 16'b0;
            ime_reg <= 1'b0;
`ifdef GBK_SAVESTATE
        end else if(state_frozen)begin
            // Direct restore is distinct from normal IF write-one-to-clear.
            if(state_write && state_valid)begin
                if(state_addr)ime_reg<=state_wdata[0];
                else begin ie_reg<=state_wdata[15:0];if_reg<=state_wdata[31:16];end
            end
`endif
        end else begin
            // IF latches a source edge until software acknowledges it by
            // writing a one.  Sources must win if an acknowledgement and a
            // new edge happen in the same clock.
            if_reg <= if_reg | irq_sources;
            if (req && write && hit) begin
                case ({addr[15:2],2'b00})
                    16'h0200: begin
                        ie_reg <= ((ie_reg & ~write_mask[15:0]) | write_bits[15:0]) & 16'h3fff;
                        if_reg <= (if_reg & ~write_bits[31:16]) | irq_sources;
                    end
                    16'h0208: if(write_mask[0]) ime_reg <= write_bits[0];
                    default: begin end
                endcase
            end
        end
    end
endmodule
