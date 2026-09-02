/**
 * Shared scaffolding for region tests.
 *
 * Every test builds its own region from a fixed planet, because the point of the region is that it is derived
 * rather than stored - two builds from the same inputs have to agree, and a test that reused one region could
 * not tell that apart from a region that simply never changes.
 */
/datum/unit_test/rimstation_overworld_region
	abstract_type = /datum/unit_test/rimstation_overworld_region

/// A planet that does not depend on any campaign existing.
/datum/unit_test/rimstation_overworld_region/proc/test_planet(seed = "overworld-test-seed")
	RETURN_TYPE(/datum/planet_definition)
	var/datum/planet_definition/planet = new(seed, "overworld-test-planet")
	allocated += planet
	return planet

/// Builds a region and keeps it alive for the test.
/datum/unit_test/rimstation_overworld_region/proc/build(datum/planet_definition/planet, extent = OVERWORLD_EXTENT_STANDARD, roughness = OVERWORLD_ROUGHNESS_VARIED, abundance = OVERWORLD_ABUNDANCE_NORMAL)
	RETURN_TYPE(/datum/overworld_region)
	var/datum/overworld_region/region = new(planet, list(
		"extent" = extent,
		"roughness" = roughness,
		"abundance" = abundance,
	))
	allocated += region
	return region


/**
 * The field is the right shape, whatever size it is.
 *
 * A hex field of radius r holds exactly 1 + 3r(r + 1) cells. Getting this wrong produces a region that looks
 * plausible and is quietly the wrong size, which every distance and travel time downstream then inherits.
 */
/datum/unit_test/rimstation_overworld_region/shape

/datum/unit_test/rimstation_overworld_region/shape/Run()
	var/datum/planet_definition/planet = test_planet()
	var/list/radii = OVERWORLD_EXTENT_RADII

	for(var/extent in OVERWORLD_EXTENTS)
		var/datum/overworld_region/region = build(planet, extent)
		var/radius = radii[extent]
		var/expected = 1 + 3 * radius * (radius + 1)

		TEST_ASSERT_EQUAL(length(region.cells), expected, "The [extent] region holds the wrong number of cells for radius [radius].")
		TEST_ASSERT_EQUAL(region.radius, radius, "The [extent] region reported the wrong radius.")

		// Every cell is inside the radius, and no coordinate appears twice.
		var/list/seen = list()
		for(var/cell_id in region.cells)
			var/datum/overworld_cell/cell = region.cells[cell_id]
			TEST_ASSERT(!seen[cell_id], "The [extent] region contains cell '[cell_id]' twice.")
			seen[cell_id] = TRUE
			TEST_ASSERT(overworld_axial_distance(0, 0, cell.q, cell.r) <= radius, "Cell '[cell_id]' lies outside the [extent] region's radius.")
			TEST_ASSERT_EQUAL(cell_id, "[cell.q],[cell.r]", "Cell '[cell_id]' does not use its own coordinates as its id.")

	// The colony is the middle of its own map.
	var/datum/overworld_region/standard = build(planet)
	var/datum/overworld_cell/home = standard.get_cell(0, 0)
	TEST_ASSERT_NOTNULL(home, "The region has no cell at the origin, so the colony has nowhere to be.")
	TEST_ASSERT(home.topology != OVERWORLD_TOPOLOGY_IMPASSABLE, "The colony's own cell is impassable, so nobody could ever leave.")


/**
 * The same inputs build the same region, and different inputs build a different one.
 *
 * This is the whole reason the region is not saved. If regeneration could drift, every discovered cell and
 * resolved site recorded against it would slowly start describing somewhere else.
 */
/datum/unit_test/rimstation_overworld_region/is_deterministic

/datum/unit_test/rimstation_overworld_region/is_deterministic/Run()
	var/datum/planet_definition/planet = test_planet()

	var/datum/overworld_region/first = build(planet)
	var/datum/overworld_region/second = build(planet)
	TEST_ASSERT_EQUAL(first.fingerprint, second.fingerprint, "Building the same region twice produced two different worlds.")

	// Every option has to be part of the identity, or two campaigns would share a fingerprint while looking
	// nothing alike.
	TEST_ASSERT(build(planet, OVERWORLD_EXTENT_COMPACT).fingerprint != first.fingerprint, "Changing the region's extent did not change it.")
	TEST_ASSERT(build(planet, OVERWORLD_EXTENT_STANDARD, OVERWORLD_ROUGHNESS_RUGGED).fingerprint != first.fingerprint, "Changing the terrain roughness did not change the region.")
	TEST_ASSERT(build(planet, OVERWORLD_EXTENT_STANDARD, OVERWORLD_ROUGHNESS_VARIED, OVERWORLD_ABUNDANCE_RICH).fingerprint != first.fingerprint, "Changing resource abundance did not change the region.")

	// A different planet is a different place.
	var/datum/planet_definition/elsewhere = test_planet("a-different-world")
	TEST_ASSERT(build(elsewhere).fingerprint != first.fingerprint, "Two different planets generated the same region.")

	// Generating a region must not touch the planet record it was derived from.
	var/list/before = planet.serialize()
	build(planet)
	TEST_ASSERT_EQUAL(json_encode(planet.serialize()), json_encode(before), "Generating a region modified the planet it was generated from.")


