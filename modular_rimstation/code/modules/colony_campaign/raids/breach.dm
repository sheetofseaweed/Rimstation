/**
 * Breaking into a closed colony.
 *
 * The colony is unpowered, so its airlocks stay shut, and a mineral door opens only for a mob with a player. A
 * colony with its doors closed therefore has no walkable way in. A breach finds the cheapest way through what
 * the raiders can break - doors, windows, grilles, girders, barricades - and sends them to break it, one
 * obstacle at a time. Walls are never breached: raiders cannot damage them.
 */

/// TRUE when raiders can break `blocker` by hitting it.
/proc/is_raid_breachable(obj/blocker)
	return blocker.uses_integrity && !(blocker.resistance_flags & INDESTRUCTIBLE)

/// The first dense object on `here` that keeps a raider out, or null when nothing does.
/proc/get_raid_breach_blocker(turf/here, datum/can_pass_info/pass_info)
	RETURN_TYPE(/obj)
	for(var/obj/blocker in here)
		if(blocker.density && !blocker.CanAStarPass(NONE, pass_info))
			return blocker
	return null


/// One planned way in: the obstacles to break, in order from the outside inward, and where to stand for each.
/datum/colony_raid_breach
	/// What the breach opens a way to.
	var/turf/goal
	/// Turfs holding something to break, from the outside inward.
	var/list/turf/obstacles
	/// For each obstacle, the open turf beside it on the raiders' side. Same order as `obstacles`.
	var/list/turf/staging
	/// Which obstacle is being broken now.
	var/stage = 1
	/// When the first raider reached the current obstacle. Zero until one has.
	var/stage_started_at = 0

/datum/colony_raid_breach/New(turf/goal, list/turf/obstacles, list/turf/staging)
	src.goal = goal
	src.obstacles = obstacles
	src.staging = staging

/datum/colony_raid_breach/proc/current_obstacle()
	RETURN_TYPE(/turf)
	return stage <= length(obstacles) ? obstacles[stage] : null

/datum/colony_raid_breach/proc/current_staging()
	RETURN_TYPE(/turf)
	return stage <= length(staging) ? staging[stage] : null

/// Moves on to the next obstacle. Returns FALSE when there is none left.
/datum/colony_raid_breach/proc/advance()
	stage++
	stage_started_at = 0
	return stage <= length(obstacles)


/**
 * What entering `next` costs a breach search, or null when raiders can never get onto it.
 * Open ground costs 1. Each breakable blocker adds a base cost plus the hits it takes, so open detours win.
 */
/datum/colony_raid_navigator/proc/breach_step_cost(turf/next)
	if(!next || next.density || SSpathfinder.space_type_cache[next.type])
		return null
	switch(next.pathing_pass_method)
		if(TURF_PATHING_PASS_NO)
			return null
		if(TURF_PATHING_PASS_PROC)
			if(!next.CanAStarPass(NONE, pass_info))
				return null
	var/cost = 1
	for(var/obj/blocker in next)
		if(!blocker.density || blocker.CanAStarPass(NONE, pass_info))
			continue
		if(!is_raid_breachable(blocker))
			return null
		cost += COLONY_RAID_BREACH_BASE_COST + ceil(blocker.get_integrity() / COLONY_RAID_BREACH_HIT_DAMAGE)
	return min(cost, COLONY_RAID_BREACH_MAX_STEP_COST)

/**
 * The cheapest way from `goal` out to any turf `outside` reaches, breaking through what is in the way.
 * Dial's algorithm over real turfs: step costs are bounded integers, so a ring of buckets replaces a heap.
 * Returns a breach with no obstacles when the way is already open, or null when there is no way at all.
 */
/datum/colony_raid_navigator/proc/find_breach(turf/goal, datum/path_map/outside)
	RETURN_TYPE(/datum/colony_raid_breach)
	if(!goal || !outside)
		return null
	var/list/cost_to = list()
	var/list/came_from = list()
	var/bucket_count = COLONY_RAID_BREACH_MAX_STEP_COST + 1
	var/list/buckets = new /list(bucket_count)
	for(var/bucket_index in 1 to bucket_count)
		buckets[bucket_index] = list()

	cost_to[goal] = 0
	buckets[1] += goal
	var/pending = 1
	var/expanded = 0
	var/current_cost = 0
	while(pending && expanded < COLONY_RAID_BREACH_SEARCH_LIMIT)
		var/list/bucket = buckets[(current_cost % bucket_count) + 1]
		while(length(bucket))
			var/turf/here = bucket[length(bucket)]
			bucket.len--
			pending--
			// A turf re-queued at a lower cost leaves its older entry behind.
			if(cost_to[here] != current_cost)
				continue
			if(here != goal && outside.next_closest[here])
				return build_breach(goal, here, came_from)
			expanded++
			for(var/turf/open/next as anything in get_adjacent_open_turfs(here))
				var/step_cost = breach_step_cost(next)
				if(isnull(step_cost))
					continue
				var/new_cost = current_cost + step_cost
				if(!isnull(cost_to[next]) && cost_to[next] <= new_cost)
					continue
				cost_to[next] = new_cost
				came_from[next] = here
				buckets[(new_cost % bucket_count) + 1] += next
				pending++
		current_cost++
		CHECK_TICK
		// The raid can end while this sleeps.
		if(QDELETED(src))
			return null
	return null

