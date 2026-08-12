/**
 * One telegraphed, finite assault on the colony.
 *
 * The raid owns *when and where*; the mobs it spawns keep their own local combat AI. Strategy deliberately
 * does not live in /datum/component/spawner, which is a unit emitter and should stay one.
 *
 * The lifecycle is strictly forward. A raid that could skip from queued to assaulting would remove the
 * preparation window the colony is promised, which is the whole difference between a crisis and an ambush.
 */
/datum/colony_raid
	/// Identifies this raid in logs, telemetry and the chapter outcome.
	var/raid_id
	/// Current lifecycle state.
	var/state = COLONY_RAID_QUEUED
	/// Recorded once, when the raid stops mattering.
	var/outcome
	/// Why it ended that way.
	var/outcome_reason

	/// Total points this raid may spend.
	var/threat_budget = 100
	/// Most attackers alive at once, independent of budget.
	var/live_cap = 12
	/// Faction the attackers belong to.
	var/faction = "rimstation_raiders"
	/// Fraction of the roster that must die before the survivors give up.
	var/casualty_threshold = 0.6

	/// Weakrefs to spawned attackers, so a dead raid does not pin mobs in memory.
	var/list/datum/weakref/roster
	/// How many attackers actually arrived. Casualty ratios are measured against this, not the budget.
	var/deployed_strength = 0
	/// Assoc of turf to the turf it was reached from, built once from the core. Both reachability and routes.
	var/list/route_map
	/// Assoc of attacker weakref to its remaining approach waypoints.
	var/list/attacker_routes
	/// Turfs the attackers will arrive on.
	var/list/turf/insertion_turfs
	/// The core this raid is trying to take.
	var/datum/weakref/objective_ref
	/// Chapter result this raid reports into.
	var/datum/colony_chapter_outcome/chapter_outcome

	/// Seconds of warning before the assault begins.
	var/warning_duration = 2 MINUTES
	/// Stoppable timer that starts the assault.
	var/assault_timer_id
	/// Record of what this raid did, submitted once at resolution.
	var/datum/colony_raid_telemetry/telemetry

/datum/colony_raid/New()
	. = ..()
	raid_id = "raid-[world.time]-[rand(1000, 9999)]"
	roster = list()
	insertion_turfs = list()
	telemetry = new(raid_id)

/datum/colony_raid/Destroy(force)
	cancel_timers()
	STOP_PROCESSING(SSprocessing, src)
	QDEL_NULL(telemetry)
	route_map = null
	attacker_routes = null
	roster = null
	insertion_turfs = null
	objective_ref = null
	chapter_outcome = null
	return ..()

/**
 * Moves the raid to `new_state` if that transition is legal. Returns TRUE when it happened.
 *
 * Legal means the next step forward, or a jump straight to resolved. The jump exists because a raid can be
 * cancelled before it deploys, and a cancelled raid still has to reach a terminal state to be cleaned up.
 */
/datum/colony_raid/proc/set_state(new_state)
	var/list/order = COLONY_RAID_STATE_ORDER
	var/current_index = order.Find(state)
	var/new_index = order.Find(new_state)
	if(!new_index)
		log_game("Colony raid [raid_id] refused unknown state '[new_state]'.")
		return FALSE
	if(state == COLONY_RAID_RESOLVED)
		return FALSE
	if(new_state != COLONY_RAID_RESOLVED && new_index != current_index + 1)
		log_game("Colony raid [raid_id] refused transition [state] -> [new_state].")
		return FALSE

	state = new_state
	telemetry?.record_state(new_state)
	return TRUE

/**
 * Buys attackers until the budget, the live cap or the per-unit maximums run out.
 *
 * Minimums are purchased first so a raid always arrives with its intended shape. The weighted fill then
 * spends what is left, and stops the moment nothing affordable remains rather than spinning on leftovers.
 */
/datum/colony_raid/proc/build_composition(budget, list/datum/colony_raid_unit/available, cap)
	RETURN_TYPE(/list)
	var/list/composition = list()
	var/remaining = budget
	var/head_count = 0

	for(var/datum/colony_raid_unit/unit as anything in available)
		for(var/i in 1 to unit.minimum_count)
			if(remaining < unit.point_cost || head_count >= cap)
				break
			composition[unit.mob_type] += 1
			remaining -= unit.point_cost
			head_count++

	while(head_count < cap)
		var/list/affordable = list()
		for(var/datum/colony_raid_unit/unit as anything in available)
			if(unit.point_cost > remaining)
				continue
			if(composition[unit.mob_type] >= unit.maximum_count)
				continue
			affordable[unit] = unit.weight
		if(!length(affordable))
			break
		var/datum/colony_raid_unit/picked = pick_weight(affordable)
		composition[picked.mob_type] += 1
		remaining -= picked.point_cost
		head_count++

	return composition

