/// A seed that sealed the real landing clearing off from every map edge before raid passes existed.
#define RAID_LANES_SEALED_SEED "57a4a5340590507299ce8b9a3f6f2fc776e7b536a1e733a6326366a2fefea0e2"

/// TRUE when `edge` has any raid ground at all, reachable or not.
/proc/rimstation_edge_has_raid_ground(datum/rimstation_colony_generation_context/context, edge)
	for(var/index in 1 to length(context.terrain_plan))
		if(context.is_raid_edge_candidate(index, edge))
			return TRUE
	return FALSE

/**
 * A landing walled in by rock still gets a route to every edge that has raid ground.
 * About one seed in twenty-four did this, and every raid on such a map cancelled.
 */
/datum/unit_test/rimstation_planet_raid_passes

/datum/unit_test/rimstation_planet_raid_passes/Run()
	var/datum/planet_definition/planet = new("rimstation-raid-pass-test")
	allocated += planet
	var/datum/rimstation_colony_generation_context/context = new(planet, 1, 1, 96, 96, 2)
	allocated += context
	context.set_landing_bounds(43, 43, 54, 54)
	TEST_ASSERT(context.build_plan(), "The landscape plan could not be built.")

	// A full ring of rock just beyond the landing's protected radius, the shape the sealed seeds had.
	for(var/index in 1 to length(context.terrain_plan))
		var/ring = max(abs(context.index_x(index) - 48), abs(context.index_y(index) - 48))
		if(ring >= 14 && ring <= 16)
			context.terrain_plan[index] = RIMSTATION_TERRAIN_MOUNTAIN
	var/list/sealed = context.build_landing_reachability()
	var/list/edges_with_ground = list()
	for(var/edge in GLOB.cardinals)
		TEST_ASSERT(!context.is_edge_reachable(edge, sealed), "The test ring left the [dir2text(edge)] edge reachable, so this proves nothing.")
		if(rimstation_edge_has_raid_ground(context, edge))
			edges_with_ground += edge
	TEST_ASSERT(length(edges_with_ground), "No edge of the test plan has raid ground, so this proves nothing.")

	context.open_raid_passes()
	var/list/opened = context.build_landing_reachability()
	for(var/edge in edges_with_ground)
		TEST_ASSERT(context.is_edge_reachable(edge, opened), "No pass was cut to the [dir2text(edge)] edge, so a raid could never start there.")
	TEST_ASSERT(context.raid_pass_count >= 1 && context.raid_pass_count <= 4, "[context.raid_pass_count] passes were cut through a ring that needed between one and four.")
	for(var/index in 1 to length(context.terrain_plan))
		if(opened[index])
			TEST_ASSERT_NOTEQUAL(context.terrain_plan[index], RIMSTATION_TERRAIN_SINKHOLE, "A raid pass was cut across a sinkhole.")

/**
 * Every marker has a lane home across walkable ground, marked for clearing, with nodes along it.
 * The lane is what keeps the route the plan found open once flora is placed on real turfs.
 */
/datum/unit_test/rimstation_planet_raid_lanes

/datum/unit_test/rimstation_planet_raid_lanes/Run()
	var/datum/planet_definition/planet = new("rimstation-raid-lane-test")
	allocated += planet
	var/datum/rimstation_colony_generation_context/context = new(planet, 1, 1, 96, 96, 2)
	allocated += context
	context.set_landing_bounds(43, 43, 54, 54)
	TEST_ASSERT(context.build_plan(), "The landscape plan could not be built.")
	TEST_ASSERT(length(context.raid_insertion_indices), "The test plan produced no raid markers, so this proves nothing.")
	TEST_ASSERT_EQUAL(length(context.raid_lane_nodes), length(context.raid_insertion_indices), "Some raid markers have no lane.")

	var/list/distances = new /list(length(context.terrain_plan))
	context.build_landing_reachability(distances)
	var/anchor_index = context.get_landing_anchor_index()
	TEST_ASSERT_EQUAL(length(context.raid_lane_paths), length(context.raid_insertion_indices), "Some raid markers have no lane path.")
	for(var/lane_number in 1 to length(context.raid_insertion_indices))
		var/list/lane = context.raid_lane_paths[lane_number]
		TEST_ASSERT(length(lane), "Lane [lane_number] is empty.")
		TEST_ASSERT_EQUAL(lane[1], context.raid_insertion_indices[lane_number], "Lane [lane_number] does not start at its marker.")
		for(var/step in 1 to length(lane))
			var/index = lane[step]
			TEST_ASSERT(context.is_plan_walkable(index), "Lane [lane_number] crosses unwalkable terrain at [context.index_x(index)],[context.index_y(index)].")
			TEST_ASSERT(context.raid_lane_mask[index], "Lane [lane_number] has a tile at [context.index_x(index)],[context.index_y(index)] that is not kept clear.")
			// Every step is one nearer the landing, so the lane is a shortest route and cannot loop.
			var/next_index = step < length(lane) ? lane[step + 1] : anchor_index
			TEST_ASSERT_EQUAL(distances[next_index], distances[index] - 1, "Lane [lane_number] steps away from the landing at [context.index_x(index)],[context.index_y(index)].")
		var/list/nodes = context.raid_lane_nodes[lane_number]
		var/expected_nodes = floor(length(lane) / COLONY_RAID_WAYPOINT_SPACING)
		TEST_ASSERT(length(nodes) <= expected_nodes, "Lane [lane_number] has [length(nodes)] nodes along [length(lane)] tiles, more than one per waypoint spacing.")
		for(var/node_index in nodes)
			TEST_ASSERT(node_index in lane, "A node of lane [lane_number] is not on its lane.")

	// The trail follows the lanes over open ground, and leaves fords and tunnels as they are.
	var/trail_tiles = 0
	for(var/index in 1 to length(context.terrain_plan))
		var/turf_type = context.get_lowland_turf_type(context.index_x(index), context.index_y(index))
		var/terrain = context.terrain_plan[index]
		if(turf_type == /turf/open/misc/dirt/planet/rimstation/trail)
			trail_tiles++
			TEST_ASSERT(context.raid_trail_mask[index], "A trail tile at [context.index_x(index)],[context.index_y(index)] is on no lane.")
			continue
		if(!context.raid_trail_mask[index])
			continue
		TEST_ASSERT(terrain != RIMSTATION_TERRAIN_LOWLAND && terrain != RIMSTATION_TERRAIN_RIVER_BANK, "Open ground on a lane at [context.index_x(index)],[context.index_y(index)] did not become trail.")
	TEST_ASSERT(trail_tiles, "The test plan's lanes produced no trail at all.")

