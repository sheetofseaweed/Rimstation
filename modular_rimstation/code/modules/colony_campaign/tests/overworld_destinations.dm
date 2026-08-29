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
	TEST_ASSERT_NULL(load_overworld_destination("site-that-cannot-load", "LT_THIS_DOES_NOT_EXIST"), "A destination was returned for a template that cannot be loaded.")
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
	var/datum/overworld_destination/camp = load_overworld_destination(null, LAZY_TEMPLATE_KEY_RIMSTATION_TRANSIT)
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
	var/datum/overworld_destination/again = load_overworld_destination(null, LAZY_TEMPLATE_KEY_RIMSTATION_TRANSIT)
	TEST_ASSERT_EQUAL(again, camp, "Loading the camp twice built a second one.")

	// The reservation is a fact about this boot. If it ever reached the campaign record, the next boot would
	// come up believing in turfs nobody reserved.
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(region_state)
		var/encoded = json_encode(region_state.serialize())
		TEST_ASSERT(!findtext(encoded, "turf_reservation"), "A turf reservation was written into the campaign record.")

	// Deliberately not cleaned up: the reservation cannot be released, and dropping the registry entry would
	// only make the next caller reserve a second block for the same camp.


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
