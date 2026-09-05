/**
 * Bringing an expedition's destination into being.
 *
 * The inherited loader does not fail politely - a missing file, an unparseable map or an exhausted reservation
 * pool all CRASH - so most of what matters here is refusing to call it. The one test that does load something
 * real is worth its cost: landmark binding only happens inside the load, and nothing cheaper proves it works.
 */
/datum/unit_test/rimstation_overworld_destinations
	abstract_type = /datum/unit_test/rimstation_overworld_destinations

/// Nothing reaches the inherited loader unless it is going to work.
/datum/unit_test/rimstation_overworld_destinations/refuses_before_loading

/datum/unit_test/rimstation_overworld_destinations/refuses_before_loading/Run()
	// The two the campaign actually ships. If either of these ever reports a problem, the content is missing
	// and every expedition in the game is broken - which is worth failing a test over.
	TEST_ASSERT_NULL(overworld_template_problem(LAZY_TEMPLATE_KEY_RIMSTATION_TRANSIT), "The caravan transit template is not loadable.")
	TEST_ASSERT_NULL(overworld_template_problem(LAZY_TEMPLATE_KEY_RIMSTATION_RESOURCE_SITE), "The resource site template is not loadable.")

	// A key nobody registered, which is what a typo in a define looks like from here.
	TEST_ASSERT_NOTNULL(overworld_template_problem("LT_THIS_DOES_NOT_EXIST"), "An unregistered template key was accepted.")
	TEST_ASSERT_NOTNULL(overworld_template_problem(""), "An empty template key was accepted.")
	TEST_ASSERT_NOTNULL(overworld_template_problem(null), "A null template key was accepted.")

	// A registered key whose file is not there. This is the case the inherited loader crashes on, so it has to
	// be caught here or a content mistake takes the round down with it.
	var/datum/lazy_template/rimstation_resource_site/site_template = GLOB.lazy_templates[LAZY_TEMPLATE_KEY_RIMSTATION_RESOURCE_SITE]
	TEST_ASSERT_NOTNULL(site_template, "The resource site template is not registered at all.")
	var/real_name = site_template.map_name
	site_template.map_name = "rimstation_this_file_does_not_exist"
	TEST_ASSERT_NOTNULL(overworld_template_problem(LAZY_TEMPLATE_KEY_RIMSTATION_RESOURCE_SITE), "A template whose file is missing was accepted, which would crash the loader.")
	site_template.map_name = real_name

	// And a refused load builds nothing rather than leaving an empty shell in the registry.
	TEST_ASSERT_NULL(load_overworld_destination("site-that-cannot-load", null), "A destination was returned without a valid provider.")
	TEST_ASSERT_NULL(GLOB.rimstation_overworld_destinations["site-that-cannot-load"], "A failed load left an entry in the destination registry.")


/**
 * A loaded scene knows where to put people, and loading it again does not build a second one.
 *
 * This one really loads a map. The camp is used rather than a site because it needs no generated region behind
 * it, so what is under test is the loading rather than the campaign around it.
 */
/datum/unit_test/rimstation_overworld_destinations/loads_and_binds

/datum/unit_test/rimstation_overworld_destinations/loads_and_binds/Run()
	// The camp may already be standing: any expedition that departs brings it up, and reservations are never
	// released. That is fine - what is under test is that asking for it yields one bound, usable scene, which
	// is true whether this call built it or found it.
	var/datum/overworld_destination/camp = load_overworld_destination(null, /datum/overworld_scene_provider/premade/transit)
	TEST_ASSERT_NOTNULL(camp, "The travelling camp could not be loaded.")
	TEST_ASSERT_NOTNULL(camp.reservation, "A loaded destination reserved no turfs.")
	TEST_ASSERT_NULL(camp.site_id, "The travelling camp claimed to belong to a site.")

	// The landmarks are the whole reason for listening to the load. Without them a party arrives nowhere.
	TEST_ASSERT(length(camp.arrival_turfs), "The camp was loaded with nowhere for anybody to arrive.")
	var/turf/spot = camp.pick_arrival_turf()
	TEST_ASSERT_NOTNULL(spot, "The camp offered no open turf to put a body on.")
	TEST_ASSERT(!isclosedturf(spot), "The camp offered a wall as an arrival point.")

	// Filed under the camp's own key, which cannot collide with a site id.
	TEST_ASSERT_EQUAL(get_caravan_transit(), camp, "A loaded camp was not findable afterwards.")

	// Asking again returns what is standing rather than building a second copy - which would strand anybody in
	// the first one and reserve another block of turfs for nothing.
	var/datum/overworld_destination/again = load_overworld_destination(null, /datum/overworld_scene_provider/premade/transit)
	TEST_ASSERT_EQUAL(again, camp, "Loading the camp twice built a second one.")

	// The reservation is a fact about this boot. If it ever reached the campaign record, the next boot would
	// come up believing in turfs nobody reserved.
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(region_state)
		var/encoded = json_encode(region_state.serialize())
		TEST_ASSERT(!findtext(encoded, "turf_reservation"), "A turf reservation was written into the campaign record.")

	// Deliberately not cleaned up: the reservation cannot be released, and dropping the registry entry would
	// only make the next caller reserve a second block for the same camp.


