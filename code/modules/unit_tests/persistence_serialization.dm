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
	// RIMSTATION EDIT START - ORG: two /obj/item/stack/sheet/iron. Stacks merge into one object, so the turf
	// only ever held a single item and the object limit was never reached.
	var/obj/item/wrench/first_sheet = allocate(/obj/item/wrench, test_turf)
	allocate(/obj/item/wrench, test_turf)
	// RIMSTATION EDIT END

	CONFIG_SET(number/persistent_max_object_limit_per_turf, 1)
	SSworld_save.reset_current_save_diagnostics()
	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_TURFS | SAVE_AREAS)
	CONFIG_SET(number/persistent_max_object_limit_per_turf, old_object_limit)

	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data when the object limit is reached")
	TEST_ASSERT_EQUAL(SSworld_save.current_save_diagnostics["skip_reasons"]["object_limit"], 1, "Expected one object limit skip to be recorded")
	TEST_ASSERT_EQUAL(SSworld_save.current_save_diagnostics["skip_types"]["[first_sheet.type]"], 1, "Expected one skipped item to be counted for the object limit") // RIMSTATION EDIT: ORG - "iron sheet"

/datum/unit_test/persistence_serialization_cancel_metrics

/datum/unit_test/persistence_serialization_cancel_metrics/Run()
	// RIMSTATION EDIT: ORG - x + 5, which is past the end of the test room and so never a floor.
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 4, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(test_turf), "Expected cancel test turf to be a floor")

	allocate(/obj/item/stack/sheet/iron, test_turf)

	SSworld_save.reset_current_save_diagnostics()
	SSworld_save.save_cancel_requested = TRUE
	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_TURFS | SAVE_AREAS)
	SSworld_save.save_cancel_requested = FALSE

	TEST_ASSERT_NULL(map, "Expected write_map() to stop when cancellation has been requested")
	TEST_ASSERT_EQUAL(SSworld_save.current_save_diagnostics["failure_reasons"]["cancel_requested"], 1, "Expected one cancel failure to be recorded")
	TEST_ASSERT_EQUAL(SSworld_save.current_save_diagnostics["failure_types"]["global"], 1, "Expected cancellation to be counted as a global failure")

// RIMSTATION EDIT ADDITION START - component-driven object state.
#define TEST_LABEL_TEXT "toolbox spare"

/// A label is a component holding an object in nullspace, so the serializer never walked it and a labelled item
/// came back unlabelled. Everything needed to rebuild the component has to reach the map.
/datum/unit_test/persistence_serialization_sticker_saved

/datum/unit_test/persistence_serialization_sticker_saved/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(test_turf), "Expected sticker test turf to be a floor")

	var/obj/item/wrench/labelled = allocate(/obj/item/wrench, test_turf)
	var/obj/item/label/sticky = allocate(/obj/item/label, test_turf, TEST_LABEL_TEXT)
	sticky.stick_to_atom(labelled, 12, 20)

	TEST_ASSERT_EQUAL(labelled.name, "wrench ([TEST_LABEL_TEXT])", "Expected the label to rename the wrench before saving")
	TEST_ASSERT_NULL(sticky.loc, "Expected the label to be parked in nullspace by the sticker component")

	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_OBJECTS_PROPERTIES)

	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data for a labelled object")
	TEST_ASSERT(findtext(map, "/obj/item/label"), "Expected the label object to be written to the map")
	TEST_ASSERT(findtext(map, "label_name = \"[TEST_LABEL_TEXT]\""), "Expected the label text to be written to the map")
	TEST_ASSERT(findtext(map, "save_sticker_offset = list(12, 20)"), "Expected the label's stick offsets to be written to the map")
	TEST_ASSERT(findtext(map, "save_container_parent_id"), "Expected the wrench to be written as the label's container")
	TEST_ASSERT(findtext(map, "save_container_child_id"), "Expected the label to be linked back to the wrench")
	// the wrench's name is rebuilt by the label on load, so persisting it would append the text a second time
	TEST_ASSERT(!findtext(map, "name = \"wrench"), "Expected the labelled name to be left out of the map")

/// The whole point: write a labelled object out and read it back, and get a labelled object.
/datum/unit_test/persistence_serialization_sticker_round_trip

