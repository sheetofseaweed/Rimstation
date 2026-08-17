/**
 * The settlement disagrees with itself, and somebody has to rule on it.
 *
 * Two colonists, one dispute, two rulings. Whoever is ruled against takes it badly and whoever is ruled for
 * takes it well, both through the mood system the game already has - so the consequence is carried by the
 * people involved rather than by an abstract number.
 *
 * Refusing to rule is a third answer in practice: the decision expires, both parties stay aggrieved, and the
 * settlement carries the pressure.
 */
/datum/colony_incident/dispute
	name = "settlement dispute"
	category = COLONY_INCIDENT_CATEGORY_SOCIAL
	tags = list(INCIDENT_TAG_UNREST)
	warning_duration = 30 SECONDS
	answer_sources = INCIDENT_ANSWER_CONSOLE | INCIDENT_ANSWER_COLONY_CORE
	/// The two colonists arguing.
	var/datum/weakref/first_party_ref
	var/datum/weakref/second_party_ref
	/// Which way it was settled. Zero if nobody ruled.
	var/ruling = 0

/datum/colony_incident/dispute/can_begin()
	if(!..())
		return FALSE
	return length(find_colonists()) >= 2

/// Living, playing colonists who could plausibly be arguing.
/datum/colony_incident/dispute/proc/find_colonists()
	RETURN_TYPE(/list)
	var/list/found = list()
	for(var/mob/living/carbon/human/person in GLOB.player_list)
		if(person.stat == DEAD || !person.client)
			continue
		found += person
	return found

/datum/colony_incident/dispute/select_target()
	var/list/colonists = find_colonists()
	if(length(colonists) < 2)
		return FALSE

	var/mob/living/carbon/human/first = pick(colonists)
	colonists -= first
	var/mob/living/carbon/human/second = pick(colonists)

	first_party_ref = WEAKREF(first)
	second_party_ref = WEAKREF(second)
	return TRUE

/datum/colony_incident/dispute/announce_warning()
	var/mob/living/carbon/human/first = first_party_ref?.resolve()
	var/mob/living/carbon/human/second = second_party_ref?.resolve()
	if(!first || !second)
		return FALSE

	priority_announce("An argument between [first.real_name] and [second.real_name] has spread through the settlement. Somebody will have to settle it.", "Colony Advisory")
	return TRUE

/datum/colony_incident/dispute/execute()
	var/mob/living/carbon/human/first = first_party_ref?.resolve()
	var/mob/living/carbon/human/second = second_party_ref?.resolve()
	if(!first || !second)
		// One of them left or died. There is no dispute left to settle.
		resolve(COLONY_INCIDENT_OUTCOME_IGNORED)
		return FALSE

	var/content = "[first.real_name] and [second.real_name] are at odds, and the settlement is taking sides.<br><br>\
		Someone has to rule on it. Whoever is ruled against will not take it well.<br><br>\
		Leaving it unsettled will suit nobody."

	if(!ask_colony("Settlement Dispute", content, list("Rule for [first.real_name].", "Rule for [second.real_name]."), PROC_REF(on_answered)))
		resolve(COLONY_INCIDENT_OUTCOME_IGNORED, 1)
		return FALSE
	return TRUE

/// Index 1 rules for the first party, index 2 for the second.
/datum/colony_incident/dispute/proc/on_answered(index)
	var/mob/living/carbon/human/first = first_party_ref?.resolve()
	var/mob/living/carbon/human/second = second_party_ref?.resolve()
	if(!first || !second)
		resolve(COLONY_INCIDENT_OUTCOME_IGNORED)
		return

	ruling = index
	var/mob/living/carbon/human/favoured = (index == 1) ? first : second
	var/mob/living/carbon/human/aggrieved = (index == 1) ? second : first

	favoured.add_mood_event("colony_dispute", /datum/mood_event/colony_dispute_won)
	aggrieved.add_mood_event("colony_dispute", /datum/mood_event/colony_dispute_lost)

	priority_announce("The dispute has been settled in [favoured.real_name]'s favour.", "Colony Advisory")
	// Settled is better than festering, but somebody still lost. A ruling relieves a little pressure, not all.
	resolve(COLONY_INCIDENT_OUTCOME_SUCCEEDED, -1)

/**
 * Nobody ruled, so both parties stay angry.
 *
 * Reached through the event clock rather than an answer, which is why the mood is applied here rather than in
 * the answer handler.
 */
/datum/colony_incident/dispute/begin_resolving()
	if(!..())
		return FALSE
	if(ruling)
		return TRUE

	for(var/datum/weakref/party_ref in list(first_party_ref, second_party_ref))
		var/mob/living/carbon/human/party = party_ref?.resolve()
		party?.add_mood_event("colony_dispute", /datum/mood_event/colony_dispute_unsettled)

	resolve(COLONY_INCIDENT_OUTCOME_FAILED, 2)
	return TRUE

/datum/colony_incident/dispute/build_result(datum/colony_incident_result/building)
	building.record_telemetry("ruling", ruling)

	if(ruling)
		building.add_consequence("the settlement ruled on a dispute, and one of them resented it")
	else
		building.add_consequence("a dispute was left unsettled and both sides resent it")
	return TRUE


/datum/mood_event/colony_dispute_won
	description = "The settlement took my side."
	mood_change = 3
	timeout = 10 MINUTES

/datum/mood_event/colony_dispute_lost
	description = "The settlement took their side over mine."
	mood_change = -4
	timeout = 10 MINUTES

/datum/mood_event/colony_dispute_unsettled
	description = "Nobody would settle it. It is still eating at me."
	mood_change = -2
	timeout = 10 MINUTES
