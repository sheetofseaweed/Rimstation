#define RIMSTATION_EXPEDITION_SCENE_ROLL_MAX 10000
#define RIMSTATION_EXPEDITION_SCENE_NOISE_ZOOM 13

/**
 * Runtime scene providers for expeditions.
 *
 * A provider owns how a scene is made, while /datum/overworld_destination continues to own the resulting
 * reservation and the landmarks found in it. This keeps the expedition lifecycle independent of content:
 * transit and ruins can remain authored maps while resource sites are generated from their strategic cell.
 */
/datum/overworld_scene_provider

/// Why this provider cannot build the requested scene, or null when it can.
/datum/overworld_scene_provider/proc/problem(site_id)
	return "'[type]' is not a usable overworld scene provider"

/// Fills an empty destination. This may sleep while it reserves or loads turfs.
/datum/overworld_scene_provider/proc/load_destination(datum/overworld_destination/destination)
	return FALSE


/// A provider backed by one lazy template.
/datum/overworld_scene_provider/premade
	var/template_key

/datum/overworld_scene_provider/premade/problem(site_id)
	return overworld_template_problem(template_key)

/datum/overworld_scene_provider/premade/load_destination(datum/overworld_destination/destination)
	return destination?.load_template_scene(template_key)

/datum/overworld_scene_provider/premade/transit
	template_key = LAZY_TEMPLATE_KEY_RIMSTATION_TRANSIT

/datum/overworld_scene_provider/premade/resource
	template_key = LAZY_TEMPLATE_KEY_RIMSTATION_RESOURCE_SITE

/datum/overworld_scene_provider/premade/resource/problem(site_id)
	var/datum/overworld_site/site = get_active_overworld_region()?.sites[site_id]
	if(!site || site.kind != OVERWORLD_SITE_RESOURCE)
		return "'[site_id]' is not a resource site in the active region"
	return ..()

/datum/overworld_scene_provider/premade/ruin
	template_key = LAZY_TEMPLATE_KEY_RIMSTATION_RUIN_SITE

/datum/overworld_scene_provider/premade/ruin/problem(site_id)
	var/datum/overworld_site/site = get_active_overworld_region()?.sites[site_id]
	if(!site || site.kind != OVERWORLD_SITE_RUIN)
		return "'[site_id]' is not a ruin in the active region"
	return ..()


/// A resource landscape generated from the planet, site identity, and strategic cell.
/datum/overworld_scene_provider/procedural_resource

/datum/overworld_scene_provider/procedural_resource/problem(site_id)
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/overworld_site/site = region?.sites[site_id]
	if(!site || site.kind != OVERWORLD_SITE_RESOURCE)
		return "'[site_id]' is not a resource site in the active region"
	if(!get_active_colony_planet())
		return "the active campaign has no planet definition"
	if(!region.cells["[site.q],[site.r]"])
		return "resource site '[site_id]' does not stand on a valid region cell"
	return null

/datum/overworld_scene_provider/procedural_resource/load_destination(datum/overworld_destination/destination)
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/overworld_site/site = region?.sites[destination?.site_id]
	var/datum/overworld_cell/cell = region?.cells["[site?.q],[site?.r]"]
	var/datum/rimstation_expedition_scene_context/context = new(get_active_colony_planet(), site, cell)
	if(!context.build_plan() || !context.materialize(destination))
		qdel(context)
		if(destination?.reservation)
			qdel(destination.reservation)
			destination.reservation = null
		return FALSE
	qdel(context)
	return TRUE


/// Provider for a generated site's kind. Null means the site does not describe loadable content.
/proc/overworld_site_scene_provider(site_id)
	var/datum/overworld_site/site = get_active_overworld_region()?.sites[site_id]
	switch(site?.kind)
		if(OVERWORLD_SITE_RESOURCE)
			return /datum/overworld_scene_provider/procedural_resource
		if(OVERWORLD_SITE_RUIN)
			return /datum/overworld_scene_provider/premade/ruin
	return null

