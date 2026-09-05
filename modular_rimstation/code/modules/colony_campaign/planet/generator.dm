#define RIMSTATION_ELEVATION_ZOOM 84
#define RIMSTATION_RIDGE_ZOOM 48
#define RIMSTATION_CLIMATE_ZOOM 110
#define RIMSTATION_ECOLOGY_ZOOM 38
#define RIMSTATION_MOUNTAIN_THRESHOLD 0.68
#define RIMSTATION_CAVE_GROWTH_THRESHOLD 0.57
#define RIMSTATION_CAVE_GROWTH_PASSES 4
#define RIMSTATION_RIVER_HALF_WIDTH 2
#define RIMSTATION_RIVER_POOL_CHANCE 1100
#define RIMSTATION_GENERATION_ROLL_MAX 10000
#define RIMSTATION_RAID_MARKERS_PER_EDGE 2
#define RIMSTATION_RAID_MARKER_MIN_SPACING 20

/**
 * The deterministic plan behind one generated colony landscape.
 *
 * Z2 and Z3 read the same arrays: terrain on the upper level is therefore always the roof of the matching
 * mountain footprint below. Coordinates are local to these bounds, so a future overmap cell can reuse this
 * context without its result depending on a turf reservation's absolute world coordinates or load order.
 * `cell_identity` already namespaces every stream when supplied. `cell_profile` is retained as the extension
 * point for chosen-cell climate and geology; the planet remains the current source of those values.
 */
/datum/rimstation_colony_generation_context
	var/datum/planet_definition/planet
	var/generation_version
	var/cell_identity
	var/list/cell_profile

	var/min_x
	var/min_y
	var/max_x
	var/max_y
	var/width
	var/height
	var/deep_z
	var/surface_z
	var/highlands_z
	var/sky_z

	var/landing_min_x
	var/landing_min_y
	var/landing_max_x
	var/landing_max_y
	/// Boolean mask of the authored landing area, indexed like every generated field.
	var/list/landing_mask
	/// Euclidean distance from the authored landing shape, populated only through the blend radius.
	var/list/landing_distance_field

	var/list/elevation_field
	var/list/ridge_field
	var/list/heat_field
	var/list/moisture_field
	var/list/ecology_field
	var/list/cave_field
	var/list/terrain_plan
	var/list/biome_plan
	/// Mountain footprint before caves open inside it; retained for generation diagnostics and balancing.
	var/mountain_tile_count = 0
	/// Numeric rust-g seeds folded to this context, cached because coordinate placement reads them heavily.
	var/list/resolved_seeds
	/// Indexed by the highland coordinate. The value points from the lowland stair toward its plateau exit.
	var/list/ascent_directions
	/// Walkable, landing-connected map-edge coordinates where raids may be proposed after ecology placement.
	var/list/raid_insertion_indices
	var/plan_built = FALSE

/datum/rimstation_colony_generation_context/New(
	datum/planet_definition/planet,
	min_x,
	min_y,
	max_x,
	max_y,
	surface_z,
	cell_identity,
	list/cell_profile,
)
	. = ..()
	src.planet = planet
	src.generation_version = planet?.generation_version
	src.cell_identity = cell_identity
	src.cell_profile = cell_profile
	src.min_x = min_x
	src.min_y = min_y
	src.max_x = max_x
	src.max_y = max_y
	src.width = max_x - min_x + 1
	src.height = max_y - min_y + 1
	src.surface_z = surface_z
	deep_z = surface_z - 1
	highlands_z = surface_z + 1
	sky_z = surface_z + 2

/datum/rimstation_colony_generation_context/Destroy(force)
	planet = null
	cell_profile = null
	elevation_field = null
	ridge_field = null
	heat_field = null
	moisture_field = null
	ecology_field = null
	cave_field = null
	terrain_plan = null
	biome_plan = null
	landing_mask = null
	landing_distance_field = null
	resolved_seeds = null
	ascent_directions = null
	raid_insertion_indices = null
	return ..()

/// Finds the exact authored clearing shape without making it part of generated terrain.
/datum/rimstation_colony_generation_context/proc/discover_landing_bounds()
	if(surface_z < 1)
		return
	landing_mask = new /list(width * height)
	for(var/x in min_x to max_x)
		for(var/y in min_y to max_y)
			var/turf/checking = locate(x, y, surface_z)
			if(!istype(get_area(checking), /area/rimstation_colony/surface/landing))
				continue
			landing_mask[coordinate_index(x, y)] = TRUE
			landing_min_x = isnull(landing_min_x) ? x : min(landing_min_x, x)
			landing_min_y = isnull(landing_min_y) ? y : min(landing_min_y, y)
			landing_max_x = isnull(landing_max_x) ? x : max(landing_max_x, x)
			landing_max_y = isnull(landing_max_y) ? y : max(landing_max_y, y)
	build_landing_distance_field()

/// Test and preview callers can provide an authored reservation without creating real turfs.
/datum/rimstation_colony_generation_context/proc/set_landing_bounds(min_x, min_y, max_x, max_y)
	landing_min_x = max(src.min_x, min_x)
	landing_min_y = max(src.min_y, min_y)
	landing_max_x = min(src.max_x, max_x)
	landing_max_y = min(src.max_y, max_y)
	landing_mask = new /list(width * height)
	for(var/x in landing_min_x to landing_max_x)
		for(var/y in landing_min_y to landing_max_y)
			landing_mask[coordinate_index(x, y)] = TRUE
	build_landing_distance_field()

/**
 * Measures outward from every authored landing turf instead of from its bounding box.
 *
 * The radius is deliberately small, so stamping exact Euclidean distances around the authored tiles is both
 * cheaper and more faithful than a whole-map path search. A round or irregular landing area therefore keeps
 * a round or irregular transition instead of acquiring square corners from its extrema.
 */
