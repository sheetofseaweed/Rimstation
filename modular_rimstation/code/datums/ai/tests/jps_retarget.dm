/**
 * A JPS walker given a new travel target mid-walk has to walk to the new one.
 * The JPS mover used to repath its running loop toward the first target, so the mob never changed course.
 */
/datum/unit_test/jps_retarget_mid_walk

/datum/unit_test/jps_retarget_mid_walk/Run()
	var/turf/first_target = locate(run_loc_floor_top_right.x, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	var/turf/second_target = locate(run_loc_floor_bottom_left.x, run_loc_floor_top_right.y, run_loc_floor_bottom_left.z)
	var/mob/living/basic/mouse/jps_walker/walker = allocate(/mob/living/basic/mouse/jps_walker, run_loc_floor_bottom_left)

	walker.ai_controller.set_blackboard_key(BB_TRAVEL_DESTINATION, first_target)
	sleep(1 SECONDS)
	var/datum/move_loop/has_target/jps/loop = GLOB.move_manager.processing_on(walker, SSai_movement)
	TEST_ASSERT(istype(loop) && loop.target == first_target, "The walker had no JPS loop toward its first target after 1 second, so nothing was retargeted.")

	walker.ai_controller.set_blackboard_key(BB_TRAVEL_DESTINATION, second_target)
	var/closest = get_dist(walker, second_target)
	var/give_up_at = world.time + 20 SECONDS
	while(closest > 1 && world.time < give_up_at)
		sleep(0.5 SECONDS)
		closest = min(closest, get_dist(walker, second_target))
	TEST_ASSERT(closest <= 1, "A walker given a new target mid-walk came no closer than [closest] tiles to it, so it kept walking to the old one.")

/// Never gives up, so a walker stuck on its old target cannot recover by failing and restarting toward the new one.
/datum/ai_movement/jps/never_gives_up
	max_pathing_attempts = INFINITY

/// Walks to BB_TRAVEL_DESTINATION and keeps the move running when the key changes, as raid travel does.
/datum/ai_controller/basic_controller/jps_walker
	ai_movement = /datum/ai_movement/jps/never_gives_up
	ai_traits = DEFAULT_AI_FLAGS | RUN_WHILE_UNWATCHED
	behavior_tree_json = null
	behavior_nodes = list(
		BT_DESC_TYPE = /datum/bt_node/decorator/bb_key_set,
		"observer_abort" = BT_ABORT_LOWER_PRIORITY,
		"key" = BB_TRAVEL_DESTINATION,
		BT_DESC_CHILDREN = list(list(
			BT_DESC_TYPE = /datum/bt_node/ai_behavior/move_to_target,
			"target_key" = BB_TRAVEL_DESTINATION,
			"required_dist" = 1,
			"finish_on_arrival" = FALSE,
		)),
	)

/// Slow enough to still be mid-walk across the test room after 1 second.
/mob/living/basic/mouse/jps_walker
	gold_core_spawnable = NO_SPAWN
	contributes_to_ratcap = FALSE
	speed = 5
	ai_controller = /datum/ai_controller/basic_controller/jps_walker
