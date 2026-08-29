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
	/// The colony's research, as it stood when the chapter began. Recaptured from the live techweb on commit.
	var/datum/colony_research_record/research
	/// What the settlement owns and how it came to own it. Written through on every change.
	var/datum/settlement_ledger/ledger

	/// Everyone this generation has known. Rebuilt from the manifest at the start of every chapter.
	var/datum/colonist_roster/roster

	/// What play has done to the region. The region itself is derived, so only this is carried.
	var/datum/overworld_state/overworld

	/// Colonist ids seen at any point this chapter. Append-only until the chapter ends.
	var/list/colonists_seen_this_chapter = list()

	/**
	 * Colonist id to a weakref of the body currently playing them.
	 *
	 * Written by bind_colonist() and cleared by the binding component when a body goes away. Its reader is the
	 * equipment declaration, which has to find the live body behind a colonist while a save is being written.
	 */
	var/list/active_colonist_bodies = list()
	/// Which chapter the attendance window above describes. Null until somebody is seen.
	var/seen_chapter
	/// Incidents running right now, so nothing schedules over the top of one already in progress.
	var/list/active_incidents
	/// Serialized results of incidents this chapter, oldest first. Read by pacing, not by play.
	var/list/incident_history
	/// What the colony has been through, and how much slack it is owed. Persisted with the campaign.
	var/datum/colony_story_state/story_state
	/// TRUE once this chapter has thrown something serious at the colony, so a win is not mistaken for a rest.
	var/faced_major_threat_this_chapter = FALSE

	/**
	 * What the campaign clock read when this chapter became active, and the world time that reading was taken at.
	 *
	 * Runtime only, and never rebased. The clock is derived from these two rather than counted up, because this
	 * subsystem does not fire - and giving it a tick merely to add deciseconds would make campaign time depend on
	 * the MC keeping up, which is precisely the thing that stops being true when the colony is busy.
	 *
	 * Null between chapters, which is what makes the stored clock authoritative while nothing is being played.
	 */
	var/chapter_clock_origin = null
	var/chapter_world_time_origin = null

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
/datum/controller/subsystem/campaign/proc/create_campaign(campaign_id, started_by, list/region_options)
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

	// Written at creation because the region is derived from these: a campaign without them would generate a
	// different world on its next boot than the one whoever started it was shown.
	var/datum/overworld_state/region_state = new(region_options)
	fresh.overworld_record = region_state.serialize()
	qdel(region_state)
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
	// Cleared before the manifest changes hands. Between a load and the chapter starting, nothing is being
	// played, so campaign time is whatever the record says rather than a running total from the last chapter.
	chapter_clock_origin = null
	chapter_world_time_origin = null

	if(loading_manifest)
		manifest = loading_manifest
		// Belongs to the manifest, not to the subsystem: carrying either across would give a new generation the
		// research and the savings of the one that was lost.
		research = null
		ledger = null
		story_state = null
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
	faced_major_threat_this_chapter = FALSE
	// Before the restores below, because restoring the ledger can write an entry and an entry without a clock
	// reading is a hole in the campaign's history.
	start_campaign_time()
	// Asynchronous because this is reached from a signal handler and it is the one step here that sleeps:
	// rebuilding the techweb runs recalculate_nodes(), which yields through stoplag(). Everything after it
	// stays synchronous, so the chapter's state, ledger, roster and open marker are all in place before this
	// proc returns - only the techweb finishes catching up a tick later, which nothing is waiting on.
	INVOKE_ASYNC(src, PROC_REF(restore_research))
	restore_ledger()
	// The larder came back with the map, so the ledger's figure is whatever was true when the chapter was
	// committed. The food in the box is the truth; this makes the number agree with it again.
	sync_colony_food_to_ledger()
	restore_roster()
	restore_overworld()
	warn_if_map_is_not_a_colony()
	mark_chapter_opened(manifest.chapter)
	message_admins("Colony campaign [manifest.campaign_id]: [manifest.generation_id], chapter [manifest.chapter] begins [manifest.active_checkpoint_id ? "from committed checkpoint [manifest.active_checkpoint_id]" : "on a newly generated world"].")
	return TRUE

/**
 * How far into the campaign we are, right now, in deciseconds.
 *
 * The one authority on campaign time. Everything that stamps a moment - ledger entries, incident starts and
 * ends, journey legs - asks this rather than reading the stored clock, because the stored clock is only ever
 * as fresh as the last time something was written, and most of what wants a timestamp happens between writes.
 *
 * Derived from two immutable origins instead of accumulated, so it cannot drift, cannot be double-counted by
 * being synced twice, and does not need this subsystem to fire. While no chapter is active the stored clock is
 * the answer, which is what makes a reload resume from the checkpoint rather than from wherever the world
 * happened to be.
 */
