/**
 * The thing that actually moves a caravan.
 *
 * Owns no persistent state whatsoever. SScampaign holds the party record and writes it to disk; this only
 * decides when the next boundary is due and asks for one transition. That split is what lets a chapter end,
 * or the server reboot, in the middle of a journey without this subsystem having an opinion about it.
 *
 * Time comes from `SScampaign.get_campaign_time()` rather than from world.time or from counting fires. A leg
 * that was scheduled to arrive at a given campaign-clock reading arrives at that reading whether the server
 * was keeping up or not, and a client that closes the map and reopens it computes the same position from the
 * same number.
 */
SUBSYSTEM_DEF(overworld)
	name = "Overworld"
	wait = 1 SECONDS
	runlevels = RUNLEVEL_GAME
	ss_flags = SS_BACKGROUND
	/// Set while a scene is being brought up, so a second fire cannot start the same load again.
	var/loading_destination = FALSE

/datum/controller/subsystem/overworld/fire(resumed = FALSE)
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party)
		return
	// Being assembled, finished, or lost: none of those are journeys in progress.
	if(party.is_planning() || (party.state in OVERWORLD_PARTY_TERMINAL_STATES))
		return
	// A checkpoint is being written and the world has to hold still for it. The leg is not lost - it is due at
	// a campaign-clock reading, and that reading will still have passed on the next fire.
	if(!SScampaign.can_mutate_world())
		return

	advance_party(party)

/**
 * Moves the party on by at most one boundary. Returns TRUE if something happened.
 *
 * At most one, deliberately. Catching up through several missed legs in a single fire would fire several
 * arrivals, several food charges and several discoveries in one tick, and would do it at the exact moment the
 * server was already struggling enough to fall behind.
 */
/datum/controller/subsystem/overworld/proc/advance_party(datum/overworld_party/party)
	if(party.state != OVERWORLD_PARTY_OUTBOUND && party.state != OVERWORLD_PARTY_RETURNING)
		return FALSE
	if(!party.leg_arrives_at)
		return FALSE
	if(SScampaign.get_campaign_time() < party.leg_arrives_at)
		return FALSE

	return complete_leg(party)

/**
 * The party crosses into the cell it was walking towards.
 *
 * Everything that happens on arrival happens here, in one order, once: the position moves, the rations are
 * eaten, the ground is revealed, and only then is the next leg scheduled. Anything that wants to interrupt the
 * journey does so by leaving the party in a state that is not outbound or returning.
 */
/datum/controller/subsystem/overworld/proc/complete_leg(datum/overworld_party/party)
	var/datum/overworld_region/region = get_active_overworld_region()
	if(!region)
		return FALSE

	var/entered_cell_id = party.leg_target_cell()
	if(!entered_cell_id || !region.cells[entered_cell_id])
		// The route no longer describes this region. Stop rather than walking into nowhere.
		halt_party(party, "the route no longer matches the region")
		return FALSE

	party.current_cell = entered_cell_id
	party.leg_started_at = 0
	party.leg_arrives_at = 0

	// One ration per head per boundary, taken from what the party carried out rather than from the colony -
	// the colony already paid at departure and this is the allocation being spent down.
	var/mouths = party.living_member_count()
	party.supplies = max(0, party.supplies - mouths)

	// Walking into somewhere is how the region gets explored. This is the one funnel, so it serializes and
	// pushes the map for us.
	SScampaign.discover_overworld_cell(entered_cell_id)

	if(party.state == OVERWORLD_PARTY_RETURNING)
		if(party.at_home())
			return finish_journey(party)
		party.next_leg_index--
		return schedule_leg(party, region)

	if(party.at_destination(region))
		return begin_site_visit(party)

	party.next_leg_index++
	return schedule_or_ask(party, region)

/**
 * Sets the clock for the next boundary. Returns TRUE if the party is now walking.
 *
 * Cost comes from the generated terrain of the cell being entered, so a route across hard ground genuinely
 * takes longer than the same distance across open ground - which is the entire reason the two route offers
 * differ.
 */
