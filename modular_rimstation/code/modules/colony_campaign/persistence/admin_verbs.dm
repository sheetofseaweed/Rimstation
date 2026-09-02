/**
 * Admin entry point for starting a campaign.
 *
 * A campaign is deliberately not started by config or by booting a particular map. It is the only copy of its
 * colony from the moment it exists, so bringing one into being is an explicit act by a person, on a round they
 * are looking at. Every subsequent boot picks the campaign up from its manifest without being asked.
 *
 * The round this is run on becomes chapter one, and the colony as it stands at round end is what gets
 * committed - so it is meant to be run on a fresh colony round, not halfway through a ruined one.
 */
ADMIN_VERB(rimstation_start_colony_campaign, R_ADMIN, "Start Colony Campaign", "Begins a persistent campaign on this colony, committing it at round end.", ADMIN_CATEGORY_EVENTS)
	// The screen itself reports why a campaign cannot start, so the checks are not duplicated here - the reason
	// is more useful shown beside the button it disables than as a line of chat before anything opens.
	var/datum/campaign_setup/setup = new(key_name(user))
	setup.ui_interact(user.mob)


/**
 * Points this server at a campaign that already exists in storage.
 *
 * Takes effect at the next boot rather than now, because which colony is on the map was decided while the
 * world was loading and cannot be changed underneath the people standing on it.
 */
ADMIN_VERB(rimstation_resume_colony_campaign, R_ADMIN, "Resume Colony Campaign", "Sets which existing campaign this server runs, from the next round.", ADMIN_CATEGORY_EVENTS)
	var/list/campaigns = list_campaign_ids()
	if(!length(campaigns))
		to_chat(user, span_warning("There are no campaigns in storage to resume."))
		return

	var/chosen = tgui_input_list(user, "Which campaign should this server run?", "Colony Campaign", campaigns)
	if(isnull(chosen))
		return

	if(!write_active_campaign_id(chosen))
		to_chat(user, span_warning("The campaign pointer could not be written. Check the game log."))
		return

	message_admins("[key_name_admin(user)] set this server's campaign to [chosen]. It loads at the next round.")
	log_admin("[key_name(user)] set this server's campaign to [chosen].")
	to_chat(user, span_notice("This server will run campaign '[chosen]' from the next round. The current round keeps the map it already loaded."))


/**
 * Reports whether a checkpoint on disk is actually whole.
 *
 * Reads only. This is the question to ask before selecting something for recovery, and the answer separates
 * "the files are there" from "this finished being written".
 */
ADMIN_VERB(rimstation_validate_colony_checkpoint, R_ADMIN, "Validate Campaign Checkpoint", "Checks whether a checkpoint on disk is complete and loadable.", ADMIN_CATEGORY_DEBUG)
	if(!SScampaign.manifest)
		to_chat(user, span_warning("No campaign is loaded, so there is no generation whose checkpoints could be checked."))
		return

	var/datum/campaign_manifest/manifest = SScampaign.manifest
	var/list/checkpoints = list_campaign_checkpoint_ids(manifest.campaign_id, manifest.generation_id)
	if(!length(checkpoints))
		to_chat(user, span_warning("Generation [manifest.generation_id] has no checkpoints on disk."))
		return

	var/chosen = tgui_input_list(user, "Checkpoint to validate", "Colony Campaign", checkpoints)
	if(isnull(chosen))
		return

	var/datum/campaign_checkpoint/checkpoint = new(manifest.campaign_id, manifest.generation_id, chosen)
	var/complete = checkpoint.is_complete()
	var/artifacts_valid = checkpoint.validate_artifacts()
	var/loadable = SSworld_save.is_save_loadable(checkpoint.artifact_path)
	qdel(checkpoint)

	log_admin("[key_name(user)] validated campaign checkpoint [chosen]: complete=[complete], artifacts=[artifacts_valid], loadable=[loadable].")
	to_chat(user, boxed_message(span_notice(jointext(list(
		"Checkpoint: [chosen]",
		"Committed: [manifest.active_checkpoint_id == chosen ? "yes - this is what the campaign loads" : "no"]",
		"Finished being written: [complete ? "yes" : "NO - it has no completion marker"]",
		"Artifacts validate: [artifacts_valid ? "yes" : "NO"]",
		"Map is loadable: [loadable ? "yes" : "NO"]",
	), "\n"))))