/datum/controller/subsystem/campaign/proc/get_campaign_time()
	if(isnull(chapter_clock_origin) || isnull(chapter_world_time_origin))
		return manifest?.campaign_clock || 0

	// Clamped because world.time is not guaranteed to only move forwards across a load, and a negative delta
	// would run the campaign's history backwards - entries would stamp before ones already written.
	var/elapsed = max(0, world.time - chapter_world_time_origin)
	return chapter_clock_origin + elapsed

/**
 * Starts this chapter's contribution to campaign time.
 *
 * Takes the stored clock as its floor, so a chapter always begins where the last committed one left off.
 */
/datum/controller/subsystem/campaign/proc/start_campaign_time()
	chapter_clock_origin = manifest?.campaign_clock || 0
	chapter_world_time_origin = world.time

/**
 * Copies the live clock into the manifest, so a write picks it up.
 *
 * Deliberately does not rebase the origins. Rebasing would make the answer depend on how many times this was
 * called, which is how a clock that is synced before a snapshot and again before a commit ends up counting the
 * time between them twice.
 */
/datum/controller/subsystem/campaign/proc/sync_campaign_time()
	if(!manifest)
		return FALSE
	manifest.campaign_clock = get_campaign_time()
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

		// The moment the generation ended is part of what is being recorded, so it is taken before the record
		// is built rather than left at whatever the last commit happened to store.
		sync_campaign_time()

		manifest.generation_closed = TRUE
		manifest.closure_reason = reason
		manifest.active_checkpoint_id = null
		manifest.last_outcome = COLONY_OUTCOME_FAILURE

		var/datum/colony_story_state/story = get_story_state()
		if(story)
			story.advance_chapter(COLONY_OUTCOME_FAILURE, TRUE)
			sync_story_state()

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
	// The colony is new; the campaign is not. Time is the one thing that survives a generation being lost,
	// because how long this has been going on is true regardless of how many towns it took.
	fresh.campaign_clock = get_campaign_time()

	// The campaign remembers how old it is; the new colony inherits none of the previous one's scars.
	var/datum/colony_story_state/story = get_story_state()
	if(story)
		story.reset_for_new_generation()
		fresh.storyteller_state = story.serialize()

	// The region's options are a preference about how this campaign is played, so they survive. Everything the
	// last generation discovered described ground that no longer exists, so none of it does.
	var/datum/overworld_state/region_state = get_overworld_state()
	if(region_state)
		region_state.reset_for_new_generation()
		fresh.overworld_record = region_state.serialize()

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

/**
 * Puts the colony's stored research back into this round's techweb.
 *
 * Called as the chapter begins, because a techweb is rebuilt from nothing every round - an ordinary shift has
 * no memory, and remembering is the whole difference between a campaign and a shift.
 */
/datum/controller/subsystem/campaign/proc/restore_research()
	if(!manifest)
		return FALSE

	research = new
	if(length(manifest.research_record) && !research.deserialize(manifest.research_record))
		// Refusing to load is not the same as having researched nothing, so this is said out loud rather than
		// quietly handing the colony a blank techweb.
		log_game("Campaign [manifest.campaign_id] has an unreadable research record; this chapter starts from a fresh techweb.")
		message_admins("The colony's research record could not be read. This chapter starts from an unresearched techweb.")
		return FALSE

	var/datum/techweb/web = get_colony_techweb()
	if(!web)
		log_game("Campaign [manifest.campaign_id] found no techweb to restore its research into.")
		return FALSE

	// Cut back before anything is restored, so the colony's own record is what widens the techweb rather than
	// the station starting set the techweb granted itself.
	if(CONFIG_GET(flag/campaign_restrict_starting_research))
		var/removed = restrict_techweb_to_campaign_start(web)
		if(removed)
			log_game("Campaign [manifest.campaign_id] withheld [removed] station starting nodes.")

	if(!CONFIG_GET(flag/campaign_research_persistence))
		log_game("Campaign [manifest.campaign_id] is not carrying research between chapters; persistence is disabled in config.")
		return TRUE

	var/restored = research.restore_into(web)
	if(restored)
		log_game("Campaign [manifest.campaign_id] restored [restored] researched nodes.")
	return TRUE