/// Turns a found route into a breach: every turf on it holding a blocker, with the turf before it to stand on.
/datum/colony_raid_navigator/proc/build_breach(turf/goal, turf/outside_turf, list/came_from)
	RETURN_TYPE(/datum/colony_raid_breach)
	var/list/turf/route = list()
	var/turf/walked = outside_turf
	while(walked && walked != goal)
		route += walked
		walked = came_from[walked]
	var/list/turf/obstacles = list()
	var/list/turf/staging = list()
	// The first turf is outside and open, so obstacles start from the second.
	for(var/position in 2 to length(route))
		if(get_raid_breach_blocker(route[position], pass_info))
			obstacles += route[position]
			staging += route[position - 1]
	return new /datum/colony_raid_breach(goal, obstacles, staging)


/**
 * Plans a way in from one map edge when the core cannot be walked to from any. Returns the arrival turfs it used.
 * Runs at warning time, when nothing has spawned yet, so it may wait for each edge's map.
 */
/datum/colony_raid/proc/plan_entry_breach(turf/core_turf, list/turf/candidates)
	RETURN_TYPE(/list)
	var/list/by_edge = list()
	for(var/turf/candidate as anything in candidates)
		LAZYADDASSOCLIST(by_edge, "[get_edge_direction(candidate)]", candidate)
	for(var/edge in shuffle(assoc_to_keys(by_edge)))
		var/list/turf/edge_turfs = by_edge[edge]
		var/turf/source = edge_turfs[1]
		var/datum/path_map/outside = navigator.get_map_now(source)
		if(QDELETED(src))
			return list()
		if(!outside)
			continue
		var/datum/colony_raid_breach/plan = navigator.find_breach(core_turf, outside)
		if(QDELETED(src))
			return list()
		if(!length(plan?.obstacles))
			continue
		var/list/turf/arrivals = list()
		for(var/turf/arrival as anything in edge_turfs)
			if(outside.next_closest[arrival])
				arrivals += arrival
		shared_exit = source
		start_breach(plan)
		return arrivals
	return list()

/// Asks for a breach toward `goal_turf` in the background. One plan at a time, and not too often.
/datum/colony_raid/proc/request_breach(turf/goal_turf)
	if(breach || planning_breach || world.time < next_breach_plan_at)
		return FALSE
	planning_breach = TRUE
	next_breach_plan_at = world.time + COLONY_RAID_BREACH_REPLAN_DELAY
	INVOKE_ASYNC(src, PROC_REF(plan_breach), goal_turf)
	return TRUE

/// Plans a breach from the raiders' side, the exit's map, toward `goal_turf`. Sleeps while maps build.
/datum/colony_raid/proc/plan_breach(turf/goal_turf)
	var/turf/outside_turf = get_shared_exit()
	var/datum/path_map/outside = outside_turf ? navigator?.get_map_now(outside_turf) : null
	var/datum/colony_raid_breach/plan
	if(outside && !QDELETED(src))
		plan = navigator.find_breach(goal_turf, outside)
	planning_breach = FALSE
	if(QDELETED(src) || state != COLONY_RAID_ASSAULTING || breach)
		return
	if(length(plan?.obstacles))
		start_breach(plan)
		return
	// No way in at all, or one that is open on paper and raiders still cannot walk. Both count as a failed try.
	failed_breaches++
	log_game("Colony raid [raid_id] found no way to break in toward [AREACOORD(goal_turf)] ([failed_breaches] of [COLONY_RAID_MAX_BREACH_ATTEMPTS]).")
	if(failed_breaches >= COLONY_RAID_MAX_BREACH_ATTEMPTS)
		order_retreat()
	else if(plan)
		navigator.request(goal_turf)

/datum/colony_raid/proc/start_breach(datum/colony_raid_breach/plan)
	breach = plan
	navigator.request(plan.current_staging())
	log_game("Colony raid [raid_id] will break in through [length(plan.obstacles)] obstacle(s), the first at [AREACOORD(plan.current_obstacle())].")

/**
 * Moves an attacker bound for the breach's goal to the current obstacle, and tells it to break it once close.
 * Legs toward the staging turf change only on arrival or when stuck, the same as ordinary routes.
 */
