/**
 * The region of planet the colony can travel across.
 *
 * Derived, never stored. The planet's seeds plus the three campaign creation options are enough to rebuild
 * every cell, every site and every cost identically, so the campaign writes down only what play changed -
 * which cells were discovered, which sites were resolved - and rebuilds the rest on load.
 *
 * That is the whole reason this must be deterministic. Discovery and site state are recorded against cell and
 * site ids; if regeneration could drift, those records would slowly start describing a different place while
 * still looking valid.
 *
 * Coordinates are axial hex `(q, r)`, with the colony at the origin. The third cube axis is always `-q - r`,
 * which is what makes distance cheap to compute and is why it is never stored.
 */

/**
 * Distance in hexes between two axial coordinates.
 *
 * Converted through cube coordinates, where distance is simply the largest absolute axis difference. Doing it
 * directly in axial space is the classic place to get hex maths subtly wrong on diagonals.
 */
/proc/overworld_axial_distance(from_q, from_r, to_q, to_r)
	var/dq = from_q - to_q
	var/dr = from_r - to_r
	var/ds = (-from_q - from_r) - (-to_q - to_r)
	return max(abs(dq), abs(dr), abs(ds))

/**
 * TRUE when `options` is something a region may be generated from.
 *
 * Options reach here from a player at campaign creation, so each is checked against its allowlist rather than
 * trusted. An unknown value must refuse rather than fall back to a default: silently generating a different
 * world than the one somebody chose is worse than refusing to generate one.
 */
/proc/is_valid_overworld_options(list/options)
	if(!islist(options) || !length(options))
		return FALSE

	var/list/extents = OVERWORLD_EXTENTS
	var/list/roughnesses = OVERWORLD_ROUGHNESS_OPTIONS
	var/list/abundances = OVERWORLD_ABUNDANCE_OPTIONS

	if(!(options["extent"] in extents))
		return FALSE
	if(!(options["roughness"] in roughnesses))
		return FALSE
	if(!(options["abundance"] in abundances))
		return FALSE
	return TRUE

/// The options a campaign gets when nobody chose any.
/proc/default_overworld_options()
	RETURN_TYPE(/list)
	return list(
		"extent" = OVERWORLD_EXTENT_STANDARD,
		"roughness" = OVERWORLD_ROUGHNESS_VARIED,
		"abundance" = OVERWORLD_ABUNDANCE_NORMAL,
	)


/// One hex of the region. Plain values only - this is rebuilt, never serialized.
/datum/overworld_cell
	var/q = 0
	var/r = 0
	/// One of OVERWORLD_TOPOLOGY_*, deciding cost and passability.
	var/topology = OVERWORLD_TOPOLOGY_EASY
	/// Strategic terrain label, for the map's palette and pattern. Not a turf type.
	var/terrain = OVERWORLD_TERRAIN_GRASSLAND
	/// 0-3. How dangerous crossing here is, before anything the party is carrying.
	var/danger = 0
	/// 0-99. How high the ground stands, for drawing relief. Water is lowest. Derived, never stored.
	var/height = 0

/datum/overworld_cell/New(q, r)
	. = ..()
	src.q = q
	src.r = r

/// `q,r`. Stable for the life of a generation, and what discovery is recorded against.
/datum/overworld_cell/proc/cell_id()
	return "[q],[r]"

/// Seconds of campaign time to cross, or zero if nothing can.
/datum/overworld_cell/proc/traversal_seconds()
	var/list/costs = OVERWORLD_TOPOLOGY_COSTS
	var/multiplier = costs[topology]
	if(!multiplier)
		return 0
	return OVERWORLD_BASE_TRAVERSAL_SECONDS * multiplier

/datum/overworld_cell/proc/is_passable()
	return topology != OVERWORLD_TOPOLOGY_IMPASSABLE


/// Something on the map worth travelling to.
/datum/overworld_site
	/// One of OVERWORLD_SITE_*.
	var/kind = OVERWORLD_SITE_RESOURCE
	/// Deterministic selection order within its kind. With the kind, this is the site's identity.
	var/rank = 1
	var/q = 0
	var/r = 0
	/// Ledger units this site pays out, for resource sites.
	var/yield = 0

/datum/overworld_site/New(kind, rank, q, r)
	. = ..()
	src.kind = kind
	src.rank = rank
	src.q = q
	src.r = r

/**
 * `<kind>:<rank>`. Deliberately not the coordinate.
 *
 * A site can be relocated during generation when it lands somewhere unreachable, and it is still the same
 * site afterwards - so its identity cannot be where it happens to be standing.
 */
/datum/overworld_site/proc/site_id()
	return "[kind]:[rank]"


/**
 * A generated region: every cell, every site, and a fingerprint identifying the whole thing.
 *
 * Built in one pass in New() rather than lazily, because half a region is not usable for anything and the
 * largest region is under four hundred cells.
 *
 * Nothing in here yields, and that is deliberate - do not add CHECK_TICK back. Generating and routing are pure
 * bounded arithmetic over those four hundred cells, with the hashing done natively, so there is no frame worth
 * saving. The cost of being able to sleep is paid by every caller instead: a region built from a signal handler
 * or from ui_act() would be sleeping somewhere it must not, and deferring the work to dodge that only moves the
 * problem to whatever state has changed by the time it runs.
 */