/datum/controller/subsystem/overworld/proc/schedule_leg(datum/overworld_party/party, datum/overworld_region/region)
	var/next_cell_id = party.leg_target_cell()
	var/datum/overworld_cell/next_cell = region?.cells[next_cell_id]
	if(!next_cell)
		halt_party(party, "the next step of the route is not on this region")
		return FALSE

	// Out of rations mid-journey is a bug in the supply arithmetic rather than a hardship to simulate: the
	// departure debit is sized for the whole round trip. Say so and stop, rather than inventing starvation.
	if(party.supplies <= 0 && party.living_member_count())
		halt_party(party, "the expedition ran out of rations, which its departure debit should have prevented")
		return FALSE

	var/now = SScampaign.get_campaign_time()
	party.leg_started_at = now
	party.leg_arrives_at = now + (next_cell.traversal_seconds() SECONDS)
	SScampaign.commit_party_change()
	return TRUE

/**
 * Stops a journey where it stands and says why.
 *
 * Not a loss and not a completion - the party keeps its people and its supplies, and an admin is told. Every
 * caller is a case that should not be reachable, so the useful thing is a legible halt rather than a guess at
 * what the party meant to do.
 */
/datum/controller/subsystem/overworld/proc/halt_party(datum/overworld_party/party, reason)
	party.leg_started_at = 0
	party.leg_arrives_at = 0
	log_game("Colony expedition [party.party_id] halted: [reason].")
	message_admins(span_boldwarning("Colony expedition [party.party_id] has halted: [reason]. It is holding at [party.current_cell]."))
	SScampaign.commit_party_change()
	return FALSE

/// The party reaches what it came for and starts working it.
/datum/controller/subsystem/overworld/proc/begin_site_visit(datum/overworld_party/party)
	// A survey has nothing to walk into. The country is the point, so it is taken in from where they stand and
	// they turn straight round - loading a scene for it would reserve turfs nobody would ever enter.
	if(party.is_surveying())
		return complete_survey(party)

	if(!party.set_state(OVERWORLD_PARTY_AT_SITE, "the expedition reached its destination"))
		return FALSE

	// Nobody online means nobody to stand in it. Arriving is a fact about the record and happens on time either
	// way; the ground is only worth reserving once somebody is there to walk on it, and a reservation made for
	// an empty party is one that is never handed back. Whoever rejoins brings the site up themselves.
	if(!party.living_member_count())
		log_game("Colony expedition [party.party_id] reached [party.destination_site_id] with nobody online; the site waits until somebody joins.")
		SScampaign.commit_party_change()
		return TRUE

	// Loading a scene sleeps, and this is a subsystem fire. The party is already at the site as far as the
	// record is concerned; the ground under their feet catches up a moment later.
	INVOKE_ASYNC(src, PROC_REF(bring_up_site), party.party_id, party.destination_site_id)
	SScampaign.commit_party_change()
	return TRUE

/**
 * Brings the site's scene into being and puts the party in it.
 *
 * Everything is re-resolved by id after the load, because the load sleeps: the party may have been lost, the
 * campaign may have ended, and a body held across that gap may be gone.
 */
/datum/controller/subsystem/overworld/proc/bring_up_site(party_id, site_id)
	UNTIL(!loading_destination)
	loading_destination = TRUE
	// Which scene depends on what kind of site it is: a deposit and a ruin are different places to stand.
	var/datum/overworld_destination/site = load_overworld_destination(site_id, overworld_site_template_key(site_id))
	loading_destination = FALSE

	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party || party.party_id != party_id || party.state != OVERWORLD_PARTY_AT_SITE)
		return FALSE

	if(!site)
		halt_party(party, "the site could not be brought up")
		return FALSE

	move_party_to(party, site)
	SScampaign.commit_party_change()
	return TRUE

/**
 * Puts every living member of a party into a loaded scene.
 *
 * Resolved by colonist id rather than from a held list of bodies, so somebody who died, disconnected or was
 * replaced while a scene was loading is simply not moved.
 */
/datum/controller/subsystem/overworld/proc/move_party_to(datum/overworld_party/party, datum/overworld_destination/destination)
	var/turf/arrival = destination?.pick_arrival_turf()
	if(!arrival)
		return 0

	var/moved = 0
	for(var/colonist_id in party.member_ids)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(!body || body.stat == DEAD)
			continue
		body.forceMove(arrival)
		moved++
	return moved

/**
 * The journey is over and the party is home.
 *
 * The unspent rations go back, once. They were an allocation of the colony's food rather than a second pile,
 * so returning them is the other half of the departure debit rather than a reward.
 */
