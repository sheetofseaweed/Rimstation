/**
 * Nodes a techweb already holds, plus everything its prerequisite chain can still lead to.
 * A node nothing can ever pay for is not traversed, so a retired branch does not look reachable.
 */
/proc/campaign_obtainable_techweb_nodes(datum/techweb/web)
	RETURN_TYPE(/list)
	var/list/obtainable = web.researched_nodes.Copy()

	var/progressed = TRUE
	while(progressed)
		progressed = FALSE
		for(var/node_path in SSresearch.techweb_nodes)
			if(obtainable[node_path])
				continue
			var/datum/techweb_node/node = SSresearch.techweb_nodes[node_path]
			if(!campaign_techweb_node_is_payable(node, web))
				continue
			var/satisfied = TRUE
			for(var/prerequisite_path in node.prerequisite_nodes)
				if(!obtainable[prerequisite_path])
					satisfied = FALSE
					break
			if(!satisfied)
				continue
			obtainable[node_path] = TRUE
			progressed = TRUE
	return obtainable

/// FALSE when no amount of play can pay for a node. An INFINITY price is how a node is retired without deleting it.
/proc/campaign_techweb_node_is_payable(datum/techweb_node/node, datum/techweb/web)
	var/list/price = node.get_price(web)
	for(var/point_type in price)
		if(price[point_type] >= INFINITY)
			return FALSE
	return TRUE


/**
 * Nothing an ordinary station can research is permanently out of a colony's reach.
 * Read as a difference against an unrestricted techweb, so an upstream dead end is not reported as ours.
 */
/datum/unit_test/rimstation_campaign_research_reachability

/datum/unit_test/rimstation_campaign_research_reachability/Run()
	ensure_techweb_nodes_for_test()

	var/datum/techweb/station = new /datum/techweb
	allocated += station
	var/list/station_obtainable = campaign_obtainable_techweb_nodes(station)

	var/datum/techweb/colony = new /datum/techweb
	allocated += colony
	restrict_techweb_to_campaign_start(colony)
	var/list/colony_obtainable = campaign_obtainable_techweb_nodes(colony)

	log_test("Campaign research: [length(colony.researched_nodes)] nodes known at start, [length(colony.available_nodes)] researchable at once, [length(colony_obtainable)] of [length(SSresearch.techweb_nodes)] ever obtainable.")

	// A colony with nothing researchable has no first move, whatever the rest of the graph says.
	TEST_ASSERT(length(colony.available_nodes), "A colony starts with no researchable node at all.")

	var/list/stranded = list()
	for(var/node_path in station_obtainable)
		if(colony_obtainable[node_path])
			continue
		var/datum/techweb_node/node = SSresearch.techweb_nodes[node_path]
		stranded += "[node.display_name] ([node_path])"
	TEST_ASSERT(!length(stranded), "[length(stranded)] node(s) a station can get are unreachable in a campaign: [stranded.Join(" / ")]")

	// Designs are what a player actually loses, and one stranded node takes every design it holds with it.
	var/list/stranded_designs = list()
	for(var/design_path in SSresearch.techweb_designs)
		var/datum/design/design = SSresearch.techweb_designs[design_path]
		var/on_station = FALSE
		var/in_colony = FALSE
		for(var/node_path in design.unlocked_by)
			if(station_obtainable[node_path])
				on_station = TRUE
			if(colony_obtainable[node_path])
				in_colony = TRUE
		if(on_station && !in_colony)
			stranded_designs += "[design.name] ([design_path])"
	TEST_ASSERT(!length(stranded_designs), "[length(stranded_designs)] design(s) a station can build are unbuildable in a campaign: [stranded_designs.Join(" / ")]")
