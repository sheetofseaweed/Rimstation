/**
 * Manifest promotion has to survive being interrupted.
 *
 * Manifests are numbered and never rewritten, because neither BYOND nor rust-g can rename a file - so
 * "replace the manifest" would mean deleting the only pointer to the town and hoping the write lands. These
 * assertions cover the case that scheme exists for: a commit that stops halfway must leave the previous
 * manifest complete and selectable.
 *
 * Everything is written under a test-owned campaign id and deleted in Destroy().
 */
/datum/unit_test/rimstation_campaign_promotion
	/// Campaign id used for every file this test writes, so cleanup can remove exactly its own data.
	var/test_campaign_id = "unit-test-campaign"

/datum/unit_test/rimstation_campaign_promotion/Run()
	var/datum/campaign_manifest/manifest = new(test_campaign_id, "generation-1")
	allocated += manifest

	// First commit: sequence 1.
	var/first_sequence = write_campaign_manifest(manifest)
	TEST_ASSERT_EQUAL(first_sequence, 1, "The first manifest was not written as sequence 1.")
	TEST_ASSERT(fexists(campaign_manifest_path(test_campaign_id, 1)), "The first manifest was not written to disk.")

	// Second commit points at a checkpoint.
	manifest.active_checkpoint_id = "checkpoint-1"
	manifest.chapter = 2
	var/second_sequence = write_campaign_manifest(manifest)
	TEST_ASSERT_EQUAL(second_sequence, 2, "The second manifest did not take the next sequence number.")

	// The newest valid manifest is the live one.
	var/datum/campaign_manifest/loaded = load_active_campaign_manifest(test_campaign_id)
	allocated += loaded
	TEST_ASSERT_NOTNULL(loaded, "No active manifest could be loaded after two commits.")
	TEST_ASSERT_EQUAL(loaded.chapter, 2, "The loaded manifest was not the newest one.")
	TEST_ASSERT_EQUAL(loaded.active_checkpoint_id, "checkpoint-1", "The loaded manifest did not carry the committed checkpoint.")

	// Simulate a commit interrupted mid-write: a truncated newest manifest.
	rustg_file_write("{\"schema_version\": 1, \"campaign_id\": \"unit-tes", campaign_manifest_path(test_campaign_id, 3))
	var/datum/campaign_manifest/after_interruption = load_active_campaign_manifest(test_campaign_id)
	allocated += after_interruption
	TEST_ASSERT_NOTNULL(after_interruption, "A truncated newest manifest left the campaign with nothing to load.")
	TEST_ASSERT_EQUAL(after_interruption.chapter, 2, "A truncated manifest was loaded instead of falling back to the last complete one.")
	TEST_ASSERT_EQUAL(after_interruption.active_checkpoint_id, "checkpoint-1", "Falling back after an interrupted commit lost the committed checkpoint.")

	// Structurally valid JSON that is not a valid manifest must also be refused rather than loaded.
	rustg_file_write(json_encode(list("schema_version" = 1, "campaign_id" = test_campaign_id)), campaign_manifest_path(test_campaign_id, 4))
	var/datum/campaign_manifest/after_bad_record = load_active_campaign_manifest(test_campaign_id)
	allocated += after_bad_record
	TEST_ASSERT_EQUAL(after_bad_record.chapter, 2, "A manifest missing its generation id was accepted as the live campaign.")

	// A manifest that does not validate is never written in the first place.
	var/datum/campaign_manifest/contradictory = new(test_campaign_id, "generation-1")
	allocated += contradictory
	contradictory.active_checkpoint_id = "checkpoint-9"
	contradictory.generation_closed = TRUE
	TEST_ASSERT_NULL(write_campaign_manifest(contradictory), "A closed generation still claiming a checkpoint was written to disk.")

/datum/unit_test/rimstation_campaign_promotion/Destroy()
	// Remove only this test's own campaign directory.
	var/campaign_root = campaign_path(test_campaign_id)
	if(campaign_root)
		fdel("[campaign_root]/")
	return ..()


/**
 * A checkpoint is only committable once it is finished.
 *
 * The completion marker is what separates "these files happen to exist" from "this checkpoint finished being
 * written", and it is written last precisely so a crashed stage cannot be mistaken for a finished one.
 */
/datum/unit_test/rimstation_campaign_checkpoint_completion
	var/test_campaign_id = "unit-test-checkpoint"

