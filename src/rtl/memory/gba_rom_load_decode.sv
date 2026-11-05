// All three Game Pak windows alias the complete32 MiB cartridge aperture.
// A word index needs23 bits; dropping bridge bit24 wraps loads at16 MiB.
module gba_rom_load_decode(
    input wire bridge_write,input wire [31:0] bridge_addr,
    output wire load_write,output wire [22:0] load_addr
);
    assign load_write=bridge_write && bridge_addr[31:24]>=8'h08 && bridge_addr[31:24]<=8'h0d;
    assign load_addr=bridge_addr[24:2];
endmodule
