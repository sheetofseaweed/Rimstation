/**
 * The map directory whitelist has to survive persistence being enabled.
 *
 * The original check switched itself off whenever PERSISTENT_SAVE_ENABLED was set - which is how this
 * repository runs - so every directory was accepted. Persistence genuinely needs nested paths, so the fix is
 * to allow nesting rather than to allow everything, and these assertions pin that distinction.
 */
/datum/unit_test/rimstation_map_directory_whitelist

/datum/unit_test/rimstation_map_directory_whitelist/Run()
	// The roots themselves, with and without a trailing slash.
	TEST_ASSERT(is_whitelisted_map_directory(MAP_DIRECTORY_MAPS), "The maps directory was rejected by its own whitelist.")
	TEST_ASSERT(is_whitelisted_map_directory(MAP_DIRECTORY_DATA), "The data directory was rejected by its own whitelist.")
	TEST_ASSERT(is_whitelisted_map_directory(MAP_PERSISTENT_DIRECTORY), "The persistence directory was rejected by its own whitelist.")
	TEST_ASSERT(is_whitelisted_map_directory("[MAP_DIRECTORY_MAPS]/"), "A trailing slash made a whitelisted root fail.")

	// The case the bypass existed for: a timestamped save folder inside the persistence root.
	TEST_ASSERT(is_whitelisted_map_directory("[MAP_PERSISTENT_DIRECTORY]2026-08-11_UTC_12.00.00"), "A persistence save subdirectory was rejected, which would stop saved worlds loading.")

	// Nesting is allowed under the persistence root only. Callers wanting a file inside _maps or data pass
	// that subfolder as part of the filename, so treating "data" as a licence to read anything below it
	// would hand back exactly the hole this whitelist exists to close.
	TEST_ASSERT(!is_whitelisted_map_directory("[MAP_DIRECTORY_DATA]/load_map_security_temp"), "An arbitrary subdirectory of the data root was accepted as a map directory.")
	TEST_ASSERT(!is_whitelisted_map_directory("[MAP_DIRECTORY_MAPS]/some_other_folder"), "An arbitrary subdirectory of the maps root was accepted as a map directory.")

	// Anything outside the roots stays out, persistence enabled or not.
	TEST_ASSERT(!is_whitelisted_map_directory("fartyShitPants"), "An arbitrary directory was accepted.")
	TEST_ASSERT(!is_whitelisted_map_directory("config"), "The config directory was accepted as a map source.")
	TEST_ASSERT(!is_whitelisted_map_directory(""), "An empty directory was accepted.")
	TEST_ASSERT(!is_whitelisted_map_directory(null), "A null directory was accepted.")

	// A prefix that merely starts the same is not inside the root.
	TEST_ASSERT(!is_whitelisted_map_directory("[MAP_DIRECTORY_MAPS]_secret"), "A directory that only shares a prefix with a whitelisted root was accepted.")

	// Traversal is refused rather than normalised.
	TEST_ASSERT(!is_whitelisted_map_directory("[MAP_DIRECTORY_MAPS]/../config"), "A path traversing out of a whitelisted root was accepted.")
