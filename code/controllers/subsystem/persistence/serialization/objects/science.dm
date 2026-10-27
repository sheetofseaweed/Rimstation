/obj/item/disk/get_save_vars(save_flags=ALL)
	. = ..()
	. += NAMEOF(src, icon_state)

/obj/item/disk/data/get_save_vars(save_flags=ALL)
	. = ..()
	. += NAMEOF(src, read_only)

// The disk holds node typepaths itself now, rather than a techweb to replay them into, so the list is written
// straight out. Initialize() only fills stored_nodes when it is not already a list, so the saved value stands.
/obj/item/disk/tech_disk/get_custom_save_vars(save_flags=ALL)
	. = ..()
	if(!length(stored_nodes))
		return
	.[NAMEOF(src, stored_nodes)] = stored_nodes.Copy()