/datum/overworld_region
	var/generation_version = OVERWORLD_GENERATION_VERSION
	/// The three validated creation options this region was built from.
	var/list/options
	var/radius = 0
	/// Cell id to /datum/overworld_cell.
	var/list/cells
	/// Site id to /datum/overworld_site.
	var/list/sites
	/// Identifies this exact region. Two builds that agree here are the same place.
	var/fingerprint
	/// How many peaks were cut down to open a pass. Version 2 only; for the admin readout.
	var/passes_opened = 0
	/// What the client needs to draw this region's planet: list("seed", "temperature_c", "moisture"). Derived, not stored.
	var/list/planet_climate

/datum/overworld_region/New(datum/planet_definition/planet, list/build_options, version = OVERWORLD_GENERATION_VERSION)
	. = ..()
	cells = list()
	sites = list()
	options = (is_valid_overworld_options(build_options) ? build_options.Copy() : default_overworld_options())
	// A stored campaign names the generator that built its world. Its cell and site ids mean nothing on another.
	if(isnum(version) && version >= OVERWORLD_OLDEST_GENERATION_VERSION && version <= OVERWORLD_GENERATION_VERSION)
		generation_version = version

	var/list/radii = OVERWORLD_EXTENT_RADII
	radius = radii[options["extent"]]

	if(generation_version == 1)
		generate_cells_v1(planet)
	else
		generate_cells_v2(planet)
	generate_sites(planet)
	planet_climate = list(
		"seed" = hex2num(copytext(rustg_hash_string(RUSTG_HASH_SHA256, "globe:[planet?.root_seed]"), 1, 7)) % 1000000,
		"temperature_c" = round((isnum(planet?.mean_temperature) ? planet.mean_temperature : T20C) - T0C, 0.1),
		"moisture" = isnum(planet?.moisture) ? planet.moisture : 50,
	)
	fingerprint = compute_fingerprint()

/datum/overworld_region/Destroy(force)
	QDEL_LIST_ASSOC_VAL(cells)
	QDEL_LIST_ASSOC_VAL(sites)
	cells = null
	sites = null
	options = null
	planet_climate = null
	return ..()

/datum/overworld_cell/proc/is_origin()
	return !q && !r

/// The cell at these coordinates, or null if it is outside the region.
/datum/overworld_region/proc/get_cell(q, r)
	RETURN_TYPE(/datum/overworld_cell)
	return cells["[q],[r]"]

/// Every site of one kind, in rank order.
/datum/overworld_region/proc/sites_of_kind(kind)
	RETURN_TYPE(/list)
	var/list/found = list()
	for(var/site_id in sites)
		var/datum/overworld_site/site = sites[site_id]
		if(site.kind == kind)
			found += site
	return found

/**
 * The hash a cell's values are derived from.
 *
 * The namespace carries the generator version, the options, and the planet's own profile strings, so a future
 * content table can specialise without needing a new seed stream - and so two regions built by different
 * generator versions cannot silently be compared.
 */
/datum/overworld_region/proc/cell_hash(datum/planet_definition/planet, stream, q, r)
	var/stream_seed = planet?.get_stream_seed(stream)
	var/namespace = "overworld:[generation_version]:[options["extent"]]:[options["roughness"]]:[options["abundance"]]:[planet?.resource_profile]:[planet?.ecology_profile]:[planet?.ruin_theme]"
	return copytext(rustg_hash_string(RUSTG_HASH_SHA256, "[namespace]:[stream_seed]:[stream]:[q]:[r]"), 1, OVERWORLD_HASH_LENGTH + 1)

/// A hash reduced to 0-99, so generation rules can be written as percentages.
/datum/overworld_region/proc/hash_percentile(hash)
	return hex2num(hash) % 100

/**
 * Builds every cell in the field, one independent roll per hex. Generator version 1.
 *
 * Kept unchanged for campaigns made with it: their discoveries and sites are recorded against this output.
 * Topology, terrain and danger each come from a different stream.
 */
/datum/overworld_region/proc/generate_cells_v1(datum/planet_definition/planet)
	var/list/weights = OVERWORLD_TOPOLOGY_WEIGHTS
	var/list/split = weights[options["roughness"]]
	var/list/danger_bias = OVERWORLD_ROUGHNESS_DANGER_BIAS
	var/bias = danger_bias[options["roughness"]]

	for(var/q in -radius to radius)
		for(var/r in max(-radius, -q - radius) to min(radius, -q + radius))
			var/datum/overworld_cell/cell = new(q, r)

			// The colony's own ground is always crossable and safe. Everything else is generated.
			if(cell.is_origin())
				cell.topology = OVERWORLD_TOPOLOGY_EASY
				cell.danger = 0
			else
				cell.topology = pick_topology(hash_percentile(cell_hash(planet, PLANET_STREAM_TERRAIN, q, r)), split)
				cell.danger = clamp(round((hash_percentile(cell_hash(planet, PLANET_STREAM_ECOLOGY, q, r)) + bias) / 25), 0, 3)

			cell.terrain = pick_terrain(planet, q, r)
			cell.height = topology_height(cell.topology)
			cells[cell.cell_id()] = cell

/// A stand-in height for a version 1 cell, which has no elevation of its own.
/datum/overworld_region/proc/topology_height(topology)
	switch(topology)
		if(OVERWORLD_TOPOLOGY_NORMAL)
			return 45
		if(OVERWORLD_TOPOLOGY_DIFFICULT)
			return 70
		if(OVERWORLD_TOPOLOGY_IMPASSABLE)
			return 90
	return 25