/**
 * Sites are placed where they were promised, in numbers that were promised.
 *
 * Counts are exact rather than probable because the campaign creation screen tells the player what they are
 * choosing. "Rich" that sometimes produces fewer deposits than "normal" is a lie told at creation time.
 */
/datum/unit_test/rimstation_overworld_region/site_placement

/datum/unit_test/rimstation_overworld_region/site_placement/Run()
	var/datum/planet_definition/planet = test_planet()
	var/list/resource_counts = OVERWORLD_RESOURCE_SITE_COUNTS
	var/list/ruin_counts = OVERWORLD_RUIN_SITE_COUNTS

	for(var/extent in OVERWORLD_EXTENTS)
		for(var/abundance in OVERWORLD_ABUNDANCE_OPTIONS)
			var/datum/overworld_region/region = build(planet, extent, OVERWORLD_ROUGHNESS_VARIED, abundance)
			var/list/by_extent = resource_counts[extent]

			TEST_ASSERT_EQUAL(length(region.sites_of_kind(OVERWORLD_SITE_RESOURCE)), by_extent[abundance], "A [extent]/[abundance] region has the wrong number of resource sites.")
			TEST_ASSERT_EQUAL(length(region.sites_of_kind(OVERWORLD_SITE_RUIN)), ruin_counts[extent], "A [extent] region has the wrong number of ruins.")

	// Site ids identify a site, not a place - a relocated site keeps its identity.
	var/datum/overworld_region/region = build(planet)
	var/list/seen_ids = list()
	for(var/site_id in region.sites)
		var/datum/overworld_site/site = region.sites[site_id]
		TEST_ASSERT(!seen_ids[site_id], "Two sites share the id '[site_id]'.")
		seen_ids[site_id] = TRUE
		TEST_ASSERT_EQUAL(site_id, "[site.kind]:[site.rank]", "Site '[site_id]' is not identified by its kind and rank.")
		TEST_ASSERT_NOTNULL(region.get_cell(site.q, site.r), "Site '[site_id]' sits on a cell that does not exist.")

	// Nothing worth travelling to is on a tile nobody can reach.
	for(var/site_id in region.sites)
		var/datum/overworld_site/site = region.sites[site_id]
		var/datum/overworld_cell/standing_on = region.get_cell(site.q, site.r)
		TEST_ASSERT(standing_on.topology != OVERWORLD_TOPOLOGY_IMPASSABLE, "Site '[site_id]' was placed on impassable ground.")


/**
 * Everything the colony needs is somewhere it can actually walk to.
 *
 * Terrain is generated before sites are placed, so a region can legitimately produce a pocket of ground cut
 * off by impassable cells. A site stranded in one is content the player is told about and can never reach.
 */
/datum/unit_test/rimstation_overworld_region/reachability

/datum/unit_test/rimstation_overworld_region/reachability/Run()
	var/datum/planet_definition/planet = test_planet()

	// Rugged is the hardest case: a tenth of the map is impassable.
	for(var/extent in OVERWORLD_EXTENTS)
		var/datum/overworld_region/region = build(planet, extent, OVERWORLD_ROUGHNESS_RUGGED, OVERWORLD_ABUNDANCE_RICH)
		var/list/reachable = region.reachable_cell_ids()
		TEST_ASSERT(length(reachable), "A [extent] region had nothing reachable from the colony at all.")

		for(var/site_id in region.sites)
			var/datum/overworld_site/site = region.sites[site_id]
			TEST_ASSERT(reachable["[site.q],[site.r]"], "Site '[site_id]' cannot be reached from the colony in a [extent] rugged region.")


/**
 * A new colony can see something worth doing, and something worth going to find.
 *
 * The opening has to answer "what now?" without exploration, and still leave a reason to explore. One deposit
 * inside the initial reveal does the first; one ruin four to six cells out does the second.
 */
/datum/unit_test/rimstation_overworld_region/starter_sites

