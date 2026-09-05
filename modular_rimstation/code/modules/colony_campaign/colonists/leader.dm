/// A colonist who can answer for the settlement. Not a head of staff: the rank is only a card the
/// communications console accepts, so an incident asking for a reply has somebody who can give one.
/datum/job/colony_leader
	title = JOB_COLONY_LEADER
	description = "Answer for the settlement. Take what comes over the radio, and live in the colony your answers build."
	faction = FACTION_STATION
	// Three, because an answer only one person can give is one the colony loses when they log off.
	total_positions = 3
	spawn_positions = 3
	supervisors = "nobody. You answer to the people who live with your decisions."
	exp_granted_type = EXP_TYPE_CREW
	outfit = /datum/outfit/job/colonist/leader
	plasmaman_outfit = /datum/outfit/plasmaman
	paycheck = PAYCHECK_LOWER
	paycheck_department = ACCOUNT_CIV
	display_order = JOB_DISPLAY_ORDER_CAPTAIN
	department_for_prefs = /datum/job_department/assistant
	job_flags = STATION_JOB_FLAGS
	config_tag = "COLONY_LEADER"
	colony_role = TRUE

/// A leader arrives the way any colonist does; the roster does not care what they were elected to do.
/datum/job/colony_leader/after_spawn(mob/living/spawned, client/player_client)
	. = ..()
	if(!ishuman(spawned) || !player_client)
		return
	settle_colonist(spawned, player_client.ckey)

/// Built on the planet rather than on the hub the rest of the fork latejoins to. Falls back if unplaced.
/datum/job/colony_leader/get_latejoin_spawn_point()
	var/atom/colony_arrival = get_colony_latejoin_spawn_point()
	return colony_arrival || ..()


/// The colonist kit, plus the hat that says who was asked.
/datum/outfit/job/colonist/leader
	name = JOB_COLONY_LEADER
	jobtype = /datum/job/colony_leader
	id_trim = /datum/id_trim/job/colony_leader
	head = /obj/item/clothing/head/cowboy/brown


/// The colonist trim plus ACCESS_COMMAND. Deliberately a superset: applying a trim clears the card first,
/// so a colonist promoted mid-campaign must not lose access on the way.
/datum/id_trim/job/colony_leader
	assignment = JOB_COLONY_LEADER
	trim_state = "trim_assistant"
	sechud_icon_state = SECHUD_ASSISTANT
	minimal_access = list(
		ACCESS_COMMAND,
		)
	extra_access = list(
		ACCESS_MAINT_TUNNELS,
		)
	template_access = list(
		ACCESS_CAPTAIN,
		ACCESS_CHANGE_IDS,
		)
	job = /datum/job/colony_leader


/**
 * Writes a leader's rank onto the card they are actually carrying. Returns TRUE if it changed one.
 *
 * The job dresses every arrival, but a returning colonist has that kit withdrawn and collects their own things
 * from a locker instead - see withdraw_issued_outfit(). The card in there was stamped whenever they last stored
 * it, so somebody elected between chapters comes back holding a colonist's card and finds the console shut.
 *
 * Hooked to collection rather than to spawning, because at spawn a returner is carrying nothing at all.
 */
/proc/stamp_colony_leader_access(mob/living/carbon/human/leader)
	if(!ishuman(leader) || !istype(leader.mind?.assigned_role, /datum/job/colony_leader))
		return FALSE

	var/obj/item/card/id/card = leader.get_idcard(hand_first = FALSE)
	if(!card || (ACCESS_COMMAND in card.access))
		return FALSE

	SSid_access.apply_trim_to_card(card, /datum/id_trim/job/colony_leader)
	log_game("Colony campaign: [key_name(leader)] collected a card that did not carry their leadership, so it was re-stamped.")
	return TRUE
