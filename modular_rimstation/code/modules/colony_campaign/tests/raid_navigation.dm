/// Lets `walker` move on its own for up to `timeout`, and returns the closest it came to `target`.
/proc/rimstation_closest_approach(mob/living/walker, atom/target, timeout = 20 SECONDS)
	var/closest = get_dist(walker, target)
	var/give_up_at = world.time + timeout
	while(closest > 1 && world.time < give_up_at)
		sleep(0.5 SECONDS)
		closest = min(closest, get_dist(walker, target))
	return closest

/**
 * A raider sent at the core has to arrive next to it, with its real AI doing the walking and no player near.
 * Unwatched off-station AI sleeps, and JPS cannot end on the dense core tile. Either one left raiders standing.
 */
/datum/unit_test/rimstation_raid_raider_reaches_core

/datum/unit_test/rimstation_raid_raider_reaches_core/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/obj/structure/colony_core/core = allocate(/obj/structure/colony_core, run_loc_floor_top_right)
	raid.objective_ref = WEAKREF(core)
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/raider = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, run_loc_floor_bottom_left)
	raid.roster += WEAKREF(raider)

	TEST_ASSERT(raid.assign_objective(raider), "The raid could not give a raider its objective.")
	var/closest = rimstation_closest_approach(raider, core)
	TEST_ASSERT(closest <= 1, "A raider sent at the colony core came no closer than [closest] tiles, so it could never take it.")
	TEST_ASSERT_NOTEQUAL(raider.ai_controller.ai_status, AI_STATUS_OFF, "A raider's AI went to sleep with no player near, so it would stand at the map edge.")

	raid.resolve_raid(COLONY_RAID_OUTCOME_REPELLED, "the test ended it")
	TEST_ASSERT(!(raider.ai_controller.ai_traits & RUN_WHILE_UNWATCHED), "A survivor of a finished raid kept running its AI with nobody near.")

/**
 * A raider handed a new leg mid-walk has to walk to the new leg, not the old one.
 * The JPS move loop kept its first target, so raiders shuffled at their first leg on the real map.
 */
/datum/unit_test/rimstation_raid_raider_follows_new_leg

/datum/unit_test/rimstation_raid_raider_follows_new_leg/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/turf/first_leg = run_loc_floor_top_right
	var/turf/second_leg = locate(run_loc_floor_top_right.x, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/raider = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, run_loc_floor_bottom_left)
	raid.keep_awake(raider)

	raider.ai_controller.set_blackboard_key(BB_TRAVEL_DESTINATION, first_leg)
	sleep(1 SECONDS)
	raider.ai_controller.set_blackboard_key(BB_TRAVEL_DESTINATION, second_leg)
	var/closest = rimstation_closest_approach(raider, second_leg)
	TEST_ASSERT(closest <= 1, "A raider given a new leg mid-walk came no closer than [closest] tiles to it, so it was still walking to the old one.")

/// Route maps the raid queues have to finish on their own, in slices, with nobody waiting on them.
/datum/unit_test/rimstation_raid_maps_build_in_background

/datum/unit_test/rimstation_raid_maps_build_in_background/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/turf/goal = run_loc_floor_top_right
	TEST_ASSERT(raid.navigator.request(goal), "A route map could not be queued.")
	TEST_ASSERT(!raid.navigator.request(goal), "A second build was queued toward a goal that was already building.")

	var/give_up_at = world.time + 20 SECONDS
	while(!raid.navigator.has_map(goal) && world.time < give_up_at)
		sleep(0.5 SECONDS)
	TEST_ASSERT(raid.navigator.has_map(goal), "A queued route map never finished, so raiders would wait on it forever.")
	TEST_ASSERT(raid.navigator.is_reachable(run_loc_floor_bottom_left, goal), "A finished route map had no route across an open room.")
	TEST_ASSERT(!length(raid.navigator.builds), "A finished build was left in the queue.")

