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


/**
 * Ends the running raid, on whatever terms the admin chooses.
 *
 * Three endings rather than one, because they are not the same event to anything downstream. A raid *repelled*
 * is a fight the colony won and the pacing state learns from; one *cancelled* never happened and teaches
 * nothing; a *retreat* is neither - the attackers are called off but the raid stays live until they are gone,
 * which is the only ending that leaves the colony a battlefield to clean up rather than an empty field.
 */
ADMIN_VERB(rimstation_end_colony_raid, R_ADMIN, "End Colony Raid", "Ends the running raid as repelled, cancelled, or a retreat.", ADMIN_CATEGORY_COLONY)
	var/datum/colony_raid/raid = get_attacking_colony_raid()
	if(!raid)
		to_chat(user, span_warning("No colony raid is running."))
		return

	var/list/endings = list(
		"Repelled - the colony won it" = COLONY_RAID_OUTCOME_REPELLED,
		"Succeeded - the attackers got what they came for" = COLONY_RAID_OUTCOME_SUCCEEDED,
		"Cancelled - it never happened" = COLONY_RAID_OUTCOME_CANCELLED,
		"Order a retreat - call them off and let them walk out" = "retreat",
	)
	var/chosen = tgui_input_list(user, "How should raid [raid.raid_id] end?", "Colony Raid", endings)
	if(isnull(chosen))
		return

	var/ending = endings[chosen]
	if(ending == "retreat")
		if(!raid.order_retreat())
			to_chat(user, span_warning("Raid [raid.raid_id] is not in a state that can retreat."))
			return
		message_admins("[key_name_admin(user)] ordered colony raid [raid.raid_id] to retreat.")
		log_admin("[key_name(user)] ordered colony raid [raid.raid_id] to retreat.")
		return

	if(!raid.resolve_raid(ending, "ended by [key_name(user)]"))
		to_chat(user, span_warning("Raid [raid.raid_id] has already ended as [raid.outcome]."))
		return

	message_admins("[key_name_admin(user)] ended colony raid [raid.raid_id] as [ending].")
	log_admin("[key_name(user)] ended colony raid [raid.raid_id] as [ending].")


/**
 * Reports what the running raid is actually doing.
 *
 * A raid is mostly invisible from outside: how many attackers are left, how far the core has been taken and
 * what the thing is even trying to do are all on the datum. Asking beforehand is how you decide whether to end
 * it, so this reads and changes nothing.
 */
ADMIN_VERB(rimstation_inspect_colony_raid, R_ADMIN, "Inspect Colony Raid", "Reports the running raid's state, strength and objective progress.", ADMIN_CATEGORY_COLONY_DEBUG)
	var/datum/colony_raid/raid = get_attacking_colony_raid()
	if(!raid)
		to_chat(user, span_notice("No colony raid is running."))
		return

	var/list/lines = list()
	lines += "Raid [raid.raid_id]: [raid.state][raid.outcome ? " ([raid.outcome]: [raid.outcome_reason])" : ""]"
	lines += "Goal: [raid.goal]. Faction: [raid.faction]."
	lines += "Budget [raid.threat_budget], deployed strength [raid.deployed_strength], live cap [raid.live_cap]."
	lines += "Attackers alive: [raid.living_attacker_count()] of [length(raid.roster)] spawned."
	lines += "Loot extracted: [raid.extracted_loot]."

	var/obj/structure/colony_core/core = raid.objective_ref?.resolve()
	if(core)
		var/progress = core.capture_duration ? round((core.capture_progress / core.capture_duration) * 100) : 0
		lines += "Core capture progress: [progress]%."
	else
		lines += "Core capture progress: no core to take."

	to_chat(user, boxed_message(span_notice(lines.Join("\n"))))
