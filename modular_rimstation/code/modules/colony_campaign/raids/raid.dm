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
	/// What this raid came for. One of COLONY_RAID_GOAL_*.
	var/goal = COLONY_RAID_GOAL_CORE
	/// How many things have actually left the map. Loot still being carried has not been stolen yet.
	var/extracted_loot = 0
	/// Route maps for destinations that are not the core, keyed by destination turf.
	var/list/secondary_route_maps
	/// Where each attacker is currently headed, so nobody is re-routed every tick and never finishes a leg.
	var/list/current_destinations
	/// The single agreed way out. One exit means one route map rather than one per attacker.
	var/turf/shared_exit

	/// Seconds of warning before the assault begins.
	var/warning_duration = 2 MINUTES
	/// Stoppable timer that starts the assault.
	var/assault_timer_id
	/// Record of what this raid did, submitted once at resolution.
	var/datum/colony_raid_telemetry/telemetry

/**
 * Every raid that has not finished being cleaned up.
 *
 * Kept so that something deciding whether to start a raid can ask whether one is already happening. Two at
 * once is not twice the story - they compete for the same insertion points and the same core.
 */
GLOBAL_LIST_EMPTY(colony_raids)

/**
 * The raid currently attacking the colony, or null if nothing is.
 *
 * A colony can lose its core to a fire or to somebody's bad decision as easily as to an attack, so this
 * answering null is a real answer and not a lookup failure - it is what lets a loss say "no raid did this".
 */
/proc/get_attacking_colony_raid()
	RETURN_TYPE(/datum/colony_raid)
	for(var/datum/colony_raid/running as anything in GLOB.colony_raids)
		if(running.state != COLONY_RAID_RESOLVED)
			return running
	return null

/// TRUE when a raid is currently running. The question anything scheduling one needs answered.
/proc/is_colony_raid_running()
	return !isnull(get_attacking_colony_raid())

/datum/colony_raid/New()
	. = ..()
	raid_id = "raid-[world.time]-[rand(1000, 9999)]"
	roster = list()
	insertion_turfs = list()
	telemetry = new(raid_id)
	GLOB.colony_raids += src

