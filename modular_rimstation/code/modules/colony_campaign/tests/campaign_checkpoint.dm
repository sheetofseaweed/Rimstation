/**
 * A named checkpoint is loaded, or nothing is.
 *
 * The inherited selection walks every save on disk and takes the newest loadable one, which is precisely how
 * a town from a previous generation comes back after a defeat. A campaign names its checkpoint, and a named
 * checkpoint that fails validation has to be a hard failure rather than a licence to load something else.
 */
/datum/unit_test/rimstation_campaign_exact_checkpoint

/datum/unit_test/rimstation_campaign_exact_checkpoint/Run()
	// A name that does not exist must not fall back to whatever else is on disk.
	TEST_ASSERT_NULL(SSworld_save.cache_z_levels_map_configs("checkpoint-that-does-not-exist"), "Naming a missing checkpoint returned map configs anyway, which means it substituted another save.")

	// Unit test runs never load saved worlds at all, named or otherwise.
	TEST_ASSERT(SSworld_save.save_loading_blocked(), "World save loading is not blocked during unit tests.")
	TEST_ASSERT_NULL(SSworld_save.cache_z_levels_map_configs(), "A unit test run selected a save to load.")


/**
 * Save destinations come from IDs that ultimately came off disk, so they are treated as untrusted paths.
 */
/datum/unit_test/rimstation_campaign_save_destination

/datum/unit_test/rimstation_campaign_save_destination/Run()
	// The two roots a save is allowed to land in.
	TEST_ASSERT(SSworld_save.is_valid_save_destination("[MAP_PERSISTENT_DIRECTORY]2026-08-11_UTC_12.00.00"), "An ordinary timestamped save directory was refused.")
	TEST_ASSERT(SSworld_save.is_valid_save_destination("[CAMPAIGN_STORAGE_ROOT]campaign-alpha/generations/generation-1/working/checkpoint-2"), "A campaign working checkpoint directory was refused.")

	// Anything else, or anything climbing out, is not a save destination.
	var/list/refused = list(
		"config",
		"data",
		"[CAMPAIGN_STORAGE_ROOT]../../config",
		"[MAP_PERSISTENT_DIRECTORY]../escape",
		"",
		null,
	)
	for(var/destination in refused)
		TEST_ASSERT(!SSworld_save.is_valid_save_destination(destination), "The save destination '[destination]' was accepted, which would let a campaign write outside its own storage.")

	// And a refused destination must stop the save rather than silently writing to the default pool.
	TEST_ASSERT(!SSworld_save.save_world(silent = TRUE, destination_directory = "config"), "A save with an invalid destination went ahead.")