/datum/controller/subsystem/overworld/proc/finish_journey(datum/overworld_party/party)
	if(!party.set_state(OVERWORLD_PARTY_COMPLETE, "the expedition came home"))
		return FALSE

	var/returned = party.supplies
	party.supplies = 0
	if(returned > 0)
		// Back into the larder as real food. Crediting the ledger's figure instead would survive only until the
		// next recount, which sets that figure to whatever the box actually holds.
		return_colony_food(returned, "expedition_rations_returned", party.party_id)

	INVOKE_ASYNC(src, PROC_REF(bring_party_home), party.party_id)
	log_game("Colony expedition [party.party_id] returned with [returned] rations left over.")
	message_admins("Colony expedition [party.party_id] has returned to the settlement.")
	SScampaign.commit_party_change()
	return TRUE

/**
 * Moves a party that has just turned for home back into the travelling camp.
 *
 * Without this they stand around the site they have finished with while the map says they are on the road,
 * which is the same mismatch the hitching post exists to fix at the other end of the journey.
 */
/datum/controller/subsystem/overworld/proc/board_for_return(party_id)
	UNTIL(!loading_destination)
	loading_destination = TRUE
	var/datum/overworld_destination/camp = load_overworld_destination(null, LAZY_TEMPLATE_KEY_RIMSTATION_TRANSIT)
	loading_destination = FALSE

	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party || party.party_id != party_id || party.state != OVERWORLD_PARTY_RETURNING)
		return FALSE
	if(!camp)
		return FALSE

	move_party_to(party, camp)
	return TRUE

/// Puts the returning party back in the colony, then frees the slot for the next expedition.
/datum/controller/subsystem/overworld/proc/bring_party_home(party_id)
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party || party.party_id != party_id)
		return FALSE

	var/turf/landing = get_caravan_return_turf()
	if(landing)
		for(var/colonist_id in party.member_ids)
			var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
			if(body && body.stat != DEAD)
				body.forceMove(landing)

	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	region_state?.clear_party("the expedition came home")
	SScampaign.commit_party_change()
	return TRUE

/**
 * Where a returning caravan is put down.
 *
 * The mapped landmark first, then the colony core, then whatever the ordinary colonist arrival would use.
 * Three fallbacks because arriving nowhere means a body in nullspace, which is worse than arriving somewhere
 * slightly wrong.
 */
/proc/get_caravan_return_turf()
	RETURN_TYPE(/turf)
	for(var/obj/effect/landmark/rimstation_caravan_return/marker in GLOB.landmarks_list)
		var/turf/spot = get_turf(marker)
		if(spot)
			return spot

	var/obj/structure/colony_core/core = get_colony_core()
	var/turf/beside_core = core ? get_step(core, SOUTH) : null
	if(beside_core && !isclosedturf(beside_core))
		return beside_core

	return get_colonist_arrival_turf()


/**
 * Finishes a departure once the travelling camp is standing.
 *
 * Split from `depart_party()` because bringing the camp up sleeps, and a great deal can change in that gap:
 * somebody can die, a raid can start, the round can end, the campaign can be committed. So nothing here trusts
 * what was true when the button was clicked - every fact is asked again, and the party is only actually sent
 * once they all still hold.
 *
 * Everything is re-resolved by id. A body reference held across the load could be a mob that has since been
 * deleted, which is exactly the reference the departure would then try to move.
 */
/datum/controller/subsystem/overworld/proc/complete_departure(party_id)
	// Waited on rather than refused. Two scenes coming up at once is a timing accident, not a reason to stand
	// an expedition down - and `lazy_load()` is called directly here, so it does not get the serialisation that
	// SSmapping.lazy_load_template() would have provided.
	UNTIL(!loading_destination)
	loading_destination = TRUE
	var/datum/overworld_destination/camp = load_overworld_destination(null, LAZY_TEMPLATE_KEY_RIMSTATION_TRANSIT)
	loading_destination = FALSE

	// From here on, everything is as it is now rather than as it was when somebody clicked.
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party || party.party_id != party_id)
		return FALSE
	if(party.state != OVERWORLD_PARTY_DEPARTING)
		return FALSE

	if(!camp)
		return abort_departure(party_id, "the travelling camp could not be brought up")
	if(!SScampaign.can_mutate_world())
		return abort_departure(party_id, "the colony was being written to disk")
	if(is_colony_raid_running())
		return abort_departure(party_id, "the colony came under attack before the expedition left")
	if(!party.living_member_count())
		return abort_departure(party_id, "nobody who signed on was still able to travel")

	var/datum/overworld_region/region = get_active_overworld_region()
	if(!region || !region.is_valid_route(party.route, SScampaign.get_overworld_state()?.discovered_cells))
		return abort_departure(party_id, "the route stopped being one the colony could walk")

	if(!party.set_state(OVERWORLD_PARTY_OUTBOUND, "the expedition got on the road"))
		return abort_departure(party_id, "the expedition could not be put on the road")

	// Standing at home, walking towards the second cell of the route.
	party.current_cell = party.route[1]
	party.next_leg_index = 2
	move_party_to(party, camp)
	schedule_or_ask(party, region)
	return TRUE

