/obj/item/disk/get_save_vars(save_flags=ALL)
	. = ..()
	. += NAMEOF(src, icon_state)

/obj/item/disk/data/get_save_vars(save_flags=ALL)
	. = ..()
	. += NAMEOF(src, read_only)

/obj/item/disk/tech_disk/get_custom_save_vars(save_flags=ALL)
	. = ..()
	if(!length(stored_research.researched_nodes))
		return
	.[NAMEOF(src, persistent_datum_data)] = assoc_to_keys(stored_research.researched_nodes)

/obj/item/disk/tech_disk/PersistentInitialize()
	. = ..()
	if(!LAZYLEN(persistent_datum_data))
		return
	for(var/node in persistent_datum_data)
		stored_research.research_node_id(node, TRUE, FALSE, FALSE)
	persistent_datum_data = null
