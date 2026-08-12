/**
 * A test run must never leave a world save behind.
 *
 * Saves written during testing are restored over the *next* round, which silently swaps the map's areas and
 * fails unrelated tests. That happened, and cost a lot of time to trace back from failures in blob placement
 * and mob factions, so the guard is asserted rather than trusted.
 */
/datum/unit_test/rimstation_world_save_blocked_in_tests

/datum/unit_test/rimstation_world_save_blocked_in_tests/Run()
	TEST_ASSERT(SSworld_save.save_writing_blocked(), "World saving is not blocked during unit tests, so this run can contaminate the next one.")
	TEST_ASSERT(!SSworld_save.can_save_world(), "World saving reported itself allowed during a unit test run.")
	// Every write path routes through save_world(), including the autosave that never checked the config.
	TEST_ASSERT(!SSworld_save.save_world(silent = TRUE), "save_world() went ahead during a unit test run.")

	// Loading is a separate switch, because a run can be poisoned by a save some earlier round left behind.
	TEST_ASSERT(SSworld_save.save_loading_blocked(), "World save loading is not blocked during unit tests.")
	TEST_ASSERT_NULL(SSworld_save.get_last_save(), "A unit test run selected a saved world to load over the test map.")
