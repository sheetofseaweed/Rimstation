/**
 * Ends the chapter now, on the same path the round ending would have taken.
 *
 * Deliberately routed through `resolve_chapter_at_round_end()` rather than reaching for the commit directly.
 * That proc is the one funnel every ending goes through - it decides between committing a colony that held and
 * closing a generation that did not, marks the outcome as having touched persistence, and hands anything it
 * cannot make sense of to recovery. An admin ending should differ from a natural one only in when it happens.
 *
 * Writing the checkpoint walks the whole map, so this takes a moment and the world is frozen while it does.
 */
ADMIN_VERB(rimstation_end_colony_chapter, R_ADMIN, "End Colony Chapter", "Ends and commits the chapter now, as though the round had ended.", ADMIN_CATEGORY_COLONY)
	if(!SScampaign.is_campaign_active())
		to_chat(user, span_warning("No campaign is running, so there is no chapter to end."))
		return

	if(!SScampaign.chapter_outcome)
		to_chat(user, span_warning("This chapter has no outcome record, so it cannot be ended cleanly. It is already a recovery case."))
		return

	var/list/endings = list(
		"The colony held - commit it" = COLONY_OUTCOME_SUCCESS,
		"The colony was lost - close the generation" = COLONY_OUTCOME_FAILURE,
	)
	var/chosen = tgui_input_list(user, "How did chapter [SScampaign.manifest.chapter] end?", "Colony Campaign", endings)
	if(isnull(chosen))
		return
	var/result = endings[chosen]

	var/reason = tgui_input_text(user, "Why? This is recorded against the chapter.", "Colony Campaign", "ended by an admin", max_length = MAX_MESSAGE_LEN)
	if(!reason)
		return

	if(tgui_alert(user, "End chapter [SScampaign.manifest.chapter] as [result]? [result == COLONY_OUTCOME_FAILURE ? "This closes the generation permanently." : "This writes a checkpoint and freezes the world while it does."]", "Colony Campaign", list("End Chapter", "Cancel")) != "End Chapter")
		return

	if(!SScampaign.chapter_outcome.is_resolved())
		SScampaign.chapter_outcome.resolve(result, reason)

	message_admins(span_boldwarning("[key_name_admin(user)] is ending colony chapter [SScampaign.manifest.chapter] as [result]: [reason]"))
	log_admin("[key_name(user)] ended colony chapter [SScampaign.manifest.chapter] as [result]: [reason]")

	if(!SScampaign.resolve_chapter_at_round_end())
		to_chat(user, span_warning("The chapter did not end cleanly. The campaign is now in state '[SScampaign.campaign_state]' - check the game log."))
		return

	to_chat(user, span_notice("Chapter ended as [result]. The campaign is in state '[SScampaign.campaign_state]'."))


/**
 * Closes the generation without pretending the chapter resolved.
 *
 * Separate from ending a chapter as a failure, because the two are different claims. A failed chapter is a
 * result the colony earned and the pacing state learns from. This is an admin saying the generation is over
 * regardless - for a colony wrecked by a bug, or one abandoned - and it goes straight to the closure.
 */
ADMIN_VERB(rimstation_declare_colony_defeat, R_ADMIN, "Declare Colony Defeat", "Closes the current generation permanently, without resolving the chapter.", ADMIN_CATEGORY_COLONY)
	if(!SScampaign.manifest)
		to_chat(user, span_warning("No campaign is loaded, so there is no generation to close."))
		return

	var/reason = tgui_input_text(user, "Why is this generation over?", "Colony Campaign", max_length = MAX_MESSAGE_LEN)
	if(!reason)
		return

	if(tgui_alert(user, "Close generation [SScampaign.manifest.generation_id] permanently? Its checkpoint stays on disk but stops being loadable, and the next round starts a new generation.", "Colony Campaign", list("Close It", "Cancel")) != "Close It")
		return

	if(!SScampaign.declare_defeat("[reason] (declared by [key_name(user)])"))
		to_chat(user, span_warning("The generation could not be closed from state '[SScampaign.campaign_state]'."))
		return

	message_admins(span_boldwarning("[key_name_admin(user)] declared the colony lost: [reason]"))
	log_admin("[key_name(user)] declared the colony lost: [reason]")
	to_chat(user, span_notice("Generation closed. The next round starts a new one."))


/**
 * Moves the campaign clock.
 *
 * The clock is derived from two origins rather than accumulated, so it cannot be nudged by writing a total -
 * moving it means moving the origin it counts from. Everything that stamps a moment reads this, so a clock
 * dragged backwards past entries that already exist would put the campaign's history out of order. Only
 * forward moves are offered for that reason.
 */
ADMIN_VERB(rimstation_set_campaign_clock, R_ADMIN, "Advance Campaign Clock", "Moves the campaign clock forward by a chosen number of hours.", ADMIN_CATEGORY_COLONY_DEBUG)
	if(!SScampaign.manifest)
		to_chat(user, span_warning("No campaign is loaded, so there is no clock."))
		return

	var/current = SScampaign.get_campaign_time()
	to_chat(user, span_notice("The campaign clock reads [DisplayTimeText(current)] ([current] deciseconds)."))

	var/hours = tgui_input_number(user, "Advance the clock by how many hours?", "Colony Campaign", default = 0, max_value = 8760, min_value = 0)
	if(isnull(hours) || !hours)
		return

	// The origin moves back by the amount the clock should move forward, which is the only way to shift a
	// derived total without breaking the arithmetic that produces it.
	SScampaign.chapter_clock_origin += (hours HOURS)
	SScampaign.sync_campaign_time()

	var/moved = SScampaign.get_campaign_time()
	message_admins("[key_name_admin(user)] advanced the campaign clock by [hours] hours, to [DisplayTimeText(moved)].")
	log_admin("[key_name(user)] advanced the campaign clock by [hours] hours.")
	to_chat(user, span_notice("The campaign clock now reads [DisplayTimeText(moved)]."))