/datum/rimstation_colony_generation_context/proc/build_landing_distance_field()
	landing_distance_field = new /list(width * height)
	if(!length(landing_mask))
		return
	for(var/landing_index in 1 to length(landing_mask))
		if(!landing_mask[landing_index])
			continue
		var/landing_x = index_x(landing_index)
		var/landing_y = index_y(landing_index)
		for(var/x_offset in -RIMSTATION_LANDING_BLEND_RADIUS to RIMSTATION_LANDING_BLEND_RADIUS)
			for(var/y_offset in -RIMSTATION_LANDING_BLEND_RADIUS to RIMSTATION_LANDING_BLEND_RADIUS)
				var/distance = sqrt((x_offset * x_offset) + (y_offset * y_offset))
				if(distance > RIMSTATION_LANDING_BLEND_RADIUS)
					continue
				var/nearby_index = coordinate_index(landing_x + x_offset, landing_y + y_offset)
				if(isnull(nearby_index))
					continue
				var/current_distance = landing_distance_field[nearby_index]
				if(isnull(current_distance) || distance < current_distance)
					landing_distance_field[nearby_index] = distance
		CHECK_TICK

/datum/rimstation_colony_generation_context/proc/contains(x, y)
	return x >= min_x && x <= max_x && y >= min_y && y <= max_y

/datum/rimstation_colony_generation_context/proc/coordinate_index(x, y)
	if(!contains(x, y))
		return null
	return ((y - min_y) * width) + (x - min_x) + 1

/datum/rimstation_colony_generation_context/proc/index_x(index)
	return ((index - 1) % width) + min_x

/datum/rimstation_colony_generation_context/proc/index_y(index)
	return floor((index - 1) / width) + min_y

/datum/rimstation_colony_generation_context/proc/offset_x(x, direction)
	if(direction & EAST)
		return x + 1
	if(direction & WEST)
		return x - 1
	return x

/datum/rimstation_colony_generation_context/proc/offset_y(y, direction)
	if(direction & NORTH)
		return y + 1
	if(direction & SOUTH)
		return y - 1
	return y

/// Numeric seed suitable for rust-g noise, namespaced to this plan rather than its absolute loaded Z.
/datum/rimstation_colony_generation_context/proc/resolve_seed(stream)
	LAZYINITLIST(resolved_seeds)
	var/cached_seed = resolved_seeds[stream]
	if(!isnull(cached_seed))
		return cached_seed
	var/stream_seed = planet?.get_stream_seed(stream)
	if(isnull(stream_seed))
		return null
	var/cell_seed_key = "planet"
	if(!isnull(cell_identity))
		cell_seed_key = "cell:[cell_identity]"
	var/folded = rustg_hash_string(RUSTG_HASH_SHA256, "[stream_seed]:colony:[width]x[height]:[cell_seed_key]")
	var/resolved_seed = hex2num(copytext(folded, 1, 7)) % 50000
	resolved_seeds[stream] = resolved_seed
	return resolved_seed

/// Pure coordinate roll. Content placement never consumes BYOND's global RNG.
/datum/rimstation_colony_generation_context/proc/coordinate_roll(stream, x, y, salt, modulus = RIMSTATION_GENERATION_ROLL_MAX)
	if(modulus <= 0)
		return 0
	var/seed = resolve_seed(stream)
	if(isnull(seed))
		return 0
	var/local_x = x - min_x
	var/local_y = y - min_y
	var/folded = rustg_hash_string(RUSTG_HASH_XXH64, "[seed]:[local_x]:[local_y]:[salt]")
	return hex2num(copytext(folded, 1, 7)) % modulus

/datum/rimstation_colony_generation_context/proc/sample_noise(seed, x, y, zoom)
	var/local_x = x - min_x + 1
	var/local_y = y - min_y + 1
	return text2num(rustg_noise_get_at_coordinates("[seed]", "[local_x / zoom]", "[local_y / zoom]"))

/// Distance outside the exact landing shape. Zero means the coordinate is authored ground.
/datum/rimstation_colony_generation_context/proc/landing_distance(x, y)
	var/index = coordinate_index(x, y)
	if(isnull(index) || !length(landing_distance_field))
		return INFINITY
	var/distance = landing_distance_field[index]
	return isnull(distance) ? INFINITY : distance

/datum/rimstation_colony_generation_context/proc/landing_blend(x, y)
	return clamp(landing_distance(x, y) / RIMSTATION_LANDING_BLEND_RADIUS, 0, 1)

/datum/rimstation_colony_generation_context/proc/is_landing_protected(x, y, padding = 0)
	return landing_distance(x, y) <= padding

/**
 * Builds the reusable fields first, then derives rivers, caves, and ascents in deterministic passes.
 * Materialization happens later so validation and fingerprints never need to mutate the world.
 */
