/**
 * The things the road puts in front of a caravan.
 *
 * One decision was enough to prove travel is not "click and wait". Three is enough that a second journey is not
 * the first one again, which is the whole of what this file adds.
 *
 * Each archetype is a singleton datum rather than a table of lists, because a choice needs to *do* something
 * and the doing does not fit in a list. They are instantiated once and looked up by id; nothing reads their
 * lists through `initial()`, which returns nothing for list vars and would silently make every archetype look
 * like it declared no choices at all.
 *
 * Which archetype a party meets is derived from the planet and the ground, never rolled. A party that reloads
 * finds the same problem waiting, and the ecology of the world it landed on decides what kind of problem that
 * tends to be - the costs are the same everywhere, only the frequency moves.
 */
/datum/overworld_decision
	/// Stable id, stored in the pending decision and matched when an answer arrives.
	var/id
	/// What the party is looking at.
	var/name
	/// Shown when the caravan stops. One sentence; the choices carry the detail.
	var/reveal_text
	/// Ordered choice ids. Every archetype must keep at least one that is always available.
	var/list/choice_ids
	/// Choice id to list(label, detail). Detail names the cost, because a choice with a hidden price is a trap.
	var/list/choice_copy

/datum/overworld_decision/New()
	. = ..()
	choice_ids = list()
	choice_copy = list()

/// Which of this archetype's choices the party can actually take right now.
/datum/overworld_decision/proc/available_choices(datum/overworld_party/party, datum/overworld_region/region, blocked_cell)
	RETURN_TYPE(/list)
	return choice_ids.Copy()

/// Applies one choice. Returns TRUE if the party is moving again afterwards.
/datum/overworld_decision/proc/apply_choice(datum/overworld_party/party, datum/overworld_region/region, choice_id, blocked_cell)
	return SSoverworld.schedule_leg(party, region)

/// Stamina and bruises for everybody who is actually here to feel them.
/datum/overworld_decision/proc/wear_down_party(datum/overworld_party/party, stamina, brute, message)
	for(var/colonist_id in party.member_ids)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(!body || body.stat == DEAD)
			continue
		if(stamina)
			body.adjust_stamina_loss(stamina)
		if(brute)
			body.adjust_brute_loss(brute)
		if(message)
			to_chat(body, span_warning(message))

/// Tells everybody on the party what just happened, wherever they are standing.
/datum/overworld_decision/proc/tell_party(datum/overworld_party/party, message)
	for(var/colonist_id in party.member_ids)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(body)
			to_chat(body, span_notice(message))


/**
 * Weather. The one that costs skin if you push through it.
 *
 * The original decision, kept as the archetype it always was: something in the way, and three honest answers -
 * take the damage, take the time, or take the long road.
 */
/datum/overworld_decision/weather_front
	id = OVERWORLD_DECISION_WEATHER
	name = "weather front"
	reveal_text = "A wall of weather is coming across the country ahead."

/datum/overworld_decision/weather_front/New()
	. = ..()
	choice_ids = list(OVERWORLD_CHOICE_PRESS_ON, OVERWORLD_CHOICE_SHELTER, OVERWORLD_CHOICE_SKIRT)
	choice_copy = list(
		OVERWORLD_CHOICE_PRESS_ON = list("Press on", "Walk into it. Everyone takes a beating."),
		OVERWORLD_CHOICE_SHELTER = list("Shelter", "Wait it out. Ninety seconds and a meal each."),
		OVERWORLD_CHOICE_SKIRT = list("Skirt it", "Go around. Longer, and the extra ground costs its own rations."),
	)

/datum/overworld_decision/weather_front/available_choices(datum/overworld_party/party, datum/overworld_region/region, blocked_cell)
	// Pressing on is always here. It is the answer that costs no rations, which is what stops a party being
	// stranded by a problem it cannot afford any other response to.
	var/list/offered = list(OVERWORLD_CHOICE_PRESS_ON)
	var/mouths = max(1, party.living_member_count())

	if(party.supplies >= (2 * mouths))
		offered += OVERWORLD_CHOICE_SHELTER

	var/list/detour = party.detour_route(region)
	if(length(detour) >= 2)
		var/added = (length(detour) - 1) - (length(party.route) - 1)
		if(party.supplies >= (added + 1) * mouths)
			offered += OVERWORLD_CHOICE_SKIRT

	return offered

/datum/overworld_decision/weather_front/apply_choice(datum/overworld_party/party, datum/overworld_region/region, choice_id, blocked_cell)
	switch(choice_id)
		if(OVERWORLD_CHOICE_SHELTER)
			return SSoverworld.apply_wait(party, region)
		if(OVERWORLD_CHOICE_SKIRT)
			return SSoverworld.apply_detour(party, region, blocked_cell)

	wear_down_party(party, OVERWORLD_DECISION_FORCE_STAMINA, OVERWORLD_DECISION_FORCE_BRUTE, "You push through the worst of it. It takes something out of you.")
	return SSoverworld.schedule_leg(party, region)