/datum/unit_test/persistence_serialization_sticker_round_trip/Run()
	var/turf/source_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	var/turf/dest_turf = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(source_turf), "Expected round trip source turf to be a floor")
	TEST_ASSERT(isfloorturf(dest_turf), "Expected round trip destination turf to be a floor")

	var/obj/item/wrench/labelled = allocate(/obj/item/wrench, source_turf)
	var/obj/item/label/sticky = allocate(/obj/item/label, source_turf, TEST_LABEL_TEXT)
	sticky.stick_to_atom(labelled, 12, 20)

	// turfs and areas are left out so the load only spawns objects onto the destination turf
	var/map = write_map(source_turf.x, source_turf.y, source_turf.z, source_turf.x, source_turf.y, source_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_OBJECTS_PROPERTIES)
	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data for a labelled object")

	// the container globals are load-side state, and write_map() has already flushed its own
	GLOB.save_containers_parents.Cut()
	GLOB.save_containers_children.Cut()

	var/datum/parsed_map/parsed = new(map)
	TEST_ASSERT_NOTNULL(parsed.bounds, "Expected the written map to parse back into bounds")
	parsed.load(dest_turf.x, dest_turf.y, dest_turf.z, no_changeturf = TRUE)

	// parsed_map.load() leaves what it spawned uninitialised, and the container links are registered from
	// Initialize(). Map templates run this step themselves.
	var/list/loaded_movables = list()
	for(var/atom/movable/loaded in dest_turf)
		loaded_movables += loaded
	SSatoms.InitializeAtoms(loaded_movables)

	SSworld_save.link_loaded_containers()
	GLOB.save_containers_parents.Cut()
	GLOB.save_containers_children.Cut()

	var/obj/item/wrench/reloaded = locate(/obj/item/wrench) in dest_turf
	TEST_ASSERT_NOTNULL(reloaded, "Expected the wrench to load onto the destination turf")

	// GetComponent() refuses dupe-allowed components, and an atom can hold many stickers
	var/list/restored_components = reloaded.GetComponents(/datum/component/sticker)
	TEST_ASSERT_EQUAL(length(restored_components), 1, "Expected exactly one sticker component to be rebuilt on load")
	var/datum/component/sticker/restored = restored_components[1]
	TEST_ASSERT_EQUAL(restored.px, 12, "Expected the horizontal stick offset to survive the round trip")
	TEST_ASSERT_EQUAL(restored.py, 20, "Expected the vertical stick offset to survive the round trip")

	var/obj/item/label/reloaded_label = restored.our_sticker
	TEST_ASSERT_NOTNULL(reloaded_label, "Expected the rebuilt component to hold a label")
	TEST_ASSERT_EQUAL(reloaded_label.label_name, TEST_LABEL_TEXT, "Expected the label text to survive the round trip")
	TEST_ASSERT_EQUAL(reloaded_label.name, "label ([TEST_LABEL_TEXT])", "Expected the label's own name to be rebuilt from its text")
	TEST_ASSERT_NULL(locate(/obj/item/label) in dest_turf, "Expected the label to be parked in nullspace, not left on the floor")

	// the actual reported bug: the name has to come back, exactly once
	TEST_ASSERT_EQUAL(reloaded.name, "wrench ([TEST_LABEL_TEXT])", "Expected the reloaded wrench to still be labelled")
	TEST_ASSERT(HAS_TRAIT(reloaded, TRAIT_HAS_LABEL), "Expected the reloaded wrench to carry TRAIT_HAS_LABEL")
	TEST_ASSERT(HAS_TRAIT(reloaded, TRAIT_STICKERED), "Expected the reloaded wrench to carry TRAIT_STICKERED")

	// and it has to still be removable, which is what a persisted name alone would not give us
	qdel(reloaded_label)
	TEST_ASSERT_EQUAL(reloaded.name, "wrench", "Expected peeling the reloaded label to restore the original name")
	TEST_ASSERT(!HAS_TRAIT(reloaded, TRAIT_HAS_LABEL), "Expected peeling the reloaded label to clear TRAIT_HAS_LABEL")

	allocated += reloaded

/// Stored contents are saved by a different proc than turf contents, so a labelled item inside a toolbox
/// reaches the sticker path by its own route.
/datum/unit_test/persistence_serialization_sticker_in_container

/datum/unit_test/persistence_serialization_sticker_in_container/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(test_turf), "Expected container sticker test turf to be a floor")

	var/obj/item/storage/toolbox/toolbox = allocate(/obj/item/storage/toolbox, test_turf)
	var/obj/item/wrench/labelled = allocate(/obj/item/wrench, test_turf)
	var/obj/item/label/sticky = allocate(/obj/item/label, test_turf, TEST_LABEL_TEXT)
	labelled.forceMove(toolbox)
	sticky.stick_to_atom(labelled, 12, 20)

	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_OBJECTS_PROPERTIES)

	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data for a labelled object inside a container")
	TEST_ASSERT(findtext(map, "/obj/item/label"), "Expected the label of a stored item to be written to the map")
	TEST_ASSERT(findtext(map, "label_name = \"[TEST_LABEL_TEXT]\""), "Expected the stored item's label text to be written to the map")
	TEST_ASSERT(findtext(map, "save_sticker_offset = list(12, 20)"), "Expected the stored item's stick offsets to be written to the map")

#undef TEST_LABEL_TEXT
// RIMSTATION EDIT ADDITION END
