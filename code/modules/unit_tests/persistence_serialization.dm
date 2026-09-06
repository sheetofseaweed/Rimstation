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

#define TEST_ID_OWNER "Vera Holt"
#define TEST_ID_ASSIGNMENT "Colonist"

/**
 * An ID card is almost entirely the data printed on it, and none of it was in the save whitelist.
 *
 * A card that survives a chapter as blank plastic is worse than one that was deleted, because it looks like it
 * still works. Owner, age, assignment and access all have to reach the map.
 */
/datum/unit_test/persistence_serialization_id_card_saved

/datum/unit_test/persistence_serialization_id_card_saved/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(test_turf), "Expected the ID card test turf to be a floor")

	var/obj/item/card/id/card = allocate(/obj/item/card/id, test_turf)
	card.registered_name = TEST_ID_OWNER
	card.registered_age = 27
	card.assignment = TEST_ID_ASSIGNMENT
	card.access = list(ACCESS_MAINT_TUNNELS)

	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_OBJECTS_PROPERTIES)

	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data for an ID card")
	TEST_ASSERT(findtext(map, "registered_name = \"[TEST_ID_OWNER]\""), "Expected the card's owner to be written to the map, or it comes back belonging to nobody")
	TEST_ASSERT(findtext(map, "registered_age = 27"), "Expected the card's registered age to be written to the map")
	TEST_ASSERT(findtext(map, "assignment = \"[TEST_ID_ASSIGNMENT]\""), "Expected the card's assignment to be written to the map")
	// Access levels are strings, so they land in the map quoted.
	TEST_ASSERT(findtext(map, "access = list(\"[ACCESS_MAINT_TUNNELS]\")"), "Expected the card's access to be written to the map, or it comes back opening nothing")

/// A trim is a singleton datum and cannot be written to a map. Its type can, and that is what has to be stored.
/datum/unit_test/persistence_serialization_id_card_trim_saved

/datum/unit_test/persistence_serialization_id_card_trim_saved/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	var/obj/item/card/id/card = allocate(/obj/item/card/id, test_turf)

	SSid_access.apply_trim_to_card(card, /datum/id_trim/job/assistant)
	TEST_ASSERT_NOTNULL(card.trim, "Expected the test to be able to put a trim on a card")

	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_OBJECTS_PROPERTIES)

	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data for a trimmed ID card")
	TEST_ASSERT(findtext(map, "trim = [/datum/id_trim/job/assistant]"), "Expected the card's trim to be written to the map as a typepath")
	// A datum reference written verbatim would be a useless string like \[0x2000001\].
	TEST_ASSERT(!findtext(map, "trim = \"\["), "Expected the trim to be written as a typepath rather than a datum reference")

/**
 * A PDA is a container nothing was walking, so the card inside one was dropped on every save.
 *
 * It is not /obj/item/storage and had no on_object_saved(), so the shell was written and its contents were not.
 * A card left loose in a backpack survived; the same card in the PDA it belongs in did not.
 */
/datum/unit_test/persistence_serialization_pda_contents_saved

/datum/unit_test/persistence_serialization_pda_contents_saved/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(test_turf), "Expected the PDA test turf to be a floor")

	var/obj/item/modular_computer/pda/pda = allocate(/obj/item/modular_computer/pda, test_turf)
	var/obj/item/card/id/card = allocate(/obj/item/card/id, test_turf)
	card.registered_name = TEST_ID_OWNER
	pda.insert_id(card)
	TEST_ASSERT_EQUAL(pda.stored_id, card, "Expected the test to be able to put a card in a PDA")

	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_OBJECTS_PROPERTIES)

	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data for a PDA")
	TEST_ASSERT(findtext(map, "registered_name = \"[TEST_ID_OWNER]\""), "Expected the card inside the PDA to be written to the map")
	TEST_ASSERT(findtext(map, "save_container_parent_id"), "Expected the PDA to be written as the card's container")
	// Initialize() builds a cell from a typepath, so a saved cell would land beside a second one it made itself.
	TEST_ASSERT(findtext(map, "internal_cell = null"), "Expected the PDA to be told not to build its own cell over the saved one")

