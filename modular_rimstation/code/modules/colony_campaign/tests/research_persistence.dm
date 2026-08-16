/**
 * Puts the global techweb node list back if an earlier test emptied it.
 *
 * Something else in the suite destroys every /datum/techweb_node before these tests run. Research is fine in a
 * live round and these tests pass when focused, so this is a test-suite ordering problem rather than a defect
 * in the game - but a test that silently proves nothing because another test wrecked shared state is worse
 * than one that repairs it and says so.
 */
/proc/ensure_techweb_nodes_for_test()
	if(length(SSresearch.techweb_nodes))
		return FALSE
	SSresearch.initialize_all_techweb_nodes()
	return TRUE


/**
 * A colony keeps what it researched, and keeps only what it actually paid for.
 *
 * The techweb is rebuilt from nothing every round, so without this a campaign would begin each chapter having
 * forgotten everything. Restoring is not a purchase: a colony that already paid for a node must not be charged
 * again, and the balance it comes back with has to be the balance it left with.
 */
/datum/unit_test/rimstation_colony_research_round_trip

/datum/unit_test/rimstation_colony_research_round_trip/Run()
	ensure_techweb_nodes_for_test()

	var/datum/techweb/source = new /datum/techweb
	allocated += source
	var/datum/techweb/destination = new /datum/techweb
	allocated += destination

	TEST_ASSERT(length(SSresearch.techweb_nodes), "SSresearch holds no techweb nodes ([length(SSresearch.techweb_nodes)] of [length(subtypesof(/datum/techweb_node))] subtypes, [length(SSresearch.techweb_nodes_starting)] starting), so there is nothing for a colony to research or carry between chapters.")

	// Must be a node a fresh techweb does *not* already have. Every techweb researches the starting nodes in
	// New(), so restoring one of those would prove nothing about restoring anything.
	var/datum/techweb_node/node
	for(var/node_id in SSresearch.techweb_nodes)
		if(SSresearch.techweb_nodes_starting[node_id])
			continue
		node = SSresearch.techweb_nodes[node_id]
		break
	TEST_ASSERT_NOTNULL(node, "All [length(SSresearch.techweb_nodes)] techweb nodes are starting nodes, so restoration cannot be tested.")
	TEST_ASSERT(!destination.researched_nodes[node.id], "A fresh techweb already knows the node this test restores, so it proves nothing.")

	TEST_ASSERT(source.research_node(node, force = TRUE, auto_adjust_cost = FALSE, get_that_dosh = FALSE), "A node could not be researched into a fresh techweb.")
	source.research_points = list(TECHWEB_POINT_TYPE_GENERIC = 1234)

	var/datum/colony_research_record/record = new
	allocated += record
	TEST_ASSERT(record.capture_from(source), "The colony's research could not be read out of its techweb.")
	TEST_ASSERT(node.id in record.researched_node_ids, "A researched node was not captured.")
	TEST_ASSERT_EQUAL(record.research_points[TECHWEB_POINT_TYPE_GENERIC], 1234, "Unspent points were not captured.")

	// Through disk and back, because that is the trip it actually makes.
	var/datum/colony_research_record/restored = new
	allocated += restored
	TEST_ASSERT(restored.deserialize(json_decode(json_encode(record.serialize()))), "A research record did not survive a JSON round trip.")

	TEST_ASSERT(restored.restore_into(destination), "Restoring the colony's research into a fresh techweb restored nothing.")
	TEST_ASSERT(destination.researched_nodes[node.id], "A restored colony had forgotten a node it had researched.")
	TEST_ASSERT_EQUAL(destination.research_points[TECHWEB_POINT_TYPE_GENERIC], 1234, "A restored colony did not come back with the points it left with.")

	// Restoring must not charge for what was already bought.
	var/datum/techweb/broke = new /datum/techweb
	allocated += broke
	broke.research_points = list()
	TEST_ASSERT(restored.restore_into(broke), "A colony with no points could not restore research it had already paid for.")
	TEST_ASSERT(broke.researched_nodes[node.id], "A colony that could not afford its own research lost it on restore.")

	// Restoring is idempotent, since a chapter can be restored more than once across a reboot.
	var/points_before = destination.research_points[TECHWEB_POINT_TYPE_GENERIC]
	restored.restore_into(destination)
	TEST_ASSERT_EQUAL(destination.research_points[TECHWEB_POINT_TYPE_GENERIC], points_before, "Restoring twice changed the colony's balance.")

	// A node this build no longer has costs the colony that node, not its campaign.
	var/datum/colony_research_record/with_retired = new
	allocated += with_retired
	var/list/record_with_retired = record.serialize()
	record_with_retired["researched_node_ids"] = list(node.id, "a_node_that_no_longer_exists")
	TEST_ASSERT(with_retired.deserialize(record_with_retired), "A record naming a retired node was refused outright.")
	var/datum/techweb/after_retirement = new /datum/techweb
	allocated += after_retirement
	TEST_ASSERT(with_retired.restore_into(after_retirement), "A record naming a retired node restored nothing at all.")
	TEST_ASSERT(after_retirement.researched_nodes[node.id], "Dropping a retired node also dropped a valid one.")