/**
 * Puts a half-departed expedition back the way it was.
 *
 * The rations go back to the colony, because they were an allocation for a journey that is not happening. The
 * bodies were never moved - nothing touches them until every check has passed - so there is nothing to undo
 * about where anybody is standing.
 */
/datum/controller/subsystem/overworld/proc/abort_departure(party_id, reason)
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party || party.party_id != party_id)
		return FALSE
	if(party.state != OVERWORLD_PARTY_DEPARTING)
		return FALSE

	var/returned = party.supplies
	party.supplies = 0
	if(returned > 0)
		return_colony_food(returned, "expedition_stood_down", party.party_id)

	party.set_state(OVERWORLD_PARTY_FORMING, reason)
	// Readiness is cleared with it: everybody agreed to a departure that did not happen, and should be asked
	// again rather than sent the moment the problem clears.
	party.clear_readiness("the departure was stood down")

	log_game("Colony expedition [party.party_id] stood down before leaving: [reason].")
	message_admins(span_warning("Colony expedition [party.party_id] was stood down before it left: [reason]. Its rations were returned."))
	SScampaign.commit_party_change()
	return FALSE


/**
 * Schedules the next leg, unless the road has something to ask first.
 *
 * Every outbound leg goes through here rather than straight to `schedule_leg()`, so there is exactly one place
 * that decides whether a boundary is walked or argued about. Returning legs never ask - the way home is not
 * where a party wants a new problem, and the rations were priced for the road they know.
 */
/datum/controller/subsystem/overworld/proc/schedule_or_ask(datum/overworld_party/party, datum/overworld_region/region)
	if(party.decision_is_due())
		return raise_decision(party, region)
	return schedule_leg(party, region)

/**
 * Stops the party at a boundary and asks them what they want to do about it.
 *
 * Raised immediately before the leg would have been scheduled, and it names the cell in front of them. Naming
 * it is what makes a detour meaningful - there is a concrete piece of ground to go around - and it is also why
 * a site one hex from home can still be interrupted.
 */
/datum/controller/subsystem/overworld/proc/raise_decision(datum/overworld_party/party, datum/overworld_region/region)
	var/blocked_cell = party.leg_target_cell()
	if(!blocked_cell)
		return FALSE
	if(!party.set_state(OVERWORLD_PARTY_DECISION, "the road put a question to the expedition"))
		return FALSE

	// Which kind of problem, derived from the party and the ground rather than rolled, so a reload finds the
	// same one waiting.
	var/datum/overworld_decision/archetype = pick_overworld_decision(party, region, blocked_cell)
	if(!archetype)
		return FALSE

	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	party.pending_decision = list(
		// A stable id so an answer can be matched to the question it was asked about, and so applying the same
		// answer twice is recognisable rather than merely unlikely.
		"id" = "decision-[party.party_id]-[region_state ? region_state.next_decision_number++ : 0]",
		"kind" = archetype.id,
		"name" = archetype.name,
		"reveal" = archetype.reveal_text,
		"cell" = blocked_cell,
		"choices" = archetype.available_choices(party, region, blocked_cell),
		"labels" = archetype.choice_copy.Copy(),
	)

	party.leg_started_at = 0
	party.leg_arrives_at = 0
	log_game("Colony expedition [party.party_id] halted at [party.current_cell]: the way to [blocked_cell] is blocked.")
	SScampaign.commit_party_change()
	return TRUE