/// A thief has to reach a stash to loot it, and a stash is as dense as the core.
/datum/unit_test/rimstation_raid_thief_reaches_stash

/datum/unit_test/rimstation_raid_thief_reaches_stash/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/obj/structure/closet/colonist_storage/stash/stash = allocate(/obj/structure/closet/colonist_storage/stash, run_loc_floor_top_right)
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/thief = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, run_loc_floor_bottom_left)
	raid.roster += WEAKREF(thief)

	// A raid queues its stash maps at deploy. This one never deployed, so it builds the map here.
	TEST_ASSERT_NOTNULL(raid.navigator.get_map_now(get_turf(stash)), "No route map could be built toward the stash.")
	TEST_ASSERT(raid.route_attacker_to(thief, stash), "A thief could not be routed to a stash in the same room.")
	var/closest = rimstation_closest_approach(thief, stash)
	TEST_ASSERT(closest <= 1, "A thief sent at a stash came no closer than [closest] tiles, so it could never loot it.")

/**
 * A raider closing on its leg is left alone, and one that lost its leg gets a new one from where it stands.
 * Combat drags raiders off their legs, and JPS refuses any leg further than AI_MAX_PATH_LENGTH.
 */
/datum/unit_test/rimstation_raid_raider_reroutes

/datum/unit_test/rimstation_raid_raider_reroutes/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/turf/here = run_loc_floor_bottom_left
	var/turf/goal = run_loc_floor_top_right
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/raider = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, here)
	// The raider must not move while its route is read.
	raider.ai_controller.force_ai_off()
	TEST_ASSERT_NOTNULL(raid.navigator.get_map_now(goal), "No route map could be built in the test room.")

	var/turf/far_leg = locate(here.x + AI_MAX_PATH_LENGTH + 10, here.y, here.z)
	TEST_ASSERT_NOTNULL(far_leg, "The test map is too small to place a leg out of path range.")
	var/datum/colony_raid_route/route = new(goal, far_leg)
	raid.attacker_routes = list()
	raid.attacker_routes[WEAKREF(raider)] = route

	raid.update_attacker_routes()
	TEST_ASSERT_EQUAL(raid.reroute_count, 1, "A raider whose leg was out of path range was not given a new one.")
	TEST_ASSERT_EQUAL(route.leg, goal, "A raider within one leg of its goal was not sent straight to it.")
	TEST_ASSERT_EQUAL(raider.ai_controller.blackboard[BB_TRAVEL_DESTINATION], goal, "A new leg was never handed to the raider.")

	// Closing on a leg is progress, and progress is left alone.
	var/turf/side = locate(goal.x, here.y, here.z)
	route.leg = side
	route.best_distance = INFINITY
	raid.update_attacker_routes()
	TEST_ASSERT_EQUAL(raid.reroute_count, 1, "A raider making progress was given a new leg anyway.")
	TEST_ASSERT_EQUAL(route.leg, side, "A raider making progress had its leg replaced.")

	// In range but no longer getting closer is stuck too.
	route.best_distance = 0
	route.last_progress = world.time - COLONY_RAID_REROUTE_DELAY
	raid.update_attacker_routes()
	TEST_ASSERT_EQUAL(raid.reroute_count, 2, "A raider that stopped closing on its leg was never given a new one.")

	// A leg out of path range is never handed out: travel to it fails, and on the colony map the raider then idled.
	route.leg = far_leg
	TEST_ASSERT(!raid.advance_waypoint(raider, WEAKREF(raider)), "A leg out of path range was handed to a raider.")
	TEST_ASSERT_NULL(raider.ai_controller.blackboard[BB_TRAVEL_DESTINATION], "A raider kept a travel destination it could never path to.")

/// A retreat has to hand out its later legs, or it stops at the first waypoint and the raid never ends.
/datum/unit_test/rimstation_raid_retreat_keeps_walking

