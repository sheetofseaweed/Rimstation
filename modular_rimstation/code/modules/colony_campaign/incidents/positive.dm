/**
 * Someone walks out of the wilds asking to be let in.
 *
 * The decision is food against hands: a refugee eats, and in exchange the colony gets another person who can
 * work. Taking them in costs stored rations up front, which is why it is a decision rather than a gift.
 *
 * Answerable at the colony core as well as a console. Deciding who joins the settlement by standing at the
 * heart of it is if anything more fitting than doing it over the radio.
 */
/datum/colony_incident/refugee
	name = "refugee"
	category = COLONY_INCIDENT_CATEGORY_POSITIVE
	tags = list(INCIDENT_TAG_ARRIVAL)
	warning_duration = 45 SECONDS
	answer_sources = INCIDENT_ANSWER_CONSOLE | INCIDENT_ANSWER_COLONY_CORE
	/// Rations the refugee needs to be taken in, if the settlement tracks any.
	var/food_price = 15
	/// What it costs instead when the settlement has no tracked stores to draw on.
	var/credit_price = 300
	/// What the colony actually paid, for the record.
	var/paid_in
	/// Set once they are actually admitted.
	var/admitted = FALSE
	/// The person who took the role, if anyone did.
	var/datum/weakref/refugee_ref

/datum/colony_incident/refugee/can_begin()
	if(!..())
		return FALSE
	// Somewhere to arrive at, and someone to arrive to.
	return !isnull(locate(/obj/structure/colony_core) in world)

/datum/colony_incident/refugee/announce_warning()
	priority_announce("Someone is approaching the settlement on foot from the wilds. They are asking to be let in.", "Colony Advisory")
	return TRUE

/datum/colony_incident/refugee/execute()
	var/content = "A traveller has reached the settlement and is asking for shelter.<br><br>\
		They will work for their keep, but they will need feeding: [food_price] units of stored food.<br><br>\
		Do we take them in?"

	if(!ask_colony("Refugee at the Gate", content, list("Take them in.", "Turn them away."), PROC_REF(on_answered)))
		resolve(COLONY_INCIDENT_OUTCOME_IGNORED)
		return FALSE
	return TRUE

/// Index 1 admits them, index 2 turns them away.
/datum/colony_incident/refugee/proc/on_answered(index)
	if(index != 1)
		priority_announce("The traveller has been turned away and is walking back into the wilds.", "Colony Advisory")
		resolve(COLONY_INCIDENT_OUTCOME_IGNORED, 1)
		return

	if(!pay_for_keep())
		priority_announce("The settlement cannot feed another mouth. The traveller moves on.", "Colony Advisory")
		resolve(COLONY_INCIDENT_OUTCOME_FAILED, 1)
		return

	// Offered to ghosts rather than spawned empty: a colonist nobody is playing is scenery, not a colonist.
	INVOKE_ASYNC(src, PROC_REF(offer_role))

/**
 * Takes the cost of feeding them, in stores if the settlement has any and in credits otherwise.
 *
 * Tracked stores are the better price and nothing produces them yet - harvests do not reach the ledger - so
 * without the fallback this incident could never succeed. When a producer exists the food path simply starts
 * being the one that gets used.
 */
/datum/colony_incident/refugee/proc/pay_for_keep()
	if(SScampaign.adjust_resource("food", -food_price, LEDGER_CATEGORY_INCIDENT, "fed a refugee", null, id))
		paid_in = "[food_price] stored food"
		return TRUE

	if(SScampaign.try_debit(credit_price, LEDGER_CATEGORY_INCIDENT, "bought in food for a refugee", null, id))
		paid_in = "[credit_price] credits"
		return TRUE

	return FALSE

/// Polls for someone to play the refugee, then places them if anyone takes it.
/datum/colony_incident/refugee/proc/offer_role()
	var/list/candidates = SSpolling.poll_ghost_candidates(
		"A settlement has agreed to take you in. Join them as a colonist?",
		ROLE_PAI,
		FALSE,
		30 SECONDS,
		role_name_text = "colony refugee",
	)

	if(!length(candidates))
		// The food is spent either way: the colony agreed to feed someone. Nobody came, which is its own story.
		priority_announce("The traveller never reached the gate.", "Colony Advisory")
		resolve(COLONY_INCIDENT_OUTCOME_FAILED, 1)
		return

	var/mob/dead/observer/chosen = pick(candidates)
	var/mob/living/carbon/human/arrival = spawn_refugee(chosen)
	if(!arrival)
		resolve(COLONY_INCIDENT_OUTCOME_FAILED, 1)
		return

	admitted = TRUE
	refugee_ref = WEAKREF(arrival)
	priority_announce("[arrival.real_name] has joined the settlement.", "Colony Advisory")
	resolve(COLONY_INCIDENT_OUTCOME_SUCCEEDED, -2)

/**
 * Puts the new colonist on the ground beside the core, in the colony's faction.
 *
 * They are a colonist in every way the game currently has one: colony faction, standing in the settlement,
 * saved with the map at the end of the chapter. Colonist *identity* - a record that survives as a person
 * rather than as a body - is Phase 4's job, and this deliberately does not fake it.
 */
/datum/colony_incident/refugee/proc/spawn_refugee(mob/dead/observer/candidate)
	RETURN_TYPE(/mob/living/carbon/human)
	var/obj/structure/colony_core/core = locate() in world
	var/turf/arrival_turf = core ? get_step(core, pick(GLOB.cardinals)) : null
	if(!arrival_turf || arrival_turf.density)
		arrival_turf = core ? get_turf(core) : null
	if(!arrival_turf)
		return null

	var/mob/living/carbon/human/arrival = new(arrival_turf)
	arrival.randomize_human_appearance()
	arrival.set_faction(list(RIMSTATION_COLONY_FACTION))
	arrival.equipOutfit(/datum/outfit/colonist_refugee)
	arrival.key = candidate.key
	return arrival

/datum/colony_incident/refugee/build_result(datum/colony_incident_result/building)
	building.record_telemetry("paid_in", paid_in)
	building.record_telemetry("admitted", admitted)

	if(admitted)
		building.add_consequence("the settlement took in a refugee, at a cost of [paid_in]")
		building.add_reward("another pair of hands")
	else
		building.add_consequence("the settlement did not take anyone in")
	return TRUE


/// What a refugee arrives wearing. Deliberately poor: they walked here.
/datum/outfit/colonist_refugee
	name = "Colony Refugee"
	uniform = /obj/item/clothing/under/color/grey
	shoes = /obj/item/clothing/shoes/workboots
	back = /obj/item/storage/backpack