/**
 * Applies one answer to a pending decision. Returns null on success, or why it was refused.
 *
 * Idempotent by identity rather than by luck: the answer names the decision it is answering, and the decision
 * is cleared before any effect lands. A second click, or a second player answering at the same moment, finds
 * nothing left to answer rather than paying the cost twice.
 */
/datum/controller/subsystem/overworld/proc/answer_decision(datum/overworld_party/party, decision_id, choice, mob/living/answered_by)
	if(!party?.pending_decision)
		return "There is nothing to decide."
	if(party.state != OVERWORLD_PARTY_DECISION)
		return "The expedition is not waiting on a decision."
	if(party.pending_decision["id"] != decision_id)
		return "That answer is to a different question."

	var/list/allowed = party.pending_decision["choices"]
	if(!(choice in allowed))
		return "That is not one of the choices."

	var/datum/overworld_region/region = get_active_overworld_region()
	if(!region)
		return "This colony has no regional map."

	var/datum/overworld_decision/archetype = get_overworld_decision(party.pending_decision["kind"])
	if(!archetype)
		return "Nobody can work out what the expedition was looking at."

	// Cleared and counted before anything is spent, so nothing can re-enter and spend it again.
	var/blocked_cell = party.pending_decision["cell"]
	party.pending_decision = null
	party.decisions_taken++

	if(!party.set_state(OVERWORLD_PARTY_OUTBOUND, "the expedition chose [choice]"))
		return "The expedition could not get moving again."

	archetype.apply_choice(party, region, choice, blocked_cell)

	log_game("Colony expedition [party.party_id] answered [decision_id] ([archetype.id]) with '[choice]'[answered_by ? " ([key_name(answered_by)])" : ""].")
	SScampaign.commit_party_change()
	return null

/**
 * Push on through. Costs nothing but skin.
 *
 * The zero-ration answer, deliberately: it is what stops a party being stranded by a decision it could not
 * afford any other response to. Bodies that are not here take no injury - inventing one for somebody who was
 * disconnected would be punishing them for their connection - but the journey continues for everybody.
 */
/datum/controller/subsystem/overworld/proc/apply_force(datum/overworld_party/party, datum/overworld_region/region)
	for(var/colonist_id in party.member_ids)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(!body || body.stat == DEAD)
			continue
		body.adjust_stamina_loss(OVERWORLD_DECISION_FORCE_STAMINA)
		body.adjust_brute_loss(OVERWORLD_DECISION_FORCE_BRUTE)
		to_chat(body, span_warning("You push through the worst of it. It takes something out of you."))

	return schedule_leg(party, region)

/// Go the long way. The extra ground costs its own time, risk and rations, like any other ground.
/datum/controller/subsystem/overworld/proc/apply_detour(datum/overworld_party/party, datum/overworld_region/region, blocked_cell)
	var/list/detour = party.detour_route(region)
	if(length(detour) < 2)
		// Offered and then not available is a bug, but stranding the party over it would be worse.
		return apply_force(party, region)

	party.route = detour
	party.next_leg_index = 2
	party.route_kind = party.route_kind || OVERWORLD_ROUTE_FASTEST
	for(var/colonist_id in party.member_ids)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(body)
			to_chat(body, span_notice("The caravan turns aside, working its way around."))
	return schedule_leg(party, region)

/// Sit it out. Ninety seconds and a meal each, then the original road.
/datum/controller/subsystem/overworld/proc/apply_wait(datum/overworld_party/party, datum/overworld_region/region)
	var/mouths = party.living_member_count()
	party.supplies = max(0, party.supplies - mouths)

	if(!schedule_leg(party, region))
		return FALSE

	// Added on top of the leg it was already going to take, rather than replacing it.
	party.leg_arrives_at += (OVERWORLD_DECISION_WAIT_SECONDS SECONDS)
	for(var/colonist_id in party.member_ids)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(body)
			to_chat(body, span_notice("The caravan makes camp and waits it out."))
	return TRUE


/**
 * What a death does to an expedition.
 *
 * Driven from the roster's own death record rather than from a second signal on the body. There is already one
 * place that decides somebody has died, and a competing detector would eventually disagree with it about who
 * is alive - which is the one thing a party must never be wrong about.
 *
 * A death does not end a journey. The survivors keep walking, keep eating and keep the ore; only running out
 * of living people ends it. Nobody is resurrected and no rescue is dispatched: this phase has no answer to a
 * party dying out there beyond recording that it did.
 */
