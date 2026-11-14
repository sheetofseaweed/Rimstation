/// Orders given to a party that has already left: a new site, a second stop, or home.
/// Each test drives the order procs the table calls, then `SSoverworld.fire()`.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders
	abstract_type = /datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders

/// A travel campaign with the whole region on the map, so a test can pick any site.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/proc/begin_open_campaign()
	RETURN_TYPE(/datum/overworld_party)
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	SScampaign.overworld.discover_radius(region, OVERWORLD_HOME_CELL, region.radius)
	return party

/// Every site at least `min_edges` crossings from the colony, in the region's own order.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/proc/sites_beyond(datum/overworld_region/region, min_edges = 2)
	RETURN_TYPE(/list)
	var/list/found = list()
	var/list/seen = get_discovered_cell_ids(region)
	for(var/site_id in region.sites)
		var/datum/overworld_site/site = region.sites[site_id]
		if(length(region.plan_route(OVERWORLD_HOME_CELL, "[site.q],[site.r]", OVERWORLD_ROUTE_FASTEST, seen)) > min_edges)
			found += site
	return found

/// Signs a living colonist on, without the locker and muster a real sign-on needs.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/proc/add_traveller(datum/overworld_party/party, ckey = "playerone", name = "Vera Holt")
	RETURN_TYPE(/mob/living/carbon/human)
	var/datum/colonist_record/record = SScampaign.roster.find_or_create(ckey, name, generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	SScampaign.bind_colonist(body, record)
	party.member_ids += record.colonist_id
	return body

/// Fires through due crossings while the party stays in `while_state`. Bounded, so a failure cannot hang.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/proc/walk_while(datum/overworld_party/party, while_state)
	var/guard = 0
	while(party.state == while_state && party.leg_arrives_at && guard < 80)
		guard++
		skip_to_arrival(party)
		SSoverworld.fire()

/// Moves campaign time to this fraction of the way through the crossing in progress.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/proc/walk_part_of_leg(datum/overworld_party/party, fraction)
	var/target_time = party.leg_started_at + ((party.leg_arrives_at - party.leg_started_at) * fraction)
	var/shift = target_time - SScampaign.get_campaign_time()
	if(shift > 0)
		SScampaign.chapter_world_time_origin -= shift


/// A party that changed its mind on the road must still walk all the way home.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/reroute_then_home_ends_at_the_colony

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/reroute_then_home_ends_at_the_colony/Run()
	var/datum/overworld_party/party = begin_open_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/sites = sites_beyond(region, 2)
	TEST_ASSERT(length(sites) >= 2, "The test region has fewer than two sites far enough apart to reroute between.")
	var/datum/overworld_site/first = sites[1]
	var/datum/overworld_site/second = sites[2]

	var/list/route = region.plan_route(OVERWORLD_HOME_CELL, "[first.q],[first.r]", OVERWORLD_ROUTE_FASTEST, get_discovered_cell_ids(region))
	put_on_the_road(party, route, supplies = 200)
	party.destination_site_id = first.site_id()

	// One crossing out, then a change of mind.
	skip_to_arrival(party)
	SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.current_cell, route[2], "The party did not make its first crossing.")
	TEST_ASSERT_NULL(SSoverworld.order_to_site(party, second.site_id()), "A party on the road was refused a new destination.")

	walk_while(party, OVERWORLD_PARTY_OUTBOUND)
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_AT_SITE, "A rerouted party never reached its new site.")
	TEST_ASSERT_EQUAL(party.current_cell, "[second.q],[second.r]", "A rerouted party stopped somewhere other than its new site.")

	TEST_ASSERT_NULL(SSoverworld.order_home(party, "test"), "A party at a site could not be sent home.")
	walk_while(party, OVERWORLD_PARTY_RETURNING)
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_COMPLETE, "A rerouted party never finished its journey.")
	TEST_ASSERT_EQUAL(party.current_cell, OVERWORLD_HOME_CELL, "A party that had rerouted was counted as home while standing at [party.current_cell].")


