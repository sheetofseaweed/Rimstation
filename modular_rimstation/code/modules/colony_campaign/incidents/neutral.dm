/**
 * A trader hailing the settlement with an offer that expires.
 *
 * Answered on a communications console and nowhere else. A caravan on the radio is not something you reply to
 * by touching a monument in the middle of the colony, and a settlement that has not built a console yet has an
 * ordinary in-game reason it cannot take the call.
 *
 * The offer is deliberately a logistics decision rather than a shop: the goods arrive by pod at a spot the
 * colony has to walk to, and the price is paid out of the settlement's account before anything is sent.
 */
/datum/colony_incident/trader
	name = "trade caravan"
	category = COLONY_INCIDENT_CATEGORY_NEUTRAL
	tags = list(INCIDENT_TAG_TRADE, INCIDENT_TAG_ARRIVAL)
	warning_duration = 30 SECONDS
	answer_sources = INCIDENT_ANSWER_CONSOLE
	/// What the caravan wants for its cargo.
	var/asking_price = 0
	/// What it is selling, as a type to quantity.
	var/list/offered_goods
	/// Set once the colony agrees and the goods are actually sent.
	var/deal_struck = FALSE

/datum/colony_incident/trader/can_begin()
	if(!..())
		return FALSE
	// No console, no call. This is a real constraint on the colony rather than a reason to route around it.
	return length(GLOB.shuttle_caller_list) > 0

/datum/colony_incident/trader/select_target()
	// Priced against what the settlement can actually pay, so an offer is always tempting and never impossible.
	var/datum/settlement_ledger/settlement = SScampaign.get_ledger()
	var/available = settlement?.credits || 0
	asking_price = max(250, FLOOR(available * 0.35, 50))

	offered_goods = list(
		/obj/item/stack/sheet/iron/fifty = 2,
		/obj/item/stack/sheet/glass/fifty = 1,
		/obj/item/stack/medical/wrap = 3,
	)
	return TRUE

/datum/colony_incident/trader/announce_warning()
	priority_announce("A trade caravan is hailing the settlement. They are asking for an answer at a communications console.", "Incoming Transmission")
	return TRUE

/datum/colony_incident/trader/execute()
	var/list/manifest = list()
	for(var/goods_type in offered_goods)
		var/atom/goods = goods_type
		manifest += "[offered_goods[goods_type]]x [initial(goods.name)]"

	var/content = "We are passing your settlement and will trade before we move on.<br><br>\
		Offered: [english_list(manifest)]<br>\
		Price: [asking_price] credits<br><br>\
		We will not wait long."

	if(!ask_colony("Trade Caravan", content, list("Accept the trade.", "Send them on their way."), PROC_REF(on_answered)))
		// Nobody could be asked, so nobody turned it down.
		resolve(COLONY_INCIDENT_OUTCOME_IGNORED)
		return FALSE
	return TRUE

/// Runs when the colony answers. Index 1 accepts, index 2 declines.
/datum/colony_incident/trader/proc/on_answered(index)
	if(index != 1)
		priority_announce("Understood. We will trade elsewhere.", "Trade Caravan")
		resolve(COLONY_INCIDENT_OUTCOME_IGNORED)
		return

	// Paid before anything is sent, and refused outright if the settlement cannot cover it - a caravan does not
	// extend credit to a colony it has just met.
	if(!SScampaign.try_debit(asking_price, LEDGER_CATEGORY_TRADE, "trade caravan goods", null, id))
		priority_announce("Your account does not cover the price. We will move on.", "Trade Caravan")
		resolve(COLONY_INCIDENT_OUTCOME_FAILED, 1)
		return

	deal_struck = TRUE
	deliver_goods()
	priority_announce("Payment received. Your cargo is on its way down.", "Trade Caravan")
	resolve(COLONY_INCIDENT_OUTCOME_SUCCEEDED, -1)

/// Drops the goods somewhere the colony has to go and collect them.
/datum/colony_incident/trader/proc/deliver_goods()
	var/turf/landing = find_delivery_turf()
	if(!landing)
		return FALSE

	var/obj/structure/closet/supplypod/pod = new
	pod.explosionSize = list(0, 0, 0, 0)
	for(var/goods_type in offered_goods)
		for(var/i in 1 to offered_goods[goods_type])
			new goods_type(pod)
	new /obj/effect/pod_landingzone(landing, pod)
	return TRUE

/// Somewhere open near the colony core, so the drop is a short walk rather than an expedition.
/datum/colony_incident/trader/proc/find_delivery_turf()
	RETURN_TYPE(/turf)
	var/obj/structure/colony_core/core = locate() in world
	if(!core)
		return null

	var/list/candidates = list()
	for(var/turf/open/candidate in range(7, core))
		if(candidate.density || isspaceturf(candidate))
			continue
		candidates += candidate
	return length(candidates) ? pick(candidates) : get_turf(core)

/datum/colony_incident/trader/build_result(datum/colony_incident_result/building)
	building.record_telemetry("asking_price", asking_price)
	building.record_telemetry("deal_struck", deal_struck)

	if(deal_struck)
		building.add_consequence("the settlement traded [asking_price] credits for supplies")
		building.add_reward("caravan supplies")
	else
		building.add_consequence("the caravan moved on without trading")
	return TRUE