/datum/rimstation_colony_generation_context/proc/build_plan()
	if(plan_built || !planet || width <= 0 || height <= 0)
		return FALSE

	var/tile_count = width * height
	elevation_field = new /list(tile_count)
	ridge_field = new /list(tile_count)
	heat_field = new /list(tile_count)
	moisture_field = new /list(tile_count)
	ecology_field = new /list(tile_count)
	cave_field = new /list(tile_count)
	terrain_plan = new /list(tile_count)
	biome_plan = new /list(tile_count)
	ascent_directions = new /list(tile_count)

	var/elevation_seed = resolve_seed(PLANET_STREAM_ELEVATION)
	var/ridge_seed = resolve_seed(PLANET_STREAM_RIDGES)
	var/heat_seed = resolve_seed(PLANET_STREAM_BIOME_HEAT)
	var/moisture_seed = resolve_seed(PLANET_STREAM_BIOME_HUMIDITY)
	var/ecology_seed = resolve_seed(PLANET_STREAM_ECOLOGY)
	var/cave_seed = resolve_seed(PLANET_STREAM_CAVES)
	if(isnull(elevation_seed) || isnull(ridge_seed) || isnull(heat_seed) || isnull(moisture_seed) || isnull(ecology_seed) || isnull(cave_seed))
		return FALSE

	var/planet_moisture = clamp(planet.moisture / 100, 0, 1)
	var/temperature_bias = clamp((planet.mean_temperature - T20C) / 100, -0.2, 0.2)
	mountain_tile_count = 0
	for(var/y in min_y to max_y)
		for(var/x in min_x to max_x)
			var/index = coordinate_index(x, y)
			var/elevation_noise = sample_noise(elevation_seed, x, y, RIMSTATION_ELEVATION_ZOOM)
			var/raw_ridge = sample_noise(ridge_seed, x, y, RIMSTATION_RIDGE_ZOOM)
			var/ridge = 1 - abs((raw_ridge * 2) - 1)
			var/elevation = (elevation_noise * 0.72) + (ridge * 0.28)
			var/blend = landing_blend(x, y)
			if(is_landing_protected(x, y, RIMSTATION_LANDING_BLEND_RADIUS))
				elevation = min(elevation, RIMSTATION_MOUNTAIN_THRESHOLD - 0.05)

			elevation_field[index] = elevation
			ridge_field[index] = ridge
			heat_field[index] = clamp((sample_noise(heat_seed, x, y, RIMSTATION_CLIMATE_ZOOM) * 0.7) + 0.15 + temperature_bias, 0, 1)
			moisture_field[index] = clamp((sample_noise(moisture_seed, x, y, RIMSTATION_CLIMATE_ZOOM) * 0.55) + (planet_moisture * 0.45), 0, 1)
			ecology_field[index] = sample_noise(ecology_seed, x, y, RIMSTATION_ECOLOGY_ZOOM)
			cave_field[index] = sample_noise(cave_seed, x, y, RIMSTATION_RIDGE_ZOOM)

			if(elevation >= RIMSTATION_MOUNTAIN_THRESHOLD)
				terrain_plan[index] = RIMSTATION_TERRAIN_MOUNTAIN
				biome_plan[index] = RIMSTATION_BIOME_HIGHLAND
				mountain_tile_count++
			else
				terrain_plan[index] = RIMSTATION_TERRAIN_LOWLAND
				biome_plan[index] = classify_lowland_biome(index, blend)
			CHECK_TICK

	route_river()
	carve_caves()
	select_ascents()
	select_raid_insertions()
	plan_built = TRUE
	return TRUE

/datum/rimstation_colony_generation_context/proc/classify_lowland_biome(index, blend = 1)
	if(blend < 0.75)
		return RIMSTATION_BIOME_GRASSLAND
	var/moisture = moisture_field[index]
	var/ecology = ecology_field[index]
	if(moisture >= 0.68)
		return ecology >= 0.4 ? RIMSTATION_BIOME_FOREST : RIMSTATION_BIOME_WETLAND
	if(moisture >= 0.43)
		return ecology >= 0.55 ? RIMSTATION_BIOME_FOREST : RIMSTATION_BIOME_SCRUBLAND
	return ecology >= 0.72 ? RIMSTATION_BIOME_SCRUBLAND : RIMSTATION_BIOME_GRASSLAND

/// Traces one continuous channel through the lowest nearby terrain from north to south.
/datum/rimstation_colony_generation_context/proc/route_river()
	var/usable_width = max(width - 16, 1)
	var/current_x = min_x + min(8, width - 1) + coordinate_roll(PLANET_STREAM_RIVERS, min_x, min_y, "river_start", usable_width)
	current_x = clamp(current_x, min_x, max_x)

	for(var/y in min_y to max_y)
		var/best_x = current_x
		var/best_score = INFINITY
		for(var/offset in -4 to 4)
			var/candidate_x = clamp(current_x + offset, min_x, max_x)
			var/index = coordinate_index(candidate_x, y)
			var/score = elevation_field[index]
			if(is_mountain_footprint(index))
				score += 2
			if(is_landing_protected(candidate_x, y, RIMSTATION_LANDING_BLEND_RADIUS))
				score += 5
			score += abs(offset) * 0.015
			score += (coordinate_roll(PLANET_STREAM_RIVERS, candidate_x, y, "river_meander") / RIMSTATION_GENERATION_ROLL_MAX) * 0.12
			if(score < best_score)
				best_score = score
				best_x = candidate_x
		current_x = best_x

		var/deep_pool = coordinate_roll(PLANET_STREAM_RIVERS, current_x, y, "river_depth") < RIMSTATION_RIVER_POOL_CHANCE
		for(var/bank_offset in -RIMSTATION_RIVER_HALF_WIDTH to RIMSTATION_RIVER_HALF_WIDTH)
			var/river_x = current_x + bank_offset
			if(!contains(river_x, y) || is_landing_protected(river_x, y, RIMSTATION_LANDING_BLEND_RADIUS))
				continue
			var/index = coordinate_index(river_x, y)
			if(abs(bank_offset) == RIMSTATION_RIVER_HALF_WIDTH)
				if(terrain_plan[index] != RIMSTATION_TERRAIN_RIVER_SHALLOW && terrain_plan[index] != RIMSTATION_TERRAIN_RIVER_DEEP)
					terrain_plan[index] = RIMSTATION_TERRAIN_RIVER_BANK
			else if(bank_offset == 0 && deep_pool)
				terrain_plan[index] = RIMSTATION_TERRAIN_RIVER_DEEP
			else
				terrain_plan[index] = RIMSTATION_TERRAIN_RIVER_SHALLOW
			biome_plan[index] = RIMSTATION_BIOME_WETLAND
		CHECK_TICK

/datum/rimstation_colony_generation_context/proc/is_mountain_footprint(index)
	if(isnull(index))
		return FALSE
	return terrain_plan[index] == RIMSTATION_TERRAIN_MOUNTAIN || terrain_plan[index] == RIMSTATION_TERRAIN_CAVE

/datum/rimstation_colony_generation_context/proc/mountain_neighbor_count(x, y)
	var/count = 0
	for(var/direction in GLOB.cardinals)
		var/neighbor_index = coordinate_index(offset_x(x, direction), offset_y(y, direction))
		if(is_mountain_footprint(neighbor_index))
			count++
	return count

/// Direction from a mountain edge toward traversable lowland, or null for an interior tile.
/datum/rimstation_colony_generation_context/proc/get_outward_direction(x, y)
	for(var/direction in GLOB.cardinals)
		var/outside_x = offset_x(x, direction)
		var/outside_y = offset_y(y, direction)
		var/outside_index = coordinate_index(outside_x, outside_y)
		if(isnull(outside_index) || is_mountain_footprint(outside_index))
			continue
		if(terrain_plan[outside_index] == RIMSTATION_TERRAIN_RIVER_DEEP)
			continue
		return direction
	return null

