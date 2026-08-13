/**
 * A checkpoint that stages everything except the map.
 *
 * World saving is blocked outright during tests - a save written by a test run gets restored over the next one
 * - so the map write is replaced by the marker a finished save leaves behind. Artifact validation, the
 * completion marker and the commit all still run for real, which is where the interesting failures live.
 */
/datum/campaign_checkpoint/unit_test_stub

/datum/campaign_checkpoint/unit_test_stub/stage_world_artifacts()
	rustg_file_write(json_encode(list("save_completed" = TRUE)), "[artifact_path]/[SSworld_save.get_save_completion_marker()]")
	return artifact_path


/**
 * Shared scaffolding for the four ways a chapter can stop.
 *
 * Each of these drives the real subsystem, so each has to hand it back exactly as it found it. A failed
 * assertion returns from Run() immediately, so the restore lives in Destroy() where it cannot be skipped.
 */
/datum/unit_test/campaign_failure_path
	abstract_type = /datum/unit_test/campaign_failure_path
	/// Campaign id this test owns. Everything it writes lives under it and is deleted with it.
	var/test_campaign_id
	var/saved_state
	var/datum/campaign_manifest/saved_manifest
	var/saved_checkpoint_type
	var/saved_recovery_selection

/// Puts SScampaign into a known empty state and takes custody of it for the duration of the test.
/datum/unit_test/campaign_failure_path/proc/take_campaign()
	saved_state = SScampaign.campaign_state
	saved_manifest = SScampaign.manifest
	saved_checkpoint_type = SScampaign.checkpoint_type
	saved_recovery_selection = SScampaign.recovery_selection

	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	SScampaign.manifest = null
	SScampaign.recovery_selection = null
	SScampaign.recovery_selected_by = null
	SScampaign.checkpoint_type = /datum/campaign_checkpoint/unit_test_stub

/// Plays one chapter to a successful commit, leaving a committed checkpoint for the test to work against.
/datum/unit_test/campaign_failure_path/proc/commit_one_chapter(datum/campaign_manifest/manifest)
	SScampaign.manifest = manifest
	if(!SScampaign.begin_load(manifest) || !SScampaign.begin_chapter())
		return FALSE

	var/datum/colony_chapter_outcome/won = new
	won.resolve(COLONY_OUTCOME_SUCCESS, "the raid was repelled")
	. = SScampaign.request_commit(won) && SScampaign.perform_commit()
	qdel(won)

/datum/unit_test/campaign_failure_path/Destroy()
	SScampaign.campaign_state = saved_state
	SScampaign.manifest = saved_manifest
	SScampaign.checkpoint_type = saved_checkpoint_type
	SScampaign.recovery_selection = saved_recovery_selection
	SScampaign.recovery_selected_by = null
	saved_manifest = null

	var/campaign_root = campaign_path(test_campaign_id)
	if(campaign_root)
		fdel("[campaign_root]/")
	return ..()


/**
 * A won chapter is preserved, and preserved on disk rather than only in memory.
 *
 * The commit is the only thing that carries a colony from one round to the next, so this walks the whole
 * ordinary path and then reloads the manifest to prove the next boot would find the same checkpoint.
 */
/datum/unit_test/campaign_failure_path/rimstation_campaign_success_commit
	test_campaign_id = "unit-test-success"

