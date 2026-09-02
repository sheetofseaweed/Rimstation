/**
 * The contracts the overworld has to keep to be affordable and safe to store.
 *
 * Two kinds of promise live here. One is about cost: the region is rebuilt from its inputs rather than stored,
 * which is only a good trade while rebuilding is rare and bounded. The other is about what reaches disk: the
 * campaign record has to survive a reboot, so anything in it that only means something in this process - a ref,
 * a coordinate, a loaded scene - is a field that comes back as a lie.
 *
 * Both are asserted here rather than measured in the running game. Permanent counters to prove a contract that
 * holds are just telemetry nobody reads.
 */
/datum/unit_test/rimstation_overworld_contracts
	abstract_type = /datum/unit_test/rimstation_overworld_contracts


/**
 * Region generation stays bounded, and is not redone for every look at the map.
 *
 * The largest region a player can choose is radius eleven, which is 397 cells. That number is the budget for
 * everything downstream - the payload, the route planner's linear scan, the memory - so it is asserted rather
 * than assumed.
 */
/datum/unit_test/rimstation_overworld_contracts/generation_is_bounded_and_cached

/datum/unit_test/rimstation_overworld_contracts/generation_is_bounded_and_cached/Run()
	var/datum/planet_definition/planet = new("contract-test-seed", "contract-test-planet")
	allocated += planet

	// The largest world on offer, and the ceiling everything else is sized against.
	var/datum/overworld_region/biggest = new(planet, list(
		"extent" = OVERWORLD_EXTENT_EXPANSIVE,
		"roughness" = OVERWORLD_ROUGHNESS_RUGGED,
		"abundance" = OVERWORLD_ABUNDANCE_RICH,
	))
	var/cell_count = length(biggest.cells)
	var/site_count = length(biggest.sites)
	qdel(biggest)

	TEST_ASSERT_EQUAL(cell_count, 397, "The largest region is no longer 397 cells, so every budget sized against it is now wrong.")
	TEST_ASSERT(site_count <= 20, "The largest region generated [site_count] sites; each is a map template that can be loaded and never released.")

	// The region is cached against its inputs. Asking twice must not rebuild it, because ui_data() asks on
	// every single push - regenerating four hundred cells per viewer per update would be the most expensive
	// thing in the round by a wide margin.
	var/datum/overworld_region/first = get_active_overworld_region()
	TEST_ASSERT_NOTNULL(first, "There was no active region to ask for.")
	for(var/attempt in 1 to 5)
		TEST_ASSERT_EQUAL(get_active_overworld_region(), first, "Asking for the active region rebuilt it instead of reusing it.")

	// And the cache is keyed on what the region is built from, so a changed option really does rebuild.
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(region_state)
		var/original_extent = region_state.options["extent"]
		region_state.options["extent"] = (original_extent == OVERWORLD_EXTENT_COMPACT) ? OVERWORLD_EXTENT_EXPANSIVE : OVERWORLD_EXTENT_COMPACT
		var/datum/overworld_region/after_change = get_active_overworld_region()
		TEST_ASSERT(after_change != first, "Changing the region's options did not rebuild it, so the map would draw the old world.")
		region_state.options["extent"] = original_extent


/**
 * Nothing reaches the campaign record that stops meaning anything after a reboot.
 *
 * The overworld record is JSON on disk. A datum reference, a turf, a coordinate into a reservation or a loaded
 * scene all serialize into something that looks like data and is meaningless the moment the process ends - and
 * the failure would not show until somebody resumed a campaign and found it describing nowhere.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_record_is_storable

/datum/unit_test/rimstation_colonist_chapter/overworld_record_is_storable/Run()
	begin_test_campaign()
	SScampaign.overworld = new(default_overworld_options())
	SScampaign.ledger = new
	SScampaign.start_campaign_time()

	var/datum/overworld_region/region = get_active_overworld_region()
	SScampaign.overworld.reveal_initial(region)

	// A record with something in every part of it: discovery, a changed site, and a party mid-journey holding a
	// question. An empty record proves nothing about what a full one would carry.
	var/datum/overworld_party/party = SScampaign.form_party()
	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	SScampaign.bind_colonist(body, vera)
	party.member_ids += vera.colonist_id

	party.route = region.plan_route("0,0", "2,0", OVERWORLD_ROUTE_FASTEST)
	party.current_cell = party.route[1]
	party.next_leg_index = 2
	party.supplies = 20
	party.set_state(OVERWORLD_PARTY_DEPARTING, "test")
	party.set_state(OVERWORLD_PARTY_OUTBOUND, "test")
	party.set_state(OVERWORLD_PARTY_DECISION, "test")
	party.pending_decision = list(
		"id" = "decision-test-1",
		"kind" = OVERWORLD_DECISION_WEATHER,
		"cell" = "1,0",
		"choices" = list(OVERWORLD_CHOICE_PRESS_ON),
	)

	for(var/site_id in region.sites)
		SScampaign.overworld.set_site_state(region, site_id, OVERWORLD_SITE_STATE_DEPLETED, "test")
		break

	SScampaign.sync_overworld()
	var/encoded = json_encode(SScampaign.manifest.overworld_record)
	TEST_ASSERT(length(encoded), "The overworld record encoded to nothing.")

	// Anything that is a reference to something in this process, rather than a fact about the campaign.
	var/list/forbidden = list(
		"/datum/" = "a datum reference",
		"/obj/" = "an object reference",
		"/mob/" = "a mob reference",
		"/turf/" = "a turf reference",
		"/area/" = "an area reference",
		"turf_reservation" = "a turf reservation",
		"lazy_template" = "a map template",
		"0x" = "a raw reference",
	)
	for(var/needle in forbidden)
		TEST_ASSERT(!findtext(encoded, needle), "The overworld record contains [forbidden[needle]], which means nothing after a reboot.")

	// The generated region must not be in there either. It is derived from the planet and the options, and a
	// stored copy would be a second answer to what the world looks like - one that drifts.
	TEST_ASSERT(!findtext(encoded, "topology"), "The overworld record stored generated terrain, which the generator already decides.")
	TEST_ASSERT(!findtext(encoded, "traversal"), "The overworld record stored generated travel costs.")
	TEST_ASSERT(!findtext(encoded, "\"danger\""), "The overworld record stored generated danger values.")

	// What it should contain: the options it was built from, what was explored, what play changed, and the one
	// party. Each of these is something no generator could work out on its own.
	TEST_ASSERT(findtext(encoded, "discovered_cells"), "The overworld record does not carry what the colony explored.")
	TEST_ASSERT(findtext(encoded, "site_states"), "The overworld record does not carry what play changed.")
	TEST_ASSERT(findtext(encoded, "active_party"), "The overworld record does not carry the expedition.")
	TEST_ASSERT(findtext(encoded, "region_fingerprint"), "The overworld record does not say which region it describes.")

	// And it survives the trip. A record that encodes but cannot be read back is the same as no record.
	var/datum/overworld_state/reloaded = new(default_overworld_options())
	allocated += reloaded
	TEST_ASSERT(reloaded.deserialize(SScampaign.manifest.overworld_record), "A full overworld record could not be read back.")
	TEST_ASSERT_NOTNULL(reloaded.active_party, "The expedition did not survive the round trip.")
	TEST_ASSERT_EQUAL(length(reloaded.discovered_cells), length(SScampaign.overworld.discovered_cells), "Discovery did not survive the round trip.")
	TEST_ASSERT_EQUAL(length(reloaded.site_states), length(SScampaign.overworld.site_states), "Changed sites did not survive the round trip.")
