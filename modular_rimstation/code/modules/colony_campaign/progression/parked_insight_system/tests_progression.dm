/**
 * The technology graph has to be traversable, and every node has to be worth reaching.
 *
 * A graph nobody can finish is not obvious from reading it - a cycle three nodes long looks perfectly
 * reasonable at each individual node - so the structure is checked rather than reviewed.
 */
/datum/unit_test/rimstation_colony_tech_graph

/datum/unit_test/rimstation_colony_tech_graph/Run()
	var/list/problems = validate_colony_tech_graph()
	TEST_ASSERT(!length(problems), "The colony technology graph is not sound:\n[problems.Join("\n")]")

	TEST_ASSERT(length(GLOB.colony_tech_nodes), "The colony technology graph is empty.")

	// All six stages carry something. A stage with no nodes is a gap in the curve, not a spare label.
	var/list/stages_seen = list()
	for(var/node_id in GLOB.colony_tech_nodes)
		var/datum/colony_tech_node/node = GLOB.colony_tech_nodes[node_id]
		stages_seen[node.stage] = TRUE

	for(var/stage in COLONY_TECH_STAGES)
		TEST_ASSERT(stages_seen[stage], "No technology node is in the '[stage]' stage, so that part of the curve does not exist.")

	// Something has to be unlockable from a standing start, or the curve never begins.
	var/found_root = FALSE
	for(var/node_id in GLOB.colony_tech_nodes)
		var/datum/colony_tech_node/node = GLOB.colony_tech_nodes[node_id]
		if(node.is_root())
			found_root = TRUE
			TEST_ASSERT_EQUAL(node.stage, COLONY_TECH_STAGE_SURVIVAL, "Root node '[node_id]' is in stage '[node.stage]'; a colony starts knowing survival, not [node.stage].")
			TEST_ASSERT(!node.cost, "Root node '[node_id]' has a cost, but nothing can be earned before the first node is unlocked.")
	TEST_ASSERT(found_root, "No technology node can be unlocked from a standing start.")


/**
 * Every design the colony fabricator can build belongs to exactly one node.
 *
 * The graph is an allowlist, so a design nobody placed cannot be built at all. That is the safe direction to
 * fail in, but it is silent - the design simply is not in the menu - which is why it is asserted here. If this
 * fails after a design is added, place it in a node rather than relaxing the check.
 */
/datum/unit_test/rimstation_colony_tech_covers_designs

/datum/unit_test/rimstation_colony_tech_covers_designs/Run()
	var/list/unplaced = list()
	var/buildable_count = 0

	for(var/design_id in SSresearch.techweb_designs)
		var/datum/design/design = SSresearch.techweb_designs[design_id]
		if(!(design.build_type & COLONY_FABRICATOR))
			continue
		buildable_count++
		if(!GLOB.colony_tech_node_by_design_id[design_id])
			unplaced += design_id

	TEST_ASSERT(buildable_count, "No designs are buildable on the colony fabricator, so this test proves nothing.")
	TEST_ASSERT(!length(unplaced), "[length(unplaced)] colony fabricator designs are in no technology node and can never be built:\n[unplaced.Join(", ")]")

	// And nothing is claimed that the fabricator cannot build, which would be a node promising a phantom.
	var/list/unbuildable = list()
	for(var/design_id in GLOB.colony_tech_node_by_design_id)
		var/datum/design/design = SSresearch.techweb_designs[design_id]
		if(!design || !(design.build_type & COLONY_FABRICATOR))
			unbuildable += "[design_id] (in [GLOB.colony_tech_node_by_design_id[design_id]])"
	TEST_ASSERT(!length(unbuildable), "Technology nodes claim designs the colony fabricator cannot build:\n[unbuildable.Join(", ")]")


/**
 * A new colony can do the things it arrived able to do, and none of the things that end the early game.
 *
 * These two assertions are the whole shape of the opening. The first says the curve does not take away what
 * the colonists landed with; the second says arriving does not hand them the station catalog.
 */