/datum/unit_test/campaign_failure_path/rimstation_campaign_success_commit/Run()
	take_campaign()

	var/datum/campaign_manifest/manifest = new(test_campaign_id, "generation-1")
	allocated += manifest
	SScampaign.manifest = manifest

	TEST_ASSERT(SScampaign.begin_load(manifest), "The campaign refused to load a valid manifest.")
	TEST_ASSERT(SScampaign.begin_chapter(), "The campaign refused to begin a chapter.")
	TEST_ASSERT(fexists(campaign_chapter_open_path(test_campaign_id, "generation-1", 1)), "Starting a chapter left no record that it was opened, so an interrupted round could not be told from one that never started.")

	var/datum/colony_chapter_outcome/won = new
	allocated += won
	won.resolve(COLONY_OUTCOME_SUCCESS, "the raid was repelled")
	TEST_ASSERT(SScampaign.request_commit(won), "A successful chapter was refused a commit.")
	TEST_ASSERT(SScampaign.perform_commit(), "A successful chapter did not commit.")

	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_INTERMISSION, "A completed commit did not leave the campaign in intermission.")
	TEST_ASSERT_EQUAL(manifest.active_checkpoint_id, "checkpoint-1", "The commit did not point the campaign at the checkpoint it just wrote.")
	TEST_ASSERT_EQUAL(manifest.chapter, 2, "The chapter did not advance after a commit.")
	TEST_ASSERT_EQUAL(manifest.last_outcome, COLONY_OUTCOME_SUCCESS, "A committed chapter was not recorded as a success.")
	TEST_ASSERT(fexists(campaign_chapter_end_path(test_campaign_id, "generation-1", 1)), "A committed chapter left no clean-end record, so the next boot would read it as a crash.")

	// The commit only counts if it survives the process that made it.
	var/datum/campaign_manifest/reloaded = load_active_campaign_manifest(test_campaign_id)
	allocated += reloaded
	TEST_ASSERT_NOTNULL(reloaded, "A committed campaign could not be loaded back off disk.")
	TEST_ASSERT_EQUAL(reloaded.active_checkpoint_id, "checkpoint-1", "The committed checkpoint did not reach disk, so the colony would be gone next boot.")
	TEST_ASSERT_EQUAL(reloaded.chapter, 2, "The advanced chapter did not reach disk.")
	TEST_ASSERT(!reloaded.generation_closed, "A won chapter closed the generation.")

	// And the boot after it loads exactly that checkpoint, without consulting anything else on disk.
	TEST_ASSERT_EQUAL(SScampaign.select_checkpoint_for_boot(), campaign_checkpoint_path(test_campaign_id, "generation-1", "checkpoint-1"), "The boot after a commit did not select the checkpoint that was committed.")
	TEST_ASSERT(SScampaign.chapter_ended_cleanly(reloaded), "A committed chapter was reported as not having ended cleanly.")


/**
 * A lost chapter commits nothing, and the loss outlives the round that produced it.
 *
 * The failure this guards is a defeat that exists only in memory: the manifest on disk would still name the
 * checkpoint, and the next boot would quietly reload the colony that was just lost.
 */
/datum/unit_test/campaign_failure_path/rimstation_campaign_defeat_no_commit
	test_campaign_id = "unit-test-defeat"

