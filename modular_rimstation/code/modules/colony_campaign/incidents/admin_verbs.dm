/**
 * Runs a named incident now, through the machinery that would have scheduled it.
 *
 * Deliberately not a bare `new` on the incident. An incident owns no clock of its own - the carrier event
 * drives its warning window, its arrival and its end - so one built outside an event would announce itself and
 * then stand in warning until the round ended. Forcing therefore picks the incident and lets everything else
 * happen exactly as it would have.
 *
 * The incident still has to agree it can begin. An admin decides what happens to the colony, not whether the
 * world is in a state that can carry it.
 */
ADMIN_VERB(rimstation_force_colony_incident, R_ADMIN, "Force Colony Incident", "Runs a chosen colony incident now, on the usual warning and duration.", ADMIN_CATEGORY_COLONY)
	if(!SScampaign.is_campaign_active())
		to_chat(user, span_warning("No campaign is running, so there is no colony for an incident to happen to."))
		return

	var/list/choices = list()
	for(var/datum/colony_incident/incident_type as anything in subtypesof(/datum/colony_incident))
		if(SScampaign.is_abstract_incident(incident_type))
			continue
		choices["[initial(incident_type.name)] ([initial(incident_type.category)])"] = incident_type

	if(!length(choices))
		to_chat(user, span_warning("This build has no runnable colony incidents."))
		return

	var/chosen = tgui_input_list(user, "Which incident should happen?", "Colony Incident", choices)
	if(isnull(chosen))
		return

	var/datum/colony_incident/picked = choices[chosen]
	var/wanted_category = initial(picked.category)

	var/datum/round_event_control/colony_incident/carrier
	for(var/datum/round_event_control/colony_incident/candidate in SSevents.control)
		if(candidate.incident_category == wanted_category)
			carrier = candidate
			break

	if(!carrier)
		to_chat(user, span_warning("No event control schedules '[wanted_category]' incidents, so this one has nothing to carry it."))
		return

	carrier.forced_incident_type = picked
	carrier.run_event(announce_chance_override = 100, admin_forced = TRUE)

	message_admins("[key_name_admin(user)] forced colony incident [picked] ([wanted_category]).")
	log_admin("[key_name(user)] forced colony incident [picked].")


/**
 * Stops a running incident, either as cancelled or with a real outcome.
 *
 * The two are not interchangeable. Cancelling says nothing happened: reservations go back and the pacing state
 * learns nothing, which is what you want for an incident that fired by mistake. Resolving says the colony met
 * it and this is how it went, which is recorded and shapes what the storyteller offers next.
 */
ADMIN_VERB(rimstation_end_colony_incident, R_ADMIN, "End Colony Incident", "Cancels or resolves an incident that is currently running.", ADMIN_CATEGORY_COLONY)
	if(!length(SScampaign.active_incidents))
		to_chat(user, span_warning("No colony incidents are running."))
		return

	var/list/running = list()
	for(var/datum/colony_incident/incident as anything in SScampaign.active_incidents)
		running["[incident.name] - [incident.state] ([incident.id])"] = incident

	var/chosen = tgui_input_list(user, "Which incident should stop?", "Colony Incident", running)
	if(isnull(chosen))
		return

	var/datum/colony_incident/target = running[chosen]
	if(QDELETED(target))
		to_chat(user, span_warning("That incident is already gone."))
		return

	var/list/endings = list(
		"Cancel - it never happened" = "cancel",
		"Resolve as succeeded" = COLONY_INCIDENT_OUTCOME_SUCCEEDED,
		"Resolve as failed" = COLONY_INCIDENT_OUTCOME_FAILED,
		"Resolve as ignored" = COLONY_INCIDENT_OUTCOME_IGNORED,
	)
	var/how = tgui_input_list(user, "How should [target.name] end?", "Colony Incident", endings)
	if(isnull(how))
		return

	var/ending = endings[how]
	if(ending == "cancel")
		if(!target.cancel("ended by [key_name(user)]"))
			to_chat(user, span_warning("[target.name] could not be cancelled from state '[target.state]'."))
			return
		message_admins("[key_name_admin(user)] cancelled colony incident [target.id] ([target.name]).")
		log_admin("[key_name(user)] cancelled colony incident [target.id].")
		return

	if(!target.resolve(ending))
		to_chat(user, span_warning("[target.name] could not be resolved from state '[target.state]'."))
		return

	message_admins("[key_name_admin(user)] resolved colony incident [target.id] ([target.name]) as [ending].")
	log_admin("[key_name(user)] resolved colony incident [target.id] as [ending].")


/**
 * Reads and sets the two numbers that decide how hard the colony's next chapter is.
 *
 * Loss is what just went wrong and fades on its own; recovery is how much easier the colony is owed and only
 * comes down through quiet chapters. They are the storyteller's whole memory of the campaign, so being able to
 * read them is most of the value here - a colony being handed nothing but disasters, or nothing at all, is
 * explained by these two numbers and by nothing else.
 */
ADMIN_VERB(rimstation_set_storyteller_pressure, R_ADMIN, "Set Colony Storyteller Pressure", "Reads and adjusts the loss and recovery scores that pace the campaign.", ADMIN_CATEGORY_COLONY_DEBUG)
	var/datum/colony_story_state/story = SScampaign.get_story_state()
	if(!story)
		to_chat(user, span_warning("No campaign is loaded, so there is no pacing state."))
		return

	var/list/lines = list()
	lines += "Campaign age: [story.campaign_age] chapters. This generation: [story.chapter_age]."
	lines += "Recent loss: [story.recent_loss] / 100. Recovery owed: [story.recovery] / 100."
	lines += "Chapters since a major threat: [story.chapters_since_major_threat()]."
	lines += "Recovering hard: [story.is_recovering_hard() ? "yes - destructive incidents are being held back" : "no"]."
	lines += "Incidents remembered: [length(story.recent_incidents)]."
	to_chat(user, boxed_message(span_notice(lines.Join("\n"))))

	var/new_loss = tgui_input_number(user, "Recent loss (0-100)", "Colony Storyteller", default = story.recent_loss, max_value = 100, min_value = 0, round_value = TRUE)
	if(isnull(new_loss))
		return
	var/new_recovery = tgui_input_number(user, "Recovery owed (0-100)", "Colony Storyteller", default = story.recovery, max_value = 100, min_value = 0, round_value = TRUE)
	if(isnull(new_recovery))
		return

	story.recent_loss = new_loss
	story.recovery = new_recovery
	SScampaign.sync_story_state()

	message_admins("[key_name_admin(user)] set colony storyteller pressure to loss [new_loss], recovery [new_recovery].")
	log_admin("[key_name(user)] set colony storyteller pressure to loss [new_loss], recovery [new_recovery].")