/datum/unit_test/rimstation_colony_tech_opening_state

/datum/unit_test/rimstation_colony_tech_opening_state/Run()
	var/datum/colony_progression/fresh = new
	allocated += fresh

	// The opening kit is hand tools and seeds, so replacing them must not need research.
	var/list/opening_designs = list(
		/datum/design/shovel,
		/datum/design/pickaxe,
		/datum/design/hatchet,
		/datum/design/survival_knife,
		/datum/design/flashlight,
		/datum/design/prefab_floor_tile,
	)
	for(var/datum/design/design_type as anything in opening_designs)
		var/design_id = initial(design_type.id)
		TEST_ASSERT(fresh.is_design_unlocked(design_id), "A new colony cannot build '[design_id]', which it needs to replace what it landed with.")
		TEST_ASSERT_EQUAL(GLOB.colony_tech_nodes[GLOB.colony_tech_node_by_design_id[design_id]].stage, COLONY_TECH_STAGE_SURVIVAL, "Opening design '[design_id]' is not in the survival stage.")

	// The things that retire the early game are a long way off, not three clicks away.
	var/list/late_designs = list(
		/datum/design/rcd_ammo,
		/datum/design/rld_mini,
		/datum/design/rtd_loaded,
		/datum/design/rwd,
		/datum/design/rpd,
		/datum/design/adv_capacitor,
		/datum/design/adv_matter_bin,
		/datum/design/adv_scanning,
		/datum/design/super_cell,
		/datum/design/nano_servo,
		/datum/design/high_micro_laser,
		/datum/design/rped,
	)
	for(var/datum/design/design_type as anything in late_designs)
		var/design_id = initial(design_type.id)
		TEST_ASSERT(!fresh.is_design_unlocked(design_id), "A brand new colony can already build '[design_id]', which skips the entire technology curve.")

	// None of them is reachable in one purchase either, however much insight a colony is handed.
	fresh.insight = 1000
	for(var/node_id in fresh.get_available_nodes())
		var/datum/colony_tech_node/node = GLOB.colony_tech_nodes[node_id]
		TEST_ASSERT_NOTEQUAL(node.stage, COLONY_TECH_STAGE_ADVANCED, "Advanced node '[node_id]' can be bought as a colony's first purchase.")


/// Unlocking spends what it costs, refuses what it cannot afford, and never half-happens.
/datum/unit_test/rimstation_colony_tech_unlock

/datum/unit_test/rimstation_colony_tech_unlock/Run()
	var/datum/colony_progression/progression = new
	allocated += progression

	// Prerequisites come first, whatever the colony can afford.
	progression.insight = 1000
	TEST_ASSERT(!progression.is_unlocked("advanced_components"), "A new colony already knows precision components.")
	TEST_ASSERT(!progression.unlock("advanced_components", "test"), "A node was unlocked with none of its prerequisites met.")
	TEST_ASSERT_EQUAL(progression.insight, 1000, "A refused unlock still spent insight.")
	TEST_ASSERT_NOTNULL(progression.why_locked("advanced_components"), "A node that cannot be unlocked reported no reason.")

	// The first real purchase.
	var/datum/colony_tech_node/metalwork = GLOB.colony_tech_nodes["craft_metalwork"]
	TEST_ASSERT_NOTNULL(metalwork, "The metalworking node is missing, so the early curve has no spine.")
	progression.insight = metalwork.cost
	TEST_ASSERT(progression.unlock("craft_metalwork", "test"), "Metalworking could not be unlocked with exactly its cost paid.")
	TEST_ASSERT_EQUAL(progression.insight, 0, "Unlocking did not spend the node's cost.")
	TEST_ASSERT(progression.is_unlocked("craft_metalwork"), "An unlocked node did not register as unlocked.")
	TEST_ASSERT(progression.is_design_unlocked(/datum/design/colony_arc_welder::id), "Unlocking metalworking did not make its designs buildable.")

	// It cannot be bought twice, and being broke is a refusal rather than a debt.
	TEST_ASSERT(!progression.unlock("craft_metalwork", "test"), "A node was unlocked a second time.")
	TEST_ASSERT(!progression.unlock("craft_glassworking", "test"), "A node was unlocked with no insight to pay for it.")
	TEST_ASSERT_EQUAL(progression.insight, 0, "A refused unlock left the colony in insight debt.")

	// Insight is awarded, never subtracted, through the award path.
	TEST_ASSERT(!progression.award_insight(-5, "test"), "Negative insight was awarded.")
	TEST_ASSERT(progression.award_insight(5, "test"), "Insight could not be awarded.")
	TEST_ASSERT_EQUAL(progression.insight, 5, "Awarding insight did not add it.")

	// Every unlock is written down.
	TEST_ASSERT_EQUAL(length(progression.unlock_log), 1, "The unlock was not recorded in the progression log.")