/// A generated site's plan is local, repeatable, and guarantees a walkable route to its objective.
/datum/unit_test/rimstation_overworld_destinations/procedural_resource_plan

/datum/unit_test/rimstation_overworld_destinations/procedural_resource_plan/Run()
	var/datum/planet_definition/planet = new("expedition-scene-test-seed", "expedition-scene-test")
	var/datum/overworld_site/site = new(OVERWORLD_SITE_RESOURCE, 3, 4, -2)
	var/datum/overworld_cell/cell = new(4, -2)
	cell.terrain = OVERWORLD_TERRAIN_FOREST
	cell.topology = OVERWORLD_TOPOLOGY_DIFFICULT
	cell.danger = 2

	var/datum/rimstation_expedition_scene_context/first = new(planet, site, cell)
	var/datum/rimstation_expedition_scene_context/second = new(planet, site, cell)
	TEST_ASSERT(first.build_plan(), "The first procedural resource plan could not be built.")
	TEST_ASSERT(second.build_plan(), "The same procedural resource plan could not be rebuilt.")
	TEST_ASSERT_EQUAL(first.fingerprint(), second.fingerprint(), "The same planet and site produced different resource scenes.")

	var/arrival_index = first.coordinate_index(first.arrival_x, first.arrival_y)
	var/objective_index = first.coordinate_index(first.objective_x, first.objective_y)
	TEST_ASSERT(first.trail_mask[arrival_index], "The guaranteed trail does not include the caravan arrival.")
	TEST_ASSERT(first.trail_mask[objective_index], "The guaranteed trail does not reach the deposit clearing.")
	TEST_ASSERT(ispath(first.turf_plan[arrival_index], /turf/open), "The caravan arrival was planned as closed terrain.")
	TEST_ASSERT(ispath(first.turf_plan[objective_index], /turf/open), "The resource objective was planned as closed terrain.")
	TEST_ASSERT(ispath(first.turf_plan[first.coordinate_index(1, 1)], /turf/closed/indestructible/rock), "The reservation edge was not safely enclosed.")

	var/list/frontier = list(arrival_index)
	var/list/reached = new /list(first.width * first.height)
	reached[arrival_index] = TRUE
	while(length(frontier))
		var/current = frontier[1]
		frontier.Cut(1, 2)
		var/current_x = first.index_x(current)
		var/current_y = first.index_y(current)
		for(var/list/offset as anything in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
			var/neighbour = first.coordinate_index(current_x + offset[1], current_y + offset[2])
			if(isnull(neighbour) || reached[neighbour] || !first.trail_mask[neighbour])
				continue
			reached[neighbour] = TRUE
			frontier += neighbour
	TEST_ASSERT(reached[objective_index], "The generated trail has a break between arrival and objective.")

	var/datum/overworld_site/other_site = new(OVERWORLD_SITE_RESOURCE, 4, 4, -2)
	var/datum/rimstation_expedition_scene_context/other = new(planet, other_site, cell)
	TEST_ASSERT(other.build_plan(), "A second site's procedural resource plan could not be built.")
	TEST_ASSERT_NOTEQUAL(first.fingerprint(), other.fingerprint(), "Two different site identities produced the same resource scene.")

	qdel(other)
	qdel(other_site)
	qdel(second)
	qdel(first)
	qdel(cell)
	qdel(site)
	qdel(planet)


/// A deposit pays once, and the campaign record rather than the object is what remembers that.
/datum/unit_test/rimstation_colonist_chapter/overworld_deposit_pays_once

/datum/unit_test/rimstation_colonist_chapter/overworld_deposit_pays_once/Run()
	begin_test_campaign()
	SScampaign.overworld = new(default_overworld_options())
	SScampaign.ledger = new

	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	TEST_ASSERT_NOTNULL(region, "The test could not build a region.")

	var/datum/overworld_site/deposit_site = null
	for(var/site_id in region.sites)
		var/datum/overworld_site/candidate = region.sites[site_id]
		if(candidate.kind == OVERWORLD_SITE_RESOURCE)
			deposit_site = candidate
			break
	TEST_ASSERT_NOTNULL(deposit_site, "The region generated no resource site to work.")

	var/obj/structure/rimstation_resource_deposit/seam = allocate(/obj/structure/rimstation_resource_deposit, run_loc_floor_bottom_left)
	TEST_ASSERT(seam.bind_to_site(deposit_site.site_id()), "A deposit could not be bound to a generated site.")
	TEST_ASSERT_EQUAL(seam.deposit_yield, deposit_site.yield, "A deposit did not take its worth from the site it stands for.")
	TEST_ASSERT(!seam.worked, "A freshly bound deposit was already spent.")

	// A seam belonging to nowhere is inert rather than free ore.
	var/obj/structure/rimstation_resource_deposit/orphan = allocate(/obj/structure/rimstation_resource_deposit, run_loc_floor_bottom_left)
	TEST_ASSERT(!orphan.bind_to_site(null), "A deposit bound itself to no site at all.")
	TEST_ASSERT(orphan.worked, "A deposit belonging to no site was left workable.")
	TEST_ASSERT(!orphan.bind_to_site("site-that-does-not-exist"), "A deposit bound itself to a site outside the region.")

	// Depleting the site is what stops a second payout, so it is asserted through the record rather than the
	// object: the object lives in a reservation that outlives the chapter, and would otherwise offer again.
	TEST_ASSERT(region_state.set_site_state(region, deposit_site.site_id(), OVERWORLD_SITE_STATE_DEPLETED, "test"), "A site could not be marked depleted.")

	var/obj/structure/rimstation_resource_deposit/second_visit = allocate(/obj/structure/rimstation_resource_deposit, run_loc_floor_bottom_left)
	TEST_ASSERT(!second_visit.bind_to_site(deposit_site.site_id()), "A deposit at an already-stripped site bound itself as workable.")
	TEST_ASSERT(second_visit.worked, "Walking back into a stripped site offered the ore again.")
	TEST_ASSERT_NOTNULL(second_visit.inert_reason, "A spent deposit gave no reason a player could read.")


/// A procedural provider reserves real turfs and binds a real objective to the generated site.
/datum/unit_test/rimstation_colonist_chapter/overworld_generated_resource_scene

/datum/unit_test/rimstation_colonist_chapter/overworld_generated_resource_scene/Run()
	begin_test_campaign()
	SScampaign.overworld = new(default_overworld_options())

	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/overworld_site/resource_site
	for(var/site_id in region?.sites)
		var/datum/overworld_site/candidate = region.sites[site_id]
		if(candidate.kind == OVERWORLD_SITE_RESOURCE)
			resource_site = candidate
			break
	TEST_ASSERT_NOTNULL(resource_site, "The test campaign generated no resource site.")

	var/site_id = resource_site.site_id()
	TEST_ASSERT_EQUAL(overworld_site_scene_provider(site_id), /datum/overworld_scene_provider/procedural_resource, "A resource site did not select the procedural provider.")
	TEST_ASSERT_NULL(overworld_scene_problem(site_id, /datum/overworld_scene_provider/procedural_resource), "The procedural provider refused a valid resource site.")

	var/datum/overworld_destination/destination = load_overworld_destination(site_id, /datum/overworld_scene_provider/procedural_resource)
	TEST_ASSERT_NOTNULL(destination, "The procedural resource scene could not be materialized.")
	TEST_ASSERT_NOTNULL(destination.reservation, "The procedural resource scene reserved no turfs.")
	TEST_ASSERT_EQUAL(destination.reservation.width, OVERWORLD_PROCEDURAL_SCENE_WIDTH, "The resource reservation has the wrong width.")
	TEST_ASSERT_EQUAL(destination.reservation.height, OVERWORLD_PROCEDURAL_SCENE_HEIGHT, "The resource reservation has the wrong height.")
	TEST_ASSERT_NOTNULL(destination.scene_area, "The generated scene has no independent expedition area.")
	TEST_ASSERT(length(destination.arrival_turfs), "The generated scene has nowhere for the caravan to arrive.")
	TEST_ASSERT_NOTNULL(destination.pick_arrival_turf(), "The generated scene offered no open arrival turf.")

	var/obj/structure/rimstation_resource_deposit/deposit = destination.objective_ref?.resolve()
	TEST_ASSERT_NOTNULL(deposit, "The generated resource scene has no deposit.")
	TEST_ASSERT_EQUAL(deposit.site_id, site_id, "The generated deposit was not bound to its strategic site.")
	TEST_ASSERT_EQUAL(get_area(deposit), destination.scene_area, "The generated deposit is not in the scene's own area.")