/// Total budget cost of a composition, used for verification and telemetry.
/datum/colony_raid/proc/composition_cost(list/composition, list/datum/colony_raid_unit/available)
	var/total = 0
	for(var/datum/colony_raid_unit/unit as anything in available)
		total += composition[unit.mob_type] * unit.point_cost
	return total

/**
 * Collects the turfs this raid is allowed to arrive on.
 *
 * Candidates are mapped-in landmarks, but a landmark is only a *proposal*. The surface is generated after the
 * map is authored, so a mapper cannot promise a tile is reachable - generation routinely seals one inside a
 * closed pocket of rock. Attackers spawned there simply stand around, which is how this was found.
 *
 * So every candidate is checked against a walkable region flood-filled outward from the core. That is a real
 * connectivity answer rather than a proxy for one, and it is done here rather than through SSpathfinder
 * because that subsystem is asynchronous and cannot answer inline during selection.
 */
/datum/colony_raid/proc/find_insertion_turfs()
	RETURN_TYPE(/list)
	var/list/turf/valid = list()
	if(!length(GLOB.rimstation_raid_insertion_points))
		return valid

	var/obj/effect/landmark/rimstation_settlement_center/centre = GLOB.rimstation_settlement_center
	var/turf/core_turf = get_turf(objective_ref?.resolve()) || get_turf(centre)
	if(!core_turf)
		return valid

	// One flood fill per raid, reused for every candidate and for building approach routes.
	route_map = build_route_map(core_turf)
	var/rejected_unreachable = 0

	for(var/obj/effect/landmark/rimstation_raid_insertion/candidate as anything in GLOB.rimstation_raid_insertion_points)
		var/turf/candidate_turf = get_turf(candidate)
		if(!candidate_turf || candidate_turf.density)
			continue
		// Arriving on top of the settlement is the failure this whole proc exists to prevent.
		if(centre && candidate_turf.z == centre.z && get_dist(candidate_turf, centre) < COLONY_RAID_EXCLUSION_RADIUS)
			continue
		if(!is_edge_band_turf(candidate_turf))
			continue
		if(!route_map[candidate_turf])
			rejected_unreachable++
			continue
		valid += candidate_turf

	if(rejected_unreachable)
		log_game("Colony raid [raid_id] discarded [rejected_unreachable] insertion point(s) with no walkable route to the core.")
	return valid

/**
 * Breadth-first search outward from `origin`, returning an assoc of turf to the turf it was reached from.
 *
 * Doubles as the reachability answer (a key exists only if the turf is walkable-connected to the origin) and
 * as the route home: following parents from any turf leads back to the origin along a walkable path. Doing
 * both in one pass matters, because the map is 255x255 and this runs once per raid.
 *
 * The frontier is walked by index rather than consumed with Cut(), because repeatedly removing the head of a
 * 60,000-entry list is quadratic.
 */
/datum/colony_raid/proc/build_route_map(turf/origin, max_turfs = COLONY_RAID_REACHABILITY_LIMIT)
	RETURN_TYPE(/list)
	var/list/came_from = list()
	if(!origin)
		return came_from

	// The core tile itself holds a dense structure, so seed from the walkable ring around it instead.
	var/list/frontier = list()
	for(var/turf/open/starting as anything in get_adjacent_open_turfs(origin))
		if(!is_walkable_turf(starting))
			continue
		came_from[starting] = origin
		frontier += starting

	var/index = 1
	while(index <= length(frontier) && length(came_from) < max_turfs)
		var/turf/current = frontier[index++]
		for(var/turf/open/neighbour as anything in get_adjacent_open_turfs(current))
			if(came_from[neighbour])
				continue
			if(!is_walkable_turf(neighbour))
				continue
			came_from[neighbour] = current
			frontier += neighbour
		CHECK_TICK

	return came_from

