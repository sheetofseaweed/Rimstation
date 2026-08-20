// RIMSTATION EDIT ADDITION - the whole file. ID cards keep what is printed on them.

/**
 * An ID card is almost entirely the data written on it, and none of that data is in the save whitelist.
 *
 * The whitelist an object saves by default is `color, dir, pixel_x, pixel_y, density, opacity, anchored,
 * resistance_flags, req_access, id_tag, obj_flags` - note that `req_access` is what a door *demands*, not what
 * a card *carries*. So a saved card came back as blank plastic: no owner, no age, no assignment, no access.
 *
 * That was invisible while carried items were deleted outright at the end of every chapter. Once colonists
 * started keeping what they were wearing, it became a colony of people holding each other's anonymous cards.
 *
 * `name` is deliberately not saved: it is generated from the owner and assignment by update_label(), so
 * restoring those two and relabelling produces the right name without storing a second copy of it.
 */
/obj/item/card/id/get_save_vars(save_flags = ALL)
	. = ..()
	. += NAMEOF(src, registered_name)
	. += NAMEOF(src, registered_age)
	. += NAMEOF(src, assignment)
	. += NAMEOF(src, access)
	return .

/**
 * A trim is a singleton datum, which cannot be written into a map file. Its type can.
 *
 * The path is written into `trim` itself and turned back into the datum by PersistentInitialize(), so the card
 * carries a typepath for the short window between being loaded and being initialised.
 */
/obj/item/card/id/get_custom_save_vars(save_flags = ALL)
	. = ..()
	if(trim)
		.[NAMEOF(src, trim)] = trim.type
	return .

/**
 * Turns the saved trim path back into a trim, without letting it overwrite what the card actually said.
 *
 * apply_trim_to_card() clears access and rewrites assignment from the trim, because its usual job is printing
 * a fresh card. Here the card is the record and the trim is only the template it was printed from, so what was
 * saved is put back over the top.
 *
 * Trim restoration is best-effort on purpose: SSatoms does not depend on SSid_access, so the trim singletons
 * may not exist yet when this runs. A card that loses its trim still has its owner, assignment and access,
 * which is the part that matters; one that lost those would be a blank.
 */
/obj/item/card/id/PersistentInitialize()
	. = ..()
	if(!ispath(trim, /datum/id_trim))
		return

	var/trim_path = trim
	// Cleared first so nothing can mistake a typepath for the datum that belongs here.
	trim = null

	var/list/saved_access = access?.Copy()
	var/saved_assignment = assignment

	if(length(SSid_access.trim_singletons_by_path) && SSid_access.trim_singletons_by_path[trim_path])
		SSid_access.apply_trim_to_card(src, trim_path, copy_access = FALSE)
	else
		log_game("A saved ID card carried trim '[trim_path]', which could not be applied. The card keeps its own access.")

	access = saved_access || list()
	assignment = saved_assignment
	update_label()
	update_icon()
