/**
 * A campaign has to be able to start, and starting one must never be able to replace one.
 *
 * Creation is the only moment a campaign is brought into being from nothing. From then on it is the only copy
 * of its colony, so every route that could write over an existing one is closed here rather than trusted to
 * the person running the verb.
 */
/datum/unit_test/campaign_failure_path/rimstation_campaign_creation
	test_campaign_id = "unit-test-creation"

/datum/unit_test/campaign_failure_path/rimstation_campaign_creation/Run()
	take_campaign()

	// A round starting on a server without a campaign does nothing whatsoever.
	SScampaign.on_round_starting(SSticker, world.time)
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_NONE, "A round starting on a server with no campaign moved the campaign state.")
	TEST_ASSERT_NULL(SScampaign.chapter_outcome, "A round starting on a server with no campaign opened a chapter.")

	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_ACTIVE, "Creating a campaign did not start its first chapter.")
	TEST_ASSERT_NOTNULL(SScampaign.chapter_outcome, "A chapter began with no result record for anything to report into.")
	TEST_ASSERT_EQUAL(SScampaign.manifest.chapter, 1, "A new campaign did not start at chapter 1.")
	TEST_ASSERT(length(SScampaign.manifest.planet_record), "A new campaign was created with no planet to build on.")
	TEST_ASSERT(fexists(campaign_chapter_open_path(test_campaign_id, "generation-1", 1)), "Starting a campaign left no record that its first chapter was opened.")

	// It exists on disk, which is what makes the next boot pick it up.
	var/datum/campaign_manifest/on_disk = load_active_campaign_manifest(test_campaign_id)
	allocated += on_disk
	TEST_ASSERT_NOTNULL(on_disk, "A created campaign was not written to disk, so it would vanish at reboot.")
	TEST_ASSERT_EQUAL(on_disk.generation_id, "generation-1", "A new campaign did not start at its first generation.")

	// Starting one on top of a running campaign, or on top of one already on disk, is refused.
	TEST_ASSERT(!SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign was created while one was already running.")
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	SScampaign.manifest = null
	TEST_ASSERT(!SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign was created over one that already existed on disk.")

	// And an id that could not be a directory never gets as far as writing anything.
	TEST_ASSERT(!SScampaign.create_campaign("../escape", "admin-key"), "A campaign was created with an id that escapes its own storage root.")


/**
 * The server has to be able to find the campaign again, under the name it was actually given.
 *
 * This is the failure that made the first working commit invisible: the colony committed perfectly, and the
 * next boot went looking for a campaign called something else, found nothing, and generated a fresh world
 * without a word. A campaign nobody can name again is a lost colony, whatever is on disk.
 */
/datum/unit_test/campaign_failure_path/rimstation_campaign_is_findable_next_boot
	test_campaign_id = "unit-test-findable"

/datum/unit_test/campaign_failure_path/rimstation_campaign_is_findable_next_boot/Run()
	take_campaign()
	fdel(active_campaign_pointer_path())
	TEST_ASSERT_NULL(read_active_campaign_id(), "A server with no pointer named a campaign anyway.")

	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")
	TEST_ASSERT_EQUAL(read_active_campaign_id(), test_campaign_id, "Creating a campaign did not record it as the one this server runs, so the next boot would look for a different one.")
	TEST_ASSERT(test_campaign_id in list_campaign_ids(), "A created campaign was not listed among the campaigns in storage.")

	// Play it to a commit, then boot the way the subsystem does: read the pointer, then evaluate it.
	TEST_ASSERT(SScampaign.resolve_chapter_at_round_end(), "The chapter could not be resolved.")
	TEST_ASSERT_EQUAL(SScampaign.manifest.active_checkpoint_id, "checkpoint-1", "The chapter did not commit.")

	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	SScampaign.manifest = null
	var/booted_id = read_active_campaign_id()
	TEST_ASSERT_EQUAL(booted_id, test_campaign_id, "The next boot would not find the campaign this server was running.")
	TEST_ASSERT_EQUAL(SScampaign.evaluate_boot_state(booted_id), CAMPAIGN_STATE_LOADING, "Booting the recorded campaign did not load it.")
	TEST_ASSERT_EQUAL(SScampaign.select_checkpoint_for_boot(), campaign_checkpoint_path(test_campaign_id, "generation-1", "checkpoint-1"), "The boot after a commit would not load the colony that was committed.")

	// A pointer naming something unusable must not be honoured.
	rustg_file_write(json_encode(list("campaign_id" = "../escape")), active_campaign_pointer_path())
	TEST_ASSERT_NULL(read_active_campaign_id(), "A pointer naming an id that escapes the storage root was honoured.")
	rustg_file_write("{\"campaign_id\": ", active_campaign_pointer_path())
	TEST_ASSERT_NULL(read_active_campaign_id(), "A truncated pointer file was honoured.")


/**
 * The colony core reports a loss into whatever chapter is running, without being told about it.
 *
 * A core is placed during mapload, long before a chapter exists, so anything that assigned the chapter record
 * at creation time would capture null and silently never resolve. That failure is invisible in isolation -
 * the core works perfectly, it just reports to nobody - so the connection is asserted from both ends.
 */
/datum/unit_test/campaign_failure_path/rimstation_campaign_core_reports_loss
	test_campaign_id = "unit-test-core-loss"

/datum/unit_test/campaign_failure_path/rimstation_campaign_core_reports_loss/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	var/obj/structure/colony_core/core = allocate(/obj/structure/colony_core)
	TEST_ASSERT_EQUAL(core.get_chapter_outcome(), SScampaign.chapter_outcome, "A core placed while a campaign runs does not report into that campaign's chapter.")

	core.advance_contest(TRUE, core.capture_duration)
	TEST_ASSERT_EQUAL(core.state, COLONY_CORE_CAPTURED, "The core did not capture, so the loss path is untested.")
	TEST_ASSERT_EQUAL(SScampaign.chapter_outcome.result, COLONY_OUTCOME_FAILURE, "Losing the core recorded no failure against the chapter being played.")

	// Round end acts on that loss: the generation closes and nothing is committed.
	TEST_ASSERT(SScampaign.resolve_chapter_at_round_end(), "Round end did not act on a lost chapter.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_RESET_PENDING, "A lost chapter did not close the generation at round end.")
	TEST_ASSERT(SScampaign.manifest.generation_closed, "A lost chapter left the generation open.")
	TEST_ASSERT_NULL(SScampaign.manifest.active_checkpoint_id, "A lost chapter left a checkpoint pointer behind.")
	TEST_ASSERT(SScampaign.chapter_outcome.touched_persistence, "The campaign acted on an outcome without marking it as acted on.")
	TEST_ASSERT(!("checkpoint-1" in list_campaign_checkpoint_ids(test_campaign_id, "generation-1")), "A lost chapter committed a checkpoint of the ruined colony.")


/**
 * A colony nothing managed to take is a colony that held.
 *
 * This is the only route by which a campaign advances at all, so the round simply ending has to count as a
 * win. The alternative - treating an ordinary round end as undecided - would mean a colony could never keep
 * anything it built, which is the entire point of the campaign.
 */
/datum/unit_test/campaign_failure_path/rimstation_campaign_held_colony_commits
	test_campaign_id = "unit-test-held"

/datum/unit_test/campaign_failure_path/rimstation_campaign_held_colony_commits/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")
	TEST_ASSERT(!SScampaign.chapter_outcome.is_resolved(), "The chapter was decided before anything happened in it.")

	TEST_ASSERT(SScampaign.resolve_chapter_at_round_end(), "Round end did not act on a chapter nobody decided.")
	TEST_ASSERT_EQUAL(SScampaign.chapter_outcome.result, COLONY_OUTCOME_SUCCESS, "A colony that was never taken did not count as having held.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_INTERMISSION, "A colony that held was not committed at round end.")
	TEST_ASSERT_EQUAL(SScampaign.manifest.chapter, 2, "A committed chapter did not advance the campaign.")
	TEST_ASSERT_EQUAL(SScampaign.manifest.active_checkpoint_id, "checkpoint-1", "A committed chapter did not become the campaign's checkpoint.")
	TEST_ASSERT("checkpoint-1" in list_campaign_checkpoint_ids(test_campaign_id, "generation-1"), "A committed chapter wrote no checkpoint to disk.")
	TEST_ASSERT(fexists(campaign_chapter_end_path(test_campaign_id, "generation-1", 1)), "A committed chapter left no clean-end record, so the next boot would read it as a crash.")

	// Which is what the next boot finds.
	var/datum/campaign_manifest/on_disk = load_active_campaign_manifest(test_campaign_id)
	allocated += on_disk
	TEST_ASSERT_EQUAL(on_disk.active_checkpoint_id, "checkpoint-1", "The committed colony did not reach disk.")
	TEST_ASSERT_EQUAL(on_disk.chapter, 2, "The advanced chapter did not reach disk.")
	TEST_ASSERT_EQUAL(SScampaign.select_checkpoint_for_boot(), campaign_checkpoint_path(test_campaign_id, "generation-1", "checkpoint-1"), "The boot after a held chapter would not load the colony it committed.")

	// The chapter after it opens against the same generation rather than starting the campaign over.
	SScampaign.on_round_starting(SSticker, world.time)
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_ACTIVE, "The round after a commit did not start the next chapter.")
	TEST_ASSERT_EQUAL(SScampaign.manifest.generation_id, "generation-1", "The chapter after a commit started a different generation.")
	TEST_ASSERT(!SScampaign.chapter_outcome.is_resolved(), "The next chapter inherited the previous chapter's result.")