/**
 * Turns a route map into the short hops an attacker can actually be asked to walk.
 *
 * Basic-mob JPS will not path further than AI_MAX_PATH_LENGTH, so a raider told to walk to a core 110 tiles
 * away simply stands still. Following the route map back from the arrival point and sampling it every
 * COLONY_RAID_WAYPOINT_SPACING tiles gives a chain of legs that are each short enough to path.
 *
 * Returned in travel order, ending at the objective.
 */
/datum/colony_raid/proc/build_waypoint_chain(turf/from)
	RETURN_TYPE(/list)
	var/list/turf/chain = list()

	// No route map means no intermediate legs, but the chain must still end somewhere: an attacker handed an
	// empty chain has nowhere to go at all, which is the failure this whole mechanism exists to prevent.
	if(length(route_map) && from)
		var/turf/current = from
		var/steps_since_waypoint = 0
		// Walk parent links back toward the core. The origin has no parent, which terminates the loop.
		while(route_map[current])
			current = route_map[current]
			steps_since_waypoint++
			if(steps_since_waypoint >= COLONY_RAID_WAYPOINT_SPACING)
				chain += current
				steps_since_waypoint = 0

	// Always finish on the objective itself, however short the last leg is.
	var/atom/objective = objective_ref?.resolve()
	if(objective)
		chain += get_turf(objective)
	return chain

/**
 * TRUE when something walking could stand on this turf.
 *
 * Deliberately conservative about dense objects: refusing to arrive somewhere that needs a door opened is a
 * far cheaper mistake than arriving somewhere the attackers cannot leave.
 */
/datum/colony_raid/proc/is_walkable_turf(turf/candidate)
	if(!candidate || candidate.density)
		return FALSE
	for(var/obj/blocker in candidate)
		if(blocker.density)
			return FALSE
	return TRUE

/// TRUE when the turf sits in the band along the map edge where arrivals are permitted.
/datum/colony_raid/proc/is_edge_band_turf(turf/candidate)
	if(candidate.x <= COLONY_RAID_EDGE_BAND || candidate.y <= COLONY_RAID_EDGE_BAND)
		return TRUE
	if(candidate.x >= world.maxx - COLONY_RAID_EDGE_BAND || candidate.y >= world.maxy - COLONY_RAID_EDGE_BAND)
		return TRUE
	return FALSE

/**
 * Starts the telegraph. Returns FALSE if the raid could not deploy and cancelled itself.
 *
 * Refusing to run is a real outcome. Spawning inside the town because no edge tile was available would be
 * worse than no raid at all.
 */
/datum/colony_raid/proc/begin_warning()
	if(state != COLONY_RAID_QUEUED)
		return FALSE

	// A raid starting mid-commit would put attackers into a world that is being written to disk, producing a
	// checkpoint that matches no moment that ever existed.
	if(!SScampaign.can_mutate_world())
		log_game("Colony raid [raid_id] cancelled: the campaign is committing a checkpoint.")
		resolve_raid(COLONY_RAID_OUTCOME_CANCELLED, "the campaign was committing a checkpoint")
		return FALSE

	insertion_turfs = find_insertion_turfs()
	if(!length(insertion_turfs))
		log_game("Colony raid [raid_id] cancelled: no validated insertion points.")
		resolve_raid(COLONY_RAID_OUTCOME_CANCELLED, "no validated insertion points existed")
		return FALSE

	set_state(COLONY_RAID_WARNING)
	telemetry.insertion_direction = describe_insertion_direction()
	// Sample the settlement before anything is shot at, so damage is a difference rather than a guess.
	telemetry.sample_settlement_integrity()
	announce_warning()
	assault_timer_id = addtimer(CALLBACK(src, PROC_REF(begin_assault)), warning_duration, TIMER_STOPPABLE)
	return TRUE

/// Compass direction the attackers are arriving from, relative to the settlement.
/datum/colony_raid/proc/describe_insertion_direction()
	var/turf/sample = length(insertion_turfs) ? insertion_turfs[1] : null
	var/obj/effect/landmark/rimstation_settlement_center/centre = GLOB.rimstation_settlement_center
	if(!sample || !centre)
		return "unknown"
	return dir2text(get_dir(centre, sample))

/// Tells the colony what is coming, roughly from where, and how long it has.
/datum/colony_raid/proc/announce_warning()
	var/direction = describe_insertion_direction()
	priority_announce(
		"Hostile movement detected approaching from [direction]. Estimated contact in [DisplayTimeText(warning_duration)]. They are moving on the colony core.",
		"Colony Perimeter Alert",
	)