/// What a colony knows has to survive the round that taught it.
/datum/unit_test/rimstation_colony_tech_persistence

/datum/unit_test/rimstation_colony_tech_persistence/Run()
	var/datum/colony_progression/original = new
	allocated += original
	original.insight = 20
	TEST_ASSERT(original.unlock("craft_metalwork", "test"), "Metalworking could not be unlocked.")
	TEST_ASSERT(original.unlock("power_basics", "test"), "Power basics could not be unlocked.")

	var/datum/colony_progression/restored = new
	allocated += restored
	TEST_ASSERT(restored.deserialize(json_decode(json_encode(original.serialize()))), "A progression record did not survive a JSON round trip.")
	TEST_ASSERT_EQUAL(restored.insight, original.insight, "Restoring the colony lost its unspent insight.")
	TEST_ASSERT(restored.is_unlocked("craft_metalwork"), "Restoring the colony lost a technology it had unlocked.")
	TEST_ASSERT(restored.is_unlocked("power_basics"), "Restoring the colony lost a technology it had unlocked.")
	TEST_ASSERT(restored.is_design_unlocked(/datum/design/cable_coil::id), "A restored colony cannot build what it had researched.")

	// A record naming a technology that no longer exists costs that capability, not the campaign.
	var/list/with_retired_node = original.serialize()
	with_retired_node["unlocked_node_ids"] = list("craft_metalwork", "a_node_that_was_removed")
	var/datum/colony_progression/after_retirement = new
	allocated += after_retirement
	TEST_ASSERT(after_retirement.deserialize(with_retired_node), "A record naming a retired technology was refused outright.")
	TEST_ASSERT(after_retirement.is_unlocked("craft_metalwork"), "Dropping a retired technology also dropped a valid one.")
	TEST_ASSERT(!after_retirement.is_unlocked("a_node_that_was_removed"), "A technology that no longer exists was restored.")

	// Roots are what a colony arrives knowing, so they come back even if the record omits them.
	var/list/without_roots = original.serialize()
	without_roots["unlocked_node_ids"] = list()
	var/datum/colony_progression/stripped = new
	allocated += stripped
	TEST_ASSERT(stripped.deserialize(without_roots), "A record with no unlocked nodes was refused.")
	TEST_ASSERT(stripped.is_design_unlocked(/datum/design/shovel::id), "A restored colony could not build a shovel, which every colony arrives able to build.")

	// Nonsense is refused rather than loaded as an empty colony.
	var/datum/colony_progression/guarded = new
	allocated += guarded
	TEST_ASSERT(!guarded.deserialize(null), "A null progression record was accepted.")
	var/list/bad_version = original.serialize()
	bad_version["schema_version"] = COLONY_PROGRESSION_SCHEMA_VERSION + 1
	TEST_ASSERT(!guarded.deserialize(bad_version), "A progression record from an unknown schema was accepted.")
