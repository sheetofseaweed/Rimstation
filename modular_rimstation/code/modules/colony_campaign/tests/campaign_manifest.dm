/**
 * The manifest is the only thing standing between a lost town and a resurrected one.
 *
 * These assertions are about contradictions rather than field values: a checkpoint pointer with no generation
 * to own it, and a closed generation still claiming a live checkpoint. The second is the exact shape of
 * "defeat quietly restored the old town next boot".
 */
/datum/unit_test/rimstation_campaign_manifest

/datum/unit_test/rimstation_campaign_manifest/Run()
	var/datum/campaign_manifest/manifest = new("campaign-alpha", "generation-1")
	allocated += manifest
	manifest.active_checkpoint_id = "checkpoint-1"
	TEST_ASSERT(manifest.validate(), "A well-formed manifest was rejected.")

	// JSON round trip has to reconstruct the same campaign, or a reboot loads a different town.
	var/list/decoded = json_decode(json_encode(manifest.serialize()))
	var/datum/campaign_manifest/restored = new
	allocated += restored
	TEST_ASSERT(restored.deserialize(decoded), "A well-formed manifest was refused on load.")
	TEST_ASSERT(manifest.equals(restored), "A manifest did not survive a JSON round trip.")

	// A closed generation must never still point at a checkpoint.
	var/datum/campaign_manifest/contradictory = new("campaign-alpha", "generation-1")
	allocated += contradictory
	contradictory.active_checkpoint_id = "checkpoint-1"
	contradictory.generation_closed = TRUE
	TEST_ASSERT(!contradictory.validate(), "A closed generation was allowed to keep an active checkpoint, which would resurrect a lost town.")

	// Rejected records must not partially overwrite a good manifest.
	var/list/bad_schema = decoded.Copy()
	bad_schema["schema_version"] = CAMPAIGN_MANIFEST_SCHEMA_VERSION + 1
	var/datum/campaign_manifest/guarded = new("campaign-beta", "generation-9")
	allocated += guarded
	TEST_ASSERT(!guarded.deserialize(bad_schema), "A manifest from an unknown future schema was accepted.")
	TEST_ASSERT_EQUAL(guarded.campaign_id, "campaign-beta", "A refused manifest still overwrote the campaign id.")
	TEST_ASSERT_EQUAL(guarded.generation_id, "generation-9", "A refused manifest still overwrote the generation id.")

	// Missing identity is not loadable.
	var/list/no_generation = decoded.Copy()
	no_generation["generation_id"] = null
	TEST_ASSERT(!guarded.deserialize(no_generation), "A manifest with no generation id was accepted.")


/**
 * Campaign IDs become directory names, so they are validated as paths and not just as strings.
 */
/datum/unit_test/rimstation_campaign_id_safety

/datum/unit_test/rimstation_campaign_id_safety/Run()
	TEST_ASSERT(is_safe_campaign_id("campaign-alpha"), "A plain campaign id was rejected.")
	TEST_ASSERT(is_safe_campaign_id("2026-08-11_UTC_12.00.00"), "A timestamp-style id was rejected.")

	// Each of these would let a manifest address a directory outside its own campaign.
	var/list/unsafe_ids = list(
		"..",
		"../escape",
		"campaign/../../etc",
		"campaign/nested",
		"campaign\\nested",
		"campaign id",
		"",
		null,
	)
	for(var/unsafe in unsafe_ids)
		TEST_ASSERT(!is_safe_campaign_id(unsafe), "The unsafe campaign id '[unsafe]' was accepted, which could build a path outside the campaign directory.")

	var/datum/campaign_manifest/traversing = new("campaign-alpha", "../elsewhere")
	allocated += traversing
	TEST_ASSERT(!traversing.validate(), "A manifest with a traversing generation id was accepted.")


/**
 * The lifecycle is what keeps a win, a loss and a crash from blurring together.
 *
 * The transition that matters most is the one that must not exist: there is no path from defeated back to
 * active, so a lost generation cannot be quietly resumed.
 */
/datum/unit_test/rimstation_campaign_lifecycle

