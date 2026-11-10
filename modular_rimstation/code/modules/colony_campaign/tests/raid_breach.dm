/**
 * Rings `centre` with wooden barricades on all eight sides, and returns the one south of it as a door.
 * Every other barricade is made indestructible, so the door is the only way in.
 */
/datum/unit_test/proc/rimstation_build_breach_ring(turf/centre)
	RETURN_TYPE(/obj/structure/barricade/wooden)
	var/obj/structure/barricade/wooden/door
	for(var/turf/around in orange(1, centre))
		var/obj/structure/barricade/wooden/piece = allocate(/obj/structure/barricade/wooden, around)
		if(around.x == centre.x && around.y == centre.y - 1)
			door = piece
			continue
		piece.resistance_flags |= INDESTRUCTIBLE
	return door

/**
 * A closed ring is planned through its one breakable door, an open gap is used instead of breaking anything,
 * and a ring with nothing breakable has no way in at all.
 */
/datum/unit_test/rimstation_raid_breach_plan

/datum/unit_test/rimstation_raid_breach_plan/Run()
	var/datum/colony_raid_navigator/navigator = new
	allocated += navigator
	var/turf/outside_turf = run_loc_floor_bottom_left
	var/turf/core_turf = locate(outside_turf.x + 2, outside_turf.y + 2, outside_turf.z)
	allocate(/obj/structure/colony_core, core_turf)
	var/obj/structure/barricade/wooden/door = rimstation_build_breach_ring(core_turf)
	var/turf/door_turf = get_turf(door)

	var/datum/path_map/outside = navigator.get_map_now(outside_turf)
	TEST_ASSERT_NOTNULL(outside, "No route map could be built outside the ring.")
	var/datum/colony_raid_breach/plan = navigator.find_breach(core_turf, outside)
	TEST_ASSERT_NOTNULL(plan, "A ring with a breakable door had no planned way in.")
	TEST_ASSERT_EQUAL(length(plan.obstacles), 1, "A ring with one door was planned through [length(plan.obstacles)] obstacles.")
	TEST_ASSERT_EQUAL(plan.obstacles[1], door_turf, "The breach did not go through the only breakable door.")
	TEST_ASSERT_EQUAL(plan.staging[1], locate(door_turf.x, door_turf.y - 1, door_turf.z), "Raiders were told to stand somewhere other than outside the door.")

	// An open gap is free, so nothing is broken when walking round is possible.
	var/obj/structure/barricade/wooden/west_wall = locate() in locate(core_turf.x - 1, core_turf.y, core_turf.z)
	qdel(west_wall)
	navigator.request(outside_turf)
	var/datum/colony_raid_breach/open_plan = navigator.find_breach(core_turf, navigator.get_map_now(outside_turf))
	TEST_ASSERT_NOTNULL(open_plan, "A ring with an open gap had no way in at all.")
	TEST_ASSERT_EQUAL(length(open_plan.obstacles), 0, "Raiders planned to break a door beside an open gap.")

	// Nothing breakable and no gap means no way in.
	var/obj/structure/barricade/wooden/new_wall = allocate(/obj/structure/barricade/wooden, locate(core_turf.x - 1, core_turf.y, core_turf.z))
	new_wall.resistance_flags |= INDESTRUCTIBLE
	door.resistance_flags |= INDESTRUCTIBLE
	navigator.request(outside_turf)
	TEST_ASSERT_NULL(navigator.find_breach(core_turf, navigator.get_map_now(outside_turf)), "A ring of unbreakable walls was given a way in.")

/// A raider told to break something walks to it and hits it until it gives way, with its real AI.
/datum/unit_test/rimstation_raid_raider_breaks_through

/datum/unit_test/rimstation_raid_raider_breaks_through/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/obj/structure/barricade/wooden/target = allocate(/obj/structure/barricade/wooden, run_loc_floor_top_right)
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/raider = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, run_loc_floor_bottom_left)
	raid.keep_awake(raider)
	raider.ai_controller.set_blackboard_key(BB_RAID_BREACH_TARGET, target)

	var/give_up_at = world.time + 30 SECONDS
	while(!QDELETED(target) && world.time < give_up_at)
		sleep(0.5 SECONDS)
	TEST_ASSERT(QDELETED(target), "A raider told to break a barricade had not broken it after 30 seconds.")
	TEST_ASSERT_NULL(raider.ai_controller.blackboard[BB_RAID_BREACH_TARGET], "A raider kept its breach order after the target was gone.")