/// A party on its way home can be sent out again, and then it is going out, not home.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/returning_party_can_go_out_again

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/returning_party_can_go_out_again/Run()
	var/datum/overworld_party/party = begin_open_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/sites = sites_beyond(region, 3)
	TEST_ASSERT(length(sites), "The test region has no site three crossings out.")
	var/datum/overworld_site/target = sites[1]
	var/site_cell = "[target.q],[target.r]"

	var/list/route = region.plan_route(OVERWORLD_HOME_CELL, site_cell, OVERWORLD_ROUTE_FASTEST, get_discovered_cell_ids(region))
	put_on_the_road(party, route, supplies = 200)
	party.destination_site_id = target.site_id()
	walk_while(party, OVERWORLD_PARTY_OUTBOUND)
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_AT_SITE, "The party never reached its site.")

	TEST_ASSERT_NULL(SSoverworld.order_home(party, "test"), "A party at a site could not be sent home.")
	skip_to_arrival(party)
	SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_RETURNING, "A party one crossing into its return is not returning.")
	TEST_ASSERT(party.current_cell != site_cell, "A returning party did not leave the site.")

	// The site is still unworked, so going back to it is a fair order.
	TEST_ASSERT_NULL(SSoverworld.order_to_site(party, target.site_id()), "A returning party was refused a new destination.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_OUTBOUND, "A returning party that was sent out again still thinks it is going home.")

	walk_while(party, OVERWORLD_PARTY_OUTBOUND)
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_AT_SITE, "A party sent out again finished somewhere other than a site.")
	TEST_ASSERT_EQUAL(party.current_cell, site_cell, "A party sent out again stopped at [party.current_cell], not at its site.")


/// Turning back on the first crossing is allowed, and costs only the ground already covered.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/first_crossing_can_be_turned_back

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/first_crossing_can_be_turned_back/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/route = region.plan_route(OVERWORLD_HOME_CELL, overworld_test_target(region, 3), OVERWORLD_ROUTE_FASTEST)
	TEST_ASSERT(length(route) >= 3, "The test could not plan a route long enough to walk.")
	put_on_the_road(party, route, supplies = 50)

	var/crossing = party.leg_arrives_at - party.leg_started_at
	walk_part_of_leg(party, 0.4)
	TEST_ASSERT_NULL(SSoverworld.order_home(party, "test"), "A party on its first crossing could not turn back.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_RETURNING, "A party that turned back is not returning.")

	var/walk_back = party.leg_arrives_at - SScampaign.get_campaign_time()
	TEST_ASSERT(walk_back > crossing * 0.3 && walk_back < crossing * 0.5, "Walking back 40% of a [crossing] crossing was priced at [walk_back].")

	skip_to_arrival(party)
	SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_COMPLETE, "A party that walked back to the colony was not counted home.")


