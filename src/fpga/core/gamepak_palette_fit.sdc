# Fit guidance for the 133 MHz runner-up palette address path. Its normal
# single-cycle requirement is 7.512 ns. Target more routing margin here.
set palette_rank [get_registers {*gba_ppu:ppu|text_composite_pipe.winners[*] *gba_ppu:ppu|text_composite_pipe.opaque[*]}]
set palette_address [get_registers {*gba_memory_map:memory|second_palette_addr[*]}]
if {[get_collection_size $palette_rank] == 0 || [get_collection_size $palette_address] == 0} {
    error "Missing palette priority-to-address endpoints"
}
set_max_delay -from $palette_rank -to $palette_address 7.20