/**
 * The settlement's ledger, built from the manifest the first time it is asked for.
 *
 * Materialised on demand for the same reason the research record is: nothing has to be ordered correctly
 * between the manifest arriving and something wanting to spend money.
 */
/datum/controller/subsystem/campaign/proc/get_ledger()
	RETURN_TYPE(/datum/settlement_ledger)
	if(!manifest)
		return null

	if(!ledger)
		ledger = new
		if(length(manifest.ledger_record) && !ledger.deserialize(manifest.ledger_record))
			log_game("Campaign [manifest.campaign_id] has an unreadable ledger; the settlement's accounts start empty.")
			message_admins("The settlement ledger could not be read. Its balance and history have been reset.")
	return ledger

/// Writes the live ledger back into the manifest, which is what a commit will store.
/datum/controller/subsystem/campaign/proc/sync_ledger()
	if(manifest && ledger)
		manifest.ledger_record = ledger.serialize()

/// Puts the settlement's money back into this round's account, which starts every round from scratch.
/datum/controller/subsystem/campaign/proc/restore_ledger()
	var/datum/settlement_ledger/settlement = get_ledger()
	if(!settlement)
		return FALSE

	var/datum/bank_account/account = get_settlement_account()
	if(!account)
		log_game("Campaign [manifest.campaign_id] found no settlement account to restore its balance into.")
		return FALSE

	// A campaign that has never recorded anything keeps whatever the round granted, so a first chapter is not
	// forced to start at zero credits.
	if(!length(manifest.ledger_record))
		settlement.capture_from(account)
		sync_ledger()
		return TRUE

	settlement.restore_into(account)
	return TRUE

/**
 * Spends the settlement's money. Returns TRUE only if it had it.
 *
 * Routed through here rather than called on the ledger so that nothing can move the settlement's money without
 * the change reaching the record that survives the round.
 */
/datum/controller/subsystem/campaign/proc/try_debit(amount, category, reason_code, actor_id, related_id)
	var/datum/settlement_ledger/settlement = get_ledger()
	if(!settlement || !settlement.try_debit(get_settlement_account(), amount, category, reason_code, actor_id, related_id, get_campaign_time()))
		return FALSE
	sync_ledger()
	return TRUE

/// Adds to the settlement's money and records why.
/datum/controller/subsystem/campaign/proc/credit(amount, category, reason_code, actor_id, related_id)
	var/datum/settlement_ledger/settlement = get_ledger()
	if(!settlement || !settlement.credit(get_settlement_account(), amount, category, reason_code, actor_id, related_id, get_campaign_time()))
		return FALSE
	sync_ledger()
	return TRUE

/// Moves a resource quantity and records why. Refuses to take more than the settlement holds.
/datum/controller/subsystem/campaign/proc/adjust_resource(resource_id, amount, category, reason_code, actor_id, related_id)
	var/datum/settlement_ledger/settlement = get_ledger()
	if(!settlement || !settlement.adjust_resource(resource_id, amount, category, reason_code, actor_id, related_id, get_campaign_time()))
		return FALSE
	sync_ledger()
	return TRUE

/// Records something worth remembering that moved neither money nor materials.
/datum/controller/subsystem/campaign/proc/record_nonfinancial(category, reason_code, actor_id, related_id)
	var/datum/settlement_ledger/settlement = get_ledger()
	if(!settlement || !settlement.record_nonfinancial(category, reason_code, actor_id, related_id, get_campaign_time()))
		return FALSE
	sync_ledger()
	return TRUE

/// Reads the round's closing balance back out of the account, so spending outside the ledger is not lost.
/datum/controller/subsystem/campaign/proc/capture_ledger()
	var/datum/settlement_ledger/settlement = get_ledger()
	if(!settlement)
		return FALSE

	var/datum/bank_account/account = get_settlement_account()
	if(account && !settlement.capture_from(account))
		return FALSE

	sync_ledger()
	return TRUE

/**
 * Reads this round's research back out of the techweb and into the manifest.
 *
 * Done at commit rather than as research happens, so a chapter that is lost or interrupted does not carry its
 * research forward - what the colony keeps is what it held when the chapter was preserved.
 */
/datum/controller/subsystem/campaign/proc/capture_research()
	if(!manifest)
		return FALSE

	var/datum/techweb/web = get_colony_techweb()
	if(!web)
		return FALSE

	// Nothing is captured when persistence is off, so turning it back on later does not resurrect a chapter's
	// research that the colony was told it would not keep.
	if(!CONFIG_GET(flag/campaign_research_persistence))
		return FALSE

	if(!research)
		research = new
	if(!research.capture_from(web))
		return FALSE

	manifest.research_record = research.serialize()
	return TRUE

