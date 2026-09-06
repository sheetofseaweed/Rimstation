/**
 * Areas a player built do not survive a map file as themselves, so their identity is written beside them.
 *
 * A .dmm records an area as a typepath. The serializer adds whitelisted vars, but `name` is not one of them and
 * adding it would not help: the map reader keys its area instances by type, so every tile that names the same
 * type lands in the same instance whatever vars it carried. Fine for mapped areas, which are one instance per
 * type by design. Ruinous for areas made during a round.
 *
 * Blueprints build every room from the bare `/area` type, so a colony that had built fourteen named rooms
 * reloaded with all fourteen collapsed into a single area - and, because `/area` is named "Space", one called
 * Space. One area holds one APC, and an area's energy use is the sum of everything in it, so a single APC was
 * left paying for fourteen rooms and drained at fourteen times the rate.
 *
 * The fix writes a marker onto each of those tiles carrying a stable id for the area they belonged to. On load
 * the markers are grouped by that id and each group is given its own area again, which is the same thing the
 * blueprint does when the room is first drawn.
 *
 * Only areas a player made are marked. A mapped area is already one instance per type and reconstructing it
 * would split something that was never broken.
 */

/// Ids handed out to areas during the save in progress, keyed by area instance. Cleared between saves.
GLOBAL_LIST_EMPTY(save_area_ids)
/// Turfs read off the map that are waiting to be put back into their own area, keyed by saved area id.
GLOBAL_LIST_EMPTY(loaded_area_turfs)
/// What each saved area id was, keyed by the same id. See [/obj/effect/persistent_area_marker].
GLOBAL_LIST_EMPTY(loaded_area_records)
/// Ground a saved shuttle was parked on, as `turf -> area typepath`. Read by the shuttle restore, not by areas.
GLOBAL_LIST_EMPTY(loaded_underlying_areas)

/**
 * TRUE when an area was made during a round rather than drawn on the map.
 *
 * These are the only areas whose typepath does not identify them. A blueprint room registers itself in
 * GLOB.custom_areas; a custom shuttle's areas do not, so their type is named directly.
 */
/proc/area_needs_identity_saved(area/saved_area)
	if(!isarea(saved_area))
		return FALSE
	return GLOB.custom_areas[saved_area] || istype(saved_area, /area/shuttle/custom)

/**
 * Writes the marker for one turf's area into the map block being built, if that area needs one.
 *
 * Called from write_map() rather than from a save hook, because areas are not walked as objects - the writer
 * reads the area straight off the turf and never asks it anything.
 */
/proc/write_persistent_area_marker(list/map_string, area/saved_area, turf/marked)
	if(!area_needs_identity_saved(saved_area))
		return FALSE

	var/area_id = GLOB.save_area_ids[saved_area]
	if(!area_id)
		area_id = assign_random_name()
		GLOB.save_area_ids[saved_area] = area_id

	// Falsey values are dropped by the encoder, which is what we want: they match the marker's own defaults.
	TGM_MAP_BLOCK(map_string, /obj/effect/persistent_area_marker, generate_tgm_typepath_metadata(list(
		"persistent_area_id" = area_id,
		"persistent_area_type" = "[saved_area.type]",
		"persistent_area_name" = saved_area.name,
		"persistent_area_outdoors" = saved_area.outdoors,
		"persistent_area_gravity" = saved_area.default_gravity,
		"persistent_area_blueprinted" = !!GLOB.custom_areas[saved_area],
		"persistent_underlying_area_type" = underlying_area_type_under(saved_area, marked),
	)))
	return TRUE

/**
 * The ground a shuttle tile is parked on, as a typepath, or null when the tile is not a shuttle's.
 *
 * A shuttle gives each turf back to the area it took it from when it lifts off, and that map lives only on the
 * port. Without it a restored shuttle takes off and leaves the fallback area behind instead - which, for a port
 * whose own area_type was read back as the shuttle's, means a hole of shuttle floor in the middle of a colony.
 *
 * Only asked of shuttle tiles, so the containing-shuttle scan runs a few hundred times rather than per turf.
 */
/proc/underlying_area_type_under(area/saved_area, turf/marked)
	if(!istype(saved_area, /area/shuttle) || !isturf(marked))
		return null

	var/obj/docking_port/mobile/owner = SSshuttle.get_containing_shuttle(marked)
	var/area/underneath = owner?.underlying_areas_by_turf[marked]
	return underneath ? "[underneath.type]" : null


/**
 * One tile's worth of "this belonged to an area the map file cannot describe".
 *
 * Records itself and goes away immediately, in the manner of every other mapping helper. Nothing reads the
 * object; the rebuild reads what it left behind, which is what lets the marker die before the areas exist.
 */
