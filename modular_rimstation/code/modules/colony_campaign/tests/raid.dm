/**
 * A raid is a budget, not a difficulty number.
 *
 * The colony has to be able to lose a fight it was outmatched in and survive one it prepared for, which only
 * works if the threat that arrives is bounded and knowable. These assertions cover the boundary rather than
 * the flavour: a composition that quietly overspends is a raid nobody could have prepared for.
 */
/datum/unit_test/rimstation_raid_budget

/datum/unit_test/rimstation_raid_budget/Run()
	var/datum/colony_raid/raid = new
	allocated += raid

	var/list/datum/colony_raid_unit/roster = list(
		new /datum/colony_raid_unit(/mob/living/basic/rabbit, 10, 0, 5, "grunt", 5),
		new /datum/colony_raid_unit(/mob/living/basic/chicken, 25, 0, 3, "heavy", 2),
	)
	for(var/datum/colony_raid_unit/unit as anything in roster)
		allocated += unit

	// Run repeatedly: selection is weighted, so a single pass could miss an overspend.
	for(var/attempt in 1 to 40)
		var/list/composition = raid.build_composition(100, roster, 20)
		var/cost = raid.composition_cost(composition, roster)
		TEST_ASSERT(cost <= 100, "A raid composition cost [cost] against a budget of 100 on attempt [attempt].")
		var/head_count = 0
		for(var/mob_type in composition)
			head_count += composition[mob_type]
		TEST_ASSERT(head_count <= 20, "A raid composition fielded [head_count] units against a live cap of 20.")

	// The live cap has to bind even when the budget is effectively unlimited.
	var/list/capped = raid.build_composition(100000, roster, 4)
	var/capped_heads = 0
	for(var/mob_type in capped)
		capped_heads += capped[mob_type]
	TEST_ASSERT_EQUAL(capped_heads, 4, "A rich raid ignored its live cap and fielded [capped_heads] units.")

	// Per-unit maximums cap composition even with budget and headroom to spare.
	for(var/mob_type in capped)
		var/datum/colony_raid_unit/matching
		for(var/datum/colony_raid_unit/unit as anything in roster)
			if(unit.mob_type == mob_type)
				matching = unit
				break
		TEST_ASSERT(capped[mob_type] <= matching.maximum_count, "A raid fielded more [mob_type] than its maximum allows.")

	// Leftover points that cannot buy the cheapest unit must end selection rather than loop.
	var/list/starved = raid.build_composition(9, roster, 20)
	TEST_ASSERT(!length(starved), "A raid that could not afford its cheapest unit still fielded something.")

	// Minimums are honoured when affordable, so a raid never arrives as an empty threat.
	var/datum/colony_raid_unit/mandatory = new /datum/colony_raid_unit(/mob/living/basic/deer, 10, 2, 4, "leader", 1)
	allocated += mandatory
	var/list/with_minimum = raid.build_composition(100, list(mandatory), 20)
	TEST_ASSERT(with_minimum[/mob/living/basic/deer] >= 2, "A raid did not field the minimum count of a required unit.")


/**
 * The lifecycle exists so a raid cannot skip its own telegraph.
 *
 * Warning then assembling then arriving is the preparation window the colony is promised. A raid that could
 * jump straight to assaulting would be exactly the unfair surprise this phase is meant to rule out.
 */
/datum/unit_test/rimstation_raid_states