/// Turning back between two cells walks back to the last cell, then on home. It is not a fresh crossing.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/turning_back_keeps_the_ground_covered

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/turning_back_keeps_the_ground_covered/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/route = region.plan_route(OVERWORLD_HOME_CELL, overworld_test_target(region, 4), OVERWORLD_ROUTE_FASTEST)
	TEST_ASSERT(length(route) >= 4, "The test could not plan a route long enough to turn back on.")
	put_on_the_road(party, route, supplies = 80)

	skip_to_arrival(party)
	SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.current_cell, route[2], "The party did not make its first crossing.")

	var/crossing = party.leg_arrives_at - party.leg_started_at
	var/supplies_before = party.supplies
	walk_part_of_leg(party, 0.4)
	TEST_ASSERT_NULL(SSoverworld.order_home(party, "test"), "A party between two cells could not turn back.")

	var/walk_back = party.leg_arrives_at - SScampaign.get_campaign_time()
	TEST_ASSERT(walk_back > crossing * 0.3 && walk_back < crossing * 0.5, "Walking back 40% of a [crossing] crossing was priced at [walk_back].")
	// What the map draws the marker from. Without it the marker jumps back to the cell and crawls out again.
	TEST_ASSERT_EQUAL(party.leg_origin_cell, route[3], "A party that turned back does not know which cell it turned back from.")

	skip_to_arrival(party)
	SSoverworld.fire()
	TEST_ASSERT_NULL(party.leg_origin_cell, "A party back on its cell still thinks it is inside the crossing it turned back from.")
	TEST_ASSERT_EQUAL(party.current_cell, route[2], "A party that turned back did not come back to the cell it had left.")
	TEST_ASSERT_EQUAL(party.supplies, supplies_before, "Coming back to a cell the party never left cost it a ration.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_RETURNING, "A party that turned back is not returning.")
	TEST_ASSERT_EQUAL(party.leg_target_cell(), route[1], "A party that turned back is not walking toward the colony.")


/// A new order that uses the crossing already in progress does not start that crossing again.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/onward_order_keeps_the_crossing

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/onward_order_keeps_the_crossing/Run()
	var/datum/overworld_party/party = begin_open_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/sites = sites_beyond(region, 3)
	TEST_ASSERT(length(sites), "The test region has no site three crossings out.")
	var/datum/overworld_site/target = sites[1]

	// Heading for a point part of the way along the road to the site.
	var/list/full_road = region.plan_route(OVERWORLD_HOME_CELL, "[target.q],[target.r]", OVERWORLD_ROUTE_FASTEST, get_discovered_cell_ids(region))
	put_on_the_road(party, full_road.Copy(1, 3), supplies = 200)

	walk_part_of_leg(party, 0.4)
	var/due = party.leg_arrives_at
	TEST_ASSERT_NULL(SSoverworld.order_to_site(party, target.site_id()), "A party on the road was refused a new destination.")
	TEST_ASSERT_EQUAL(party.leg_target_cell(), full_road[2], "The new order changed which cell the party is crossing into.")
	TEST_ASSERT_EQUAL(party.leg_arrives_at, due, "An order that continues the same crossing started that crossing again.")


/// A party with no rations walks slowly and goes hungry. It does not stop for good.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/hungry_party_keeps_walking

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/hungry_party_keeps_walking/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/mob/living/carbon/human/body = add_traveller(party)
	body.set_nutrition(NUTRITION_LEVEL_FED)

	var/list/route = region.plan_route(OVERWORLD_HOME_CELL, overworld_test_target(region, 3), OVERWORLD_ROUTE_FASTEST)
	TEST_ASSERT(length(route) >= 3, "The test could not plan a route long enough to walk.")
	put_on_the_road(party, route, supplies = 0)
	TEST_ASSERT(party.leg_arrives_at > 0, "A party with no rations was left standing on the road.")

	var/datum/overworld_cell/next_cell = region.cells[route[2]]
	TEST_ASSERT((party.leg_arrives_at - party.leg_started_at) > (next_cell.traversal_seconds() SECONDS), "A hungry party crossed as fast as a fed one.")

	var/fed = body.nutrition
	skip_to_arrival(party)
	SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.current_cell, route[2], "A hungry party did not make its crossing.")
	TEST_ASSERT(body.nutrition < fed, "A crossing with no ration did not make the traveller hungry.")
	TEST_ASSERT(party.leg_arrives_at > 0, "A hungry party stopped after one crossing.")


/// A detour is offered only to a party that can feed itself along it and all the way home.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/detour_is_priced_both_ways

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/detour_is_priced_both_ways/Run()
	var/datum/overworld_party/party = begin_open_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/seen = get_discovered_cell_ids(region)
	var/list/route = region.plan_route(OVERWORLD_HOME_CELL, overworld_test_target(region, 4), OVERWORLD_ROUTE_FASTEST, seen)
	TEST_ASSERT(length(route) >= 4, "The test could not plan a route long enough to go around.")
	put_on_the_road(party, route, supplies = 500)

	var/list/detour = party.detour_route(region)
	TEST_ASSERT(length(detour) >= 2, "The test region offers no way around the next cell.")
	var/list/way_back = region.plan_route(detour[length(detour)], OVERWORLD_HOME_CELL, OVERWORLD_ROUTE_FASTEST, seen)
	TEST_ASSERT(length(way_back) >= 2, "The test region offers no way home from the far end.")
	var/needed = ((length(detour) - 1) + (length(way_back) - 1)) * max(1, party.living_member_count())

	var/datum/overworld_decision/weather = get_overworld_decision(OVERWORLD_DECISION_WEATHER)
	var/blocked = party.leg_target_cell()

	party.supplies = needed - 1
	TEST_ASSERT(!(OVERWORLD_CHOICE_SKIRT in weather.available_choices(party, region, blocked)), "A party was offered a detour that would leave it without rations before it got home.")
	party.supplies = needed
	TEST_ASSERT(OVERWORLD_CHOICE_SKIRT in weather.available_choices(party, region, blocked), "A party that could feed itself along the detour was not offered it.")


