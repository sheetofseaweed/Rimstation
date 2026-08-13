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
	/// Checkpoint implementation to commit through. A seam, so tests can stage without writing a world save.
	var/checkpoint_type = /datum/campaign_checkpoint
	/// Checkpoint an admin chose to recover from, overriding the committed pointer for this boot only.
	var/recovery_selection
	/// Who made that selection.
	var/recovery_selected_by
	/// Result record for the chapter being played. Everything that can decide a chapter reports into this one.
	var/datum/colony_chapter_outcome/chapter_outcome
	/// Set while the world is being written outside a commit, which needs the same stillness a commit does.
	var/world_quiesced = FALSE

/datum/controller/subsystem/campaign/Initialize()
	RegisterSignal(SSticker, COMSIG_TICKER_ROUND_STARTING, PROC_REF(on_round_starting))
#ifdef UNIT_TESTS
	// A test run must not adopt whatever campaign the server happens to have on disk, in either direction.
	return SS_INIT_SUCCESS
#else
	// Which campaign to run is read from disk, never assumed: a server that is told nothing runs nothing.
	var/campaign_id = read_active_campaign_id()
	if(campaign_id)
		evaluate_boot_state(campaign_id)
	return SS_INIT_SUCCESS
#endif

/// The round starting is what starts the chapter, on servers that are running a campaign at all.
/datum/controller/subsystem/campaign/proc/on_round_starting(datum/source, start_time)
	SIGNAL_HANDLER
	if(!is_campaign_active())
		return
	begin_chapter()

/**
 * Starts a campaign that does not exist yet, and plays this round as its first chapter.
 *
 * Refuses to start on top of anything already on disk. A campaign is the only copy of its colony, so "start a
 * campaign" must never be a command that can quietly replace one.
 */
/datum/controller/subsystem/campaign/proc/create_campaign(campaign_id, started_by)
	if(!is_safe_campaign_id(campaign_id))
		return FALSE
	if(is_campaign_active())
		log_admin("Campaign creation refused: [campaign_id] was requested while a campaign is already running.")
		return FALSE

	var/datum/campaign_manifest/existing = load_active_campaign_manifest(campaign_id)
	if(existing)
		qdel(existing)
		log_admin("Campaign creation refused: [campaign_id] already exists on disk.")
		return FALSE

	var/datum/campaign_manifest/fresh = new(campaign_id, "generation-1")
	fresh.planet_record = build_generation_planet_record(campaign_id, 1)
	if(isnull(write_campaign_manifest(fresh)))
		log_admin("Campaign creation failed: [campaign_id] could not be written to disk.")
		return FALSE

	// Recorded before the chapter starts: a campaign this server cannot find again next boot is a lost colony,
	// and it is better to refuse now than to play a chapter that quietly goes nowhere.
	if(!write_active_campaign_id(campaign_id))
		log_admin("Campaign creation failed: [campaign_id] could not be recorded as this server's campaign.")
		return FALSE

	manifest = fresh
	if(!begin_load(fresh))
		return FALSE

	log_game("Campaign [campaign_id] created by [started_by || "unknown"].")
	return begin_chapter()

/**
 * Decides, once per boot, which of the four situations this server is in.
 *
 * The four are: no campaign at all, a generation to resume, a generation that was lost and needs replacing,
 * and a chapter that stopped without saying why. Keeping the last two apart is the whole point of the phase -
 * a killed server must not cost a colony - so the distinction is drawn from a record on disk rather than from
 * whatever the previous round left in memory.
 */