/datum/unit_test/rimstation_raid_states/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	TEST_ASSERT_EQUAL(raid.state, COLONY_RAID_QUEUED, "A new raid did not start queued.")

	// The legal forward path, one step at a time.
	var/list/forward_path = list(
		COLONY_RAID_WARNING,
		COLONY_RAID_ASSEMBLING,
		COLONY_RAID_ARRIVING,
		COLONY_RAID_ASSAULTING,
		COLONY_RAID_RETREATING,
		COLONY_RAID_RESOLVED,
	)
	for(var/next_state in forward_path)
		TEST_ASSERT(raid.set_state(next_state), "The raid refused the legal transition to [next_state].")
		TEST_ASSERT_EQUAL(raid.state, next_state, "The raid did not record its transition to [next_state].")

	// Resolved is terminal.
	TEST_ASSERT(!raid.set_state(COLONY_RAID_ASSAULTING), "A resolved raid allowed itself to be restarted.")

	// Skipping the telegraph is the transition that matters most.
	var/datum/colony_raid/skipper = new
	allocated += skipper
	TEST_ASSERT(!skipper.set_state(COLONY_RAID_ASSAULTING), "A queued raid jumped straight to assaulting, skipping its warning.")
	TEST_ASSERT_EQUAL(skipper.state, COLONY_RAID_QUEUED, "A rejected transition still mutated the raid state.")

	// Going backwards is not a thing a raid does.
	var/datum/colony_raid/backslider = new
	allocated += backslider
	backslider.set_state(COLONY_RAID_WARNING)
	backslider.set_state(COLONY_RAID_ASSEMBLING)
	TEST_ASSERT(!backslider.set_state(COLONY_RAID_WARNING), "A raid transitioned backwards to an earlier state.")

	// Cancellation from any state must still be able to reach resolved, or a cancelled raid leaks.
	var/datum/colony_raid/cancelled = new
	allocated += cancelled
	TEST_ASSERT(cancelled.set_state(COLONY_RAID_RESOLVED), "A queued raid could not be cancelled to resolved.")

	// Nonsense states are refused rather than stored.
	var/datum/colony_raid/nonsense = new
	allocated += nonsense
	TEST_ASSERT(!nonsense.set_state("rampaging"), "The raid accepted a state outside its own vocabulary.")


/// A raid with nowhere valid to arrive must cancel, never fall back to spawning inside the settlement.
/datum/unit_test/rimstation_raid_insertion

/datum/unit_test/rimstation_raid_insertion/Run()
	var/datum/colony_raid/raid = new
	allocated += raid

	// The unit test map has no colony landmarks at all, which is exactly the "nowhere valid" case.
	var/list/turf/found = raid.find_insertion_turfs()
	TEST_ASSERT(!length(found), "The raid invented insertion points on a map with no colony landmarks.")

	TEST_ASSERT(!raid.begin_warning(), "A raid with no validated insertion points started anyway.")
	TEST_ASSERT_EQUAL(raid.state, COLONY_RAID_RESOLVED, "A raid that could not deploy did not resolve itself.")
	TEST_ASSERT_EQUAL(raid.outcome, COLONY_RAID_OUTCOME_CANCELLED, "A raid that could not deploy did not record itself as cancelled.")


/**
 * Reachability is the check that stops attackers spawning inside sealed rock.
 *
 * A landmark cannot promise this: the surface is generated after the map is authored, so generation can and
 * does seal insertion points inside closed pockets. Attackers spawned there just stand still.
 */
/datum/unit_test/rimstation_raid_reachability

