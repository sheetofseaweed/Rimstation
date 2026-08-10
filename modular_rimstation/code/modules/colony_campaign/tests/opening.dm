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


/**
 * The colony generator has to stay deterministic.
 *
 * The inherited non-biome path selects turfs with pick(), which is only reproducible while there is exactly
 * one candidate per side. Adding a second turf type would silently reintroduce an unseeded roll, so this
 * guards the assumption rather than the terrain.
 */
/datum/unit_test/rimstation_colony_generator_determinism

/datum/unit_test/rimstation_colony_generator_determinism/Run()
	var/datum/map_generator/cave_generator/rimstation_colony/generator = new
	allocated += generator

	TEST_ASSERT_EQUAL(length(generator.open_turf_types), 1, "The colony generator has more than one open turf type, which makes pick() reintroduce randomness into terrain.")
	TEST_ASSERT_EQUAL(length(generator.closed_turf_types), 1, "The colony generator has more than one closed turf type, which makes pick() reintroduce randomness into terrain.")
	TEST_ASSERT_NOTNULL(generator.generation_seed_provider, "The colony generator was not bound to a planet, so its terrain would not be reproducible.")

	// The parent installs lavaland defaults in New() when these are left unset, which would put goliaths and
	// megafauna on a surface whose colonists start with a knife.
	var/area/rimstation_colony/surface/wilds/wilds_area = /area/rimstation_colony/surface/wilds
	TEST_ASSERT(!(initial(wilds_area.area_flags_mapping) & MEGAFAUNA_SPAWN_ALLOWED), "The colony surface would spawn megafauna, which a starting colony cannot answer.")
	for(var/mob_type in generator.mob_spawn_list)
		TEST_ASSERT(!ispath(mob_type, /mob/living/basic/mining), "The colony surface would spawn lavaland fauna ([mob_type]) into the opening.")
	for(var/flora_type in generator.flora_spawn_list)
		TEST_ASSERT(!ispath(flora_type, /obj/structure/flora/ash), "The colony surface would spawn ashland flora ([flora_type]) on an Earthlike world.")
	TEST_ASSERT(length(generator.mob_spawn_list), "The colony surface has no fauna at all, leaving nothing to hunt or herd.")
	TEST_ASSERT(length(generator.flora_spawn_list), "The colony surface has no flora at all, so there is no renewable wood.")

	// The same coordinate must resolve the same way every time the grid is built.
	var/cave_seed = generator.resolve_generation_seed(PLANET_STREAM_TERRAIN, 1)
	TEST_ASSERT_NOTNULL(cave_seed, "The colony generator produced no terrain seed.")
	// Sampled across the whole surface rather than one row: perlin features are tens of tiles wide, so a
	// narrow sample can legitimately be uniform even when the map as a whole is not.
	var/open_count = 0
	var/total_count = 0
	var/lowest_noise = INFINITY
	var/highest_noise = -INFINITY
	for(var/x = 1; x <= 240; x += 8)
		for(var/y = 1; y <= 240; y += 8)
			var/noise = text2num(rustg_noise_get_at_coordinates("[cave_seed]", "[x / generator.perlin_zoom]", "[y / generator.perlin_zoom]"))
			lowest_noise = min(lowest_noise, noise)
			highest_noise = max(highest_noise, noise)
			var/open = generator.resolve_cave_openness(cave_seed, x, y)
			TEST_ASSERT_EQUAL(open, generator.resolve_cave_openness(cave_seed, x, y), "Cave openness changed between calls at [x],[y].")
			total_count++
			if(open)
				open_count++

	var/open_percent = round((open_count / total_count) * 100, 1)
	TEST_ASSERT(open_count > 0 && open_count < total_count, "The seeded cave grid came out entirely [open_count ? "open" : "solid"], which would make the surface unplayable. Noise ranged [lowest_noise] to [highest_noise] against a threshold of [generator.noise_percent / 100].")
	// A surface that is nearly all rock or nearly all field is technically playable and practically useless.
	TEST_ASSERT(open_percent >= 20 && open_percent <= 80, "The seeded cave grid came out [open_percent]% open, outside the usable 20-80% band. Noise ranged [lowest_noise] to [highest_noise].")
