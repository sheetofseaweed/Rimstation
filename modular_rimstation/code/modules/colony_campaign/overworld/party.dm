/**
 * One caravan, from being assembled to being home or being lost.
 *
 * There is at most one of these at a time, which is a design decision rather than a limitation: a colony this
 * size cannot staff two expeditions, and every question about who is away has one answer while that is true.
 *
 * Everything here is validated against the region and the roster rather than trusted. A party is the only
 * thing in the campaign that carries people off the map, so a forged member id or a route through country
 * nobody has walked is not a display bug - it is colonists disappearing.
 */
/datum/overworld_party
	/// Stable identifier, issued once from a monotonic counter and never reused.
	var/party_id
	/// Where the journey is up to. Only ever changed through set_state().
	var/state = OVERWORLD_PARTY_FORMING
	/// Colonist ids signed on, in the order they signed on.
	var/list/member_ids
	/// Colonist ids that have said they are ready. Always a subset of member_ids.
	var/list/ready_member_ids
	/// The site this party is going to, or null while nobody has chosen.
	var/destination_site_id
	/// The planned walk out, as cell ids from home. Empty until a destination is chosen.
	var/list/route
	/// Which of the two offers was taken. Explanation and audit only; the route itself is authoritative.
	var/route_kind
	/// Where the party is standing on the region.
	var/current_cell = "0,0"
	/// Which leg of the route is next. 1 means it has not left the first cell.
	var/next_leg_index = 1
	/// Campaign-clock readings for the leg in progress, so a countdown survives a reconnect.
	var/leg_started_at = 0
	var/leg_arrives_at = 0
	/// Rations in hand. Debited whole at departure and spent down on the road.
	var/supplies = 0
	/// A question the road has put to the party, or null. One answer from any member clears it.
	var/list/pending_decision

/datum/overworld_party/New(party_id)
	. = ..()
	src.party_id = party_id
	member_ids = list()
	ready_member_ids = list()
	route = list()

/datum/overworld_party/Destroy(force)
	member_ids = null
	ready_member_ids = null
	route = null
	pending_decision = null
	return ..()

/**
 * Moves the party forward. Returns TRUE only if the move was allowed.
 *
 * The single place state changes, so the forward-only rule is enforced once instead of at every call site. A
 * finished or lost party can never reopen: both are states somebody has already been paid out or mourned for,
 * and reversing either would pay a journey twice.
 */
/datum/overworld_party/proc/set_state(new_state, reason)
	if(!(new_state in OVERWORLD_PARTY_STATES))
		return FALSE
	if(state == new_state)
		return FALSE
	if(state in OVERWORLD_PARTY_TERMINAL_STATES)
		log_game("Overworld party [party_id] refused [state] -> [new_state]: it is already finished.")
		return FALSE

	var/list/allowed = list(
		OVERWORLD_PARTY_FORMING = list(OVERWORLD_PARTY_DEPARTING, OVERWORLD_PARTY_LOST),
		OVERWORLD_PARTY_DEPARTING = list(OVERWORLD_PARTY_OUTBOUND, OVERWORLD_PARTY_LOST),
		OVERWORLD_PARTY_OUTBOUND = list(OVERWORLD_PARTY_DECISION, OVERWORLD_PARTY_AT_SITE, OVERWORLD_PARTY_RETURNING, OVERWORLD_PARTY_LOST),
		OVERWORLD_PARTY_DECISION = list(OVERWORLD_PARTY_OUTBOUND, OVERWORLD_PARTY_RETURNING, OVERWORLD_PARTY_LOST),
		OVERWORLD_PARTY_AT_SITE = list(OVERWORLD_PARTY_RETURNING, OVERWORLD_PARTY_LOST),
		OVERWORLD_PARTY_RETURNING = list(OVERWORLD_PARTY_DECISION, OVERWORLD_PARTY_COMPLETE, OVERWORLD_PARTY_LOST),
	)

	if(!(new_state in allowed[state]))
		log_game("Overworld party [party_id] refused [state] -> [new_state]([reason || "no reason"]).")
		return FALSE

	log_game("Overworld party [party_id] [state] -> [new_state]([reason || "no reason"]).")
	state = new_state
	return TRUE

/// TRUE while membership and the plan can still be edited.
/datum/overworld_party/proc/is_planning()
	return OVERWORLD_PARTY_IS_PLANNING(state)

/**
 * Why this colonist may not sign on, or null if they may.
 *
 * Returns the reason rather than a bare refusal because every one of these is shown beside the button it
 * disables. "You cannot join" with no explanation is the kind of thing people file bug reports about.
 */
