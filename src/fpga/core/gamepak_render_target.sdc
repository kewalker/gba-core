# Bound the raster coordinate path already covered by the 30 ns hardware
# audit. The two clocks share a clock group only to permit this constraint.
set raster_clock [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set render_clock [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}]
set coordinate_regs [get_keepers {*gba_ppu:ppu|x* *gba_ppu:ppu|y*}]
# Mosaic lookups share the same 30 ns address budget (check-mosaic-timing.tcl).
set mosaic_regs [get_keepers -nowarn {*gba_mosaic_coordinate:mosaic_horizontal* *gba_mosaic_coordinate:mosaic_vertical*}]
set vram_address_regs [get_keepers {*scheduler|ram_addr*}]
if {[get_collection_size $raster_clock] != 1 || [get_collection_size $render_clock] != 1 ||
    [get_collection_size $coordinate_regs] != 17 || [get_collection_size $vram_address_regs] != 15 ||
    [get_collection_size $mosaic_regs] == 0} {
    error "Unexpected raster timing endpoints: clocks [get_collection_size $raster_clock]/[get_collection_size $render_clock], registers [get_collection_size $coordinate_regs]/[get_collection_size $vram_address_regs], mosaic [get_collection_size $mosaic_regs]"
}
set coordinate_regs [add_to_collection $coordinate_regs $mosaic_regs]
set raster_sinks [get_fanouts -no_logic [get_clock_info -targets $raster_clock]]
set render_sinks [get_fanouts -no_logic [get_clock_info -targets $render_clock]]
if {[get_collection_size [remove_from_collection $coordinate_regs $raster_sinks]] ||
    [get_collection_size [remove_from_collection $vram_address_regs $render_sinks]] ||
    [get_collection_size $raster_sinks] != [get_collection_size [remove_from_collection $raster_sinks $render_sinks]]} {
    error "Raster timing endpoints are outside the expected clock domains"
}
set other_raster_regs [remove_from_collection $raster_sinks $coordinate_regs]
set other_render_regs [remove_from_collection $render_sinks $vram_address_regs]
set_false_path -from $render_clock -to $raster_clock
set_false_path -from $raster_clock -to $other_render_regs
set_false_path -from $other_raster_regs -to $vram_address_regs
set_max_delay -from $coordinate_regs -to $vram_address_regs 28.0
set_min_delay -from $coordinate_regs -to $vram_address_regs 0.0