/datum/unit_test/rimstation_raid_reachability/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/datum/colony_raid_navigator/navigator = raid.navigator

	// Nothing here may replace a turf: run_loc_floor_bottom_left is shared with every later test, and turfs
	// are not restored on teardown the way allocated objects are. Swapping one in poisons the whole suite.
	var/turf/origin = run_loc_floor_bottom_left
	TEST_ASSERT_NOTNULL(navigator.get_map_now(origin), "No route map could be built from an open floor turf.")

	// Neighbours of an open floor are reachable, and a raider next to its goal is sent straight to it.
	var/turf/open/neighbour = get_step(origin, EAST)
	TEST_ASSERT(navigator.is_reachable(neighbour, origin), "An adjacent open floor turf was not considered reachable.")
	TEST_ASSERT_EQUAL(navigator.next_leg(neighbour, origin), origin, "A raider next to its goal was not sent straight to it.")

	// A dense object makes a turf unwalkable, which is the same rejection generated rock relies on.
	var/turf/blocked_turf = get_step(origin, NORTH)
	TEST_ASSERT(navigator.is_reachable(blocked_turf, origin), "The turf this test blocks was never reachable, so this proves nothing.")
	var/obj/structure/blocker = allocate(/obj/structure/girder, blocked_turf)
	TEST_ASSERT(blocker.density, "The structure used to block a turf was not dense, so this proves nothing.")

	// The old map predates the girder. A fresh one must route around it rather than through it.
	TEST_ASSERT(navigator.request(origin), "A fresh route map could not be requested.")
	navigator.get_map_now(origin)
	TEST_ASSERT(!navigator.is_reachable(blocked_turf, origin), "A route map walked through a turf blocked by a dense structure.")


/**
 * Waypoints have to be short enough for a basic mob to actually path to.
 *
 * This is the constraint that made two earlier attempts fail: basic-mob JPS refuses any path longer than
 * AI_MAX_PATH_LENGTH, so an attacker handed a destination 110 tiles away just stands still. Nothing about
 * "the objective was assigned" catches that, which is why the spacing itself is asserted.
 */
/datum/unit_test/rimstation_raid_waypoint_range

/datum/unit_test/rimstation_raid_waypoint_range/Run()
	TEST_ASSERT(COLONY_RAID_WAYPOINT_SPACING < AI_MAX_PATH_LENGTH, "Raid waypoints are spaced [COLONY_RAID_WAYPOINT_SPACING] tiles apart, beyond the [AI_MAX_PATH_LENGTH] tile limit basic mobs will path, so attackers would never move.")
	TEST_ASSERT(COLONY_RAID_WAYPOINT_ARRIVAL_DISTANCE < COLONY_RAID_WAYPOINT_SPACING, "The waypoint arrival radius is not smaller than the spacing, so attackers would skip legs of their route.")

	var/datum/colony_raid/raid = new
	allocated += raid
	var/obj/structure/colony_core/core = allocate(/obj/structure/colony_core)
	raid.objective_ref = WEAKREF(core)

	// With no route map there is nothing to read, so attackers must still be pointed at something.
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/attacker = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider)
	TEST_ASSERT(raid.assign_objective(attacker), "An attacker with no route map was left without a destination.")
	TEST_ASSERT_NOTNULL(attacker.ai_controller.blackboard[BB_TRAVEL_DESTINATION], "An attacker was given no travel destination at all.")

	// A straight route, built by hand so the leg rule is checked exactly: one spacing ahead, then the goal itself.
	var/z = run_loc_floor_bottom_left.z
	var/turf/goal = locate(100, 100, z)
	var/datum/path_map/line = new
	line.start = goal
	line.next_closest[goal] = FLOW_PATH_END
	for(var/x in 101 to 140)
		line.next_closest[locate(x, 100, z)] = locate(x - 1, 100, z)
	LAZYSET(raid.navigator.maps, goal, line)

	var/turf/far = locate(140, 100, z)
	var/turf/leg = raid.navigator.next_leg(far, goal)
	TEST_ASSERT_EQUAL(get_dist(far, leg), COLONY_RAID_WAYPOINT_SPACING, "A leg read from a route map was not one waypoint spacing ahead.")
	TEST_ASSERT_EQUAL(raid.navigator.next_leg(locate(110, 100, z), goal), goal, "A raider within one leg of its goal was not sent straight to it.")
	TEST_ASSERT_NULL(raid.navigator.next_leg(locate(140, 101, z), goal), "A raider with no route on the map was given a leg anyway.")


/**
 * Attackers have to be told where to go.
 *
 * The inherited trooper AI fights well but has no reason to walk anywhere, so a raid that only spawns mobs
 * produces attackers milling around the map edge. That shipped once; this is the assertion that catches it.
 */