/// Why a provider cannot make this destination, without reserving any turfs.
/proc/overworld_scene_problem(site_id, provider_type)
	if(!ispath(provider_type, /datum/overworld_scene_provider))
		return "no valid scene provider was named"
	var/datum/overworld_scene_provider/provider = new provider_type
	var/problem = provider.problem(site_id)
	qdel(provider)
	return problem


/**
 * Pure plan and runtime materializer for one resource scene.
 *
 * All generation works in local coordinates. Moving the reservation, loading another scene first, or changing
 * world.maxx therefore cannot change the result. The strategic cell supplies its visible terrain, traversal
 * topology, and danger; the planet and stable site id supply the random streams.
 */
/datum/rimstation_expedition_scene_context
	var/datum/planet_definition/planet
	var/datum/overworld_site/site
	var/datum/overworld_cell/cell
	var/site_id
	var/width = OVERWORLD_PROCEDURAL_SCENE_WIDTH
	var/height = OVERWORLD_PROCEDURAL_SCENE_HEIGHT
	var/arrival_x
	var/arrival_y = 5
	var/objective_x
	var/objective_y
	var/terrain_seed
	var/ecology_seed
	var/resource_seed
	var/list/turf_plan
	var/list/trail_mask
	var/has_stream = FALSE
	var/plan_built = FALSE

/datum/rimstation_expedition_scene_context/New(
	datum/planet_definition/planet,
	datum/overworld_site/site,
	datum/overworld_cell/cell,
	width = OVERWORLD_PROCEDURAL_SCENE_WIDTH,
	height = OVERWORLD_PROCEDURAL_SCENE_HEIGHT,
)
	. = ..()
	src.planet = planet
	src.site = site
	src.cell = cell
	src.site_id = site?.site_id()
	src.width = width
	src.height = height
	arrival_x = round(width / 2)
	objective_y = height - 8

/datum/rimstation_expedition_scene_context/Destroy(force)
	planet = null
	site = null
	cell = null
	turf_plan = null
	trail_mask = null
	return ..()

/datum/rimstation_expedition_scene_context/proc/coordinate_index(x, y)
	if(x < 1 || x > width || y < 1 || y > height)
		return null
	return ((y - 1) * width) + x

/datum/rimstation_expedition_scene_context/proc/index_x(index)
	return ((index - 1) % width) + 1

/datum/rimstation_expedition_scene_context/proc/index_y(index)
	return floor((index - 1) / width) + 1

/datum/rimstation_expedition_scene_context/proc/resolve_seed(stream)
	var/stream_seed = planet?.get_stream_seed(stream)
	if(isnull(stream_seed) || !site_id || !cell)
		return null
	var/folded = rustg_hash_string(RUSTG_HASH_SHA256, "[stream_seed]:expedition:[site_id]:[cell.q],[cell.r]:[width]x[height]")
	return hex2num(copytext(folded, 1, 7)) % 50000

/datum/rimstation_expedition_scene_context/proc/coordinate_roll(stream_seed, x, y, salt, modulus = RIMSTATION_EXPEDITION_SCENE_ROLL_MAX)
	if(isnull(stream_seed) || modulus <= 0)
		return 0
	var/folded = rustg_hash_string(RUSTG_HASH_XXH64, "[stream_seed]:[x]:[y]:[salt]")
	return hex2num(copytext(folded, 1, 7)) % modulus

/datum/rimstation_expedition_scene_context/proc/sample_noise(seed, x, y, zoom = RIMSTATION_EXPEDITION_SCENE_NOISE_ZOOM)
	return text2num(rustg_noise_get_at_coordinates("[seed]", "[x / zoom]", "[y / zoom]"))