/datum/controller/subsystem/overworld/proc/note_party_death(colonist_id)
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party || !(colonist_id in party.member_ids))
		return FALSE

	// Their agreement to go dies with them. The list is what the departure gate counts, and a dead member who
	// still reads as ready would let a caravan leave one short without anybody noticing.
	party.ready_member_ids -= colonist_id

	if(party.living_member_count())
		SScampaign.commit_party_change()
		return TRUE

	return lose_party(party, "every colonist on it died")

/**
 * The expedition is gone, and so is what it was carrying.
 *
 * The rations are forfeit rather than refunded - they went out of the colony with people who are not bringing
 * them back - and that is written down rather than merely subtracted, so a chapter that ends poorer has a line
 * saying why. What the party discovered stays discovered: the ground it walked is still walked, and deleting
 * that would punish the colony twice for the same loss.
 */
/datum/controller/subsystem/overworld/proc/lose_party(datum/overworld_party/party, reason)
	if(!party.set_state(OVERWORLD_PARTY_LOST, reason))
		return FALSE

	var/forfeited = party.supplies
	party.supplies = 0
	if(forfeited > 0)
		SScampaign.record_nonfinancial(
			LEDGER_CATEGORY_EXPEDITION,
			"expedition_lost_with_supplies",
			actor_id = null,
			related_id = party.party_id,
		)

	party.leg_started_at = 0
	party.leg_arrives_at = 0
	party.pending_decision = null

	log_game("Colony expedition [party.party_id] was lost: [reason]. [forfeited] rations went with it.")
	message_admins(span_boldwarning("Colony expedition [party.party_id] has been lost at [party.current_cell]: [reason]."))
	priority_announce(
		"The colony has lost contact with its expedition. They are not coming back.",
		"Expedition Lost",
		sound = null,
	)
	SScampaign.commit_party_change()
	return TRUE

/**
 * Who is actually standing in the colony right now.
 *
 * Membership rather than coordinates, because a party is away the moment it departs regardless of which
 * reservation its bodies happen to be sitting in. Anything that wants to know how thin the colony is - the
 * undefended warning, admin telemetry - asks this rather than counting living mobs, which would count the
 * travellers as defenders right up until something attacked.
 */
/proc/get_colonists_physically_at_colony()
	RETURN_TYPE(/list)
	var/list/present = list()
	var/datum/colonist_roster/roster = SScampaign.get_roster()
	if(!roster)
		return present

	var/datum/overworld_party/party = SScampaign.get_active_party()
	// A party still gathering has not gone anywhere; its members are as present as anybody.
	var/list/away = (party && !party.is_planning() && !(party.state in OVERWORLD_PARTY_TERMINAL_STATES)) ? party.member_ids : list()

	for(var/colonist_id in roster.records)
		if(colonist_id in away)
			continue
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(body && body.stat != DEAD)
			present += colonist_id
	return present


/// TRUE when this colonist is on an expedition that has actually left the colony.
/proc/is_travelling_member(colonist_id)
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party || !(colonist_id in party.member_ids))
		return FALSE
	// Still gathering, finished, or lost: all of those belong in the colony like anybody else.
	return !party.is_planning() && !(party.state in OVERWORLD_PARTY_TERMINAL_STATES)

/**
 * Hands a resuming traveller their own belongings back.
 *
 * A colonist who ends a chapter on the road cannot walk to their locker to collect their things, because their
 * locker is in a colony they are nowhere near. So the locker comes to them.
 *
 * Only ever their own locker. The shared stash cannot say which coat belonged to whom, so drawing from it
 * would hand somebody else's kit to whoever happened to rejoin first.
 */
/proc/restore_traveller_belongings(mob/living/body, datum/colonist_record/record)
	var/obj/structure/closet/colonist_storage/locker/personal = get_personal_colonist_locker(record?.colonist_id)
	if(!personal)
		// Keeping the issued outfit is the right answer here: they are about to be put somewhere with no shops.
		log_game("Colony campaign: [record?.display_name] resumed an expedition with no personal locker; they keep the issued outfit.")
		return FALSE

	if(!length(personal.contents))
		log_game("Colony campaign: [record?.display_name] resumed an expedition with an empty locker; they keep the issued outfit.")
		return FALSE

	return return_colonist_belongings(personal, body)

