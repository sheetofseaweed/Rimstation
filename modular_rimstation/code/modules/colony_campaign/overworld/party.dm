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
	/**
	 * A cell this party is going to look at, for a journey with no site at the end of it.
	 *
	 * Exactly one of this and `destination_site_id` is ever set. A survey is the other kind of expedition: it
	 * buys map rather than goods, which on a region you have to walk to see is the scarcer of the two.
	 */
	var/survey_cell
	/// The planned walk out, as cell ids from home. Empty until a destination is chosen.
	var/list/route
	/// Which of the two offers was taken. Explanation and audit only; the route itself is authoritative.
	var/route_kind
	/// Where the party is standing on the region.
	var/current_cell = "0,0"
	/// Index in route of the cell being walked into. The route is always stored in walking order.
	var/next_leg_index = 1
	/// Campaign-clock readings for the leg in progress, so a countdown survives a reconnect.
	var/leg_started_at = 0
	var/leg_arrives_at = 0
	/// The far cell of a crossing the party turned round inside. Null on an ordinary crossing.
	var/leg_origin_cell
	/// Where the party walked out of the colony map, as list(x, y, z). Null when it left from the hitching post.
	var/list/exit_point
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
	exit_point = null
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
		// A party away from home can be sent on to another site, from a site or from the road back.
		OVERWORLD_PARTY_AT_SITE = list(OVERWORLD_PARTY_OUTBOUND, OVERWORLD_PARTY_RETURNING, OVERWORLD_PARTY_LOST),
		OVERWORLD_PARTY_RETURNING = list(OVERWORLD_PARTY_OUTBOUND, OVERWORLD_PARTY_DECISION, OVERWORLD_PARTY_COMPLETE, OVERWORLD_PARTY_LOST),
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
	// Readiness is meaningless until there is a plan to be ready for - of either kind.
	if(!length(route) || !has_destination())
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
/// `giving_the_word` is a member who counts as ready without having said so.
/datum/overworld_party/proc/everyone_ready(giving_the_word)
	if(!length(member_ids))
		return FALSE
	for(var/colonist_id in member_ids)
		if(colonist_id != giving_the_word && !(colonist_id in ready_member_ids))
			return FALSE
	return TRUE

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

/// Sends a party that has already left toward another site, from the cell it stands on.
/// Returns TRUE if it now has that order. Rations are not recharged.
/datum/overworld_party/proc/change_destination(datum/overworld_region/region, site_id, list/only_within)
	if(state != OVERWORLD_PARTY_OUTBOUND && state != OVERWORLD_PARTY_RETURNING && state != OVERWORLD_PARTY_AT_SITE)
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
	// One cell means the party stands on the site's own cell. That is an order only for a party walking off it.
	if(!length(planned) || (length(planned) < 2 && !leg_arrives_at))
		return FALSE

	if(state != OVERWORLD_PARTY_OUTBOUND && !set_state(OVERWORLD_PARTY_OUTBOUND, "the expedition changed its destination"))
		return FALSE

	destination_site_id = site_id
	survey_cell = null
	take_route(planned)
	return TRUE

/// Sends a party that has already left to look at unknown ground that touches known ground.
/// Returns TRUE if it now has that order.
/datum/overworld_party/proc/change_survey(datum/overworld_region/region, cell_id, list/only_within)
	if(state != OVERWORLD_PARTY_OUTBOUND && state != OVERWORLD_PARTY_RETURNING && state != OVERWORLD_PARTY_AT_SITE)
		return FALSE
	if(pending_decision)
		return FALSE
	if(!region?.cells[cell_id])
		return FALSE

	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(region_state?.is_discovered(cell_id))
		return FALSE

	// One step into the dark, from ground somebody has walked.
	var/list/reachable = only_within ? only_within.Copy() : list()
	reachable[cell_id] = TRUE
	var/list/planned = region.plan_route(current_cell, cell_id, route_kind || OVERWORLD_ROUTE_FASTEST, reachable)
	if(length(planned) < 2)
		return FALSE

	if(state != OVERWORLD_PARTY_OUTBOUND && !set_state(OVERWORLD_PARTY_OUTBOUND, "the expedition went to look at new ground"))
		return FALSE

	survey_cell = cell_id
	destination_site_id = null
	take_route(planned)
	return TRUE