/datum/rimstation_expedition_scene_context/proc/build_plan()
	if(plan_built || !planet || !site_id || !cell || width < 21 || height < 21)
		return FALSE

	terrain_seed = resolve_seed(PLANET_STREAM_TERRAIN)
	ecology_seed = resolve_seed(PLANET_STREAM_ECOLOGY)
	resource_seed = resolve_seed(PLANET_STREAM_RESOURCES)
	if(isnull(terrain_seed) || isnull(ecology_seed) || isnull(resource_seed))
		return FALSE

	objective_x = round(width / 2) - round(width / 6) + coordinate_roll(resource_seed, width, height, "objective", round(width / 3))
	objective_x = clamp(objective_x, 7, width - 6)
	has_stream = cell.terrain == OVERWORLD_TERRAIN_MARSH
	if(cell.terrain == OVERWORLD_TERRAIN_FOREST)
		has_stream = coordinate_roll(terrain_seed, 1, 1, "stream") < 6500
	else if(cell.terrain == OVERWORLD_TERRAIN_TAIGA)
		has_stream = coordinate_roll(terrain_seed, 1, 1, "stream") < 4000
	else if(cell.terrain == OVERWORLD_TERRAIN_GRASSLAND)
		has_stream = coordinate_roll(terrain_seed, 1, 1, "stream") < 2500

	trail_mask = new /list(width * height)
	build_trail()
	turf_plan = new /list(width * height)

	for(var/y in 1 to height)
		for(var/x in 1 to width)
			var/index = coordinate_index(x, y)
			var/turf_type = choose_turf_type(x, y, index)
			if(!turf_type)
				return FALSE
			turf_plan[index] = turf_type
		CHECK_TICK

	plan_built = TRUE
	return TRUE

/// A three-tile trail guarantees a walkable route from the caravan to the deposit.
/datum/rimstation_expedition_scene_context/proc/build_trail()
	var/vertical_span = max(1, objective_y - arrival_y)
	var/first_trail_x
	var/last_trail_x
	for(var/y in arrival_y to objective_y)
		var/progress = (y - arrival_y) / vertical_span
		var/base_x = arrival_x + ((objective_x - arrival_x) * progress)
		var/meander = round((sample_noise(terrain_seed, y, site.rank, 7) - 0.5) * 5)
		var/trail_x = clamp(round(base_x) + meander, 4, width - 3)
		if(isnull(first_trail_x))
			first_trail_x = trail_x
		last_trail_x = trail_x
		for(var/offset in -1 to 1)
			trail_mask[coordinate_index(trail_x + offset, y)] = TRUE

	// Join both ends of the meander to their clearings, even when the first or last bend was wide.
	var/from_x = min(arrival_x, first_trail_x)
	var/to_x = max(arrival_x, first_trail_x)
	for(var/x in from_x to to_x)
		trail_mask[coordinate_index(x, arrival_y)] = TRUE
	from_x = min(objective_x, last_trail_x)
	to_x = max(objective_x, last_trail_x)
	for(var/x in from_x to to_x)
		trail_mask[coordinate_index(x, objective_y)] = TRUE

/datum/rimstation_expedition_scene_context/proc/is_protected_coordinate(x, y, index)
	if(trail_mask[index])
		return TRUE
	if(max(abs(x - arrival_x), abs(y - arrival_y)) <= 3)
		return TRUE
	return max(abs(x - objective_x), abs(y - objective_y)) <= 3

/datum/rimstation_expedition_scene_context/proc/choose_turf_type(x, y, index)
	var/edge_distance = min(x - 1, y - 1, width - x, height - y)
	if(edge_distance < OVERWORLD_PROCEDURAL_SCENE_BORDER)
		return cold_terrain() ? /turf/closed/indestructible/rock/snow : /turf/closed/indestructible/rock

	if(is_protected_coordinate(x, y, index))
		return ground_turf_type(x, y, trail = TRUE)

	// The second edge is broken up so the playable space reads as a natural basin rather than a square room.
	if(edge_distance == OVERWORLD_PROCEDURAL_SCENE_BORDER && sample_noise(terrain_seed, x, y, 8) > 0.35)
		return rock_turf_type()

	if(has_stream && is_stream_coordinate(x, y))
		if(coordinate_roll(terrain_seed, x, y, "deep_water") < 1800)
			return /turf/open/water/rimstation/deep
		return /turf/open/water/rimstation

	var/rock_threshold = 0.88
	switch(cell.topology)
		if(OVERWORLD_TOPOLOGY_NORMAL)
			rock_threshold = 0.80
		if(OVERWORLD_TOPOLOGY_DIFFICULT)
			rock_threshold = 0.70
		if(OVERWORLD_TOPOLOGY_IMPASSABLE)
			rock_threshold = 0.62
	if(sample_noise(resource_seed, x, y) > rock_threshold)
		return rock_turf_type()

	return ground_turf_type(x, y)

