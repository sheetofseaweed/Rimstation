/**
 * Route planning, on ground the test controls completely.
 *
 * Generated regions are deliberately not used for the arithmetic here. A route test that ran over random
 * terrain would be asserting whatever that seed happened to produce, and would go green for the wrong reason
 * the moment the generator changed. So each of these flattens the region first and then builds the exact
 * obstacle it is about.
 */
/datum/unit_test/rimstation_overworld_route
	abstract_type = /datum/unit_test/rimstation_overworld_route

/// A region with every cell easy going and nothing living on it, ready to have obstacles put back in.
/datum/unit_test/rimstation_overworld_route/proc/flat_region(extent = OVERWORLD_EXTENT_COMPACT)
	RETURN_TYPE(/datum/overworld_region)
	var/datum/planet_definition/planet = new("overworld-route-seed", "overworld-route-planet")
	allocated += planet

	var/datum/overworld_region/region = new(planet, list(
		"extent" = extent,
		"roughness" = OVERWORLD_ROUGHNESS_VARIED,
		"abundance" = OVERWORLD_ABUNDANCE_NORMAL,
	))
	allocated += region

	for(var/cell_id in region.cells)
		var/datum/overworld_cell/cell = region.cells[cell_id]
		cell.topology = OVERWORLD_TOPOLOGY_EASY
		cell.danger = 0
	return region

/// Every cell in the region, as the "everywhere has been seen" set the planner takes.
/datum/unit_test/rimstation_overworld_route/proc/all_cells(datum/overworld_region/region)
	RETURN_TYPE(/list)
	var/list/everywhere = list()
	for(var/cell_id in region.cells)
		everywhere[cell_id] = TRUE
	return everywhere


/**
 * A route is a real walk: adjacent steps, no repeats, and the time it claims is the time it costs.
 */
/datum/unit_test/rimstation_overworld_route/walks_real_ground

/datum/unit_test/rimstation_overworld_route/walks_real_ground/Run()
	var/datum/overworld_region/region = flat_region()

	var/list/route = region.plan_route("0,0", "3,0", OVERWORLD_ROUTE_FASTEST)
	TEST_ASSERT(length(route), "No route was found across open ground.")
	TEST_ASSERT_EQUAL(route[1], "0,0", "A route did not begin where the party is standing.")
	TEST_ASSERT_EQUAL(route[length(route)], "3,0", "A route did not end at its destination.")

	// Three cells apart on open ground is three steps. Anything longer means the planner wandered.
	TEST_ASSERT_EQUAL(length(route), 4, "The shortest route across open ground was not the direct one.")
	TEST_ASSERT(region.is_valid_route(route), "The planner produced a route its own validator rejects.")

	// Entered cells only: the party is already standing on the first one and does not pay to arrive there.
	TEST_ASSERT_EQUAL(region.route_travel_seconds(route), 3 * OVERWORLD_BASE_TRAVERSAL_SECONDS, "An open-ground route did not cost one easy crossing per step.")
	TEST_ASSERT_EQUAL(region.route_danger(route), 0, "An empty region reported danger on the road.")

	// Asking twice must answer the same, or the two offers a player compares mean nothing.
	var/list/again = region.plan_route("0,0", "3,0", OVERWORLD_ROUTE_FASTEST)
	TEST_ASSERT_EQUAL(json_encode(route), json_encode(again), "The same question produced two different routes.")

	// Standing where you are going is a route of one cell that costs nothing.
	var/list/nowhere = region.plan_route("0,0", "0,0", OVERWORLD_ROUTE_FASTEST)
	TEST_ASSERT_EQUAL(length(nowhere), 1, "Routing to where the party already stands did not produce a single cell.")
	TEST_ASSERT_EQUAL(region.route_travel_seconds(nowhere), 0, "Standing still cost travel time.")


/**
 * Difficult ground costs more, and danger costs the safer route exactly what it is priced at.
 *
 * The per-pip rate is the entire difference between the two offers, so it is asserted directly rather than
 * inferred from which way a route happened to bend.
 */
/datum/unit_test/rimstation_overworld_route/prices_ground_and_danger