/// Forgets the plan, keeping the people. Used when a destination stops being reachable or available.
/datum/overworld_party/proc/clear_destination(reason)
	if(!is_planning())
		return FALSE
	destination_site_id = null
	survey_cell = null
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
/datum/overworld_party/proc/departure_problem(datum/overworld_region/region, list/only_within, giving_the_word)
	if(!is_planning())
		return "This expedition has already left."
	if(!length(member_ids))
		return "Nobody has signed on."
	if(!has_destination())
		return "No destination has been chosen."
	if(survey_cell && !region?.cells[survey_cell])
		return "That stretch of country is not on this map."
	if(destination_site_id && !region?.sites[destination_site_id])
		return "That destination is not on this map."
	if(!region.is_valid_route(route, only_within))
		return "The planned route is no longer one the colony can walk."
	if(!everyone_ready(giving_the_word))
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
	if(muster_point())
		return null

	var/atom/anchor = muster_anchor()
	if(!anchor)
		return "This colony has no hitching post to muster at. Gather at the edge of the map instead."
	if(!length(member_ids))
		return null

	var/datum/colonist_roster/roster = SScampaign.get_roster()
	var/list/names = list()
	for(var/colonist_id in members_away_from(anchor))
		var/datum/colonist_record/record = roster?.get_record(colonist_id)
		names += record?.display_name || colonist_id

	return "Not everybody has gathered at [isturf(anchor) ? "the way out" : "the hitching post"]: [english_list(names)]."

/// Members who are not within gathering distance of `anchor`, as colonist ids.
/datum/overworld_party/proc/members_away_from(atom/anchor)
	RETURN_TYPE(/list)
	var/list/away = list()
	var/turf/centre = get_turf(anchor)
	for(var/colonist_id in member_ids)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		var/turf/standing = (body && body.stat != DEAD) ? get_turf(body) : null
		if(!standing || !centre || standing.z != centre.z || get_dist(standing, centre) > OVERWORLD_GATHER_RADIUS)
			away += colonist_id
	return away

/// Where the party is gathering: a member's turf at a way out if one stands there, else the hitching post.
/datum/overworld_party/proc/muster_anchor()
	for(var/colonist_id in member_ids)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		var/turf/standing = (body && body.stat != DEAD) ? get_turf(body) : null
		if(is_caravan_exit_turf(standing))
			return standing
	return get_caravan_hitching_post()

/// The place the whole party can leave from right now: the hitching post, or a way out. Null if not gathered.
/datum/overworld_party/proc/muster_point()
	if(!length(member_ids))
		return null
	var/obj/structure/caravan_hitching_post/post = get_caravan_hitching_post()
	if(post && !length(members_away_from(post)))
		return post
	var/atom/anchor = muster_anchor()
	if(isturf(anchor) && !length(members_away_from(anchor)))
		return anchor
	return null

/// Members standing where the party is gathering, as colonist ids.
/datum/overworld_party/proc/gathered_member_ids()
	RETURN_TYPE(/list)
	var/atom/anchor = muster_anchor()
	if(!anchor)
		return list()
	return member_ids - members_away_from(anchor)

/// The turf the party walked out of the colony map at, or null.
/datum/overworld_party/proc/exit_turf()
	RETURN_TYPE(/turf)
	if(length(exit_point) != 3)
		return null
	return locate(exit_point[1], exit_point[2], exit_point[3])