/**
 * Something large has been through here recently.
 *
 * No route change on this one: the animal is not in the way, it is *around*, and going around a whole range is
 * not a thing a caravan can do. The interesting axis is how much noise to make, and hunting turns a delay into
 * food - the one decision that can pay for itself.
 */
/datum/overworld_decision/predator_spoor
	id = OVERWORLD_DECISION_SPOOR
	name = "predator spoor"
	reveal_text = "Tracks cross the road ahead. Something big made them, and not long ago."

/datum/overworld_decision/predator_spoor/New()
	. = ..()
	choice_ids = list(OVERWORLD_CHOICE_KEEP_QUIET, OVERWORLD_CHOICE_SCARE_OFF, OVERWORLD_CHOICE_HUNT)
	choice_copy = list(
		OVERWORLD_CHOICE_KEEP_QUIET = list("Keep quiet", "Go slowly and stay downwind. Forty-five seconds."),
		OVERWORLD_CHOICE_SCARE_OFF = list("Scare it off", "Noise and fire. Tiring, but quick."),
		OVERWORLD_CHOICE_HUNT = list("Hunt it", "Ninety seconds and hard work, for meat on the road."),
	)

/datum/overworld_decision/predator_spoor/available_choices(datum/overworld_party/party, datum/overworld_region/region, blocked_cell)
	// Keeping quiet costs only time, so it is the one that is always affordable.
	var/list/offered = list(OVERWORLD_CHOICE_KEEP_QUIET)

	// Both of the others need somebody actually present to do them. A party nobody is playing cannot shout at
	// an animal or chase it down.
	if(party.living_member_count())
		offered += OVERWORLD_CHOICE_SCARE_OFF
		offered += OVERWORLD_CHOICE_HUNT

	return offered

/datum/overworld_decision/predator_spoor/apply_choice(datum/overworld_party/party, datum/overworld_region/region, choice_id, blocked_cell)
	switch(choice_id)
		if(OVERWORLD_CHOICE_SCARE_OFF)
			wear_down_party(party, OVERWORLD_DECISION_SCARE_STAMINA, 0, "You make yourselves loud and large until whatever it was thinks better of it.")
			return SSoverworld.schedule_leg(party, region)

		if(OVERWORLD_CHOICE_HUNT)
			wear_down_party(party, OVERWORLD_DECISION_SCARE_STAMINA, 0, "You run it down. Hard work, and worth it.")
			// Straight into what the party is carrying, not into the colony's larder. This is meat found on the
			// road; it never came through the settlement and it does not pass through its books.
			var/taken = party.living_member_count()
			party.supplies += taken
			SScampaign.record_nonfinancial(
				LEDGER_CATEGORY_EXPEDITION,
				"expedition_hunted",
				actor_id = null,
				related_id = party.party_id,
			)
			if(!SSoverworld.schedule_leg(party, region))
				return FALSE
			party.leg_arrives_at += (OVERWORLD_DECISION_WAIT_SECONDS SECONDS)
			return TRUE

	tell_party(party, "You go quietly, and whatever made the tracks never knows you passed.")
	if(!SSoverworld.schedule_leg(party, region))
		return FALSE
	party.leg_arrives_at += (OVERWORLD_DECISION_LOOK_SECONDS SECONDS)
	return TRUE


/**
 * Somebody else's fire, a long way off.
 *
 * The exploration decision. It costs time rather than blood, and pays in map - which on a region you have to
 * walk to survey is the scarcest thing there is.
 */
/datum/overworld_decision/distant_smoke
	id = OVERWORLD_DECISION_SMOKE
	name = "distant smoke"
	reveal_text = "There is smoke on the horizon, off the line of the road."

/datum/overworld_decision/distant_smoke/New()
	. = ..()
	choice_ids = list(OVERWORLD_CHOICE_IGNORE, OVERWORLD_CHOICE_OBSERVE, OVERWORLD_CHOICE_INVESTIGATE)
	choice_copy = list(
		OVERWORLD_CHOICE_IGNORE = list("Ignore it", "Not your business. Keep walking."),
		OVERWORLD_CHOICE_OBSERVE = list("Watch a while", "Forty-five seconds, and you learn what is over there."),
		OVERWORLD_CHOICE_INVESTIGATE = list("Go and look", "Ninety seconds and a meal each, and you learn what is around it too."),
	)

/datum/overworld_decision/distant_smoke/available_choices(datum/overworld_party/party, datum/overworld_region/region, blocked_cell)
	// Ignoring it is free and always available, which is what keeps this decision from ever stranding anybody.
	var/list/offered = list(OVERWORLD_CHOICE_IGNORE)

	// The other two need there to be something unseen to see. On a fully surveyed corner of the region there
	// is nothing to learn, and offering it anyway would be selling nothing.
	if(!isnull(unseen_neighbour(party, region)))
		offered += OVERWORLD_CHOICE_OBSERVE
		if(party.supplies >= (2 * max(1, party.living_member_count())))
			offered += OVERWORLD_CHOICE_INVESTIGATE

	return offered