/datum/rimstation_colony_generation_context/proc/is_far_from_selected(index, list/selected, minimum_distance)
	var/x = index_x(index)
	var/y = index_y(index)
	for(var/other_index in selected)
		if(max(abs(x - index_x(other_index)), abs(y - index_y(other_index))) < minimum_distance)
			return FALSE
	return TRUE

/**
 * Every extra cave cell grows from a carved entrance path. Noise controls the chambers, but cannot create an
 * isolated pocket with no usable entrance because disconnected candidates are never admitted to the plan.
 */
/datum/rimstation_colony_generation_context/proc/carve_caves()
	var/list/entries = list()
	var/fallback_entry
	for(var/index in 1 to length(terrain_plan))
		if(terrain_plan[index] != RIMSTATION_TERRAIN_MOUNTAIN)
			continue
		var/x = index_x(index)
		var/y = index_y(index)
		var/outward = get_outward_direction(x, y)
		if(isnull(outward) || is_landing_protected(x, y, RIMSTATION_LANDING_BLEND_RADIUS))
			continue
		if(isnull(fallback_entry))
			fallback_entry = index
		if(length(entries) >= RIMSTATION_MAX_CAVE_SYSTEMS)
			continue
		if(coordinate_roll(PLANET_STREAM_CAVES, x, y, "cave_entry", 1000) >= 18)
			continue
		if(!is_far_from_selected(index, entries, 28))
			continue
		entries += index

	if(!length(entries) && !isnull(fallback_entry))
		entries += fallback_entry

	for(var/entry_index in entries)
		var/entry_x = index_x(entry_index)
		var/entry_y = index_y(entry_index)
		var/inward = REVERSE_DIR(get_outward_direction(entry_x, entry_y))
		carve_cave_tunnel(entry_x, entry_y, inward)

	for(var/growth_pass in 1 to RIMSTATION_CAVE_GROWTH_PASSES)
		var/list/to_open = list()
		for(var/index in 1 to length(terrain_plan))
			if(terrain_plan[index] != RIMSTATION_TERRAIN_MOUNTAIN || cave_field[index] < RIMSTATION_CAVE_GROWTH_THRESHOLD)
				continue
			var/x = index_x(index)
			var/y = index_y(index)
			for(var/direction in GLOB.cardinals)
				var/neighbor_index = coordinate_index(offset_x(x, direction), offset_y(y, direction))
				if(!isnull(neighbor_index) && terrain_plan[neighbor_index] == RIMSTATION_TERRAIN_CAVE)
					to_open += index
					break
		for(var/index in to_open)
			terrain_plan[index] = RIMSTATION_TERRAIN_CAVE
			biome_plan[index] = RIMSTATION_BIOME_CAVE
		CHECK_TICK

/datum/rimstation_colony_generation_context/proc/carve_cave_tunnel(start_x, start_y, inward_direction)
	var/current_x = start_x
	var/current_y = start_y
	var/last_direction = inward_direction
	var/tunnel_length = 24 + coordinate_roll(PLANET_STREAM_CAVES, start_x, start_y, "cave_length", 20)
	for(var/step_number in 1 to tunnel_length)
		var/current_index = coordinate_index(current_x, current_y)
		if(isnull(current_index) || !is_mountain_footprint(current_index))
			break
		terrain_plan[current_index] = RIMSTATION_TERRAIN_CAVE
		biome_plan[current_index] = RIMSTATION_BIOME_CAVE

		for(var/direction in GLOB.cardinals)
			var/side_x = offset_x(current_x, direction)
			var/side_y = offset_y(current_y, direction)
			var/side_index = coordinate_index(side_x, side_y)
			if(!isnull(side_index) && terrain_plan[side_index] == RIMSTATION_TERRAIN_MOUNTAIN && coordinate_roll(PLANET_STREAM_CAVES, side_x, side_y, "cave_width", 100) < 35)
				terrain_plan[side_index] = RIMSTATION_TERRAIN_CAVE
				biome_plan[side_index] = RIMSTATION_BIOME_CAVE

		var/best_direction
		var/best_score = -INFINITY
		for(var/direction in GLOB.cardinals)
			var/next_x = offset_x(current_x, direction)
			var/next_y = offset_y(current_y, direction)
			var/next_index = coordinate_index(next_x, next_y)
			if(isnull(next_index) || !is_mountain_footprint(next_index))
				continue
			var/score = cave_field[next_index] + (mountain_neighbor_count(next_x, next_y) * 0.04)
			if(step_number <= 6 && direction == inward_direction)
				score += 0.3
			if(direction == REVERSE_DIR(last_direction))
				score -= 0.25
			score += coordinate_roll(PLANET_STREAM_CAVES, next_x, next_y, "cave_path_[step_number]", 1000) / 10000
			if(score > best_score)
				best_score = score
				best_direction = direction
		if(isnull(best_direction))
			break
		current_x = offset_x(current_x, best_direction)
		current_y = offset_y(current_y, best_direction)
		last_direction = best_direction

/// Chooses a small, deterministic set of climbable breaks in otherwise bounded plateau edges.
/datum/rimstation_colony_generation_context/proc/select_ascents()
	var/list/selected = list()
	var/fallback_index
	var/fallback_direction
	for(var/index in 1 to length(terrain_plan))
		if(terrain_plan[index] != RIMSTATION_TERRAIN_MOUNTAIN)
			continue
		var/x = index_x(index)
		var/y = index_y(index)
		var/outward = get_outward_direction(x, y)
		if(isnull(outward) || is_landing_protected(x, y, RIMSTATION_LANDING_BLEND_RADIUS))
			continue
		var/outside_x = offset_x(x, outward)
		var/outside_y = offset_y(y, outward)
		var/outside_index = coordinate_index(outside_x, outside_y)
		if(isnull(outside_index) || terrain_plan[outside_index] != RIMSTATION_TERRAIN_LOWLAND)
			continue
		if(isnull(fallback_index))
			fallback_index = index
			fallback_direction = REVERSE_DIR(outward)
		if(length(selected) >= RIMSTATION_MAX_ASCENTS)
			continue
		if(coordinate_roll(PLANET_STREAM_TERRAIN, x, y, "ascent", 1000) >= 10)
			continue
		if(!is_far_from_selected(index, selected, 24))
			continue
		selected += index
		ascent_directions[index] = REVERSE_DIR(outward)

	if(!length(selected) && !isnull(fallback_index))
		ascent_directions[fallback_index] = fallback_direction