/datum/overworld_party/proc/joining_problem(colonist_id)
	if(!is_planning())
		return "This expedition has already left."
	if(!istext(colonist_id) || !colonist_id)
		return "That is not a colonist."
	if(colonist_id in member_ids)
		return "They are already signed on."
	if(length(member_ids) >= OVERWORLD_PARTY_MAX_MEMBERS)
		return "The caravan is full."

	var/datum/colonist_roster/roster = SScampaign.get_roster()
	var/datum/colonist_record/record = roster?.get_record(colonist_id)
	if(!record)
		return "They are not on the colony's roster."
	if(record.status == COLONIST_STATUS_DEAD)
		return "They are dead."
	if(record.status == COLONIST_STATUS_AWAY)
		return "They are not in the colony this chapter."

	// A body, because a caravan carries people rather than records - and the body is what gets moved.
	var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
	if(!body || body.stat == DEAD)
		return "They are not up and about."

	// The locker is where their belongings wait while they are away. Without one there is nowhere to put them
	// back, and a returning colonist would arrive to an empty colony and no kit.
	if(!get_personal_colonist_locker(colonist_id))
		return "They have not claimed a personal locker to leave their things in."

	return null

/**
 * Signs one colonist on. Returns TRUE only if they were added by this call.
 *
 * Adding anybody invalidates everyone's readiness, because "I am ready" was said about a different expedition
 * than the one that now exists.
 */
/datum/overworld_party/proc/add_member(colonist_id)
	if(joining_problem(colonist_id))
		return FALSE

	member_ids += colonist_id
	clear_readiness("the party changed")
	return TRUE

/// Takes one colonist back off. Returns TRUE only if they were on it.
/datum/overworld_party/proc/remove_member(colonist_id)
	if(!is_planning())
		return FALSE
	if(!(colonist_id in member_ids))
		return FALSE

	member_ids -= colonist_id
	ready_member_ids -= colonist_id
	clear_readiness("the party changed")
	return TRUE

/// Records that one member has said they are ready. Only ever for themselves.
/datum/overworld_party/proc/set_ready(colonist_id, ready = TRUE)
	if(!is_planning())
		return FALSE
	if(!(colonist_id in member_ids))
		return FALSE
	if(!ready)
		ready_member_ids -= colonist_id
		return TRUE
	// Readiness is meaningless until there is a plan to be ready for.
	if(!length(route) || !destination_site_id)
		return FALSE
	if(colonist_id in ready_member_ids)
		return TRUE

	ready_member_ids += colonist_id
	return TRUE

/// Drops everybody's readiness. Called whenever the thing they agreed to changes underneath them.
/datum/overworld_party/proc/clear_readiness(reason)
	if(!length(ready_member_ids))
		return FALSE
	ready_member_ids.Cut()
	log_game("Overworld party [party_id] cleared readiness([reason || "no reason"]).")
	return TRUE

/// TRUE when everybody signed on has said yes, and there is somebody to say it.
/datum/overworld_party/proc/everyone_ready()
	return length(member_ids) && length(ready_member_ids) >= length(member_ids)

/**
 * Sets where the party is going and how it gets there.
 *
 * The route is planned here rather than accepted from whoever asked. A client picks between offers; it does
 * not get to describe the walk, because the walk is what the time, the risk and the food are computed from.
 */
/datum/overworld_party/proc/set_destination(datum/overworld_region/region, site_id, kind, list/only_within)
	if(!is_planning())
		return FALSE

	var/datum/overworld_site/site = region?.sites[site_id]
	if(!site)
		return FALSE
	if(!(kind in OVERWORLD_ROUTE_KINDS))
		return FALSE

	var/list/planned = region.plan_route(current_cell, "[site.q],[site.r]", kind, only_within)
	if(length(planned) < 2)
		return FALSE

	destination_site_id = site_id
	route = planned
	route_kind = kind
	next_leg_index = 1
	clear_readiness("the route changed")
	return TRUE

/// Forgets the plan, keeping the people. Used when a destination stops being reachable or available.
/datum/overworld_party/proc/clear_destination(reason)
	if(!is_planning())
		return FALSE
	destination_site_id = null
	route = list()
	route_kind = null
	clear_readiness(reason || "the destination was cleared")
	return TRUE

/// How many cell boundaries the party crosses going out. The way home costs the same again.
/datum/overworld_party/proc/outbound_edges()
	return max(0, length(route) - 1)

/**
 * The whole food bill for this journey, for this many people.
 *
 * Both directions plus a reserve, charged per head. Priced at planning time so it can be shown before anybody
 * commits, and charged only at departure - a party that never leaves eats nothing.
 */
/datum/overworld_party/proc/supply_cost()
	var/heads = length(member_ids)
	if(!heads || !length(route))
		return 0
	return ((OVERWORLD_SUPPLY_PER_EDGE * outbound_edges()) + OVERWORLD_SUPPLY_RESERVE) * heads

/**
 * Why this party cannot leave yet, or null if it can.
 *
 * Everything is rechecked here rather than relying on what was true when people signed on. Between the first
 * member joining and the last saying ready, somebody can have died, disconnected, or eaten the food.
 */