/// Turns a percentile into a topology using the roughness split, which is ordered easy/normal/difficult/impassable.
/datum/overworld_region/proc/pick_topology(percentile, list/split)
	var/running = split[1]
	if(percentile < running)
		return OVERWORLD_TOPOLOGY_EASY
	running += split[2]
	if(percentile < running)
		return OVERWORLD_TOPOLOGY_NORMAL
	running += split[3]
	if(percentile < running)
		return OVERWORLD_TOPOLOGY_DIFFICULT
	return OVERWORLD_TOPOLOGY_IMPASSABLE

/**
 * Chooses a strategic terrain label from heat and humidity.
 *
 * The planet's own mean temperature and moisture shift both axes, so a cold world reads as cold across its
 * whole region rather than every planet producing the same spread of biomes.
 */
/datum/overworld_region/proc/pick_terrain(datum/planet_definition/planet, q, r)
	var/heat = hash_percentile(cell_hash(planet, PLANET_STREAM_BIOME_HEAT, q, r))
	var/humidity = hash_percentile(cell_hash(planet, PLANET_STREAM_BIOME_HUMIDITY, q, r))

	heat = clamp(heat + round(((planet?.mean_temperature || T20C) - T20C) / 2), 0, 99)
	humidity = clamp(humidity + round(((planet?.moisture || 50) - 50) / 2), 0, 99)

	var/list/table = OVERWORLD_TERRAIN_TABLE
	var/list/row = table[band_index(heat)]
	return row[band_index(humidity)]

/// 1, 2 or 3 for a 0-99 value split at 33 and 67.
/datum/overworld_region/proc/band_index(value)
	if(value < 33)
		return 1
	if(value < 67)
		return 2
	return 3


/**
 * Builds every cell from smooth fields, so the land comes in regions: basins hold water, ridges make
 * ranges, and climate changes slowly across the map. Version 2 of the generator.
 *
 * Each field is ranked across the region before it is used. Ranks give exact shares (the roughness split,
 * the water share), whatever shape the noise happens to have on this planet.
 */
/datum/overworld_region/proc/generate_cells_v2(datum/planet_definition/planet)
	var/elevation_seed = noise_seed(planet, PLANET_STREAM_ELEVATION)
	var/fine_seed = (elevation_seed + 7) % OVERWORLD_NOISE_SEED_MODULUS
	var/ridge_seed = noise_seed(planet, PLANET_STREAM_RIDGES)
	var/heat_seed = noise_seed(planet, PLANET_STREAM_BIOME_HEAT)
	var/humidity_seed = noise_seed(planet, PLANET_STREAM_BIOME_HUMIDITY)
	var/wild_seed = noise_seed(planet, PLANET_STREAM_ECOLOGY)

	var/list/elevation = list()
	var/list/ruggedness = list()
	var/list/heat_raw = list()
	var/list/humidity_raw = list()
	var/list/wild_raw = list()

	for(var/q in -radius to radius)
		for(var/r in max(-radius, -q - radius) to min(radius, -q + radius))
			var/datum/overworld_cell/cell = new(q, r)
			var/cell_id = cell.cell_id()
			cells[cell_id] = cell

			var/x = OVERWORLD_HEX_X(q, r)
			var/y = OVERWORLD_HEX_Y(r)
			elevation[cell_id] = (sample_field(elevation_seed, x, y, OVERWORLD_ELEVATION_ZOOM) * 0.7) + (sample_field(fine_seed, x, y, OVERWORLD_ELEVATION_ZOOM / 2) * 0.3)
			// High along a line rather than at a point, so the peaks form ranges.
			var/ridge = 1 - abs((sample_field(ridge_seed, x, y, OVERWORLD_RIDGE_ZOOM) * 2) - 1)
			ruggedness[cell_id] = ridge * ridge
			heat_raw[cell_id] = sample_field(heat_seed, x, y, OVERWORLD_CLIMATE_ZOOM)
			humidity_raw[cell_id] = sample_field(humidity_seed, x, y, OVERWORLD_CLIMATE_ZOOM)
			wild_raw[cell_id] = sample_field(wild_seed, x, y, OVERWORLD_WILDNESS_ZOOM)

	place_water(planet, elevation)
	place_relief(elevation, ruggedness)
	open_passes()
	place_climate(planet, heat_raw, humidity_raw)
	place_danger(wild_raw)

/// A deterministic noise seed for one planet stream. Numeric, because that is what the noise library reads.
/datum/overworld_region/proc/noise_seed(datum/planet_definition/planet, stream)
	return hex2num(cell_hash(planet, stream, "noise", 0)) % OVERWORLD_NOISE_SEED_MODULUS

/// Smooth noise from 0 to 1 at a point, with features about `zoom` hexes across.
/datum/overworld_region/proc/sample_field(seed, x, y, zoom)
	// The offset keeps samples off the lattice, where this noise is always exactly one half.
	var/value = text2num(rustg_noise_get_at_coordinates("[seed]", "[(x / zoom) + 0.371]", "[(y / zoom) + 0.529]"))
	return isnum(value) ? clamp(value, 0, 1) : 0.5

/**
 * Turns values into ranks from 0 to 99, lowest value first. Ties are broken on cell id.
 *
 * `values` is cell id to number. Only the ids in `only`, if given, are ranked.
 */