/obj/effect/persistent_area_marker
	name = "area identity marker"
	icon = 'icons/effects/mapping_helpers.dmi'
	icon_state = ""
	anchored = TRUE
	invisibility = INVISIBILITY_ABSTRACT
	plane = POINT_PLANE
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF
	/// Which saved area this tile belonged to. Tiles sharing one are one room.
	var/persistent_area_id
	/// Typepath of that area, as text. A path cannot be a map var without being resolved first.
	var/persistent_area_type
	/// What the area was called. The whole reason this marker exists.
	var/persistent_area_name
	/// Whether the area could see the sky. Blueprints inherit this and roofing reads it.
	var/persistent_area_outdoors = FALSE
	/// The area's gravity, which a blueprint room inherits from the ground it was drawn on.
	var/persistent_area_gravity = 0
	/// TRUE if a player drew this with blueprints. Those get setup(); a shuttle's areas keep their own defaults.
	var/persistent_area_blueprinted = FALSE
	/// For a shuttle tile, the area it is parked on, as text. What the shuttle gives back when it lifts off.
	var/persistent_underlying_area_type

/obj/effect/persistent_area_marker/Initialize(mapload)
	. = ..()
	var/turf/marked = get_turf(src)
	if(!marked || !persistent_area_id)
		return INITIALIZE_HINT_QDEL

	LAZYADD(GLOB.loaded_area_turfs[persistent_area_id], marked)
	var/underlying_type = text2path(persistent_underlying_area_type)
	if(ispath(underlying_type, /area))
		GLOB.loaded_underlying_areas[marked] = underlying_type

	if(!GLOB.loaded_area_records[persistent_area_id])
		GLOB.loaded_area_records[persistent_area_id] = list(
			"type" = text2path(persistent_area_type),
			"name" = persistent_area_name,
			"outdoors" = persistent_area_outdoors,
			"gravity" = persistent_area_gravity,
			"blueprinted" = persistent_area_blueprinted,
		)

	return INITIALIZE_HINT_QDEL


/**
 * Puts every saved area back, one instance per id, and hands its turfs over.
 *
 * Runs once, from SSworld_save, after the map is loaded and before anything is asked to work out what it is
 * powering. Each group gets a brand new area rather than the loaded one being renamed, because the loaded one
 * is holding every other room of the same type as well.
 *
 * Returns how many areas were rebuilt.
 */
/datum/controller/subsystem/world_save/proc/rebuild_persistent_areas()
	. = 0
	if(!length(GLOB.loaded_area_turfs))
		return 0

	for(var/area_id in GLOB.loaded_area_turfs)
		var/list/turfs = GLOB.loaded_area_turfs[area_id]
		var/list/record = GLOB.loaded_area_records[area_id]
		if(!length(turfs) || !islist(record))
			continue

		var/area_type = record["type"]
		if(!ispath(area_type, /area))
			log_mapping("A saved area named '[record["name"]]' claimed type '[area_type]', which this build does not have. Its [length(turfs)] tiles keep the area they loaded into.")
			continue

		if(rebuild_one_persistent_area(area_type, record, turfs))
			.++
		CHECK_TICK

	GLOB.loaded_area_turfs.Cut()
	GLOB.loaded_area_records.Cut()

	if(.)
		require_area_resort()
		log_mapping("Rebuilt [.] area(s) that were made during an earlier chapter.")
	return .

/**
 * Rebuilds a single saved area and moves its turfs into it.
 *
 * Follows create_area(): setup() for the name and the flags a room gets, the gravity and sky of the ground it
 * was drawn on, a custom_area component so the shuttle blueprint can still see it, and a firedoor recalculation
 * for every area the turfs came out of. set_turfs_to_area() re-points any APC on those tiles at the new area,
 * which is what puts each room back on its own power budget.
 */
/datum/controller/subsystem/world_save/proc/rebuild_one_persistent_area(area_type, list/record, list/turf/turfs)
	var/area/rebuilt = new area_type(null)
	// setup() is what a blueprint does to a new room, and only a blueprint room should get it: it clears
	// territory flags and drops the power channels for the area's APC to raise again.
	if(record["blueprinted"])
		rebuilt.setup(record["name"] || initial(rebuilt.name))
		rebuilt.AddComponent(/datum/component/custom_area)
		GLOB.custom_areas[rebuilt] = TRUE
	else
		rebuilt.name = record["name"] || initial(rebuilt.name)

	rebuilt.outdoors = record["outdoors"]
	rebuilt.default_gravity = record["gravity"]

	var/list/area/emptied = list()
	set_turfs_to_area(turfs, rebuilt, emptied)
	rebuilt.reg_in_areas_in_z()

	// The areas the turfs left keep firelocks that now span a boundary that moved.
	for(var/area_name in emptied)
		var/area/vacated = emptied[area_name]
		for(var/obj/machinery/door/firedoor/firelock as anything in vacated.firedoors)
			firelock.CalculateAffectingAreas()

	rebuilt.power_change()
	return TRUE
