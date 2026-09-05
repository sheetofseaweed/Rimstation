/**
 * The opening package is a design contract, not just a list.
 *
 * These assertions encode the Phase 1 rule that a colony starts pre-industrial and scales with the people
 * actually present. They are written against the policy rather than against the current contents, so
 * rebalancing quantities is free but smuggling in a lathe is not.
 */
/datum/unit_test/rimstation_opening_loadout

/datum/unit_test/rimstation_opening_loadout/Run()
	var/datum/colony_opening_package/package = new
	allocated += package

	// Anything here would collapse the early production chain this phase exists to create.
	var/list/banned_types = list(
		/obj/item/construction/rcd,
		/obj/item/gun/energy,
		/obj/machinery/autolathe,
		/obj/machinery/rnd,
		/obj/item/stack/sheet/iron,
		/obj/item/storage/backpack/holding,
	)

	var/list/manifest = package.get_manifest(6)
	TEST_ASSERT(length(manifest), "The opening package granted nothing at all.")
	for(var/item_type in manifest)
		for(var/banned_type in banned_types)
			TEST_ASSERT(!ispath(item_type, banned_type), "The opening package contains [item_type], which is industrial-grade starting equipment.")
		TEST_ASSERT(manifest[item_type] > 0, "The opening package listed [item_type] but granted none of it.")

	// The categories a colony cannot open without.
	var/list/required_categories = list(
		"an ignition source" = /obj/item/match,
		"bedding material" = /obj/item/stack/sheet/cloth,
		"renewable food" = /obj/item/seeds,
		"a water container" = /obj/item/reagent_containers/cup,
		"a digging tool" = /obj/item/shovel,
	)
	for(var/category in required_categories)
		var/required_root = required_categories[category]
		var/found = FALSE
		for(var/item_type in manifest)
			if(ispath(item_type, required_root))
				found = TRUE
				break
		TEST_ASSERT(found, "The opening package has no [category], so the colony cannot get started.")


/// Two players have to be viable and twenty must not receive a stockpile.
/datum/unit_test/rimstation_opening_scaling

/datum/unit_test/rimstation_opening_scaling/Run()
	var/datum/colony_opening_package/package = new
	allocated += package

	var/list/tiny_colony = package.get_manifest(2)
	var/list/large_colony = package.get_manifest(20)

	for(var/item_type in package.shared_supplies)
		var/list/rule = package.shared_supplies[item_type]
		var/tiny = tiny_colony[item_type]
		var/large = large_colony[item_type]

		TEST_ASSERT(tiny >= rule["base"], "Shared supply [item_type] dropped below its base quantity at two colonists.")
		TEST_ASSERT(large >= tiny, "Shared supply [item_type] shrank as the colony grew.")
		TEST_ASSERT(large <= rule["cap"], "Shared supply [item_type] exceeded its cap at twenty colonists.")

	// An empty colony must not produce negative or runaway quantities.
	var/list/empty_colony = package.get_manifest(0)
	for(var/item_type in empty_colony)
		TEST_ASSERT(empty_colony[item_type] >= 0, "Shared supply [item_type] went negative with no colonists.")

	// Personal supplies are per head, so they have to actually track headcount.
	for(var/item_type in package.personal_supplies)
		TEST_ASSERT(large_colony[item_type] > tiny_colony[item_type], "Personal supply [item_type] did not scale with colonist count.")


/// The crate is the only thing that turns the package into objects a colonist can pick up.
/datum/unit_test/rimstation_opening_crate

/datum/unit_test/rimstation_opening_crate/Run()
	var/obj/structure/closet/crate/colony_supplies/crate = allocate(/obj/structure/closet/crate/colony_supplies)
	// Mapped-in crates fill on LateInitialize; allocate() does not run that, so drive it directly.
	crate.fill_from_package()

	var/list/contents_by_type = list()
	for(var/obj/item/carried in crate)
		contents_by_type[carried.type] += 1
	TEST_ASSERT(length(contents_by_type), "The colony supply crate came up empty, so the colony starts with nothing.")

	var/datum/colony_opening_package/package = new
	allocated += package
	for(var/item_type in package.shared_supplies)
		var/found = FALSE
		for(var/spawned_type in contents_by_type)
			if(ispath(spawned_type, item_type))
				found = TRUE
				break
		TEST_ASSERT(found, "The colony supply crate is missing [item_type] from the opening package.")

	// Stacks have to arrive as one stack carrying a count, not as one object per unit.
	for(var/obj/item/stack/bundle in crate)
		TEST_ASSERT(bundle.amount > 0, "A stack in the supply crate arrived with no amount.")