/datum/overworld_region/proc/rank_percentiles(list/values, list/only)
	RETURN_TYPE(/list)
	var/list/entries = list()
	for(var/cell_id in values)
		if(only && !only[cell_id])
			continue
		var/padded = num2text(round(clamp(values[cell_id], 0, 1) * 999999), 7)
		while(length(padded) < 6)
			padded = "0[padded]"
		entries += "[padded]|[cell_id]"

	var/list/ranks = list()
	var/count = length(entries)
	var/index = 0
	for(var/entry in sort_list(entries))
		ranks[copytext(entry, findtext(entry, "|") + 1)] = floor(index * 100 / count)
		index++
	return ranks

/// TRUE when this cell belongs to the open ground around the colony.
/datum/overworld_region/proc/in_home_valley(datum/overworld_cell/cell)
	return overworld_axial_distance(0, 0, cell.q, cell.r) <= OVERWORLD_HOME_VALLEY_RADIUS

/// Floods the lowest ground. The share under water follows the planet's moisture.
/datum/overworld_region/proc/place_water(datum/planet_definition/planet, list/elevation)
	var/moisture = clamp(isnum(planet?.moisture) ? planet.moisture : 50, 0, 100)
	var/water_percent = round(OVERWORLD_WATER_PERCENT_MIN + ((moisture / 100) * (OVERWORLD_WATER_PERCENT_MAX - OVERWORLD_WATER_PERCENT_MIN)))

	var/list/candidates = list()
	for(var/cell_id in cells)
		if(!in_home_valley(cells[cell_id]))
			candidates[cell_id] = TRUE

	var/list/ranks = rank_percentiles(elevation, candidates)
	for(var/cell_id in ranks)
		var/datum/overworld_cell/cell = cells[cell_id]
		if(ranks[cell_id] < water_percent)
			cell.terrain = OVERWORLD_TERRAIN_WATER
			cell.topology = OVERWORLD_TOPOLOGY_IMPASSABLE
			cell.height = round(ranks[cell_id] * OVERWORLD_WATER_HEIGHT_MAX / max(1, water_percent))

/**
 * Gives the land its going: peaks, foothills, broken ground and plains.
 *
 * Land is ranked by height and ridge together, then split by the roughness option. The ground near the
 * colony is pressed down, so a colony starts in a valley and not against a cliff.
 */
/datum/overworld_region/proc/place_relief(list/elevation, list/ruggedness)
	var/list/elevation_ranks = rank_percentiles(elevation)
	var/list/score = list()
	for(var/cell_id in cells)
		var/datum/overworld_cell/cell = cells[cell_id]
		if(cell.terrain == OVERWORLD_TERRAIN_WATER)
			continue
		var/distance = overworld_axial_distance(0, 0, cell.q, cell.r)
		var/near_home = max(0, 1 - (distance / (OVERWORLD_HOME_VALLEY_RADIUS + 3)))
		score[cell_id] = clamp((elevation_ranks[cell_id] / 99) * 0.55 + (ruggedness[cell_id] * 0.45) - (near_home * 0.3), 0, 1)

	var/list/weights = OVERWORLD_TOPOLOGY_WEIGHTS
	var/list/split = weights[options["roughness"]]
	var/list/ranks = rank_percentiles(score)
	for(var/cell_id in ranks)
		var/datum/overworld_cell/cell = cells[cell_id]
		// Rank 99 is the highest ground, so the split is read from the top down.
		var/from_top = 99 - ranks[cell_id]
		if(from_top < split[4])
			cell.topology = OVERWORLD_TOPOLOGY_IMPASSABLE
		else if(from_top < split[4] + split[3])
			cell.topology = OVERWORLD_TOPOLOGY_DIFFICULT
		else if(from_top < split[4] + split[3] + split[2])
			cell.topology = OVERWORLD_TOPOLOGY_NORMAL
		else
			cell.topology = OVERWORLD_TOPOLOGY_EASY

		if(in_home_valley(cell) && (cell.topology == OVERWORLD_TOPOLOGY_IMPASSABLE || cell.topology == OVERWORLD_TOPOLOGY_DIFFICULT))
			cell.topology = OVERWORLD_TOPOLOGY_NORMAL
		if(cell.is_origin())
			cell.topology = OVERWORLD_TOPOLOGY_EASY
		cell.height = OVERWORLD_WATER_HEIGHT_MAX + 1 + round(ranks[cell_id] * (98 - OVERWORLD_WATER_HEIGHT_MAX) / 99)

/**
 * Cuts a pass through any range that walls land off from the colony.
 *
 * The cheapest way in is found with a peak costing many ordinary cells, so a pass goes through the
 * thinnest part of the wall. Peaks on it become hard going. Water is never crossed: an island stays one.
 */
