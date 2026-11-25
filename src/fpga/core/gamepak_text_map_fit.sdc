# Give the routed BG3 text map to VRAM address path extra setup margin.
# The render clock's regular single-cycle period is 7.512 ns.
set text_map_address [get_registers {*gba_text_row_cache:text_rows.bg3|map_addr*}]
set vram_port_address [get_keepers {*scheduler|ram_addr*}]
if {[get_collection_size $text_map_address] == 0 || [get_collection_size $vram_port_address] == 0} {
    error "Missing text map to VRAM address endpoints"
}
set_max_delay -from $text_map_address -to $vram_port_address 7.25
