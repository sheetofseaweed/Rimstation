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

#undef RIMSTATION_DAYLIGHT_ALPHA
#undef RIMSTATION_DAYLIGHT_COLOR
