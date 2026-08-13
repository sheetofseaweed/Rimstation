/**
 * A campaign written by an older build has to survive being read by this one.
 *
 * The manifest is the only pointer to a colony, so a schema change is a moment where every existing campaign
 * either comes forward intact or is lost. The cases that matter are the ones where a migration could plausibly
 * do damage: mutating the record it was handed, running twice, or being given a record from a build that knew
 * more than this one does.
 */
/datum/unit_test/rimstation_campaign_migration

/// A manifest exactly as version 1 wrote them, before generations were counted.
/datum/unit_test/rimstation_campaign_migration/proc/build_version_one_record()
	RETURN_TYPE(/list)
	return list(
		"schema_version" = 1,
		"campaign_id" = "campaign-alpha",
		"generation_id" = "generation-1",
		"active_checkpoint_id" = "checkpoint-3",
		"planet_record" = list("root_seed" = "seed"),
		"chapter" = 4,
		"campaign_clock" = 1200,
		"storyteller_state" = list(),
		"record_references" = list(),
		"last_outcome" = COLONY_OUTCOME_SUCCESS,
		"generation_closed" = FALSE,
		"closure_reason" = null,
	)

/datum/unit_test/rimstation_campaign_migration/Run()
	var/list/original = build_version_one_record()

	var/list/migrated = migrate_campaign_manifest_record(original)
	TEST_ASSERT_NOTNULL(migrated, "A version 1 manifest could not be brought forward, which would lose every campaign written by an older build.")
	TEST_ASSERT_EQUAL(migrated["schema_version"], CAMPAIGN_MANIFEST_SCHEMA_VERSION, "Migration did not bring the record to the current schema version.")
	TEST_ASSERT_EQUAL(migrated["generation_number"], 1, "A version 1 record did not become the first generation.")

	// Everything the old record already said has to survive the trip.
	TEST_ASSERT_EQUAL(migrated["campaign_id"], "campaign-alpha", "Migration lost the campaign id.")
	TEST_ASSERT_EQUAL(migrated["generation_id"], "generation-1", "Migration lost the generation id.")
	TEST_ASSERT_EQUAL(migrated["active_checkpoint_id"], "checkpoint-3", "Migration lost the committed checkpoint, which is the colony itself.")
	TEST_ASSERT_EQUAL(migrated["chapter"], 4, "Migration lost the chapter count.")
	TEST_ASSERT_EQUAL(migrated["campaign_clock"], 1200, "Migration lost the campaign clock.")

	// The record it was handed is still on disk and must be exactly as it was.
	TEST_ASSERT_EQUAL(original["schema_version"], 1, "Migration rewrote the version of the record it was given.")
	TEST_ASSERT_NULL(original["generation_number"], "Migration added a field to the record it was given rather than to a copy.")

	// Running it again changes nothing, which is what makes a failed boot safe to retry.
	var/list/twice = migrate_campaign_manifest_record(migrated)
	TEST_ASSERT_NOTNULL(twice, "Migrating an already-current record refused it.")
	TEST_ASSERT_EQUAL(json_encode(twice), json_encode(migrated), "Migration is not idempotent; running it twice produced a different campaign.")

	// A generation number the record already carries is kept rather than reset to the first generation.
	var/list/later_generation = build_version_one_record()
	later_generation["generation_number"] = 3
	var/list/migrated_later = migrate_campaign_manifest_record(later_generation)
	TEST_ASSERT_EQUAL(migrated_later["generation_number"], 3, "Migration reset a campaign to its first generation, so the next one would reuse a name already on disk.")

	// A record from a newer build is refused rather than loaded with its unknown fields dropped on write-back.
	var/list/from_the_future = build_version_one_record()
	from_the_future["schema_version"] = CAMPAIGN_MANIFEST_SCHEMA_VERSION + 1
	TEST_ASSERT_NULL(migrate_campaign_manifest_record(from_the_future), "A manifest from a newer schema was accepted, which would rewrite it with the fields this build does not know about removed.")

	// And anything that is not a version at all is not guessed at.
	for(var/bad_version in list("2", 0, -1, 1.5, null))
		var/list/malformed = build_version_one_record()
		malformed["schema_version"] = bad_version
		TEST_ASSERT_NULL(migrate_campaign_manifest_record(malformed), "A manifest whose schema version was '[bad_version]' was accepted.")


/// A version 1 manifest loads into a working campaign, not just into a valid-looking list.
/datum/unit_test/rimstation_campaign_migration_load

/datum/unit_test/rimstation_campaign_migration_load/Run()
	var/list/legacy = list(
		"schema_version" = 1,
		"campaign_id" = "campaign-alpha",
		"generation_id" = "generation-2",
		"active_checkpoint_id" = "checkpoint-1",
		"planet_record" = list(),
		"chapter" = 2,
		"campaign_clock" = 0,
		"storyteller_state" = list(),
		"record_references" = list(),
		"last_outcome" = COLONY_OUTCOME_SUCCESS,
		"generation_closed" = FALSE,
		"closure_reason" = null,
	)

	var/datum/campaign_manifest/loaded = new
	allocated += loaded
	TEST_ASSERT(loaded.deserialize(legacy), "A version 1 manifest was refused on load.")
	TEST_ASSERT_EQUAL(loaded.schema_version, CAMPAIGN_MANIFEST_SCHEMA_VERSION, "A migrated manifest did not carry the current schema version.")
	TEST_ASSERT_EQUAL(loaded.generation_number, 1, "A migrated manifest did not receive a generation number.")
	TEST_ASSERT_EQUAL(loaded.active_checkpoint_id, "checkpoint-1", "A migrated manifest lost the checkpoint it points at.")
	TEST_ASSERT(loaded.validate(), "A migrated manifest does not validate, so the campaign it describes could not be loaded.")

	// Once migrated it writes back in the current shape, so the next boot has nothing left to migrate.
	var/datum/campaign_manifest/round_tripped = new
	allocated += round_tripped
	TEST_ASSERT(round_tripped.deserialize(json_decode(json_encode(loaded.serialize()))), "A migrated manifest did not survive being written and read back.")
	TEST_ASSERT(loaded.equals(round_tripped), "A migrated manifest changed when it was written back out.")

	// A record that migrates cleanly but is still contradictory is refused on its own merits.
	var/list/contradictory = legacy.Copy()
	contradictory["generation_closed"] = TRUE
	var/datum/campaign_manifest/refused = new
	allocated += refused
	TEST_ASSERT(!refused.deserialize(contradictory), "A closed generation still claiming a checkpoint passed because it migrated successfully.")
