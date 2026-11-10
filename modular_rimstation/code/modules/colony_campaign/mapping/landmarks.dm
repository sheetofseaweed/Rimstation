/**
 * Where colonists begin the chapter.
 *
 * Kept separate from the job spawn system on purpose: the colony is not a station roster, and later phases
 * place returning colonists here by campaign record rather than by job.
 */
/obj/effect/landmark/rimstation_colony_spawn
	name = "rimstation colony spawn"
	icon_state = "x2"

/**
 * A validated map-edge tile a raid is allowed to arrive on.
 *
 * Generated after terrain and ecology from landing-connected edge coordinates. It remains only a proposal:
 * the raid validates real turf density and connectivity again when an attack begins, after players may have
 * changed the map.
 */
/obj/effect/landmark/rimstation_raid_insertion
	name = "rimstation raid insertion point"
	icon_state = "x3"
	/// The generated lane that starts here. Shared with that lane's nodes.
	var/lane_id

/**
 * A point along a generated raid lane, every waypoint spacing from its marker toward the landing.
 * The lane is the route the plan found and kept free of dense flora. Order 1 is nearest the map edge.
 */
/obj/effect/landmark/rimstation_raid_lane_node
	name = "rimstation raid lane node"
	icon_state = "x4"
	/// The lane this node belongs to, matching its marker's lane_id.
	var/lane_id
	/// Position along the lane, counted from the map edge inward.
	var/lane_order = 0

/// Origin of the settlement exclusion radius. Raids may not insert within range of this.
/obj/effect/landmark/rimstation_settlement_center
	name = "rimstation settlement center"
	icon_state = "x"

GLOBAL_LIST_EMPTY(rimstation_colony_spawns)
GLOBAL_LIST_EMPTY(rimstation_raid_insertion_points)
GLOBAL_LIST_EMPTY(rimstation_raid_lane_nodes)
GLOBAL_DATUM(rimstation_settlement_center, /obj/effect/landmark/rimstation_settlement_center)

/obj/effect/landmark/rimstation_colony_spawn/Initialize(mapload)
	. = ..()
	GLOB.rimstation_colony_spawns += src

/obj/effect/landmark/rimstation_colony_spawn/Destroy()
	GLOB.rimstation_colony_spawns -= src
	return ..()

/obj/effect/landmark/rimstation_raid_insertion/Initialize(mapload)
	. = ..()
	GLOB.rimstation_raid_insertion_points += src

/obj/effect/landmark/rimstation_raid_insertion/Destroy()
	GLOB.rimstation_raid_insertion_points -= src
	return ..()

// A checkpoint map is never regenerated, so the lane survives a chapter only in what these save.
/obj/effect/landmark/rimstation_raid_insertion/get_save_vars(save_flags = ALL)
	. = ..()
	. += NAMEOF(src, lane_id)
	return .

/obj/effect/landmark/rimstation_raid_lane_node/Initialize(mapload)
	. = ..()
	GLOB.rimstation_raid_lane_nodes += src

/obj/effect/landmark/rimstation_raid_lane_node/Destroy()
	GLOB.rimstation_raid_lane_nodes -= src
	return ..()

/obj/effect/landmark/rimstation_raid_lane_node/get_save_vars(save_flags = ALL)
	. = ..()
	. += NAMEOF(src, lane_id)
	. += NAMEOF(src, lane_order)
	return .

/obj/effect/landmark/rimstation_settlement_center/Initialize(mapload)
	. = ..()
	if(GLOB.rimstation_settlement_center)
		stack_trace("A second rimstation settlement center was mapped in at [AREACOORD(src)].")
	GLOB.rimstation_settlement_center = src

/obj/effect/landmark/rimstation_settlement_center/Destroy()
	if(GLOB.rimstation_settlement_center == src)
		GLOB.rimstation_settlement_center = null
	return ..()