/**
 * Loads something other than the committed checkpoint, for this boot only.
 *
 * Nothing is written: the committed pointer stays where it is, so a wrong choice costs a reboot and no more.
 */
ADMIN_VERB(rimstation_select_colony_recovery, R_ADMIN, "Select Campaign Recovery Snapshot", "Chooses a checkpoint to recover from instead of the committed one.", ADMIN_CATEGORY_DEBUG)
	if(!SScampaign.manifest)
		to_chat(user, span_warning("No campaign is loaded, so there is nothing to recover."))
		return

	var/list/snapshots = SScampaign.list_recovery_snapshots()
	if(!length(snapshots))
		to_chat(user, span_warning("This generation has no complete checkpoints to recover from."))
		return

	var/chosen = tgui_input_list(user, "Checkpoint to recover from", "Colony Campaign", snapshots)
	if(isnull(chosen))
		return

	if(tgui_alert(user, "Recover from '[chosen]'? The committed checkpoint stays where it is; this only changes what loads next.", "Colony Campaign", list("Recover", "Cancel")) != "Recover")
		return

	if(!SScampaign.select_recovery_snapshot(chosen, key_name(user)))
		to_chat(user, span_warning("'[chosen]' was refused. It may not be complete - validate it first."))
		return

	to_chat(user, span_notice("The next load will use '[chosen]'. The committed checkpoint is untouched."))


/**
 * Writes a fallback copy of the colony as it stands, without making it the campaign's checkpoint.
 *
 * Holds the world still while it writes, so the copy shows one moment rather than a mixture of several.
 */
ADMIN_VERB(rimstation_snapshot_colony_campaign, R_ADMIN, "Create Campaign Snapshot", "Writes the colony as it stands now as an uncommitted fallback copy.", ADMIN_CATEGORY_DEBUG)
	if(!SScampaign.manifest)
		to_chat(user, span_warning("No campaign is loaded, so there is nothing to snapshot."))
		return

	if(!SScampaign.can_mutate_world())
		to_chat(user, span_warning("The world is already being written. Wait for that to finish."))
		return

	var/snapshot_id = "snapshot-[time2text(world.realtime, "YYYY-MM-DD_hh.mm.ss", TIMEZONE_UTC)]"
	if(tgui_alert(user, "Write a snapshot of the colony as it stands? This pauses events while the map is written and does not change what the campaign loads.", "Colony Campaign", list("Write", "Cancel")) != "Write")
		return

	if(!SScampaign.create_snapshot(snapshot_id, key_name(user)))
		to_chat(user, span_warning("The snapshot could not be written. Check the game log."))
		return

	to_chat(user, span_notice("Snapshot '[snapshot_id]' written. Recover from it with Select Campaign Recovery Snapshot."))