/**
 * The colony's roster, built from the manifest the first time it is asked for.
 *
 * Materialised on demand for the same reason the ledger is: nothing has to be ordered correctly between the
 * manifest arriving and somebody wanting to join.
 */
/datum/controller/subsystem/campaign/proc/get_roster()
	RETURN_TYPE(/datum/colonist_roster)
	if(!manifest)
		return null

	if(!roster)
		roster = new
		if(length(manifest.roster_record) && !roster.deserialize(manifest.roster_record))
			log_game("Campaign [manifest.campaign_id] has an unreadable roster; this chapter starts with nobody written down.")
			message_admins("The colony's roster could not be read. This chapter starts with an empty roster - do not commit it if the record matters.")
	return roster

/// Writes the live roster back into the manifest, which is what a commit will store.
/datum/controller/subsystem/campaign/proc/sync_roster()
	if(manifest && roster)
		manifest.roster_record = roster.serialize()

/**
 * Makes sure the attendance window belongs to the chapter currently being played.
 *
 * Keyed on the chapter number rather than on being called at the right moment, because there is no reliable
 * moment to call it. Roundstart colonists are bound during the ticker's equip_characters(), which runs before
 * COMSIG_TICKER_ROUND_STARTING is what starts the chapter - so clearing the window when a chapter begins would
 * throw away everybody who spawned with the round and mark the whole colony absent from a chapter it played.
 *
 * Returns TRUE when a new window was opened.
 */
/datum/controller/subsystem/campaign/proc/ensure_attendance_window()
	var/playing_chapter = manifest?.chapter
	if(seen_chapter == playing_chapter)
		return FALSE

	colonists_seen_this_chapter = list()
	active_colonist_bodies = list()
	seen_chapter = playing_chapter
	return TRUE

/// Starts the chapter from the roster the last one committed.
/datum/controller/subsystem/campaign/proc/restore_roster()
	if(!manifest)
		return FALSE

	ensure_attendance_window()
	return !isnull(get_roster())

/**
 * Marks `body` as the one playing `record` this chapter, and counts their attendance.
 *
 * Attendance is credited here rather than at commit, on the same principle as death: it is recorded when it
 * happens, so a chapter that ends badly still knows who turned up for it. Crediting is once per chapter per
 * colonist, so rejoining after a disconnect does not inflate anybody's history.
 */
/datum/controller/subsystem/campaign/proc/bind_colonist(mob/living/body, datum/colonist_record/record)
	if(!istype(body) || !istype(record))
		return FALSE

	var/datum/colonist_roster/colony = get_roster()
	// A record has to be one of ours. Binding a body to a colonist the colony has never written down would
	// produce attendance for somebody who does not exist here.
	if(!colony || colony.get_record(record.colonist_id) != record)
		return FALSE

	// Opened here rather than at chapter start, so a colonist bound before the chapter formally begins is still
	// counted. See ensure_attendance_window().
	ensure_attendance_window()

	var/datum/component/colonist_binding/existing = body.GetComponent(/datum/component/colonist_binding)
	if(existing)
		// Already bound to this colonist is success; bound to a different one is not something to silently fix.
		return existing.colonist_id == record.colonist_id

	if(!body.AddComponent(/datum/component/colonist_binding, record.colonist_id))
		return FALSE

	active_colonist_bodies[record.colonist_id] = WEAKREF(body)
	if(!(record.colonist_id in colonists_seen_this_chapter))
		colonists_seen_this_chapter += record.colonist_id
		record.chapters_attended++

	if(record.status != COLONIST_STATUS_DEAD)
		record.status = COLONIST_STATUS_ACTIVE
	return TRUE

/**
 * Forgets which body was playing a colonist. The record is untouched - a person does not stop existing.
 *
 * The weakref is compared rather than trusted, so a body being cleaned up long after it was replaced cannot
 * unregister whichever body took its place.
 */
/datum/controller/subsystem/campaign/proc/forget_colonist_body(colonist_id, datum/weakref/body_ref)
	if(active_colonist_bodies[colonist_id] != body_ref)
		return FALSE

	active_colonist_bodies -= colonist_id
	return TRUE

/**
 * Which colonist a body is playing, or null if it is not playing one.
 *
 * Asked of the binding on the mob rather than of the registry, so it answers correctly for a body that is not
 * the campaign's currently registered one - and so anything holding a mob can find its colonist without
 * knowing an id first.
 */
