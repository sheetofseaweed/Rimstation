// Stickers and hand-labeller labels are held by /datum/component/sticker, and the stuck atom sits in nullspace.
// The serializer walks turf contents, so neither the component nor the atom it holds was ever seen: a labelled
// crate came back unlabelled. Each stuck atom is written as a container child of what it is stuck to, carrying
// the offsets it was applied at, and re-attached through the component on load.
//
// Do not "fix" this by adding name to /atom/get_save_vars() instead. That restores the text without the label,
// so it cannot be peeled off, it examines as unlabelled, and the label re-appends to the restored name on the
// next save. It also fights every type that builds its name during Initialize() - stacks, material-derived
// items, greyscale items - which would silently discard the saved value or double up on it.
//
// Only /obj parents are covered. Closed turfs never reach this path (the writer only calls property saving for
// open turfs), and mobs are not restored through the container system.

/**
 * Writes every atom stuck to this one into the map as a container child.
 *
 * Kept separate from on_object_saved() because container types override that without calling parent, and
 * save_stored_contents() cannot be reused here - it always walks contents, which would double-save them.
 */
/atom/proc/save_attached_stickers(map_string, turf/current_loc, list/obj_blacklist)
	if(!HAS_TRAIT(src, TRAIT_STICKERED))
		return

	// reuse the id if on_object_saved() already claimed one for stored contents
	var/parent_container_id_tag = GLOB.save_containers_parents[src]

	for(var/datum/component/sticker/stuck_component as anything in GetComponents(/datum/component/sticker))
		var/atom/movable/stuck_atom = stuck_component.our_sticker
		if(isnull(stuck_atom) || !stuck_atom.is_saveable(current_loc, obj_blacklist))
			continue

		if(!parent_container_id_tag)
			parent_container_id_tag = assign_random_name()
			GLOB.save_containers_parents[src] = parent_container_id_tag

		GLOB.save_containers_children[stuck_atom] = parent_container_id_tag
		GLOB.save_sticker_offsets[stuck_atom] = list(stuck_component.px, stuck_component.py)

		var/metadata = generate_tgm_metadata(stuck_atom)
		TGM_MAP_BLOCK(map_string, stuck_atom.type, metadata)

/**
 * Re-attaches this atom to what it was stuck to before the save.
 *
 * Called instead of moving the atom into the container's contents. Subtypes that carry their own stick
 * bookkeeping (callbacks, examine text) override this to route through their own attach proc.
 */
/atom/movable/proc/restore_stuck_to(atom/target, px, py)
	target.AddComponent(/datum/component/sticker, src, target.dir, px, py)

/obj/item/label/restore_stuck_to(atom/target, px, py)
	stick_to_atom(target, px, py)
	// the maploader assigns label_name directly, so the label's own name was never rebuilt from it
	update_appearance(UPDATE_NAME)

/obj/item/label/get_save_vars(save_flags=ALL)
	. = ..()
	. += NAMEOF(src, label_name)
	return .

/obj/item/sticker/restore_stuck_to(atom/target, px, py)
	attempt_attach(target, null, px, py)

/obj/item/sticker/get_save_vars(save_flags=ALL)
	. = ..()
	// subtypes with an icon_states list roll a random one, so it is not derivable from the typepath
	. += NAMEOF(src, icon_state)
	return .