/datum/controller/subsystem/campaign/proc/evaluate_boot_state(campaign_id)
	var/datum/campaign_manifest/found = load_active_campaign_manifest(campaign_id)
	if(!found)
		// Named as this server's campaign but unreadable, which is a colony that will not appear this round.
		log_world("Campaign '[campaign_id]' has no manifest that loads; this server will run no campaign this round.")
		return campaign_state

	if(found.generation_closed)
		manifest = found
		begin_next_generation(found.closure_reason || "the previous generation was lost")
		log_world("Campaign [campaign_id]: previous generation was lost, opening [manifest.generation_id] on a new world.")
		return campaign_state

	if(!begin_load(found))
		return campaign_state

	if(!chapter_ended_cleanly(found))
		enter_recovery("chapter [found.chapter] never finished; falling back to the last committed checkpoint")

	log_world("Campaign [campaign_id]: [found.generation_id], chapter [found.chapter], loading [select_checkpoint_for_boot() || "a newly generated world"].")
	return campaign_state

/**
 * The checkpoint directory this boot should load, or null to generate a fresh world.
 *
 * Never scans. The inherited selection walks every save on disk and takes the newest loadable one, which is
 * precisely how a town from a closed generation comes back; a campaign only ever names the checkpoint its own
 * live generation committed.
 */
/datum/controller/subsystem/campaign/proc/select_checkpoint_for_boot()
	if(!manifest || manifest.generation_closed)
		return null

	var/selected = recovery_selection || manifest.active_checkpoint_id
	if(!selected)
		return null
	return campaign_checkpoint_path(manifest.campaign_id, manifest.generation_id, selected)

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
	if(!set_campaign_state(CAMPAIGN_STATE_ACTIVE, "chapter [manifest.chapter] started"))
		return FALSE

	// A fresh record per chapter. Carrying the previous one over would let last chapter's loss decide this one.
	QDEL_NULL(chapter_outcome)
	chapter_outcome = new
	mark_chapter_opened(manifest.chapter)
	message_admins("Colony campaign [manifest.campaign_id]: [manifest.generation_id], chapter [manifest.chapter] begins [manifest.active_checkpoint_id ? "from committed checkpoint [manifest.active_checkpoint_id]" : "on a newly generated world"].")
	return TRUE

/**
 * Records that a chapter started, so the boot after it can tell a crash from a chapter never reached.
 *
 * Written before anything is played rather than after, because the case it exists for is the one where nothing
 * later gets the chance to run.
 */
/datum/controller/subsystem/campaign/proc/mark_chapter_opened(chapter)
	if(!manifest)
		return FALSE

	var/path = campaign_chapter_open_path(manifest.campaign_id, manifest.generation_id, chapter)
	if(!path)
		return FALSE

	rustg_file_write(json_encode(list(
		"chapter" = chapter,
		"generation_id" = manifest.generation_id,
		"loaded_checkpoint_id" = manifest.active_checkpoint_id,
		"opened_at" = "[world.realtime]",
	)), path)
	return fexists(path)

/// Records that a chapter ended for a legible reason. Win or loss both count; only a crash leaves none.
/datum/controller/subsystem/campaign/proc/mark_chapter_ended(chapter, outcome, reason)
	if(!manifest)
		return FALSE

	var/path = campaign_chapter_end_path(manifest.campaign_id, manifest.generation_id, chapter)
	if(!path)
		return FALSE

	rustg_file_write(json_encode(list(
		"chapter" = chapter,
		"generation_id" = manifest.generation_id,
		"outcome" = outcome,
		"reason" = reason,
		"ended_at" = "[world.realtime]",
	)), path)
	return fexists(path)

/**
 * FALSE when the chapter this manifest describes was started and never finished.
 *
 * A chapter that was never opened counts as clean: there is nothing for an interruption to have interrupted,
 * which is the state a campaign sits in between a commit and the next round.
 */
/datum/controller/subsystem/campaign/proc/chapter_ended_cleanly(datum/campaign_manifest/candidate)
	if(!istype(candidate))
		return FALSE

	var/open_path = campaign_chapter_open_path(candidate.campaign_id, candidate.generation_id, candidate.chapter)
	if(!open_path || !fexists(open_path))
		return TRUE

	var/end_path = campaign_chapter_end_path(candidate.campaign_id, candidate.generation_id, candidate.chapter)
	return end_path && fexists(end_path)

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
 * candidate.
 *
 * The closure has to reach disk to mean anything. A defeat recorded only in memory is undone by the next boot,
 * which reads the previous manifest, finds it still pointing at the checkpoint, and loads the colony that was
 * just lost.
 */