/**
 * Raiders near the obstacle are told to break it, a broken obstacle ends the breach, a slow one fails it,
 * and enough failures send the raid home.
 */
/datum/unit_test/rimstation_raid_breach_orders

/datum/unit_test/rimstation_raid_breach_orders/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	for(var/next_state in list(COLONY_RAID_WARNING, COLONY_RAID_ASSEMBLING, COLONY_RAID_ARRIVING, COLONY_RAID_ASSAULTING))
		raid.set_state(next_state)
	var/turf/outside_turf = run_loc_floor_bottom_left
	var/turf/core_turf = locate(outside_turf.x + 2, outside_turf.y + 2, outside_turf.z)
	var/obj/structure/colony_core/core = allocate(/obj/structure/colony_core, core_turf)
	raid.objective_ref = WEAKREF(core)
	var/obj/structure/barricade/wooden/door = rimstation_build_breach_ring(core_turf)
	var/turf/door_turf = get_turf(door)

	var/turf/staging = locate(door_turf.x, door_turf.y - 1, door_turf.z)
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/raider = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, staging)
	raider.ai_controller.force_ai_off()
	raid.roster += WEAKREF(raider)
	raid.attacker_routes = list()
	raid.attacker_routes[WEAKREF(raider)] = new /datum/colony_raid_route(core_turf, null)

	var/datum/path_map/outside = raid.navigator.get_map_now(outside_turf)
	raid.start_breach(raid.navigator.find_breach(core_turf, outside))
	raid.update_attacker_routes()
	TEST_ASSERT_EQUAL(raider.ai_controller.blackboard[BB_RAID_BREACH_TARGET], door, "A raider beside the door was not told to break it.")
	TEST_ASSERT(raid.breach.stage_started_at, "The breach clock did not start when a raider reached the door.")

	qdel(door)
	raid.update_breach()
	TEST_ASSERT_NULL(raid.breach, "A breach whose only obstacle was gone did not end.")
	TEST_ASSERT_NULL(raider.ai_controller.blackboard[BB_RAID_BREACH_TARGET], "A raider kept its breach order after the breach ended.")
	TEST_ASSERT_EQUAL(raid.failed_breaches, 0, "A successful breach was counted as a failure.")

	// A door nobody manages to break within the limit fails the breach.
	allocate(/obj/structure/barricade/wooden, door_turf)
	raid.start_breach(raid.navigator.find_breach(core_turf, outside))
	raid.breach.stage_started_at = world.time - COLONY_RAID_BREACH_STAGE_TIME_LIMIT
	raid.update_breach()
	TEST_ASSERT_NULL(raid.breach, "A breach past its time limit was not given up.")
	TEST_ASSERT_EQUAL(raid.failed_breaches, 1, "A breach past its time limit was not counted as a failure.")

	// The last allowed failure sends the raid home rather than leaving it at the wall.
	raid.failed_breaches = COLONY_RAID_MAX_BREACH_ATTEMPTS - 1
	raid.start_breach(raid.navigator.find_breach(core_turf, outside))
	raid.breach.stage_started_at = world.time - COLONY_RAID_BREACH_STAGE_TIME_LIMIT
	raid.update_breach()
	TEST_ASSERT_EQUAL(raid.state, COLONY_RAID_RETREATING, "A raid out of breach attempts did not withdraw.")

/// A colony closed on every side is broken into from an edge rather than the raid being cancelled.
/datum/unit_test/rimstation_raid_entry_breach