/datum/rimstation_expedition_scene_context/proc/is_stream_coordinate(x, y)
	var/channel_x = round(width / 2) + round((sample_noise(terrain_seed, y, site.rank + 17, 9) - 0.5) * 15)
	return abs(x - channel_x) <= 1

/datum/rimstation_expedition_scene_context/proc/cold_terrain()
	switch(cell.terrain)
		if(OVERWORLD_TERRAIN_FROZEN_STEPPE, OVERWORLD_TERRAIN_TUNDRA, OVERWORLD_TERRAIN_TAIGA)
			return TRUE
	return FALSE

/datum/rimstation_expedition_scene_context/proc/rock_turf_type()
	return cold_terrain() ? /turf/closed/mineral/rimstation_expedition/snow : /turf/closed/mineral/rimstation_expedition

/datum/rimstation_expedition_scene_context/proc/ground_turf_type(x, y, trail = FALSE)
	if(trail)
		return cold_terrain() ? /turf/open/misc/asteroid/snow/rimstation : /turf/open/misc/dirt/planet/rimstation

	switch(cell.terrain)
		if(OVERWORLD_TERRAIN_FROZEN_STEPPE)
			return /turf/open/misc/asteroid/snow/rimstation
		if(OVERWORLD_TERRAIN_TUNDRA)
			return coordinate_roll(terrain_seed, x, y, "snow_patch") < 7600 ? /turf/open/misc/asteroid/snow/rimstation : /turf/open/misc/dirt/planet/rimstation
		if(OVERWORLD_TERRAIN_TAIGA)
			return coordinate_roll(terrain_seed, x, y, "snow_patch") < 2800 ? /turf/open/misc/asteroid/snow/rimstation : /turf/open/misc/grass/rimstation
		if(OVERWORLD_TERRAIN_DESERT)
			return /turf/open/misc/dirt/jungle/wasteland/rimstation
		if(OVERWORLD_TERRAIN_SCRUBLAND, OVERWORLD_TERRAIN_SAVANNA)
			return /turf/open/misc/dirt/planet/rimstation
		if(OVERWORLD_TERRAIN_MARSH)
			return /turf/open/misc/dirt/planet/rimstation/wet
	return /turf/open/misc/grass/rimstation

/// Stable summary for tests and diagnostics; does not reserve or change any turf.
/datum/rimstation_expedition_scene_context/proc/fingerprint(sample_count = 96)
	if(!plan_built || sample_count <= 0)
		return null
	var/list/parts = list(
		"site=[site_id]",
		"cell=[cell.q],[cell.r]:[cell.terrain]:[cell.topology]:[cell.danger]",
		"bounds=[width]x[height]",
		"arrival=[arrival_x],[arrival_y]",
		"objective=[objective_x],[objective_y]",
		"stream=[has_stream]",
	)
	for(var/i in 1 to sample_count)
		var/x = ((i * 17) % width) + 1
		var/y = ((i * 29) % height) + 1
		var/index = coordinate_index(x, y)
		parts += "[x],[y]:[turf_plan[index]]:[trail_mask[index]]:[coordinate_roll(ecology_seed, x, y, "fingerprint")]"
	return rustg_hash_string(RUSTG_HASH_SHA256, parts.Join("|"))