/// Authored landing turf closest to the centre of the authored shape.
/datum/rimstation_colony_generation_context/proc/get_landing_anchor_index()
	if(isnull(landing_min_x) || !length(landing_mask))
		return null
	var/centre_x = (landing_min_x + landing_max_x) / 2
	var/centre_y = (landing_min_y + landing_max_y) / 2
	var/best_index
	var/best_distance = INFINITY
	for(var/index in 1 to length(landing_mask))
		if(!landing_mask[index])
			continue
		var/x_distance = index_x(index) - centre_x
		var/y_distance = index_y(index) - centre_y
		var/distance = (x_distance * x_distance) + (y_distance * y_distance)
		if(distance >= best_distance)
			continue
		best_distance = distance
		best_index = index
	return best_index

/// TRUE when the generated ground can carry the raid route flood fill.
/datum/rimstation_colony_generation_context/proc/is_plan_walkable(index)
	if(isnull(index))
		return FALSE
	var/terrain = terrain_plan[index]
	return terrain != RIMSTATION_TERRAIN_MOUNTAIN && terrain != RIMSTATION_TERRAIN_RIVER_DEEP

/// All plan coordinates connected to the landing clearing without crossing solid mountains or deep water.
/datum/rimstation_colony_generation_context/proc/build_landing_reachability()
	var/list/reachable = new /list(length(terrain_plan))
	var/anchor_index = get_landing_anchor_index()
	if(isnull(anchor_index) || !is_plan_walkable(anchor_index))
		return reachable

	var/list/frontier = list(anchor_index)
	reachable[anchor_index] = TRUE
	var/frontier_position = 1
	while(frontier_position <= length(frontier))
		var/current_index = frontier[frontier_position++]
		var/current_x = index_x(current_index)
		var/current_y = index_y(current_index)
		for(var/direction in GLOB.cardinals)
			var/neighbor_index = coordinate_index(offset_x(current_x, direction), offset_y(current_y, direction))
			if(isnull(neighbor_index) || reachable[neighbor_index] || !is_plan_walkable(neighbor_index))
				continue
			reachable[neighbor_index] = TRUE
			frontier += neighbor_index
		CHECK_TICK
	return reachable

/datum/rimstation_colony_generation_context/proc/is_raid_edge_candidate(index, edge)
	var/terrain = terrain_plan[index]
	if(terrain != RIMSTATION_TERRAIN_LOWLAND && terrain != RIMSTATION_TERRAIN_RIVER_BANK)
		return FALSE
	var/x = index_x(index)
	var/y = index_y(index)
	switch(edge)
		if(NORTH)
			return y >= max_y - COLONY_RAID_EDGE_BAND + 1
		if(EAST)
			return x >= max_x - COLONY_RAID_EDGE_BAND + 1
		if(SOUTH)
			return y <= min_y + COLONY_RAID_EDGE_BAND - 1
		if(WEST)
			return x <= min_x + COLONY_RAID_EDGE_BAND - 1
	return FALSE

/**
 * Picks two reachable proposals along each edge.
 *
 * The raid system still validates real turf density and connectivity when an attack begins. These generated
 * landmarks make that validation useful on a procedural map instead of asking one stale mapped coordinate to
 * survive every possible mountain layout.
 */
/datum/rimstation_colony_generation_context/proc/select_raid_insertions()
	raid_insertion_indices = list()
	var/list/reachable = build_landing_reachability()
	for(var/edge in GLOB.cardinals)
		for(var/slot in 1 to RIMSTATION_RAID_MARKERS_PER_EDGE)
			var/fraction = slot / (RIMSTATION_RAID_MARKERS_PER_EDGE + 1)
			var/target_x = round(min_x + ((width - 1) * fraction))
			var/target_y = round(min_y + ((height - 1) * fraction))
			var/best_index
			var/best_score = INFINITY
			for(var/index in 1 to length(terrain_plan))
				if(!reachable[index] || !is_raid_edge_candidate(index, edge))
					continue
				if(!is_far_from_selected(index, raid_insertion_indices, RIMSTATION_RAID_MARKER_MIN_SPACING))
					continue
				var/x = index_x(index)
				var/y = index_y(index)
				var/along_edge_distance
				var/inward_distance
				if(edge == NORTH || edge == SOUTH)
					along_edge_distance = abs(x - target_x)
					inward_distance = min(abs(y - min_y), abs(max_y - y))
				else
					along_edge_distance = abs(y - target_y)
					inward_distance = min(abs(x - min_x), abs(max_x - x))
				var/score = (along_edge_distance * 10) + inward_distance
				score += coordinate_roll(PLANET_STREAM_ECOLOGY, x, y, "raid_marker_[edge]_[slot]", 1000) / 1000
				if(score >= best_score)
					continue
				best_score = score
				best_index = index
			if(!isnull(best_index))
				raid_insertion_indices += best_index
	return raid_insertion_indices

/datum/rimstation_colony_generation_context/proc/is_plateau_edge(x, y)
	var/index = coordinate_index(x, y)
	if(!is_mountain_footprint(index))
		return FALSE
	for(var/direction in GLOB.alldirs)
		var/neighbor_index = coordinate_index(offset_x(x, direction), offset_y(y, direction))
		if(!isnull(neighbor_index) && !is_mountain_footprint(neighbor_index))
			return TRUE
	return FALSE

