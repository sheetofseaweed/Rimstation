/// Generator version 2: land that comes in regions, and campaigns that keep the generator they began with.
/datum/unit_test/rimstation_overworld_worldgen
	abstract_type = /datum/unit_test/rimstation_overworld_worldgen

/// A region from its own planet, kept alive for the test.
/datum/unit_test/rimstation_overworld_worldgen/proc/build(seed = "worldgen-test-seed", roughness = OVERWORLD_ROUGHNESS_VARIED, extent = OVERWORLD_EXTENT_STANDARD, version = OVERWORLD_GENERATION_VERSION)
	RETURN_TYPE(/datum/overworld_region)
	var/datum/planet_definition/planet = new(seed, "worldgen-test-planet")
	allocated += planet
	var/datum/overworld_region/region = new(planet, list(
		"extent" = extent,
		"roughness" = roughness,
		"abundance" = OVERWORLD_ABUNDANCE_NORMAL,
	), version)
	allocated += region
	return region

/// Share of neighbouring land cells with the same terrain. Independent rolls score near one in nine.
/datum/unit_test/rimstation_overworld_worldgen/proc/terrain_agreement(datum/overworld_region/region)
	var/pairs = 0
	var/same = 0
	var/list/directions = OVERWORLD_AXIAL_DIRECTIONS
	for(var/cell_id in region.cells)
		var/datum/overworld_cell/cell = region.cells[cell_id]
		if(cell.terrain == OVERWORLD_TERRAIN_WATER)
			continue
		for(var/list/step as anything in directions)
			var/datum/overworld_cell/neighbour = region.get_cell(cell.q + step[1], cell.r + step[2])
			if(!neighbour || neighbour.terrain == OVERWORLD_TERRAIN_WATER)
				continue
			pairs++
			if(neighbour.terrain == cell.terrain)
				same++
	return pairs ? same / pairs : 0


/// Neighbouring cells share a biome far more often than with one roll per hex.
/datum/unit_test/rimstation_overworld_worldgen/land_comes_in_regions

/datum/unit_test/rimstation_overworld_worldgen/land_comes_in_regions/Run()
	for(var/seed in list("worldgen-test-seed", "worldgen-second-seed"))
		var/old_agreement = terrain_agreement(build(seed, version = 1))
		var/new_agreement = terrain_agreement(build(seed))
		TEST_ASSERT(new_agreement > old_agreement + 0.2, "On '[seed]' neighbours share a biome [round(new_agreement * 100)]% of the time, against [round(old_agreement * 100)]% with one roll per hex.")


/// The colony starts in open country, whatever the planet and the roughness.
/datum/unit_test/rimstation_overworld_worldgen/home_valley_is_open

/datum/unit_test/rimstation_overworld_worldgen/home_valley_is_open/Run()
	for(var/extent in OVERWORLD_EXTENTS)
		for(var/seed in list("worldgen-test-seed", "worldgen-second-seed", "worldgen-third-seed"))
			var/datum/overworld_region/region = build(seed, OVERWORLD_ROUGHNESS_RUGGED, extent)
			var/datum/overworld_cell/home = region.get_cell(0, 0)
			TEST_ASSERT_EQUAL(home.topology, OVERWORLD_TOPOLOGY_EASY, "The colony's own cell is not open ground on '[seed]' ([extent]).")
			TEST_ASSERT_EQUAL(home.danger, 0, "The colony's own cell is dangerous on '[seed]' ([extent]).")
			for(var/cell_id in region.cells)
				var/datum/overworld_cell/cell = region.cells[cell_id]
				if(overworld_axial_distance(0, 0, cell.q, cell.r) > OVERWORLD_HOME_VALLEY_RADIUS)
					continue
				TEST_ASSERT(cell.terrain != OVERWORLD_TERRAIN_WATER, "Cell [cell_id] beside the colony is water on '[seed]' ([extent]).")
				TEST_ASSERT(cell.topology == OVERWORLD_TOPOLOGY_EASY || cell.topology == OVERWORLD_TOPOLOGY_NORMAL, "Cell [cell_id] beside the colony is [cell.topology] on '[seed]' ([extent]).")