/datum/unit_test/rimstation_raid_entry_breach/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/turf/outside_turf = run_loc_floor_bottom_left
	var/turf/core_turf = locate(outside_turf.x + 2, outside_turf.y + 2, outside_turf.z)
	allocate(/obj/structure/colony_core, core_turf)
	var/obj/structure/barricade/wooden/door = rimstation_build_breach_ring(core_turf)

	var/list/turf/arrivals = raid.plan_entry_breach(core_turf, list(outside_turf))
	TEST_ASSERT_EQUAL(length(arrivals), 1, "A closed colony with a breakable door had no arrival point.")
	TEST_ASSERT_EQUAL(arrivals[1], outside_turf, "The raid would arrive somewhere other than the edge it planned from.")
	TEST_ASSERT_NOTNULL(raid.breach, "A closed colony was arrived at with no plan to break in.")
	TEST_ASSERT_EQUAL(raid.breach.current_obstacle(), get_turf(door), "The planned way in was not the door.")
	TEST_ASSERT_EQUAL(raid.shared_exit, outside_turf, "The raid's way out was not the edge it came in from.")

	var/datum/colony_raid/blocked = new
	allocated += blocked
	door.resistance_flags |= INDESTRUCTIBLE
	TEST_ASSERT(!length(blocked.plan_entry_breach(core_turf, list(outside_turf))), "A colony behind unbreakable walls was given an arrival point.")
	TEST_ASSERT_NULL(blocked.breach, "A colony behind unbreakable walls was given a breach.")

/**
 * Raiders gather at the second node of an arrival lane, wait for stragglers within the time limit, then go for
 * the objective together.
 */
/datum/unit_test/rimstation_raid_rally

/datum/unit_test/rimstation_raid_rally/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/turf/edge = run_loc_floor_bottom_left
	var/z = edge.z
	var/obj/effect/landmark/rimstation_raid_insertion/marker = allocate(/obj/effect/landmark/rimstation_raid_insertion, edge)
	marker.lane_id = "lane-test"
	var/list/node_spots = list(locate(edge.x + 1, edge.y, z), locate(edge.x + 3, edge.y, z), run_loc_floor_top_right)
	for(var/order in 1 to length(node_spots))
		var/obj/effect/landmark/rimstation_raid_lane_node/node = allocate(/obj/effect/landmark/rimstation_raid_lane_node, node_spots[order])
		node.lane_id = "lane-test"
		node.lane_order = order
	var/obj/effect/landmark/rimstation_raid_lane_node/other_lane = allocate(/obj/effect/landmark/rimstation_raid_lane_node, locate(edge.x + 4, edge.y + 2, z))
	other_lane.lane_id = "lane-elsewhere"
	other_lane.lane_order = COLONY_RAID_RALLY_LANE_ORDER

	raid.insertion_turfs = list(edge)
	TEST_ASSERT_EQUAL(raid.choose_rally(), node_spots[COLONY_RAID_RALLY_LANE_ORDER], "The rally was not the right node of the arrival lane.")
	TEST_ASSERT_NOTNULL(raid.navigator.get_map_now(raid.rally_turf), "No route map could be built toward the rally.")

	var/turf/core_turf = locate(edge.x, edge.y + 4, z)
	raid.objective_ref = WEAKREF(allocate(/obj/structure/colony_core, core_turf))
	for(var/next_state in list(COLONY_RAID_WARNING, COLONY_RAID_ASSEMBLING, COLONY_RAID_ARRIVING, COLONY_RAID_ASSAULTING))
		raid.set_state(next_state)
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/near = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, edge)
	near.ai_controller.force_ai_off()
	raid.roster += WEAKREF(near)
	TEST_ASSERT(raid.start_rally(), "A raider that could reach the rally was not sent to it.")
	var/datum/colony_raid_route/near_route = raid.attacker_routes[WEAKREF(near)]
	TEST_ASSERT_EQUAL(near_route.goal, raid.rally_turf, "A raider was not routed to the rally.")

	// A straggler still on its way holds the rally open, until the time limit.
	var/turf/far_turf = locate(edge.x - (COLONY_RAID_RALLY_RADIUS + 10), edge.y, z)
	TEST_ASSERT_NOTNULL(far_turf, "The test map has no room to place a straggler.")
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/far = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, far_turf)
	far.ai_controller.force_ai_off()
	raid.roster += WEAKREF(far)
	raid.attacker_routes[WEAKREF(far)] = new /datum/colony_raid_route(raid.rally_turf, raid.rally_turf)
	raid.update_rally()
	TEST_ASSERT_NOTNULL(raid.rally_turf, "The rally ended while a raider bound for it was still far away.")
	raid.rally_ends_at = world.time - 1
	raid.update_rally()
	TEST_ASSERT_NULL(raid.rally_turf, "The rally outlasted its time limit.")
	near_route = raid.attacker_routes[WEAKREF(near)]
	TEST_ASSERT_EQUAL(near_route.goal, core_turf, "A raider leaving the rally was not sent at the objective.")