/datum/controller/subsystem/campaign/proc/get_colonist_record_for_body(mob/living/body)
	RETURN_TYPE(/datum/colonist_record)
	if(!istype(body))
		return null

	var/datum/component/colonist_binding/binding = body.GetComponent(/datum/component/colonist_binding)
	if(!binding)
		return null

	var/datum/colonist_roster/colony = get_roster()
	return colony?.get_record(binding.colonist_id)

/// The body currently playing a colonist, or null if nobody is.
/datum/controller/subsystem/campaign/proc/get_colonist_body(colonist_id)
	RETURN_TYPE(/mob/living)
	var/datum/weakref/body_ref = active_colonist_bodies[colonist_id]
	return body_ref?.resolve()

/// Records that a colonist died, at the moment it happened rather than at the end of the chapter.
/datum/controller/subsystem/campaign/proc/note_colonist_death(colonist_id)
	var/datum/colonist_roster/colony = get_roster()
	if(!colony)
		return FALSE

	var/datum/colonist_record/record = colony.get_record(colonist_id)
	if(!record || record.status == COLONIST_STATUS_DEAD)
		return FALSE

	record.status = COLONIST_STATUS_DEAD
	log_game("Colony campaign [manifest?.campaign_id]: colonist [record.display_name] ([colonist_id]) died in chapter [manifest?.chapter].")
	return TRUE

/**
 * Writes down who was actually here this chapter.
 *
 * Attendance was already counted as people arrived, so this is only the status sweep: everyone the chapter did
 * not see becomes away. The sweep never touches the dead, because otherwise a colony would forget its dead
 * simply by playing a chapter without them - which is every chapter after the one they died in.
 */
/datum/controller/subsystem/campaign/proc/capture_roster()
	if(!manifest)
		return FALSE

	var/datum/colonist_roster/colony = get_roster()
	if(!colony)
		return FALSE

	for(var/colonist_id in colony.records)
		var/datum/colonist_record/record = colony.records[colonist_id]

		// Anybody still standing has their skills read now. Those who already left wrote theirs down as their
		// binding came off, so their record is left exactly as they left it.
		var/mob/living/body = get_colonist_body(colonist_id)
		if(body)
			capture_colonist_skills(record, body.mind)

		if(record.status == COLONIST_STATUS_DEAD)
			continue
		record.status = (colonist_id in colonists_seen_this_chapter) ? COLONIST_STATUS_ACTIVE : COLONIST_STATUS_AWAY

	sync_roster()
	return TRUE

/// Writes a colonist's skills into their record, if the campaign still has one for them.
/datum/controller/subsystem/campaign/proc/capture_skills_for(colonist_id, datum/mind/mind)
	if(!istype(mind))
		return FALSE

	var/datum/colonist_roster/colony = get_roster()
	var/datum/colonist_record/record = colony?.get_record(colonist_id)
	if(!record)
		return FALSE

	return capture_colonist_skills(record, mind)

/**
 * What play has done to the region, built from the manifest the first time it is asked for.
 *
 * Materialised on demand for the same reason the ledger and roster are: nothing has to be ordered correctly
 * between the manifest arriving and somebody opening the map.
 */
/datum/controller/subsystem/campaign/proc/get_overworld_state()
	RETURN_TYPE(/datum/overworld_state)
	if(!manifest)
		return null

	if(!overworld)
		overworld = new
		if(length(manifest.overworld_record) && !overworld.deserialize(manifest.overworld_record))
			log_game("Campaign [manifest.campaign_id] has an unreadable overworld record; the region starts unexplored.")
			message_admins("The colony's regional map could not be read. Its discoveries have been reset - do not commit if that record mattered.")
	return overworld

/// Writes the live overworld state back into the manifest, which is what a commit will store.
/datum/controller/subsystem/campaign/proc/sync_overworld()
	if(manifest && overworld)
		manifest.overworld_record = overworld.serialize()

/**
 * Opens the region for the chapter, revealing the colony's own surroundings the first time.
 *
 * The fingerprint is compared rather than trusted: if the region rebuilt differently from the one the stored
 * discoveries were recorded against, every cell id in that record now describes somewhere else. That is a
 * generator drift bug rather than something to repair silently, so it is said out loud and the discoveries are
 * kept - throwing them away would destroy the evidence.
 */
