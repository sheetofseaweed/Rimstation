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
	/// Route maps toward the core, the exit and every stash. The one answer to where attackers can walk.
	var/datum/colony_raid_navigator/navigator
	/// Assoc of attacker weakref to its /datum/colony_raid_route.
	var/list/attacker_routes
	/// Turfs the attackers will arrive on.
	var/list/turf/insertion_turfs
	/// The core this raid is trying to take.
	var/datum/weakref/objective_ref
	/// What this raid came for. One of COLONY_RAID_GOAL_*.
	var/goal = COLONY_RAID_GOAL_CORE
	/// How many things have actually left the map. Loot still being carried has not been stolen yet.
	var/extracted_loot = 0
	/// The single agreed way out. One exit means one route map rather than one per attacker.
	var/turf/shared_exit
	/// When the raid entered its current state. The assault and retreat time limits count from here.
	var/state_changed_at = 0
	/// How many times an attacker was given a fresh route from where it stood.
	var/reroute_count = 0

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
	navigator = new
	GLOB.colony_raids += src

/datum/colony_raid/Destroy(force)
	GLOB.colony_raids -= src
	cancel_timers()
	STOP_PROCESSING(SSprocessing, src)
	QDEL_NULL(telemetry)
	QDEL_NULL(navigator)
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
	state_changed_at = world.time
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
 * So every candidate is checked against the core's route map, built now with a raider's passability rules.
 * That is a real connectivity answer, and the same map then gives the attackers their routes.
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

	// Waits for the map, so the warning names a direction the raid can actually come from.
	var/datum/path_map/core_map = navigator.get_map_now(core_turf)
	if(!core_map)
		return valid
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
		if(!core_map.next_closest[candidate_turf])
			rejected_unreachable++
			continue
		valid += candidate_turf

	if(rejected_unreachable)
		log_game("Colony raid [raid_id] discarded [rejected_unreachable] insertion point(s) with no walkable route to the core.")
	return pick_entry_edge(valid)

/// TRUE when the turf sits in the band along the map edge where arrivals are permitted.
/datum/colony_raid/proc/is_edge_band_turf(turf/candidate)
	if(candidate.x <= COLONY_RAID_EDGE_BAND || candidate.y <= COLONY_RAID_EDGE_BAND)
		return TRUE
	if(candidate.x >= world.maxx - COLONY_RAID_EDGE_BAND || candidate.y >= world.maxy - COLONY_RAID_EDGE_BAND)
		return TRUE
	return FALSE

/// The map edge a turf is closest to, as a cardinal direction.
/datum/colony_raid/proc/get_edge_direction(turf/candidate)
	var/nearest = NORTH
	var/nearest_distance = world.maxy - candidate.y
	if(candidate.y - 1 < nearest_distance)
		nearest = SOUTH
		nearest_distance = candidate.y - 1
	if(world.maxx - candidate.x < nearest_distance)
		nearest = EAST
		nearest_distance = world.maxx - candidate.x
	if(candidate.x - 1 < nearest_distance)
		nearest = WEST
	return nearest

/**
 * Keeps only the arrival turfs on one randomly chosen map edge.
 *
 * A raid arrives from the direction it announces and leaves the same way. Spread over every edge, it split into
 * small groups that took separate routes, and its exit could sit across the map behind the colony.
 */
/datum/colony_raid/proc/pick_entry_edge(list/turf/candidates)
	RETURN_TYPE(/list)
	var/list/by_edge = list()
	for(var/turf/candidate as anything in candidates)
		LAZYADDASSOCLIST(by_edge, "[get_edge_direction(candidate)]", candidate)
	if(!length(by_edge))
		return list()
	return by_edge[pick(by_edge)]

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
	// A state assigned directly rather than through set_state() starts its clock on the first tick.
	if(!state_changed_at)
		state_changed_at = world.time

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

	if(state == COLONY_RAID_ASSAULTING && goal == COLONY_RAID_GOAL_THEFT)
		work_the_theft()
	else if(state == COLONY_RAID_RETREATING)
		withdraw_survivors()
	// Retreats walk in legs too. Without this, a retreat stops at its first waypoint and never ends.
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
		// A running raid blocks every later raid and caravan, so survivors that cannot get out must not hold it open.
		if(world.time - state_changed_at >= COLONY_RAID_RETREAT_TIME_LIMIT)
			resolve_raid(finish_theft_outcome(), "the survivors scattered")
			return PROCESS_KILL
		return

	// A theft raid that has carried off everything it came for is finished, win or lose for the colony.
	if(goal == COLONY_RAID_GOAL_THEFT && !length(find_loot_targets()) && !any_raider_carrying())
		resolve_raid(finish_theft_outcome(), extracted_loot ? "the attackers left with what they came for" : "there was nothing left worth taking")
		return PROCESS_KILL

	// Enough of the roster is dead that the rest give up, or the assault ran out of time.
	var/beaten = deployed_strength && ((deployed_strength - alive) / deployed_strength) >= casualty_threshold
	var/out_of_time = world.time - state_changed_at >= COLONY_RAID_ASSAULT_TIME_LIMIT && core?.state != COLONY_CORE_CONTESTED
	if(beaten || out_of_time)
		order_retreat()