/datum/controller/subsystem/campaign/proc/declare_defeat(reason)
	if(!set_campaign_state(CAMPAIGN_STATE_DEFEATED, reason))
		return FALSE

	if(manifest)
		var/lost_checkpoint_id = manifest.active_checkpoint_id
		var/lost_chapter = manifest.chapter

		manifest.generation_closed = TRUE
		manifest.closure_reason = reason
		manifest.active_checkpoint_id = null
		manifest.last_outcome = COLONY_OUTCOME_FAILURE

		write_generation_closure(reason, lost_checkpoint_id)
		mark_chapter_ended(lost_chapter, COLONY_OUTCOME_FAILURE, reason)

		if(isnull(write_campaign_manifest(manifest)))
			log_game("Campaign could not write the closure of generation [manifest.generation_id]; the manifest on disk still points at [lost_checkpoint_id].")
			message_admins("Campaign defeat could not be written to disk. Unless this is repaired, the lost generation will load again on reboot.")

	set_campaign_state(CAMPAIGN_STATE_RESET_PENDING, "generation closed")
	return TRUE

/**
 * Writes the record of why a generation ended, once.
 *
 * Never rewritten: a second defeat cannot restate why the first one happened, and an admin reading this later
 * is entitled to the original account.
 */
/datum/controller/subsystem/campaign/proc/write_generation_closure(reason, lost_checkpoint_id)
	if(!manifest)
		return FALSE

	var/path = campaign_closure_path(manifest.campaign_id, manifest.generation_id)
	if(!path)
		return FALSE
	if(fexists(path))
		return TRUE

	rustg_file_write(json_encode(list(
		"campaign_id" = manifest.campaign_id,
		"generation_id" = manifest.generation_id,
		"generation_number" = manifest.generation_number,
		"chapter" = manifest.chapter,
		"last_checkpoint_id" = lost_checkpoint_id,
		"reason" = reason,
		"closed_at" = "[world.realtime]",
	)), path)
	return fexists(path)

/**
 * Opens a fresh generation on a new world.
 *
 * Starts from nothing on purpose. Searching older generations for something to load is the exact mechanism by
 * which a lost colony returns, so the new generation is given a planet derived from its own number and an
 * empty checkpoint pointer, and the old generation's files are left alone as archive.
 */
/datum/controller/subsystem/campaign/proc/begin_next_generation(reason)
	if(!manifest)
		return FALSE

	var/next_number = manifest.generation_number + 1
	var/datum/campaign_manifest/fresh = new(manifest.campaign_id, "generation-[next_number]")
	fresh.generation_number = next_number
	fresh.planet_record = build_generation_planet_record(manifest.campaign_id, next_number)

	if(isnull(write_campaign_manifest(fresh)))
		enter_recovery("a new generation could not be written to disk")
		return FALSE

	log_game("Campaign opened generation [fresh.generation_id] ([reason]).")
	manifest = fresh
	return begin_load(fresh)

/// The world a given generation is built on. Derived from campaign identity, so it is stable if rebuilt.
/datum/controller/subsystem/campaign/proc/build_generation_planet_record(campaign_id, generation_number)
	RETURN_TYPE(/list)
	var/root_seed = rustg_hash_string(RUSTG_HASH_SHA256, "[campaign_id]:generation:[generation_number]")
	var/datum/planet_definition/planet = new(root_seed, "[campaign_id]-generation-[generation_number]")
	var/list/record = planet.serialize()
	qdel(planet)
	return record

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

/**
 * An admin ending the round early. Recovery, never defeat.
 *
 * Recorded with who did it, because "the colony was lost" and "someone rebooted the server" produce the same
 * absence of a chapter ending and must not be allowed to look alike afterwards.
 */
