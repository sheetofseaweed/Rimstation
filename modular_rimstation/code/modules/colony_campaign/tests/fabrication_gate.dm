/**
 * During a campaign the colony fabricator builds what the colony has researched, and nothing else.
 *
 * The inherited machine deliberately bypasses research: it connects to the admin techweb, which has everything
 * researched, and overrides the design filter to take every design in the game. That is right for a one-round
 * outpost and wrong for a campaign, where research is the only thing that makes the colony's capability grow.
 *
 * Nothing new gates the designs. The parent machine already filters by `stored_research.researched_designs`
 * and already revalidates a build request against the same list in `ui_act`, so the whole change is pointing
 * the machine at the colony's real techweb and stepping out of the way.
 */
/datum/unit_test/rimstation_colony_fabrication_gate
	var/saved_state
	var/datum/campaign_manifest/saved_manifest

/datum/unit_test/rimstation_colony_fabrication_gate/Run()
	saved_state = SScampaign.campaign_state
	saved_manifest = SScampaign.manifest
	ensure_techweb_nodes_for_test()

	// Outside a campaign the machine keeps its inherited behaviour exactly.
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	SScampaign.manifest = null

	var/obj/machinery/rnd/production/colony_lathe/ungated = allocate(/obj/machinery/rnd/production/colony_lathe)
	TEST_ASSERT(istype(ungated.stored_research, /datum/techweb/admin), "Outside a campaign the colony fabricator no longer uses the pre-researched techweb, which changes ordinary rounds.")
	var/ungated_count = length(ungated.cached_designs)
	TEST_ASSERT(ungated_count, "Outside a campaign the colony fabricator offered no designs at all.")

	// Inside one it connects to the colony's own techweb.
	var/datum/campaign_manifest/manifest = new("unit-test-fabrication", "generation-1")
	allocated += manifest
	SScampaign.manifest = manifest
	SScampaign.campaign_state = CAMPAIGN_STATE_ACTIVE

	var/obj/machinery/rnd/production/colony_lathe/gated = allocate(/obj/machinery/rnd/production/colony_lathe)
	var/datum/techweb/colony_web = get_colony_techweb()
	TEST_ASSERT_NOTNULL(colony_web, "There is no colony techweb for the fabricator to be gated by.")
	TEST_ASSERT_EQUAL(gated.stored_research, colony_web, "During a campaign the colony fabricator is not connected to the colony's techweb.")

	// Every design it offers is one the colony actually researched. This is the gate.
	for(var/datum/design/design as anything in gated.cached_designs)
		TEST_ASSERT(colony_web.researched_designs[design.id], "The colony fabricator offered '[design.id]', which the colony has not researched.")

	// And it offers strictly less than the ungated machine, or the gate is not doing anything.
	TEST_ASSERT(length(gated.cached_designs) < ungated_count, "A campaign colony fabricator offered [length(gated.cached_designs)] designs against [ungated_count] ungated, so research gates nothing.")

	// A design the colony has not researched is refused by the same list ui_act revalidates against, so it
	// cannot be forged by sending a build request for it.
	var/datum/design/unresearched
	for(var/design_id in SSresearch.techweb_designs)
		var/datum/design/candidate = SSresearch.techweb_designs[design_id]
		if((candidate.build_type & COLONY_FABRICATOR) && !colony_web.researched_designs[design_id])
			unresearched = candidate
			break
	TEST_ASSERT_NOTNULL(unresearched, "Every colony fabricator design is already researched, so the gate cannot be tested.")
	TEST_ASSERT(!(unresearched in gated.cached_designs), "An unresearched design was listed by a campaign colony fabricator.")
	TEST_ASSERT(!colony_web.researched_designs[unresearched.id], "An unresearched design was present in the list ui_act validates builds against.")

	SScampaign.campaign_state = saved_state
	SScampaign.manifest = saved_manifest

/datum/unit_test/rimstation_colony_fabrication_gate/Destroy()
	SScampaign.campaign_state = saved_state
	SScampaign.manifest = saved_manifest
	saved_manifest = null
	return ..()


/**
 * Research finished during a chapter reaches the fabricator without a reboot.
 *
 * `post_machine_initialize()` connects whatever techweb the machine points at, and connecting is what
 * subscribes it to research updates. So the colony fabricator only has to name the right web; doing the
 * connecting itself as well registers those signals twice, which runtimes.
 */
/datum/unit_test/rimstation_colony_fabrication_live_update
	var/saved_state
	var/datum/campaign_manifest/saved_manifest

/datum/unit_test/rimstation_colony_fabrication_live_update/Run()
	saved_state = SScampaign.campaign_state
	saved_manifest = SScampaign.manifest
	ensure_techweb_nodes_for_test()

	var/datum/campaign_manifest/manifest = new("unit-test-live-research", "generation-1")
	allocated += manifest
	SScampaign.manifest = manifest
	SScampaign.campaign_state = CAMPAIGN_STATE_ACTIVE

	var/datum/techweb/colony_web = get_colony_techweb()
	TEST_ASSERT_NOTNULL(colony_web, "There is no colony techweb to research into.")

	var/obj/machinery/rnd/production/colony_lathe/lathe = allocate(/obj/machinery/rnd/production/colony_lathe)

	// Find an unresearched node that unlocks something this machine could build.
	var/datum/techweb_node/node
	var/datum/design/target_design
	for(var/node_id in SSresearch.techweb_nodes)
		if(colony_web.researched_nodes[node_id])
			continue
		var/datum/techweb_node/candidate = SSresearch.techweb_nodes[node_id]
		for(var/design_id in candidate.design_ids)
			var/datum/design/design = SSresearch.techweb_designs[design_id]
			if(design && (design.build_type & COLONY_FABRICATOR) && !colony_web.researched_designs[design_id])
				node = candidate
				target_design = design
				break
		if(node)
			break
	TEST_ASSERT_NOTNULL(node, "No unresearched node unlocks a colony fabricator design, so a live update cannot be tested.")
	TEST_ASSERT(!(target_design in lathe.cached_designs), "The fabricator already offered '[target_design.id]' before it was researched.")

	TEST_ASSERT(colony_web.research_node(node, force = TRUE, auto_adjust_cost = FALSE, get_that_dosh = FALSE), "The node could not be researched.")
	// The machine batches its updates behind a timer, so ask it directly rather than waiting on one.
	lathe.update_designs()
	TEST_ASSERT(target_design in lathe.cached_designs, "Researching '[node.id]' did not make '[target_design.id]' buildable at the colony fabricator.")

	SScampaign.campaign_state = saved_state
	SScampaign.manifest = saved_manifest

/datum/unit_test/rimstation_colony_fabrication_live_update/Destroy()
	SScampaign.campaign_state = saved_state
	SScampaign.manifest = saved_manifest
	saved_manifest = null
	return ..()