/// Spawns the bought attackers across the validated arrival tiles.
/datum/colony_raid/proc/deploy_attackers()
	var/list/available = get_available_units()
	var/list/composition = build_composition(threat_budget, available, live_cap)
	telemetry.record_composition(composition, composition_cost(composition, available))
	for(var/mob_type in composition)
		for(var/i in 1 to composition[mob_type])
			var/turf/arrival = pick(insertion_turfs)
			var/mob/living/attacker = new mob_type(arrival)
			attacker.set_faction(list(faction))
			assign_objective(attacker)
			roster += WEAKREF(attacker)
			offer_to_ghosts(attacker)
			// Killing a thief has to return the goods, and troopers are DEL_ON_DEATH - so this has to be
			// watching before anything can die carrying anything.
			attacker.AddComponent(/datum/component/raider_loot)
			// Counted as AI here and moved across if somebody takes it; a raid is assembled complete and
			// volunteers only ever replace a unit that was already going to attack.
			telemetry.ai_units++

	queue_route_maps()
	offer_raid_to_ghosts()

/// Queues every map the fight will need, so each is usually finished before anybody asks for it.
/datum/colony_raid/proc/queue_route_maps()
	// The core map dates from the warning, which is when the colony builds its defences.
	navigator.request(get_turf(objective_ref?.resolve()))
	navigator.request(get_shared_exit())
	if(goal != COLONY_RAID_GOAL_THEFT)
		return
	for(var/obj/structure/closet/colonist_storage/container as anything in find_loot_targets())
		navigator.request(get_turf(container))

/// One attacker's destination, the leg it is walking now, and whether it is still closing on that leg.
/datum/colony_raid_route
	/// Where the route ends.
	var/turf/goal
	/// The waypoint the attacker is walking to now. The goal itself on the last leg.
	var/turf/leg
	/// Closest the attacker has come to its current leg.
	var/best_distance = INFINITY
	/// When the attacker last came closer to its current leg.
	var/last_progress = 0

/datum/colony_raid_route/New(turf/goal, turf/leg)
	src.goal = goal
	src.leg = leg || goal
	note_progress(INFINITY)

/// Records a new closest distance. Pass INFINITY when the current leg changes.
/datum/colony_raid_route/proc/note_progress(distance)
	best_distance = distance
	last_progress = world.time

/**
 * Gives one attacker its approach route and points it at the first leg.
 *
 * This is the whole of the "strategy" layer: the mob's own AI still decides how to fight, break obstacles and
 * pick targets. All the raid contributes is somewhere to be when nothing else is happening - and, critically,
 * somewhere *close enough to path to*. Handing it the distant core instead leaves it standing still.
 */
/datum/colony_raid/proc/assign_objective(mob/living/attacker)
	var/atom/objective = objective_ref?.resolve()
	if(!objective || !attacker.ai_controller)
		return FALSE

	keep_awake(attacker)
	var/datum/weakref/attacker_ref = WEAKREF(attacker)
	var/turf/objective_turf = get_turf(objective)
	// With no map the objective is presumably already close, so the route heads straight for it.
	LAZYSET(attacker_routes, attacker_ref, new /datum/colony_raid_route(objective_turf, navigator.next_leg(get_turf(attacker), objective_turf)))
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
		var/datum/ai_controller/controller = attacker?.ai_controller
		if(!controller)
			continue
		controller.clear_blackboard_key(BB_TRAVEL_DESTINATION)
		// Survivors are no longer a raid, so they sleep like any other mob when nobody is near.
		if(!(initial(controller.ai_traits) & RUN_WHILE_UNWATCHED))
			controller.ai_traits &= ~RUN_WHILE_UNWATCHED
			controller.reset_ai_status()
	attacker_routes = null