/// What the campaign currently thinks is true, for diagnosing a colony that loaded as the wrong thing.
ADMIN_VERB(rimstation_inspect_colony_campaign, R_ADMIN, "Inspect Colony Campaign", "Reports the campaign's state, generation and committed checkpoint.", ADMIN_CATEGORY_DEBUG)
	if(!SScampaign.manifest)
		var/named = read_active_campaign_id()
		if(named)
			to_chat(user, span_warning("This server is set to run campaign '[named]', but no campaign loaded this round. Its manifest may be missing or unreadable - check the game log."))
		else
			to_chat(user, span_notice("No campaign is loaded, and none is named. This server is running ordinary persistence."))
		to_chat(user, span_notice("Campaigns in storage: [list_campaign_ids().Join(", ") || "none"]"))
		return

	var/datum/campaign_manifest/manifest = SScampaign.manifest
	var/list/report = list(
		"Campaign: [manifest.campaign_id]",
		"State: [SScampaign.campaign_state]([SScampaign.last_state_reason || "no reason recorded"])",
		"Generation: [manifest.generation_id] (number [manifest.generation_number])[manifest.generation_closed ? " - CLOSED: [manifest.closure_reason]" : ""]",
		"Chapter: [manifest.chapter], last outcome [manifest.last_outcome]",
		"Committed checkpoint: [manifest.active_checkpoint_id || "none"]",
		"Would load: [SScampaign.select_checkpoint_for_boot() || "a newly generated world"]",
	)

	if(SScampaign.recovery_selection)
		report += "Recovery snapshot [SScampaign.recovery_selection] selected by [SScampaign.recovery_selected_by || "unknown"]"

	var/list/snapshots = SScampaign.list_recovery_snapshots()
	report += "Recoverable checkpoints: [length(snapshots) ? snapshots.Join(", ") : "none"]"

	// How this chapter is going, and what decided it if anything has. The raid id is the only place the
	// attribution is visible - it goes to the round log otherwise, which is not somewhere you can look mid-round.
	var/datum/colony_chapter_outcome/outcome = SScampaign.chapter_outcome
	if(outcome?.is_resolved())
		report += "This chapter: [outcome.result] - [outcome.reason || "no reason recorded"]"
		report += "Decided by raid: [outcome.raid_id || "none - no raid was responsible"]"
	else if(outcome)
		report += "This chapter: still being played"

	// The region, which is derived rather than stored - so the fingerprint is the only way to tell whether the
	// world being drawn is the one the discoveries were recorded against.
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(region)
		report += "---"
		report += "Region: [region.options["extent"]] extent, [region.options["roughness"]] terrain, [region.options["abundance"]] resources"
		report += "Generator [region.generation_version], fingerprint [region.fingerprint]"
		report += "Explored: [length(region_state?.discovered_cells)] of [length(region.cells)] cells"

		var/list/changed = list()
		for(var/site_id in region_state?.site_states)
			changed += "[site_id] ([region_state.get_site_state(site_id)])"
		report += "Sites play has changed: [length(changed) ? changed.Join(", ") : "none"]"

		if(region_state && region_state.region_fingerprint && region_state.region_fingerprint != region.fingerprint)
			report += span_boldwarning("The stored discoveries were recorded against a DIFFERENT region. This is generator drift.")

	// Who is out there, and what it leaves behind. The first question after "was there a raid" is always how
	// many people were home for it.
	var/datum/overworld_party/expedition = SScampaign.get_active_party()
	if(expedition)
		report += "---"
		report += "Expedition [expedition.party_id]: [expedition.state], [length(expedition.member_ids)] signed on ([expedition.living_member_count()] alive)"
		report += "At [expedition.current_cell], heading for [expedition.leg_target_cell() || "nowhere"], bound for [expedition.destination_site_id || "nowhere yet"]"
		report += "Carrying [expedition.supplies] rations, [expedition.decisions_taken] interruption(s) answered"

		if(expedition.leg_arrives_at)
			var/remaining = max(0, expedition.leg_arrives_at - SScampaign.get_campaign_time())
			report += "Next boundary in [round(remaining / 10)] seconds of campaign time"

		if(expedition.pending_decision)
			var/list/offered = expedition.pending_decision["choices"]
			report += "HALTED on '[expedition.pending_decision["kind"]]' ([expedition.pending_decision["id"]]), offering: [length(offered) ? offered.Join(", ") : "nothing"]"

	report += "Colonists in the settlement: [length(get_colonists_physically_at_colony())]"

	// Reservations held this boot. These are never persisted, so this is the only place they can be seen.
	var/list/loaded = list()
	for(var/registry_key in GLOB.rimstation_overworld_destinations)
		loaded += registry_key
	report += "Scenes loaded this boot: [length(loaded) ? loaded.Join(", ") : "none"]"

	var/datum/colony_raid/attacker = get_attacking_colony_raid()
	if(attacker)
		report += "Raid in progress: [attacker.raid_id] ([attacker.state]), budget [attacker.threat_budget], [attacker.living_attacker_count()] attackers still standing"

	// Who the colony thinks lives here. The register console is the player-facing version of this.
	var/datum/colonist_roster/roster = SScampaign.get_roster()
	if(roster)
		var/here = 0
		var/away = 0
		var/dead = 0
		for(var/colonist_id in roster.records)
			var/datum/colonist_record/record = roster.records[colonist_id]
			switch(record.status)
				if(COLONIST_STATUS_ACTIVE)
					here++
				if(COLONIST_STATUS_AWAY)
					away++
				if(COLONIST_STATUS_DEAD)
					dead++
		report += "Roster: [length(roster.records)] colonists - [here] here, [away] away, [dead] dead"

	// Pacing is the thing you cannot see from in the world: recovery decides what the storyteller is willing
	// to throw next, so it has to be readable somewhere or it can only be judged by guessing.
	var/datum/colony_story_state/story = SScampaign.get_story_state()
	if(story)
		report += "---"
		report += "Campaign age: [story.campaign_age] chapters ([story.chapter_age] this generation)"
		report += "Recovery owed: [story.recovery]/100[story.is_recovering_hard() ? " - too battered for disasters" : ""]"
		report += "Recent loss: [story.recent_loss]/100"
		report += "Chapters since a major threat: [story.chapters_since_major_threat()]"
		report += "Storms weighted at: [story.get_event_weight_multiplier(list(TAG_DESTRUCTIVE))]x, quiet events at [story.get_event_weight_multiplier(list(TAG_NEUTRAL))]x"
		report += "Incidents remembered: [length(story.recent_incidents)]"

	to_chat(user, boxed_message(span_notice(report.Join("\n"))))