/datum/colony_raid/Destroy(force)
	GLOB.colony_raids -= src
	cancel_timers()
	STOP_PROCESSING(SSprocessing, src)
	QDEL_NULL(telemetry)
	route_map = null
	secondary_route_maps = null
	current_destinations = null
	shared_exit = null
	attacker_routes = null
	roster = null
	insertion_turfs = null
	objective_ref = null
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
 * Candidates are generated landmarks, but a landmark is only a *proposal*. Players can build walls, dig out
 * mountains, bridge water, or otherwise change connectivity after map generation. Attackers spawned into a
 * stale sealed pocket would simply stand around.
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
/datum/colony_raid/proc/build_waypoint_chain(turf/from, list/using_route_map, atom/ending_at)
	RETURN_TYPE(/list)
	var/list/turf/chain = list()
	using_route_map = using_route_map || route_map
	ending_at = ending_at || objective_ref?.resolve()

	// No route map means no intermediate legs, but the chain must still end somewhere: an attacker handed an
	// empty chain has nowhere to go at all, which is the failure this whole mechanism exists to prevent.
	if(length(using_route_map) && from)
		var/turf/current = from
		var/steps_since_waypoint = 0
		// Walk parent links back toward the origin. The origin has no parent, which terminates the loop.
		while(using_route_map[current])
			current = using_route_map[current]
			steps_since_waypoint++
			if(steps_since_waypoint >= COLONY_RAID_WAYPOINT_SPACING)
				chain += current
				steps_since_waypoint = 0

	// Always finish on the destination itself, however short the last leg is.
	if(ending_at)
		chain += get_turf(ending_at)
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

	// Defaulted rather than demanded of the caller. Everything a raid does hangs off this one reference - the
	// waypoint chain ends at it, the contesting faction is registered on it, and the capture clock only runs
	// `if(core)` - so a raid built without one deploys, walks nowhere, and can never take anything. That is a
	// silent failure that looks like broken pathfinding, and it is not something a caller should be able to
	// cause by forgetting a line.
	if(!objective_ref?.resolve())
		var/obj/structure/colony_core/target = get_colony_core()
		if(!target)
			log_game("Colony raid [raid_id] cancelled: the colony has no core to attack.")
			resolve_raid(COLONY_RAID_OUTCOME_CANCELLED, "the colony has no core to attack")
			return FALSE
		objective_ref = WEAKREF(target)

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
	// A raid is the serious threat pacing measures everything else against, so it is recorded the moment it is
	// committed to rather than at its outcome - a raid survived is still a chapter that was not a rest.
	SScampaign.note_major_threat()
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
	// What they came for is told to the colony up front, because it is what the colony would have to decide
	// how to answer - defending the core and defending the stores are different plans.
	var/intent = "They are moving on the colony core."
	if(goal == COLONY_RAID_GOAL_THEFT)
		intent = "They appear to be moving on the settlement's stores."
	priority_announce(
		"Hostile movement detected approaching from [direction]. Estimated contact in [DisplayTimeText(warning_duration)]. [intent]",
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
		if(goal == COLONY_RAID_GOAL_THEFT)
			work_the_theft()
		update_attacker_routes()

	if(state == COLONY_RAID_RETREATING || goal == COLONY_RAID_GOAL_THEFT)
		// Anyone leaving by the edge has left the chapter, and takes whatever they were holding with them.
		// Checked during the assault as well as the retreat, because a thief does not wait to be beaten before
		// going - getting away is the whole plan.
		for(var/datum/weakref/attacker_ref as anything in roster)
			var/mob/living/attacker = attacker_ref.resolve()
			if(!attacker || attacker.stat == DEAD)
				continue
			if(!is_edge_band_turf(get_turf(attacker)))
				continue
			// Arriving and leaving happen on the same tiles: insertion points are edge tiles by definition. So
			// standing on the edge only means departure once there is something to depart with, or once the
			// raid has been called off. Without this a theft raid deletes its own attackers on its first tick,
			// empty-handed, on the ground they just landed on.
			if(state != COLONY_RAID_RETREATING && !length(get_raider_loot(attacker)))
				continue
			extract_raider(attacker)
			qdel(attacker)

	if(state == COLONY_RAID_RETREATING)
		if(!living_attacker_count())
			resolve_raid(finish_theft_outcome(), "the survivors withdrew")
			return PROCESS_KILL
		return

	// A theft raid that has carried off everything it came for is finished, win or lose for the colony.
	if(goal == COLONY_RAID_GOAL_THEFT && !length(find_loot_targets()) && !any_raider_carrying())
		resolve_raid(finish_theft_outcome(), extracted_loot ? "the attackers left with what they came for" : "there was nothing left worth taking")
		return PROCESS_KILL

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
			offer_to_ghosts(attacker)
			// Killing a thief has to return the goods, and troopers are DEL_ON_DEATH - so this has to be
			// watching before anything can die carrying anything.
			attacker.AddComponent(/datum/component/raider_loot)
			// Counted as AI here and moved across if somebody takes it; a raid is assembled complete and
			// volunteers only ever replace a unit that was already going to attack.
			telemetry.ai_units++

	offer_raid_to_ghosts()

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

/**
 * Takes the marching orders off every surviving attacker.
 *
 * Called when the raid ends, whatever the reason. Survivors keep their own AI - they will still defend
 * themselves if the colony comes after them - but they stop walking at an objective that is no longer theirs
 * to take.
 *
 * It also removes a source of teardown noise. A travel destination is a turf, and move loops deliberately do
 * not watch turfs for deletion ("we don't care", movement_types.dm) because turfs are not normally deleted -
 * but a generation reset rebuilds the map and deletes all of them, leaving queued pathfinding requests holding
 * a destination and a mob that both stopped existing. Clearing orders at the end of the fight means nothing is
 * still trying to path when the world goes away.
 */
/datum/colony_raid/proc/stand_down_attackers()
	for(var/datum/weakref/attacker_ref as anything in roster)
		var/mob/living/attacker = attacker_ref.resolve()
		if(!attacker?.ai_controller)
			continue
		attacker.ai_controller.clear_blackboard_key(BB_TRAVEL_DESTINATION)
	attacker_routes = null

/**
 * Gives `attacker` a chain of short legs to `destination` and starts it on the first one.
 *
 * Everything goes through here rather than setting a travel destination directly, because basic-mob JPS
 * refuses any path longer than AI_MAX_PATH_LENGTH - a raider handed a target sixty tiles away does not walk
 * thirty and stop, it stands exactly still. Route maps are cached per destination and attackers share
 * destinations, so this costs a couple of flood fills per raid rather than one per attacker.
 *
 * Sticky by design: an attacker already heading somewhere is left alone so it can finish its current leg.
 */
/datum/colony_raid/proc/route_attacker_to(mob/living/attacker, atom/destination)
	if(!attacker?.ai_controller)
		return FALSE
	var/turf/goal_turf = get_turf(destination)
	if(!goal_turf)
		return FALSE

	var/datum/weakref/attacker_ref = WEAKREF(attacker)
	LAZYINITLIST(current_destinations)
	if(current_destinations[attacker_ref] == goal_turf)
		return TRUE

	LAZYINITLIST(secondary_route_maps)
	if(!secondary_route_maps[goal_turf])
		secondary_route_maps[goal_turf] = build_route_map(goal_turf)

	current_destinations[attacker_ref] = goal_turf
	LAZYINITLIST(attacker_routes)
	attacker_routes[attacker_ref] = build_waypoint_chain(get_turf(attacker), secondary_route_maps[goal_turf], goal_turf)
	return advance_waypoint(attacker, attacker_ref)

/// The way out everybody uses. Chosen once so the raid keeps one exit route rather than one per attacker.
/datum/colony_raid/proc/get_shared_exit()
	RETURN_TYPE(/turf)
	if(shared_exit)
		return shared_exit
	shared_exit = length(insertion_turfs) ? pick(insertion_turfs) : null
	return shared_exit

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
	// Routed rather than pointed at: the way out is usually further than AI_MAX_PATH_LENGTH, and an attacker
	// handed a destination that far away stands still instead of retreating.
	for(var/datum/weakref/attacker_ref as anything in roster)
		var/mob/living/attacker = attacker_ref.resolve()
		if(!attacker || attacker.stat == DEAD || !attacker.ai_controller)
			continue
		if(send_raider_home(attacker))
			continue
		// Nowhere to withdraw to. Standing orders still have to be cancelled, or calling off the attack would
		// leave everybody marching on the objective exactly as before.
		attacker.ai_controller.clear_blackboard_key(BB_TRAVEL_DESTINATION)
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
	stand_down_attackers()

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
	// Announced rather than reported to a particular caller, because a raid can be started by an admin verb or
	// carried by a storyteller incident, and neither should have to be the one watching it finish.
	SEND_SIGNAL(src, COMSIG_COLONY_RAID_RESOLVED, outcome, reason)
	return TRUE

/datum/colony_raid/proc/cancel_timers()
	if(!assault_timer_id)
		return
	deltimer(assault_timer_id)
	assault_timer_id = null