/**
 * The nearest cell to the party that nobody has walked, chosen the same way twice.
 *
 * Sorted before picking so the answer does not depend on the order the region happened to build its cells in.
 */
/datum/overworld_decision/distant_smoke/proc/unseen_neighbour(datum/overworld_party/party, datum/overworld_region/region)
	var/datum/overworld_cell/standing = region?.cells[party.current_cell]
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(!standing || !region_state)
		return null

	var/list/candidates = list()
	var/list/directions = OVERWORLD_AXIAL_DIRECTIONS
	for(var/list/step as anything in directions)
		var/datum/overworld_cell/neighbour = region.get_cell(standing.q + step[1], standing.r + step[2])
		if(!neighbour)
			continue
		var/neighbour_id = neighbour.cell_id()
		if(region_state.is_discovered(neighbour_id))
			continue
		candidates += neighbour_id

	if(!length(candidates))
		return null
	return sort_list(candidates)[1]

/datum/overworld_decision/distant_smoke/apply_choice(datum/overworld_party/party, datum/overworld_region/region, choice_id, blocked_cell)
	var/target = unseen_neighbour(party, region)

	switch(choice_id)
		if(OVERWORLD_CHOICE_OBSERVE)
			if(target)
				SScampaign.get_overworld_state()?.discover_cell(region, target)
				SScampaign.sync_overworld()
				SScampaign.refresh_overworld_consoles()
				tell_party(party, "You watch a while, and put what is over there on the map.")
			if(!SSoverworld.schedule_leg(party, region))
				return FALSE
			party.leg_arrives_at += (OVERWORLD_DECISION_LOOK_SECONDS SECONDS)
			return TRUE

		if(OVERWORLD_CHOICE_INVESTIGATE)
			// A meal each for the walk out and back, and the ground around it comes back with you. Revealed
			// through the ordinary discovery funnel, so it serializes and reaches every open map.
			party.supplies = max(0, party.supplies - party.living_member_count())
			if(target)
				SScampaign.discover_overworld_cell(target)
				tell_party(party, "You walk out far enough to see properly, and come back knowing the country around it.")
			if(!SSoverworld.schedule_leg(party, region))
				return FALSE
			party.leg_arrives_at += (OVERWORLD_DECISION_WAIT_SECONDS SECONDS)
			return TRUE

	tell_party(party, "Whoever lit it is somebody else's problem. You keep walking.")
	return SSoverworld.schedule_leg(party, region)


/// Every archetype, built once and looked up by id.
GLOBAL_LIST_INIT(overworld_decisions, build_overworld_decision_table())

/proc/build_overworld_decision_table()
	RETURN_TYPE(/list)
	var/list/table = list()
	for(var/datum/overworld_decision/archetype as anything in subtypesof(/datum/overworld_decision))
		var/datum/overworld_decision/built = new archetype
		if(!built.id)
			continue
		table[built.id] = built
	return table

/// One archetype by id, or null.
/proc/get_overworld_decision(decision_id)
	RETURN_TYPE(/datum/overworld_decision)
	return GLOB.overworld_decisions[decision_id]

/**
 * Which kind of problem this party meets, derived rather than rolled.
 *
 * Keyed on the party, the ground and the planet's ecology, so it survives a reload and cannot be rerolled by
 * asking twice. The ecology profile biases which archetype comes up without ever changing what one costs - a
 * lively world meets more animals, not more expensive animals.
 */
/proc/pick_overworld_decision(datum/overworld_party/party, datum/overworld_region/region, blocked_cell)
	RETURN_TYPE(/datum/overworld_decision)
	var/list/table = GLOB.overworld_decisions
	if(!length(table))
		return null

	var/list/weights = OVERWORLD_DECISION_ECOLOGY_WEIGHTS
	var/list/bias = weights[region?.options?["roughness"]] || weights[OVERWORLD_ROUGHNESS_VARIED]

	var/hash = rustg_hash_string(RUSTG_HASH_SHA256, "decision-kind:[party.party_id]:[blocked_cell]")
	var/roll = hex2num(copytext(hash, 1, OVERWORLD_HASH_LENGTH + 1))
	if(!isnum(roll))
		return table[OVERWORLD_DECISION_WEATHER]

	var/total = 0
	for(var/decision_id in bias)
		total += bias[decision_id]
	if(total <= 0)
		return table[OVERWORLD_DECISION_WEATHER]

	var/landed = round(roll) % total
	var/running = 0
	for(var/decision_id in bias)
		running += bias[decision_id]
		if(landed < running)
			return table[decision_id] || table[OVERWORLD_DECISION_WEATHER]

	return table[OVERWORLD_DECISION_WEATHER]