/datum/unit_test/rimstation_overworld_region/starter_sites/Run()
	var/datum/planet_definition/planet = test_planet()

	for(var/extent in OVERWORLD_EXTENTS)
		var/datum/overworld_region/region = build(planet, extent)

		var/found_near_resource = FALSE
		for(var/datum/overworld_site/site as anything in region.sites_of_kind(OVERWORLD_SITE_RESOURCE))
			if(overworld_axial_distance(0, 0, site.q, site.r) <= OVERWORLD_INITIAL_REVEAL_RADIUS)
				found_near_resource = TRUE
				break
		TEST_ASSERT(found_near_resource, "A [extent] colony can see no resource site at all when it starts, so the map opens with nothing to do.")

		var/found_starter_ruin = FALSE
		for(var/datum/overworld_site/site as anything in region.sites_of_kind(OVERWORLD_SITE_RUIN))
			var/distance = overworld_axial_distance(0, 0, site.q, site.r)
			if(distance >= OVERWORLD_STARTER_RUIN_MIN_DISTANCE && distance <= OVERWORLD_STARTER_RUIN_MAX_DISTANCE)
				found_starter_ruin = TRUE
				break
		TEST_ASSERT(found_starter_ruin, "A [extent] region has no ruin at travelling distance, so there is nothing to set out for.")


/// Yields stay inside the band the creation screen promised, whatever the seed.
/datum/unit_test/rimstation_overworld_region/resource_yields

/datum/unit_test/rimstation_overworld_region/resource_yields/Run()
	var/datum/planet_definition/planet = test_planet()
	var/list/bands = OVERWORLD_RESOURCE_YIELDS

	for(var/abundance in OVERWORLD_ABUNDANCE_OPTIONS)
		var/list/band = bands[abundance]
		var/datum/overworld_region/region = build(planet, OVERWORLD_EXTENT_EXPANSIVE, OVERWORLD_ROUGHNESS_VARIED, abundance)

		for(var/datum/overworld_site/site as anything in region.sites_of_kind(OVERWORLD_SITE_RESOURCE))
			TEST_ASSERT(site.yield >= band[1], "A [abundance] deposit yields [site.yield], below the promised floor of [band[1]].")
			TEST_ASSERT(site.yield <= band[2], "A [abundance] deposit yields [site.yield], above the promised ceiling of [band[2]].")


/// Options come from a player, so anything outside the allowlist is refused rather than generated.
/datum/unit_test/rimstation_overworld_region/rejects_unknown_options

/datum/unit_test/rimstation_overworld_region/rejects_unknown_options/Run()
	TEST_ASSERT(!is_valid_overworld_options(null), "A null option set was accepted.")
	TEST_ASSERT(!is_valid_overworld_options(list()), "An empty option set was accepted.")
	TEST_ASSERT(!is_valid_overworld_options(list("extent" = "enormous", "roughness" = OVERWORLD_ROUGHNESS_VARIED, "abundance" = OVERWORLD_ABUNDANCE_NORMAL)), "An unknown extent was accepted.")
	TEST_ASSERT(!is_valid_overworld_options(list("extent" = OVERWORLD_EXTENT_STANDARD, "roughness" = "flat", "abundance" = OVERWORLD_ABUNDANCE_NORMAL)), "An unknown roughness was accepted.")
	TEST_ASSERT(!is_valid_overworld_options(list("extent" = OVERWORLD_EXTENT_STANDARD, "roughness" = OVERWORLD_ROUGHNESS_VARIED, "abundance" = "infinite")), "An unknown abundance was accepted.")

	TEST_ASSERT(is_valid_overworld_options(list("extent" = OVERWORLD_EXTENT_STANDARD, "roughness" = OVERWORLD_ROUGHNESS_VARIED, "abundance" = OVERWORLD_ABUNDANCE_NORMAL)), "A valid option set was refused.")


/// Hex distance is the measure everything else is built on, so it is checked directly rather than trusted.
/datum/unit_test/rimstation_overworld_axial_distance

/datum/unit_test/rimstation_overworld_axial_distance/Run()
	TEST_ASSERT_EQUAL(overworld_axial_distance(0, 0, 0, 0), 0, "A cell is not at distance zero from itself.")

	// Each of the six neighbours of the origin is one step away.
	var/list/neighbours = OVERWORLD_AXIAL_DIRECTIONS
	for(var/list/step as anything in neighbours)
		TEST_ASSERT_EQUAL(overworld_axial_distance(0, 0, step[1], step[2]), 1, "The neighbour at [step[1]],[step[2]] is not one step from the origin.")

	// Straight lines and diagonals, the case a naive implementation gets wrong.
	TEST_ASSERT_EQUAL(overworld_axial_distance(0, 0, 3, 0), 3, "Three cells along one axis is not distance three.")
	TEST_ASSERT_EQUAL(overworld_axial_distance(0, 0, 0, 3), 3, "Three cells along the other axis is not distance three.")
	TEST_ASSERT_EQUAL(overworld_axial_distance(0, 0, 3, -3), 3, "Three cells along the third axis is not distance three.")
	TEST_ASSERT_EQUAL(overworld_axial_distance(0, 0, 2, 2), 4, "A two-and-two step is not distance four.")
	TEST_ASSERT_EQUAL(overworld_axial_distance(-2, 5, 1, -1), 6, "Distance between two arbitrary cells is wrong.")