/datum/unit_test/rimstation_raid_objective_routing

/datum/unit_test/rimstation_raid_objective_routing/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/obj/structure/colony_core/core = allocate(/obj/structure/colony_core)
	raid.objective_ref = WEAKREF(core)

	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/attacker = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider)
	TEST_ASSERT_NOTNULL(attacker.ai_controller, "A raider spawned with no AI controller, so it could never be given an objective.")

	TEST_ASSERT(raid.assign_objective(attacker), "The raid failed to assign its objective to an attacker.")
	// Destinations are turfs, because waypoints along the approach route are turfs.
	TEST_ASSERT_EQUAL(attacker.ai_controller.blackboard[BB_TRAVEL_DESTINATION], get_turf(core), "The attacker was not pointed at the colony core.")

	// The behaviour tree must actually consume that key, or setting it achieves nothing. Walked rather than
	// read off the controller, because planning is a tree of nodes now and not a flat list of subtrees.
	var/found_travel_move = FALSE
	var/list/to_visit = attacker.ai_controller.behavior_nodes?.Copy() || list()
	var/index = 1
	while(index <= length(to_visit))
		var/datum/bt_node/node = to_visit[index++]
		if(istype(node, /datum/bt_node/ai_behavior/move_to_target))
			var/datum/bt_node/ai_behavior/move_to_target/mover = node
			if(mover.target_key == BB_TRAVEL_DESTINATION)
				found_travel_move = TRUE
				break
		// A leaf returns null here, and `list += null` appends a null entry rather than nothing.
		var/list/children = node.get_children()
		if(children)
			to_visit += children

	TEST_ASSERT(found_travel_move, "The raider AI never moves towards BB_TRAVEL_DESTINATION, so it would ignore its objective.")

	// Retreat has to redirect them away from the objective rather than leaving them pressing it.
	raid.set_state(COLONY_RAID_WARNING)
	raid.set_state(COLONY_RAID_ASSEMBLING)
	raid.set_state(COLONY_RAID_ARRIVING)
	raid.set_state(COLONY_RAID_ASSAULTING)
	raid.roster += WEAKREF(attacker)
	raid.order_retreat()
	TEST_ASSERT_EQUAL(raid.state, COLONY_RAID_RETREATING, "The raid did not enter its retreating state.")
	TEST_ASSERT_NOTEQUAL(attacker.ai_controller.blackboard[BB_TRAVEL_DESTINATION], get_turf(core), "A retreating attacker was still heading for the colony core.")


/// Resolution has to clean up after itself, or a finished raid keeps ticking.
/datum/unit_test/rimstation_raid_resolution

/datum/unit_test/rimstation_raid_resolution/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	raid.set_state(COLONY_RAID_WARNING)
	raid.assault_timer_id = addtimer(CALLBACK(raid, TYPE_PROC_REF(/datum/colony_raid, begin_assault)), 10 MINUTES, TIMER_STOPPABLE)
	var/lingering_timer = raid.assault_timer_id

	raid.resolve_raid(COLONY_RAID_OUTCOME_REPELLED, "the attackers were killed")
	TEST_ASSERT_EQUAL(raid.state, COLONY_RAID_RESOLVED, "Resolving the raid did not move it to resolved.")
	TEST_ASSERT_EQUAL(raid.outcome, COLONY_RAID_OUTCOME_REPELLED, "Resolving the raid did not record its outcome.")
	TEST_ASSERT(!timeleft(lingering_timer), "A resolved raid left its assault timer running.")

	// First outcome wins, so a late cleanup cannot rewrite how the fight actually went.
	raid.resolve_raid(COLONY_RAID_OUTCOME_CANCELLED, "cleanup")
	TEST_ASSERT_EQUAL(raid.outcome, COLONY_RAID_OUTCOME_REPELLED, "A second resolution overwrote the recorded raid outcome.")
