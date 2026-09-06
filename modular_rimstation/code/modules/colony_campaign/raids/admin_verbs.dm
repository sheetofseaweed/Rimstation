/**
 * Admin entry point for the Phase 1 raid.
 *
 * The storyteller does not schedule colony raids yet - that binding belongs to a later phase, once incident
 * pacing is tuned against a colony rather than a station. Until then this is how a raid is started, which is
 * also what makes the vertical slice testable on demand instead of on the storyteller's schedule.
 */
ADMIN_VERB(rimstation_start_colony_raid, R_ADMIN, "Start Colony Raid", "Begins a telegraphed raid on the colony core.", ADMIN_CATEGORY_COLONY)
	var/obj/structure/colony_core/core = get_colony_core()
	if(!core)
		to_chat(user, span_warning("There is no colony core on this map."))
		return

	if(!length(GLOB.rimstation_raid_insertion_points))
		to_chat(user, span_warning("This map has no raid insertion landmarks, so a raid would have nowhere valid to arrive."))
		return

	var/budget = tgui_input_number(user, "Threat budget for this raid", "Colony Raid", default = 100, max_value = 1000, min_value = 10)
	if(isnull(budget))
		return
	var/warning_seconds = tgui_input_number(user, "Seconds of warning before the assault", "Colony Raid", default = 120, max_value = 1800, min_value = 0)
	if(isnull(warning_seconds))
		return

	var/datum/colony_raid/raid = new
	raid.threat_budget = budget
	raid.warning_duration = warning_seconds SECONDS
	raid.objective_ref = WEAKREF(core)

	if(!raid.begin_warning())
		to_chat(user, span_warning("The raid could not deploy and cancelled itself: [raid.outcome_reason]."))
		qdel(raid)
		return

	message_admins("[key_name_admin(user)] started colony raid [raid.raid_id] with a budget of [budget].")
	log_admin("[key_name(user)] started colony raid [raid.raid_id] with a budget of [budget].")