/datum/rimstation_colony_generation_context/proc/get_lowland_turf_type(x, y)
	var/index = coordinate_index(x, y)
	switch(terrain_plan[index])
		if(RIMSTATION_TERRAIN_MOUNTAIN)
			return /turf/closed/mineral/random/rimstation
		if(RIMSTATION_TERRAIN_CAVE)
			return /turf/open/misc/asteroid/rimstation
		if(RIMSTATION_TERRAIN_RIVER_BANK)
			return /turf/open/misc/dirt/planet/rimstation/wet
		if(RIMSTATION_TERRAIN_RIVER_SHALLOW)
			return /turf/open/water/rimstation
		if(RIMSTATION_TERRAIN_RIVER_DEEP)
			return /turf/open/water/rimstation/deep
	if(biome_plan[index] == RIMSTATION_BIOME_GRASSLAND || biome_plan[index] == RIMSTATION_BIOME_FOREST)
		return /turf/open/misc/grass/rimstation
	if(biome_plan[index] == RIMSTATION_BIOME_WETLAND)
		return /turf/open/misc/dirt/planet/rimstation/wet
	return /turf/open/misc/dirt/planet/rimstation

/datum/rimstation_colony_generation_context/proc/get_highland_turf_type(x, y)
	var/index = coordinate_index(x, y)
	if(!is_mountain_footprint(index))
		return /turf/open/openspace/rimstation
	return /turf/open/misc/grass/rimstation/highland

/// Stable summary used by tests and preview tooling without touching real turfs.
/datum/rimstation_colony_generation_context/proc/fingerprint(sample_count = 64)
	if(!plan_built || sample_count <= 0)
		return null
	var/list/parts = list(
		"version=[generation_version]",
		"bounds=[width]x[height]",
		"cell=[cell_identity]",
		"return=[get_landing_anchor_index()]",
		"raids=[raid_insertion_indices.Join(",")]",
	)
	for(var/i in 1 to sample_count)
		var/x = min_x + ((i * 17) % width)
		var/y = min_y + ((i * 29) % height)
		var/index = coordinate_index(x, y)
		var/feature_roll = coordinate_roll(PLANET_STREAM_ECOLOGY, x, y, "fingerprint_feature")
		parts += "[x-min_x],[y-min_y]:[terrain_plan[index]]:[biome_plan[index]]:[round(elevation_field[index], 0.001)]:[round(moisture_field[index], 0.001)]:[ascent_directions[index]]:[feature_roll]"
	return rustg_hash_string(RUSTG_HASH_SHA256, parts.Join("|"))


/**
 * Primary-map materializer. This is intentionally a pre-initialization map generator: future expedition
 * reservations must use runtime-safe ChangeTurf and atom initialization behind a separate scene provider.
 */
/datum/map_generator/rimstation_colony
	buildmode_name = "Rimstation Colony Landscape"
	var/datum/planet_definition/planet
	var/datum/rimstation_colony_generation_context/generation_context

/datum/map_generator/rimstation_colony/New(datum/planet_definition/planet)
	. = ..()
	src.planet = planet || get_active_colony_planet()

/datum/map_generator/rimstation_colony/Destroy(force)
	QDEL_NULL(generation_context)
	planet = null
	return ..()

/datum/map_generator/rimstation_colony/proc/create_generation_context(min_x, min_y, max_x, max_y, surface_z, cell_identity, list/cell_profile)
	RETURN_TYPE(/datum/rimstation_colony_generation_context)
	return new /datum/rimstation_colony_generation_context(planet, min_x, min_y, max_x, max_y, surface_z, cell_identity, cell_profile)

/datum/map_generator/rimstation_colony/generate_terrain(list/turf/turfs, area/generate_in)
	if(!length(turfs) || !planet)
		return
	var/min_x = world.maxx
	var/min_y = world.maxy
	var/max_x = 1
	var/max_y = 1
	for(var/turf/target as anything in turfs)
		min_x = min(min_x, target.x)
		min_y = min(min_y, target.y)
		max_x = max(max_x, target.x)
		max_y = max(max_y, target.y)

	QDEL_NULL(generation_context)
	generation_context = create_generation_context(min_x, min_y, max_x, max_y, generate_in.z)
	generation_context.discover_landing_bounds()
	if(!generation_context.build_plan())
		CRASH("Rimstation colony landscape plan could not be built.")

	var/start_time = REALTIMEOFDAY
	for(var/turf/lowland as anything in turfs)
		var/lowland_type = generation_context.get_lowland_turf_type(lowland.x, lowland.y)
		replace_uninitialized_turf(lowland, lowland_type)
		var/turf/highland = locate(lowland.x, lowland.y, generation_context.highlands_z)
		if(highland)
			var/highland_type = generation_context.get_highland_turf_type(lowland.x, lowland.y)
			replace_uninitialized_turf(highland, highland_type)
		CHECK_TICK

	place_ascents()
	var/mountain_percentage = round((generation_context.mountain_tile_count / (generation_context.width * generation_context.height)) * 100, 0.1)
	var/message = "Rimstation colony terrain generation finished in [(REALTIMEOFDAY - start_time) / 10]s ([mountain_percentage]% mountain footprint)."
	add_startup_message(message)
	log_world(message)

/// Safe only during mapping initialization, before either turf has initialized.
/datum/map_generator/rimstation_colony/proc/replace_uninitialized_turf(turf/old_turf, new_turf_type)
	var/old_flags = old_turf.turf_flags
	var/turf/new_turf = new new_turf_type(old_turf)
	if(old_flags & NO_RUINS)
		new_turf.turf_flags |= NO_RUINS
	return new_turf

/datum/map_generator/rimstation_colony/proc/place_ascents()
	for(var/index in 1 to length(generation_context.ascent_directions))
		var/stair_direction = generation_context.ascent_directions[index]
		if(!stair_direction)
			continue
		var/highland_x = generation_context.index_x(index)
		var/highland_y = generation_context.index_y(index)
		var/stair_x = generation_context.offset_x(highland_x, REVERSE_DIR(stair_direction))
		var/stair_y = generation_context.offset_y(highland_y, REVERSE_DIR(stair_direction))
		var/turf/stair_turf = locate(stair_x, stair_y, generation_context.surface_z)
		if(!stair_turf || istype(get_area(stair_turf), /area/rimstation_colony/surface/landing))
			continue
		var/obj/structure/stairs/stone/stairs = new(stair_turf)
		stairs.dir = stair_direction

