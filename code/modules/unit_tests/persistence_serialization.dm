/obj/item/persistence_unit_test_abstract
	item_flags = ABSTRACT

/datum/unit_test/persistence_serialization_blacklist_metrics

/datum/unit_test/persistence_serialization_blacklist_metrics/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(test_turf), "Expected blacklist test turf to be a floor")

	var/obj/item/stack/sheet/iron/blacklisted_sheet = allocate(/obj/item/stack/sheet/iron, test_turf)
	var/list/custom_blacklist = typecacheof(list(/obj/item/stack/sheet/iron))

	SSworld_save.reset_current_save_diagnostics()
	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_TURFS | SAVE_AREAS, SAVE_SHUTTLEAREA_DONTCARE, custom_blacklist)

	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data when skipping a blacklisted object")
	TEST_ASSERT_EQUAL(SSworld_save.current_save_diagnostics["skip_reasons"]["blacklist"], 1, "Expected one blacklist skip to be recorded")
	TEST_ASSERT_EQUAL(SSworld_save.current_save_diagnostics["skip_types"]["[blacklisted_sheet.type]"], 1, "Expected the skipped iron sheet type to be counted once")

/datum/unit_test/persistence_serialization_abstract_item_metrics

/datum/unit_test/persistence_serialization_abstract_item_metrics/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 3, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(test_turf), "Expected abstract item test turf to be a floor")

	var/obj/item/persistence_unit_test_abstract/abstract_item = allocate(/obj/item/persistence_unit_test_abstract, test_turf)

	SSworld_save.reset_current_save_diagnostics()
	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_TURFS | SAVE_AREAS)

	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data when skipping an abstract item")
	TEST_ASSERT_EQUAL(SSworld_save.current_save_diagnostics["skip_reasons"]["abstract_item"], 1, "Expected one abstract item skip to be recorded")
	TEST_ASSERT_EQUAL(SSworld_save.current_save_diagnostics["skip_types"]["[abstract_item.type]"], 1, "Expected the skipped abstract item type to be counted once")

/datum/unit_test/persistence_serialization_object_limit_metrics

/datum/unit_test/persistence_serialization_object_limit_metrics/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 4, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(test_turf), "Expected object limit test turf to be a floor")

	var/old_object_limit = CONFIG_GET(number/persistent_max_object_limit_per_turf)
	var/obj/item/stack/sheet/iron/first_sheet = allocate(/obj/item/stack/sheet/iron, test_turf)
	allocate(/obj/item/stack/sheet/iron, test_turf)

	CONFIG_SET(number/persistent_max_object_limit_per_turf, 1)
	SSworld_save.reset_current_save_diagnostics()
	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_TURFS | SAVE_AREAS)
	CONFIG_SET(number/persistent_max_object_limit_per_turf, old_object_limit)

	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data when the object limit is reached")
	TEST_ASSERT_EQUAL(SSworld_save.current_save_diagnostics["skip_reasons"]["object_limit"], 1, "Expected one object limit skip to be recorded")
	TEST_ASSERT_EQUAL(SSworld_save.current_save_diagnostics["skip_types"]["[first_sheet.type]"], 1, "Expected one skipped iron sheet to be counted for the object limit")

/datum/unit_test/persistence_serialization_cancel_metrics

/datum/unit_test/persistence_serialization_cancel_metrics/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 5, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(test_turf), "Expected cancel test turf to be a floor")

	allocate(/obj/item/stack/sheet/iron, test_turf)

	SSworld_save.reset_current_save_diagnostics()
	SSworld_save.save_cancel_requested = TRUE
	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_TURFS | SAVE_AREAS)
	SSworld_save.save_cancel_requested = FALSE

	TEST_ASSERT_NULL(map, "Expected write_map() to stop when cancellation has been requested")
	TEST_ASSERT_EQUAL(SSworld_save.current_save_diagnostics["failure_reasons"]["cancel_requested"], 1, "Expected one cancel failure to be recorded")
	TEST_ASSERT_EQUAL(SSworld_save.current_save_diagnostics["failure_types"]["global"], 1, "Expected cancellation to be counted as a global failure")
