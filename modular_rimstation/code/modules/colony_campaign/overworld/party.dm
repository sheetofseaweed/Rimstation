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
	/// How many interruptions this journey has answered. One is the whole of it for now; Task 6 adds more.
	var/decisions_taken = 0

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
		// Departing is the one state that can go backwards, and only to forming. Bringing up the travelling
		// camp sleeps, so departure has a gap in the middle of it; if anything has changed by the time that load
		// returns, the honest answer is that the expedition never left, not that it left into a broken world.
		OVERWORLD_PARTY_DEPARTING = list(OVERWORLD_PARTY_OUTBOUND, OVERWORLD_PARTY_FORMING, OVERWORLD_PARTY_LOST),
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

	// A site the colony has already emptied stays on the map as history, but nobody is walking three days to
	// stand in front of a hole somebody else finished. Refused here so the trip is never planned at all.
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(region_state && region_state.get_site_state(site_id) != OVERWORLD_SITE_STATE_AVAILABLE)
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

/**
 * Changes where a party already on the road is heading. Returns TRUE if it is now walking somewhere new.
 *
 * Only between cells, never mid-leg with a question outstanding: a party that could reroute while halted would
 * be answering the road by walking away from it. The route is recomputed from where they are standing rather
 * than from the colony, so the cost of changing your mind is only ever the ground still in front of you.
 */
/datum/overworld_party/proc/change_destination(datum/overworld_region/region, site_id, list/only_within)
	if(state != OVERWORLD_PARTY_OUTBOUND && state != OVERWORLD_PARTY_RETURNING)
		return FALSE
	if(pending_decision)
		return FALSE

	var/datum/overworld_site/site = region?.sites[site_id]
	if(!site)
		return FALSE

	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(region_state && region_state.get_site_state(site_id) != OVERWORLD_SITE_STATE_AVAILABLE)
		return FALSE

	var/list/planned = region.plan_route(current_cell, "[site.q],[site.r]", route_kind || OVERWORLD_ROUTE_FASTEST, only_within)
	if(length(planned) < 2)
		return FALSE

	// Rations are not recharged by changing plans. A party that turns for somewhere further than it packed for
	// will run short, and the supply check on the next leg is what says so.
	destination_site_id = site_id
	route = planned
	next_leg_index = 2
	set_state(OVERWORLD_PARTY_OUTBOUND, "the expedition changed its destination")
	return TRUE

/**
 * Turns a party on the road straight round for home, wherever it is.
 *
 * The way back is planned fresh from where they stand rather than reusing the outbound road, because they may
 * have rerouted since and the road they came by is not necessarily the one they are on.
 */
/datum/overworld_party/proc/turn_for_home(datum/overworld_region/region, list/only_within)
	if(state != OVERWORLD_PARTY_OUTBOUND && state != OVERWORLD_PARTY_RETURNING)
		return FALSE
	if(pending_decision)
		return FALSE

	var/list/planned = region?.plan_route(current_cell, "0,0", route_kind || OVERWORLD_ROUTE_FASTEST, only_within)
	if(length(planned) < 2)
		return FALSE

	// Stored forwards and walked backwards, like every other return: the travel code counts the index down.
	var/list/reversed = list()
	for(var/index = length(planned) to 1 step -1)
		reversed += planned[index]

	route = reversed
	destination_site_id = null
	current_cell = reversed[length(reversed)]
	next_leg_index = length(reversed) - 1
	set_state(OVERWORLD_PARTY_RETURNING, "the expedition turned for home")
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

	// And everybody has to actually be here. A caravan that left from wherever people happened to be standing
	// read as teleporting away rather than setting out.
	var/not_here = gathering_problem()
	if(not_here)
		return not_here

	return null

/**
 * Why the party is not gathered and ready to walk out, or null if it is.
 *
 * Named individually rather than counted, because "two people are missing" sends everybody looking at each
 * other, and "Vera Holt is not at the post" sends one person to the post.
 */