/// Water fills the low ground, cannot be crossed, and sits below every land cell.
/datum/unit_test/rimstation_overworld_worldgen/water_is_low_and_impassable

/datum/unit_test/rimstation_overworld_worldgen/water_is_low_and_impassable/Run()
	var/datum/overworld_region/region = build()
	var/water = 0
	for(var/cell_id in region.cells)
		var/datum/overworld_cell/cell = region.cells[cell_id]
		if(cell.terrain != OVERWORLD_TERRAIN_WATER)
			TEST_ASSERT(cell.height > OVERWORLD_WATER_HEIGHT_MAX, "Land cell [cell_id] stands no higher than water, at [cell.height].")
			continue
		water++
		TEST_ASSERT(!cell.is_passable(), "Water at [cell_id] can be walked across.")
		TEST_ASSERT_EQUAL(cell.danger, 0, "Water at [cell_id] carries a danger rating nobody can meet.")
		TEST_ASSERT(cell.height <= OVERWORLD_WATER_HEIGHT_MAX, "Water at [cell_id] stands at [cell.height], above the land.")

	TEST_ASSERT(water >= 1, "A standard region on an ordinary planet has no water at all.")
	TEST_ASSERT(water <= length(region.cells) * OVERWORLD_WATER_PERCENT_MAX / 100, "[water] of [length(region.cells)] cells are water, more than the wettest planet allows.")


/// Peaks stand in ranges with foothills, not one at a time on the plain.
/datum/unit_test/rimstation_overworld_worldgen/peaks_form_ranges

/datum/unit_test/rimstation_overworld_worldgen/peaks_form_ranges/Run()
	var/datum/overworld_region/region = build(roughness = OVERWORLD_ROUGHNESS_RUGGED, extent = OVERWORLD_EXTENT_EXPANSIVE)
	var/peaks = 0
	var/in_ranges = 0
	for(var/cell_id in region.cells)
		var/datum/overworld_cell/cell = region.cells[cell_id]
		if(cell.is_passable() || cell.terrain == OVERWORLD_TERRAIN_WATER)
			continue
		peaks++
		if(region.has_neighbour_topology(cell, OVERWORLD_TOPOLOGY_IMPASSABLE) || region.has_neighbour_topology(cell, OVERWORLD_TOPOLOGY_DIFFICULT))
			in_ranges++

	TEST_ASSERT(peaks >= 3, "A rugged expansive region has only [peaks] peaks.")
	TEST_ASSERT(in_ranges * 4 >= peaks * 3, "Only [in_ranges] of [peaks] peaks have high ground beside them.")


/// Rougher settings give more hard going and more peaks.
/datum/unit_test/rimstation_overworld_worldgen/roughness_changes_the_going

/datum/unit_test/rimstation_overworld_worldgen/roughness_changes_the_going/Run()
	var/list/hard_counts = list()
	for(var/roughness in OVERWORLD_ROUGHNESS_OPTIONS)
		var/datum/overworld_region/region = build(roughness = roughness)
		var/hard = 0
		for(var/cell_id in region.cells)
			var/datum/overworld_cell/cell = region.cells[cell_id]
			if(cell.terrain != OVERWORLD_TERRAIN_WATER && (cell.topology == OVERWORLD_TOPOLOGY_DIFFICULT || cell.topology == OVERWORLD_TOPOLOGY_IMPASSABLE))
				hard++
		hard_counts[roughness] = hard

	TEST_ASSERT(hard_counts[OVERWORLD_ROUGHNESS_GENTLE] < hard_counts[OVERWORLD_ROUGHNESS_VARIED], "Gentle ground ([hard_counts[OVERWORLD_ROUGHNESS_GENTLE]] hard cells) is no easier than varied ([hard_counts[OVERWORLD_ROUGHNESS_VARIED]]).")
	TEST_ASSERT(hard_counts[OVERWORLD_ROUGHNESS_VARIED] < hard_counts[OVERWORLD_ROUGHNESS_RUGGED], "Varied ground ([hard_counts[OVERWORLD_ROUGHNESS_VARIED]] hard cells) is no easier than rugged ([hard_counts[OVERWORLD_ROUGHNESS_RUGGED]]).")