/datum/overworld_region/proc/open_passes()
	// The full search below is the costliest step of generation, so it runs only when land is walled off.
	var/list/already = reachable_cell_ids()
	var/walled_off = FALSE
	for(var/cell_id in cells)
		var/datum/overworld_cell/cell = cells[cell_id]
		if(cell.is_passable() && !already[cell_id])
			walled_off = TRUE
			break
	if(!walled_off)
		return

	var/origin_id = OVERWORLD_HOME_CELL
	var/list/best = list()
	var/list/came_from = list()
	var/list/settled = list()
	best[origin_id] = 0

	var/list/directions = OVERWORLD_AXIAL_DIRECTIONS
	while(TRUE)
		var/current_id = null
		var/current_cost = null
		for(var/candidate_id in best)
			if(settled[candidate_id])
				continue
			var/candidate_cost = best[candidate_id]
			if(isnull(current_cost) || candidate_cost < current_cost || (candidate_cost == current_cost && candidate_id < current_id))
				current_id = candidate_id
				current_cost = candidate_cost
		if(isnull(current_id))
			break

		settled[current_id] = TRUE
		var/datum/overworld_cell/current = cells[current_id]
		for(var/list/step as anything in directions)
			var/datum/overworld_cell/neighbour = get_cell(current.q + step[1], current.r + step[2])
			if(!neighbour || neighbour.terrain == OVERWORLD_TERRAIN_WATER)
				continue
			var/neighbour_id = neighbour.cell_id()
			if(settled[neighbour_id])
				continue
			var/through = current_cost + (neighbour.is_passable() ? 1 : OVERWORLD_PASS_PEAK_COST)
			var/known = best[neighbour_id]
			if(isnull(known) || through < known || (through == known && current_id < came_from[neighbour_id]))
				best[neighbour_id] = through
				came_from[neighbour_id] = current_id

	var/list/reachable = reachable_cell_ids()
	for(var/cell_id in sort_list(cells.Copy()))
		var/datum/overworld_cell/cell = cells[cell_id]
		if(reachable[cell_id] || !cell.is_passable() || isnull(best[cell_id]))
			continue
		var/walk_id = cell_id
		while(walk_id && walk_id != origin_id)
			var/datum/overworld_cell/on_path = cells[walk_id]
			if(!on_path.is_passable())
				on_path.topology = OVERWORLD_TOPOLOGY_DIFFICULT
				passes_opened++
			walk_id = came_from[walk_id]
		reachable = reachable_cell_ids()

/**
 * Chooses each land cell's terrain from heat and humidity that change slowly across the map.
 *
 * The south of the region is warmer than the north, high ground is colder, and land near water is wetter.
 * The planet's own temperature and moisture move both axes, as in the first generator.
 */
/datum/overworld_region/proc/place_climate(datum/planet_definition/planet, list/heat_raw, list/humidity_raw)
	var/list/heat_ranks = rank_percentiles(heat_raw)
	var/list/humidity_ranks = rank_percentiles(humidity_raw)
	// A region is small against a planet: it varies around the planet's own climate, it does not span it.
	var/degrees_warmer = (isnum(planet?.mean_temperature) ? planet.mean_temperature : T20C) - T20C
	var/heat_base = 50 + (degrees_warmer * OVERWORLD_HEAT_PER_DEGREE)
	var/humidity_base = 50 + (((isnum(planet?.moisture) ? planet.moisture : 50) - 50) * OVERWORLD_HUMIDITY_PER_MOISTURE)
	var/list/table = OVERWORLD_TERRAIN_TABLE

	for(var/cell_id in cells)
		var/datum/overworld_cell/cell = cells[cell_id]
		if(cell.terrain == OVERWORLD_TERRAIN_WATER)
			continue

		var/heat = heat_base + ((heat_ranks[cell_id] - 50) * OVERWORLD_HEAT_SPREAD) + round(cell.r * OVERWORLD_LATITUDE_HEAT / max(1, radius))
		switch(cell.topology)
			if(OVERWORLD_TOPOLOGY_DIFFICULT)
				heat -= OVERWORLD_HIGHLAND_CHILL
			if(OVERWORLD_TOPOLOGY_IMPASSABLE)
				heat -= OVERWORLD_HIGHLAND_CHILL * 2

		var/humidity = humidity_base + ((humidity_ranks[cell_id] - 50) * OVERWORLD_HUMIDITY_SPREAD)
		var/water_distance = distance_to_water(cell, 2)
		if(water_distance == 1)
			humidity += OVERWORLD_SHORE_HUMIDITY
		else if(water_distance == 2)
			humidity += round(OVERWORLD_SHORE_HUMIDITY / 2)

		var/list/row = table[band_index(clamp(heat, 0, 99))]
		cell.terrain = row[band_index(clamp(humidity, 0, 99))]

/// Hexes from this cell to the nearest water, or 0 if there is none within `limit`.
/datum/overworld_region/proc/distance_to_water(datum/overworld_cell/cell, limit)
	for(var/ring in 1 to limit)
		for(var/dq in -ring to ring)
			for(var/dr in max(-ring, -dq - ring) to min(ring, -dq + ring))
				if(overworld_axial_distance(0, 0, dq, dr) != ring)
					continue
				var/datum/overworld_cell/other = get_cell(cell.q + dq, cell.r + dr)
				if(other?.terrain == OVERWORLD_TERRAIN_WATER)
					return ring
	return 0

/**
 * How dangerous each cell is. Wild country is more dangerous, and so is country far from the colony.
 *
 * The land is ranked by that score and split into quarters, as the first generator's danger was, so all
 * four ratings appear. The roughness option moves the split. The colony's valley is never above 1.
 */
