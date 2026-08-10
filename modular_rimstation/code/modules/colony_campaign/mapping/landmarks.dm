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
 * Mapped in rather than searched for at runtime so that arrival points stay off cliffs and out of the
 * settlement, and so a mapper can see exactly where attackers can come from.
 */
/obj/effect/landmark/rimstation_raid_insertion
	name = "rimstation raid insertion point"
	icon_state = "x3"

/// Origin of the settlement exclusion radius. Raids may not insert within range of this.
/obj/effect/landmark/rimstation_settlement_center
	name = "rimstation settlement center"
	icon_state = "x"

GLOBAL_LIST_EMPTY(rimstation_colony_spawns)
GLOBAL_LIST_EMPTY(rimstation_raid_insertion_points)
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

/obj/effect/landmark/rimstation_settlement_center/Initialize(mapload)
	. = ..()
	if(GLOB.rimstation_settlement_center)
		stack_trace("A second rimstation settlement center was mapped in at [AREACOORD(src)].")
	GLOB.rimstation_settlement_center = src

/obj/effect/landmark/rimstation_settlement_center/Destroy()
	if(GLOB.rimstation_settlement_center == src)
		GLOB.rimstation_settlement_center = null
	return ..()