/datum/map_generator/rimstation_colony/populate_terrain(list/turf/turfs, area/generate_in)
	if(!generation_context?.plan_built || generate_in.z != generation_context.surface_z)
		return
	var/start_time = REALTIMEOFDAY
	for(var/turf/lowland as anything in turfs)
		var/index = generation_context.coordinate_index(lowland.x, lowland.y)
		var/terrain = generation_context.terrain_plan[index]
		var/biome = generation_context.biome_plan[index]
		populate_coordinate(lowland, lowland.x, lowland.y, terrain, biome, "lowland")

		if(generation_context.is_mountain_footprint(index))
			var/turf/highland = locate(lowland.x, lowland.y, generation_context.highlands_z)
			if(highland && !generation_context.is_plateau_edge(lowland.x, lowland.y))
				populate_coordinate(highland, lowland.x, lowland.y, RIMSTATION_TERRAIN_LOWLAND, RIMSTATION_BIOME_HIGHLAND, "highland")
		CHECK_TICK

	place_generated_landmarks()
	var/message = "Rimstation colony ecology generation finished in [(REALTIMEOFDAY - start_time) / 10]s."
	add_startup_message(message)
	log_world(message)

/// Places travel endpoints only after ecology, on coordinates the deterministic plan reserved for them.
/datum/map_generator/rimstation_colony/proc/place_generated_landmarks()
	var/return_index = generation_context.get_landing_anchor_index()
	if(!isnull(return_index))
		var/turf/return_turf = locate(
			generation_context.index_x(return_index),
			generation_context.index_y(return_index),
			generation_context.surface_z,
		)
		if(return_turf)
			new /obj/effect/landmark/rimstation_caravan_return(return_turf)

	for(var/index in generation_context.raid_insertion_indices)
		var/turf/insertion_turf = locate(
			generation_context.index_x(index),
			generation_context.index_y(index),
			generation_context.surface_z,
		)
		if(insertion_turf)
			new /obj/effect/landmark/rimstation_raid_insertion(insertion_turf)

/datum/map_generator/rimstation_colony/proc/populate_coordinate(turf/target, x, y, terrain, biome, layer_namespace)
	if(terrain == RIMSTATION_TERRAIN_RIVER_SHALLOW || terrain == RIMSTATION_TERRAIN_RIVER_DEEP || terrain == RIMSTATION_TERRAIN_MOUNTAIN)
		return
	var/index = generation_context.coordinate_index(x, y)
	if(layer_namespace == "lowland" && (index in generation_context.raid_insertion_indices))
		return
	var/blend = generation_context.landing_blend(x, y)
	if(blend <= 0.25)
		return

	if(terrain == RIMSTATION_TERRAIN_CAVE)
		if(generation_context.coordinate_roll(PLANET_STREAM_RESOURCES, x, y, "[layer_namespace]_resource_outcrop") < 12)
			var/outcrop_type = generation_context.coordinate_roll(PLANET_STREAM_RESOURCES, x, y, "[layer_namespace]_outcrop_type", 2) ? /obj/structure/flora/rock/pile/siderite : /obj/structure/flora/rock/pile/shale
			new outcrop_type(target)
		else if(generation_context.coordinate_roll(PLANET_STREAM_RESOURCES, x, y, "[layer_namespace]_cave_rock") < 180)
			new /obj/structure/flora/rock(target)
		return

	var/flora_threshold
	switch(biome)
		if(RIMSTATION_BIOME_FOREST)
			flora_threshold = 1500
		if(RIMSTATION_BIOME_WETLAND)
			flora_threshold = 1000
		if(RIMSTATION_BIOME_SCRUBLAND)
			flora_threshold = 650
		if(RIMSTATION_BIOME_HIGHLAND)
			flora_threshold = 450
		else
			flora_threshold = 400
	flora_threshold *= (0.5 + generation_context.ecology_field[index]) * blend
	if(generation_context.coordinate_roll(PLANET_STREAM_ECOLOGY, x, y, "[layer_namespace]_flora") < flora_threshold)
		spawn_flora(target, x, y, biome, layer_namespace)

	var/feature_threshold = 55
	if(biome == RIMSTATION_BIOME_FOREST)
		feature_threshold = 90
	else if(biome == RIMSTATION_BIOME_WETLAND)
		feature_threshold = 75
	else if(biome == RIMSTATION_BIOME_HIGHLAND)
		feature_threshold = 65
	if(generation_context.coordinate_roll(PLANET_STREAM_RESOURCES, x, y, "[layer_namespace]_feature") < feature_threshold)
		var/feature_type = /obj/structure/flora/rock
		if(biome == RIMSTATION_BIOME_FOREST || biome == RIMSTATION_BIOME_WETLAND)
			if(generation_context.coordinate_roll(PLANET_STREAM_RESOURCES, x, y, "[layer_namespace]_fallen_log", 100) < 45)
				feature_type = /obj/structure/flora/rimstation_fallen_log
		new feature_type(target)

	if(generation_context.coordinate_roll(PLANET_STREAM_ECOLOGY, x, y, "[layer_namespace]_fauna") < 5)
		spawn_fauna(target, x, y, layer_namespace)