/// The whole point: write out a PDA with a card in it and read one back, with the card in the slot.
/datum/unit_test/persistence_serialization_pda_round_trip

/datum/unit_test/persistence_serialization_pda_round_trip/Run()
	var/turf/source_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	var/turf/dest_turf = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(source_turf), "Expected the PDA round trip source turf to be a floor")
	TEST_ASSERT(isfloorturf(dest_turf), "Expected the PDA round trip destination turf to be a floor")

	var/obj/item/modular_computer/pda/pda = allocate(/obj/item/modular_computer/pda, source_turf)
	var/obj/item/card/id/card = allocate(/obj/item/card/id, source_turf)
	card.registered_name = TEST_ID_OWNER
	pda.insert_id(card)

	var/map = write_map(source_turf.x, source_turf.y, source_turf.z, source_turf.x, source_turf.y, source_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_OBJECTS_PROPERTIES)
	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data for a PDA holding a card")

	GLOB.save_containers_parents.Cut()
	GLOB.save_containers_children.Cut()

	var/datum/parsed_map/parsed = new(map)
	TEST_ASSERT_NOTNULL(parsed.bounds, "Expected the written map to parse back into bounds")
	parsed.load(dest_turf.x, dest_turf.y, dest_turf.z, no_changeturf = TRUE)

	var/list/loaded_movables = list()
	for(var/atom/movable/loaded in dest_turf)
		loaded_movables += loaded
	SSatoms.InitializeAtoms(loaded_movables)

	SSworld_save.link_loaded_containers()
	GLOB.save_containers_parents.Cut()
	GLOB.save_containers_children.Cut()

	var/obj/item/modular_computer/pda/reloaded = locate(/obj/item/modular_computer/pda) in dest_turf
	TEST_ASSERT_NOTNULL(reloaded, "Expected the PDA to load onto the destination turf")
	allocated += reloaded
	reloaded.PersistentInitialize()

	// Loose in contents is not good enough: every consumer reads the slot, so a card that is not in one is gone.
	TEST_ASSERT_NOTNULL(reloaded.stored_id, "Expected the reloaded PDA to have a card in its slot")
	TEST_ASSERT_EQUAL(reloaded.stored_id.registered_name, TEST_ID_OWNER, "Expected the reloaded card to still name its owner")
	TEST_ASSERT_NOTNULL(reloaded.internal_cell, "Expected the reloaded PDA to have a cell, or it will not turn on")
	TEST_ASSERT_EQUAL(reloaded.internal_cell.loc, reloaded, "Expected the reloaded PDA's cell to be inside it")


#define TEST_AREA_ROOM_NAME "Vera's Workshop"

/// A blueprint room is a bare /area with a name, and only the name says which room it is. It has to reach the map.
/datum/unit_test/persistence_area_identity_saved

/datum/unit_test/persistence_area_identity_saved/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(test_turf), "Expected the area identity test turf to be a floor")

	var/area/original = get_area(test_turf)
	var/area/room = new /area(null)
	room.setup(TEST_AREA_ROOM_NAME)
	GLOB.custom_areas[room] = TRUE
	set_turfs_to_area(list(test_turf), room)

	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_TURFS | SAVE_AREAS)

	// Put the test room back before asserting, so a failure does not leave the suite's own area carved up.
	set_turfs_to_area(list(test_turf), original)
	GLOB.custom_areas -= room
	qdel(room)

	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data for a player-built area")
	TEST_ASSERT(findtext(map, "/obj/effect/persistent_area_marker"), "Expected a player-built area to write an identity marker, or every room of its type merges on load")
	TEST_ASSERT(findtext(map, "persistent_area_name = \"[TEST_AREA_ROOM_NAME]\""), "Expected the room's name to reach the map")
	TEST_ASSERT(findtext(map, "persistent_area_id"), "Expected the room to be given an id, which is what keeps two rooms apart")
	TEST_ASSERT(findtext(map, "persistent_area_blueprinted = 1"), "Expected the marker to record that a blueprint drew this room")

/**
 * Two saved rooms come back as two rooms, each holding its own turfs.
 *
 * This is the failure the whole file exists for: the map reader hands one area instance to every tile that
 * names the same type, so fourteen rooms loaded as one area with one APC paying for all of them.
 */
