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
	if(SScampaign.is_campaign_active())
		to_chat(user, span_warning("A campaign is already running: [SScampaign.manifest.campaign_id], generation [SScampaign.manifest.generation_id], chapter [SScampaign.manifest.chapter]."))
		return

	var/obj/structure/colony_core/core = locate() in world
	if(!core)
		to_chat(user, span_warning("There is no colony core on this map. A campaign here could never be lost, only saved, which is not a campaign."))
		return

	if(!CONFIG_GET(flag/persistent_save_enabled))
		to_chat(user, span_warning("Persistent saving is disabled in config, so a campaign would have nothing to commit."))
		return

	var/campaign_id = tgui_input_text(user, "Identifier for this campaign", "Colony Campaign", default = CAMPAIGN_DEFAULT_ID, max_length = 32)
	if(isnull(campaign_id))
		return

	if(!is_safe_campaign_id(campaign_id))
		to_chat(user, span_warning("'[campaign_id]' cannot be used as a directory name. Use letters, digits, dots, dashes and underscores."))
		return

	if(tgui_alert(user, "Start campaign '[campaign_id]'? This round becomes its first chapter, and the colony as it stands at round end will be committed.", "Colony Campaign", list("Start", "Cancel")) != "Start")
		return

	if(!SScampaign.create_campaign(campaign_id, key_name(user)))
		to_chat(user, span_warning("The campaign could not be started. It may already exist on disk - check the game log."))
		return

	message_admins("[key_name_admin(user)] started colony campaign [campaign_id]. This round is chapter 1.")
	log_admin("[key_name(user)] started colony campaign [campaign_id].")


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
