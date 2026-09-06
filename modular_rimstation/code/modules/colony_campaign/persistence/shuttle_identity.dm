/**
 * A custom shuttle read off a checkpoint is an object, not a shuttle, until something puts it back together.
 *
 * The port itself round-trips: it is an /obj on a turf, and its size and id are in the save whitelist. What does
 * not round-trip is everything that made it a shuttle, because none of it is a var a map file can hold.
 *
 * The one that breaks everything else is registration. Only two things ever call register() - the shuttle
 * template loader and create_shuttle() - and a port read off a station map is neither, so it never reaches
 * SSshuttle.mobile_docking_ports. Every lookup downstream goes through that list, so the shuttle was invisible
 * to its own consoles: get_containing_shuttle() returned null, and the navigation computer then threw
 * dereferencing it. A stationary port does register itself in Initialize(); a mobile one does not, and the save
 * system is the first thing to load one without a template.
 *
 * The rest follows from the areas being right, which they now are - see area_identity.dm. Everything here runs
 * from PersistentInitialize(), which is called only for atoms that came off a save and only after the areas
 * have been rebuilt, so the bounding-box scan below sees the rooms the colony actually built.
 *
 * Only custom shuttles are restored. They are what the save flags exist for, and registering any mobile port
 * found on a map would duplicate a template shuttle that had already registered itself.
 */
/obj/docking_port/mobile/custom/PersistentInitialize()
	. = ..()
	if(registered)
		return

	// A port with no areas is not a shuttle, and registering one would put something in SSshuttle's list that
	// every consumer has to then guard against. Better to leave it as the inert object it loaded as.
	if(!rebuild_saved_shuttle_areas())
		return

	rebuild_saved_underlying_areas()

	// replace = TRUE keeps the id the colony's consoles and home dock were named after. Uniquing it here would
	// rename the shuttle every time the campaign reloaded.
	register(replace = TRUE, custom = TRUE)
	// Re-runs connect_to_shuttle() over every area and everything in them, which is what re-links the control
	// console, the navigation computer, airlocks, cameras and engines.
	linkup(get_docked())

	log_mapping("Restored custom shuttle '[name]' ([shuttle_id]) from a checkpoint: [length(shuttle_areas)] area(s), [turf_count] turfs.")

/**
 * Finds the shuttle's own areas again by looking at what is standing in its footprint.
 *
 * This is the same scan Initialize() does when it is handed no area list. It has to be run a second time
 * because that scan happened before SSworld_save put the saved areas back, so it collected the single merged
 * area the map reader had made and would leave the shuttle owning an area with no turfs left in it.
 *
 * The default area - the frame the shuttle was first drawn as, which the blueprint console insists you stand in
 * - is the one named after the shuttle, since that is what create_shuttle() called setup() with. It is placed
 * first because expand_shuttle() reads shuttle_areas[1] to find it.
 */
/obj/docking_port/mobile/custom/proc/rebuild_saved_shuttle_areas()
	var/list/area/found = list()
	var/area/named_after_us = null
	turf_count = 0

	for(var/turf/covered as anything in return_ordered_turfs(x, y, z, dir))
		var/area/covering = covered.loc
		if(!istype(covering, area_type))
			continue
		turf_count++
		if(found[covering])
			continue
		found[covering] = TRUE
		if(covering.name == name)
			named_after_us = covering

	if(!length(found))
		log_mapping("Restored custom shuttle '[name]' ([shuttle_id]) found no [area_type] areas in its footprint; it will not fly.")
		return FALSE

	if(named_after_us)
		found -= named_after_us
		found.Insert(1, named_after_us)
		found[named_after_us] = TRUE

	shuttle_areas = found
	default_area = shuttle_areas[1]
	return TRUE

/**
 * Puts back the map of which ground each of the shuttle's turfs is standing on.
 *
 * A shuttle hands every turf back to the area it took it from when it lifts off. That map is built when the
 * shuttle is drawn and lives only on the port, so a restored shuttle had none - and would have given the colony
 * back the fallback area instead, which for a home dock that read its own area_type off the shuttle means
 * leaving a hole of shuttle floor where the shuttle had been parked.
 */
/obj/docking_port/mobile/custom/proc/rebuild_saved_underlying_areas()
	if(!length(GLOB.loaded_underlying_areas))
		return 0

	. = 0
	for(var/turf/covered as anything in return_ordered_turfs(x, y, z, dir))
		var/underlying_type = GLOB.loaded_underlying_areas[covered]
		if(!underlying_type)
			continue
		var/area/underneath = GLOB.areas_by_type[underlying_type]
		if(!underneath)
			continue
		underlying_areas_by_turf[covered] = underneath
		GLOB.loaded_underlying_areas -= covered
		.++
	return .


/**
 * Blueprints read off a checkpoint, waiting for the shuttle they were drawn for, keyed by its shuttle id.
 *
 * A blueprint's link to its shuttle is a weakref, so it does not survive either. A restored blueprint reads as
 * blank, which is worse than useless: used on the shuttle frame it already describes, it would try to build a
 * second shuttle on top of the first.
 *
 * Filled by the blueprints as they load and read once every port has restored itself, because the two run in
 * whatever order the map put them in and a blueprint cannot look up a shuttle that has not registered yet.
 */
GLOBAL_LIST_EMPTY(loaded_shuttle_blueprints)

/obj/item/shuttle_blueprints
	/// Which shuttle this was drawn for, by id. Text, because a weakref cannot be written to a map file.
	var/saved_shuttle_id
	/// TRUE if this was that shuttle's master blueprint - the one that may copy itself and rename the ship.
	var/saved_is_master = FALSE

/// Both are written through the custom path, which is the only one that can read a weakref and turn it into text.
/obj/item/shuttle_blueprints/get_custom_save_vars(save_flags = ALL)
	. = ..()
	var/obj/docking_port/mobile/custom/linked = shuttle_ref?.resolve()
	if(!istype(linked))
		return .

	.[NAMEOF(src, saved_shuttle_id)] = linked.shuttle_id
	.[NAMEOF(src, saved_is_master)] = (linked.master_blueprint?.resolve() == src)
	return .

/obj/item/shuttle_blueprints/PersistentInitialize()
	. = ..()
	if(!saved_shuttle_id)
		return
	LAZYADD(GLOB.loaded_shuttle_blueprints[saved_shuttle_id], src)

/**
 * Hands each restored blueprint back to its shuttle.
 *
 * Runs after every atom off the save has had its PersistentInitialize(), which is the only point at which both
 * the blueprints and the ports they name are guaranteed to exist.
 *
 * Returns how many were relinked.
 */
/datum/controller/subsystem/world_save/proc/relink_saved_shuttle_blueprints()
	. = 0
	for(var/shuttle_id in GLOB.loaded_shuttle_blueprints)
		var/obj/docking_port/mobile/custom/shuttle = SSshuttle.getShuttle(shuttle_id)
		for(var/obj/item/shuttle_blueprints/blueprint as anything in GLOB.loaded_shuttle_blueprints[shuttle_id])
			// Read before clearing: link_to_shuttle() decides mastership from it.
			var/was_master = blueprint.saved_is_master
			blueprint.saved_shuttle_id = null
			blueprint.saved_is_master = FALSE
			// A shuttle that did not come back leaves its blueprints blank, which is what they honestly are now.
			if(!istype(shuttle))
				continue
			blueprint.link_to_shuttle(shuttle, was_master)
			.++

	GLOB.loaded_shuttle_blueprints.Cut()
	return .