/datum/unit_test/rimstation_raid_retreat_keeps_walking/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	for(var/next_state in list(COLONY_RAID_WARNING, COLONY_RAID_ASSEMBLING, COLONY_RAID_ARRIVING, COLONY_RAID_ASSAULTING, COLONY_RAID_RETREATING))
		raid.set_state(next_state)

	var/turf/here = run_loc_floor_bottom_left
	var/turf/exit = run_loc_floor_top_right
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/raider = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, here)
	raider.ai_controller.force_ai_off()
	raid.roster += WEAKREF(raider)
	TEST_ASSERT_NOTNULL(raid.navigator.get_map_now(exit), "No route map could be built toward the exit.")
	// The raider stands on its first waypoint, which is where a retreat used to stop for good.
	raid.attacker_routes = list()
	raid.attacker_routes[WEAKREF(raider)] = new /datum/colony_raid_route(exit, here)

	raid.process(1)
	TEST_ASSERT_EQUAL(raid.state, COLONY_RAID_RETREATING, "A retreat with a survivor still walking ended early.")
	TEST_ASSERT_EQUAL(raider.ai_controller.blackboard[BB_TRAVEL_DESTINATION], exit, "A retreating raider was never handed its next leg.")

/// One stuck raider must not hold a raid open, because a running raid blocks every later raid and caravan.
/datum/unit_test/rimstation_raid_time_limits

/datum/unit_test/rimstation_raid_time_limits/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	for(var/next_state in list(COLONY_RAID_WARNING, COLONY_RAID_ASSEMBLING, COLONY_RAID_ARRIVING, COLONY_RAID_ASSAULTING))
		raid.set_state(next_state)
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/raider = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, run_loc_floor_bottom_left)
	raider.ai_controller.force_ai_off()
	raid.roster += WEAKREF(raider)

	raid.process(1)
	TEST_ASSERT_EQUAL(raid.state, COLONY_RAID_ASSAULTING, "A fresh assault was called off before its time limit.")

	raid.state_changed_at = world.time - COLONY_RAID_ASSAULT_TIME_LIMIT
	raid.process(1)
	TEST_ASSERT_EQUAL(raid.state, COLONY_RAID_RETREATING, "An assault past its time limit was never called off.")

	raid.state_changed_at = world.time - COLONY_RAID_RETREAT_TIME_LIMIT
	raid.process(1)
	TEST_ASSERT_EQUAL(raid.state, COLONY_RAID_RESOLVED, "A retreat past its time limit kept the raid open.")

/// A raid arrives from the one direction it announces, and leaves the same way.
/datum/unit_test/rimstation_raid_single_entry_edge

/datum/unit_test/rimstation_raid_single_entry_edge/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/z = run_loc_floor_bottom_left.z
	var/turf/west_a = locate(2, 100, z)
	var/turf/west_b = locate(3, 140, z)
	var/turf/east = locate(world.maxx - 1, 100, z)
	var/turf/north = locate(100, world.maxy - 1, z)
	TEST_ASSERT_EQUAL(raid.get_edge_direction(west_a), WEST, "A turf beside the west edge was not placed on it.")
	TEST_ASSERT_EQUAL(raid.get_edge_direction(east), EAST, "A turf beside the east edge was not placed on it.")
	TEST_ASSERT_EQUAL(raid.get_edge_direction(north), NORTH, "A turf beside the north edge was not placed on it.")

	// The edge is random, so ask often enough to see more than one of them.
	for(var/attempt in 1 to 12)
		var/list/turf/picked = raid.pick_entry_edge(list(west_a, east, west_b, north))
		TEST_ASSERT(length(picked), "A raid with arrival points on three edges was given none.")
		var/edge = raid.get_edge_direction(picked[1])
		for(var/turf/arrival as anything in picked)
			TEST_ASSERT_EQUAL(raid.get_edge_direction(arrival), edge, "A raid was given arrival points on more than one map edge.")
		if(edge == WEST)
			TEST_ASSERT_EQUAL(length(picked), 2, "A raid arriving from the west lost one of that edge's arrival points.")