/datum/controller/subsystem/campaign/proc/restore_overworld()
	var/datum/overworld_state/region_state = get_overworld_state()
	if(!region_state)
		return FALSE

	var/datum/overworld_region/region = get_active_overworld_region()
	if(!region)
		return FALSE

	if(region_state.region_fingerprint && region_state.region_fingerprint != region.fingerprint)
		log_game("Campaign [manifest.campaign_id]: the region rebuilt with a different fingerprint than its stored discoveries were recorded against.")
		message_admins(span_boldwarning("The colony's regional map no longer matches what was explored. This is a generator drift bug; report it rather than continuing to rely on the map."))

	if(!length(region_state.discovered_cells))
		region_state.reveal_initial(region)

	region_state.region_fingerprint = region.fingerprint
	sync_overworld()
	return TRUE

/**
 * Marks a cell and its neighbours as seen, and tells any open map about it.
 *
 * The single funnel every discovery goes through, so there is exactly one place that serializes and exactly
 * one place that refreshes the interface - the map is on manual updates, and a discovery nobody pushed would
 * simply not appear.
 */
/datum/controller/subsystem/campaign/proc/discover_overworld_cell(cell_id)
	var/datum/overworld_state/region_state = get_overworld_state()
	var/datum/overworld_region/region = get_active_overworld_region()
	if(!region_state || !region)
		return 0

	var/revealed = region_state.discover_around(region, cell_id)
	if(!revealed)
		return 0

	sync_overworld()
	refresh_overworld_consoles()
	return revealed

/// The expedition being assembled or under way, if there is one.
/datum/controller/subsystem/campaign/proc/get_active_party()
	RETURN_TYPE(/datum/overworld_party)
	var/datum/overworld_state/region_state = get_overworld_state()
	return region_state?.active_party

/**
 * Records that the party changed, and shows it.
 *
 * The same funnel discovery uses. Every party edit goes through here rather than serializing at its own call
 * site, because the map is on manual updates and a change nobody pushed simply does not appear - which looks
 * exactly like the button being broken.
 */
/datum/controller/subsystem/campaign/proc/commit_party_change()
	sync_overworld()
	refresh_overworld_consoles()
	// The reminder people carry and the lantern on the post are both views of the membership, so they are
	// rebuilt here rather than at each call site - there is no way to change a party without them following.
	var/datum/overworld_party/party = get_active_party()
	refresh_caravan_alerts(party)
	refresh_hitching_post(party)
	return TRUE

/// Starts assembling an expedition. Returns it, or null if one already exists.
/datum/controller/subsystem/campaign/proc/form_party()
	RETURN_TYPE(/datum/overworld_party)
	var/datum/overworld_state/region_state = get_overworld_state()
	var/datum/overworld_party/party = region_state?.create_party()
	if(!party)
		return null

	log_game("Colony campaign [manifest?.campaign_id]: expedition [party.party_id] is being assembled.")
	commit_party_change()
	return party

/**
 * Sends the party out, exactly once, paying for it as it goes.
 *
 * The whole point of this proc is that the check and the charge are not separable. Everything is revalidated
 * here - not at the moment somebody clicked ready - and the food is debited before the state moves, so a
 * caravan can never be on the road unpaid for, and a refused departure can never have eaten anything.
 */
/datum/controller/subsystem/campaign/proc/depart_party()
	var/datum/overworld_party/party = get_active_party()
	if(!party)
		return "There is no expedition to send."

	var/datum/overworld_region/region = get_active_overworld_region()
	if(!region)
		return "This colony has no regional map."

	var/blocked = party.departure_problem(region, get_discovered_cell_ids(region))
	if(blocked)
		return blocked

	var/cost = party.supply_cost()
	// Paid before the state moves, and paid all at once: out of the larder if the colony has stocked it, and
	// out of the budget for whatever is missing. Nothing is taken unless the whole bill can be met, so a
	// refused departure leaves the colony exactly as it was.
	if(!pay_for_colony_food(cost, "expedition_supplies", party.party_id))
		return "The colony could not put together the food this journey needs."

	if(!party.set_state(OVERWORLD_PARTY_DEPARTING, "the expedition set out"))
		// departure_problem() already proved the party was still forming, so reaching here means the state
		// machine and the departure checks disagree. Say so loudly: the food is gone and nobody left with it.
		stack_trace("expedition [party.party_id] paid for its supplies and was then refused departure")
		return "The expedition could not be sent."

	party.supplies = cost
	// The camp has to be standing before anybody can be put in it, and bringing it up sleeps. The party is
	// locked as departing for the duration, and SSoverworld either finishes the job or puts it back.
	INVOKE_ASYNC(SSoverworld, TYPE_PROC_REF(/datum/controller/subsystem/overworld, complete_departure), party.party_id)
	log_game("Colony campaign [manifest?.campaign_id]: expedition [party.party_id] left for [party.destination_site_id] with [length(party.member_ids)] colonists and [cost] food.")
	message_admins("Colony expedition [party.party_id] left for [party.destination_site_id] with [length(party.member_ids)] colonists.")
	commit_party_change()
	return null