/// A party at a site can go on to a second site without going home first.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/second_stop_from_a_site

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/second_stop_from_a_site/Run()
	var/datum/overworld_party/party = begin_open_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/sites = sites_beyond(region, 2)
	TEST_ASSERT(length(sites) >= 2, "The test region has fewer than two sites to visit in one journey.")
	var/datum/overworld_site/first = sites[1]
	var/datum/overworld_site/second = sites[2]
	var/first_cell = "[first.q],[first.r]"

	var/list/route = region.plan_route(OVERWORLD_HOME_CELL, first_cell, OVERWORLD_ROUTE_FASTEST, get_discovered_cell_ids(region))
	put_on_the_road(party, route, supplies = 200)
	party.destination_site_id = first.site_id()
	walk_while(party, OVERWORLD_PARTY_OUTBOUND)
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_AT_SITE, "The party never reached its first site.")

	TEST_ASSERT_NULL(SSoverworld.order_to_site(party, second.site_id()), "A party at a site was refused a second stop.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_OUTBOUND, "A party sent to a second stop is not on the road.")
	TEST_ASSERT_EQUAL(party.route[1], first_cell, "The road to the second stop does not start at the first.")
	TEST_ASSERT(party.leg_arrives_at > 0, "A party sent to a second stop was given no crossing to walk.")

	walk_while(party, OVERWORLD_PARTY_OUTBOUND)
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_AT_SITE, "The party never reached its second site.")
	TEST_ASSERT_EQUAL(party.current_cell, "[second.q],[second.r]", "The party stopped somewhere other than its second site.")


/// What a traveller is hauling goes where the traveller goes.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/hauled_crate_travels

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/hauled_crate_travels/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/mob/living/carbon/human/body = add_traveller(party)
	var/obj/structure/closet/crate/cargo = allocate(/obj/structure/closet/crate, get_step(run_loc_floor_bottom_left, EAST))
	body.start_pulling(cargo)
	TEST_ASSERT_EQUAL(body.pulling, cargo, "The test colonist could not take hold of a crate.")

	var/datum/overworld_destination/camp = new(null, null)
	allocated += camp
	camp.arrival_turfs += run_loc_floor_top_right

	TEST_ASSERT_EQUAL(SSoverworld.move_party_to(party, camp), 1, "The party's one traveller was not moved.")
	TEST_ASSERT_EQUAL(body.loc, run_loc_floor_top_right, "The traveller was not put on the arrival turf.")
	TEST_ASSERT_EQUAL(cargo.loc, run_loc_floor_top_right, "The crate a traveller was hauling was left behind.")
	TEST_ASSERT_EQUAL(body.pulling, cargo, "The traveller let go of the crate on the way.")


/// Two people at one table each keep their own selection.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/each_viewer_keeps_a_selection

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/each_viewer_keeps_a_selection/Run()
	begin_open_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/sites = sites_beyond(region, 2)
	TEST_ASSERT(length(sites) >= 2, "The test region has fewer than two sites to select.")
	var/datum/overworld_site/first = sites[1]
	var/datum/overworld_site/second = sites[2]

	var/obj/machinery/computer/colony_overworld/table = allocate(/obj/machinery/computer/colony_overworld)
	var/mob/living/carbon/human/vera = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/ossian = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)

	var/datum/overworld_map_view/view = table.map_view
	view.set_preview(vera, first.site_id(), null)
	view.set_preview(ossian, second.site_id(), null)
	TEST_ASSERT_EQUAL(view.ui_data(vera)["previewed_site_id"], first.site_id(), "One viewer's selection was replaced by another viewer's.")
	TEST_ASSERT_EQUAL(view.ui_data(ossian)["previewed_site_id"], second.site_id(), "The second viewer was not shown their own selection.")
	TEST_ASSERT(length(view.ui_data(vera)["route_offers"]), "A viewer was offered no route to the site they selected.")

	// Closing the window forgets that viewer and nobody else.
	view.ui_close(vera)
	TEST_ASSERT_NULL(view.ui_data(vera)["previewed_site_id"], "A viewer who closed the map kept a selection.")
	TEST_ASSERT_EQUAL(view.ui_data(ossian)["previewed_site_id"], second.site_id(), "Closing one viewer's map cleared another viewer's selection.")