/datum/colony_raid/proc/begin_assault()
	assault_timer_id = null
	if(state != COLONY_RAID_WARNING)
		return
	set_state(COLONY_RAID_ASSEMBLING)
	set_state(COLONY_RAID_ARRIVING)
	deploy_attackers()
	set_state(COLONY_RAID_ASSAULTING)
	deployed_strength = length(roster)
	// Only now can anything take the core, and only this raid's faction.
	var/obj/structure/colony_core/core = objective_ref?.resolve()
	core?.register_contesting_faction(faction)
	// Nothing else drives the fight: the core's capture clock and the raid's own end conditions are both
	// evaluated from here.
	START_PROCESSING(SSprocessing, src)

/**
 * Drives the fight.
 *
 * The colony core takes its elapsed time from here rather than running its own timer, so capture progress and
 * the raid's outcome can never disagree about how long attackers held the objective.
 */
/datum/colony_raid/process(seconds_per_tick)
	if(state != COLONY_RAID_ASSAULTING && state != COLONY_RAID_RETREATING)
		return PROCESS_KILL

	var/obj/structure/colony_core/core = objective_ref?.resolve()
	if(core)
		core.advance_contest(core.has_hostiles_present(), seconds_per_tick SECONDS)
		if(core.state == COLONY_CORE_CAPTURED)
			resolve_raid(COLONY_RAID_OUTCOME_SUCCEEDED, "the attackers took the colony core")
			return PROCESS_KILL

	var/alive = living_attacker_count()
	if(!alive)
		resolve_raid(COLONY_RAID_OUTCOME_REPELLED, "every attacker was killed")
		return PROCESS_KILL

	if(state == COLONY_RAID_ASSAULTING)
		update_attacker_routes()

	if(state == COLONY_RAID_RETREATING)
		// Survivors that made it back to the edge have left the chapter.
		for(var/datum/weakref/attacker_ref as anything in roster)
			var/mob/living/attacker = attacker_ref.resolve()
			if(!attacker || attacker.stat == DEAD)
				continue
			if(is_edge_band_turf(get_turf(attacker)))
				qdel(attacker)
		if(!living_attacker_count())
			resolve_raid(COLONY_RAID_OUTCOME_REPELLED, "the survivors withdrew")
			return PROCESS_KILL
		return

	// Enough of the roster is dead that the rest give up.
	if(deployed_strength && ((deployed_strength - alive) / deployed_strength) >= casualty_threshold)
		order_retreat()

/// Spawns the bought attackers across the validated arrival tiles.
/datum/colony_raid/proc/deploy_attackers()
	var/list/available = get_available_units()
	var/list/composition = build_composition(threat_budget, available, live_cap)
	telemetry.record_composition(composition, composition_cost(composition, available))
	// One chain per arrival point, shared by everyone who lands there.
	var/list/chains_by_turf = list()
	for(var/turf/arrival_turf as anything in insertion_turfs)
		chains_by_turf[arrival_turf] = build_waypoint_chain(arrival_turf)

	for(var/mob_type in composition)
		for(var/i in 1 to composition[mob_type])
			var/turf/arrival = pick(insertion_turfs)
			var/mob/living/attacker = new mob_type(arrival)
			attacker.set_faction(list(faction))
			assign_objective(attacker, chains_by_turf[arrival])
			roster += WEAKREF(attacker)
			// Phase 1 raids are AI-complete by design; Phase 5 is what offers these to ghosts.
			telemetry.ai_units++

/**
 * Gives one attacker its approach route and points it at the first leg.
 *
 * This is the whole of the "strategy" layer: the mob's own AI still decides how to fight, break obstacles and
 * pick targets. All the raid contributes is somewhere to be when nothing else is happening - and, critically,
 * somewhere *close enough to path to*. Handing it the distant core instead leaves it standing still.
 */
/datum/colony_raid/proc/assign_objective(mob/living/attacker, list/turf/route)
	var/atom/objective = objective_ref?.resolve()
	if(!objective || !attacker.ai_controller)
		return FALSE

	LAZYINITLIST(attacker_routes)
	var/datum/weakref/attacker_ref = WEAKREF(attacker)
	// With no route the objective is presumably already close, so head straight for it.
	attacker_routes[attacker_ref] = length(route) ? route.Copy() : list(get_turf(objective))
	return advance_waypoint(attacker, attacker_ref)