/**
 * Every combination of the three creation options builds a region somebody can actually play.
 *
 * Twenty-seven worlds, and a player can pick any of them at creation. Each has to be bounded, connected enough
 * to leave the colony, and stable - a combination that generated an unreachable starter deposit, or a different
 * region on each rebuild, would be a campaign that could not be played and would not say so until somebody had
 * already committed to it.
 */
/datum/unit_test/rimstation_overworld_region/every_option_combination_is_playable

/datum/unit_test/rimstation_overworld_region/every_option_combination_is_playable/Run()
	var/datum/planet_definition/planet = test_planet("every-combination-seed")

	// Regions are destroyed as they are finished with rather than collected in `allocated`.
	//
	// Twenty-seven worlds built twice is fifty-four regions of up to four hundred cells each, and every cell is
	// a datum. Holding them all and dropping eighteen thousand at once floods the garbage queue - which does not
	// break this test, it breaks whatever unrelated types are queued behind it and get reported as hard deletes.
	// Two regions alive at a time keeps the churn flat.

	var/list/extents = OVERWORLD_EXTENTS
	var/list/roughnesses = OVERWORLD_ROUGHNESS_OPTIONS
	var/list/abundances = OVERWORLD_ABUNDANCE_OPTIONS
	var/list/radii = OVERWORLD_EXTENT_RADII

	var/combinations = 0
	for(var/extent in extents)
		for(var/roughness in roughnesses)
			for(var/abundance in abundances)
				combinations++
				var/label = "[extent]/[roughness]/[abundance]"
				var/datum/overworld_region/region = new(planet, list(
					"extent" = extent,
					"roughness" = roughness,
					"abundance" = abundance,
				))
				// Read off before the region is destroyed, so the comparison below outlives it.
				var/region_fingerprint = region.fingerprint

				// The right shape, and no more cells than a hex field of that radius can hold.
				var/expected_radius = radii[extent]
				TEST_ASSERT_EQUAL(region.radius, expected_radius, "[label] built at the wrong radius.")
				TEST_ASSERT_EQUAL(length(region.cells), 1 + (3 * expected_radius * (expected_radius + 1)), "[label] did not build a whole hex field.")

				// Somewhere to go, and somewhere to go that can be reached on foot.
				var/list/reachable = region.reachable_cell_ids()
				TEST_ASSERT(length(reachable) > 1, "[label] walled the colony in; nobody could leave.")

				var/list/deposits = region.sites_of_kind(OVERWORLD_SITE_RESOURCE)
				TEST_ASSERT(length(deposits), "[label] generated no deposits at all.")

				var/starter_found = FALSE
				for(var/datum/overworld_site/site as anything in deposits)
					if(reachable["[site.q],[site.r]"] && overworld_axial_distance(0, 0, site.q, site.r) <= OVERWORLD_INITIAL_REVEAL_RADIUS)
						starter_found = TRUE
						break
				TEST_ASSERT(starter_found, "[label] left the colony with no deposit it could see or reach at the start.")

				// Every site stands somewhere real and somewhere walkable.
				for(var/site_id in region.sites)
					var/datum/overworld_site/site = region.sites[site_id]
					var/cell_id = "[site.q],[site.r]"
					var/datum/overworld_cell/cell = region.cells[cell_id]
					TEST_ASSERT_NOTNULL(cell, "[label] put site '[site_id]' outside the region.")
					TEST_ASSERT(cell.is_passable(), "[label] put site '[site_id]' on ground nobody can cross.")
					TEST_ASSERT(reachable[cell_id], "[label] put site '[site_id]' somewhere unreachable from the colony.")

				// The same inputs build the same world. Discovery and site records are keyed on these ids, so
				// drift here would slowly turn a saved campaign into a description of somewhere else.
				var/datum/overworld_region/rebuilt = new(planet, list(
					"extent" = extent,
					"roughness" = roughness,
					"abundance" = abundance,
				))
				var/rebuilt_fingerprint = rebuilt.fingerprint
				qdel(rebuilt)
				qdel(region)
				TEST_ASSERT_EQUAL(rebuilt_fingerprint, region_fingerprint, "[label] rebuilt into a different region.")

	TEST_ASSERT_EQUAL(combinations, 27, "The option table no longer offers twenty-seven worlds; this test is out of date.")