/datum/unit_test/persistence_area_identity_rebuilt

/datum/unit_test/persistence_area_identity_rebuilt/Run()
	var/turf/first_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	var/turf/second_turf = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(first_turf), "Expected the first rebuild turf to be a floor")
	TEST_ASSERT(isfloorturf(second_turf), "Expected the second rebuild turf to be a floor")

	var/area/original = get_area(first_turf)
	TEST_ASSERT_EQUAL(get_area(second_turf), original, "Expected both rebuild turfs to start in the same area")

	// What a loaded map leaves behind: two rooms' worth of tiles, grouped by which room they were.
	GLOB.loaded_area_turfs.Cut()
	GLOB.loaded_area_records.Cut()
	GLOB.loaded_area_turfs["room-one"] = list(first_turf)
	GLOB.loaded_area_records["room-one"] = list("type" = /area, "name" = "Room One", "outdoors" = FALSE, "gravity" = 0, "blueprinted" = TRUE)
	GLOB.loaded_area_turfs["room-two"] = list(second_turf)
	GLOB.loaded_area_records["room-two"] = list("type" = /area, "name" = "Room Two", "outdoors" = FALSE, "gravity" = 0, "blueprinted" = TRUE)

	var/rebuilt = SSworld_save.rebuild_persistent_areas()

	var/area/first_area = get_area(first_turf)
	var/area/second_area = get_area(second_turf)

	// Hand the suite's turfs back before asserting, so a failure here does not break every test after it.
	set_turfs_to_area(list(first_turf, second_turf), original)
	for(var/area/rebuilt_area in list(first_area, second_area))
		if(rebuilt_area != original)
			GLOB.custom_areas -= rebuilt_area
			qdel(rebuilt_area)

	TEST_ASSERT_EQUAL(rebuilt, 2, "Expected both saved rooms to be rebuilt")
	TEST_ASSERT(first_area != original, "Expected the first room's turf to be moved out of the area it loaded into")
	TEST_ASSERT(first_area != second_area, "Expected two saved rooms to come back as two areas, not one merged one")
	TEST_ASSERT_EQUAL(first_area.name, "Room One", "Expected the first room to come back under its own name")
	TEST_ASSERT_EQUAL(second_area.name, "Room Two", "Expected the second room to come back under its own name")
	TEST_ASSERT(!length(GLOB.loaded_area_turfs), "Expected the rebuild to consume what the map left behind")

#undef TEST_AREA_ROOM_NAME

#define TEST_SHUTTLE_NAME "Unit Test Shuttle"
#define TEST_SHUTTLE_ID "unit_test_shuttle"

/**
 * A shuttle tile records the ground it is parked on, because only the port knows and the port is not saved.
 *
 * A shuttle gives each turf back to that area when it lifts off. Without this the restored shuttle falls back
 * to its dock's area_type, which for a home dock was read off the shuttle sitting on it - so taking off would
 * leave a patch of shuttle floor behind instead of the ground.
 */
/datum/unit_test/persistence_shuttle_underlying_area_saved

/datum/unit_test/persistence_shuttle_underlying_area_saved/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(test_turf), "Expected the shuttle underlying area test turf to be a floor")

	var/area/ground = get_area(test_turf)
	var/area/hull = new /area/shuttle/custom(null)
	hull.setup(TEST_SHUTTLE_NAME)
	set_turfs_to_area(list(test_turf), hull)

	var/obj/docking_port/mobile/custom/port = new(test_turf, list(hull))
	port.name = TEST_SHUTTLE_NAME
	port.shuttle_id = TEST_SHUTTLE_ID
	port.width = 1
	port.height = 1
	port.underlying_areas_by_turf[test_turf] = ground
	port.register(replace = TRUE, custom = TRUE)

	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_TURFS | SAVE_AREAS | SAVE_AREAS_CUSTOM_SHUTTLES)

	// Hand the suite's turf back before asserting, so a failure does not leave it inside a shuttle.
	set_turfs_to_area(list(test_turf), ground)
	port.unregister()
	SSshuttle.assoc_mobile -= TEST_SHUTTLE_ID
	qdel(port, force = TRUE)

	TEST_ASSERT_NOTNULL(map, "Expected write_map() to return data for a shuttle tile")
	TEST_ASSERT(findtext(map, "persistent_underlying_area_type = \"[ground.type]\""), "Expected a shuttle tile to record the ground it is parked on, or the shuttle leaves shuttle floor behind when it flies")