/datum/overworld_party/proc/departure_problem(datum/overworld_region/region, list/only_within)
	if(!is_planning())
		return "This expedition has already left."
	if(!length(member_ids))
		return "Nobody has signed on."
	if(!destination_site_id)
		return "No destination has been chosen."
	if(!region?.sites[destination_site_id])
		return "That destination is not on this map."
	if(!region.is_valid_route(route, only_within))
		return "The planned route is no longer one the colony can walk."
	if(!everyone_ready())
		return "Not everybody has said they are ready."

	for(var/colonist_id in member_ids)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(!body || body.stat == DEAD)
			var/datum/colonist_roster/roster = SScampaign.get_roster()
			var/datum/colonist_record/record = roster?.get_record(colonist_id)
			return "[record?.display_name || colonist_id] is no longer able to travel."

	// Asked of the larder and the budget together, because a colony that has not stocked up can still buy
	// rations in - it just pays for them.
	var/short = colony_food_problem(supply_cost())
	if(short)
		return short

	return null

/// Flat list form for the manifest. Keep in step with deserialize().
/datum/overworld_party/proc/serialize()
	RETURN_TYPE(/list)
	return list(
		"party_id" = party_id,
		"state" = state,
		"member_ids" = member_ids.Copy(),
		"ready_member_ids" = ready_member_ids.Copy(),
		"destination_site_id" = destination_site_id,
		"route" = route.Copy(),
		"route_kind" = route_kind,
		"current_cell" = current_cell,
		"next_leg_index" = next_leg_index,
		"leg_started_at" = leg_started_at,
		"leg_arrives_at" = leg_arrives_at,
		"supplies" = supplies,
		"pending_decision" = pending_decision?.Copy(),
	)

/**
 * Loads a record produced by serialize(). Returns TRUE on success.
 *
 * Everything is validated into locals before anything is assigned, so a record that turns out to be bad leaves
 * the party exactly as it was. A half-loaded caravan is worse than none: it would have members with no route,
 * or a route with no state, and the travel code would act on both.
 */
/datum/overworld_party/proc/deserialize(list/data)
	if(!islist(data))
		return FALSE

	var/incoming_id = data["party_id"]
	if(!istext(incoming_id) || !incoming_id)
		return FALSE

	var/incoming_state = data["state"]
	if(!(incoming_state in OVERWORLD_PARTY_STATES))
		return FALSE

	var/list/incoming_members = list()
	if(islist(data["member_ids"]))
		for(var/colonist_id in data["member_ids"])
			if(istext(colonist_id) && !(colonist_id in incoming_members))
				incoming_members += colonist_id

	var/list/incoming_ready = list()
	if(islist(data["ready_member_ids"]))
		for(var/colonist_id in data["ready_member_ids"])
			// Readiness is only meaningful for somebody who is actually on the party.
			if(istext(colonist_id) && (colonist_id in incoming_members) && !(colonist_id in incoming_ready))
				incoming_ready += colonist_id

	var/list/incoming_route = list()
	if(islist(data["route"]))
		for(var/cell_id in data["route"])
			if(istext(cell_id))
				incoming_route += cell_id

	var/incoming_kind = data["route_kind"]
	if(!isnull(incoming_kind) && !(incoming_kind in OVERWORLD_ROUTE_KINDS))
		incoming_kind = null

	var/incoming_cell = data["current_cell"]
	if(!istext(incoming_cell) || !incoming_cell)
		incoming_cell = "0,0"

	var/incoming_leg = data["next_leg_index"]
	if(!isnum(incoming_leg) || incoming_leg < 1 || incoming_leg != round(incoming_leg))
		incoming_leg = 1

	var/incoming_supplies = data["supplies"]
	if(!isnum(incoming_supplies) || incoming_supplies < 0)
		incoming_supplies = 0

	var/list/incoming_decision = islist(data["pending_decision"]) ? data["pending_decision"] : null

	party_id = incoming_id
	state = incoming_state
	member_ids = incoming_members
	ready_member_ids = incoming_ready
	destination_site_id = istext(data["destination_site_id"]) ? data["destination_site_id"] : null
	route = incoming_route
	route_kind = incoming_kind
	current_cell = incoming_cell
	next_leg_index = incoming_leg
	leg_started_at = isnum(data["leg_started_at"]) ? data["leg_started_at"] : 0
	leg_arrives_at = isnum(data["leg_arrives_at"]) ? data["leg_arrives_at"] : 0
	supplies = round(incoming_supplies)
	pending_decision = incoming_decision?.Copy()
	return TRUE

/// Notes a membership change in the round log, so who went out is answerable afterwards.
/datum/overworld_party/proc/log_membership(datum/colonist_record/record, what)
	log_game("Colony expedition [party_id]: [record?.display_name || "somebody"] [what] the expedition ([length(member_ids)] signed on).")

/// Tells the colony an expedition is leaving. A caravan going out is everybody's business - it is fewer hands.
/datum/overworld_party/proc/announce_departure()
	var/datum/colonist_roster/roster = SScampaign.get_roster()
	var/list/names = list()
	for(var/colonist_id in member_ids)
		var/datum/colonist_record/record = roster?.get_record(colonist_id)
		names += record?.display_name || colonist_id

	priority_announce(
		"An expedition has left the settlement: [english_list(names)]. The colony is short [length(names)] [length(names) == 1 ? "pair of hands" : "pairs of hands"] until they return.",
		"Expedition Departed",
		sound = null,
	)
