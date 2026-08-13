/**
 * The ordinary round-end save runs on ordinary servers and nowhere else.
 *
 * Two failures sit behind this. A defeated campaign that still writes a timestamped save leaves the ruined
 * colony in the pool for the newest-save scan to pick up, which is defeat undone by an autosave. A successful
 * one that also writes there buries its own committed checkpoint under a newer save of the same ground.
 * Neither is visible at the point it happens; both surface a reboot later as the wrong world.
 */
/datum/unit_test/rimstation_campaign_roundend_save_policy
	var/test_campaign_id = "unit-test-roundend"
	var/saved_state
	var/datum/campaign_manifest/saved_manifest
	var/datum/colony_chapter_outcome/saved_outcome

/datum/unit_test/rimstation_campaign_roundend_save_policy/Run()
	saved_state = SScampaign.campaign_state
	saved_manifest = SScampaign.manifest
	saved_outcome = SScampaign.chapter_outcome

	// With no campaign at all, the inherited behaviour is exactly what it was: the config flag decides.
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	SScampaign.manifest = null
	TEST_ASSERT_EQUAL(SScampaign.should_run_legacy_roundend_save(), CONFIG_GET(flag/persistent_save_enabled), "A server with no campaign did not fall back to the ordinary persistence flag.")

	// Every campaign state refuses it, including the ones that look idle. Driven off the transition table so a
	// state added later cannot quietly skip this.
	var/datum/campaign_manifest/manifest = new(test_campaign_id, "generation-1")
	allocated += manifest
	SScampaign.manifest = manifest

	var/list/transitions = CAMPAIGN_STATE_TRANSITIONS
	for(var/known_state in transitions)
		SScampaign.campaign_state = known_state
		TEST_ASSERT(!SScampaign.should_run_legacy_roundend_save(), "A campaign in state '[known_state]' still ran the ordinary round-end save, which writes its colony into the shared autosave pool.")

	// A chapter that already reached a conclusion is not second-guessed on the way out.
	for(var/decided_state in list(CAMPAIGN_STATE_INTERMISSION, CAMPAIGN_STATE_RESET_PENDING, CAMPAIGN_STATE_DEFEATED, CAMPAIGN_STATE_RECOVERY))
		SScampaign.campaign_state = decided_state
		TEST_ASSERT(!SScampaign.resolve_chapter_at_round_end(), "Round end overrode a chapter that had already been decided as '[decided_state]'.")
		TEST_ASSERT_EQUAL(SScampaign.campaign_state, decided_state, "Round end moved a campaign that had already decided its chapter.")

	// A chapter with no result record at all is recovery, not a guess in either direction.
	SScampaign.campaign_state = CAMPAIGN_STATE_ACTIVE
	SScampaign.chapter_outcome = null
	TEST_ASSERT(SScampaign.resolve_chapter_at_round_end(), "A round ending with no chapter result recorded nothing.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_RECOVERY, "A missing chapter result was not treated as recovery.")
	TEST_ASSERT(!manifest.generation_closed, "A missing chapter result closed the generation, costing a colony that was never lost.")

	// And with no campaign, round end has nothing to say at all.
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	SScampaign.manifest = null
	TEST_ASSERT(!SScampaign.resolve_chapter_at_round_end(), "Round end acted on a server that is not running a campaign.")

/datum/unit_test/rimstation_campaign_roundend_save_policy/Destroy()
	SScampaign.campaign_state = saved_state
	SScampaign.manifest = saved_manifest
	SScampaign.chapter_outcome = saved_outcome
	saved_manifest = null
	saved_outcome = null

	var/campaign_root = campaign_path(test_campaign_id)
	if(campaign_root)
		fdel("[campaign_root]/")
	return ..()
