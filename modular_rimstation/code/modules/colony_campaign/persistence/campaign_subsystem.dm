/**
 * The only authority over campaign lifecycle.
 *
 * The recon's hardest requirement is that a win, a loss, and a crash are three different things that a
 * round ending cannot blur together. That only holds if exactly one datum decides which of the three
 * happened, so nothing else is allowed to write the active checkpoint pointer or move the state.
 *
 * This subsystem owns policy, not storage: it says *whether* to commit, and the checkpoint code says how.
 */
SUBSYSTEM_DEF(campaign)
	name = "Campaign"
	ss_flags = SS_NO_FIRE
	/// Current lifecycle state. Only ever changed through set_campaign_state().
	var/campaign_state = CAMPAIGN_STATE_NONE
	/// The active campaign record. Null until a campaign is loaded or created.
	var/datum/campaign_manifest/manifest
	/// Why the campaign last entered recovery or defeat, for admin diagnosis.
	var/last_state_reason

/datum/controller/subsystem/campaign/Initialize()
	return SS_INIT_SUCCESS

/// TRUE when moving to `new_state` is legal from where we are now.
/datum/controller/subsystem/campaign/proc/can_transition_to(new_state)
	var/list/transitions = CAMPAIGN_STATE_TRANSITIONS
	var/list/allowed = transitions[campaign_state]
	return (new_state in allowed)

/**
 * Moves the campaign to `new_state`, refusing illegal transitions.
 *
 * Refusal is deliberately silent-but-logged rather than a runtime: an illegal transition usually means two
 * systems raced to end the chapter, and the correct outcome is that the first one wins.
 */
/datum/controller/subsystem/campaign/proc/set_campaign_state(new_state, reason)
	if(!can_transition_to(new_state))
		log_game("Campaign refused transition [campaign_state] -> [new_state]([reason || "no reason"]).")
		return FALSE

	log_game("Campaign [campaign_state] -> [new_state]([reason || "no reason"]).")
	campaign_state = new_state
	if(reason)
		last_state_reason = reason
	return TRUE

/// Begins selecting and loading a committed checkpoint.
/datum/controller/subsystem/campaign/proc/begin_load(datum/campaign_manifest/loading_manifest)
	if(loading_manifest && !loading_manifest.validate())
		// A manifest we cannot trust is a recovery situation, never a fresh start that silently loses a town.
		enter_recovery("the campaign manifest failed validation")
		return FALSE
	if(!set_campaign_state(CAMPAIGN_STATE_LOADING, "loading campaign"))
		return FALSE
	if(loading_manifest)
		manifest = loading_manifest
	return TRUE

/// Marks the loaded campaign as being played.
/datum/controller/subsystem/campaign/proc/begin_chapter()
	if(!manifest)
		enter_recovery("a chapter was started with no campaign manifest")
		return FALSE
	return set_campaign_state(CAMPAIGN_STATE_ACTIVE, "chapter [manifest.chapter] started")

/**
 * Asks for the current chapter to be committed.
 *
 * Only an explicitly successful outcome may commit. Anything else - pending, failure, or a missing outcome -
 * is refused here rather than further down, so that "the round ended" can never reach the promotion code.
 */
/datum/controller/subsystem/campaign/proc/request_commit(datum/colony_chapter_outcome/outcome)
	if(!istype(outcome) || outcome.result != COLONY_OUTCOME_SUCCESS)
		log_game("Campaign refused a commit for outcome '[outcome?.result || "none"]'.")
		return FALSE
	if(!manifest)
		enter_recovery("a commit was requested with no campaign manifest")
		return FALSE
	return set_campaign_state(CAMPAIGN_STATE_COMMITTING, outcome.reason || "chapter succeeded")

/**
 * Closes this generation permanently.
 *
 * Clears the checkpoint pointer so the lost town can never be selected again, but deliberately does not
 * delete anything: the previous checkpoint stays on disk for admin inspection, it simply stops being a load
 * candidate. Phase 2 keeps this non-destructive until the failure-path tests all pass.
 */
/datum/controller/subsystem/campaign/proc/declare_defeat(reason)
	if(!set_campaign_state(CAMPAIGN_STATE_DEFEATED, reason))
		return FALSE
	if(manifest)
		manifest.generation_closed = TRUE
		manifest.closure_reason = reason
		manifest.active_checkpoint_id = null
		manifest.last_outcome = COLONY_OUTCOME_FAILURE
	set_campaign_state(CAMPAIGN_STATE_RESET_PENDING, "generation closed")
	return TRUE

/**
 * Records that something ended abnormally.
 *
 * A crash, an admin abort or a failed load is not a defeat. Keeping them distinct is what stops an
 * infrastructure fault from destroying a town, so this never touches the checkpoint pointer.
 */
/datum/controller/subsystem/campaign/proc/enter_recovery(reason)
	if(!set_campaign_state(CAMPAIGN_STATE_RECOVERY, reason))
		return FALSE
	message_admins("Campaign entered recovery: [reason]. The last committed checkpoint is unchanged.")
	return TRUE

/// TRUE when a campaign is being played, which is what campaign-aware code keys off.
/datum/controller/subsystem/campaign/proc/is_campaign_active()
	return !isnull(manifest) && campaign_state != CAMPAIGN_STATE_NONE

/**
 * FALSE while the world must stop changing underneath a commit.
 *
 * A checkpoint is written by walking the map, so anything that mutates it mid-walk produces a save that
 * matches no moment that ever existed - half the town before a raid arrived, half after. Callers that start
 * new world-changing activity ask here first.
 */
/datum/controller/subsystem/campaign/proc/can_mutate_world()
	return campaign_state != CAMPAIGN_STATE_COMMITTING

/**
 * Runs a full commit: stage the checkpoint, then point the manifest at it.
 *
 * Returns TRUE only if the campaign now points at a new checkpoint. Any failure leaves the previously
 * committed checkpoint live and drops into recovery rather than defeat - a commit that did not work is an
 * infrastructure problem, not a lost colony.
 */
/datum/controller/subsystem/campaign/proc/perform_commit()
	if(campaign_state != CAMPAIGN_STATE_COMMITTING)
		return FALSE
	if(!manifest)
		enter_recovery("a commit ran with no campaign manifest")
		return FALSE

	var/checkpoint_id = "checkpoint-[manifest.chapter]"
	var/datum/campaign_checkpoint/checkpoint = new(manifest.campaign_id, manifest.generation_id, checkpoint_id)

	if(!checkpoint.stage(manifest) || !checkpoint.commit(manifest))
		qdel(checkpoint)
		enter_recovery("the chapter could not be committed")
		return FALSE

	qdel(checkpoint)
	set_campaign_state(CAMPAIGN_STATE_INTERMISSION, "committed checkpoint [checkpoint_id]")
	return TRUE