/datum/unit_test/rimstation_overworld_route/prices_ground_and_danger/Run()
	var/datum/overworld_region/region = flat_region()
	var/datum/overworld_cell/cell = region.get_cell(1, 0)
	TEST_ASSERT_NOTNULL(cell, "The test could not find the cell it meant to work on.")

	// Easy ground is the base rate, and the two route kinds agree while nothing lives there.
	TEST_ASSERT_EQUAL(region.entry_cost(cell, OVERWORLD_ROUTE_FASTEST), OVERWORLD_BASE_TRAVERSAL_SECONDS, "Easy ground did not cost the base traversal time.")
	TEST_ASSERT_EQUAL(region.entry_cost(cell, OVERWORLD_ROUTE_SAFER), OVERWORLD_BASE_TRAVERSAL_SECONDS, "Safe empty ground cost the safer route extra.")

	// Rough ground costs both kinds the same multiple, because it is slow rather than hostile.
	cell.topology = OVERWORLD_TOPOLOGY_DIFFICULT
	TEST_ASSERT_EQUAL(region.entry_cost(cell, OVERWORLD_ROUTE_FASTEST), OVERWORLD_BASE_TRAVERSAL_SECONDS * 2, "Difficult ground did not cost double.")

	// Danger is free to the fastest route and priced to the safer one, at the published rate per pip.
	cell.topology = OVERWORLD_TOPOLOGY_EASY
	cell.danger = 2
	TEST_ASSERT_EQUAL(region.entry_cost(cell, OVERWORLD_ROUTE_FASTEST), OVERWORLD_BASE_TRAVERSAL_SECONDS, "Danger slowed down the fastest route, which is supposed to ignore it.")
	var/expected_safer_cost = OVERWORLD_BASE_TRAVERSAL_SECONDS + (2 * OVERWORLD_DANGER_TIME_PENALTY)
	TEST_ASSERT_EQUAL(region.entry_cost(cell, OVERWORLD_ROUTE_SAFER), expected_safer_cost, "The safer route did not price danger at the published rate per pip.")


/**
 * The safer route walks around what the fastest route walks through.
 *
 * Asserted as a property rather than as a specific set of cells: what matters is that one offer trades time
 * for a quieter road, not that it bends in a particular direction.
 */
/datum/unit_test/rimstation_overworld_route/trades_time_for_safety

/datum/unit_test/rimstation_overworld_route/trades_time_for_safety/Run()
	var/datum/overworld_region/region = flat_region(OVERWORLD_EXTENT_STANDARD)

	// One hostile cell, sitting on the only direct line there is.
	//
	// The destination lies straight along an axis, so the shortest walk is unique and four steps long. Stepping
	// around the bad cell costs six rather than five, because a hex path's length always shares parity with the
	// distance it covers - so the detour is a fixed ninety seconds, and the danger has to be priced above that
	// before the safer route is willing to pay it. Four pips at thirty seconds each is a hundred and twenty.
	var/datum/overworld_cell/dangerous = region.get_cell(2, 0)
	TEST_ASSERT_NOTNULL(dangerous, "The test could not find the cell it meant to make dangerous.")
	dangerous.danger = 4

	var/list/fastest = region.plan_route("0,0", "4,0", OVERWORLD_ROUTE_FASTEST)
	var/list/safer = region.plan_route("0,0", "4,0", OVERWORLD_ROUTE_SAFER)
	TEST_ASSERT(length(fastest), "No fast route was found.")
	TEST_ASSERT(length(safer), "No safe route was found.")
	TEST_ASSERT(region.is_valid_route(safer), "The safer route is not a walk the validator accepts.")

	TEST_ASSERT_EQUAL(length(fastest), 5, "The fastest route did not take the direct line.")
	TEST_ASSERT(dangerous.cell_id() in fastest, "The fastest route avoided the dangerous cell, which it is supposed to ignore.")

	TEST_ASSERT(!(dangerous.cell_id() in safer), "The safer route walked through the one cell it was meant to avoid.")
	TEST_ASSERT_EQUAL(region.route_danger(safer), 0, "The safer route walked into danger when a clear way around existed.")
	TEST_ASSERT(region.route_danger(safer) < region.route_danger(fastest), "The safer route walked into as much danger as the fast one.")
	TEST_ASSERT(region.route_travel_seconds(safer) > region.route_travel_seconds(fastest), "The safer route was not slower, so it cost nothing to take.")

	// Below the price of the detour, the safer route is honest enough to take the short way anyway.
	dangerous.danger = 1
	var/list/still_direct = region.plan_route("0,0", "4,0", OVERWORLD_ROUTE_SAFER)
	TEST_ASSERT_EQUAL(length(still_direct), 5, "The safer route paid for a detour that cost more than the danger it avoided.")


