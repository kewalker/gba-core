// One-port PPU read scheduler for shared VRAM.
//
// The PPU exposes several logical read addresses (BG map/tile and OBJ tile),
// but they are sampled while a pixel is held for several fast render clocks.
// This module services those addresses round-robin through one registered
// dual-port RAM read port and holds each returned halfword for the PPU.
module gba_vram_render_scheduler #(
    parameter integer WORDS = 24576,
    parameter integer PORTS = 10,
    parameter bit WINDOW_SLOT_ALIASES = 1'b0
) (
    input  logic                 cpu_clk,
    input  logic                 reset,
    input  logic                 cpu_write,
    input  logic [$clog2(WORDS)-1:0] cpu_addr,
    input  logic [31:0]           cpu_wdata,
    input  logic [3:0]            cpu_byteena,
    output logic [31:0]           cpu_rdata,
    input  logic                 render_clk,
    input  logic                 mode2_window_reads,
    input  logic                 mode1_affine_reads,
    input  logic                 mode2_affine_reads,
    input  logic [PORTS*17-1:0]   render_addr_flat,
    output logic [PORTS*16-1:0]   render_data_flat,
    output logic [31:0]          obj_word_data,
    output logic [15:0]          obj_word_addr,
    output logic                 obj_word_valid
);
    logic [$clog2(WORDS)-1:0] ram_addr;
    logic [$clog2(WORDS)-1:0] next_ram_addr;
    logic [31:0] ram_cpu_rdata;
    logic [31:0] ram_render_rdata;
    logic [$clog2(PORTS)-1:0] selected_port;
    logic [PORTS-1:0] selected_lane;
    wire wrap_round=selected_port == PORTS-1 ||
        (PORTS>8 && WINDOW_SLOT_ALIASES && mode2_window_reads && selected_port>=7);
    wire [$clog2(PORTS)-1:0] next_port=wrap_round ? '0 : selected_port+1'b1;
    logic [$clog2(PORTS)-1:0] issued_port;
    logic [$clog2(PORTS)-1:0] waiting_port;
    logic [$clog2(PORTS)-1:0] returned_port;
    logic issued_halfword;
    logic waiting_halfword;
    logic returned_halfword;
    logic [16:0] selected_addr;
    logic [15:0] obj_issued_addr;
    integer i;

    gba_vram_dualport #(.WORDS(WORDS)) storage (
        .cpu_clk, .cpu_write, .cpu_addr, .cpu_wdata, .cpu_byteena,
        .cpu_rdata(ram_cpu_rdata),
        .ppu_clk(render_clk), .ppu_addr(ram_addr),
        .ppu_rdata(ram_render_rdata)
    );
    assign cpu_rdata = ram_cpu_rdata;

    always_comb begin
        // Decode the slot in parallel with each address's range check.
        // A variable slice followed by the range check put both mux levels
        // after the dependent affine tile address on the fast RAM path.
        selected_addr = '0;
`ifndef GBK_SAVESTATE
        next_ram_addr = '0;
`endif
        for (integer port_index = 0; port_index < PORTS; port_index = port_index + 1) begin
            selected_addr = selected_addr |
                (render_addr_flat[port_index*17 +: 17] & {17{selected_lane[port_index]}});
`ifndef GBK_SAVESTATE
            next_ram_addr = next_ram_addr |
                (render_addr_flat[port_index*17+1 +: $clog2(WORDS)] &
                 {$clog2(WORDS){selected_lane[port_index] &&
                    render_addr_flat[port_index*17+1 +: 16] < WORDS}});
`endif
        end
    end
