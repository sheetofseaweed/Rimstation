/**
 * The colony's food store: the one thing that puts food into the campaign.
 *
 * Before the larder existed, every use of food was a spend and nothing anywhere was a source, so the figure
 * sat at zero forever and anything gated on it could never happen. These are mostly about the two rules that
 * keeps honest: the larder is what the number counts, and spending is all or nothing.
 */
/datum/unit_test/rimstation_colony_larder
	abstract_type = /datum/unit_test/rimstation_colony_larder

/// A larder on the test floor, with the ledger ready to mirror it.
/datum/unit_test/rimstation_colony_larder/proc/build_larder()
	RETURN_TYPE(/obj/structure/closet/crate/freezer/colony_larder)
	return allocate(/obj/structure/closet/crate/freezer/colony_larder, run_loc_floor_bottom_left)

/// Puts one loaf in and returns it. A loaf is ten nutriment, which is five units.
/datum/unit_test/rimstation_colony_larder/proc/stock_loaf(obj/structure/closet/crate/freezer/colony_larder/larder)
	RETURN_TYPE(/obj/item/food/bread/plain)
	var/obj/item/food/bread/plain/loaf = allocate(/obj/item/food/bread/plain)
	loaf.forceMove(larder)
	return loaf


/// Food is counted by what is in it, measured in nutriment rather than in objects.
/datum/unit_test/rimstation_colony_larder/counts_what_is_in_it

/datum/unit_test/rimstation_colony_larder/counts_what_is_in_it/Run()
	TEST_ASSERT_EQUAL(count_colony_food(), 0, "A colony with no larder reported food anyway.")

	var/obj/structure/closet/crate/freezer/colony_larder/larder = build_larder()
	TEST_ASSERT_EQUAL(count_colony_food(), 0, "An empty larder reported food in it.")
	TEST_ASSERT_EQUAL(get_colony_larder(), larder, "The colony could not find the larder that was just built.")

	// A loaf is ten nutriment and a unit is two, so a loaf stocks five.
	var/obj/item/food/bread/plain/loaf = stock_loaf(larder)
	TEST_ASSERT_EQUAL(food_units_in(loaf), 5, "A loaf of bread was not worth five units of food.")
	TEST_ASSERT_EQUAL(count_colony_food(), 5, "Putting a loaf in the larder did not stock the colony.")

	stock_loaf(larder)
	TEST_ASSERT_EQUAL(count_colony_food(), 10, "A second loaf did not add to the stores.")

	// Counted by nutriment, so nobody stocks a colony by filling it with things that are not food.
	var/obj/item/wrench/tool = allocate(/obj/item/wrench)
	tool.forceMove(larder)
	TEST_ASSERT_EQUAL(food_units_in(tool), 0, "A wrench was counted as food.")
	TEST_ASSERT_EQUAL(count_colony_food(), 10, "Putting a wrench in the larder fed the colony.")

	// Taking it back out is allowed: this is a box, not a one-way conversion.
	loaf.forceMove(run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(count_colony_food(), 5, "Taking a loaf out of the larder did not reduce the stores.")


/// Spending food is all or nothing, and reaches for the scraps before the loaves.
/datum/unit_test/rimstation_colony_larder/spends_all_or_nothing

/datum/unit_test/rimstation_colony_larder/spends_all_or_nothing/Run()
	var/obj/structure/closet/crate/freezer/colony_larder/larder = build_larder()
	stock_loaf(larder)
	stock_loaf(larder)
	TEST_ASSERT_EQUAL(count_colony_food(), 10, "The test could not stock the larder.")

	// More than the colony has takes nothing at all, rather than emptying it and coming up short.
	TEST_ASSERT(!consume_colony_food(11, "test"), "The colony spent food it did not have.")
	TEST_ASSERT_EQUAL(count_colony_food(), 10, "A refused spend still ate the colony's food.")

	TEST_ASSERT(consume_colony_food(5, "test"), "The colony could not spend food it had.")
	TEST_ASSERT_EQUAL(count_colony_food(), 5, "Spending five units did not take five units.")

	TEST_ASSERT(consume_colony_food(5, "test"), "The colony could not spend the rest of its food.")
	TEST_ASSERT_EQUAL(count_colony_food(), 0, "The larder still held food after everything was spent.")

	// Smallest first, so a small bill does not break into a loaf while scraps are sitting there.
	var/obj/item/food/bread/plain/whole = stock_loaf(larder)
	var/obj/item/food/breadslice/plain/slice = allocate(/obj/item/food/breadslice/plain)
	slice.forceMove(larder)
	TEST_ASSERT_EQUAL(food_units_in(slice), 1, "A slice of bread was not worth one unit of food.")

	TEST_ASSERT(consume_colony_food(1, "test"), "The colony could not spend a single unit.")
	TEST_ASSERT(QDELETED(slice), "Spending one unit did not take the slice that covered it.")
	TEST_ASSERT(!QDELETED(whole), "Spending one unit broke into a whole loaf while a slice was available.")


/// The ledger's figure follows the larder, so anything reading the ledger reads the truth.
/datum/unit_test/rimstation_colony_larder/ledger_mirrors_the_larder

/datum/unit_test/rimstation_colony_larder/ledger_mirrors_the_larder/Run()
	var/datum/campaign_manifest/manifest = new("unit-test-larder", "generation-1")
	allocated += manifest
	var/saved_manifest = SScampaign.manifest
	var/datum/settlement_ledger/saved_ledger = SScampaign.ledger
	SScampaign.manifest = manifest
	SScampaign.ledger = new

	var/obj/structure/closet/crate/freezer/colony_larder/larder = build_larder()
	stock_loaf(larder)
	stock_loaf(larder)

	sync_colony_food_to_ledger()
	TEST_ASSERT_EQUAL(SScampaign.ledger.get_resource(COLONY_FOOD_RESOURCE), 10, "The ledger did not learn what the larder holds.")

	// Spending goes through the larder, and the ledger follows it down without being told separately.
	TEST_ASSERT(consume_colony_food(4, "test"), "The colony could not spend its food.")
	TEST_ASSERT_EQUAL(SScampaign.ledger.get_resource(COLONY_FOOD_RESOURCE), count_colony_food(), "The ledger and the larder disagree about how much food there is.")

	// The larder wins. A ledger figure that drifted for any reason is corrected to what is in the box, which is
	// the contract that makes the larder the only place food has to be kept right.
	SScampaign.adjust_resource(COLONY_FOOD_RESOURCE, 500, LEDGER_CATEGORY_ADMIN, "drift")
	TEST_ASSERT(SScampaign.ledger.get_resource(COLONY_FOOD_RESOURCE) > count_colony_food(), "The test could not create the drift it meant to correct.")
	sync_colony_food_to_ledger()
	TEST_ASSERT_EQUAL(SScampaign.ledger.get_resource(COLONY_FOOD_RESOURCE), count_colony_food(), "A recount did not put the ledger back to what the larder actually holds.")

	QDEL_NULL(SScampaign.ledger)
	SScampaign.manifest = saved_manifest
	SScampaign.ledger = saved_ledger
