// RIMSTATION EDIT ADDITION - the whole file. A PDA keeps what is inside it.

/**
 * A modular computer is a container that nothing was walking.
 *
 * It is not /obj/item/storage, and it had no on_object_saved(), so the serializer wrote the shell and dropped
 * everything in it. A colonist who put their ID in their PDA - which is where an ID lives - came back to an
 * empty PDA and no card, while the same card left loose in a backpack survived.
 */
/obj/item/modular_computer/on_object_saved(map_string, turf/current_loc, list/obj_blacklist)
	save_stored_contents(map_string, current_loc, obj_blacklist)

/**
 * Stops the loaded computer from building a second cell and disk for the saved ones to land beside.
 *
 * Initialize() turns these two typepaths into instances. The real ones are saved as contents, so the vars are
 * blanked in the save and re-pointed by PersistentInitialize() once the contents are back inside.
 */
/obj/item/modular_computer/get_custom_save_vars(save_flags = ALL)
	. = ..()
	.[NAMEOF(src, inserted_disk)] = null
	.[NAMEOF(src, internal_cell)] = null
	return .

/**
 * Puts the restored contents back into the slots they came out of.
 *
 * link_loaded_containers() has already moved them inside, but every slot is a var and no var holding a datum
 * survives a map file. Without this the computer is loaded holding its own contents and reporting none of them:
 * no cell, so it will not turn on, and no ID, so the card reads as gone.
 *
 * Two ID cards cannot be told apart once they are both loose in contents, so the first found takes the main
 * slot and the second the alt slot. That is the order they were written in, and a second card is rare.
 */
/obj/item/modular_computer/PersistentInitialize()
	. = ..()
	for(var/obj/item/restored in contents)
		if(isnull(internal_cell) && istype(restored, /obj/item/stock_parts/power_store))
			internal_cell = restored
			continue
		if(isnull(inserted_disk) && istype(restored, /obj/item/disk/computer))
			inserted_disk = restored
			continue
		if(isnull(inserted_pai) && istype(restored, /obj/item/pai_card))
			inserted_pai = restored
			continue
		if(!istype(restored, /obj/item/card/id))
			continue
		if(isnull(stored_id))
			stored_id = restored
		else if(isnull(alt_stored_id))
			alt_stored_id = restored

	update_appearance()
	update_slot_icon()