/// A record of a returning party from before routes were stored in walking order still walks home.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/old_returning_record_walks_home

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/old_returning_record_walks_home/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/route = region.plan_route(OVERWORLD_HOME_CELL, overworld_test_target(region, 3), OVERWORLD_ROUTE_FASTEST)
	TEST_ASSERT(length(route) >= 4, "The test could not plan a route long enough to return along.")

	// As the old code wrote it: the outbound road, standing on its last cell, index counting down.
	put_on_the_road(party, route, supplies = 40)
	var/list/record = party.serialize()
	record["state"] = OVERWORLD_PARTY_RETURNING
	record["current_cell"] = route[length(route)]
	record["next_leg_index"] = length(route) - 1
	record -= "route_forward"

	TEST_ASSERT(party.deserialize(record), "An old returning record could not be read.")
	TEST_ASSERT_EQUAL(party.leg_target_cell(), route[length(route) - 1], "An old returning record walks toward the wrong cell.")
	TEST_ASSERT_EQUAL(party.route[length(party.route)], OVERWORLD_HOME_CELL, "An old returning record does not end at the colony.")

	walk_while(party, OVERWORLD_PARTY_RETURNING)
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_COMPLETE, "An old returning record never reached the colony.")
	TEST_ASSERT_EQUAL(party.current_cell, OVERWORLD_HOME_CELL, "An old returning record finished at [party.current_cell].")