/**
 * A saved custom shuttle comes back as a shuttle, not as an object shaped like one.
 *
 * Only the shuttle template loader and create_shuttle() ever call register(), and a port read off a saved map
 * is neither, so it never reached SSshuttle.mobile_docking_ports. Everything downstream looks the shuttle up
 * through that list, so its own consoles could not find it and the navigation computer threw on the null.
 *
 * The areas matter as much: the map reader hands every /area/shuttle/custom tile one merged instance, and the
 * area rebuild then moves the turfs into the real rooms - which leaves the port owning an area with nothing in
 * it unless it looks again.
 */
/datum/unit_test/persistence_shuttle_restored_from_save

/datum/unit_test/persistence_shuttle_restored_from_save/Run()
	var/turf/first_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	var/turf/second_turf = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(first_turf), "Expected the first shuttle restore turf to be a floor")
	TEST_ASSERT(isfloorturf(second_turf), "Expected the second shuttle restore turf to be a floor")

	var/area/ground = get_area(first_turf)
	// The default area is the one create_shuttle() named after the shuttle. The other is a room drawn inside it.
	var/area/hull = new /area/shuttle/custom(null)
	hull.setup(TEST_SHUTTLE_NAME)
	var/area/hold = new /area/shuttle/custom(null)
	hold.setup("Unit Test Hold")
	set_turfs_to_area(list(first_turf), hull)
	set_turfs_to_area(list(second_turf), hold)

	var/obj/docking_port/mobile/custom/port = new(first_turf, list(hull, hold))
	port.name = TEST_SHUTTLE_NAME
	port.shuttle_id = TEST_SHUTTLE_ID
	port.width = 2
	port.height = 1

	// What a checkpoint load actually leaves behind: the port knows its size and its id, and nothing else.
	// Its areas were the merged instance the map reader made, which no longer holds any of these turfs.
	port.shuttle_areas = list()
	port.default_area = null
	port.turf_count = 0

	port.PersistentInitialize()

	var/was_registered = port.registered
	var/in_registry = (port in SSshuttle.mobile_docking_ports)
	var/list/restored_areas = port.shuttle_areas.Copy()
	var/area/restored_default = port.default_area
	var/restored_turf_count = port.turf_count

	// Full cleanup before asserting. A registered shuttle or a stranded area would break every later test.
	set_turfs_to_area(list(first_turf, second_turf), ground)
	port.unregister()
	SSshuttle.assoc_mobile -= TEST_SHUTTLE_ID
	qdel(port, force = TRUE) // takes default_area with it
	qdel(hold)

	TEST_ASSERT(was_registered, "Expected a restored shuttle to register itself, or nothing can find it - including its own consoles")
	TEST_ASSERT(in_registry, "Expected a restored shuttle to reach SSshuttle.mobile_docking_ports, which is what get_containing_shuttle() reads")
	TEST_ASSERT_EQUAL(length(restored_areas), 2, "Expected the restored shuttle to find both of its areas again")
	TEST_ASSERT_EQUAL(restored_default, hull, "Expected the area named after the shuttle to be its default area, which is the one expand_shuttle() and the blueprint console read")
	TEST_ASSERT_EQUAL(restored_areas[1], hull, "Expected the default area to be first, since shuttle_areas\[1\] is how the default is found")
	TEST_ASSERT_EQUAL(restored_turf_count, 2, "Expected the restored shuttle to count its own turfs, which is what sizes its engines")

/// A console that finds no shuttle refuses, rather than reading a name off the null it was handed.
/datum/unit_test/persistence_shuttle_console_survives_no_port

