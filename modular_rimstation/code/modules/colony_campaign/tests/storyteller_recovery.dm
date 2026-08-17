/**
 * Recovery is what the colony is owed, and it is only paid back by quiet chapters that went well.
 *
 * The distinction being tested is between *loss*, which is a memory of the last thing and fades on its own,
 * and *recovery*, which is a debt. If recovery fell for any surviving chapter, a colony that wins every raid
 * would be treated as though nothing had been happening to it.
 */
/datum/unit_test/rimstation_story_state_recovery

/datum/unit_test/rimstation_story_state_recovery/Run()
	var/datum/colony_story_state/story = new
	allocated += story

	TEST_ASSERT_EQUAL(story.recovery, 0, "A new campaign starts owed something.")
	TEST_ASSERT_EQUAL(story.recent_loss, 0, "A new campaign starts having lost something.")

	// Things going wrong raise both.
	TEST_ASSERT(story.record_loss(3), "A loss was not recorded.")
	TEST_ASSERT(story.recovery > 0, "Losing something did not entitle the colony to any relief.")
	TEST_ASSERT(story.recent_loss > 0, "Losing something was not remembered.")
	var/recovery_after_loss = story.recovery

	// Nothing recorded is not a loss.
	TEST_ASSERT(!story.record_loss(0), "Nothing happening was recorded as a loss.")
	TEST_ASSERT(!story.record_loss(-5), "Something going well was recorded as a loss.")
	TEST_ASSERT_EQUAL(story.recovery, recovery_after_loss, "A refused loss still moved recovery.")

	// A chapter that went badly does not pay the debt down.
	story.advance_chapter(COLONY_OUTCOME_FAILURE)
	TEST_ASSERT_EQUAL(story.recovery, recovery_after_loss, "A failed chapter reduced what the colony was owed.")

	// Neither does one survived at the cost of a real fight.
	story.advance_chapter(COLONY_OUTCOME_SUCCESS, faced_major_threat = TRUE)
	TEST_ASSERT_EQUAL(story.recovery, recovery_after_loss, "A chapter survived through a major threat was treated as a rest.")
	TEST_ASSERT_EQUAL(story.chapters_since_major_threat(), 0, "A chapter with a major threat was not recorded as one.")

	// A quiet, successful chapter does.
	story.advance_chapter(COLONY_OUTCOME_SUCCESS)
	TEST_ASSERT(story.recovery < recovery_after_loss, "A quiet, successful chapter did not pay down what the colony was owed.")
	TEST_ASSERT(story.chapters_since_major_threat() > 0, "Time since the last serious threat is not counting up.")

	// The campaign ages whatever happens.
	TEST_ASSERT_EQUAL(story.campaign_age, 3, "The campaign did not age once per chapter.")

	// Neither score can be driven out of range, however much happens.
	for(var/i in 1 to 50)
		story.record_loss(10)
	TEST_ASSERT(story.recovery <= 100, "Recovery ran past its ceiling.")
	TEST_ASSERT(story.recent_loss <= 100, "Recent loss ran past its ceiling.")

	for(var/i in 1 to 50)
		story.advance_chapter(COLONY_OUTCOME_SUCCESS)
	TEST_ASSERT(story.recovery >= 0, "Recovery fell below zero.")
	TEST_ASSERT(story.recent_loss >= 0, "Recent loss fell below zero.")


/**
 * Pacing bends the odds and never removes an option entirely.
 *
 * A multiplier that can reach zero retires an event silently, which is indistinguishable from a bug; one that
 * can grow without limit crowds out everything else. Both ends are asserted rather than assumed.
 */
/datum/unit_test/rimstation_story_state_multipliers