/**
 * The planner must produce a useful, vertically coordinated landscape without touching the global RNG.
 */
/datum/unit_test/rimstation_colony_generator_determinism

/datum/unit_test/rimstation_colony_generator_determinism/Run()
	var/datum/planet_definition/planet = new("rimstation-landscape-test")
	var/datum/map_generator/rimstation_colony/generator = new(planet)
	var/datum/rimstation_colony_generation_context/first = generator.create_generation_context(1, 1, 96, 96, 2)
	var/datum/rimstation_colony_generation_context/second = generator.create_generation_context(1, 1, 96, 96, 2)
	allocated += planet
	allocated += generator
	allocated += first
	allocated += second
	first.set_landing_bounds(43, 43, 54, 54)
	second.set_landing_bounds(43, 43, 54, 54)
	TEST_ASSERT(first.build_plan(), "The first deterministic landscape plan could not be built.")
	TEST_ASSERT(second.build_plan(), "The repeated deterministic landscape plan could not be built.")
	TEST_ASSERT_EQUAL(first.fingerprint(), second.fingerprint(), "The same planet and bounds produced two different landscape plans.")

	var/area/rimstation_colony/surface/wilds/wilds_area = /area/rimstation_colony/surface/wilds
	TEST_ASSERT(!(initial(wilds_area.area_flags_mapping) & MEGAFAUNA_SPAWN_ALLOWED), "The colony surface would spawn megafauna, which a starting colony cannot answer.")

	var/list/terrain_counts = list()
	var/ascent_count = 0
	for(var/index in 1 to length(first.terrain_plan))
		var/terrain = first.terrain_plan[index]
		var/terrain_key = "[terrain]"
		terrain_counts[terrain_key] = (terrain_counts[terrain_key] || 0) + 1
		if(first.ascent_directions[index])
			ascent_count++
	TEST_ASSERT(terrain_counts["[RIMSTATION_TERRAIN_LOWLAND]"], "The generated plan contains no ordinary lowland.")
	TEST_ASSERT(terrain_counts["[RIMSTATION_TERRAIN_MOUNTAIN]"], "The generated plan contains no solid mountain interiors.")
	TEST_ASSERT(terrain_counts["[RIMSTATION_TERRAIN_CAVE]"], "The generated mountains contain no entrance-connected caves.")
	TEST_ASSERT(terrain_counts["[RIMSTATION_TERRAIN_RIVER_SHALLOW]"], "The generated river contains no fordable channel.")
	TEST_ASSERT(terrain_counts["[RIMSTATION_TERRAIN_RIVER_DEEP]"], "The generated river contains no occasional deep pools.")
	TEST_ASSERT(ascent_count > 0, "The highlands have no generated ascent point.")
	TEST_ASSERT(ascent_count <= RIMSTATION_MAX_ASCENTS, "The highlands generated [ascent_count] ascents, above the bounded maximum of [RIMSTATION_MAX_ASCENTS].")
	TEST_ASSERT(length(first.raid_insertion_indices) > 0, "The generated plan found no landing-connected raid insertion points.")
	TEST_ASSERT(length(first.raid_insertion_indices) <= 8, "The generated plan produced more than two raid insertion points per map edge.")
	for(var/index in first.raid_insertion_indices)
		TEST_ASSERT(first.is_plan_walkable(index), "A generated raid insertion point is not walkable in the terrain plan.")
		var/x = first.index_x(index)
		var/y = first.index_y(index)
		var/edge_distance = min(x - first.min_x, first.max_x - x, y - first.min_y, first.max_y - y)
		TEST_ASSERT(edge_distance < COLONY_RAID_EDGE_BAND, "A generated raid insertion point at [x],[y] is outside the allowed edge band.")

	TEST_ASSERT(first.landing_distance(37, 37) > RIMSTATION_LANDING_BLEND_RADIUS, "The landing blend still expands from square bounding-box corners.")
	for(var/x in first.min_x to first.max_x)
		for(var/y in first.min_y to first.max_y)
			if(first.landing_distance(x, y) > RIMSTATION_LANDING_BLEND_RADIUS)
				continue
			var/index = first.coordinate_index(x, y)
			var/terrain = first.terrain_plan[index]
			TEST_ASSERT(terrain != RIMSTATION_TERRAIN_MOUNTAIN && terrain != RIMSTATION_TERRAIN_CAVE, "Mountain terrain intruded into the landing blend at [x],[y].")
			TEST_ASSERT(terrain != RIMSTATION_TERRAIN_RIVER_SHALLOW && terrain != RIMSTATION_TERRAIN_RIVER_DEEP, "The river intruded into the landing blend at [x],[y].")
