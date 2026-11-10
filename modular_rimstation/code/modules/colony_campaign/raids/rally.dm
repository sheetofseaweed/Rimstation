/**
 * Gathering on a raid lane before the push.
 *
 * Raiders arrive at up to two markers on one edge and walk at different speeds, so without a rally they reach
 * the colony one at a time. They gather at a lane node near the edge first, on the trail the colony can see.
 */

/// Picks the rally: the node COLONY_RAID_RALLY_LANE_ORDER along an arrival lane, or the furthest one short of it.
/datum/colony_raid/proc/choose_rally()
	rally_turf = null
	var/list/arrival_lanes = list()
	for(var/obj/effect/landmark/rimstation_raid_insertion/marker as anything in GLOB.rimstation_raid_insertion_points)
		if(marker.lane_id && (get_turf(marker) in insertion_turfs))
			arrival_lanes[marker.lane_id] = TRUE
	var/list/best_by_lane = list()
	for(var/obj/effect/landmark/rimstation_raid_lane_node/node as anything in GLOB.rimstation_raid_lane_nodes)
		if(!arrival_lanes[node.lane_id] || node.lane_order > COLONY_RAID_RALLY_LANE_ORDER)
			continue
		var/obj/effect/landmark/rimstation_raid_lane_node/current = best_by_lane[node.lane_id]
		if(!current || node.lane_order > current.lane_order)
			best_by_lane[node.lane_id] = node
	if(!length(best_by_lane))
		return null
	var/obj/effect/landmark/rimstation_raid_lane_node/chosen = best_by_lane[pick(best_by_lane)]
	rally_turf = get_turf(chosen)
	// Built during the warning, so it is ready when the raiders land.
	navigator.request(rally_turf)
	return rally_turf

/// Sends every attacker that can reach the rally to it. Returns FALSE, and drops the rally, when nobody can.
/datum/colony_raid/proc/start_rally()
	if(!rally_turf || !navigator.has_map(rally_turf))
		rally_turf = null
		return FALSE
	var/sent = 0
	for(var/datum/weakref/attacker_ref as anything in roster)
		var/mob/living/attacker = attacker_ref.resolve()
		if(!attacker || attacker.stat == DEAD || !navigator.is_reachable(get_turf(attacker), rally_turf))
			continue
		if(route_attacker_to(attacker, rally_turf))
			sent++
	if(!sent)
		rally_turf = null
		return FALSE
	rally_ends_at = world.time + COLONY_RAID_RALLY_TIME_LIMIT
	return TRUE

/// Ends the rally once everyone bound for it is close, or it has waited long enough.
/datum/colony_raid/proc/update_rally()
	if(!rally_turf)
		return
	if(world.time < rally_ends_at)
		for(var/datum/weakref/attacker_ref as anything in attacker_routes)
			var/datum/colony_raid_route/route = attacker_routes[attacker_ref]
			if(route?.goal != rally_turf)
				continue
			var/mob/living/attacker = attacker_ref.resolve()
			if(!attacker || attacker.stat == DEAD)
				continue
			if(get_dist(attacker, rally_turf) > COLONY_RAID_RALLY_RADIUS)
				return
	end_rally()

/// Sends everyone at the rally on to the objective.
/datum/colony_raid/proc/end_rally()
	var/turf/finished = rally_turf
	rally_turf = null
	rally_ends_at = 0
	for(var/datum/weakref/attacker_ref as anything in roster)
		var/mob/living/attacker = attacker_ref.resolve()
		var/datum/colony_raid_route/route = attacker_routes?[attacker_ref]
		if(!attacker || attacker.stat == DEAD || route?.goal != finished)
			continue
		if(goal == COLONY_RAID_GOAL_THEFT)
			// The theft logic gives thieves their stash on its next pass.
			LAZYREMOVE(attacker_routes, attacker_ref)
		else
			assign_objective(attacker)
	log_game("Colony raid [raid_id] left its rally at [AREACOORD(finished)].")