/// Flat list form for the manifest. Keep in step with deserialize().
/datum/overworld_party/proc/serialize()
	RETURN_TYPE(/list)
	return list(
		"party_id" = party_id,
		"state" = state,
		"member_ids" = member_ids.Copy(),
		"ready_member_ids" = ready_member_ids.Copy(),
		"destination_site_id" = destination_site_id,
		"survey_cell" = survey_cell,
		"route" = route.Copy(),
		"route_kind" = route_kind,
		"current_cell" = current_cell,
		"next_leg_index" = next_leg_index,
		"leg_started_at" = leg_started_at,
		"leg_arrives_at" = leg_arrives_at,
		"leg_origin_cell" = leg_origin_cell,
		"exit_point" = exit_point?.Copy(),
		// Marks a route stored in walking order. Older records counted a return down the outbound road.
		"route_forward" = TRUE,
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

	// An older record of a returning party: its road is the outbound one, with the index counting down.
	// Rewritten as the walk still ahead, so the travel code has one direction to follow.
	if(incoming_state == OVERWORLD_PARTY_RETURNING && !data["route_forward"])
		var/list/walk_back = list()
		for(var/index = min(length(incoming_route), incoming_leg + 1) to 1 step -1)
			walk_back += incoming_route[index]
		incoming_route = walk_back
		incoming_leg = 2

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
	survey_cell = istext(data["survey_cell"]) ? data["survey_cell"] : null
	route = incoming_route
	route_kind = incoming_kind
	current_cell = incoming_cell
	next_leg_index = incoming_leg
	leg_started_at = isnum(data["leg_started_at"]) ? data["leg_started_at"] : 0
	leg_arrives_at = isnum(data["leg_arrives_at"]) ? data["leg_arrives_at"] : 0
	leg_origin_cell = istext(data["leg_origin_cell"]) ? data["leg_origin_cell"] : null
	var/list/incoming_exit = data["exit_point"]
	exit_point = (islist(incoming_exit) && length(incoming_exit) == 3 && isnum(incoming_exit[1]) && isnum(incoming_exit[2]) && isnum(incoming_exit[3])) ? incoming_exit.Copy() : null
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
 * The route is stored in walking order in both directions. Index 1 is used only by a party that turned
 * round inside a crossing: it is walking back into the cell it stands on.
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
	return current_cell == OVERWORLD_HOME_CELL

/// TRUE when the party is standing on whatever it set out for - a site's cell, or a cell in its own right.
/datum/overworld_party/proc/at_destination(datum/overworld_region/region)
	if(survey_cell)
		return current_cell == survey_cell

	var/datum/overworld_site/site = region?.sites[destination_site_id]
	if(!site)
		return FALSE
	return current_cell == "[site.q],[site.r]"

/// TRUE once this expedition has somewhere to go, of either kind.
/datum/overworld_party/proc/has_destination()
	return !isnull(destination_site_id) || !isnull(survey_cell)

/// Turns the party for the colony from wherever it is. Returns TRUE if it now has that order.
/// The caller schedules a crossing when the party stood still; see take_route().
/datum/overworld_party/proc/begin_return(reason, datum/overworld_region/region, list/only_within)
	if(pending_decision)
		return FALSE

	var/list/road = way_home(region, only_within)
	if(!length(road))
		return FALSE
	if(state != OVERWORLD_PARTY_RETURNING && !set_state(OVERWORLD_PARTY_RETURNING, reason || "the expedition turned for home"))
		return FALSE

	// Whatever it went out for is behind it now.
	survey_cell = null
	destination_site_id = null
	take_route(road)
	return TRUE

/// The walk from the party's cell to the colony, as cell ids. Empty when there is none.
/// Uses the road it came out by when that road starts at the colony; otherwise asks the planner.
/datum/overworld_party/proc/way_home(datum/overworld_region/region, list/only_within)
	RETURN_TYPE(/list)
	var/standing_at = route.Find(current_cell)
	if(standing_at && state == OVERWORLD_PARTY_RETURNING && route[length(route)] == OVERWORLD_HOME_CELL)
		return route.Copy(standing_at)

	if(standing_at && state != OVERWORLD_PARTY_RETURNING && route[1] == OVERWORLD_HOME_CELL)
		var/list/back = list()
		for(var/index = standing_at to 1 step -1)
			back += route[index]
		return back

	var/list/planned = region?.plan_route(current_cell, OVERWORLD_HOME_CELL, route_kind || OVERWORLD_ROUTE_FASTEST, only_within)
	return planned || list()

/// Gives the party a new walk from the cell it stands on, without restarting a crossing in progress.
/// It carries on if the new walk uses that crossing, and walks back what it covered if not.
/datum/overworld_party/proc/take_route(list/new_route)
	// The other end of the crossing in progress, whichever way the party faces inside it.
	var/far_cell = leg_arrives_at ? (leg_origin_cell || leg_target_cell()) : null
	route = new_route.Copy()

	if(!far_cell || far_cell == current_cell)
		// Standing still. The caller schedules the crossing into the second cell.
		next_leg_index = 2
		leg_origin_cell = null
		leg_started_at = 0
		leg_arrives_at = 0
		return

	var/facing_away = isnull(leg_origin_cell)
	var/uses_crossing = (length(route) >= 2 && route[2] == far_cell)
	if(uses_crossing != facing_away)
		reverse_leg()

	if(uses_crossing)
		next_leg_index = 2
		leg_origin_cell = null
		return

	// Index 1 is the cell the party stands on: it is walking back into it.
	next_leg_index = 1
	leg_origin_cell = far_cell

/// Turns the party round inside its crossing. What it has covered becomes what is left to walk.
/datum/overworld_party/proc/reverse_leg()
	var/whole = leg_arrives_at - leg_started_at
	if(whole <= 0)
		return
	var/now = SScampaign.get_campaign_time()
	var/covered = clamp(now - leg_started_at, 0, whole)
	leg_started_at = now - (whole - covered)
	leg_arrives_at = now + covered

/// Seconds until the party reaches the end of its route, at the pace of a fed party.
/datum/overworld_party/proc/seconds_to_route_end(datum/overworld_region/region)
	var/total = 0
	if(leg_arrives_at)
		total += max(0, leg_arrives_at - SScampaign.get_campaign_time()) / (1 SECONDS)
	// With a crossing in progress its cell is already counted above.
	for(var/index in (leg_arrives_at ? next_leg_index + 1 : max(2, next_leg_index)) to length(route))
		var/datum/overworld_cell/cell = region?.cells[route[index]]
		total += cell?.traversal_seconds()
	return round(total)

/// The cells still to be walked, starting with the one the party stands on.
/datum/overworld_party/proc/road_ahead()
	RETURN_TYPE(/list)
	var/list/ahead = list(current_cell)
	for(var/index in max(1, next_leg_index) to length(route))
		if(route[index] != current_cell)
			ahead += route[index]
	return ahead

/// Rations needed to walk `walk_out` to its end and then home from there.
/// One ration a head for each cell entered.
/datum/overworld_party/proc/rations_to_finish(datum/overworld_region/region, list/walk_out, list/only_within)
	var/mouths = max(1, living_member_count())
	var/out_edges = max(0, length(walk_out) - 1)
	var/far_end = length(walk_out) ? walk_out[length(walk_out)] : current_cell
	var/list/back = region?.plan_route(far_end, OVERWORLD_HOME_CELL, route_kind || OVERWORLD_ROUTE_FASTEST, only_within)
	// No known way back from unseen ground. Assume it is as far home as it was out.
	var/back_edges = length(back) ? length(back) - 1 : out_edges
	return (out_edges + back_edges) * mouths

/// Rations the party must still eat to finish its journey and reach the colony. Zero when it is not away.
/datum/overworld_party/proc/rations_still_needed(datum/overworld_region/region, list/only_within)
	if(is_planning() || state == OVERWORLD_PARTY_DEPARTING || (state in OVERWORLD_PARTY_TERMINAL_STATES))
		return 0
	var/mouths = living_member_count()
	if(!mouths)
		return 0
	var/list/ahead = road_ahead()
	if(state == OVERWORLD_PARTY_RETURNING)
		return (length(ahead) - 1) * mouths
	return rations_to_finish(region, ahead, only_within)


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


/// TRUE when this expedition went out to look at country rather than to collect anything.
/datum/overworld_party/proc/is_surveying()
	return !isnull(survey_cell)

/**
 * Sends this party to look at one unknown cell.
 *
 * The target is unknown by definition, which is the whole difficulty: routes may only cross ground the colony
 * has walked, so a survey can only be aimed at a cell touching known country. The planner is given the
 * discovered set plus the target itself - one step into the dark, from somewhere real.
 */
/datum/overworld_party/proc/set_survey_destination(datum/overworld_region/region, cell_id, kind, list/only_within)
	if(!is_planning())
		return FALSE
	if(!region?.cells[cell_id])
		return FALSE
	if(!(kind in OVERWORLD_ROUTE_KINDS))
		return FALSE

	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(region_state?.is_discovered(cell_id))
		// Already on the map. Walking somewhere known to look at it would buy nothing.
		return FALSE

	var/list/reachable = only_within ? only_within.Copy() : list()
	reachable[cell_id] = TRUE

	var/list/planned = region.plan_route(current_cell, cell_id, kind, reachable)
	if(length(planned) < 2)
		return FALSE

	survey_cell = cell_id
	destination_site_id = null
	route = planned
	route_kind = kind
	next_leg_index = 1
	clear_readiness("the route changed")
	return TRUE

/**
 * Every unknown cell the colony could send somebody to look at.
 *
 * The frontier: cells nobody has walked that touch somewhere they have. Anything further out cannot be routed
 * to, because the ground in between is unknown as well - the map is opened one ring at a time, by walking.
 */
/proc/get_overworld_frontier_cells(datum/overworld_region/region)
	RETURN_TYPE(/list)
	var/list/frontier = list()
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(!region || !region_state)
		return frontier

	var/list/directions = OVERWORLD_AXIAL_DIRECTIONS
	for(var/known_id in region_state.discovered_cells)
		var/datum/overworld_cell/known = region.cells[known_id]
		if(!known)
			continue
		for(var/list/step as anything in directions)
			var/datum/overworld_cell/neighbour = region.get_cell(known.q + step[1], known.r + step[2])
			if(!neighbour || !neighbour.is_passable())
				continue
			var/neighbour_id = neighbour.cell_id()
			if(region_state.is_discovered(neighbour_id) || frontier[neighbour_id])
				continue
			frontier[neighbour_id] = TRUE

	return frontier
