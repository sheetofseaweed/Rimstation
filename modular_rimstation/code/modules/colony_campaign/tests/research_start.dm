/**
 * The temporary colony starting set retains station prerequisites without granting advanced research.
 */
/datum/unit_test/rimstation_campaign_starting_research

/datum/unit_test/rimstation_campaign_starting_research/Run()
	ensure_techweb_nodes_for_test()

	var/datum/techweb/web = new /datum/techweb
	allocated += web

	restrict_techweb_to_campaign_start(web)

	// Exactly the configured prerequisites, and nothing else.
	var/list/allowed = CAMPAIGN_STARTING_RESEARCH_NODES
	for(var/node_id in allowed)
		TEST_ASSERT(web.researched_nodes[node_id], "A colony did not start knowing '[node_id]', which it is meant to arrive with.")
	for(var/node_id in web.researched_nodes)
		TEST_ASSERT(node_id in allowed, "A colony started knowing '[node_id]', which is outside its starting set.")
	TEST_ASSERT(web.researched_nodes[TECHWEB_NODE_MEDBAY_EQUIP], "The colony lost its medical starting prerequisite.")
	TEST_ASSERT(!web.researched_nodes[TECHWEB_NODE_CHEM_SYNTHESIS], "The colony received Chemical Synthesis for free.")
	TEST_ASSERT(web.available_nodes[TECHWEB_NODE_CHEM_SYNTHESIS], "The medical starting prerequisite did not make Chemical Synthesis available.")

	// The designs those nodes unlock came with them, so the colony can actually build something.
	TEST_ASSERT(length(web.researched_designs), "A restricted colony techweb unlocked no designs at all.")

	// Applying it twice changes nothing further.
	var/settled = length(web.researched_nodes)
	restrict_techweb_to_campaign_start(web)
	TEST_ASSERT_EQUAL(length(web.researched_nodes), settled, "Restricting an already-restricted techweb changed it again.")


/**
 * The price a console shows is the price it charges.
 *
 * These are separate code paths - the UI cache read the node's raw costs while the purchase used get_price() -
 * so a campaign multiplier applied to one and not the other. That displayed one number and billed another.
 */
/datum/unit_test/campaign_failure_path/rimstation_research_price_display
	test_campaign_id = "unit-test-price-display"

/datum/unit_test/campaign_failure_path/rimstation_research_price_display/Run()
	take_campaign()
	ensure_techweb_nodes_for_test()

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
	TEST_ASSERT_NOTNULL(priced_node, "No techweb node costs anything, so pricing cannot be tested.")

	var/raw_cost = priced_node.research_costs[point_type]

	// Outside a campaign the two agree because nothing is multiplying anything.
	TEST_ASSERT_EQUAL(priced_node.get_price(null)[point_type], raw_cost, "A node cost more than its listed price outside a campaign.")

	// Inside one, the charged price moves - and anything displaying the raw cost would now be lying.
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")
	var/campaign_cost = priced_node.get_price(null)[point_type]
	TEST_ASSERT_EQUAL(campaign_cost, round(raw_cost * CAMPAIGN_RESEARCH_COST_MULTIPLIER), "Research did not cost the campaign multiplier more.")
	TEST_ASSERT_NOTEQUAL(campaign_cost, raw_cost, "The charged price is the raw price, so displaying the raw cost would be correct by accident.")
