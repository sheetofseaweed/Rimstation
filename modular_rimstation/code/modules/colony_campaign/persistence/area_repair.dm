/**
 * Splits an area that a load merged back into the rooms it was made of.
 *
 * Only for colonies saved before areas carried their identity. Those checkpoints have every player-built room
 * collapsed into one area - usually the one named "Space", since that is what the bare /area type is called -
 * and nothing on disk says where the walls between them were.
 *
 * What is recoverable is the shape: a room is still airtight, so detect_room() finds it again from any tile
 * inside it. What is not recoverable is the name, because it was never written down. Each rebuilt room is
 * numbered, and the colony can rename it with blueprints the same way it named it the first time.
 *
 * Rooms are found from APCs rather than from every tile, because an APC is what makes the split worth doing -
 * a room with its own APC is a room paying its own power bill - and because starting from arbitrary tiles would
 * carve the outdoors into hundreds of fragments.
 */

/// Matches the blueprint limit, which is what drew these rooms. Not shared: the original is #undef'd on sight.
#define COLONY_REPAIR_MAX_ROOM_SIZE 300
ADMIN_VERB(rimstation_resplit_merged_area, R_ADMIN, "Resplit Merged Colony Area", "Rebuilds the rooms inside an area that a checkpoint load merged together.", ADMIN_CATEGORY_PERSISTENCE)
	var/list/candidates = list()
	for(var/area/candidate as anything in GLOB.areas)
		if(length(candidate.apcs_in_area()) > 1)
			candidates[candidate.name] = candidate

	if(!length(candidates))
		to_chat(user, span_warning("No area holds more than one APC, so nothing here looks merged."))
		return

	var/chosen_name = tgui_input_list(user, "Which area should be split back into rooms?", "Colony Area Repair", candidates)
	if(isnull(chosen_name))
		return

	var/area/merged = candidates[chosen_name]
	if(QDELETED(merged))
		to_chat(user, span_warning("That area is gone."))
		return

	var/split = resplit_area_by_apcs(merged)
	if(!split)
		to_chat(user, span_warning("No airtight room could be found around any APC in [merged.name]. Nothing was changed."))
		return

	message_admins("[key_name_admin(user)] split [split] room(s) out of the merged area '[chosen_name]'.")
	log_admin("[key_name(user)] split [split] room(s) out of the merged area '[chosen_name]'.")
	to_chat(user, span_notice("Rebuilt [split] room(s). They are numbered, not named - the names were never saved. \
		Blueprints will rename them."))

/// Every APC whose area is this one. The area's own `apc` var holds only the last one to claim it.
/area/proc/apcs_in_area()
	RETURN_TYPE(/list)
	. = list()
	for(var/obj/machinery/power/apc/found as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/power/apc))
		if(found.area == src)
			. += found

/**
 * Gives each APC in a merged area the airtight room around it, as its own area.
 *
 * The first room found keeps nothing: every room is moved out into a new area, and whatever is left - corridors,
 * outdoors, anything with no APC - stays in the area they were merged into. Returns how many rooms were split.
 */
/proc/resplit_area_by_apcs(area/merged)
	if(!isarea(merged))
		return 0

	// Same break list create_area() uses, so a room that blueprints would refuse is refused here too.
	var/static/list/room_breakers = typecacheof(list(
		/turf/open/space,
		/area/shuttle,
	))

	var/split = 0
	for(var/obj/machinery/power/apc/anchor as anything in merged.apcs_in_area())
		var/list/room = detect_room(get_turf(anchor), room_breakers, COLONY_REPAIR_MAX_ROOM_SIZE * 2)
		if(!length(room) || length(room) > COLONY_REPAIR_MAX_ROOM_SIZE)
			continue

		// Rooms already moved out are not merged any more, so a later APC must not drag them back.
		var/list/still_merged = list()
		for(var/turf/candidate as anything in room)
			if(get_area(candidate) == merged)
				still_merged += candidate
		if(!length(still_merged))
			continue

		split++
		var/area/rebuilt = new merged.type(null)
		rebuilt.setup("Recovered Room [split]")
		rebuilt.outdoors = merged.outdoors
		rebuilt.default_gravity = merged.default_gravity
		rebuilt.AddComponent(/datum/component/custom_area)
		GLOB.custom_areas[rebuilt] = TRUE

		set_turfs_to_area(still_merged, rebuilt)
		rebuilt.reg_in_areas_in_z()
		rebuilt.power_change()

	if(split)
		for(var/obj/machinery/door/firedoor/firelock as anything in merged.firedoors)
			firelock.CalculateAffectingAreas()
		require_area_resort()

	return split

#undef COLONY_REPAIR_MAX_ROOM_SIZE