/**
 * Puts food in the colony's larder without anybody having had to grow it.
 *
 * For testing and for repairing a colony that lost its stores to a bug. Food is the one resource with a single
 * producer - the larder - so this stocks that rather than writing the ledger directly, which the next recount
 * would simply undo.
 */
ADMIN_VERB(rimstation_stock_colony_larder, R_ADMIN, "Stock Colony Larder", "Adds food units to the colony's larder.", ADMIN_CATEGORY_DEBUG)
	var/obj/structure/closet/crate/freezer/colony_larder/larder = get_colony_larder()
	if(!larder)
		to_chat(user, span_warning("This colony has no larder. Build or spawn an /obj/structure/closet/crate/freezer/colony_larder first."))
		return

	var/units = tgui_input_number(user, "How many units of food? The larder currently holds [count_colony_food()].", "Colony Larder", default = 50, max_value = 1000, min_value = 1)
	if(!units)
		return

	// Stocked as real items rather than as a number, so what an admin adds behaves exactly like what a colony
	// grew: it can be counted, taken back out, stolen by a raid, and saved with the map.
	var/loaves = CEILING(units / (10 / COLONY_FOOD_UNIT_NUTRIMENT), 1)
	for(var/index in 1 to loaves)
		new /obj/item/food/bread/plain(larder)

	sync_colony_food_to_ledger()
	log_admin("[key_name(user)] stocked the colony larder with [loaves] loaves ([count_colony_food()] units total).")
	to_chat(user, span_notice("Added [loaves] loaves. The larder now holds [count_colony_food()] units of food."))


/**
 * Debug tools for driving an expedition without waiting for one.
 *
 * These exist because a caravan takes real minutes to cross real ground, and one person testing alone cannot
 * sit through a full journey to check the third thing that happens on it. Every one of them logs, and none is
 * reachable from anything a player touches - they are a way to reach a state, not a way to play.
 */

/// Puts one hex on the map without anybody walking to it.
ADMIN_VERB(rimstation_reveal_overworld_cell, R_DEBUG, "Reveal Overworld Cell", "Marks one region cell as discovered.", ADMIN_CATEGORY_DEBUG)
	var/datum/overworld_region/region = get_active_overworld_region()
	if(!region)
		to_chat(user, span_warning("There is no region to reveal anything on."))
		return

	var/typed = tgui_input_text(user, "Which cell? Coordinates as 'q,r', with the colony at 0,0.", "Overworld Debug", "1,0")
	if(!typed)
		return
	if(!region.cells[typed])
		to_chat(user, span_warning("'[typed]' is not a cell on this region."))
		return

	var/revealed = SScampaign.discover_overworld_cell(typed)
	log_admin("[key_name(user)] revealed overworld cell [typed] ([revealed] cells newly seen).")
	to_chat(user, span_notice("Revealed [typed] and its surroundings ([revealed] newly seen)."))

/// Brings the current leg due immediately, so the next boundary happens on the next subsystem fire.
ADMIN_VERB(rimstation_advance_expedition_leg, R_DEBUG, "Advance Expedition Leg", "Makes the travelling party's current leg arrive now.", ADMIN_CATEGORY_DEBUG)
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party)
		to_chat(user, span_warning("No expedition exists."))
		return
	if(!party.leg_arrives_at)
		to_chat(user, span_warning("The expedition is not walking anywhere: it is [party.state]."))
		return

	// The clock is derived from an origin, so the leg is brought forward by moving the origin rather than by
	// writing the arrival time - anything else would be undone the moment the clock was read again.
	var/remaining = party.leg_arrives_at - SScampaign.get_campaign_time()
	if(remaining > 0)
		SScampaign.chapter_world_time_origin -= (remaining + 1)

	log_admin("[key_name(user)] brought expedition [party.party_id]'s leg forward by [round(remaining / 10)] seconds.")
	to_chat(user, span_notice("The leg is due now. It arrives on the next overworld tick."))

