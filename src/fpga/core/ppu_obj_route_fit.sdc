# Guide placement of the two measured OBJ cache setup paths. The renderer
# keeps its 7.512 ns cycle and all normal timing checks.
set restore_render [get_keepers {*gba_state_video:state_video|render_sync[2]}]
set obj_width [get_keepers {*gba_obj_row_cache:object_rows.rows|width_shift*}]
set obj_response [get_keepers {*scheduler|obj_word_addr[*] *gba_obj_row_cache:object_rows.rows|response_tag[*]}]
set obj_cached_data [get_keepers {*gba_obj_row_cache:object_rows.rows|cached_data[*]}]
if {[get_collection_size $restore_render] == 0 || [get_collection_size $obj_width] == 0 ||
    [get_collection_size $obj_response] == 0 || [get_collection_size $obj_cached_data] == 0} {
    error "Missing measured OBJ cache timing endpoints"
}
set_max_delay -from $restore_render -to $obj_width 7.15
set_max_delay -from $obj_response -to $obj_cached_data 7.25