/datum/unit_test/persistence_shuttle_console_survives_no_port/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)

	// A runtime raised in here fails the test, which is the assertion that matters.
	var/obj/machinery/computer/camera_advanced/shuttle_docker/custom/navigation = allocate(/obj/machinery/computer/camera_advanced/shuttle_docker/custom, test_turf)
	TEST_ASSERT(!navigation.connect_to_shuttle(TRUE, null, null), "Expected a navigation computer to refuse to connect to no shuttle at all")

	var/obj/machinery/computer/shuttle/custom_shuttle/control = allocate(/obj/machinery/computer/shuttle/custom_shuttle, test_turf)
	TEST_ASSERT(!control.connect_to_shuttle(TRUE, null, null), "Expected a shuttle control console to refuse to connect to no shuttle at all")

/**
 * A blueprint comes back knowing which shuttle it describes, and whether it is the master.
 *
 * The link is a weakref both ways, so neither survives. A restored blueprint read as blank - and a blank
 * blueprint used on the shuttle frame it already describes tries to build a second shuttle over the first.
 */
/datum/unit_test/persistence_shuttle_blueprint_relinked

/datum/unit_test/persistence_shuttle_blueprint_relinked/Run()
	var/turf/test_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(isfloorturf(test_turf), "Expected the blueprint relink test turf to be a floor")

	var/area/ground = get_area(test_turf)
	var/area/hull = new /area/shuttle/custom(null)
	hull.setup(TEST_SHUTTLE_NAME)
	set_turfs_to_area(list(test_turf), hull)

	var/obj/docking_port/mobile/custom/port = new(test_turf, list(hull))
	port.name = TEST_SHUTTLE_NAME
	port.shuttle_id = TEST_SHUTTLE_ID
	port.width = 1
	port.height = 1
	port.register(replace = TRUE, custom = TRUE)

	var/obj/item/shuttle_blueprints/blueprint = allocate(/obj/item/shuttle_blueprints, test_turf)
	blueprint.link_to_shuttle(port, is_master = TRUE)

	// What the save records for it, and what the map file actually gets.
	var/list/saved = blueprint.get_custom_save_vars()
	var/map = write_map(test_turf.x, test_turf.y, test_turf.z, test_turf.x, test_turf.y, test_turf.z, SAVE_OBJECTS | SAVE_OBJECTS_VARIABLES | SAVE_OBJECTS_PROPERTIES)

	// Now the load: the weakrefs are gone and only what reached the map is left.
	blueprint.unlink()
	port.master_blueprint = null
	blueprint.saved_shuttle_id = saved["saved_shuttle_id"]
	blueprint.saved_is_master = saved["saved_is_master"]
	GLOB.loaded_shuttle_blueprints.Cut()
	blueprint.PersistentInitialize()
	SSworld_save.relink_saved_shuttle_blueprints()

	var/obj/docking_port/mobile/custom/found_shuttle = blueprint.shuttle_ref?.resolve()
	var/obj/item/shuttle_blueprints/found_master = port.master_blueprint?.resolve()

	// Cleanup before asserting, so a failure does not leave a registered shuttle behind.
	set_turfs_to_area(list(test_turf), ground)
	port.unregister()
	SSshuttle.assoc_mobile -= TEST_SHUTTLE_ID
	if(blueprint.shuttle_ref) // unlink() dereferences it unguarded, and a failed relink leaves it null
		blueprint.unlink()
	qdel(port, force = TRUE) // takes hull with it
	GLOB.loaded_shuttle_blueprints.Cut()

	TEST_ASSERT_EQUAL(saved["saved_shuttle_id"], TEST_SHUTTLE_ID, "Expected the blueprint to save which shuttle it describes")
	TEST_ASSERT(saved["saved_is_master"], "Expected the blueprint to save that it was the master")
	TEST_ASSERT(findtext(map, "saved_shuttle_id = \"[TEST_SHUTTLE_ID]\""), "Expected the blueprint's shuttle to reach the map file")
	TEST_ASSERT_EQUAL(found_shuttle, port, "Expected a restored blueprint to find its shuttle again, or it reads as blank and builds a second one")
	TEST_ASSERT_EQUAL(found_master, blueprint, "Expected the master blueprint to still be the master after a reload")

#undef TEST_SHUTTLE_NAME
#undef TEST_SHUTTLE_ID
#undef TEST_ID_OWNER
#undef TEST_ID_ASSIGNMENT
// RIMSTATION EDIT ADDITION END