/// A party on the road can be sent to look at unknown ground, and then goes home as any survey does.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/survey_order_on_the_road

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/survey_order_on_the_road/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()

	var/list/route = region.plan_route(OVERWORLD_HOME_CELL, overworld_test_target(region, 2), OVERWORLD_ROUTE_FASTEST, get_discovered_cell_ids(region))
	TEST_ASSERT(length(route) >= 3, "The test could not plan a route inside the ground the colony starts with.")
	put_on_the_road(party, route, supplies = 200)
	skip_to_arrival(party)
	SSoverworld.fire()

	var/target = null
	for(var/cell_id in get_overworld_frontier_cells(region))
		target = cell_id
		break
	TEST_ASSERT_NOTNULL(target, "There is no unknown ground next to known ground to look at.")

	TEST_ASSERT_NOTNULL(SSoverworld.order_to_survey(party, OVERWORLD_HOME_CELL), "A party was sent to survey ground the colony already knows.")
	TEST_ASSERT_NULL(SSoverworld.order_to_survey(party, target), "A party on the road was refused a survey of the frontier.")
	TEST_ASSERT_EQUAL(party.survey_cell, target, "A party sent to survey does not know which ground it is going to look at.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_OUTBOUND, "A party sent to survey is not on its way out.")

	walk_while(party, OVERWORLD_PARTY_OUTBOUND)
	TEST_ASSERT(region_state.is_discovered(target), "The ground the party was sent to look at is still unknown.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_RETURNING, "A party that finished a survey did not turn for home.")

	walk_while(party, OVERWORLD_PARTY_RETURNING)
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_COMPLETE, "A party that surveyed from the road never got home.")
	TEST_ASSERT_EQUAL(party.current_cell, OVERWORLD_HOME_CELL, "A party that surveyed from the road finished at [party.current_cell].")


/// The map tells a party that is out what a new order costs before it is given.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/map_prices_an_order_on_the_road

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/map_prices_an_order_on_the_road/Run()
	var/datum/overworld_party/party = begin_open_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/sites = sites_beyond(region, 2)
	TEST_ASSERT(length(sites), "The test region has no site to price a walk to.")
	var/datum/overworld_site/target = sites[1]
	var/datum/overworld_map_view/view = get_personal_overworld_map()

	// Nothing is priced for a party that has not left: the planning offers do that.
	view.set_preview(null, target.site_id(), null)
	TEST_ASSERT_NULL(view.ui_data(null)["order_preview"], "The map priced a new order for a party that is still at home.")

	var/list/route = region.plan_route(OVERWORLD_HOME_CELL, overworld_test_target(region, 3), OVERWORLD_ROUTE_FASTEST, get_discovered_cell_ids(region))
	put_on_the_road(party, route, supplies = 3)
	var/list/preview = view.ui_data(null)["order_preview"]
	view.set_preview(null, null, null)
	TEST_ASSERT_NOTNULL(preview, "The map did not price an order for a party on the road.")
	TEST_ASSERT_EQUAL(preview["kind"], "site", "An order to a site was priced as something else.")
	TEST_ASSERT(preview["steps"] >= 2, "The priced walk is shorter than the site is far.")
	TEST_ASSERT(preview["rations_needed"] > preview["rations_carried"], "A party with three rations was not told the walk needs more.")


/// A colonist carries the map, and is shown the way out while standing at one.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/colonist_carries_the_map

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/colonist_carries_the_map/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/mob/living/carbon/human/body = add_traveller(party)
	party.member_ids.Cut()
	TEST_ASSERT_NOTNULL(locate(/datum/action/colony_expedition_map) in body.actions, "A colonist was not given the expedition map.")
	TEST_ASSERT(get_personal_overworld_map().ui_data(body)["viewer_is_colonist"], "The carried map does not know its reader is a colonist.")

	allocate(/obj/effect/landmark/rimstation_caravan_exit, run_loc_floor_top_right)
	TEST_ASSERT_NULL(body.alerts[ALERT_CARAVAN_EXIT], "A colonist away from any way out was shown one.")
	body.forceMove(run_loc_floor_top_right)
	TEST_ASSERT_NOTNULL(body.alerts[ALERT_CARAVAN_EXIT], "A colonist standing at a way out was not shown it.")
	body.forceMove(run_loc_floor_bottom_left)
	TEST_ASSERT_NULL(body.alerts[ALERT_CARAVAN_EXIT], "A colonist who walked away from the way out is still shown it.")

	// Using the way out forms the expedition and signs the colonist on, if they are able to go.
	body.forceMove(run_loc_floor_top_right)
	var/obj/structure/closet/colonist_storage/locker/personal = allocate(/obj/structure/closet/colonist_storage/locker, run_loc_floor_bottom_left)
	claim_colonist_locker(body, personal)
	muster_at_exit(body)
	TEST_ASSERT_EQUAL(length(party.member_ids), 1, "A colonist who used the way out was not signed on.")


/// A party gathered at a way out can leave with no hitching post, and comes back in at the same place.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/leaves_and_returns_by_the_way_out

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/orders/leaves_and_returns_by_the_way_out/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/bank_account/account = get_settlement_account()
	if(account)
		account.account_balance = 9000

	var/mob/living/carbon/human/vera = add_traveller(party, "playerone", "Vera Holt")
	var/mob/living/carbon/human/otto = add_traveller(party, "playertwo", "Otto Vance")
	var/datum/colonist_record/vera_record = SScampaign.get_colonist_record_for_body(vera)
	var/datum/colonist_record/otto_record = SScampaign.get_colonist_record_for_body(otto)
	TEST_ASSERT_NOTNULL(party.gathering_problem(), "A party with no post and nobody at a way out was counted as gathered.")

	allocate(/obj/effect/landmark/rimstation_caravan_exit, run_loc_floor_top_right)
	vera.forceMove(run_loc_floor_top_right)
	var/problem = party.gathering_problem()
	TEST_ASSERT(findtext(problem, "Otto Vance") && findtext(problem, "way out"), "The party was not told who is missing from the way out: '[problem]'.")
	TEST_ASSERT_NULL(party.muster_point(), "A party with a member across the room was counted as gathered.")

	otto.forceMove(run_loc_floor_top_right)
	TEST_ASSERT_NULL(party.gathering_problem(), "A party standing together at a way out was refused.")
	TEST_ASSERT_EQUAL(party.muster_point(), run_loc_floor_top_right, "A party at a way out is not mustered there.")

	var/datum/overworld_site/target = pick_any_reachable_site(region, party)
	TEST_ASSERT_NOTNULL(target, "The test region offered no site to walk to.")
	TEST_ASSERT(party.set_destination(region, target.site_id(), OVERWORLD_ROUTE_FASTEST, get_discovered_cell_ids(region)), "A destination could not be chosen.")

	// Otto has not said yes, so Vera giving the word is not enough.
	TEST_ASSERT_NOTNULL(SScampaign.depart_party(vera_record.colonist_id), "A party left though one member had not agreed to go.")
	party.ready_member_ids += otto_record.colonist_id
	TEST_ASSERT_NULL(SScampaign.depart_party(vera_record.colonist_id), "A gathered party was refused when a member gave the word.")
	TEST_ASSERT(party.state != OVERWORLD_PARTY_FORMING, "A party that was sent out is still mustering.")

	TEST_ASSERT_EQUAL(party.exit_turf(), run_loc_floor_top_right, "The party does not remember where it walked out.")
	TEST_ASSERT_EQUAL(get_caravan_return_turf(party), run_loc_floor_top_right, "A party that left by a way out would not come back in by it.")

	var/datum/overworld_party/restored = new()
	allocated += restored
	TEST_ASSERT(restored.deserialize(party.serialize()), "A departed party could not be read back.")
	TEST_ASSERT_EQUAL(restored.exit_turf(), run_loc_floor_top_right, "A stored party forgot where it walked out.")