/datum/overworld_region/proc/place_danger(list/wild_raw)
	var/list/wild_ranks = rank_percentiles(wild_raw)
	var/list/danger_bias = OVERWORLD_ROUGHNESS_DANGER_BIAS
	var/bias = danger_bias[options["roughness"]]

	var/list/score = list()
	for(var/cell_id in cells)
		var/datum/overworld_cell/cell = cells[cell_id]
		cell.danger = 0
		if(cell.terrain == OVERWORLD_TERRAIN_WATER || cell.is_origin())
			continue

		var/distance = overworld_axial_distance(0, 0, cell.q, cell.r)
		var/value = wild_ranks[cell_id] + (distance * OVERWORLD_FAR_DANGER / max(1, radius))
		switch(cell.terrain)
			if(OVERWORLD_TERRAIN_FOREST, OVERWORLD_TERRAIN_MARSH, OVERWORLD_TERRAIN_TAIGA)
				value += 10
			if(OVERWORLD_TERRAIN_DESERT, OVERWORLD_TERRAIN_FROZEN_STEPPE)
				value += 5
		if(cell.topology == OVERWORLD_TOPOLOGY_DIFFICULT)
			value += 10
		score[cell_id] = value / 160

	var/list/ranks = rank_percentiles(score)
	for(var/cell_id in ranks)
		var/datum/overworld_cell/cell = cells[cell_id]
		cell.danger = clamp(floor(clamp(ranks[cell_id] + bias, 0, 99) / 25), 0, OVERWORLD_MAX_CELL_DANGER)
		if(in_home_valley(cell))
			cell.danger = min(cell.danger, 1)

/**
 * Places sites, then guarantees the ones a new colony is promised.
 *
 * Cells are ranked by their hash rather than rolled independently, so the counts the creation screen shows are
 * exact rather than expected. Only reachable, passable, non-origin cells are eligible, which is what stops a
 * deposit being generated inside a pocket of rock nobody can walk to.
 */
/datum/overworld_region/proc/generate_sites(datum/planet_definition/planet)
	var/list/reachable = reachable_cell_ids()
	var/list/resource_counts = OVERWORLD_RESOURCE_SITE_COUNTS
	var/list/by_extent = resource_counts[options["extent"]]
	var/list/ruin_counts = OVERWORLD_RUIN_SITE_COUNTS

	place_sites(planet, OVERWORLD_SITE_RESOURCE, PLANET_STREAM_RESOURCES, by_extent[options["abundance"]], reachable)
	place_sites(planet, OVERWORLD_SITE_RUIN, PLANET_STREAM_RUINS, ruin_counts[options["extent"]], reachable)

	guarantee_starter_resource(planet, reachable)
	guarantee_starter_ruin(planet, reachable)

/// Ranks every eligible cell by its stream hash and takes the top `count`.
/datum/overworld_region/proc/place_sites(datum/planet_definition/planet, kind, stream, count, list/reachable)
	if(count <= 0)
		return

	// One sortable string per candidate: score descending, then cell id, so equal scores still have exactly one
	// order. Built this way rather than by sorting an associative list because BYOND's list sorts differ on
	// whether they carry values with keys, and a placement that depended on that would be a generator whose
	// output could change without any rule changing.
	var/list/ranked = list()
	for(var/cell_id in sort_list(cells.Copy()))
		var/datum/overworld_cell/cell = cells[cell_id]
		if(cell.is_origin() || !cell.is_passable() || !reachable[cell_id])
			continue
		var/score = hash_percentile(cell_hash(planet, stream, cell.q, cell.r)) + site_bonus(kind, cell)
		// Inverted and zero padded so a plain descending text sort ranks by score first.
		ranked += "[num2text(999 - score, 3)]:[cell_id]"

	var/placed = 0
	for(var/entry in sortTim(ranked, GLOBAL_PROC_REF(cmp_text_asc)))
		if(placed >= count)
			break
		var/cell_id = copytext(entry, findtext(entry, ":") + 1)
		var/datum/overworld_cell/cell = cells[cell_id]
		if(!cell || cell_has_site(cell))
			continue
		placed++
		var/datum/overworld_site/site = new(kind, placed, cell.q, cell.r)
		if(kind == OVERWORLD_SITE_RESOURCE)
			site.yield = roll_yield(planet, cell)
		sites[site.site_id()] = site

/// Extra placement score from the ground: ore in the hills, ruins on open ground. Zero for version 1.
/datum/overworld_region/proc/site_bonus(kind, datum/overworld_cell/cell)
	if(generation_version == 1)
		return 0
	switch(kind)
		if(OVERWORLD_SITE_RESOURCE)
			if(cell.topology == OVERWORLD_TOPOLOGY_DIFFICULT || has_neighbour_topology(cell, OVERWORLD_TOPOLOGY_IMPASSABLE))
				return 30
		if(OVERWORLD_SITE_RUIN)
			if(cell.topology == OVERWORLD_TOPOLOGY_EASY)
				return 20
	return 0

/// TRUE when a land neighbour of this cell has this topology. Water does not count as a peak.
/datum/overworld_region/proc/has_neighbour_topology(datum/overworld_cell/cell, topology)
	var/list/directions = OVERWORLD_AXIAL_DIRECTIONS
	for(var/list/step as anything in directions)
		var/datum/overworld_cell/neighbour = get_cell(cell.q + step[1], cell.r + step[2])
		if(neighbour && neighbour.topology == topology && neighbour.terrain != OVERWORLD_TERRAIN_WATER)
			return TRUE
	return FALSE

/// TRUE when something already stands on this cell. One site per hex keeps the map readable.
/datum/overworld_region/proc/cell_has_site(datum/overworld_cell/cell)
	for(var/site_id in sites)
		var/datum/overworld_site/site = sites[site_id]
		if(site.q == cell.q && site.r == cell.r)
			return TRUE
	return FALSE