`ifdef GBK_SAVESTATE
    // Bound the late address mux to a two-input group and a final group OR.
    // The serial accumulation inferred five LUT levels after the affine
    // address. Keep group outputs separate without adding a register/cycle.
    localparam integer ADDRESS_BITS=$clog2(WORDS),ADDRESS_GROUPS=(PORTS+1)/2;
    wire [ADDRESS_BITS-1:0] address_terms[0:ADDRESS_GROUPS*2-1];
    wire [ADDRESS_BITS-1:0] address_groups[0:ADDRESS_GROUPS-1];
    genvar term,group_index;
    generate for(term=0;term<ADDRESS_GROUPS*2;term=term+1)begin : address_term
        if(term<PORTS)assign address_terms[term]=
            render_addr_flat[term*17+1 +: ADDRESS_BITS] &
            {ADDRESS_BITS{selected_lane[term] && render_addr_flat[term*17+1 +: 16]<WORDS}};
        else assign address_terms[term]='0;
    end
    for(group_index=0;group_index<ADDRESS_GROUPS;group_index=group_index+1)begin : address_group
        (* keep = 1 *) wire [ADDRESS_BITS-1:0] kept_address;
        assign kept_address=address_terms[group_index*2] |
            address_terms[group_index*2+1];
        assign address_groups[group_index]=kept_address;
    end endgenerate
    always_comb begin
        next_ram_addr='0;
        for(integer group_index=0;group_index<ADDRESS_GROUPS;group_index=group_index+1)
            next_ram_addr=next_ram_addr | address_groups[group_index];
    end
`endif

    always_ff @(posedge render_clk) begin
        if (reset) begin
            selected_port <= '0;
            selected_lane <= {{(PORTS-1){1'b0}},1'b1};
            issued_port <= '0;
            waiting_port <= '0;
            returned_port <= '0;
            issued_halfword <= 1'b0;
            waiting_halfword <= 1'b0;
            returned_halfword <= 1'b0;
            ram_addr <= '0;
            render_data_flat <= '0;
            obj_word_data <= '0;
            obj_word_addr <= '0;
            obj_word_valid <= 1'b0;
            obj_issued_addr <= '0;
        end else begin
            // Production slot 7 is OBJ. Preserve the complete physical word
            // so adjacent sprite halfwords do not need separate VRAM turns.
            // Slot 7 cannot be reissued before its three-stage response.
            // Hold its aligned address until that response, then publish the
            // tag with the data. Consumers need not wait a fixed worst case.
            if (selected_port == 7) obj_issued_addr <= selected_addr[16:1];
            obj_word_valid <= returned_port == 7;
            if (returned_port == 7) begin
                obj_word_data <= ram_render_rdata;
                obj_word_addr <= obj_issued_addr;
            end
            render_data_flat[returned_port*16 +: 16] <=
                returned_halfword ? ram_render_rdata[31:16] : ram_render_rdata[15:0];
            // Break the path from a BG read result through its dependent
            // tile address into the physical VRAM address register.
            ram_addr <= next_ram_addr;
            // Mode 1 has two map/tile pairs for affine BG2. Publish both
            // map samples to slot 4 and both tile samples to slot 9; leaving
            // the duplicate results unconsumed misses the shortest dot's
            // deadline when the affine map entry changes.
            // Native mode 2 likewise publishes its two pairs under map
            // tag 0 and tile tag 5; OBJ row RAM supplies its window mask.
            // Mode 2 has no text BG1. Reuse its slots for a second
            // sample of each window mask, tagging the result for the
            // original mask output. Halfword tags follow the same pipeline.
            if (WINDOW_SLOT_ALIASES && mode1_affine_reads) begin
                case(selected_port)
                    0,5: issued_port <= 4;
                    1: issued_port <= 0;
                    2: issued_port <= 1;
                    3: issued_port <= 2;
                    4,9: issued_port <= 9;
                    6: issued_port <= 3;
                    8: issued_port <= 6;
                    default: issued_port <= selected_port;
                endcase
            end else if (WINDOW_SLOT_ALIASES && mode2_affine_reads) begin
                case(selected_port)
                    0,2:issued_port<=0;
                    1,3:issued_port<=4;
                    4,6:issued_port<=5;
                    5:issued_port<=3;
                    default:issued_port<=selected_port;
                endcase
            end
            else if (WINDOW_SLOT_ALIASES && mode2_window_reads && selected_port == 2)
                issued_port <= 6;
            else if (WINDOW_SLOT_ALIASES && mode2_window_reads && selected_port == 3)
                issued_port <= 1;
            else
                issued_port <= selected_port;
            issued_halfword <= selected_addr[0];
            // RAM has a clocked address and a clocked output. Keep the
            // destination tag and halfword selection aligned with both.
            waiting_port <= issued_port;
            waiting_halfword <= issued_halfword;
            returned_port <= waiting_port;
            returned_halfword <= waiting_halfword;
            // Preserve the BIOS mode-2 eight-slot cadence. Mode 0 adds
            // dedicated BG3 text map/tile slots at the end of the round.
            selected_port <= next_port;
            selected_lane <= PORTS'(1) << next_port;
        end
    end
endmodule