/// Records come off disk, so a hand-edited one must not hand a colony a fortune or a debt.
/datum/unit_test/rimstation_colony_research_record_validation

/datum/unit_test/rimstation_colony_research_record_validation/Run()
	var/datum/colony_research_record/record = new
	allocated += record

	TEST_ASSERT(!record.deserialize(null), "A null research record was accepted.")
	TEST_ASSERT(!record.deserialize(list()), "A record with no schema version was accepted.")

	var/list/from_the_future = record.serialize()
	from_the_future["schema_version"] = COLONY_RESEARCH_SCHEMA_VERSION + 1
	TEST_ASSERT(!record.deserialize(from_the_future), "A research record from an unknown schema was accepted.")

	// Negative and non-numeric balances are dropped rather than restored.
	var/list/with_bad_points = record.serialize()
	with_bad_points["research_points"] = list(TECHWEB_POINT_TYPE_GENERIC = -5000, "nonsense" = "lots")
	TEST_ASSERT(record.deserialize(with_bad_points), "A record with an unusable balance was refused outright.")
	TEST_ASSERT(!length(record.research_points), "A negative or non-numeric research balance was restored.")


/**
 * Research costs more during a campaign, and exactly as much as before outside one.
 *
 * The multiplier is applied where the price is asked for, so there is no route - affordability, purchase, or
 * the number a console displays - that sees the station price during a campaign.
 */
/datum/unit_test/rimstation_colony_research_cost_multiplier
	var/saved_state
	var/datum/campaign_manifest/saved_manifest

/datum/unit_test/rimstation_colony_research_cost_multiplier/Run()
	saved_state = SScampaign.campaign_state
	saved_manifest = SScampaign.manifest
	ensure_techweb_nodes_for_test()

	// Find a node that actually costs something, whatever it is priced in, so the multiplication is observable.
	TEST_ASSERT(length(SSresearch.techweb_nodes), "SSresearch reports [length(SSresearch.techweb_nodes)] techweb nodes, so no price can be checked.")

	var/datum/techweb_node/priced_node
	var/point_type
	for(var/node_id in SSresearch.techweb_nodes)
		var/datum/techweb_node/candidate = SSresearch.techweb_nodes[node_id]
		for(var/candidate_type in candidate.research_costs)
			if(candidate.research_costs[candidate_type] > 0)
				priced_node = candidate
				point_type = candidate_type
				break
		if(priced_node)
			break
	TEST_ASSERT_NOTNULL(priced_node, "None of the [length(SSresearch.techweb_nodes)] techweb nodes costs anything, so the multiplier cannot be tested.")

	// Outside a campaign, an ordinary shift pays ordinary prices.
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	SScampaign.manifest = null
	var/list/station_price = priced_node.get_price(null)
	TEST_ASSERT_EQUAL(station_price[point_type], priced_node.research_costs[point_type], "A node cost more than its listed price outside a campaign.")

	// Inside one, everything costs the multiplier more.
	var/datum/campaign_manifest/manifest = new("unit-test-research", "generation-1")
	allocated += manifest
	SScampaign.manifest = manifest
	SScampaign.campaign_state = CAMPAIGN_STATE_ACTIVE

	var/list/campaign_price = priced_node.get_price(null)
	TEST_ASSERT_EQUAL(campaign_price[point_type], round(priced_node.research_costs[point_type] * CAMPAIGN_RESEARCH_COST_MULTIPLIER), "Research did not cost the campaign multiplier more.")

	// And asking twice must not compound: the node's own cost list has to be left alone.
	var/list/asked_again = priced_node.get_price(null)
	TEST_ASSERT_EQUAL(asked_again[point_type], campaign_price[point_type], "Asking a node's price twice multiplied it twice, so research would become unaffordable over a round.")
	TEST_ASSERT_EQUAL(priced_node.research_costs[point_type], station_price[point_type], "Reading a campaign price permanently changed the node's real cost.")

/datum/unit_test/rimstation_colony_research_cost_multiplier/Destroy()
	SScampaign.campaign_state = saved_state
	SScampaign.manifest = saved_manifest
	saved_manifest = null
	return ..()