/// Ranges never wall land off from the colony. A pass is cut instead; only water can make an island.
/datum/unit_test/rimstation_overworld_worldgen/ranges_leave_a_pass

/datum/unit_test/rimstation_overworld_worldgen/ranges_leave_a_pass/Run()
	for(var/seed in list("worldgen-test-seed", "worldgen-second-seed", "worldgen-third-seed"))
		var/datum/overworld_region/region = build(seed, OVERWORLD_ROUGHNESS_RUGGED, OVERWORLD_EXTENT_EXPANSIVE)
		var/list/reachable = region.reachable_cell_ids()
		var/passable = 0
		for(var/cell_id in region.cells)
			var/datum/overworld_cell/cell = region.cells[cell_id]
			if(cell.is_passable())
				passable++
		TEST_ASSERT(length(reachable) * 10 >= passable * 9, "On '[seed]' only [length(reachable)] of [passable] open cells can be reached from the colony.")


/// The first generator still builds exactly what it always built, for campaigns made with it.
/datum/unit_test/rimstation_overworld_worldgen/version_one_is_unchanged

/datum/unit_test/rimstation_overworld_worldgen/version_one_is_unchanged/Run()
	var/datum/planet_definition/planet = new("worldgen-test-seed", "worldgen-test-planet")
	allocated += planet
	var/list/options = default_overworld_options()
	var/datum/overworld_region/region = new(planet, options, 1)
	allocated += region
	TEST_ASSERT_EQUAL(region.generation_version, 1, "A region asked for with generator 1 was built by generator [region.generation_version].")

	var/list/weights = OVERWORLD_TOPOLOGY_WEIGHTS
	var/list/split = weights[options["roughness"]]
	for(var/cell_id in region.cells)
		var/datum/overworld_cell/cell = region.cells[cell_id]
		TEST_ASSERT(cell.terrain != OVERWORLD_TERRAIN_WATER, "Generator 1 made water at [cell_id], which it never did.")
		TEST_ASSERT_EQUAL(cell.terrain, region.pick_terrain(planet, cell.q, cell.r), "Generator 1 gave [cell_id] a terrain its own rule does not give.")
		if(cell.is_origin())
			continue
		var/expected = region.pick_topology(region.hash_percentile(region.cell_hash(planet, PLANET_STREAM_TERRAIN, cell.q, cell.r)), split)
		TEST_ASSERT_EQUAL(cell.topology, expected, "Generator 1 gave [cell_id] a topology its own rule does not give.")

	var/datum/overworld_region/newer = new(planet, options)
	allocated += newer
	TEST_ASSERT(newer.fingerprint != region.fingerprint, "Generators 1 and 2 built the same world.")


/// A campaign's world is rebuilt by the generator it was made with, until an admin moves it on.
/datum/unit_test/rimstation_colonist_chapter/overworld_keeps_its_generator