/// Ground nobody can cross, and country nobody has seen, both stop a route dead.
/datum/unit_test/rimstation_overworld_route/refuses_what_cannot_be_walked

/datum/unit_test/rimstation_overworld_route/refuses_what_cannot_be_walked/Run()
	var/datum/overworld_region/region = flat_region()

	// Wall the destination in completely. A region can genuinely do this, and the map has to be able to say so
	// rather than offering a route that walks through rock.
	var/list/directions = OVERWORLD_AXIAL_DIRECTIONS
	for(var/list/step as anything in directions)
		var/datum/overworld_cell/wall = region.get_cell(3 + step[1], 0 + step[2])
		if(wall)
			wall.topology = OVERWORLD_TOPOLOGY_IMPASSABLE

	TEST_ASSERT_EQUAL(length(region.plan_route("0,0", "3,0", OVERWORLD_ROUTE_FASTEST)), 0, "A route was found into a cell that is walled off.")

	// An impassable destination is refused even before the walk is attempted.
	var/datum/overworld_cell/blocked = region.get_cell(1, 0)
	blocked.topology = OVERWORLD_TOPOLOGY_IMPASSABLE
	TEST_ASSERT_EQUAL(length(region.plan_route("0,0", "1,0", OVERWORLD_ROUTE_FASTEST)), 0, "A route was planned into impassable ground.")

	// A cell that does not exist is not somewhere anybody can be sent.
	TEST_ASSERT_EQUAL(length(region.plan_route("0,0", "99,99", OVERWORLD_ROUTE_FASTEST)), 0, "A route was planned to a cell outside the region.")

	// And the planner will not route through country the colony has not seen.
	var/datum/overworld_region/open_region = flat_region()
	var/list/only_home = list("0,0" = TRUE)
	TEST_ASSERT_EQUAL(length(open_region.plan_route("0,0", "2,0", OVERWORLD_ROUTE_FASTEST, only_within = only_home)), 0, "A route was planned through undiscovered country.")


/**
 * A route arriving from a client is not believed.
 *
 * Every one of these is something a forged message could claim, and each would buy something: a teleport, a
 * walk through rock, or a payout for crossings that were never made.
 */
/datum/unit_test/rimstation_overworld_route/rejects_forged_routes

/datum/unit_test/rimstation_overworld_route/rejects_forged_routes/Run()
	var/datum/overworld_region/region = flat_region()

	TEST_ASSERT(!region.is_valid_route(list()), "An empty route was accepted.")
	TEST_ASSERT(!region.is_valid_route(list("0,0", "5,0")), "A route that jumps between distant cells was accepted.")
	TEST_ASSERT(!region.is_valid_route(list("0,0", "99,99")), "A route through a cell that does not exist was accepted.")
	TEST_ASSERT(!region.is_valid_route(list("0,0", "1,0", "0,0")), "A route that visits the same cell twice was accepted.")

	var/datum/overworld_cell/blocked = region.get_cell(1, 0)
	blocked.topology = OVERWORLD_TOPOLOGY_IMPASSABLE
	TEST_ASSERT(!region.is_valid_route(list("0,0", "1,0")), "A route through impassable ground was accepted.")

	// Length is bounded against the region, so a route cannot be padded out into a journey of a thousand legs.
	var/list/overlong = list()
	for(var/index in 1 to (region.radius * 4) + 8)
		overlong += "0,0"
	TEST_ASSERT(!region.is_valid_route(overlong), "A route longer than the region could possibly need was accepted.")

	// Restricted to what has been seen, a real walk through unseen ground is still refused.
	var/list/only_home = list("0,0" = TRUE)
	TEST_ASSERT(!region.is_valid_route(list("0,0", "0,1"), only_within = only_home), "A route through undiscovered country passed validation.")