/datum/controller/subsystem/campaign/proc/admin_abort(reason, admin_key)
	if(!enter_recovery("aborted by [admin_key || "an admin"]: [reason || "no reason given"]"))
		return FALSE

	log_admin("Campaign aborted by [admin_key || "unknown"]: [reason || "no reason given"].")
	return TRUE

/**
 * Checkpoints on disk that are whole enough to be recovered from.
 *
 * Only this generation's, and only ones that finished being written. A checkpoint appearing here is not a
 * claim that it was ever committed - that is exactly why selecting one is an explicit admin act.
 */
/datum/controller/subsystem/campaign/proc/list_recovery_snapshots()
	RETURN_TYPE(/list)
	var/list/snapshots = list()
	if(!manifest)
		return snapshots

	for(var/checkpoint_id in list_campaign_checkpoint_ids(manifest.campaign_id, manifest.generation_id))
		var/datum/campaign_checkpoint/candidate = new(manifest.campaign_id, manifest.generation_id, checkpoint_id)
		if(candidate.is_complete() && candidate.validate_artifacts())
			snapshots += checkpoint_id
		qdel(candidate)

	return snapshots

/**
 * Points this boot at a snapshot other than the committed one.
 *
 * Deliberately does not write anything: the committed pointer stays exactly where it was, so a recovery
 * attempt that turns out to be the wrong choice costs nothing and can be undone by rebooting.
 */
/datum/controller/subsystem/campaign/proc/select_recovery_snapshot(checkpoint_id, selected_by)
	if(!manifest)
		return FALSE

	if(!(checkpoint_id in list_recovery_snapshots()))
		log_admin("Campaign recovery selection of [checkpoint_id] refused: it is not a complete checkpoint of generation [manifest.generation_id].")
		return FALSE

	recovery_selection = checkpoint_id
	recovery_selected_by = selected_by
	log_admin("Campaign recovery snapshot [checkpoint_id] selected by [selected_by || "unknown"].")
	message_admins("Campaign will load recovery snapshot [checkpoint_id], selected by [selected_by || "unknown"]. The committed checkpoint is unchanged.")
	return TRUE

/// TRUE when a campaign is being played, which is what campaign-aware code keys off.
/datum/controller/subsystem/campaign/proc/is_campaign_active()
	return !isnull(manifest) && campaign_state != CAMPAIGN_STATE_NONE

/**
 * TRUE when the inherited round-end world save should run.
 *
 * A campaign decides for itself what becomes of its world, and the answer is frequently "nothing": a lost
 * colony must not be written down at all, and a won one is preserved by a commit into its own generation
 * rather than by another timestamp in the shared autosave pool. Saving on top of that would either resurrect
 * a colony that was lost or bury a committed checkpoint under a newer save of the same ground.
 *
 * Either half of the campaign being set counts as a campaign owning the world, since a transition in progress
 * is still a campaign.
 */
/datum/controller/subsystem/campaign/proc/should_run_legacy_roundend_save()
	if(manifest || campaign_state != CAMPAIGN_STATE_NONE)
		return FALSE
	return CONFIG_GET(flag/persistent_save_enabled)

/**
 * The chapter's verdict, taken as the round ends.
 *
 * A colony nothing managed to take is a colony that held, so an unresolved chapter succeeds and the evolved
 * town is committed. That has to be the rule: a commit is the only way a campaign advances, and if an ordinary
 * round ending counted as anything else, a colony could never keep what it built.
 *
 * A server that is killed never reaches this proc at all, and that is precisely what separates the two cases.
 * It leaves a chapter opened with no ending, which the next boot reads as recovery rather than as a result.
 *
 * Anything that already decided - a defeat, an admin abort, a commit that has run - is left alone.
 */