/datum/unit_test/rimstation_colonist_chapter/overworld_keeps_its_generator/Run()
	begin_test_campaign()
	SScampaign.overworld = new(default_overworld_options())
	SScampaign.ledger = new
	var/datum/overworld_state/region_state = SScampaign.overworld
	TEST_ASSERT_EQUAL(region_state.generation_version, OVERWORLD_GENERATION_VERSION, "A new campaign does not use the newest generator.")
	TEST_ASSERT_EQUAL(get_active_overworld_region().generation_version, OVERWORLD_GENERATION_VERSION, "A new campaign's region was built by an older generator.")

	// An older campaign, as it comes off disk.
	var/list/record = region_state.serialize()
	record["generation_version"] = 1
	TEST_ASSERT(region_state.deserialize(record), "A campaign made with generator 1 could not be read.")
	TEST_ASSERT_EQUAL(get_active_overworld_region().generation_version, 1, "A campaign made with generator 1 had its world rebuilt by a newer one.")

	record["generation_version"] = 0
	TEST_ASSERT(!region_state.deserialize(record), "A record naming generator 0, which never existed, was accepted.")

	// Moved on by an admin: the old map's records go with it.
	region_state.discover_cell(get_active_overworld_region(), "1,0")
	TEST_ASSERT_NULL(region_state.adopt_newest_generator(), "An idle campaign could not be moved to the newest generator.")
	TEST_ASSERT_EQUAL(region_state.generation_version, OVERWORLD_GENERATION_VERSION, "Moving to the newest generator did not change the generator.")
	TEST_ASSERT_EQUAL(length(region_state.discovered_cells), 0, "Discoveries of the old map survived the move to a new one.")
	TEST_ASSERT_EQUAL(get_active_overworld_region().generation_version, OVERWORLD_GENERATION_VERSION, "The region was not rebuilt after the move.")
	TEST_ASSERT_NOTNULL(region_state.adopt_newest_generator(), "A campaign already on the newest generator was moved again.")

	// Not while somebody is out there on the old map.
	region_state.generation_version = 1
	var/datum/overworld_party/party = SScampaign.form_party()
	party.set_state(OVERWORLD_PARTY_DEPARTING, "test")
	party.set_state(OVERWORLD_PARTY_OUTBOUND, "test")
	TEST_ASSERT_NOTNULL(region_state.adopt_newest_generator(), "The map was rebuilt under an expedition that is away.")
	TEST_ASSERT_EQUAL(region_state.generation_version, 1, "A refused move changed the generator anyway.")

	// A lost generation starts a new world, on the newest generator.
	region_state.reset_for_new_generation()
	TEST_ASSERT_EQUAL(region_state.generation_version, OVERWORLD_GENERATION_VERSION, "A new generation's world was not built by the newest generator.")


/// The planet's climate decides the region's: a cold planet is mostly cold country, a temperate one mostly mild.
/datum/unit_test/rimstation_overworld_worldgen/climate_follows_the_planet

/datum/unit_test/rimstation_overworld_worldgen/climate_follows_the_planet/proc/band_counts(temperature)
	RETURN_TYPE(/list)
	var/datum/planet_definition/planet = new("worldgen-test-seed", "worldgen-test-planet")
	allocated += planet
	planet.mean_temperature = temperature
	var/datum/overworld_region/region = new(planet, default_overworld_options())
	allocated += region

	var/list/table = OVERWORLD_TERRAIN_TABLE
	var/list/counts = list(0, 0, 0)
	for(var/cell_id in region.cells)
		var/datum/overworld_cell/cell = region.cells[cell_id]
		for(var/band in 1 to 3)
			if(cell.terrain in table[band])
				counts[band]++
	return counts

/datum/unit_test/rimstation_overworld_worldgen/climate_follows_the_planet/Run()
	var/list/temperate = band_counts(T20C)
	var/list/cold = band_counts(T0C)
	var/list/hot = band_counts(T20C + 25)

	TEST_ASSERT(temperate[2] > temperate[1] && temperate[2] > temperate[3], "A temperate planet's region is not mostly mild: [temperate[1]] cold, [temperate[2]] mild, [temperate[3]] hot.")
	TEST_ASSERT(cold[1] > cold[2] + cold[3], "A 0 C planet's region is not mostly cold: [cold[1]] cold, [cold[2]] mild, [cold[3]] hot.")
	TEST_ASSERT(hot[3] > hot[1] + hot[2], "A 45 C planet's region is not mostly hot: [hot[1]] cold, [hot[2]] mild, [hot[3]] hot.")