/**
 * Reserves and materializes the pure plan. Runtime-created atoms initialize from New(); turfs are then linked
 * to their new neighbours and handed to static lighting as one batch.
 */
/datum/rimstation_expedition_scene_context/proc/materialize(datum/overworld_destination/destination)
	if(!plan_built || !destination || destination.site_id != site_id)
		return FALSE

	var/datum/turf_reservation/reservation = SSmapping.request_turf_block_reservation(width, height, 1)
	if(!reservation)
		return FALSE
	destination.reservation = reservation

	var/turf/bottom_left = reservation.bottom_left_turfs[1]
	if(!bottom_left)
		return FALSE

	var/area/rimstation_expedition/site/site_area = new
	site_area.name = "Expedition Site - [cell.terrain] [site.rank]"
	destination.scene_area = site_area
	var/list/generated_turfs = list()

	for(var/y in 1 to height)
		for(var/x in 1 to width)
			var/turf/old_turf = locate(bottom_left.x + x - 1, bottom_left.y + y - 1, bottom_left.z)
			if(!old_turf)
				return FALSE
			old_turf.change_area(old_turf.loc, site_area)
			var/turf/generated = old_turf.ChangeTurf(turf_plan[coordinate_index(x, y)])
			generated_turfs += generated
		CHECK_TICK

	for(var/turf/generated as anything in generated_turfs)
		CALCULATE_ADJACENT_TURFS(generated, NORMAL_TURF)
		CHECK_TICK
	SSlighting.setup_static_lighting_if_needed(generated_turfs)

	populate(destination, bottom_left)
	log_game("Generated expedition resource site '[site_id]' as [width]x[height] [cell.terrain]/[cell.topology] terrain.")
	return length(destination.arrival_turfs) && destination.objective_ref

/datum/rimstation_expedition_scene_context/proc/populate(datum/overworld_destination/destination, turf/bottom_left)
	var/turf/arrival = local_turf(bottom_left, arrival_x, arrival_y)
	var/turf/objective = local_turf(bottom_left, objective_x, objective_y)
	if(!arrival || !objective)
		return FALSE

	new /obj/effect/landmark/rimstation_expedition_arrival(arrival)
	destination.arrival_turfs += arrival
	new /obj/machinery/computer/colony_overworld(local_turf(bottom_left, arrival_x + 2, arrival_y))

	var/obj/structure/rimstation_resource_deposit/deposit = new(objective)
	deposit.bind_to_site(site_id)
	destination.objective_ref = WEAKREF(deposit)

	for(var/index in 1 to length(turf_plan))
		var/x = index_x(index)
		var/y = index_y(index)
		if(is_protected_coordinate(x, y, index))
			continue
		var/turf/target = local_turf(bottom_left, x, y)
		if(!target || isclosedturf(target) || istype(target, /turf/open/water))
			continue
		populate_coordinate(target, x, y)
		CHECK_TICK

	return TRUE

/datum/rimstation_expedition_scene_context/proc/local_turf(turf/bottom_left, x, y)
	RETURN_TYPE(/turf)
	return locate(bottom_left.x + x - 1, bottom_left.y + y - 1, bottom_left.z)

/datum/rimstation_expedition_scene_context/proc/populate_coordinate(turf/target, x, y)
	var/flora_threshold = 350
	switch(cell.terrain)
		if(OVERWORLD_TERRAIN_FOREST)
			flora_threshold = 2100
		if(OVERWORLD_TERRAIN_TAIGA)
			flora_threshold = 1500
		if(OVERWORLD_TERRAIN_GRASSLAND)
			flora_threshold = 900
		if(OVERWORLD_TERRAIN_MARSH)
			flora_threshold = 850
		if(OVERWORLD_TERRAIN_SAVANNA)
			flora_threshold = 650
		if(OVERWORLD_TERRAIN_TUNDRA)
			flora_threshold = 450
		if(OVERWORLD_TERRAIN_FROZEN_STEPPE, OVERWORLD_TERRAIN_DESERT)
			flora_threshold = 180

	if(coordinate_roll(ecology_seed, x, y, "flora") < flora_threshold)
		spawn_flora(target, x, y)
	else if(coordinate_roll(resource_seed, x, y, "loose_rock") < 110)
		new /obj/structure/flora/rock(target)

	var/fauna_threshold = cell.danger * 3
	if(fauna_threshold && coordinate_roll(ecology_seed, x, y, "fauna") < fauna_threshold)
		var/fauna_type = coordinate_roll(ecology_seed, x, y, "fauna_type", 3) == 0 ? /mob/living/basic/goat : /mob/living/basic/deer
		new fauna_type(target)