/datum/controller/subsystem/campaign/proc/resolve_chapter_at_round_end()
	if(!is_campaign_active())
		return FALSE
	if(campaign_state in list(CAMPAIGN_STATE_INTERMISSION, CAMPAIGN_STATE_RESET_PENDING, CAMPAIGN_STATE_DEFEATED, CAMPAIGN_STATE_RECOVERY))
		return FALSE

	if(!chapter_outcome)
		return enter_recovery("the round ended with no chapter result to act on")

	if(!chapter_outcome.is_resolved())
		chapter_outcome.resolve(COLONY_OUTCOME_SUCCESS, "the colony held through the chapter")

	// From here the result is acted on rather than only recorded, which is what this flag exists to mark.
	chapter_outcome.touched_persistence = TRUE

	if(chapter_outcome.result == COLONY_OUTCOME_FAILURE)
		return declare_defeat(chapter_outcome.reason)

	if(!request_commit(chapter_outcome))
		return enter_recovery("the chapter succeeded but could not be approved for a commit")
	return perform_commit()

/**
 * FALSE while the world must stop changing underneath a commit.
 *
 * A checkpoint is written by walking the map, so anything that mutates it mid-walk produces a save that
 * matches no moment that ever existed - half the town before a raid arrived, half after. Callers that start
 * new world-changing activity ask here first.
 */
/datum/controller/subsystem/campaign/proc/can_mutate_world()
	return !world_quiesced && campaign_state != CAMPAIGN_STATE_COMMITTING

/**
 * Writes a checkpoint without promoting it.
 *
 * The point of a snapshot is that it changes nothing: the committed pointer is untouched, so this is a copy an
 * admin can fall back to rather than a decision about what the campaign is. Recovering from one is a separate,
 * explicit act.
 *
 * It walks the map exactly as a commit does, so it holds the world still for the duration - a snapshot taken
 * while a raid moves through it shows half the colony before the raid and half after.
 */
/datum/controller/subsystem/campaign/proc/create_snapshot(snapshot_id, created_by)
	if(!manifest)
		return FALSE
	if(!can_mutate_world())
		log_admin("Campaign snapshot [snapshot_id] refused: the world is already being written.")
		return FALSE

	var/datum/campaign_checkpoint/snapshot = new checkpoint_type(manifest.campaign_id, manifest.generation_id, snapshot_id)
	if(!snapshot.artifact_path)
		qdel(snapshot)
		log_admin("Campaign snapshot refused: '[snapshot_id]' cannot be a checkpoint id.")
		return FALSE

	world_quiesced = TRUE
	var/staged = snapshot.stage(manifest)
	world_quiesced = FALSE
	qdel(snapshot)

	if(!staged)
		log_admin("Campaign snapshot [snapshot_id] failed while being written; nothing was promoted.")
		return FALSE

	log_admin("Campaign snapshot [snapshot_id] written by [created_by || "unknown"]. The committed checkpoint is unchanged.")
	message_admins("Campaign snapshot [snapshot_id] written by [created_by || "unknown"]. It is a fallback copy, not a commit.")
	return TRUE

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

	var/played_chapter = manifest.chapter
	var/checkpoint_id = "checkpoint-[played_chapter]"
	var/datum/campaign_checkpoint/checkpoint = new checkpoint_type(manifest.campaign_id, manifest.generation_id, checkpoint_id)

	if(!checkpoint.stage(manifest) || !checkpoint.commit(manifest))
		qdel(checkpoint)
		enter_recovery("the chapter could not be committed")
		return FALSE

	qdel(checkpoint)
	// Only now did the chapter end cleanly. Recording it earlier would make a failed commit look like a
	// finished chapter to the next boot.
	mark_chapter_ended(played_chapter, COLONY_OUTCOME_SUCCESS, last_state_reason)
	set_campaign_state(CAMPAIGN_STATE_INTERMISSION, "committed checkpoint [checkpoint_id]")
	message_admins("Colony campaign [manifest.campaign_id] committed [checkpoint_id]. The colony returns next round as chapter [manifest.chapter].")
	return TRUE
