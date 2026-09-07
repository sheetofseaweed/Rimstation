/**
 * Edits what the colony remembers about one person.
 *
 * The record is deliberately thin - status, how long they have been here, what they learned - because a
 * player's preferences already carry everything else. That thinness is what makes editing it safe: there is
 * nothing here that a body, a mind or an inventory also believes, so nothing can be put out of step with them.
 *
 * Status is the field worth having. A colonist marked dead by a bug, or one who should be counted as away
 * rather than lost, is otherwise stuck that way for the rest of the campaign.
 */
ADMIN_VERB(rimstation_edit_colonist_record, R_ADMIN, "Edit Colonist Record", "Changes a colonist's status, attendance or skills.", ADMIN_CATEGORY_COLONY)
	var/datum/colonist_roster/roster = SScampaign.get_roster()
	if(!roster || !length(roster.records))
		to_chat(user, span_warning("No campaign is loaded, or its roster is empty."))
		return

	var/datum/colonist_record/record = pick_colony_colonist_record(user, roster, "Which colonist?")
	if(!record)
		return

	var/list/fields = list(
		"Status - [record.status]" = "status",
		"Chapters attended - [record.chapters_attended]" = "attendance",
		"Clear their home point" = "home",
		"Clear their skills" = "skills",
	)
	var/chosen = tgui_input_list(user, "What about [record.display_name] should change?", "Colony Roster", fields)
	if(isnull(chosen))
		return

	switch(fields[chosen])
		if("status")
			var/new_status = tgui_input_list(user, "Status for [record.display_name]", "Colony Roster", COLONIST_STATUSES)
			if(isnull(new_status))
				return
			record.status = new_status
			to_chat(user, span_notice("[record.display_name] is now [new_status]."))

		if("attendance")
			var/attended = tgui_input_number(user, "Chapters attended", "Colony Roster", default = record.chapters_attended, max_value = 9999, min_value = 0, round_value = TRUE)
			if(isnull(attended))
				return
			record.chapters_attended = attended
			to_chat(user, span_notice("[record.display_name] has attended [attended] chapters."))

		if("home")
			record.home_point = null
			to_chat(user, span_notice("[record.display_name] no longer has a home point and can claim a new one."))

		if("skills")
			record.skills = list()
			to_chat(user, span_notice("[record.display_name]'s stored skills are cleared. What they learn this chapter is captured at the end of it as usual."))

	SScampaign.sync_roster()
	message_admins("[key_name_admin(user)] edited the colonist record for [record.display_name] ([record.colonist_id]).")
	log_admin("[key_name(user)] edited the colonist record for [record.display_name] ([record.colonist_id]).")


/**
 * Removes somebody from the roster entirely.
 *
 * A colonist who is gone rather than dead - a duplicate created by a bug, or a test record - has no state to
 * express that, and leaving them counted skews everything that reads the roster's size. Removal is not the
 * same as death and does not pretend to be: a dead colonist is part of the colony's history and stays in it.
 */
ADMIN_VERB(rimstation_remove_colonist_record, R_ADMIN, "Remove Colonist Record", "Deletes a colonist from the roster. Use death for someone who died.", ADMIN_CATEGORY_COLONY)
	var/datum/colonist_roster/roster = SScampaign.get_roster()
	if(!roster || !length(roster.records))
		to_chat(user, span_warning("No campaign is loaded, or its roster is empty."))
		return

	var/datum/colonist_record/record = pick_colony_colonist_record(user, roster, "Which colonist should be removed?")
	if(!record)
		return

	if(tgui_alert(user, "Remove [record.display_name] ([record.colonist_id]) from the roster? Somebody who died should be marked dead instead - the colony keeps its dead.", "Colony Roster", list("Remove", "Cancel")) != "Remove")
		return

	var/removed_name = record.display_name
	var/removed_id = record.colonist_id
	roster.records -= removed_id
	qdel(record)
	SScampaign.sync_roster()

	message_admins(span_boldwarning("[key_name_admin(user)] removed [removed_name] ([removed_id]) from the colony roster."))
	log_admin("[key_name(user)] removed [removed_name] ([removed_id]) from the colony roster.")
	to_chat(user, span_notice("[removed_name] is no longer on the roster."))


/// Reports the roster as it stands, without changing any of it.
ADMIN_VERB(rimstation_inspect_colony_roster, R_ADMIN, "Inspect Colony Roster", "Lists every colonist the colony remembers, with status and attendance.", ADMIN_CATEGORY_COLONY_DEBUG)
	var/datum/colonist_roster/roster = SScampaign.get_roster()
	if(!roster)
		to_chat(user, span_warning("No campaign is loaded, so there is no roster."))
		return

	var/list/lines = list()
	lines += "Roster: [length(roster.records)] colonists. Next number: [roster.next_colonist_number]."
	for(var/status in COLONIST_STATUSES)
		lines += "  [status]: [roster.count_by_status(status)]"
	lines += "---"

	for(var/colonist_id in roster.records)
		var/datum/colonist_record/record = roster.records[colonist_id]
		var/home = record.home_point ? "home [record.home_point["x"]],[record.home_point["y"]],[record.home_point["z"]]" : "no home"
		lines += "[record.display_name] ([colonist_id]) - [record.status], [record.chapters_attended] chapters, [length(record.skills)] skills, [home], ckey [record.owner_ckey || "none"]"

	to_chat(user, boxed_message(span_notice(lines.Join("\n"))))


/// Shared roster picker. Shows status and owner, because two colonists can carry the same display name.
/proc/pick_colony_colonist_record(client/user, datum/colonist_roster/roster, prompt)
	RETURN_TYPE(/datum/colonist_record)
	var/list/choices = list()
	for(var/colonist_id in roster.records)
		var/datum/colonist_record/record = roster.records[colonist_id]
		choices["[record.display_name] - [record.status] ([record.owner_ckey || "no ckey"])"] = colonist_id

	var/chosen = tgui_input_list(user, prompt, "Colony Roster", choices)
	if(isnull(chosen))
		return null
	return roster.records[choices[chosen]]
