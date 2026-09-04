#define RIMSTATION_COLONY_CONFIG "rimstation_colony"
#define RIMSTATION_COLONY_MAP "_maps/map_files/rimstation_colony/rimstation_colony.dmm"
/// Matches the generated surface size used by the other planetary maps in this repository.
#define RIMSTATION_COLONY_SIZE 255
/// Rock below, ground to stand on, sky above. Further levels stack in the middle.
#define RIMSTATION_COLONY_MINIMUM_LEVELS 3

/datum/unit_test/rimstation_colony_map_contract
	test_flags = UNIT_TEST_MAP_TEST

/datum/unit_test/rimstation_colony_map_contract/Run()
	var/datum/map_config/map_config = load_map_config(RIMSTATION_COLONY_CONFIG, MAP_DIRECTORY_MAPS)
	allocated += map_config

	TEST_ASSERT(!map_config.defaulted, "Rimstation Colony's map config could not be loaded.")
	TEST_ASSERT_EQUAL(map_config.map_name, "Rimstation Colony", "The development map should keep its stable display name.")
	TEST_ASSERT_EQUAL(map_config.map_path, "map_files/rimstation_colony", "The map should live in its dedicated map directory.")
	TEST_ASSERT_EQUAL(map_config.map_file, "rimstation_colony.dmm", "The config should load the colony seed DMM.")
	TEST_ASSERT(map_config.planetary, "Rimstation Colony should use planetary atmosphere behavior.")
	TEST_ASSERT(!map_config.height_autosetup, "The map's vertical links should be explicit rather than inferred.")
	TEST_ASSERT_EQUAL(map_config.minetype, MINETYPE_NONE, "The underground layer is part of the map and should not load a separate mining level.")
	TEST_ASSERT_EQUAL(map_config.space_ruin_levels, 0, "The colony seed should not add space ruin levels.")
	TEST_ASSERT_EQUAL(map_config.space_empty_levels, 0, "The colony seed should not add empty space levels.")
	TEST_ASSERT_EQUAL(map_config.wilderness_levels, 0, "The colony seed should not add generated wilderness levels.")

	// Levels are checked by role, not by index. The colony may gain layers; what may not change is that the
	// bottom is diggable rock, the top is open air, and the links between them are unbroken.
	var/level_count = length(map_config.traits)
	TEST_ASSERT(level_count >= RIMSTATION_COLONY_MINIMUM_LEVELS, "The colony seed declares [level_count] levels and needs at least [RIMSTATION_COLONY_MINIMUM_LEVELS].")

	// What a colony level may strip down to. Anything else decays into station or space turf when scraped.
	var/list/colony_baseturfs = list(
		"/turf/open/misc/asteroid/rimstation",
		"/turf/open/misc/dirt/planet/rimstation",
		"/turf/open/openspace/rimstation",
	)

	var/list/underground_traits = map_config.traits[1]
	TEST_ASSERT(underground_traits[ZTRAIT_STATION], "The underground should be part of the loaded colony map.")
	TEST_ASSERT(underground_traits[ZTRAIT_MINING], "Only the bottom level should carry the mining-level trait.")
	TEST_ASSERT(underground_traits[ZTRAIT_GRAVITY], "The underground should have standard gravity.")
	TEST_ASSERT(underground_traits[ZTRAIT_UP] && !underground_traits[ZTRAIT_DOWN], "The bottom level should link upward only.")
	TEST_ASSERT_NULL(underground_traits[ZTRAIT_LINKAGE], "The underground should not cross-link at its map edges.")
	TEST_ASSERT_EQUAL(underground_traits[ZTRAIT_BASETURF], "/turf/open/misc/asteroid/rimstation", "The underground baseturf should preserve breathable excavated stone.")

	var/list/sky_traits = map_config.traits[level_count]
	TEST_ASSERT(sky_traits[ZTRAIT_STATION], "The sky should be part of the loaded colony map.")
	TEST_ASSERT(!sky_traits[ZTRAIT_MINING], "The sky should not be treated as a mining level.")
	TEST_ASSERT(sky_traits[ZTRAIT_GRAVITY], "The sky should have standard gravity for falling and cliffs.")
	TEST_ASSERT(!sky_traits[ZTRAIT_UP] && sky_traits[ZTRAIT_DOWN], "The top level should link downward only.")
	TEST_ASSERT_NULL(sky_traits[ZTRAIT_LINKAGE], "The sky should not cross-link at its map edges.")
	TEST_ASSERT_EQUAL(sky_traits[ZTRAIT_BASETURF], "/turf/open/openspace/rimstation", "The upper level should remain open sky when stripped to baseturf.")

	// Everything between the two ends. A level that links only one way splits the z-stack in half, and
	// roofing walks that stack to decide which tiles see the sky.
	for(var/level_index in 2 to level_count - 1)
		var/list/middle_traits = map_config.traits[level_index]
		TEST_ASSERT(middle_traits[ZTRAIT_STATION], "Level [level_index] is not part of the loaded colony map, so sunlight and weather would skip it.")
		TEST_ASSERT(!middle_traits[ZTRAIT_MINING], "Level [level_index] carries the mining trait, which belongs to the bottom level alone.")
		TEST_ASSERT(middle_traits[ZTRAIT_GRAVITY], "Level [level_index] should have standard gravity.")
		TEST_ASSERT(middle_traits[ZTRAIT_UP] && middle_traits[ZTRAIT_DOWN], "Level [level_index] does not link both ways, which breaks the z-stack above or below it.")
		TEST_ASSERT_NULL(middle_traits[ZTRAIT_LINKAGE], "Level [level_index] should not cross-link at its map edges.")
		var/middle_baseturf = middle_traits[ZTRAIT_BASETURF]
		TEST_ASSERT((middle_baseturf in colony_baseturfs), "Level [level_index] strips down to [middle_baseturf], which is not a colony baseturf.")

	var/list/required_paths = list(
		"/area/rimstation_colony/underground",
		"/area/rimstation_colony/surface",
		"/area/rimstation_colony/sky",
		"/turf/open/misc/asteroid/rimstation",
		"/turf/closed/mineral/random/rimstation",
		"/turf/open/misc/dirt/planet/rimstation",
		"/turf/open/openspace/rimstation",
		"/turf/open/cliff/rimstation",
	)
	for(var/path_as_text in required_paths)
		TEST_ASSERT_NOTNULL(text2path(path_as_text), "The Rimstation map support type [path_as_text] is missing.")

	var/turf/open/misc/asteroid/rimstation/underground_turf = /turf/open/misc/asteroid/rimstation
	TEST_ASSERT_EQUAL(initial(underground_turf.initial_gas_mix), OPENTURF_DEFAULT_ATMOS, "Excavated underground tiles should contain Earthlike air.")
	TEST_ASSERT(!initial(underground_turf.planetary_atmos), "The underground should keep finite cave air instead of acting as an infinite atmosphere source.")

	var/turf/closed/mineral/random/rimstation/mineral_turf = /turf/closed/mineral/random/rimstation
	TEST_ASSERT_EQUAL(initial(mineral_turf.initial_gas_mix), OPENTURF_DEFAULT_ATMOS, "Mining the seed rock should reveal Earthlike cave air.")
	TEST_ASSERT_EQUAL(initial(mineral_turf.turf_type), /turf/open/misc/asteroid/rimstation, "Mining Rimstation rock should reveal the dedicated underground turf.")
	TEST_ASSERT_EQUAL(initial(mineral_turf.baseturfs), /turf/open/misc/asteroid/rimstation, "Rimstation rock should scrape down to breathable underground stone.")

	var/turf/open/misc/dirt/planet/rimstation/surface_turf = /turf/open/misc/dirt/planet/rimstation
	TEST_ASSERT_EQUAL(initial(surface_turf.initial_gas_mix), OPENTURF_DEFAULT_ATMOS, "The surface should start with Earthlike air.")
	TEST_ASSERT(initial(surface_turf.planetary_atmos), "The surface should replenish its Earthlike planetary atmosphere.")
	TEST_ASSERT_EQUAL(initial(surface_turf.baseturfs), /turf/open/misc/dirt/planet/rimstation, "The surface should remain native soil when scraped.")

	var/turf/open/openspace/rimstation/sky_turf = /turf/open/openspace/rimstation
	TEST_ASSERT_EQUAL(initial(sky_turf.initial_gas_mix), OPENTURF_DEFAULT_ATMOS, "The open sky should carry Earthlike air between levels.")
	TEST_ASSERT(initial(sky_turf.planetary_atmos), "The open sky should replenish Earthlike planetary air.")
	TEST_ASSERT_EQUAL(initial(sky_turf.baseturfs), /turf/open/openspace/rimstation, "Open sky should remain open sky as a baseturf.")

	var/turf/open/cliff/rimstation/cliff_turf = /turf/open/cliff/rimstation
	TEST_ASSERT_EQUAL(initial(cliff_turf.initial_gas_mix), OPENTURF_DEFAULT_ATMOS, "Cliffs should share the Earthlike surface atmosphere.")
	TEST_ASSERT(initial(cliff_turf.planetary_atmos), "Cliffs should participate in the planetary atmosphere.")
	TEST_ASSERT_EQUAL(initial(cliff_turf.underlay_tile), /turf/open/misc/dirt/planet/rimstation, "Cliffs should visually sit on Rimstation soil.")

	var/area/rimstation_colony/underground/underground_area = /area/rimstation_colony/underground
	TEST_ASSERT(!initial(underground_area.outdoors), "The underground should not receive daylight.")
	TEST_ASSERT_EQUAL(initial(underground_area.base_lighting_alpha), 0, "The underground should begin naturally dark.")

	// RIMSTATION EDIT CHANGE START - Daylight comes from the sky above each tile now, not from the area, so
	// the surface has to carry ordinary lighting objects and no base lighting at all. An area still lighting
	// itself would stay bright under a roof, which is the bug this replaced.
	var/area/rimstation_colony/surface/surface_area = /area/rimstation_colony/surface
	TEST_ASSERT(initial(surface_area.outdoors), "The main layer should be exposed to the planet's sky.")
	TEST_ASSERT(initial(surface_area.static_lighting), "The surface needs lighting objects so lamps and roof shade work on it.")
	TEST_ASSERT_EQUAL(initial(surface_area.base_lighting_alpha), 0, "The surface must not light itself; roofing it would leave it bright.")

	var/area/rimstation_colony/sky/sky_area = /area/rimstation_colony/sky
	TEST_ASSERT(initial(sky_area.outdoors), "The upper layer should be open air.")
	TEST_ASSERT(initial(sky_area.static_lighting), "The upper layer needs lighting objects for the same reason as the surface.")
	TEST_ASSERT_EQUAL(initial(sky_area.base_lighting_alpha), 0, "The open-air layer must not light itself.")
	// RIMSTATION EDIT CHANGE END

	var/datum/parsed_map/parsed_map = new(file(RIMSTATION_COLONY_MAP))
	allocated += parsed_map
	TEST_ASSERT_NOTNULL(parsed_map.parsed_bounds, "The Rimstation Colony DMM could not be parsed.")
	TEST_ASSERT_EQUAL(parsed_map.parsed_bounds[MAP_MAXX] - parsed_map.parsed_bounds[MAP_MINX] + 1, RIMSTATION_COLONY_SIZE, "The colony map should be [RIMSTATION_COLONY_SIZE] tiles wide.")
	TEST_ASSERT_EQUAL(parsed_map.parsed_bounds[MAP_MAXY] - parsed_map.parsed_bounds[MAP_MINY] + 1, RIMSTATION_COLONY_SIZE, "The colony map should be [RIMSTATION_COLONY_SIZE] tiles tall.")
	TEST_ASSERT_EQUAL(parsed_map.parsed_bounds[MAP_MAXZ] - parsed_map.parsed_bounds[MAP_MINZ] + 1, level_count, "The colony DMM holds a different number of z-levels than its map config declares traits for.")

	// Each level is restricted to the areas that belong on it. The surface carries two: generated wilds and
	// the hand-placed landing clearing that must never be generated over.
	var/list/underground_areas = list("/area/rimstation_colony/underground")
	var/list/surface_areas = list("/area/rimstation_colony/surface/wilds", "/area/rimstation_colony/surface/landing")
	var/list/sky_areas = list("/area/rimstation_colony/sky")
	// Only the two ends are fixed by role. A level added in the middle may be any of the three kinds.
	var/list/middle_areas = underground_areas + surface_areas + sky_areas
	// A station-grade spawn on a colony map would drop players into a department that does not exist here.
	var/list/forbidden_model_fragments = list(
		"/obj/effect/landmark/start/",
		"/obj/machinery/computer/cargo",
		"/obj/machinery/rnd/",
		"/obj/machinery/autolathe",
	)

	var/found_colony_spawn = FALSE
	var/found_settlement_center = FALSE
	var/found_raid_insertion = FALSE
	var/list/seen_keys = list()
	for(var/datum/grid_set/grid_set as anything in parsed_map.gridSets)
		var/list/allowed_areas = middle_areas
		if(grid_set.zcrd == 1)
			allowed_areas = underground_areas
		else if(grid_set.zcrd == level_count)
			allowed_areas = sky_areas
		for(var/grid_line in grid_set.gridLines)
			for(var/key_position in 1 to length(grid_line) step parsed_map.key_len)
				var/model_key = copytext(grid_line, key_position, key_position + parsed_map.key_len)
				if(seen_keys["[grid_set.zcrd]:[model_key]"])
					continue
				seen_keys["[grid_set.zcrd]:[model_key]"] = TRUE
				var/model = parsed_map.grid_models[model_key]

				var/area_matched = FALSE
				for(var/allowed_area in allowed_areas)
					if(findtext(model, allowed_area))
						area_matched = TRUE
						break
				TEST_ASSERT(area_matched, "Z-level [grid_set.zcrd] model [model_key] used an area that does not belong on that layer.")

				for(var/forbidden in forbidden_model_fragments)
					TEST_ASSERT(!findtext(model, forbidden), "The colony map contains [forbidden], which is station-grade content.")

				if(findtext(model, "/obj/effect/landmark/rimstation_colony_spawn"))
					found_colony_spawn = TRUE
				if(findtext(model, "/obj/effect/landmark/rimstation_settlement_center"))
					found_settlement_center = TRUE
				if(findtext(model, "/obj/effect/landmark/rimstation_raid_insertion"))
					found_raid_insertion = TRUE

	TEST_ASSERT(found_colony_spawn, "The colony map has nowhere for colonists to start.")
	TEST_ASSERT(found_settlement_center, "The colony map has no settlement centre, so raids cannot measure an exclusion radius.")
	TEST_ASSERT(found_raid_insertion, "The colony map has no validated raid insertion points, so attackers would have to spawn arbitrarily.")

	// The wilds are genturf and rely on the generator running; the landing site must not be generated over.
	var/area/rimstation_colony/surface/wilds/wilds_area = /area/rimstation_colony/surface/wilds
	TEST_ASSERT(initial(wilds_area.use_mapgen), "The wilds must run their map generator, or the map keeps its placeholder genturf.")
	TEST_ASSERT(initial(wilds_area.area_flags_mapping) & CAVES_ALLOWED, "The wilds must allow cave generation.")
	TEST_ASSERT_EQUAL(initial(wilds_area.map_generator), /datum/map_generator/cave_generator/rimstation_colony, "The wilds should generate from the colony's own seeded generator.")

	var/area/rimstation_colony/surface/landing/landing_area = /area/rimstation_colony/surface/landing
	TEST_ASSERT(!initial(landing_area.use_mapgen), "The landing site must stay hand-placed so colonists cannot spawn inside rock.")

#undef RIMSTATION_COLONY_CONFIG
#undef RIMSTATION_COLONY_MAP
#undef RIMSTATION_COLONY_MINIMUM_LEVELS
#undef RIMSTATION_COLONY_SIZE