/datum/unit_test/rimstation_story_state_multipliers/Run()
	var/datum/colony_story_state/story = new
	allocated += story

	// A campaign owed nothing changes nothing.
	TEST_ASSERT_EQUAL(story.get_event_weight_multiplier(list(TAG_DESTRUCTIVE)), 1, "A settled colony had its disasters weighted differently.")
	TEST_ASSERT_EQUAL(story.get_event_weight_multiplier(list(TAG_POSITIVE)), 1, "A settled colony had its good fortune weighted differently.")
	TEST_ASSERT_EQUAL(story.get_event_weight_multiplier(list()), 1, "An untagged event was weighted by pacing that cannot know anything about it.")

	// A battered one sees fewer disasters and more of everything gentle.
	story.recovery = 100
	var/destructive = story.get_event_weight_multiplier(list(TAG_DESTRUCTIVE))
	var/combat = story.get_event_weight_multiplier(list(TAG_COMBAT))
	var/positive = story.get_event_weight_multiplier(list(TAG_POSITIVE))
	var/neutral = story.get_event_weight_multiplier(list(TAG_NEUTRAL))

	TEST_ASSERT(destructive < 1, "A battered colony was no less likely to be handed a disaster.")
	TEST_ASSERT(combat < 1, "A battered colony was no less likely to be handed a fight.")
	TEST_ASSERT(positive > 1, "A battered colony was no more likely to catch a break.")
	TEST_ASSERT(neutral > 1, "A battered colony was no more likely to be left alone.")

	// Bounded at both ends, at every level of recovery.
	for(var/level in list(0, 10, 40, 75, 100))
		story.recovery = level
		for(var/list/tag_set in list(list(TAG_DESTRUCTIVE), list(TAG_COMBAT), list(TAG_POSITIVE), list(TAG_NEUTRAL)))
			var/multiplier = story.get_event_weight_multiplier(tag_set)
			TEST_ASSERT(multiplier >= COLONY_STORY_MIN_MULTIPLIER, "Pacing weighted an event down to [multiplier], which would retire it silently.")
			TEST_ASSERT(multiplier <= COLONY_STORY_MAX_MULTIPLIER, "Pacing weighted an event up to [multiplier], which would crowd out everything else.")

	// Nothing about this depends on when it is asked.
	story.recovery = 60
	TEST_ASSERT_EQUAL(story.get_event_weight_multiplier(list(TAG_DESTRUCTIVE)), story.get_event_weight_multiplier(list(TAG_DESTRUCTIVE)), "Asking the same question twice gave two answers.")


/**
 * The storyteller reads the colony's state, and legacy rounds are untouched.
 *
 * The second half is the one worth guarding: a campaign changing how an ordinary shift weighs its events would
 * be a fork-wide balance change nobody asked for.
 */
/datum/unit_test/campaign_failure_path/rimstation_story_state_storyteller_binding
	test_campaign_id = "unit-test-story-binding"

/datum/unit_test/campaign_failure_path/rimstation_story_state_storyteller_binding/Run()
	take_campaign()

	// With no campaign, every event weighs exactly what it always did.
	var/datum/round_event_control/colony_incident/environmental/control = new
	allocated += control
	TEST_ASSERT_EQUAL(control.get_campaign_weight_multiplier(), 1, "An event was reweighted with no campaign running.")

	var/datum/round_event_control/legacy = new
	allocated += legacy
	legacy.tags = list(TAG_DESTRUCTIVE)
	TEST_ASSERT_EQUAL(legacy.get_campaign_weight_multiplier(), 1, "A legacy station event was reweighted outside campaign mode.")

	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")
	var/datum/colony_story_state/story = SScampaign.get_story_state()
	TEST_ASSERT_NOTNULL(story, "A running campaign has no pacing state.")

	// A settled colony still changes nothing.
	story.recovery = 0
	TEST_ASSERT_EQUAL(control.get_campaign_weight_multiplier(), 1, "A settled campaign reweighted its events anyway.")
	// Buyable while the colony is settled, so the refusal below is about recovery rather than about timing.
	TEST_ASSERT(control.can_spawn_storyteller_event(50, 30 MINUTES), "A storm was unbuyable even for a settled colony, so the recovery gate below would prove nothing.")

	// A battered one is handed fewer disasters, and the destructive categories stop being buyable outright.
	story.recovery = 100
	TEST_ASSERT(control.get_campaign_weight_multiplier() < 1, "A battered colony was no less likely to be handed a storm.")
	TEST_ASSERT(story.is_recovering_hard(), "A colony at full recovery was not considered to be recovering hard.")
	TEST_ASSERT(!control.can_spawn_storyteller_event(50, 30 MINUTES), "A storm was still buyable for a colony that has been through the worst of it.")

	// But something gentle always remains, which is the point of holding the disasters back.
	var/datum/round_event_control/colony_incident/positive/relief = new
	allocated += relief
	TEST_ASSERT(relief.can_spawn_storyteller_event(50, 30 MINUTES), "Nothing kind was available to a colony that badly needed it.")
	TEST_ASSERT(relief.get_campaign_weight_multiplier() > 1, "Good fortune was not made likelier for a colony that needed it.")