/// Every danger rating appears, and the far country is more dangerous than the colony's own.
/datum/unit_test/rimstation_overworld_worldgen/danger_rises_with_distance

/datum/unit_test/rimstation_overworld_worldgen/danger_rises_with_distance/Run()
	var/datum/overworld_region/region = build(extent = OVERWORLD_EXTENT_EXPANSIVE)
	var/list/by_rating = list(0, 0, 0, 0)
	var/near_total = 0
	var/near_count = 0
	var/far_total = 0
	var/far_count = 0
	for(var/cell_id in region.cells)
		var/datum/overworld_cell/cell = region.cells[cell_id]
		if(cell.terrain == OVERWORLD_TERRAIN_WATER)
			continue
		by_rating[cell.danger + 1]++
		var/distance = overworld_axial_distance(0, 0, cell.q, cell.r)
		if(distance <= OVERWORLD_HOME_VALLEY_RADIUS)
			TEST_ASSERT(cell.danger <= 1, "Cell [cell_id] in the colony's valley has danger [cell.danger].")
		if(distance <= region.radius / 2)
			near_total += cell.danger
			near_count++
		else
			far_total += cell.danger
			far_count++

	for(var/rating in 0 to OVERWORLD_MAX_CELL_DANGER)
		TEST_ASSERT(by_rating[rating + 1] > 0, "No land cell has danger [rating]: [by_rating.Join(", ")].")
	TEST_ASSERT(far_total / max(1, far_count) > near_total / max(1, near_count), "The far half of the region is no more dangerous than the near half.")


/// The map sends what the globe draws: the planet, the time of day, and each known hex's height.
/datum/unit_test/rimstation_colonist_chapter/overworld_map_feeds_the_globe

/datum/unit_test/rimstation_colonist_chapter/overworld_map_feeds_the_globe/Run()
	begin_test_campaign()
	SScampaign.overworld = new(default_overworld_options())
	SScampaign.ledger = new
	var/datum/overworld_region/region = get_active_overworld_region()
	SScampaign.overworld.reveal_initial(region)
	var/datum/overworld_map_view/view = get_personal_overworld_map()

	var/list/planet = view.ui_static_data(null)["planet"]
	TEST_ASSERT(islist(planet), "The map sent no planet for the globe to draw.")
	TEST_ASSERT(isnum(planet["seed"]) && planet["seed"] >= 0 && planet["seed"] < 1000000, "The globe's planet seed is [planet["seed"]], outside 0 to 999999.")
	TEST_ASSERT(isnum(planet["temperature_c"]) && isnum(planet["moisture"]), "The globe's planet climate is not numbers.")

	var/datum/planet_definition/other = new("worldgen-other-seed", "worldgen-other-planet")
	allocated += other
	var/datum/overworld_region/elsewhere = new(other, default_overworld_options())
	allocated += elsewhere
	TEST_ASSERT(elsewhere.planet_climate["seed"] != planet["seed"], "Two planets got the same globe.")

	var/list/data = view.ui_data(null)
	var/list/sun = data["sun"]
	TEST_ASSERT(islist(sun), "The map sent no time of day for the globe's sun.")
	TEST_ASSERT(sun["fraction"] >= 0 && sun["fraction"] < 1, "The time of day is [sun["fraction"]], outside one day.")
	TEST_ASSERT(sun["day_length"] > 0, "The day has no length, so the globe's sun could not move.")

	var/list/known = data["known_cells"]
	TEST_ASSERT(length(known), "The map sent no known hexes.")
	for(var/list/cell as anything in known)
		TEST_ASSERT(isnum(cell["height"]) && cell["height"] >= 0 && cell["height"] <= 99, "Hex [cell["id"]] was sent with height [cell["height"]].")
