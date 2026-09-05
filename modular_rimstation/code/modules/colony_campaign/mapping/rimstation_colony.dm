/// Map support for Rimstation's persistent, Earthlike colony world.

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
	// Sunlight now comes from the sky above each tile, not from the area. Static lighting has to be on so
	// lamps work outdoors after dark, and outdoors is only read where there is no level above to check.
	outdoors = TRUE
	static_lighting = TRUE

/**
 * The generated wilderness that makes up most of the surface.
 *
 * Everything here is genturf in the DMM and gets replaced at init by the colony landscape generator, so the
 * checked-in map stays small and the terrain comes from the planet record instead.
 */
/area/rimstation_colony/surface/wilds
	name = "Rimstation Wilds"
	icon_state = "unexplored"
	area_flags_mapping = UNIQUE_AREA | CAVES_ALLOWED | FLORA_ALLOWED | MOB_SPAWN_ALLOWED
	use_mapgen = TRUE
	map_generator = /datum/map_generator/rimstation_colony

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

/**
 * The upper face of the shared elevation plan.
 *
 * It starts as open air in the DMM. The Z2 wilds generator owns this level too and replaces only mountain
 * footprints, which prevents two area generators from sampling subtly different vertical landscapes.
 */
/area/rimstation_colony/surface/highlands
	name = "Rimstation Highlands"
	icon_state = "explored"
	area_flags_mapping = UNIQUE_AREA
	use_mapgen = FALSE
	map_generator = null

/area/rimstation_colony/sky
	name = "Rimstation Open Air"
	icon_state = "space"
	outdoors = TRUE
	static_lighting = TRUE
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

/// Damp soil along river margins and wetlands.
/turf/open/misc/dirt/planet/rimstation/wet
	name = "damp colony soil"
	icon_state = "greenerdirt"
	base_icon_state = "greenerdirt"

/// Temperate ground used for grasslands, forests, and mountain plateaus.
/turf/open/misc/grass/rimstation
	name = "colony grass"
	desc = "A hardy carpet of temperate grass."
	baseturfs = /turf/open/misc/dirt/planet/rimstation
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	planetary_atmos = TRUE

/// A solid mountain top. The rock face projects over adjacent open air; leaving the top causes a real z-fall.
/turf/open/misc/grass/rimstation/highland
	name = "rocky highland"
	desc = "Grass-covered rock overlooking the lowlands. The exposed edges drop steeply away."
	smoothing_flags = SMOOTH_BITMASK | SMOOTH_BORDER

/turf/open/misc/grass/rimstation/highland/set_smoothed_icon_state(new_junction)
	. = ..()
	// ChangeTurf queues neighboring turfs to smooth, so the ledge also follows construction and excavation.
	update_appearance(UPDATE_OVERLAYS)

/turf/open/misc/grass/rimstation/highland/update_overlays()
	. = ..()
	var/exposed_directions = NONE
	for(var/direction in GLOB.cardinals)
		var/turf/neighbor = get_step(src, direction)
		if(isopenspaceturf(neighbor))
			exposed_directions |= direction
	if(!exposed_directions)
		return

	// These are edge strips and exterior corner pieces, not full rock tiles. Reuse the eight appearances.
	var/static/list/cliff_edges = list()
	for(var/direction in GLOB.alldirs)
		if((exposed_directions & direction) != direction)
			continue
		// At an inward corner, the adjacent edge strips already meet. Do not draw a cap over solid ground.
		var/turf/neighbor = get_step(src, direction)
		if(!isopenspaceturf(neighbor))
			continue
		var/mutable_appearance/cliff_edge = cliff_edges["[direction]"]
		if(!cliff_edge)
			cliff_edge = mutable_appearance('modular_rimstation/icons/turf/ntf_rockcliff.dmi', "rockcliff_overlay", ABOVE_OPEN_TURF_LAYER, appearance_flags = RESET_TRANSFORM)
			cliff_edge = make_mutable_appearance_directional(cliff_edge, direction)
			cliff_edge.pixel_w = ((direction & EAST) ? world.icon_size : 0) - ((direction & WEST) ? world.icon_size : 0)
			cliff_edge.pixel_z = ((direction & NORTH) ? world.icon_size : 0) - ((direction & SOUTH) ? world.icon_size : 0)
			cliff_edges["[direction]"] = cliff_edge
		. += cliff_edge

/// Fordable fresh water. Most of a generated river uses this type.
/turf/open/water/rimstation
	name = "river shallows"
	desc = "Cool fresh water, shallow enough to ford with care."
	baseturfs = /turf/open/water/rimstation
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	planetary_atmos = TRUE

/// Occasional pools break up the otherwise fordable channel.
/turf/open/water/rimstation/deep
	name = "deep river pool"
	desc = "A deep pocket in the river channel."
	icon_state = "deep_riverwater_motion"
	immerse_overlay = "immerse_deep"
	baseturfs = /turf/open/water/rimstation/deep
	is_swimming_tile = TRUE

/// Open planetary air above the surface. This is transparent and permits z-falls.
/turf/open/openspace/rimstation
	name = "open sky"
	desc = "Open air above the colony. Watch your step."
	baseturfs = /turf/open/openspace/rimstation
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	planetary_atmos = TRUE

/// Legacy single-z cliff face for authored maps. Generated mountain tops use highland grass and real z-falls.
/turf/open/cliff/rimstation
	name = "rocky cliff"
	desc = "A steep escarpment overlooking the colony."
	icon = 'icons/turf/cliff/icerock_cliff.dmi'
	icon_state = "icerock_wall-0"
	base_icon_state = "icerock_wall"
	smoothing_flags = SMOOTH_BITMASK | SMOOTH_BORDER
	smoothing_groups = SMOOTH_GROUP_TURF_OPEN_CLIFF
	canSmoothWith = SMOOTH_GROUP_TURF_OPEN_CLIFF
	layer = EDGED_TURF_LAYER
	plane = WALL_PLANE
	transform = MAP_SWITCH(TRANSLATE_MATRIX(-4, -4), matrix())
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	planetary_atmos = TRUE
	baseturfs = /turf/open/misc/dirt/planet/rimstation
	underlay_tile = /turf/open/misc/dirt/planet/rimstation
	underlay_plane = FLOOR_PLANE
	undertile_pixel_x = 4
	undertile_pixel_y = 4

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
	// Single-z lazy templates, so there is never a turf above. outdoors is what decides here.
	outdoors = TRUE
	static_lighting = TRUE

/// The camp a caravan travels in. It holds bodies and shows the map; it does not simulate the road.
/area/rimstation_expedition/transit
	name = "Caravan Camp"

/// Somewhere worth walking to.
/area/rimstation_expedition/site
	name = "Expedition Site"