/datum/unit_test/rimstation_campaign_lifecycle/Run()
	var/original_state = SScampaign.campaign_state
	var/datum/campaign_manifest/original_manifest = SScampaign.manifest

	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	SScampaign.manifest = null

	var/datum/campaign_manifest/manifest = new("campaign-test", "generation-1")
	allocated += manifest
	manifest.active_checkpoint_id = "checkpoint-1"

	// Illegal transitions must not mutate state.
	TEST_ASSERT(!SScampaign.set_campaign_state(CAMPAIGN_STATE_ACTIVE, "skipping load"), "The campaign jumped straight to active without loading.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_NONE, "A refused transition still changed the campaign state.")
	TEST_ASSERT(!SScampaign.set_campaign_state("wandering", "nonsense"), "The campaign accepted a state outside its own vocabulary.")

	// The ordinary path through a successful chapter.
	TEST_ASSERT(SScampaign.begin_load(manifest), "The campaign refused to begin loading a valid manifest.")
	TEST_ASSERT(SScampaign.begin_chapter(), "The campaign refused to begin a chapter after loading.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_ACTIVE, "The campaign did not become active.")

	// Only an explicitly successful outcome may commit.
	var/datum/colony_chapter_outcome/pending = new
	allocated += pending
	TEST_ASSERT(!SScampaign.request_commit(pending), "A pending chapter outcome was allowed to commit.")
	TEST_ASSERT(!SScampaign.request_commit(null), "A commit with no outcome at all was allowed.")

	var/datum/colony_chapter_outcome/lost = new
	allocated += lost
	lost.resolve(COLONY_OUTCOME_FAILURE, "the core fell")
	TEST_ASSERT(!SScampaign.request_commit(lost), "A failed chapter was allowed to commit, which would promote a ruined town.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_ACTIVE, "A refused commit still moved the campaign out of active.")

	var/datum/colony_chapter_outcome/won = new
	allocated += won
	won.resolve(COLONY_OUTCOME_SUCCESS, "the raid was repelled")
	TEST_ASSERT(SScampaign.request_commit(won), "A successful chapter was refused a commit.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_COMMITTING, "A successful commit did not enter the committing state.")

	SScampaign.campaign_state = original_state
	SScampaign.manifest = original_manifest


/// Defeat closes a generation for good; recovery leaves everything exactly where it was.
/datum/unit_test/rimstation_campaign_defeat_versus_recovery

/datum/unit_test/rimstation_campaign_defeat_versus_recovery/Run()
	var/original_state = SScampaign.campaign_state
	var/datum/campaign_manifest/original_manifest = SScampaign.manifest

	// Defeat: the checkpoint pointer is cleared and the generation is closed.
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	var/datum/campaign_manifest/losing = new("campaign-test", "generation-1")
	allocated += losing
	losing.active_checkpoint_id = "checkpoint-1"
	SScampaign.manifest = losing
	SScampaign.begin_load(losing)
	SScampaign.begin_chapter()

	TEST_ASSERT(SScampaign.declare_defeat("the colony core was captured"), "The campaign refused to accept a defeat.")
	TEST_ASSERT(losing.generation_closed, "Defeat did not close the generation.")
	TEST_ASSERT_NULL(losing.active_checkpoint_id, "Defeat left the checkpoint pointer intact, so the lost town could load again.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_RESET_PENDING, "Defeat did not leave the campaign waiting for a new generation.")
	TEST_ASSERT(losing.validate(), "The manifest was left in a contradictory state after defeat.")

	// There is no way back from defeat.
	TEST_ASSERT(!SScampaign.set_campaign_state(CAMPAIGN_STATE_ACTIVE, "resuming a lost generation"), "A defeated campaign was allowed to become active again.")

	// Recovery: an abnormal ending must not touch the checkpoint at all.
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	var/datum/campaign_manifest/interrupted = new("campaign-test", "generation-2")
	allocated += interrupted
	interrupted.active_checkpoint_id = "checkpoint-7"
	SScampaign.manifest = interrupted
	SScampaign.begin_load(interrupted)
	SScampaign.begin_chapter()

	TEST_ASSERT(SScampaign.enter_recovery("the server was killed mid-chapter"), "The campaign refused to enter recovery.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_RECOVERY, "The campaign did not enter recovery.")
	TEST_ASSERT(!interrupted.generation_closed, "A crash closed the generation, which would treat an infrastructure fault as a defeat.")
	TEST_ASSERT_EQUAL(interrupted.active_checkpoint_id, "checkpoint-7", "Recovery cleared the checkpoint pointer, losing the committed town.")

	// And recovery can hand back to a normal chapter.
	TEST_ASSERT(SScampaign.set_campaign_state(CAMPAIGN_STATE_ACTIVE, "recovered"), "A recovered campaign could not resume.")

	SScampaign.campaign_state = original_state
	SScampaign.manifest = original_manifest