/**
 * Keeps an attacker's AI running when no player is near it.
 * Off-station AI sleeps unwatched, and raids land at the map edge, far from everybody.
 */
/datum/colony_raid/proc/keep_awake(mob/living/attacker)
	var/datum/ai_controller/controller = attacker.ai_controller
	if(!controller || (controller.ai_traits & RUN_WHILE_UNWATCHED))
		return
	controller.ai_traits |= RUN_WHILE_UNWATCHED
	controller.reset_ai_status()

/**
 * Sends `attacker` toward `destination` in legs short enough for JPS, which refuses paths over AI_MAX_PATH_LENGTH.
 * Sticky: a raider already heading there keeps its route. With no map yet, it keeps its old route until one exists.
 */
/datum/colony_raid/proc/route_attacker_to(mob/living/attacker, atom/destination)
	if(!attacker?.ai_controller)
		return FALSE
	var/turf/goal_turf = get_turf(destination)
	if(!goal_turf)
		return FALSE

	keep_awake(attacker)
	var/datum/weakref/attacker_ref = WEAKREF(attacker)
	var/datum/colony_raid_route/current = attacker_routes?[attacker_ref]
	if(current?.goal == goal_turf)
		return TRUE

	if(!navigator.has_map(goal_turf))
		navigator.request(goal_turf)
		return FALSE
	LAZYSET(attacker_routes, attacker_ref, new /datum/colony_raid_route(goal_turf, navigator.next_leg(get_turf(attacker), goal_turf)))
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
	var/datum/colony_raid_route/route = attacker_routes?[attacker_ref]
	if(!route?.leg)
		return FALSE
	attacker.ai_controller?.set_blackboard_key(BB_TRAVEL_DESTINATION, route.leg)
	return TRUE

/**
 * Hands each attacker its next leg on arrival, and a fresh one from where it stands once it is lost or stuck.
 * Legs are read from the route map at the raider's own position, so a fight that drags it off costs it nothing.
 */
/datum/colony_raid/proc/update_attacker_routes()
	for(var/datum/weakref/attacker_ref as anything in attacker_routes)
		var/mob/living/attacker = attacker_ref.resolve()
		if(!attacker || attacker.stat == DEAD)
			continue
		var/datum/colony_raid_route/route = attacker_routes[attacker_ref]
		var/turf/here = get_turf(attacker)
		if(!route?.leg || !here || here.z != route.goal?.z)
			continue

		var/distance = get_dist(here, route.leg)
		var/arrived = distance <= COLONY_RAID_WAYPOINT_ARRIVAL_DISTANCE
		// Standing at the goal is holding it, not being stuck.
		if(arrived && route.leg == route.goal)
			continue
		if(!arrived)
			// Out of path range is lost at once. In range, only a raider that stopped closing in is stuck.
			if(distance <= AI_MAX_PATH_LENGTH)
				if(distance < route.best_distance)
					route.note_progress(distance)
					continue
				if(world.time - route.last_progress < COLONY_RAID_REROUTE_DELAY)
					continue
			// Lost or stuck. The map may predate a wall the colony built since, so ask for a fresh one.
			reroute_count++
			navigator.refresh(route.goal)

		var/turf/next = navigator.next_leg(here, route.goal)
		if(!next)
			// No route from here on the current map. JPS can still try the goal itself if it is in range.
			next = get_dist(here, route.goal) <= AI_MAX_PATH_LENGTH ? route.goal : route.leg
		route.leg = next
		route.note_progress(INFINITY)
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
		// No way out yet. Standing orders still have to be cancelled, or calling off the attack would leave
		// everybody marching on the objective exactly as before. withdraw_survivors() keeps trying.
		LAZYREMOVE(attacker_routes, attacker_ref)
		attacker.ai_controller.clear_blackboard_key(BB_TRAVEL_DESTINATION)
	priority_announce("The surviving attackers are pulling back.", "Colony Perimeter Alert")
	return TRUE

/// Routes every survivor toward the exit. Survivors stay put until the exit's map exists.
/datum/colony_raid/proc/withdraw_survivors()
	for(var/datum/weakref/attacker_ref as anything in roster)
		var/mob/living/attacker = attacker_ref.resolve()
		if(attacker && attacker.stat != DEAD)
			send_raider_home(attacker)

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