/// Pushes new map data to anyone looking at one. Autoupdate is off, so this is how the map ever changes.
/datum/controller/subsystem/campaign/proc/refresh_overworld_consoles()
	for(var/obj/machinery/computer/colony_overworld/table as anything in GLOB.colony_overworld_consoles)
		SStgui.update_uis(table)

/**
 * How many threat points a raid scheduled right now is worth.
 *
 * Deliberately small: a base, a growth term per chapter survived, a ceiling, and a reduction for a colony that
 * is still recovering. It reuses the storyteller's own recovery figure rather than introducing a second,
 * competing measure of how battered the settlement is - there should only ever be one answer to that.
 *
 * A fuller model - defences built, population actually online, economic reach - belongs with the rest of the
 * raid work. This exists so that a scheduled raid grows with the colony instead of being the same fixed
 * hundred points forever.
 */
/datum/controller/subsystem/campaign/proc/get_raid_threat_budget()
	var/datum/colony_story_state/story = get_story_state()
	var/chapters_survived = story?.campaign_age || 0
	var/budget = COLONY_RAID_BASE_BUDGET + (chapters_survived * COLONY_RAID_BUDGET_PER_CHAPTER)
	budget = min(budget, COLONY_RAID_MAX_BUDGET)

	// Recovery runs 0-100 and already means "how much this colony is owed a quiet chapter". At its worst it
	// halves the attack rather than cancelling it; refusing outright is the storyteller's job, not the budget's.
	var/recovery_scale = 1 - (clamp(story?.recovery || 0, 0, 100) / 200)
	return max(COLONY_RAID_BASE_BUDGET / 2, round(budget * recovery_scale))

/**
 * Which incidents of `incident_category` could run right now.
 *
 * Asked before the storyteller spends anything, so a category with no runnable incident is simply never
 * bought. Concrete incidents arrive with Phase 3 Task 5; until then every category is legitimately empty and
 * the controls stay unbuyable, which is the correct behaviour rather than a gap.
 */
/datum/controller/subsystem/campaign/proc/get_eligible_incident_types(incident_category)
	RETURN_TYPE(/list)
	var/list/eligible = list()
	if(!incident_category || !is_campaign_active())
		return eligible

	for(var/datum/colony_incident/incident_type as anything in subtypesof(/datum/colony_incident))
		if(initial(incident_type.category) != incident_category)
			continue
		if(is_abstract_incident(incident_type))
			continue
		eligible += incident_type

	return eligible

/// TRUE for incident types that exist to be inherited from rather than run.
/datum/controller/subsystem/campaign/proc/is_abstract_incident(datum/colony_incident/incident_type)
	return initial(incident_type.abstract_incident)

/**
 * The most recent incident results, newest first.
 *
 * Deliberately short. The point is to stop the same story landing twice running, not to give the colony a
 * permanent memory that eventually rules everything out.
 */
/datum/controller/subsystem/campaign/proc/get_recent_incident_records(window = COLONY_INCIDENT_HISTORY_WINDOW)
	RETURN_TYPE(/list)
	var/list/recent = list()
	if(!length(incident_history))
		return recent

	for(var/index = length(incident_history); index >= 1 && length(recent) < window; index--)
		recent += list(incident_history[index])
	return recent

/**
 * How strongly this incident should be preferred right now.
 *
 * Two penalties, both fading with distance: having run recently, and sharing a flavour with something that
 * ran recently. The first stops repeats, the second stops three different storms in a row from feeling like
 * one long storm.
 *
 * Floored rather than allowed to reach zero, so recency can never empty a category out entirely.
 */