/datum/unit_test/rimstation_campaign_checkpoint_completion/Run()
	var/datum/campaign_manifest/manifest = new(test_campaign_id, "generation-1")
	allocated += manifest

	var/datum/campaign_checkpoint/checkpoint = new(test_campaign_id, "generation-1", "checkpoint-1")
	allocated += checkpoint
	TEST_ASSERT_NOTNULL(checkpoint.working_path, "A checkpoint with safe ids produced no working path.")

	// Nothing staged yet: not complete, and not committable.
	TEST_ASSERT(!checkpoint.is_complete(), "An unstaged checkpoint reported itself complete.")
	TEST_ASSERT(!checkpoint.commit(manifest), "An unstaged checkpoint was committed.")
	TEST_ASSERT_NULL(manifest.active_checkpoint_id, "A refused commit still pointed the manifest at the checkpoint.")

	// Files present but no completion marker is exactly the crashed-mid-stage case.
	rustg_file_write(json_encode(manifest.serialize()), "[checkpoint.working_path]/campaign.json")
	TEST_ASSERT(!checkpoint.is_complete(), "A checkpoint with artifacts but no completion marker reported itself complete.")
	TEST_ASSERT(!checkpoint.commit(manifest), "A checkpoint missing its completion marker was committed.")

	// A checkpoint whose campaign record belongs to another generation must not validate.
	var/datum/campaign_manifest/foreign = new(test_campaign_id, "generation-other")
	allocated += foreign
	rustg_file_write(json_encode(foreign.serialize()), "[checkpoint.working_path]/campaign.json")
	TEST_ASSERT(!checkpoint.validate_artifacts(), "A checkpoint describing a different generation passed validation.")

	// Unsafe ids never produce a path to write to at all.
	var/datum/campaign_checkpoint/traversing = new(test_campaign_id, "generation-1", "../escape")
	allocated += traversing
	TEST_ASSERT_NULL(traversing.working_path, "A checkpoint with a traversing id produced a usable path.")
	TEST_ASSERT(!traversing.stage(manifest), "A checkpoint with a traversing id was staged.")

/datum/unit_test/rimstation_campaign_checkpoint_completion/Destroy()
	var/campaign_root = campaign_path(test_campaign_id)
	if(campaign_root)
		fdel("[campaign_root]/")
	return ..()


/**
 * The world has to stop changing while a checkpoint is written.
 *
 * A checkpoint is produced by walking the map. Anything that mutates it mid-walk yields a save showing half
 * the town before an event and half after - a state that never existed. The guard is asserted at its call
 * sites, not just where it is defined, because a quiesce nobody consults is decoration.
 */
/datum/unit_test/rimstation_campaign_quiesce

/datum/unit_test/rimstation_campaign_quiesce/Run()
	var/original_state = SScampaign.campaign_state
	var/datum/campaign_manifest/original_manifest = SScampaign.manifest

	TEST_ASSERT(SScampaign.can_mutate_world(), "The world was reported as quiesced outside a commit.")

	// Drive the campaign into committing through the legal path.
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	var/datum/campaign_manifest/manifest = new("unit-test-quiesce", "generation-1")
	allocated += manifest
	SScampaign.manifest = manifest
	SScampaign.begin_load(manifest)
	SScampaign.begin_chapter()
	var/datum/colony_chapter_outcome/won = new
	allocated += won
	won.resolve(COLONY_OUTCOME_SUCCESS, "the raid was repelled")
	SScampaign.request_commit(won)
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_COMMITTING, "The campaign did not reach the committing state.")

	TEST_ASSERT(!SScampaign.can_mutate_world(), "The world was still mutable while a checkpoint was being committed.")

	// The guard has to actually be consulted by the things that change the world.
	var/datum/colony_raid/raid = new
	allocated += raid
	TEST_ASSERT(!raid.begin_warning(), "A raid started while the campaign was committing a checkpoint.")
	TEST_ASSERT_EQUAL(raid.outcome, COLONY_RAID_OUTCOME_CANCELLED, "A raid blocked by a commit did not record itself as cancelled.")

	SScampaign.campaign_state = original_state
	SScampaign.manifest = original_manifest


/// Campaign paths are built from ids that came off disk, so every level refuses to escape its root.
/datum/unit_test/rimstation_campaign_paths

/datum/unit_test/rimstation_campaign_paths/Run()
	TEST_ASSERT_EQUAL(campaign_path("alpha"), "[CAMPAIGN_STORAGE_ROOT]alpha", "A campaign path was not built under the campaign storage root.")
	TEST_ASSERT_EQUAL(campaign_generation_path("alpha", "gen-1"), "[CAMPAIGN_STORAGE_ROOT]alpha/generations/gen-1", "A generation path was not built where expected.")

	// An unsafe id at any level poisons the whole path, so every level returns null rather than a partial one.
	TEST_ASSERT_NULL(campaign_path("../escape"), "An unsafe campaign id produced a path.")
	TEST_ASSERT_NULL(campaign_generation_path("alpha", "../escape"), "An unsafe generation id produced a path.")
	TEST_ASSERT_NULL(campaign_working_path("alpha", "gen-1", "../escape"), "An unsafe checkpoint id produced a working path.")
	TEST_ASSERT_NULL(campaign_checkpoint_path("../escape", "gen-1", "checkpoint-1"), "An unsafe campaign id produced a checkpoint path.")
	TEST_ASSERT_NULL(campaign_manifest_path("alpha", 0), "A manifest sequence below 1 produced a path.")

	// Sequence parsing has to reject anything that is not a numbered manifest.
	TEST_ASSERT_EQUAL(extract_manifest_sequence("manifest.7.json"), 7, "A numbered manifest filename was not parsed.")
	var/list/not_manifests = list("manifest.json", "manifest..json", "campaign.json", "manifest.abc.json", "manifest.7.json.bak", "manifest.0.json")
	for(var/filename in not_manifests)
		TEST_ASSERT_NULL(extract_manifest_sequence(filename), "'[filename]' was parsed as a numbered manifest.")

	// Malformed JSON must be refused rather than thrown on.
	TEST_ASSERT_NULL(safely_decode_json("{\"truncated\": "), "Malformed JSON was decoded instead of refused.")
	TEST_ASSERT_NULL(safely_decode_json(""), "Empty text was decoded instead of refused.")
	TEST_ASSERT_NULL(safely_decode_json(null), "Null was decoded instead of refused.")