/**
 * What the colony has been through survives the chapter that put it through it.
 *
 * Kept in the manifest's `storyteller_state`, which has been carried since Phase 2 with nothing reading it - so
 * this is a field being filled rather than a schema being grown.
 */
/datum/unit_test/campaign_failure_path/rimstation_story_state_persistence
	test_campaign_id = "unit-test-story-persistence"

/datum/unit_test/campaign_failure_path/rimstation_story_state_persistence/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	// Chapter one goes badly.
	var/datum/colony_story_state/story = SScampaign.get_story_state()
	TEST_ASSERT_NOTNULL(story, "A running campaign has no pacing state.")
	story.record_loss(5)
	SScampaign.sync_story_state()
	var/recovery_owed = story.recovery
	TEST_ASSERT(recovery_owed > 0, "A hard chapter left the colony owed nothing.")

	TEST_ASSERT(SScampaign.resolve_chapter_at_round_end(), "The chapter could not be resolved.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_INTERMISSION, "The chapter did not commit.")

	// The committed campaign carries it.
	var/datum/campaign_manifest/committed = load_active_campaign_manifest(test_campaign_id)
	allocated += committed
	TEST_ASSERT(length(committed.storyteller_state), "A committed campaign carries no pacing state at all.")

	var/datum/colony_story_state/restored = new
	allocated += restored
	TEST_ASSERT(restored.deserialize(committed.storyteller_state), "The pacing state could not be read back off a committed campaign.")
	TEST_ASSERT_EQUAL(restored.campaign_age, story.campaign_age, "Restoring the campaign lost how old it was.")
	TEST_ASSERT(restored.recovery > 0, "Restoring the campaign lost what the colony was owed, so chapter two would be as hard as chapter one.")

	// Chapter two therefore starts knowing what chapter one cost.
	SScampaign.story_state = null
	var/datum/colony_story_state/next_chapter = SScampaign.get_story_state()
	TEST_ASSERT_NOTNULL(next_chapter, "The next chapter has no pacing state.")
	TEST_ASSERT_EQUAL(next_chapter.recovery, restored.recovery, "The next chapter did not begin with what the colony was owed.")
	TEST_ASSERT(next_chapter.campaign_age >= 1, "The next chapter began with the campaign at no age.")

	// Records off disk are clamped rather than trusted.
	var/datum/colony_story_state/guarded = new
	allocated += guarded
	TEST_ASSERT(!guarded.deserialize(null), "A null pacing record was accepted.")
	var/list/absurd = story.serialize()
	absurd["recovery"] = 99999
	absurd["recent_loss"] = -500
	TEST_ASSERT(guarded.deserialize(absurd), "A record with impossible scores was refused outright rather than clamped.")
	TEST_ASSERT(guarded.recovery <= 100, "A record claiming impossible recovery was restored as-is.")
	TEST_ASSERT(guarded.recent_loss >= 0, "A record claiming negative loss was restored as-is.")

	var/list/from_the_future = story.serialize()
	from_the_future["schema_version"] = COLONY_STORY_SCHEMA_VERSION + 1
	TEST_ASSERT(!guarded.deserialize(from_the_future), "A pacing record from an unknown schema was accepted.")


/// A new generation inherits the campaign's age and none of the previous colony's scars.
/datum/unit_test/rimstation_story_state_new_generation

/datum/unit_test/rimstation_story_state_new_generation/Run()
	var/datum/colony_story_state/story = new
	allocated += story

	story.record_loss(8)
	story.advance_chapter(COLONY_OUTCOME_FAILURE, faced_major_threat = TRUE)
	story.record_incident(list("incident_id" = "incident-1", "pressure_change" = 2))
	var/age_before = story.campaign_age

	story.reset_for_new_generation()
	TEST_ASSERT_EQUAL(story.campaign_age, age_before, "A new generation forgot how long the campaign had been running.")
	TEST_ASSERT_EQUAL(story.chapter_age, 0, "A new generation started part-way through its own history.")
	TEST_ASSERT_EQUAL(story.recovery, 0, "A new colony inherited the debt owed to the one that was lost.")
	TEST_ASSERT_EQUAL(story.recent_loss, 0, "A new colony inherited the losses of the one that was lost.")
	TEST_ASSERT(!length(story.recent_incidents), "A new colony inherited the previous one's incidents.")