/**
 * Sends a rejoining colonist back to wherever their expedition actually is.
 *
 * Called after the ordinary arrival has already put them somewhere safe in the colony, which matters: bringing
 * the scene up sleeps, and a body that was waiting in nullspace for it would be a body nobody could find if the
 * load failed. They stand in the colony for a moment and are then moved out.
 *
 * Everything is re-resolved by id afterwards for the usual reason - the party can end, and the body can stop
 * existing, in the time a map takes to load.
 */
/datum/controller/subsystem/overworld/proc/resume_traveller(colonist_id)
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party || !is_travelling_member(colonist_id))
		return FALSE

	// At a site they are at the site; anywhere else on the journey they are in the camp.
	var/at_site = party.state == OVERWORLD_PARTY_AT_SITE
	var/site_id = at_site ? party.destination_site_id : null
	var/template_key = at_site ? overworld_site_template_key(site_id) : LAZY_TEMPLATE_KEY_RIMSTATION_TRANSIT

	// Preflighted before anything is promised. A content problem should leave somebody standing in the colony
	// with an admin warning, not halfway into a scene that does not exist.
	var/problem = overworld_template_problem(template_key)
	if(problem)
		log_game("Colony campaign: [colonist_id] could not be returned to their expedition: [problem].")
		message_admins(span_boldwarning("[colonist_id] rejoined an expedition but its scene could not be loaded: [problem]. They have been left in the colony."))
		return FALSE

	INVOKE_ASYNC(src, PROC_REF(transfer_to_expedition), colonist_id, party.party_id, site_id, template_key)
	return TRUE

/// Brings the scene up and puts one rejoining body in it.
/datum/controller/subsystem/overworld/proc/transfer_to_expedition(colonist_id, party_id, site_id, template_key)
	UNTIL(!loading_destination)
	loading_destination = TRUE
	var/datum/overworld_destination/destination = load_overworld_destination(site_id, template_key)
	loading_destination = FALSE

	// Everything asked again, because a map load is long enough for all of it to have changed.
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party || party.party_id != party_id || !is_travelling_member(colonist_id))
		return FALSE

	var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
	if(!body || body.stat == DEAD)
		return FALSE

	var/turf/arrival = destination?.pick_arrival_turf()
	if(!arrival)
		message_admins(span_boldwarning("[colonist_id] rejoined an expedition but its scene offered nowhere to stand. They have been left in the colony."))
		return FALSE

	body.forceMove(arrival)
	to_chat(body, span_notice("You are back with the expedition, out in the country beyond the colony."))
	log_game("Colony campaign: [colonist_id] rejoined expedition [party_id] at [AREACOORD(arrival)].")
	return TRUE


/**
 * The party arrives at the country it came to look at, takes it in, and turns for home.
 *
 * The whole payout of a survey happens here, in one place, and it is map rather than goods. That difference is
 * the point of the mission type: ore has to be carried back and can be lost with the people carrying it, where
 * ground that has been seen stays seen even if nobody makes it home.
 */
/datum/controller/subsystem/overworld/proc/complete_survey(datum/overworld_party/party)
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(!region || !region_state)
		return FALSE

	var/revealed = region_state.discover_radius(region, party.current_cell, OVERWORLD_SURVEY_REVEAL_RADIUS)

	SScampaign.record_nonfinancial(
		LEDGER_CATEGORY_EXPEDITION,
		"survey_completed",
		actor_id = null,
		related_id = party.current_cell,
	)

	for(var/colonist_id in party.member_ids)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(body)
			to_chat(body, span_notice("You take a long look at the country from here. [revealed] new [revealed == 1 ? "stretch" : "stretches"] of ground go onto the colony's map."))

	log_game("Colony expedition [party.party_id] surveyed [party.current_cell] and revealed [revealed] cells.")

	// Home the way they came. `begin_return()` clears the survey target, so nothing can re-reveal on the way.
	if(!party.begin_return("the survey was finished"))
		return halt_party(party, "the expedition could not turn for home after its survey")

	if(!schedule_leg(party, region))
		return FALSE

	// A moment spent looking, on top of the crossing. Enough to read as an act rather than a bounce off the far
	// edge of the map.
	party.leg_arrives_at += (OVERWORLD_SURVEY_SECONDS SECONDS)

	INVOKE_ASYNC(src, PROC_REF(board_for_return), party.party_id)
	SScampaign.commit_party_change()
	return TRUE