/// Points an attacker at the next leg of its route. Returns TRUE if it now has somewhere to go.
/datum/colony_raid/proc/advance_waypoint(mob/living/attacker, datum/weakref/attacker_ref)
	var/list/turf/route = attacker_routes?[attacker_ref]
	if(!length(route))
		return FALSE
	attacker.ai_controller?.set_blackboard_key(BB_TRAVEL_DESTINATION, route[1])
	return TRUE

/**
 * Walks every attacker along its route.
 *
 * Handing out the next leg only once the current one is reached is what keeps each pathfinding request inside
 * the range basic mobs will actually attempt.
 */
/datum/colony_raid/proc/update_attacker_routes()
	for(var/datum/weakref/attacker_ref as anything in attacker_routes)
		var/mob/living/attacker = attacker_ref.resolve()
		if(!attacker || attacker.stat == DEAD)
			continue
		var/list/turf/route = attacker_routes[attacker_ref]
		if(!length(route))
			continue
		if(get_dist(attacker, route[1]) > COLONY_RAID_WAYPOINT_ARRIVAL_DISTANCE)
			continue
		// Reached this leg; hand over the next one, or leave them on the objective if this was the last.
		if(length(route) > 1)
			route.Cut(1, 2)
			advance_waypoint(attacker, attacker_ref)

/// Sends the survivors back the way they came and stops them pressing the objective.
/datum/colony_raid/proc/order_retreat()
	if(!set_state(COLONY_RAID_RETREATING))
		return FALSE
	var/turf/exit_point = length(insertion_turfs) ? pick(insertion_turfs) : null
	for(var/datum/weakref/attacker_ref as anything in roster)
		var/mob/living/attacker = attacker_ref.resolve()
		if(!attacker || attacker.stat == DEAD || !attacker.ai_controller)
			continue
		attacker.ai_controller.set_blackboard_key(BB_TRAVEL_DESTINATION, exit_point)
	priority_announce("The surviving attackers are pulling back.", "Colony Perimeter Alert")
	return TRUE

/**
 * The unit table this raid draws from. Phase 5 replaces this with per-faction rosters.
 *
 * Pirates are reused rather than given bespoke mobs because they already come with working melee and ranged
 * AI; the point of this phase is the budget and the lifecycle around them, not new combatants.
 */
/datum/colony_raid/proc/get_available_units()
	RETURN_TYPE(/list)
	return list(
		new /datum/colony_raid_unit(/mob/living/basic/trooper/pirate/melee/rimstation_raider, 20, 2, 8, "grunt", 5),
		new /datum/colony_raid_unit(/mob/living/basic/trooper/pirate/ranged/rimstation_raider, 35, 0, 4, "ranged", 2),
	)

/// How many of the spawned attackers are still alive.
/datum/colony_raid/proc/living_attacker_count()
	var/alive = 0
	for(var/datum/weakref/attacker_ref as anything in roster)
		var/mob/living/attacker = attacker_ref.resolve()
		if(attacker && attacker.stat != DEAD)
			alive++
	return alive

/**
 * Records how the raid ended and stops it doing anything further.
 *
 * First outcome wins: once the fight has been decided, later cleanup must not rewrite the story.
 */
/datum/colony_raid/proc/resolve_raid(new_outcome, reason)
	if(outcome)
		return FALSE
	outcome = new_outcome
	outcome_reason = reason
	cancel_timers()
	STOP_PROCESSING(SSprocessing, src)
	set_state(COLONY_RAID_RESOLVED)

	// The fight is over, so nothing can be taking the core any more.
	var/obj/structure/colony_core/finished_core = objective_ref?.resolve()
	finished_core?.unregister_contesting_faction(faction)

	if(telemetry)
		telemetry.outcome = outcome
		// Captured here rather than at warning so that a raid cancelled before it deployed still records
		// what it was offered - "we budgeted 100 points and found nowhere to land" is worth knowing.
		telemetry.offered_budget = threat_budget
		var/obj/structure/colony_core/core = objective_ref?.resolve()
		if(core)
			telemetry.core_capture_progress = core.capture_duration ? (core.capture_progress / core.capture_duration) : 0
		telemetry.submit()

	log_game("Colony raid [raid_id] resolved as [outcome]: [reason].")
	message_admins("Colony raid [raid_id] resolved as [outcome]: [reason].")
	return TRUE

/datum/colony_raid/proc/cancel_timers()
	if(!assault_timer_id)
		return
	deltimer(assault_timer_id)
	assault_timer_id = null