/datum/unit_test/campaign_failure_path/rimstation_campaign_defeat_no_commit/Run()
	take_campaign()

	var/datum/campaign_manifest/manifest = new(test_campaign_id, "generation-1")
	allocated += manifest
	TEST_ASSERT(commit_one_chapter(manifest), "The setup chapter could not be committed.")

	// Chapter two is the one that is lost.
	TEST_ASSERT(SScampaign.begin_load(manifest), "The campaign refused to load for a second chapter.")
	TEST_ASSERT(SScampaign.begin_chapter(), "The campaign refused to begin a second chapter.")

	var/datum/colony_chapter_outcome/lost = new
	allocated += lost
	lost.resolve(COLONY_OUTCOME_FAILURE, "the colony core was captured")
	TEST_ASSERT(!SScampaign.request_commit(lost), "A lost chapter was allowed to request a commit.")
	TEST_ASSERT(!SScampaign.perform_commit(), "A commit ran for a chapter that was never approved for one.")

	TEST_ASSERT(SScampaign.declare_defeat("the colony core was captured"), "The campaign refused to accept a defeat.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_RESET_PENDING, "Defeat did not leave the campaign waiting for a new generation.")
	TEST_ASSERT(manifest.generation_closed, "Defeat did not close the generation.")
	TEST_ASSERT_NULL(manifest.active_checkpoint_id, "Defeat left the checkpoint pointer intact, so the lost colony could load again.")

	// Nothing was staged for the chapter that was lost.
	var/list/checkpoints = list_campaign_checkpoint_ids(test_campaign_id, "generation-1")
	TEST_ASSERT(!("checkpoint-2" in checkpoints), "Defeat wrote a checkpoint for the chapter it lost.")
	TEST_ASSERT("checkpoint-1" in checkpoints, "Defeat deleted the checkpoint the colony had already earned.")

	// The loss is recorded where the next boot will read it.
	TEST_ASSERT(fexists(campaign_closure_path(test_campaign_id, "generation-1")), "Defeat left no closure record on disk.")
	TEST_ASSERT(fexists(campaign_chapter_end_path(test_campaign_id, "generation-1", 2)), "A lost chapter left no end record, so it would be mistaken for a crash.")

	var/datum/campaign_manifest/reloaded = load_active_campaign_manifest(test_campaign_id)
	allocated += reloaded
	TEST_ASSERT_NOTNULL(reloaded, "The campaign could not be loaded back after a defeat.")
	TEST_ASSERT(reloaded.generation_closed, "The defeat existed only in memory; the next boot would load the lost colony again.")
	TEST_ASSERT_NULL(reloaded.active_checkpoint_id, "The manifest on disk still points at the checkpoint of a lost generation.")
	TEST_ASSERT_NULL(SScampaign.select_checkpoint_for_boot(), "A defeated generation still selected a checkpoint to load.")

	// The closure record states why it happened once, and is not restated afterwards.
	TEST_ASSERT(SScampaign.write_generation_closure("a different reason entirely", "checkpoint-1"), "Rewriting a closure record reported failure instead of leaving the original alone.")
	var/list/closure = safely_decode_json(rustg_file_read(campaign_closure_path(test_campaign_id, "generation-1")))
	TEST_ASSERT_NOTNULL(closure, "The closure record could not be read back.")
	TEST_ASSERT_EQUAL(closure["reason"], "the colony core was captured", "A second defeat overwrote the record of why the generation was actually lost.")


/**
 * A new generation starts from nothing, however much valid history is sitting on disk.
 *
 * This is the resurrection case. A previous generation's checkpoint is complete, valid and still present -
 * defeat never deletes it - so the only thing standing between it and being loaded is that nothing goes
 * looking for it.
 */
/datum/unit_test/campaign_failure_path/rimstation_campaign_older_save_no_resurrection
	test_campaign_id = "unit-test-resurrection"

/datum/unit_test/campaign_failure_path/rimstation_campaign_older_save_no_resurrection/Run()
	take_campaign()

	// A colony that survived its first chapter and lost its second.
	var/datum/campaign_manifest/manifest = new(test_campaign_id, "generation-1")
	allocated += manifest
	TEST_ASSERT(commit_one_chapter(manifest), "The setup chapter could not be committed.")
	TEST_ASSERT(SScampaign.begin_load(manifest), "The campaign refused to load for a second chapter.")
	TEST_ASSERT(SScampaign.begin_chapter(), "The campaign refused to begin a second chapter.")
	TEST_ASSERT(SScampaign.declare_defeat("the colony core was captured"), "The campaign refused to accept a defeat.")

	// The old checkpoint is intact and would load perfectly well if anything asked for it.
	var/old_checkpoint_path = campaign_checkpoint_path(test_campaign_id, "generation-1", "checkpoint-1")
	TEST_ASSERT(fexists("[old_checkpoint_path]/[CHECKPOINT_COMPLETION_MARKER]"), "Defeat deleted the previous checkpoint rather than leaving it for inspection.")

	// Reboot.
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	SScampaign.manifest = null
	TEST_ASSERT_EQUAL(SScampaign.evaluate_boot_state(test_campaign_id), CAMPAIGN_STATE_LOADING, "Booting on a closed generation did not open a new one.")

	var/datum/campaign_manifest/fresh = SScampaign.manifest
	TEST_ASSERT_NOTNULL(fresh, "Booting on a closed generation produced no campaign at all.")
	TEST_ASSERT_EQUAL(fresh.generation_id, "generation-2", "The new generation did not take the next generation id.")
	TEST_ASSERT_EQUAL(fresh.generation_number, 2, "The new generation was not counted.")
	TEST_ASSERT_EQUAL(fresh.chapter, 1, "The new generation inherited the chapter count of the one that was lost.")
	TEST_ASSERT_NULL(fresh.active_checkpoint_id, "A new generation inherited a checkpoint from the generation before it.")
	TEST_ASSERT_NULL(SScampaign.select_checkpoint_for_boot(), "A new generation selected a checkpoint belonging to a lost one.")

	// It is a different world, not the same one with the buildings knocked down.
	var/list/lost_world = SScampaign.build_generation_planet_record(test_campaign_id, 1)
	TEST_ASSERT(length(fresh.planet_record), "A new generation was created without a planet to build on.")
	TEST_ASSERT_NOTEQUAL(fresh.planet_record["root_seed"], lost_world["root_seed"], "A new generation was placed on the world the campaign had just lost.")

	// The lost generation's checkpoints are not reachable from the new one, by any route.
	var/list/snapshots = SScampaign.list_recovery_snapshots()
	TEST_ASSERT(!length(snapshots), "A new generation offered a lost generation's checkpoints as recovery snapshots.")

	// And structurally: campaign checkpoints sit outside the autosave pool, so the newest-save scan that would
	// happily load one never sees them in the first place.
	TEST_ASSERT(findtext(CAMPAIGN_STORAGE_ROOT, MAP_PERSISTENT_DIRECTORY) != 1, "Campaign checkpoints live inside the autosave pool, where scanning for the newest save would find and load a lost colony.")


/**
 * A killed server is an infrastructure fault, not a lost colony.
 *
 * The signature is an opened chapter with no ending of any kind. The colony has to come back from its last
 * committed checkpoint, and the generation has to stay open.
 */
/datum/unit_test/campaign_failure_path/rimstation_campaign_crash_recovery
	test_campaign_id = "unit-test-crash"

/datum/unit_test/campaign_failure_path/rimstation_campaign_crash_recovery/Run()
	take_campaign()

	var/datum/campaign_manifest/manifest = new(test_campaign_id, "generation-1")
	allocated += manifest
	TEST_ASSERT(commit_one_chapter(manifest), "The setup chapter could not be committed.")

	// Chapter two starts and the process dies: no commit, no defeat, no ending at all.
	TEST_ASSERT(SScampaign.begin_load(manifest), "The campaign refused to load for a second chapter.")
	TEST_ASSERT(SScampaign.begin_chapter(), "The campaign refused to begin a second chapter.")

	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	SScampaign.manifest = null
	TEST_ASSERT_EQUAL(SScampaign.evaluate_boot_state(test_campaign_id), CAMPAIGN_STATE_RECOVERY, "An interrupted chapter was not treated as recovery.")

	var/datum/campaign_manifest/recovered = SScampaign.manifest
	TEST_ASSERT_NOTNULL(recovered, "Recovery produced no campaign to recover.")
	TEST_ASSERT(!recovered.generation_closed, "A crash closed the generation, turning an infrastructure fault into a lost colony.")
	TEST_ASSERT_EQUAL(recovered.active_checkpoint_id, "checkpoint-1", "Recovery cleared the committed checkpoint pointer.")
	TEST_ASSERT(!fexists(campaign_closure_path(test_campaign_id, "generation-1")), "A crash wrote a generation closure record.")
	TEST_ASSERT_EQUAL(SScampaign.select_checkpoint_for_boot(), campaign_checkpoint_path(test_campaign_id, "generation-1", "checkpoint-1"), "Recovery did not default to the last committed checkpoint.")

	// Recovery is a state the campaign plays on from, not one it is stuck in.
	TEST_ASSERT(SScampaign.begin_chapter(), "A recovered campaign could not start its chapter.")

	// A chapter that did end is not recovered from on the next boot.
	TEST_ASSERT(SScampaign.mark_chapter_ended(recovered.chapter, COLONY_OUTCOME_SUCCESS, "the chapter finished"), "A chapter ending could not be recorded.")
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	SScampaign.manifest = null
	TEST_ASSERT_EQUAL(SScampaign.evaluate_boot_state(test_campaign_id), CAMPAIGN_STATE_LOADING, "A chapter that ended cleanly was still treated as an interrupted one.")


/**
 * An admin ending the round early is recovery too, and is recorded as having been a person.
 *
 * Working snapshots exist on disk beside the committed checkpoint. They are reachable only by an explicit
 * selection that validates them, and selecting one must not disturb what is actually committed.
 */
/datum/unit_test/campaign_failure_path/rimstation_campaign_admin_abort_recovery
	test_campaign_id = "unit-test-abort"

/datum/unit_test/campaign_failure_path/rimstation_campaign_admin_abort_recovery/Run()
	take_campaign()

	var/datum/campaign_manifest/manifest = new(test_campaign_id, "generation-1")
	allocated += manifest
	TEST_ASSERT(commit_one_chapter(manifest), "The setup chapter could not be committed.")
	TEST_ASSERT(SScampaign.begin_load(manifest), "The campaign refused to load for a second chapter.")
	TEST_ASSERT(SScampaign.begin_chapter(), "The campaign refused to begin a second chapter.")

	TEST_ASSERT(SScampaign.admin_abort("ending the round early", "admin-key"), "The campaign refused an admin abort.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_RECOVERY, "An admin abort did not enter recovery.")
	TEST_ASSERT(!manifest.generation_closed, "An admin abort closed the generation, costing a colony that was never lost.")
	TEST_ASSERT_EQUAL(manifest.active_checkpoint_id, "checkpoint-1", "An admin abort cleared the committed checkpoint pointer.")
	TEST_ASSERT(!fexists(campaign_closure_path(test_campaign_id, "generation-1")), "An admin abort wrote a generation closure record.")
	TEST_ASSERT(findtext(SScampaign.last_state_reason, "admin-key"), "An admin abort did not record who performed it.")

	// A snapshot that does not exist, or was never finished, cannot be recovered from.
	TEST_ASSERT(!SScampaign.select_recovery_snapshot("checkpoint-does-not-exist", "admin-key"), "A snapshot that does not exist was selected for recovery.")
	var/datum/campaign_checkpoint/unit_test_stub/unfinished = new(test_campaign_id, "generation-1", "checkpoint-unfinished")
	allocated += unfinished
	unfinished.stage_world_artifacts()
	TEST_ASSERT(!SScampaign.select_recovery_snapshot("checkpoint-unfinished", "admin-key"), "A checkpoint that never finished being written was selected for recovery.")

	// A finished but uncommitted snapshot is exactly what recovery is for.
	var/datum/campaign_checkpoint/unit_test_stub/snapshot = new(test_campaign_id, "generation-1", "checkpoint-2")
	allocated += snapshot
	TEST_ASSERT(snapshot.stage(manifest), "A recovery snapshot could not be staged.")
	TEST_ASSERT("checkpoint-2" in SScampaign.list_recovery_snapshots(), "A complete checkpoint was not offered as a recovery snapshot.")

	TEST_ASSERT(SScampaign.select_recovery_snapshot("checkpoint-2", "admin-key"), "A complete recovery snapshot was refused.")
	TEST_ASSERT_EQUAL(SScampaign.recovery_selected_by, "admin-key", "The recovery selection did not record who made it.")
	TEST_ASSERT_EQUAL(SScampaign.select_checkpoint_for_boot(), campaign_checkpoint_path(test_campaign_id, "generation-1", "checkpoint-2"), "The selected recovery snapshot was not the one that would load.")

	// Choosing a snapshot changes what this boot loads and nothing else.
	var/datum/campaign_manifest/reloaded = load_active_campaign_manifest(test_campaign_id)
	allocated += reloaded
	TEST_ASSERT_EQUAL(reloaded.active_checkpoint_id, "checkpoint-1", "An admin recovery selection overwrote the committed checkpoint pointer.")
	TEST_ASSERT(!reloaded.generation_closed, "An admin recovery selection closed the generation.")