/datum/map_generator/rimstation_colony/proc/spawn_flora(turf/target, x, y, biome, layer_namespace)
	var/static/list/deciduous_types = list(
		/obj/structure/flora/tree/rimstation_deciduous,
		/obj/structure/flora/tree/rimstation_deciduous/style_2,
		/obj/structure/flora/tree/rimstation_deciduous/style_3,
		/obj/structure/flora/tree/rimstation_deciduous/style_4,
		/obj/structure/flora/tree/rimstation_deciduous/style_5,
	)
	var/static/list/pine_types = list(
		/obj/structure/flora/tree/pine/rimstation,
		/obj/structure/flora/tree/pine/rimstation/style_2,
		/obj/structure/flora/tree/pine/rimstation/style_3,
	)
	var/static/list/tall_grass_types = list(
		/obj/structure/flora/grass/rimstation_tall,
		/obj/structure/flora/grass/rimstation_tall/style_2,
		/obj/structure/flora/grass/rimstation_tall/style_3,
		/obj/structure/flora/grass/rimstation_tall/style_4,
		/obj/structure/flora/grass/rimstation_tall/style_5,
	)
	var/static/list/berry_types = list(
		/obj/structure/flora/bush/rimstation_berry,
		/obj/structure/flora/bush/rimstation_berry/style_2,
		/obj/structure/flora/bush/rimstation_berry/style_3,
	)
	var/selector = generation_context.coordinate_roll(PLANET_STREAM_ECOLOGY, x, y, "[layer_namespace]_flora_type", 100)
	var/flora_type
	switch(biome)
		if(RIMSTATION_BIOME_FOREST)
			if(selector < 45)
				flora_type = deciduous_types[(selector % length(deciduous_types)) + 1]
			else if(selector < 70)
				flora_type = pine_types[(selector % length(pine_types)) + 1]
			else if(selector < 77)
				flora_type = berry_types[(selector % length(berry_types)) + 1]
			else if(selector < 88)
				flora_type = /obj/structure/flora/bush/ferny
			else
				flora_type = tall_grass_types[(selector % length(tall_grass_types)) + 1]
		if(RIMSTATION_BIOME_WETLAND)
			if(selector < 45)
				flora_type = /obj/structure/flora/bush/reed
			else if(selector < 80)
				flora_type = tall_grass_types[(selector % length(tall_grass_types)) + 1]
			else if(selector < 85)
				flora_type = berry_types[(selector % length(berry_types)) + 1]
			else
				flora_type = /obj/structure/flora/bush/ferny
		if(RIMSTATION_BIOME_SCRUBLAND)
			if(selector < 35)
				flora_type = /obj/structure/flora/bush/sparsegrass
			else if(selector < 55)
				flora_type = tall_grass_types[(selector % 2) + 1]
			else if(selector < 75)
				flora_type = /obj/structure/flora/bush/ferny
			else if(selector < 90)
				flora_type = /obj/structure/flora/rock
			else if(selector < 95)
				flora_type = /obj/structure/flora/tree/dead
			else
				flora_type = /obj/structure/flora/rimstation_fallen_log
		if(RIMSTATION_BIOME_HIGHLAND)
			if(selector < 45)
				flora_type = pine_types[(selector % length(pine_types)) + 1]
			else if(selector < 55)
				flora_type = deciduous_types[(selector % length(deciduous_types)) + 1]
			else if(selector < 70)
				flora_type = tall_grass_types[(selector % length(tall_grass_types)) + 1]
			else if(selector < 90)
				flora_type = /obj/structure/flora/rock
			else if(selector < 95)
				flora_type = /obj/structure/flora/tree/dead
			else
				flora_type = /obj/structure/flora/rimstation_fallen_log
		else
			if(selector < 46)
				flora_type = tall_grass_types[(selector % length(tall_grass_types)) + 1]
			else if(selector < 71)
				flora_type = /obj/structure/flora/bush/flowers_yw
			else if(selector < 78)
				flora_type = berry_types[(selector % length(berry_types)) + 1]
			else if(selector < 89)
				flora_type = /obj/structure/flora/bush/flowers_br
			else
				flora_type = /obj/structure/flora/bush/grassy
	var/obj/structure/flora/spawned = new flora_type(target)
	spawned.dir = GLOB.cardinals[(generation_context.coordinate_roll(PLANET_STREAM_ECOLOGY, x, y, "[layer_namespace]_flora_dir", 4)) + 1]

/datum/map_generator/rimstation_colony/proc/spawn_fauna(turf/target, x, y, layer_namespace)
	var/selector = generation_context.coordinate_roll(PLANET_STREAM_ECOLOGY, x, y, "[layer_namespace]_fauna_type", 15)
	var/fauna_type
	switch(selector)
		if(0 to 4)
			fauna_type = /mob/living/basic/rabbit
		if(5 to 8)
			fauna_type = /mob/living/basic/chicken
		if(9 to 11)
			fauna_type = /mob/living/basic/deer
		if(12 to 13)
			fauna_type = /mob/living/basic/goat
		else
			fauna_type = /mob/living/basic/cow
	var/mob/living/spawned = new fauna_type(target)
	spawned.dir = GLOB.cardinals[(generation_context.coordinate_roll(PLANET_STREAM_ECOLOGY, x, y, "[layer_namespace]_fauna_dir", 4)) + 1]


/// Convenience wrapper used by deterministic previews and unit tests.
/datum/colony_planet_generator
	var/datum/planet_definition/planet
	var/datum/map_generator/rimstation_colony/surface_generator

/datum/colony_planet_generator/New(datum/planet_definition/planet)
	. = ..()
	src.planet = planet
	surface_generator = new(planet)

/datum/colony_planet_generator/Destroy(force)
	QDEL_NULL(surface_generator)
	planet = null
	return ..()

/datum/colony_planet_generator/proc/terrain_fingerprint(sample_count = 64, cell_identity)
	if(!planet)
		return null
	var/datum/rimstation_colony_generation_context/context = surface_generator.create_generation_context(1, 1, 96, 96, 2, cell_identity)
	if(!context.build_plan())
		qdel(context)
		return null
	var/fingerprint = context.fingerprint(sample_count)
	qdel(context)
	return fingerprint

#undef RIMSTATION_CAVE_GROWTH_PASSES
#undef RIMSTATION_CAVE_GROWTH_THRESHOLD
#undef RIMSTATION_CLIMATE_ZOOM
#undef RIMSTATION_ECOLOGY_ZOOM
#undef RIMSTATION_ELEVATION_ZOOM
#undef RIMSTATION_GENERATION_ROLL_MAX
#undef RIMSTATION_MOUNTAIN_THRESHOLD
#undef RIMSTATION_RAID_MARKERS_PER_EDGE
#undef RIMSTATION_RAID_MARKER_MIN_SPACING
#undef RIMSTATION_RIDGE_ZOOM
#undef RIMSTATION_RIVER_HALF_WIDTH
#undef RIMSTATION_RIVER_POOL_CHANCE