/**
 * On the real colony map, every marker and lane node is reachable from the core by a raider's own rules.
 * The plan only promises a route; flora, rocks and the authored landing decide whether real turfs keep it.
 */
/datum/unit_test/rimstation_colony_raid_lanes_walkable
	test_flags = UNIT_TEST_MAP_TEST

/datum/unit_test/rimstation_colony_raid_lanes_walkable/Run()
	// Only the generated colony has raid lanes; on any other map there is nothing to check.
	if(SSmapping.current_map.map_name != "Rimstation Colony")
		return
	var/obj/structure/colony_core/core = get_colony_core()
	TEST_ASSERT_NOTNULL(core, "The colony map has no core to route raids toward.")
	var/turf/core_turf = get_turf(core)
	TEST_ASSERT(length(GLOB.rimstation_raid_insertion_points) >= 2, "The colony map has [length(GLOB.rimstation_raid_insertion_points)] raid marker(s), so raids have almost nowhere to start.")

	var/datum/colony_raid_navigator/navigator = new
	allocated += navigator
	TEST_ASSERT_NOTNULL(navigator.get_map_now(core_turf), "No route map could be built from the colony core.")
	for(var/obj/effect/landmark/rimstation_raid_insertion/marker as anything in GLOB.rimstation_raid_insertion_points)
		TEST_ASSERT(navigator.is_reachable(get_turf(marker), core_turf), "The raid marker at [AREACOORD(marker)] has no walkable route to the core.")
		TEST_ASSERT(marker.lane_id, "The raid marker at [AREACOORD(marker)] belongs to no lane.")
	for(var/obj/effect/landmark/rimstation_raid_lane_node/node as anything in GLOB.rimstation_raid_lane_nodes)
		var/turf/node_turf = get_turf(node)
		for(var/obj/blocker in node_turf)
			TEST_ASSERT(!blocker.density, "Lane node [node.lane_id]:[node.lane_order] at [AREACOORD(node_turf)] is blocked by [blocker].")
		TEST_ASSERT(navigator.is_reachable(node_turf, core_turf), "Lane node [node.lane_id]:[node.lane_order] at [AREACOORD(node_turf)] has no walkable route to the core.")

	// The trail is visible on real turfs, and nothing grows on it.
	var/trail_turfs = 0
	for(var/turf/open/misc/dirt/planet/rimstation/trail/trail in block(locate(1, 1, core_turf.z), locate(world.maxx, world.maxy, core_turf.z)))
		trail_turfs++
		var/obj/structure/flora/growth = locate() in trail
		TEST_ASSERT_NULL(growth, "[growth] grows on the trail at [AREACOORD(trail)].")
	TEST_ASSERT(trail_turfs >= length(GLOB.rimstation_raid_insertion_points), "The colony map has only [trail_turfs] trail tile(s) for [length(GLOB.rimstation_raid_insertion_points)] raid lane(s).")

	// The seed that used to seal the real landing, now with passes cut. Planned only; no turfs change.
	var/datum/planet_definition/sealed_planet = new(RAID_LANES_SEALED_SEED, RIMSTATION_DEVELOPMENT_PLANET_ID)
	allocated += sealed_planet
	var/datum/rimstation_colony_generation_context/context = new(sealed_planet, 1, 1, world.maxx, world.maxy, core_turf.z)
	allocated += context
	context.discover_landing_bounds()
	TEST_ASSERT(context.build_plan(), "The once-sealed seed's landscape plan could not be built.")
	TEST_ASSERT(context.raid_pass_count >= 1, "The once-sealed seed needed no raid pass, so this no longer reproduces the seal.")
	TEST_ASSERT(length(context.raid_insertion_indices) >= 4, "The once-sealed seed still has only [length(context.raid_insertion_indices)] raid marker(s).")

#undef RAID_LANES_SEALED_SEED
