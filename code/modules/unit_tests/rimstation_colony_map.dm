#define RIMSTATION_COLONY_CONFIG "rimstation_colony"
#define RIMSTATION_COLONY_MAP "_maps/map_files/rimstation_colony/rimstation_colony.dmm"

/datum/unit_test/rimstation_colony_map_contract
	test_flags = UNIT_TEST_MAP_TEST

/datum/unit_test/rimstation_colony_map_contract/Run()
	var/datum/map_config/map_config = load_map_config(RIMSTATION_COLONY_CONFIG, MAP_DIRECTORY_MAPS)
	allocated += map_config

	TEST_ASSERT(!map_config.defaulted, "Rimstation Colony's map config could not be loaded.")
	TEST_ASSERT_EQUAL(map_config.map_name, "Rimstation Colony", "The development map should keep its stable display name.")
	TEST_ASSERT_EQUAL(map_config.map_path, "map_files/rimstation_colony", "The map should live in its dedicated map directory.")
	TEST_ASSERT_EQUAL(map_config.map_file, "rimstation_colony.dmm", "The config should load the three-level seed DMM.")
	TEST_ASSERT(map_config.planetary, "Rimstation Colony should use planetary atmosphere behavior.")
	TEST_ASSERT(!map_config.height_autosetup, "The map's vertical links should be explicit rather than inferred.")
	TEST_ASSERT_EQUAL(map_config.minetype, MINETYPE_NONE, "The underground layer is part of the map and should not load a separate mining level.")
	TEST_ASSERT_EQUAL(map_config.space_ruin_levels, 0, "The colony seed should not add space ruin levels.")
	TEST_ASSERT_EQUAL(map_config.space_empty_levels, 0, "The colony seed should not add empty space levels.")
	TEST_ASSERT_EQUAL(map_config.wilderness_levels, 0, "The colony seed should not add generated wilderness levels.")

	TEST_ASSERT_EQUAL(length(map_config.traits), 3, "The colony seed should contain underground, surface, and sky levels.")
	var/list/underground_traits = map_config.traits[1]
	var/list/surface_traits = map_config.traits[2]
	var/list/sky_traits = map_config.traits[3]

	TEST_ASSERT(underground_traits[ZTRAIT_STATION], "The underground should be part of the loaded colony map.")
	TEST_ASSERT(underground_traits[ZTRAIT_MINING], "Only the underground should carry the mining-level trait.")
	TEST_ASSERT(underground_traits[ZTRAIT_GRAVITY], "The underground should have standard gravity.")
	TEST_ASSERT(underground_traits[ZTRAIT_UP] && !underground_traits[ZTRAIT_DOWN], "The underground should link upward to the surface only.")
	TEST_ASSERT_NULL(underground_traits[ZTRAIT_LINKAGE], "The underground should not cross-link at its map edges.")
	TEST_ASSERT_EQUAL(underground_traits[ZTRAIT_BASETURF], "/turf/open/misc/asteroid/rimstation", "The underground baseturf should preserve breathable excavated stone.")

	TEST_ASSERT(surface_traits[ZTRAIT_STATION], "The surface should be part of the loaded colony map.")
	TEST_ASSERT(!surface_traits[ZTRAIT_MINING], "The main surface should not be treated as a mining level.")
	TEST_ASSERT(surface_traits[ZTRAIT_GRAVITY], "The surface should have standard gravity.")
	TEST_ASSERT(surface_traits[ZTRAIT_UP] && surface_traits[ZTRAIT_DOWN], "The surface should link to both surrounding levels.")
	TEST_ASSERT_NULL(surface_traits[ZTRAIT_LINKAGE], "The surface should not cross-link at its map edges.")
	TEST_ASSERT_EQUAL(surface_traits[ZTRAIT_BASETURF], "/turf/open/misc/dirt/planet/rimstation", "The surface baseturf should preserve Earthlike soil.")

	TEST_ASSERT(sky_traits[ZTRAIT_STATION], "The sky should be part of the loaded colony map.")
	TEST_ASSERT(!sky_traits[ZTRAIT_MINING], "The sky should not be treated as a mining level.")
	TEST_ASSERT(sky_traits[ZTRAIT_GRAVITY], "The sky should have standard gravity for falling and future cliffs.")
	TEST_ASSERT(!sky_traits[ZTRAIT_UP] && sky_traits[ZTRAIT_DOWN], "The sky should link downward to the surface only.")
	TEST_ASSERT_NULL(sky_traits[ZTRAIT_LINKAGE], "The sky should not cross-link at its map edges.")
	TEST_ASSERT_EQUAL(sky_traits[ZTRAIT_BASETURF], "/turf/open/openspace/rimstation", "The upper level should remain open sky when stripped to baseturf.")

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

	var/area/rimstation_colony/surface/surface_area = /area/rimstation_colony/surface
	TEST_ASSERT(initial(surface_area.outdoors), "The main layer should be exposed to the planet's sky.")
	TEST_ASSERT(!initial(surface_area.static_lighting), "The surface should use outdoor base lighting rather than room lighting objects.")
	TEST_ASSERT(initial(surface_area.base_lighting_alpha) > 0, "The main outdoor layer should receive daylight without treating Z3 as a roof.")

	var/area/rimstation_colony/sky/sky_area = /area/rimstation_colony/sky
	TEST_ASSERT(initial(sky_area.outdoors), "The upper layer should be open air.")
	TEST_ASSERT(!initial(sky_area.static_lighting), "The upper layer should use outdoor base lighting.")
	TEST_ASSERT(initial(sky_area.base_lighting_alpha) > 0, "The open-air layer should be daylight-lit.")

	var/datum/parsed_map/parsed_map = new(file(RIMSTATION_COLONY_MAP))
	allocated += parsed_map
	TEST_ASSERT_NOTNULL(parsed_map.parsed_bounds, "The Rimstation Colony DMM could not be parsed.")
	TEST_ASSERT_EQUAL(parsed_map.parsed_bounds[MAP_MAXX] - parsed_map.parsed_bounds[MAP_MINX] + 1, 10, "The seed map should be 10 tiles wide.")
	TEST_ASSERT_EQUAL(parsed_map.parsed_bounds[MAP_MAXY] - parsed_map.parsed_bounds[MAP_MINY] + 1, 10, "The seed map should be 10 tiles tall.")
	TEST_ASSERT_EQUAL(parsed_map.parsed_bounds[MAP_MAXZ] - parsed_map.parsed_bounds[MAP_MINZ] + 1, 3, "The seed map should contain exactly three z-levels.")

	var/list/expected_layer_turfs = list(
		"/turf/closed/mineral/random/rimstation",
		"/turf/open/misc/dirt/planet/rimstation",
		"/turf/open/openspace/rimstation",
	)
	var/list/expected_layer_areas = list(
		"/area/rimstation_colony/underground",
		"/area/rimstation_colony/surface",
		"/area/rimstation_colony/sky",
	)
	for(var/datum/grid_set/grid_set as anything in parsed_map.gridSets)
		var/expected_turf = expected_layer_turfs[grid_set.zcrd]
		var/expected_area = expected_layer_areas[grid_set.zcrd]
		for(var/grid_line in grid_set.gridLines)
			for(var/key_position in 1 to length(grid_line) step parsed_map.key_len)
				var/model_key = copytext(grid_line, key_position, key_position + parsed_map.key_len)
				var/model = parsed_map.grid_models[model_key]
				TEST_ASSERT(findtext(model, expected_turf), "Z-level [grid_set.zcrd] should use [expected_turf], but model [model_key] did not.")
				TEST_ASSERT(findtext(model, expected_area), "Z-level [grid_set.zcrd] should use [expected_area], but model [model_key] did not.")

#undef RIMSTATION_COLONY_CONFIG
#undef RIMSTATION_COLONY_MAP
