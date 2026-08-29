/// Map support for Rimstation's persistent, Earthlike colony world.

#define RIMSTATION_DAYLIGHT_ALPHA 200
#define RIMSTATION_DAYLIGHT_COLOR "#FFF4D6"

/area/rimstation_colony
	name = "Rimstation Colony"
	icon = 'icons/area/areas_station.dmi'
	icon_state = "mining"
	default_gravity = STANDARD_GRAVITY
	requires_power = TRUE
	always_unpowered = TRUE
	power_environ = FALSE
	power_equip = FALSE
	power_light = FALSE
	flags_1 = NONE
	area_flags = VALID_TERRITORY
	area_flags_mapping = UNIQUE_AREA
	allow_shuttle_docking = TRUE

/area/rimstation_colony/underground
	name = "Rimstation Underground"
	icon_state = "unexplored"
	outdoors = FALSE
	base_lighting_alpha = 0

/area/rimstation_colony/surface
	name = "Rimstation Surface"
	icon_state = "explored"
	outdoors = TRUE
	static_lighting = FALSE
	base_lighting_alpha = RIMSTATION_DAYLIGHT_ALPHA
	base_lighting_color = RIMSTATION_DAYLIGHT_COLOR

/**
 * The generated wilderness that makes up most of the surface.
 *
 * Everything here is genturf in the DMM and gets replaced at init by the colony cave generator, so the
 * checked-in map stays small and the terrain comes from the planet record instead.
 */
/area/rimstation_colony/surface/wilds
	name = "Rimstation Wilds"
	icon_state = "unexplored"
	area_flags_mapping = UNIQUE_AREA | CAVES_ALLOWED | FLORA_ALLOWED | MOB_SPAWN_ALLOWED
	use_mapgen = TRUE
	map_generator = /datum/map_generator/cave_generator/rimstation_colony

/**
 * The one clearing the colony starts in.
 *
 * Deliberately excluded from generation: colonists need somewhere that is guaranteed open, flat and free of
 * hostile spawns, and a generated landing site could bury them in rock.
 */
/area/rimstation_colony/surface/landing
	name = "Rimstation Landing Site"
	icon_state = "explored"
	use_mapgen = FALSE

/area/rimstation_colony/sky
	name = "Rimstation Open Air"
	icon_state = "space"
	outdoors = TRUE
	static_lighting = FALSE
	base_lighting_alpha = RIMSTATION_DAYLIGHT_ALPHA
	base_lighting_color = RIMSTATION_DAYLIGHT_COLOR
	skip_minimap_rendering = TRUE

/// Breathable stone exposed by mining the underground layer.
/turf/open/misc/asteroid/rimstation
	name = "subterranean stone"
	desc = "Compacted native stone beneath the colony."
	baseturfs = /turf/open/misc/asteroid/rimstation
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	planetary_atmos = FALSE
	worm_chance = 0

/// The mineable form used to seed the colony's underground layer.
/turf/closed/mineral/random/rimstation
	name = "subterranean rock"
	baseturfs = /turf/open/misc/asteroid/rimstation
	turf_type = /turf/open/misc/asteroid/rimstation
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	defer_change = TRUE
	exposure_based = TRUE

/// Native soil for the main, middle colony layer.
/turf/open/misc/dirt/planet/rimstation
	name = "colony soil"
	desc = "Rich, Earthlike soil suitable for construction and cultivation."
	baseturfs = /turf/open/misc/dirt/planet/rimstation
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	planetary_atmos = TRUE

/// Open planetary air above the surface. This is transparent and permits z-falls.
/turf/open/openspace/rimstation
	name = "open sky"
	desc = "Open air above the colony. Watch your step."
	baseturfs = /turf/open/openspace/rimstation
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	planetary_atmos = TRUE

/// Earthlike cliff support for later hand-mapping on the upper layer.
/turf/open/cliff/rimstation
	name = "rocky cliff"
	desc = "A steep escarpment overlooking the colony."
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	planetary_atmos = TRUE
	underlay_tile = /turf/open/misc/dirt/planet/rimstation
	underlay_plane = FLOOR_PLANE

/**
 * Ground an expedition stands on, away from the colony.
 *
 * Deliberately not UNIQUE_AREA, unlike the colony above. These are loaded from lazy templates, once per site
 * per chapter, so each load has to get its own area - a shared one would mean two deposits on opposite sides of
 * the region reporting the same power, lighting and name.
 */
/area/rimstation_expedition
	name = "Expedition"
	icon = 'icons/area/areas_misc.dmi'
	icon_state = "away"
	default_gravity = STANDARD_GRAVITY
	requires_power = FALSE
	always_unpowered = TRUE
	power_environ = FALSE
	power_equip = FALSE
	power_light = FALSE
	flags_1 = NONE
	area_flags = VALID_TERRITORY
	outdoors = TRUE
	static_lighting = FALSE
	base_lighting_alpha = RIMSTATION_DAYLIGHT_ALPHA
	base_lighting_color = RIMSTATION_DAYLIGHT_COLOR

/// The camp a caravan travels in. It holds bodies and shows the map; it does not simulate the road.
/area/rimstation_expedition/transit
	name = "Caravan Camp"

/// Somewhere worth walking to.
/area/rimstation_expedition/site
	name = "Expedition Site"

#undef RIMSTATION_DAYLIGHT_ALPHA
#undef RIMSTATION_DAYLIGHT_COLOR