/datum/overworld_party/proc/gathering_problem()
	if(!get_caravan_hitching_post())
		return "This colony has no hitching post to muster at."

	var/list/absent = member_ids - party_members_at_post(src)
	if(!length(absent))
		return null

	var/datum/colonist_roster/roster = SScampaign.get_roster()
	var/list/names = list()
	for(var/colonist_id in absent)
		var/datum/colonist_record/record = roster?.get_record(colonist_id)
		names += record?.display_name || colonist_id

	return "Not everybody has gathered at the hitching post: [english_list(names)]."

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
		"decisions_taken" = decisions_taken,
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

	/**
	 * A stored question is only worth keeping while something can still ask it.
	 *
	 * The archetype it names is content, and content moves: a record can name one that no longer exists, or
	 * predate the whole idea of naming one. Either way this build cannot present the choices or accept an
	 * answer, and a party halted on a question nobody can ask never moves again.
	 *
	 * So it is dropped, and the halt is dropped with it - keeping the state without the question would trade a
	 * broken interface for a frozen expedition, which is the worse of the two.
	 */
	var/list/incoming_decision = islist(data["pending_decision"]) ? data["pending_decision"] : null
	if(incoming_decision && !get_overworld_decision(incoming_decision["kind"]))
		log_game("Overworld party [incoming_id] carried a decision this build cannot ask ('[incoming_decision["kind"] || "none named"]'); it and the halt have been dropped.")
		incoming_decision = null
		if(incoming_state == OVERWORLD_PARTY_DECISION)
			incoming_state = OVERWORLD_PARTY_OUTBOUND

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
	decisions_taken = (isnum(data["decisions_taken"]) && data["decisions_taken"] >= 0) ? round(data["decisions_taken"]) : 0
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


/**
 * The cell this party is currently walking into, or null if it is not between cells.
 *
 * `next_leg_index` is an index into the outbound route in both directions - the way home is the same road
 * walked backwards, so returning counts the index down rather than keeping a second route.
 */
/datum/overworld_party/proc/leg_target_cell()
	if(next_leg_index < 1 || next_leg_index > length(route))
		return null
	return route[next_leg_index]

/// How many of the people who signed on are still alive to eat and to carry things.
/datum/overworld_party/proc/living_member_count()
	var/alive = 0
	for(var/colonist_id in member_ids)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(body && body.stat != DEAD)
			alive++
	return alive

/// TRUE when the party is standing back at the colony.
/datum/overworld_party/proc/at_home()
	return current_cell == (length(route) ? route[1] : "0,0")

/// TRUE when the party is standing on the cell holding the site it set out for.
/datum/overworld_party/proc/at_destination(datum/overworld_region/region)
	var/datum/overworld_site/site = region?.sites[destination_site_id]
	if(!site)
		return FALSE
	return current_cell == "[site.q],[site.r]"

/**
 * Turns the party around and points it back down the road it came.
 *
 * The route is not recomputed. A party walks home the way it knows, which is also the way its remaining
 * rations were priced for - finding a shorter path back would be a different journey than the one paid for.
 */
/datum/overworld_party/proc/begin_return(reason)
	if(!set_state(OVERWORLD_PARTY_RETURNING, reason || "the expedition turned for home"))
		return FALSE

	// The index of where it is standing now, so the first step home is the cell before it.
	var/standing_at = route.Find(current_cell)
	next_leg_index = standing_at ? max(1, standing_at - 1) : 1
	return TRUE


/**
 * Which boundary of the outbound walk the road interrupts. Zero when there is nothing long enough to interrupt.
 *
 * Derived from the party id and the route rather than rolled, so it survives a reload: a party that reconnects
 * mid-journey finds the same interruption waiting at the same place rather than a freshly rolled one somewhere
 * else. Deriving it also means it cannot be rerolled by asking twice.
 */
/datum/overworld_party/proc/decision_boundary_index()
	var/boundaries = length(route) - 1
	if(boundaries < 1)
		return 0

	var/hash = rustg_hash_string(RUSTG_HASH_SHA256, "decision:[party_id]:[route.Join(">")]")
	var/roll = hex2num(copytext(hash, 1, OVERWORLD_HASH_LENGTH + 1))
	if(!isnum(roll))
		return 1
	// Indexes the cell being walked into, so the first boundary a party can be stopped at is the second cell.
	return 2 + (round(roll) % boundaries)

/// TRUE when this boundary is the one the road has something to say about, and it has not said it yet.
/datum/overworld_party/proc/decision_is_due()
	if(decisions_taken > 0 || pending_decision)
		return FALSE
	if(state != OVERWORLD_PARTY_OUTBOUND)
		return FALSE
	return next_leg_index == decision_boundary_index()

/**
 * A way to the destination that does not cross the cell in front of them.
 *
 * Recomputed by the server from the cell the party is standing on, so a detour is a real walk with real costs
 * rather than a discount for having been interrupted.
 */
/datum/overworld_party/proc/detour_route(datum/overworld_region/region)
	RETURN_TYPE(/list)
	var/blocked = leg_target_cell()
	var/list/discovered = SScampaign.get_overworld_state()?.discovered_cells
	if(!region || !blocked || !length(route))
		return list()

	// The blocked cell is taken out of what the planner may walk through. Everything else the colony has seen
	// is still fair ground.
	var/list/without_blocked = list()
	for(var/cell_id in discovered)
		if(cell_id != blocked)
			without_blocked[cell_id] = TRUE

	return region.plan_route(current_cell, route[length(route)], route_kind || OVERWORLD_ROUTE_FASTEST, without_blocked)