/datum/colony_raid/proc/follow_breach(mob/living/attacker, datum/weakref/attacker_ref, datum/colony_raid_route/route, turf/here)
	var/turf/obstacle = breach.current_obstacle()
	if(get_dist(here, obstacle) <= COLONY_RAID_BREACH_ORDER_RANGE)
		var/obj/blocker = get_raid_breach_blocker(obstacle, navigator.pass_info)
		var/datum/ai_controller/controller = attacker.ai_controller
		if(blocker && controller && controller.blackboard[BB_RAID_BREACH_TARGET] != blocker)
			controller.set_blackboard_key(BB_RAID_BREACH_TARGET, blocker)
		if(!breach.stage_started_at)
			breach.stage_started_at = world.time
		return

	var/turf/staging = breach.current_staging()
	var/distance = get_dist(here, route.leg)
	if(route.toward == staging && distance > COLONY_RAID_WAYPOINT_ARRIVAL_DISTANCE && distance <= AI_MAX_PATH_LENGTH)
		if(distance < route.best_distance)
			route.note_progress(distance)
			return
		if(world.time - route.last_progress < COLONY_RAID_REROUTE_DELAY)
			return
	var/turf/next = navigator.next_leg(here, staging)
	if(!next)
		next = get_dist(here, staging) <= AI_MAX_PATH_LENGTH ? staging : route.leg
	route.toward = staging
	route.leg = next
	route.note_progress(INFINITY)
	advance_waypoint(attacker, attacker_ref)

/// Moves the breach along once its obstacle is open, and gives it up when the raiders take too long.
/datum/colony_raid/proc/update_breach()
	if(!breach)
		return
	var/obj/blocker = get_raid_breach_blocker(breach.current_obstacle(), navigator.pass_info)
	if(!blocker)
		if(breach.advance())
			navigator.request(breach.current_staging())
			return
		end_breach(succeeded = TRUE)
		return
	if(!is_raid_breachable(blocker))
		end_breach(succeeded = FALSE)
		return
	if(breach.stage_started_at && world.time - breach.stage_started_at >= COLONY_RAID_BREACH_STAGE_TIME_LIMIT)
		end_breach(succeeded = FALSE)

/// Ends the current breach. A broken-through goal gets a fresh map; enough failures send the raiders home.
/datum/colony_raid/proc/end_breach(succeeded)
	var/turf/opened = breach.goal
	clear_breach_orders()
	breach = null
	if(succeeded)
		log_game("Colony raid [raid_id] broke through toward [AREACOORD(opened)].")
		navigator.request(opened)
		return
	failed_breaches++
	log_game("Colony raid [raid_id] failed to break in toward [AREACOORD(opened)] ([failed_breaches] of [COLONY_RAID_MAX_BREACH_ATTEMPTS]).")
	if(failed_breaches >= COLONY_RAID_MAX_BREACH_ATTEMPTS)
		order_retreat()

/// Takes the breach target off every attacker.
/datum/colony_raid/proc/clear_breach_orders()
	for(var/datum/weakref/attacker_ref as anything in roster)
		var/mob/living/attacker = attacker_ref.resolve()
		attacker?.ai_controller?.clear_blackboard_key(BB_RAID_BREACH_TARGET)


/// Raider subtree: walk next to the breach target and hit it until it gives way.
/datum/bt_node/subtree/rimstation_raid_breach
	behavior_tree_json = "modular_rimstation/code/modules/colony_campaign/raids/raid_breach.bt.json"

/// Hits the breach target while adjacent. Succeeds once it is gone or open, which clears the order.
/datum/bt_node/ai_behavior/rimstation_breach
	/// Blackboard key holding the object to break.
	var/target_key = BB_RAID_BREACH_TARGET
	time_between_perform = 1 SECONDS

/datum/bt_node/ai_behavior/rimstation_breach/perform(seconds_per_tick, datum/ai_controller/controller)
	var/obj/target = controller.blackboard[target_key]
	if(QDELETED(target) || !target.density)
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_SUCCEEDED
	var/mob/living/basic/raider = controller.pawn
	if(!istype(raider) || get_dist(raider, target) > 1)
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_FAILED
	if(!raider.Adjacent(target))
		// Diagonal across a wall corner. Step to whichever side of the target is open, then swing next time.
		for(var/turf/beside in list(locate(target.x, raider.y, raider.z), locate(raider.x, target.y, raider.z)))
			if(!beside.is_blocked_turf(exclude_mobs = TRUE) && raider.Move(beside, get_dir(raider, beside)))
				break
		return AI_BEHAVIOR_DELAY
	raider.melee_attack(target)
	return AI_BEHAVIOR_DELAY

/datum/bt_node/ai_behavior/rimstation_breach/finish_action(datum/ai_controller/controller, succeeded)
	. = ..()
	if(succeeded)
		controller.clear_blackboard_key(target_key)