/// A deterministic yield inside the band the chosen abundance promised.
/datum/overworld_region/proc/roll_yield(datum/planet_definition/planet, datum/overworld_cell/cell)
	var/list/bands = OVERWORLD_RESOURCE_YIELDS
	var/list/band = bands[options["abundance"]]
	var/span = band[2] - band[1] + 1
	return band[1] + (hash_percentile(cell_hash(planet, PLANET_STREAM_RESOURCES, cell.q, cell.r)) % span)

/**
 * Makes sure a new colony can see something worth doing.
 *
 * If generation happened to put every deposit out of sight, the nearest one is moved into the initial reveal
 * rather than a new one being invented - the promised count stays exact, and the site keeps its identity.
 */
/datum/overworld_region/proc/guarantee_starter_resource(datum/planet_definition/planet, list/reachable)
	var/list/deposits = sites_of_kind(OVERWORLD_SITE_RESOURCE)
	if(!length(deposits))
		return

	for(var/datum/overworld_site/site as anything in deposits)
		if(overworld_axial_distance(0, 0, site.q, site.r) <= OVERWORLD_INITIAL_REVEAL_RADIUS)
			return

	var/datum/overworld_cell/destination = nearest_free_cell(reachable, 1, OVERWORLD_INITIAL_REVEAL_RADIUS)
	if(!destination)
		return
	relocate_site(deposits[1], destination)

/// The same guarantee for the ruin a colony is meant to set out for.
/datum/overworld_region/proc/guarantee_starter_ruin(datum/planet_definition/planet, list/reachable)
	var/list/ruins = sites_of_kind(OVERWORLD_SITE_RUIN)
	if(!length(ruins))
		return

	for(var/datum/overworld_site/site as anything in ruins)
		var/distance = overworld_axial_distance(0, 0, site.q, site.r)
		if(distance >= OVERWORLD_STARTER_RUIN_MIN_DISTANCE && distance <= OVERWORLD_STARTER_RUIN_MAX_DISTANCE)
			return

	var/datum/overworld_cell/destination = nearest_free_cell(reachable, OVERWORLD_STARTER_RUIN_MIN_DISTANCE, OVERWORLD_STARTER_RUIN_MAX_DISTANCE)
	if(!destination)
		return
	relocate_site(ruins[1], destination)

/// Moves a site without changing what it is. Its id is its kind and rank, so relocation preserves identity.
/datum/overworld_region/proc/relocate_site(datum/overworld_site/site, datum/overworld_cell/destination)
	site.q = destination.q
	site.r = destination.r

/// The first reachable, passable, site-free cell within a distance band. Ordered by id so it is deterministic.
/datum/overworld_region/proc/nearest_free_cell(list/reachable, min_distance, max_distance)
	RETURN_TYPE(/datum/overworld_cell)
	var/list/ordered = sort_list(cells.Copy())
	for(var/cell_id in ordered)
		var/datum/overworld_cell/cell = cells[cell_id]
		if(cell.is_origin() || !cell.is_passable() || !reachable[cell_id])
			continue
		var/distance = overworld_axial_distance(0, 0, cell.q, cell.r)
		if(distance < min_distance || distance > max_distance)
			continue
		if(cell_has_site(cell))
			continue
		return cell
	return null

/**
 * Every cell that can be walked to from the colony, as an assoc set of cell id to TRUE.
 *
 * A flood fill rather than a distance check, because impassable terrain can seal off a pocket of otherwise
 * ordinary ground. This is the same lesson the raid insertion points taught: a coordinate being close is not
 * the same as it being reachable.
 */
/datum/overworld_region/proc/reachable_cell_ids()
	RETURN_TYPE(/list)
	var/list/found = list()
	var/datum/overworld_cell/origin = get_cell(0, 0)
	if(!origin?.is_passable())
		return found

	var/list/directions = OVERWORLD_AXIAL_DIRECTIONS
	var/list/frontier = list(origin)
	found[origin.cell_id()] = TRUE

	var/index = 1
	while(index <= length(frontier))
		var/datum/overworld_cell/current = frontier[index]
		index++
		for(var/list/step as anything in directions)
			var/datum/overworld_cell/neighbour = get_cell(current.q + step[1], current.r + step[2])
			if(!neighbour || !neighbour.is_passable() || found[neighbour.cell_id()])
				continue
			found[neighbour.cell_id()] = TRUE
			frontier += neighbour

	return found

/**
 * What entering this cell costs the planner, in seconds.
 *
 * The fastest route pays only for the ground. The safer route also pays for what lives on it, at a fixed rate
 * per danger pip - that rate is the entire difference between the two answers, and it is deliberately a time
 * price rather than a separate score so the two routes can be compared on one axis.
 */
/datum/overworld_region/proc/entry_cost(datum/overworld_cell/cell, kind)
	if(!cell)
		return 0

	var/cost = cell.traversal_seconds()
	if(kind == OVERWORLD_ROUTE_SAFER)
		cost += cell.danger * OVERWORLD_DANGER_TIME_PENALTY
	return cost

/**
 * The cheapest walk from one cell to another, as cell ids including both ends.
 *
 * Dijkstra rather than a heuristic search: costs vary per cell and the region is small enough that being exact
 * is cheaper than being clever. Returns an empty list when there is no way through, which is a real answer -
 * impassable ground can wall a corner of the region off entirely, and the map has to be able to say so.
 *
 * Ties are broken on cell id so that two servers, or the same server twice, offer the same route for the same
 * question. A route that wandered differently each time it was asked would make the two offers meaningless.
 *
 * `only_within` optionally restricts the walk to a set of cell ids - discovery, in practice. A party cannot
 * plan a path through country nobody has seen.
 */