/// Stops the party at the next boundary with a chosen kind of problem.
ADMIN_VERB(rimstation_force_expedition_decision, R_DEBUG, "Force Expedition Decision", "Halts the travelling party with a chosen decision archetype.", ADMIN_CATEGORY_DEBUG)
	var/datum/overworld_party/party = SScampaign.get_active_party()
	var/datum/overworld_region/region = get_active_overworld_region()
	if(!party || !region)
		to_chat(user, span_warning("No expedition is travelling."))
		return
	if(party.state != OVERWORLD_PARTY_OUTBOUND)
		to_chat(user, span_warning("The expedition is [party.state]; only a party on its way out can be stopped."))
		return
	if(party.pending_decision)
		to_chat(user, span_warning("The expedition is already stopped by something."))
		return

	var/list/kinds = list()
	for(var/decision_id in GLOB.overworld_decisions)
		kinds += decision_id
	var/chosen = tgui_input_list(user, "Which kind of problem?", "Overworld Debug", kinds)
	if(!chosen)
		return

	var/datum/overworld_decision/archetype = get_overworld_decision(chosen)
	var/blocked_cell = party.leg_target_cell()
	if(!archetype || !blocked_cell)
		to_chat(user, span_warning("That decision could not be put in front of them."))
		return

	if(!party.set_state(OVERWORLD_PARTY_DECISION, "an admin put a problem in the road"))
		to_chat(user, span_warning("The expedition refused to stop."))
		return

	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	party.pending_decision = list(
		"id" = "decision-[party.party_id]-[region_state ? region_state.next_decision_number++ : 0]",
		"kind" = archetype.id,
		"name" = archetype.name,
		"reveal" = archetype.reveal_text,
		"cell" = blocked_cell,
		"choices" = archetype.available_choices(party, region, blocked_cell),
		"labels" = archetype.choice_copy.Copy(),
	)
	party.leg_started_at = 0
	party.leg_arrives_at = 0
	SScampaign.commit_party_change()

	log_admin("[key_name(user)] forced a '[chosen]' decision on expedition [party.party_id].")
	to_chat(user, span_notice("The expedition has stopped for a [archetype.name]."))

/**
 * Brings an expedition home from wherever it is, intact.
 *
 * The recovery tool rather than a gameplay one: it exists for a party that has ended up somewhere the game
 * cannot get it out of. It walks them home properly rather than teleporting, so the return, the refund and the
 * arrival all happen the way they normally would.
 */
ADMIN_VERB(rimstation_recall_expedition, R_DEBUG, "Recall Expedition", "Turns the travelling party around and sends it home.", ADMIN_CATEGORY_DEBUG)
	var/datum/overworld_party/party = SScampaign.get_active_party()
	var/datum/overworld_region/region = get_active_overworld_region()
	if(!party || !region)
		to_chat(user, span_warning("No expedition exists."))
		return

	if(tgui_alert(user, "Turn expedition [party.party_id] around and send it home from [party.current_cell]?", "Overworld Debug", list("Recall", "Cancel")) != "Recall")
		return

	// Cleared first: a party holding a question cannot be turned around, and the question is meaningless once
	// somebody has decided the journey is over.
	party.pending_decision = null
	if(party.state == OVERWORLD_PARTY_DECISION)
		party.set_state(OVERWORLD_PARTY_OUTBOUND, "recalled by an admin")
	if(party.state == OVERWORLD_PARTY_AT_SITE)
		party.begin_return("recalled by an admin")
	else if(!party.turn_for_home(region, SScampaign.get_overworld_state()?.discovered_cells))
		to_chat(user, span_warning("They could not be routed home from [party.current_cell]. The region may have changed under them."))
		return

	SSoverworld.schedule_leg(party, region)
	INVOKE_ASYNC(SSoverworld, TYPE_PROC_REF(/datum/controller/subsystem/overworld, board_for_return), party.party_id)
	SScampaign.commit_party_change()

	log_admin("[key_name(user)] recalled expedition [party.party_id] from [party.current_cell].")
	message_admins("[key_name_admin(user)] recalled colony expedition [party.party_id].")
	to_chat(user, span_notice("They are walking home from [party.current_cell]."))