/datum/rimstation_expedition_scene_context/proc/spawn_flora(turf/target, x, y)
	var/selector = coordinate_roll(ecology_seed, x, y, "flora_type", 100)
	var/flora_type
	if(cell.terrain == OVERWORLD_TERRAIN_FOREST)
		flora_type = selector < 58 ? /obj/structure/flora/tree/rimstation_deciduous : /obj/structure/flora/tree/pine/rimstation
	else if(cell.terrain == OVERWORLD_TERRAIN_TAIGA || cell.terrain == OVERWORLD_TERRAIN_TUNDRA)
		flora_type = selector < 72 ? /obj/structure/flora/tree/pine/rimstation : /obj/structure/flora/grass/rimstation_tall
	else if(cell.terrain == OVERWORLD_TERRAIN_MARSH)
		flora_type = selector < 60 ? /obj/structure/flora/bush/reed : /obj/structure/flora/grass/rimstation_tall
	else if(cell.terrain == OVERWORLD_TERRAIN_DESERT || cell.terrain == OVERWORLD_TERRAIN_FROZEN_STEPPE)
		flora_type = selector < 50 ? /obj/structure/flora/rock : /obj/structure/flora/bush/sparsegrass
	else if(selector < 18)
		flora_type = /obj/structure/flora/tree/rimstation_deciduous
	else if(selector < 30)
		flora_type = /obj/structure/flora/bush/rimstation_berry
	else if(selector < 82)
		flora_type = /obj/structure/flora/grass/rimstation_tall
	else
		flora_type = /obj/structure/flora/bush/flowers_yw

	var/obj/structure/flora/spawned = new flora_type(target)
	spawned.dir = GLOB.cardinals[(coordinate_roll(ecology_seed, x, y, "flora_direction", 4)) + 1]


/// Breathable snow for a generated reservation, independent of the reservation z-level's planetary traits.
/turf/open/misc/asteroid/snow/rimstation
	baseturfs = /turf/open/misc/asteroid/snow/rimstation
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	planetary_atmos = FALSE

/// Mineable scenery without random ore: the bound deposit is the site's deliberate, persistent payout.
/turf/closed/mineral/rimstation_expedition
	name = "rocky outcrop"
	desc = "Native stone pushed up through the surrounding soil."
	baseturfs = /turf/open/misc/dirt/planet/rimstation
	turf_type = /turf/open/misc/dirt/planet/rimstation
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	temperature = T20C

/turf/closed/mineral/rimstation_expedition/snow
	parent_type = /turf/closed/mineral/snowmountain
	name = "snowy outcrop"
	desc = "Native stone mantled in old snow."
	baseturfs = /turf/open/misc/asteroid/snow/rimstation
	turf_type = /turf/open/misc/asteroid/snow/rimstation
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	temperature = T20C

/// Deterministic cracked earth: the parent randomizes its icon through BYOND's global RNG.
/turf/open/misc/dirt/jungle/wasteland/rimstation
	baseturfs = /turf/open/misc/dirt/jungle/wasteland/rimstation
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	planetary_atmos = FALSE
	floor_variance = 0

#undef RIMSTATION_EXPEDITION_SCENE_NOISE_ZOOM
#undef RIMSTATION_EXPEDITION_SCENE_ROLL_MAX