/datum/overworld_region/proc/plan_route(from_id, to_id, kind = OVERWORLD_ROUTE_FASTEST, list/only_within)
	RETURN_TYPE(/list)
	var/list/empty = list()

	var/datum/overworld_cell/origin = cells[from_id]
	var/datum/overworld_cell/target = cells[to_id]
	if(!origin || !target || !origin.is_passable() || !target.is_passable())
		return empty
	if(length(only_within) && (!only_within[from_id] || !only_within[to_id]))
		return empty
	if(from_id == to_id)
		return list(from_id)

	var/list/best = list()
	var/list/came_from = list()
	var/list/settled = list()
	best[from_id] = 0

	var/list/directions = OVERWORLD_AXIAL_DIRECTIONS
	while(TRUE)
		// Cheapest unsettled cell, with the id breaking ties. Linear scan: a few hundred cells at most, and a
		// heap here would be more code to get wrong than it would ever save.
		var/current_id = null
		var/current_cost = null
		for(var/candidate_id in best)
			if(settled[candidate_id])
				continue
			var/candidate_cost = best[candidate_id]
			if(isnull(current_cost) || candidate_cost < current_cost || (candidate_cost == current_cost && candidate_id < current_id))
				current_id = candidate_id
				current_cost = candidate_cost

		if(isnull(current_id))
			return empty
		if(current_id == to_id)
			break

		settled[current_id] = TRUE
		var/datum/overworld_cell/current = cells[current_id]
		for(var/list/step as anything in directions)
			var/datum/overworld_cell/neighbour = get_cell(current.q + step[1], current.r + step[2])
			if(!neighbour || !neighbour.is_passable())
				continue
			var/neighbour_id = neighbour.cell_id()
			if(settled[neighbour_id])
				continue
			if(length(only_within) && !only_within[neighbour_id])
				continue

			var/through = current_cost + entry_cost(neighbour, kind)
			var/known = best[neighbour_id]
			// The id comparison keeps the recorded parent stable when two approaches cost the same, which is
			// what stops an equal-cost route from being drawn differently on two identical maps.
			if(isnull(known) || through < known || (through == known && current_id < came_from[neighbour_id]))
				best[neighbour_id] = through
				came_from[neighbour_id] = current_id

	var/list/reversed = list(to_id)
	var/walk_id = to_id
	while(walk_id != from_id)
		walk_id = came_from[walk_id]
		if(isnull(walk_id))
			return empty
		reversed += walk_id

	var/list/route = list()
	for(var/index = length(reversed) to 1 step -1)
		route += reversed[index]
	return route

/**
 * TRUE when every step of a route is a real, adjacent, passable move.
 *
 * Routes arrive from the client as a list of ids, so none of this can be taken on trust. Length is bounded
 * against the region rather than left open: a route that doubled back forever would still be adjacent at every
 * step, and would take a caravan a year to walk.
 */
/datum/overworld_region/proc/is_valid_route(list/route, list/only_within)
	if(!islist(route) || length(route) < 1)
		return FALSE
	// Every cell twice over is already far more than any sane path; beyond that it is a denial of service.
	if(length(route) > (radius * 4) + 2)
		return FALSE

	var/list/seen = list()
	var/datum/overworld_cell/previous = null
	for(var/cell_id in route)
		var/datum/overworld_cell/cell = cells[cell_id]
		if(!cell || !cell.is_passable())
			return FALSE
		if(length(only_within) && !only_within[cell_id])
			return FALSE
		// A route that visits the same cell twice is either a mistake or an attempt to inflate the payout for
		// crossings that were never made.
		if(seen[cell_id])
			return FALSE
		seen[cell_id] = TRUE

		if(previous && overworld_axial_distance(previous.q, previous.r, cell.q, cell.r) != 1)
			return FALSE
		previous = cell
	return TRUE

/// How long a route takes, in seconds. The first cell is where the party already is, so it is not paid for.
/datum/overworld_region/proc/route_travel_seconds(list/route)
	var/total = 0
	for(var/index in 2 to length(route))
		var/datum/overworld_cell/cell = cells[route[index]]
		if(cell)
			total += cell.traversal_seconds()
	return total

/// Total danger pips a route walks into, on the same "entered cells only" rule as its travel time.
/datum/overworld_region/proc/route_danger(list/route)
	var/total = 0
	for(var/index in 2 to length(route))
		var/datum/overworld_cell/cell = cells[route[index]]
		if(cell)
			total += cell.danger
	return total

/**
 * A stable identifier for the whole region.
 *
 * Cell ids are sorted before hashing, because BYOND associative lists keep insertion order and two builds that
 * happened to insert in a different sequence would otherwise fingerprint differently while being identical.
 */
/datum/overworld_region/proc/compute_fingerprint()
	var/list/parts = list("[generation_version]:[options["extent"]]:[options["roughness"]]:[options["abundance"]]")

	for(var/cell_id in sort_list(cells.Copy()))
		var/datum/overworld_cell/cell = cells[cell_id]
		parts += "[cell_id]:[cell.topology]:[cell.terrain]:[cell.danger]"

	for(var/site_id in sort_list(sites.Copy()))
		var/datum/overworld_site/site = sites[site_id]
		parts += "[site_id]:[site.q],[site.r]:[site.yield]"

	return rustg_hash_string(RUSTG_HASH_SHA256, parts.Join("|"))