/datum/controller/subsystem/campaign/proc/get_incident_selection_weight(datum/colony_incident/incident_type)
	var/weight = COLONY_INCIDENT_BASE_WEIGHT
	var/list/recent = get_recent_incident_records()
	if(!length(recent))
		return weight

	var/list/own_tags = get_colony_incident_tags(incident_type)
	var/distance = 0
	for(var/list/record as anything in recent)
		distance++
		// Newest counts most. A repeat two incidents ago matters less than the one that just happened.
		var/recency = (length(recent) - distance + 1) / length(recent)

		if(record["incident_type"] == "[incident_type]")
			weight -= round(70 * recency)
			continue

		var/list/record_tags = record["tags"]
		if(!islist(record_tags))
			continue
		for(var/tag in own_tags)
			if(tag in record_tags)
				weight -= round(25 * recency)
				break

	return max(weight, COLONY_INCIDENT_MINIMUM_WEIGHT)

/**
 * Builds one incident of the given category, or null if none can run.
 *
 * Eligibility is asked of the candidate itself rather than guessed at from outside: an incident knows what it
 * needs, and building one only to discard it is cheap next to getting the answer wrong. Which of the eligible
 * ones gets built is weighted against what the colony has been through lately.
 */
/datum/controller/subsystem/campaign/proc/create_incident(incident_category)
	RETURN_TYPE(/datum/colony_incident)
	var/list/candidates = get_eligible_incident_types(incident_category)
	if(!length(candidates))
		return null

	var/list/weighted = list()
	for(var/incident_type in candidates)
		weighted[incident_type] = get_incident_selection_weight(incident_type)

	while(length(weighted))
		var/incident_type = pick_weight(weighted)
		weighted -= incident_type

		var/datum/colony_incident/candidate = new incident_type
		if(candidate.can_begin())
			LAZYADD(active_incidents, candidate)
			return candidate
		qdel(candidate)

	return null

/**
 * What the colony has been through, built from the manifest the first time it is asked for.
 *
 * Kept in `storyteller_state`, a manifest field that has been carried and migrated since Phase 2 with nothing
 * reading it - so pacing memory needs no schema of its own.
 */
/datum/controller/subsystem/campaign/proc/get_story_state()
	RETURN_TYPE(/datum/colony_story_state)
	if(!manifest)
		return null

	if(!story_state)
		story_state = new
		if(length(manifest.storyteller_state) && !story_state.deserialize(manifest.storyteller_state))
			log_game("Campaign [manifest.campaign_id] has an unreadable pacing record; the colony's recent history starts empty.")
	return story_state

/// Writes the live pacing state back into the manifest, which is what a commit will store.
/datum/controller/subsystem/campaign/proc/sync_story_state()
	if(manifest && story_state)
		manifest.storyteller_state = story_state.serialize()

/**
 * Files an incident's result against the chapter, and stops tracking the incident that produced it.
 *
 * This is the single wire between what happens and what pacing remembers: every incident resolves through
 * here, so nothing has to remember to report itself separately.
 */
/datum/controller/subsystem/campaign/proc/record_incident_result(datum/colony_incident_result/incident_result)
	if(!istype(incident_result))
		return FALSE

	var/list/record = incident_result.serialize()
	LAZYADD(incident_history, list(record))

	var/datum/colony_story_state/story = get_story_state()
	if(story)
		story.record_incident(record)
		sync_story_state()
	return TRUE

/**
 * Notes that the colony faced something serious this chapter.
 *
 * A chapter survived at the cost of a real fight is not a quiet one, and recovery must not fall for it -
 * otherwise a colony that wins every raid is treated as though nothing has been happening to it.
 */
/datum/controller/subsystem/campaign/proc/note_major_threat()
	faced_major_threat_this_chapter = TRUE
	var/datum/colony_story_state/story = get_story_state()
	if(story)
		story.record_major_threat()
		sync_story_state()
	return TRUE

/// Drops an incident that has stopped, so a finished one cannot block the next.
/datum/controller/subsystem/campaign/proc/forget_incident(datum/colony_incident/incident)
	LAZYREMOVE(active_incidents, incident)
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

	// A snapshot is a picture of now, so the clock in it reads now. This promotes nothing: the committed
	// pointer is untouched, and syncing does not rebase, so a later commit is unaffected by having done this.
	sync_campaign_time()

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

	// Taken before the checkpoint is staged, so the research and accounts written into the campaign record are
	// the ones belonging to the world being preserved alongside them.
	capture_research()
	capture_ledger()
	capture_roster()
	sync_campaign_time()

	// Aged before the checkpoint is staged, so the campaign record preserved alongside the world describes the
	// chapter that just ended rather than the one before it.
	var/datum/colony_story_state/closing_story = get_story_state()
	if(closing_story)
		closing_story.advance_chapter(COLONY_OUTCOME_SUCCESS, faced_major_threat_this_chapter)
		sync_story_state()

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
